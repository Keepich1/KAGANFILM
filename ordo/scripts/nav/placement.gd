class_name Placement
extends RefCounted
## Правила места постройки (ARCHITECTURE §10): один и тот же расчёт для приказа (ECON) и призрака
## (VIEW/UI). Состояние навигации не меняет — можно звать откуда угодно.
##
## Клетка следа (place_cells) — первая причина по порядку:
##   OUT_OF_MAP (вне карты) → OVERLAP (штамп, ядро жилы, живое дерево или жила в клетке) →
##   WATER (вода, если place.water = false; глубокая вода всегда) → SLOPE (крутизна клетки).
## След целиком (у прошедших клеток):
##   SLOPE (перепад высот по углам клеток следа > place.max_slope, кроме water) →
##   NOT_NEAR (near — жила нужного ресурса ближе r; water_zone — в зоне воды; across_river — у реки) →
##   NOT_ALLOWED (across_river — на броде) → NO_TERRITORY → ENEMY_UNITS (враг внутри следа).
## check_place = худшая причина по этому порядку; затем — NOT_ALLOWED (выключенная постройка или
## чужая сторона) и NO_RES (не по карману). Ворота (on_wall "align") — через WallTool.snap_on_wall;
## башня (on_wall "replace") может стоять на своих звеньях стены (они уходят).
## Без EconApi (тесты, вид без экономики) территория, near, сторона и цена не проверяются; если же econ
## был дан в setup и уже освобождён — NOT_ALLOWED на всё (NavGrid.econ_lost), а не молчаливое OK.

const ORDER := [NavApi.Why.OUT_OF_MAP, NavApi.Why.OVERLAP, NavApi.Why.WATER, NavApi.Why.SLOPE,
	NavApi.Why.NOT_ON_WALL, NavApi.Why.NOT_NEAR, NavApi.Why.NOT_ALLOWED, NavApi.Why.NO_TERRITORY,
	NavApi.Why.ENEMY_UNITS, NavApi.Why.NO_RES]
const FORD_R := 40.0              # м: ближе к броду тўғон не ставится
const WATER_ZONE_MIN := 128       # вода ECON (0..255): от этого — зона воды
## Кольца и направления раскладки көч (без тригонометрии: 16 единичных векторов)
const RING_R := [18.0, 26.0, 34.0, 42.0, 50.0, 60.0, 72.0, 86.0, 100.0]
const DIRS := [Vector2(0.0, 1.0), Vector2(0.382683, 0.92388), Vector2(0.707107, 0.707107),
	Vector2(0.92388, 0.382683), Vector2(1.0, 0.0), Vector2(0.92388, -0.382683), Vector2(0.707107, -0.707107),
	Vector2(0.382683, -0.92388), Vector2(0.0, -1.0), Vector2(-0.382683, -0.92388), Vector2(-0.707107, -0.707107),
	Vector2(-0.92388, -0.382683), Vector2(-1.0, 0.0), Vector2(-0.92388, 0.382683), Vector2(-0.707107, 0.707107),
	Vector2(-0.382683, 0.92388)]

var _units := PackedInt32Array()


func check_place(g: NavGrid, player: int, btype: int, center: Vector2, rot_q: int) -> int:
	g.sync_node_index()
	var d := g.defs
	if d == null or btype < 0 or btype >= d.b_ids.size() or d.b_enabled[btype] == 0 or g.econ_lost():
		return NavApi.Why.NOT_ALLOWED
	if not _faction_ok(g, player, btype):
		return NavApi.Why.NOT_ALLOWED
	var place: Dictionary = d.b_place[btype]
	var why: int
	if String(place.get("on_wall", "")) == "align":
		why = int(g.walls.snap_on_wall(g, player, btype, center)["why"])
	else:
		var cells := place_cells(g, player, btype, center, rot_q)
		why = NavApi.Why.OK
		for v in cells:
			if v != NavApi.Why.OK and (why == NavApi.Why.OK or ORDER.find(v) < ORDER.find(why)):
				why = v
		if cells.is_empty():
			why = NavApi.Why.OUT_OF_MAP
	if why != NavApi.Why.OK:
		return why
	if not _can_pay(g, player, d.building_cost(btype)):
		return NavApi.Why.NO_RES
	return NavApi.Why.OK


