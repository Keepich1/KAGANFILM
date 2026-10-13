extends SceneTree
## Стройка, урон, руины, ремонт (ARCHITECTURE §15 ECON; ECONOMY §1.6, §2.2, §9.3 T8):
##   godot --headless --path ordo --script res://tests/test_econ_build.gd
## 1) стройка: цена, SITE, штамп, зеркало ST_SITE; n^0,75 — 4 работника строят в 2,83 раза быстрее;
##    готово — BUILDING_DONE, население, работники к прежней работе / на своё поле;
## 2) «нужно сначала» (Бурж — после Хумдона), предел на игрока (один Бозор), своя земля;
## 3) арык — цепочкой «звено за звеном», поле у арыка поливается; начало — только у своего тўғона или на своём
##    арыке (ECONOMY §2.2.1), землю даёт только законная сеть, предел сети 400 м; звено через place_site — INVALID;
##    пересчёт воды на сети в 100 звеньев — по готовому соседству (≤ 2 мс на такт, ARCHITECTURE §16);
## 4) T8: 20 чабуулов — Уй за 9–13 с, Тўғон за 30–40 с; 20 навкаров — Боз үй за 3–5 с;
## 5) руина, снос стройки с возвратом, ремонт за полцены, потеря ставки.

const HQ := Vector2(90, 0)


func _init() -> void:
	_site()
	_speed()
	_rules()
	_aryk()
	_aryk_rules()
	_net_perf()
	_damage()
	_ruins_repair()
	SimHarness.finish(self)


func _site() -> void:
	print("[стройка]")
	var k := EconKit.make()
	var p := k.kokand(HQ, 6)
	var e := k.econ
	var ws := k.workers_of(p)
	var st := e.spawn_node(k.defs.node(&"stone"), Vector2(140, 0), 900_000)
	e.assign_gather(p, PackedInt32Array([ws[0]]), st)
	k.run_s(5.0)
	var wood0 := k.res(p, "wood")
	var h := e.place_site(p, k.b(&"uy"), Vector2(90, 30), 0, PackedInt32Array([ws[0], ws[1]]))
	SimHarness.check(h > 0 and e.buildings.state[e.buildings.slot(h)] == BuildingTable.State.SITE, "Уй: стройка (SITE)")
	SimHarness.check(k.res(p, "wood") == wood0 - 80.0 and k.res(p, "stone") == 230.0, "цена списана: 80 дерева, 20 камня")
	SimHarness.check(e.place_site(p, k.b(&"uy"), Vector2(92, 31), 0, PackedInt32Array()) == -(100 + NavApi.Why.OVERLAP),
		"на занятое место нельзя (штамп в навигации)")
	var stub := k.port as CombatPortStub
	SimHarness.check(stub.structures.has(h) and int(stub.structures[h]["flags"]) & BattleSim.ST_SITE != 0, "зеркало в ядре с ST_SITE")
	var cap0 := e.players.pop_cap[p]
	var c0 := k.events.head
	k.run_s(25.0)
	SimHarness.check(e.buildings.state[e.buildings.slot(h)] == BuildingTable.State.ACTIVE and k.count_ev(SimEvents.Ev.BUILDING_DONE, c0) == 1,
		"двое достроили Уй (BUILDING_DONE)")
	SimHarness.check(e.players.pop_cap[p] == cap0 + 15, "население +15")
	SimHarness.check(int(stub.structures[h]["flags"]) & BattleSim.ST_SITE == 0, "зеркало без ST_SITE")
	var j0 := e.worker_job(ws[0])
	SimHarness.check(j0 == EconWorkers.Job.TO_NODE or j0 == EconWorkers.Job.GATHER, "каменотёс вернулся к жиле")
	SimHarness.check(e.worker_job(ws[1]) == EconWorkers.Job.IDLE, "второй — свободен (прежней работы не было)")
	# поле: строитель сам начинает пахать
	var f := e.place_site(p, k.b(&"dala"), Vector2(60, 40), 0, PackedInt32Array([ws[2]]))
	k.run_s(30.0)
	SimHarness.check(e.buildings.state[e.buildings.slot(f)] == BuildingTable.State.ACTIVE
		and e.worker_job(ws[2]) in [EconWorkers.Job.TO_FIELD, EconWorkers.Job.FARM], "построил поле — пашет его")
	# пусто в приказе — ближайший свободный
	var g := e.place_site(p, k.b(&"tegirmon"), Vector2(60, 70), 0, PackedInt32Array())
	k.run_s(1.0)
	var builders := 0
	for u_h in ws:
		if e.worker_job(u_h) in [EconWorkers.Job.TO_SITE, EconWorkers.Job.BUILD]:
			builders += 1
	SimHarness.check(g > 0 and builders == 1, "работников не дали — идёт ближайший свободный")


