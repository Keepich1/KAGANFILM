class_name BattleRoot
extends Node3D
## Корень сцены боя (scenes/battle/battle.tscn): клавиши времени и камер (ТЗ 10).
##   P — пауза, + / − — скорость (×¼…×4), R — бой заново,
##   C — кинокамера / камера стратегии (любое движение камерой включает стратегическую),
##   1–4 — готовые виды камеры стратегии, ЛКМ — выбрать отряд.
##
## Серия кадров за один прогон (проверка без монитора):
##   tools/shot.sh res://scenes/test/battle_clash.tscn /abs/last.png --at=99 \
##       --series=4.2@CamWarCry,8.3@CamVolley,15@CamImpact --series_out=/abs/dir --series_prefix=v1_

const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0]

@export var scenario_path: NodePath = ^"Scenario"
@export var cine_camera_path: NodePath = ^"Cameras/CamCine"
@export var rts_camera_path: NodePath = ^"Cameras/CamBattleRTS"
## Начинать с кинокамеры (иначе — со стратегической)
@export var start_cinematic := true
## Делать свою камеру текущей при запуске (выключить, если камерой управляет сборка)
@export var take_camera := true

var scenario: ScenarioClash
var cine: Camera3D
var rts: RtsCamera
var _speed_i := 2
var _shot_mode := false
var _series: Array = []      # [время, имя камеры]
var _series_out := ""
var _series_prefix := ""
var _series_busy := false


func _ready() -> void:
	scenario = get_node_or_null(scenario_path) as ScenarioClash
	cine = get_node_or_null(cine_camera_path) as Camera3D
	rts = get_node_or_null(rts_camera_path) as RtsCamera
	var ordo := get_node_or_null("/root/Ordo")
	_shot_mode = ordo != null and ordo.has_arg("shot")
	if rts:
		rts.moved_by_player.connect(_use_rts)
	if take_camera:
		if start_cinematic and cine:
			cine.make_current()
		elif rts:
			rts.make_current()
	if ordo and ordo.has_arg("series"):
		for item in String(ordo.arg("series")).split(",", false):
			var kv := item.split("@")
			if kv.size() == 2:
				_series.append([float(kv[0]), kv[1]])
		_series.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		_series_out = ordo.arg("series_out", ProjectSettings.globalize_path("user://"))
		_series_prefix = ordo.arg("series_prefix", "")


func _process(_delta: float) -> void:
	if _series.is_empty() or _series_busy or scenario == null:
		return
	if scenario.time + 0.07 >= float(_series[0][0]):
		_capture(_series.pop_front())


## Кадр серии: камера становится текущей, через кадр снимок
func _capture(item: Array) -> void:
	_series_busy = true
	var cam := get_tree().current_scene.find_child(String(item[1]), true, false) as Camera3D
	if cam:
		cam.make_current()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s%s_%s.png" % [_series_out, _series_prefix, String(item[1]).to_lower().trim_prefix("cam"), String.num(float(item[0]), 1)]
	img.save_png(path)
	print("[бой] кадр серии: ", path, " t=", snappedf(scenario.time, 0.01))
	_series_busy = false


func _use_rts() -> void:
	if rts and not rts.current:
		# стратегическая камера продолжает с того места, куда смотрела кинокамера
		if cine and cine.current:
			var f := cine.global_position - cine.global_basis.z * 60.0
			rts.go_to(Vector4(f.x, f.z, clampf(rts.distance, 40.0, 120.0), rts.yaw_deg), true)
		rts.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if _shot_mode or scenario == null:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).physical_keycode:
		KEY_P:
			scenario.paused = not scenario.paused
		KEY_EQUAL, KEY_KP_ADD:
			_speed_i = mini(_speed_i + 1, SPEEDS.size() - 1)
			scenario.time_scale = SPEEDS[_speed_i]
		KEY_MINUS, KEY_KP_SUBTRACT:
			_speed_i = maxi(_speed_i - 1, 0)
			scenario.time_scale = SPEEDS[_speed_i]
		KEY_R:
			scenario.restart()
		KEY_C:
			if cine and not cine.current:
				cine.make_current()
			else:
				_use_rts()