## Причина по каждой клетке следа (строки по z, в строке — по x)
func place_cells(g: NavGrid, player: int, btype: int, center: Vector2, rot_q: int) -> PackedByteArray:
	g.sync_node_index()
	var out := PackedByteArray()
	var d := g.defs
	if d == null or btype < 0 or btype >= d.b_ids.size():
		return out
	var r := NavApi.footprint(d, btype, center, rot_q, g.origin)
	var place: Dictionary = d.b_place[btype]
	var team := g.team_of_player(player)
	var any_ok := false
	var lost := g.econ_lost()
	for row in range(r.position.y, r.end.y):
		for col in range(r.position.x, r.end.x):
			var why := NavApi.Why.NOT_ALLOWED if lost else cell_why(g, col, row, team, place, d.b_kind[btype])
			out.append(why)
			any_ok = any_ok or why == NavApi.Why.OK
	if any_ok:
		var fw := footprint_why(g, player, btype, center, r, place)
		if fw != NavApi.Why.OK:
			for i in out.size():
				if out[i] == NavApi.Why.OK:
					out[i] = fw
	return out


## Причина для одной клетки (col, row) — без учёта следа целиком
func cell_why(g: NavGrid, col: int, row: int, team: int, place: Dictionary, kind: int) -> int:
	if col < 0 or row < 0 or col >= g.w or row >= g.h:
		return NavApi.Why.OUT_OF_MAP
	var c := row * g.w + col
	var f := g.flags[c]
	var bh := g.struct_of[c]
	if bh != 0:
		var ok_own := false
		if String(place.get("on_wall", "")) == "replace":
			var rec := g.stamp_of(bh)
			ok_own = not rec.is_empty() and rec[0] == team and rec[2] & NavApi.F.WALL != 0 and g.flags[c] & NavApi.F.GATE == 0
		if not ok_own:
			return NavApi.Why.OVERLAP
	if f & NavApi.F.NODE or g.node_in_cell(c):
		return NavApi.Why.OVERLAP
	var water_ok := bool(place.get("water", false))
	if f & NavApi.F.WATER:
		if not water_ok:
			return NavApi.Why.WATER
		return NavApi.Why.OK
	if f & NavApi.F.STATIC:
		return NavApi.Why.SLOPE
	return NavApi.Why.OK


## Причина для следа целиком (rect — клетки следа)
func footprint_why(g: NavGrid, player: int, btype: int, center: Vector2, r: Rect2i, place: Dictionary) -> int:
	var d := g.defs
	var water_ok := bool(place.get("water", false))
	# перепад высот по углам клеток следа
	if not water_ok and not g.flat:
		var lo := INF
		var hi := -INF
		for row in range(r.position.y, r.end.y + 1):
			for col in range(r.position.x, r.end.x + 1):
				var hh := Terrain.height_at(g.origin.x + col * NavApi.CELL, g.origin.y + row * NavApi.CELL)
				lo = minf(lo, hh)
				hi = maxf(hi, hh)
		if hi - lo > float(place.get("max_slope", 1.2)):
			return NavApi.Why.SLOPE
	if bool(place.get("across_river", false)):
		var wet := false
		for row in range(r.position.y, r.end.y):
			for col in range(r.position.x, r.end.x):
				wet = wet or g.flags[row * g.w + col] & NavApi.F.WATER != 0
		if not wet:
			return NavApi.Why.NOT_NEAR
		var fd: Array = Terrain.info().get("ford", []) if not g.flat else []
		if fd.size() >= 2 and center.distance_squared_to(Vector2(float(fd[0]), float(fd[1]))) < FORD_R * FORD_R:
			return NavApi.Why.NOT_ALLOWED
	if bool(place.get("water_zone", false)) and not _in_water_zone(g, center):
		return NavApi.Why.NOT_NEAR
	var near: Dictionary = place.get("near", {})
	if not near.is_empty() and g.econ != null and g.econ.nodes != null:
		var mask := 0
		for nt: int in (near.get("nodes", PackedInt32Array()) as PackedInt32Array):
			if nt >= 0:
				mask |= 1 << d.n_res[nt]
		if g.econ.node_near(mask, center, float(near.get("r", 26.0))) == 0:
			return NavApi.Why.NOT_NEAR
	if bool(place.get("territory", true)) and g.econ != null and g.econ.players != null \
			and player >= 0 and player < g.econ.players.count and not g.econ.in_territory(player, center):
		return NavApi.Why.NO_TERRITORY
	if enemy_inside(g, g.team_of_player(player), r):
		return NavApi.Why.ENEMY_UNITS
	return NavApi.Why.OK


