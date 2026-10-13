extends SceneTree
## Повтор «Города» (ARCHITECTURE §3 #24, §15 GAME; CONTRACT §10.4):
##   • SimCmd.encode/decode туда и обратно, испорченные байты — пустой список;
##   • повтор из журнала равен живой игре (сценарный игрок против ИИ, 8 мин с первым набегом);
##   • изменённый журнал расходится; другие данные (Defs.hash) — повтор не запускается;
##   • файл повтора: запись и чтение;
##   • GameDriver: игра узлом (issue → такт + 1), запись повтора, просмотр повтора до конца.
## Реализации — GameSim.impl_for: по умолчанию настоящие (если они в проекте), --impl=stub или ORDO_IMPL=stub — заглушки.
##   godot --headless --path ordo --script res://tests/test_replay.gd [-- --impl=stub]

var _impl := {}


func _init() -> void:
	_impl = GameSim.impl_for(OS.get_cmdline_user_args(), OS.get_environment("ORDO_IMPL"))
	_test_encode()
	_test_live_vs_replay()
	_test_driver()
	SimHarness.finish(self)


func _test_encode() -> void:
	print("[SimCmd.encode / decode]")
	var rng := BattleRng.new(77)
	var cmds: Array[PackedInt32Array] = []
	for i in 300:
		var h := Ids.make(1 + rng.range_i(5), rng.range_i(5000), 1 + rng.range_i(4000))
		var c: PackedInt32Array
		match i % 6:
			0: c = SimCmd.move(PackedInt32Array([h]), Vector2(rng.range_f(-500, 500), rng.range_f(-500, 500)), i % 2 == 0)
			1: c = SimCmd.build_wall(PackedInt32Array([h]), 3, PackedVector2Array([Vector2(1, 2), Vector2(30.5, -4.25), Vector2(-7, 9)]))
			2: c = SimCmd.train(h, rng.range_i(20), 1 + rng.range_i(5))
			3: c = SimCmd.spawn(rng.range_i(20), 1 + rng.range_i(100), Vector2(-340, 40), PI * 0.5, -1)
			4: c = SimCmd.attack(PackedInt32Array([h, h + 1]), h + 2)
			_: c = SimCmd.stop(PackedInt32Array())
		c[SimCmd.H_PLAYER] = i % 3
		c[SimCmd.H_TICK] = i * 7
		c[SimCmd.H_SEQ] = i
		cmds.append(c)
	var bytes := SimCmd.encode(cmds)
	var back := SimCmd.decode(bytes)
	var same := back.size() == cmds.size()
	for i in mini(back.size(), cmds.size()):
		same = same and back[i] == cmds[i]
	SimHarness.check(same, "300 приказов туда и обратно (%d байт)" % bytes.size())
	var broken := bytes.slice(0, bytes.size() - 6)
	SimHarness.check(SimCmd.decode(broken).is_empty() and SimCmd.decode(PackedByteArray([1, 2, 3])).is_empty(),
		"обрезанные и чужие байты — пустой список")


func _play(p_seed: int, ticks: int) -> GameSim:
	var g := GameSim.new()
	g.impl = _impl.duplicate()
	g.setup(MapValley.MAP, SimHarness.default_players(), p_seed)
	var sp := ScriptedPlayer.new(0)
	while g.tick < ticks:
		for c in sp.commands(g.tick, g.query):
			g.submit(0, c)
		g.step()
	return g


