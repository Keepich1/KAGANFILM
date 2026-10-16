class_name MainMenu
extends Node3D
## Главное меню «Ордо» (ТЗ §9 режимы, §12 интерфейс, §11.7 качество). Сцена по умолчанию проекта.
##
## Фон — долина и лагерь кыпчаков среза (тот же мир, тот же лагерь, жизнь лагеря BattleAmbient) в свете
## выбранного времени суток, камера медленно плывёт (MenuCamera). Слева — доска резного ореха в латунной
## раме: «Ордо», пояс двух сторон (бирюзовые изразцы Коканда и красный войлок кыпчаков), переключатель
## «Время суток: День | Закат» (Ordo.set_light_mode — фон меняется сразу, выбор запоминается и действует
## в «Сражении» и обоих «Городах») и пункты:
##   «Сражение»            — срез стиля (scenes/slice.tscn) ровно как одобрен; Esc там — назад сюда;
##   «Город: за Коканд»    — scenes/gorod/gorod.tscn, местный игрок — Коканд, ИИ — кыпчаки;
##   «Город: за кыпчаков»  — то же за кыпчаков;
##   «Игра с другом»       — «Город» один на один по сети (scripts/menu/friend_game.gd, ТЗ §16): лобби — один
##                           «Создать игру», другой «Подключиться» по адресу; партия — NetSession / NetMatch
##                           (scripts/net/). Макет лобби с выдуманными адресами — ключ --online_mock=1 (и кадры
##                           состояний --menu_online=…); --online_mock=0 — настоящая сеть и с --menu_online;
##   «Настройки» | «Выход» — в одну строку. «Настройки»: качество (как F2: «Высокое» / «Среднее» /
##                           «Низкое»), время суток, масштаб интерфейса (75–150 %, Ordo.set_ui_scale),
##                           громкость, во весь экран.
## Масштаб интерфейса меняет холст окна (Ordo): доска, лист «Настроек» и лист «Игры с другом» раскладываются
## по нему заново (_layout); выше холста — ужимаются целиком (доска и так во всю высоту экрана: крупнее 100 %
## ей некуда).
## Картинки — assets/ui (tools/gen_ui.py, пакет UI); если их нет — простые цветные рамки.
## Ключи запуска (для инструментов кадров): --menu_settings — открыть «Настройки» (масштаб — ключ Ordo
## --ui_scale=N); --menu_hover=N — подсветить пункт N (0 «Сражение» … 3 «Игра с другом», 4 «Настройки»,
## 5 «Выход»); --start=slice|kokand|kipchak — сразу в режим; --menu_press_light=day|sunset — нажать
## переключатель времени суток на доске после запуска (кадр проверки: фон меняется на лету); --menu_tip=Имя —
## подсказка узла на кадре (Item_settings, Quality_high, SetLight_sunset, Online_main…);
## --menu_online[=состояние] — открыть макет «Игра с другом» (choose, host_wait, host_ready, join,
## join_connecting, join_fail, join_wait, version, help), --menu_online_alt=N — вариант состояния,
## --menu_online_side=kipchak — хозяин за кыпчаков; F8 / Shift+F8 — следующее / предыдущее состояние (только
## с --menu_online). --net_auto=host | join:адрес — открыть настоящее лобби и сразу «Создать игру» /
## «Подключиться» (кадры двух окон; вместе с --net_bind=127.0.0.1 и --net_show_addr=mock — без настоящих адресов
## в кадре). Подсказки — записки CityTips (заголовок и строка), как в «Городе».
## Пока открыт лист («Настройки» или «Игра с другом»), доска за затемнением не берёт фокус с клавиатуры.

const SLICE := "res://scenes/slice.tscn"
const GOROD := "res://scenes/gorod/gorod.tscn"
const FRIEND_GAME := "res://scripts/menu/friend_game.gd"
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
## Поля доски вокруг столбца пунктов (сверху, снизу) и тень слева
const COL_TOP := 46.0
const COL_BOTTOM := 34.0
const SHADE_W := 1060.0
## Лист «Настроек»: ширина, поля столбца, отступ от доски; поле от краёв холста и доски
const SHEET_W := 660.0
const SHEET_PAD := Vector2(54, 36)
const SHEET_GAP := 40.0
const EDGE := 24.0
## Лист «Игра с другом»: ширина; высота — по содержимому состояния, не ниже ONLINE_MIN_H (ряд кнопок у низа
## листа) и не выше ONLINE_MAX_H (самый высокий ход лобби, friend_game.FLOW_H; при 1920×1080 и 100 % лист такой
## высоты встаёт на доску без ужатия; тест следит). Верх листа — вровень с верхним краем доски, короткие состояния
## короче книзу; масштаб — один на ход лобби (_place_online)
const ONLINE_W := 780.0
const ONLINE_MIN_H := 600.0
const ONLINE_MAX_H := 960.0
## Масштаб клавишами: перестроить холст через столько секунд после последнего нажатия
const SCALE_WAIT := 0.4
## Высота большого пункта (значок, заголовок, подпись) и маленького; зазор между большими
const ITEM_BIG_H := 96.0
const ITEM_SMALL_H := 64.0
const ITEM_GAP := 8.0

