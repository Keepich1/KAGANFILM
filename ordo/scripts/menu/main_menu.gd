class_name MainMenu
extends Node3D
## Главное меню «Ордо» (ТЗ §9 режимы, §12 интерфейс, §11.7 качество). Сцена по умолчанию проекта.
##
## Фон — долина на закате и лагерь кыпчаков среза (тот же мир, тот же лагерь, жизнь лагеря BattleAmbient),
## камера медленно плывёт (MenuCamera). Слева — доска резного ореха в латунной раме: «Ордо», пояс двух
## сторон (бирюзовые изразцы Коканда и красный войлок кыпчаков) и пункты:
##   «Сражение»            — срез стиля (scenes/slice.tscn) ровно как одобрен; Esc там — назад сюда;
##   «Город: за Коканд»    — scenes/gorod/gorod.tscn, местный игрок — Коканд, ИИ — кыпчаки;
##   «Город: за кыпчаков»  — то же за кыпчаков;
##   «Настройки»           — качество (как F2: «Высокое» / «Среднее» / «Низкое»), громкость, во весь экран;
##   «Выход».
## Картинки — assets/ui (tools/gen_ui.py, пакет UI); если их нет — простые цветные рамки.
## Ключи запуска (для инструментов кадров): --menu_settings — открыть «Настройки»; --menu_hover=N — подсветить
## пункт N (кадр проверки); --start=slice|kokand|kipchak — сразу в режим.

const SLICE := "res://scenes/slice.tscn"
const GOROD := "res://scenes/gorod/gorod.tscn"
const UI := "res://assets/ui/"
const FONT_HEAD := "res://assets/ui/fonts/cormorant_unicase/CormorantUnicase-SemiBold.ttf"
const FONT_HEAD_BOLD := "res://assets/ui/fonts/cormorant_unicase/CormorantUnicase-Bold.ttf"
const FONT_TEXT := "res://assets/ui/fonts/alegreya/Alegreya-VariableFont_wght.ttf"
const FONT_ITALIC := "res://assets/ui/fonts/alegreya/Alegreya-Italic-VariableFont_wght.ttf"

## Цвета: пергамент по ореху, латунь, тушь по бумаге (как у интерфейса «Города», UiTheme)
const PARCH := Color("#f0dfb8")
const PARCH_DIM := Color("#c9b38a")
const BRASS := Color("#e2bf72")
const BRASS_DIM := Color("#a8864a")
const INK := Color("#2b1a10")
const INK_SOFT := Color("#5a4028")
const SHADOW := Color(0.05, 0.03, 0.01, 0.9)

const BOARD_X := 72.0
const BOARD_W := 600.0
const BOARD_TOP := 56.0

## Пункты меню: [id, заголовок, подпись, значок]
const ITEMS := [
	["slice", "Сражение", "Срез стиля: залп сарбозов и натиск сайыскеров", "icons/unit_general"],
	["kokand", "Город: за Коканд", "Город у арыков: поля, кирпич, стены и ворота", "icons/crest_kokand"],
	["kipchak", "Город: за кыпчаков", "Кочевой лагерь: юрты, табуны, олжо и көч", "icons/crest_kipchak"],
	["settings", "Настройки", "", ""],
	["quit", "Выход", "", ""],
]

@onready var world: World = $World
@onready var camp: KipchakCamp = $Camp

var _ordo: Node
var _ui: Control
var _settings: Control
var _loading: Control
var _buttons: Array[Button] = []
var _q_buttons := {}
var _volume: HSlider
var _full: CheckButton
var _cache := {}
var _busy := false


func _ready() -> void:
	_ordo = get_node_or_null("/root/Ordo")
	camp.snap_to_terrain()
	_clear_grass()
	_build_ui()
	if _ordo:
		if _ordo.has_arg("menu_settings"):
			_open_settings()
		if _ordo.has_arg("menu_hover"):
			var i := clampi(int(_ordo.arg("menu_hover")), 0, _buttons.size() - 1)
			_buttons[i].grab_focus()
		var start := String(_ordo.arg("start", ""))
		if start != "":
			_ordo.clear_arg("start")
			_choose.call_deferred(start)
	if not (_ordo and (_ordo.has_arg("menu_settings") or _ordo.has_arg("menu_hover"))):
		_buttons[0].grab_focus.call_deferred()
	# кадр без монитора (tools/shot.sh): до кадра — дешёвая отрисовка, как у среза и «Города»
	if _ordo and _ordo.has_arg("shot"):
		_shot_at = float(_ordo.arg("at", "1.0"))
		world.environment_node.environment.volumetric_fog_temporal_reprojection_enabled = false


