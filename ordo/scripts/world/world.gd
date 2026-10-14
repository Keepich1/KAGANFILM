class_name World
extends Node3D
## Мир среза: земля, небо, солнце, туман, вода, трава, деревья, камни.
## Сцена scenes/world/world.tscn — её вставляют срез (scenes/slice.tscn), «Город» и главное меню.
##
## Время суток (решение автора 2026-10-14): «День» (по умолчанию) или «Закат» — Ordo.light_mode,
## переключатель в главном меню. Числа обоих — scripts/world/light_presets.gd (LightPresets);
## мир ставит их при запуске и сразу при смене режима (apply_light): солнце, заполнение, кривая тона,
## туман, небо, воздух земли, туман низин, живописный фильтр и общие параметры ordo_*.
## Закат: солнце на западе-юго-западе ~10° (CONTRACT §3), тёплый ключевой свет, холодное
## сине-бирюзовое заполнение, контровой свет. День: солнце ~48° с юго-юго-запада, свет почти белый.
##
## Для других областей:
##   World.sun_direction() -> Vector3      направление НА солнце (единичный вектор)
##   World.instance                        текущий мир (или null)
##   world.get_marker("camp")              метки: camp, koroo, jylky, meadow, ford (+ Marker3D в Markers)
##   world.set_grass_clearings([Vector3(x, z, радиус), ...])  — убрать траву под постройками
##   world.city_light = true; world.apply_light()  — свет для вида сверху («Город»: LightPresets city)

signal built
## Свет мира сменился (время суток): режим LightPresets.DAY / SUNSET
signal light_applied(mode: String)

## Азимут солнца, градусы (0 — север, 90 — восток, 247,5 — запад-юго-запад). Ставит apply_light по режиму.
@export_range(0.0, 360.0) var sun_azimuth := 210.0
## Высота солнца над горизонтом, градусы. Ставит apply_light по режиму.
@export_range(1.0, 80.0) var sun_elevation := 50.0
## Задавать общие живописные параметры ordo_* при запуске
@export var set_paint_globals := true
## Свет по времени суток игрока (Ordo.light_mode) и сразу при смене (меню переключает на лету)
@export var follow_light_mode := true

## Поправки света для вида сверху («Город»: LightPresets city — у заката солнце выше, тени облаков слабее)
var city_light := false
## Режим, свет которого стоит сейчас ("" — ещё не ставили)
var light_mode := ""

static var instance: World
static var _sun_dir := Vector3(-0.91, 0.17, 0.38)

@onready var sun: DirectionalLight3D = $Sun
@onready var environment_node: WorldEnvironment = $Environment
@onready var terrain: TerrainMesh = $Terrain


static func sun_direction() -> Vector3:
	return _sun_dir


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	apply_light(LightPresets.current_mode() if follow_light_mode else LightPresets.SUNSET)
	if follow_light_mode:
		var o := get_node_or_null("/root/Ordo")
		if o and not o.is_connected("light_mode_changed", _on_light_mode_changed):
			o.connect("light_mode_changed", _on_light_mode_changed)
	# толпа (CrowdLayer.SUN_GROUP) смотрит каскады теней солнца: тень юнита — только в тех каскадах, куда она падает
	if sun:
		sun.add_to_group(&"ordo_sun")
	_place_markers()
	_debug_args()
	built.emit()


## Отладка кадров: --nofog (без тумана), --novolfog (без объёмного тумана).
func _debug_args() -> void:
	var o := get_node_or_null("/root/Ordo")
	if o == null:
		return
	var env := environment_node.environment
	if o.has_arg("nofog"):
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
	if o.has_arg("novolfog"):
		env.volumetric_fog_enabled = false
	var parts := {"grass": "Grass", "scatter": "Scatter", "water": "Water", "fogbanks": "FogBanks"}
	for part in parts:
		if o.has_arg("no" + part):
			var n := get_node_or_null(String(parts[part])) as Node3D
			if n:
				n.visible = false
				n.process_mode = Node.PROCESS_MODE_DISABLED
	if o.has_arg("grassdebug") and has_node("Grass"):
		for r in ($Grass as GrassField).ring_materials():
			for k in ["base_color", "mid_color", "tip_color", "cool_tip", "dry_tip"]:
				r.set_shader_parameter(k, Color(1, 0, 1))
	if o.has_arg("noglow"):
		env.glow_enabled = false
	if o.has_arg("nomsaa"):
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	var post := painterly_post()
	if post:
		if o.has_arg("nopost"):
			post.enabled = false
		if o.has_arg("post_radius"):
			post.radius_1080 = float(o.arg("post_radius"))


