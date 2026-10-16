extends SceneTree
## Одна игра для проверки по сети двумя процессами (tests/test_net_two.gd запускает две-три такие):
##   godot --headless --path ordo --script res://tests/net_peer.gd -- --role=host|guest [ключи]
## Настоящие NetSession (ENet, сверка версий) и NetMatch (шаг в ногу) без сцены: GameDriver в корне дерева,
## сценарный игрок (NetBot) отдаёт приказы через issue — как интерфейс. Итог — JSON в --out.
## Ключи:
##   --role=host|guest     хозяин (игрок 0, Коканд) или друг (игрок 1)
##   --mode=match|lobby    партия до --ticks тактов или только лобби (стоит --stay секунд, пишет события)
##   --addr=127.0.0.1      адрес хозяина (друг); --net_port=N, --net_bind=127.0.0.1 — порт и только свой компьютер
##   --ticks=900 --seed=4242 --drop_at=T (друг: на такте T обрыв связи без «пока», потом стучится снова сам)
##   --stay=С --timeout=С  сколько стоять в лобби; предел всей проверки
##   --replay=путь         повтор партии (как у одиночной игры)
##   --net_fake_code=…     другая игра (проверка «Разные версии»)
##   --close_at=T          партия: на такте T закрыть окно (крестик — NOTIFICATION_WM_CLOSE_REQUEST, как Windows);
##   --close_after=С       лобби: через С секунд после входа — то же. Итог пишется до закрытия ({result: closed,
##                         closed_unix}), игру закрывает сама NetSession — когда «пока» ушло
## Время событий — и от запуска (t), и по часам компьютера (unix): две игры сверяют, когда одна закрылась, а другая
## об этом узнала.

var _o: Node
var _role := "host"
var _mode := "match"
var _out := ""
var _ticks := 900
var _seed := 4242
var _drop_at := -1
var _stay := 10.0
var _timeout := 90.0
var _session: NetSession
var _driver: GameDriver
var _bot: NetBot
var _events: Array = []
var _sums: Array = []
var _dropped := false
var _t0 := 0


func _init() -> void:
	_run.call_deferred()


func _arg(name: String, def := "") -> String:
	return String(_o.call("arg", name, def)) if _o else def


func _run() -> void:
	await process_frame
	await process_frame
	_o = root.get_node_or_null("Ordo")
	_role = _arg("role", "host")
	_mode = _arg("mode", "match")
	_out = _arg("out", "")
	_ticks = int(_arg("ticks", "900"))
	_seed = int(_arg("seed", "4242"))
	_drop_at = int(_arg("drop_at", "-1"))
	_stay = float(_arg("stay", "10"))
	_timeout = float(_arg("timeout", "90"))
	_t0 = Time.get_ticks_msec()
	NetMatch.last_path = _arg("replay", "user://net/test_%s.ordorep" % _role)
	_session = NetSession.get_or_create(self)
	_session.event.connect(func(kind: StringName, info: Dictionary) -> void:
		var e := {"kind": String(kind), "t": _elapsed(), "unix": Time.get_unix_time_from_system()}
		for k in info:
			if k == "their":
				var th: Dictionary = info[k]
				e["their_number"] = String(th.get("number", ""))
				e["their_code"] = NetVersion.code_text(th.get("code", PackedByteArray()))
			else:
				e[k] = info[k]
		_events.append(e)
		print("[сеть %s] %.2f с: %s %s" % [_role, _elapsed(), kind, str(info.keys())]))
	NetVersion.wait()
	if _role == "host":
		await _host()
	else:
		await _guest()


func _elapsed() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0


## Когда (с запуска) было последнее событие этого вида; −1 — не было
func _event_t(kind: String) -> float:
	var t := -1.0
	for e: Dictionary in _events:
		if e.get("kind") == kind:
			t = float(e.get("t", 0.0))
	return t


func _host() -> void:
	var err := _session.host()
	if err != OK:
		_finish({"result": "port_busy", "err": err})
		return
	_session.send_lobby(0, _seed)
	if _mode == "lobby":
		# стоять в лобби; --close_after — закрыть окно через столько секунд после входа друга
		var t_end := _elapsed() + _stay
		while _elapsed() < t_end:
			var jt := _event_t("friend_joined")
			if jt >= 0.0 and _arg("close_after") != "" and _elapsed() - jt >= float(_arg("close_after")):
				await _close_window({})
				return
			await process_frame
		_finish({"result": "lobby", "friend": _session.connected()})
		return
	while not _session.connected():
		if _elapsed() > _timeout:
			_finish({"result": "no_friend"})
			return
		await process_frame
	# пара пингов, чтобы задержка приказов была по связи (как в лобби)
	await create_timer(1.2).timeout
	var m := _session.start_match(0, _seed)
	if m == null:
		_finish({"result": "start_failed"})
		return
	await _play()


