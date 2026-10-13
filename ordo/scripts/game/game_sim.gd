class_name GameSim
extends RefCounted
## Симуляция «Города» (ARCHITECTURE §5.1, §7.4; CONTRACT §10): фиксированный такт 1/30 с и порядок
## приказы → ИИ → econ.pre_step → nav (если менялась) → пути → ядро → econ.post_step → медленные шаги →
## победа → контрольная сумма раз в 30 тактов. Только RefCounted, без Node, Time, OS и randf.
##
## Реализации договоров берутся по имени класса, если они уже есть в проекте (после слияния пакетов):
## NavGrid, CombatPortBattle, EconomySim; иначе — заглушки NavStub, CombatPortStub, EconStub.
## До setup() можно задать impl = {"port": "stub" | объект, "nav": …, "econ": …, "defs": Defs}.
##
##   var g := GameSim.new()
##   g.setup(MapValley.MAP, [{faction = &"kokand", team = 0, ctrl = PlayerTable.Ctrl.HUMAN},
##                          {faction = &"kipchak", team = 1, ctrl = PlayerTable.Ctrl.AI, difficulty = 0}], 7)
##   g.submit(0, SimCmd.move(ids, Vector2(10, 20)))
##   g.step()

const DT := BattleSim.DT
const CHECK_EVERY := 30
## Фазы такта для замеров: prof.mark(фаза) зовётся после каждой фазы (prof — объект теста, не симуляции)
enum Ph { ORDERS, AI, ECON_PRE, NAV, KERNEL, ECON_POST, ECON_SLOW, VICTORY, CHECKSUM, COUNT }

var tick := 0
var seed := 1
var defs: Defs
var rules: Dictionary
var rules_id := &"GOROD"
var map_id := "valley"
var port: CombatPort
var nav: NavApi
var econ: EconApi
var events: SimEvents
var queue: CommandQueue
var orders: Orders
var ai: Array[AiController] = []
var victory: Victory
var query: GameQuery
var checksums := PackedInt64Array()
var players_cfg: Array[Dictionary] = []
## Какие реализации взять (до setup): "auto" (по умолчанию), "stub" или готовый объект
var impl := {}
## Объект замеров (тесты): mark(фаза: int)
var prof: Object = null
## Игра кончилась (Victory): остались игроки одной команды; winner — команда (−1 — никто)
var over: bool:
	get:
		return victory != null and victory.over
var winner: int:
	get:
		return victory.winner_team if victory != null else -1

var _ai_out: Array[PackedInt32Array] = []
var _nav_seen := 0


## players: [{faction, team, ctrl, difficulty}]; карта — MapValley.MAP или Defs.maps[id]
func setup(map: Dictionary, players: Array, p_seed: int, p_rules_id := &"GOROD") -> void:
	seed = p_seed
	rules_id = p_rules_id
	defs = impl.get("defs", null) if impl.get("defs", null) is Defs else Defs.shared()
	rules = defs.rules_of(rules_id)
	map_id = String(map.get("id", "valley"))
	players_cfg.clear()
	for pc: Dictionary in players:
		players_cfg.append(pc.duplicate(true))
	tick = 0
	checksums.clear()
	ai.clear()
	events = SimEvents.new()
	nav = _make("nav", &"NavGrid", NavStub)
	port = _make("port", &"CombatPortBattle", CombatPortStub)
	econ = _make("econ", &"EconomySim", EconStub)
	var teams := 0
	for pc: Dictionary in players_cfg:
		teams = maxi(teams, int(pc.get("team", 0)) + 1)
	nav.setup(Terrain.info(), defs, econ, port)
	port.setup(defs, nav, {"teams": maxi(teams, 2), "homes": MapSetup.homes(map, players_cfg),
		"corpse_s": rules.get("corpse_s", -1), "bounds_origin": nav.origin,
		"bounds_size": Vector2(nav.w, nav.h) * NavApi.CELL, "victory": "none", "flee": "home"})
	econ.setup(defs, rules, port, nav, events, seed)
	queue = CommandQueue.new()
	queue.input_delay = maxi(1, int(rules.get("input_delay", 1)))
	victory = Victory.new()
	victory.setup(econ, port, events)
	orders = Orders.new()
	orders.setup(self)
	query = GameQueryImpl.new(self)
	MapSetup.populate(self, map, players_cfg)
	_nav_seen = nav.version


