class_name WorldQuality
extends Node
## Режимы качества мира (ТЗ 11.7). Слушает Ordo.quality и Ordo.quality_changed.
##   «Высокое» (ПК): полный свет, мягкие тени на 4 каскада, объёмный туман с лучами,
##                   живописный фильтр, густая трава, подробные модели дальше. Как было в срезе.
##   «Среднее» (ПК попроще): тот же вид дешевле — живописный фильтр в половине разрешения
##                   с бережным увеличением, сетка тумана реже, тени те же 4 каскада, но карта
##                   вдвое меньше и ближе (500 м), SSAO проще, травы меньше, кадр 3D 77 % (FSR 1).
##   «Низкое» (слабые ПК, телефоны): кадр 3D ~2/3 экрана (FSR 1), тени 2 каскада и ближе,
##                   без объёмного тумана (обычная дымка гуще), без SSAO и MSAA (FXAA),
##                   живописный фильтр в половине разрешения, травы втрое меньше, LOD раньше.
## Узел ищет соседей по именам в сцене мира: Environment, Sun, Terrain, Grass, Scatter.
##
## Для других областей: WorldQuality.preset(уровень) — числа уровня (толпа: crowd_lod,
## crowd_lod1_shadow; эффекты: fx), WorldQuality.level_name(), next_level() (F2),
## auto_level() — выбор по видеокарте при первом запуске (Ordo запоминает выбор игрока).
## Ключ --upscale=fsr1|fsr2|bilinear подменяет способ увеличения (для сравнения).

const HIGH := "high"
const MEDIUM := "medium"
const LOW := "low"
## Порядок F2: «Высокое» → «Среднее» → «Низкое» → «Высокое»
const LEVELS := [HIGH, MEDIUM, LOW]
const NAMES := {HIGH: "Высокое", MEDIUM: "Среднее", LOW: "Низкое"}

## Числа уровней. scale — доля разрешения 3D, upscale — как растянуть до экрана;
## post — живописный фильтр: full / half (половина разрешения) / off.
const PRESETS := {
	HIGH: {
		"scale": 1.0, "upscale": "bilinear", "msaa": true,
		"post": "full", "volfog": true, "fog_grid": 128, "ssao": true, "ssao_low": false,
		"shadow_splits": 4, "shadow_dist": 700.0, "shadow_atlas": 8192, "shadow_soft": "high",
		"grass_density": 1.0, "grass_range": 1.0, "terrain_lod": 1.0, "scatter_lod": 1.0,
		"crowd_lod": 1.0, "crowd_lod1_shadow": true, "fx": 1.0,
	},
	MEDIUM: {
		"scale": 0.77, "upscale": "fsr1", "msaa": true,
		"post": "half", "volfog": true, "fog_grid": 96, "ssao": true, "ssao_low": true,
		"shadow_splits": 4, "shadow_dist": 500.0, "shadow_atlas": 4096, "shadow_soft": "low",
		"grass_density": 0.6, "grass_range": 0.85, "terrain_lod": 0.8, "scatter_lod": 0.8,
		"crowd_lod": 0.75, "crowd_lod1_shadow": true, "fx": 0.75,
	},
	LOW: {
		"scale": 0.67, "upscale": "fsr1", "msaa": false,
		"post": "half", "volfog": false, "fog_grid": 64, "ssao": false, "ssao_low": true,
		"shadow_splits": 2, "shadow_dist": 320.0, "shadow_atlas": 4096, "shadow_soft": "low",
		"grass_density": 0.33, "grass_range": 0.6, "terrain_lod": 0.6, "scatter_lod": 0.6,
		"crowd_lod": 0.5, "crowd_lod1_shadow": false, "fx": 0.5,
	},
}

@export var world_path := NodePath("..")


static func preset(level: String) -> Dictionary:
	return PRESETS.get(level, PRESETS[HIGH])


static func level_name(level: String) -> String:
	return NAMES.get(level, level)


## Следующий уровень по F2
static func next_level(level: String) -> String:
	var i := LEVELS.find(level)
	return LEVELS[(i + 1) % LEVELS.size()]


