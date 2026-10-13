extends SceneTree
## Замер «Города» под нагрузкой (ARCHITECTURE §16, §15 GAME): 600 работников + 300 бойцов + 200 построек +
## 100 звеньев стен, 60 с; ИИ-кыпчаки с базой и защитой; каждые 10 с один отряд из 30 идёт через город
## (~100 юнитов в движении); замер — после 3 с разгона. Печатает среднее / p99 / худшее по системам такта
## (GameSim.Ph) и проваливает тест выше целей §16 «ср. (p99)»: ядро ≤ 3 (5) мс, экономика ≤ 1 (2), пути ≤ 2 (4),
## ИИ ≤ 0.3 (1), приказы + победа + сумма ≤ 0.2, всё ≤ 6.5 (10). Берёт настоящие реализации, если они уже в проекте
## (GameSim.impl_for: --impl=stub или ORDO_IMPL=stub — заглушки); на заглушках числа ядра, путей и экономики —
## только порядок величины.
##
## Занятая машина. В шапке — loadavg и число ЦП. Фазы меряются часами (стена); кроме того, весь такт — по
## процессорному времени потока (Linux: /proc/thread-self/schedstat, как у VIEW --perf_cpu). Если стена / ЦП
## больше BUSY (чужие процессы отнимают ЦП), проверки идут по числам, делённым на это отношение, — в выводе
## помечено «поправка ×1/k». На свободной машине (k ≈ 1) проверки — по чистой стене. Итог на занятой
## машине — ориентир; ворота §16 — на свободной (I1/I3).
##   godot --headless --path ordo --script res://tests/test_perf_city.gd


class Prof:
	var cur := PackedInt32Array()
	var rows: Array[PackedInt32Array] = []
	## Процессорное время потока за такт, мкс (пусто, если schedstat нет)
	var cpu := PackedInt32Array()
	var _last := 0
	var _cpu0 := -1

	func _init() -> void:
		cur.resize(GameSim.Ph.COUNT)
		for i in GameSim.Ph.COUNT:
			rows.append(PackedInt32Array())

	func begin() -> void:
		_cpu0 = Prof.thread_cpu_usec()
		_last = Time.get_ticks_usec()

	func mark(ph: int) -> void:
		var now := Time.get_ticks_usec()
		rows[ph].append(now - _last)
		_last = now
		if ph == GameSim.Ph.CHECKSUM and _cpu0 >= 0:
			var c := Prof.thread_cpu_usec()
			if c >= 0:
				cpu.append(c - _cpu0)

	## Процессорное время этого потока, мкс; −1 — нет /proc/thread-self/schedstat
	static func thread_cpu_usec() -> int:
		var f := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
		if f == null:
			return -1
		return int(f.get_line().split(" ")[0]) / 1000


const SECONDS := 60
## Стена / ЦП выше этого — машина занята, проверки с поправкой
const BUSY := 1.25


func _init() -> void:
	print(_load_line())
	var g := GameSim.new()
	g.impl = GameSim.impl_for(OS.get_cmdline_user_args(), OS.get_environment("ORDO_IMPL"))
	g.setup(MapValley.MAP, SimHarness.default_players(), 13)
	print("реализации: ", g.impl_names())
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


## Шапка: loadavg (1, 5, 15 мин) и число ЦП — по ней видно, что замер шёл на занятой машине
func _load_line() -> String:
	var cores := OS.get_processor_count()
	var f := FileAccess.open("/proc/loadavg", FileAccess.READ)
	if f == null:
		return "нагрузка машины: loadavg нет, ЦП %d" % cores
	var la := f.get_line().split(" ")
	var l1 := float(la[0])
	return "нагрузка машины: loadavg %s %s %s на %d ЦП%s" % [la[0], la[1], la[2], cores,
		"  — ЗАНЯТА, стена завышена" if l1 > cores else ""]


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
	var n := prof.rows[0].size()
	var total := PackedInt32Array()
	var econ := PackedInt32Array()
	var game := PackedInt32Array()
	total.resize(n)
	econ.resize(n)
	game.resize(n)
	print("")
	print("  система              ср., мс   p99, мс   худш., мс")
	for ph in GameSim.Ph.COUNT:
		var r := prof.rows[ph]
		for i in r.size():
			total[i] += r[i]
			if ph == GameSim.Ph.ECON_PRE or ph == GameSim.Ph.ECON_POST or ph == GameSim.Ph.ECON_SLOW:
				econ[i] += r[i]
			if ph == GameSim.Ph.ORDERS or ph == GameSim.Ph.VICTORY or ph == GameSim.Ph.CHECKSUM:
				game[i] += r[i]
		print("  %-18s %8.3f  %8.3f  %9.3f" % [names[ph], _avg(r), _p99(r), _worst(r)])
	print("  %-18s %8.3f  %8.3f  %9.3f" % ["экономика (такт)", _avg(econ), _p99(econ), _worst(econ)])
	print("  %-18s %8.3f  %8.3f  %9.3f" % ["всего", _avg(total), _p99(total), _worst(total)])
	# занятость: стена / процессорное время потока за те же такты
	var k := 1.0
	if prof.cpu.size() == n and n > 0:
		var cpu_sum := 0
		var wall_sum := 0
		for i in n:
			cpu_sum += prof.cpu[i]
			wall_sum += total[i]
		k = maxf(1.0, float(wall_sum) / maxf(float(cpu_sum), 1.0))
		# по тактам schedstat ступенчат (шаг планировщика, ~4 мс) — верно только среднее
		print("  %-18s %8.3f  (по тактам — ступенями планировщика, только среднее)" % ["всего (ЦП потока)", _avg(prof.cpu)])
		print("  стена / ЦП = %.2f%s" % [k, "  — машина занята: проверки с поправкой ×1/%.2f" % k if k > BUSY else ""])
	else:
		print("  ЦП потока не измерить (нет /proc/thread-self/schedstat): проверки по стене")
	print("")
	var f := k if k > BUSY else 1.0
	var tag := "" if f == 1.0 else ", поправка ×1/%.2f" % f
	# цели §16: [название, ряд, ср., p99 (0 — без p99)]
	var gates := [
		["ядро", prof.rows[GameSim.Ph.KERNEL], 3.0, 5.0],
		["экономика", econ, 1.0, 2.0],
		["пути", prof.rows[GameSim.Ph.NAV], 2.0, 4.0],
		["ИИ", prof.rows[GameSim.Ph.AI], 0.3, 1.0],
		["приказы + победа + сумма", game, 0.2, 0.0],
		["всё", total, 6.5, 10.0],
	]
	for gt: Array in gates:
		var r: PackedInt32Array = gt[1]
		var a := _avg(r) / f
		SimHarness.check(a <= float(gt[2]), "%s: ср. ≤ %s мс (%.3f%s)" % [gt[0], str(gt[2]), a, tag])
		if float(gt[3]) > 0.0:
			var p := _p99(r) / f
			SimHarness.check(p <= float(gt[3]), "%s: p99 ≤ %s мс (%.3f%s)" % [gt[0], str(gt[3]), p, tag])


func _avg(r: PackedInt32Array) -> float:
	var s := 0
	for v in r:
		s += v
	return s / 1000.0 / maxi(r.size(), 1)


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
