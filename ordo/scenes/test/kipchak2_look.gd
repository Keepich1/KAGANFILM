extends Node3D
## Проверка второй очереди лагеря кыпчаков: постройки, укрепления, месторождения, работники
## с инструментами. Временный свет заката и земля (как camp_look), мир потом даст свой.
##
##   tools/shot.sh res://scenes/test/kipchak2_look.tscn out.png --at=3 --cam=CamCampRTS --size=1280x720
##   несколько кадров за один запуск (без tools/shot.sh, через tools/godot.sh):
##     -- --multi=CamCampRTS@3,CamKurultai@3.2 --outdir=/абс/путь --tag=k2
##
## Камеры: CamCampRTS (RTS ~50°, ~70 м: база в частоколе), CamKurultai, CamPalisade (частокол,
## ворота, башня), CamDeposits (камень и золото, по три стадии), CamWorkers (крупно: рубят,
## копают, строят, несут — малчы и деҳқон), CamKen, CamJooker, CamMunara, CamArba,
## CamStates (стройки и руины всех построек), CamLOD (издали — LOD1).
## --only=base,states,deposits,workers — собрать только часть (быстрее).

const H := AnimSpec.Human
const BUILDING := preload("res://scenes/kipchak2/kipchak_building.gd")
const DEPOSIT_SCRIPT := "res://scenes/kipchak2/resource_deposit.gd"
const CAMP_MODELS := "res://assets/models/kipchak/"

## Частокол: 60 гнёзд по кругу (шаг 3 м), ворота и башни занимают по два гнезда
const RING_N := 60
const RING_R := 28.66      # 1.5 / sin(3°): хорда гнезда ровно 3.0 м
const GATE_SLOT := 0       # ворота между гнёздами 0 и 1 — на юг (+Z)
const TOWER_SLOTS := [7, 51, 22, 37]
const SITE_SLOTS := [29, 30]   # звенья на стройке (работники строят)
const RUIN_SLOTS := [44]        # пролом

var _groups := PackedStringArray()
var _shots: Array = []
var _busy := false
var _since_switch := 0
var _clock := 0.0
var _t := 0.0
var _layers := {}
var _workers: Array = []     # {unit, i, state, aux, pos, yaw, path(a, b), speed, var}


func _ready() -> void:
	var only := _arg("only", "")
	if only != "":
		_groups = only.split(",")
	_environment()
	_sun()
	_ground()
	if _on("base"):
		_base()
	if _on("states"):
		_states()
	if _on("deposits"):
		_deposits_row()
	if _on("workers"):
		_worker_yard()
	_cameras()
	for id in _layers:
		var n := 0
		for w in _workers:
			if w["unit"] == id:
				n += 1
		(_layers[id] as CrowdLayer).set_visible_count(n)
	_update_workers(0.0)
	var multi := _arg("multi", "")
	if multi != "":
		var outdir := _arg("outdir", "user://")
		var tag := _arg("tag", "f")
		for s in multi.split(","):
			var p := s.split("@")
			_shots.append({"cam": p[0], "at": float(p[1]), "path": "%s/%s_%s.png" % [outdir, tag, p[0]]})
	var cam := _arg("cam", "CamCampRTS")
	var c := find_child(cam, true, false) as Camera3D
	if c:
		c.make_current()


func _process(delta: float) -> void:
	_t += delta
	_clock += delta
	_update_workers(_t)
	if not _shots.is_empty() and not _busy:
		var s: Dictionary = _shots[0]
		var cam := find_child(s["cam"], true, false) as Camera3D
		if cam and not cam.current:
			cam.make_current()
			_since_switch = 0
		_since_switch += 1
		if _clock >= s["at"] and _since_switch > 2:
			_busy = true
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png(s["path"])
			print("[kipchak2] кадр ", s["path"])
			_shots.pop_front()
			_busy = false
			if _shots.is_empty():
				get_tree().quit()


func _arg(n: String, def: String) -> String:
	var o := get_node_or_null("/root/Ordo")
	return o.arg(n, def) if o else def


func _on(group: String) -> bool:
	return _groups.is_empty() or group in _groups


