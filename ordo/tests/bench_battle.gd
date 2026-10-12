extends SceneTree
## Замер процессора боя без отрисовки (ТЗ 11.5): симуляция + вид (толпа) на 1000 / 3000 / 5000 солдат.
##   godot --headless --path ordo --script res://tests/bench_battle.gd
##   … -- --sizes=1000,3000 --seconds=24 --phases --nothread
## Бой — нагрузочный сценарий среза (F9, StressScenario), зерно 7: отряды сходятся в свалку.
##
## Таблица 1 (всё на одном потоке, как было до фона): на каждый шаг симуляции (1/30 с) —
## два обновления вида (кадр 60 к/с) и отправка буферов толпы; «итог» — главный поток на кадр.
## Таблица 2 (как в игре, SimStepper): кадры по 16,7 мс, шаг боя считается в фоне, пока
## главный поток «рисует» (здесь — ждёт конца кадра); «главный поток» — его занятость на кадр
## (шаги, вид, отправка), «ожидание» — сколько он ждал фоновый шаг. Сумма боя должна совпасть.
## --phases — раскладка шага симуляции по частям (отдельный прогон, мс на шаг).
## Видеокарты здесь нет: это только время процессора на бой.

const FRAME_USEC := 16667

var _sizes: Array[int] = [1000, 3000, 5000]
var _seconds := 24.0
var _phases := false
var _threads := true
var _done := false


## Замер — в первом кадре: узлы в дереве уже готовы (_ready отработал)
func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sizes="):
			_sizes.clear()
			for s in a.trim_prefix("--sizes=").split(",", false):
				_sizes.append(int(s))
		elif a.begins_with("--seconds="):
			_seconds = float(a.trim_prefix("--seconds="))
		elif a == "--phases":
			_phases = true
		elif a == "--nothread":
			_threads = false
	print("Процессор: %s, потоков %d" % [OS.get_processor_name(), OS.get_processor_count()])
	print("")
	print("1) Один поток: %.0f с боя, шаг 1/30 с, вид — 2 кадра на шаг (60 к/с)" % _seconds)
	print("%-7s | %-15s | %-15s | %-15s | %-10s | %-6s | %s" % ["солдат", "шаг сим, мс", "вид, мс/кадр", "толпа→GPU, мс", "итог мс/к", "живых", "сумма боя"])
	print("%-7s | %-15s | %-15s | %-15s | %-10s | %-6s |" % ["", "сред / худш", "сред / худш", "сред / худш", "60 к/с", ""])
	var sums := {}
	for n in _sizes:
		var r := _bench(n)
		sums[n] = r.sums
		# на кадр 60 к/с: половина шага симуляции + вид + отправка
		var per_frame: float = r.sim_avg * 0.5 + r.view_avg + r.flush_avg
		print("%-7d | %6.2f / %6.2f | %6.2f / %6.2f | %6.2f / %6.2f | %10.2f | %-6d | %d" % [
			r.units, r.sim_avg, r.sim_max, r.view_avg, r.view_max, r.flush_avg, r.flush_max, per_frame, r.alive, r.checksum])
	if _threads:
		print("")
		print("2) Как в игре: шаг боя в фоне (SimStepper), кадр 16,7 мс")
		print("%-7s | %-15s | %-15s | %-15s | %-8s | %s" % ["солдат", "шаг сим, мс", "главный поток", "ожидание фона", "кадров", "сумма боя"])
		print("%-7s | %-15s | %-15s | %-15s | %-8s |" % ["", "сред / худш", "мс/к сред/худш", "мс/к сред/худш", "> 16,7"])
		for n in _sizes:
			var r := _bench_threaded(n)
			print("%-7d | %6.2f / %6.2f | %6.2f / %6.2f | %6.2f / %6.2f | %-8d | %d %s" % [
				r.units, r.sim_avg, r.sim_max, r.main_avg, r.main_max, r.wait_avg, r.wait_max, r.over,
				r.checksum, "(совпала, шаг %d)" % r.steps if r.checksum == sums.get(n, {}).get(r.steps, -1) else "(НЕ СОВПАЛА, шаг %d)" % r.steps])
	if _phases:
		for n in _sizes:
			_bench_phases(n)


func _make(n: int) -> Array:
	var sc := StressScenario.new()
	sc.name = "Scenario"
	sc.soldiers = n
	var holder := Node3D.new()
	holder.name = "Bench%d" % n
	root.add_child(holder)
	holder.add_child(sc)
	sc.set_process(false)          # шагаем сами
	sc.start(7)
	var view := BattleView.new()
	view.name = "View"
	view.ambient_path = ^"../NoAmbient"
	holder.add_child(view)
	view.set_process(false)
	return [holder, sc, view]


func _flush(view: BattleView) -> void:
	for l in view.layers.values():
		if l.has_method("_flush"):
			l._flush()