func _guest() -> void:
	var err := _session.join(_arg("addr", "127.0.0.1"))
	if err != OK:
		_finish({"result": "join_error", "err": err})
		return
	while not _session.has_match_waiting():
		var last: Dictionary = _events.back() if not _events.is_empty() else {}
		var k := String(last.get("kind", ""))
		if k in ["refused", "connect_failed", "host_left", "host_lost"]:
			_finish({"result": k, "why": last.get("why", ""), "verdict": last.get("verdict", "")})
			return
		if _mode == "lobby" and _elapsed() > _stay:
			_finish({"result": "lobby", "joined": _session.connected()})
			return
		# лобби: вошли — через N секунд уйти самому («Выйти», с «пока») или пропасть без «пока»
		var joined_t := -1.0
		for e: Dictionary in _events:
			if e.get("kind") == "joined":
				joined_t = float(e.get("t", 0.0))
		if joined_t >= 0.0 and _arg("leave_after") != "" and _elapsed() - joined_t >= float(_arg("leave_after")):
			_session.leave()
			await create_timer(1.6).timeout
			_finish({"result": "left"})
			return
		if joined_t >= 0.0 and _arg("drop_after") != "" and _elapsed() - joined_t >= float(_arg("drop_after")):
			_session.simulate_drop()
			await create_timer(0.5).timeout
			_finish({"result": "dropped"})
			return
		if joined_t >= 0.0 and _arg("close_after") != "" and _elapsed() - joined_t >= float(_arg("close_after")):
			await _close_window({})
			return
		if _elapsed() > _timeout:
			_finish({"result": "no_start"})
			return
		await process_frame
	await _play()


func _play() -> void:
	_driver = GameDriver.new()
	_driver.autostart = false
	root.add_child(_driver)
	# шаги ведёт эта проверка (после такта — приказы бота), не время: _process драйвера выключен (после входа в
	# дерево — при входе Godot включает его сам)
	_driver.set_process(false)
	_driver.start_net_game(_session.take_match())
	var m := _driver.net
	_bot = NetBot.new(_driver.local_player)
	print("[сеть %s] партия: игрок %d, задержка %d, зерно %d" % [_role, _driver.local_player, m.delay, m.seed])
	var close_at := int(_arg("close_at", "-1"))
	var saw_lost := false
	var left_unix := 0.0
	while true:
		var steps := 0
		while steps < 6 and _driver.game.tick < _ticks and _driver.can_step():
			_driver.step()
			steps += 1
			var t := _driver.game.tick
			if t % 30 == 0:
				_sums.append(str(_driver.game.checksums[_driver.game.checksums.size() - 1]))
			for c in _bot.commands(t, _driver.query):
				_driver.issue(c)
			if _role == "guest" and t == _drop_at and not _dropped:
				_dropped = true
				print("[сеть %s] такт %d: обрыв связи (без «пока»)" % [_role, t])
				_session.simulate_drop()
				break
			if t == close_at:
				break
		if _driver.game.tick == close_at:
			await _close_window({"tick": _driver.game.tick})
			return
		saw_lost = saw_lost or m.link == &"lost"
		# конец: свой последний такт и сверка его суммы с другом
		if _driver.game.tick >= _ticks and m.checked_upto >= _ticks:
			break
		if m.link == &"desync" or m.link == &"left":
			left_unix = Time.get_unix_time_from_system()
			break
		if _elapsed() > _timeout:
			break
		await process_frame
	var rec := _driver.game.replay_record()
	var replay := _arg("replay", "")
	if replay != "":
		_driver.save_replay(replay)
	var res := {"result": "ok" if m.link == &"ok" and _driver.game.tick >= _ticks else "link_" + String(m.link),
		"tick": _driver.game.tick, "sums": _sums, "final": str(_driver.game.checksum()),
		"checked_upto": m.checked_upto, "checks_ok": m.checks_ok, "delay": m.delay, "local": _driver.local_player,
		"cmds": SimCmd.decode(rec["log"]).size(), "dropped": _dropped, "desync_tick": m.desync_tick,
		"saw_lost": saw_lost, "left_unix": left_unix}
	# дать другу дойти до конца, потом уйти самому («пока»)
	await create_timer(0.6).timeout
	_session.leave()
	await create_timer(0.4).timeout
	_finish(res)


## Закрыть окно крестиком, как Windows (NOTIFICATION_WM_CLOSE_REQUEST корню): итог — заранее, игру закрывает сама
## NetSession, когда «пока» ушло; не закрыла за 5 с — «close_stuck»
func _close_window(extra: Dictionary) -> void:
	var res := extra.duplicate()
	res["result"] = "closed"
	res["closed_unix"] = Time.get_unix_time_from_system()
	_write(res)
	print("[сеть %s] %.2f с: закрываем окно (крестик)" % [_role, _elapsed()])
	root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var t0 := _elapsed()
	while _elapsed() - t0 < 5.0:
		await process_frame
	_finish({"result": "close_stuck"})


func _write(res: Dictionary) -> void:
	res["role"] = _role
	res["events"] = _events
	res["seconds"] = _elapsed()
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(res, "  "))
			f.close()
	print("[сеть %s] итог: %s" % [_role, res.get("result")])


func _finish(res: Dictionary) -> void:
	_write(res)
	if _session:
		_session.close_now()
	if _driver:
		_driver.queue_free()
	quit(0)
