class_name BattleView
extends Node3D
## Отображение боя: симуляция (ScenarioClash) и жизнь лагеря (BattleAmbient) → слои толпы,
## по одному слою на вид юнита, каждый кадр.
##
## Слой — настоящая толпа CrowdLayer (scripts/units/crowd_layer.gd), если она есть в проекте,
## иначе запасной BattleDebugLayer с теми же методами. Классы толпы подключаются по пути
## во время работы, без прямых ссылок: после слияния настоящая толпа подхватится сама.
##
## Анимация (AnimSpec): ход по скорости (шаг/бег, шаг/рысь/галоп), фаза шага растёт на
## пройденный путь / STRIDE (ноги не скользят), разовые — по времени от начала, смерть → лежит,
## клич → CHEER, сарбозы — SHOOT/RELOAD, копейщики на разгоне — CHARGE. Вариант w стабилен.

const CROWD_LAYER_PATH := "res://scripts/units/crowd_layer.gd"
const REGISTRY_PATH := "res://scripts/units/unit_registry.gd"
const DebugLayer := preload("res://scripts/battle/debug_layer.gd")

const H := AnimSpec.Human
const R := AnimSpec.Horse
const S := AnimSpec.Sheep

## Скорости смены хода, м/с (как у толпы: CrowdAnim)
const HUMAN_RUN_FROM := 2.4
const HORSE_TROT_FROM := 2.6
const HORSE_GALLOP_FROM := 5.5

@export var scenario_path: NodePath = ^"../Scenario"
@export var ambient_path: NodePath = ^"../Ambient"
## Рисовать запасными фигурами, даже если настоящая толпа есть
@export var force_debug := false

var scenario: ScenarioClash
var ambient: BattleAmbient
## unit_id → слой (CrowdLayer или BattleDebugLayer)
var layers := {}
var using_real_crowd := false

var _crowd_script: Script
var _registry := {}
var _sim: BattleSim
var _u_layer: Array[String] = []
var _u_slot := PackedInt32Array()
var _u_skel := PackedInt32Array()     # 0 человек, 1 конь (всадник)
var _u_stride_k := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _lx := PackedFloat32Array()
var _lz := PackedFloat32Array()
var _a_slot := PackedInt32Array()
var _counts := {}


func _ready() -> void:
	scenario = get_node_or_null(scenario_path) as ScenarioClash
	ambient = get_node_or_null(ambient_path) as BattleAmbient
	if not force_debug and ResourceLoader.exists(CROWD_LAYER_PATH):
		_crowd_script = load(CROWD_LAYER_PATH) as Script
		using_real_crowd = _crowd_script != null
	if ResourceLoader.exists(REGISTRY_PATH):
		var reg := load(REGISTRY_PATH) as Script
		if reg:
			_registry = reg.get_script_constant_map().get("UNITS", {})
	if scenario:
		scenario.started.connect(_on_started)
		if scenario.sim:
			_on_started(scenario.current_seed)
	elif ambient:
		_rebuild()


## Данные вида юнита: из UnitRegistry, если есть, иначе запасные
func unit_info(unit_id: String) -> Dictionary:
	if _registry.has(unit_id):
		return _registry[unit_id]
	return DebugLayer.INFO.get(unit_id, {})


## Слой вида юнита (создаётся при первом обращении)
func layer(unit_id: String) -> Node3D:
	return layers.get(unit_id)


func _on_started(_seed: int) -> void:
	_sim = scenario.sim
	_rebuild()


