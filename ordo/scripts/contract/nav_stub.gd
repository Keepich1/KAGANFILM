class_name NavStub
extends NavApi
## Заглушка навигации (ARCHITECTURE §19.0 #7) для пакетов до I1: открытое поле.
##   • всё проходимо, reachable — всегда; путь — прямо к цели ([goal]); билеты служатся в service();
##   • расстановка: только границы карты и пересечение со штампами (прямоугольники клеток);
##   • plan_wall — звенья по прямой с шагом len − overlap; snap_on_wall — NOT_ON_WALL.
## Детерминирована; version растёт на каждом штампе/снятии.

var _defs: Defs
var _stamps := {}              # b_h → [Rect2i, team]  (порядок вставки — детерминирован)
var _tickets := {}             # ticket → PathResult (null — ещё в очереди)
var _queue: Array[Array] = []  # [ticket, from, to]
var _next_ticket := 1


func setup(info: Dictionary, defs: Defs, econ: EconApi, port: CombatPort) -> void:
	_defs = defs
	var n := int(info.get("size", 513))
	var spacing := float(info.get("spacing", 2.0))
	var o: Array = info.get("origin", [-512.0, -512.0])
	origin = Vector2(float(o[0]), float(o[1]))
	w = int((n - 1) * spacing / CELL)
	h = w
	version = 0


func passable(team: int, c: int) -> bool:
	return c >= 0 and c < w * h


func reachable(team: int, a: Vector2, b: Vector2) -> bool:
	return true


func nearest_passable(team: int, p: Vector2, max_r := 40.0) -> Vector2:
	var lo := origin + Vector2(0.5, 0.5)
	var hi := origin + Vector2(w, h) * CELL - Vector2(0.5, 0.5)
	return p.clamp(lo, hi)


func structure_at(p: Vector2) -> int:
	var c := cell_of(p)
	if c < 0:
		return 0
	var cell := Vector2i(c % w, c / w)
	for b_h: int in _stamps:
		if (_stamps[b_h][0] as Rect2i).has_point(cell):
			return b_h
	return 0


func static_grid() -> PackedByteArray:
	var g := PackedByteArray()
	g.resize(w * h)
	return g


func speed_grid() -> PackedByteArray:
	var g := PackedByteArray()
	g.resize(w * h)
	g.fill(16)
	return g


func stamp_building(b_h: int, team: int, center: Vector2, btype: int, rot_q: int) -> Rect2i:
	var r := NavApi.footprint(_defs, btype, center, rot_q, origin)
	_stamps[b_h] = [r, team]
	version += 1
	return r


func stamp_link(b_h: int, team: int, a: Vector2, b: Vector2, btype: int) -> Rect2i:
	var ca := ((a - origin) / CELL).floor()
	var cb := ((b - origin) / CELL).floor()
	var lo := Vector2i(mini(int(ca.x), int(cb.x)), mini(int(ca.y), int(cb.y)))
	var hi := Vector2i(maxi(int(ca.x), int(cb.x)), maxi(int(ca.y), int(cb.y)))
	var r := Rect2i(lo, hi - lo + Vector2i.ONE)
	_stamps[b_h] = [r, team]
	version += 1
	return r


func unstamp(b_h: int) -> void:
	if _stamps.erase(b_h):
		version += 1


func request(team: int, from: Vector2, to: Vector2, client: int, prio := 0) -> int:
	var t := _next_ticket
	_next_ticket += 1
	_tickets[t] = null
	_queue.append([t, from, to])
	return t


func service(tick: int) -> void:
	for q in _queue:
		if _tickets.has(q[0]):
			_tickets[q[0]] = _straight(q[1], q[2])
	_queue.clear()


func result(ticket: int) -> PathResult:
	return _tickets.get(ticket, null)


func release(ticket: int) -> void:
	_tickets.erase(ticket)


func stale(r: PathResult) -> bool:
	return false


func find_now(team: int, from: Vector2, to: Vector2) -> PathResult:
	return _straight(from, to)


func check_place(player: int, btype: int, center: Vector2, rot_q: int) -> int:
	var r := NavApi.footprint(_defs, btype, center, rot_q, origin)
	if r.position.x < 0 or r.position.y < 0 or r.end.x > w or r.end.y > h:
		return Why.OUT_OF_MAP
	for b_h: int in _stamps:
		if (_stamps[b_h][0] as Rect2i).intersects(r):
			return Why.OVERLAP
	return Why.OK


func place_cells(player: int, btype: int, center: Vector2, rot_q: int) -> PackedByteArray:
	var r := NavApi.footprint(_defs, btype, center, rot_q, origin)
	var out := PackedByteArray()
	for row in range(r.position.y, r.end.y):
		for col in range(r.position.x, r.end.x):
			var why := Why.OK
			if col < 0 or row < 0 or col >= w or row >= h:
				why = Why.OUT_OF_MAP
			else:
				for b_h: int in _stamps:
					if (_stamps[b_h][0] as Rect2i).has_point(Vector2i(col, row)):
						why = Why.OVERLAP
						break
			out.append(why)
	return out


func snap(btype: int, p: Vector2, rot_q: int) -> Vector2:
	return NavApi.snap_center(_defs, btype, p, rot_q, origin)


func plan_wall(player: int, wtype: int, pts: PackedVector2Array) -> Dictionary:
	var centers := PackedVector2Array()
	var rots := PackedFloat32Array()
	var why := PackedByteArray()
	var pitch := maxf(_defs.b_link_len[wtype] - _defs.b_link_overlap[wtype], 0.5)
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := b - a
		var k := maxi(1, ceili(seg.length() / pitch - 0.001))
		var rot := atan2(seg.x, seg.y) - PI / 2.0   # звено вытянуто по своей оси X
		for j in k:
			var c := a + seg * ((j + 0.5) / k)
			centers.append(c)
			rots.append(rot)
			why.append(Why.OK if cell_of(c) >= 0 else Why.OUT_OF_MAP)
	var cost := PackedInt32Array()
	cost.resize(_defs.R)
	for r in _defs.R:
		cost[r] = _defs.b_cost[wtype * _defs.R + r] * centers.size()
	return {"centers": centers, "rots": rots, "why": why, "cost": cost}


func snap_on_wall(player: int, btype: int, p: Vector2) -> Dictionary:
	return {"why": Why.NOT_ON_WALL, "center": p, "rot": 0.0, "removes": PackedInt32Array()}


func ring_slots(player: int, center: Vector2, btypes: PackedInt32Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := btypes.size()
	var radius := 18.0 + 3.0 * n
	for i in n:
		var a := TAU * i / maxi(n, 1)
		out.append(center + Vector2(sin(a), cos(a)) * radius)
	return out


func checksum() -> int:
	return version


func _straight(from: Vector2, to: Vector2) -> PathResult:
	var r := PathResult.new()
	r.pts = PackedVector2Array([to])
	r.cost = from.distance_to(to)
	r.issued_ver = version
	return r
