extends Node3D
## Проверка анимаций толпы: все виды юнитов в разных состояниях под временным закатным светом.
##
##   tools/shot.sh res://scenes/test/units_anim.tscn out.png --at=2 --cam=CamLineup
## Камеры: CamLineup (обзор 3/4), CamClose (крупно всадник и сарбоз), CamTop (RTS ~80 м),
## CamGait (дорожки с движением — проверка скольжения ног), CamRiders, CamInfantry, CamSide.
## Свет и земля здесь — временные, только для проверки юнитов (настоящие — у области «Мир»).
##
## Для быстрых проверок (без tools/shot.sh, через tools/godot.sh):
##   --t0=5.0                  сдвиг времени анимации (не нужно ждать кадры)
##   --only=infantry,riders    только группы: infantry, riders, close, lanes, formation
##   --multi=CamA@0.1,CamB@0.2 --outdir=/абс/путь --tag=x   несколько кадров за один запуск

const H := AnimSpec.Human
const R := AnimSpec.Horse
const SH := AnimSpec.Sheep

var _layers := {}            # unit_id → CrowdLayer
var _entries: Array = []     # {unit, skel, i, state, pos, yaw, speed, lane, var, off, aux}
var _t := 0.0
var _clock := 0.0
var _groups := PackedStringArray()
var _shots: Array = []       # [{cam, at, path}]
var _busy := false


func _ready() -> void:
	_t = float(_arg("t0", "0"))
	var only := _arg("only", "")
	if only != "":
		_groups = only.split(",")
	_build_world()
	_build_lineup()
	for id in _layers:
		var n := 0
		for e in _entries:
			if e["unit"] == id:
				n += 1
		(_layers[id] as CrowdLayer).set_visible_count(n)
	_update(_t)
	var multi := _arg("multi", "")
	if multi != "":
		var outdir := _arg("outdir", "user://")
		var tag := _arg("tag", "f")
		var k := 0
		for s in multi.split(","):
			var p := s.split("@")
			_shots.append({"cam": p[0], "at": float(p[1]), "path": "%s/%s_%02d_%s.png" % [outdir, tag, k, p[0]]})
			k += 1


func _process(delta: float) -> void:
	_t += delta
	_clock += delta
	_update(_t)
	if not _shots.is_empty() and not _busy:
		var s: Dictionary = _shots[0]
		var cam := find_child(s["cam"], true, false) as Camera3D
		if cam and not cam.current:
			cam.make_current()
		if _clock >= s["at"]:
			_busy = true
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png(ProjectSettings.globalize_path(s["path"]))
			print("[units] кадр ", s["path"], " t=", snappedf(_t, 0.001))
			_shots.pop_front()
			_busy = false
			if _shots.is_empty():
				get_tree().quit()


func _arg(n: String, def: String) -> String:
	var ordo := get_node_or_null("/root/Ordo")
	return ordo.arg(n, def) if ordo else def


func _on(group: String) -> bool:
	return _groups.is_empty() or group in _groups


# ---------------------------------------------------------------- расстановка

func _add(unit: String, state: int, pos: Vector3, yaw_deg := 0.0, speed := 0.0, lane := Vector2.ZERO,
		aux := 0.0) -> void:
	if not _layers.has(unit):
		var l := CrowdLayer.new()
		l.name = unit
		add_child(l)
		l.setup(unit, 64)
		if _arg("lod", "") != "":
			l.lod_distance = float(_arg("lod", "90"))  # проверка LOD1: --lod=0.5
		_layers[unit] = l
	var i := 0
	for e in _entries:
		if e["unit"] == unit:
			i += 1
	var skel: String = UnitRegistry.info(unit)["skeleton"]
	_entries.append({"unit": unit, "skel": skel, "i": i, "state": state, "pos": pos, "yaw": deg_to_rad(yaw_deg),
		"speed": speed, "lane": lane, "var": fposmod(0.137 + _entries.size() * 0.618034, 1.0),
		"off": fposmod(_entries.size() * 0.37, 1.0), "aux": aux})