var _shot_at := -1.0
var _fast_on := false
var _frames := 0


func _process(_delta: float) -> void:
	if _shot_at < 0.0:
		return
	_frames += 1
	if _frames < 2:
		return
	var want := float(_ordo.get("scene_time")) < _shot_at - 0.1
	if want == _fast_on:
		return
	_fast_on = want
	var vp := get_viewport()
	var q: String = _ordo.get("quality")
	if want:
		vp.scaling_3d_scale = 0.25
	else:
		WorldQuality.apply_viewport(vp, q)
	world.sun.shadow_enabled = not want
	var post := world.painterly_post()
	if post:
		post.enabled = not want and WorldQuality.preset(q).post != "off"
	if not want:
		_shot_at = -1.0


## Поляны без травы под юртами и загонами (как в срезе)
func _clear_grass() -> void:
	var list: Array = []
	for n in camp.buildings():
		var r := float(n.get_meta("footprint", 0.0))
		if r > 0.0:
			list.append(Vector3(n.global_position.x, n.global_position.z, r + 0.8))
	world.set_grass_clearings(list.slice(0, 48))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		if _settings.visible:
			_close_settings()
			get_viewport().set_input_as_handled()


# ================================================================= выбор

func _choose(id: String) -> void:
	if _busy:
		return
	match id:
		"slice":
			_go(SLICE, tr("Сражение"))
		"kokand", "kipchak":
			if not ResourceLoader.exists(GOROD):
				_flash(tr("«Город» ещё собирается — загляните в следующую сборку"))
				return
			if _ordo:
				_ordo.set_arg("faction", id)
				_ordo.clear_arg("replay")
			_go(GOROD, tr("Город: за Коканд") if id == "kokand" else tr("Город: за кыпчаков"))
		"settings":
			_open_settings()
		"quit":
			get_tree().quit()


## Затемнить, показать «Загрузка…» (кадр успевает нарисоваться) и сменить сцену
func _go(path: String, title: String) -> void:
	_busy = true
	(_loading.get_node("Title") as Label).text = title
	_loading.visible = true
	_loading.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_loading, "modulate:a", 1.0, 0.35)
	await tw.finished
	await get_tree().process_frame
	await get_tree().process_frame
	print("[меню] → ", path)
	get_tree().change_scene_to_file(path)


func _flash(text: String) -> void:
	var l := _ui.get_node("Flash") as Label
	l.text = text
	l.visible = true
	l.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.4)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)


# ================================================================= интерфейс

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	_ui = Control.new()
	_ui.name = "Root"
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = _make_theme()
	layer.add_child(_ui)
	# тень слева: доска и надписи читаются на любом небе
	var shade := TextureRect.new()
	shade.texture = _gradient([Color(0.05, 0.03, 0.02, 0.78), Color(0.05, 0.03, 0.02, 0.0)], [0.0, 1.0])
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_bottom = 1.0
	shade.offset_right = 1060.0
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)
	# доска: орех с заклёпками, латунная рама
	var board := Control.new()
	board.name = "Board"
	board.anchor_bottom = 1.0
	board.offset_left = BOARD_X
	board.offset_top = BOARD_TOP
	board.offset_right = BOARD_X + BOARD_W
	board.offset_bottom = -BOARD_TOP
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(board)
	board.add_child(_nine("panel", 40.0, Color("#4a2f1c")))
	var frame := _nine("frame_brass", 24.0, Color(0, 0, 0, 0))
	board.add_child(frame)
	if _tex("frame_brass") == null:
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.border_color = BRASS_DIM
		sb.set_border_width_all(3)
		var p := Panel.new()
		p.add_theme_stylebox_override("panel", sb)
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board.add_child(p)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 44.0
	col.offset_right = -44.0
	col.offset_top = 46.0
	col.offset_bottom = -34.0
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(col)
	# заголовок
	var title := _label(tr("Ордо"), _font(FONT_HEAD_BOLD), 112, BRASS)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.02, 0.95))
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	col.add_child(title)
	var sub := _label(tr("Коканд и кыпчаки · степь у Тянь-Шаня"), _font(FONT_ITALIC, 500), 25, PARCH_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(_gap(22))
	col.add_child(_belts())
	col.add_child(_gap(30))
	# пункты
	for it: Array in ITEMS:
		var b := _item_button(it)
		col.add_child(b)
		_buttons.append(b)
		if it[0] == "kipchak":
			col.add_child(_gap(26))
			col.add_child(_rule())
			col.add_child(_gap(18))
		else:
			col.add_child(_gap(10))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)
	var foot := _label(_footer_text(), _font(FONT_ITALIC, 450), 18, PARCH_DIM)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.modulate.a = 0.85
	col.add_child(foot)
	# соседние пункты по стрелкам (по кругу)
	for i in _buttons.size():
		_buttons[i].focus_neighbor_top = _buttons[(i - 1 + _buttons.size()) % _buttons.size()].get_path()
		_buttons[i].focus_neighbor_bottom = _buttons[(i + 1) % _buttons.size()].get_path()
	_build_settings()
	_build_loading()
	var flash := _label("", _font(FONT_ITALIC, 500), 24, PARCH)
	flash.name = "Flash"
	flash.add_theme_constant_override("outline_size", 6)
	flash.add_theme_color_override("font_outline_color", SHADOW)
	flash.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	flash.grow_horizontal = Control.GROW_DIRECTION_BOTH
	flash.offset_top = -90.0
	flash.offset_bottom = -50.0
	flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flash.visible = false
	_ui.add_child(flash)


