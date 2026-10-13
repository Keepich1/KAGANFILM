extends SceneTree
## Приказы «Города» (ARCHITECTURE §8, §15 GAME; CONTRACT §10.4):
##   • очередь: задержка input_delay, порядок (игрок, номер), приказы ИИ после внешних, журнал;
##   • маршрут: бой → CombatPort, хозяйство → EconApi, работники в боевом приказе уходят с работы;
##   • отказы → CMD_REJECTED с причиной: форма, устаревший и чужой описатель, не тот вид, нет ресурсов,
##     выбывший игрок, SPAWN не у ИИ, постройка чужой стороны;
##   • SPAWN у ИИ — отряд и UNIT_SPAWNED на каждого.
##   godot --headless --path ordo --script res://tests/test_orders.gd

const Err := EconApi.Err


## Заглушка экономики, у которой все работники свободны (для BUILD без работников)
class IdleEcon extends EconStub:
	func idle_workers(p: int) -> PackedInt32Array:
		var out := PackedInt32Array()
		var buf := PackedInt32Array()
		port.units_near(players.team[p], Vector2.ZERO, 1.0e6, false, UnitStats.WORKER, buf)
		for u in buf:
			if port.owner(u) == p:
				out.append(u)
		return out


func _init() -> void:
	_test_queue()
	_test_routing()
	_test_rejects()
	_test_spawn()
	SimHarness.finish(self)


func _game(econ: EconApi = null) -> GameSim:
	var g := GameSim.new()
	g.impl = {"port": "stub", "nav": "stub", "econ": econ if econ != null else "stub"}
	g.setup(MapValley.MAP, SimHarness.default_players(), 3)
	return g


func _test_queue() -> void:
	print("[очередь приказов]")
	var q := CommandQueue.new()
	q.input_delay = 2
	q.push(1, 10, SimCmd.stop(PackedInt32Array([Ids.make(Ids.Kind.UNIT, 1, 1)])))
	q.push(0, 10, SimCmd.stop(PackedInt32Array([Ids.make(Ids.Kind.UNIT, 2, 1)])), true)
	q.push(0, 10, SimCmd.stop(PackedInt32Array([Ids.make(Ids.Kind.UNIT, 3, 1)])))
	q.push(0, 11, SimCmd.stop(PackedInt32Array([Ids.make(Ids.Kind.UNIT, 4, 1)])))
	SimHarness.check(q.take(11).is_empty(), "до такта исполнения приказов нет (задержка 2)")
	var a := q.take(12)
	SimHarness.check(a.size() == 3, "такт 12: три приказа")
	var order := PackedInt32Array()
	for c in a:
		order.append(SimCmd.ids(c)[0] & 0xFFFF)
	SimHarness.check(order == PackedInt32Array([3, 2, 1]), "порядок: игрок 0 (внешний, затем ИИ), игрок 1 — %s" % str(order))
	SimHarness.check(a[0][SimCmd.H_TICK] == 12 and a[0][SimCmd.H_PLAYER] == 0 and a[0][SimCmd.H_SEQ] == 0,
		"проставлены игрок, такт, номер")
	SimHarness.check(a[1][SimCmd.H_SEQ] >= CommandQueue.AI_SEQ, "номер приказа ИИ — с AI_SEQ")
	SimHarness.check(q.take(13).size() == 1 and q.log.size() == 4, "такт 13: последний; журнал — 4")
	SimHarness.check(q.external_log().size() == 3, "в журнал повтора — только внешние (3)")