func _o_has(key: String) -> bool:
	var o := get_node_or_null("/root/Ordo")
	return o != null and bool(o.call("has_arg", key))


func _on_light_mode_changed(mode: String) -> void:
	apply_light(mode)


## Свет времени суток (LightPresets): солнце, окружение, небо, воздух земли, туман низин, фильтр, ordo_*.
## Пустой режим — тот, что стоит (повторно — например, после city_light).
func apply_light(mode: String = "") -> void:
	if mode == "":
		mode = light_mode if light_mode != "" else LightPresets.current_mode()
	light_mode = mode
	var p := LightPresets.preset(mode)
	if set_paint_globals:
		var g := LightPresets.globals(mode, city_light)
		for k in g:
			RenderingServer.global_shader_parameter_set(k, g[k])
		var o := get_node_or_null("/root/Ordo")
		if o:
			o.call("set_wind", g["ordo_wind"])
	sun_azimuth = float(p.sun_azimuth)
	sun_elevation = LightPresets.sun_elevation(mode, city_light)
	if sun:
		sun.light_color = p.sun_color
		sun.light_energy = float(p.sun_energy)
		sun.light_volumetric_fog_energy = float(p.sun_fog_energy)
	if environment_node and environment_node.environment:
		var env := environment_node.environment
		var e: Dictionary = p.env
		for k in e:
			env.set(k, e[k])
		var level := String(get_node("/root/Ordo").get("quality")) if has_node("/root/Ordo") else WorldQuality.HIGH
		LightPresets.apply_fog(env, mode, bool(WorldQuality.preset(level).volfog))
		var sky_mat: ShaderMaterial = env.sky.sky_material as ShaderMaterial if env.sky else null
		if sky_mat:
			var sk: Dictionary = p.sky
			for k in sk:
				sky_mat.set_shader_parameter(k, sk[k])
	if terrain and terrain.material:
		var t: Dictionary = p.terrain
		for k in t:
			terrain.material.set_shader_parameter(k, t[k])
	var grass := get_node_or_null("Grass") as GrassField
	if grass and not _o_has("grassdebug"):
		var gr: Dictionary = p.grass
		var mats: Array[ShaderMaterial] = grass.ring_materials()
		if grass.material:
			mats.append(grass.material)
		for m in mats:
			for k in gr:
				m.set_shader_parameter(k, gr[k])
	var banks := get_node_or_null("FogBanks") as FogBanks
	if banks:
		banks.apply_light(p.fog_banks)
	var post := painterly_post()
	if post:
		var pp: Dictionary = p.post
		for k in pp:
			post.set(k, pp[k])
	if is_inside_tree():
		place_sun()
	light_applied.emit(mode)


## Живописный фильтр кадра (CompositorEffect) или null.
func painterly_post() -> PainterlyPost:
	var comp := environment_node.compositor
	if comp == null:
		return null
	for e in comp.compositor_effects:
		if e is PainterlyPost:
			return e
	return null


## Ставит солнце по азимуту и высоте (свет идёт ОТ солнца).
func place_sun() -> void:
	var az := deg_to_rad(sun_azimuth)
	var el := deg_to_rad(sun_elevation)
	_sun_dir = Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()
	if sun:
		sun.basis = Basis.looking_at(-_sun_dir, Vector3.UP)
	var o: Node = get_node_or_null("/root/Ordo") if is_inside_tree() else null
	if o:
		o.call("set_sun_dir", _sun_dir)


func get_marker(name: String) -> Vector3:
	return Terrain.marker(name)


## Поляны без травы под постройками: [Vector3(x, z, радиус), ...] (до 48 штук).
func set_grass_clearings(list: Array) -> void:
	var g := get_node_or_null("Grass") as GrassField
	if g:
		g.set_clearings(list)


func _place_markers() -> void:
	var root := get_node_or_null("Markers")
	if root == null:
		root = Node3D.new()
		root.name = "Markers"
		add_child(root)
	for key in Terrain.info().get("markers", {}):
		var m := Marker3D.new()
		m.name = String(key).capitalize()
		m.position = Terrain.marker(key)
		root.add_child(m)
