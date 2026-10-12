extends Node3D
## Сквозная проверка конвейера: glb → Painterly → свет заката → кадр.

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.12, 0.2, 0.35)
	psm.sky_horizon_color = Color(0.95, 0.6, 0.35)
	psm.ground_horizon_color = Color(0.5, 0.4, 0.3)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.45, 0.6)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.7, 0.45)
	sun.light_energy = 2.2
	sun.rotation_degrees = Vector3(-12, -60, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://shaders/painterly_surface.gdshader")
	gm.set_shader_parameter("albedo_tint", Color(0.45, 0.4, 0.28))
	ground.material_override = gm
	add_child(ground)
	var yurt := (load("res://assets/models/test/smoke_yurt.glb") as PackedScene).instantiate()
	Painterly.apply(yurt)
	add_child(yurt)
	var cam := Camera3D.new()
	cam.position = Vector3(9, 4, 9)
	add_child(cam)
	cam.look_at(Vector3(0, 1.5, 0))
	cam.make_current()
