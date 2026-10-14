class_name LightPresets
extends RefCounted
## Время суток мира — одно место для обоих вариантов света (решение автора 2026-10-14: свет мягче,
## по умолчанию «День», «Закат» — по выбору в главном меню). Ставит мир: World.apply_light(режим).
##
##   «День»  — солнце высоко (~48°) с юго-юго-запада, почти белый чуть тёплый ключевой свет, холодное
##             голубое заполнение неба, короткие мягкие тени, лёгкая дымка к горам, рисованные облака.
##   «Закат» — одобренный срез стиля: солнце на западе-юго-западе, 10°, тёплый свет, контровой свет,
##             небо заката; контраст ниже прежнего: тени светлее и цветнее, мягче кривая тона,
##             слабее контровой свет и тёплая полоса на границе света, тени облаков мягче.
##
## Разделы режима:
##   sun_*        — солнце (азимут: 0 — север, 90 — восток; высота, цвет, сила, сила в объёмном тумане);
##   env          — окружение (Environment: заполнение, кривая тона, туман, объёмный туман, свечение);
##   fog_*        — дымка, которую подменяет качество без объёмного тумана (apply_fog);
##   sky          — параметры рисованного неба (shaders/sky.gdshader);
##   terrain      — воздух, тени и тон земли (shaders/terrain.gdshader);
##   grass        — цвета травы (shaders/grass.gdshader, GrassField);
##   fog_banks    — туман в низинах и дымка над полем (FogBanks);
##   post         — живописный фильтр (PainterlyPost: подъём теней, тёплые света, виньетка);
##   globals      — общие живописные параметры ordo_* (shaders/include/painterly.gdshaderinc);
##   city         — поправки для «Города» (вид сверху): sun_elevation, clouds (сила теней облаков).
## Ключ --light=day|sunset — время суток для кадров (Ordo.light_mode).

const DAY := "day"
const SUNSET := "sunset"
const MODES := [DAY, SUNSET]
const NAMES := {DAY: "День", SUNSET: "Закат"}

## Ветер одинаков в обоих режимах (Ordo.wind — зеркало)
const WIND := Vector4(0.82, 0.35, 1.0, 0.55)

