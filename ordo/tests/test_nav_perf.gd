extends SceneTree
## Замер службы путей (ARCHITECTURE §9.5, §16: «Paths ≤ 2 ms (4)» на такт) на городской нагрузке:
##   • карта «Долина» 256² с рельефом: город Коканда и лагерь кыпчаков (~200 построек, частокол,
##     стена с воротами, жилы), и синтетическая 400² (1,6 км) с теми же долями;
##   • за 30 с (900 тактов): ходки работников (40 пар «узел — склад», туда и обратно, ~2 за такт),
##     приказы отрядам (8 средних путей каждые 15 тактов), набеги через карту (4 длинных каждые 60
##     тактов, в том числе с проломом); стройка и разрушение: новая стройка каждые 45 тактов (40 в
##     минуту), снесённое звено стены или частокола либо дом каждые 30 тактов (набег), новая стена из
##     10 звеньев с воротами (ворота — через stamp_building) каждые 300 тактов. Тактов со штампами —
##     ~5 % (p99 их не прячет: он — 10-й худший такт из 900).
## Такт меряется целиком и вживую: штампы и снятия этого такта + service (в нём ленивое перемечивание
## графа; слои breach — по первому запросу с проломом). Время такта — часы потока без ожидания
## процессора (T.net_us). Прогон повторяется RUNS раз с тем же городом и той же нагрузкой (результаты
## обязаны совпасть), по каждому такту берётся меньшее из прогонов — шум чужих процессов (вытеснение
## гипервизором) так отсекается, а работа такта — нет. Провал — если среднее > 2 мс или p99 > 4 мс.
##   godot --headless --path ordo --script res://tests/test_nav_perf.gd

const T := preload("res://tests/test_nav.gd")
const TICKS := 900
const RUNS := 3


func _init() -> void:
	_run("Долина 256² (рельеф)", {}, 1.0)
	_run("синтетика 400² (1,6 км)", T.MAP_400, 1.6)
	SimHarness.finish(self)


func _run(title: String, info: Dictionary, scale: float) -> void:
	print("[%s]" % title)
	var runs: Array[Dictionary] = []
	for r in RUNS:
		var k := T.make(info)
		var nav: NavGrid = k["nav"]
		var city := _city(k, scale)
		nav.sync_for_paths()
		runs.append(_workload(k, city, scale))
	var est := PackedFloat32Array()
	est.resize(TICKS)
	for tick in TICKS:
		var m := INF
		for r in runs:
			m = minf(m, (r["ticks"] as PackedFloat32Array)[tick])
		est[tick] = m
	var live := runs[0]
	var same := true
	for r in runs:
		same = same and r["sum"] == live["sum"] and r["log"] == live["log"]
	var avg := _avg(est)
	var p99 := _p99(est)
	var st_ticks: PackedInt32Array = live["stamp_ticks"]
	var st := PackedFloat32Array()
	for tick in st_ticks:
		st.append(est[tick])
	var st_sorted := st.duplicate()
	st_sorted.sort()
	var cpu := 0.0
	for r in runs:
		cpu += float(r["cpu"]) / RUNS
	print("  запросов: %d (ходки %d, отряды %d, набеги %d), из кэша %d; пролом %d, нет прохода %d" % [
		live["n"], live["n_work"], live["n_squad"], live["n_raid"], live["hits"], live["breach"], live["no_route"]])
	print("  штампов %d, снятий %d; тактов с ними %d из %d (%.1f %%): такт среднее %.2f, медиана %.2f, макс. %.2f мс" % [
		live["stamps"], live["unstamps"], st.size(), TICKS, 100.0 * st.size() / TICKS, _avg(st),
		st_sorted[st_sorted.size() / 2] if st.size() > 0 else 0.0, st_sorted[st_sorted.size() - 1] if st.size() > 0 else 0.0])
	print("  перемечиваний walk %d (полных пересчётов компонент %d, областей в проверках разрыва %d)" % [
		live["flushes"], live["full"], live["split"]])
	var one := live["ticks"] as PackedFloat32Array
	print("  один прогон (без отсева): среднее %.3f, p99 %.2f, макс. %.2f мс; проц. (schedstat) среднее %.3f мс" % [
		_avg(one), _p99(one), _max(one), cpu])
	SimHarness.check(same, "%d прогона совпали (сумма %d, журнал путей %d)" % [RUNS, live["sum"], hash(live["log"])])
	SimHarness.check(avg <= 2.0, "пути за такт (вживую, меньшее из %d): среднее %.3f мс ≤ 2" % [RUNS, avg])
	SimHarness.check(p99 <= 4.0, "p99 %.2f мс ≤ 4 (такты со штампами внутри; макс. %.2f мс)" % [p99, _max(est)])


## Город Коканда, лагерь кыпчаков, жилы, частокол вокруг короо, стена с воротами у города.
## Ответ: {links: звенья стены и частокола, houses: постройки}
func _city(k: Dictionary, scale: float) -> Dictionary:
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
	var houses := PackedInt32Array()
	var tries := 0
	while houses.size() < 200 and tries < 4000:
		tries += 1
		var p := houses.size() % 2
		var ids: Array = kok_ids if p == 0 else kip_ids
		var bt := d.building(ids[rng.randi() % ids.size()])
		var rq := rng.randi() % 4
		var base := kok if p == 0 else kip
		var at := nav.snap(bt, base + Vector2(rng.randf_range(-140, 140), rng.randf_range(-140, 140)), rq)
		if nav.check_place(p, bt, at, rq) == NavApi.Why.OK:
			houses.append(econ.spawn_building(p, bt, at, rq))
	# частокол вокруг загона кыпчаков и стена с воротами перед городом
	var links := T.wall(k, 1, &"chep", T.ring_pts(kip + Vector2(-55, 45), 22.0, 10))
	links.append_array(T.wall(k, 0, &"devor", PackedVector2Array([kok + Vector2(-170, -120), kok + Vector2(-170, 120)])))
	T.gate(k, 0, &"darvoza", kok + Vector2(-170, 0))
	return {"links": links, "houses": houses}


