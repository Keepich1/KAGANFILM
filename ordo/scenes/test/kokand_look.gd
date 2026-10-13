extends Node3D
## Проверка вида города Коканда: временный свет заката (мир потом даст свой), рисованная
## земля и камеры для кадров. Модели — обёртки scenes/kokand/*.tscn (KokandBuilding).
##   tools/shot.sh res://scenes/test/kokand_look.tscn out.png --cam=CamTown --at=3
## Несколько кадров за один запуск (быстрее на программном рендере):
##   tools/godot.sh --path . --resolution 1280x720 --fixed-fps 30 res://scenes/test/kokand_look.tscn \
##     -- --multi=CamTown,CamUrda --out_dir=/abs/dir --at=3
## Режимы (--mode=): town — город за стеной (по умолчанию); models — все модели рядами (готовые,
## стройка, руины); lod — то же для LOD1.
## Камеры города: CamTown (RTS ~50°, ~90 м), CamWallClose (одобренная кирпичная стена крупно),
##   CamUrda, CamFields, CamGate, CamHouses, CamMilitary, CamMill, CamFar (дальше LOD), CamLow.
## Камеры моделей: CamFort, CamBuildings, CamSites, CamRuins, CamFieldRow, CamBurj, CamDarvoza,
##   CamUy, CamDetail.

const S := "res://scenes/kokand/"

var _multi: PackedStringArray = []
var _out_dir := ""
var _at := 3.0
var _t := 0.0
var _shooting := false
## Начало координат города (в режиме world — луг мира у поля боя, CONTRACT §3)
var _origin := Vector3.ZERO
var _snap := false
var _world: Node3D


func _ready() -> void:
	var o := get_node_or_null("/root/Ordo")
	var mode := "town"
	if o:
		mode = o.call("arg", "mode", "town")
		var m: String = o.call("arg", "multi", "")
		if m != "":
			_multi = m.split(",")
			_out_dir = o.call("arg", "out_dir", "")
			_at = float(o.call("arg", "at", "3"))
	if mode == "world":
		# город на настоящей земле мира: свет, небо, туман, трава, живописный фильтр — как в игре
		_world = (load("res://scenes/world/world.tscn") as PackedScene).instantiate() as Node3D
		add_child(_world)
		_origin = Vector3(92, 0, 18)
		_snap = true
		_town()
		_world_dressing()
		return
	_environment()
	_sun()
	_ground()
	if mode == "town":
		_town()
	else:
		_lineup(mode == "lod")


func _process(delta: float) -> void:
	_t += delta
	if _multi.size() > 0 and not _shooting and _t >= _at:
		_shooting = true
		_shoot_all()


func _shoot_all() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	for cam_name in _multi:
		var cam := find_child(cam_name, true, false) as Camera3D
		if cam == null:
			print("[kokand] нет камеры ", cam_name)
			continue
		cam.make_current()
		for k in 3:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := _out_dir.path_join(cam_name + ".png")
		img.save_png(path)
		print("[kokand] кадр: ", path)
	get_tree().quit()


# ---------------------------------------------------------------- свет и земля (временные)

func _environment() -> void:
	# свет и тон как у мира (scenes/world/world.tscn): заполнение 0,75, AgX с контрастом,
	# SSAO, свечение, туман, живописный фильтр кадра (PainterlyPost) — чтобы кадр проверки
	# был таким же, как в игре; небо — рисованное небо мира. Без объёмного тумана (дорого на ЦП).
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	if ResourceLoader.exists("res://shaders/sky.gdshader"):
		sm.shader = load("res://shaders/sky.gdshader")
		sm.set_shader_parameter("brush_tex", load("res://assets/textures/world/brush_world.png"))
	else:
		sm.shader = preload("res://scenes/test/kokand_sky.gdshader")
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.29, 0.47, 0.6)
	env.ambient_light_sky_contribution = 0.0
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.95
	env.set("tonemap_agx_contrast", 1.38)
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.2
	env.ssao_power = 1.5
	env.ssao_light_affect = 0.1
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.5
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color(0.42, 0.45, 0.56)
	env.fog_light_energy = 0.7
	env.fog_sun_scatter = 0.05
	env.fog_density = 0.0009
	env.fog_aerial_perspective = 0.75
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.06
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	var o := get_node_or_null("/root/Ordo")
	var post := not (o != null and bool(o.call("has_arg", "nopost")))
	if post and ResourceLoader.exists("res://scripts/world/painterly_post.gd"):
		var eff := (load("res://scripts/world/painterly_post.gd") as Script).new() as CompositorEffect
		var comp := Compositor.new()
		comp.compositor_effects = [eff]
		we.compositor = comp
	add_child(we)


