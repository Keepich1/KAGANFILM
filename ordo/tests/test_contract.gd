extends SceneTree
## Проверка договора M0 (ARCHITECTURE §19.0): все классы scripts/contract/* создаются,
## заглушки перекрывают каждый метод своего договора, простые инварианты работают,
## FakeCity живёт 300 тактов без ошибок.
##   godot --headless --path ordo --script res://tests/test_contract.gd


func _init() -> void:
	_test_classes()
	_test_ids()
	_test_cmd()
	_test_events()
	_test_tables()
	_test_port_stub()
	_test_nav_stub()
	_test_econ_stub()
	_test_scatter()
	_test_fonts()
	_test_fake_city()
	SimHarness.finish(self)


## Все классы создаются; заглушки перекрывают все методы договора (иначе push_error в работе)
func _test_classes() -> void:
	print("[классы договора]")
	var objs := [SimEvents.new(), Defs.build(), CombatPort.new(), CombatPortStub.new(), NavApi.new(), PathResult.new(),
		NavStub.new(), EconApi.new(), EconStub.new(), PlayerTable.new(), BuildingTable.new(), NodeTable.new(),
		HerdTable.new(), GameQuery.new(), FakeCity.new(), SelectionModel.new(), ScatterData.new(), SimHarness.new()]
	var ok := true
	for o: Object in objs:
		ok = ok and o != null
	SimHarness.check(ok, "создаются %d классов (+ Ids, SimCmd — статические)" % objs.size())
	for pair in [[CombatPort, CombatPortStub], [NavApi, NavStub], [EconApi, EconStub], [GameQuery, FakeCity]]:
		var missing := _missing_overrides(pair[0], pair[1])
		SimHarness.check(missing.is_empty(), "%s перекрывает все методы %s %s" % [
			pair[1].get_global_name(), pair[0].get_global_name(), "" if missing.is_empty() else str(missing)])


func _missing_overrides(base: Script, sub: Script) -> PackedStringArray:
	var own := {}
	for m: Dictionary in sub.get_script_method_list():
		own[m["name"]] = true
	# get_script_method_list включает унаследованные — сверяем по исходнику подкласса
	var src := sub.source_code
	var out := PackedStringArray()
	var allow_shared := ["cell_of", "cell_center", "footprint", "snap_center"]   # NavApi: общая геометрия клеток
	for m: Dictionary in base.get_script_method_list():
		var name: String = m["name"]
		if name.begins_with("_") or name in allow_shared or not own.has(name):
			continue
		if src.find("\nfunc %s(" % name) < 0 and src.find("\nstatic func %s(" % name) < 0:
			out.append(name)
	return out


func _test_ids() -> void:
	print("[Ids]")
	var h := Ids.make(Ids.Kind.BUILDING, 1234, 77)
	SimHarness.check(Ids.kind(h) == Ids.Kind.BUILDING and Ids.slot(h) == 1234 and Ids.gen(h) == 77, "make → kind/slot/gen")
	var top := Ids.make(Ids.Kind.HERD, 0xFFFF, 0xFFF)
	SimHarness.check(top > 0 and top < 0x7FFFFFFF and PackedInt32Array([top])[0] == top, "описатель влезает в int32")
	SimHarness.check(Ids.next_gen(0xFFF) == 1 and Ids.next_gen(1) == 2 and Ids.make(Ids.Kind.UNIT, 0, 1) != Ids.NULL,
		"поколение 1..4095 по кругу, живой ≠ 0")