## Пункты меню: [id, заголовок, подпись, значок]. «Настройки» и «Выход» — в одну строку (доска при
## 1920×1080 и 100 % не ужимается: столбец 870 из 888)
const ITEMS := [
	["slice", "Сражение", "Срез стиля: залп сарбозов и натиск сайыскеров", "icons/unit_general"],
	["kokand", "Город: за Коканд", "Город у арыков: поля, кирпич, стены и ворота", "icons/crest_kokand"],
	["kipchak", "Город: за кыпчаков", "Кочевой лагерь: юрты, табуны, олжо и көч", "icons/crest_kipchak"],
	["online", "Игра с другом", "Город по сети: Коканд против кыпчаков", ""],
	["settings", "Настройки", "", ""],
	["quit", "Выход", "", ""],
]
## Подсказки пунктов (записка CityTips: заголовок, строка)
const ITEM_TIPS := {
	"slice": "Сражение\nГотовый бой: залп сарбозов и натиск сайыскеров. Esc — назад в меню.",
	"kokand": "Город: за Коканд\nПартия против ИИ: поля у арыков, кирпич, стены. Esc — меню паузы.",
	"kipchak": "Город: за кыпчаков\nПартия против ИИ: юрты, табуны, набеги, көч. Esc — меню паузы.",
	"online": "Игра с другом\nГород один на один по сети: Коканд против кыпчаков.\n~ Один создаёт игру, другой подключается по адресу.\n~ У обоих должна быть одна и та же версия игры.",
	"settings": "Настройки\nКачество графики, время суток, масштаб интерфейса, громкость, экран.",
	"quit": "Выход\nЗакрыть игру.",
}

@onready var world: World = $World
@onready var camp: KipchakCamp = $Camp

var _ordo: Node
var _ui: Control
var _settings: Control
var _loading: Control
var _buttons: Array[Button] = []
var _q_buttons := {}
## Переключатели времени суток: на доске и в «Настройках» — {режим: Button}
var _light_board := {}
var _light_settings := {}
var _volume: HSlider
var _scale: HSlider
var _scale_txt: Label
var _scale_drag := false
## Ползунок масштаба сдвинут клавишами — холст перестраивается через SCALE_WAIT после последнего нажатия
var _scale_wait: Timer
var _full: CheckButton
var _shade: Control
var _board: Control
var _board_col: VBoxContainer
var _sheet: Control
var _sheet_col: VBoxContainer
## Макет «Игра с другом» (friend_game.gd): корень на весь экран и его лист
var _online: Control
var _online_sheet: Control
var _cache := {}
var _busy := false


func _ready() -> void:
	_ordo = get_node_or_null("/root/Ordo")
	camp.snap_to_terrain()
	_clear_grass()
	_build_ui()
	if _ordo:
		_ordo.connect("light_mode_changed", _on_light_mode_changed)
		_ordo.connect("ui_scale_changed", _on_ui_scale_changed)
		if _ordo.has_arg("menu_settings"):
			_open_settings()
		if _ordo.has_arg("menu_online"):
			# ключ без значения — «1»: первое состояние
			_open_online(String(_ordo.arg("menu_online")), int(_ordo.arg("menu_online_alt", "0")))
		elif _ordo.has_arg("net_auto"):
			# кадр двух настоящих окон: сеть живёт настоящим временем — время сцены (--fixed-fps 30) идёт с ним вровень
			if _ordo.has_arg("shot"):
				Engine.max_fps = 30
			_open_online()
		if _ordo.has_arg("menu_press_light"):
			var lb := _light_board.get(String(_ordo.arg("menu_press_light")), null) as Button
			if lb:
				(func() -> void: lb.button_pressed = true).call_deferred()
		if _ordo.has_arg("menu_tip"):
			# кадр проверки подсказки: «навести мышь» на узел с этим именем за миг до кадра
			var at := maxf(0.1, float(_ordo.arg("at", "1.0")) - 1.2)
			get_tree().create_timer(at).timeout.connect(_hover_tip.bind(String(_ordo.arg("menu_tip"))))
		if _ordo.has_arg("menu_hover"):
			var i := clampi(int(_ordo.arg("menu_hover")), 0, _buttons.size() - 1)
			_buttons[i].grab_focus()
		var start := String(_ordo.arg("start", ""))
		if start != "":
			_ordo.clear_arg("start")
			_choose.call_deferred(start)
	if not (_ordo and (_ordo.has_arg("menu_settings") or _ordo.has_arg("menu_hover") or _ordo.has_arg("menu_online")
			or _ordo.has_arg("net_auto"))):
		_buttons[0].grab_focus.call_deferred()
	# код версии для сверки по сети считается с запуска меню, в отдельном потоке (к «Игре с другом» он готов)
	NetVersion.start()
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


## Esc в «Настройках» — закрыть. Esc на листе «Игра с другом» ловит сам лист (friend_game._input — раньше поля
## адреса, иначе первое нажатие съело бы поле): сюда он не доходит
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
				# новая партия — новое зерно (карта та же; бой, набеги и случайности ИИ — свои)
				if not _ordo.has_arg("seed") or _ordo.has_arg("menu_seed"):
					_ordo.set_arg("seed", str(randi_range(1, 999999)))
					_ordo.set_arg("menu_seed", "1")
			_go(GOROD, tr("Город: за Коканд") if id == "kokand" else tr("Город: за кыпчаков"))
		"online":
			_open_online()
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


