extends SceneTree
## Табуны, отары, трава, вода, набеги, олжо (ARCHITECTURE §15 ECON; ECONOMY §2.2–2.3, §3.3–3.4, §4.1–4.2;
## T1, T2, T5, T6, T7): godot --headless --path ordo --script res://tests/test_econ_herds_fields.gd

const KIP := Vector2(-60, 20)
const KOK := Vector2(90, 0)


func _init() -> void:
	_horses()
	_koroo()
	_pasture()
	_barymta()
	_post()
	_drop()
	_water()
	_bounty()
	SimHarness.finish(self)


## T5: двор с 6 / 10 / 20 / 30 конями — +1 / +2 / +3 / 0 за 20 с; кони — ресурс; всадник берёт коня
func _horses() -> void:
	print("[кони, T5]")
	var k := EconKit.make()
	var p := k.kipchak(KIP, 0)
	var e := k.econ
	SimHarness.check(k.res(p, "horse") == 6.0, "старт: 6 коней на коновязи ставки")
	var yard := k.build_now(p, &"jylky", Vector2(-25, 90), 2)
	k.run_s(1.0)
	var ordo_h := e.hd.herd_at(e, e.buildings.slot(e.players.hq_b[p]), -1)
	var yard_h := e.hd.herd_at(e, e.buildings.slot(yard), -1)
	SimHarness.check(e.herds.heads(ordo_h) == 0 and e.herds.heads(yard_h) == 6, "с первым двором кони ушли с коновязи")
	for case in [[6, 1], [10, 2], [20, 3], [30, 0]]:
		e.spawn_herd(p, k.defs.herd(&"horse"), yard, case[0])
		k.run_s(20.0)
		SimHarness.check(e.herds.heads(yard_h) - case[0] == case[1], "%d коней — +%d за 20 с" % [case[0], case[1]])
	SimHarness.check(k.res(p, "horse") == 30.0, "запас коней = голов в табунах (30)")
	var panel := e.building_panel(yard)
	SimHarness.check(panel["herd"]["heads"] == 30 and panel["herd"]["cap"] == 30, "панель двора: 30/30")
	SimHarness.check(e.train(p, yard, k.u(&"chabuulchu"), 2) == EconApi.Err.OK and k.res(p, "horse") == 28.0,
		"найм двух чабуулов — минус 2 коня")
	e.spawn_herd(p, k.defs.herd(&"horse"), yard, 0)
	k.step()
	SimHarness.check(e.train(p, yard, k.u(&"atchan"), 1) == -EconApi.Err.NO_RES, "без коней всадника не нанять")
	var why := ""
	for t: Dictionary in e.building_panel(yard)["trains"]:
		if t["utype"] == k.u(&"atchan"):
			why = t["why"]
	SimHarness.check(why == "Нет коней в табуне", "кнопка: «Нет коней в табуне»")
	# два двора делят поровну
	e.spawn_herd(p, k.defs.herd(&"horse"), yard, 20)
	var yard2 := k.build_now(p, &"jylky", Vector2(15, 90), 2)
	k.run_s(1.0)
	SimHarness.check(e.herds.heads(yard_h) == 10 and e.herds.heads(e.hd.herd_at(e, e.buildings.slot(yard2), -1)) == 10,
		"два двора — по 10")


## T7: короо на свежей траве с 0 / 1 / 2 пастухами — 54 / 72 / 90 еды в минуту
func _koroo() -> void:
	print("[короо, T7]")
	for n in [0, 1, 2]:
		var k := EconKit.make()
		var p := k.kipchak(KIP, n)
		var e := k.econ
		var pen := k.build_now(p, &"koroo", Vector2(-60, -50))
		if n > 0:
			e.assign_gather(p, k.workers_of(p), pen)
		k.run_s(20.0)
		var f0 := k.res(p, "food")
		k.run_s(30.0)
		var per_min := (k.res(p, "food") - f0) * 2.0
		var expect: float = 54.0 + 18.0 * n
		SimHarness.check_range(per_min / expect, 0.95, 1.01, "%d пастух(а): %.1f еды в минуту (≈ %d)" % [n, per_min, expect])
	var k := EconKit.make()
	var p := k.kipchak(KIP, 0)
	var e := k.econ
	k.set_res(p, "wood", 5000.0)
	var placed := 0
	for i in 12:
		var at := Vector2(-123 + (i % 4) * 42.0, -43 + (i / 4) * 42.0)
		if e.place_site(p, k.b(&"koroo"), at, 0, PackedInt32Array()) > 0:
			placed += 1
	SimHarness.check(placed == 10, "не больше 10 короо (поставлено %d)" % placed)
	var near := e.place_why(p, k.b(&"koroo"), Vector2(-100, -30), 0)
	SimHarness.check(near != 0, "короо ближе 40 м к другой — нельзя")


