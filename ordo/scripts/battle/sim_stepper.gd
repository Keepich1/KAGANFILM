class_name SimStepper
extends RefCounted
## Шаги боя для вида (BattleView): ведёт SimDriver (ScenarioClash, GameDriver) вместо его собственного _process
## (тот же счёт времени: накопитель, скорость, пауза, не больше 12 шагов за кадр).
##
## Малый бой — шаги на главном потоке, ровно как раньше. Большой (от THREAD_MIN юнитов) —
## следующий шаг считается заранее в фоне (WorkerThreadPool), пока главный поток рисует кадр;
## шаг принимается в тот кадр, когда он и пришёл бы без фона. Вид в это время показывает
## снимок двух последних принятых шагов (snapshot), а не живые массивы симуляции.
## Шаги те же и в том же порядке — бой не меняется ни на бит (tests/bench_battle.gd сверяет сумму).
##
## Сигналы сценария не вызываются из фонового потока: на время фона их слушатели переподключены
## на запись и получают те же вызовы в том же порядке на главном потоке, когда шаг принят.
## Шаг, после которого бой начнётся заново (loop), всегда идёт на главном потоке.
## Пока шаг в фоне, симуляцию снаружи не менять: сначала sync() (так делает BattleRoot для R).
##
## Ключ --simthread=auto|on|off (по умолчанию auto); при съёмке (--shot, --movie) фон выключен.

const THREAD_MIN := 600
const MAX_STEPS := 12
const DT := BattleSim.DT

var scenario: SimDriver
## auto — фон для больших боёв, on — всегда, off — никогда
var mode := "auto"
## Фон включён сейчас
var threaded := false
## Итоги для замеров (tests/bench_battle.gd): шагов, мс шагов (сумма, худший), ожидание фона, мс
var stat_steps := 0
var stat_ms := 0.0
var stat_ms_max := 0.0
var stat_wait_ms := 0.0
var stat_wait_ms_max := 0.0
## Шаг этого боя за прошлую секунду, мс: среднее и худший (экран F9)
var step_avg := 0.0
var step_max := 0.0
var _win := Vector3.ZERO           # сумма, худший, число — за текущую секунду
var _win_start := 0
## Снимок для вида (только при фоне): тот бой, тот шаг
var snap_sim: BattleSim
var snap_time := 0.0
var s_x := PackedFloat32Array()
var s_z := PackedFloat32Array()
var s_h := PackedFloat32Array()
var s_px := PackedFloat32Array()
var s_pz := PackedFloat32Array()
var s_ph := PackedFloat32Array()
var s_vx := PackedFloat32Array()
var s_vz := PackedFloat32Array()
var s_life := PackedInt32Array()
var s_death_t := PackedFloat32Array()
var s_act := PackedInt32Array()
var s_act_t := PackedFloat32Array()
var s_reload_t := PackedFloat32Array()
var s_couched := PackedInt32Array()
var s_fall := PackedInt32Array()
var s_sq_status := PackedInt32Array()

var _task := -1
var _pending_sim: BattleSim        # шаг посчитан заранее (sync), ещё не принят
var _task_usec := 0               # пишет фоновый поток, читается после ожидания
var _main_tid := 0
var _queue: Array = []            # [имя сигнала, аргументы] — из фонового шага
var _recorders := {}              # имя → Callable записи
var _listeners := {}              # имя → [[Callable, флаги], ...]
var _relay := false


func _init(p_scenario: SimDriver) -> void:
	scenario = p_scenario
	_main_tid = OS.get_main_thread_id()
	var tree := Engine.get_main_loop() as SceneTree
	var ordo: Node = tree.root.get_node_or_null("Ordo") if tree else null
	if ordo:
		mode = String(ordo.call("arg", "simthread", "auto"))
		if ordo.call("has_arg", "shot") or ordo.call("has_arg", "movie"):
			mode = "off"


## Время кадра: шаги, которые пора сделать; scenario.alpha — доля до следующего шага
func advance(delta: float) -> void:
	var sc := scenario
	if sc == null or sc.sim == null or sc.paused:
		return
	sc._acc += delta * sc.time_scale
	var guard := 0
	if _pending_sim != null and _pending_sim != sc.sim:
		_pending_sim = null      # бой начат заново — заготовленный шаг не нужен
	while sc._acc >= DT and guard < MAX_STEPS:
		if _task >= 0:
			_collect()
		elif not sc.can_step():
			# игра по сети ждёт приказы друга (барьер такта): время не копится — потом без рывка вперёд
			sc._acc = minf(sc._acc, DT)
			break
		elif _pending_sim != null:
			_pending_sim = null  # шаг уже посчитан (sync) — только принять
			sc._acc -= DT
			_snapshot()
		else:
			_step_here()
		guard += 1
	if guard >= MAX_STEPS:
		sc._acc = 0.0
	sc.alpha = clampf(sc._acc / DT, 0.0, 1.0)
	_update_mode()
	if threaded and _task < 0 and _pending_sim == null and not _restarts_next():
		_launch()


## Дождаться фонового шага (если он идёт) и вернуть слушателям их сигналы.
## Звать перед любым изменением симуляции снаружи (перезапуск, приказы).
## Посчитанный заранее шаг остаётся в запасе: в своё время он принимается без пересчёта.
func sync() -> void:
	if _task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_pending_sim = scenario.sim
	_stat(_task_usec / 1000.0)
	_flush_queue()


## Отпустить сценарий: фон дождаться, слушателей вернуть, сценарий снова шагает сам
func release(give_back_process := true) -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_queue.clear()
	_relay_release()
	# записи держат ссылку на шагатель — без них он освободится
	_recorders.clear()
	_listeners.clear()
	if give_back_process and is_instance_valid(scenario):
		scenario.set_process(true)


