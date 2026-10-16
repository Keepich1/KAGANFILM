class_name NetHud
extends Control
## Записки игры по сети поверх интерфейса «Города» (ТЗ §16, стиль записок ТЗ 11.1/12; владелец — NET). Ставит
## GorodPlay, когда у драйвера партия по сети (GameDriver.net). Читает NetMatch 10 раз в секунду.
##
## Записка у балки (полоска бумаги с сургучной печатью посередине под балкой — там, где в игре против ИИ висит
## табличка набега: в игре двух людей набегов нет; ширина — по самой длинной строке):
##   золотая — «Друг поставил паузу» / «Пауза у обоих», «Друг открыл меню — игра стоит у обоих», «Ждём друга — у
##             него ещё загружается игра…», «Ждём друга…» (приказы друга запаздывают дольше секунды), «Связь
##             медленная — приказы будут чуть запаздывать.», «Друг сменил скорость: ×2», «Друг вышел из игры»
##             (после конца партии);
##   зелёная — «Друг снова на связи», «Друг снял паузу».
## Лист под балкой — связь пропала: «Ждём друга…» с красной печатью (как «Связь с другом пропала» в лобби): что
## случилось, когда ждать бесполезно (друг закрыл «Ордо» или вышел — тогда «Выйти»), «ждём уже 0:42» и «Выйти»
## (сперва «Выйти из партии?» — «Остаться» / «Выйти»).
## Лист посреди экрана (как конец партии; высота — по тексту) — партию продолжить нельзя: «Друг вышел из игры»,
## «Партия остановлена» (игры разошлись: почему и что делать); записи партии — кнопка «Открыть папку» (путь — в
## её подсказке), «В главное меню».
## Мелкие строки курсивом в мелком окне (записка на экране мельче SMALL_K) и при масштабе интерфейса от BIG_UI —
## плотнее и на точку крупнее (как в лобби «Игра с другом»).

## Записка у балки: ширина (наименьшая и наибольшая), высота, сверху под балкой
const PIN_W := 640.0
const PIN_W_MAX := 940.0
const PIN_H := 64.0
const PIN_TOP := 84.0
## Лист «Ждём друга…» под балкой
const WAIT_W := 720.0
## Лист посреди экрана и «Выйти из партии?» — ширина (высота — по тексту)
const END_W := 720.0
const CONFIRM_W := 580.0
const HZ := 0.1
## Записка «Ждём друга…» — если приказы друга запаздывают дольше, мс
const STALL_MS := 1000
## «Связь медленная» держится столько секунд и напоминает о себе не чаще раза в SLOW_EVERY
const SLOW_HOLD := 8.0
const SLOW_EVERY := 60.0
const BACK_HOLD := 4.0
const SPEED_HOLD := 4.0
## Мелкие строки плотнее: записка на экране мельче SMALL_K или масштаб интерфейса от BIG_UI
const SMALL_K := 0.8
const BIG_UI := 1.25

var hud: CityHud
var driver: GameDriver

var _pin: NinePatchRect
var _pin_seal: TextureRect
var _pin_col: VBoxContainer
var _pin_text: Label
var _pin_sub: Label
var _pin_w := PIN_W
var _wait: Control
var _wait_lbl: Label
var _end: Control
var _confirm: Control
var _key := ""
var _t := 0.0
var _clock := 0.0
var _slow_next := 0.0
var _back_seen := 0
var _flash_key := ""
var _flash_until := -1.0
var _small := false
## Строки курсивом (мелкие) — их делает плотнее _restyle (без типа: среди них бывают уже освобождённые)
var _ital: Array = []


## Поставить записки поверх интерфейса (в его корень — тема и масштаб те же)
static func attach(p_hud: CityHud, p_driver: GameDriver) -> NetHud:
	var n := NetHud.new()
	n.name = "NetHud"
	n.hud = p_hud
	n.driver = p_driver
	n.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p_hud.root.add_child(n)
	# под меню паузы и экраном конца партии (они — окна поверх игры: CityHud.modal_open считает всё, что после меню;
	# записки связи окном не считаются — обычные записки «Города» не прячутся)
	if p_hud.menu != null:
		p_hud.root.move_child(n, p_hud.menu.get_index())
	n._build()
	return n