## Строка внизу экрана на hold секунд, потом гаснет (кадр проверки держит её дольше). Пока открыт лист
## «Игра с другом» — строка под ним (на 150 % низ экрана занят листом)
func _flash(text: String, hold := 2.4) -> void:
	if _online != null and _online.visible:
		_online.call("flash", text, hold)
		return
	var l := _ui.get_node("Flash") as Label
	l.text = text
	l.visible = true
	l.modulate.a = 1.0
	if l.has_meta("tween"):
		var old := l.get_meta("tween") as Tween
		if old and old.is_valid():
			old.kill()
	var tw := create_tween()
	tw.tween_interval(hold)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	l.set_meta("tween", tw)


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
	shade.offset_right = SHADE_W
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)
	_shade = shade
	# доска: орех с заклёпками, латунная рама (место и размер — _layout, по холсту)
	var board := Control.new()
	board.name = "Board"
	board.position = Vector2(BOARD_X, BOARD_TOP)
	board.size = Vector2(BOARD_W, 1080.0 - BOARD_TOP * 2.0)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(board)
	_board = board
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
	col.offset_top = COL_TOP
	col.offset_bottom = -COL_BOTTOM
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(col)
	_board_col = col
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
	col.add_child(_gap(24))
	# время суток — до выбора режима: действует в «Сражении» и обоих «Городах»
	col.add_child(_light_switch())
	col.add_child(_gap(20))
	# пункты: большие столбцом, под латунной чертой — «Настройки» и «Выход» одной строкой (3 : 2)
	var small_row: HBoxContainer = null
	var last_big := "online" if _online_on() else "kipchak"
	for it: Array in ITEMS:
		if it[0] == "online" and not _online_on():
			continue
		var b := _item_button(it)
		_buttons.append(b)
		if String(it[2]) != "":
			col.add_child(b)
			if it[0] == last_big:
				col.add_child(_gap(20))
				col.add_child(_rule())
				col.add_child(_gap(16))
			else:
				col.add_child(_gap(ITEM_GAP))
			continue
		if small_row == null:
			small_row = HBoxContainer.new()
			small_row.name = "SmallItems"
			small_row.add_theme_constant_override("separation", 12)
			small_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(small_row)
			col.add_child(_gap(10))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = 3.0 if it[0] == "settings" else 2.0
		small_row.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)
	var foot := _label(_footer_text(), _font(FONT_ITALIC, 450), 18, PARCH_DIM)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.modulate.a = 0.85
	col.add_child(foot)
	# соседние пункты по стрелкам (по кругу); переключатель времени суток — над первым пунктом;
	# «Настройки» и «Выход» в одной строке: вверх — «Игра с другом», вниз — время суток, между собой — ← →
	for i in _buttons.size():
		_buttons[i].focus_neighbor_top = _buttons[(i - 1 + _buttons.size()) % _buttons.size()].get_path()
		_buttons[i].focus_neighbor_bottom = _buttons[(i + 1) % _buttons.size()].get_path()
	var day := _light_board[LightPresets.DAY] as Button
	var dusk := _light_board[LightPresets.SUNSET] as Button
	# последний большой пункт («Игра с другом», а без неё — «Город: за кыпчаков»)
	var above := _item(last_big)
	var settings := _item("settings")
	var quit := _item("quit")
	for sb: Button in [day, dusk]:
		sb.focus_neighbor_bottom = _buttons[0].get_path()
		sb.focus_neighbor_top = settings.get_path()
	day.focus_neighbor_right = dusk.get_path()
	dusk.focus_neighbor_left = day.get_path()
	_buttons[0].focus_neighbor_top = day.get_path()
	above.focus_neighbor_bottom = settings.get_path()
	for b: Button in [settings, quit]:
		b.focus_neighbor_top = above.get_path()
		b.focus_neighbor_bottom = day.get_path()
	settings.focus_neighbor_right = quit.get_path()
	quit.focus_neighbor_left = settings.get_path()
	_build_settings()
	_build_online()
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
	_ui.resized.connect(_layout)
	_layout()


## Доска и листы («Настройки», «Игра с другом») по холсту (окно, масштаб интерфейса). Доска — во всю высоту
## экрана (на мелком масштабе — той же длины, что при 100 %, не тянется пустым орехом); пункты выше холста —
## ужимается целиком. Листы — _place_sheet: «Настройки» по высоте своих строк, «Игра с другом» — по высоте
## содержимого состояния (_place_online).
func _layout() -> void:
	var view := _ui.size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var need := _board_col.get_combined_minimum_size().y + COL_TOP + COL_BOTTOM + BOARD_TOP * 2.0
	var s := minf(1.0, view.y / need)
	_board.scale = Vector2(s, s)
	_board.position = Vector2(BOARD_X, BOARD_TOP) * s
	# высота холста при 100 % (множитель окна 1): доска до низа его, на мелком масштабе — не длиннее
	var full := view.y * minf(1.0, get_window().content_scale_factor)
	_board.size = Vector2(BOARD_W, minf(view.y / s, maxf(need, full)) - BOARD_TOP * 2.0)
	_shade.offset_right = SHADE_W * s
	if _sheet != null:
		_place_sheet(_sheet, Vector2(SHEET_W, _sheet_col.get_combined_minimum_size().y + SHEET_PAD.y * 2.0))
	_place_online()