## Время стройки: 1 и 4 работника (n^0,75)
func _speed() -> void:
	print("[скорость стройки n^0,75]")
	var times := []
	for n in [1, 4]:
		var k := EconKit.make()
		var p := k.kokand(HQ, n)
		var e := k.econ
		var h := e.place_site(p, k.b(&"uy"), Vector2(90, 22), 0, k.workers_of(p))
		var b := e.buildings.slot(h)
		var t0 := -1
		var t1 := -1
		for i in 1200:
			k.step()
			if t0 < 0 and e.buildings.workers_n[b] >= n:
				t0 = k.tick
			if e.buildings.state[b] == BuildingTable.State.ACTIVE:
				t1 = k.tick
				break
		times.append(float(t1 - t0) / 30.0)
		print("  %d работник(а): %.2f с" % [n, times[-1]])
	SimHarness.check_range(times[0], 24.5, 25.5, "один работник — 25 с (build_time)")
	SimHarness.check_range(times[0] / times[1], 2.83 * 0.95, 2.83 * 1.05, "четверо — в 4^0,75 = 2,83 раза быстрее")


func _rules() -> void:
	print("[правила постройки]")
	var k := EconKit.make()
	var p := k.kokand(HQ, 2)
	var e := k.econ
	k.set_res(p, "wood", 5000.0)
	k.set_res(p, "stone", 5000.0)
	k.set_res(p, "brick", 500.0)
	SimHarness.check(e.place_site(p, k.b(&"burj"), Vector2(120, 30), 0, PackedInt32Array()) == -EconApi.Err.NOT_ALLOWED,
		"Бурж — только после Хумдона")
	SimHarness.check(e.place_site(p, k.b(&"bozor"), Vector2(60, -40), 0, PackedInt32Array()) > 0, "первый Бозор")
	SimHarness.check(e.place_site(p, k.b(&"bozor"), Vector2(130, -40), 0, PackedInt32Array()) == -EconApi.Err.NOT_ALLOWED,
		"второй Бозор — нельзя (один на игрока)")
	SimHarness.check(e.place_site(p, k.b(&"uy"), Vector2(300, 300), 0, PackedInt32Array()) == -(100 + NavApi.Why.NO_TERRITORY),
		"далеко от своих построек — «не своя земля»")
	SimHarness.check(e.place_wall(p, k.b(&"devor"), PackedVector2Array([Vector2(70, 40), Vector2(90, 40)]), PackedInt32Array())
		!= -EconApi.Err.NOT_ALLOWED, "стены — в Сб. 1 (пахсу можно класть)")
	SimHarness.check(e.place_site(p, k.b(&"devor"), Vector2(70, 40), 0, PackedInt32Array()) == -EconApi.Err.INVALID,
		"звено стены через place_site — INVALID (только BUILD_WALL)")
	SimHarness.check(e.place_site(p, k.b(&"boz"), Vector2(70, 40), 0, PackedInt32Array()) == -EconApi.Err.NOT_ALLOWED,
		"юрту кыпчаков Коканду не построить")
	var menu := e.build_menu(p, &"economy")
	var names := PackedStringArray()
	for it: Dictionary in menu:
		names.append(it["name"])
	SimHarness.check(menu.size() == 11 and not names.has("Темирчихона"), "меню «Хозяйство» Коканда: 11 построек Сб. 1")
	var fort := e.build_menu(p, &"fort")
	var fort_why := {}
	for it in fort:
		fort_why[it["name"]] = String(it["why"])
	SimHarness.check(fort_why.has("Пахса девор") and fort_why.has("Дарвоза") and fort_why.has("Бурж")
		and fort_why["Бурж"].begins_with("Сначала"),
		"«Укрепления» в Сб. 1: пахса, дарвоза, бурж («Сначала: Хумдон»)")
	k.set_res(p, "wood", 10.0)
	var uy: Dictionary = e.build_menu(p, &"economy")[0]
	SimHarness.check(not uy["enabled"] and String(uy["why"]).begins_with("Нужно: 70 дерево"), "нет дерева — «Нужно: 70 дерево»")


