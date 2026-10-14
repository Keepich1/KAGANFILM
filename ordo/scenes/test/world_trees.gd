extends Node3D
## Проверочная сцена деревьев мира (scenes/test/world_trees.tscn): настоящий мир (земля, небо,
## солнце заката, туман, живописный фильтр) и ряд из четырёх видов на краю луга — арча, ива (тал),
## карагач, тополь (терек). Деревья ряда собраны так же, как в WorldScatter: MultiMesh + материал
## вида (берётся у самого WorldScatter, поэтому вид в точности как в срезе).
##
## Один кадр:      tools/shot.sh res://scenes/test/world_trees.tscn out.png --at=3 --cam=CamLineup --size=1280x720
## Серия кадров:   tools/shot.sh res://scenes/test/world_trees.tscn last.png --at=999 --size=1280x720 \
##                   --series=CamLineup,CamBacklit,CamClose --series_out=/abs/dir [--series_at=2.5] [--series_prefix=p_]
## --trees_lod=1 — в ряду только облегчённые модели (сравнить LOD0 и LOD1 с одной точки).
## --nograss / --nofog / --nopost — как в мире.
## --studio — облегчённый мир для быстрых проверок на слабой машине: без земли, воды, травы,
##            тумана-пятен и деревьев мира; под рядом — простой кусок земли по высотам мира.
## --settle=N — сколько кадров ждать после смены камеры (по умолчанию 8).

const KINDS := ["juniper", "willow", "elm", "poplar"]
## Ряд: x, z (у южного края луга, за ним — река с рощами тополей и ив)
const ROW := {
	"juniper": Vector2(22.0, -24.0),
	"willow": Vector2(36.0, -26.0),
	"elm": Vector2(54.0, -24.0),
	"poplar": Vector2(70.0, -25.0),
}
## Второй ряд — дальше от камеры (проверка LOD1 и средних дистанций)
const ROW_FAR := {
	"juniper": Vector2(30.0, -64.0),
	"willow": Vector2(44.0, -70.0),
	"elm": Vector2(60.0, -66.0),
	"poplar": Vector2(76.0, -64.0),
}
## Сколько кадров ждать после смены камеры (объёмный туман и фильтр устаиваются)
const SETTLE_FRAMES := 8

var _ordo: Node
var _series: PackedStringArray = []
var _series_out := ""
var _series_prefix := ""
var _series_at := 2.5
var _busy := false


func _ready() -> void:
	_ordo = get_node_or_null("/root/Ordo")
	_place_cameras()
	if _ordo and _ordo.has_arg("series"):
		_series = String(_ordo.arg("series")).split(",", false)
		_series_out = String(_ordo.arg("series_out", ProjectSettings.globalize_path("res://renders/trees")))
		_series_prefix = String(_ordo.arg("series_prefix", ""))
		_series_at = float(_ordo.arg("series_at", "2.5"))
		DirAccess.make_dir_recursive_absolute(_series_out)
	# деревья ряда — после того как WorldScatter построил свои материалы
	await get_tree().process_frame
	if _ordo and _ordo.has_arg("studio"):
		_studio()
	_build_rows()
	print("[деревья] сцена готова, %d мс" % Time.get_ticks_msec())


func _process(_delta: float) -> void:
	if _series.is_empty() or _busy or _ordo == null:
		return
	if float(_ordo.get("scene_time")) >= _series_at:
		_busy = true
		_shoot_series()


func _shoot_series() -> void:
	var last: Image = null
	for cam_name in _series:
		var cam := find_child(cam_name, true, false) as Camera3D
		if cam == null:
			push_warning("world_trees: нет камеры %s" % cam_name)
			continue
		cam.make_current()
		for i in int(_ordo.arg("settle", str(SETTLE_FRAMES))):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		last = get_viewport().get_texture().get_image()
		var path := "%s/%s%s.png" % [_series_out, _series_prefix, cam_name]
		last.save_png(path)
		print("[деревья] кадр: %s, %d мс" % [path, Time.get_ticks_msec()])
	if last and _ordo.has_arg("shot"):
		last.save_png(ProjectSettings.globalize_path(String(_ordo.arg("shot"))))
	get_tree().quit()


# ---------------------------------------------------------------- камеры

func _g(x: float, z: float, up: float) -> Vector3:
	return Vector3(x, Terrain.height_at(x, z) + up, z)


func _cam(cam_name: String, from: Vector3, to: Vector3, fov: float) -> void:
	var cam := get_node_or_null(cam_name) as Camera3D
	if cam == null:
		cam = Camera3D.new()
		cam.name = cam_name
		add_child(cam)
	cam.position = from
	cam.look_at(to, Vector3.UP)
	cam.fov = fov
	cam.near = 0.25
	cam.far = 6000.0


