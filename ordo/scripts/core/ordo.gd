extends Node
## Общие службы среза: качество графики и съёмка кадров из командной строки.
##
## Кадр без монитора (см. tools/shot.sh):
##   godot --path ordo --fixed-fps 30 res://scenes/slice.tscn -- --shot=out.png --at=6 --cam=CamCamp
## Параметры после «--»:
##   --shot=путь.png   сохранить кадр и выйти
##   --at=секунды      момент кадра по времени сцены (по умолчанию 1.0)
##   --cam=Имя         сделать текущей камеру Camera3D с этим именем
##   --quality=high|medium|low  режим качества (ТЗ 11.7; не запоминается)
##   --seed=N          зерно случайностей сцены
## Качество: выбор игрока (F2) хранится в user://settings.cfg; при первом запуске —
## по видеокарте (WorldQuality.auto_level). Съёмка (--shot, --movie, --hero) — всегда «Высокое»,
## если не задано --quality, и настройки не читает и не пишет.

signal quality_changed(level: String)

const QUALITY_HIGH := "high"
const QUALITY_MEDIUM := "medium"
const QUALITY_LOW := "low"
const SETTINGS_PATH := "user://settings.cfg"
## Главное меню (сцена по умолчанию проекта)
const MENU_SCENE := "res://scenes/menu/main_menu.tscn"

var quality := QUALITY_HIGH
## Откуда качество: arg (ключ), saved (выбор игрока), auto (по видеокарте), shot (съёмка), mobile
var quality_source := "default"
var seed := 1
var scene_time := 0.0
## Громкость (главная шина, 0..1) и окно во весь экран — настройки игрока (главное меню)
var volume := 0.8
var fullscreen := false
## Живой ветер — зеркало global ordo_wind (RenderingServer отдаёт глобальные uniform только
## в редакторе): xy — куда дует по мировым x/z, z — сила (×6 м/с), w — порывистость.
## Менять через set_wind(), чтобы шейдеры и эффекты на процессоре видели одно и то же.
var wind := Vector4(0.82, 0.35, 1.0, 0.55)
## Направление НА солнце — зеркало global ordo_sun_dir (ставит мир, World.place_sun)
var sun_dir := Vector3(-0.91, 0.17, 0.38)

var _shot_path := ""
var _shot_at := 1.0
var _cam_name := ""
var _args := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_shot_path = _args.get("shot", "")
	_shot_at = float(_args.get("at", "1.0"))
	_cam_name = _args.get("cam", "")
	seed = int(_args.get("seed", "1"))
	var g: Variant = ProjectSettings.get_setting("shader_globals/ordo_wind", {})
	if g is Dictionary and (g as Dictionary).get("value") is Vector4:
		wind = (g as Dictionary)["value"]
	if not _capturing():
		_load_prefs()
	if _args.has("quality"):
		quality = _args["quality"]
		quality_source = "arg"
	elif _capturing():
		quality_source = "shot"
	else:
		var saved := _load_quality()
		if saved != "":
			quality = saved
			quality_source = "saved"
		elif OS.has_feature("mobile"):
			quality = QUALITY_LOW
			quality_source = "mobile"
		else:
			quality = WorldQuality.auto_level()
			quality_source = "auto"


func arg(name: String, default_value := "") -> String:
	return _args.get(name, default_value)


func has_arg(name: String) -> bool:
	return _args.has(name)


## Ключ запуска из кода (главное меню → «Город»: faction, seed): сцена читает его так же, как из командной строки
func set_arg(name: String, value: String) -> void:
	_args[name] = value


func clear_arg(name: String) -> void:
	_args.erase(name)


## Перейти в главное меню (из среза — Esc, из «Города» — меню паузы); пусто — меню нет (запуск сцены напрямую)
func to_menu() -> bool:
	if not ResourceLoader.exists(MENU_SCENE):
		return false
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)
	return true


## Сменить качество; remember — запомнить выбор игрока (user://settings.cfg)
func set_quality(level: String, remember := true) -> void:
	quality = level
	if remember and not _capturing() and not _args.has("quality"):
		quality_source = "saved"
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		cfg.set_value("graphics", "quality", level)
		cfg.set_value("graphics", "adapter", RenderingServer.get_video_adapter_name())
		cfg.save(SETTINGS_PATH)
	quality_changed.emit(level)


func _load_quality() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return ""
	var q := String(cfg.get_value("graphics", "quality", ""))
	return q if q in [QUALITY_HIGH, QUALITY_MEDIUM, QUALITY_LOW] else ""


## Съёмка кадра или ролика: качество не выбирается само и не запоминается
func _capturing() -> bool:
	return _args.has("shot") or _args.has("movie") or _args.has("hero")


func set_wind(w: Vector4) -> void:
	wind = w
	RenderingServer.global_shader_parameter_set("ordo_wind", w)


func set_sun_dir(d: Vector3) -> void:
	sun_dir = d.normalized()
	RenderingServer.global_shader_parameter_set("ordo_sun_dir", sun_dir)


func is_low() -> bool:
	return quality == QUALITY_LOW


func is_medium() -> bool:
	return quality == QUALITY_MEDIUM


## Esc в срезе — назад в главное меню (у «Города» — своё меню паузы). При съёмке — нет.
func _unhandled_input(event: InputEvent) -> void:
	if _capturing() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if (event as InputEventKey).keycode != KEY_ESCAPE:
		return
	var cur := get_tree().current_scene
	if cur and cur.scene_file_path == "res://scenes/slice.tscn" and to_menu():
		get_viewport().set_input_as_handled()


## Громкость 0..1 (главная шина) и окно во весь экран — из настроек игрока
func set_volume(v: float, remember := true) -> void:
	volume = clampf(v, 0.0, 1.0)
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
		AudioServer.set_bus_mute(bus, volume <= 0.001)
	if remember:
		_save_value("audio", "volume", volume)


func set_fullscreen(on: bool, remember := true) -> void:
	fullscreen = on
	if not _capturing() and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	if remember:
		_save_value("display", "fullscreen", on)


func _save_value(section: String, key: String, v: Variant) -> void:
	if _capturing():
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(section, key, v)
	cfg.save(SETTINGS_PATH)


func _load_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	set_volume(float(cfg.get_value("audio", "volume", 0.8)), false)
	if bool(cfg.get_value("display", "fullscreen", false)):
		set_fullscreen(true, false)


func _process(delta: float) -> void:
	scene_time += delta
	if _cam_name != "" and get_tree().current_scene:
		var cam := get_tree().current_scene.find_child(_cam_name, true, false) as Camera3D
		if cam:
			cam.make_current()
	if _shot_path != "" and scene_time >= _shot_at:
		var path := _shot_path
		_shot_path = ""
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		# путь абсолютный (tools/shot.sh так и передаёт) или res:// / user://
		var err := img.save_png(ProjectSettings.globalize_path(path))
		print("[ordo] кадр: ", path, " ", img.get_size(), " err=", err)
		get_tree().quit()
