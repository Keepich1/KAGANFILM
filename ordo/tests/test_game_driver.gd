extends SceneTree
## GameDriver и потоки (ARCHITECTURE §7.4, §16 «Phase 2»; SimStepper): приказы интерфейса и шаг в фоне.
##   • issue() кладёт приказ во входящие, step() переносит их в очередь игры: такт и порядок — как у прямого
##     game.submit между шагами (контрольные суммы двух игр совпадают);
##   • шаги в другом потоке, а приказы с главного — ни один не теряется, номера по порядку, игра не падает;
##   • пока background_steps = false, restarts_next() → true (SimStepper шагает на главном потоке);
##   • зерно игры доходит до ядра: у разных зёрен — разный BattleRng (на настоящем ядре);
##   • на настоящем ядре: SimStepper с фоном, приказы во время фонового шага, sync() находит шагатель.
## Реализации — GameSim.impl_for: по умолчанию настоящие (если они в проекте), --impl=stub или ORDO_IMPL=stub — заглушки.
##   godot --headless --path ordo --script res://tests/test_game_driver.gd [-- --impl=stub]

const STEPS := 240

var _impl := {}


func _init() -> void:
	_impl = GameSim.impl_for(OS.get_cmdline_user_args(), OS.get_environment("ORDO_IMPL"))
	_test_inbox_matches_submit()
	_test_threaded_issue()
	_test_stop_gap()
	_test_kernel_seed()
	_test_stepper()
	SimHarness.finish(self)


func _driver(p_seed := 3) -> GameDriver:
	var d := GameDriver.new()
	d.autostart = false
	d.game_impl = _impl.duplicate()
	d.start_game(p_seed, &"kokand", 0)
	return d


## Новая игра с теми же реализациями, что у драйвера
func _game(p_seed := 3) -> GameSim:
	var g := GameSim.new()
	g.impl = _impl.duplicate()
	g.setup(MapValley.MAP, SimHarness.default_players(), p_seed)
	return g


## Работники игрока 0
func _workers(g: GameSim) -> PackedInt32Array:
	var out := PackedInt32Array()
	var q := g.query as GameQueryImpl
	for u in q.units_of(0):
		if q.unit_flags(u) & UnitStats.WORKER:
			out.append(u)
	return out


## Приказ номер k из набора (ходьба туда-сюда у ставки, иногда стоп)
func _cmd(ws: PackedInt32Array, k: int) -> PackedInt32Array:
	var one := ws.slice(k % ws.size(), k % ws.size() + 1)
	if k % 3 == 2:
		return SimCmd.stop(one)
	return SimCmd.move(one, Vector2(170 + (k % 7) * 3.0, 40 + (k % 5) * 3.0))


func _test_inbox_matches_submit() -> void:
	print("[входящие: тот же такт и порядок, что у game.submit]")
	var d := _driver()
	var g := _game()
	print("реализации: ", d.game.impl_names())
	var ws := _workers(d.game)
	var k := 0
	for t in STEPS:
		if t % 4 == 1:
			for j in 3:
				d.issue(_cmd(ws, k))
				g.submit(0, _cmd(ws, k))
				k += 1
		if t == 5:
			SimHarness.check(d.inbox_count() == 3 and d.game.queue.pending_count() == 0,
				"issue() — во входящие, не в очередь игры (входящих %d)" % d.inbox_count())
		d.step()
		g.step()
	SimHarness.check(d.inbox_count() == 0, "step() забрал все входящие")
	SimHarness.check(d.game.checksums == g.checksums and d.game.checksums.size() == STEPS / 30,
		"суммы раз в 30 тактов совпадают с прямым submit (%d сумм)" % d.game.checksums.size())
	var a := d.game.queue.external_log()
	var b := g.queue.external_log()
	var same := a.size() == b.size() and a.size() == k
	for i in mini(a.size(), b.size()):
		same = same and a[i] == b[i]
	SimHarness.check(same, "журнал приказов (такт, игрок, номер) тот же: %d" % a.size())
	d.free()