func _test_cmd() -> void:
	print("[SimCmd]")
	var ids := PackedInt32Array([Ids.make(Ids.Kind.UNIT, 3, 1), Ids.make(Ids.Kind.UNIT, 4, 2)])
	var b := Ids.make(Ids.Kind.BUILDING, 5, 1)
	var cmds: Array[PackedInt32Array] = [
		SimCmd.move(ids, Vector2(10.5, -3.25), true, 1.5, true), SimCmd.move_line(ids, Vector2(1, 2), Vector2(3, 4)),
		SimCmd.attack(ids, b), SimCmd.attack_move(ids, Vector2(5, 5)), SimCmd.stop(ids), SimCmd.hold(ids),
		SimCmd.stance(ids, 2), SimCmd.gait(ids, 1), SimCmd.formation(ids, 3), SimCmd.fire_mode(ids, SimCmd.FIRE_MELEE),
		SimCmd.kachyp(ids, true), SimCmd.war_cry(ids[0]), SimCmd.form_squad(ids[0], ids), SimCmd.disband(Ids.make(Ids.Kind.SQUAD, 1, 1)),
		SimCmd.garrison(ids, b), SimCmd.ungarrison(b), SimCmd.gather(ids, Ids.make(Ids.Kind.NODE, 9, 1)),
		SimCmd.build(ids, 3, Vector2(100, 50), 1), SimCmd.build(PackedInt32Array(), 3, Vector2(100, 50), 0),
		SimCmd.build_wall(ids, 7, PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])),
		SimCmd.assist(ids, b), SimCmd.demolish(b), SimCmd.train(b, 2, 3), SimCmd.cancel_train(b, 0),
		SimCmd.rally(b, Vector2(1, 1)), SimCmd.set_recipe(b, 0), SimCmd.trade(b, 0, 3, 5000), SimCmd.set_dam(b, false),
		SimCmd.pack(b), SimCmd.pack_all(b), SimCmd.unpack(ids, Vector2(0, 0)), SimCmd.herd_move(Ids.make(Ids.Kind.HERD, 0, 1), Vector2(3, 3)),
		SimCmd.spawn(4, 20, Vector2(300, 0), PI, 2)]
	var all_ok := true
	var ops := {}
	for c in cmds:
		ops[c[SimCmd.H_OP]] = true
		if not SimCmd.validate_shape(c):
			all_ok = false
			print("    плохая форма: ", SimCmd.name_of(c[0]), " ", c)
	SimHarness.check(all_ok and ops.size() == SimCmd.Op.size() - 1, "все %d конструкторов дают верную форму" % (SimCmd.Op.size() - 1))
	var m := cmds[0]
	SimHarness.check(SimCmd.ids(m) == ids and SimCmd.arg_pos(m, 0).is_equal_approx(Vector2(10.5, -3.25))
		and is_equal_approx(SimCmd.arg_angle(m, 3), 1.5) and SimCmd.arg(m, 4) == 1, "MOVE: ids, позиция, курс, очередь")
	SimHarness.check(is_nan(SimCmd.arg_angle(cmds[5], 0)) and SimCmd.mrad(NAN) == SimCmd.NO_ANGLE, "NAN ↔ NO_ANGLE")
	SimHarness.check(SimCmd.wall_points(cmds[19]).size() == 3, "точки стены")
	var back := SimCmd.decode(SimCmd.encode(cmds))
	var same := back.size() == cmds.size()
	for i in mini(back.size(), cmds.size()):
		same = same and back[i] == cmds[i]
	SimHarness.check(same, "encode → decode без потерь")
	var bytes := SimCmd.encode(cmds)
	SimHarness.check(SimCmd.decode(bytes.slice(0, bytes.size() - 4)).is_empty(), "обрезанные байты → пустой список")
	var bad: Array[PackedInt32Array] = [PackedInt32Array([SimCmd.Op.MOVE]), PackedInt32Array([99, 0, 0, 0, 0]),
		SimCmd.stop(PackedInt32Array()), SimCmd.war_cry(0), SimCmd.move(ids, Vector2.ZERO).slice(0, 8),
		SimCmd.train(b, 2, 0), SimCmd.trade(b, 1, 1, 10), SimCmd.stance(ids, 9)]
	var none_ok := true
	for c in bad:
		none_ok = none_ok and not SimCmd.validate_shape(c)
	SimHarness.check(none_ok, "испорченные приказы отвергаются (%d случаев)" % bad.size())


func _test_events() -> void:
	print("[SimEvents]")
	var ev := SimEvents.new()
	ev.tick = 5
	ev.push(SimEvents.Ev.LOOT, 1, 3, 4000, 77, Vector2(1, 2))
	var r := ev.range_since(0)
	var i := ev.at(r.x)
	SimHarness.check(r == Vector2i(0, 1) and ev.e_kind[i] == SimEvents.Ev.LOOT and ev.e_b[i] == 4000 and ev.e_tick[i] == 5,
		"событие читается по курсору")
	for k in SimEvents.CAP + 10:
		ev.push(SimEvents.Ev.TRAINED, 0, k)
	r = ev.range_since(1)
	SimHarness.check(r.y == SimEvents.CAP + 11 and r.x == r.y - SimEvents.CAP and ev.e_a[ev.at(r.y - 1)] == SimEvents.CAP + 9,
		"кольцо: отставший читатель теряет самые старые, новые на месте")