## Трава: 100% → 40% за 10 мин под отарой; PASTURE_LOW; авто-перегон; Мал союу
func _pasture() -> void:
	print("[пастбище]")
	var k := EconKit.make()
	var p := k.kipchak(KIP, 0)
	var e := k.econ
	var pen := k.build_now(p, &"koroo", Vector2(-60, -60))
	e.set_auto_move(p, pen, false)
	var h := e.hd.herd_at(e, e.buildings.slot(pen), -1)
	var g0 := e.fld.avg_under(e, Vector2(-60, -60), e.herds.graze_r[h])
	var c0 := k.events.head
	k.run_s(600.0)
	var g1 := e.fld.avg_under(e, Vector2(-60, -60), e.herds.graze_r[h])
	print("  трава %d → %d" % [g0, g1])
	SimHarness.check(g0 == 1000 and g1 >= 390 and g1 <= 420, "трава 100% → 40% за 10 мин")
	SimHarness.check(k.count_ev(SimEvents.Ev.PASTURE_LOW, c0) == 1, "«Жайыт тозду» (PASTURE_LOW)")
	SimHarness.check(e.herds.heads(h) == 40, "отара 40")
	# авто-перегон
	e.set_auto_move(p, pen, true)
	c0 = k.events.head
	k.run_s(10.0)
	var b := e.buildings.slot(pen)
	var moved := Vector2(e.buildings.x[b], e.buildings.z[b]).distance_to(Vector2(-60, -60))
	var ev := k.last_ev(SimEvents.Ev.PASTURE_LOW, c0)
	SimHarness.check(moved >= 39.0 and moved <= 81.0 and ev >= 0 and k.events.e_c[ev] == 2, "авто-перегон на 40–80 м (%.0f м)" % moved)
	var f0 := k.res(p, "food")
	k.run_s(20.0)
	SimHarness.check(k.res(p, "food") == f0, "в перегоне ~30 с еды нет")
	k.run_s(15.0)
	SimHarness.check(k.res(p, "food") > f0, "встал — снова кормит")
	f0 = k.res(p, "food")
	SimHarness.check(e.slaughter(p, pen) == EconApi.Err.OK and k.res(p, "food") == f0 + 120.0 and e.herds.heads(h) == 30,
		"Мал союу: −10 овец, +120 еды")
	SimHarness.check(e.slaughter(p, pen) == -EconApi.Err.BUSY, "не чаще раза в 60 с")


## T6: барымта — 10 всадников у неохраняемого двора, круг 6 с, уводят 5 коней; охрана в 30 м — круг стоит
func _barymta() -> void:
	print("[барымта, T6]")
	var k := EconKit.make()
	var kip := k.kipchak(KIP, 0)
	var kok := k.kokand(KOK, 0)
	var e := k.econ
	var stub := k.port as CombatPortStub
	var yard := k.build_now(kip, &"jylky", Vector2(-25, 90), 2)
	k.run_s(1.0)
	var yb := e.buildings.slot(yard)
	e.spawn_herd(kip, k.defs.herd(&"horse"), yard, 20)
	var riders := PackedInt32Array()
	for i in 10:
		riders.append(k.port.spawn(kok, e.players.team[kok], &"navkar", Vector2(-25 + (i % 5) * 2.0, 104 + (i / 5) * 2.0), 0.0))
	# охрана в 30 м: круг стоит
	var guard := k.port.spawn(kip, e.players.team[kip], &"jooker", Vector2(-25, 70), 0.0)
	k.run_s(8.0)
	SimHarness.check(e.herds.heads(e.hd.herd_at(e, yb, -1)) >= 20, "охрана хозяина рядом — круг стоит")
	stub.remove(guard)
	var c0 := k.events.head
	k.run_s(3.0)
	SimHarness.check(e.raid.raid_progress(e, yb) > 0.2 and e.raid.raid_progress(e, yb) < 0.8, "круг прогресса идёт (%.2f)" % e.raid.raid_progress(e, yb))
	k.run_s(4.0)
	var st := k.last_ev(SimEvents.Ev.HERD_STOLEN, c0)
	SimHarness.check(st >= 0 and k.events.e_c[st] == 5, "за 6 с уведено 5 коней (1 на 2 всадника)")
	var stolen := k.events.e_a[st]
	SimHarness.check(e.herds.state[e.herds.slot(stolen)] == HerdTable.State.CAPTURED, "стадо идёт за налётчиком")
	# налётчик убит — кони бегут домой
	k.port.kill(k.events.e_b[st])
	c0 = k.events.head
	k.run_s(30.0)
	SimHarness.check(k.count_ev(SimEvents.Ev.HERD_RETURNED, c0) == 1, "налётчик убит — табун вернулся (HERD_RETURNED)")
	SimHarness.check(k.count_ev(SimEvents.Ev.HERD_STOLEN, c0) == 1, "пока угнанное не уведено — новой барымты нет (одна за 30 с)")
	# новый угон и увод домой: кони — в Отхону «отлар»
	var ot := k.build_now(kok, &"otxona", Vector2(60, 60))
	st = k.last_ev(SimEvents.Ev.HERD_STOLEN, c0)
	SimHarness.check(st >= 0, "второй угон")
	if st >= 0:
		var cap := k.events.e_b[st]
		var heads := k.events.e_c[st]
		k.port.move(PackedInt32Array([cap]), Vector2(60, 40), true)
		k.run_s(25.0)
		SimHarness.check(e.b_otlar[e.buildings.slot(ot)] == heads, "довёл до Отхоны — %d «отлар»" % heads)


