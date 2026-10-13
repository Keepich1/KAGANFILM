extends SceneTree
## Добыча (ARCHITECTURE §15 ECON; ECONOMY §1.1): godot --headless --path ordo --script res://tests/test_econ_gather.gd
## 1) доход в пределах ±10% от модели ходки, посчитанной из Defs (ноша, эффективная скорость, бег, путь);
## 2) дальний склад — меньше (−15% на каждые лишние 20 м по модели); Кен — золото +50%;
## 3) дерево: TREE_FELLED / NODE_DEPLETED, работник переходит к соседнему дереву того же вида;
## 4) поле у воды/лалми и мельница — в test_econ_herds_fields; здесь — 500 работников ≤ 1 мс на такт.

const HQ := Vector2(90, 0)


func _init() -> void:
	_rate("stone", Vector2(90, 50), 3)
	_rate("wood", Vector2(60, 40), 2)
	_far_vs_near()
	_ken()
	_trees()
	_idle()
	_perf()
	SimHarness.finish(self)


## Доход n работников с узла против модели ходки (каждому — свой путь от его места до склада)
func _rate(res_id: String, at: Vector2, n: int) -> void:
	print("[доход: %s, %d работника]" % [res_id, n])
	var k := EconKit.make()
	var p := k.kokand(HQ, n)
	var e := k.econ
	var nt := k.defs.node(&"stone") if res_id == "stone" else k.defs.node(&"tree_poplar")
	var node := e.spawn_node(nt, at, 9_000_000)
	if res_id == "wood":
		e.nodes.workers_max[e.nodes.slot(node)] = 8
	SimHarness.check(e.assign_gather(p, k.workers_of(p), node) == EconApi.Err.OK, "приказ «добывать»")
	k.run_s(60.0)
	var got := _measure(k, p, 400.0)
	var model := 0.0
	var ui := k.u(&"dehqon")
	var r := k.r(StringName(res_id))
	for u_h in k.workers_of(p):
		var w := e.un_w[Ids.slot(u_h)]
		var spot := e.wk._node_spot_pos(e, e.nodes.slot(node), e.wk.w_spot[w])
		var drop := e.buildings.slot(e.players.hq_b[p])
		var d := spot.distance_to(e.edge_point(drop, spot, 1.0))
		model += EconWorkers.trip_model(k.defs.u_carry_milli[ui], e.wk.raw[ui * e.R + r], e.wk.speed[ui], d) / 1000.0
	print("  в минуту: %.1f, модель %.1f" % [got, model])
	SimHarness.check_range(got / model, 0.9, 1.1, "%s: доход / модель" % res_id)
	# при складе в 25 м модель даёт эффективную скорость UnitEcon.gather (ECONOMY §1.1)
	var eff := EconWorkers.trip_model(k.defs.u_carry_milli[ui], e.wk.raw[ui * e.R + r], e.wk.speed[ui], 25.0)
	SimHarness.check_range(eff / (k.defs.u_gather[ui * e.R + r] * 60.0), 0.97, 1.03, "%s: в 25 м — скорость из UnitEcon" % res_id)


## Точный доход (в минуту): у каждого работника — сданное между первой и последней сдачей за s секунд
func _measure(k: EconKit, p: int, s: float) -> float:
	var e := k.econ
	var ws := PackedInt32Array()
	for u_h in k.workers_of(p):
		ws.append(e.un_w[Ids.slot(u_h)])
	var first := PackedInt32Array()
	var last := PackedInt32Array()
	var amount := PackedInt32Array()
	var prev := PackedInt32Array()
	for w in ws:
		first.append(-1)
		last.append(-1)
		amount.append(0)
		prev.append(e.wk.w_carry[w])
	for t in roundi(s * 30.0):
		k.step()
		for i in ws.size():
			var w := ws[i]
			var c := e.wk.w_carry[w]
			if c < prev[i] and e.wk.w_job[w] != EconWorkers.Job.TO_DROP:
				# сдал prev[i] на этом такте
				if first[i] < 0:
					first[i] = k.tick
				else:
					amount[i] += prev[i]
					last[i] = k.tick
			prev[i] = c
	var total := 0.0
	for i in ws.size():
		if last[i] > first[i]:
			total += float(amount[i]) / 1000.0 / float(last[i] - first[i]) * 1800.0
	return total


