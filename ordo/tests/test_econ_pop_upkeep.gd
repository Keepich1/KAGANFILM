extends SceneTree
## Найм, население, содержание, голод, подать, обмен (ARCHITECTURE §15 ECON; ECONOMY §1.4, §1.5, §2.5, §2.7;
## T4, T9): godot --headless --path ordo --script res://tests/test_econ_pop_upkeep.gd

const HQ := Vector2(90, 0)


func _init() -> void:
	_upkeep()
	_famine()
	_famine_income()
	_queue()
	_pop_cap()
	_unique()
	_otlar()
	_tax_trade()
	SimHarness.finish(self)


## 100 бойцов × 0,7 = 70 еды в минуту ±1
func _upkeep() -> void:
	print("[содержание]")
	var k := EconKit.make()
	var p := k.kokand(HQ, 0)
	var e := k.econ
	for i in 100:
		k.unit(p, &"sarboz", HQ + Vector2(20 + i % 10, 20 + i / 10))
	for i in 10:
		k.unit(p, &"navkar", HQ + Vector2(-20 - i, 20))
	SimHarness.check(e.p_upkeep[p] == 100 * 700 + 10 * 1400, "содержание: 100 сарбозов × 0,7 + 10 навкаров × 1,4 = 84/мин")
	k.set_res(p, "food", 5000.0)
	k.run_s(30.0)
	var f0 := k.res(p, "food")
	k.run_s(180.0)
	var per_min := (f0 - k.res(p, "food")) / 3.0
	SimHarness.check_range(per_min, 83.0, 85.0, "еды в минуту на содержание")
	SimHarness.check(e.players.pop_used[p] == 110, "население: 110 бойцов")
	SimHarness.check(e.players.income[p * e.R + k.r(&"food")] < 0, "доход еды на балке — минус (%d)" % (e.players.income[p * e.R + k.r(&"food")] / 1000))


## T9: еда 0 → атака −20% сразу; через 60 с — дезертиры; при 50 еды голод кончается
func _famine() -> void:
	print("[голод, T9]")
	var k := EconKit.make()
	var p := k.kokand(HQ, 0)
	var e := k.econ
	var sq := k.port.spawn_squad(p, 0, &"sarboz", 40, HQ + Vector2(40, 40), 0.0)
	for u_h in k.port.members(sq):
		e.register_unit(u_h, p, k.u(&"sarboz"))
	for i in 10:
		k.unit(p, &"kamonchi", HQ + Vector2(-30, 30 + i * 2))
	k.set_res(p, "food", 10.0)
	var c0 := k.events.head
	k.run_s(30.0)
	SimHarness.check(e.players.famine[p] == 1 and k.count_ev(SimEvents.Ev.FAMINE, c0) == 1 and k.res(p, "food") == 0.0,
		"еды не хватило на содержание — голод (FAMINE)")
	var mods := k.owner_mods(p)
	SimHarness.check(mods.size() == BattleSim.MOD_N and is_equal_approx(mods[BattleSim.MOD_ATK], 0.8)
		and is_equal_approx(mods[BattleSim.MOD_STAM], 0.5), "в ядро: атака ×0,8, выносливость ×0,5")
	SimHarness.check(is_equal_approx(e.players.stat[p * PlayerTable.Stat.COUNT + PlayerTable.Stat.ATK], 0.8), "PlayerTable.stat: ATK 0,8")
	var urda := e.players.hq_b[p]
	SimHarness.check(e.train(p, urda, k.u(&"dehqon"), 1) == -EconApi.Err.NOT_ALLOWED, "в голод за еду не нанять")
	var n0 := e.p_soldiers[p]
	k.run_s(40.0)
	SimHarness.check(e.p_soldiers[p] == n0, "до 60 с — без дезертиров")
	k.run_s(25.0)
	var lost := n0 - e.p_soldiers[p]
	SimHarness.check(lost == 2, "через 60 с: отряд 40 −1 (3%%, не меньше 1), одиночки −1 (%d)" % lost)
	k.run_s(30.0)
	SimHarness.check(n0 - e.p_soldiers[p] == 4, "ещё через 30 с — снова")
	k.set_res(p, "food", 60.0)
	k.run_s(1.0)
	mods = k.owner_mods(p)
	SimHarness.check(e.players.famine[p] == 0 and is_equal_approx(mods[BattleSim.MOD_ATK], 1.0), "50 еды и больше — голод кончился")


