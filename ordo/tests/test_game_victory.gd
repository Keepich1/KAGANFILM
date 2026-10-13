extends SceneTree
## Победа и поражение «Города» (ARCHITECTURE §3 #16, §15 GAME; ТЗ 9): поражение при потере ставки и при
## гибели арбы со свёрнутым ордо; VICTORY команде, что осталась; выбывший не приказывает.
## «Разрушение» ставки тест делает записью в таблицу (на любой реализации). Арба: на настоящей экономике —
## приказ PACK_ALL и гибель арбы с ордо (CombatPort.kill); на заглушке «сворачивает» сам тест (ArbaEcon).
## Реализации — GameSim.impl_for: по умолчанию настоящие (если они в проекте), --impl=stub или ORDO_IMPL=stub — заглушки.
##   godot --headless --path ordo --script res://tests/test_game_victory.gd [-- --impl=stub]


## Заглушка экономики, которая знает груз арб (как EconomySim.arba_cargo)
class ArbaEcon extends EconStub:
	var cargo := {}

	func arba_cargo(u_h: int) -> int:
		return int(cargo.get(u_h, 0))


var _impl := {}


func _init() -> void:
	_impl = GameSim.impl_for(OS.get_cmdline_user_args(), OS.get_environment("ORDO_IMPL"))
	var real := _real()
	_test_hq_loss()
	if real:
		_test_arba_loss_real()
	_test_arba_loss()
	SimHarness.finish(self)


## Печатает реализации; true — настоящие
func _real() -> bool:
	var g := _game(null)
	print("реализации: ", g.impl_names())
	return g.real_impl()


## econ — своя заглушка экономики (порт и навигация — тоже заглушки); null — выбранные реализации
func _game(econ: EconApi) -> GameSim:
	var g := GameSim.new()
	g.impl = {"port": "stub", "nav": "stub", "econ": econ} if econ != null else _impl.duplicate()
	g.setup(MapValley.MAP, [{"faction": &"kipchak", "team": 0, "ctrl": PlayerTable.Ctrl.HUMAN, "difficulty": 0},
		{"faction": &"kokand", "team": 1, "ctrl": PlayerTable.Ctrl.AI, "difficulty": 0}], 4)
	return g


func _events(g: GameSim, kind: int) -> Array:
	var out: Array = []
	var r := g.events.range_since(0)
	for seq in range(r.x, r.y):
		var i := g.events.at(seq)
		if g.events.e_kind[i] == kind:
			out.append([g.events.e_player[i], g.events.e_a[i], g.events.e_b[i]])
	return out


func _test_hq_loss() -> void:
	print("[потеря ставки]")
	var g := _game(null)
	SimHarness.run_s(g, 5.0)
	SimHarness.check(not g.over and _events(g, SimEvents.Ev.PLAYER_DEFEATED).is_empty(), "5 с — оба в игре")
	var B := g.econ.buildings
	var urda := g.econ.players.hq_b[1]
	B.state[B.slot(urda)] = BuildingTable.State.RUIN          # «ECON»: урда разрушена
	g.step()
	var d := _events(g, SimEvents.Ev.PLAYER_DEFEATED)
	SimHarness.check(d.size() == 1 and d[0][0] == 1 and d[0][1] == Victory.REASON_HQ and d[0][2] == 1,
		"PLAYER_DEFEATED(Коканд, причина «ставка», команда 1): %s" % str(d))
	var v := _events(g, SimEvents.Ev.VICTORY)
	SimHarness.check(v.size() == 1 and v[0][1] == 0 and g.over and g.winner == 0, "VICTORY команде 0, игра окончена")
	var c := g.events.head
	g.submit(1, SimCmd.stop(g.query.units_of(1).slice(0, 1)))
	SimHarness.run_s(g, 2.0)
	SimHarness.check(_events(g, SimEvents.Ev.VICTORY).size() == 1, "VICTORY — один раз")
	var rej := false
	var r := g.events.range_since(c)
	for seq in range(r.x, r.y):
		rej = rej or g.events.e_kind[g.events.at(seq)] == SimEvents.Ev.CMD_REJECTED
	SimHarness.check(rej, "приказ выбывшего — отказ")


