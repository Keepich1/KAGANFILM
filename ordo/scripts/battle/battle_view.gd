class_name BattleView
extends Node3D
## Отображение боя: симуляция (SimDriver: ScenarioClash, GameDriver) и жизнь лагеря (BattleAmbient) → слои толпы,
## по одному слою на вид юнита, каждый кадр.
##
## Слой — настоящая толпа CrowdLayer (scripts/units/crowd_layer.gd), если она есть в проекте,
## иначе запасной BattleDebugLayer с теми же методами. Классы толпы подключаются по пути
## во время работы, без прямых ссылок: после слияния настоящая толпа подхватится сама.
##
## Анимация (AnimSpec): ход по скорости (шаг/бег, шаг/рысь/галоп), фаза шага растёт на
## пройденный путь / STRIDE (ноги не скользят), разовые — по времени от начала, смерть → лежит,
## клич → CHEER, сарбозы — SHOOT/RELOAD, копейщики на разгоне — CHARGE. Вариант w стабилен.
##
## Скорость (тысячи юнитов): шаги боя ведёт SimStepper — у большого боя шаг считается в фоне,
## пока кадр рисуется, а вид читает снимок прошлых шагов. Юниты пишутся прямо в буфер слоя
## (CrowdLayer.buffer), по слоям; павшие, раз записанные, больше не трогаются (лежат на месте).
## Время вида за кадр — PerfMeter «view» (экран F9 в срезе).

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

# длительности и шаги из AnimSpec — числами (без поиска в словаре на каждого юнита)
const DH_SHOOT: float = AnimSpec.DURATION_HUMAN[H.SHOOT]
const DH_MELEE: float = AnimSpec.DURATION_HUMAN[H.MELEE]
const DH_CHEER: float = AnimSpec.DURATION_HUMAN[H.CHEER]
const DH_RELOAD: float = AnimSpec.DURATION_HUMAN[H.RELOAD]
const DH_DYING: float = AnimSpec.DURATION_HUMAN[H.DYING]
const DR_MELEE: float = AnimSpec.DURATION_HORSE[R.MELEE]
const DR_CHEER: float = AnimSpec.DURATION_HORSE[R.CHEER]
const DR_REAR: float = AnimSpec.DURATION_HORSE[R.REAR]
const DR_DYING: float = AnimSpec.DURATION_HORSE[R.DYING]
const SH_WALK: float = AnimSpec.STRIDE_HUMAN[H.WALK]
const SH_RUN: float = AnimSpec.STRIDE_HUMAN[H.RUN]
const SH_FLEE: float = AnimSpec.STRIDE_HUMAN[H.FLEE]
const SR_WALK: float = AnimSpec.STRIDE_HORSE[R.WALK]
const SR_TROT: float = AnimSpec.STRIDE_HORSE[R.TROT]
const SR_GALLOP: float = AnimSpec.STRIDE_HORSE[R.GALLOP]
const SR_CHARGE: float = AnimSpec.STRIDE_HORSE[R.CHARGE]
const ALIVE := BattleSim.Life.ALIVE
const DEAD := BattleSim.Life.DEAD
const DYING := BattleSim.Life.DYING

@export var scenario_path: NodePath = ^"../Scenario"
@export var ambient_path: NodePath = ^"../Ambient"
## Рисовать запасными фигурами, даже если настоящая толпа есть
@export var force_debug := false

var scenario: SimDriver
var ambient: BattleAmbient
## unit_id → слой (CrowdLayer или BattleDebugLayer)
var layers := {}
var using_real_crowd := false

var _crowd_script: Script
var _registry := {}
var _sim: BattleSim
var _stepper: SimStepper
var _u_layer: Array[String] = []
var _u_slot := PackedInt32Array()
var _u_skel := PackedInt32Array()     # 0 человек, 1 конь (всадник)
var _u_stride_k := PackedFloat32Array()
var _u_fallrot := PackedFloat32Array()  # поворот павшего (вразнобой)
var _u_done := PackedByteArray()      # павший уже записан — дальше не трогаем
var _phase := PackedFloat32Array()
var _lx := PackedFloat32Array()
var _lz := PackedFloat32Array()
var _a_slot := PackedInt32Array()
var _a_layer: Array = []
var _counts := {}
# слои боя по порядку и их юниты (в порядке мест)
var _layer_list: Array = []
var _layer_units: Array[PackedInt32Array] = []
var _layer_fast: Array[bool] = []