func _build_lineup() -> void:
	# листы поз: --sheet=юнит,состояние[,поворот][,доп];юнит,... — по 10 фаз в ряд (камеры CamSheet0, 1…)
	var sheet := _arg("sheet", "")
	if sheet != "":
		var vp := get_viewport().get_visible_rect().size
		var aspect := vp.x / maxf(vp.y, 1.0)
		var row := 0
		for one in sheet.split(";"):
			var a := one.split(",")
			var unit := a[0]
			var st := int(a[1])
			var yaw := float(a[2]) if a.size() > 2 else 0.0
			var aux := float(a[3]) if a.size() > 3 else 0.0
			var skel: String = UnitRegistry.info(unit)["skeleton"]
			var big := skel == "rider" or skel == "horse"
			var step := 3.0 if big else 1.3
			var z := -row * 20.0
			for k in 10:
				_add(unit, st, Vector3((k - 4.5) * step, 0, z), yaw, 0.0, Vector2.ZERO, aux)
				_entries[-1]["sheet_phase"] = k / 9.0
			var span := step * 10.2
			var h := 2.0 if big else 1.05
			var dist := span / (2.0 * tan(deg_to_rad(16.0)) * aspect)
			_cam("CamSheet%d" % row, Vector3(0, h + dist * 0.18, z + dist), Vector3(0, h * 0.8, z), 32.0)
			row += 1
		return
	if _on("infantry"):
		# сарбоз во всех разовых состояниях
		var x := -8.4
		for st in [H.IDLE, H.SHOOT, H.RELOAD, H.MELEE, H.BRACE, H.CHEER, H.DYING, H.DEAD]:
			_add("kok_sarboz", st, Vector3(x, 0, 2.2), 0.0, 0.0, Vector2.ZERO, float(int(x) % 2))
			x += 1.5
		x = -8.4
		for st in [H.IDLE, H.MELEE, H.BRACE, H.CHEER, H.DYING]:
			_add("kip_jooker", st, Vector3(x, 0, 0.4), 0.0, 0.0, Vector2.ZERO, 1.0)
			x += 1.5
		for a in [0.0, 0.25, 0.5]:
			_add("kip_malchy", H.WORK, Vector3(x, 0, 0.4), 0.0, 0.0, Vector2.ZERO, a)
			x += 1.5
		x = -8.4
		for st in [H.IDLE, H.CHEER, H.MELEE]:
			_add("kok_sarboz_banner", st, Vector3(x, 0, -1.6), 0.0)
			x += 1.6
		_add("kip_malchy", H.IDLE, Vector3(x, 0, -1.6), 0.0)
		x += 1.5
		for st in [SH.GRAZE, SH.GRAZE, SH.GRAZE, SH.DYING, SH.DEAD]:
			_add("sheep", st, Vector3(x, 0, -1.6), 70.0)
			x += 1.2
	if _on("riders"):
		var x := -9.0
		for st in [R.IDLE, R.MELEE, R.REAR, R.CHEER, R.DYING, R.DEAD]:
			_add("kip_sayisker", st, Vector3(x, 0, -5.0), 0.0)
			x += 3.0
		x = -9.0
		_add("kip_kolbashchy", R.IDLE, Vector3(x, 0, -9.0), 0.0)
		_add("kip_sayisker_banner", R.IDLE, Vector3(x + 3.0, 0, -9.0), 0.0)
		_add("kok_yuzboshi", R.IDLE, Vector3(x + 6.0, 0, -9.0), 0.0)
		_add("kok_yuzboshi", R.MELEE, Vector3(x + 9.0, 0, -9.0), 0.0)
		_add("horse", R.IDLE, Vector3(x + 12.0, 0, -9.0), 30.0)
		_add("horse", R.IDLE, Vector3(x + 14.5, 0, -10.0), -40.0)
	if _on("close"):
		_add("kip_sayisker", R.IDLE, Vector3(-6.2, 0, 7.6), 118.0)
		_add("kok_sarboz", H.IDLE, Vector3(-2.5, 0, 10.4), 62.0)
		_add("kip_jooker", H.IDLE, Vector3(-6.6, 0, 11.6), 75.0)
	if _on("lanes"):
		# дорожки с движением (вдоль +X, по кругу): проверка шага без скольжения
		var lanes := [
			["kok_sarboz", H.WALK, 5.0, 1.6], ["kok_sarboz", H.RUN, 4.0, 3.4], ["kip_jooker", H.FLEE, 3.0, 3.6],
			["kip_malchy", H.WORK, 2.0, 1.4], ["kok_sarboz_banner", H.WALK, 1.0, 1.6], ["sheep", SH.WALK, -0.3, 0.7],
			["sheep", SH.RUN, -1.2, 2.4], ["kip_sayisker", R.WALK, -3.0, 1.8], ["kok_yuzboshi", R.TROT, -5.5, 4.0],
			["kip_sayisker", R.GALLOP, -8.0, 9.0], ["kip_kolbashchy", R.CHARGE, -10.5, 9.5],
			["kip_sayisker_banner", R.GALLOP, -13.0, 8.5], ["horse", R.TROT, -15.5, 4.0], ["kip_jooker", H.RUN, 6.0, 3.4],
		]
		for ln in lanes:
			var aux := 0.75 if ln[0] == "kip_malchy" else 1.0
			_add(ln[0], ln[1], Vector3(14.0, 0, ln[2]), 90.0, ln[3], Vector2(14.0, 40.0), aux)
	if _on("formation"):
		# строй для проверки читаемости сверху
		for r in 6:
			for c in 8:
				_add("kok_sarboz", H.IDLE if (r + c) % 3 else H.SHOOT, Vector3(-34.0 + c * 1.1, 0, -6.0 + r * 1.3), 90.0)
		for r in 3:
			for c in 5:
				_add("kip_sayisker", R.IDLE, Vector3(-16.0 + r * 3.0, 0, -7.0 + c * 2.2), -90.0)
		for r in 3:
			for c in 6:
				_add("kip_jooker", H.IDLE, Vector3(-20.5 + r * 1.2, 0, 5.0 + c * 1.2), -90.0)


