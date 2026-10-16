extends SceneTree
## Масштаб интерфейса (просьба автора 2026-10-15: «масштаб интерфейса можно было регулировать»):
##   godot --headless --path ordo --script res://tests/test_ui_scale.gd
## Множитель холста окна (Ordo.ui_window_factor): масштаб игрока на подъём сцены, не теснее 1280×720;
## выбор игрока в автозагрузке Ordo: 100 % по умолчанию, 75–150 % шагом 5, запоминание в файле настроек,
## ключ --ui_scale сильнее и не запоминается, съёмка — 100 %; главное меню при 75 / 100 / 150 %: доска
## и лист «Настроек» целиком на холсте (лист — в пределах доски), при 100 % доска во всю высоту (и на 16:10,
## 4:3), на мелком масштабе — той же длины; ползунок: колесо не двигает, клавишами — через миг после нажатия.
## Доска с пунктом «Игра с другом» при 1920×1080 и 100 % не ужата (×1); лист макета «Игра с другом» во всех
## 9 состояниях и их вариантах — на холсте, в пределах доски по высоте, правее неё, верх вровень с доской, высота
## по содержимому (от 600, не выше высоты своего хода), масштаб один на ход лобби (выбор, хозяин, подключение,
## справка: внутри хода лист не растёт и не мельчает; при 150 % короткие ходы крупнее), начало тела на одном месте,
## записка не вылезает за свои строки; ничего не прыгает: поле адреса при «Подключиться», ряд кнопок хозяина при
## «друг вошёл», дощечки выбора и кнопки справки при новой записке; адрес, вписанный до справки, на месте;
## фокус после закрытия листов — на их пунктах доски, пока лист открыт — стрелки и Tab не уходят на доску;
## «Подключаемся» и «Вы в игре у друга» — фокус не на «Отмена» / «Выйти» (Enter их не жмёт); рамка фокуса — только
## после клавиш; служебные адреса (0.x, 224.x и выше) — «Такой адрес не подойдёт»;
## Esc в поле адреса — сразу назад; поле адреса чистит ввод (русская раскладка, сообщение целиком, порт
## 1–65535), ошибки и находки — в записке листа; макет прощёлкивается (26.115.40.12 — в игре у друга, другой
## адрес — «Не получилось»), «Отмена» у хозяина начинает с начала.
## Состояния и варианты листа проверяются на макете (--online_mock=1: выдуманные адреса, без сети). Настоящее лобби
## (--online_mock=0): пункт «Игра с другом» на доске и в установщике, лист открывается на выборе, без строки «Макет
## экрана», под кнопками — своя версия игры (сети тест не открывает: Windows не спросит про доступ к сети).
## Раскладка «Города» — test_ui_bind.
## Свои экземпляры Ordo пишут во временный файл настроек — настройки игрока не трогаются.

const ORDO := "res://scripts/core/ordo.gd"
const MENU := "res://scenes/menu/main_menu.tscn"
const ONLINE_STATES := ["choose", "host_wait", "host_ready", "join", "join_connecting", "join_fail", "join_wait",
	"version", "help"]

var _fails := 0
var _tmp := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	# автозагрузка Ordo появляется в дереве к первому кадру
	await process_frame
	_tmp = OS.get_cache_dir().path_join("ordo_test_ui_scale_%d.cfg" % OS.get_process_id())
	_check_factor()
	_check_ordo()
	await _check_menu()
	DirAccess.remove_absolute(_tmp)
	print("")
	print("ИТОГ: ", "ВСЁ ПРОШЛО" if _fails == 0 else "ПРОВАЛОВ: %d" % _fails)
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _check_factor() -> void:
	print("[множитель холста]")
	var f := func(win: Vector2, user: float, boost := 1.0) -> float:
		return float(load(ORDO).ui_window_factor(win, Vector2(1920, 1080), user, boost))
	_check(is_equal_approx(f.call(Vector2(1920, 1080), 1.0), 1.0), "1920×1080, 100 % — 1")
	_check(is_equal_approx(f.call(Vector2(1920, 1080), 1.5), 1.5), "1920×1080, 150 % — 1,5 (холст 1280×720)")
	_check(is_equal_approx(f.call(Vector2(1920, 1080), 0.75), 0.75), "1920×1080, 75 % — 0,75 (холст 2560×1440)")
	_check(is_equal_approx(f.call(Vector2(2560, 1440), 1.25), 1.25), "2560×1440, 125 % — 1,25")
	_check(is_equal_approx(f.call(Vector2(1280, 720), 1.0, 1.2), 1.2), "1280×720 в «Городе» (подъём 1,2), 100 % — 1,2")
	_check(is_equal_approx(f.call(Vector2(1280, 720), 1.5, 1.2), 1.5), "1280×720 в «Городе», 150 % — не теснее 1280×720: 1,5")
	_check(is_equal_approx(f.call(Vector2(2560, 1080), 1.5), 1.5) and is_equal_approx(f.call(Vector2(1440, 1080), 1.5), 1.5),
		"широкое 21:9 и квадратное 4:3 окно, 150 % — 1,5 (холст не уже 1280×720)")
	_check(is_equal_approx(f.call(Vector2(0, 0), 1.5), 1.0), "окно без размера — 1")
	_check(is_equal_approx(f.call(Vector2(1280, 720), 0.75), 1.125) and is_equal_approx(f.call(Vector2(1280, 720), 1.0), 1.125),
		"1280×720, 75 и 100 % — не мельче 0,75 на экране: 1,125")
	_check(is_equal_approx(f.call(Vector2(1280, 720), 0.75, 1.2), 1.125) and is_equal_approx(f.call(Vector2(1280, 720), 1.0, 1.2), 1.2),
		"1280×720 в «Городе»: 75 % — 1,125 (0,75 на экране), 100 % — 1,2 (подъём «Города»)")
	_check(is_equal_approx(f.call(Vector2(1600, 900), 0.75), 0.9) and is_equal_approx(f.call(Vector2(1920, 1080), 0.75), 0.75),
		"1600×900, 75 % — 0,9 (0,75 на экране); 1920×1080, 75 % — 0,75")


