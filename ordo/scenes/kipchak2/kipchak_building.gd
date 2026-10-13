class_name KipchakBuilding
extends Node3D
## Постройка или укрепление кыпчаков второй очереди (ТЗ 5.3, 6): модель по виду и состоянию.
##
##   var b := preload("res://scenes/kipchak2/munara.tscn").instantiate() as KipchakBuilding
##   add_child(b)
##   b.state = KipchakBuilding.State.SITE      # стройка (работники строят)
##   b.state = KipchakBuilding.State.BUILT     # готово
##   b.state = KipchakBuilding.State.RUIN      # руины (у звена и ворот — пролом, проходимо)
##   b.set_door_open(true)                     # ворота (darbaza): створки внутрь
##   for s in b.slots(): …                     # гарнизон башни: Marker3D Markers/Slot_1..6
##   b.markers("WorkSpot_")                    # где стоят работники (кен), Spawn — где выходят обученные
##
## Модели: assets/models/kipchak/<kind>[_site|_ruin][_lod1].glb (tools/gen_kipchak2.py).
## Материалы — KipchakModels.apply (живописные, ткань колышется от ordo_wind),
## LOD1 дальше lod_distance (дизеринг, как в лагере). Начало узла — центр основания,
## фасад в +Z (ТЗ 11.6). Метаданные сцены: kind, footprint (Vector2, м), side.

enum State { SITE, BUILT, RUIN }

const MODEL_DIR := "res://assets/models/kipchak/"
const SUFFIX := ["_site", "", "_ruin"]
## Контровой свет построек — как у лагеря (белый войлок светится по краю)
const RIM_STRENGTH := 1.1

## Вид: ken, jooker, kurultai, munara, chep, darbaza, munara_arba
@export var kind := "ken"
@export var state: State = State.BUILT:
	set(value):
		state = value
		if is_inside_tree():
			_rebuild()
## С какого расстояния камеры модель сменяется облегчённой (LOD1), м
@export var lod_distance := 140.0
## Пятно вытоптанной земли из glb (узлы «Ground*»). Как в лагере: по умолчанию землю рисуют
## декали/земля мира, пятно спрятано (свет на нём не совпадает со светом земли).
@export var show_ground := false
## Оттенок войлока (как metadata/tint у юрт лагеря)
@export var tint := Color(1, 1, 1, 1)

var _model: Node3D
var _door_open := 0.0


func _ready() -> void:
	var o := get_node_or_null("/root/Ordo")
	if o and bool(o.call("is_low")):
		lod_distance = minf(lod_distance, 80.0)   # телефоны (ТЗ 11.7)
	_rebuild()


## Узел модели текущего состояния (LOD0 и LOD1 внутри)
func model() -> Node3D:
	return _model


## Ворота: открыть/закрыть (amount 0..1 — для плавного открытия по кадрам).
## Door_L поворачивается на +90°, Door_R на −90° вокруг петли (створки уходят внутрь, к −Z).
func set_door_open(open: bool, amount := 1.0) -> void:
	_door_open = clampf(amount, 0.0, 1.0) if open else 0.0
	if _model == null:
		return
	for d in _model.find_children("Door", "", true, false):
		var l := d.get_node_or_null("Door_L") as Node3D
		var r := d.get_node_or_null("Door_R") as Node3D
		if l:
			l.rotation.y = deg_to_rad(90.0) * _door_open
		if r:
			r.rotation.y = deg_to_rad(-90.0) * _door_open


## Метки гарнизона башни (Marker3D Markers/Slot_1..N, +Z метки — наружу, к врагу)
func slots() -> Array[Marker3D]:
	return markers("Slot_")


## Метки по началу имени (Slot_, WorkSpot_, Smoke_, Spawn) — Marker3D в узле Markers
func markers(prefix: String) -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	var m := get_node_or_null("Markers")
	if m == null:
		return out
	for c in m.get_children():
		if c is Marker3D and String(c.name).begins_with(prefix):
			out.append(c)
	return out


## Одна метка по имени: marker("Spawn")
func marker(marker_name: String) -> Marker3D:
	return get_node_or_null("Markers/" + marker_name) as Marker3D


func _rebuild() -> void:
	if _model:
		_model.free()
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var base: String = MODEL_DIR + kind + String(SUFFIX[state])
	var opts := {"rim_strength": RIM_STRENGTH}
	if tint != Color(1, 1, 1, 1):
		opts["albedo_tint"] = tint
	var l0 := _instance(base + ".glb", "LOD0")
	if l0 == null:
		return
	KipchakModels.apply(l0, opts)
	var l1 := _instance(base + "_lod1.glb", "LOD1")
	if l1:
		KipchakModels.apply(l1, opts)
		_set_range(l0, 0.0, lod_distance)
		_set_range(l1, lod_distance, 0.0)
	if not show_ground:
		for n in _model.find_children("Ground*", "MeshInstance3D", true, false):
			(n as MeshInstance3D).visible = false
	for n in _model.find_children("Ground*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_door_open(_door_open > 0.0, _door_open)


func _instance(path: String, node_name: String) -> Node3D:
	if not ResourceLoader.exists(path):
		if node_name == "LOD0":
			push_error("KipchakBuilding: нет модели %s" % path)
		return null
	var n := (load(path) as PackedScene).instantiate() as Node3D
	n.name = node_name
	_model.add_child(n)
	return n


func _set_range(root: Node, begin: float, end: float) -> void:
	if root is GeometryInstance3D:
		var g := root as GeometryInstance3D
		g.visibility_range_begin = begin
		g.visibility_range_end = end
		g.visibility_range_begin_margin = 4.0 if begin > 0.0 else 0.0
		g.visibility_range_end_margin = 4.0 if end > 0.0 else 0.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for c in root.get_children():
		_set_range(c, begin, end)
