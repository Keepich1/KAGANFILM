class_name BuildingView
extends Node3D
## Постройки «Города» (ARCHITECTURE §13): по BuildingTable через GameQuery.
##
## Готовые постройки — MultiMesh на (тип, стадия поля, клетка CELL), как у WorldScatter: и
## render "multimesh" (звенья стен, арыки, дома, юрты), и "scene" с моделью арта или заместителем —
## мало вызовов отрисовки (у модели арта 1–5 частей, у заместителя одна). Двор дома (Var_1..3) —
## по месту: часть двора рисуется только у своих домов. Колесо мельницы крутится (экземпляры части
## «Wheel» каждый кадр, их мало). Узлами (BuildingLook.make) — стройки, руины, горящие и поля-
## заместители (полив — параметр экземпляра «wet»).
## Поле (дала) с моделью — стадия урожая (BuildingLook: <имя>_s0/_s1/_s2): «лалми» (воды меньше
## половины) — всходы, полив без работников — зелёное, полив с работниками — спелое.
## Дым (трубы, тандыры, печь — метки обёртки арта; тюндюки юрт) — один GPUParticles3D на группу
## (точки выпуска — по постройкам), дальше SMOKE_RANGE не рисуется. Плоское (поля, арыки, вода,
## двор, крышки срезов, обломки) теней не отбрасывает.
## Стройка растёт по progress (срез модели _site или готовой с лесами), руина — модель _ruin или
## обгоревший низ и обломки, свёрнутая (PACKED) не видна. Урон больше половины — огонь и дым
## (костёр лагеря без кострища) и копоть: постройка на это время уходит из MultiMesh в свой узел
## (дома, юрты, звенья — главные цели набега), починили — возвращается.
##
## Таблица сверяется каждый кадр дёшево (поколение, состояние, тип, прогресс по слотам); меняется
## только то, что изменилось. Время — PerfMeter «view_buildings».
##
##   view.node_of(b) -> Node3D        узел постройки слота b (null — MultiMesh или нет)
##   view.ground_y(b) -> float         высота основания
##   view.mm_instances(btype) -> int   готовых в MultiMesh у типа (тесты)

const CELL := 128.0
## Дым группы MultiMesh не рисуется дальше, м (от середины группы)
const SMOKE_RANGE := 320.0
const SMOKE_MAX := 1400
## Стадия урожая полей сверяется раз в столько кадров
const FIELD_EVERY := 30
const FIRE := preload("res://scenes/camp/campfire.tscn")
const FREE := BuildingTable.State.FREE
const SITE := BuildingTable.State.SITE
const ACTIVE := BuildingTable.State.ACTIVE
const PACKED := BuildingTable.State.PACKED
const RUIN := BuildingTable.State.RUIN

@export var driver_path: NodePath = ^"../../Driver"
## Дальность смены LOD0 → LOD1 у моделей, м
@export var lod_distance := 140.0

var query: GameQuery
var defs: Defs

var _gen := PackedInt32Array()
var _state := PackedInt32Array()
var _btype := PackedInt32Array()
var _prog := PackedInt32Array()
var _burn := PackedByteArray()
var _var := PackedInt32Array()           # двор дома (BuildingLook.variant_of) или стадия поля
var _node: Array[Node3D] = []
var _group: Array[String] = []           # ключ группы MultiMesh слота ("" — нет)
var _groups := {}                        # ключ → {btype, stage, slots: PackedInt32Array, mmis: Array, spin: Array}
var _dirty: Array[String] = []
var _spinning: Array[String] = []        # группы с колёсами
var _driver: Node
var _frame := 0
var _mm_kind := PackedInt32Array()       # по типу: −1 не знаем, 0 — узел, 1 — MultiMesh
var _t := 0.0


func _ready() -> void:
	_driver = get_node_or_null(driver_path)
	if _driver and _driver.has_signal("started"):
		_driver.connect("started", func(_s: int) -> void: set_query(CityView.query_of(_driver)))
	if CityView.query_of(_driver):
		set_query(CityView.query_of(_driver))


## Подключить окно чтения (новая игра — всё заново)
func set_query(q: GameQuery) -> void:
	for n in _node:
		if n:
			n.queue_free()
	for k in _groups:
		for mi: Node in _groups[k].mmis:
			mi.queue_free()
	_groups.clear()
	_dirty.clear()
	_spinning.clear()
	_node.clear()
	_group.clear()
	for a: Variant in [_gen, _state, _btype, _prog, _var]:
		a.resize(0)
	_burn.resize(0)
	_mm_kind.resize(0)
	query = q
	defs = q.defs() if q else null
	if q:
		sync()