## Барымта у коновязи ставки кыпчаков
func _post() -> void:
	print("[коновязь ставки]")
	var k := EconKit.make()
	var kip := k.kipchak(KIP, 0)
	var kok := k.kokand(KOK, 0)
	var e := k.econ
	for i in 6:
		k.port.spawn(kok, e.players.team[kok], &"navkar", KIP + Vector2(-4 + i * 2.0, 14), 0.0)
	var c0 := k.events.head
	k.run_s(8.0)
	var st := k.last_ev(SimEvents.Ev.HERD_STOLEN, c0)
	SimHarness.check(st >= 0 and k.events.e_c[st] == 3 and k.res(kip, "horse") == 3.0, "6 всадников у ставки — уведено 3 коня с коновязи")


## «Бросить» (ECONOMY §4.1): отряд отпускает угнанных коней — они сами бегут домой
func _drop() -> void:
	print("[«Бросить»]")
	var k := EconKit.make()
	var kip := k.kipchak(KIP, 0)
	var kok := k.kokand(KOK, 0)
	var e := k.econ
	var sq := k.port.spawn_squad(kok, e.players.team[kok], &"navkar", 6, KIP + Vector2(0, 16), 0.0)
	var c0 := k.events.head
	k.run_s(8.0)
	var st := k.last_ev(SimEvents.Ev.HERD_STOLEN, c0)
	SimHarness.check(st >= 0 and k.res(kip, "horse") == 3.0, "угнали 3 коня с коновязи")
	if st < 0:
		return
	var h := k.events.e_a[st]
	SimHarness.check(e.drop_loot(kip, PackedInt32Array([sq])) == 0, "чужой игрок за налётчика не бросит")
	SimHarness.check(e.drop_loot(kok, PackedInt32Array([sq])) == 1 and e.herds.state[e.herds.slot(h)] == HerdTable.State.DRIVEN,
		"«Бросить» (отряд) — стадо отпущено")
	k.port.move(PackedInt32Array([sq]), KIP + Vector2(0, 120), true)
	c0 = k.events.head
	k.run_s(5.0)
	SimHarness.check(k.count_ev(SimEvents.Ev.HERD_RETURNED, c0) == 1 and k.res(kip, "horse") == 6.0, "кони прибежали домой")


