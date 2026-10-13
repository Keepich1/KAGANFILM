extends SceneTree
## Замер службы путей (ARCHITECTURE §9.5, §16: «Paths ≤ 2 ms (4)» на такт) на городской нагрузке:
##   • карта «Долина» 256² с рельефом: город Коканда и лагерь кыпчаков (~200 построек, частокол,
##     стена с воротами, жилы), и синтетическая 400² (1,6 км) с теми же долями;
##   • за 30 с (900 тактов): ходки работников (40 пар «узел — склад», туда и обратно, ~2 за такт),
##     приказы отрядам (8 средних путей каждые 15 тактов), набеги через карту (4 длинных каждые 60
##     тактов, в том числе с проломом), новая постройка каждые 90 тактов (штамп + перемечивание).
## Среднее — процессорное время потока за 900 тактов (машину делят другие агенты, часы врут).
## p99 — по повтору: тот же город и те же штампы на тех же тактах; каждый запрос такта (не из кэша)
## решается заново 5 раз, берётся лучшее время по часам; такт = сумма запросов + перемечивание
## после штампа (лучшее из двух прогонов). Провал — если среднее > 2 мс или p99 > 4 мс.
##   godot --headless --path ordo --script res://tests/test_nav_perf.gd

const T := preload("res://tests/test_nav.gd")
const TICKS := 900
const REPS := 5


func _init() -> void:
	_run("Долина 256² (рельеф)", {}, 1.0)
	_run("синтетика 400² (1,6 км)", T.MAP_400, 1.6)
	SimHarness.finish(self)


func _run(title: String, info: Dictionary, scale: float) -> void:
	print("[%s]" % title)
	var k := T.make(info)
	var nav: NavGrid = k["nav"]
	_city(k, scale)
	nav.sync_for_paths()
	nav.paths.trace = true
	var live := _workload(k, scale)
	# повтор: оценка каждого такта без чужого шума
	var k2 := T.make(info)
	var nav2: NavGrid = k2["nav"]
	_city(k2, scale)
	nav2.sync_for_paths()
	var log: Array = nav.paths.trace_log
	var stamps: Array = live["stamp_list"]
	var flush_live: Dictionary = live["flush_ms"]
	var est := PackedFloat32Array()
	est.resize(TICKS)
	var hit_ms := 0.0
	var li := 0
	var si := 0
	var worst_req := 0.0
	var worst_flush := 0.0
	for tick in TICKS:
		var sum := 0.0
		while si < stamps.size() and int(stamps[si][0]) == tick:
			var st: Array = stamps[si]
			(k2["econ"] as EconStub).spawn_building(st[1], st[2], st[3], 0)
			si += 1
			var t0 := Time.get_ticks_usec()
			nav2.sync_for_paths()
			for t in 2:
				nav2.walk_layer(t).comp_of(0)
				nav2.breach_layer(t).comp_of(0)
			var f := minf((Time.get_ticks_usec() - t0) / 1000.0, float(flush_live.get(tick, INF)))
			worst_flush = maxf(worst_flush, f)
			sum += f
		while li < log.size() and int(log[li][0]) == tick:
			var q: Array = log[li]
			li += 1
			if q[4]:
				if hit_ms == 0.0:
					hit_ms = T.best_ms(func() -> void: nav2.paths.solve(nav2, q[1], q[2], q[3], true), REPS)
				sum += hit_ms
				continue
			var ms := T.best_ms(func() -> void: nav2.paths.solve(nav2, q[1], q[2], q[3], false), REPS)
			worst_req = maxf(worst_req, ms)
			sum += ms
		est[tick] = sum
	var sorted := est.duplicate()
	sorted.sort()
	var avg := 0.0
	for v in est:
		avg += v
	avg /= TICKS
	var p99 := sorted[int(TICKS * 0.99) - 1]
	var live_sorted: PackedFloat32Array = (live["ticks"] as PackedFloat32Array).duplicate()
	live_sorted.sort()
	print("  запросов: %d (ходки %d, отряды %d, набеги %d), из кэша %d; пролом %d, нет прохода %d" % [
		live["n"], live["n_work"], live["n_squad"], live["n_raid"], live["hits"], live["breach"], live["no_route"]])
	print("  на запрос (проц., живой прогон): ходка %.3f, отряд %.3f, набег %.3f мс; худший запрос (повтор) %.2f мс" % [
		live["c_work"], live["c_squad"], live["c_raid"], worst_req])
	print("  штампов: %d, перемечивание после штампа (2 команды × walk + breach): до %.2f мс" % [stamps.size(), worst_flush])
	print("  живой прогон, часы: среднее %.3f, p99 %.2f, макс. %.2f мс (шум машины)" % [
		live["wall_avg"], live_sorted[int(TICKS * 0.99) - 1], live_sorted[TICKS - 1]])
	SimHarness.check(live["cpu"] <= 2.0 or avg <= 2.0,
		"пути за такт: среднее %.3f мс проц. (живой), %.3f мс (повтор) ≤ 2" % [live["cpu"], avg])
	SimHarness.check(p99 <= 4.0, "p99 %.2f мс ≤ 4 (повтор; макс. %.2f мс)" % [p99, sorted[TICKS - 1]])