func _update(t: float) -> void:
	for e in _entries:
		var layer: CrowdLayer = _layers[e["unit"]]
		var st: int = e["state"]
		var skel: String = e["skel"]
		var pos: Vector3 = e["pos"]
		var phase := 0.0
		var aux: float = e["aux"]
		var spd: float = e["speed"]
		if spd > 0.0:
			var lane: Vector2 = e["lane"]
			var dist: float = spd * t + e["off"] * 7.0
			pos.x = lane.x + fposmod(dist, lane.y - lane.x)
			phase = fposmod(dist / _stride(skel, st), 1.0)
		elif e.has("sheet_phase"):
			phase = e["sheet_phase"]
		else:
			phase = _phase(skel, st, t + e["off"] * 3.0)
		var xf := Transform3D(Basis(Vector3.UP, e["yaw"]), pos)
		layer.set_instance(e["i"], xf, AnimSpec.custom(st, phase, aux, e["var"]))


func _stride(skel: String, st: int) -> float:
	match skel:
		"human":
			if st == H.WORK:
				return AnimSpec.STRIDE_HUMAN[H.WALK]
			return AnimSpec.STRIDE_HUMAN.get(st, 1.5)
		"sheep":
			return AnimSpec.STRIDE_SHEEP.get(st, 0.7)
		_:
			return AnimSpec.STRIDE_HORSE.get(st, 1.9)


