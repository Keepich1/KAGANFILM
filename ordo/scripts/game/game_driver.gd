class_name GameDriver
extends SimDriver
## Узел «Города» в scenes/gorod/gorod.tscn (ARCHITECTURE §7.4): шагает GameSim как SimDriver (30 Гц,
## не больше 12 шагов за кадр, пауза и скорость — локальны), отдаёт сигналы ядра для эффектов (BattleFx)
## и окно чтения query (GameQueryImpl) для вида и интерфейса — так же, как FakeCityDriver до I4.
##
## Аргументы запуска (Ordo.arg): --seed=N, --faction=kokand|kipchak, --difficulty=0..2, --ai_vs_ai,
## --replay=путь (смотреть повтор), --save_replay=путь (записать повтор при выходе).
##
## Потоки. Шаги может вести вид (SimStepper), у большого боя — в фоне (WorkerThreadPool). Поэтому:
##   • issue() только кладёт приказ во входящие (под замком); в очередь игры (CommandQueue) их переносит
##     step() — на том потоке, где идёт шаг, до game.step(). Такт и порядок приказов те же, что при прямом
##     game.submit между шагами: повтор и контрольные суммы не меняются.
##   • Окно чтения query и таблицы экономики шаг меняет на месте (снимок SimStepper — только массивы ядра).
##     Пока не все читатели (HUD, виды) зовут sync() перед чтением, фон выключен: background_steps = false,
##     restarts_next() → true, и SimStepper шагает на главном потоке. Включить — после согласования с VIEW/UI (I4).

signal ticked(tick: int)

## Запускаться самому при входе в дерево
@export var autostart := true
@export var player_faction := &"kokand"
@export var difficulty := 0
## Местный игрок тоже ИИ (смотреть бой двух ИИ)
@export var ai_vs_ai := false

var game: GameSim
var query: GameQuery
var local_player := 0
var replay_path := ""
var save_path := ""

## Реализации для GameSim.impl (тесты, автобои: GameSim.impl_for); {} — настоящие, если они в проекте
var game_impl := {}
## Шаг в фоне разрешён (см. «Потоки» выше): только когда все читатели query зовут sync() перед чтением
var background_steps := false
## Шагатель вида (BattleView.stepper()): вид может задать сам; иначе sync() ищет его по связям сигнала started
var stepper: SimStepper

var _replay := {}
var _inbox: Array[PackedInt32Array] = []
var _inbox_mx := Mutex.new()


func _ready() -> void:
	if Engine.is_editor_hint() or not autostart:
		return
	var s := 1
	var ordo := get_node_or_null("/root/Ordo")
	if ordo:
		if ordo.has_arg("seed"):
			s = int(ordo.arg("seed"))
		if ordo.has_arg("faction"):
			player_faction = StringName(ordo.arg("faction"))
		if ordo.has_arg("difficulty"):
			difficulty = clampi(int(ordo.arg("difficulty")), 0, 2)
		ai_vs_ai = ai_vs_ai or ordo.has_arg("ai_vs_ai")
		replay_path = ordo.arg("replay", "")
		save_path = ordo.arg("save_replay", "")
	if replay_path != "":
		start_replay(replay_path)
	else:
		start_game(s, player_faction, difficulty)


func start(p_seed: int) -> void:
	start_game(p_seed, player_faction, difficulty)


## Новая игра: местный игрок (0) — player_faction, ИИ (1) — другая сторона
func start_game(p_seed: int, p_faction: StringName, p_difficulty: int) -> void:
	current_seed = p_seed
	player_faction = p_faction
	difficulty = p_difficulty
	var other := &"kipchak" if p_faction == &"kokand" else &"kokand"
	var ctrl0 := PlayerTable.Ctrl.AI if ai_vs_ai else PlayerTable.Ctrl.HUMAN
	var players: Array[Dictionary] = [
		{"faction": p_faction, "team": 0, "ctrl": ctrl0, "difficulty": p_difficulty},
		{"faction": other, "team": 1, "ctrl": PlayerTable.Ctrl.AI, "difficulty": p_difficulty}]
	game = GameSim.new()
	game.impl = game_impl.duplicate()
	game.setup(MapValley.MAP, players, p_seed)
	_attach()


