class_name World
extends Node3D
## Мир среза: земля, небо, солнце заката, туман, вода, трава, деревья, камни.
## Сцена scenes/world/world.tscn — её вставляет сборка (scenes/slice.tscn).
##
## Солнце — на западе-юго-западе, высота ~10° (CONTRACT §3). Тёплый ключевой свет,
## холодное сине-бирюзовое заполнение (Environment → Ambient), цветные тени.
## Общие живописные параметры ordo_* задаются здесь при запуске (см. PAINT_GLOBALS).
##
## Для других областей:
##   World.sun_direction() -> Vector3      направление НА солнце (единичный вектор)
##   World.instance                        текущий мир (или null)
##   world.get_marker("camp")              метки: camp, koroo, jylky, meadow, ford (+ Marker3D в Markers)
##   world.set_grass_clearings([Vector3(x, z, радиус), ...])  — убрать траву под постройками

signal built

## Азимут солнца, градусы (0 — север, 90 — восток, 247,5 — запад-юго-запад)
@export_range(0.0, 360.0) var sun_azimuth := 247.5
## Высота солнца над горизонтом, градусы
@export_range(1.0, 40.0) var sun_elevation := 10.0
## Задавать общие живописные параметры ordo_* при запуске
@export var set_paint_globals := true

## Рекомендованные значения общих параметров для заката (ordo_* в project.godot)
const PAINT_GLOBALS := {
	"ordo_key_tint": Color(1.0, 0.92, 0.82),
	"ordo_shadow_tint": Color(0.17, 0.27, 0.44),
	"ordo_terminator": Color(0.95, 0.38, 0.2, 0.42),
	"ordo_rim_color": Color(1.0, 0.76, 0.48, 0.95),
	"ordo_band_soft": 0.13,
	"ordo_brush_amount": 0.38,
	"ordo_brush_scale": 0.9,
	"ordo_wind": Vector4(0.82, 0.35, 1.0, 0.55),
}

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
	if set_paint_globals:
		for k in PAINT_GLOBALS:
			RenderingServer.global_shader_parameter_set(k, PAINT_GLOBALS[k])
	place_sun()
	_place_markers()
	_debug_args()
	built.emit()


## Отладка кадров: --nofog (без тумана), --novolfog (без объёмного тумана).
func _debug_args() -> void:
	var env := environment_node.environment
	if Ordo.has_arg("nofog"):
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
	if Ordo.has_arg("novolfog"):
		env.volumetric_fog_enabled = false
	if Ordo.has_arg("noglow"):
		env.glow_enabled = false
	if Ordo.has_arg("nomsaa"):
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	var post := painterly_post()
	if post:
		if Ordo.has_arg("nopost"):
			post.enabled = false
		if Ordo.has_arg("post_radius"):
			post.radius_1080 = float(Ordo.arg("post_radius"))


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


func get_marker(name: String) -> Vector3:
	return Terrain.marker(name)


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
