extends Node3D
## Нагрузочная проверка толпы: 500 сарбозов против 500 кыпчаков (сайыскеры и жоокеры), всё анимировано.
##
##   tools/shot.sh res://scenes/test/units_stress.tscn out.png --at=6 --cam=CamRTS
## Каждые 30 кадров печатает: время нашего обновления на процессоре (расчёт + set_instance),
## число вызовов отрисовки, треугольников, объектов и FPS.
## Хореография простая (не симуляция боя): сарбозы стоят и стреляют залпами, жоокеры бегут,
## сайыскеры разгоняются в атаку, у встречи — рукопашная, часть падает.

const H := AnimSpec.Human
const R := AnimSpec.Horse

var _layers := {}
var _units: Array = []   # {layer, i, kind, x, z, dir, speed, state, var, t0}
var _t := 0.0
var _frames := 0
var _acc_us := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	_world()
	_spawn("kok_sarboz", 500, Vector2(-34.0, 0.0), 25, 1.15, 1.25, 1.0)
	_spawn("kip_jooker", 250, Vector2(30.0, -8.0), 25, 1.2, 1.3, -1.0)
	_spawn("kip_sayisker", 250, Vector2(48.0, 6.0), 25, 2.2, 3.0, -1.0)
	_spawn("kok_sarboz_banner", 4, Vector2(-36.5, 0.0), 4, 6.0, 1.0, 1.0)
	_spawn("kip_sayisker_banner", 3, Vector2(52.0, 6.0), 3, 8.0, 1.0, -1.0)
	_spawn("kip_kolbashchy", 1, Vector2(60.0, 0.0), 1, 1.0, 1.0, -1.0)
	_spawn("kok_yuzboshi", 2, Vector2(-44.0, 0.0), 2, 12.0, 1.0, 1.0)
	for id in _layers:
		var n := 0
		for u in _units:
			if u["unit"] == id:
				n += 1
		(_layers[id] as CrowdLayer).set_visible_count(n)
	print("[stress] юнитов: ", _units.size(), " слоёв: ", _layers.size())


func _spawn(unit: String, n: int, origin: Vector2, cols: int, dx: float, dz: float, facing: float) -> void:
	var layer := CrowdLayer.new()
	layer.name = unit
	add_child(layer)
	layer.setup(unit, n)
	_layers[unit] = layer
	for i in n:
		var c := i % cols
		var r := i / cols
		_units.append({"unit": unit, "layer": layer, "i": i,
			"x": origin.x - facing * r * dz + _rng.randf_range(-0.12, 0.12),
			"z": origin.y + (c - cols * 0.5) * dx + _rng.randf_range(-0.12, 0.12),
			"dir": facing, "var": _rng.randf(), "dist": _rng.randf() * 3.0, "die": _rng.randf()})


func _process(delta: float) -> void:
	_t += delta
	var t0 := Time.get_ticks_usec()
	for u in _units:
		_step(u, delta)
	var us := float(Time.get_ticks_usec() - t0)
	_acc_us += us
	_frames += 1
	if _frames % 30 == 0:
		var rs := RenderingServer
		print("[stress] t=%.1f с  обновление %.2f мс/кадр (1000+ юнитов)  вызовов отрисовки %d  треугольников %d  объектов %d  FPS %.1f" % [
			_t, _acc_us / 30000.0,
			rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			Engine.get_frames_per_second()])
		_acc_us = 0.0


func _step(u: Dictionary, dt: float) -> void:
	var unit: String = u["unit"]
	var dir: float = u["dir"]
	var x: float = u["x"]
	var state := 0
	var phase := 0.0
	var aux := 1.0
	var speed := 0.0
	var var_w: float = u["var"]
	var t := _t + var_w * 0.4
	if unit.begins_with("kok_sarboz"):
		# залп каждые 4 с, потом перезарядка
		var cyc := fposmod(t, 12.4)
		if unit.ends_with("banner"):
			state = H.CHEER
			phase = fposmod(t / 2.0, 1.0)
		elif cyc < 1.4:
			state = H.SHOOT
			phase = cyc / 1.4
		elif cyc < 12.4:
			state = H.RELOAD
			phase = (cyc - 1.4) / 11.0
		if u["die"] < 0.08 and _t > 4.0 + u["die"] * 40.0:
			var k: float = (_t - 4.0 - u["die"] * 40.0) / 1.3
			state = H.DYING if k < 1.0 else H.DEAD
			phase = minf(k, 1.0)
			aux = float(u["i"] % 2)
	elif unit == "kip_jooker":
		speed = 3.4 if x > -20.0 else 0.0
		if speed > 0.0:
			state = H.RUN
		else:
			state = H.MELEE
			phase = fposmod(t / 0.9, 1.0)
	elif unit == "kok_yuzboshi":
		state = R.IDLE
		phase = fposmod(t / AnimSpec.IDLE_PERIOD, 1.0)
	else:
		# всадники: шаг → галоп → атака → рукопашная у строя
		speed = 1.8 if _t < 2.0 else (8.0 if _t < 4.0 else 9.5)
		if x < -24.0:
			speed = 0.0
		if speed == 0.0:
			state = R.MELEE
			phase = fposmod(t / 0.9, 1.0)
		elif speed < 2.5:
			state = R.WALK
		elif speed < 9.0:
			state = R.GALLOP
		else:
			state = R.CHARGE if not unit.ends_with("banner") else R.GALLOP
		if u["die"] < 0.1 and x < -18.0:
			state = R.DEAD
			phase = 1.0
			aux = float(u["i"] % 2)
			speed = 0.0
	if speed > 0.0:
		x += dir * speed * dt
		u["x"] = x
		u["dist"] = u["dist"] + speed * dt
		phase = fposmod(u["dist"] / CrowdAnim.stride_for(unit, state), 1.0)
	var basis := Basis(Vector3.UP, atan2(dir, 0.0))
	var xf := Transform3D(basis, Vector3(x, Terrain.height_at(x, u["z"]), u["z"]))
	(u["layer"] as CrowdLayer).set_instance(u["i"], xf, AnimSpec.custom(state, phase, aux, var_w))


func _world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.06, 0.1, 0.22)
	psm.sky_horizon_color = Color(0.85, 0.5, 0.3)
	psm.ground_horizon_color = Color(0.3, 0.25, 0.2)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.26, 0.4, 0.55)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.fog_enabled = true
	env.fog_light_color = Color(0.42, 0.42, 0.5)
	env.fog_density = 0.004
	env.fog_aerial_perspective = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.64, 0.38)
	sun.light_energy = 2.6
	sun.rotation_degrees = Vector3(-9.0, -67.5, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(800, 800)
	ground.mesh = pm
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://shaders/painterly_surface.gdshader")
	gm.set_shader_parameter("albedo_tint", Color(0.17, 0.18, 0.12))
	ground.material_override = gm
	add_child(ground)
	var cam := Camera3D.new()
	cam.name = "CamRTS"
	cam.far = 800.0
	cam.fov = 45.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 62.0, 62.0), Vector3(0.0, 0.0, 0.0))
	cam.make_current()
	var cam2 := Camera3D.new()
	cam2.name = "CamLow"
	cam2.fov = 50.0
	cam2.far = 800.0
	add_child(cam2)
	cam2.look_at_from_position(Vector3(-10.0, 14.0, 40.0), Vector3(-10.0, 0.0, 0.0))
	var cam3 := Camera3D.new()
	cam3.name = "CamSarboz"
	cam3.fov = 50.0
	add_child(cam3)
	cam3.look_at_from_position(Vector3(-36.0, 4.0, 22.0), Vector3(-44.0, 1.0, 10.0))