func _phase(skel: String, st: int, t: float) -> float:
	var dur := 0.0
	match skel:
		"human":
			if st == H.IDLE:
				return fposmod(t / AnimSpec.IDLE_PERIOD, 1.0)
			if st == H.WORK:
				return fposmod(t / 1.3, 1.0)
			if st == H.DEAD:
				return 1.0
			dur = AnimSpec.DURATION_HUMAN.get(st, 1.0)
		"sheep":
			if st == SH.GRAZE:
				return fposmod(t / AnimSpec.IDLE_PERIOD, 1.0)
			if st == SH.DEAD:
				return 1.0
			dur = AnimSpec.DURATION_SHEEP.get(st, 1.0)
		_:
			if st == R.IDLE:
				return fposmod(t / AnimSpec.IDLE_PERIOD, 1.0)
			if st == R.DEAD:
				return 1.0
			dur = AnimSpec.DURATION_HORSE.get(st, 1.0)
	# разовое состояние: проигрывается и держится 0.8 с в конце, потом снова
	return clampf(fposmod(t, dur + 0.8) / dur, 0.0, 1.0)


# ---------------------------------------------------------------- временный мир

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.06, 0.1, 0.22)
	psm.sky_horizon_color = Color(0.88, 0.5, 0.3)
	psm.sky_curve = 0.12
	psm.ground_horizon_color = Color(0.35, 0.27, 0.22)
	psm.ground_bottom_color = Color(0.12, 0.1, 0.1)
	psm.sun_angle_max = 8.0
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.26, 0.4, 0.55)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.42, 0.42, 0.5)
	env.fog_density = 0.0025
	env.fog_sun_scatter = 0.35
	env.fog_aerial_perspective = 0.4
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.64, 0.38)
	sun.light_energy = 2.6
	sun.rotation_degrees = Vector3(-9.0, -67.5, 0.0)  # солнце с запада-юго-запада, низко
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.shadow_blur = 1.5
	add_child(sun)
	var ground := MeshInstance3D.new()
	ground.mesh = _ground_mesh(700.0, 6.0)
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://shaders/painterly_surface.gdshader")
	gm.set_shader_parameter("albedo_tex", preload("res://assets/textures/common/brush_noise.png"))
	gm.set_shader_parameter("albedo_tint", Color(0.2, 0.2, 0.13))
	ground.material_override = gm
	add_child(ground)
	_cam("CamLineup", Vector3(-1.5, 15.5, 17.0), Vector3(-1.5, 0.6, -2.6), 50.0)
	# крупно, контровой свет: камера смотрит в сторону низкого солнца (запад)
	_cam("CamClose", Vector3(1.6, 1.55, 12.6), Vector3(-4.2, 1.45, 9.3), 42.0)
	_cam("CamTop", Vector3(-8.0, 58.0, 52.0), Vector3(-8.0, 0.0, -2.0), 50.0)
	_cam("CamGait", Vector3(27.0, 11.0, 15.0), Vector3(27.0, 0.6, -4.0), 55.0)
	_cam("CamRiders", Vector3(-1.0, 6.0, 4.5), Vector3(-1.0, 1.2, -6.5), 55.0)
	_cam("CamInfantry", Vector3(-3.5, 3.8, 8.0), Vector3(-3.5, 0.9, 0.6), 55.0)
	_cam("CamSide", Vector3(27.0, 2.2, 10.0), Vector3(27.0, 1.0, -2.0), 45.0)
	# камера из аргументов: --campos=x,y,z --camlook=x,y,z [--camfov=40]
	var cp := _arg("campos", "")
	if cp != "":
		var a := cp.split_floats(",")
		var b := _arg("camlook", "0,1,0").split_floats(",")
		_cam("CamArg", Vector3(a[0], a[1], a[2]), Vector3(b[0], b[1], b[2]), float(_arg("camfov", "40")))


func _cam(cam_name: String, pos: Vector3, target: Vector3, fov: float) -> void:
	var c := Camera3D.new()
	c.name = cam_name
	c.fov = fov
	c.far = 600.0
	add_child(c)
	c.look_at_from_position(pos, target)
	if cam_name == "CamLineup":
		c.make_current()


func _ground_mesh(size: float, uv_m: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	var pts := [Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h)]
	for idx in [0, 1, 2, 0, 2, 3]:
		var p: Vector3 = pts[idx]
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(p.x, p.z) / uv_m)
		st.add_vertex(p)
	return st.commit()
