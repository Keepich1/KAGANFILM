extends SceneTree
## Время суток (решение автора 2026-10-14: «День» по умолчанию, «Закат» по выбору, свет мягче):
##   godot --headless --path ordo --script res://tests/test_light_mode.gd
## Числа обоих режимов (LightPresets), выбор игрока в автозагрузке Ordo: по умолчанию «День», ключ --light,
## запоминание в файле настроек (при съёмке — нет), мир ставит свет режима при запуске и сразу при смене,
## «Город» — поправки вида сверху только у заката, дымка «Низкого» качества — по режиму.
## Свои экземпляры Ordo пишут во временный файл настроек — настройки игрока не трогаются.

const ORDO := "res://scripts/core/ordo.gd"
const WORLD := "res://scenes/world/world.tscn"

var _fails := 0
var _tmp := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	# автозагрузка Ordo появляется в дереве к первому кадру
	await process_frame
	_tmp = OS.get_cache_dir().path_join("ordo_test_light_%d.cfg" % OS.get_process_id())
	_check_presets()
	await _check_ordo()
	await _check_world()
	DirAccess.remove_absolute(_tmp)
	print("")
	print("ИТОГ: ", "ВСЁ ПРОШЛО" if _fails == 0 else "ПРОВАЛОВ: %d" % _fails)
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _check_presets() -> void:
	print("[числа режимов]")
	var keys := ["sun_azimuth", "sun_elevation", "sun_color", "sun_energy", "sun_fog_energy", "env", "fog_density",
		"fog_height_density", "fog_sun_scatter", "sky", "terrain", "grass", "fog_banks", "post", "globals", "city"]
	for mode: String in LightPresets.MODES:
		var p := LightPresets.preset(mode)
		var missing: Array = keys.filter(func(k: String) -> bool: return not p.has(k))
		_check(missing.is_empty(), "%s: все разделы на месте %s" % [mode, missing])
	var day := LightPresets.preset(LightPresets.DAY)
	var dusk := LightPresets.preset(LightPresets.SUNSET)
	# одинаковый набор ключей: смена режима ставит каждый параметр, ничего не остаётся от другого режима
	for sec in ["env", "sky", "terrain", "grass", "fog_banks", "post", "globals"]:
		var a: Array = (day[sec] as Dictionary).keys()
		var b: Array = (dusk[sec] as Dictionary).keys()
		a.sort()
		b.sort()
		_check(a == b, "%s: одни и те же параметры у дня и заката" % sec)
	_check(LightPresets.preset("нет такого") == day, "неизвестный режим — «День»")
	_check(LightPresets.mode_name(LightPresets.DAY) == "День" and LightPresets.mode_name(LightPresets.SUNSET) == "Закат",
		"названия «День» и «Закат»")
	var del := float(day.sun_elevation)
	_check(del >= 45.0 and del <= 55.0, "день: солнце высоко (%.0f°)" % del)
	_check(is_equal_approx(float(dusk.sun_elevation), 10.0) and is_equal_approx(float(dusk.sun_azimuth), 247.5),
		"закат: солнце как в срезе (запад-юго-запад, 10°)")
	var dc: Color = day.sun_color
	_check(dc.r >= dc.g and dc.g >= dc.b and dc.b > 0.8, "день: свет почти белый, чуть тёплый")
	print("[контраст ниже прежнего (до 2026-10-14: заполнение 0,75, кривая 1,38, контраст 1,12, контровой 0,95,")
	print("  полоса 0,42, тени облаков 0,6, тень 0,17 0,27 0,44)]")
	for mode: String in LightPresets.MODES:
		var p := LightPresets.preset(mode)
		var e: Dictionary = p.env
		var g: Dictionary = p.globals
		_check(float(e.tonemap_agx_contrast) < 1.38 and float(e.adjustment_contrast) < 1.12, "%s: кривая тона мягче" % mode)
		_check((g.ordo_rim_color as Color).a < 0.95 and (g.ordo_terminator as Color).a < 0.42,
			"%s: контровой свет и тёплая полоса слабее" % mode)
		_check((g.ordo_clouds as Vector4).x < 0.6, "%s: тени облаков мягче" % mode)
		var st: Color = g.ordo_shadow_tint
		_check(st.get_luminance() > Color(0.17, 0.27, 0.44).get_luminance(), "%s: цветная тень светлее" % mode)
		# тень цветная, не серая и не чёрная: синий канал заметно выше красного
		_check(st.b > st.r + 0.15, "%s: тень холодная, цветная" % mode)
		var amb := (e.ambient_light_color as Color).get_luminance() * float(e.ambient_light_energy)
		_check(amb > Color(0.29, 0.47, 0.6).get_luminance() * 0.75, "%s: заполнение неба ярче (%.2f)" % [mode, amb])
	# контровой свет — не больше 0,4 (было 0,95): против солнца юниты без горящих оранжевых граней
	for mode: String in LightPresets.MODES:
		_check((LightPresets.preset(mode).globals.ordo_rim_color as Color).a <= 0.4, "%s: контровой свет ≤ 0,4" % mode)
	# днём ключевой свет почти белый, на закате — тёплый
	_check((day.globals.ordo_key_tint as Color).b > (dusk.globals.ordo_key_tint as Color).b, "днём свет белее, чем на закате")
	print("[«Город»: поправки вида сверху]")
	_check(is_equal_approx(LightPresets.sun_elevation(LightPresets.SUNSET, true), 16.0), "закат в «Городе»: солнце 16°")
	_check(LightPresets.clouds(LightPresets.SUNSET, true).x < LightPresets.clouds(LightPresets.SUNSET).x,
		"закат в «Городе»: тени облаков слабее, чем в срезе")
	_check(is_equal_approx(LightPresets.sun_elevation(LightPresets.DAY, true), float(day.sun_elevation))
		and LightPresets.clouds(LightPresets.DAY, true) == LightPresets.clouds(LightPresets.DAY),
		"день в «Городе» — без поправок")
	var gl := LightPresets.globals(LightPresets.DAY)
	_check(gl.has("ordo_wind") and gl.has("ordo_clouds") and gl.has("ordo_key_tint"), "общие ordo_* с ветром и облаками")
	print("[дымка по качеству]")
	var env := Environment.new()
	for mode: String in LightPresets.MODES:
		LightPresets.apply_fog(env, mode, true)
		var thin := env.fog_density
		LightPresets.apply_fog(env, mode, false)
		_check(env.fog_density > thin, "%s: без объёмного тумана («Низкое») дымка гуще" % mode)