## Лист «Игра с другом»: высоту даёт сам лист (по содержимому состояния), масштаб — по высоте хода лобби
## (friend_game.top_h: выбор, хозяин, подключение, справка), верх — вровень с доской (_place_sheet, top_h)
func _place_online() -> void:
	if _online_sheet == null:
		return
	_place_sheet(_online_sheet, Vector2(ONLINE_W, float(_online.call("sheet_height"))), float(_online.call("top_h")))
	_online.call("layout")


## Лист правее доски на SHEET_GAP и посередине её высоты; не выше полосы доски без полей (иначе ужат
## целиком через scale); правее не влезает — посередине экрана. top_h > 0 — лист «Игра с другом»: верх вровень с
## верхним краем доски во всех окнах, лист высотой top_h доходит ровно до нижнего края (строка «макет» под листом —
## на пейзаже под доской); сам лист короче — короче книзу. Масштаб такого листа — по top_h, а не по высоте сейчас:
## иначе на 150 % лист и весь текст на нём росли бы и мельчали при каждой смене состояния; ещё он ужимается, чтобы
## встать правее доски (на 150 % он крупнее, но доску не закрывает)
func _place_sheet(sheet: Control, sheet_size: Vector2, top_h := 0.0) -> void:
	var view := _ui.size
	var s := _board.scale.x
	var band_h := _board.size.y * s
	var avail := band_h if top_h > 0.0 else band_h - EDGE * 2.0 * s
	var ss := minf(1.0, minf((view.x - EDGE * 2.0) / sheet_size.x, avail / maxf(sheet_size.y, top_h)))
	var x := (BOARD_X + BOARD_W) * s + SHEET_GAP
	if top_h > 0.0:
		var right := (view.x - EDGE - x) / sheet_size.x
		if right >= 0.5:
			ss = minf(ss, right)
	sheet.scale = Vector2(ss, ss)
	sheet.size = sheet_size
	if x + sheet_size.x * ss > view.x - EDGE:
		x = (view.x - sheet_size.x * ss) * 0.5
	var y := _board.position.y + (band_h - sheet_size.y * ss) * 0.5
	if top_h > 0.0:
		y = _board.position.y
	sheet.position = Vector2(x, y)


## Пункт меню: дощечка (кнопка) с латунной рамкой; заголовок, подпись курсивом, герб стороны слева
func _item_button(it: Array) -> Button:
	var id: String = it[0]
	var big := String(it[2]) != ""
	var b := CityTips.TipButton.new()
	b.name = "Item_" + id
	b.tooltip_text = tr(String(ITEM_TIPS.get(id, "")))
	b.custom_minimum_size = Vector2(0, ITEM_BIG_H if big else ITEM_SMALL_H)
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
	if id == "online" and _tex("icons/crest_kokand") != null and _tex("icons/crest_kipchak") != null:
		# один значок из двух гербов — сами знаки, без кружков и без обводки: звезда Коканда и рога кыпчаков по
		# диагонали, весом как значки соседних пунктов
		var pair := CrestPair.new()
		pair.a = _tex("icons/crest_kokand")
		pair.b = _tex("icons/crest_kipchak")
		pair.custom_minimum_size = Vector2(64, 64)
		pair.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pair)
	elif icon_path != "" and _tex(icon_path) != null:
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
	# наконечник стрелы у выбранного пункта (курсор интерфейса — наконечник, ТЗ §12) — на одном месте у правого
	# края дощечки, не в строке: длинная подпись («Сражение») иначе выталкивала его на латунную рамку
	var mark := ArrowMark.new()
	mark.name = "Mark"
	mark.anchor_left = 1.0
	mark.anchor_right = 1.0
	mark.anchor_top = 0.5
	mark.anchor_bottom = 0.5
	mark.offset_left = -44.0
	mark.offset_right = -18.0
	mark.offset_top = -15.0
	mark.offset_bottom = 15.0
	mark.visible = false
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(mark)
	# «Игра с другом» горит, пока открыт её лист (фокус там, на листе)
	var lit := func(on: bool) -> void:
		on = on or (id == "online" and _online != null and _online.visible)
		mark.visible = on
		head.add_theme_color_override("font_color", BRASS if on else PARCH)
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	b.focus_entered.connect(lit.bind(true))
	b.focus_exited.connect(lit.bind(false))
	b.set_meta("item_lit", lit)
	return b


## Пункт доски по id («Item_<id>»)
func _item(id: String) -> Button:
	for b in _buttons:
		if b.name == "Item_" + id:
			return b
	return null


## Переключатель «Время суток: День | Закат» на доске: две дощечки встык, выбранная — латунь с тушью,
## другая — тёмный орех; у каждой рисованный знак (солнце высоко / солнце на горизонте)
func _light_switch() -> Control:
	var row := HBoxContainer.new()
	row.name = "LightSwitch"
	row.custom_minimum_size = Vector2(0, 56)
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := _label(tr("Время суток"), _font(FONT_HEAD), 30, PARCH)
	cap.add_theme_constant_override("outline_size", 4)
	cap.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02, 0.9))
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.custom_minimum_size = Vector2(206, 0)
	row.add_child(cap)
	var group := ButtonGroup.new()
	for mode: String in [LightPresets.DAY, LightPresets.SUNSET]:
		var b := _light_button(mode, group, mode == LightPresets.DAY, 36, 26)
		b.name = "Light_" + mode
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		_light_board[mode] = b
	_sync_light()
	return row


