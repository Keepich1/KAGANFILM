extends SceneTree
## Победа и поражение «Города» (ARCHITECTURE §3 #16, §15 GAME; ТЗ 9): поражение при потере ставки и при
## гибели арбы со свёрнутым ордо; VICTORY команде, что осталась; выбывший не приказывает.
## На заглушках: «разрушение» и «сворачивание» здесь делает тест, записывая таблицы вместо ECON.
##   godot --headless --path ordo --script res://tests/test_game_victory.gd


## Заглушка экономики, которая знает груз арб (как EconomySim.arba_cargo)
class ArbaEcon extends EconStub:
	var cargo := {}

	func arba_cargo(u_h: int) -> int:
		return int(cargo.get(u_h, 0))


func _init() -> void:
	_test_hq_loss()
	_test_arba_loss()
	SimHarness.finish(self)


func _game(econ: EconApi) -> GameSim:
	var g := GameSim.new()
	g.impl = {"port": "stub", "nav": "stub", "econ": econ}
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
	var g := _game(EconStub.new())
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


func _test_arba_loss() -> void:
	print("[арба с ордо]")
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
