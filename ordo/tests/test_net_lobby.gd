extends SceneTree
## Лобби «Игра с другом» на настоящей сети — какие экраны показывают события NetSession (ТЗ §16), без сокетов:
## события подаются прямо в лист (_on_net), как их шлёт NetSession. Экраны и тексты — одобренного макета.
##   • хозяин: друг вошёл — «Друг подключился» (связь хорошая / медленная), вышел сам — «Друг вышел…», пропал —
##     «Связь с другом пропала…», не смог войти — у кого старая версия (с настоящими номерами), «собраны
##     по-разному»;
##   • свои адреса: Radmin VPN не найден — строка «не найден» и записка о нём; два домашних — обе строки, лист
##     на холсте; «Дома» не найден — без кнопки;
##   • подключившийся: «Друг ответил — сверяем версии», «Вы в игре у друга» (сторона и номер партии хозяина),
##     хозяин сменил сторону — записка «теперь вы за …», «Разные версии игры» (вердикт → вариант), «место
##     занято», «друг не ответил», хозяин вышел / пропал;
##   • «В прошлый раз» — только если адрес уже был; под листом нет «Макет экрана», версия — своя.
##   • «Город» в партии по сети: записки связи, меню паузы без «Начать заново» (пауза — общая, приказом), конец
##     партии без «Ещё раз»; пауза стояла до меню, друг снял её, пока меню открыто, — закрытие меню паузу снова не
##     ставит; «В главное меню» — сперва «Выйти из партии?» («Остаться» / «Выйти»); друг открыл меню — «Друг открыл
##     меню»; связь пропала — лист «Ждём друга…» (красная печать, «ждём уже …», «Выйти» спрашивает ещё раз); друг
##     вышел и «Партия остановлена» — лист по тексту, без «не с того же сайта», «Открыть папку» вместо пути.
## Своя автозагрузка Ordo пишет во временный файл настроек — настройки игрока не трогаются.
##   godot --headless --path ordo --script res://tests/test_net_lobby.gd

const MENU := "res://scenes/menu/main_menu.tscn"