## Свой экземпляр автозагрузки: временный файл настроек, свои ключи (как из командной строки)
func _make_ordo(args: Dictionary) -> Node:
	var o: Node = (load(ORDO) as GDScript).new()
	o.name = "OrdoTest"
	o.set("settings_path", _tmp)
	o.set("_args", args.duplicate())
	o.set("process_mode", Node.PROCESS_MODE_DISABLED)
	root.add_child(o)
	return o


func _saved_light() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(_tmp) != OK:
		return ""
	return String(cfg.get_value("graphics", "light", ""))


func _check_ordo() -> void:
	print("[выбор игрока: Ordo.light_mode]")
	DirAccess.remove_absolute(_tmp)
	var o := _make_ordo({})
	_check(String(o.get("light_mode")) == "day" and String(o.get("light_source")) == "default",
		"новый игрок — «День»")
	var got: Array = []
	o.connect("light_mode_changed", func(m: String) -> void: got.append(m))
	o.call("set_light_mode", "sunset")
	_check(String(o.get("light_mode")) == "sunset" and got == ["sunset"], "смена на «Закат» — сигнал light_mode_changed")
	_check(_saved_light() == "sunset", "выбор записан в файл настроек")
	o.call("set_light_mode", "sunset")
	_check(got.size() == 1, "тот же режим ещё раз — без лишнего сигнала")
	o.call("set_light_mode", "полдень")
	_check(String(o.get("light_mode")) == "day", "неизвестный режим — «День»")
	o.call("set_light_mode", "sunset")
	o.free()
	var o2 := _make_ordo({})
	_check(String(o2.get("light_mode")) == "sunset" and String(o2.get("light_source")) == "saved",
		"при следующем запуске — сохранённый «Закат»")
	o2.call("set_light_mode", "day", false)
	_check(_saved_light() == "sunset", "remember=false — файл не трогается")
	o2.free()
	var o3 := _make_ordo({"light": "day"})
	_check(String(o3.get("light_mode")) == "day" and String(o3.get("light_source")) == "arg",
		"ключ --light=day сильнее сохранённого")
	o3.call("set_light_mode", "sunset")
	o3.call("set_light_mode", "day")
	_check(_saved_light() == "sunset", "с ключом --light выбор не запоминается")
	o3.free()
	var o4 := _make_ordo({"light": "sunset"})
	_check(String(o4.get("light_mode")) == "sunset", "ключ --light=sunset")
	o4.free()
	DirAccess.remove_absolute(_tmp)
	var o5 := _make_ordo({"shot": "/dev/null", "at": "999"})
	_check(String(o5.get("light_mode")) == "day", "съёмка без ключа — «День»")
	o5.call("set_light_mode", "sunset")
	_check(_saved_light() == "", "при съёмке выбор не пишется")
	o5.free()
	var o6 := _make_ordo({"light": "вечер"})
	_check(String(o6.get("light_mode")) == "day", "ключ с неизвестным режимом — «День»")
	o6.free()
	await process_frame