## Арык цепочкой: поле у воды
func _aryk() -> void:
	print("[арык и вода]")
	var k := EconKit.make()
	var p := k.kokand(HQ, 4)
	var e := k.econ
	var dam := k.build_now(p, &"togon", Vector2(90, -60))
	var pts := PackedVector2Array([Vector2(90, -52), Vector2(90, -12)])
	var chain := e.place_wall(p, k.b(&"aryk"), pts, k.workers_of(p))
	var links := 0
	for b in e.buildings.hw:
		if e.buildings.chain[b] == chain and e.buildings.state[b] == BuildingTable.State.SITE:
			links += 1
	SimHarness.check(chain > 0 and links == 10 and k.res(p, "wood") == 400.0 - 20.0, "арык: 10 звеньев по 2 дерева")
	k.run_s(60.0)
	var done := 0
	for b in e.buildings.hw:
		if e.buildings.chain[b] == chain and e.buildings.state[b] == BuildingTable.State.ACTIVE:
			done += 1
	SimHarness.check(done == 10, "звенья построены одно за другим (%d)" % done)
	var f := k.build_now(p, &"dala", Vector2(112, -36))
	k.step()
	var fb := e.buildings.slot(f)
	SimHarness.check(e.buildings.state[fb] == BuildingTable.State.ACTIVE and e.b_water[fb] == 1000 and e.b_net[fb] == e.buildings.slot(dam),
		"поле у арыка — у воды, место тўғона занято")
	SimHarness.check(e.net.water_at(e, Vector2(110, -36)) == 1000 and e.net.water_at(e, Vector2(150, -36)) == 0,
		"зона воды — 24 м от арыка")
	var panel := e.building_panel(dam)
	SimHarness.check(panel["water_places"]["used"] == 1 and panel["water_places"]["cap"] == 8, "панель тўғона: «Сув 1/8»")


