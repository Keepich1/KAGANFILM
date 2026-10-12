class_name BattleStandInRig
extends Node3D
## Временная «сцена заката» для тестов боя: небо, низкое солнце с запада-юго-запада
## (8–12°, тёплый ключ), холодное сине-бирюзовое окружение, AgX, лёгкая дымка, земля.
## Если в сцене уже есть свет и окружение мира — ничего не добавляет (кроме того, чего нет).

## Высота солнца, градусы (CONTRACT §3: 8–12°)
@export var sun_elevation := 10.0
## Азимут солнца от севера по часовой, градусы (запад-юго-запад ≈ 247.5°)
@export var sun_azimuth := 247.5
@export var ground := true
@export var ground_size := 1400.0


func _ready() -> void:
	var root := get_tree().current_scene if get_tree().current_scene else get_parent()
	if root.find_children("*", "WorldEnvironment", true, false).is_empty():
		add_child(_environment())
	if root.find_children("*", "DirectionalLight3D", true, false).is_empty():
		add_child(_sun())
	if ground:
		add_child(_ground())


## Направление на солнце (единичный вектор из точки к солнцу)
static func sun_direction(elevation: float, azimuth: float) -> Vector3:
	var el := deg_to_rad(elevation)
	var az := deg_to_rad(azimuth)
	# север −Z, восток +X
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()


func _sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.74, 0.52)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 260.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_blur = 1.5
	sun.light_angular_distance = 1.2
	var d := sun_direction(sun_elevation, sun_azimuth)
	sun.basis = Basis.looking_at(-d, Vector3.UP)
	return sun


func _environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.07, 0.13, 0.24)
	psm.sky_horizon_color = Color(0.86, 0.56, 0.4)
	psm.sky_curve = 0.12
	psm.ground_bottom_color = Color(0.12, 0.11, 0.12)
	psm.ground_horizon_color = Color(0.6, 0.42, 0.32)
	psm.sun_angle_max = 18.0
	psm.sun_curve = 0.08
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.44, 0.62)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.4, 0.46, 0.58)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.3
	env.fog_density = 0.0032
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.3
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.06
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.name = "StandInEnvironment"
	we.environment = env
	return we


func _ground() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "StandInGround"
	var pm := PlaneMesh.new()
	pm.size = Vector2(ground_size, ground_size)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/fx/stand_in_ground.gdshader")
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