## Настоящая экономика: PACK_ALL сворачивает лагерь, ордо едет в арбах (BuildingDefs: arbas 2); пока цела
## хоть одна арба с ордо — в игре; погибли все (ECON разрушает свёрнутое ордо) — поражение
func _test_arba_loss_real() -> void:
	print("[арба с ордо — настоящая экономика]")
	var g := _game(null)
	SimHarness.run_s(g, 2.0)
	var P := g.econ.players
	var ordo := P.hq_b[0]
	g.submit(0, SimCmd.pack_all(ordo))
	var arbas := PackedInt32Array()
	var t0 := g.tick
	while g.tick - t0 < 30 * 120 and arbas.is_empty():
		g.step()
		if P.hq_b[0] == Ids.NULL and g.tick % 15 == 0:
			arbas = _arbas_with(g, 0, ordo)
	SimHarness.check(not arbas.is_empty(), "PACK_ALL: ставка свёрнута, ордо в арбах: %d (%.1f с)" % [arbas.size(), (g.tick - t0) / 30.0])
	if arbas.is_empty():
		return
	SimHarness.run_s(g, 3.0)
	SimHarness.check(not g.over and _events(g, SimEvents.Ev.PLAYER_DEFEATED).is_empty(), "ставка в пути, арбы целы — в игре")
	for i in arbas.size():
		g.port.kill(arbas[i])
		SimHarness.run_s(g, 1.0)
		var d := _events(g, SimEvents.Ev.PLAYER_DEFEATED)
		if i < arbas.size() - 1:
			SimHarness.check(d.is_empty() and not g.over, "погибла арба %d из %d — ордо едет в других, в игре" % [i + 1, arbas.size()])
		else:
			SimHarness.check(d.size() == 1 and d[0][0] == 0 and d[0][1] == Victory.REASON_ARBA,
				"погибли все арбы с ордо — поражение (причина 1): %s" % str(d))
	SimHarness.check(g.over and g.winner == 1, "победа команды 1")


## Арбы игрока p, везущие постройку b_h (EconApi.arba_cargo). Только договор GameQuery: ссылка теста на
## GameQueryImpl здесь оставляет на выходе Godot «resources still in use» (цикл скриптов GameSim ↔ GameQueryImpl)
func _arbas_with(g: GameSim, p: int, b_h: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for u in g.query.units_of(p):
		var ut := g.defs.unit(g.port.type_id(u))
		if ut >= 0 and g.defs.u_flags[ut] & UnitStats.WAGON and g.econ.arba_cargo(u) == b_h:
			out.append(u)
	return out


func _test_arba_loss() -> void:
	print("[арба с ордо — заглушка экономики]")
	var econ := ArbaEcon.new()
	var g := _game(econ)
	SimHarness.run_s(g, 2.0)
	var P := g.econ.players
	var B := g.econ.buildings
	var ordo := P.hq_b[0]
	# «ECON»: свернули весь лагерь — ставка в арбе
	B.state[B.slot(ordo)] = BuildingTable.State.PACKED
	P.hq_b[0] = 0
	var arba := g.port.spawn(0, 0, &"arba", Vector2(-170, 120), 0.0)
	econ.cargo[arba] = ordo
	SimHarness.run_s(g, 10.0)
	SimHarness.check(not g.over and _events(g, SimEvents.Ev.PLAYER_DEFEATED).is_empty(), "ставка в пути, арба цела — в игре")
	g.submit(0, SimCmd.move(PackedInt32Array([arba]), Vector2(-120, 60)))
	SimHarness.run_s(g, 3.0)
	SimHarness.check(not g.over, "арба едет — в игре")
	# развернули: снова стоит
	B.state[B.slot(ordo)] = BuildingTable.State.SITE
	P.hq_b[0] = ordo
	econ.cargo.erase(arba)
	SimHarness.run_s(g, 3.0)
	SimHarness.check(not g.over, "лагерь развёрнут — в игре")
	# свернули снова, арбу убили
	B.state[B.slot(ordo)] = BuildingTable.State.PACKED
	P.hq_b[0] = 0
	econ.cargo[arba] = ordo
	SimHarness.run_s(g, 1.0)
	g.port.kill(arba)
	SimHarness.run_s(g, 1.0)
	var d := _events(g, SimEvents.Ev.PLAYER_DEFEATED)
	SimHarness.check(d.size() == 1 and d[0][0] == 0 and d[0][1] == Victory.REASON_ARBA, "арба с ордо погибла — поражение (причина 1): %s" % str(d))
	SimHarness.check(g.over and g.winner == 1, "победа команды 1")
	# свёрнуто, а арбы нет вовсе — поражение после ожидания
	var econ2 := ArbaEcon.new()
	var g2 := _game(econ2)
	SimHarness.run_s(g2, 1.0)
	var o2 := g2.econ.players.hq_b[0]
	g2.econ.buildings.state[g2.econ.buildings.slot(o2)] = BuildingTable.State.PACKED
	g2.econ.players.hq_b[0] = 0
	SimHarness.run_s(g2, 0.5)
	SimHarness.check(not g2.over, "без арбы — ждём %d тактов" % Victory.ARBA_GRACE)
	SimHarness.run_s(g2, 1.5)
	SimHarness.check(g2.over and g2.winner == 1, "ставка свёрнута, арбы нет — поражение")