func _test_tables() -> void:
	print("[таблицы]")
	var bt := BuildingTable.new()
	var b0 := bt.alloc()
	var h0 := bt.handle(b0)
	var b1 := bt.alloc(BuildingTable.State.ACTIVE)
	SimHarness.check(bt.hw == 2 and bt.valid(h0) and bt.q.size() == 2 * BuildingTable.QMAX and bt.q[0] == -1, "alloc растит все массивы")
	bt.release(b0)
	var b2 := bt.alloc()
	SimHarness.check(b2 == b0 and not bt.valid(h0) and bt.valid(bt.handle(b2)) and bt.valid(bt.handle(b1)),
		"освобождённый слот снова в деле с новым поколением")
	var nt := NodeTable.new()
	var n := nt.alloc(2)
	var ht := HerdTable.new()
	var hh := ht.alloc()
	SimHarness.check(nt.valid(nt.handle(n)) and not nt.valid(bt.handle(b1)) and ht.valid(ht.handle(hh)), "узлы и стада: валидность по виду")
	var pt := PlayerTable.new()
	var p := pt.add(1, 0, PlayerTable.Ctrl.AI, 9)
	SimHarness.check(pt.count == 1 and pt.res.size() == 9 and pt.stat.size() == PlayerTable.Stat.COUNT and pt.stat[0] == 1.0
		and p == 0, "игрок: ресурсы R, множители 1.0")


func _test_port_stub() -> void:
	print("[CombatPortStub]")
	var parts := SimHarness.make_stubs()
	var port: CombatPortStub = parts["port"]
	var spot := SimHarness.flat_spot()
	var w := port.spawn(0, 0, &"dehqon", spot, 0.0)
	var s := port.spawn_squad(1, 1, &"jooker", 20, spot + Vector2(40, 0), PI, &"juz_bashy")
	SimHarness.check(port.valid(w) and port.members(port.squad_of(w)) == PackedInt32Array([w]) and port.members(s).size() == 21,
		"одиночка — отряд из одного; отряд 20 + офицер")
	port.move(PackedInt32Array([w]), spot + Vector2(10, 0))
	var arrived := false
	for k in 150:
		port.step()
		if port.take_arrivals().has(port.squad_of(w)):
			arrived = true
			break
	SimHarness.check(arrived and port.pos(w).distance_to(spot + Vector2(10, 0)) < 0.01, "дошёл шагом и сообщил о прибытии")
	var near := PackedInt32Array()
	SimHarness.check(port.units_near(0, spot, 60.0, true, 0, near) == 21 and port.enemy_near(0, spot, 60.0), "враги рядом")
	port.set_work(w, AnimSpec.WORK_CHOP)
	var victim := port.members(s)[0]
	port.kill(victim)
	var deaths := port.take_deaths()
	port.step()
	SimHarness.check(deaths == PackedInt32Array([victim, 0]) and not port.valid(victim) and port.members(s).size() == 20,
		"kill → смерть в буфере, слот свободен на следующем такте")
	var singles := port.disband(s)
	SimHarness.check(singles.size() == 20 and not port.valid(s), "распустить — 20 одиночек")
	var off := singles[singles.size() - 1]
	var s2 := port.form_squad(off, singles.slice(0, 10))
	SimHarness.check(port.members(s2).size() == 11, "собрать отряд из офицера и 10 бойцов")
	var save := {}
	port.save_into(save)
	var cs := port.checksum()
	var copy := CombatPortStub.new()
	copy.load_from(save)
	SimHarness.check(copy.checksum() == cs and copy.valid(w), "сохранение и загрузка")


func _test_nav_stub() -> void:
	print("[NavStub]")
	var parts := SimHarness.make_stubs()
	var nav: NavStub = parts["nav"]
	var defs: Defs = parts["defs"]
	var urda := defs.building(&"urda")
	var c := nav.snap(urda, Vector2(185, 57), 0)
	var r := nav.stamp_building(Ids.make(Ids.Kind.BUILDING, 0, 1), 0, c, urda, 0)
	SimHarness.check(nav.w == 256 and r.size == Vector2i(5, 5) and nav.cell_center(nav.cell_of(c)).is_equal_approx(c),
		"сетка 256², урда 5×5 клеток, нечётный след — центр клетки")
	var uy := defs.building(&"uy")
	var cu := nav.snap(uy, Vector2(203.3, 31.1), 0)
	SimHarness.check(is_equal_approx(fposmod(cu.x - nav.origin.x, NavApi.CELL), 0.0), "чётный след — угол клетки")
	SimHarness.check(nav.check_place(0, uy, c, 0) == NavApi.Why.OVERLAP and nav.check_place(0, uy, cu + Vector2(40, 0), 0) == NavApi.Why.OK
		and nav.check_place(0, uy, Vector2(600, 0), 0) == NavApi.Why.OUT_OF_MAP, "расстановка: пересечение, свободно, вне карты")
	var dv := defs.building(&"devor")
	var plan := nav.plan_wall(0, dv, PackedVector2Array([Vector2(0, 0), Vector2(32, 0)]))
	SimHarness.check(plan["centers"].size() == 10 and plan["cost"][defs.res(&"wood")] == 30000, "стена 32 м — 10 звеньев по 3,2 м, 30 дерева")
	var t := nav.request(0, Vector2.ZERO, Vector2(50, 0), 1)
	var before := nav.result(t)
	nav.service(1)
	var pr := nav.result(t)
	SimHarness.check(before == null and pr != null and pr.pts == PackedVector2Array([Vector2(50, 0)]), "путь готов после service()")