## Приказ игрока (интерфейс, сценарий, сеть): исполнится на такте tick + input_delay
func submit(player: int, cmd: PackedInt32Array) -> void:
	queue.push(player, tick, cmd)


func step() -> void:
	tick += 1
	events.tick = tick
	for cmd in queue.take(tick):
		orders.apply(cmd)
	if prof:
		prof.call("mark", Ph.ORDERS)
	for a in ai:
		if (tick + a.phase) % a.period == 0:
			a.think(tick, query, _ai_out)
			if not a.notes.is_empty():
				_apply_notes(a)
	for c in _ai_out:
		queue.push(c[SimCmd.H_PLAYER], tick, c, true)
	_ai_out.clear()
	if prof:
		prof.call("mark", Ph.AI)
	econ.pre_step(tick)
	if prof:
		prof.call("mark", Ph.ECON_PRE)
	if nav.version != _nav_seen:
		_nav_seen = nav.version
		port.on_nav_changed()
	nav.service(tick)
	port.deliver_paths()
	if prof:
		prof.call("mark", Ph.NAV)
	port.step()
	if prof:
		prof.call("mark", Ph.KERNEL)
	econ.post_step(tick, port.take_deaths(), port.take_structure_hits(), port.take_arrivals())
	if prof:
		prof.call("mark", Ph.ECON_POST)
	if tick % 30 == 0:
		econ.slow_step(tick)
	if tick % 150 == 75:
		econ.fields_step(tick)
	if prof:
		prof.call("mark", Ph.ECON_SLOW)
	victory.check(tick)
	if prof:
		prof.call("mark", Ph.VICTORY)
	if tick % CHECK_EVERY == 0:
		checksums.append(checksum())
	if prof:
		prof.call("mark", Ph.CHECKSUM)


## Сумма состояния: ядро, экономика, навигация, ИИ (с их генераторами), победа, такт
func checksum() -> int:
	var h := _mix(17, tick)
	h = _mix(h, port.checksum())
	h = _mix(h, econ.checksum())
	h = _mix(h, nav.checksum())
	for a in ai:
		h = _mix(h, a.checksum())
	h = _mix(h, victory.checksum())
	return h


## Запись повтора: зерно, карта, Defs.hash(), правила, игроки, журнал внешних приказов, контрольные суммы
func replay_record() -> Dictionary:
	return {"version": Replay.VERSION, "seed": seed, "map_id": map_id, "defs_hash": defs.hash(),
		"rules_id": String(rules_id), "players": players_cfg.duplicate(true),
		"log": SimCmd.encode(queue.external_log()), "end_tick": tick, "checksums": checksums.duplicate()}


## Игра из записи повтора (ещё не прогнана): null, если запись не подходит (Replay.last_error)
static func from_replay(d: Dictionary) -> GameSim:
	return Replay.make_game(d)


# ================================================================= служебное

func _apply_notes(a: AiController) -> void:
	for n: Array in a.notes:
		match int(n[0]):
			AiController.NOTE_EVENT:
				events.push(int(n[1]), int(n[2]), int(n[3]), int(n[4]), int(n[5]), n[6])
			AiController.NOTE_REMOVE:
				var hs: PackedInt32Array = n[1]
				for h in hs:
					if port.alive(h):
						port.remove(h)
	a.notes.clear()


func _make(key: String, cls: StringName, stub: GDScript) -> Object:
	var v: Variant = impl.get(key, "auto")
	if v is Object:
		return v
	if String(v) != "stub":
		var path := _class_path(cls)
		if path != "":
			return (load(path) as GDScript).new()
	return stub.new()


static func _class_path(cls: StringName) -> String:
	for c: Dictionary in ProjectSettings.get_global_class_list():
		if c["class"] == cls:
			return c["path"]
	return ""


static func _mix(h: int, v: int) -> int:
	return ((h * 1000003) ^ (v & 0xFFFFFFFF)) & 0xFFFFFFFFFF
