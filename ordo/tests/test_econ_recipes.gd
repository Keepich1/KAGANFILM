extends SceneTree
## Хумдон и ғишт (ARCHITECTURE §15 ECON; ECONOMY §2.4; T3): godot --headless --path ordo --script res://tests/test_econ_recipes.gd
## 3 работника × 60 с — +36 ғишт, −18 дерева; без дров — стоит («нет дров»); без воды — 50%; только в зоне воды.

const KOK := Vector2(90, 0)


func _init() -> void:
	var k := EconKit.make()
	var p := k.kokand(KOK, 3)
	var e := k.econ
	var stub := k.port as CombatPortStub
	SimHarness.check(e.place_why(p, k.b(&"xumdon"), Vector2(60, 40), 0) == 100 + NavApi.Why.NOT_NEAR, "Хумдон вне зоны воды — нельзя")
	SimHarness.check(e.ghost_why(p, k.b(&"xumdon"), Vector2(60, 40), 0) == NavApi.Why.NOT_NEAR, "призрак Хумдона вне воды — NOT_NEAR")
	var dam := k.build_now(p, &"togon", Vector2(90, -100))
	e.place_wall(p, k.b(&"aryk"), PackedVector2Array([Vector2(90, -94), Vector2(90, 30)]), PackedInt32Array())
	for b in e.buildings.hw:
		if e.buildings.state[b] == BuildingTable.State.SITE:
			e._sites.erase(b)
			e._activate(b, true)
	k.step()
	SimHarness.check(e.place_why(p, k.b(&"xumdon"), Vector2(112, -40), 0) == 0, "в зоне воды — можно")
	var kiln := k.build_now(p, &"xumdon", Vector2(112, -40))
	k.step()
	var kb := e.buildings.slot(kiln)
	SimHarness.check(e.b_water[kb] == 1000 and e.net.used[e.buildings.slot(dam)] == 1, "печь заняла место воды")
	SimHarness.check(e.assign_gather(p, k.workers_of(p), kiln) == EconApi.Err.OK, "трое — к печи")
	while e.buildings.workers_n[kb] < 3 and k.tick < 3000:
		k.step()
	# выровнять на секунду и мерить ровно 60 с
	while k.tick % 30 != 1:
		k.step()
	var b0 := k.res(p, "brick")
	var w0 := k.res(p, "wood")
	k.run_s(60.0)
	print("  за минуту: ғишт +%.0f, дерево %.0f" % [k.res(p, "brick") - b0, k.res(p, "wood") - w0])
	SimHarness.check_range(k.res(p, "brick") - b0, 34.0, 38.0, "3 работника: 36 ғишт в минуту")
	SimHarness.check_range(w0 - k.res(p, "wood"), 17.0, 19.0, "и 18 дерева в минуту")
	var panel := e.building_panel(kiln)
	SimHarness.check(panel["workers"]["n"] == 3 and panel["workers"]["max"] == 3 and panel["fuel"] == true, "панель печи: 3/3, дрова есть")
	# без дров
	k.set_res(p, "wood", 0.0)
	var c0 := k.events.head
	var b1 := k.res(p, "brick")
	k.run_s(20.0)
	SimHarness.check(k.res(p, "brick") == b1 and e.building_panel(kiln)["fuel"] == false, "нет дров — печь стоит («нет дров»)")
	SimHarness.check(k.count_ev(SimEvents.Ev.NOT_ENOUGH, c0) == 1, "записка один раз (NOT_ENOUGH)")
	k.set_res(p, "wood", 500.0)
	k.run_s(10.0)
	SimHarness.check(k.res(p, "brick") > b1, "дрова есть — снова жжёт")
	# без воды — 50%
	stub.test_hit_structure(dam, 1_000_000, 0)
	k.run_s(21.0)
	SimHarness.check(e.b_water[kb] == 0, "тўғон сломан, сеть высохла")
	while k.tick % 30 != 1:
		k.step()
	b1 = k.res(p, "brick")
	k.run_s(60.0)
	SimHarness.check_range(k.res(p, "brick") - b1, 16.0, 20.0, "без воды — 18 ғишт в минуту (50%)")
	SimHarness.finish(self)