func _build() -> void:
	_small = _is_small()
	_pin = NinePatchRect.new()
	_pin.name = "NetPin"
	_pin.texture = UiTheme.tex("note")
	_pin.patch_margin_left = 26
	_pin.patch_margin_right = 26
	_pin.patch_margin_top = 20
	_pin.patch_margin_bottom = 20
	_pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin.visible = false
	add_child(_pin)
	_pin_seal = TextureRect.new()
	_pin_seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pin_seal.position = Vector2(6, 3)
	_pin_seal.size = Vector2(58, 58)
	_pin_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin.add_child(_pin_seal)
	_pin_col = VBoxContainer.new()
	_pin_col.position = Vector2(72, 6)
	_pin_col.size = Vector2(PIN_W - 96, PIN_H - 14)
	_pin_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_pin_col.add_theme_constant_override("separation", -4)
	_pin_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin.add_child(_pin_col)
	_pin_text = UiTheme.label("", UiTheme.text(650), 21, true)
	_pin_text.clip_text = true
	_pin_col.add_child(_pin_text)
	_pin_sub = _italic("", 18)
	_pin_sub.clip_text = true
	_pin_col.add_child(_pin_sub)
	_layout()
	resized.connect(_layout)
	_refresh(true)
	# кадры (--net_demo_open, вместе с --net_demo): menu — меню паузы, menu_quit — «Выйти из партии?» в нём,
	# quit — «Выйти из партии?» листа «Ждём друга…» (--net_demo=lost)
	var o := get_node_or_null("/root/Ordo")
	if o != null and bool(o.call("has_arg", "net_demo_open")):
		_demo_open(String(o.call("arg", "net_demo_open")))


func _demo_open(what: String) -> void:
	await get_tree().create_timer(0.5).timeout
	match what:
		"menu", "menu_quit":
			hud.open_menu()
			if what == "menu_quit":
				hud.menu.call("_quit")
		"quit":
			_ask_quit()


func _process(delta: float) -> void:
	_clock += delta
	_t += delta
	if _t < HZ:
		return
	_t = 0.0
	_refresh(false)


## Состояние партии → какая записка или лист сейчас
func _refresh(force: bool) -> void:
	var m := driver.net
	if m == null:
		return
	var key := _state(m)
	if key == _key and not force:
		if is_instance_valid(_wait_lbl) and key.begins_with("lost"):
			_wait_lbl.text = _waited(m)
		return
	_key = key
	_show(key, m)


func _state(m: NetMatch) -> String:
	if m.over:
		return "over_left" if m.link == &"left" else "over"
	match m.link:
		&"desync":
			return "desync"
		&"left":
			return "left"
		&"lost":
			return "lost_guest" if m.reconnecting() else "lost"
	if not m.peer_ready:
		return "loading"
	if m.paused:
		if m.pause_by != m.local:
			return "menu_friend" if m.friend_menu else "paused_friend"
		return "paused_me"
	# короткие записки: друг вернулся, друг снял паузу, сменил скорость, связь медленная (не чаще раза в SLOW_EVERY)
	if m.back_at_ms > 0 and m.back_at_ms != _back_seen:
		_back_seen = m.back_at_ms
		_flash("back", BACK_HOLD)
	if m.resumed_by_friend:
		m.resumed_by_friend = false
		_flash("resumed", 3.0)
	if m.speed_by_friend > 0.0:
		_flash("speed:" + _speed_text(m.speed_by_friend), SPEED_HOLD)
		m.speed_by_friend = 0.0
	if m.stall_ms() >= STALL_MS:
		return "waiting"
	if m.slow() and _clock >= _slow_next:
		_slow_next = _clock + SLOW_EVERY
		_flash("slow", SLOW_HOLD)
	if _clock < _flash_until:
		return _flash_key
	return ""


func _flash(key: String, hold: float) -> void:
	_flash_key = key
	_flash_until = _clock + hold