func _bench(n: int) -> Dictionary:
	var made := _make(n)
	var holder: Node3D = made[0]
	var sc: StressScenario = made[1]
	var view: BattleView = made[2]
	var steps := int(_seconds / BattleSim.DT)
	var sim_sum := 0.0
	var sim_max := 0.0
	var view_sum := 0.0
	var view_max := 0.0
	var flush_sum := 0.0
	var flush_max := 0.0
	var frames := 0
	for i in steps:
		var t0 := Time.get_ticks_usec()
		sc.step()
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		sim_sum += dt
		sim_max = maxf(sim_max, dt)
		for k in 2:
			sc.alpha = 0.5 * k
			t0 = Time.get_ticks_usec()
			view.update_view()
			dt = (Time.get_ticks_usec() - t0) / 1000.0
			view_sum += dt
			view_max = maxf(view_max, dt)
			t0 = Time.get_ticks_usec()
			_flush(view)
			dt = (Time.get_ticks_usec() - t0) / 1000.0
			flush_sum += dt
			flush_max = maxf(flush_max, dt)
			frames += 1
	var sim := sc.sim
	var out := {"units": sim.n, "sim_avg": sim_sum / steps, "sim_max": sim_max,
		"view_avg": view_sum / frames, "view_max": view_max,
		"flush_avg": flush_sum / frames, "flush_max": flush_max,
		"alive": sim.side_alive(0) + sim.side_alive(1), "checksum": sim.checksum(), "sums": {}}
	# суммы для сверки с фоном: фон мог заготовить шаг вперёд
	out.sums[sim.steps] = sim.checksum()
	sc.step()
	out.sums[sim.steps] = sim.checksum()
	holder.free()
	return out


## Как в игре: кадр за кадром по 16,7 мс; вид сам ведёт шаги (SimStepper, фон для большого боя)
func _bench_threaded(n: int) -> Dictionary:
	var made := _make(n)
	var holder: Node3D = made[0]
	var sc: StressScenario = made[1]
	var view: BattleView = made[2]
	var st := view.stepper()
	st.mode = "on"
	var steps := int(_seconds / BattleSim.DT)
	var main_sum := 0.0
	var main_max := 0.0
	var frames := 0
	var over := 0
	while sc.sim.steps < steps:
		var f0 := Time.get_ticks_usec()
		# ровно столько времени, чтобы не перескочить нужный шаг
		var left := (steps - sc.sim.steps) * BattleSim.DT
		view._process(minf(1.0 / 60.0, left))
		_flush(view)
		var busy := Time.get_ticks_usec() - f0
		main_sum += busy / 1000.0
		main_max = maxf(main_max, busy / 1000.0)
		frames += 1
		if busy > FRAME_USEC:
			over += 1
		else:
			OS.delay_usec(FRAME_USEC - busy)   # «отрисовка» — фон считает следующий шаг
	st.sync()
	var sim := sc.sim
	var out := {"units": sim.n, "sim_avg": st.stat_ms / maxi(st.stat_steps, 1), "sim_max": st.stat_ms_max,
		"main_avg": main_sum / frames, "main_max": main_max,
		"wait_avg": st.stat_wait_ms / frames, "wait_max": st.stat_wait_ms_max, "over": over,
		"checksum": sim.checksum(), "steps": sim.steps}
	holder.free()
	return out


## Раскладка шага по частям: тот же порядок, что в BattleSim.step (отдельный прогон)
func _bench_phases(n: int) -> void:
	var made := _make(n)
	var holder: Node3D = made[0]
	var sc: StressScenario = made[1]
	var sim := sc.sim
	var names := ["ИИ сценария", "прошлые позиции", "хэш", "центры отрядов", "отряды", "решения бойцов",
		"действия", "движение+расталкивание", "победа"]
	var sums := PackedFloat64Array()
	sums.resize(names.size())
	var steps := int(_seconds / BattleSim.DT)
	for i in steps:
		var t := [Time.get_ticks_usec()]
		var mark := func(k: int) -> void:
			var now := Time.get_ticks_usec()
			sums[k] += (now - t[0]) / 1000.0
			t[0] = now
		sc._ai()
		mark.call(0)
		sim.time += BattleSim.DT
		sim.steps += 1
		for u in sim.n:
			sim.u_px[u] = sim.u_x[u]
			sim.u_pz[u] = sim.u_z[u]
			sim.u_ph[u] = sim.u_h[u]
		mark.call(1)
		sim._rebuild_hash()
		mark.call(2)
		for s in sim.squads:
			sim._update_centroid(s)
		mark.call(3)
		for s in sim.squads:
			sim._squad_step(s)
		mark.call(4)
		sim._units_think()
		mark.call(5)
		sim._resolve_actions()
		mark.call(6)
		sim._integrate()
		mark.call(7)
		sim._victory_check()
		mark.call(8)
	print("")
	print("Шаг симуляции по частям, %d юнитов (мс на шаг, среднее за %.0f с):" % [sim.n, _seconds])
	var total := 0.0
	for k in names.size():
		total += sums[k] / steps
		print("  %-24s %6.2f" % [names[k], sums[k] / steps])
	print("  %-24s %6.2f" % ["всего", total])
	holder.free()