func _place_cameras() -> void:
	# ряд сбоку-спереди: солнце слева (запад-юго-запад), за рядом — река с рощами
	_cam("CamLineup", _g(46.0, 12.0, 4.5), _g(46.0, -30.0, 7.0), 50.0)
	# против солнца: контровой свет по краям крон
	_cam("CamBacklit", _g(92.0, -46.0, 3.0), _g(30.0, -22.0, 8.0), 48.0)
	# крупно: крона карагача и ива рядом (мазки, края гроздей, ветви)
	_cam("CamClose", _g(50.0, -10.0, 5.0), _g(52.0, -24.0, 8.5), 46.0)
	# крупно тополь: колонна кроны, кора, свет с запада
	_cam("CamPoplar", _g(62.0, -8.0, 3.0), _g(70.0, -25.0, 10.5), 52.0)
	# крупно ива: каскады прядей, «колокол», просветы к стволу
	_cam("CamWillow", _g(30.0, -11.0, 3.0), _g(37.5, -26.0, 4.5), 50.0)
	# крупно арча: кривой ствол, комки хвои
	_cam("CamJuniper", _g(17.0, -16.0, 2.5), _g(22.5, -24.0, 3.2), 50.0)
	# сверху, как камера стратегии (~50° вниз)
	_cam("CamTop", _g(48.0, 0.0, 62.0), _g(48.0, -46.0, 0.0), 42.0)
	# рощи у реки из самого мира (тополя и ивы у воды)
	_cam("CamRiver", _g(22.0, -100.0, 7.0), _g(55.0, -140.0, 5.0), 50.0)
	# арча на склоне у восточных холмов
	_cam("CamSlope", _g(300.0, 8.0, 10.0), _g(342.0, 18.0, 12.0), 48.0)


# ---------------------------------------------------------------- ряд деревьев

func _scatter_material(kind: String) -> Material:
	var scatter := find_child("Scatter", true, false)
	if scatter == null:
		return null
	for c in scatter.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with(kind + "_"):
			return (c as MultiMeshInstance3D).material_override
	return null


func _mesh_of(path: String) -> Mesh:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var root := ps.instantiate()
	var mesh: Mesh = null
	for n in root.find_children("*", "MeshInstance3D", true, false):
		mesh = (n as MeshInstance3D).mesh
		break
	if mesh == null and root is MeshInstance3D:
		mesh = (root as MeshInstance3D).mesh
	root.free()
	return mesh


func _build_rows() -> void:
	var force_lod := int(_ordo.arg("trees_lod", "-1")) if _ordo else -1
	var root := Node3D.new()
	root.name = "TreeRows"
	add_child(root)
	for kind: String in KINDS:
		var mat := _scatter_material(kind)
		if mat == null:
			push_warning("world_trees: нет материала %s у WorldScatter" % kind)
			continue
		var lod0 := _mesh_of("res://assets/models/world/%s.glb" % kind)
		var lod1 := _mesh_of("res://assets/models/world/%s_lod1.glb" % kind)
		for row in [ROW, ROW_FAR]:
			var p: Vector2 = row[kind]
			var lod := 0 if row == ROW else 1
			if force_lod >= 0:
				lod = force_lod
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = lod0 if lod == 0 else lod1
			mm.instance_count = 1
			var rot := 0.6 if kind != "willow" else PI * 0.5      # ива клонится к реке (на север)
			var s := 1.0
			var b := Basis(Vector3.UP, rot).scaled(Vector3(s, s, s))
			mm.set_instance_transform(0, Transform3D(b, Vector3(p.x, Terrain.height_at(p.x, p.y) - 0.15, p.y)))
			mm.set_instance_custom_data(0, Color(0.5, 0.5, 0.5, 1.0))
			var mi := MultiMeshInstance3D.new()
			mi.name = "%s_row_L%d_%d" % [kind, lod, int(p.y)]
			mi.multimesh = mm
			mi.material_override = mat
			root.add_child(mi)


# ---------------------------------------------------------------- облегчённый мир

## Прячет тяжёлые части мира и кладёт под ряд кусок земли по высотам мира (шаг 2 м).
func _studio() -> void:
	var world := find_child("World", false, false)
	if world:
		for part in ["Terrain", "Water", "Grass", "FogBanks", "Scatter"]:
			var n := world.get_node_or_null(part) as Node3D
			if n:
				n.visible = false
				n.process_mode = Node.PROCESS_MODE_DISABLED
	var x0 := -40.0
	var z0 := -140.0
	var step := 2.0
	var nx := 100
	var nz := 90
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in nz:
		for i in nx:
			var q: Array[Vector3] = []
			for d: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var x := x0 + (i + d.x) * step
				var z := z0 + (j + d.y) * step
				q.append(Vector3(x, Terrain.height_at(x, z), z))
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(q[k].x, q[k].z) / 12.0)
				st.add_vertex(q[k])
	var mi := MeshInstance3D.new()
	mi.name = "StudioGround"
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/painterly_surface.gdshader")
	mat.set_shader_parameter("albedo_tex", load("res://assets/textures/world/ground_grass.png"))
	mat.set_shader_parameter("albedo_tint", Color(0.62, 0.62, 0.5))
	mat.set_shader_parameter("rim_strength", 0.0)
	mi.material_override = mat
	add_child(mi)