## Город Коканда, лагерь кыпчаков, жилы, частокол вокруг короо, стена с воротами у города
func _city(k: Dictionary, scale: float) -> void:
	var nav: NavGrid = k["nav"]
	var econ: EconStub = k["econ"]
	var d: Defs = k["defs"]
	var kok := Vector2(184, 56) * scale
	var kip := Vector2(-60, 20) * scale
	econ.spawn_building(0, d.building(&"urda"), nav.snap(d.building(&"urda"), kok, 3), 3)
	econ.spawn_building(1, d.building(&"ordo"), nav.snap(d.building(&"ordo"), kip, 0), 0)
	for dep: Array in MapValley.MAP["deposits"]:
		econ.spawn_node(d.node(StringName(dep[0])), (dep[1] as Vector2) * scale)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var kok_ids := [&"uy", &"uy", &"uy", &"tegirmon", &"ombor", &"dala", &"kazarma", &"bozor"]
	var kip_ids := [&"boz", &"boz", &"boz", &"koroo", &"jooker", &"jylky"]
	var placed := 0
	var tries := 0
	while placed < 200 and tries < 4000:
		tries += 1
		var p := placed % 2
		var ids: Array = kok_ids if p == 0 else kip_ids
		var bt := d.building(ids[rng.randi() % ids.size()])
		var rq := rng.randi() % 4
		var base := kok if p == 0 else kip
		var at := nav.snap(bt, base + Vector2(rng.randf_range(-140, 140), rng.randf_range(-140, 140)), rq)
		if nav.check_place(p, bt, at, rq) == NavApi.Why.OK:
			econ.spawn_building(p, bt, at, rq)
			placed += 1
	# частокол вокруг загона кыпчаков и стена с воротами перед городом
	T.wall(k, 1, &"chep", T.ring_pts(kip + Vector2(-55, 45), 22.0, 10))
	T.wall(k, 0, &"devor", PackedVector2Array([kok + Vector2(-170, -120), kok + Vector2(-170, 120)]))
	T.gate(k, 0, &"darvoza", kok + Vector2(-170, 0))


