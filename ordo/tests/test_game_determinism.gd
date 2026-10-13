extends SceneTree
## Детерминизм «Города» (ARCHITECTURE §5.2, §15 GAME): одинаковое зерно → одинаковые контрольные суммы
## раз в 30 тактов.
##   • 15 мин «ИИ против сценарного игрока» × 2 — суммы совпадают;
##   • 15 мин «ИИ против ИИ» × 2 — совпадают; другое зерно — расходятся;
##   • ИИ ≤ 0.3 мс на такт в среднем.
## Берёт настоящие NavGrid / CombatPortBattle / EconomySim, если они уже в проекте (после I3), иначе заглушки.
##   godot --headless --path ordo --script res://tests/test_game_determinism.gd


class Prof:
	var acc := PackedInt64Array()
	var _last := 0

	func _init() -> void:
		acc.resize(GameSim.Ph.COUNT)

	func begin() -> void:
		_last = Time.get_ticks_usec()

	func mark(ph: int) -> void:
		var now := Time.get_ticks_usec()
		acc[ph] += now - _last
		_last = now


const MIN15 := 30 * 60 * 15


func _init() -> void:
	var g := GameSim.new()
	g.setup(MapValley.MAP, SimHarness.default_players(), 1)
	print("реализации: порт %s, навигация %s, экономика %s" % [_cls(g.port), _cls(g.nav), _cls(g.econ)])
	_test_vs_scripted()
	_test_ai_vs_ai()
	SimHarness.finish(self)


func _cls(o: Object) -> String:
	return (o.get_script() as Script).get_global_name()


func _run(p_seed: int, players: Array, scripted: bool, prof: Prof = null) -> GameSim:
	var g := GameSim.new()
	g.setup(MapValley.MAP, players, p_seed)
	g.prof = prof
	var sp := ScriptedPlayer.new(0)
	while g.tick < MIN15:
		if scripted:
			for c in sp.commands(g.tick, g.query):
				g.submit(0, c)
		if prof:
			prof.begin()
		g.step()
	return g


func _count(g: GameSim, kind: int) -> int:
	var k := 0
	var r := g.events.range_since(0)
	for seq in range(r.x, r.y):
		if g.events.e_kind[g.events.at(seq)] == kind:
			k += 1
	return k


func _test_vs_scripted() -> void:
	print("[15 мин: ИИ против сценарного игрока, дважды]")
	var prof := Prof.new()
	var t0 := Time.get_ticks_msec()
	var a := _run(21, SimHarness.default_players(), true, prof)
	var ms := Time.get_ticks_msec() - t0
	var b := _run(21, SimHarness.default_players(), true)
	SimHarness.check(a.checksums.size() == MIN15 / 30 and a.checksums == b.checksums,
		"%d контрольных сумм совпали (последняя %d)" % [a.checksums.size(), a.checksums[-1]])
	SimHarness.check(_count(a, SimEvents.Ev.RAID_STARTED) >= 3 and _count(a, SimEvents.Ev.CMD_REJECTED) > 0,
		"за 15 мин набегов %d, отказов %d, приказов исполнено %d" % [_count(a, SimEvents.Ev.RAID_STARTED),
		_count(a, SimEvents.Ev.CMD_REJECTED), a.orders.applied])
	var ai_ms := prof.acc[GameSim.Ph.AI] / 1000.0 / MIN15
	SimHarness.check(ai_ms <= 0.3, "ИИ в среднем %.4f мс/такт; вся игра %.3f мс/такт" % [ai_ms, float(ms) / MIN15])


func _test_ai_vs_ai() -> void:
	print("[15 мин: ИИ против ИИ, дважды; другое зерно]")
	var pl := [{"faction": &"kokand", "team": 0, "ctrl": PlayerTable.Ctrl.AI, "difficulty": 0},
		{"faction": &"kipchak", "team": 1, "ctrl": PlayerTable.Ctrl.AI, "difficulty": 0}]
	var a := _run(5, pl, false)
	var b := _run(5, pl, false)
	var c := _run(6, pl, false)
	SimHarness.check(a.checksums == b.checksums, "зерно 5 дважды — суммы совпали")
	SimHarness.check(a.checksums != c.checksums, "зерно 6 — суммы другие")
	SimHarness.check(_count(a, SimEvents.Ev.RAID_STARTED) >= 4, "набеги в обе стороны: %d" % _count(a, SimEvents.Ev.RAID_STARTED))