# что читает кадр: живые массивы симуляции или снимок SimStepper (бой в фоне)
var _b_owner: Object
var _b_time := 0.0
var _b_x := PackedFloat32Array()
var _b_z := PackedFloat32Array()
var _b_h := PackedFloat32Array()
var _b_px := PackedFloat32Array()
var _b_pz := PackedFloat32Array()
var _b_ph := PackedFloat32Array()
var _b_vx := PackedFloat32Array()
var _b_vz := PackedFloat32Array()
var _b_life := PackedInt32Array()
var _b_death_t := PackedFloat32Array()
var _b_act := PackedInt32Array()
var _b_act_t := PackedFloat32Array()
var _b_reload_t := PackedFloat32Array()
var _b_couched := PackedInt32Array()
var _b_fall := PackedInt32Array()
var _b_sq_status := PackedInt32Array()
var _b_var := PackedFloat32Array()
var _b_role := PackedInt32Array()
var _b_squad := PackedInt32Array()

# высоты земли (Terrain.height_at, та же формула — без вызова на каждого юнита)
var _hgt := PackedFloat32Array()
var _hn := 0
var _hsp := 2.0
var _hox := 0.0
var _hoz := 0.0


func _ready() -> void:
	scenario = get_node_or_null(scenario_path) as SimDriver
	ambient = get_node_or_null(ambient_path) as BattleAmbient
	if not force_debug and ResourceLoader.exists(CROWD_LAYER_PATH):
		_crowd_script = load(CROWD_LAYER_PATH) as Script
		using_real_crowd = _crowd_script != null
	if ResourceLoader.exists(REGISTRY_PATH):
		var reg := load(REGISTRY_PATH) as Script
		if reg:
			_registry = reg.get_script_constant_map().get("UNITS", {})
	if scenario:
		# шаги боя ведёт вид (тот же счёт времени; большой бой — в фоне)
		_stepper = SimStepper.new(scenario)
		scenario.set_process(false)
		scenario.started.connect(_on_started)
		if scenario.sim:
			_on_started(scenario.current_seed)
	elif ambient:
		_rebuild()


func _exit_tree() -> void:
	if _stepper:
		_stepper.release(false)


func _enter_tree() -> void:
	if _stepper and is_instance_valid(scenario):
		scenario.set_process(false)


## Дождаться фонового шага боя: перед любым изменением симуляции снаружи (перезапуск, приказы)
func sync_sim() -> void:
	if _stepper:
		_stepper.sync()


## Шаги боя (SimStepper) — у большого боя фон включён
func stepper() -> SimStepper:
	return _stepper


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
	_u_fallrot.resize(n)
	_u_done.resize(n)
	_u_done.fill(0)
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
		_u_fallrot[u] = (BattleRng.hash01(u * 7 + 3) - 0.5) * 1.5
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
	# юниты боя по слоям, в порядке мест
	_layer_list.clear()
	_layer_units.clear()
	_layer_fast.clear()
	var index := {}
	for u in n:
		var vid := _u_layer[u]
		if vid == "":
			continue
		if not index.has(vid):
			index[vid] = _layer_list.size()
			var l: Node3D = layers[vid]
			_layer_list.append(l)
			_layer_units.append(PackedInt32Array())
			_layer_fast.append(l.has_method("buffer") and l.has_method("expand_bounds"))
		_layer_units[int(index[vid])].append(u)
	_a_layer.resize(an)
	for i in an:
		_a_layer[i] = layers.get(ambient.unit_ids[i])
	_hgt = Terrain.heights()
	_hn = Terrain.size()
	_hsp = Terrain.spacing()
	var o := Terrain.origin()
	_hox = o.x
	_hoz = o.y
	_b_owner = null


func _make_layer() -> Node3D:
	if using_real_crowd:
		var l := _crowd_script.new() as Node3D
		if l:
			return l
	return DebugLayer.new()


func _process(delta: float) -> void:
	if _stepper:
		_stepper.advance(delta)
	update_view()


## Кадр вида без шага боя (замер tests/bench_battle.gd зовёт его сам)
func update_view() -> void:
	var t0 := Time.get_ticks_usec()
	if _sim and scenario and scenario.sim == _sim:
		_update_battle()
	if ambient:
		_update_ambient()
	PerfMeter.add_frame(&"view", (Time.get_ticks_usec() - t0) / 1000.0)


# ---------------------------------------------------------------- данные кадра

## Живые массивы симуляции (без фона; и для проверок test_view)
func _bind_sim(sim: BattleSim) -> void:
	_b_owner = sim
	_b_time = sim.time
	_b_x = sim.u_x
	_b_z = sim.u_z
	_b_h = sim.u_h
	_b_px = sim.u_px
	_b_pz = sim.u_pz
	_b_ph = sim.u_ph
	_b_vx = sim.u_vx
	_b_vz = sim.u_vz
	_b_life = sim.u_life
	_b_death_t = sim.u_death_t
	_b_act = sim.u_act
	_b_act_t = sim.u_act_t
	_b_reload_t = sim.u_reload_t
	_b_couched = sim.u_couched
	_b_fall = sim.u_fall
	_b_sq_status = sim.sq_status
	_bind_const(sim)


