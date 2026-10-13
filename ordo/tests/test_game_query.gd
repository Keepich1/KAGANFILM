extends SceneTree
## Окно чтения GameQueryImpl (ARCHITECTURE §7.5) и расстановка карты (MapSetup, MapValley):
##   • перекрывает все методы договора GameQuery;
##   • ставки далеко друг от друга (ТЗ 8), жилы по правилу ECONOMY §1.1, деревья — из ScatterData;
##   • база ИИ (AiDefs.BASE) и отряды защиты стоят; у игрока-человека — только старт;
##   • описатели ↔ индексы, pick (свой юнит, здание, узел), selection_info, building_panel / build_menu
##     (запасной вариант без ECON), orders_for, minimap, raid_eta_ticks.
##   godot --headless --path ordo --script res://tests/test_game_query.gd


func _init() -> void:
	_test_overrides()
	_test_map()
	_test_query()
	SimHarness.finish(self)


func _game(f0: StringName, c0: int, f1: StringName, c1: int) -> GameSim:
	var g := GameSim.new()
	g.impl = {"port": "stub", "nav": "stub", "econ": "stub"}
	g.setup(MapValley.MAP, [{"faction": f0, "team": 0, "ctrl": c0, "difficulty": 0},
		{"faction": f1, "team": 1, "ctrl": c1, "difficulty": 0}], 2)
	return g


func _test_overrides() -> void:
	print("[договор GameQuery]")
	var own := {}
	var src := (GameQueryImpl as Script).source_code
	var missing := PackedStringArray()
	for m: Dictionary in (GameQuery as Script).get_script_method_list():
		var name: String = m["name"]
		if name.begins_with("_"):
			continue
		if src.find("func %s(" % name) < 0:
			missing.append(name)
	SimHarness.check(missing.is_empty(), "GameQueryImpl перекрывает все методы GameQuery %s" % ("" if missing.is_empty() else str(missing)))
	var cp := SimHarness.make_game()
	SimHarness.check(cp is GameSim and cp.query is GameQueryImpl, "SimHarness.make_game() даёт GameSim с GameQueryImpl")


func _test_map() -> void:
	print("[карта: ставки, жилы, база ИИ]")
	var g := _game(&"kokand", PlayerTable.Ctrl.HUMAN, &"kipchak", PlayerTable.Ctrl.AI)
	var q := g.query as GameQueryImpl
	var a := AiController.hq_pos(q, 0)
	var b := AiController.hq_pos(q, 1)
	SimHarness.check(a.distance_to(b) >= 340.0, "ставки в %.0f м друг от друга (≥ 340 на карте 1 км)" % a.distance_to(b))
	var N := g.econ.nodes
	var gold := 0
	var stone := 0
	var trees := 0
	var near_gold := [0, 0]
	var near_stone := [0, 0]
	for n in N.hw:
		var nt := N.ntype[n]
		if g.defs.n_scatter_kind[nt] >= 0:
			trees += 1
			continue
		var p := Vector2(N.x[n], N.z[n])
		var is_gold := g.defs.n_ids[nt] == "gold"
		if is_gold:
			gold += 1
		else:
			stone += 1
		for k in 2:
			var d := p.distance_to(a if k == 0 else b)
			if d >= 90.0 and d <= 140.0:
				if is_gold:
					near_gold[k] += 1
				else:
					near_stone[k] += 1
	SimHarness.check(gold == 5 and stone == 5, "5 золотых и 5 каменных жил (%d / %d)" % [gold, stone])
	SimHarness.check(near_gold == [1, 1] and near_stone == [1, 1], "у каждой ставки в ~120 м — золото и камень")
	SimHarness.check(trees > 400 and trees <= ScatterData.trees().size(), "деревья карты: %d из %d" % [trees, ScatterData.trees().size()])
	var rich := false
	for n in N.hw:
		if g.defs.n_ids[N.ntype[n]] == "gold" and N.amount_milli[n] == 5000 * 1000:
			rich = absf(Vector2(N.x[n], N.z[n]).distance_to(a) - Vector2(N.x[n], N.z[n]).distance_to(b)) < 20.0
	SimHarness.check(rich, "спорное богатое золото (5000) — посередине")
	# база ИИ-кыпчаков: AiDefs.BASE
	var base: Dictionary = g.defs.ai["BASE"]["kipchak"]
	var B := g.econ.buildings
	var have := {}
	for i in B.hw:
		if B.owner[i] == 1:
			var id := g.defs.b_ids[B.btype[i]]
			have[id] = int(have.get(id, 0)) + 1
	var ok := true
	for id: String in base["buildings"]:
		ok = ok and int(have.get(id, 0)) >= int(base["buildings"][id])
	for id: String in base["towers"]:
		ok = ok and int(have.get(id, 0)) >= int(base["towers"][id])
	SimHarness.check(ok, "база ИИ-кыпчаков: %s" % str(have))
	var H := g.econ.herds
	var horses := 0
	var sheep := 0
	for h in H.hw:
		if H.owner[h] == 1:
			if g.defs.h_ids[H.htype[h]] == "horse":
				horses += H.heads(h)
			else:
				sheep += H.heads(h)
	SimHarness.check(horses == 6 + 20 and sheep == 6 * 40, "табун 6 у ставки + 20 во дворах, отары по 40 (%d коней, %d овец)" % [horses, sheep])
	var gar := 0
	for c in g.ai:
		if c is GarrisonAi:
			gar = c.squads.size()
	SimHarness.check(gar >= 2, "отряды защиты у ставки и у башен: %d" % gar)
	var mine := 0
	for i in B.hw:
		if B.owner[i] == 0:
			mine += 1
	SimHarness.check(have.size() > 3 and mine == 1 + 1 + _links(g, 0), "у человека-Коканда — урда, тўғон и Бош ариқ (%d)" % mine)
	# зеркально: ИИ-Коканд
	var g2 := _game(&"kipchak", PlayerTable.Ctrl.HUMAN, &"kokand", PlayerTable.Ctrl.AI)
	var have2 := {}
	var B2 := g2.econ.buildings
	for i in B2.hw:
		if B2.owner[i] == 1:
			var id := g2.defs.b_ids[B2.btype[i]]
			have2[id] = int(have2.get(id, 0)) + 1
	var base2: Dictionary = g2.defs.ai["BASE"]["kokand"]
	var ok2 := true
	for id: String in base2["buildings"]:
		ok2 = ok2 and int(have2.get(id, 0)) >= int(base2["buildings"][id])
	SimHarness.check(ok2 and int(have2.get("burj", 0)) == 2, "база ИИ-Коканда: %s" % str(have2))