## Дощечка времени суток: [знак] Название; left — левая половина пары (скругления снаружи)
func _light_button(mode: String, group: ButtonGroup, left: bool, font_size: int, icon_size: int) -> Button:
	var b := CityTips.TipButton.new()
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 56)
	b.tooltip_text = tr(LightPresets.mode_name(mode)) + "\n" + (tr("Солнце высоко, свет ровный и светлый")
		if mode == LightPresets.DAY else tr("Низкое солнце, тёплый свет и длинные тени — как в срезе стиля"))
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, _seg_box(st, left))
	b.toggled.connect(func(on: bool) -> void:
		if on:
			_set_light(mode))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var mark := SunMark.new()
	mark.name = "Mark"
	mark.sunset = mode == LightPresets.SUNSET
	mark.custom_minimum_size = Vector2(icon_size + 6, icon_size)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mark)
	var head := _label(tr(LightPresets.mode_name(mode)), _font(FONT_HEAD), font_size, PARCH)
	head.name = "Head"
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(head)
	var lit := func() -> void:
		var on := b.button_pressed
		head.add_theme_color_override("font_color", INK if on else (BRASS if b.has_focus() else PARCH_DIM))
		mark.on = on
		mark.queue_redraw()
	b.toggled.connect(func(_on: bool) -> void: lit.call())
	b.focus_entered.connect(lit)
	b.focus_exited.connect(lit)
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	b.set_meta("lit", lit)
	return b