## Скорость для записки: «2», «0.5» (как на кнопке скорости на балке)
static func _speed_text(s: float) -> String:
	return str(snappedf(s, 0.01)).trim_suffix(".0")


func _show(key: String, m: NetMatch) -> void:
	_pin.visible = false
	if is_instance_valid(_wait):
		_drop(_wait)
		_wait = null
		_wait_lbl = null
	if not key.begins_with("lost"):
		_close_confirm()
	match key:
		"paused_friend":
			_put("gold", tr("Друг поставил паузу"), tr("P или кнопка паузы вверху справа — продолжить игру у обоих"))
		"paused_me":
			_put("gold", tr("Пауза у обоих — друг тоже ждёт"), tr("P или кнопка паузы вверху справа — продолжить"))
		"menu_friend":
			_put("gold", tr("Друг открыл меню — игра стоит у обоих"), tr("Пойдёт дальше, когда друг закроет меню"))
		"loading":
			_put("gold", tr("Ждём друга — у него ещё загружается игра…"), tr("Партия начнётся у обоих сразу"))
		"waiting":
			_put("gold", tr("Ждём друга…"), tr("Его приказы запаздывают — игра пойдёт дальше, как только они придут"))
		"slow":
			_put("gold", tr("Связь медленная — приказы будут чуть запаздывать."), tr("Так бывает, когда далеко или сеть занята"))
		"back":
			_put("green", tr("Друг снова на связи — играем дальше"), "")
		"resumed":
			_put("green", tr("Друг снял паузу — играем дальше"), "")
		"over_left":
			_put("gold", tr("Друг вышел из игры"), "")
		"lost", "lost_guest":
			_show_wait(m)
		"left":
			_show_end(m, false)
		"desync":
			_show_end(m, true)
		_:
			if key.begins_with("speed:"):
				_put("gold", tr("Друг сменил скорость: ×%s") % key.get_slice(":", 1),
					tr("Скорость общая: + и − меняют её у обоих"))


## Записка у балки: печать, строка и строка мельче; ширина — по длинной строке
func _put(seal: String, text: String, sub: String) -> void:
	_pin_seal.texture = UiTheme.tex("seal_" + seal)
	_pin_text.text = text
	_pin_sub.text = sub
	_pin_sub.visible = sub != ""
	var need := maxf(_line_w(_pin_text), _line_w(_pin_sub) if sub != "" else 0.0)
	_pin_w = clampf(need + 72.0 + 34.0, PIN_W, PIN_W_MAX)
	_pin.visible = true
	_layout()


static func _line_w(l: Label) -> float:
	return l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x


# ================================================================= связь пропала: лист под балкой

