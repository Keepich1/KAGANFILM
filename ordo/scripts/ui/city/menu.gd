class_name CityMenu
extends Control
## Меню игры (кнопка ≡ на балке, F10, Esc при пустом выделении): лист «самаркандской бумаги» поверх
## затемнённого мира — «Продолжить», «Управление» (памятка клавиш ТЗ §10), «Начать заново», «Выйти».
## Пока меню открыто, симуляция стоит (SimDriver.paused) и ввод в мир выключен; закрытие возвращает как было.
## «Начать заново» и «Выйти» — сигналы CityHud (restart_requested / quit_requested); если их никто не
## слушает, сцена перезагружается / игра закрывается.

signal closed

const W := 460.0
const H := 430.0
const HELP_W := 1240.0
const HELP_H := 690.0
const ROW := 40.0
const KEY_W := 214.0

## Памятка: [клавиши, что делают] по двум столбцам (ТЗ §10, ARCHITECTURE §14, ECONOMY §1.7, §2.6, §4.1)
const HELP_LEFT := [
	["Выбор и приказы", ""],
	["ЛКМ", "выбрать; рамка — несколько"],
	["Двойной щелчок", "все такие же на экране"],
	["ПКМ", "идти, бить, добывать, строить"],
	["ПКМ и протянуть", "линия строя и разворот"],
	["Двойной ПКМ", "бегом / галопом"],
	["Shift", "в очередь"],
	["Ctrl+ПКМ", "простая атака, без набега"],
	["F · H · G", "строй · стой · качып атуу"],
	["R · V · U", "огонь / рукопашная · клич · отряд"],
	["K · Shift+K", "свернуть юрту · весь лагерь"],
	["K с арбами", "развернуть лагерь у курсора"],
]
const HELP_RIGHT := [
	["Город и камера", ""],
	["B, буквы", "«Хозяйство» и постройки"],
	["Колесо, R", "повернуть постройку"],
	["Shift+ЛКМ", "поставить ещё одну"],
	["«.» · N", "свободный работник · тревога"],
	["V у Урды · Tab", "Ҳашар · наложения на карту"],
	["Ctrl+1…9 · 1…9", "запомнить · вызвать группу"],
	["WASD · Q/E", "двигать · вращать камеру"],
	["F5–F8", "виды камеры"],
	["P · + / − · M", "пауза · скорость · звук"],
	["Del · Esc · F10", "снести · отмена · меню"],
]

var hud: CityHud
var _sheet: NinePatchRect
var _help: NinePatchRect
var _was_paused := false
var _input_was := true


func setup(p_hud: CityHud) -> void:
	hud = p_hud
	name = "Menu"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_sheet = _paper(W, H)
	_sheet.name = "Sheet"
	var title := UiTheme.label(tr("Меню"), UiTheme.head_bold(), 40, true)
	title.position = Vector2(0, 26)
	title.size = Vector2(W, 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sheet.add_child(title)
	var box := VBoxContainer.new()
	box.position = Vector2(80, 98)
	box.size = Vector2(W - 160, H - 130)
	box.add_theme_constant_override("separation", 12)
	_sheet.add_child(box)
	for it in [["Продолжить", close], ["Управление", show_help], ["Начать заново", _restart], ["Выйти", _quit]]:
		var b := Button.new()
		b.text = tr(it[0])
		b.custom_minimum_size = Vector2(0, 56)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", UiTheme.head_bold())
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(it[1])
		box.add_child(b)
	_help = _paper(HELP_W, HELP_H)
	_help.name = "Help"
	_help.visible = false
	var ht := UiTheme.label(tr("Управление"), UiTheme.head_bold(), 38, true)
	ht.position = Vector2(0, 22)
	ht.size = Vector2(HELP_W, 46)
	ht.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.add_child(ht)
	_column(HELP_LEFT, Vector2(64, 90))
	_column(HELP_RIGHT, Vector2(HELP_W * 0.5 + 24, 90))
	var back := Button.new()
	back.text = tr("Назад")
	back.focus_mode = Control.FOCUS_NONE
	back.position = Vector2(HELP_W * 0.5 - 100, HELP_H - 80)
	back.size = Vector2(200, 52)
	back.add_theme_font_override("font", UiTheme.head_bold())
	back.add_theme_font_size_override("font_size", 22)
	back.pressed.connect(func() -> void: _show_sheet())
	_help.add_child(back)


func _paper(w: float, h: float) -> NinePatchRect:
	var p := NinePatchRect.new()
	p.texture = UiTheme.tex("paper")
	for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		p.set(m, 30)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.offset_left = -w * 0.5
	p.offset_right = w * 0.5
	p.offset_top = -h * 0.5
	p.offset_bottom = h * 0.5
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	var frame := NinePatchRect.new()
	frame.texture = UiTheme.tex("frame_brass")
	for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		frame.set(m, 14)
	frame.draw_center = false
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = -10
	frame.offset_top = -10
	frame.offset_right = 10
	frame.offset_bottom = 10
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(frame)
	return p


func _column(rows: Array, at: Vector2) -> void:
	var y := at.y
	var col_w := HELP_W * 0.5 - 80.0
	for r: Array in rows:
		if r[1] == "":
			var head := UiTheme.label(tr(r[0]), UiTheme.head_bold(), 26, true)
			head.position = Vector2(at.x, y)
			_help.add_child(head)
			y += 46.0
			continue
		var key := UiTheme.label(tr(r[0]), UiTheme.text(800), 19, true)
		key.position = Vector2(at.x, y)
		key.size = Vector2(KEY_W - 8.0, 28)
		key.add_theme_color_override("font_color", UiTheme.GOLD)
		_help.add_child(key)
		var what := UiTheme.label(tr(r[1]), UiTheme.text(500), 19, true)
		what.position = Vector2(at.x + KEY_W, y)
		what.size = Vector2(col_w - KEY_W, 28)
		what.clip_text = true
		_help.add_child(what)
		y += ROW


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	visible = true
	_show_sheet()
	if hud.driver:
		_was_paused = hud.driver.paused
		hud.driver.paused = true
	if hud.input:
		_input_was = hud.input.enabled
		hud.input.enabled = false
	CityCursor.apply(CityCursor.Kind.DEFAULT)


func close() -> void:
	if not visible:
		return
	visible = false
	if hud.driver:
		hud.driver.paused = _was_paused
	if hud.input:
		hud.input.enabled = _input_was
	closed.emit()


func show_help() -> void:
	_sheet.visible = false
	_help.visible = true


func help_open() -> bool:
	return visible and _help.visible


func _show_sheet() -> void:
	_sheet.visible = true
	_help.visible = false


func _restart() -> void:
	close()
	hud.request_restart()


func _quit() -> void:
	close()
	hud.request_quit()


## Esc / F10 при открытом меню: из памятки — назад, иначе закрыть
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if k.physical_keycode == KEY_ESCAPE or k.physical_keycode == KEY_F10:
		if _help.visible:
			_show_sheet()
		else:
			close()
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()