## Свой экземпляр автозагрузки: временный файл настроек, свои ключи (как из командной строки)
func _make_ordo(args: Dictionary) -> Node:
	var o: Node = (load(ORDO) as GDScript).new()
	o.name = "OrdoTest"
	o.set("settings_path", _tmp)
	o.set("_args", args.duplicate())
	o.set("process_mode", Node.PROCESS_MODE_DISABLED)
	root.add_child(o)
	return o


func _saved() -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(_tmp) != OK:
		return null
	return cfg.get_value("display", "ui_scale", null)


func _check_ordo() -> void:
	print("[выбор игрока: Ordo.ui_scale]")
	DirAccess.remove_absolute(_tmp)
	var o := _make_ordo({})
	_check(is_equal_approx(float(o.get("ui_scale")), 1.0), "новый игрок — 100 %")
	var got: Array = []
	o.connect("ui_scale_changed", func(s: float) -> void: got.append(s))
	o.call("set_ui_scale", 1.25)
	_check(is_equal_approx(float(o.get("ui_scale")), 1.25) and got.size() == 1, "125 % — сигнал ui_scale_changed")
	_check(_saved() != null and is_equal_approx(float(_saved()), 1.25), "выбор записан в файл настроек")
	o.call("set_ui_scale", 1.25)
	_check(got.size() == 1, "тот же масштаб ещё раз — без лишнего сигнала")
	o.call("set_ui_scale", 3.0)
	_check(is_equal_approx(float(o.get("ui_scale")), 1.5), "больше 150 % — 150 %")
	o.call("set_ui_scale", 0.2)
	_check(is_equal_approx(float(o.get("ui_scale")), 0.75), "меньше 75 % — 75 %")
	o.call("set_ui_scale", 1.13)
	_check(is_equal_approx(float(o.get("ui_scale")), 1.15), "шаг 5 %: 113 → 115")
	o.call("set_ui_scale", 1.25)
	o.free()
	var o2 := _make_ordo({})
	_check(is_equal_approx(float(o2.get("ui_scale")), 1.25), "при следующем запуске — сохранённые 125 %")
	o2.call("set_ui_scale", 0.9, false)
	_check(is_equal_approx(float(_saved()), 1.25), "remember=false — файл не трогается")
	o2.free()
	var o3 := _make_ordo({"ui_scale": "150"})
	_check(is_equal_approx(float(o3.get("ui_scale")), 1.5), "ключ --ui_scale=150 сильнее сохранённого")
	o3.call("set_ui_scale", 0.8)
	_check(is_equal_approx(float(_saved()), 1.25), "с ключом --ui_scale выбор не запоминается")
	o3.free()
	var o4 := _make_ordo({"ui_scale": "0.75"})
	_check(is_equal_approx(float(o4.get("ui_scale")), 0.75), "ключ --ui_scale=0.75 (доли)")
	o4.free()
	var o4b := _make_ordo({"ui_scale": "113"})
	_check(is_equal_approx(float(o4b.get("ui_scale")), 1.15), "ключ --ui_scale=113 — на шаге ползунка: 115 %")
	o4b.free()
	var o5 := _make_ordo({"shot": "/dev/null", "at": "999"})
	_check(is_equal_approx(float(o5.get("ui_scale")), 1.0), "съёмка без ключа — 100 % (настройки не читает)")
	o5.free()
	# свои экземпляры ставили множитель окну — вернуть его автозагрузке
	var ordo := root.get_node_or_null("Ordo")
	if ordo:
		ordo.call("apply_ui_scale")


