extends Node
## Общие службы среза: качество графики и съёмка кадров из командной строки.
##
## Кадр без монитора (см. tools/shot.sh):
##   godot --path ordo --fixed-fps 30 res://scenes/slice.tscn -- --shot=out.png --at=6 --cam=CamCamp
## Параметры после «--»:
##   --shot=путь.png   сохранить кадр и выйти
##   --at=секунды      момент кадра по времени сцены (по умолчанию 1.0)
##   --cam=Имя         сделать текущей камеру Camera3D с этим именем
##   --quality=high|low  режим качества (ТЗ 11.7)
##   --seed=N          зерно случайностей сцены

signal quality_changed(level: String)

const QUALITY_HIGH := "high"
const QUALITY_LOW := "low"

var quality := QUALITY_HIGH
var seed := 1
var scene_time := 0.0

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
	if _args.has("quality"):
		quality = _args["quality"]
	elif OS.has_feature("mobile"):
		quality = QUALITY_LOW


func arg(name: String, default_value := "") -> String:
	return _args.get(name, default_value)


func has_arg(name: String) -> bool:
	return _args.has(name)


func set_quality(level: String) -> void:
	quality = level
	quality_changed.emit(level)


func is_low() -> bool:
	return quality == QUALITY_LOW


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