## Вид читает снимок (фон) или живые массивы (без фона)
func uses_snapshot() -> bool:
	return threaded and snap_sim != null and snap_sim == scenario.sim


func _want_thread() -> bool:
	match mode:
		"on", "1", "true":
			return true
		"off", "0", "false":
			return false
	return scenario.sim.n >= THREAD_MIN


func _update_mode() -> void:
	var want := _want_thread()
	if want == threaded:
		return
	if _task >= 0:
		return  # переключимся, когда фон освободится
	threaded = want
	if threaded:
		_relay_capture()
		_snapshot()
	else:
		_relay_release()
		snap_sim = null


## После этого шага сценарий начнёт бой заново (новый BattleSim) — такой шаг только здесь
func _restarts_next() -> bool:
	return scenario.restarts_next()


func _step_here() -> void:
	var sc := scenario
	sc._acc -= DT
	var t0 := Time.get_ticks_usec()
	sc.step()
	_stat((Time.get_ticks_usec() - t0) / 1000.0)
	if threaded:
		_snapshot()


func _stat(ms: float) -> void:
	PerfMeter.add_sample(&"sim", ms)
	stat_steps += 1
	stat_ms += ms
	stat_ms_max = maxf(stat_ms_max, ms)
	_win = Vector3(_win.x + ms, maxf(_win.y, ms), _win.z + 1.0)
	var now := Time.get_ticks_msec()
	if now - _win_start >= 1000:
		_win_start = now
		step_avg = _win.x / maxf(_win.z, 1.0)
		step_max = _win.y
		_win = Vector3.ZERO


func _launch() -> void:
	_relay_capture()
	_task_usec = 0
	# высокий приоритет: шаг нужен к сроку, его не должны задерживать фоновые загрузки
	_task = WorkerThreadPool.add_task(_work, true, "Ордо: шаг боя")


func _work() -> void:
	var t0 := Time.get_ticks_usec()
	scenario.step()
	_task_usec = Time.get_ticks_usec() - t0


func _collect() -> void:
	var t0 := Time.get_ticks_usec()
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var wait := (Time.get_ticks_usec() - t0) / 1000.0
	PerfMeter.add_frame(&"sim_wait", wait)
	stat_wait_ms += wait
	stat_wait_ms_max = maxf(stat_wait_ms_max, wait)
	scenario._acc -= DT
	_stat(_task_usec / 1000.0)
	_flush_queue()
	_snapshot()


## Копия того, что читает вид (фон в это время не работает)
func _snapshot() -> void:
	var sim := scenario.sim
	snap_sim = sim
	snap_time = sim.time
	s_x = sim.u_x.duplicate()
	s_z = sim.u_z.duplicate()
	s_h = sim.u_h.duplicate()
	s_px = sim.u_px.duplicate()
	s_pz = sim.u_pz.duplicate()
	s_ph = sim.u_ph.duplicate()
	s_vx = sim.u_vx.duplicate()
	s_vz = sim.u_vz.duplicate()
	s_life = sim.u_life.duplicate()
	s_death_t = sim.u_death_t.duplicate()
	s_act = sim.u_act.duplicate()
	s_act_t = sim.u_act_t.duplicate()
	s_reload_t = sim.u_reload_t.duplicate()
	s_couched = sim.u_couched.duplicate()
	s_fall = sim.u_fall.duplicate()
	s_sq_status = sim.sq_status.duplicate()


# ---------------------------------------------------------------- сигналы сценария

func _relay_capture() -> void:
	if not _relay:
		_relay = true
		for s in scenario.get_script().get_script_signal_list():
			var name := StringName(s["name"])
			if _recorders.has(name):
				continue
			_recorders[name] = func(...args: Array) -> void: _record(name, args)
			_listeners[name] = []
	# все слушатели (и подключившиеся позже) — на запись
	for name: StringName in _recorders:
		var rec: Callable = _recorders[name]
		for c in scenario.get_signal_connection_list(name):
			var cb: Callable = c["callable"]
			if cb == rec:
				continue
			scenario.disconnect(name, cb)
			(_listeners[name] as Array).append([cb, int(c["flags"])])
		if not scenario.is_connected(name, rec):
			scenario.connect(name, rec)


func _relay_release() -> void:
	if not _relay:
		return
	_relay = false
	if not is_instance_valid(scenario):
		return
	for name: StringName in _recorders:
		var rec: Callable = _recorders[name]
		if scenario.is_connected(name, rec):
			scenario.disconnect(name, rec)
		for l in _listeners[name]:
			var cb: Callable = l[0]
			if cb.is_valid() and not scenario.is_connected(name, cb):
				scenario.connect(name, cb, int(l[1]))
		(_listeners[name] as Array).clear()


func _record(name: StringName, args: Array) -> void:
	if OS.get_thread_caller_id() == _main_tid:
		_deliver(name, args)       # сигнал с главного потока (start, перезапуск) — сразу
	else:
		_queue.append([name, args])


func _flush_queue() -> void:
	if _queue.is_empty():
		return
	var q := _queue
	_queue = []
	for item in q:
		_deliver(item[0], item[1])


func _deliver(name: StringName, args: Array) -> void:
	var list: Array = _listeners.get(name, [])
	var i := 0
	while i < list.size():
		var cb: Callable = list[i][0]
		var flags: int = list[i][1]
		if not cb.is_valid():
			list.remove_at(i)
			continue
		if flags & Object.CONNECT_ONE_SHOT:
			list.remove_at(i)
		else:
			i += 1
		if flags & Object.CONNECT_DEFERRED:
			cb.bindv(args).call_deferred()
		else:
			cb.callv(args)