## Пункт меню: дощечка (кнопка) с латунной рамкой; заголовок, подпись курсивом, герб стороны слева
func _item_button(it: Array) -> Button:
	var id: String = it[0]
	var big := String(it[2]) != ""
	var b := Button.new()
	b.name = "Item_" + id
	b.custom_minimum_size = Vector2(0, 104 if big else 64)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(_choose.bind(id))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 22.0
	row.offset_right = -18.0
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var icon_path: String = it[3]
	if icon_path != "" and _tex(icon_path) != null:
		var icon := TextureRect.new()
		icon.texture = _tex(icon_path)
		icon.custom_minimum_size = Vector2(64, 64)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", -2)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	var head := _label(tr(it[1]), _font(FONT_HEAD), 40 if big else 32, PARCH)
	head.name = "Head"
	head.add_theme_constant_override("outline_size", 4)
	head.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02, 0.9))
	texts.add_child(head)
	if big:
		var sub := _label(tr(it[2]), _font(FONT_ITALIC, 480), 20, PARCH_DIM)
		sub.name = "Sub"
		texts.add_child(sub)
	# наконечник стрелы у выбранного пункта (курсор интерфейса — наконечник, ТЗ §12)
	var mark := ArrowMark.new()
	mark.name = "Mark"
	mark.custom_minimum_size = Vector2(26, 30)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.visible = false
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mark)
	var lit := func(on: bool) -> void:
		mark.visible = on
		head.add_theme_color_override("font_color", BRASS if on else PARCH)
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	b.focus_entered.connect(lit.bind(true))
	b.focus_exited.connect(lit.bind(false))
	return b


## Пояс двух сторон: бирюзовые изразцы Коканда и красный войлок кыпчаков встык, с латунной кромкой
func _belts() -> Control:
	var box := HBoxContainer.new()
	box.custom_minimum_size = Vector2(0, 30)
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["belt_kokand", "belt_kipchak"]:
		var t := _tex(side)
		var r: Control
		if t:
			var tr_ := TextureRect.new()
			tr_.texture = t
			tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr_.stretch_mode = TextureRect.STRETCH_TILE
			r = tr_
		else:
			var c := ColorRect.new()
			c.color = Color("#2f8f74") if side == "belt_kokand" else Color("#b0392f")
			r = c
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.custom_minimum_size = Vector2(0, 30)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(r)
	return box


func _rule() -> Control:
	var c := ColorRect.new()
	c.color = Color(BRASS_DIM.r, BRASS_DIM.g, BRASS_DIM.b, 0.55)
	c.custom_minimum_size = Vector2(0, 2)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _footer_text() -> String:
	var v := String(ProjectSettings.get_setting("application/config/version", ""))
	var s := tr("Godot 4.7 · рабочая сборка")
	return (tr("Сборка ") + v + " · " + s) if v != "" else s


# ---------------------------------------------------------------- настройки