func _show_wait(m: NetMatch) -> void:
	var p := _paper("NetWait")
	add_child(p)
	_frame(p)
	var seal := TextureRect.new()
	seal.texture = UiTheme.tex("seal_red")
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.position = Vector2(26, 22)
	seal.size = Vector2(66, 66)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(seal)
	var star := Star.new()
	star.position = Vector2(WAIT_W - 70, 24)
	star.size = Vector2(38, 38)
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star.still = _shot()
	p.add_child(star)
	# столбец: заголовок, что случилось, когда ждать бесполезно; внизу — сколько ждём и «Выйти»
	var col := VBoxContainer.new()
	col.position = Vector2(108, 22)
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(col)
	col.add_child(UiTheme.label(tr("Ждём друга…"), UiTheme.head_bold(), 34, true))
	col.add_child(_wrapped(_lost_text(m), UiTheme.text(560), 20))
	col.add_child(_italic(_lost_hint(m), 18, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(row)
	_wait_lbl = _italic(_waited(m), 18)
	_wait_lbl.name = "NetWaited"
	_wait_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wait_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_wait_lbl)
	var b := _button("NetQuit", tr("Выйти"), tr("Выйти из партии в главное меню — продолжить её будет нельзя"), Vector2(200, 50), 22)
	b.pressed.connect(_ask_quit)
	row.add_child(b)
	var cw := WAIT_W - 140.0
	var h := _col_height(col, cw)
	col.size = Vector2(cw, h)
	p.size = Vector2(WAIT_W, h + 44.0)
	_wait = p
	_layout()


## Что с другом: у хозяина — ждём, пока друг подключится; у подключившегося — стучимся снова сами
func _lost_text(m: NetMatch) -> String:
	if m.reconnecting():
		return tr("Связь с другом пропала — подключаемся снова. Игра стоит на том же месте и пойдёт дальше, когда связь вернётся.")
	return tr("Связь с другом пропала. Игра стоит на том же месте и пойдёт дальше, когда друг подключится снова — он сделает это сам.")


## Когда ждать бесполезно: игра друга закрыта — партию не продолжить (сохранения нет)
func _lost_hint(m: NetMatch) -> String:
	if m.reconnecting():
		return tr("Если друг закрыл «Ордо» или вышел, подключиться не выйдет — тогда нажмите «Выйти».")
	return tr("Если друг закрыл «Ордо» или вышел, он не вернётся — тогда нажмите «Выйти».")


## «ждём уже 0:42» — с тех пор, как пропала связь
func _waited(m: NetMatch) -> String:
	var s := m.lost_sec()
	return tr("ждём уже %d:%02d") % [s / 60, s % 60]


# ================================================================= «Выйти из партии?»

## «Выйти» на листе «Ждём друга…»: выйти можно только насовсем — спросить ещё раз («Остаться» — первой)
func _ask_quit() -> void:
	if is_instance_valid(_confirm):
		return
	var root := _dimmed("NetConfirm")
	var sheet := _paper("Sheet")
	root.add_child(sheet)
	_frame(sheet)
	var col := VBoxContainer.new()
	col.position = Vector2(48, 32)
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	sheet.add_child(col)
	var title := UiTheme.label(tr("Выйти из партии?"), UiTheme.head_bold(), 40, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var body := _wrapped(tr("Продолжить эту партию потом будет нельзя."), UiTheme.text(560), 21)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(row)
	var stay := _button("NetStay", tr("Остаться"), tr("Ждать друга дальше"), Vector2(200, 54), 22)
	stay.pressed.connect(_close_confirm)
	row.add_child(stay)
	var go := _button("NetQuitNow", tr("Выйти"), tr("Выйти из партии в главное меню насовсем"), Vector2(200, 54), 22)
	go.pressed.connect(_quit)
	row.add_child(go)
	var cw := CONFIRM_W - 96.0
	var h := _col_height(col, cw)
	col.size = Vector2(cw, h)
	_confirm = root
	hud.add_dialog(sheet, Vector2(CONFIRM_W, h + 64.0))


func _close_confirm() -> void:
	if is_instance_valid(_confirm):
		_drop(_confirm)
	_confirm = null


## Убрать лист в конце кадра; имя — сразу другое: новый лист с тем же именем ставится в том же кадре
static func _drop(n: Node) -> void:
	n.name = "%s_old%d" % [n.name, n.get_instance_id()]
	n.queue_free()


# ================================================================= партию продолжить нельзя: лист посреди экрана

func _show_end(m: NetMatch, desync: bool) -> void:
	if is_instance_valid(_end):
		_drop(_end)
	_close_confirm()
	var root := _dimmed("NetEnd")
	var w := END_W
	var sheet := _paper("Sheet")
	root.add_child(sheet)
	_frame(sheet)
	var seal := TextureRect.new()
	seal.texture = UiTheme.tex("seal_red")
	seal.position = Vector2(w * 0.5 - 40, -34)
	seal.size = Vector2(80, 80)
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(seal)
	var text := ""
	var small := ""
	# что показать в папке: свой повтор разошедшейся партии (рядом — повтор друга) или запись партии
	var path := NetMatch.last_path
	if desync:
		text = tr("Игры у вас и у друга разошлись — дальше каждый видел бы своё. Так бывает, если один из вас на Windows, а другой на Linux, или из-за ошибки в игре. Начните новую партию; если повторится — отправьте автору игры записи партии.")
		small = tr("Записи партии сохранены — их покажет «Открыть папку».")
		path = m.saved[0] if not m.saved.is_empty() else NetMatch.DIR
	else:
		text = tr("Друг нажал «В главное меню» или закрыл «Ордо» — эту партию продолжить нельзя.")
		small = tr("Запись партии сохранена — её покажет «Открыть папку».")
	var where := ProjectSettings.globalize_path(path)
	# столбец: заголовок, что случилось и что делать, где записи; кнопки — внизу
	var col := VBoxContainer.new()
	col.position = Vector2(56, 54)
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	sheet.add_child(col)
	var title := UiTheme.label(tr("Партия остановлена") if desync else tr("Друг вышел из игры"), UiTheme.head_bold(), 50, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var body := _wrapped(text, UiTheme.text(560), 22)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(body)
	var note := _italic(small, 18, true)
	note.name = "NetSaved"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.tooltip_text = where
	note.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(note)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(row)
	var folder := _button("NetFolder", tr("Открыть папку"), where, Vector2(250, 58), 24)
	folder.pressed.connect(_open_folder.bind(path))
	row.add_child(folder)
	var menu := _button("NetMenu", tr("В главное меню"), tr("Выйти из партии в главное меню"), Vector2(260, 58), 24)
	menu.pressed.connect(_quit)
	row.add_child(menu)
	var cw := w - 112.0
	var h := _col_height(col, cw)
	col.size = Vector2(cw, h)
	_end = root
	hud.add_dialog(sheet, Vector2(w, 54.0 + h + 38.0))


## Показать записи партии в Проводнике (файл — выделен); файла нет — открыть папку записей
func _open_folder(path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path) or DirAccess.dir_exists_absolute(abs_path):
		OS.shell_show_in_file_manager(abs_path, true)
		return
	var dir := ProjectSettings.globalize_path(NetMatch.DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	OS.shell_open(dir)


# ================================================================= детали

## Лист бумаги (как у меню паузы): поля 30
func _paper(node_name: String) -> NinePatchRect:
	var p := NinePatchRect.new()
	p.name = node_name
	p.texture = UiTheme.tex("paper")
	for side in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		p.set(side, 30)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


## Затемнение во весь экран под листом посреди экрана (щелчки в мир не идут)
func _dimmed(node_name: String) -> Control:
	var root := Control.new()
	root.name = node_name
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	return root


## Кнопка листа (орех в латуни, как в меню паузы); подсказка — записка «Города»: заголовок и строка
func _button(node_name: String, text: String, tip: String, min_size: Vector2, fsize: int) -> Button:
	var b := CityTips.TipButton.new()
	b.name = node_name
	b.text = text
	b.tooltip_text = "%s\n%s" % [text, tip]
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	b.add_theme_font_override("font", UiTheme.head_bold())
	b.add_theme_font_size_override("font_size", fsize)
	return b


## Строка тушью с переносом по словам (ширину даёт столбец)
func _wrapped(text: String, f: Font, fsize: int) -> Label:
	var l := UiTheme.label(_nb(text), f, fsize, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1, 0)
	return l


## Последние два слова — неразрывным пробелом: одно короткое слово («Выйти».) не остаётся на строке одно
static func _nb(text: String) -> String:
	var i := text.rfind(" ")
	return text if i < 0 else text.substr(0, i) + String.chr(0xA0) + text.substr(i + 1)


## Мелкая строка курсивом тушью; в мелком окне и на крупном интерфейсе — плотнее и на точку крупнее (_restyle)
func _italic(text: String, fsize: int, wrap := false) -> Label:
	var l := UiTheme.label(_nb(text) if wrap else text, _ital_font(), fsize + (1 if _small else 0), true)
	l.set_meta("fsize", fsize)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(1, 0)
	_ital = _ital.filter(func(x: Variant) -> bool: return is_instance_valid(x))
	_ital.append(l)
	return l


func _ital_font() -> Font:
	return UiTheme.italic(600 if _small else 520)


## Высота столбца по содержимому при ширине w (метки с переносом считаются по этой ширине). Наименьший размер
## Control помнит прежний (метка без ширины — по букве в строке): после новой ширины — пересчитать
static func _col_height(col: VBoxContainer, w: float) -> float:
	var h := 0.0
	var n := 0
	for c in col.get_children():
		var ctl := c as Control
		if ctl == null or not ctl.visible:
			continue
		if ctl is Label:
			ctl.size = Vector2(w, 0.0)
			ctl.update_minimum_size()
			ctl.size = Vector2(w, 0.0)
		h += ctl.get_combined_minimum_size().y
		n += 1
	return h + float(col.get_theme_constant("separation")) * maxi(n - 1, 0)


## Латунная рамка листа (как у меню паузы и конца партии)
func _frame(p: Control) -> void:
	var frame := NinePatchRect.new()
	frame.texture = UiTheme.tex("frame_brass")
	for side in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		frame.set(side, 14)
	frame.draw_center = false
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = -10
	frame.offset_top = -10
	frame.offset_right = 10
	frame.offset_bottom = 10
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(frame)


func _quit() -> void:
	_close_confirm()
	hud.request_quit()


## Записка и лист «Ждём друга…» — посередине под балкой; масштаб — как у балки и записок (bar_scale). Окно стало
## мельче (или крупнее) порога — мелкие строки заново, листы — по новой высоте
func _layout() -> void:
	var view := hud.view_size()
	var s := CityBottomPanel.bar_scale(view)
	_pin.scale = Vector2(s, s)
	_pin.size = Vector2(_pin_w, PIN_H)
	_pin_col.size = Vector2(_pin_w - 96.0, PIN_H - 14.0)
	_pin.position = Vector2(view.x * 0.5 - _pin_w * s * 0.5, PIN_TOP * s)
	if is_instance_valid(_wait):
		_wait.scale = Vector2(s, s)
		_wait.position = Vector2(view.x * 0.5 - WAIT_W * s * 0.5, (PIN_TOP + 8.0) * s)
	var small := _is_small()
	if small != _small:
		_small = small
		_restyle.call_deferred()


func _restyle() -> void:
	_ital = _ital.filter(func(x: Variant) -> bool: return is_instance_valid(x))
	for l: Label in _ital:
		l.add_theme_font_override("font", _ital_font())
		l.add_theme_font_size_override("font_size", int(l.get_meta("fsize")) + (1 if _small else 0))
	# листы и записка — заново (высота и ширина по строкам)
	if driver != null and driver.net != null:
		var keep := is_instance_valid(_confirm)
		_show(_key, driver.net)
		if keep and _key.begins_with("lost"):
			_close_confirm()
			_ask_quit()


## Мелкое окно (записка на экране мельче SMALL_K: масштаб балки × холст окна) или крупный интерфейс (от BIG_UI)
func _is_small() -> bool:
	var o := get_node_or_null("/root/Ordo")
	var ui := float(o.get("ui_scale")) if o != null else 1.0
	return _screen_k() < SMALL_K or ui >= BIG_UI - 0.001


func _screen_k() -> float:
	var k := CityBottomPanel.bar_scale(hud.view_size())
	var w := get_window()
	if w == null or w.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED:
		return k
	var base := Vector2(w.content_scale_size)
	if base.x > 0.0 and base.y > 0.0:
		k *= minf(w.size.x / base.x, w.size.y / base.y)
	return k * w.content_scale_factor


func _shot() -> bool:
	var o := get_node_or_null("/root/Ordo")
	return o != null and bool(o.call("has_arg", "shot"))


## Латунная звезда ожидания (как в лобби): медленно поворачивается; на кадре проверки стоит
class Star extends Control:
	var t := 0.0
	var still := false

	func _process(delta: float) -> void:
		if still:
			return
		t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		var a0 := 0.2 + t * TAU / 12.0
		var pts := PackedVector2Array()
		for i in 16:
			var a := a0 + TAU * float(i) / 16.0
			pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.48))
		for i in 8:
			var tip: Vector2 = pts[i * 2]
			draw_colored_polygon(PackedVector2Array([c, pts[(i * 2 + 15) % 16], tip]), Color("#ecd08c"))
			draw_colored_polygon(PackedVector2Array([c, tip, pts[i * 2 + 1]]), Color("#a8864a"))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(0.16, 0.08, 0.02, 0.9), 1.4, true)
		draw_circle(c, r * 0.17, Color("#7d5c26"))