func _process(delta: float) -> void:
	if query == null:
		return
	var t0 := CityView.now_usec()
	_t += delta
	sync()
	_spin()
	CityView.mark(&"view_buildings", t0)


## Сверка с таблицей построек: что изменилось — перестроить
func sync() -> void:
	_frame += 1
	var bt := query.buildings()
	var hw := bt.hw
	if _gen.size() < hw:
		var old := _gen.size()
		for a: Variant in [_gen, _state, _btype, _prog, _var]:
			a.resize(hw)
		_burn.resize(hw)
		_node.resize(hw)
		_group.resize(hw)
		for b in range(old, hw):
			_gen[b] = 0
			_state[b] = FREE
			_btype[b] = -1
			_prog[b] = -1
			_var[b] = 0
			_group[b] = ""
	var gen := bt.gen
	var state := bt.state
	var btype := bt.btype
	var prog := bt.progress
	for b in hw:
		if gen[b] != _gen[b] or state[b] != _state[b] or btype[b] != _btype[b]:
			_drop(b)
			_burn[b] = 0
			_gen[b] = gen[b]
			_state[b] = state[b]
			_btype[b] = btype[b]
			_prog[b] = -1
			_make(b, bt)
		if state[b] == SITE and prog[b] != _prog[b] and _node[b]:
			_prog[b] = prog[b]
			BuildingLook.set_progress(_node[b], prog[b] / 1000.0)
	# урон: раз в 10 кадров; стадии полей — раз в FIELD_EVERY
	if _frame % 10 == 0:
		_check_damage(bt)
	if _frame % FIELD_EVERY == 0:
		_check_fields(bt)
	for k in _dirty:
		_rebuild_group(k, bt)
	_dirty.clear()


func node_of(b: int) -> Node3D:
	return _node[b] if b < _node.size() else null


func ground_y(b: int) -> float:
	var bt := query.buildings()
	return _ground(bt.x[b], bt.z[b], defs.b_size[bt.btype[b]] if bt.btype[b] >= 0 else Vector2.ONE, bt.rot[b])


## Готовых в MultiMesh у типа — для тестов
func mm_instances(btype: int) -> int:
	var s := 0
	for k in _groups:
		var g: Dictionary = _groups[k]
		if g.btype == btype:
			s += (g.slots as PackedInt32Array).size()
	return s


## Узлов-построек (стройки, руины, горящие, поля-заместители) — для тестов
func scene_nodes() -> int:
	var s := 0
	for n in _node:
		if n:
			s += 1
	return s


## Групп MultiMesh (тип, стадия, клетка) — для тестов и замера
func group_count() -> int:
	return _groups.size()


## Готовая постройка типа ty рисуется MultiMesh: всё, кроме полей-заместителей (у них свой полив
## на экземпляр)
func uses_multimesh(ty: int) -> bool:
	if _mm_kind.size() < defs.b_ids.size():
		var old := _mm_kind.size()
		_mm_kind.resize(defs.b_ids.size())
		for t in range(old, _mm_kind.size()):
			_mm_kind[t] = -1
	if _mm_kind[ty] < 0:
		var mm := defs.b_render[ty] == Defs.Render.MULTIMESH or defs.b_kind[ty] != Defs.BKind.FIELD or \
			BuildingLook.model_name(defs, ty) != ""
		_mm_kind[ty] = 1 if mm else 0
	return _mm_kind[ty] == 1


## Стадия урожая поля b: «лалми» (воды под полем меньше половины) — 0 всходы, полив без работников —
## 1 зелёное, полив и работники — 2 спелое
func field_stage(b: int, bt: BuildingTable) -> int:
	var w := FieldView.water_at(query.water(), query.field_dims(), Vector2(bt.x[b], bt.z[b]))
	if w < 0.5:
		return 0
	return 2 if bt.workers_n[b] > 0 else 1


# ---------------------------------------------------------------- внутреннее

func _drop(b: int) -> void:
	if _node[b]:
		_free(_node[b])
		_node[b] = null
	if _group[b] != "":
		var g: Dictionary = _groups.get(_group[b], {})
		if not g.is_empty():
			var slots: PackedInt32Array = g.slots
			var i := slots.find(b)
			if i >= 0:
				slots.remove_at(i)
				g.slots = slots
			if not _dirty.has(_group[b]):
				_dirty.append(_group[b])
		_group[b] = ""