func _check_menu() -> void:
	print("[главное меню при 75 / 100 / 150 %]")
	var ordo := root.get_node_or_null("Ordo")
	_check(ordo != null, "автозагрузка Ordo в дереве")
	if ordo == null:
		return
	# ползунок меню запоминает выбор — во временный файл, не в настройки игрока
	var old_path := String(ordo.get("settings_path"))
	ordo.set("settings_path", _tmp)
	# состояния листа «Игра с другом» — на макете (выдуманные адреса, сети нет)
	ordo.call("set_arg", "online_mock", "1")
	var w := root
	var old_size := w.size
	var old_mode := w.content_scale_mode
	var old_css := w.content_scale_size
	var old_aspect := w.content_scale_aspect
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_size = Vector2i(1920, 1080)
	var menu: Node = (load(MENU) as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame
	menu.call("_open_settings")
	for cs: Array in [[Vector2i(1920, 1080), 1.0], [Vector2i(1920, 1080), 1.5], [Vector2i(1280, 720), 1.5],
			[Vector2i(1920, 1080), 0.75], [Vector2i(1280, 720), 0.75], [Vector2i(1280, 720), 1.0],
			[Vector2i(1920, 1200), 1.0], [Vector2i(1440, 1080), 1.0], [Vector2i(1920, 1200), 0.75]]:
		var win: Vector2i = cs[0]
		var ui: float = cs[1]
		w.size = win
		ordo.call("set_ui_scale", ui, false)
		await process_frame
		var tag := "окно %d×%d, %d %%" % [win.x, win.y, int(roundf(ui * 100.0))]
		var view := (menu.get("_ui") as Control).size
		var board := menu.get("_board") as Control
		var sheet := menu.get("_sheet") as Control
		var slider := menu.get("_scale") as HSlider
		var br := board.get_global_rect()
		var sr := sheet.get_global_rect()
		var whole := Rect2(Vector2.ZERO, view).grow(0.5)
		_check(whole.encloses(br), "%s: доска на холсте %s (%s, ужата ×%.2f)" % [tag, view, br, board.scale.x])
		_check(whole.encloses(sr), "%s: лист «Настроек» на холсте (%s, ужат ×%.2f)" % [tag, sr, sheet.scale.x])
		_check(sr.position.y >= br.position.y - 0.5 and sr.end.y <= br.end.y + 0.5,
			"%s: лист «Настроек» в пределах доски по высоте (%.0f…%.0f в %.0f…%.0f)" % [
			tag, sr.position.y, sr.end.y, br.position.y, br.end.y])
		_check(is_equal_approx(slider.value, roundf(ui * 100.0)), "%s: ползунок показывает %d %%" % [tag, int(slider.value)])
		var k := board.scale.x
		if w.content_scale_factor >= 1.0:
			_check(is_equal_approx(br.position.y, 56.0 * k) and is_equal_approx(br.end.y, view.y - 56.0 * k),
				"%s: доска во всю высоту (%.0f…%.0f, ужата ×%.2f)" % [tag, br.position.y, br.end.y, k])
		else:
			_check(is_equal_approx(br.size.y, (view.y * w.content_scale_factor - 112.0) * board.scale.x),
				"%s: доска той же длины, что при 100 %% (%.0f), — не тянется пустым орехом" % [tag, br.size.y])
		if win == Vector2i(1920, 1080) and is_equal_approx(ui, 1.0):
			_check(is_equal_approx(k, 1.0) and menu.call("_item", "online") != null,
				"%s: доска с пунктом «Игра с другом» не ужата (×%.3f)" % [tag, k])
		await _check_online(menu, tag, br, view)
		menu.call("_open_settings")
	# ползунок: колесо мыши его не двигает; клавишами — масштаб у Ordo через миг после последнего нажатия
	var slider := menu.get("_scale") as HSlider
	_check(not slider.scrollable, "колесо мыши ползунок масштаба не двигает")
	ordo.call("set_ui_scale", 1.0, false)
	slider.value = 120.0
	slider.value = 125.0
	var now := float(ordo.get("ui_scale"))
	await create_timer(0.6).timeout
	_check(is_equal_approx(now, 1.0) and is_equal_approx(float(ordo.get("ui_scale")), 1.25),
		"ползунок клавишами 120 → 125 %%: холст не сразу (%.2f), потом Ordo.ui_scale 1,25" % now)
	ordo.call("set_ui_scale", 1.0, false)
	await _check_focus(menu)
	await _check_online_input(menu)
	menu.free()
	w.size = Vector2i(1920, 1080)
	ordo.call("set_ui_scale", 1.0, false)
	await _check_real_lobby(ordo)
	ordo.call("clear_arg", "online_mock")
	ordo.set("settings_path", old_path)
	w.size = old_size
	w.content_scale_size = old_css
	w.content_scale_aspect = old_aspect
	w.content_scale_mode = old_mode
	await process_frame


## Лист «Игра с другом» во всех состояниях и их вариантах: на холсте, в пределах доски по высоте, правее доски
## (не посередине экрана); верх листа — вровень с верхним краем доски; высота — по содержимому (не ниже
## ONLINE_MIN_H, не выше высоты своего хода FLOW_H, а та — не выше ONLINE_MAX_H), содержимое влезает; масштаб —
## один на ход лобби (выбор, хозяин, подключение, справка); начало тела (записка или первая строка под линией шага)
## — на одном месте во всех состояниях; записка не вылезает за свои строки (новая записка не сдвигает лист). Без
## прыжков: у хозяина ряд кнопок и низ листа одни во всех вариантах (друг вошёл — ни на точку), у выбора —
## дощечки, у справки — «Узнать мой адрес» и «Понятно»; поле адреса не сдвигается при «Подключиться». При
## 1920×1080 / 100 % все ходы — без ужатия (×1); при 150 % короткие ходы (выбор, подключение) крупнее, чем при 100 %
func _check_online(menu: Node, tag: String, br: Rect2, view: Vector2) -> void:
	var sheet := menu.get("_online_sheet") as Control
	var col := sheet.get_node("Col") as Control
	var online := menu.get("_online") as Control
	var consts: Dictionary = online.get_script().get_script_constant_map()
	var alts: Dictionary = consts["ALTS"]
	var flows: Dictionary = consts["FLOWS"]
	var flow_h: Dictionary = consts["FLOW_H"]
	var lo := float(menu.get_script().get_script_constant_map()["ONLINE_MIN_H"])
	var hi := float(menu.get_script().get_script_constant_map()["ONLINE_MAX_H"])
	var msg := sheet.find_child("Msg", true, false) as Control
	var msg_text := sheet.find_child("Msg_text", true, false) as Label
	var body := sheet.find_child("Body", true, false) as Control
	var buttons := sheet.find_child("Buttons", true, false) as Control
	var whole := Rect2(Vector2.ZERO, view).grow(0.5)
	var bad := PackedStringArray()
	var start0 := NAN
	# по ходам: масштаб, на экране, самая большая высота (и где)
	var k_of := {}
	var screen_of := {}
	var most := {}
	var most_at := {}
	# что не должно прыгать: [ход или состояние] → первое значение и где
	var same := {}
	var field := {}
	var n := 0
	for st: String in ONLINE_STATES:
		for alt in int(alts.get(st, 1)):
			n += 1
			var id := "%s/%d" % [st, alt]
			var flow := String(flows[st])
			menu.call("_open_online", st, alt)
			# строки с переносом досчитывают высоту за кадр-два, лист встаёт по высоте кадром позже
			await process_frame
			await process_frame
			await process_frame
			var sr := sheet.get_global_rect()
			var k := sheet.scale.y
			var h := sheet.size.y
			var need := col.get_combined_minimum_size().y + 72.0
			if h > float(most.get(flow, 0.0)):
				most[flow] = h
				most_at[flow] = id
			# начало тела — в точках листа: записка, а без неё — первая строка тела
			var first := msg if msg.visible else body
			var start := (first.get_global_rect().position.y - sr.position.y) / k
			if is_nan(start0):
				start0 = start
			if not k_of.has(flow):
				k_of[flow] = k
				screen_of[flow] = float(online.call("screen_k"))
			var f := sheet.find_child("Join_addr", true, false) as Control
			if f != null and st in ["join", "join_connecting"] and alt == 0:
				field[st] = f.get_global_rect()
			# без прыжков: что сравниваем в каком состоянии (глобальные y — масштаб внутри хода один)
			var probes := {}
			if flow == "host":
				probes["host: ряд кнопок"] = buttons.get_global_rect().position.y
				probes["host: низ листа"] = sr.end.y
			elif st == "choose":
				for pn: String in ["Online_host", "Online_join"]:
					var p := sheet.find_child(pn, true, false) as Control
					probes["choose: " + pn] = p.get_global_rect().position.y if p else -1.0
			elif st == "help":
				var row := sheet.find_child("NetRow", true, false) as Control
				probes["help: «Узнать мой адрес»"] = row.get_global_rect().position.y if row else -1.0
				probes["help: «Понятно»"] = buttons.get_global_rect().position.y
			for key: String in probes:
				if not same.has(key):
					same[key] = [probes[key], id]
				elif absf(float(probes[key]) - float(same[key][0])) > 0.01:
					bad.append("%s: %.2f, а в %s — %.2f (прыгает)" % [key, probes[key], same[key][1], same[key][0]])
			var lines := int(online.get("_msg_lines"))
			if not whole.encloses(sr):
				bad.append("%s: не на холсте %s" % [id, sr])
			elif sr.position.y < br.position.y - 0.5 or sr.end.y > br.end.y + 0.5:
				bad.append("%s: выше доски (%.0f…%.0f)" % [id, sr.position.y, sr.end.y])
			elif absf(sr.position.y - br.position.y) > 0.5:
				bad.append("%s: верх листа %.1f не вровень с доской %.1f" % [id, sr.position.y, br.position.y])
			elif sr.position.x < br.end.x:
				bad.append("%s: не правее доски (x %.0f)" % [id, sr.position.x])
			elif need > h + 0.5:
				bad.append("%s: содержимое %.0f выше листа %.0f" % [id, need, h])
			elif col.get_combined_minimum_size().x > sheet.size.x - 108.0 + 0.5:
				bad.append("%s: содержимое шириной %.0f шире столбца листа %.0f — всё съезжает вправо" % [
					id, col.get_combined_minimum_size().x, sheet.size.x - 108.0])
			elif h < lo - 0.5 or h > float(flow_h[flow]) + 0.5:
				bad.append("%s: высота листа %.0f вне %.0f…%.0f (ход %s)" % [id, h, lo, flow_h[flow], flow])
			elif absf(k - float(k_of[flow])) > 0.0005:
				bad.append("%s: лист ужат ×%.3f, а в начале хода «%s» ×%.3f — лист растёт и мельчает внутри хода" % [id, k, flow, k_of[flow]])
			elif absf(start - start0) > 0.5:
				bad.append("%s: тело начинается на %.1f, а у первого состояния на %.1f" % [id, start, start0])
			elif msg.visible and lines > 0 and msg_text.get_line_count() > lines:
				bad.append("%s: записка в %d строки, а место у неё на %d — лист прыгнет" % [id, msg_text.get_line_count(), lines])
	if field.size() == 2 and not (field["join"] as Rect2).is_equal_approx(field["join_connecting"] as Rect2):
		bad.append("поле адреса сдвинулось при «Подключиться»: %s → %s" % [field["join"], field["join_connecting"]])
	for flow: String in flow_h:
		if float(flow_h[flow]) > hi + 0.5:
			bad.append("высота хода %s %.0f выше ONLINE_MAX_H %.0f" % [flow, flow_h[flow], hi])
	var big := tag.begins_with("окно 1920×1080, 100")
	if big:
		for flow: String in k_of:
			if float(k_of[flow]) < 0.9995:
				bad.append("при 1920×1080 / 100 %% ход %s ужат ×%.3f" % [flow, k_of[flow]])
	if tag.begins_with("окно 1920×1080, 150"):
		for flow: String in ["choose", "join"]:
			if float(screen_of.get(flow, 0.0)) < 1.15:
				bad.append("при 150 %% ход %s на экране ×%.2f — не крупнее, чем при 100 %%" % [flow, screen_of.get(flow, 0.0)])
	menu.call("_close_online")
	var sizes := PackedStringArray()
	for flow: String in ["choose", "host", "join", "help"]:
		sizes.append("%s ×%.3f (экран ×%.2f, до %.0f из %.0f: %s)" % [flow, k_of.get(flow, 0.0), screen_of.get(flow, 0.0),
			most.get(flow, 0.0), flow_h[flow], most_at.get(flow, "")])
	_check(bad.is_empty(), "%s: лист «Игра с другом» — %d состояний и вариантов на холсте, верх вровень с доской, правее неё, высота по ходу, масштаб один на ход, тело на месте, записки и кнопки не прыгают: %s%s" % [
		tag, n, "; ".join(sizes), ("  " + "; ".join(bad)) if bad.size() > 0 else ""])


## Фокус после закрытия листов — на их пунктах доски (пункт ищется по имени: номера сдвигаются)
func _check_focus(menu: Node) -> void:
	print("[фокус после листов]")
	var vp := menu.get_viewport()
	menu.call("_open_settings")
	await process_frame
	menu.call("_close_settings")
	await process_frame
	var f := vp.gui_get_focus_owner()
	_check(f != null and f.name == "Item_settings", "закрыли «Настройки» — фокус на «Настройках» (%s)" % (f.name if f else "нет"))
	menu.call("_open_online", "host_wait", 0)
	await process_frame
	await process_frame
	f = vp.gui_get_focus_owner()
	_check(f != null and f.name == "Copy_0", "открыли лобби (host_wait) — фокус на «Копировать» Radmin VPN (%s)" % (f.name if f else "нет"))
	var online := menu.get("_online") as Control
	online.call("escape")
	await process_frame
	f = vp.gui_get_focus_owner()
	_check(online.visible and f != null and String(online.get("_state")) == "choose",
		"Esc в host_wait — назад к выбору (%s)" % online.get("_state"))
	online.call("escape")
	await process_frame
	f = vp.gui_get_focus_owner()
	_check(not online.visible and f != null and f.name == "Item_online",
		"Esc в выборе — лист закрыт, фокус на «Игре с другом» (%s)" % (f.name if f else "нет"))
	# клавиатура не уходит с листа на доску за затемнением (иначе Enter запустил бы пункт под листом)
	for st: String in ["choose", "host_wait"]:
		menu.call("_open_online", st, 0)
		await process_frame
		await process_frame
		var gone := PackedStringArray()
		for key: int in [KEY_LEFT, KEY_UP, KEY_TAB, KEY_TAB, KEY_TAB, KEY_TAB, KEY_TAB, KEY_TAB, KEY_LEFT, KEY_DOWN, KEY_DOWN, KEY_LEFT]:
			_key(vp, key)
			await process_frame
			f = vp.gui_get_focus_owner()
			if f == null or not online.is_ancestor_of(f):
				gone.append(String(f.name) if f else "нет")
		_check(gone.is_empty(), "%s: стрелки и Tab не уводят фокус с листа на доску (%s)" % [
			st, ", ".join(gone) if gone.size() > 0 else "фокус на листе"])
	menu.call("_open_settings")
	await process_frame
	var gone_s := PackedStringArray()
	var settings := menu.get("_settings") as Control
	for key: int in [KEY_LEFT, KEY_UP, KEY_UP, KEY_TAB, KEY_TAB, KEY_LEFT]:
		_key(vp, key)
		await process_frame
		f = vp.gui_get_focus_owner()
		if f == null or not settings.is_ancestor_of(f):
			gone_s.append(String(f.name) if f else "нет")
	_check(gone_s.is_empty(), "«Настройки»: стрелки и Tab не уводят фокус на доску (%s)" % (
		", ".join(gone_s) if gone_s.size() > 0 else "фокус на листе"))
	menu.call("_close_settings")
	await process_frame
	f = vp.gui_get_focus_owner()
	_check(f != null and f.name == "Item_settings", "после «Настроек» доска снова берёт фокус (%s)" % (f.name if f else "нет"))
	# Esc в поле адреса — сразу назад: поле не съедает первое нажатие
	menu.call("_open_online", "join", 0)
	await process_frame
	await process_frame
	f = vp.gui_get_focus_owner()
	var in_field := f != null and f.name == "Join_addr"
	_key(vp, KEY_ESCAPE)
	await process_frame
	_check(in_field and String(online.get("_state")) == "choose",
		"Esc в поле адреса — с первого нажатия назад к выбору (фокус был в поле: %s, стало %s)" % [in_field, online.get("_state")])
	# «Подключаемся» и «Вы в игре у друга»: фокус не на «Отмена» / «Выйти» — Enter не отменяет и не выводит из игры
	for st: String in ["join_connecting", "join_wait"]:
		menu.call("_open_online", st, 0)
		await process_frame
		await process_frame
		f = vp.gui_get_focus_owner()
		var on_left := f != null and f.name == "Online_left"
		_key(vp, KEY_ENTER)
		await process_frame
		_check(not on_left and String(online.get("_state")) == st,
			"%s: фокус не на левой кнопке (%s), Enter состояние не меняет (%s)" % [st, f.name if f else "нет", online.get("_state")])
	# рамка фокуса — только после ходьбы клавишами: открыли мышью — её нет, Tab — есть, щелчок мышью — снова нет
	var gate: Object = online.get("_gate")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = Vector2(2, 2)
	vp.push_input(mb)
	var mb_up := mb.duplicate() as InputEventMouseButton
	mb_up.pressed = false
	vp.push_input(mb_up)
	var off_first := not bool(gate.get("on"))
	_key(vp, KEY_TAB)
	await process_frame
	var on_tab := bool(gate.get("on"))
	vp.push_input(mb)
	vp.push_input(mb_up)
	_check(off_first and on_tab and not bool(gate.get("on")),
		"рамка фокуса: после мыши её нет (%s), после Tab есть (%s), после щелчка снова нет (%s)" % [off_first, on_tab, gate.get("on")])
	menu.call("_close_online")
	await process_frame


## Нажать и отпустить клавишу (как с клавиатуры: через окно, до интерфейса)
func _key(vp: Viewport, key: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.physical_keycode = key
	ev.pressed = true
	vp.push_input(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	vp.push_input(up)


## Поле «Адрес друга»: русская раскладка, «http://», сообщение целиком; «Подключиться» — только с верным адресом
func _check_online_input(menu: Node) -> void:
	print("[макет «Игра с другом»: поле адреса]")
	menu.call("_open_online", "join", 0)
	await process_frame
	var online := menu.get("_online") as Control
	var field := online.find_child("Join_addr", true, false) as LineEdit
	var main := online.find_child("Online_main", true, false) as Button
	_check(field != null and main != null and main.disabled, "пустое поле — «Подключиться» недоступна")
	if field == null or main == null:
		return
	# неразрывный пробел листа — именно U+00A0 (правка файла легко превращает его в обычный пробел, и предлоги
	# «в», «и» снова повиснут в конце строки)
	var nb := String(online.get_script().get_script_constant_map()["NBSP"])
	_check(nb.length() == 1 and nb.unicode_at(0) == 0xA0, "NBSP листа — неразрывный пробел U+00A0")
	# сообщения поля — в записке листа (Msg): красная — ошибка, зелёная — адрес нашёлся в сообщении
	var msg := online.find_child("Msg_text", true, false) as Label
	for c: Array in [["26ю115ю40ю12", "26.115.40.12", false], ["  http://26.115.40.12 ", "26.115.40.12", false],
			["Привет! Мой адрес 26.115.40.12, заходи", "26.115.40.12", true], ["26б115б40б12ж7777", "26.115.40.12:7777", false],
			["26.115.40.12ж7777", "26.115.40.12:7777", false], ["Заходи: 26.115.40.12ж7777 !", "26.115.40.12:7777", true]]:
		online.call("_on_field_changed", c[0])
		var said := msg != null and msg.text.begins_with("Нашли адрес") and String(online.get("_msg_kind")) == "green"
		_check(field.text == c[1] and not main.disabled and said == c[2],
			"«%s» → «%s» (вышло «%s»), «Подключиться» горит, «нашли в сообщении» — %s" % [c[0], c[1], field.text, said])
	# раскладку чинят, только когда вписаны одни цифры и знаки: в обычной фразе «1,2,3,4» — не адрес
	online.call("_on_field_changed", "")
	online.call("_on_field_changed", "Счёт 1,2,3,4 — ок")
	_check(main.disabled and not msg.text.begins_with("Нашли адрес") and field.text == "",
		"фраза «Счёт 1,2,3,4 — ок» — не адрес (вышло «%s»), «Подключиться» недоступна" % field.text)
	# вставили текст без адреса — поле как было (не склеенные слова), только красная записка
	online.call("_on_field_changed", "26.115.40.12")
	online.call("_on_field_changed", "Привет, заходи вечером!", true)
	_check(field.text == "26.115.40.12" and String(online.get("_msg_kind")) == "red"
		and msg.text.replace(nb, " ").begins_with("В скопированном нет адреса"),
		"вставили «Привет, заходи вечером!» — поле как было («%s»), красная записка (%s)" % [field.text, msg.text])
	# пробел посреди адреса убран — курсор остаётся у того же знака, а не уходит в конец
	field.text = "26.1 15.40.12"
	field.caret_column = 5
	online.call("_on_field_changed", field.text)
	_check(field.text == "26.115.40.12" and field.caret_column == 4,
		"пробел посреди адреса убран, курсор на месте (%s, курсор %d)" % [field.text, field.caret_column])
	online.call("_on_field_changed", "26.115.40")
	_check(main.disabled and String(online.get("_msg_kind")) != "red",
		"неполный адрес — «Подключиться» недоступна, пока пишут — без ошибки (записка %s)" % online.get("_msg_kind"))
	online.call("_on_field_changed", "300.1.2.3")
	_check(main.disabled, "число больше 255 — «Подключиться» недоступна")
	# служебные адреса: к другу по ним не подключиться (ENet откажет сразу, а не «не ответил»)
	for bad_addr: String in ["0.1.2.3", "224.0.0.1", "255.255.255.255"]:
		online.call("_on_field_changed", bad_addr)
		online.call("_field_error", bad_addr)
		_check(main.disabled and msg.text.replace(nb, " ").begins_with("Такой адрес не подойдёт"),
			"«%s» — «Подключиться» недоступна, записка «Такой адрес не подойдёт» (%s)" % [bad_addr, msg.text])
	for c: Array in [["26.115.40.12:99999", false], ["26.115.40.12:0", false], ["26.115.40.12:65535", true], ["26.115.40.12:1", true]]:
		online.call("_on_field_changed", c[0])
		_check(main.disabled != c[1], "порт: «%s» — «Подключиться» %s" % [c[0], "горит" if c[1] else "недоступна (порт 1–65535)"])
	online.call("_on_field_changed", "127.0.0.1")
	_check(not main.disabled and msg.text.begins_with("Это адрес вашего компьютера"),
		"127.0.0.1 — предупреждение «это ваш компьютер», но подключиться можно (две копии на одном ПК)")
	online.call("_field_error", "26.115.40")
	_check(String(online.get("_msg_kind")) == "red" and bool(online.get("_field_deco").get("err")),
		"неверный адрес — красная записка и красная черта под полем")
	menu.call("_close_online")
	await _check_online_flow(menu)


## Макет можно прощёлкать: к 26.115.40.12 — через ~3 с «вы в игре у друга», к другому адресу — «Не получилось»;
## «Отмена» у хозяина забывает номер партии; копирование адреса — зелёная записка на листе, не на пейзаже;
## вписанный адрес и курсор переживают справку; у хозяина справка не сбрасывает время ожидания; адрес в
## интернете макет помнит только у хозяина, и записка о нём — по тому, кто читает
func _check_online_flow(menu: Node) -> void:
	print("[макет «Игра с другом»: щелчками]")
	var online := menu.get("_online") as Control
	# адрес вписан, но «Подключиться» ещё не нажато — сходили в справку и вернулись: адрес и курсор на месте
	menu.call("_open_online", "join", 0)
	await process_frame
	var draft := online.find_child("Join_addr", true, false) as LineEdit
	draft.text = "26.115.4"
	draft.caret_column = 3
	online.call("_on_field_changed", draft.text)
	online.call("_to_help")
	var was_help := String(online.get("_state")) == "help"
	online.call("_on_main")
	await process_frame
	await process_frame
	draft = online.find_child("Join_addr", true, false) as LineEdit
	_check(was_help and draft != null and draft.text == "26.115.4" and draft.caret_column == 3,
		"«Адрес друга» → справка → «Понятно»: вписанное на месте («%s», курсор %d)" % [
		draft.text if draft else "нет поля", draft.caret_column if draft else -1])
	# хозяин ждёт друга (часы идут), сходил в справку: «уже 0:03» не прыгает на «0:00», друг «входит» в срок
	menu.call("_open_online", "host_wait", 0)
	await process_frame
	online.call("_go_live", "host_wait")
	online.set("_clock", 3.2)
	online.call("_to_help")
	await process_frame
	online.call("_on_main")
	await process_frame
	var wait_lbl := online.get("_wait_lbl") as Label
	_check(String(online.get("_state")) == "host_wait" and float(online.get("_clock")) >= 3.2
		and wait_lbl != null and wait_lbl.text == "уже 0:03",
		"справка у хозяина время ожидания не сбрасывает (%.1f с, «%s»)" % [online.get("_clock"), wait_lbl.text if wait_lbl else ""])
	# адрес в интернете: у хозяина справка его помнит и пишет «отправьте адрес другу»; у остальных — забывает,
	# а записка зовёт сначала создать игру
	online.call("_to_help")
	await process_frame
	online.call("_net_done", online.find_child("NetRow", true, false))
	var host_msg := String((online.find_child("Msg_text", true, false) as Label).text)
	online.call("_on_main")
	await process_frame
	var kept := bool(online.get("_net_found"))
	online.set("_live", false)
	menu.call("_open_online", "choose", 0)
	await process_frame
	online.call("_to_help")
	await process_frame
	online.call("_net_done", online.find_child("NetRow", true, false))
	var choose_msg := String((online.find_child("Msg_text", true, false) as Label).text)
	online.call("_on_main")
	await process_frame
	_check(kept and not bool(online.get("_net_found")) and not host_msg.contains("Создать") and choose_msg.contains("Создать"),
		"адрес в интернете: хозяин его помнит (%s), без игры — забыт (%s); записка хозяину «%s», остальным «%s»" % [
		kept, online.get("_net_found"), host_msg, choose_msg])
	for c: Array in [["26.115.40.12", "join_wait"], ["26.115.40.13", "join_fail"]]:
		menu.call("_open_online", "join", 0)
		await process_frame
		var field := online.find_child("Join_addr", true, false) as LineEdit
		field.text = c[0]
		online.call("_on_field_changed", c[0])
		online.call("_on_main")
		var at := String(online.get("_state"))
		await create_timer(3.6).timeout
		_check(at == "join_connecting" and String(online.get("_state")) == c[1],
			"«Подключиться» к %s — сначала «Подключаемся», через 3 с — %s (вышло %s → %s)" % [c[0], c[1], at, online.get("_state")])
	menu.call("_open_online", "host_wait", 0)
	await process_frame
	online.set("_seed", 123456)
	var copy := online.find_child("Copy_0", true, false) as Button
	copy.pressed.emit()
	_check(String(online.get("_msg_kind")) == "green" and copy.text == "Скопировано",
		"«Копировать» — «Скопировано» и зелёная записка на листе (%s)" % online.get("_msg_kind"))
	# справка из ожидания друга игру не закрывает: «Понятно» — снова «Ждём друга», номер партии тот же
	online.call("_to_help")
	var in_help := String(online.get("_state")) == "help"
	online.call("_on_main")
	await process_frame
	_check(in_help and String(online.get("_state")) == "host_wait" and int(online.get("_seed")) == 123456,
		"справка из «Ждём друга» — «Понятно» возвращает в то же ожидание (%s, номер %s)" % [online.get("_state"), online.get("_seed")])
	online.call("escape")
	await process_frame
	_check(String(online.get("_state")) == "choose" and int(online.get("_seed")) == 482913,
		"«Отмена» у хозяина — снова выбор, номер партии с начала (%s)" % online.get("_seed"))
	menu.call("_close_online")
	await process_frame


## Настоящее лобби (--online_mock=0; так — в установщике): пункт «Игра с другом» на доске (6 пунктов, доска при
## 1920×1080 / 100 % не ужата), лист открывается на выборе (даже если просили другое состояние — его ведёт сеть),
## без строки «Макет экрана»; под кнопками — своя версия игры (NetVersion: номер или «рабочая сборка от …»).
## Кнопки сети тест не жмёт: сервер на 7777 открыл бы окно Windows про доступ к сети
func _check_real_lobby(ordo: Node) -> void:
	print("[настоящее лобби — как в установщике]")
	ordo.call("set_arg", "online_mock", "0")
	var menu: Node = (load(MENU) as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	var board := menu.get("_board") as Control
	var buttons: Array = menu.get("_buttons")
	_check(menu.call("_item", "online") != null and buttons.size() == 6,
		"пункт «Игра с другом» на доске, пунктов %d" % buttons.size())
	_check(is_equal_approx(board.scale.x, 1.0), "доска при 1920×1080 / 100 %% не ужата (×%.3f)" % board.scale.x)
	menu.call("_open_online", "host_ready", 0)
	await process_frame
	var online := menu.get("_online") as Control
	var note := online.find_child("MockNote", true, false) as Label
	var build := online.find_child("Build", true, false) as Label
	_check(String(online.get("_state")) == "choose" and not bool(online.get("_mock")),
		"лист открылся на выборе, это не макет (%s)" % online.get("_state"))
	_check(note != null and not note.visible, "строки «Макет экрана» под листом нет")
	var want := "Ваша версия игры: " + NetVersion.label(NetVersion.info())
	_check(build != null and build.text == want, "своя версия под кнопками: «%s»" % (build.text if build else ""))
	menu.call("_close_online")
	await process_frame
	var f := menu.get_viewport().gui_get_focus_owner()
	_check(f != null and f.name == "Item_online", "лист закрыт — фокус на «Игре с другом» (%s)" % (f.name if f else "нет"))
	menu.free()