# ---------------------------------------------------------------- свет и земля (временные)

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
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
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
	gm.set_shader_parameter("camp_center", Vector3(0, 0, 0))
	gm.set_shader_parameter("camp_radius", 36.0)
	ground.material_override = gm
	ground.position = Vector3(20, 0, 20)
	add_child(ground)


# ---------------------------------------------------------------- постройки

func _building(kind: String, pos: Vector3, yaw := 0.0, state := 1, parent: Node = self) -> Node3D:
	var b := Node3D.new()
	b.set_script(BUILDING)
	b.set("kind", kind)
	b.set("state", state)
	b.name = "%s_%d" % [kind, parent.get_child_count()]
	b.position = pos
	b.rotation_degrees.y = yaw
	parent.add_child(b)
	return b


func _camp_model(file: String, pos: Vector3, yaw := 0.0) -> Node3D:
	var n := (load(CAMP_MODELS + file + ".glb") as PackedScene).instantiate() as Node3D
	KipchakModels.apply(n, {"rim_strength": 1.1})
	n.position = pos
	n.rotation_degrees.y = yaw
	add_child(n)
	return n


func _deposit(kind: String, stage: int, pos: Vector3, yaw := 0.0) -> Node3D:
	if not ResourceLoader.exists(DEPOSIT_SCRIPT):
		return null
	var d := Node3D.new()
	d.set_script(load(DEPOSIT_SCRIPT))
	d.set("kind", kind)
	d.set("stage", stage)
	d.name = "Deposit_%s_%d_%d" % [kind, stage, get_child_count()]
	d.position = pos
	d.rotation_degrees.y = yaw
	add_child(d)
	return d


func _ring_pos(a_deg: float) -> Vector3:
	var a := deg_to_rad(a_deg)
	return Vector3(sin(a) * RING_R, 0, cos(a) * RING_R)


func _base() -> void:
	# стан: курултай в середине, юрты, жоокер үйү, кен у золотой жилы, частокол кольцом
	_building("kurultai", Vector3(-3, 0, -5), 0.0)
	_building("jooker", Vector3(-15, 0, 9), 35.0)
	_deposit("gold", 0, Vector3(17.5, 0, -16.5), 20.0)
	_building("ken", Vector3(11.5, 0, -9.5), -40.0)
	_deposit("stone", 1, Vector3(-17, 0, -15), -30.0)
	for p in [[Vector3(12, 0, 13), -30.0], [Vector3(19, 0, 2), -80.0], [Vector3(-21, 0, -3), 70.0],
			[Vector3(4, 0, 17), 0.0]]:
		_camp_model("boz", p[0], p[1])
	_camp_model("campfire", Vector3(6, 0, 9), 0.0)
	_camp_model("woodpile", Vector3(15.5, 0, 9), -40.0)
	_camp_model("hay", Vector3(-9, 0, 18), 0.0)
	_building("munara_arba", Vector3(5, 0, -20), 100.0)
	var step := 360.0 / RING_N
	for i in RING_N:
		var skip := false
		for s in TOWER_SLOTS + [GATE_SLOT]:
			if i == s or i == s + 1:
				skip = true
		if skip:
			continue
		var st := 1
		if i in SITE_SLOTS:
			st = 0
		elif i in RUIN_SLOTS:
			st = 2
		var a := i * step
		_building("chep", _ring_pos(a), a, st)
	var ga := (GATE_SLOT + 0.5) * step
	var gate := _building("darbaza", _ring_pos(ga), ga)
	gate.name = "Gate"
	for s in TOWER_SLOTS:
		var ta: float = (float(s) + 0.5) * step
		var tp := _ring_pos(ta) - Vector3(sin(deg_to_rad(ta)), 0, cos(deg_to_rad(ta))) * 0.6
		_building("munara", tp, ta)
	# работники у стана: несут руду от жилы к кену, строят звенья, копают у жилы
	_worker("kok_dehqon", H.WORK, 0.25, Vector3(15.6, 0, -13.6), 130.0)
	_worker("kip_malchy", H.WORK, 0.25, Vector3(19.8, 0, -13.4), -150.0)
	_worker("kip_malchy", H.WORK, 0.75, Vector3(0, 0, 0), 0.0, [Vector3(16, 0, -12.5), Vector3(12.5, 0, -6.0)], 1.3)
	_worker("kok_dehqon", H.WORK, 0.75, Vector3(0, 0, 0), 0.0, [Vector3(18, 0, -11.5), Vector3(13.5, 0, -5.5)], 1.2)
	var sa: float = (float(SITE_SLOTS[0]) + 0.5) * step
	var sp := _ring_pos(sa) - Vector3(sin(deg_to_rad(sa)), 0, cos(deg_to_rad(sa))) * 2.0
	_worker("kip_malchy", H.WORK, 0.5, sp + Vector3(1.0, 0, 0.3), sa + 180.0)
	_worker("kok_dehqon", H.WORK, 0.5, sp + Vector3(-1.2, 0, 0.2), sa + 180.0)
	_worker("kip_malchy", H.WORK, 0.0, Vector3(-16, 0, -12.8), 160.0)
	_worker("kip_malchy", H.IDLE, 0.0, Vector3(-11, 0, 14), 40.0)
	_worker("kok_dehqon", H.WALK, 0.0, Vector3(0, 0, 0), 0.0, [Vector3(-8, 0, 20), Vector3(6, 0, 4)], 1.3)