func _make(b: int, bt: BuildingTable) -> void:
	var st := bt.state[b]
	var ty := bt.btype[b]
	if st == FREE or st == PACKED or ty < 0:
		return
	var field := defs.b_kind[ty] == Defs.BKind.FIELD
	_var[b] = field_stage(b, bt) if field else BuildingLook.variant_of(defs, ty, Vector2(bt.x[b], bt.z[b]))
	var stage := _var[b] if field else 2
	if st == ACTIVE and _burn[b] == 0 and uses_multimesh(ty):
		var key := "%d:%d:%d:%d" % [ty, stage if field else 0, floori(bt.x[b] / CELL), floori(bt.z[b] / CELL)]
		if not _groups.has(key):
			_groups[key] = {"btype": ty, "stage": stage, "slots": PackedInt32Array(), "mmis": [], "spin": []}
		var g: Dictionary = _groups[key]
		var slots: PackedInt32Array = g.slots
		slots.append(b)
		g.slots = slots
		_group[b] = key
		if not _dirty.has(key):
			_dirty.append(key)
		return
	var n := BuildingLook.make(defs, ty, st, lod_distance, 0 if field else _var[b], stage)
	n.name = "B%d_%s" % [b, defs.b_ids[ty]]
	n.transform = _xform(b, bt)
	if BuildingLook.is_flat(defs, ty):
		BuildingLook.no_shadow(n)
	add_child(n)
	_node[b] = n
	# срез стройки и руины — от основания на своём месте, а не от y = 0 мира
	BuildingLook.set_base(n)
	if st == SITE:
		_prog[b] = bt.progress[b]
		BuildingLook.set_progress(n, bt.progress[b] / 1000.0)
	elif st == ACTIVE and _burn[b] == 1:
		_set_fire(n, true)


## Убрать узел сразу из дерева (новый узел с тем же именем в этом же кадре не переименуется)
func _free(n: Node) -> void:
	if n.get_parent() == self:
		remove_child(n)
	n.queue_free()


func _xform(b: int, bt: BuildingTable) -> Transform3D:
	var ty := bt.btype[b]
	var yaw := bt.rot[b]
	if defs.b_flags[ty] & Defs.BF_ROUND:
		# юрты: свой поворот по описателю (ARCHITECTURE §10)
		yaw = BattleRng.hash01(bt.handle(b)) * TAU
	var y := _ground(bt.x[b], bt.z[b], defs.b_size[ty], yaw)
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(bt.x[b], y, bt.z[b]))


## Основание: по самой низкой точке углов (не висит на склоне), поле и звено — по центру
func _ground(x: float, z: float, size: Vector2, yaw: float) -> float:
	var h := Terrain.height_at(x, z)
	if size.x * size.y < 10.0:
		return h
	var e := size * 0.45
	for k in 4:
		var c := Vector2(e.x * (1.0 if k % 2 == 0 else -1.0), e.y * (1.0 if k < 2 else -1.0)).rotated(-yaw)
		h = minf(h, Terrain.height_at(x + c.x, z + c.y))
	return h


func _rebuild_group(key: String, bt: BuildingTable) -> void:
	var g: Dictionary = _groups.get(key, {})
	if g.is_empty():
		return
	for mi: Node in g.mmis:
		_free(mi)
	var mmis: Array = []
	var spin: Array = []
	var slots: PackedInt32Array = g.slots
	if slots.is_empty():
		_groups.erase(key)
		_spinning.erase(key)
		return
	var ty: int = g.btype
	var stage: int = g.stage
	var flat := BuildingLook.is_flat(defs, ty)
	var base: Array[Transform3D] = []
	for i in slots.size():
		base.append(_xform(slots[i], bt))
	var has_lod1 := BuildingLook.parts_for(defs, ty, 1, stage).size() > 0
	for lod in 2:
		var parts := BuildingLook.parts_for(defs, ty, lod, stage)
		for pi in parts.size():
			var p: Dictionary = parts[pi]
			# часть двора Var_k — только у домов своего варианта
			var idx := PackedInt32Array()
			for i in slots.size():
				if int(p["var"]) == 0 or _var[slots[i]] == int(p["var"]):
					idx.append(i)
			if idx.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = p.mesh
			mm.instance_count = idx.size()
			var px: Transform3D = p.xform
			var xs: Array[Transform3D] = []
			for j in idx.size():
				var xf: Transform3D = base[idx[j]] * px
				mm.set_instance_transform(j, xf)
				xs.append(xf)
			var mi := MultiMeshInstance3D.new()
			mi.name = "MM_%s_P%d_L%d" % [key.replace(":", "_"), pi, lod]
			mi.multimesh = mm
			if flat or not bool(p.get("shadow", true)):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if p.material:
				mi.material_override = p.material
			if has_lod1:
				mi.visibility_range_begin = lod_distance if lod == 1 else 0.0
				mi.visibility_range_end = lod_distance if lod == 0 else 0.0
				mi.visibility_range_begin_margin = 4.0 if lod == 1 else 0.0
				mi.visibility_range_end_margin = 4.0 if lod == 0 else 0.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(mi)
			mmis.append(mi)
			if bool(p.get("spin", false)):
				spin.append({"mm": mm, "xs": xs})
	# дым (трубы, тандыры, печь, тюндюки): один выпуск на группу — светлый и тёмный отдельно
	for dark: bool in [false, true]:
		var pts := PackedVector3Array()
		var amount := 0
		for i in slots.size():
			for sp: Dictionary in BuildingLook.smoke_points(defs, ty, _var[slots[i]]):
				if bool(sp.dark) == dark:
					pts.append(base[i] * (sp.pos as Vector3))
					amount = maxi(amount, int(sp.amount))
		if pts.is_empty():
			continue
		var sm := group_smoke(pts, amount, dark)
		sm.name = "Smoke_%s%s" % [key.replace(":", "_"), "_dark" if dark else ""]
		add_child(sm)
		mmis.append(sm)
	g.mmis = mmis
	g.spin = spin
	if spin.is_empty():
		_spinning.erase(key)
	elif not _spinning.has(key):
		_spinning.append(key)


