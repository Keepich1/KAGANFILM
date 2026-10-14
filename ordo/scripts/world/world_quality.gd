class_name WorldQuality
extends Node
## Режимы качества мира (ТЗ 11.7). Слушает Ordo.quality и Ordo.quality_changed.
##   «Высокое» (ПК): полный свет, мягкие тени на 4 каскада, объёмный туман с лучами,
##                   живописный фильтр, густая трава, подробные модели дальше. Вид как в срезе;
##                   дешевле то, чего не видно (кадры до/после — отчёт perf2): живописный фильтр
##                   на мониторе выше 1080p считается в кадре 1080 точек по высоте и бережно
##                   увеличивается (на 1080p — прежний полный путь); сглаживание SMAA вместо MSAA 4×
##                   (настройка проекта: глубина и цвет кадра хранились вчетверо; цена — тонкие ости
##                   травы вблизи пунктиром, MSAA 4× их размывал, а MSAA 2× — нет; --aa=msaa вернёт прежнее);
##                   карта теней 4096 вместо 8192 (размытие тени вдвое меньше в точках карты —
##                   та же мягкость в метрах); сетка тумана 128 × 128 × 64 слоя в глубину (было 128);
##                   тень юнита рисуется только в тех каскадах солнца, куда она падает (не во всех четырёх).
##   «Среднее» (ПК попроще): тот же вид дешевле — живописный фильтр в половине разрешения
##                   с бережным увеличением, сетка тумана реже, тени те же 4 каскада, но карта
##                   вдвое меньше и ближе (500 м), SSAO проще, травы меньше, кадр 3D 77 % (FSR 1).
##   «Низкое» (слабые ПК, телефоны): кадр 3D ~2/3 экрана (FSR 1), тени 2 каскада и ближе,
##                   без объёмного тумана (обычная дымка гуще), без SSAO и MSAA (FXAA),
##                   живописный фильтр в половине разрешения, травы втрое меньше, LOD раньше.
## Узел ищет соседей по именам в сцене мира: Environment, Sun, Terrain, Grass, Scatter.
##
## Для других областей: WorldQuality.preset(уровень) — числа уровня (толпа: crowd_lod,
## crowd_lod1_shadow, crowd_shadow — дальность теней юнитов, м; эффекты: fx), WorldQuality.level_name(), next_level() (F2),
## auto_level() — выбор по видеокарте при первом запуске (Ordo запоминает выбор игрока).
## Ключи сравнения (автору — проверить на своём ПК с F9, что дала каждая мера, и вернуть прежнее):
##   --upscale=fsr1|fsr2|bilinear — способ увеличения; --post=full|half|off — живописный фильтр;
##   --post_cap=0 — фильтр «Высокого» в полном кадре на любом мониторе (как было), --post_cap=1440 — до 1440p;
##   --post_detail=1 — мелочь при увеличении мазков не закрывать (как у «Среднего»), 0 — закрывать целиком;
##   --aa=msaa|msaa2|smaa|fxaa|off — сглаживание (msaa — 4×, как было);
##   --shadow_atlas=8192 — карта теней (размытие подстраивается); --fog_grid=128 --fog_depth=128 — сетка тумана;
##   --shadow_soft=medium — мягкая тень дешевле (вдвое меньше выборок; «Высокое» — high);
##   --crowd_cascades=all — тени юнитов во всех каскадах солнца, как было; --crowd_shadow=126 — дальность
##   теней юнитов, м; --crowd_lod=90 — дальность смены LOD юнитов, м (CrowdLayer).

const HIGH := "high"
const MEDIUM := "medium"
const LOW := "low"
## Порядок F2: «Высокое» → «Среднее» → «Низкое» → «Высокое»
const LEVELS := [HIGH, MEDIUM, LOW]
const NAMES := {HIGH: "Высокое", MEDIUM: "Среднее", LOW: "Низкое"}

