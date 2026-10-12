extends Node3D
## Проверка вида лагеря кыпчаков: временный свет заката (мир потом даст свой),
## рисованная земля и камеры для кадров.
##   tools/shot.sh res://scenes/test/camp_look.tscn out.png --cam=CamYurtClose --at=3
## Камеры: CamYurtClose, CamKhan, CamCampWide, CamCampLow, CamFar — проверка LOD1 (режим "camp"),
##         CamLineup, CamBoz, CamOrdo, CamProps (режим "models").

## "camp" — весь лагерь (scenes/camp/camp.tscn); "models" — модели в ряд
@export_enum("camp", "models") var mode := "camp"

const CAMP := "res://scenes/camp/camp.tscn"
const MODELS := "res://assets/models/kipchak/"


func _ready() -> void:
	_environment()
	_sun()
	_ground()
	if mode == "models":
		_lineup()
	else:
		add_child((load(CAMP) as PackedScene).instantiate())
		_camp_cameras()


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://scenes/test/camp_sky.gdshader")
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.33, 0.45, 0.64)
	env.ambient_light_energy = 0.34
	# без отражений неба: войлок и дерево матовые (иначе на куполе «пластиковый» блеск)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	if Ordo.has_arg("sky_reflect"):  # проверка: как войлок выглядит с отражениями неба
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.36, 0.36, 0.46)
	env.fog_density = 0.0024
	env.fog_sun_scatter = 0.35
	env.fog_aerial_perspective = 0.0
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.04
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	add_child(we)


func _sun() -> void:
	# солнце с запада-юго-запада, ~10° над горизонтом (CONTRACT §3)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.77, 0.55)
	sun.light_energy = 2.8
	sun.rotation_degrees = Vector3(-10, -67.5, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 260.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)


func _ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	ground.mesh = pm
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://scenes/test/camp_ground.gdshader")
	ground.material_override = gm
	ground.position = Vector3(-60, 0, 20)
	add_child(ground)


func _model(file: String, pos: Vector3, yaw := 0.0) -> Node3D:
	var n := (load(MODELS + file + ".glb") as PackedScene).instantiate() as Node3D
	KipchakModels.apply(n)
	n.position = pos
	n.rotation_degrees.y = yaw
	add_child(n)
	return n


func _cam(cam_name: String, pos: Vector3, target: Vector3, fov := 40.0) -> Camera3D:
	var c := Camera3D.new()
	c.name = cam_name
	c.fov = fov
	c.far = 1500.0
	add_child(c)
	c.position = pos
	c.look_at(target)
	return c


func _lineup() -> void:
	# модели в ряд вдоль X, двери на юго-восток (к камере)
	var items := [["ordo", Vector3(-18, 0, 0)], ["boz", Vector3(0, 0, 0)], ["boz_lod1", Vector3(9, 0, 0)],
		["ordo_lod1", Vector3(26, 0, 0)]]
	for it in items:
		if ResourceLoader.exists(MODELS + it[0] + ".glb"):
			_model(it[0], it[1], 35.0)
	var props := ["tug", "arba", "campfire", "kazan", "woodpile", "felt_rolls", "hay", "saddle_rack"]
	var x := -14.0
	for p in props:
		if ResourceLoader.exists(MODELS + p + ".glb"):
			_model(p, Vector3(x, 0, 14), 20.0)
		x += 5.0
	_cam("CamLineup", Vector3(4, 14, 40), Vector3(4, 2, 4), 45.0)
	_cam("CamBoz", Vector3(6.5, 2.4, 9.0), Vector3(0.3, 2.3, 0), 40.0).make_current()
	_cam("CamOrdo", Vector3(-6, 5, 18), Vector3(-17, 3.5, 0), 45.0)
	_cam("CamProps", Vector3(6, 6, 30), Vector3(6, 0.8, 14), 40.0)
	for it in [["koroo", Vector3(-12, 0, -26)], ["jylky", Vector3(12, 0, -26)]]:
		if ResourceLoader.exists(MODELS + it[0] + ".glb"):
			_model(it[0], it[1], 0.0)
	_cam("CamPens", Vector3(0, 16, 2), Vector3(0, 0, -24), 50.0)
	_cam("CamArba", Vector3(-6.5, 3.2, 21), Vector3(-9, 1.0, 14), 45.0)
	_cam("CamTug", Vector3(-11, 6.5, 22), Vector3(-14, 6.0, 14), 45.0)


func _camp_cameras() -> void:
	var c := Vector3(-60, 0, 20)
	var camp := get_node("Camp")
	_cam("CamCampWide", c + Vector3(20, 74, 70), c + Vector3(-3, 0, 14), 46.0).make_current()
	# крупно одна боз үй: дверь, орнамент, сетка верёвок; камера с юго-запада от двери
	var boz := camp.get_node("Buildings/Boz_2") as Node3D
	var d := Vector3(sin(boz.rotation.y), 0, cos(boz.rotation.y))
	var eye := boz.position + d.rotated(Vector3.UP, deg_to_rad(-30.0)) * 13.0 + Vector3(0, 1.5, 0)
	_cam("CamYurtClose", eye, boz.position + d * 2.2 + Vector3(0, 2.1, 0), 44.0)
	# ханская юрта со щитами и туг с вымпелом
	var ordo := camp.get_node("Buildings/Ordo") as Node3D
	var od := Vector3(sin(ordo.rotation.y), 0, cos(ordo.rotation.y))
	var oe := ordo.position + od.rotated(Vector3.UP, deg_to_rad(-12.0)) * 26.0 + Vector3(0, 4.5, 0)
	_cam("CamKhan", oe, ordo.position + od * 4.0 + Vector3(0, 4.0, 0), 42.0)
	# дальняя проверка LOD1 (дальше lod_distance)
	_cam("CamFar", c + Vector3(150, 120, 170), c + Vector3(0, 0, 20), 30.0)
	# низкая кинокамера против солнца: силуэты на закате, дым
	_cam("CamCampLow", c + Vector3(25.4, 1.3, -5.6), c + Vector3(0, 6.4, 1.5), 52.0)