## Половина пары: выбранная — латунь, другая — тёмный орех; рамка латунная, снаружи скруглено
func _seg_box(state: String, left: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var on := state in ["pressed", "hover_pressed"]
	sb.bg_color = Color("#d5ad62") if on else (Color("#5a3a22") if state == "hover" else Color("#3a2414"))
	sb.border_color = BRASS if state in ["hover", "focus", "hover_pressed"] else BRASS_DIM
	sb.set_border_width_all(2)
	var r := 10
	sb.corner_radius_top_left = r if left else 0
	sb.corner_radius_bottom_left = r if left else 0
	sb.corner_radius_top_right = 0 if left else r
	sb.corner_radius_bottom_right = 0 if left else r
	sb.set_content_margin_all(6)
	if state == "focus":
		sb.draw_center = false
		sb.set_border_width_all(3)
	return sb


func _on_light_mode_changed(_mode: String) -> void:
	_sync_light()


func _set_light(mode: String) -> void:
	if _ordo:
		_ordo.call("set_light_mode", mode)
	_sync_light()


func _sync_light() -> void:
	var cur: String = String(_ordo.get("light_mode")) if _ordo else LightPresets.DAY
	for d: Dictionary in [_light_board, _light_settings]:
		for m: String in d:
			var b := d[m] as Button
			b.set_pressed_no_signal(m == cur)
			if b.has_meta("lit"):
				(b.get_meta("lit") as Callable).call()


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


## Подпись внизу доски: у установщика — «Версия 0.1.N» (тем же словом, что в «Игре с другом»: друзья сверяют
## версии), при запуске из Godot — «рабочая сборка»
func _footer_text() -> String:
	var v := String(ProjectSettings.get_setting("application/config/version", ""))
	return (tr("Версия %s · Godot 4.7") % v) if v != "" else tr("Godot 4.7 · рабочая сборка")


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
	# место и размер листа — _layout (по высоте строк и по холсту)
	var sheet := Control.new()
	sheet.name = "Sheet"
	sheet.position = Vector2(BOARD_X + BOARD_W + SHEET_GAP, BOARD_TOP)
	sheet.size = Vector2(SHEET_W, 780)
	_settings.add_child(sheet)
	_sheet = sheet
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
	col.offset_left = SHEET_PAD.x
	col.offset_right = -SHEET_PAD.x
	col.offset_top = SHEET_PAD.y
	col.offset_bottom = -SHEET_PAD.y
	col.add_theme_constant_override("separation", 10)
	sheet.add_child(col)
	_sheet_col = col
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
		var qb := CityTips.TipButton.new()
		qb.text = tr(WorldQuality.NAMES[lv])
		qb.tooltip_text = _quality_tip(lv)
		qb.toggle_mode = true
		qb.custom_minimum_size = Vector2(170, 54)
		qb.add_theme_font_override("font", _font(FONT_HEAD))
		qb.add_theme_font_size_override("font_size", 26)
		qb.pressed.connect(_set_quality.bind(lv))
		qrow.add_child(qb)
		qb.name = "Quality_" + lv
		_q_buttons[lv] = qb
	col.add_child(_label(tr("В игре — клавиша F2. «Низкое» — для слабых компьютеров."), _font(FONT_ITALIC, 480), 20, INK_SOFT))
	col.add_child(_gap(8))
	# время суток — то же, что переключатель на доске
	col.add_child(_label(tr("Время суток"), _font(FONT_HEAD), 28, INK))
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 0)
	col.add_child(lrow)
	var lgroup := ButtonGroup.new()
	for mode: String in [LightPresets.DAY, LightPresets.SUNSET]:
		var lb := _light_button(mode, lgroup, mode == LightPresets.DAY, 30, 22)
		lb.name = "SetLight_" + mode
		lb.custom_minimum_size = Vector2(210, 54)
		lrow.add_child(lb)
		_light_settings[mode] = lb
	col.add_child(_label(tr("Для «Сражения» и «Города». Закат — как в срезе стиля."), _font(FONT_ITALIC, 480), 20, INK_SOFT))
	col.add_child(_gap(8))
	# масштаб интерфейса: ползунок 75–150 %; холст перестраивается, когда ползунок отпущен
	# (иначе лист с ползунком ужимался бы прямо под мышью), а клавишами — через миг после последнего
	# нажатия; колесо мыши ползунок не двигает (крутили бы, листая)
	col.add_child(_label(tr("Масштаб интерфейса"), _font(FONT_HEAD), 28, INK))
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 16)
	col.add_child(srow)
	_scale = HSlider.new()
	_scale.name = "UiScale"
	_scale.min_value = 75.0
	_scale.max_value = 150.0
	_scale.step = 5.0
	_scale.tick_count = 4
	_scale.ticks_on_borders = true
	_scale.scrollable = false
	_scale.custom_minimum_size = Vector2(0, 32)
	_scale.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scale.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scale.value = roundf(float(_ordo.get("ui_scale")) * 100.0) if _ordo else 100.0
	_scale.tooltip_text = tr("Крупнее или мельче весь интерфейс: 75–150 %, шаг 5 %. Стрелки ← → — тоже")
	srow.add_child(_scale)
	_scale_txt = _label("", _font(FONT_TEXT, 700), 26, INK)
	_scale_txt.custom_minimum_size = Vector2(86, 0)
	_scale_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	srow.add_child(_scale_txt)
	_scale_wait = Timer.new()
	_scale_wait.one_shot = true
	_scale_wait.wait_time = SCALE_WAIT
	_scale_wait.timeout.connect(_apply_ui_scale)
	_scale.add_child(_scale_wait)
	_scale.drag_started.connect(func() -> void: _scale_drag = true)
	_scale.drag_ended.connect(func(_changed: bool) -> void:
		_scale_drag = false
		_scale_wait.stop()
		_apply_ui_scale())
	_scale.value_changed.connect(func(_v: float) -> void:
		_show_ui_scale()
		if not _scale_drag:
			_scale_wait.start())
	_show_ui_scale()
	col.add_child(_label(tr("Крупнее или мельче — в «Сражении» и «Городе».\nМеню и так во всю высоту экрана — крупнее не станет."),
		_font(FONT_ITALIC, 480), 20, INK_SOFT))
	col.add_child(_gap(8))
	# громкость (звука пока нет — ползунок уже запоминается)
	col.add_child(_label(tr("Громкость"), _font(FONT_HEAD), 28, INK))
	_volume = HSlider.new()
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.05
	_volume.custom_minimum_size = Vector2(0, 32)
	_volume.value = float(_ordo.get("volume")) if _ordo else 0.8
	_volume.tooltip_text = tr("Громкость всей игры")
	_volume.value_changed.connect(func(v: float) -> void:
		if _ordo:
			_ordo.call("set_volume", v))
	col.add_child(_volume)
	col.add_child(_label(tr("Звук появится в следующих сборках."), _font(FONT_ITALIC, 480), 20, INK_SOFT))
	col.add_child(_gap(8))
	_full = CheckButton.new()
	_full.text = tr("Во весь экран")
	_full.tooltip_text = tr("Игра на весь экран или в окне")
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
	col.add_child(_gap(10))
	var done := CityTips.TipButton.new()
	done.text = tr("Готово")
	done.tooltip_text = tr("Готово\nЗакрыть настройки (Esc) — всё уже запомнено")
	done.custom_minimum_size = Vector2(220, 58)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done.add_theme_font_override("font", _font(FONT_HEAD))
	done.add_theme_font_size_override("font_size", 30)
	done.pressed.connect(_close_settings)
	col.add_child(done)
	_sync_quality()
	_sync_light()


## Кадр проверки подсказки (--menu_tip=Имя): событие движения мыши на середину узла — Godot покажет его
## подсказку (настоящая мышь не двигается)
func _hover_tip(node_name: String) -> void:
	var c := _ui.find_child(node_name, true, false) as Control
	if c == null or not c.is_visible_in_tree():
		print("[меню] подсказка: нет узла ", node_name)
		return
	var ev := InputEventMouseMotion.new()
	ev.position = c.get_global_rect().get_center()
	ev.global_position = ev.position
	# настоящий курсор может быть вне окна съёмки — окно должно считать, что мышь над ним
	get_viewport().notification(NOTIFICATION_VP_MOUSE_ENTER)
	get_viewport().push_input(ev, true)


## Число у ползунка масштаба: «125 %»
func _show_ui_scale() -> void:
	_scale_txt.text = "%d %%" % int(roundf(_scale.value))


## Ползунок отпущен (или сдвинут клавишами): масштаб — Ordo (запоминается), холст перестроится сам
func _apply_ui_scale() -> void:
	if _ordo:
		_ordo.call("set_ui_scale", _scale.value / 100.0)


