extends SceneTree
## Игра по сети на одном компьютере: две (и три) настоящие игры — отдельные процессы Godot (tests/net_peer.gd),
## ENet по UDP через 127.0.0.1 (только свой компьютер: Windows не спрашивает про доступ к сети), ТЗ §16:
##   • партия: хозяин и друг 900 тактов отдают сценарные приказы (стройка, найм, ход, добыча) — суммы каждые 30
##     тактов совпадают (сверены и по сети: 30 сверок у каждой игры), в конце тоже; повторы обеих игр одинаковые
##     и совпадают с партией (Replay.verify) — повтор партии по сети пишется так же, как одиночной;
##   • обрыв: на такте 300 у друга пропала связь (без «пока»), он стучится снова сам (метка партии) — обе игры
##     продолжают с того же такта, суммы в конце те же, что у партии без обрыва;
##   • другая игра: тот же номер версии, другой код — отказ «Разные версии игры», вердикт «собраны по-разному»;
##     старая версия у друга — у него «старая у вас», у хозяина «старая у друга»;
##   • третий: у хозяина уже есть друг — третьему отказ с причиной «место занято» (не «друг не ответил»);
##   • лобби: друг вышел сам (с «пока») — у хозяина «Друг вышел»; пропал без «пока» — «Связь с другом пропала»;
##   • место занято: второе окно «Ордо» создаёт игру на том же порту — ошибка (лобби: choose, вариант 1);
##   • окно закрыли крестиком (посреди партии и в лобби; друг и хозяин): другой узнаёт «вышел» меньше чем за
##     секунду (а не через 8–20 с, когда ENet заметит отключение) и не стучится снова; закрывшая игра выходит сама,
##     когда «пока» ушло;
##   • в журналах игр нет ошибок движка и скриптов.
## Журналы и итоги игр — во временной папке (печатается); при провале её не удаляем.
##   godot --headless --path ordo --script res://tests/test_net_two.gd

const PEER := "res://tests/net_peer.gd"
const TICKS := 900