func _test_econ_stub() -> void:
	print("[EconStub]")
	var parts := SimHarness.make_stubs()
	var econ: EconStub = parts["econ"]
	var defs: Defs = parts["defs"]
	var p := econ.add_player(0, &"kokand", PlayerTable.Ctrl.HUMAN)
	SimHarness.check(econ.res(p, defs.res(&"wood")) == 400000, "стартовые ресурсы Коканда")
	var hq := econ.spawn_building(p, defs.building(&"urda"), Vector2(184, 56), 3)
	SimHarness.check(econ.players.hq_b[p] == hq and econ.players.pop_cap[p] == 25, "ставка: hq_b и +25 населения")
	var site := econ.place_site(p, defs.building(&"uy"), Vector2(220, 40), 0, PackedInt32Array())
	SimHarness.check(site > 0 and econ.buildings.state[econ.buildings.slot(site)] == BuildingTable.State.SITE
		and econ.res(p, defs.res(&"wood")) == 320000, "стройка дома: описатель, SITE, −80 дерева")
	SimHarness.check(econ.place_site(p, defs.building(&"uy"), Vector2(220, 40), 0, PackedInt32Array()) == -(100 + NavApi.Why.OVERLAP),
		"занятое место → −(100 + OVERLAP)")
	var n := econ.spawn_node(defs.node(&"stone"), Vector2(260, -60))
	SimHarness.check(econ.node_near(1 << defs.res(&"stone"), Vector2(250, -50), 30.0) == n, "ближайшая залежь камня")
	SimHarness.check(econ.train(p, hq, defs.unit(&"dehqon"), 1) == EconApi.Err.OK and econ.calls.size() >= 2, "приказы записываются")


func _test_scatter() -> void:
	print("[ScatterData]")
	var trees := ScatterData.trees()
	var ok: bool = not trees.is_empty() and trees[0][0] == 0 and trees[0][1] == 0
	var kinds_ordered := true
	for i in range(1, trees.size()):
		kinds_ordered = kinds_ordered and (trees[i][0] > trees[i - 1][0] or (trees[i][0] == trees[i - 1][0] and trees[i][1] == trees[i - 1][1] + 1))
	SimHarness.check(ok and kinds_ordered, "деревья в порядке файла: %d" % trees.size())
	SimHarness.check(ScatterData.ref_kind(ScatterData.ref(3, 2)) == 3 and ScatterData.ref_index(ScatterData.ref(3, 2)) == 2, "scatter_ref туда и обратно")


## Шрифты интерфейса (ТЗ 12): Cormorant Unicase и Alegreya с кириллицей, включая ү ө ң қ ҳ ў ғ
func _test_fonts() -> void:
	print("[шрифты]")
	var letters := "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюяҮүӨөҢңҚқҲҳЎўҒғ"
	for path in ["res://assets/ui/fonts/cormorant_unicase/CormorantUnicase-Regular.ttf",
			"res://assets/ui/fonts/cormorant_unicase/CormorantUnicase-Bold.ttf",
			"res://assets/ui/fonts/alegreya/Alegreya-VariableFont_wght.ttf",
			"res://assets/ui/fonts/alegreya/Alegreya-Italic-VariableFont_wght.ttf"]:
		var f := load(path) as FontFile
		var missing := ""
		if f != null:
			for i in letters.length():
				if not f.has_char(letters.unicode_at(i)):
					missing += letters[i]
		SimHarness.check(f != null and missing == "", "%s: кириллица %s" % [path.get_file(), "полная" if missing == "" else "нет " + missing])
	SimHarness.check(FileAccess.file_exists("res://assets/ui/fonts/cormorant_unicase/OFL.txt")
		and FileAccess.file_exists("res://assets/ui/fonts/alegreya/OFL.txt"), "лицензии OFL рядом со шрифтами")