## Уровень для этой видеокарты (первый запуск, пока игрок сам не выбрал F2).
## Видеокарта программная или встроенная — «Низкое»; по имени: RTX x060 и выше, RX 6600 и выше —
## «Высокое»; GTX 1660, RTX x050, RX 5600/5700, Arc A7xx — «Среднее»; GTX 1650 и ниже — «Низкое».
## Имя не узнали — по памяти видеокарты; не узнали и её — «Среднее» (безопасно).
static func auto_level() -> String:
	if OS.has_feature("mobile") or OS.has_feature("web"):
		return LOW
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	var type := RenderingServer.get_video_adapter_type()
	if type == RenderingDevice.DEVICE_TYPE_CPU or "llvmpipe" in adapter or "lavapipe" in adapter \
			or "swiftshader" in adapter or "software" in adapter:
		return LOW
	if type == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
		# Apple M — встроенная, но сильная
		return MEDIUM if "apple m" in adapter else LOW
	var tier := gpu_tier(adapter)
	if tier >= 0:
		return [LOW, MEDIUM, HIGH][tier]
	var vram := video_memory_gb()
	if vram >= 7.5:
		return HIGH
	if vram >= 3.5:
		return MEDIUM
	if vram > 0.1:
		return LOW
	return MEDIUM


## Память видеокарты, ГБ (0 — неизвестно)
static func video_memory_gb() -> float:
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		return 0.0
	return float(rd.get_device_total_memory()) / 1073741824.0


## Класс видеокарты по имени: 2 — сильная, 1 — средняя, 0 — слабая, −1 — не знаем
static func gpu_tier(adapter: String) -> int:
	var a := adapter.to_lower()
	var re := RegEx.new()
	# NVIDIA: RTX 2060…5090, GTX 750…1660, MX
	re.compile("(rtx|gtx)\\s*(\\d{3,4})")
	var m := re.search(a)
	if m and not ("rtx a" in a or "quadro" in a):
		var num := int(m.get_string(2))
		if m.get_string(1) == "rtx":
			var series := num / 100
			var t := num % 100
			if (series >= 30 and t >= 60) or (series == 20 and t >= 70):
				return 2
			return 1
		if num >= 1660 and num < 1700:
			return 1
		if num >= 1070 and num < 1100:
			return 1
		return 0
	if " mx" in a or a.begins_with("mx"):
		return 0
	if "rtx a" in a or "quadro" in a:
		return 1
	# AMD: RX 480…9070
	re.compile("rx\\s*(\\d{3,4})")
	m = re.search(a)
	if m:
		var num := int(m.get_string(1))
		if num < 1000:
			return 0       # RX 470/480/570/580/590
		var series := num / 1000
		var t := (num % 1000) / 10 if series >= 9 else (num / 100) % 10
		if series >= 6 and t >= 6:
			return 2
		if series >= 5 and t >= 6:
			return 1
		return 0
	if "vega 56" in a or "vega 64" in a or "radeon vii" in a:
		return 1
	# Intel Arc: A7xx/B5xx — средняя, A3xx — слабая
	re.compile("arc\\S*\\s*([ab])(\\d{3})")
	m = re.search(a)
	if m:
		return 1 if int(m.get_string(2)) >= 500 else 0
	if "iris" in a or "uhd" in a or "hd graphics" in a:
		return 0
	return -1


func _ready() -> void:
	var o := _ordo()
	if o:
		o.connect("quality_changed", apply)
		apply.call_deferred(String(o.get("quality")))


