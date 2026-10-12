class_name NavApi
extends RefCounted
## Навигация «Города» (ARCHITECTURE §7.2, §9, §10): сетка 4 м, пути, расстановка, стены.
## NAV делает NavGrid extends NavApi (Regions, PathService, Placement, WallTool за ней);
## до I1 все пакеты работают на NavStub. Этот класс — договор: методы без реализации
## пишут push_error и возвращают значения по умолчанию.
##
## Клетки: индекс c = row * w + col, col — по x, row — по z; центр клетки — cell_center(c).
## След постройки (§6.4): cw = ceili(size.x / 4 − 0.1), ch = ceili(size.y / 4 − 0.1), поворот на
## нечётную четверть меняет их местами; центр — в центре клетки при нечётном числе клеток и в углу
## клетки при чётном (footprint / snap_center ниже — общие для NavGrid, NavStub и ECON).
## version растёт при каждом штампе/снятии (GameSim сравнивает и зовёт CombatPort.on_nav_changed).
##
## Только ведущий меняет этот файл.

const CELL := 4.0
const SECTOR := 16
enum F { STATIC = 1, WATER = 2, FORD = 4, STRUCT = 8, WALL = 16, GATE = 32, SOFT = 64, NODE = 128 }
enum Why { OK, OVERLAP, SLOPE, WATER, OUT_OF_MAP, NOT_NEAR, NOT_ON_WALL, NO_TERRITORY, ENEMY_UNITS, NO_RES, NOT_ALLOWED }

var w := 0
var h := 0
var origin := Vector2.ZERO
var version := 0


## info — Terrain.info() (size, spacing, origin); econ/port — для правил расстановки
func setup(info: Dictionary, defs: Defs, econ: EconApi, port: CombatPort) -> void:
	_todo("setup")


# ---------------------------------------------------------------- сетка

## Клетка точки, −1 — вне карты
func cell_of(p: Vector2) -> int:
	var cx := floori((p.x - origin.x) / CELL)
	var cz := floori((p.y - origin.y) / CELL)
	if cx < 0 or cz < 0 or cx >= w or cz >= h:
		return -1
	return cz * w + cx


func cell_center(c: int) -> Vector2:
	return origin + (Vector2(c % maxi(w, 1), c / maxi(w, 1)) + Vector2(0.5, 0.5)) * CELL


func passable(team: int, c: int) -> bool:
	_todo("passable")
	return false


func reachable(team: int, a: Vector2, b: Vector2) -> bool:                 # region graph, O(1) amortised
	_todo("reachable")
	return false


func nearest_passable(team: int, p: Vector2, max_r := 40.0) -> Vector2:
	_todo("nearest_passable")
	return p


func structure_at(p: Vector2) -> int:                                      # building handle or 0
	_todo("structure_at")
	return 0


func static_grid() -> PackedByteArray:                                     # terrain blocks, for kernel collision
	_todo("static_grid")
	return PackedByteArray()


func speed_grid() -> PackedByteArray:                                      # ×16 speed factor per cell
	_todo("speed_grid")
	return PackedByteArray()


func stamp_building(b_h: int, team: int, center: Vector2, btype: int, rot_q: int) -> Rect2i:
	_todo("stamp_building")
	return Rect2i()


func stamp_link(b_h: int, team: int, a: Vector2, b: Vector2, btype: int) -> Rect2i:   # 4-connected supercover
	_todo("stamp_link")
	return Rect2i()


func unstamp(b_h: int) -> void:
	_todo("unstamp")


# ---------------------------------------------------------------- пути

func request(team: int, from: Vector2, to: Vector2, client: int, prio := 0) -> int:  # ticket > 0
	_todo("request")
	return 0


func service(tick: int) -> void:
	_todo("service")


func result(ticket: int) -> PathResult:                                    # null until served
	_todo("result")
	return null


func release(ticket: int) -> void:
	_todo("release")


func stale(r: PathResult) -> bool:                                         # crosses a sector changed since issue
	_todo("stale")
	return false


func find_now(team: int, from: Vector2, to: Vector2) -> PathResult:        # tests, tools
	_todo("find_now")
	return null


# ---------------------------------------------------------------- расстановка (authoritative for SimCmd; the ghost uses the same calls)

func check_place(player: int, btype: int, center: Vector2, rot_q: int) -> int:          # Why
	_todo("check_place")
	return Why.NOT_ALLOWED


func place_cells(player: int, btype: int, center: Vector2, rot_q: int) -> PackedByteArray:  # Why per footprint cell
	_todo("place_cells")
	return PackedByteArray()


func snap(btype: int, p: Vector2, rot_q: int) -> Vector2:
	_todo("snap")
	return p


## {centers: PackedVector2Array, rots: PackedFloat32Array, why: PackedByteArray, cost: PackedInt32Array}
func plan_wall(player: int, wtype: int, pts: PackedVector2Array) -> Dictionary:
	_todo("plan_wall")
	return {"centers": PackedVector2Array(), "rots": PackedFloat32Array(), "why": PackedByteArray(),
		"cost": PackedInt32Array()}


## {why, center: Vector2, rot: float, removes: PackedInt32Array (link handles)}
func snap_on_wall(player: int, btype: int, p: Vector2) -> Dictionary:
	_todo("snap_on_wall")
	return {"why": Why.NOT_ON_WALL, "center": p, "rot": 0.0, "removes": PackedInt32Array()}


func ring_slots(player: int, center: Vector2, btypes: PackedInt32Array) -> PackedVector2Array:   # köч unpack
	_todo("ring_slots")
	return PackedVector2Array()


func checksum() -> int:
	_todo("checksum")
	return 0


# ---------------------------------------------------------------- общие правила следа (§6.4)

## Прямоугольник следа в клетках (col, row, cw, ch) для центра center
static func footprint(defs: Defs, btype: int, center: Vector2, rot_q: int, p_origin: Vector2) -> Rect2i:
	var c := defs.cells_of(btype, rot_q)
	var c0 := roundi((center.x - p_origin.x) / CELL - c.x * 0.5)
	var r0 := roundi((center.y - p_origin.y) / CELL - c.y * 0.5)
	return Rect2i(c0, r0, c.x, c.y)


## Центр постройки, прижатый к сетке: нечётное число клеток — центр клетки, чётное — угол
static func snap_center(defs: Defs, btype: int, p: Vector2, rot_q: int, p_origin: Vector2) -> Vector2:
	var c := defs.cells_of(btype, rot_q)
	var q := (p - p_origin) / CELL
	var sx := (floorf(q.x) + 0.5) if c.x % 2 == 1 else roundf(q.x)
	var sz := (floorf(q.y) + 0.5) if c.y % 2 == 1 else roundf(q.y)
	return p_origin + Vector2(sx, sz) * CELL


func _todo(what: String) -> void:
	push_error("NavApi.%s: не реализовано (%s)" % [what, get_script().resource_path])
