extends SceneTree
## Көч (ARCHITECTURE §15 ECON; ECONOMY §3.6; ТЗ 5.4): godot --headless --path ordo --script res://tests/test_econ_nomad.gd
## свернуть лагерь (15 с) → население 0, арбы с грузом → развернуть по кольцу → население и стада вернулись;
## убитая арба — постройка пропала; Кен и Коканд не сворачиваются.

const KIP := Vector2(-60, 20)


func _init() -> void:
	var k := EconKit.make()
	var p := k.kipchak(KIP, 2)
	var e := k.econ
	var boz := PackedInt32Array()
	for i in 3:
		boz.append(k.build_now(p, &"boz", KIP + Vector2(-30 + i * 30, -36)))
	var koroo := e.players.hq_b[p]
	koroo = k.build_now(p, &"koroo", KIP + Vector2(-50, 40))
	var yard := k.build_now(p, &"jylky", KIP + Vector2(40, 60), 2)
	var ken := k.build_now(p, &"ken", KIP + Vector2(60, -20))
	k.run_s(1.0)
	var cap0 := e.players.pop_cap[p]
	var horses0 := k.res(p, "horse")
	SimHarness.check(cap0 == 55 and horses0 == 6.0, "лагерь: население 55 (25 + 3 × 10), 6 коней")
	SimHarness.check(e.pack(p, ken) == -EconApi.Err.NOT_ALLOWED, "Кен не сворачивается")
	var hq := e.players.hq_b[p]
	var c0 := k.events.head
	SimHarness.check(e.pack_all(p, hq) == EconApi.Err.OK, "свернуть весь лагерь")
	k.step()
	SimHarness.check(e.players.pop_cap[p] == 0, "население сразу 0")
	k.run_s(15.0)
	var packed := 0
	for b in e.buildings.hw:
		if e.buildings.state[b] == BuildingTable.State.PACKED:
			packed += 1
	var arbas := PackedInt32Array()
	for s in e.un_cargo.size():
		if e.un_cargo[s] > 0 and e.un_gen[s] != 0:
			arbas.append(Ids.make(Ids.Kind.UNIT, s, e.un_gen[s]))
	SimHarness.check(packed == 6 and arbas.size() == 7 and k.count_ev(SimEvents.Ev.PACKED, c0) == 6,
		"через 15 с: 6 построек в арбах, арб 7 (ставка — 2)")
	SimHarness.check(e.players.hq_b[p] == 0 and e.has_hq(p), "ставка в арбе: hq_b = 0, но игрок жив")
	SimHarness.check(e.arba_cargo(arbas[0]) != 0 and e.buildings.valid(e.arba_cargo(arbas[0])), "arba_cargo → постройка")
	SimHarness.check(e.players.pop_used[p] == 2, "арбы мест не занимают")
	SimHarness.check(k.nav.check_place(p, k.b(&"boz"), KIP + Vector2(0, -36), 0) == NavApi.Why.OK, "место лагеря свободно (штампы сняты)")
	# развернуть в 120 м
	var to := KIP + Vector2(0, -120)
	c0 = k.events.head
	SimHarness.check(e.unpack(p, arbas, to) == EconApi.Err.OK, "развернуть у новой стоянки")
	k.run_s(80.0)
	var active := 0
	for b in e.buildings.hw:
		if e.buildings.state[b] == BuildingTable.State.ACTIVE and e.buildings.owner[b] == p:
			active += 1
	SimHarness.check(active == 7 and k.count_ev(SimEvents.Ev.UNPACKED, c0) == 6, "все встали (UNPACKED)")
	SimHarness.check(e.players.pop_cap[p] == cap0, "население вернулось: %d" % e.players.pop_cap[p])
	var hb := e.buildings.slot(e.players.hq_b[p]) if e.buildings.valid(e.players.hq_b[p]) else -1
	SimHarness.check(hb >= 0 and Vector2(e.buildings.x[hb], e.buildings.z[hb]).distance_to(to) < 4.0, "ставка — в центре новой стоянки")
	var kb := e.buildings.slot(koroo)
	var kh := e.hd.herd_at(e, kb, -1)
	SimHarness.check(kh >= 0 and e.herds.state[kh] == HerdTable.State.PEN and e.herds.heads(kh) == 40
		and Vector2(e.herds.x[kh], e.herds.z[kh]).distance_to(Vector2(e.buildings.x[kb], e.buildings.z[kb])) < 0.1,
		"отара пришла с короо и пасётся")
	SimHarness.check(k.res(p, "horse") >= horses0, "кони целы")
	var left := 0
	for s in e.un_cargo.size():
		if e.un_cargo[s] > 0 and e.un_gen[s] != 0:
			left += 1
	SimHarness.check(left == 0, "арбы исчезли")
	# убитая арба
	e.pack(p, boz[0])
	k.run_s(16.0)
	var ar := PackedInt32Array()
	for s in e.un_cargo.size():
		if e.un_cargo[s] > 0 and e.un_gen[s] != 0:
			ar.append(Ids.make(Ids.Kind.UNIT, s, e.un_gen[s]))
	c0 = k.events.head
	k.port.kill(ar[0])
	k.run_s(1.0)
	SimHarness.check(not e.buildings.valid(boz[0]) and k.count_ev(SimEvents.Ev.BUILDING_DESTROYED, c0) == 1, "арба убита — юрта пропала")
	SimHarness.check(e.players.pop_cap[p] == cap0 - 10, "население −10")
	# Коканд не кочует
	var kok := k.kokand(Vector2(150, 0), 0, 0)
	SimHarness.check(e.pack(kok, e.players.hq_b[kok]) == -EconApi.Err.NOT_ALLOWED, "Коканд не сворачивается")
	SimHarness.finish(self)