## Снимок двух последних принятых шагов (бой считается в фоне)
func _bind_snapshot(st: SimStepper) -> void:
	_b_owner = st
	_b_time = st.snap_time
	_b_x = st.s_x
	_b_z = st.s_z
	_b_h = st.s_h
	_b_px = st.s_px
	_b_pz = st.s_pz
	_b_ph = st.s_ph
	_b_vx = st.s_vx
	_b_vz = st.s_vz
	_b_life = st.s_life
	_b_death_t = st.s_death_t
	_b_act = st.s_act
	_b_act_t = st.s_act_t
	_b_reload_t = st.s_reload_t
	_b_couched = st.s_couched
	_b_fall = st.s_fall
	_b_sq_status = st.s_sq_status
	_bind_const(st.snap_sim)


## Неизменные после создания поля юнитов (их фон не пишет)
func _bind_const(sim: BattleSim) -> void:
	_b_var = sim.u_var
	_b_role = sim.u_role
	_b_squad = sim.u_squad


func _update_battle() -> void:
	if _stepper and _stepper.uses_snapshot():
		_bind_snapshot(_stepper)
	else:
		_bind_sim(_sim)
	var t := _b_time
	var a := scenario.alpha
	var n := mini(_u_slot.size(), _b_x.size())
	var done := _u_done
	var lx := _lx
	var lz := _lz
	var px := _b_px
	var pz := _b_pz
	var ph := _b_ph
	var ux := _b_x
	var uz := _b_z
	var uh := _b_h
	var vxs := _b_vx
	var vzs := _b_vz
	var lifes := _b_life
	var death_t := _b_death_t
	var fallrot := _u_fallrot
	var slots := _u_slot
	var hg := _hgt
	var hn := _hn
	var hsp := _hsp
	var hox := _hox
	var hoz := _hoz
	var hmax := hn - 1.001
	for li in _layer_list.size():
		var l: Node3D = _layer_list[li]
		var units: PackedInt32Array = _layer_units[li]
		var fast := _layer_fast[li]
		var buf: PackedFloat32Array = l.call("buffer") if fast else PackedFloat32Array()
		var x0 := INF
		var y0 := INF
		var z0 := INF
		var x1 := -INF
		var y1 := -INF
		var z1 := -INF
		for u in units:
			if u >= n or done[u] == 1:
				continue
			var life := lifes[u]
			var x := lerpf(px[u], ux[u], a)
			var z := lerpf(pz[u], uz[u], a)
			var h := lerp_angle(ph[u], uh[u], a)
			if life != ALIVE:
				# павшие лежат вразнобой, а не ровными рядами (поворот растёт за время падения)
				var k := 1.0 if life == DEAD else clampf((t - death_t[u]) / 0.8, 0.0, 1.0)
				h += fallrot[u] * k
			var mx := x - lx[u]
			var mz := z - lz[u]
			var moved := sqrt(mx * mx + mz * mz)
			lx[u] = x
			lz[u] = z
			var vx := vxs[u]
			var vz := vzs[u]
			var spd := sqrt(vx * vx + vz * vz)
			var c := _human_c(u, t, spd, moved) if _u_skel[u] == 0 else _rider_c(u, t, spd, moved)
			# высота земли: Terrain.height_at
			var y := 0.0
			if hn > 1:
				var fx := clampf((x - hox) / hsp, 0.0, hmax)
				var fz := clampf((z - hoz) / hsp, 0.0, hmax)
				var i := int(fx)
				var j := int(fz)
				var kk := j * hn + i
				var fu := fx - i
				y = lerpf(lerpf(hg[kk], hg[kk + 1], fu), lerpf(hg[kk + hn], hg[kk + hn + 1], fu), fz - j)
			if fast:
				# поворот вокруг Y (Basis(Vector3.UP, h)), строки 3×4 + INSTANCE_CUSTOM
				var o := slots[u] * 16
				var cs := cos(h)
				var sn := sin(h)
				buf[o] = cs
				buf[o + 2] = sn
				buf[o + 3] = x
				buf[o + 7] = y
				buf[o + 8] = -sn
				buf[o + 10] = cs
				buf[o + 11] = z
				buf[o + 12] = c.r
				buf[o + 13] = c.g
				buf[o + 14] = c.b
				buf[o + 15] = c.a
				x0 = minf(x0, x)
				x1 = maxf(x1, x)
				y0 = minf(y0, y)
				y1 = maxf(y1, y)
				z0 = minf(z0, z)
				z1 = maxf(z1, z)
			else:
				l.call("set_instance", slots[u], Transform3D(Basis(Vector3.UP, h), Vector3(x, y, z)), c)
			if life == DEAD:
				done[u] = 1
		if fast and x0 <= x1:
			l.call("expand_bounds", Vector3(x0, y0, z0), Vector3(x1, y1, z1))