## ECONOMY §2.2.1: арык начинают у своего тўғона или на своём арыке той же сети; землю даёт только такая сеть
func _aryk_rules() -> void:
	print("[арык: начало, своя земля, предел сети]")
	var k := EconKit.make()
	var p := k.kokand(HQ, 0)
	var e := k.econ
	k.set_res(p, "wood", 5000.0)
	k.set_res(p, "stone", 5000.0)
	var aryk := k.b(&"aryk")
	var far := Vector2(-300, -300)
	SimHarness.check(e.place_why(p, k.b(&"kazarma"), far, 0) == 100 + NavApi.Why.NO_TERRITORY, "в 400 м от Урды — не своя земля")
	var w0 := k.res(p, "wood")
	var n0 := e.buildings.count_state(BuildingTable.State.SITE)
	SimHarness.check(e.place_wall(p, aryk, PackedVector2Array([far, far + Vector2(8, 0)]), PackedInt32Array()) == -(100 + NavApi.Why.NOT_NEAR)
		and k.res(p, "wood") == w0 and e.buildings.count_state(BuildingTable.State.SITE) == n0, "арык не от тўғона — нельзя (и даром)")
	SimHarness.check(not e.in_territory(p, far) and e.place_site(p, k.b(&"kazarma"), far, 0, PackedInt32Array())
		== -(100 + NavApi.Why.NO_TERRITORY), "земли нет: казарму там не поставить")
	SimHarness.check(e.place_site(p, aryk, Vector2(100, 30), 0, PackedInt32Array()) == -EconApi.Err.INVALID and k.res(p, "wood") == w0
		and e.buildings.count_state(BuildingTable.State.SITE) == n0, "звено через place_site — INVALID, звена в (0, 0) нет")
	# законно: от своего тўғона; ветка — от своего арыка
	var dam := k.build_now(p, &"togon", Vector2(90, -100))
	SimHarness.check(e.wall_start_why(p, aryk, far) == 100 + NavApi.Why.NOT_NEAR and e.wall_start_why(p, aryk, Vector2(90, -94)) == 0,
		"инструмент стен: начало арыка вдали — нельзя, у тўғона — можно")
	SimHarness.check(e.place_wall(p, aryk, PackedVector2Array([Vector2(90, -94), Vector2(90, -54)]), PackedInt32Array()) > 0,
		"от своего тўғона — можно")
	SimHarness.check(e.place_wall(p, aryk, PackedVector2Array([Vector2(91, -70), Vector2(131, -70)]), PackedInt32Array()) > 0,
		"ветка от своего арыка (ещё стройка) — можно")
	SimHarness.check(e.in_territory(p, Vector2(150, -70)), "у ветки — своя земля (24 м)")
	# чужой тўғон и чужой арык — не начало
	var q := k.kokand(Vector2(-200, 200), 0, 1)
	k.set_res(q, "wood", 500.0)
	SimHarness.check(e.place_wall(q, aryk, PackedVector2Array([Vector2(84, -100), Vector2(44, -100)]), PackedInt32Array())
		== -(100 + NavApi.Why.NOT_NEAR), "от чужого тўғона — нельзя")
	SimHarness.check(e.place_wall(q, aryk, PackedVector2Array([Vector2(131, -70), Vector2(171, -70)]), PackedInt32Array())
		== -(100 + NavApi.Why.NOT_NEAR), "от чужого арыка — нельзя")
	# предел сети: 500 м от тўғона — ставятся звенья только до 400 м от него
	var w1 := k.res(p, "wood")
	var long := e.place_wall(p, aryk, PackedVector2Array([Vector2(84, -100), Vector2(-416, -100)]), PackedInt32Array())
	var n := 0
	var reach := 0.0
	for b in e.buildings.hw:
		if e.buildings.chain[b] == long and e.buildings.state[b] == BuildingTable.State.SITE:
			n += 1
			reach = maxf(reach, absf(e.buildings.x[b] - 90.0))
	SimHarness.check(long > 0 and n >= 95 and n <= 100 and reach <= 400.0 and k.res(p, "wood") == w1 - 2.0 * n,
		"500 м арыка — только %d звеньев до 400 м от тўғона, плата за них" % n)
	SimHarness.check(e.in_territory(p, Vector2(-250, -100)) and not e.in_territory(p, Vector2(-345, -100)),
		"земля — вдоль законной сети, не дальше")
	# тўғон снесён своими — цепочки без головы земли не дают
	SimHarness.check(e.demolish(p, dam) == EconApi.Err.OK and not e.in_territory(p, Vector2(-250, -100)),
		"тўғон снесён — земли у арыка нет")


