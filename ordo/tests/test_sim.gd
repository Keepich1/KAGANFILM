extends SceneTree
## Проверка ядра боя без графики:
##   godot --headless --path ordo --script res://tests/test_sim.gd
## 1) детерминизм: одно зерно → одна контрольная сумма через 40 с;
## 2) сценарий: залпы есть, натиск доходит, Коканд бежит, потери разумные;
## 3) скорость: шаг симуляции для 1000+ юнитов, мс.
## Ключ --timeline печатает раскадровку событий сценария.

var _fails := 0


func _init() -> void:
	var timeline := "--timeline" in OS.get_cmdline_user_args() or "--timeline" in OS.get_cmdline_args()
	_test_determinism()
	_test_scenario(1, timeline)
	_test_scenario(2, false)
	_test_scenario(3, false)
	_test_performance()
	print("")
	print("ИТОГ: ", "ВСЁ ПРОШЛО" if _fails == 0 else "ПРОВАЛОВ: %d" % _fails)
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _run(seed_value: int, seconds: float) -> ScenarioClash:
	var sc := ScenarioClash.new()
	sc.loop = false
	sc.start(seed_value)
	var steps := int(round(seconds / BattleSim.DT))
	for i in steps:
		sc.step()
	return sc


func _test_determinism() -> void:
	print("[детерминизм]")
	var a := _run(7, 40.0)
	var b := _run(7, 40.0)
	var c := _run(8, 40.0)
	var ca := a.sim.checksum()
	var cb := b.sim.checksum()
	var cc := c.sim.checksum()
	print("  зерно 7: %d, ещё раз: %d, зерно 8: %d" % [ca, cb, cc])
	_check(ca == cb, "одно зерно → одна контрольная сумма")
	_check(ca != cc, "другое зерно → другой бой")
	a.free()
	b.free()
	c.free()