func _on_ui_scale_changed(s: float) -> void:
	if not _scale_drag:
		_scale.set_value_no_signal(roundf(s * 100.0))
		_show_ui_scale()


func _open_settings() -> void:
	_sync_quality()
	_sync_light()
	# листы не лежат друг на друге: открытая «Игра с другом» закрывается
	if _online != null and _online.visible:
		_online.visible = false
	_settings.visible = true
	_board_focus(false)
	var cur: String = _ordo.get("quality") if _ordo else WorldQuality.HIGH
	(_q_buttons.get(cur, _q_buttons[WorldQuality.HIGH]) as Button).grab_focus()


func _close_settings() -> void:
	_settings.visible = false
	_board_focus(true)
	# пункт ищем по имени: номер в _buttons меняется, когда на доске появляется новый пункт
	_item("settings").grab_focus()


## Пока открыт лист, доска за затемнением не берёт фокус с клавиатуры (Tab, стрелки): иначе Enter запустил
## бы пункт под листом (мышь и так не проходит сквозь затемнение)
func _board_focus(on: bool) -> void:
	_board.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED if on else Control.FOCUS_BEHAVIOR_DISABLED


## «Игра с другом» на доске — всегда (и в установщике: игра по сети работает, решение 2026-10-16)
func _online_on() -> bool:
	return true


## Лист «Игра с другом» — макет (выдуманные адреса, кнопки листают состояния, сети нет): ключ --online_mock=1;
## без ключа — только кадры состояний (--menu_online=…): в кадр не попадают настоящие адреса, Windows не спросит
## про сеть. --online_mock=0 — настоящая сеть всегда
func _online_mock() -> bool:
	if _ordo == null:
		return false
	if _ordo.has_arg("online_mock"):
		return String(_ordo.arg("online_mock")) != "0"
	return _ordo.has_arg("menu_online")


func _set_quality(lv: String) -> void:
	if _ordo:
		_ordo.call("set_quality", lv)
	_sync_quality()


## Подсказка уровня качества — из его чисел (WorldQuality.PRESETS)
func _quality_tip(lv: String) -> String:
	var p: Dictionary = WorldQuality.PRESETS.get(lv, {})
	var lines := PackedStringArray([tr(WorldQuality.NAMES.get(lv, lv))])
	lines.append(tr("Разрешение 3D %d %% · трава %d %%") % [roundi(float(p.get("scale", 1.0)) * 100.0),
		roundi(float(p.get("grass_density", 1.0)) * 100.0)])
	lines.append(tr("Тени до %d м · %s") % [roundi(float(p.get("shadow_dist", 0.0))),
		tr("объёмный туман") if bool(p.get("volfog", false)) else tr("без объёмного тумана")])
	if lv == WorldQuality.LOW:
		lines.append(tr("Для слабых компьютеров"))
	return "\n".join(lines)


func _sync_quality() -> void:
	var cur: String = _ordo.get("quality") if _ordo else WorldQuality.HIGH
	for lv: String in _q_buttons:
		(_q_buttons[lv] as Button).set_pressed_no_signal(lv == cur)


# ---------------------------------------------------------------- игра с другом (макет)

## Лист «Игра с другом» — макет лобби (friend_game.gd, без class_name: грузится здесь, берёт у меню
## шрифты, картинки и цвета)
func _build_online() -> void:
	_online = (load(FRIEND_GAME) as GDScript).new() as Control
	_online.name = "Online"
	_ui.add_child(_online)
	_online.call("setup", self)
	_online_sheet = _online.get("sheet") as Control


## Открыть макет в состоянии state (вариант alt); «Игра с другом» на доске остаётся подсвеченной
func _open_online(state := "choose", alt := 0) -> void:
	if _settings.visible:
		_settings.visible = false
	_board_focus(false)
	_online.call("open", state, alt)
	var b := _item("online")
	if b:
		(b.get_meta("item_lit") as Callable).call(false)


func _close_online() -> void:
	_online.visible = false
	_board_focus(true)
	var b := _item("online")
	if b == null:
		_buttons[0].grab_focus()
		return
	b.grab_focus()
	(b.get_meta("item_lit") as Callable).call(true)


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
	# переключатель крупный и контрастный (ТЗ 11.2): выкл — тёмная дорожка, вкл — латунь
	th.set_icon("unchecked", "CheckButton", _switch_icon(false))
	th.set_icon("checked", "CheckButton", _switch_icon(true))
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
	# поле ввода «Адрес друга» (friend_game.TipLine): полоску, курсор и образец оно рисует само — от темы только
	# цвет адреса тушью и выделение латунью
	th.set_color("font_color", "LineEdit", INK)
	th.set_color("font_selected_color", "LineEdit", INK)
	th.set_color("selection_color", "LineEdit", Color(BRASS.r, BRASS.g, BRASS.b, 0.5))
	# подсказка — бумажная записка, тушь (как у «Города», UiTheme)
	th.set_stylebox("panel", "TooltipPanel", UiTheme.tip_box())
	th.set_font("font", "TooltipLabel", _font(FONT_TEXT, 500))
	th.set_font_size("font_size", "TooltipLabel", 17)
	th.set_color("font_color", "TooltipLabel", INK)
	th.set_color("font_shadow_color", "TooltipLabel", Color(0, 0, 0, 0))
	return th