func _test_routing() -> void:
	print("[маршрут приказов]")
	var g := _game(IdleEcon.new())
	var econ := g.econ as EconStub
	var port := g.port as CombatPortStub
	var w := _workers(g, 0)
	SimHarness.check(w.size() == 6, "у Коканда 6 стартовых деҳқонов")
	var to := Vector2(150, 40)
	g.submit(0, SimCmd.move(w.slice(0, 2), to))
	g.step()
	SimHarness.check(g.orders.applied == 1 and not port.is_idle(w[0]), "MOVE применён на следующем такте, юнит идёт")
	SimHarness.check(_called(econ, "release_units") == 1, "работники в MOVE уходят с работы (release_units)")
	SimHarness.run_s(g, 30.0)
	SimHarness.check(port.pos(w[0]).distance_to(to) < 3.0, "работник дошёл (%.1f м)" % port.pos(w[0]).distance_to(to))
	var tree := _nearest_node(g, port.pos(w[2]))
	g.submit(0, SimCmd.gather(w.slice(2, 4), tree))
	var urda := g.econ.players.hq_b[0]
	g.submit(0, SimCmd.train(urda, g.defs.unit(&"dehqon"), 2))
	g.submit(0, SimCmd.rally(urda, Vector2(170, 70)))
	g.step()
	SimHarness.check(_called(econ, "assign_gather") == 1 and _called(econ, "train") == 1 and _called(econ, "set_rally") == 1,
		"GATHER, TRAIN, RALLY → EconApi")
	var n0 := g.econ.buildings.hw
	g.submit(0, SimCmd.build(PackedInt32Array(), g.defs.building(&"uy"), Vector2(210, 110), 0))
	g.step()
	var last: Array = econ.calls[econ.calls.size() - 1]
	var ws: PackedInt32Array = last[5]
	var nearest := _nearest_of(g, w, Vector2(210, 110))
	SimHarness.check(last[0] == "place_site" and ws.size() == 1 and ws[0] == nearest and g.econ.buildings.hw == n0 + 1,
		"BUILD без работников — ближайший свободный, стройка поставлена")
	SimHarness.check(_events_of(g, SimEvents.Ev.SITE_PLACED) == 1, "событие SITE_PLACED")
	g.submit(0, SimCmd.stance(w.slice(0, 1), BattleSim.Stance.HOLD))
	g.submit(0, SimCmd.hold(w.slice(1, 2), 0.5))
	g.step()
	var s := Ids.slot(port.squad_of(w[0]))
	SimHarness.check(port.sq_stance[s] == BattleSim.Stance.HOLD, "STANCE → CombatPort.set_stance")


func _test_rejects() -> void:
	print("[отказы → CMD_REJECTED]")
	var g := _game()
	var w0 := _workers(g, 0)
	var w1 := _workers(g, 1)
	var cases := [
		["испорченная форма", PackedInt32Array([SimCmd.Op.MOVE, 0, 0, 0, 1]), Err.INVALID],
		["устаревший описатель", SimCmd.stop(PackedInt32Array([Ids.make(Ids.Kind.UNIT, Ids.slot(w0[0]), 4000)])), Err.STALE],
		["чужой юнит", SimCmd.move(w1.slice(0, 1), Vector2.ZERO), Err.NOT_OWNER],
		["не тот вид (юнит в TRAIN)", SimCmd.train(w0[0], 0, 1), Err.INVALID],
		["постройка чужой стороны", SimCmd.build(w0.slice(0, 1), g.defs.building(&"boz"), Vector2(200, 120), 0), Err.NOT_ALLOWED],
		["постройка Сб. 2 (enabled false)", SimCmd.build(w0.slice(0, 1), g.defs.building(&"temirchixona"), Vector2(200, 120), 0), Err.NOT_ALLOWED],
		["SPAWN у человека", SimCmd.spawn(g.defs.unit(&"navkar"), 5, Vector2(150, 40), 0.0), Err.NOT_ALLOWED],
		["атака своего", SimCmd.attack(w0.slice(0, 1), w0[1]), Err.NOT_ALLOWED],
		["GATHER не работником", SimCmd.gather(_soldiers(g, 1).slice(0, 1), _nearest_node(g, Vector2(-170, 110))),
			Err.NOT_ALLOWED, 1],
		["ATTACK по несуществующему зданию", SimCmd.attack(w0.slice(0, 1), Ids.make(Ids.Kind.BUILDING, 999, 1)), Err.STALE],
	]
	for c: Array in cases:
		var before := g.orders.rejected
		var cursor := g.events.head
		g.submit(c[3] if c.size() > 3 else 0, c[1])
		g.step()
		var got := _reject_reason(g, cursor)
		SimHarness.check(g.orders.rejected == before + 1 and got == c[2], "%s → причина %d (ждали %d)" % [c[0], got, c[2]])
	# нет ресурсов: Казарма 200 дерева + 100 камня, стартовых 400 / 250 — третья и четвёртая не по карману
	var cursor2 := g.events.head
	var bz := g.defs.building(&"kazarma")
	for i in 4:
		g.submit(0, SimCmd.build(w0.slice(i, i + 1), bz, Vector2(120, 150 + i * 30), 0))
	g.step()
	var reasons := _reject_reasons(g, cursor2)
	SimHarness.check(reasons.has(Err.NO_RES), "четвёртая Казарма — нет ресурсов (NO_RES) %s" % str(reasons))
	# выбывший игрок
	g.victory.defeated[0] = 1
	var cursor3 := g.events.head
	g.submit(0, SimCmd.stop(w0.slice(0, 1)))
	g.step()
	SimHarness.check(_reject_reason(g, cursor3) == Err.NOT_ALLOWED, "выбывший игрок — отказ")