func _test_fake_city() -> void:
	print("[FakeCity]")
	var city := FakeCity.new()
	city.setup(1)
	var sim := city.battle()
	var singles := 0
	for s in sim.squads:
		singles += sim.sq_single[s]
	SimHarness.check(singles >= 40 and sim.squads >= singles + 3, "40 одиночек и отряды (одиночек %d, отрядов %d)" % [singles, sim.squads - singles])
	var cursor := 0
	var kinds := {}
	var max_work := 0
	var states := {}
	for t in 300:
		city.step()
		var working := 0
		for u in sim.n:
			if sim.u_life[u] == BattleSim.Life.ALIVE and sim.u_act[u] == FakeCity.ACT_WORK:
				working += 1
		max_work = maxi(max_work, working)
		var r := city.events().range_since(cursor)
		for seq in range(r.x, r.y):
			kinds[SimEvents.name_of(city.events().e_kind[city.events().at(seq)])] = true
		cursor = r.y
	var bt := city.buildings()
	var waters := {}
	var dala := city.defs().building(&"dala")
	for b in bt.hw:
		states[bt.state[b]] = true
		if bt.btype[b] == dala:
			waters[city.building_panel(bt.handle(b))["water"]] = true
	SimHarness.check(waters.has(1.0) and waters.has(0.0), "поля у арыка и «лалми»: полив 1 и 0")
	SimHarness.check(city.tick() == 300 and sim.steps == 300, "300 тактов")
	SimHarness.check(max_work >= 10, "работают (u_act = WORK) до %d юнитов" % max_work)
	SimHarness.check(states.has(BuildingTable.State.SITE) and states.has(BuildingTable.State.ACTIVE) and states.has(BuildingTable.State.RUIN),
		"постройки: стройки, готовые, руины")
	SimHarness.check(kinds.has("RAID_WARNING") and kinds.has("RES_DELIVERED"), "события: %s" % str(kinds.keys()))
	SimHarness.check(city.nodes().hw > 400 and city.herds().hw == 2, "деревья и залежи (%d), два стада" % city.nodes().hw)
	var own := city.units_of(0)
	var info := city.selection_info(own)
	SimHarness.check(own.size() > 30 and info["kind"] == "units" and not info["cards"].is_empty(), "выделение своих: карточки")
	var hq := city.players().hq_b[0]
	var panel := city.building_panel(hq)
	SimHarness.check(panel.get("name", "") == "Урда" and not panel["trains"].is_empty(), "панель урды: найм деҳқонов")
	var menu := city.build_menu(0, &"economy")
	SimHarness.check(menu.size() >= 7 and menu[0]["hotkey"] == "Q", "меню «Хозяйство» Коканда")
	SimHarness.check(not city.orders_for(0, own).is_empty() and not city.orders_for(0, PackedInt32Array([hq])).is_empty(), "сетка приказов")
	SimHarness.check(city.pick(0, Vector2(sim.u_x[city.unit_index(own[0])], sim.u_z[city.unit_index(own[0])]), 2.0) != 0, "pick находит юнита")
	SimHarness.check(Ids.kind(city.pick(0, FakeCity.KOK_HQ + Vector2(3, 3), 0.5)) == Ids.Kind.BUILDING, "pick находит урду")
	var mm := city.minimap(0)
	SimHarness.check(mm["units"].size() > 100 and mm["buildings"].size() > 20, "миникарта")
	SimHarness.check(city.grass().size() == 64 * 64 and city.water().size() == 128 * 128 and city.field_dims() == Vector4i(64, 64, 128, 128), "трава и полив")
	var sel := SelectionModel.new()
	sel.set_selection(own.slice(0, 5))
	sel.set_group(0)
	city.battle().u_life[city.unit_index(own[0])] = BattleSim.Life.DEAD   # проверка prune (тест пишет в ядро сам)
	sel.prune(city)
	SimHarness.check(sel.selected.size() == 4 and sel.groups[0].size() == 4 and sel.recall_group(0).size() == 4, "выделение: prune и группы")
	city.submit(0, SimCmd.move(own.slice(0, 1), Vector2(150, 60)))
	SimHarness.check(city.submitted.size() == 1 and city.submitted[0][SimCmd.H_PLAYER] == 0, "приказ принят")
