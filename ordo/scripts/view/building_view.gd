class_name BuildingView
extends Node3D
## Постройки «Города» (ARCHITECTURE §13): по BuildingTable через GameQuery.
##
## render "scene" — узел на постройку (BuildingLook.make: модель или заместитель, LOD, дым тюндюка).
## render "multimesh" (звенья стен, арыки, дома, юрты) — готовые постройки одним MultiMesh на
## (тип, клетка 128 м), как у WorldScatter; стройки и руины этих типов — отдельными узлами (их мало).
## Стройка растёт по progress (срез модели + леса), руина — обгоревший низ и обломки,
## свёрнутая (PACKED) не видна. Урон больше половины — огонь и дым (костёр лагеря без кострища).
##
## Таблица сверяется каждый кадр дёшево (поколение, состояние, тип, прогресс по слотам); меняется
## только то, что изменилось. Время — PerfMeter «view_buildings».
##
##   view.node_of(b) -> Node3D        узел постройки слота b (null — MultiMesh или нет)
##   view.ground_y(b) -> float         высота основания
##   view.mm_instances(btype) -> int   экземпляров MultiMesh типа (тесты)

const CELL := 128.0
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
var _node: Array[Node3D] = []
var _group: Array[String] = []           # ключ группы MultiMesh слота ("" — нет)
var _groups := {}                        # ключ → {btype, slots: PackedInt32Array, mmis: Array, dirty}
var _dirty: Array[String] = []
var _driver: Node
var _frame := 0


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
	_node.clear()
	_group.clear()
	for a: Variant in [_gen, _state, _btype, _prog]:
		a.resize(0)
	_burn.resize(0)
	query = q
	defs = q.defs() if q else null
	if q:
		sync()


func _process(_delta: float) -> void:
	if query == null:
		return
	var t0 := Time.get_ticks_usec()
	sync()
	CityView.mark(&"view_buildings", t0)


## Сверка с таблицей построек: что изменилось — перестроить
func sync() -> void:
	_frame += 1
	var bt := query.buildings()
	var hw := bt.hw
	if _gen.size() < hw:
		var old := _gen.size()
		for a: Variant in [_gen, _state, _btype, _prog]:
			a.resize(hw)
		_burn.resize(hw)
		_node.resize(hw)
		_group.resize(hw)
		for b in range(old, hw):
			_gen[b] = 0
			_state[b] = FREE
			_btype[b] = -1
			_prog[b] = -1
			_group[b] = ""
	var gen := bt.gen
	var state := bt.state
	var btype := bt.btype
	var prog := bt.progress
	for b in hw:
		if gen[b] != _gen[b] or state[b] != _state[b] or btype[b] != _btype[b]:
			_drop(b)
			_gen[b] = gen[b]
			_state[b] = state[b]
			_btype[b] = btype[b]
			_prog[b] = -1
			_make(b, bt)
		if state[b] == SITE and prog[b] != _prog[b] and _node[b]:
			_prog[b] = prog[b]
			BuildingLook.set_progress(_node[b], prog[b] / 1000.0)
	# урон: раз в 10 кадров
	if _frame % 10 == 0:
		_check_damage(bt)
	for k in _dirty:
		_rebuild_group(k, bt)
	_dirty.clear()


func node_of(b: int) -> Node3D:
	return _node[b] if b < _node.size() else null


func ground_y(b: int) -> float:
	var bt := query.buildings()
	return _ground(bt.x[b], bt.z[b], defs.b_size[bt.btype[b]] if bt.btype[b] >= 0 else Vector2.ONE, bt.rot[b])


## Экземпляров MultiMesh у типа (LOD0) — для тестов
func mm_instances(btype: int) -> int:
	var s := 0
	for k in _groups:
		var g: Dictionary = _groups[k]
		if g.btype == btype:
			s += (g.slots as PackedInt32Array).size()
	return s


## Узлов-построек (стройки, руины, «scene») — для тестов
func scene_nodes() -> int:
	var s := 0
	for n in _node:
		if n:
			s += 1
	return s


# ---------------------------------------------------------------- внутреннее

func _drop(b: int) -> void:
	if _node[b]:
		_node[b].queue_free()
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
	_burn[b] = 0


func _make(b: int, bt: BuildingTable) -> void:
	var st := bt.state[b]
	var ty := bt.btype[b]
	if st == FREE or st == PACKED or ty < 0:
		return
	if st == ACTIVE and defs.b_render[ty] == Defs.Render.MULTIMESH:
		var key := "%d:%d:%d" % [ty, floori(bt.x[b] / CELL), floori(bt.z[b] / CELL)]
		if not _groups.has(key):
			_groups[key] = {"btype": ty, "slots": PackedInt32Array(), "mmis": []}
		var g: Dictionary = _groups[key]
		var slots: PackedInt32Array = g.slots
		slots.append(b)
		g.slots = slots
		_group[b] = key
		if not _dirty.has(key):
			_dirty.append(key)
		return
	var n := BuildingLook.make(defs, ty, st, lod_distance)
	n.name = "B%d_%s" % [b, defs.b_ids[ty]]
	n.transform = _xform(b, bt)
	add_child(n)
	_node[b] = n
	if st == SITE:
		_prog[b] = bt.progress[b]
		BuildingLook.set_progress(n, bt.progress[b] / 1000.0)


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
		mi.queue_free()
	var mmis: Array = []
	var slots: PackedInt32Array = g.slots
	if slots.is_empty():
		_groups.erase(key)
		return
	var ty: int = g.btype
	for lod in 2:
		var parts := BuildingLook.parts_for(defs, ty, lod)
		for p: Dictionary in parts:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = p.mesh
			mm.instance_count = slots.size()
			var px: Transform3D = p.xform
			for i in slots.size():
				mm.set_instance_transform(i, _xform(slots[i], bt) * px)
			var mi := MultiMeshInstance3D.new()
			mi.name = "MM_%s_L%d" % [key.replace(":", "_"), lod]
			mi.multimesh = mm
			if p.material:
				mi.material_override = p.material
			if BuildingLook.parts_for(defs, ty, 1).size() > 0:
				mi.visibility_range_begin = 0.0 if lod == 0 else lod_distance
				mi.visibility_range_end = lod_distance if lod == 0 else 0.0
				mi.visibility_range_begin_margin = 4.0 if lod == 1 else 0.0
				mi.visibility_range_end_margin = 4.0 if lod == 0 else 0.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(mi)
			mmis.append(mi)
	g.mmis = mmis


## Огонь и дым на постройках с уроном больше половины
func _check_damage(bt: BuildingTable) -> void:
	var hp := bt.hp_c
	var hpm := bt.hp_max_c
	var st := bt.state
	for b in mini(bt.hw, _node.size()):
		var burning := st[b] == ACTIVE and hpm[b] > 0 and hp[b] * 2 < hpm[b]
		if burning == (_burn[b] == 1):
			continue
		_burn[b] = 1 if burning else 0
		var n := _node[b]
		if n == null:
			continue
		var f := n.get_node_or_null("Fire")
		if burning and f == null:
			var fire := FIRE.instantiate() as Node3D
			fire.name = "Fire"
			fire.set("show_model", false)
			fire.position = Vector3(0, float(n.get_meta("height", 4.0)) * 0.7, 0)
			fire.scale = Vector3(1.6, 1.6, 1.6)
			n.add_child(fire)
			BuildingLook.set_scorch(n, 0.45)
		elif not burning and f:
			f.queue_free()
			BuildingLook.set_scorch(n, 0.0)
