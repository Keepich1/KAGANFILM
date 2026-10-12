class_name EconApi
extends RefCounted
## Экономика «Города» (ARCHITECTURE §7.3, §11). ECON делает EconomySim extends EconApi;
## до I2/I3 пакеты работают на EconStub. Этот класс — договор: методы пишут push_error и
## возвращают значения по умолчанию.
##
## Четыре таблицы (players, buildings, nodes, herds) пишет только ECON; остальные читают.
## Обработчики приказов возвращают описатель/номер (> 0) или OK (0) при успехе, а при отказе —
## −Err или −(100 + NavApi.Why); Orders превращает отказ в CMD_REJECTED(player, op, причина).
##
## Только ведущий меняет этот файл.

enum Err { OK = 0, NOT_OWNER = 1, INVALID = 2, NO_RES = 3, POP_CAP = 4, QUEUE_FULL = 5, BAD_PLACE = 6,
	BUSY = 7, NOT_ALLOWED = 8, STALE = 9 }       # handlers return −Err (or −(100 + NavApi.Why))

var players: PlayerTable
var buildings: BuildingTable
var nodes: NodeTable
var herds: HerdTable


func setup(defs: Defs, rules: Dictionary, port: CombatPort, nav: NavApi, events: SimEvents, seed: int) -> void:
	_todo("setup")


# ---------------------------------------------------------------- расстановка карты (MapSetup)

func add_player(team: int, faction: StringName, ctrl: int) -> int:
	_todo("add_player")
	return -1


func spawn_building(p: int, btype: int, center: Vector2, rot_q: int, active := true) -> int:
	_todo("spawn_building")
	return 0


## amount — запас в милли (−1 — из Defs.n_amount_milli); scatter_ref — дерево WorldScatter (ScatterData.ref)
func spawn_node(ntype: int, pos: Vector2, amount := -1, scatter_ref := -1) -> int:
	_todo("spawn_node")
	return 0


## heads — целых голов
func spawn_herd(p: int, htype: int, pen_h: int, heads: int) -> int:
	_todo("spawn_herd")
	return 0


func spawn_worker(p: int, pos: Vector2) -> int:
	_todo("spawn_worker")
	return 0


# ---------------------------------------------------------------- приказы (Orders уже проверил владельца и описатели)

func place_site(p: int, btype: int, center: Vector2, rot_q: int, workers: PackedInt32Array) -> int:
	_todo("place_site")
	return -Err.NOT_ALLOWED


func place_wall(p: int, wtype: int, pts: PackedVector2Array, workers: PackedInt32Array) -> int:   # chain id
	_todo("place_wall")
	return -Err.NOT_ALLOWED


func assign_gather(p: int, workers: PackedInt32Array, source_h: int) -> int:
	_todo("assign_gather")
	return -Err.NOT_ALLOWED


func assign_build(p: int, workers: PackedInt32Array, b_h: int) -> int:    # help build / repair (stage 2)
	_todo("assign_build")
	return -Err.NOT_ALLOWED


func train(p: int, b_h: int, utype: int, count: int) -> int:
	_todo("train")
	return -Err.NOT_ALLOWED


func cancel_train(p: int, b_h: int, index: int) -> int:
	_todo("cancel_train")
	return -Err.NOT_ALLOWED


func set_rally(p: int, b_h: int, at: Vector2, target_h: int) -> int:
	_todo("set_rally")
	return -Err.NOT_ALLOWED


func demolish(p: int, b_h: int) -> int:
	_todo("demolish")
	return -Err.NOT_ALLOWED


func set_recipe(p: int, b_h: int, recipe: int) -> int:
	_todo("set_recipe")
	return -Err.NOT_ALLOWED


func trade(p: int, b_h: int, give: int, take: int, amount_milli: int) -> int:
	_todo("trade")
	return -Err.NOT_ALLOWED


func set_dam(p: int, b_h: int, open: bool) -> int:
	_todo("set_dam")
	return -Err.NOT_ALLOWED


func pack(p: int, b_h: int) -> int:
	_todo("pack")
	return -Err.NOT_ALLOWED


func pack_all(p: int, hq_h: int) -> int:
	_todo("pack_all")
	return -Err.NOT_ALLOWED


func unpack(p: int, arbas: PackedInt32Array, center: Vector2) -> int:
	_todo("unpack")
	return -Err.NOT_ALLOWED


func herd_move(p: int, herd_h: int, to: Vector2) -> int:
	_todo("herd_move")
	return -Err.NOT_ALLOWED


func release_units(units: PackedInt32Array) -> void:      # a non-economy order took these workers off their jobs
	_todo("release_units")


# ---------------------------------------------------------------- такт (только GameSim, §5.1)

func pre_step(tick: int) -> void:
	_todo("pre_step")


func post_step(tick: int, deaths: PackedInt32Array, hits: PackedInt32Array, arrivals: PackedInt32Array) -> void:
	_todo("post_step")


func slow_step(tick: int) -> void:
	_todo("slow_step")


func fields_step(tick: int) -> void:
	_todo("fields_step")


# ---------------------------------------------------------------- запросы (GameQuery, ИИ, Placement)

func res(p: int, r: int) -> int:
	_todo("res")
	return 0


func can_pay(p: int, cost: PackedInt32Array) -> bool:
	_todo("can_pay")
	return false


func node_near(res_mask: int, pos: Vector2, r: float) -> int:
	_todo("node_near")
	return 0


func in_territory(p: int, pos: Vector2) -> bool:
	_todo("in_territory")
	return false


func wall_link_at(p: int, pos: Vector2, r: float) -> int:
	_todo("wall_link_at")
	return 0


func worker_job(u_h: int) -> int:
	_todo("worker_job")
	return 0


func idle_workers(p: int) -> PackedInt32Array:
	_todo("idle_workers")
	return PackedInt32Array()


func arba_cargo(u_h: int) -> int:
	_todo("arba_cargo")
	return 0


## Трава 16 м: байт на клетку (0..255 ~ 0..1000), размеры — GameQuery.field_dims()
func grass_grid() -> PackedByteArray:
	_todo("grass_grid")
	return PackedByteArray()


## Полив 8 м: байт на клетку (0..255 ~ 0..1000)
func water_grid() -> PackedByteArray:
	_todo("water_grid")
	return PackedByteArray()


func building_panel(b_h: int) -> Dictionary:
	_todo("building_panel")
	return {}


func build_menu(p: int, tab: StringName) -> Array[Dictionary]:
	_todo("build_menu")
	return []


func checksum() -> int:
	_todo("checksum")
	return 0


func save_into(d: Dictionary) -> void:
	_todo("save_into")


func load_from(d: Dictionary) -> void:
	_todo("load_from")


func _todo(what: String) -> void:
	push_error("EconApi.%s: не реализовано (%s)" % [what, get_script().resource_path])