var _fails := 0
var _online: Control
var _ns: NetSession


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _run() -> void:
	await process_frame
	var ordo := root.get_node_or_null("Ordo")
	var tmp := OS.get_cache_dir().path_join("ordo_test_net_lobby_%d.cfg" % OS.get_process_id())
	var old_path := String(ordo.get("settings_path"))
	ordo.set("settings_path", tmp)
	ordo.call("set_arg", "online_mock", "0")
	var menu: Node = (load(MENU) as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	menu.call("_open_online", "choose", 0)
	await process_frame
	_online = menu.get("_online") as Control
	_online.call("_session")
	_ns = _online.get("_net") as NetSession
	_check(_ns != null and not _ns.active(), "сессия есть, сети нет (тест не открывает сокетов)")
	_check(String(_online.get("_state")) == "choose", "лист открыт на выборе")
	await _host_side()
	await _guest_side()
	menu.call("_close_online")
	menu.free()
	if _ns:
		_ns.queue_free()
	await _city_part(ordo)
	ordo.call("clear_arg", "online_mock")
	ordo.set("settings_path", old_path)
	DirAccess.remove_absolute(tmp)
	await process_frame
	print("")
	print("ИТОГ: ", "ВСЁ ПРОШЛО" if _fails == 0 else "ПРОВАЛОВ: %d" % _fails)
	quit(1 if _fails > 0 else 0)


func _state() -> String:
	return "%s/%d" % [_online.get("_state"), int(_online.get("_alt"))]


func _msg() -> String:
	var l := _online.find_child("Msg_text", true, false) as Label
	return _norm(l.text) if l else ""


## Без неразрывных пробелов и «не разрывать здесь» (типографика листа, _nb)
static func _norm(s: String) -> String:
	return s.replace(String.chr(0xA0), " ").replace(String.chr(0x2060), "")


func _msg_kind() -> String:
	return String(_online.get("_msg_kind"))


## Хозяин ждёт друга: адреса подставляем (как NetAddr.scan), сервер не открываем
func _host_wait(addrs: Dictionary) -> void:
	_online.set("_addrs", addrs)
	_online.set("_host_t0", Time.get_ticks_msec() - 42000)
	_online.set("_seed", 482913)
	_online.call("_show", "host_wait", 4 if String(addrs.get("radmin", "")) == "" else 0)
	await process_frame


func _host_side() -> void:
	print("[хозяин]")
	await _host_wait({"radmin": "26.1.2.3", "home": PackedStringArray(["192.168.0.7"])})
	var addr := _online.find_child("Addresses", true, false) as Control
	var texts := []
	for l in addr.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	_check("26.1.2.3" in texts and "192.168.0.7" in texts, "строки адресов — свои адреса (%s)" % ", ".join(PackedStringArray(texts.filter(func(t: String) -> bool: return t.contains(".")))))
	var wait := _online.get("_wait_lbl") as Label
	_check(wait != null and wait.text == "уже 0:42", "сколько ждём друга — с «Создать игру» («%s»)" % (wait.text if wait else ""))
	var build := _online.find_child("Build", true, false) as Label
	_check(build.text == "Ваша версия игры: " + NetVersion.label(NetVersion.info()), "своя версия под кнопками: «%s»" % build.text)
	_check(not (_online.find_child("MockNote", true, false) as Label).visible, "под листом нет «Макет экрана»")
	_online.call("_on_net", &"friend_joined", {})
	await process_frame
	_check(_state() == "host_ready/0" and _msg_kind() == "green" and _msg().begins_with("Связь с другом хорошая"),
		"друг вошёл — «Друг подключился», зелёная записка (%s, «%s»)" % [_state(), _msg()])
	_online.call("_on_net", &"ping", {"slow": true})
	await process_frame
	_check(_state() == "host_ready/1" and _msg_kind() == "gold" and _msg().begins_with("Связь медленная"),
		"ответ друга дольше четверти секунды — «Связь медленная» (%s)" % _state())
	_online.call("_on_net", &"friend_left", {})
	await process_frame
	_check(_state() == "host_wait/2" and _msg().begins_with("Друг вышел"), "друг вышел сам — «Друг вышел…» (%s)" % _state())
	_online.call("_on_net", &"friend_lost", {})
	await process_frame
	_check(_state() == "host_wait/6" and _msg().begins_with("Связь с другом пропала"), "пропал без «пока» — «Связь с другом пропала…»")
	var old := {"number": "0.1.52", "date": 20261002, "code": "9b12000000000000".hex_decode()}
	_online.call("_on_net", &"friend_refused", {"their": old, "verdict": "theirs_old"})
	await process_frame
	_check(_state() == "host_wait/1" and _msg().contains("0.1.52") and not _msg().contains(".."), "у друга старая — «у него старая версия игры (0.1.52)…», без двух точек подряд (%s)" % _msg())
	_online.call("_on_net", &"friend_refused", {"their": {"number": "0.1.60", "date": 20261020, "code": PackedByteArray()}, "verdict": "mine_old"})
	await process_frame
	_check(_state() == "host_wait/5" and _msg().contains("0.1.60"), "у вас старая — «…у друга — 0.1.60» (%s)" % _state())
	_online.call("_on_net", &"friend_refused", {"their": {}, "verdict": "odd"})
	await process_frame
	_check(_state() == "host_wait/7" and _msg().contains("собраны по-разному"), "номер тот же, код разный — «собраны по-разному»")
	# Radmin VPN не найден; два домашних адреса; «Дома» не найден
	await _host_wait({"radmin": "", "home": PackedStringArray(["192.168.0.7", "10.0.0.4"])})
	var rows := (_online.find_child("Addresses", true, false) as Control)
	var how := rows.find_child("Radmin_how", true, false)
	_check(_state() == "host_wait/4" and how != null and _msg().begins_with("Radmin VPN не найден"),
		"Radmin VPN не найден — «не найден», «Как поставить», записка о нём (%s)" % _state())
	_check(rows.find_child("Copy_1", true, false) != null and rows.find_child("Copy_2", true, false) != null,
		"два домашних адреса — обе строки со своими «Копировать»")
	await process_frame
	var sheet := _online.get("sheet") as Control
	var view := (_online.get_parent() as Control).get_viewport_rect().size
	var r := sheet.get_global_rect()
	_check(Rect2(Vector2.ZERO, view).grow(0.5).encloses(r), "три строки адресов — лист на холсте (%s)" % r)
	await _host_wait({"radmin": "26.1.2.3", "home": PackedStringArray()})
	var home_gone := _online.find_child("Addresses", true, false) as Control
	_check(home_gone.find_child("Copy_1", true, false) == null, "«Дома» не найден — строка без «Копировать»")
	_online.call("_show", "choose", 0)


func _guest_side() -> void:
	print("[подключившийся]")
	_online.call("_show", "join", 0)
	await process_frame
	_check(_online.find_child("Join_recent", true, false) == null, "первый раз — без «В прошлый раз»")
	var cfg := ConfigFile.new()
	cfg.set_value("net", "last_addr", "26.40.50.60")
	cfg.save(NetSession._settings_path())
	_online.call("_show", "join", 0)
	await process_frame
	var recent := _online.find_child("Join_recent", true, false) as Button
	_check(recent != null and recent.text.ends_with("26.40.50.60"), "«В прошлый раз: 26.40.50.60» — из настроек")
	_online.set("_addr", "26.40.50.60")
	_online.set("_conn_t0", Time.get_ticks_msec())
	_online.call("_show", "join_connecting", 0)
	await process_frame
	_online.call("_on_net", &"reached", {})
	await process_frame
	_check(bool(_online.get("_checking")) and _msg_kind() == "green", "друг ответил — «связь есть», сверяем версии")
	_ns.lobby_side = 0
	_ns.lobby_seed = 731902
	_online.call("_on_net", &"joined", {})
	await process_frame
	var me := _online.find_child("Tablet_me", true, false) as Control
	var seed_ok := false
	for l in _online.find_children("*", "Label", true, false):
		if _norm((l as Label).text).contains("731 902"):
			seed_ok = true
	_check(_state() == "join_wait/0" and me != null and seed_ok, "«Вы в игре у друга»: номер партии хозяина 731 902 (%s)" % _state())
	var mine_side := _texts(me)
	_check(mine_side.has("Кыпчаки"), "хозяин за Коканд — вы за кыпчаков (%s)" % ", ".join(mine_side))
	_ns.lobby_side = 1
	_online.call("_on_net", &"lobby", {"side": 1, "seed": 731902})
	await process_frame
	me = _online.find_child("Tablet_me", true, false) as Control
	_check(_texts(me).has("Коканд") and _msg().contains("теперь вы за Коканд"), "хозяин сменил сторону — «теперь вы за Коканд» (%s)" % _msg())
	_online.call("_on_net", &"host_left", {})
	await process_frame
	_check(_state() == "join_wait/2" and _msg().begins_with("Друг вышел"), "хозяин вышел — «Друг вышел из игры…»")
	_online.call("_on_net", &"host_lost", {})
	await process_frame
	_check(_state() == "join_wait/3" and _msg().begins_with("Связь с другом пропала"), "хозяин пропал — «Связь с другом пропала»")
	var newer := {"number": "0.1.70", "date": 20261101, "code": "aa00000000000000".hex_decode()}
	_online.call("_on_net", &"refused", {"why": "version", "their": newer, "verdict": "mine_old"})
	await process_frame
	var rows := _texts(_online.find_child("Body", true, false) as Control)
	_check(_state() == "version/0" and ", ".join(rows).contains("0.1.70 от 1 нояб."),
		"«Разные версии»: у вас старая, у друга «0.1.70 от 1 нояб.» — новее")
	_online.call("_on_net", &"refused", {"why": "version", "their": {"number": "", "date": 20261016, "code": "bb00000000000000".hex_decode()}, "verdict": "odd"})
	await process_frame
	_check(_state() == "version/1" and ", ".join(_texts(_online.find_child("Body", true, false) as Control)).contains("код BB00"),
		"номер тот же, код разный — оба кода на экране (BB00)")
	_online.call("_on_net", &"refused", {"why": "busy", "their": {}, "verdict": ""})
	await process_frame
	_check(_state() == "join_fail/1" and _msg().contains("место занято"), "у друга уже есть второй игрок — «место занято»")
	_online.call("_on_net", &"connect_failed", {"why": "timeout"})
	await process_frame
	_check(_state() == "join_fail/0" and _msg().contains("26.40.50.60") and _msg().contains("15 секунд"),
		"не ответил — «Не получилось подключиться к 26.40.50.60 — друг не ответил за 15 секунд.»")


## «Город» в партии по сети (без сети: --net_demo=slow — друг «играет» пустыми приказами): записки связи поверх
## интерфейса, меню паузы без «Начать заново» и пауза в нём — общая (приказом), конец партии без «Ещё раз»
func _city_part(ordo: Node) -> void:
	print("[«Город» в партии по сети]")
	ordo.call("set_arg", "net_demo", "slow")
	var s: Node = (load("res://scenes/gorod/gorod.tscn") as PackedScene).instantiate()
	root.add_child(s)
	for i in 20:
		await process_frame
	var play := s.get("play") as GorodPlay
	var drv := s.get_node("Driver") as GameDriver
	_check(play != null and drv.net != null and play.net_hud != null, "у драйвера партия по сети — записки связи поставлены")
	_check(drv.game.ai.is_empty() and drv.game.players_cfg[1]["ctrl"] == PlayerTable.Ctrl.HUMAN, "оба игрока — люди, ИИ нет")
	var t0 := drv.game.tick
	for i in 30:
		await process_frame
	_check(drv.game.tick > t0, "партия идёт (такт %d → %d)" % [t0, drv.game.tick])
	var hud := play.hud
	_check(not hud.modal_open() and hud.notes.visible, "записки связи — не окно поверх игры: записки «Города» видны")
	hud.open_menu()
	var labels := []
	for b in hud.menu.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree():
			labels.append((b as Button).text)
	_check(not labels.has("Начать заново") and labels.has("В главное меню") and labels.has("Продолжить"),
		"меню паузы: %s — без «Начать заново»" % ", ".join(PackedStringArray(labels)))
	_check(drv.pause_wanted() and not drv.paused, "меню ставит общую паузу — приказом, через задержку приказов")
	for i in 20:
		await process_frame
	_check(drv.paused and drv.net.paused, "пауза наступила (такт %d)" % drv.game.tick)
	hud.menu.close()
	_check(not drv.paused and not drv.pause_wanted(), "меню закрыто — пауза снята у обоих")
	# пауза стояла до меню (P), друг снял её, пока меню открыто, — закрытое меню паузу снова не ставит
	drv.request_pause(true)
	var waited := 0.0
	while not drv.net.paused and waited < 3.0:
		await create_timer(0.05).timeout
		waited += 0.05
	var pt := drv.net.paused_tick
	hud.open_menu()
	drv.net.on_bytes(NetProto.msg(NetProto.Msg.RESUME, PackedInt32Array([pt, 1, NetMatch.RESUME_NOW])))
	_check(drv.net.paused == false and not drv.paused, "друг снял паузу, пока меню открыто, — игра идёт (такт %d)" % pt)
	hud.menu.close()
	_check(not drv.pause_wanted() and not drv.paused, "меню закрыто — паузу снова не ставит (друг её уже снял)")
	await _menu_quit(play, hud)
	await _net_notes(play, drv)
	play.call("_on_over", 0)
	await process_frame
	var end := hud.root.find_child("EndScreen", true, false)
	var end_labels := []
	if end:
		for b in end.find_children("*", "Button", true, false):
			end_labels.append((b as Button).text)
	_check(end != null and end_labels == ["В главное меню"], "конец партии — только «В главное меню» (%s)" % str(end_labels))
	s.free()
	ordo.call("clear_arg", "net_demo")
	await process_frame


## Меню партии по сети: «В главное меню» — сперва «Выйти из партии?»: «Остаться» — назад в меню, «Выйти» — выйти
func _menu_quit(play: GorodPlay, hud: CityHud) -> void:
	var quits := [0]
	var counter := func() -> void: quits[0] += 1
	hud.quit_requested.disconnect(play._to_menu)
	hud.quit_requested.connect(counter)
	hud.open_menu()
	var to_menu: Button = null
	for b in hud.menu.find_children("*", "Button", true, false):
		if (b as Button).text == "В главное меню":
			to_menu = b
	to_menu.pressed.emit()
	var confirm := hud.menu.find_child("Confirm", true, false) as Control
	_check(hud.menu.confirm_open() and quits[0] == 0 and _texts(confirm).has("Выйти из партии?"),
		"«В главное меню» — сперва «Выйти из партии?», из партии ещё не вышли")
	(hud.menu.find_child("Confirm_Остаться", true, false) as Button).pressed.emit()
	_check(hud.menu.is_open() and not hud.menu.confirm_open() and quits[0] == 0, "«Остаться» — назад в меню")
	to_menu.pressed.emit()
	(hud.menu.find_child("Confirm_Выйти", true, false) as Button).pressed.emit()
	_check(quits[0] == 1 and not hud.menu.is_open(), "«Выйти» — выход из партии")
	hud.quit_requested.disconnect(counter)
	hud.quit_requested.connect(play._to_menu)
	await create_timer(0.2).timeout


## Записки связи: меню друга, связь пропала (лист «Ждём друга…»), друг вышел, партия остановлена
func _net_notes(play: GorodPlay, drv: GameDriver) -> void:
	var nh := play.net_hud
	var m := drv.net
	# друг открыл меню — «Друг открыл меню», а не просто «поставил паузу»
	m.paused = true
	m.paused_tick = drv.game.tick
	m.pause_mask = 1 << m.remote
	m.pause_by = m.remote
	m.on_bytes(NetProto.msg(NetProto.Msg.MENU, PackedInt32Array([1])))
	await create_timer(0.25).timeout
	var pin := nh.find_child("NetPin", true, false) as Control
	_check(pin.visible and _texts(pin).has("Друг открыл меню — игра стоит у обоих"), "друг открыл меню — «Друг открыл меню — игра стоит у обоих»")
	m.on_bytes(NetProto.msg(NetProto.Msg.MENU, PackedInt32Array([0])))
	drv.request_pause(false)
	# связь пропала: лист «Ждём друга…» — красная печать, когда ждать бесполезно, «ждём уже …», «Выйти» — переспросить
	m.on_link(&"lost")
	await create_timer(0.25).timeout
	var wait := nh.find_child("NetWait", true, false) as Control
	var wt := ", ".join(_texts(wait)) if wait else ""
	_check(wait != null and wt.contains("он не вернётся — тогда нажмите «Выйти»") and wt.contains("ждём уже 0:0"),
		"связь пропала — «Ждём друга…»: когда ждать бесполезно, «ждём уже 0:00» (%s)" % wt)
	(nh.find_child("NetQuit", true, false) as Button).pressed.emit()
	var confirm := nh.find_child("NetConfirm", true, false) as Control
	_check(confirm != null and _texts(confirm).has("Выйти из партии?"), "«Выйти» — сперва «Выйти из партии?»")
	(nh.find_child("NetStay", true, false) as Button).pressed.emit()
	await process_frame
	_check(nh.find_child("NetConfirm", true, false) == null and nh.find_child("NetWait", true, false) != null, "«Остаться» — ждём дальше")
	# друг вышел: лист по тексту, «Открыть папку» и «В главное меню», пути на листе нет (он — в подсказке)
	m.on_link(&"left")
	await create_timer(0.25).timeout
	var end := nh.find_child("NetEnd", true, false) as Control
	var sheet := end.get_node("Sheet") as Control if end else null
	var et := ", ".join(_texts(sheet)) if sheet else ""
	var folder := nh.find_child("NetFolder", true, false) as Button
	_check(sheet != null and folder != null and nh.find_child("NetMenu", true, false) != null and not et.contains("/")
		and folder.tooltip_text.contains("net"), "«Друг вышел из игры»: «Открыть папку» (путь — в подсказке), «В главное меню»")
	var left_h := sheet.size.y if sheet else 0.0
	var band := 999.0
	if sheet and folder:
		var row := folder.get_parent() as Control
		var col := row.get_parent() as Control
		band = sheet.size.y - (col.position.y + row.position.y + folder.position.y + folder.size.y)
	_check(left_h > 0.0 and band > 20.0 and band < 60.0, "лист по тексту: высота %.0f, под кнопками %.0f (не пустая полоса)" % [left_h, band])
	# партия остановлена: почему (Windows и Linux или ошибка), что делать; без «не с того же сайта»
	m.link = &"desync"
	m.desync_tick = 120
	await create_timer(0.25).timeout
	end = nh.find_child("NetEnd", true, false) as Control
	sheet = end.get_node("Sheet") as Control if end else null
	et = ", ".join(_texts(sheet)) if sheet else ""
	_check(et.contains("Партия остановлена") and et.contains("Windows") and et.contains("Начните новую партию")
		and not et.contains("сайта") and not et.contains("/"), "«Партия остановлена»: почему и что делать, без «не с того же сайта» и пути")
	_check(sheet != null and sheet.size.y > left_h, "лист «Партия остановлена» выше — текста больше (%.0f > %.0f)" % [sheet.size.y if sheet else 0.0, left_h])


func _texts(n: Control) -> PackedStringArray:
	var out := PackedStringArray()
	if n == null:
		return out
	for l in n.find_children("*", "Label", true, false):
		out.append(_norm((l as Label).text))
	return out