func _sun() -> void:
	# солнце как у мира: азимут 247,5° (запад-юго-запад), высота 10° (CONTRACT §3)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1, 0.706, 0.431)
	sun.light_energy = 3.2
	var az := deg_to_rad(247.5)
	var el := deg_to_rad(10.0)
	var to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()
	sun.basis = Basis.looking_at(-to_sun, Vector3.UP)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 300.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)
	var o := get_node_or_null("/root/Ordo")
	if o and o.has_method("set_sun_dir"):
		o.call("set_sun_dir", to_sun)


func _ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	ground.mesh = pm
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://scenes/test/kokand_ground.gdshader")
	ground.material_override = gm
	add_child(ground)


func _cam(cam_name: String, pos: Vector3, target: Vector3, fov := 40.0) -> Camera3D:
	var c := Camera3D.new()
	c.name = cam_name
	c.fov = fov
	c.far = 3000.0
	add_child(c)
	var lift := 0.0
	if _snap:
		lift = Terrain.height_at(target.x + _origin.x, target.z + _origin.z)
	c.position = pos + _origin + Vector3(0, lift, 0)
	c.look_at(target + _origin + Vector3(0, lift, 0))
	return c


## Режим world: трава убрана под городом и полями, улицы и площадь — декали утоптанной земли.
func _world_dressing() -> void:
	var clear: Array = []
	for gx in range(-30, 31, 15):
		for gz in range(-26, 23, 12):
			clear.append(Vector3(_origin.x + gx, _origin.z + gz, 11.0))
	for c: Vector3 in [Vector3(-15, 44, 11), Vector3(-32, 44, 11), Vector3(15, 44, 11), Vector3(32, 42, 7), Vector3(0, 34, 6),
			Vector3(0, 46, 6)]:
		clear.append(Vector3(_origin.x + c.x, _origin.z + c.y, c.z))
	if _world.has_method("set_grass_clearings"):
		_world.call("set_grass_clearings", clear.slice(0, 48))
	var tex := load("res://assets/textures/kokand/street_decal.png") as Texture2D
	var gtex := load("res://assets/textures/kokand/ground_decal.png") as Texture2D
	# улица от ворот к урде, поперечная улица, дорога к полям, площадь перед урдой
	var streets := [[Vector3(0, 0, 30), Vector3(0, 0, -4), 7.0], [Vector3(-33, 0, 11), Vector3(33, 0, 11), 6.0],
		[Vector3(0, 0, 26), Vector3(0, 0, 60), 6.0], [Vector3(-30, 0, 35.5), Vector3(30, 0, 35.5), 4.5]]
	var i := 0
	for st: Array in streets:
		var a: Vector3 = st[0] + _origin
		var b: Vector3 = st[1] + _origin
		var w: float = st[2]
		var d := Decal.new()
		d.name = "Street_%d" % i
		d.texture_albedo = tex
		var mid := (a + b) * 0.5
		mid.y = Terrain.height_at(mid.x, mid.z)
		d.position = mid
		d.rotation.y = atan2(b.x - a.x, b.z - a.z)
		d.size = Vector3(w, 3.0, a.distance_to(b) + w)
		d.albedo_mix = 0.85
		d.modulate = Color(0.85, 0.8, 0.76, 1)
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		d.normal_fade = 0.5
		add_child(d)
		i += 1
	for c: Vector3 in [Vector3(0, 0, 4), Vector3(-20, 0, -6), Vector3(20, 0, -8), Vector3(-18, 0, 18), Vector3(18, 0, 18)]:
		var g := Decal.new()
		g.texture_albedo = gtex
		var p := c + _origin
		p.y = Terrain.height_at(p.x, p.z)
		g.position = p
		g.rotation.y = c.x * 0.37
		g.size = Vector3(26.0, 3.0, 22.0)
		g.albedo_mix = 0.75
		g.modulate = Color(0.85, 0.8, 0.75, 1)
		g.upper_fade = 0.3
		g.lower_fade = 0.3
		g.normal_fade = 0.5
		add_child(g)


func _put(kind: String, pos: Vector3, yaw_deg := 0.0, props := {}, node_name := "") -> Node3D:
	var path := S + kind + ".tscn"
	if not ResourceLoader.exists(path):
		return null
	var n := (load(path) as PackedScene).instantiate() as Node3D
	if node_name != "":
		n.name = node_name
	for k in props:
		n.set(k, props[k])
	if _snap:
		n.set("snap", true)
	n.position = pos + _origin
	n.rotation_degrees.y = yaw_deg
	add_child(n)
	return n


# ---------------------------------------------------------------- город