func _check_world() -> void:
	print("[мир ставит свет режима]")
	var ordo := root.get_node_or_null("Ordo")
	_check(ordo != null, "автозагрузка Ordo в дереве")
	if ordo == null:
		return
	var was := String(ordo.get("light_mode"))
	ordo.call("set_light_mode", "day", false)
	var w: World = (load(WORLD) as PackedScene).instantiate()
	root.add_child(w)
	await process_frame
	_check_world_mode(w, "day", false)
	# меню переключает на лету: мир слушает light_mode_changed
	ordo.call("set_light_mode", "sunset", false)
	_check_world_mode(w, "sunset", false)
	print("[«Город»: city_light]")
	w.city_light = true
	w.apply_light()
	_check(is_equal_approx(w.sun_elevation, 16.0), "закат в «Городе»: солнце 16°")
	_check(absf(World.sun_direction().y - sin(deg_to_rad(16.0))) < 1e-3, "направление на солнце — по 16°")
	ordo.call("set_light_mode", "day", false)
	_check_world_mode(w, "day", true)
	print("[качество не сбивает дымку режима]")
	var q := w.get_node("Quality") as WorldQuality
	for lv: String in ["low", "high"]:
		q.apply(lv)
		var volfog := bool(WorldQuality.preset(lv).volfog)
		var want: float = LightPresets.preset("day").fog_density[0 if volfog else 1]
		_check(is_equal_approx(w.environment_node.environment.fog_density, want), "день, «%s»: дымка дня" % lv)
	w.queue_free()
	await process_frame
	ordo.call("set_light_mode", was if was != "" else "day", false)


func _check_world_mode(w: World, mode: String, city: bool) -> void:
	var p := LightPresets.preset(mode)
	_check(w.light_mode == mode, "%s: мир в режиме" % mode)
	_check(is_equal_approx(w.sun.light_energy, float(p.sun_energy)) and w.sun.light_color.is_equal_approx(p.sun_color),
		"%s: сила и цвет солнца" % mode)
	var el := LightPresets.sun_elevation(mode, city)
	_check(absf(World.sun_direction().y - sin(deg_to_rad(el))) < 1e-3, "%s: высота солнца %.0f°" % [mode, el])
	var o := root.get_node("Ordo")
	_check((o.get("sun_dir") as Vector3).is_equal_approx(World.sun_direction()), "%s: Ordo.sun_dir — то же солнце" % mode)
	var env := w.environment_node.environment
	_check(is_equal_approx(env.ambient_light_energy, float(p.env.ambient_light_energy))
		and is_equal_approx(env.tonemap_agx_contrast, float(p.env.tonemap_agx_contrast)), "%s: заполнение и кривая тона" % mode)
	var sky := env.sky.sky_material as ShaderMaterial
	_check((sky.get_shader_parameter("zenith_color") as Color).is_equal_approx(p.sky.zenith_color)
		and (sky.get_shader_parameter("cloud_lit") as Color).is_equal_approx(p.sky.cloud_lit), "%s: небо" % mode)
	_check((w.terrain.material.get_shader_parameter("air_warm") as Color).is_equal_approx(p.terrain.air_warm),
		"%s: воздух земли" % mode)
	var post := w.painterly_post()
	_check(post != null and is_equal_approx(post.vignette, float(p.post.vignette)), "%s: живописный фильтр" % mode)
	var banks := w.get_node("FogBanks") as FogBanks
	_check(is_equal_approx(banks.density, float(p.fog_banks.density)), "%s: туман в низинах" % mode)