func _states() -> void:
	# ряд: стройка — готово — руины для каждой постройки (z = 90…)
	var kinds := ["kurultai", "jooker", "ken", "munara", "darbaza", "chep"]
	var xs := [0.0, 18.0, 33.0, 45.0, 56.0, 66.0]
	for k in kinds.size():
		for st in 3:
			_building(kinds[k], Vector3(xs[k], 0, 90.0 + st * 17.0), 0.0, st)


func _deposits_row() -> void:
	for st in 3:
		_deposit("stone", st, Vector3(-60.0 + st * 12.0, 0, 40.0), 0.0)
		_deposit("gold", st, Vector3(-60.0 + st * 12.0, 0, 55.0), 0.0)


func _worker_yard() -> void:
	# крупный план работы: дерево, жила, звено на стройке, кен; оба вида работников
	var c := Vector3(-40, 0, 80)
	var tree := (load("res://assets/models/world/elm.glb") as PackedScene).instantiate() as Node3D
	Painterly.apply(tree)
	tree.position = c + Vector3(-4.5, 0, -2.0)
	tree.scale = Vector3.ONE * 0.6
	add_child(tree)
	_deposit("stone", 1, c + Vector3(5.5, 0, -3.5), 20.0)
	_building("chep", c + Vector3(0.5, 0, -6.5), 0.0, 0)
	_worker("kip_malchy", H.WORK, 0.0, c + Vector3(-3.6, 0, -0.9), -130.0)
	_worker("kok_dehqon", H.WORK, 0.0, c + Vector3(-5.6, 0, -0.6), 150.0)
	_worker("kip_malchy", H.WORK, 0.25, c + Vector3(3.6, 0, -1.6), 140.0)
	_worker("kok_dehqon", H.WORK, 0.25, c + Vector3(5.2, 0, -1.0), 175.0)
	_worker("kip_malchy", H.WORK, 0.5, c + Vector3(-0.6, 0, -5.0), 180.0)
	_worker("kok_dehqon", H.WORK, 0.5, c + Vector3(1.3, 0, -5.1), 180.0)
	_worker("kip_malchy", H.WORK, 0.75, c, 0.0, [c + Vector3(-2.5, 0, 3.5), c + Vector3(2.0, 0, 1.0)], 1.2)
	_worker("kok_dehqon", H.WORK, 0.875, c, 0.0, [c + Vector3(2.5, 0, 3.4), c + Vector3(-1.8, 0, 1.4)], 1.1)
	_worker("kok_dehqon", H.IDLE, 0.0, c + Vector3(0.6, 0, 2.6), 160.0)
	_worker("kok_dehqon", H.WALK, 0.0, c, 0.0, [c + Vector3(-3.0, 0, 5.0), c + Vector3(3.0, 0, 5.4)], 1.4)


# ---------------------------------------------------------------- работники (толпа)