func _town() -> void:
	var town := Node3D.new()
	town.name = "Town"
	add_child(town)
	# стена: обход против часовой (на виде сверху) — зубцы наружу
	var x0 := -36.0
	var x1 := 36.0
	var zn := -32.0
	var zs := 26.0
	var walls := Node3D.new()
	walls.name = "Walls"
	town.add_child(walls)
	var o3 := _origin
	if ResourceLoader.exists(S + "tosh.tscn"):
		KokandWallLine.place(walls, o3 + Vector3(x0 + 3.0, 0, zs), o3 + Vector3(-3.4, 0, zs), "tosh", "built", false,
			"ToshS1", _snap)
		KokandWallLine.place(walls, o3 + Vector3(3.4, 0, zs), o3 + Vector3(x1 - 3.0, 0, zs), "tosh", "built", false,
			"ToshS2", _snap)
		KokandWallLine.place(walls, o3 + Vector3(x1, 0, zs - 3.0), o3 + Vector3(x1, 0, zn), "tosh", "built", false,
			"ToshE", _snap)
		KokandWallLine.place(walls, o3 + Vector3(x1, 0, zn), o3 + Vector3(x0, 0, zn), "tosh", "built", false, "ToshN",
			_snap)
		KokandWallLine.place(walls, o3 + Vector3(x0, 0, zn), o3 + Vector3(x0, 0, zs - 3.0), "tosh", "built", false,
			"ToshW", _snap)
	_put("tosh_end", Vector3(x1, 0, zn), 0.0, {}, "ToshEnd_NE")
	_put("tosh_end", Vector3(x0, 0, zn), 0.0, {}, "ToshEnd_NW")
	_put("darvoza", Vector3(0, 0, zs), 0.0, {}, "Darvoza")
	_put("burj", Vector3(x0, 0, zs), 0.0, {}, "Burj_SW")
	_put("burj", Vector3(x1, 0, zs), 0.0, {}, "Burj_SE")
	# ставка и казённые дворы
	_put("urda", Vector3(0, 0, -14), 0.0, {}, "Urda")
	_put("kazarma", Vector3(-23, 0, -22), 0.0, {}, "Kazarma")
	_put("topxona", Vector3(23, 0, -22), 0.0, {}, "Topxona")
	_put("otxona", Vector3(-26, 0, 0), 0.0, {}, "Otxona")
	_put("ombor", Vector3(23, 0, -3), 0.0, {}, "Ombor")
	# дома вдоль улицы от ворот к урде и по краям
	var houses := [[Vector3(-10, 0, 6), 90.0, 1], [Vector3(-10, 0, 16), 90.0, 2], [Vector3(-21, 0, 17), 0.0, 3],
		[Vector3(-30, 0, 17), 0.0, 1], [Vector3(10, 0, 7), -90.0, 2], [Vector3(10, 0, 17), -90.0, 3],
		[Vector3(21, 0, 17), 0.0, 1], [Vector3(30, 0, 17), 0.0, 2], [Vector3(-13, 0, -2), 90.0, 3],
		[Vector3(13, 0, -1), -90.0, 1], [Vector3(30, 0, 6), -90.0, 3]]
	var tints := [Color(1, 1, 1), Color(1.0, 0.96, 0.9), Color(0.95, 0.93, 0.9), Color(1.04, 1.0, 0.94)]
	for i in houses.size():
		var h: Array = houses[i]
		_put("uy", h[0], h[1], {"variant": h[2], "tint": tints[i % tints.size()]}, "Uy_%d" % (i + 1))
	# за стеной: поля с арыками, мельница, запруда
	_put("dala", Vector3(-15, 0, 44), 0.0, {"growth": 2}, "Dala_1")
	_put("dala", Vector3(-32, 0, 44), 0.0, {"growth": 1}, "Dala_2")
	_put("dala", Vector3(15, 0, 44), 0.0, {"growth": 0}, "Dala_3")
	_put("tegirmon", Vector3(32, 0, 42), 0.0, {}, "Tegirmon")
	# тополя вдоль арыков и карагачи во дворах (модели мира, для живого кадра)
	var poplars: Array[Vector3] = []
	for i in 10:
		poplars.append(Vector3(-41.0 + i * 3.4, 0, 54.5))
		poplars.append(Vector3(6.0 + i * 3.0, 0, 54.5))
	for p in poplars:
		_tree("poplar", p, 0.85 + 0.1 * sin(p.x))
	for p in [Vector3(-4.5, 0, 11), Vector3(5, 0, 21), Vector3(-17, 0, 9), Vector3(16, 0, 9), Vector3(4.5, 0, -1)]:
		_tree("elm", p, 0.75)
	_town_cameras()