## T9 (ECONOMY §1.5): голод — когда еды 0 И приход меньше расхода. 10 сарбозов (7 еды в минуту), приходит
## 450 в минуту и сразу тратится (еда всё время у нуля) — голода нет; приход 3 в минуту — голод
func _famine_income() -> void:
	print("[голод: приход против расхода]")
	for case in [[7500, false], [50, true]]:
		var k := EconKit.make()
		var p := k.kokand(HQ, 0)
		var e := k.econ
		for i in 10:
			k.unit(p, &"sarboz", HQ + Vector2(20 + i, 20))
		k.set_res(p, "food", 0.0)
		var spend := PackedInt32Array()
		spend.resize(e.R)
		var c0 := k.events.head
		var famine_s := 0
		for t in 1800:
			if k.tick % 30 == 5:
				# приход за секунду (как сдача работников) и сразу трата (найм, стройка)
				e.add_res(p, k.r(&"food"), case[0])
				spend[k.r(&"food")] = e.res(p, k.r(&"food"))
				e.pay(p, spend)
			k.step()
			if k.tick % 30 == 0 and e.players.famine[p] == 1:
				famine_s += 1
		var inc := e.players.income[p * e.R + k.r(&"food")] / 1000.0
		if case[1]:
			SimHarness.check(famine_s >= 50 and k.count_ev(SimEvents.Ev.FAMINE, c0) == 1,
				"приход 3/мин < расхода 7/мин, еда 0 — голод (%d с из 60)" % famine_s)
		else:
			var mods := k.owner_mods(p)
			SimHarness.check(famine_s == 0 and k.count_ev(SimEvents.Ev.FAMINE, c0) == 0
				and (mods.is_empty() or is_equal_approx(mods[BattleSim.MOD_ATK], 1.0)),
				"приход 450/мин > расхода 7/мин, еда всё время 0 — голода нет (доход %+.0f/мин)" % inc)
			SimHarness.check(e.popn.upk_acc[p] <= int(e.p_upkeep[p]) * 1800, "недостача — долгом не больше минуты содержания")


func _queue() -> void:
	print("[очередь найма]")
	var k := EconKit.make()
	var p := k.kokand(HQ, 0)
	var e := k.econ
	var urda := e.players.hq_b[p]
	var food0 := k.res(p, "food")
	SimHarness.check(e.train(p, urda, k.u(&"dehqon"), 3) == EconApi.Err.OK and e.buildings.q_n[e.buildings.slot(urda)] == 3,
		"3 деҳқона в очереди")
	SimHarness.check(k.res(p, "food") == food0 - 150.0, "цена при постановке: 150 еды")
	SimHarness.check(e.cancel_train(p, urda, 2) == EconApi.Err.OK and k.res(p, "food") == food0 - 100.0, "отмена — возврат 50")
	SimHarness.check(e.train(p, urda, k.u(&"dehqon"), 9) == EconApi.Err.OK and e.buildings.q_n[e.buildings.slot(urda)] == 5,
		"очередь — не больше 5")
	SimHarness.check(e.train(p, urda, k.u(&"dehqon"), 1) == -EconApi.Err.QUEUE_FULL, "полная очередь — QUEUE_FULL")
	SimHarness.check(e.train(p, urda, k.u(&"sarboz"), 1) == -EconApi.Err.NOT_ALLOWED, "сарбоза в Урде не нанять")
	var st := e.spawn_node(k.defs.node(&"stone"), Vector2(90, 60))
	e.set_rally(p, urda, Vector2(90, 60), st)
	var c0 := k.events.head
	k.run_s(7.2)
	var tr := k.last_ev(SimEvents.Ev.TRAINED, c0)
	SimHarness.check(tr >= 0 and k.count_ev(SimEvents.Ev.TRAINED, c0) == 1, "через 7 с — первый деҳқон (TRAINED)")
	var u_h := k.events.e_a[tr]
	var door := Vector2(k.events.e_x[tr], k.events.e_z[tr])
	# на настоящей сетке дверь — nearest_passable (клетка 4 м вне следа ставки), на заглушке — точно
	SimHarness.check(door.distance_to(HQ + Vector2(0, 10.5)) < (4.0 if k.is_real() else 0.1),
		"вышел у двери (фасад +Z): %s" % door)
	SimHarness.check(e.worker_job(u_h) == EconWorkers.Job.TO_NODE, "точка сбора на жиле — сразу к работе")
	SimHarness.check(e.players.pop_used[p] == 1 and e.players.pop_reserved[p] == 1, "занят 1, следующий в очереди занял место")


func _pop_cap() -> void:
	print("[предел населения]")
	var k := EconKit.make()
	var p := k.kokand(HQ, 24)
	var e := k.econ
	var urda := e.players.hq_b[p]
	var c0 := k.events.head
	e.train(p, urda, k.u(&"dehqon"), 2)
	k.run_s(16.0)
	SimHarness.check(e.players.pop_used[p] == 25 and k.count_ev(SimEvents.Ev.POP_CAPPED, c0) == 1, "25/25: очередь встала (POP_CAPPED)")
	k.build_now(p, &"uy", Vector2(60, 40))
	k.run_s(8.0)
	SimHarness.check(e.players.pop_used[p] == 26 and e.players.pop_cap[p] == 40, "дом +15 — найм пошёл")


