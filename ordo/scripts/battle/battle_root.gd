class_name BattleRoot
extends Node3D
## Корень сцены боя (scenes/battle/battle.tscn): клавиши времени и камер (ТЗ 10).
##   P — пауза, + / − — скорость (×¼…×4), R — бой заново,
##   C — кинокамера / камера стратегии (любое движение камерой включает стратегическую),
##   1–4 — готовые виды камеры стратегии, ЛКМ — выбрать отряд.

const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0]

@export var scenario_path: NodePath = ^"Scenario"
@export var cine_camera_path: NodePath = ^"Cameras/CamCine"
@export var rts_camera_path: NodePath = ^"Cameras/CamBattleRTS"
## Начинать с кинокамеры (иначе — со стратегической)
@export var start_cinematic := true

var scenario: ScenarioClash
var cine: Camera3D
var rts: RtsCamera
var _speed_i := 2
var _shot_mode := false


func _ready() -> void:
	scenario = get_node_or_null(scenario_path) as ScenarioClash
	cine = get_node_or_null(cine_camera_path) as Camera3D
	rts = get_node_or_null(rts_camera_path) as RtsCamera
	var ordo := get_node_or_null("/root/Ordo")
	_shot_mode = ordo != null and ordo.has_arg("shot")
	if rts:
		rts.moved_by_player.connect(_use_rts)
	if start_cinematic and cine:
		cine.make_current()
	elif rts:
		rts.make_current()


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
