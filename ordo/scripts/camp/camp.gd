class_name KipchakCamp
extends Node3D
## Лагерь кыпчаков (срез стиля, ТЗ этап 0): Хан ордосу, кольцо боз үй, туг, загоны,
## арбы, костры, дым из тюндюков. Сцена в мировых координатах (CONTRACT §3);
## своего неба и солнца нет — свет даёт мир.
##
## При запуске: ставит всё на землю (Terrain.height_at), включает живописные материалы
## (KipchakModels.apply), добавляет облегчённые модели LOD1 и дым из тюндюков.
## Раскладку пересобирает tools/gen_camp.py scene.
##
## Метки для других областей (узел Markers):
##   SheepPen, HorsePen (CampArea: центр + size), BannerPos, CampCenter, OrdoDoor,
##   Fire_1..N, GuardPost_1..N, WorkSpot_1..N.

## С какого расстояния камеры модели сменяются облегчёнными (LOD1), м
@export var lod_distance := 140.0
## Дым из тюндюков
@export var tunduk_smoke := true
## Землю загонов рисуют декали (узел Ground); пятна «Ground» из glb загонов прячем,
## чтобы свет на них совпадал со светом земли мира
@export var decal_ground := true

## Высота дымового отверстия над основанием модели, м
const TUNDUK_HEIGHT := {"boz": 4.55, "ordo": 8.1}
const SMOKE := preload("res://scenes/camp/smoke.tscn")
## Контровой свет построек сильнее общего: белый войлок на закате должен светиться по краю
const RIM_STRENGTH := 1.7


func _ready() -> void:
	if Ordo.is_low():
		# телефоны (ТЗ 11.7): облегчённые модели раньше, меньше дыма
		lod_distance = minf(lod_distance, 80.0)
	for group in ["Buildings", "Props"]:
		for n in get_node(group).get_children():
			_snap(n as Node3D, float(n.get_meta("footprint", 0.0)))
			_setup_model(n as Node3D)
	for group in ["Fires", "Ground", "Markers"]:
		for n in get_node(group).get_children():
			_snap(n as Node3D, 0.0)
	_wind_smoke()


## Метка по имени: marker("BannerPos"), marker("Fire_1").
func marker(marker_name: String) -> Marker3D:
	return get_node_or_null("Markers/" + marker_name) as Marker3D


## Все метки с началом имени: markers("GuardPost_"), markers("WorkSpot_"), markers("Fire_").
func markers(prefix: String) -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	for n in get_node("Markers").get_children():
		if String(n.name).begins_with(prefix) and n is Marker3D:
			out.append(n)
	return out


func sheep_pen() -> CampArea:
	return marker("SheepPen") as CampArea


func horse_pen() -> CampArea:
	return marker("HorsePen") as CampArea


## Постройки лагеря (для поиска пути и выделения): узлы с метаданными footprint (радиус, м).
func buildings() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in get_node("Buildings").get_children():
		out.append(n)
	return out


# ---------------------------------------------------------------- внутреннее

func _snap(n: Node3D, footprint: float) -> void:
	# ставим на землю: при большом основании — по самой низкой точке, чтобы не висело
	var p := n.global_position
	var h := Terrain.height_at(p.x, p.z)
	if footprint > 0.0:
		for k in 4:
			var a := TAU * float(k) / 4.0 + 0.4
			h = minf(h, Terrain.height_at(p.x + cos(a) * footprint, p.z + sin(a) * footprint))
	n.global_position = Vector3(p.x, h, p.z)


func _setup_model(n: Node3D) -> void:
	var path := n.scene_file_path
	if not path.ends_with(".glb"):
		return
	var opts := {"rim_strength": RIM_STRENGTH}
	if n.has_meta("tint"):
		opts["albedo_tint"] = n.get_meta("tint")
	KipchakModels.apply(n, opts)
	if decal_ground:
		_hide_ground(n)
	var lod1_path := path.get_basename() + "_lod1.glb"
	if ResourceLoader.exists(lod1_path):
		_set_range(n, 0.0, lod_distance)
		var l1 := (load(lod1_path) as PackedScene).instantiate() as Node3D
		l1.name = "LOD1"
		n.add_child(l1)
		KipchakModels.apply(l1, opts)
		_set_range(l1, lod_distance, 0.0)
		if decal_ground:
			_hide_ground(l1)
	var kind := path.get_file().get_basename()
	if tunduk_smoke and TUNDUK_HEIGHT.has(kind):
		var s := SMOKE.instantiate() as GPUParticles3D
		s.name = "TundukSmoke"
		s.position = Vector3(0, TUNDUK_HEIGHT[kind], 0)
		s.amount = int((18.0 if kind == "boz" else 26.0) * (0.5 if Ordo.is_low() else 1.0))
		s.lifetime = 9.0
		s.preprocess = 9.0
		n.add_child(s)


func _hide_ground(root: Node) -> void:
	for c in root.get_children():
		if c is MeshInstance3D and String(c.name).begins_with("Ground"):
			(c as MeshInstance3D).visible = false


func _set_range(root: Node, begin: float, end: float) -> void:
	if root is GeometryInstance3D:
		var g := root as GeometryInstance3D
		g.visibility_range_begin = begin
		g.visibility_range_end = end
		g.visibility_range_begin_margin = 4.0 if begin > 0.0 else 0.0
		g.visibility_range_end_margin = 4.0 if end > 0.0 else 0.0
	for c in root.get_children():
		_set_range(c, begin, end)


func _wind_smoke() -> void:
	# дым сносит общий ветер (ordo_wind: xy — направление по x/z, z — сила); берём из настроек проекта
	var g: Variant = ProjectSettings.get_setting("shader_globals/ordo_wind", {})
	if not (g is Dictionary and (g as Dictionary).get("value") is Vector4):
		return
	var wind: Vector4 = (g as Dictionary)["value"]
	var dir := Vector2(wind.x, wind.y).normalized() * 0.4 * wind.z
	# материал частиц общий у всех экземпляров smoke.tscn — достаточно одного дыма
	for s in find_children("*Smoke", "GPUParticles3D", true, false):
		var pm := (s as GPUParticles3D).process_material as ParticleProcessMaterial
		if pm:
			pm.gravity = Vector3(dir.x, 0.1, dir.y)