## Числа уровней. scale — доля разрешения 3D, upscale — как растянуть до экрана; aa — сглаживание:
## msaa (MSAA из настроек проекта, 4×) / smaa / fxaa; post — живописный фильтр: full / half (половина
## разрешения) / off; post_cap — кадр выше стольких точек фильтр считает уменьшенным до этой высоты
## (0 — без предела); post_detail — мелочь, которой нет в уменьшенном кадре: 1 — исходная точка
## («Среднее», «Низкое», как было), меньше — её наполовину закрывает мазок, как Кувахара полного кадра
## («Высокое»: уменьшенный кадр ближе к прежнему полному); shadow_atlas — сторона карты теней солнца (размытие тени в точках карты
## подстраивается: та же мягкость в метрах, что у 8192 со значением сцены).
const PRESETS := {
	HIGH: {
		"scale": 1.0, "upscale": "bilinear", "aa": "smaa",
		"post": "full", "post_cap": 1080, "post_detail": 0.5, "volfog": true, "fog_grid": 128, "fog_depth": 64, "ssao": true, "ssao_low": false,
		"shadow_splits": 4, "shadow_dist": 700.0, "shadow_atlas": 4096, "shadow_soft": "high",
		"grass_density": 1.0, "grass_range": 1.0, "terrain_lod": 1.0, "scatter_lod": 1.0,
		"crowd_lod": 1.0, "crowd_lod1_shadow": true, "crowd_shadow": 700.0, "fx": 1.0,
	},
	MEDIUM: {
		"scale": 0.77, "upscale": "fsr1", "aa": "msaa",
		"post": "half", "post_cap": 0, "post_detail": 1.0, "volfog": true, "fog_grid": 96, "fog_depth": 64, "ssao": true, "ssao_low": true,
		"shadow_splits": 4, "shadow_dist": 500.0, "shadow_atlas": 4096, "shadow_soft": "low",
		"grass_density": 0.6, "grass_range": 0.85, "terrain_lod": 0.8, "scatter_lod": 0.8,
		"crowd_lod": 0.75, "crowd_lod1_shadow": true, "crowd_shadow": 500.0, "fx": 0.75,
	},
	LOW: {
		"scale": 0.67, "upscale": "fsr1", "aa": "fxaa",
		"post": "half", "post_cap": 0, "post_detail": 1.0, "volfog": false, "fog_grid": 64, "fog_depth": 48, "ssao": false, "ssao_low": true,
		"shadow_splits": 2, "shadow_dist": 320.0, "shadow_atlas": 4096, "shadow_soft": "low",
		"grass_density": 0.33, "grass_range": 0.6, "terrain_lod": 0.6, "scatter_lod": 0.6,
		"crowd_lod": 0.5, "crowd_lod1_shadow": false, "crowd_shadow": 60.0, "fx": 0.5,
	},
}

@export var world_path := NodePath("..")

## Что применено последним apply() (экран F9: pixel_summary)
static var applied_atlas := 0
static var applied_soft := ""
static var applied_fog := Vector3i.ZERO


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
		# без объёмного тумана низинам нужна обычная высотная дымка погуще (числа — по времени суток)
		LightPresets.apply_fog(env, String(world.get("light_mode")) if world.get("light_mode") else LightPresets.current_mode(), volfog)
		if we.compositor:
			# --post=full|half|off и --post_cap=N подменяют живописный фильтр уровня (сравнение кадров, F9)
			var post := _arg("post", String(p.post))
			for e in we.compositor.compositor_effects:
				if e is PainterlyPost:
					e.enabled = post != "off" and not _has_arg("nopost")
					e.half_res = post == "half"
					e.max_height = int(_arg("post_cap", str(p.get("post_cap", 0))))
					e.detail_keep = float(_arg("post_detail", str(p.get("post_detail", 1.0))))
	var atlas := int(_arg("shadow_atlas", str(p.shadow_atlas)))
	if sun:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(p.shadow_splits) == 4 \
			else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = p.shadow_dist
		if not sun.has_meta("blur_8192"):
			sun.set_meta("blur_8192", sun.shadow_blur)
		sun.shadow_blur = shadow_blur_for(float(sun.get_meta("blur_8192")), atlas, level)
	RenderingServer.directional_shadow_atlas_set_size(atlas, true)
	applied_atlas = atlas
	# сетка объёмного тумана подробнее поперёк взгляда: лучи сквозь деревья и юрты читаются чётче;
	# в глубину хватает 64 слоёв (накопление по кадрам сглаживает) — вдвое дешевле прежних 128
	var fog_grid := int(_arg("fog_grid", str(p.fog_grid)))
	var fog_depth := int(_arg("fog_depth", str(p.get("fog_depth", p.fog_grid))))
	RenderingServer.environment_set_volumetric_fog_volume_size(fog_grid, fog_depth)
	applied_fog = Vector3i(fog_grid, fog_grid, fog_depth) if we and we.environment.volumetric_fog_enabled else Vector3i.ZERO
	var soft := RenderingServer.SHADOW_QUALITY_SOFT_HIGH
	# --shadow_soft=medium|low|… подменяет фильтр мягкой тени уровня (сравнение на F9: выборок на точку кадра)
	applied_soft = _arg("shadow_soft", String(p.shadow_soft))
	match applied_soft:
		"medium":
			soft = RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
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