func _worker(unit: String, state: int, aux: float, pos: Vector3, yaw: float, path := [], speed := 0.0) -> void:
	if not UnitRegistry.has(unit) or not ResourceLoader.exists(UnitRegistry.mesh_path(unit)):
		return
	if not _layers.has(unit):
		var l := CrowdLayer.new()
		l.name = "Crowd_" + unit
		add_child(l)
		l.setup(unit, 32)
		_layers[unit] = l
	var i := 0
	for w in _workers:
		if w["unit"] == unit:
			i += 1
	_workers.append({"unit": unit, "i": i, "state": state, "aux": aux, "pos": pos, "yaw": deg_to_rad(yaw),
		"path": path, "speed": speed, "var": fposmod(0.21 + _workers.size() * 0.618034, 1.0),
		"off": fposmod(_workers.size() * 0.37, 1.0)})


func _update_workers(t: float) -> void:
	for w in _workers:
		var layer: CrowdLayer = _layers[w["unit"]]
		var pos: Vector3 = w["pos"]
		var yaw: float = w["yaw"]
		var phase := 0.0
		var path: Array = w["path"]
		var st: int = w["state"]
		if path.size() == 2 and float(w["speed"]) > 0.0:
			# туда и обратно по отрезку, лицом по ходу
			var a: Vector3 = path[0]
			var b: Vector3 = path[1]
			var L := a.distance_to(b)
			var d: float = float(w["speed"]) * t + float(w["off"]) * L
			var k := fposmod(d, 2.0 * L)
			var fwd := k < L
			pos = a.lerp(b, (k if fwd else 2.0 * L - k) / L)
			var dir := (b - a) if fwd else (a - b)
			yaw = atan2(dir.x, dir.z)
			phase = fposmod(d / AnimSpec.STRIDE_HUMAN[H.WALK], 1.0)
		elif st == H.WORK:
			phase = fposmod((t + float(w["off"]) * 3.0) / 1.3, 1.0)
		else:
			phase = fposmod((t + float(w["off"]) * 3.0) / AnimSpec.IDLE_PERIOD, 1.0)
		var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
		layer.set_instance(w["i"], xf, AnimSpec.custom(st, phase, w["aux"], w["var"]))


# ---------------------------------------------------------------- камеры

func _cam(cam_name: String, pos: Vector3, target: Vector3, fov := 40.0) -> Camera3D:
	var c := Camera3D.new()
	c.name = cam_name
	c.fov = fov
	c.far = 1500.0
	add_child(c)
	c.look_at_from_position(pos, target)
	return c


func _cameras() -> void:
	# RTS: ~50° вниз, ~70 м до центра базы
	var center := Vector3(0, 0, 3.5)
	var d := 72.0
	var pitch := deg_to_rad(50.0)
	var dir := Vector3(0.28, 0, 1.0).normalized()
	_cam("CamCampRTS", center + dir * cos(pitch) * d + Vector3(0, sin(pitch) * d, 0), center, 45.0)
	_cam("CamKurultai", Vector3(9, 6.5, 14.5), Vector3(-3, 2.6, -4), 46.0)
	var ga := deg_to_rad((float(GATE_SLOT) + 0.5) * 360.0 / RING_N)
	var gp := _ring_pos(rad_to_deg(ga))
	_cam("CamPalisade", gp + Vector3(14, 6.5, 16), gp + Vector3(1, 3.2, -1), 44.0)
	_cam("CamDeposits", Vector3(-48, 13, 72), Vector3(-48, 0.5, 46), 50.0)
	_cam("CamWorkers", Vector3(-38.5, 3.2, 89.5), Vector3(-40, 0.9, 79), 46.0)
	_cam("CamKen", Vector3(19, 6.5, -1), Vector3(13, 1.2, -12), 46.0)
	_cam("CamJooker", Vector3(-4, 6.5, 22), Vector3(-15, 1.8, 8), 46.0)
	var tw := deg_to_rad((float(TOWER_SLOTS[0]) + 0.5) * 360.0 / RING_N)
	var tp := _ring_pos(rad_to_deg(tw))
	_cam("CamMunara", tp + Vector3(15, 6, 9), tp + Vector3(0, 5, 0), 46.0)
	_cam("CamArba", Vector3(10, 3.5, -14), Vector3(5, 1.3, -20), 46.0)
	_cam("CamStates", Vector3(33, 52, 150), Vector3(33, 0, 106), 50.0)
	_cam("CamLOD", Vector3(130, 120, 190), Vector3(0, 0, 0), 26.0)
