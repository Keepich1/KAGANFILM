extends SceneTree
## Замер «Города» под нагрузкой (ARCHITECTURE §16, §15 GAME): 600 работников + 300 бойцов + 200 построек +
## 100 звеньев стен, 60 с; ИИ-кыпчаки с базой и защитой; каждые 10 с один отряд из 30 идёт через город
## (~100 юнитов в движении); замер — после 3 с разгона. Печатает среднее / p99 / худшее по системам такта
## (GameSim.Ph) и проваливает тест выше целей §16 по средним: ядро ≤ 3 мс, экономика ≤ 1 мс, пути ≤ 2 мс, ИИ ≤ 0.3 мс,
## приказы + победа + сумма ≤ 0.2 мс, всё ≤ 6.5 мс. Берёт настоящие реализации, если они уже в проекте;
## на заглушках числа ядра, путей и экономики — только порядок величины.
##   godot --headless --path ordo --script res://tests/test_perf_city.gd


class Prof:
	var cur := PackedInt32Array()
	var rows: Array[PackedInt32Array] = []
	var _last := 0

	func _init() -> void:
		cur.resize(GameSim.Ph.COUNT)
		for i in GameSim.Ph.COUNT:
			rows.append(PackedInt32Array())

	func begin() -> void:
		_last = Time.get_ticks_usec()

	func mark(ph: int) -> void:
		var now := Time.get_ticks_usec()
		rows[ph].append(now - _last)
		_last = now


const SECONDS := 60


func _init() -> void:
	var g := GameSim.new()
	g.setup(MapValley.MAP, SimHarness.default_players(), 13)
	print("реализации: порт %s, навигация %s, экономика %s" % [_cls(g.port), _cls(g.nav), _cls(g.econ)])
	var squads := _populate(g)
	var q := g.query as GameQueryImpl
	var n0 := q.units_of(0).size()
	var nb := 0
	for b in g.econ.buildings.hw:
		if g.econ.buildings.owner[b] == 0:
			nb += 1
	print("Коканд: юнитов %d, построек и звеньев %d; кыпчаки-ИИ: юнитов %d" % [n0, nb, q.units_of(1).size()])
	SimHarness.check(n0 >= 900 and nb >= 300, "нагрузка набрана")
	# разгон 3 с без замера: первые приказы (GATHER на 594 работника), первые пути
	for t in 90:
		g.step()
	var prof := Prof.new()
	g.prof = prof
	var k := 0
	for t in SECONDS * 30:
		if g.tick % 300 == 0 and not squads.is_empty():
			var s := squads[k % squads.size()]
			var to := q.unit_pos(s) + (Vector2(40, 0) if k % 2 == 0 else Vector2(-40, 0))
			g.submit(0, SimCmd.move(PackedInt32Array([s]), to))
			k += 1
		prof.begin()
		g.step()
	_report(prof)
	SimHarness.finish(self)


func _cls(o: Object) -> String:
	return (o.get_script() as Script).get_global_name()


## Город Коканда: 594 работника сеткой (на работу — к деревьям и жилам), 10 отрядов по 30, 200 домов
## по сетке у ставки, 100 звеньев пахса девора по кругу
func _populate(g: GameSim) -> PackedInt32Array:
	var defs := g.defs
	var econ := g.econ
	var hq := Vector2(184, 56)
	var ws := PackedInt32Array()
	for i in 594:
		ws.append(econ.spawn_worker(0, hq + Vector2(-90 + (i % 33) * 3.0, -60 + (i / 33) * 3.0)))
	var squads := PackedInt32Array()
	for i in 10:
		squads.append(g.port.spawn_squad(0, 0, &"nayzachi" if i % 2 == 0 else &"sarboz", 30,
			Vector2(60 + (i % 5) * 18.0, -20 + (i / 5) * 30.0), PI * 0.5))
	var uy := defs.building(&"uy")
	var placed := 0
	var x := -40.0
	while placed < 200 and x < 240.0:
		var z := -120.0
		while placed < 200 and z < 240.0:
			var c := g.nav.snap(uy, Vector2(x, z), 0)
			if g.nav.check_place(0, uy, c, 0) == NavApi.Why.OK:
				econ.spawn_building(0, uy, c, 0, true)
				placed += 1
			z += 12.0
		x += 12.0
	var dv := defs.building(&"devor")
	var pitch := defs.b_link_len[dv] - defs.b_link_overlap[dv]
	for i in 100:
		var c := Vector2(-20 + i * pitch, 250.0)
		econ.spawn_building(0, dv, c, 0, true)
	# работа: по 10 работников на ближайшие узлы
	var N := econ.nodes
	var k := 0
	for n in N.hw:
		if k >= ws.size():
			break
		if N.ntype[n] < 0 or Vector2(N.x[n], N.z[n]).distance_to(hq) > 260.0:
			continue
		g.submit(0, SimCmd.gather(ws.slice(k, k + 10), N.handle(n)))
		k += 10
	return squads


func _report(prof: Prof) -> void:
	var names := ["приказы", "ИИ", "экономика (pre)", "пути", "ядро", "экономика (post)", "экономика (медл.)", "победа", "сумма"]
	var avg := PackedFloat64Array()
	var total := PackedInt32Array()
	total.resize(prof.rows[0].size())
	print("")
	print("  система              ср., мс   p99, мс   худш., мс")
	for ph in GameSim.Ph.COUNT:
		var r := prof.rows[ph]
		var s := 0
		for i in r.size():
			s += r[i]
			total[i] += r[i]
		avg.append(s / 1000.0 / maxi(r.size(), 1))
		print("  %-18s %8.3f  %8.3f  %9.3f" % [names[ph], avg[ph], _p99(r), _worst(r)])
	var tsum := 0
	for v in total:
		tsum += v
	var tavg := tsum / 1000.0 / maxi(total.size(), 1)
	print("  %-18s %8.3f  %8.3f  %9.3f" % ["всего", tavg, _p99(total), _worst(total)])
	print("")
	SimHarness.check(avg[GameSim.Ph.KERNEL] <= 3.0, "ядро ≤ 3 мс (%.3f)" % avg[GameSim.Ph.KERNEL])
	var econ := avg[GameSim.Ph.ECON_PRE] + avg[GameSim.Ph.ECON_POST] + avg[GameSim.Ph.ECON_SLOW]
	SimHarness.check(econ <= 1.0, "экономика ≤ 1 мс (%.3f)" % econ)
	SimHarness.check(avg[GameSim.Ph.NAV] <= 2.0, "пути ≤ 2 мс (%.3f)" % avg[GameSim.Ph.NAV])
	SimHarness.check(avg[GameSim.Ph.AI] <= 0.3, "ИИ ≤ 0.3 мс (%.3f)" % avg[GameSim.Ph.AI])
	var game := avg[GameSim.Ph.ORDERS] + avg[GameSim.Ph.VICTORY] + avg[GameSim.Ph.CHECKSUM]
	SimHarness.check(game <= 0.2, "приказы + победа + сумма ≤ 0.2 мс (%.3f)" % game)
	SimHarness.check(tavg <= 6.5, "всё ≤ 6.5 мс (%.3f)" % tavg)


func _p99(r: PackedInt32Array) -> float:
	if r.is_empty():
		return 0.0
	var s := r.duplicate()
	s.sort()
	return s[mini(s.size() - 1, int(s.size() * 0.99))] / 1000.0


func _worst(r: PackedInt32Array) -> float:
	var w := 0
	for v in r:
		w = maxi(w, v)
	return w / 1000.0