func _far_vs_near() -> void:
	print("[дальний склад]")
	var k := EconKit.make()
	var e := k.econ
	var ui := k.u(&"dehqon")
	var r := k.r(&"wood")
	var near := EconWorkers.trip_model(k.defs.u_carry_milli[ui], e.wk.raw[ui * e.R + r], e.wk.speed[ui], 25.0)
	var far := EconWorkers.trip_model(k.defs.u_carry_milli[ui], e.wk.raw[ui * e.R + r], e.wk.speed[ui], 45.0)
	print("  25 м: %.1f, 45 м: %.1f в минуту" % [near / 1000.0, far / 1000.0])
	SimHarness.check_range(far / near, 0.82, 0.88, "каждые лишние 20 м — около −15% (ECONOMY §1.1)")


func _ken() -> void:
	print("[Кен: золото +50%]")
	var rates := []
	for with_ken in [false, true]:
		var k := EconKit.make()
		var p := k.kipchak(Vector2(-60, 20), 3)
		var e := k.econ
		var gold := e.spawn_node(k.defs.node(&"gold"), Vector2(-60, 70), 9_000_000)
		if with_ken:
			k.build_now(p, &"ken", Vector2(-60, 56))
		else:
			k.build_now(p, &"boz", Vector2(-80, 56))       # не склад: носят в ставку — сравнение по модели
		e.assign_gather(p, k.workers_of(p), gold)
		k.run_s(40.0)
		var got := _measure(k, p, 300.0)
		var model := 0.0
		var ui := k.u(&"malchy")
		for u_h in k.workers_of(p):
			var w := e.un_w[Ids.slot(u_h)]
			var spot := e.wk._node_spot_pos(e, e.nodes.slot(gold), e.wk.w_spot[w])
			var drop := e.buildings.slot(e.wk.w_drop[w]) if e.buildings.valid(e.wk.w_drop[w]) else e.buildings.slot(e.players.hq_b[p])
			for b in e.drops_of(p):
				if e.rect_dist2(b, spot) < e.rect_dist2(drop, spot):
					drop = b
			var d := spot.distance_to(e.edge_point(drop, spot, 1.0))
			var eff := k.defs.u_gather[ui * e.R + k.r(&"gold")] * 60 * (1500 if with_ken else 1000) / 1000
			model += EconWorkers.trip_model(k.defs.u_carry_milli[ui], e.wk.rate_for(ui, k.defs.u_carry_milli[ui], eff), e.wk.speed[ui], d) / 1000.0
		print("  %s: %.1f в минуту, модель %.1f" % ["с Кеном" if with_ken else "без Кена", got, model])
		SimHarness.check_range(got / model, 0.9, 1.1, "золото %s: доход / модель" % ("у Кена" if with_ken else "без Кена"))
		rates.append(got)
	SimHarness.check(rates[1] > rates[0] * 1.5, "Кен у жилы: склад ближе и +50% добычи")


func _trees() -> void:
	print("[деревья]")
	var k := EconKit.make()
	var p := k.kokand(HQ, 2)
	var e := k.econ
	var t1 := e.spawn_node(k.defs.node(&"tree_poplar"), Vector2(70, 30), -1, ScatterData.ref(0, 7))
	var t2 := e.spawn_node(k.defs.node(&"tree_poplar"), Vector2(64, 36), -1, ScatterData.ref(0, 8))
	e.assign_gather(p, k.workers_of(p), t1)
	var c0 := k.events.head
	k.run_s(200.0)
	var fell := k.last_ev(SimEvents.Ev.TREE_FELLED, c0)
	SimHarness.check(fell >= 0 and k.events.e_a[fell] == t1 and k.events.e_b[fell] == ScatterData.ref(0, 7),
		"TREE_FELLED с узлом и деревом WorldScatter (scatter_ref)")
	SimHarness.check(not e.nodes.valid(t1), "срубленное дерево — узел освобождён")
	var on_t2 := 0
	for u_h in k.workers_of(p):
		if e.wk.w_target[e.un_w[Ids.slot(u_h)]] == t2:
			on_t2 += 1
	SimHarness.check(on_t2 > 0 or not e.nodes.valid(t2), "работники перешли к соседнему тополю")
	SimHarness.check(k.res(p, "wood") >= 400.0 + 100.0, "сто дерева с тополя дошли до склада (%.0f)" % k.res(p, "wood"))


