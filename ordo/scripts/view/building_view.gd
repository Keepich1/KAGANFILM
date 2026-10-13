class_name BuildingView
extends Node3D
## Постройки «Города» (ARCHITECTURE §13): по BuildingTable через GameQuery.
##
## render "scene" — узел на постройку (BuildingLook.make: модель или заместитель, LOD, дым тюндюка).
## render "multimesh" (звенья стен, арыки, дома, юрты) — готовые постройки одним MultiMesh на
## (тип, клетка 128 м), как у WorldScatter; стройки и руины этих типов — отдельными узлами (их мало).
## Заместители «scene»-типов без модели (один меш, один материал) готовыми — тоже MultiMesh на
## (тип, клетка): мало вызовов отрисовки; поля (дала) — узлы (полив — параметр экземпляра).
## Дым тюндюков юрт MultiMesh — один GPUParticles3D на группу (точки выпуска — тюндюки), дальше
## SMOKE_RANGE не рисуется. Плоское (поля, арыки, крышки срезов, обломки) теней не отбрасывает.
## Стройка растёт по progress (срез модели + леса), руина — обгоревший низ и обломки,
## свёрнутая (PACKED) не видна. Урон больше половины — огонь и дым (костёр лагеря без кострища) и
## копоть; готовая постройка из MultiMesh на это время уходит в свой узел (дома, юрты, звенья стен —
## главные цели набега), починили — возвращается в MultiMesh.
##
## Таблица сверяется каждый кадр дёшево (поколение, состояние, тип, прогресс по слотам); меняется
## только то, что изменилось. Время — PerfMeter «view_buildings».
##
##   view.node_of(b) -> Node3D        узел постройки слота b (null — MultiMesh или нет)
##   view.ground_y(b) -> float         высота основания
##   view.mm_instances(btype) -> int   экземпляров MultiMesh типа (тесты)

const CELL := 128.0
## Дым тюндюков группы MultiMesh не рисуется дальше, м (от середины группы)
const SMOKE_RANGE := 320.0
## Частиц дыма на тюндюк (как у узла юрты) и предел на группу
const SMOKE_PER := 14
const SMOKE_MAX := 1400
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
var _mm_kind := PackedInt32Array()      # по типу: −1 не знаем, 0 — узел, 1 — MultiMesh


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
	_mm_kind.resize(0)
	query = q
	defs = q.defs() if q else null
	if q:
		sync()


func _process(_delta: float) -> void:
	if query == null:
		return
	var t0 := CityView.now_usec()
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
			_burn[b] = 0
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


## Готовая постройка типа ty рисуется MultiMesh: render "multimesh" или заместитель без модели
## (кроме полей: у них свой полив на экземпляр)
func uses_multimesh(ty: int) -> bool:
	if _mm_kind.size() < defs.b_ids.size():
		var old := _mm_kind.size()
		_mm_kind.resize(defs.b_ids.size())
		for t in range(old, _mm_kind.size()):
			_mm_kind[t] = -1
	if _mm_kind[ty] < 0:
		var mm := defs.b_render[ty] == Defs.Render.MULTIMESH or \
			(defs.b_kind[ty] != Defs.BKind.FIELD and BuildingLook.model_path(defs, ty, ACTIVE) == "")
		_mm_kind[ty] = 1 if mm else 0
	return _mm_kind[ty] == 1


func _make(b: int, bt: BuildingTable) -> void:
	var st := bt.state[b]
	var ty := bt.btype[b]
	if st == FREE or st == PACKED or ty < 0:
		return
	if st == ACTIVE and _burn[b] == 0 and uses_multimesh(ty):
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
	if BuildingLook.is_flat(defs, ty):
		BuildingLook.no_shadow(n)
	add_child(n)
	_node[b] = n
	# срез руины (и стройки) — от основания на своём месте, а не от y = 0 мира
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
	var slots: PackedInt32Array = g.slots
	if slots.is_empty():
		_groups.erase(key)
		return
	var ty: int = g.btype
	var flat := BuildingLook.is_flat(defs, ty)
	for lod in 2:
		var parts := BuildingLook.parts_for(defs, ty, lod)
		for pi in parts.size():
			var p: Dictionary = parts[pi]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = p.mesh
			mm.instance_count = slots.size()
			var px: Transform3D = p.xform
			for i in slots.size():
				mm.set_instance_transform(i, _xform(slots[i], bt) * px)
			var mi := MultiMeshInstance3D.new()
			mi.name = "MM_%s_P%d_L%d" % [key.replace(":", "_"), pi, lod]
			mi.multimesh = mm
			if flat:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	# дым из тюндюков у юрт MultiMesh (как у лагеря среза): один выпуск на группу
	var model := defs.b_model[ty] if defs.b_model[ty] != "" else defs.b_ids[ty]
	if BuildingLook.TUNDUK_HEIGHT.has(model) and BuildingLook.model_path(defs, ty, ACTIVE) != "":
		var pts := PackedVector3Array()
		for i in slots.size():
			pts.append(_xform(slots[i], bt) * Vector3(0, BuildingLook.TUNDUK_HEIGHT[model], 0))
		var sm := group_smoke(pts)
		sm.name = "TundukSmoke_%s" % key.replace(":", "_")
		add_child(sm)
		mmis.append(sm)
	g.mmis = mmis


## Один дым на много тюндюков: GPUParticles3D дыма лагеря с выпуском из точек pts (в осях вида);
## узел — в середине точек (по нему меряется SMOKE_RANGE)
static func group_smoke(pts: PackedVector3Array) -> GPUParticles3D:
	var s := BuildingLook.SMOKE.instantiate() as GPUParticles3D
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var mid := (lo + hi) * 0.5
	var img := Image.create(pts.size(), 1, false, Image.FORMAT_RGBF)
	for i in pts.size():
		var p := pts[i] - mid
		img.set_pixel(i, 0, Color(p.x, p.y, p.z))
	var pm := (s.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.emission_point_texture = ImageTexture.create_from_image(img)
	pm.emission_point_count = pts.size()
	s.process_material = pm
	s.position = mid
	s.amount = mini(SMOKE_PER * pts.size(), SMOKE_MAX)
	s.lifetime = 9.0
	s.preprocess = 9.0
	# весь столб над каждой точкой (как у одиночного дыма: −6..8 в стороны, −1..15 вверх)
	s.visibility_aabb = AABB(lo - mid + Vector3(-6, -1, -6), hi - lo + Vector3(14, 16, 14))
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
	for b in mini(bt.hw, _node.size()):
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