## Смотреть повтор (приказы — из записи; свои приказы игнорируются)
func start_replay(path: String) -> bool:
	_replay = Replay.load_file(path)
	var g: GameSim = null
	if not _replay.is_empty():
		g = Replay.make_game(_replay, game_impl.duplicate())
	if g == null:
		push_warning("GameDriver: повтор не открыт: %s" % Replay.last_error)
		_replay = {}
		start_game(1, player_faction, difficulty)
		return false
	game = g
	current_seed = game.seed
	_attach()
	return true


## Приказ местного игрока (интерфейс): во входящие; в очередь игры — в начале следующего шага.
## Можно звать с главного потока, пока шаг идёт в фоне.
func issue(cmd: PackedInt32Array) -> void:
	if game == null or not _replay.is_empty():
		return
	_inbox_mx.lock()
	_inbox.append(cmd.duplicate())
	_inbox_mx.unlock()


## Приказов во входящих (ещё не в очереди игры)
func inbox_count() -> int:
	_inbox_mx.lock()
	var n := _inbox.size()
	_inbox_mx.unlock()
	return n


## Дождаться фонового шага (если он идёт): звать перед чтением query / таблиц экономики при background_steps
func sync() -> void:
	var st := stepper if stepper != null else _find_stepper()
	if st != null:
		st.sync()


## Пока фон не разрешён, SimStepper делает каждый шаг на главном потоке (как шаг перед новым боем)
func restarts_next() -> bool:
	return not background_steps


func step() -> void:
	if game == null:
		return
	if not _replay.is_empty() and game.tick >= int(_replay.get("end_tick", 0)):
		paused = true
		return
	_drain_inbox()
	var was_over := game.over
	game.step()
	ticked.emit(game.tick)
	if game.over and not was_over:
		battle_over.emit(game.winner)
		finished.emit()


func save_replay(path: String) -> bool:
	return game != null and Replay.save(path, game.replay_record())


func _process(delta: float) -> void:
	if game == null or paused:
		return
	_acc += delta * time_scale
	var guard := 0
	while _acc >= DT and guard < 12:
		_acc -= DT
		step()
		guard += 1
	if guard >= 12:
		_acc = 0.0
	alpha = clampf(_acc / DT, 0.0, 1.0)


func _exit_tree() -> void:
	if save_path != "" and game != null:
		save_replay(save_path)


## Входящие → очередь игры (на потоке шага): приказ получает такт tick + input_delay, как при game.submit
func _drain_inbox() -> void:
	_inbox_mx.lock()
	if _inbox.is_empty():
		_inbox_mx.unlock()
		return
	var cmds := _inbox
	_inbox = []
	_inbox_mx.unlock()
	for c in cmds:
		game.submit(local_player, c)


## Шагатель вида этого драйвера: BattleView (или его наследник) держит связь started → _on_started;
## при фоне связь переходит к записи SimStepper (лямбда шагателя)
func _find_stepper() -> SimStepper:
	for c: Dictionary in get_signal_connection_list(&"started"):
		var o: Object = (c["callable"] as Callable).get_object()
		if o is SimStepper:
			return o as SimStepper
		if o is BattleView:
			return (o as BattleView).stepper()
	return null


func _attach() -> void:
	_inbox_mx.lock()
	_inbox.clear()        # приказы прошлой игры не переходят в новую
	_inbox_mx.unlock()
	query = game.query
	local_player = 0
	sim = game.port.battle()
	_acc = 0.0
	alpha = 0.0
	paused = false
	if sim:
		wire_sim(sim)
	started.emit(current_seed)