## Значок переключателя 64×32: дорожка-капсула с ободком и головка (вкл — справа, латунная)
static func _switch_icon(on: bool) -> Texture2D:
	const W := 64
	const H := 32
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var r := H * 0.5 - 1.0
	var knob := Vector2(W - H * 0.5, H * 0.5) if on else Vector2(H * 0.5, H * 0.5)
	var track := BRASS_DIM if on else Color(INK_SOFT.r, INK_SOFT.g, INK_SOFT.b, 0.45)
	var rim := INK
	var head := BRASS if on else PARCH
	for y in H:
		for x in W:
			var p := Vector2(x + 0.5, y + 0.5)
			# расстояние до капсулы: отрезок между центрами торцов
			var cx := clampf(p.x, H * 0.5, W - H * 0.5)
			var d := p.distance_to(Vector2(cx, H * 0.5)) - r
			var c := Color(0, 0, 0, 0)
			if d < 0.0:
				c = track
			if absf(d + 1.0) < 1.2:
				c = rim
			var dk := p.distance_to(knob) - (r - 3.0)
			if dk < 0.0:
				c = head
			if absf(dk) < 1.0:
				c = rim
			var a := clampf(0.5 - maxf(d, -1.0e9), 0.0, 1.0) if d > -0.5 else 1.0
			c.a *= a
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


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


## Значок «Игры с другом»: два знака сторон без подложки и без обводки, по диагонали — звезда Коканда слева
## вверху, рога кыпчаков справа внизу, чуть внахлёст (рога поверх: они тонкие, звезда видна сквозь них). Каждый
## знак — K от своего одиночного значка у соседних пунктов (та же картинка, 64): пара весит как один значок.
## Рамка обоих знаков — по их непрозрачным точкам (у рогов поля картинки шире, знак смещён) — ровно посередине
## места значка, как одиночные значки соседних дощечек
class CrestPair extends Control:
	const K := 0.72
	## Центры знаков от середины, в долях места значка: звезда левее и выше, рога правее и ниже
	const SPREAD := Vector2(0.18, 0.16)
	var a: Texture2D
	var b: Texture2D
	var _used := {}

	func _draw() -> void:
		if a == null or b == null:
			return
		var s := minf(size.x, size.y)
		var k := s * K
		var ua := _used_rect(a)
		var ub := _used_rect(b)
		var fa := k / float(a.get_width())
		var fb := k / float(b.get_width())
		# картинка ставится так, чтобы середина знака (а не картинки) встала в свою точку диагонали
		var pa := -SPREAD * s - ua.get_center() * fa
		var pb := SPREAD * s - ub.get_center() * fb
		var box := Rect2(pa + ua.position * fa, ua.size * fa).merge(Rect2(pb + ub.position * fb, ub.size * fb))
		var shift := size * 0.5 - box.get_center()
		draw_texture_rect(a, Rect2(pa + shift, Vector2(k, k)), false)
		draw_texture_rect(b, Rect2(pb + shift, Vector2(k, k)), false)

	## Непрозрачная часть картинки (в её точках); не прочитать — вся картинка
	func _used_rect(t: Texture2D) -> Rect2:
		if _used.has(t):
			return _used[t]
		var r := Rect2(Vector2.ZERO, t.get_size())
		var img := t.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			var u := img.get_used_rect()
			if u.size.x > 0 and u.size.y > 0:
				var sc := t.get_size() / Vector2(img.get_size())
				r = Rect2(Vector2(u.position) * sc, Vector2(u.size) * sc)
		_used[t] = r
		return r


## Рисованный знак времени суток: день — солнце с лучами; закат — полдиска над чертой горизонта.
## on — дощечка выбрана (тушь по латуни), иначе — латунь по ореху
class SunMark extends Control:
	var sunset := false
	var on := false

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var ink := Color("#2b1a10") if on else Color("#e2bf72")
		var fill := Color("#fff1c9") if on else Color("#e2bf72")
		if not sunset:
			var c := Vector2(w * 0.5, h * 0.5)
			var r := h * 0.24
			for i in 8:
				var a := TAU * float(i) / 8.0
				var d := Vector2(cos(a), sin(a))
				draw_line(c + d * (r + 2.5), c + d * (h * 0.48), ink, 2.0, true)
			draw_circle(c, r, fill)
			draw_arc(c, r, 0.0, TAU, 24, ink, 1.6, true)
		else:
			var base := h * 0.74
			var c := Vector2(w * 0.5, base)
			var r := h * 0.3
			for i in 5:
				var a := PI + PI * float(i + 1) / 6.0
				var d := Vector2(cos(a), sin(a))
				draw_line(c + d * (r + 2.5), c + d * (r + h * 0.2), ink, 2.0, true)
			var pts := PackedVector2Array()
			for i in 13:
				var a := PI + PI * float(i) / 12.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, Color("#e07a3a") if on else Color("#f2a35a"))
			pts.append(pts[0])
			draw_polyline(pts, ink, 1.6, true)
			draw_line(Vector2(1.0, base), Vector2(w - 1.0, base), ink, 2.0, true)