var _exe := ""
var _dir := ""
var _port := 0
var _keep := false
## Когда процесс кончился (по часам компьютера; _wait смотрит раз в 0,25 с)
var _exit_unix := {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_exe = OS.get_executable_path()
	_dir = OS.get_cache_dir().path_join("ordo_net_test_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(_dir)
	_port = 41000 + (OS.get_process_id() * 7) % 9000
	print("папка проверки: ", _dir)
	var base := await _case_match()
	await _case_reconnect(base)
	await _case_version()
	await _case_third()
	await _case_leave()
	await _case_port_busy()
	await _case_close()
	if SimHarness.fails == 0 and not _keep:
		for f in DirAccess.get_files_at(_dir):
			DirAccess.remove_absolute(_dir.path_join(f))
		DirAccess.remove_absolute(_dir)
	SimHarness.finish(self)


## Новая игра (процесс): журнал и итог — в папке проверки под именем name
func _spawn(name: String, args: Array) -> int:
	var a := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", _dir.path_join(name + ".log"), "--script", PEER, "--"])
	for s in args:
		a.append(String(s))
	a.append("--out=" + _dir.path_join(name + ".json"))
	a.append("--net_bind=127.0.0.1")
	a.append("--net_no_save")
	return OS.create_process(_exe, a)


## Дождаться конца процессов (не дольше limit секунд; повисшие — снять)
func _wait(pids: Array, limit: float) -> bool:
	var t := 0.0
	while t < limit:
		var alive := false
		for p: int in pids:
			if p > 0 and OS.is_process_running(p):
				alive = true
			elif not _exit_unix.has(p):
				_exit_unix[p] = Time.get_unix_time_from_system()
		if not alive:
			return true
		await create_timer(0.25).timeout
		t += 0.25
	for p: int in pids:
		if p > 0 and OS.is_process_running(p):
			OS.kill(p)
	_keep = true
	return false


func _result(name: String) -> Dictionary:
	var path := _dir.path_join(name + ".json")
	if not FileAccess.file_exists(path):
		_keep = true
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}


## Журналы игр без ошибок движка и скриптов (ERROR / SCRIPT ERROR / падение)
func _clean_logs(names: Array) -> void:
	var bad := PackedStringArray()
	for n: String in names:
		var text := FileAccess.get_file_as_string(_dir.path_join(n + ".log"))
		for line in text.split("\n"):
			if line.begins_with("ERROR") or line.begins_with("SCRIPT ERROR") or line.contains("CrashHandlerException"):
				bad.append("%s: %s" % [n, line.strip_edges()])
	SimHarness.check(bad.is_empty(), "в журналах игр нет ошибок%s" % ("" if bad.is_empty() else " — " + " | ".join(bad.slice(0, 4))))
	if not bad.is_empty():
		_keep = true


func _has_event(r: Dictionary, kind: String) -> Array:
	var out := []
	for e: Dictionary in r.get("events", []):
		if String(e.get("kind", "")) == kind:
			out.append(e)
	return out


func _case_match() -> Dictionary:
	print("[партия по сети: две игры, 900 тактов]")
	var port := _port
	var h := _spawn("m_host", ["--role=host", "--net_port=%d" % port, "--ticks=%d" % TICKS,
		"--replay=" + _dir.path_join("m_host.ordorep")])
	var g := _spawn("m_guest", ["--role=guest", "--addr=127.0.0.1", "--net_port=%d" % port, "--ticks=%d" % TICKS,
		"--replay=" + _dir.path_join("m_guest.ordorep")])
	var done := await _wait([h, g], 150.0)
	var rh := _result("m_host")
	var rg := _result("m_guest")
	SimHarness.check(done and h > 0 and g > 0, "обе игры завершились сами (%.1f и %.1f с)" % [rh.get("seconds", -1.0), rg.get("seconds", -1.0)])
	SimHarness.check(rh.get("result") == "ok" and rg.get("result") == "ok" and int(rh.get("tick", 0)) == TICKS
		and int(rg.get("tick", 0)) == TICKS, "обе дошли до такта %d (%s / %s)" % [TICKS, rh.get("result"), rg.get("result")])
	SimHarness.check(int(rh.get("local", -1)) == 0 and int(rg.get("local", -1)) == 1 and int(rh.get("delay", 0)) >= 4,
		"хозяин — игрок 0, друг — игрок 1; задержка приказов %d тактов" % int(rh.get("delay", 0)))
	var sh: Array = rh.get("sums", [])
	var sg: Array = rg.get("sums", [])
	SimHarness.check(sh.size() == TICKS / 30 and sh == sg, "суммы каждые 30 тактов совпадают (%d)" % sh.size())
	SimHarness.check(rh.get("final", "a") == rg.get("final", "b"), "сумма в конце совпадает (%s)" % rh.get("final", ""))
	SimHarness.check(int(rh.get("checks_ok", 0)) == TICKS / 30 and int(rg.get("checks_ok", 0)) == TICKS / 30
		and int(rh.get("checked_upto", 0)) == TICKS, "сверка по сети: %d и %d совпавших сумм" % [rh.get("checks_ok", 0), rg.get("checks_ok", 0)])
	SimHarness.check(int(rh.get("cmds", 0)) > 30 and rh.get("cmds") == rg.get("cmds"),
		"приказов обоих игроков в журнале: %d у хозяина, %d у друга" % [rh.get("cmds", 0), rg.get("cmds", 0)])
	var rec_h := Replay.load_file(_dir.path_join("m_host.ordorep"))
	var rec_g := Replay.load_file(_dir.path_join("m_guest.ordorep"))
	SimHarness.check(not rec_h.is_empty() and not rec_g.is_empty() and rec_h.get("log") == rec_g.get("log")
		and rec_h.get("checksums") == rec_g.get("checksums"), "повторы хозяина и друга одинаковые")
	SimHarness.check(not rec_h.is_empty() and Replay.verify(rec_h), "повтор партии по сети совпадает с ней %s" % Replay.last_error)
	SimHarness.check(not _has_event(rh, "friend_joined").is_empty() and not _has_event(rg, "reached").is_empty()
		and not _has_event(rg, "joined").is_empty() and not _has_event(rg, "start").is_empty(),
		"лобби: друг вошёл, «связь есть, сверяем версии», вы в игре, «Начать игру»")
	_clean_logs(["m_host", "m_guest"])
	return rh


func _case_reconnect(base: Dictionary) -> void:
	print("[обрыв связи посреди партии и переподключение]")
	var port := _port + 1
	var h := _spawn("r_host", ["--role=host", "--net_port=%d" % port, "--ticks=%d" % TICKS])
	var g := _spawn("r_guest", ["--role=guest", "--addr=127.0.0.1", "--net_port=%d" % port, "--ticks=%d" % TICKS,
		"--drop_at=300"])
	var done := await _wait([h, g], 180.0)
	var rh := _result("r_host")
	var rg := _result("r_guest")
	SimHarness.check(done and bool(rg.get("dropped", false)), "у друга на такте 300 пропала связь (без «пока»)")
	SimHarness.check(rh.get("result") == "ok" and rg.get("result") == "ok", "переподключился сам — обе игры дошли до %d (%s / %s)" % [
		TICKS, rh.get("result"), rg.get("result")])
	SimHarness.check(rh.get("sums", []) == rg.get("sums", []) and rh.get("final", "a") == rg.get("final", "b"),
		"суммы каждые 30 тактов и в конце совпадают")
	SimHarness.check(rh.get("final", "a") == base.get("final", "b"),
		"и совпадают с партией без обрыва (%s)" % rh.get("final", ""))
	SimHarness.check(int(rh.get("checks_ok", 0)) == TICKS / 30, "все 30 сверок по сети прошли и после обрыва (%d)" % rh.get("checks_ok", 0))
	var lost := _has_event(rh, "friend_lost")
	SimHarness.check(lost.is_empty() and _has_event(rh, "friend_left").is_empty(),
		"посреди партии обрыв — не событие лобби: партия сама ждёт и продолжает")
	_clean_logs(["r_host", "r_guest"])


func _case_version() -> void:
	print("[разные версии игры]")
	var port := _port + 2
	var h := _spawn("v_host", ["--role=host", "--mode=lobby", "--stay=9", "--net_port=%d" % port])
	await create_timer(1.0).timeout
	var odd := _spawn("v_odd", ["--role=guest", "--mode=lobby", "--stay=7", "--addr=127.0.0.1", "--net_port=%d" % port,
		"--net_fake_code=deadbeefdeadbeef"])
	await create_timer(2.5).timeout
	var old := _spawn("v_old", ["--role=guest", "--mode=lobby", "--stay=7", "--addr=127.0.0.1", "--net_port=%d" % port,
		"--net_fake_code=0123456789abcdef", "--net_fake_version=0.1.2", "--net_fake_date=20200101"])
	var done := await _wait([h, odd, old], 40.0)
	var rh := _result("v_host")
	var ro := _result("v_odd")
	var rl := _result("v_old")
	SimHarness.check(done, "три игры завершились")
	SimHarness.check(ro.get("result") == "refused" and ro.get("why") == "version" and ro.get("verdict") == "odd",
		"тот же номер, другой код — «Разные версии», игры собраны по-разному (%s, %s, %s)" % [ro.get("result"), ro.get("why"), ro.get("verdict")])
	SimHarness.check(rl.get("result") == "refused" and rl.get("why") == "version" and rl.get("verdict") == "mine_old",
		"у друга старая версия — у него «старая у вас» (%s)" % rl.get("verdict"))
	var refused := _has_event(rh, "friend_refused")
	var verdicts := []
	for e: Dictionary in refused:
		verdicts.append(e.get("verdict", ""))
	SimHarness.check(verdicts == ["odd", "theirs_old"] and _has_event(rh, "friend_joined").is_empty(),
		"у хозяина: «друг не смог войти» — собраны по-разному, потом «старая у друга» (%s); никто не вошёл" % str(verdicts))
	_clean_logs(["v_host", "v_odd", "v_old"])


func _case_third() -> void:
	print("[третий игрок]")
	var port := _port + 3
	var h := _spawn("t_host", ["--role=host", "--mode=lobby", "--stay=9", "--net_port=%d" % port])
	await create_timer(1.0).timeout
	var g := _spawn("t_guest", ["--role=guest", "--mode=lobby", "--stay=7", "--addr=127.0.0.1", "--net_port=%d" % port])
	await create_timer(2.5).timeout
	var t := _spawn("t_third", ["--role=guest", "--mode=lobby", "--stay=5", "--addr=127.0.0.1", "--net_port=%d" % port])
	var done := await _wait([h, g, t], 40.0)
	var rh := _result("t_host")
	var rg := _result("t_guest")
	var rt := _result("t_third")
	SimHarness.check(done and rg.get("result") == "lobby" and bool(rg.get("joined", false)), "первый друг вошёл и ждёт начала (%s)" % rg.get("result"))
	SimHarness.check(rt.get("result") == "refused" and rt.get("why") == "busy",
		"третьему — отказ с причиной «место занято» (%s, %s)" % [rt.get("result"), rt.get("why")])
	SimHarness.check(_has_event(rh, "friend_joined").size() == 1, "у хозяина вошёл один друг")
	_clean_logs(["t_host", "t_guest", "t_third"])


## Лобби: друг вышел сам («Выйти» — с «пока») — у хозяина «Друг вышел»; пропал без «пока» — «Связь с другом
## пропала» (ТЗ §16: различимы только так)
func _case_leave() -> void:
	print("[лобби: друг вышел сам или пропал]")
	var port := _port + 5
	var h := _spawn("l_host", ["--role=host", "--mode=lobby", "--stay=10", "--net_port=%d" % port])
	await create_timer(1.0).timeout
	var a := _spawn("l_bye", ["--role=guest", "--mode=lobby", "--stay=9", "--addr=127.0.0.1", "--net_port=%d" % port,
		"--leave_after=1.5"])
	await create_timer(4.5).timeout
	var b := _spawn("l_drop", ["--role=guest", "--mode=lobby", "--stay=9", "--addr=127.0.0.1", "--net_port=%d" % port,
		"--drop_after=1.5"])
	var done := await _wait([h, a, b], 40.0)
	var rh := _result("l_host")
	var kinds := []
	for e: Dictionary in rh.get("events", []):
		if String(e.get("kind", "")) in ["friend_joined", "friend_left", "friend_lost"]:
			kinds.append(e.get("kind"))
	SimHarness.check(done and _result("l_bye").get("result") == "left" and _result("l_drop").get("result") == "dropped",
		"первый друг вышел сам, второй пропал без «пока»")
	SimHarness.check(kinds == ["friend_joined", "friend_left", "friend_joined", "friend_lost"],
		"у хозяина: вошёл — «Друг вышел», вошёл снова — «Связь с другом пропала» (%s)" % str(kinds))
	_clean_logs(["l_host", "l_bye", "l_drop"])


func _case_port_busy() -> void:
	print("[место для игры по сети уже занято]")
	var port := _port + 4
	var a := _spawn("p_first", ["--role=host", "--mode=lobby", "--stay=5", "--net_port=%d" % port])
	await create_timer(1.5).timeout
	var b := _spawn("p_second", ["--role=host", "--mode=lobby", "--stay=2", "--net_port=%d" % port])
	var done := await _wait([a, b], 30.0)
	var ra := _result("p_first")
	var rb := _result("p_second")
	SimHarness.check(done and ra.get("result") == "lobby", "первое окно создало игру")
	SimHarness.check(rb.get("result") == "port_busy", "второе окно на том же порту — «место занято» (%s)" % rb.get("result"))
	_clean_logs(["p_first", "p_second"])


## Окно закрыли крестиком (NOTIFICATION_WM_CLOSE_REQUEST, как у Windows): закрывшая игра шлёт «пока» и выходит,
## когда оно ушло; другая узнаёт «вышел» сразу по «пока» — меньше чем за секунду, а не через 8–20 с (ENet), и не
## ждёт «Ждём друга…» / не стучится снова
func _case_close() -> void:
	print("[окно закрыли крестиком]")
	# посреди партии: закрыл друг, потом — хозяин
	for who: String in ["guest", "host"]:
		var port := _port + (6 if who == "guest" else 7)
		var n := "c" + who[0]
		var h := _spawn(n + "_host", ["--role=host", "--net_port=%d" % port, "--ticks=%d" % TICKS, "--timeout=60",
			"--replay=" + _dir.path_join(n + "_host.ordorep")] + (["--close_at=150"] if who == "host" else []))
		var g := _spawn(n + "_guest", ["--role=guest", "--addr=127.0.0.1", "--net_port=%d" % port, "--ticks=%d" % TICKS,
			"--timeout=60", "--replay=" + _dir.path_join(n + "_guest.ordorep")] + (["--close_at=150"] if who == "guest" else []))
		var done := await _wait([h, g], 70.0)
		var closer := _result(n + "_" + who)
		var other := _result(n + "_" + ("host" if who == "guest" else "guest"))
		var lag := float(other.get("left_unix", 0.0)) - float(closer.get("closed_unix", 0.0))
		var gone := float(_exit_unix.get(h if who == "host" else g, 0.0)) - float(closer.get("closed_unix", 0.0))
		var whom := "друг" if who == "guest" else "хозяин"
		SimHarness.check(done and closer.get("result") == "closed" and int(closer.get("tick", 0)) == 150,
			"посреди партии %s закрыл окно на такте %d" % [whom, int(closer.get("tick", 0))])
		SimHarness.check(other.get("result") == "link_left" and not bool(other.get("saw_lost", true)),
			"у другого — «Друг вышел из игры», без «Ждём друга…» и переподключения (%s)" % other.get("result"))
		SimHarness.check(lag >= 0.0 and lag < 1.0, "он узнал через %.2f с (а не через 8–20 с)" % lag)
		SimHarness.check(gone > 0.0 and gone < NetSession.BYE_WAIT + 1.0,
			"закрывшая игра вышла сама через %.2f с — когда «пока» ушло" % gone)
		_clean_logs([n + "_host", n + "_guest"])
	# лобби: друг вошёл и закрыл окно; потом хозяин закрыл окно при вошедшем друге
	for who: String in ["guest", "host"]:
		var port := _port + (8 if who == "guest" else 9)
		var n := "cl" + who[0]
		var h := _spawn(n + "_host", ["--role=host", "--mode=lobby", "--stay=8", "--net_port=%d" % port]
			+ (["--close_after=1.5"] if who == "host" else []))
		await create_timer(1.0).timeout
		var g := _spawn(n + "_guest", ["--role=guest", "--mode=lobby", "--stay=7", "--addr=127.0.0.1", "--net_port=%d" % port]
			+ (["--close_after=1.5"] if who == "guest" else []))
		var done := await _wait([h, g], 40.0)
		var closer := _result(n + "_" + who)
		var other := _result(n + "_" + ("host" if who == "guest" else "guest"))
		var kind := "friend_left" if who == "guest" else "host_left"
		var ev := _has_event(other, kind)
		var lag := (float(ev[0].get("unix", 0.0)) if not ev.is_empty() else 99.0) - float(closer.get("closed_unix", 0.0))
		var lost := _has_event(other, "friend_lost") + _has_event(other, "host_lost")
		SimHarness.check(done and closer.get("result") == "closed" and ev.size() == 1 and lost.is_empty(),
			"лобби: %s закрыл окно — у другого «Друг вышел» (%s), не «связь пропала»" % [
				"друг" if who == "guest" else "хозяин", kind])
		SimHarness.check(lag >= 0.0 and lag < 1.0, "и узнал через %.2f с" % lag)
		_clean_logs([n + "_host", n + "_guest"])