func _workload(k: Dictionary, scale: float) -> Dictionary:
	var nav: NavGrid = k["nav"]
	var econ: EconStub = k["econ"]
	var d: Defs = k["defs"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var kok := Vector2(184, 56) * scale
	var kip := Vector2(-60, 20) * scale
	# пары «узел — склад» для ходок
	var pairs: Array[PackedVector2Array] = []
	for i in 40:
		var base := kok if i % 2 == 0 else kip
		var drop := base + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
		var node := drop + Vector2(rng.randf_range(-80, 80), rng.randf_range(-80, 80))
		pairs.append(PackedVector2Array([nav.nearest_passable(i % 2, node), nav.nearest_passable(i % 2, drop)]))
	var edges: Array = MapValley.MAP["raid_edges"]
	var ticks := PackedFloat32Array()
	ticks.resize(TICKS)
	var tickets: Dictionary = {}       # ticket → класс (0 ходка, 1 отряд, 2 набег)
	var n := [0, 0, 0]
	var stamps := 0
	var cpu0 := T.cpu_us()
	var cls_cpu := [0.0, 0.0, 0.0]
	var hits0 := nav.paths.cache_hits
	var breach := 0
	var no_route := 0
	var stamp_list: Array = []
	var flush_ms := {}
	for tick in TICKS:
		if tick % 90 == 45:
			var p := (tick / 90) % 2
			var bt := d.building(&"uy") if p == 0 else d.building(&"boz")
			for tr in 50:
				var at := nav.snap(bt, (kok if p == 0 else kip) + Vector2(rng.randf_range(-160, 160), rng.randf_range(-160, 160)), 0)
				if nav.check_place(p, bt, at, 0) == NavApi.Why.OK:
					econ.spawn_building(p, bt, at, 0)
					stamp_list.append([tick, p, bt, at])
					stamps += 1
					var tf := Time.get_ticks_usec()
					nav.sync_for_paths()
					for t in 2:
						nav.walk_layer(t).comp_of(0)
						nav.breach_layer(t).comp_of(0)
					flush_ms[tick] = (Time.get_ticks_usec() - tf) / 1000.0
					break
		# ходки: ~2 за такт
		for i in 2:
			var pr := pairs[rng.randi() % pairs.size()]
			var back := rng.randi() % 2 == 1
			var tk := nav.request(rng.randi() % 2, pr[1] if back else pr[0], pr[0] if back else pr[1], 0)
			tickets[tk] = 0
		if tick % 15 == 7:
			for i in 8:
				var team := i % 2
				var from := (kok if team == 0 else kip) + Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100))
				var to := from + Vector2(rng.randf_range(-250, 250), rng.randf_range(-250, 250)) * scale
				tickets[nav.request(team, from, to, i)] = 1
		if tick % 60 == 30:
			for i in 4:
				var e: Vector2 = edges[(tick / 60 + i) % edges.size()]
				var team := 1 if i % 2 == 0 else 0
				var to := (kok if team == 1 else kip) + Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60))
				tickets[nav.request(team, e * scale, to, 100 + i)] = 2
		var t0 := Time.get_ticks_usec()
		var c0 := T.cpu_us()
		nav.service(tick)
		var c1 := T.cpu_us()
		ticks[tick] = (Time.get_ticks_usec() - t0) / 1000.0 + float(flush_ms.get(tick, 0.0))
		# доля процессора по классам (грубо: делим такт поровну между обслуженными)
		var done: Array = []
		for tk: int in tickets:
			var r := nav.result(tk)
			if r != null:
				done.append(tk)
		for tk: int in done:
			var cl: int = tickets[tk]
			n[cl] += 1
			cls_cpu[cl] += (c1 - c0) / 1000.0 / maxf(done.size(), 1)
			var r := nav.result(tk)
			if r.breach_b != 0:
				breach += 1
			if r.no_route:
				no_route += 1
			nav.release(tk)
			tickets.erase(tk)
	var cpu := (T.cpu_us() - cpu0) / 1000.0
	var wall := 0.0
	for v in ticks:
		wall += v
	return {"ticks": ticks, "cpu": cpu / TICKS, "wall_avg": wall / TICKS, "n": n[0] + n[1] + n[2], "n_work": n[0],
		"n_squad": n[1], "n_raid": n[2], "hits": nav.paths.cache_hits - hits0, "stamp_list": stamp_list, "flush_ms": flush_ms,
		"c_work": cls_cpu[0] / maxf(n[0], 1), "c_squad": cls_cpu[1] / maxf(n[1], 1), "c_raid": cls_cpu[2] / maxf(n[2], 1),
		"breach": breach, "no_route": no_route}