## Данные анимации человека (как AnimSpec.custom). Для проверок: _human_custom(sim, …)
func _human_c(u: int, t: float, spd: float, moved: float) -> Color:
	var w := _b_var[u]
	var life := _b_life[u]
	if life == DEAD:
		return Color(float(H.DEAD), 1.0, float(_b_fall[u]), w)
	if life == DYING:
		return Color(float(H.DYING), clampf((t - _b_death_t[u]) / DH_DYING, 0.0, 1.0), float(_b_fall[u]), w)
	var act := _b_act[u]
	var at := t - _b_act_t[u]
	if act == BattleSim.Act.AIM and at >= 0.0 and at < DH_SHOOT:
		return Color(float(H.SHOOT), at / DH_SHOOT, 0.0, w)
	if act == BattleSim.Act.MELEE and at >= 0.0:
		return Color(float(H.MELEE), clampf(at / DH_MELEE, 0.0, 1.0), 0.0, w)
	if act == BattleSim.Act.CHEER and at >= 0.0:
		return Color(float(H.CHEER), clampf(at / DH_CHEER, 0.0, 1.0), 0.0, w)
	if spd > 0.05:
		var st := H.WALK
		var stride := SH_WALK
		if _b_sq_status[_b_squad[u]] == BattleSim.Status.FLEE:
			st = H.FLEE
			stride = SH_FLEE
		elif spd >= HUMAN_RUN_FROM:
			st = H.RUN
			stride = SH_RUN
		_phase[u] = fposmod(_phase[u] + moved / stride, 1.0)
		return Color(float(st), _phase[u], 1.0, w)
	var reload_left := _b_reload_t[u] - t
	if reload_left > 0.0:
		return Color(float(H.RELOAD), clampf(1.0 - reload_left / DH_RELOAD, 0.0, 1.0), 0.0, w)
	return Color(float(H.IDLE), fposmod(t / AnimSpec.IDLE_PERIOD + w, 1.0), 0.0, w)


## Данные анимации всадника (как AnimSpec.custom). Для проверок: _rider_custom(sim, …)
func _rider_c(u: int, t: float, spd: float, moved: float) -> Color:
	var w := _b_var[u]
	var life := _b_life[u]
	if life == DEAD:
		return Color(float(R.DEAD), 1.0, float(_b_fall[u]), w)
	if life == DYING:
		return Color(float(R.DYING), clampf((t - _b_death_t[u]) / DR_DYING, 0.0, 1.0), float(_b_fall[u]), w)
	var act := _b_act[u]
	var at := t - _b_act_t[u]
	if act == BattleSim.Act.MELEE and at >= 0.0:
		return Color(float(R.MELEE), clampf(at / DR_MELEE, 0.0, 1.0), 0.0, w)
	if act == BattleSim.Act.CHEER and at >= 0.0 and spd < HORSE_TROT_FROM:
		# клич полководца: конь сначала встаёт на дыбы, потом ликование
		if _b_role[u] == BattleSim.Role.GENERAL and at < DR_REAR:
			return Color(float(R.REAR), at / DR_REAR, 0.0, w)
		return Color(float(R.CHEER), clampf(at / DR_CHEER, 0.0, 1.0), 0.0, w)
	if spd > 0.05:
		var st := R.WALK
		var stride := SR_WALK
		if spd >= HORSE_GALLOP_FROM:
			if _b_couched[u] == 1:
				st = R.CHARGE
				stride = SR_CHARGE
			else:
				st = R.GALLOP
				stride = SR_GALLOP
		elif spd >= HORSE_TROT_FROM:
			st = R.TROT
			stride = SR_TROT
		_phase[u] = fposmod(_phase[u] + moved / (stride * _u_stride_k[u]), 1.0)
		return Color(float(st), _phase[u], 1.0, w)
	return Color(float(R.IDLE), fposmod(t / AnimSpec.IDLE_PERIOD + w, 1.0), 0.0, w)


## То же для проверок без кадра (tests/test_view.gd): по живым массивам sim
func _human_custom(sim: BattleSim, u: int, t: float, spd: float, moved: float) -> Color:
	if _b_owner != sim:
		_bind_sim(sim)
	return _human_c(u, t, spd, moved)


func _rider_custom(sim: BattleSim, u: int, t: float, spd: float, moved: float) -> Color:
	if _b_owner != sim:
		_bind_sim(sim)
	return _rider_c(u, t, spd, moved)


func _update_ambient() -> void:
	for i in ambient.count:
		var l = _a_layer[i] if i < _a_layer.size() else layers.get(ambient.unit_ids[i])
		if l:
			l.set_instance(_a_slot[i], ambient.xforms[i], ambient.customs[i])