func _test_threaded_issue() -> void:
	print("[шаги в фоне, приказы с главного потока]")
	var d := _driver()
	var ws := _workers(d.game)
	var n := 0
	# фон шагает с паузами 0,2 мс (чтобы шаги и приказы точно шли вперемешку и на быстрой машине)
	var task := WorkerThreadPool.add_task(func() -> void:
		for t in STEPS:
			d.step()
			OS.delay_usec(200))
	while (not WorkerThreadPool.is_task_completed(task) or n < 50) and n < 3000:
		d.issue(_cmd(ws, n))
		n += 1
		OS.delay_usec(300)
	WorkerThreadPool.wait_for_task_completion(task)
	var t_end := d.game.tick
	d.step()
	d.step()
	var log := d.game.queue.external_log()
	var seq_ok := log.size() == n
	for i in log.size():
		seq_ok = seq_ok and log[i][SimCmd.H_SEQ] == i and log[i][SimCmd.H_PLAYER] == 0
	SimHarness.check(t_end == STEPS, "фон сделал %d шагов" % t_end)
	SimHarness.check(n > 0 and seq_ok, "отдано %d приказов — все в журнале, номера 0…%d по порядку (%d)" % [n, n - 1, log.size()])
	var applied := d.game.orders.applied + d.game.orders.rejected
	SimHarness.check(applied >= n, "все исполнены или отклонены (%d)" % applied)
	d.free()


func _test_stop_gap() -> void:
	print("[фон выключен, пока читатели не зовут sync()]")
	var d := _driver()
	SimHarness.check(not d.background_steps and d.restarts_next(), "background_steps = false → restarts_next() = true")
	d.background_steps = true
	SimHarness.check(not d.restarts_next(), "background_steps = true → шаг может идти в фоне")
	d.sync()          # без вида — ничего не ждёт
	SimHarness.check(true, "sync() без вида не падает")
	d.free()


func _test_kernel_seed() -> void:
	print("[зерно игры — в ядро]")
	var a := _game(1)
	var b := _game(2)
	var c := _game(1)
	if a.port.battle() == null:
		print("  —    на заглушке ядра нет BattleRng: проверка на настоящем ядре")
		return
	var ra := a.port.battle().rng.state
	var rb := b.port.battle().rng.state
	var rc := c.port.battle().rng.state
	SimHarness.check(ra != rb and ra == rc, "BattleRng ядра: зерно 1 — %d, зерно 2 — %d, снова 1 — %d" % [ra, rb, rc])


## Настоящее ядро: шагатель вида с фоном (mode on), приказы с главного потока во время фонового шага, sync().
## Такт приказа зависит от того, успел ли фоновый шаг забрать входящие (как ввод между кадрами); повтор
## пишет такт из журнала, поэтому проверяем только, что ни один приказ не потерян и номера идут по порядку.
func _test_stepper() -> void:
	print("[SimStepper: фон и sync()]")
	var d := _driver()
	if d.sim == null:
		print("  —    на заглушке ядра нет BattleSim: проверка на настоящем ядре")
		d.free()
		return
	var st := SimStepper.new(d)
	st.mode = "on"
	d.background_steps = true
	SimHarness.check(d._find_stepper() == null, "до фона шагатель не связан с started (вида нет)")
	var ws := _workers(d.game)
	var k := 0
	var bg := 0
	var sync_ok := true
	var found := false
	for frame in STEPS:
		st.advance(BattleSim.DT)
		if st._task >= 0:
			bg += 1
			d.issue(_cmd(ws, k))     # шаг идёт в фоне — приказ с главного потока
			k += 1
		if frame % 10 == 0:
			found = found or d._find_stepper() == st
			d.sync()
			sync_ok = sync_ok and st._task < 0
	SimHarness.check(bg > STEPS / 2, "шаги шли в фоне (%d кадров из %d)" % [bg, STEPS])
	SimHarness.check(found, "sync() находит шагатель по связи started (запись SimStepper)")
	SimHarness.check(sync_ok, "после sync() фонового шага нет")
	st.advance(BattleSim.DT * 3.0)
	d.sync()
	d.step()
	d.step()
	var log := d.game.queue.external_log()
	var seq_ok := log.size() == k
	for i in log.size():
		seq_ok = seq_ok and log[i][SimCmd.H_SEQ] == i
	SimHarness.check(k > 0 and seq_ok, "приказы во время фона: %d отдано, в журнале %d, номера по порядку" % [k, log.size()])
	st.release()
	d.free()