func _test_scenario(seed_value: int, timeline: bool) -> void:
	print("[сценарий, зерно %d]" % seed_value)
	var sc := ScenarioClash.new()
	sc.loop = false
	sc.start(seed_value)
	var log := {"volley": [], "impact": [], "war_cry": [], "rout": [], "over": [], "charge": [],
		"deaths": [0, 0], "shots": 0, "hits": 0, "melee": 0, "charge_hits": 0}
	var sim := sc.sim
	sc.volley.connect(func(s, r, c, cnt): log["volley"].append([sim.time, r, cnt]))
	sc.impact.connect(func(s, p, st): log["impact"].append([sim.time, p, st]))
	sc.war_cry.connect(func(u, p): log["war_cry"].append(sim.time))
	sc.rout.connect(func(s, p): log["rout"].append([sim.time, s]))
	sc.battle_over.connect(func(w): log["over"].append([sim.time, w]))
	sc.charge_ordered.connect(func(s): log["charge"].append(sim.time))
	sc.death.connect(func(u, p): log["deaths"][sim.u_side[u]] += 1)
	sc.shot.connect(func(u, m, d, h):
		log["shots"] += 1
		if h:
			log["hits"] += 1)
	sc.melee_hit.connect(func(a, t, p): log["melee"] += 1)
	sc.charge_hit.connect(func(u, t, p): log["charge_hits"] += 1)
	var next_print := 0.0
	var k_deaths_at_impact := -1
	while sim.time < 44.0:
		sc.step()
		if timeline and sim.time >= next_print:
			next_print += 1.0
			var kc := sim.squad_centroid(sc.kip)
			var oc := sim.squad_centroid(sc.kok)
			print("  t=%5.1f  kip x=%6.1f v=%4.1f st=%5.1f mor=%5.1f alive=%2d | kok x=%6.1f mor=%5.1f alive=%3d %s" % [
				sim.time, kc.x, sim.sq_speed[sc.kip], sim.sq_stam[sc.kip], sim.sq_morale[sc.kip], sim.squad_alive(sc.kip),
				oc.x, sim.sq_morale[sc.kok], sim.squad_alive(sc.kok), "БЕГ" if sim.is_fleeing(sc.kok) else ""])
	if timeline:
		print("  клич: ", log["war_cry"])
		print("  копья наперевес: ", log["charge"])
		print("  залпы [t, шеренга, число]: ", log["volley"])
		print("  удар: ", log["impact"].map(func(e): return [snappedf(e[0], 0.01), e[2]]))
		print("  бегство: ", log["rout"])
		print("  итог: ", log["over"])
		print("  кыпчаки: якорь %s цель %s приказ %d свалка %d" % [sim.squad_anchor(sc.kip), Vector2(sim.sq_tx[sc.kip], sim.sq_tz[sc.kip]), sim.sq_order[sc.kip], sim.sq_melee[sc.kip]])
	print("  выстрелов %d, попаданий %d; ударов натиска %d; ударов в свалке %d" % [
		log["shots"], log["hits"], log["charge_hits"], log["melee"]])
	print("  потери: Коканд %d из %d, кыпчаки %d из %d" % [log["deaths"][0], sim.side_init[0], log["deaths"][1], sim.side_init[1]])
	_check(log["war_cry"].size() >= 1 and absf(log["war_cry"][0] - 3.0) < 0.5, "клич полководца около 3 с")
	_check(log["volley"].size() >= 2, "два залпа шеренгами")
	if log["volley"].size() >= 2:
		var gap: float = log["volley"][1][0] - log["volley"][0][0]
		_check(gap > 1.3 and gap < 2.4, "вторая шеренга через 1.5–2 с (%.2f)" % gap)
	_check(log["impact"].size() >= 1 and log["impact"][0][0] > 10.0 and log["impact"][0][0] < 16.5,
		"натиск доходит в 10–16 с")
	_check(log["rout"].size() >= 1 and log["rout"][0][1] == sc.kok, "Коканд бежит")
	_check(log["over"].size() >= 1 and log["over"][0][1] == 1, "победа кыпчаков")
	_check(log["deaths"][0] >= 15 and log["deaths"][0] <= 85, "потери Коканда разумные (15–85)")
	_check(log["deaths"][1] >= 3 and log["deaths"][1] <= 30, "потери кыпчаков разумные (3–30)")
	sc.free()


func _test_performance() -> void:
	print("[скорость]")
	var sim := BattleSim.new(3)
	# 6 отрядов по 100 с каждой стороны, сходятся в свалку
	var squads_a: Array[int] = []
	var squads_b: Array[int] = []
	for k in 6:
		squads_a.append(sim.add_squad(0, "sarboz" if k % 2 == 0 else "nayzachi", 100,
			Vector2(60.0, -150.0 + k * 55.0), -PI / 2, BattleSim.Formation.LINE, 50, "yuzboshi"))
		squads_b.append(sim.add_squad(1, "sayisker" if k % 2 == 0 else "jooker", 100,
			Vector2(-20.0, -150.0 + k * 55.0), PI / 2, BattleSim.Formation.LINE, 50, "juz_bashy"))
	sim.add_general(1, "kolbashchy", Vector2(-40.0, 0.0), PI / 2)
	for k in 6:
		sim.order_attack(squads_b[k], squads_a[k], BattleSim.Gait.RUN)
		sim.allow_charge(squads_b[k])
		sim.set_fire(squads_a[k], squads_b[k], 70.0)
	print("  юнитов: %d" % sim.n)
	var t0 := Time.get_ticks_usec()
	var steps := 300
	var worst := 0
	for i in steps:
		var s0 := Time.get_ticks_usec()
		sim.step()
		worst = maxi(worst, Time.get_ticks_usec() - s0)
	var avg := float(Time.get_ticks_usec() - t0) / steps / 1000.0
	print("  шаг: в среднем %.2f мс, худший %.2f мс (10 с боя, живых: %d)" % [avg, worst / 1000.0, sim.side_alive(0) + sim.side_alive(1)])
	_check(avg < 33.3, "шаг укладывается в 1/30 с")