const PRESETS := {
	SUNSET: {
		"sun_azimuth": 247.5,
		"sun_elevation": 10.0,
		"sun_color": Color(1.0, 0.706, 0.431),
		"sun_energy": 2.6,
		"sun_fog_energy": 1.0,
		"env": {
			# заполнение ярче (0,75 → 1,4): теневая сторона юнитов и юрт читается и против солнца
			"ambient_light_color": Color(0.34, 0.47, 0.6),
			"ambient_light_energy": 1.4,
			"tonemap_exposure": 0.95,
			# мягче кривая тона (1,38 → 1,16) и общий контраст (1,12 → 1,04)
			"tonemap_agx_contrast": 1.16,
			"adjustment_contrast": 1.04,
			"adjustment_saturation": 1.06,
			"ssao_intensity": 0.85,
			"glow_intensity": 0.5,
			"fog_light_color": Color(0.42, 0.45, 0.56),
			"fog_light_energy": 0.75,
			"fog_aerial_perspective": 0.75,
			"volumetric_fog_density": 0.0007,
			"volumetric_fog_albedo": Color(0.62, 0.62, 0.64),
			"volumetric_fog_emission": Color(0.05, 0.08, 0.12),
			"volumetric_fog_anisotropy": 0.5,
			# заполнение ярче — дымка в объёмном тумане от него не должна молочнеть (было 0,5 при 0,75)
			"volumetric_fog_ambient_inject": 0.3,
		},
		# дымка: [с объёмным туманом, без него («Низкое»)]
		"fog_density": [0.0005, 0.0016],
		"fog_height_density": [0.025, 0.06],
		"fog_sun_scatter": [0.05, 0.25],
		# небо заката — как в срезе (значения шейдера по умолчанию)
		"sky": {
			"zenith_color": Color(0.025, 0.085, 0.16),
			"upper_color": Color(0.09, 0.26, 0.34),
			"horizon_sun": Color(1.0, 0.56, 0.26),
			"horizon_rose": Color(0.86, 0.47, 0.44),
			"horizon_cool": Color(0.38, 0.40, 0.55),
			"ground_haze": Color(0.22, 0.2, 0.22),
			"horizon_height": 0.1,
			"stroke_amount": 0.035,
			"sun_color": Color(1.0, 0.82, 0.58),
			"sun_energy": 16.0,
			"glow_energy": 0.95,
			"glow_tight": 90.0,
			"glow_wide": 7.0,
			"ray_strength": 0.4,
			"cloud_lit": Color(1.0, 0.56, 0.36),
			"cloud_gold": Color(1.0, 0.82, 0.5),
			"cloud_shade": Color(0.2, 0.2, 0.31),
			"cloud_far": Color(0.42, 0.33, 0.42),
			"cloud_cover": 0.49,
			"cloud_soft": 0.22,
			"mount_far": Color(0.50, 0.50, 0.66),
			"mount_mid": Color(0.30, 0.31, 0.47),
			"mount_near": Color(0.17, 0.18, 0.28),
			"snow_lit": Color(0.98, 0.7, 0.6),
			"snow_shade": Color(0.56, 0.60, 0.78),
			"mount_haze": 0.62,
		},
		"terrain": {
			"air_warm": Color(0.98, 0.6, 0.42),
			"air_cool": Color(0.33, 0.38, 0.55),
			"air_energy": 0.42,
			"air_amount": 0.8,
			# против солнца земля темнела на 70 % — теперь на 50 % (меньше контраста в контражуре)
			"backlit_dim": 0.5,
			"grazing_dim": 0.4,
			"shadow_paint": Color(0.28, 0.35, 0.5, 0.045),
			"ground_value": 0.88,
			"ground_saturation": 0.9,
			"tint_grass": Color(1.0, 1.16, 0.88),
			"tint_rock": Color(0.92, 0.92, 0.95),
			"macro_warm": Color(1.08, 0.98, 0.8),
			"macro_amount": 0.55,
		},
		# трава (цвета по высоте травинки) — как в срезе
		"grass": {
			"base_color": Color(0.17, 0.19, 0.11),
			"mid_color": Color(0.33, 0.36, 0.2),
			"tip_color": Color(0.5, 0.5, 0.29),
			"cool_tip": Color(0.4, 0.47, 0.37),
			"dry_tip": Color(0.68, 0.57, 0.34),
		},
		"fog_banks": {
			"density": 0.014,
			"albedo": Color(0.86, 0.88, 0.92),
			"emission": Color(0.02, 0.03, 0.045),
			"haze_density": 0.0038,
			"haze_albedo": Color(0.95, 0.86, 0.76),
		},
		"post": {
			"shadow_lift": Color(0.02, 0.034, 0.05, 1.0),
			"shadow_range": 0.08,
			"highlight_warm": Color(1.05, 0.98, 0.88, 0.5),
			"vignette": 0.26,
		},
		"globals": {
			"ordo_key_tint": Color(1.0, 0.92, 0.82),
			# тень светлее и голубее (0,17 0,27 0,44 → 0,24 0,33 0,5)
			"ordo_shadow_tint": Color(0.24, 0.33, 0.5),
			# тёплая полоса на границе света и контровой свет слабее (0,42 → 0,24; 0,95 → 0,28):
			# против солнца юниты — не тёмные силуэты с горящими оранжевыми гранями
			"ordo_terminator": Color(0.95, 0.42, 0.24, 0.24),
			"ordo_rim_color": Color(1.0, 0.8, 0.56, 0.28),
			"ordo_band_soft": 0.16,
			"ordo_brush_amount": 0.38,
			"ordo_brush_scale": 0.9,
			# тени облаков: сила (0,6 → 0,42), масштаб (1/м — пятна ~60–90 м), снос по ветру (м/с)
			"ordo_clouds": Vector4(0.42, 0.011, 1.4, 0.6),
		},
		# «Город» сверху: солнце выше (короче тени построек, светлее лагерь у западных гор), облака слабее
		"city": {"sun_elevation": 16.0, "clouds": 0.25},
	},
	DAY: {
		"sun_azimuth": 210.0,
		"sun_elevation": 48.0,
		"sun_color": Color(1.0, 0.93, 0.8),
		"sun_energy": 2.3,
		"sun_fog_energy": 0.45,
		"env": {
			"ambient_light_color": Color(0.46, 0.58, 0.76),
			"ambient_light_energy": 0.8,
			"tonemap_exposure": 0.98,
			"tonemap_agx_contrast": 1.18,
			"adjustment_contrast": 1.03,
			"adjustment_saturation": 1.05,
			"ssao_intensity": 0.9,
			"glow_intensity": 0.3,
			"fog_light_color": Color(0.64, 0.72, 0.84),
			"fog_light_energy": 0.9,
			"fog_aerial_perspective": 0.6,
			"volumetric_fog_density": 0.0004,
			"volumetric_fog_albedo": Color(0.82, 0.84, 0.87),
			"volumetric_fog_emission": Color(0.05, 0.07, 0.1),
			"volumetric_fog_anisotropy": 0.3,
			"volumetric_fog_ambient_inject": 0.4,
		},
		"fog_density": [0.0004, 0.0011],
		"fog_height_density": [0.012, 0.03],
		"fog_sun_scatter": [0.02, 0.1],
		# рисованное голубое небо: светлая дымка у горизонта, белые кучевые облака мазками
		# (тело облака — белое, низ — серо-сиреневый: шейдер подсвечивает нижнюю кромку цветом cloud_lit)
		"sky": {
			"zenith_color": Color(0.13, 0.32, 0.62),
			"upper_color": Color(0.3, 0.52, 0.8),
			"horizon_sun": Color(0.93, 0.88, 0.78),
			"horizon_rose": Color(0.76, 0.8, 0.86),
			"horizon_cool": Color(0.66, 0.76, 0.88),
			"ground_haze": Color(0.42, 0.45, 0.48),
			"horizon_height": 0.14,
			"stroke_amount": 0.05,
			"sun_color": Color(1.0, 0.97, 0.9),
			"sun_energy": 10.0,
			"glow_energy": 0.5,
			"glow_tight": 120.0,
			"glow_wide": 6.0,
			"ray_strength": 0.0,
			"cloud_lit": Color(0.68, 0.72, 0.84),
			"cloud_gold": Color(0.95, 0.95, 0.93),
			"cloud_shade": Color(0.97, 0.97, 1.0),
			"cloud_far": Color(0.86, 0.88, 0.93),
			"cloud_cover": 0.47,
			"cloud_soft": 0.24,
			"mount_far": Color(0.62, 0.68, 0.8),
			"mount_mid": Color(0.48, 0.55, 0.67),
			"mount_near": Color(0.36, 0.42, 0.5),
			"snow_lit": Color(0.9, 0.92, 0.96),
			"snow_shade": Color(0.68, 0.75, 0.88),
			"mount_haze": 0.6,
		},
		"terrain": {
			# дымка к горам голубая, не серая (воздушная перспектива живописцев), и тоньше
			"air_warm": Color(0.84, 0.8, 0.72),
			"air_cool": Color(0.5, 0.62, 0.82),
			"air_energy": 0.45,
			"air_amount": 0.62,
			"backlit_dim": 0.35,
			"grazing_dim": 0.3,
			"shadow_paint": Color(0.32, 0.4, 0.55, 0.05),
			# земля под высоким солнцем спокойнее и темнее юнитов (ТЗ 11.2): олива и охра, не газон
			"ground_value": 0.8,
			"ground_saturation": 0.82,
			"tint_grass": Color(0.98, 1.06, 0.82),
			"tint_rock": Color(1.0, 0.94, 0.86),
			"macro_warm": Color(1.1, 0.97, 0.76),
			"macro_amount": 0.65,
		},
		"grass": {
			"base_color": Color(0.15, 0.17, 0.1),
			"mid_color": Color(0.29, 0.31, 0.17),
			"tip_color": Color(0.46, 0.45, 0.26),
			"cool_tip": Color(0.37, 0.42, 0.33),
			"dry_tip": Color(0.64, 0.53, 0.32),
		},
		"fog_banks": {
			"density": 0.006,
			"albedo": Color(0.9, 0.92, 0.95),
			"emission": Color(0.03, 0.04, 0.05),
			"haze_density": 0.0022,
			"haze_albedo": Color(0.9, 0.9, 0.88),
		},
		"post": {
			"shadow_lift": Color(0.024, 0.034, 0.045, 1.0),
			"shadow_range": 0.08,
			"highlight_warm": Color(1.02, 1.0, 0.96, 0.4),
			"vignette": 0.22,
		},
		"globals": {
			"ordo_key_tint": Color(1.0, 0.98, 0.93),
			"ordo_shadow_tint": Color(0.3, 0.4, 0.56),
			"ordo_terminator": Color(0.95, 0.6, 0.38, 0.18),
			"ordo_rim_color": Color(1.0, 0.95, 0.86, 0.35),
			"ordo_band_soft": 0.18,
			"ordo_brush_amount": 0.36,
			"ordo_brush_scale": 0.9,
			"ordo_clouds": Vector4(0.3, 0.009, 1.4, 0.6),
		},
		"city": {},
	},
}