## Сеть в 100 звеньев (400 м): работники строят ветку в 25 звеньев — пересчёт воды на каждое готовое звено
## по готовому соседству ≤ 2 мс (ARCHITECTURE §16, экономика p99); снос дома сеть не трогает
func _net_perf() -> void:
	print("[вода: 100 звеньев, скорость пересчёта]")
	var k := EconKit.make()
	var p := k.kokand(HQ, 0)
	var e := k.econ
	k.set_res(p, "wood", 5000.0)
	k.build_now(p, &"togon", Vector2(90, -100))
	e.spawn_links(p, k.b(&"aryk"), PackedVector2Array([Vector2(84, -100), Vector2(-150, -100), Vector2(-150, -264)]))
	var links := 0
	for b in e.buildings.hw:
		if e.buildings.state[b] == BuildingTable.State.ACTIVE and e.net.is_link(e.buildings.btype[b]):
			links += 1
	var fields := 0
	for i in 12:
		var f := k.build_now(p, &"dala", Vector2(60 - i * 18, -78))
		fields += 1 if f > 0 else 0
	k.step()
	var full := 1 << 30
	for i in 5:                          # стенные часы, лучший из 5: машина делится с другими процессами
		var t0 := Time.get_ticks_usec()
		e.net._repaint = true
		e.net.recompute(e)
		full = mini(full, Time.get_ticks_usec() - t0)
	var wet := 0
	for b in e.buildings.hw:
		if e.net.link_net.size() > b and e.net.link_net[b] >= 0:
			wet += 1
	print("  звеньев %d (с водой %d), полей %d; полный пересчёт %.2f мс" % [links, wet, fields, full / 1000.0])
	SimHarness.check(links >= 98 and wet == links, "все %d звеньев — одна сеть" % links)
	# ветка в 25 звеньев: каждое готовое звено — пересчёт
	var chain := e.place_wall(p, k.b(&"aryk"), PackedVector2Array([Vector2(-150, -180), Vector2(-50, -180)]), PackedInt32Array())
	var sites := PackedInt32Array()
	for b in e.buildings.hw:
		if e.buildings.chain[b] == chain and e.buildings.state[b] == BuildingTable.State.SITE:
			sites.append(b)
	var times: Array[int] = []
	var cpu0 := _now_us()
	for b in sites:
		e._sites.erase(b)
		e._activate(b, true)
		var t1 := Time.get_ticks_usec()
		e.net.recompute(e)
		times.append(Time.get_ticks_usec() - t1)
	var cpu := _now_us() - cpu0
	times.sort()
	var p90 := times[mini(times.size() - 1, times.size() * 9 / 10)] if not times.is_empty() else 0
	print("  ветка %d звеньев: пересчёт на звено — медиана %.3f мс, 90%% %.3f мс, худший %.3f мс (стенные); процессор на всё %.2f мс"
		% [sites.size(), times[times.size() / 2] / 1000.0, p90 / 1000.0, times[-1] / 1000.0, cpu / 1000.0])
	SimHarness.check(sites.size() == 25 and p90 <= 2000, "готовое звено на сети в 100 — пересчёт ≤ 2 мс (90%%: %.3f)" % (p90 / 1000.0))
	SimHarness.check(e.net.water_at(e, Vector2(-60, -200)) == 1000, "ветка с водой")
	# докрашенная сетка = перекрашенной целиком
	var inc := e.net.bytes.duplicate()
	e.net._repaint = true
	e.net.recompute(e)
	SimHarness.check(inc == e.net.bytes, "сетка полива: докраска = полная перекраска")
	SimHarness.check(full <= 8000, "полный пересчёт (засуха, снос) ≤ 8 мс (%.2f)" % (full / 1000.0))
	# снос не водного здания не трогает сеть
	var uy := k.build_now(p, &"uy", Vector2(120, 30))
	k.step()
	e.destroy_building(e.buildings.slot(uy), -1, true)
	SimHarness.check(not e._net_dirty, "снос дома — без пересчёта воды")


## Процессорное время этого потока, мкс (как test_econ_gather)
func _now_us() -> int:
	var f := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
	if f:
		return int(f.get_line().split(" ")[0]) / 1000
	return Time.get_ticks_usec()