## Колёса мельниц: поворот вокруг своей оси X (как KokandBuilding)
func _spin() -> void:
	if _spinning.is_empty():
		return
	var turn := Basis(Vector3.RIGHT, -BuildingLook.WHEEL_SPEED * _t)
	for key in _spinning:
		var g: Dictionary = _groups.get(key, {})
		for s: Dictionary in g.get("spin", []):
			var mm: MultiMesh = s.mm
			var xs: Array[Transform3D] = s.xs
			for i in xs.size():
				var xf := xs[i]
				mm.set_instance_transform(i, Transform3D(xf.basis * turn, xf.origin))


## Один дым на много точек pts (в осях вида): дым лагеря с выпуском из точек; дальше SMOKE_RANGE
## не рисуется
static func group_smoke(pts: PackedVector3Array, amount_each := 14, dark := false) -> GPUParticles3D:
	var s := BuildingLook.smoke_node(pts, amount_each, dark, SMOKE_MAX)
	s.visibility_range_end = SMOKE_RANGE
	s.visibility_range_end_margin = 20.0
	s.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return s


## Огонь и дым на постройках с уроном больше половины. Постройка из MultiMesh уходит в свой узел
## (огонь, копоть), починили — обратно
func _check_damage(bt: BuildingTable) -> void:
	var hp := bt.hp_c
	var hpm := bt.hp_max_c
	var st := bt.state
	for b in bt.hw:
		var burning := st[b] == ACTIVE and hpm[b] > 0 and hp[b] * 2 < hpm[b]
		if burning == (_burn[b] == 1):
			continue
		_burn[b] = 1 if burning else 0
		if st[b] != ACTIVE:
			continue
		if _group[b] != "" or (not burning and uses_multimesh(bt.btype[b])):
			# MultiMesh ↔ узел: пересобрать слот (огонь ставит _make)
			_drop(b)
			_make(b, bt)
		elif _node[b]:
			_set_fire(_node[b], burning)


## Поля с моделью: сменилась стадия урожая — в группу своей стадии
func _check_fields(bt: BuildingTable) -> void:
	for b in bt.hw:
		if _group[b] == "" or bt.state[b] != ACTIVE:
			continue
		var ty := bt.btype[b]
		if defs.b_kind[ty] != Defs.BKind.FIELD:
			continue
		if field_stage(b, bt) != _var[b]:
			_drop(b)
			_make(b, bt)


func _set_fire(n: Node3D, on: bool) -> void:
	var f := n.get_node_or_null("Fire")
	if on and f == null:
		var fire := FIRE.instantiate() as Node3D
		fire.name = "Fire"
		fire.set("show_model", false)
		fire.position = Vector3(0, float(n.get_meta("height", 4.0)) * 0.7, 0)
		fire.scale = Vector3(1.6, 1.6, 1.6)
		n.add_child(fire)
		BuildingLook.set_scorch(n, 0.45)
	elif not on and f:
		f.queue_free()
		BuildingLook.set_scorch(n, 0.0)