func _build_settings() -> void:
	_settings = Control.new()
	_settings.name = "Settings"
	_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings.visible = false
	_ui.add_child(_settings)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.02, 0.01, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings.add_child(dim)
	var sheet := Control.new()
	sheet.position = Vector2(BOARD_X + BOARD_W + 40.0, 210.0)
	sheet.size = Vector2(660, 560)
	_settings.add_child(sheet)
	var paper := _nine("paper", 28.0, Color("#e9d8b0"))
	sheet.add_child(paper)
	var edge := StyleBoxFlat.new()
	edge.draw_center = false
	edge.border_color = Color(INK_SOFT.r, INK_SOFT.g, INK_SOFT.b, 0.6)
	edge.set_border_width_all(2)
	edge.set_expand_margin_all(-14)
	var ep := Panel.new()
	ep.add_theme_stylebox_override("panel", edge)
	ep.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(ep)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 54.0
	col.offset_right = -54.0
	col.offset_top = 36.0
	col.offset_bottom = -36.0
	col.add_theme_constant_override("separation", 10)
	sheet.add_child(col)
	var title := _label(tr("Настройки"), _font(FONT_HEAD_BOLD), 46, INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	col.add_child(_gap(6))
	# качество (ТЗ 11.7) — как F2 в срезе
	col.add_child(_label(tr("Качество графики"), _font(FONT_HEAD), 28, INK))
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 12)
	col.add_child(qrow)
	for lv: String in WorldQuality.LEVELS:
		var qb := Button.new()
		qb.text = tr(WorldQuality.NAMES[lv])
		qb.toggle_mode = true
		qb.custom_minimum_size = Vector2(170, 54)
		qb.add_theme_font_override("font", _font(FONT_HEAD))
		qb.add_theme_font_size_override("font_size", 26)
		qb.pressed.connect(_set_quality.bind(lv))
		qrow.add_child(qb)
		_q_buttons[lv] = qb
	col.add_child(_label(tr("В игре — клавиша F2. «Низкое» — для слабых компьютеров."), _font(FONT_ITALIC, 480), 20, INK_SOFT))
	col.add_child(_gap(8))
	# громкость (звука пока нет — ползунок уже запоминается)
	col.add_child(_label(tr("Громкость"), _font(FONT_HEAD), 28, INK))
	_volume = HSlider.new()
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.05
	_volume.custom_minimum_size = Vector2(0, 32)
	_volume.value = float(_ordo.get("volume")) if _ordo else 0.8
	_volume.value_changed.connect(func(v: float) -> void:
		if _ordo:
			_ordo.call("set_volume", v))
	col.add_child(_volume)
	col.add_child(_label(tr("Звук появится в следующих сборках."), _font(FONT_ITALIC, 480), 20, INK_SOFT))
	col.add_child(_gap(8))
	_full = CheckButton.new()
	_full.text = tr("Во весь экран")
	_full.add_theme_font_override("font", _font(FONT_HEAD))
	_full.add_theme_font_size_override("font_size", 28)
	_full.add_theme_color_override("font_color", INK)
	_full.add_theme_color_override("font_hover_color", INK)
	_full.add_theme_color_override("font_pressed_color", INK)
	_full.add_theme_color_override("font_focus_color", INK)
	_full.add_theme_color_override("font_hover_pressed_color", INK)
	_full.button_pressed = bool(_ordo.get("fullscreen")) if _ordo else false
	_full.toggled.connect(func(on: bool) -> void:
		if _ordo:
			_ordo.call("set_fullscreen", on))
	col.add_child(_full)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp)
	var done := Button.new()
	done.text = tr("Готово")
	done.custom_minimum_size = Vector2(220, 58)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done.add_theme_font_override("font", _font(FONT_HEAD))
	done.add_theme_font_size_override("font_size", 30)
	done.pressed.connect(_close_settings)
	col.add_child(done)
	_sync_quality()


func _open_settings() -> void:
	_sync_quality()
	_settings.visible = true
	var cur: String = _ordo.get("quality") if _ordo else WorldQuality.HIGH
	(_q_buttons.get(cur, _q_buttons[WorldQuality.HIGH]) as Button).grab_focus()


func _close_settings() -> void:
	_settings.visible = false
	_buttons[3].grab_focus()


func _set_quality(lv: String) -> void:
	if _ordo:
		_ordo.call("set_quality", lv)
	_sync_quality()


func _sync_quality() -> void:
	var cur: String = _ordo.get("quality") if _ordo else WorldQuality.HIGH
	for lv: String in _q_buttons:
		(_q_buttons[lv] as Button).set_pressed_no_signal(lv == cur)


# ---------------------------------------------------------------- загрузка