func apply(level: String) -> void:
	var world := get_node_or_null(world_path)
	if world == null:
		return
	var p := preset(level)
	var we := world.get_node_or_null("Environment") as WorldEnvironment
	var sun := world.get_node_or_null("Sun") as DirectionalLight3D
	apply_viewport(get_viewport(), level)
	if we:
		var env := we.environment
		var volfog: bool = p.volfog
		env.volumetric_fog_enabled = volfog and not (_has_arg("nofog") or _has_arg("novolfog"))
		env.ssao_enabled = p.ssao
		# без объёмного тумана низинам нужна обычная высотная дымка погуще
		env.fog_height_density = 0.025 if volfog else 0.06
		env.fog_density = 0.0005 if volfog else 0.0016
		env.fog_sun_scatter = 0.05 if volfog else 0.25
		if we.compositor:
			for e in we.compositor.compositor_effects:
				if e is PainterlyPost:
					e.enabled = p.post != "off" and not _has_arg("nopost")
					e.half_res = p.post == "half"
	if sun:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(p.shadow_splits) == 4 \
			else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = p.shadow_dist
	RenderingServer.directional_shadow_atlas_set_size(int(p.shadow_atlas), true)
	# сетка объёмного тумана подробнее: лучи сквозь деревья и юрты читаются чётче
	RenderingServer.environment_set_volumetric_fog_volume_size(int(p.fog_grid), int(p.fog_grid))
	var soft := RenderingServer.SHADOW_QUALITY_SOFT_HIGH
	match String(p.shadow_soft):
		"low":
			soft = RenderingServer.SHADOW_QUALITY_SOFT_LOW
		"very_low":
			soft = RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW
	RenderingServer.directional_soft_shadow_filter_set_quality(soft)
	_apply_ssao_quality(bool(p.ssao_low))
	var grass := world.get_node_or_null("Grass") as GrassField
	if grass:
		grass.density_scale = p.grass_density
		grass.range_scale = p.grass_range
	var terrain := world.get_node_or_null("Terrain") as TerrainMesh
	if terrain:
		terrain.lod_scale = p.terrain_lod
		terrain.apply_lod_ranges()
	var scatter := world.get_node_or_null("Scatter") as WorldScatter
	if scatter:
		scatter.lod_scale = p.scatter_lod


## Разрешение 3D, увеличение до экрана и сглаживание по уровню
static func apply_viewport(vp: Viewport, level: String) -> void:
	if vp == null:
		return
	var p := preset(level)
	var scale: float = p.scale
	var up := _arg("upscale", p.upscale) if scale < 1.0 else "bilinear"
	match up:
		"fsr2":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		"fsr1", "fsr":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		_:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale
	# FSR 1: резкость мягче обычной (0 — самая резкая) — мазки фильтра не «звенят»
	vp.fsr_sharpness = 0.4 if scale < 1.0 else ProjectSettings.get_setting("rendering/scaling_3d/fsr_sharpness", 0.2)
	var msaa: int = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0)
	if not bool(p.msaa) or up == "fsr2":
		msaa = Viewport.MSAA_DISABLED   # FSR 2 сглаживает сам; «Низкое» — FXAA
	if _has_arg("nomsaa"):
		msaa = Viewport.MSAA_DISABLED
	vp.msaa_3d = msaa
	var ssaa: int = ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa", 0)
	vp.screen_space_aa = ssaa if bool(p.msaa) or up == "fsr2" else Viewport.SCREEN_SPACE_AA_FXAA


## Название способа увеличения для экрана F9
static func upscale_name(vp: Viewport) -> String:
	if vp == null or vp.scaling_3d_scale >= 0.999:
		return "без увеличения"
	match vp.scaling_3d_mode:
		Viewport.SCALING_3D_MODE_FSR:
			return "FSR 1"
		Viewport.SCALING_3D_MODE_FSR2:
			return "FSR 2"
	return "билинейно"


## Автозагрузка Ordo (по пути: в безголовых проверках её имени не видно)
static func _ordo() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Ordo") if tree and tree.root else null


static func _has_arg(name: String) -> bool:
	var o := _ordo()
	return o != null and bool(o.call("has_arg", name))


static func _arg(name: String, default_value: String) -> String:
	var o := _ordo()
	return String(o.call("arg", name, default_value)) if o else default_value


## SSAO проще для «Среднего» (общая настройка сервера); «Высокое» — как в проекте
func _apply_ssao_quality(low: bool) -> void:
	var q: int = ProjectSettings.get_setting("rendering/environment/ssao/quality", 2)
	var half: bool = ProjectSettings.get_setting("rendering/environment/ssao/half_size", true)
	var target: float = ProjectSettings.get_setting("rendering/environment/ssao/adaptive_target", 0.5)
	var blur: int = ProjectSettings.get_setting("rendering/environment/ssao/blur_passes", 2)
	var f0: float = ProjectSettings.get_setting("rendering/environment/ssao/fadeout_from", 50.0)
	var f1: float = ProjectSettings.get_setting("rendering/environment/ssao/fadeout_to", 300.0)
	if low:
		q = RenderingServer.ENV_SSAO_QUALITY_LOW
		half = true
		blur = mini(blur, 1)
	RenderingServer.environment_set_ssao_quality(q, half, target, blur, f0, f1)