func _rebuild() -> void:
	_counts.clear()
	var n := _sim.n if _sim else 0
	_u_layer.resize(n)
	_u_slot.resize(n)
	_u_skel.resize(n)
	_u_stride_k.resize(n)
	_phase.resize(n)
	_lx.resize(n)
	_lz.resize(n)
	for u in n:
		var vid := UnitStats.visual_for(_sim.type_of(u), _sim.u_role[u] == BattleSim.Role.BANNER)
		_u_layer[u] = vid
		_u_slot[u] = -1
		if vid == "":
			continue
		_u_slot[u] = _counts.get(vid, 0)
		_counts[vid] = _u_slot[u] + 1
		var info := unit_info(vid)
		_u_skel[u] = 0 if String(info.get("skeleton", "human")) == "human" else 1
		_u_stride_k[u] = float(info.get("scale", 1.0))
		_phase[u] = BattleRng.hash01(u * 3 + 1)
		_lx[u] = _sim.u_x[u]
		_lz[u] = _sim.u_z[u]
	var an := ambient.count if ambient else 0
	_a_slot.resize(an)
	for i in an:
		var vid: String = ambient.unit_ids[i]
		_a_slot[i] = _counts.get(vid, 0)
		_counts[vid] = _a_slot[i] + 1
	for vid in _counts:
		var l = layers.get(vid)
		var cap: int = _counts[vid]
		if l == null:
			l = _make_layer()
			l.name = "Layer_" + vid
			add_child(l)
			layers[vid] = l
			l.call("setup", vid, cap)
		elif int(l.get("capacity")) < cap:
			l.call("setup", vid, cap)
		l.call("set_visible_count", cap)
	for vid in layers:
		if not _counts.has(vid):
			layers[vid].call("set_visible_count", 0)


func _make_layer() -> Node3D:
	if using_real_crowd:
		var l := _crowd_script.new() as Node3D
		if l:
			return l
	return DebugLayer.new()


func _process(_delta: float) -> void:
	if _sim and scenario:
		_update_battle()
	if ambient:
		_update_ambient()


func _update_battle() -> void:
	var sim := _sim
	var t := sim.time
	var a := scenario.alpha
	for u in sim.n:
		var vid := _u_layer[u]
		if vid == "":
			continue
		var x := lerpf(sim.u_px[u], sim.u_x[u], a)
		var z := lerpf(sim.u_pz[u], sim.u_z[u], a)
		var h := lerp_angle(sim.u_ph[u], sim.u_h[u], a)
		if sim.u_life[u] != BattleSim.Life.ALIVE:
			# павшие лежат вразнобой, а не ровными рядами (поворот растёт за время падения)
			var k := 1.0 if sim.u_life[u] == BattleSim.Life.DEAD else clampf((t - sim.u_death_t[u]) / 0.8, 0.0, 1.0)
			h += (BattleRng.hash01(u * 7 + 3) - 0.5) * 1.5 * k
		var moved := Vector2(x - _lx[u], z - _lz[u]).length()
		_lx[u] = x
		_lz[u] = z
		var spd := Vector2(sim.u_vx[u], sim.u_vz[u]).length()
		var custom: Color
		if _u_skel[u] == 0:
			custom = _human_custom(sim, u, t, spd, moved)
		else:
			custom = _rider_custom(sim, u, t, spd, moved)
		var xf := Transform3D(Basis(Vector3.UP, h), Vector3(x, Terrain.height_at(x, z), z))
		layers[vid].set_instance(_u_slot[u], xf, custom)