func _idle() -> void:
	print("[свободные работники]")
	var k := EconKit.make()
	var p := k.kokand(HQ, 6)
	var e := k.econ
	SimHarness.check(e.idle_workers(p).size() == 6, "6 деҳқонов свободны")
	var st := e.spawn_node(k.defs.node(&"stone"), Vector2(130, 0))
	var two := PackedInt32Array([k.workers_of(p)[0], k.workers_of(p)[1]])
	e.assign_gather(p, two, st)
	SimHarness.check(e.idle_workers(p).size() == 4 and e.worker_job(two[0]) == EconWorkers.Job.TO_NODE, "двое ушли к жиле")
	e.release_units(PackedInt32Array([two[0]]))
	SimHarness.check(e.worker_job(two[0]) == EconWorkers.Job.IDLE, "боевой приказ снял с работы")
	SimHarness.check(e.node_near(1 << k.r(&"stone"), Vector2(120, 4), 30.0) == st, "node_near: ближайшая жила камня")


## 500 работников на 50 жилах: экономика ≤ 1 мс на такт (ARCHITECTURE §16)
func _perf() -> void:
	print("[500 работников]")
	var k := EconKit.make()
	var e := k.econ
	var p := k.kokand(Vector2(0, 0), 0)
	var p2 := k.kokand(Vector2(200, 200), 0, 0)
	var nodes := PackedInt32Array()
	for i in 50:
		var a := Vector2(-200 + (i % 10) * 45.0, -200 + (i / 10) * 45.0)
		nodes.append(e.spawn_node(k.defs.node(&"stone") if i % 2 == 0 else k.defs.node(&"gold"), a, 90_000_000))
		if i % 10 == 0:
			k.build_now(p, &"ombor", a + Vector2(0, 16))
	for i in 500:
		var n := nodes[i % 50]
		var at := Vector2(e.nodes.x[e.nodes.slot(n)], e.nodes.z[e.nodes.slot(n)]) + Vector2(3, 8)
		var w := e.spawn_worker(p if i < 400 else p2, at)
		e.assign_gather(p if i < 400 else p2, PackedInt32Array([w]), n)
	k.run_s(70.0)
	var t_econ := 0
	var worst := 0
	var steps := 600
	for i in steps:
		k.tick += 1
		k.events.tick = k.tick
		var t0 := _now_us()
		e.pre_step(k.tick)
		var t1 := _now_us()
		k.nav.service(k.tick)
		k.port.step()
		var deaths := k.port.take_deaths()
		var hits := k.port.take_structure_hits()
		var arr := k.port.take_arrivals()
		var t2 := _now_us()
		e.post_step(k.tick, deaths, hits, arr)
		if k.tick % 30 == 0:
			e.slow_step(k.tick)
		if k.tick % 150 == 75:
			e.fields_step(k.tick)
		var t3 := _now_us()
		var dt := (t1 - t0) + (t3 - t2)
		t_econ += dt
		worst = maxi(worst, dt)
	var avg := t_econ / float(steps) / 1000.0
	print("  экономика: %.3f мс в среднем, худший такт %.2f мс; камень %.0f, золото %.0f" % [avg, worst / 1000.0,
		k.res(p, "stone"), k.res(p, "gold")])
	SimHarness.check(avg <= 1.0, "500 работников: ≤ 1 мс на такт в среднем (%.3f)" % avg)
	SimHarness.check(k.res(p, "stone") > 250.0 + 1000.0, "добыча идёт")


## Процессорное время этого потока, мкс (/proc/thread-self/schedstat, как bench_battle) — чужие процессы
## на машине не портят замер; без него — часы
var _cpu_file := true


func _now_us() -> int:
	if _cpu_file:
		var f := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
		if f:
			return int(f.get_line().split(" ")[0]) / 1000
		_cpu_file = false
	return Time.get_ticks_usec()
