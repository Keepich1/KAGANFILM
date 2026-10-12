class_name BattleHud
extends CanvasLayer
## Минимальный интерфейс боя: полоски выделенных отрядов, пауза и скорость, подсказка клавиш
## (гаснет сама; F1 — показать снова). На кадрах без монитора (--shot) подсказки нет.

@export var scenario_path: NodePath = ^"../Scenario"
@export var selection_path: NodePath = ^"../Selection"

var scenario: ScenarioClash
var _bars: SquadBars
var _status: Label
var _help: Label
var _help_t := 9.0
var _shot_mode := false


func _ready() -> void:
	layer = 5
	scenario = get_node_or_null(scenario_path) as ScenarioClash
	var ordo := get_node_or_null("/root/Ordo")
	_shot_mode = ordo != null and (ordo.has_arg("shot") or ordo.has_arg("movie"))
	_bars = SquadBars.new()
	_bars.name = "SquadBars"
	add_child(_bars)
	_bars.selection = get_node_or_null(selection_path) as SquadSelection
	_status = _label(Vector2(0, 0), 20)
	_status.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status.position = Vector2(-120, 18)
	_status.size = Vector2(240, 30)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help = _label(Vector2(18, 0), 13)
	_help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_help.position = Vector2(18, -60)
	_help.text = "C — кинокамера / стратегия    WASD, края, колесо, Q/E, средняя кнопка — камера    1–4 — виды\nЛКМ — отряд, двойной — все такие    P — пауза    + / − — скорость    R — бой заново    F1 — подсказка"
	_help.visible = not _shot_mode


func _label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.96, 0.9, 0.78))
	l.add_theme_color_override("font_shadow_color", Color(0.05, 0.03, 0.02, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_F1:
		_help_t = 9.0
		_help.visible = true


func _process(delta: float) -> void:
	if scenario:
		if scenario.paused:
			_status.text = "Пауза"
		elif scenario.time_scale != 1.0:
			_status.text = "Скорость ×%s" % String.num(scenario.time_scale)
		else:
			_status.text = ""
	if _help.visible and not _shot_mode:
		_help_t -= delta
		_help.modulate.a = clampf(_help_t / 2.0, 0.0, 1.0)
		if _help_t <= 0.0:
			_help.visible = false
