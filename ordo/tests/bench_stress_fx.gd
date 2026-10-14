extends SceneTree
## Эффекты нагрузочного боя (F9): тот же BattleFx, что у основного боя, подключён к StressScenario
## (BattleFx.add_driver — так делает срез), шаг боя считается в фоне (SimStepper), как в игре.
##   godot --headless --path ordo --script res://tests/bench_stress_fx.gd
##   … -- --soldiers=3000 --seconds=16 --fx_max=4
## Проверки:
##   1) дым залпов и пыль коней идут: клубов дыма и пыли больше нуля (BattleFx.stat_total), выстрелы
##      и залпы дошли до эффектов; при 3000 солдат запас дыма кончается — дальние залпы ложатся стеной;
##   2) сигналы фонового шага приходят эффектам только на главном потоке и без ошибок движка
##      (свой Logger ловит всё, что движок пишет как ошибку);
##   3) эффекты не меняют бой: сумма боя после тех же шагов — как у того же боя без эффектов и без фона;
##   4) время эффектов на кадр (PerfMeter «fx»: кадр эффектов и обработчики событий) — печать
##      (--fx_max=мс — предел среднего, по умолчанию без предела: машина проверки бывает занята).
## Видеокарты здесь нет (--headless): частицы не рисуются, но клубы заказываются как в игре.
## Время — по часам главного потока: на занятой машине худшие кадры раздуты чужими процессами,
## честнее медиана.

## Кадр игры, с
const FRAME := 1.0 / 60.0


## Ловит ошибки движка и скриптов (push_error, ERR_FAIL… — например, сигнал узла из фонового потока)
class ErrorCatch extends Logger:
	var errors: Array[String] = []
	var _lock := Mutex.new()

	var warnings := 0

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_lock.lock()
		if error_type == Logger.ERROR_TYPE_WARNING:
			warnings += 1      # предупреждения не считаем ошибками, но печатаем число
		else:
			errors.append("%s %s (%s:%d %s)" % [code, rationale, file, line, function])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func count() -> int:
		_lock.lock()
		var n := errors.size()
		_lock.unlock()
		return n