func _links(g: GameSim, p: int) -> int:
	var k := 0
	var B := g.econ.buildings
	for i in B.hw:
		if B.owner[i] == p and g.defs.b_kind[B.btype[i]] == Defs.BKind.LINK:
			k += 1
	return k


func _test_query() -> void:
	print("[чтение]")
	var g := _game(&"kokand", PlayerTable.Ctrl.HUMAN, &"kipchak", PlayerTable.Ctrl.AI)
	var q := g.query as GameQueryImpl
	var us := q.units_of(0)
	SimHarness.check(us.size() == 6 and q.units_of(1).size() > 40, "units_of: Коканд 6, ИИ-кыпчаки %d" % q.units_of(1).size())
	var u := us[0]
	SimHarness.check(q.unit_handle(q.unit_index(u)) == u and q.unit_index(Ids.make(Ids.Kind.UNIT, Ids.slot(u), 4000)) == -1,
		"unit_handle ↔ unit_index, устаревший — −1")
	SimHarness.check(q.pick(0, q.unit_pos(u) + Vector2(0.3, 0), 2.0) == u, "pick: свой работник")
	var hq := g.econ.players.hq_b[0]
	SimHarness.check(q.pick(0, AiController.hq_pos(q, 0), 1.0) == hq, "pick: урда под курсором")
	var N := g.econ.nodes
	var dep := -1
	for n in N.hw:
		if g.defs.n_scatter_kind[N.ntype[n]] < 0:
			dep = n
			break
	SimHarness.check(q.pick(0, Vector2(N.x[dep], N.z[dep]) + Vector2(1, 1), 2.0) == N.handle(dep), "pick: жила")
	var si := q.selection_info(us)
	SimHarness.check(si["kind"] == "units" and si["cards"].size() == 1 and si["cards"][0]["count"] == 6, "selection_info: 6 деҳқонов одной карточкой")
	var bp := q.building_panel(hq)
	SimHarness.check(bp.get("name", "") == "Урда" and bp["trains"].size() >= 1 and bp["trains"][0]["utype"] == g.defs.unit(&"dehqon"),
		"building_panel урды: найм деҳқонов")
	var bm := q.build_menu(0, &"economy")
	SimHarness.check(bm.size() == (g.defs.f_tabs[g.econ.players.faction[0]]["economy"] as PackedInt32Array).size() and bm[0]["name"] == "Уй",
		"build_menu «Хозяйство»: %d построек, первая — Уй" % bm.size())
	var ops := PackedInt32Array()
	for o: Dictionary in q.orders_for(0, us):
		ops.append(o["op"])
	SimHarness.check(ops.has(SimCmd.Op.GATHER) and ops.has(SimCmd.Op.BUILD) and not ops.has(SimCmd.Op.FORMATION), "orders_for работников")
	var ops2 := PackedInt32Array()
	for o: Dictionary in q.orders_for(1, q.units_of(1)):
		ops2.append(o["op"])
	SimHarness.check(ops2.has(SimCmd.Op.ATTACK_MOVE) and ops2.has(SimCmd.Op.DISBAND), "orders_for отрядов: в атаку, распустить")
	var mm := q.minimap(0)
	SimHarness.check(mm["units"].size() == us.size() + q.units_of(1).size() and mm["nodes"].size() == 10, "minimap: все юниты, 10 жил")
	SimHarness.check(q.raid_eta_ticks(0) == int(g.defs.ai["RAID"]["peace_ticks"][0]) and q.raid_eta_ticks(1) == -1,
		"raid_eta_ticks: человеку — мирный период, ИИ — −1")
	SimHarness.check(q.field_dims() == Vector4i.ZERO, "field_dims: на заглушке полей нет")
	SimHarness.check(q.tick() == 0 and q.events() == g.events and q.defs() == g.defs, "tick / events / defs")