func _workload(k: Dictionary, city: Dictionary, scale: float) -> Dictionary:
	var nav: NavGrid = k["nav"]
	var econ: EconStub = k["econ"]
	var d: Defs = k["defs"]
	var B := econ.buildings
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var kok := Vector2(184, 56) * scale
	var kip := Vector2(-60, 20) * scale
	var links: PackedInt32Array = (city["links"] as PackedInt32Array).duplicate()
	var houses: PackedInt32Array = (city["houses"] as PackedInt32Array).duplicate()
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
	var unstamps := 0
	var stamp_ticks := PackedInt32Array()
	var hits0 := nav.paths.cache_hits
	var breach := 0
	var no_route := 0
	var log := ""
	var fl0 := 0
	var full0 := 0
	var split0 := 0
	for t in 2:
		fl0 += nav.walk_layer(t).flushes
		full0 += nav.walk_layer(t).full_passes + nav.breach_layer(t).full_passes
		split0 += nav.walk_layer(t).split_visits + nav.breach_layer(t).split_visits
	var cpu0 := T.cpu_us()
	for tick in TICKS:
		var t0 := T.net_us()
		var stamped := false
		# стройка: дом у города или юрта у лагеря
		if tick % 45 == 20:
			var p := (tick / 45) % 2
			var bt := d.building(&"uy") if p == 0 else d.building(&"boz")
			for tr in 50:
				var at := nav.snap(bt, (kok if p == 0 else kip) + Vector2(rng.randf_range(-160, 160), rng.randf_range(-160, 160)), 0)
				if nav.check_place(p, bt, at, 0) == NavApi.Why.OK:
					houses.append(econ.spawn_building(p, bt, at, 0, false))
					stamps += 1
					stamped = true
					break
		# набег: снесено звено стены или частокола (чаще) либо постройка
		if tick % 30 == 5:
			var from_links := (tick / 30) % 3 != 2 or houses.is_empty()
			var pool_n := links.size() if from_links else houses.size()
			if pool_n > 0:
				var i := rng.randi() % pool_n
				var h := links[i] if from_links else houses[i]
				if from_links:
					links.remove_at(i)
				else:
					houses.remove_at(i)
				nav.unstamp(h)
				B.release(B.slot(h))
				unstamps += 1
				stamped = true
		# новая стена из 10 звеньев с воротами посередине (ворота — stamp_building, как у EconStub)
		if tick % 300 == 150:
			var p := (tick / 300) % 2
			var c := (kok if p == 0 else kip) + Vector2(rng.randf_range(-120, 120), rng.randf_range(-120, 120))
			var ang := rng.randf() * TAU
			var dir := Vector2(cos(ang), sin(ang))
			var wl := T.wall(k, p, &"devor" if p == 0 else &"chep", PackedVector2Array([c - dir * 16.0, c + dir * 16.0]))
			stamps += wl.size()
			var gt := d.building(&"darvoza" if p == 0 else &"darbaza")
			var s := nav.snap_on_wall(p, gt, c)
			if int(s["why"]) == NavApi.Why.OK:
				for rh in (s["removes"] as PackedInt32Array):
					nav.unstamp(rh)
					B.release(B.slot(rh))
					wl.remove_at(wl.find(rh))
					unstamps += 1
				var rq := posmod(roundi(float(s["rot"]) / (PI / 2.0)), 4)
				econ.spawn_building(p, gt, nav.snap(gt, s["center"], rq), rq, false)
				stamps += 1
			links.append_array(wl)
			stamped = true
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
		nav.service(tick)
		ticks[tick] = (T.net_us() - t0) / 1000.0
		if stamped:
			stamp_ticks.append(tick)
		var done: Array = []
		for tk: int in tickets:
			if nav.result(tk) != null:
				done.append(tk)
		for tk: int in done:
			var cl: int = tickets[tk]
			n[cl] += 1
			var r := nav.result(tk)
			if r.breach_b != 0:
				breach += 1
			if r.no_route:
				no_route += 1
			log += "%d:%d/%d/%s;" % [tk, r.pts.size(), r.breach_b, r.no_route]
			nav.release(tk)
			tickets.erase(tk)
	var cpu := (T.cpu_us() - cpu0) / 1000.0
	var fl := -fl0
	var full := -full0
	var split := -split0
	for t in 2:
		fl += nav.walk_layer(t).flushes
		full += nav.walk_layer(t).full_passes + nav.breach_layer(t).full_passes
		split += nav.walk_layer(t).split_visits + nav.breach_layer(t).split_visits
	return {"ticks": ticks, "cpu": cpu / TICKS, "n": n[0] + n[1] + n[2], "n_work": n[0], "n_squad": n[1],
		"n_raid": n[2], "hits": nav.paths.cache_hits - hits0, "stamps": stamps, "unstamps": unstamps,
		"stamp_ticks": stamp_ticks, "breach": breach, "no_route": no_route, "sum": nav.checksum(), "log": log,
		"flushes": fl, "full": full, "split": split}


func _avg(a: PackedFloat32Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / maxf(a.size(), 1)


func _p99(a: PackedFloat32Array) -> float:
	var b := a.duplicate()
	b.sort()
	return b[int(b.size() * 0.99) - 1] if b.size() > 0 else 0.0


func _max(a: PackedFloat32Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, v)
	return m