func _test_spawn() -> void:
	print("[SPAWN у ИИ]")
	var g := _game()
	var cursor := g.events.head
	var u := g.defs.unit(&"chabuulchu")
	var cmd := SimCmd.spawn(u, 10, Vector2(-300, 40), PI * 0.5, g.defs.unit(&"juz_bashy"))
	g.submit(1, cmd)
	g.step()
	var spawned := 0
	var r := g.events.range_since(cursor)
	for seq in range(r.x, r.y):
		var i := g.events.at(seq)
		if g.events.e_kind[i] == SimEvents.Ev.UNIT_SPAWNED and g.events.e_player[i] == 1 and g.events.e_b[i] == Ids.NULL:
			spawned += 1
	SimHarness.check(spawned == 11, "10 чабуулов + жүз башы, UNIT_SPAWNED на каждого (%d)" % spawned)
	var big := SimCmd.spawn(u, 2000, Vector2(-300, 40), 0.0)
	var c2 := g.events.head
	g.submit(1, big)
	g.step()
	SimHarness.check(_reject_reason(g, c2) == Err.INVALID, "SPAWN больше MAX_IDS — отказ")


# ---------------------------------------------------------------- помощники

func _workers(g: GameSim, p: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var q := g.query as GameQueryImpl
	for u in q.units_of(p):
		if q.unit_flags(u) & UnitStats.WORKER:
			out.append(u)
	return out


func _soldiers(g: GameSim, p: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var q := g.query as GameQueryImpl
	for u in q.units_of(p):
		if q.unit_flags(u) & (UnitStats.WORKER | UnitStats.WAGON) == 0:
			out.append(u)
	return out


func _nearest_node(g: GameSim, at: Vector2) -> int:
	var N := g.econ.nodes
	var best := 0
	var bd := INF
	for n in N.hw:
		if N.ntype[n] >= 0:
			var d := Vector2(N.x[n], N.z[n]).distance_squared_to(at)
			if d < bd:
				bd = d
				best = N.handle(n)
	return best


func _nearest_of(g: GameSim, hs: PackedInt32Array, at: Vector2) -> int:
	var best := 0
	var bd := INF
	for h in hs:
		var d := g.port.pos(h).distance_squared_to(at)
		if d < bd:
			bd = d
			best = h
	return best


## Сколько раз ECON звали с этим именем (p ≥ 0 — только для игрока p)
func _called(econ: EconStub, name: String, p := 0) -> int:
	var k := 0
	for c: Array in econ.calls:
		if c[0] == name and (p < 0 or c.size() < 2 or not (c[1] is int) or c[1] == p):
			k += 1
	return k


func _events_of(g: GameSim, kind: int) -> int:
	var k := 0
	var r := g.events.range_since(0)
	for seq in range(r.x, r.y):
		if g.events.e_kind[g.events.at(seq)] == kind:
			k += 1
	return k


func _reject_reason(g: GameSim, cursor: int) -> int:
	var rs := _reject_reasons(g, cursor)
	return rs[0] if not rs.is_empty() else -1


func _reject_reasons(g: GameSim, cursor: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r := g.events.range_since(cursor)
	for seq in range(r.x, r.y):
		var i := g.events.at(seq)
		if g.events.e_kind[i] == SimEvents.Ev.CMD_REJECTED:
			out.append(g.events.e_b[i])
	return out