## T1, T2: вода — 9-е поле на тўғоне с 8 местами — «лалми»; тўғон сломан — через 20 с поля 25%
func _water() -> void:
	print("[вода, T1, T2]")
	var k := EconKit.make()
	var p := k.kokand(KOK, 0)
	var e := k.econ
	var stub := k.port as CombatPortStub
	var dam := k.build_now(p, &"togon", Vector2(90, -100))
	var w_before := k.res(p, "wood")
	var chain := e.spawn_links(p, k.b(&"aryk"), PackedVector2Array([Vector2(90, -94), Vector2(90, 30)]))
	SimHarness.check(chain > 0 and k.res(p, "wood") == w_before, "стартовый Бош ариқ карты — сразу готов и даром (spawn_links)")
	k.step()
	SimHarness.check(e.ghost_water(p, k.b(&"dala"), Vector2(70, -80)) == 1000 and e.ghost_water(p, k.b(&"dala"), Vector2(160, -80)) == 250,
		"призрак поля: у арыка — «у воды» (1000), в 70 м — «лалми» (250)")
	var fields := PackedInt32Array()
	for i in 9:
		fields.append(k.build_now(p, &"dala", Vector2(70 if i % 2 == 0 else 110, -80 + (i / 2) * 18)))
	k.step()
	var wet := 0
	for f in fields:
		wet += 1 if e.b_water[e.buildings.slot(f)] == 1000 else 0
	var last := e.buildings.slot(fields[8])
	SimHarness.check(wet == 8 and e.b_water[last] == 0, "8 мест: 8 полей у воды, 9-е — «лалми»")
	SimHarness.check(e.ghost_water(p, k.b(&"dala"), Vector2(70, 10)) == 250, "T2: призрак 10-го поля у арыка, мест нет — жёлтый «лалми»")
	var w := e.spawn_worker(p, Vector2(70, -10))
	e.assign_gather(p, PackedInt32Array([w]), fields[8])
	k.run_s(5.0)
	var ui := k.u(&"dehqon")
	var lalmi := EconWorkers.trip_model(k.defs.u_carry_milli[ui], e.wk.rate_for(ui, k.defs.u_carry_milli[ui], 30000 * 250 / 1000),
		e.wk.speed[ui], 25.0) / 1000.0
	SimHarness.check_range(lalmi, 7.4, 7.6, "лалми: 7,5 еды в минуту на работника при складе в 25 м (%.2f)" % lalmi)
	SimHarness.check(e.wk.w_mult[e.un_w[Ids.slot(w)]] == 250, "множитель поля без воды — 25%")
	var p1 := e.buildings.slot(fields[0])
	stub.test_hit_structure(dam, 1_000_000, 0)
	k.step()
	SimHarness.check(e.buildings.state[e.buildings.slot(dam)] == BuildingTable.State.RUIN, "тўғон разрушен")
	k.run_s(19.0)
	SimHarness.check(e.b_water[p1] == 1000, "19 с — ещё вода")
	k.run_s(1.5)
	SimHarness.check(e.b_water[p1] == 0 and e.net.water_at(e, Vector2(90, -40)) == 0, "через 20 с — сеть высохла: поля 25%")
	var wood := k.res(p, "wood")
	var stone := k.res(p, "stone")
	var bw := e.spawn_worker(p, Vector2(90, -80))
	SimHarness.check(e.place_site(p, k.b(&"togon"), Vector2(90, -100), 0, PackedInt32Array([bw])) == EconApi.Err.OK
		and k.res(p, "wood") == wood - 40.0 and k.res(p, "stone") == stone - 20.0, "восстановление на руинах: 40 дерева, 20 камня")
	k.run_s(20.0)
	SimHarness.check(e.buildings.state[e.buildings.slot(dam)] == BuildingTable.State.ACTIVE and e.b_water[p1] == 1000,
		"за 15 с встал — вода сразу")


## Олжо (ECONOMY §4.2): боец 4 зол. 6 еды, работник 10 + 10, здание — 30% цены золотом, ставка — 400
func _bounty() -> void:
	print("[олжо]")
	var k := EconKit.make()
	var kip := k.kipchak(KIP, 0)
	var kok := k.kokand(KOK, 1)
	var e := k.econ
	var stub := k.port as CombatPortStub
	var raider := k.port.spawn(kip, e.players.team[kip], &"chabuulchu", KOK + Vector2(30, 0), 0.0)
	var soldier := k.unit(kok, &"sarboz", KOK + Vector2(30, 5))
	var g0 := k.res(kip, "gold")
	var f0 := k.res(kip, "food")
	e.post_step(k.tick, PackedInt32Array([soldier, raider]), PackedInt32Array(), PackedInt32Array())
	SimHarness.check(k.res(kip, "gold") == g0 + 4.0 and k.res(kip, "food") == f0 + 6.0, "убит боец: +4 золота, +6 еды")
	var worker := k.workers_of(kok)[0]
	e.post_step(k.tick, PackedInt32Array([worker, raider]), PackedInt32Array(), PackedInt32Array())
	SimHarness.check(k.res(kip, "gold") == g0 + 14.0 and k.res(kip, "food") == f0 + 16.0, "убит работник: +10 и +10")
	var gk := k.res(kok, "gold")
	var killer := k.unit(kok, &"sarboz", KIP + Vector2(30, 0))
	var mal := k.unit(kip, &"jooker", KIP + Vector2(30, 4))
	e.post_step(k.tick, PackedInt32Array([mal, killer]), PackedInt32Array(), PackedInt32Array())
	SimHarness.check(k.res(kok, "gold") == gk, "оседлым олжо нет")
	var uy := k.build_now(kok, &"uy", KOK + Vector2(30, 30))
	g0 = k.res(kip, "gold")
	stub.test_hit_structure(uy, 1_000_000, raider)
	k.step()
	SimHarness.check(k.res(kip, "gold") == g0 + 30.0, "разрушен Уй (80 + 20) — 30 золота")
	stub.test_hit_structure(e.players.hq_b[kok], 10_000_000, raider)
	k.step()
	SimHarness.check(k.res(kip, "gold") == g0 + 430.0, "разрушена ставка — 400 золота")