func _test_live_vs_replay() -> void:
	print("[повтор = живая игра]")
	var g := _play(11, 30 * 60 * 8)
	var rec := g.replay_record()
	var started := 0
	var r := g.events.range_since(0)
	for seq in range(r.x, r.y):
		if g.events.e_kind[g.events.at(seq)] == SimEvents.Ev.RAID_STARTED:
			started += 1
	var n_ext := SimCmd.decode(rec["log"]).size()
	SimHarness.check(n_ext > 30 and started >= 1 and g.orders.rejected > 0,
		"живая игра 8 мин: внешних приказов %d, отказов %d, набегов %d" % [n_ext, g.orders.rejected, started])
	SimHarness.check(rec["checksums"].size() == 30 * 8 * 2, "контрольных сумм: %d (раз в 30 тактов)" % rec["checksums"].size())
	var ok := Replay.verify(rec, _impl)
	SimHarness.check(ok, "повтор из журнала совпал с живой игрой %s" % Replay.last_error)
	var g2 := Replay.make_game(rec, _impl)
	Replay.run(g2, rec)
	SimHarness.check(g2.checksum() == g.checksum() and g2.tick == g.tick and g2.orders.applied == g.orders.applied,
		"конец повтора: та же сумма, такт и число исполненных приказов")
	# изменённый журнал: лишний приказ — повтор расходится. Юнит — живой на такте приказа (900): первый юнит
	# игрока к концу игры мог появиться позже, тогда приказ — отказ «устарел», и суммы не расходятся
	var log := SimCmd.decode(rec["log"])
	var g3 := Replay.make_game(rec, _impl)
	while g3.tick < 899:
		g3.step()
	var w := PackedInt32Array()
	for u in g3.query.units_of(0):
		w.append(u)
		break
	var extra := SimCmd.move(w, Vector2(100, 100), true)
	extra[SimCmd.H_PLAYER] = 0
	extra[SimCmd.H_TICK] = 900
	extra[SimCmd.H_SEQ] = 99999
	log.append(extra)
	var bad := rec.duplicate(true)
	bad["log"] = SimCmd.encode(log)
	SimHarness.check(not Replay.verify(bad, _impl), "лишний приказ в журнале — повтор расходится (%s)" % Replay.last_error)
	var wrong := rec.duplicate(true)
	wrong["defs_hash"] = int(rec["defs_hash"]) ^ 1
	SimHarness.check(Replay.make_game(wrong, _impl) == null and Replay.last_error != "", "другие данные — не запускается: %s" % Replay.last_error)
	# файл
	var path := "user://test_replay.ordorep"
	SimHarness.check(Replay.save(path, rec), "повтор записан в %s" % path)
	var loaded := Replay.load_file(path)
	SimHarness.check(not loaded.is_empty() and loaded["log"] == rec["log"] and Replay.verify(loaded, _impl), "файл прочитан и проигран")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_driver() -> void:
	print("[GameDriver]")
	var d := GameDriver.new()
	d.autostart = false
	d.game_impl = _impl.duplicate()
	var seen := [0]
	d.ticked.connect(func(t: int) -> void: seen[0] = t)
	d.start_game(17, &"kipchak", 1)
	SimHarness.check(d.game != null and d.query is GameQueryImpl and d.game.econ.players.faction[0] == d.game.defs.faction(&"kipchak"),
		"start_game: местный игрок — кыпчаки, окно чтения — GameQueryImpl")
	for i in 90:
		d.step()
	var ws := PackedInt32Array()
	for u in d.query.units_of(0):
		if (d.query as GameQueryImpl).unit_flags(u) & UnitStats.WORKER:
			ws.append(u)
	d.issue(SimCmd.move(ws, Vector2(-140, 140)))
	for i in 600:
		d.step()
	SimHarness.check(seen[0] == 690 and d.game.orders.applied >= 1, "ticked на каждом такте, приказ исполнен")
	var path := "user://test_driver.ordorep"
	SimHarness.check(d.save_replay(path), "save_replay")
	var v := GameDriver.new()
	v.autostart = false
	v.game_impl = _impl.duplicate()
	SimHarness.check(v.start_replay(path), "start_replay")
	v.issue(SimCmd.stop(ws))                       # в просмотре повтора свои приказы не идут
	for i in 800:
		v.step()
	SimHarness.check(v.paused and v.game.tick == d.game.tick and v.game.checksum() == d.game.checksum(),
		"повтор узлом дошёл до конца записи и встал на паузу с той же суммой")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	d.free()
	v.free()