## Числа режима (неизвестный — «День»)
static func preset(mode: String) -> Dictionary:
	return PRESETS.get(mode, PRESETS[DAY])


static func mode_name(mode: String) -> String:
	return NAMES.get(mode, mode)


## Текущий режим — Ordo.light_mode (по пути: в безголовых проверках имени автозагрузки не видно); нет — «День»
static func current_mode() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var o: Node = tree.root.get_node_or_null("Ordo") if tree and tree.root else null
	if o == null:
		return DAY
	var m := String(o.get("light_mode"))
	return m if m in MODES else DAY


## Высота солнца и сила теней облаков режима; city — поправки «Города» (вид сверху)
static func sun_elevation(mode: String, city := false) -> float:
	var p := preset(mode)
	var c: Dictionary = p.get("city", {}) if city else {}
	return float(c.get("sun_elevation", p.sun_elevation))


static func clouds(mode: String, city := false) -> Vector4:
	var p := preset(mode)
	var v: Vector4 = p.globals.ordo_clouds
	if city and (p.get("city", {}) as Dictionary).has("clouds"):
		v.x = float(p.city.clouds)
	return v


## Общие живописные параметры ordo_* режима (с ветром и тенями облаков; city — поправки «Города»)
static func globals(mode: String, city := false) -> Dictionary:
	var g: Dictionary = (preset(mode).globals as Dictionary).duplicate()
	g["ordo_wind"] = WIND
	g["ordo_clouds"] = clouds(mode, city)
	return g


## Дымка окружения: с объёмным туманом — своя, без него («Низкое») — гуще (WorldQuality.apply, World.apply_light)
static func apply_fog(env: Environment, mode: String, volfog: bool) -> void:
	if env == null:
		return
	var p := preset(mode)
	var i := 0 if volfog else 1
	env.fog_density = float(p.fog_density[i])
	env.fog_height_density = float(p.fog_height_density[i])
	env.fog_sun_scatter = float(p.fog_sun_scatter[i])