## Враг внутри прямоугольника клеток r (CombatPort.units_near)
func enemy_inside(g: NavGrid, team: int, r: Rect2i) -> bool:
	if g.port == null:
		return false
	var lo := g.origin + Vector2(r.position) * NavApi.CELL
	var hi := g.origin + Vector2(r.end) * NavApi.CELL
	var c := (lo + hi) * 0.5
	var rad := (hi - lo).length() * 0.5
	if g.port.units_near(team, c, rad, true, 0, _units) == 0:
		return false
	for u in _units:
		var p := g.port.pos(u)
		if p.x >= lo.x and p.x <= hi.x and p.y >= lo.y and p.y <= hi.y:
			return true
	return false


## Места для построек после көч: ставка — в центре, остальные — по кольцам 18…100 м
func ring_slots(g: NavGrid, player: int, center: Vector2, btypes: PackedInt32Array) -> PackedVector2Array:
	g.sync_node_index()
	var out := PackedVector2Array()
	var d := g.defs
	var taken: Array[Rect2i] = []
	for i in btypes.size():
		var bt := btypes[i]
		if d == null or bt < 0 or bt >= d.b_ids.size():
			out.append(center)
			continue
		var found := false
		var p := center
		if d.b_flags[bt] & Defs.BF_HQ:
			p = NavApi.snap_center(d, bt, center, 0, g.origin)
			found = _slot_ok(g, player, bt, p, taken)
		var radii: Array = RING_R
		for rr: float in radii:
			if found:
				break
			for k in DIRS.size():
				var dir: Vector2 = DIRS[(k + i * 5) % DIRS.size()]
				p = NavApi.snap_center(d, bt, center + dir * rr, 0, g.origin)
				if _slot_ok(g, player, bt, p, taken):
					found = true
					break
		if not found:
			p = NavApi.snap_center(d, bt, center, 0, g.origin)
		out.append(p)
		taken.append(NavApi.footprint(d, bt, p, 0, g.origin).grow(1))
	return out


func _slot_ok(g: NavGrid, player: int, bt: int, p: Vector2, taken: Array[Rect2i]) -> bool:
	var r := NavApi.footprint(g.defs, bt, p, 0, g.origin)
	for t in taken:
		if t.intersects(r):
			return false
	var place: Dictionary = g.defs.b_place[bt].duplicate()
	place["territory"] = false
	var team := g.team_of_player(player)
	for row in range(r.position.y, r.end.y):
		for col in range(r.position.x, r.end.x):
			if cell_why(g, col, row, team, place, g.defs.b_kind[bt]) != NavApi.Why.OK:
				return false
	place.erase("near")
	return footprint_why(g, player, bt, p, r, place) == NavApi.Why.OK


func _faction_ok(g: NavGrid, player: int, btype: int) -> bool:
	var e := g.econ
	if e == null or e.players == null or player < 0 or player >= e.players.count:
		return true
	var f := e.players.faction[player]
	return f < 0 or f >= g.defs.f_ids.size() or g.defs.b_faction[btype] == g.defs.f_ids[f]


func _can_pay(g: NavGrid, player: int, cost: PackedInt32Array) -> bool:
	var e := g.econ
	if e == null or e.players == null or player < 0 or player >= e.players.count:
		return true
	return e.can_pay(player, cost)


## Зона воды ECON (water_grid, квадратная сетка на всю карту; пусто — без проверки)
func _in_water_zone(g: NavGrid, p: Vector2) -> bool:
	if g.econ == null:
		return true
	var wg := g.econ.water_grid()
	if wg.is_empty():
		return true
	var side := int(sqrt(float(wg.size())))
	if side * side != wg.size():
		return true
	var cs := g.w * NavApi.CELL / side
	var i := clampi(floori((p.x - g.origin.x) / cs), 0, side - 1)
	var j := clampi(floori((p.y - g.origin.y) / cs), 0, side - 1)
	return wg[j * side + i] >= WATER_ZONE_MIN