var _soldiers := 3000
var _seconds := 16.0
var _fx_max := 0.0
var _started := false
var _fails := 0
var _catch := ErrorCatch.new()
var _events := {"shot": 0, "volley": 0, "impact": 0, "charge_hit": 0, "off_main": 0}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		var v := kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"soldiers":
				_soldiers = maxi(int(v), 100)
			"seconds":
				_seconds = maxf(float(v), 1.0)
			"fx_max":
				_fx_max = float(v)
	OS.add_logger(_catch)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _run() -> void:
	print("Эффекты нагрузочного боя: %d солдат, %.0f с боя, кадр %.1f мс, шаг боя в фоне" % [
		_soldiers, _seconds, FRAME * 1000.0])
	# бой как по F9 в срезе: сценарий, вид (толпа и шаги боя), эффекты
	var holder := Node3D.new()
	holder.name = "Stress"
	root.add_child(holder)
	var sc := StressScenario.new()
	sc.name = "Scenario"
	sc.soldiers = _soldiers
	holder.add_child(sc)
	var view := BattleView.new()
	view.name = "View"
	view.ambient_path = ^"../NoAmbient"
	holder.add_child(view)
	var fx := BattleFx.new()
	fx.name = "Fx"
	fx.ambient_motes = false
	holder.add_child(fx)
	# камера стратегии над полем нагрузки: ближние события — как раньше, дальние — по запасу частиц
	var cam := Camera3D.new()
	cam.far = 4000.0
	root.add_child(cam)
	cam.global_position = Vector3(95.0, 75.0, 250.0)
	cam.look_at(Vector3(95.0, 0.0, 110.0))
	cam.make_current()
	for name: String in ["shot", "volley", "impact", "charge_hit"]:
		sc.connect(name, _on_event.bind(name))
	sc.start(7)
	view.set_process(false)
	fx.set_process(false)
	var st := view.stepper()
	if st == null:
		_check(false, "у вида нет SimStepper")
		_finish()
		return
	st.mode = "on"      # шаг в фоне, как у большого боя в игре
	var frames := int(_seconds / FRAME)
	var fx_ms := PackedFloat32Array()
	var fx_peak := 0.0
	var worst_at := 0
	var own_sum := 0.0          # сам кадр эффектов (пыль коней, ведра, свет), без обработчиков событий
	var t_wall := Time.get_ticks_msec()
	var prev_f := -1
	var prev_own := 0.0
	for f in frames + 1:
		# прошлый кадр закрыт: обработчики событий (и те, что пришли отложенным вызовом в конце кадра)
		# писали себя в PerfMeter «fx» вместе с кадром эффектов; первый кадр — разогрев, не считаем
		var e: Array = PerfMeter._m.get(&"fx", [])
		if f > 1:
			# (окно PerfMeter раз в секунду обнуляет сумму кадра — тогда не меньше своего кадра эффектов)
			var ms := maxf(float(e[1]) if e.size() > 1 and int(e[0]) == prev_f else 0.0, prev_own)
			fx_ms.append(ms)
			if ms > fx_peak:
				fx_peak = ms
				worst_at = f - 1
			own_sum += prev_own
		if f == frames:
			break
		prev_f = Engine.get_process_frames()
		view._process(FRAME)
		var t0 := Time.get_ticks_usec()
		fx._process(FRAME)
		prev_own = (Time.get_ticks_usec() - t0) / 1000.0
		await process_frame   # отложенные вызовы (очередь сигналов фонового шага) — как в игре
	st.sync()
	var wall := (Time.get_ticks_msec() - t_wall) / 1000.0
	var steps := sc.sim.steps
	var sum := sc.sim.checksum()
	var tot := fx.stat_total()
	var fx_avg := 0.0
	for v in fx_ms:
		fx_avg += v
	fx_avg /= maxf(fx_ms.size(), 1.0)
	print("  кадров %d за %.0f с · шагов боя %d (в фоне: %s, шаг в среднем %.1f мс)" % [frames, wall, steps,
		"да" if st.threaded else "нет", st.stat_ms / maxf(st.stat_steps, 1.0)])
	print("  событий: выстрелов %d, залпов %d, ударов натиска %d, сшибок конницы %d" % [_events.shot,
		_events.volley, _events.impact, _events.charge_hit])
	print("  эффекты: клубов дыма %d, пыли %d, залпов стеной %d" % [tot.smoke, tot.dust, tot.merged])
	var sorted := fx_ms.duplicate()
	sorted.sort()
	print("  время эффектов: %.2f мс на кадр в среднем (кадр эффектов %.2f, события %.2f); медиана %.2f, 95 %% кадров — до %.2f, худший %.2f мс (кадр %d)" % [
		fx_avg, own_sum / maxf(fx_ms.size(), 1.0), fx_avg - own_sum / maxf(fx_ms.size(), 1.0),
		sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0,
		sorted[int(sorted.size() * 0.95)] if not sorted.is_empty() else 0.0, fx_peak, worst_at])
	_check(st.threaded, "шаг боя считался в фоне (SimStepper)")
	_check(_events.shot > 0 and _events.volley > 0, "выстрелы и залпы дошли до эффектов")
	_check(int(tot.smoke) > 0, "дым залпов идёт (клубов %d)" % tot.smoke)
	_check(int(tot.dust) > 0, "пыль коней и натиска идёт (клубов %d)" % tot.dust)
	if _soldiers >= 3000:
		_check(int(tot.merged) > 0, "при 3000 солдат дальние залпы ложатся стеной (запас дыма общий)")
	_check(int(_events.off_main) == 0, "все сигналы боя — на главном потоке (не на главном: %d)" % _events.off_main)
	if _fx_max > 0.0:
		_check(fx_avg <= _fx_max, "эффекты в среднем не дольше %.1f мс на кадр" % _fx_max)
	holder.queue_free()
	cam.queue_free()
	await process_frame
	# тот же бой без эффектов, без вида и без фона — шаг за шагом на главном потоке
	var ref := StressScenario.new()
	ref.soldiers = _soldiers
	root.add_child(ref)
	ref.set_process(false)
	ref.start(7)
	while ref.sim.steps < steps:
		ref.step()
	_check(ref.sim.checksum() == sum, "эффекты не меняют бой: сумма боя на шаге %d совпала (%d)" % [steps, sum])
	ref.queue_free()
	await process_frame
	_finish()


func _on_event(...args: Array) -> void:
	var name: String = args.back()
	_events[name] = int(_events[name]) + 1
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		_events.off_main = int(_events.off_main) + 1


func _finish() -> void:
	var n := _catch.count()
	_check(n == 0, "ошибок движка нет (%d; предупреждений %d)" % [n, _catch.warnings])
	for i in mini(n, 8):
		print("      ", _catch.errors[i])
	print("")
	print("ИТОГ: ВСЁ ПРОШЛО" if _fails == 0 else "ИТОГ: ПРОВАЛЕНО %d" % _fails)
	quit(0 if _fails == 0 else 1)
