class_name GameDriver
extends SimDriver
## Узел «Города» в scenes/gorod/gorod.tscn (ARCHITECTURE §7.4): шагает GameSim как SimDriver (30 Гц,
## не больше 12 шагов за кадр, пауза и скорость — локальны), отдаёт сигналы ядра для эффектов (BattleFx)
## и окно чтения query (GameQueryImpl) для вида и интерфейса — так же, как FakeCityDriver до I4.
##
## Аргументы запуска (Ordo.arg): --seed=N, --faction=kokand|kipchak, --difficulty=0..2, --ai_vs_ai,
## --replay=путь (смотреть повтор), --save_replay=путь (записать повтор при выходе).

signal ticked(tick: int)

## Запускаться самому при входе в дерево
@export var autostart := true
@export var player_faction := &"kokand"
@export var difficulty := 0

var game: GameSim
var query: GameQuery
var local_player := 0
var replay_path := ""
var save_path := ""

var _replay := {}


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
	var ctrl0 := PlayerTable.Ctrl.HUMAN
	var ordo := get_node_or_null("/root/Ordo")
	if ordo and ordo.has_arg("ai_vs_ai"):
		ctrl0 = PlayerTable.Ctrl.AI
	var players: Array[Dictionary] = [
		{"faction": p_faction, "team": 0, "ctrl": ctrl0, "difficulty": p_difficulty},
		{"faction": other, "team": 1, "ctrl": PlayerTable.Ctrl.AI, "difficulty": p_difficulty}]
	game = GameSim.new()
	game.setup(MapValley.MAP, players, p_seed)
	_attach()


## Смотреть повтор (приказы — из записи; свои приказы игнорируются)
func start_replay(path: String) -> bool:
	_replay = Replay.load_file(path)
	var g: GameSim = null
	if not _replay.is_empty():
		g = Replay.make_game(_replay)
	if g == null:
		push_warning("GameDriver: повтор не открыт: %s" % Replay.last_error)
		_replay = {}
		start_game(1, player_faction, difficulty)
		return false
	game = g
	current_seed = game.seed
	_attach()
	return true


## Приказ местного игрока (интерфейс)
func issue(cmd: PackedInt32Array) -> void:
	if game and _replay.is_empty():
		game.submit(local_player, cmd)


func step() -> void:
	if game == null:
		return
	if not _replay.is_empty() and game.tick >= int(_replay.get("end_tick", 0)):
		paused = true
		return
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


func _attach() -> void:
	query = game.query
	local_player = 0
	sim = game.port.battle()
	_acc = 0.0
	alpha = 0.0
	paused = false
	if sim:
		wire_sim(sim)
	started.emit(current_seed)