func _tree(kind: String, pos: Vector3, s: float) -> void:
	var path := "res://assets/models/world/%s.glb" % kind
	if not ResourceLoader.exists(path) or not ResourceLoader.exists("res://assets/models/world/foliage.gdshader"):
		return
	var root := (load(path) as PackedScene).instantiate()
	var mesh: Mesh = null
	for n in root.find_children("*", "MeshInstance3D", true, false):
		mesh = (n as MeshInstance3D).mesh
		break
	root.free()
	if mesh == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/models/world/foliage.gdshader")
	mat.set_shader_parameter("albedo_tex", load("res://assets/textures/world/trees.png"))
	mat.set_shader_parameter("tint", Color(0.74, 0.76, 0.68) if kind == "poplar" else Color(0.62, 0.7, 0.6))
	var mi := MeshInstance3D.new()
	mi.name = "Tree_" + kind
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos + _origin
	if _snap:
		mi.position.y = Terrain.height_at(mi.position.x, mi.position.z) - 0.15
	mi.rotation.y = pos.x * 1.7
	mi.scale = Vector3.ONE * s
	add_child(mi)


func _town_cameras() -> void:
	var t := Vector3(0, 0, 4)
	var d := 90.0
	var pitch := deg_to_rad(50.0)
	var yaw := deg_to_rad(-38.0)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * d
	_cam("CamTown", t + off, t, 45.0).make_current()
	# одобренная форма: кирпичная стена с поясом и зубцами, снаружи, на закатном свету
	_cam("CamWallClose", Vector3(-22, 2.4, 36.5), Vector3(-15.5, 3.4, 26), 42.0)
	_cam("CamUrda", Vector3(-9, 13, 17), Vector3(0, 5.5, -12), 45.0)
	_cam("CamFields", Vector3(-31, 14, 29), Vector3(-17, 0, 47), 50.0)
	_cam("CamGate", Vector3(-8, 4.5, 41), Vector3(0, 4.0, 26), 45.0)
	_cam("CamHouses", Vector3(-1, 10, 31), Vector3(-10, 1.5, 10), 45.0)
	_cam("CamMilitary", Vector3(-8, 22, 2), Vector3(-23, 2, -21), 45.0)
	_cam("CamEconomy", Vector3(8, 18, 14), Vector3(23, 2, -10), 45.0)
	_cam("CamMill", Vector3(45, 6.5, 33), Vector3(32, 2, 43), 45.0)
	_cam("CamFar", Vector3(-150, 140, 210), Vector3(0, 0, 0), 30.0)
	_cam("CamLow", Vector3(-20, 1.7, 36), Vector3(0, 6.0, 20), 52.0)


# ---------------------------------------------------------------- модели рядами

func _lineup(lod: bool) -> void:
	# ряды по состояниям: готовые (z = 0), стройка (z = −34), руины (z = −68);
	# слева укрепления, правее здания с шагом 22 м
	var fort := ["tosh", "tosh_end", "devor", "devor_end", "darvoza", "burj"]
	var bld := ["urda", "kazarma", "topxona", "otxona", "uy", "tegirmon", "ombor", "dala", "bozor", "xumdon"]
	var states := ["built", "site", "ruin"]
	for si in states.size():
		var z := -si * 34.0
		var x := -26.0
		for k in fort:
			_put(k, Vector3(x, 0, z), 0.0, {"state": states[si], "lod_distance": 0.01 if lod else 1000.0})
			x += 9.5 if k in ["darvoza", "burj"] else 6.0
		x = 30.0
		for k in bld:
			if _put(k, Vector3(x, 0, z), 0.0, {"state": states[si], "lod_distance": 0.01 if lod else 1000.0}):
				x += 22.0
	_cam("CamFort", Vector3(-1, 9, 22), Vector3(-1, 2.5, 0), 50.0).make_current()
	_cam("CamFortSites", Vector3(-1, 11, -12), Vector3(-1, 1.0, -34), 50.0)
	_cam("CamFortRuins", Vector3(-1, 11, -46), Vector3(-1, 1.0, -68), 50.0)
	_cam("CamBurj", Vector3(12, 8, 18), Vector3(19, 6, 0), 45.0)
	_cam("CamDarvoza", Vector3(4, 4.5, 14), Vector3(9.5, 3.5, 0), 45.0)
	_cam("CamTosh", Vector3(-22, 3.2, 8), Vector3(-25, 3.0, 0), 45.0)
	for row in [[0.0, ""], [-34.0, "Sites"], [-68.0, "Ruins"]]:
		var z: float = row[0]
		var tag: String = row[1]
		_cam("CamA" + tag, Vector3(52, 26, z + 30), Vector3(52, 0, z - 1), 50.0)
		_cam("CamB" + tag, Vector3(118, 26, z + 30), Vector3(118, 0, z - 1), 50.0)
		_cam("CamC" + tag, Vector3(184, 26, z + 30), Vector3(184, 0, z - 1), 50.0)