## T8: урон по зданиям рукопашной (удар раз в 1,4 с)
func _damage() -> void:
	print("[урон по зданиям, T8]")
	for case in [["chabuulchu", &"uy", 9.0, 13.0], ["chabuulchu", &"togon", 30.0, 40.0], ["navkar", &"boz", 3.0, 5.0]]:
		var k := EconKit.make()
		var kok := k.kokand(HQ, 0)
		var kip := k.kipchak(Vector2(-60, 20), 0)
		var e := k.econ
		var owner := kip if case[1] == &"boz" else kok
		var att_p := kok if case[1] == &"boz" else kip
		var h := k.build_now(owner, case[1], Vector2(-60, 70) if owner == kip else Vector2(120, 40))
		var atk := PackedInt32Array()
		var dmg := int(UnitStats.get_stats(case[0])["attack"]) * 100
		for i in 20:
			atk.append(k.port.spawn(att_p, e.players.team[att_p], StringName(case[0]), Vector2(0, 0), 0.0))
		var t := 0
		var stub := k.port as CombatPortStub
		while e.buildings.valid(h) and e.buildings.state[e.buildings.slot(h)] == BuildingTable.State.ACTIVE and t < 3000:
			if (t + 1) % 42 == 0:
				for a in atk:
					stub.test_hit_structure(h, dmg, a)
			k.step()
			t += 1
		var secs := t / 30.0
		SimHarness.check_range(secs, case[2], case[3], "20 × %s: %s" % [case[0], case[1]])
		if case[1] == &"togon":
			var b := e.buildings.slot(h)
			SimHarness.check(e.buildings.state[b] == BuildingTable.State.RUIN, "тўғон — руина (ждёт восстановления)")


func _ruins_repair() -> void:
	print("[руины, снос, ремонт, ставка]")
	var k := EconKit.make()
	var p := k.kokand(HQ, 2)
	var e := k.econ
	var stub := k.port as CombatPortStub
	var uy := k.build_now(p, &"uy", Vector2(120, 30))
	var c0 := k.events.head
	stub.test_hit_structure(uy, 100000, 0)
	k.step()
	var b := e.buildings.slot(uy)
	SimHarness.check(e.buildings.state[b] == BuildingTable.State.RUIN and k.count_ev(SimEvents.Ev.BUILDING_DESTROYED, c0) == 1,
		"разрушен — руина, BUILDING_DESTROYED")
	SimHarness.check(e.place_why(p, k.b(&"uy"), Vector2(120, 30), 0) == 0, "руина не держит место")
	k.run_s(61.0)
	SimHarness.check(not e.buildings.valid(uy), "руина Уй убрана через 60 с")
	# снос стройки — возврат
	var w0 := k.res(p, "wood")
	var site := e.place_site(p, k.b(&"tegirmon"), Vector2(60, 40), 0, PackedInt32Array([k.workers_of(p)[1]]))
	SimHarness.check(e.demolish(p, site) == EconApi.Err.OK and k.res(p, "wood") == w0, "снос стройки до начала — полный возврат")
	# ремонт: полцены
	var uy2 := k.build_now(p, &"uy", Vector2(60, -30))
	var b2 := e.buildings.slot(uy2)
	e.buildings.hp_c[b2] = e.buildings.hp_max_c[b2] / 2
	var wood := k.res(p, "wood")
	var stone := k.res(p, "stone")
	SimHarness.check(e.assign_build(p, PackedInt32Array([k.workers_of(p)[0]]), uy2) == EconApi.Err.OK, "приказ «чинить»")
	k.run_s(25.0)
	SimHarness.check(e.buildings.hp_c[b2] == e.buildings.hp_max_c[b2], "починен")
	SimHarness.check_range(wood - k.res(p, "wood"), 18.0, 22.0, "половина HP за четверть цены: 20 дерева")
	SimHarness.check_range(stone - k.res(p, "stone"), 4.0, 6.0, "и 5 камня")
	# ставка
	var hq := e.players.hq_b[p]
	stub.test_hit_structure(hq, 500000, 0)
	k.step()
	SimHarness.check(e.players.hq_b[p] == 0 and not e.has_hq(p), "Урда разрушена: hq_b = 0, has_hq — нет")