func _human_custom(sim: BattleSim, u: int, t: float, spd: float, moved: float) -> Color:
	var w := sim.u_var[u]
	var life := sim.u_life[u]
	if life == BattleSim.Life.DEAD:
		return AnimSpec.custom(H.DEAD, 1.0, float(sim.u_fall[u]), w)
	if life == BattleSim.Life.DYING:
		return AnimSpec.custom(H.DYING, clampf((t - sim.u_death_t[u]) / AnimSpec.DURATION_HUMAN[H.DYING], 0.0, 1.0),
			float(sim.u_fall[u]), w)
	var act := sim.u_act[u]
	var at := t - sim.u_act_t[u]
	if act == BattleSim.Act.AIM and at >= 0.0 and at < AnimSpec.DURATION_HUMAN[H.SHOOT]:
		return AnimSpec.custom(H.SHOOT, at / AnimSpec.DURATION_HUMAN[H.SHOOT], 0.0, w)
	if act == BattleSim.Act.MELEE and at >= 0.0:
		return AnimSpec.custom(H.MELEE, clampf(at / AnimSpec.DURATION_HUMAN[H.MELEE], 0.0, 1.0), 0.0, w)
	if act == BattleSim.Act.CHEER and at >= 0.0:
		return AnimSpec.custom(H.CHEER, clampf(at / AnimSpec.DURATION_HUMAN[H.CHEER], 0.0, 1.0), 0.0, w)
	var fleeing := sim.is_fleeing(sim.u_squad[u])
	if spd > 0.05:
		var st := H.WALK
		if fleeing:
			st = H.FLEE
		elif spd >= HUMAN_RUN_FROM:
			st = H.RUN
		_phase[u] = fposmod(_phase[u] + moved / AnimSpec.STRIDE_HUMAN[st], 1.0)
		return AnimSpec.custom(st, _phase[u], 1.0, w)
	var reload_left := sim.u_reload_t[u] - t
	if reload_left > 0.0:
		var dur: float = AnimSpec.DURATION_HUMAN[H.RELOAD]
		return AnimSpec.custom(H.RELOAD, clampf(1.0 - reload_left / dur, 0.0, 1.0), 0.0, w)
	return AnimSpec.custom(H.IDLE, fposmod(t / AnimSpec.IDLE_PERIOD + w, 1.0), 0.0, w)


func _rider_custom(sim: BattleSim, u: int, t: float, spd: float, moved: float) -> Color:
	var w := sim.u_var[u]
	var life := sim.u_life[u]
	if life == BattleSim.Life.DEAD:
		return AnimSpec.custom(R.DEAD, 1.0, float(sim.u_fall[u]), w)
	if life == BattleSim.Life.DYING:
		return AnimSpec.custom(R.DYING, clampf((t - sim.u_death_t[u]) / AnimSpec.DURATION_HORSE[R.DYING], 0.0, 1.0),
			float(sim.u_fall[u]), w)
	var act := sim.u_act[u]
	var at := t - sim.u_act_t[u]
	if act == BattleSim.Act.MELEE and at >= 0.0:
		return AnimSpec.custom(R.MELEE, clampf(at / AnimSpec.DURATION_HORSE[R.MELEE], 0.0, 1.0), 0.0, w)
	if act == BattleSim.Act.CHEER and at >= 0.0 and spd < HORSE_TROT_FROM:
		# клич полководца: конь сначала встаёт на дыбы, потом ликование
		var rear: float = AnimSpec.DURATION_HORSE[R.REAR]
		if sim.u_role[u] == BattleSim.Role.GENERAL and at < rear:
			return AnimSpec.custom(R.REAR, at / rear, 0.0, w)
		return AnimSpec.custom(R.CHEER, clampf(at / AnimSpec.DURATION_HORSE[R.CHEER], 0.0, 1.0), 0.0, w)
	if spd > 0.05:
		var st := R.WALK
		if spd >= HORSE_GALLOP_FROM:
			st = R.CHARGE if sim.u_couched[u] == 1 else R.GALLOP
		elif spd >= HORSE_TROT_FROM:
			st = R.TROT
		_phase[u] = fposmod(_phase[u] + moved / (AnimSpec.STRIDE_HORSE[st] * _u_stride_k[u]), 1.0)
		return AnimSpec.custom(st, _phase[u], 1.0, w)
	return AnimSpec.custom(R.IDLE, fposmod(t / AnimSpec.IDLE_PERIOD + w, 1.0), 0.0, w)


func _update_ambient() -> void:
	for i in ambient.count:
		var l = layers.get(ambient.unit_ids[i])
		if l:
			l.set_instance(_a_slot[i], ambient.xforms[i], ambient.customs[i])