func _build_loading() -> void:
	_loading = Control.new()
	_loading.name = "Loading"
	_loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading.visible = false
	_ui.add_child(_loading)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(dim)
	var t := _label("", _font(FONT_HEAD_BOLD), 64, BRASS)
	t.name = "Title"
	t.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	t.grow_horizontal = Control.GROW_DIRECTION_BOTH
	t.grow_vertical = Control.GROW_DIRECTION_BOTH
	t.offset_top = -70.0
	t.offset_bottom = 10.0
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.add_child(t)
	var w := _label(tr("Загрузка…"), _font(FONT_ITALIC, 500), 30, PARCH_DIM)
	w.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	w.grow_horizontal = Control.GROW_DIRECTION_BOTH
	w.offset_top = 20.0
	w.offset_bottom = 70.0
	w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.add_child(w)


# ---------------------------------------------------------------- тема и ресурсы

func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = _font(FONT_TEXT, 500)
	th.default_font_size = 22
	var normal := _box("button_normal", 16.0, Color("#5a3a22"))
	var hover := _box("button_hover", 16.0, Color("#6b4528"))
	var pressed := _box("button_pressed", 16.0, Color("#3e2716"))
	for st in ["normal", "disabled"]:
		th.set_stylebox(st, "Button", normal)
	th.set_stylebox("hover", "Button", hover)
	th.set_stylebox("focus", "Button", hover)
	th.set_stylebox("pressed", "Button", pressed)
	th.set_stylebox("hover_pressed", "Button", pressed)
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		th.set_color(c, "Button", PARCH)
	th.set_color("font_pressed_color", "Button", BRASS)
	th.set_color("font_hover_pressed_color", "Button", BRASS)
	# CheckButton на бумаге — без доски
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
		th.set_stylebox(st, "CheckButton", empty)
	# ползунок: латунная дорожка и головка
	var track := StyleBoxFlat.new()
	track.bg_color = Color(INK_SOFT.r, INK_SOFT.g, INK_SOFT.b, 0.35)
	track.set_corner_radius_all(3)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := StyleBoxFlat.new()
	fill.bg_color = BRASS_DIM
	fill.set_corner_radius_all(3)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return th


func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _gradient(colors: Array, offsets: Array) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 4
	return t


## Картинка интерфейса assets/ui/<name>.png (без кэша импорта — с диска); null, если нет
func _tex(name: String) -> Texture2D:
	var path := UI + name + ".png"
	if _cache.has(path):
		return _cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	if t == null and FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img:
			t = ImageTexture.create_from_image(img)
	_cache[path] = t
	return t


func _font(path: String, weight := 0) -> Font:
	var key := "%s@%d" % [path, weight]
	if _cache.has(key):
		return _cache[key]
	var f: Font = load(path) as Font if ResourceLoader.exists(path) else null
	if f == null:
		f = ThemeDB.fallback_font
	if weight > 0:
		var fv := FontVariation.new()
		fv.base_font = f
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		f = fv
	_cache[key] = f
	return f


## 9-срез картинки на весь родитель; без картинки — плоский цвет
func _nine(name: String, margin: float, fallback: Color) -> Control:
	var t := _tex(name)
	if t == null:
		var c := ColorRect.new()
		c.color = fallback
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return c
	var n := NinePatchRect.new()
	n.texture = t
	n.patch_margin_left = int(margin)
	n.patch_margin_right = int(margin)
	n.patch_margin_top = int(margin)
	n.patch_margin_bottom = int(margin)
	n.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	n.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	n.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return n


func _box(name: String, margin: float, fallback: Color) -> StyleBox:
	var t := _tex(name)
	if t == null:
		var f := StyleBoxFlat.new()
		f.bg_color = fallback
		f.border_color = BRASS_DIM
		f.set_border_width_all(2)
		f.set_content_margin_all(10)
		return f
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = margin
	sb.texture_margin_bottom = margin
	sb.set_content_margin_all(10)
	return sb


## Латунный наконечник стрелы остриём к надписи
class ArrowMark extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var tip := Vector2(2.0, h * 0.5)
		var pts := PackedVector2Array([tip, Vector2(w, 3.0), Vector2(w * 0.62, h * 0.5), Vector2(w, h - 3.0)])
		draw_colored_polygon(pts, Color("#e2bf72"))
		draw_polyline(PackedVector2Array([tip, Vector2(w, 3.0), Vector2(w * 0.62, h * 0.5), Vector2(w, h - 3.0), tip]),
			Color(0.16, 0.08, 0.02, 0.9), 1.6, true)