## Размытие тени солнца для карты стороной atlas. Размытие задаётся в точках карты, поэтому карта
## вдвое меньше размыла бы тень вдвое шире в метрах: «Высокое» делит его — мягкость тени в метрах та же,
## что у прежней карты 8192 (blur_8192 — значение сцены). «Среднее» и «Низкое» — как было (значение сцены).
static func shadow_blur_for(blur_8192: float, atlas: int, level: String) -> float:
	if level != HIGH or atlas >= 8192 or atlas <= 0:
		return blur_8192
	return blur_8192 * float(atlas) / 8192.0


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
	var aa := aa_mode(level, up)
	# msaa — как в настройках проекта (4×), msaa2 / msaa4 — явно (сравнение)
	var msaa: int = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0)
	match aa:
		"msaa2":
			msaa = Viewport.MSAA_2X
		"msaa4":
			msaa = Viewport.MSAA_4X
	vp.msaa_3d = msaa if aa.begins_with("msaa") and not _has_arg("nomsaa") else Viewport.MSAA_DISABLED
	match aa:
		"smaa":
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
		"fxaa":
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		"msaa", "msaa2", "msaa4":
			vp.screen_space_aa = ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa", 0)
		_:
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED


## Сглаживание уровня: msaa (как в проекте, 4×) / msaa2 / msaa4 / smaa / fxaa / off
## (--aa=… подменяет; FSR 2 сглаживает сам — off)
static func aa_mode(level: String, upscale: String = "") -> String:
	if upscale == "fsr2":
		return "off"
	return _arg("aa", String(preset(level).get("aa", "msaa")))


## Цена точки кадра для экрана F9: сглаживание, в каком кадре живописный фильтр, карта теней, туман
## (то, что подменяют ключи сравнения --aa, --post, --post_cap, --shadow_atlas, --fog_grid, --fog_depth)
static func pixel_summary(vp: Viewport, post: PainterlyPost) -> String:
	if vp == null:
		return ""
	var aa := "без сглаживания"
	if vp.msaa_3d != Viewport.MSAA_DISABLED:
		aa = "MSAA %d×" % (1 << int(vp.msaa_3d))
	elif vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA:
		aa = "SMAA"
	elif vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA:
		aa = "FXAA"
	var internal := Vector2i((Vector2(vp.get_visible_rect().size) * vp.scaling_3d_scale).round())
	var paint := "фильтр выкл."
	if post and post.enabled and internal.y > 0:
		var k := post.work_scale(internal.y)
		var w := PainterlyPost.work_size(internal, k) if k < 1.0 else internal
		paint = "фильтр %d×%d" % [w.x, w.y]
	var fog := "туман %d×%d×%d" % [applied_fog.x, applied_fog.y, applied_fog.z] if applied_fog != Vector3i.ZERO \
		else "без объёмного тумана"
	return "%s · %s · тени %d (%s) · %s" % [aa, paint, applied_atlas, applied_soft, fog]


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
