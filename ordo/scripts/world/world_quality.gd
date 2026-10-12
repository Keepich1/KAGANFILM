class_name WorldQuality
extends Node
## Режимы качества мира (ТЗ 11.7). Слушает Ordo.quality и Ordo.quality_changed.
##   «Высокое» (ПК): полный свет, мягкие тени на 4 каскада, объёмный туман с лучами,
##                   живописный фильтр, густая трава, подробные модели дальше.
##   «Низкое» (телефоны): ниже разрешение 3D, тени проще и ближе, без объёмного тумана
##                   (остаётся обычная дымка), без фильтра, травы втрое меньше, LOD раньше.
## Узел ищет соседей по именам в сцене мира: Environment, Sun, Terrain, Grass, Scatter.

@export var world_path := NodePath("..")


func _ready() -> void:
	Ordo.quality_changed.connect(apply)
	apply.call_deferred(Ordo.quality)


func apply(level: String) -> void:
	var world := get_node_or_null(world_path)
	if world == null:
		return
	var high := level != Ordo.QUALITY_LOW
	var we := world.get_node_or_null("Environment") as WorldEnvironment
	var sun := world.get_node_or_null("Sun") as DirectionalLight3D
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 1.0 if high else 0.75
	if we:
		var env := we.environment
		env.volumetric_fog_enabled = high and not (Ordo.has_arg("nofog") or Ordo.has_arg("novolfog"))
		env.ssao_enabled = high
		# без объёмного тумана низинам нужна обычная высотная дымка погуще
		env.fog_height_density = 0.025 if high else 0.06
		if we.compositor:
			for e in we.compositor.compositor_effects:
				if e is PainterlyPost:
					e.enabled = high and not Ordo.has_arg("nopost")
	if sun:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if high \
			else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 700.0 if high else 320.0
	RenderingServer.directional_shadow_atlas_set_size(8192 if high else 4096, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH if high else RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW)
	var grass := world.get_node_or_null("Grass") as GrassField
	if grass:
		grass.density_scale = 1.0 if high else 0.33
		grass.range_scale = 1.0 if high else 0.6
	var terrain := world.get_node_or_null("Terrain") as TerrainMesh
	if terrain:
		terrain.lod_scale = 1.0 if high else 0.6
		terrain.apply_lod_ranges()
	var scatter := world.get_node_or_null("Scatter") as WorldScatter
	if scatter:
		scatter.lod_scale = 1.0 if high else 0.6