func _unique() -> void:
	print("[полководец]")
	var k := EconKit.make()
	var p := k.kokand(HQ, 0)
	var e := k.econ
	var urda := e.players.hq_b[p]
	k.set_res(p, "gold", 1000.0)
	var lb := k.u(&"lashkarboshi")
	SimHarness.check(e.train(p, urda, lb, 2) == EconApi.Err.OK and e.buildings.q_n[e.buildings.slot(urda)] == 1, "Лашкарбоши — один")
	k.run_s(31.0)
	SimHarness.check(e.train(p, urda, lb, 1) == -EconApi.Err.NOT_ALLOWED, "второго нельзя")
	var h := k.last_ev(SimEvents.Ev.TRAINED)
	k.port.kill(k.events.e_a[h])
	k.run_s(1.0)
	SimHarness.check(e.train(p, urda, lb, 1) == -EconApi.Err.NOT_ALLOWED, "после гибели — не сразу")
	k.run_s(120.0)
	SimHarness.check(e.train(p, urda, lb, 1) == EconApi.Err.OK, "снова через 120 с")
	SimHarness.check(e.train(p, urda, k.u(&"xos_navkar"), 1) == -EconApi.Err.NOT_ALLOWED, "Хос навкарлар — нужны Отхона и Тўпхона")


## Отлар: угнанные кони в Отхоне — −25 золота с всадника Коканда
func _otlar() -> void:
	print("[отлар]")
	var k := EconKit.make()
	var p := k.kokand(HQ, 0)
	var e := k.econ
	var ot := k.build_now(p, &"otxona", Vector2(60, 50))
	var b := e.buildings.slot(ot)
	e.b_otlar[b] = 2
	var g0 := k.res(p, "gold")
	SimHarness.check(e.building_panel(ot)["trains"][1]["cost"][k.r(&"gold")] == 20000, "панель: навкар за 45 − 25 = 20 золота")
	e.train(p, ot, k.u(&"navkar"), 3)
	SimHarness.check(k.res(p, "gold") == g0 - 20.0 - 20.0 - 45.0 and e.b_otlar[b] == 0, "два коня из Отхоны — две скидки")
	e.cancel_train(p, ot, 0)
	SimHarness.check(k.res(p, "gold") == g0 - 20.0 - 45.0 and e.b_otlar[b] == 1, "отмена — конь вернулся в Отхону")


## T4: Бозор — 10 Уй и Урда = 48 золота в минуту; Уй ниже 50% HP не платит; обмен
func _tax_trade() -> void:
	print("[подать и обмен, T4]")
	var k := EconKit.make()
	var p := k.kokand(HQ, 0)
	var e := k.econ
	var bozor := k.build_now(p, &"bozor", Vector2(60, -50))
	var houses := PackedInt32Array()
	for i in 10:
		houses.append(k.build_now(p, &"uy", Vector2(40 + (i % 5) * 12, 40 + (i / 5) * 12)))
	k.run_s(1.0)
	var g0 := k.res(p, "gold")
	k.run_s(60.0)
	SimHarness.check_range(k.res(p, "gold") - g0, 47.9, 48.1, "подать: 48 золота в минуту")
	var h0 := e.buildings.slot(houses[0])
	e.buildings.hp_c[h0] = e.buildings.hp_max_c[h0] * 4 / 10
	g0 = k.res(p, "gold")
	k.run_s(60.0)
	SimHarness.check_range(k.res(p, "gold") - g0, 43.9, 44.1, "Уй с HP < 50% не платит: 44")
	g0 = k.res(p, "gold")
	var w0 := k.res(p, "wood")
	SimHarness.check(e.trade(p, bozor, k.r(&"wood"), k.r(&"gold"), 100_000) == EconApi.Err.OK
		and k.res(p, "gold") == g0 + 40.0 and k.res(p, "wood") == w0 - 100.0, "продать 100 дерева — 40 золота")
	SimHarness.check(e.trade(p, bozor, k.r(&"gold"), k.r(&"food"), 100_000) == EconApi.Err.OK and k.res(p, "gold") == g0 + 40.0 - 110.0,
		"купить 100 еды — 110 золота")
	SimHarness.check(e.trade(p, bozor, k.r(&"gold"), k.r(&"brick"), 100_000) == -EconApi.Err.NOT_ALLOWED, "ғишт не купить")
	SimHarness.check(e.trade(p, houses[1], k.r(&"wood"), k.r(&"gold"), 100_000) == -EconApi.Err.NOT_ALLOWED, "обмен — только на Бозоре")
