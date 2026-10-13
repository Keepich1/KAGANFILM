class_name WallTool
extends RefCounted
## Стены (ARCHITECTURE §10, ТЗ §6): разметка линии звеньев, ворота и башни на стене.
## Состояние навигации не меняет (зовут и призрак, и ECON).
##
## plan_wall: по каждому отрезку ломаной — k = ⌈длина / шаг⌉ звеньев равномерно (шаг ≤ len − overlap,
## так что соседние звенья заходят друг на друга не меньше overlap); звено — 4-связная полоса клеток
## между его концами (центр ± len/2). Причина звена: OUT_OF_MAP → OVERLAP (чужое или не стена; свои
## звенья той же стены можно продолжать, арыку — свою сеть) → WATER → SLOPE → NO_TERRITORY → ENEMY_UNITS.
## Кроме ключей договора, ответ несёт концы звеньев: a, b (PackedVector2Array) — для stamp_link.
## Поворот звена rot = atan2(x, z) − π/2 (ось X модели вдоль линии; как у NavStub) — только для вида
## и зеркала ядра; решения правил по нему не принимаются.
##
## snap_on_wall (этап 2): ворота (on_wall "align") — на свою стену, по её линии, заменяют звенья под
## собой; башня ("replace") — в клетки сетки у стены, звенья под следом уходят; без стены — как
## обычная постройка. Ответ: {why, center, rot, removes, a, b} (a, b — концы ворот для stamp_link).

const SNAP_R := 6.0               # м: ищем звено стены не дальше
const LINE_EPS := 1.0             # м: звено «на линии» ворот

var _units := PackedInt32Array()


func plan_wall(g: NavGrid, player: int, wtype: int, pts: PackedVector2Array) -> Dictionary:
	var centers := PackedVector2Array()
	var rots := PackedFloat32Array()
	var why := PackedByteArray()
	var ends_a := PackedVector2Array()
	var ends_b := PackedVector2Array()
	var d := g.defs
	var cost := PackedInt32Array()
	cost.resize(d.R if d else 0)
	var res := {"centers": centers, "rots": rots, "why": why, "cost": cost, "a": ends_a, "b": ends_b}
	if d == null or wtype < 0 or wtype >= d.b_ids.size() or d.b_link_len[wtype] <= 0.0:
		return res
	var ln := d.b_link_len[wtype]
	var pitch := maxf(ln - d.b_link_overlap[wtype], 0.5)
	var team := g.team_of_player(player)
	var enabled := d.b_enabled[wtype] != 0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := b - a
		var L := seg.length()
		if L < 0.01:
			continue
		var k := maxi(1, ceili(L / pitch - 0.001))
		var dir := seg / L
		var rot := atan2(seg.x, seg.y) - PI / 2.0
		for j in k:
			var c := a + seg * ((j + 0.5) / k)
			var la := c - dir * (ln * 0.5)
			var lb := c + dir * (ln * 0.5)
			centers.append(c)
			rots.append(rot)
			ends_a.append(la)
			ends_b.append(lb)
			why.append(link_why(g, player, team, wtype, c, la, lb) if enabled else NavApi.Why.NOT_ALLOWED)
	for r in d.R:
		cost[r] = d.b_cost[wtype * d.R + r] * centers.size()
	res["centers"] = centers
	res["rots"] = rots
	res["why"] = why
	res["cost"] = cost
	res["a"] = ends_a
	res["b"] = ends_b
	return res


## Причина для одного звена la→lb
func link_why(g: NavGrid, player: int, team: int, wtype: int, c: Vector2, la: Vector2, lb: Vector2) -> int:
	var d := g.defs
	var link_kind := d.b_kind[wtype] == Defs.BKind.LINK
	var raw := NavRaster.supercover4(la, lb, g.origin, NavApi.CELL)
	var worst := NavApi.Why.OK
	for k in range(0, raw.size(), 2):
		var col := raw[k]
		var row := raw[k + 1]
		var why := NavApi.Why.OK
		if col < 0 or row < 0 or col >= g.w or row >= g.h:
			why = NavApi.Why.OUT_OF_MAP
		else:
			var cc := row * g.w + col
			var f := g.flags[cc]
			var bh := g.struct_of[cc]
			if bh != 0 and not _joinable(g, cc, team, link_kind):
				why = NavApi.Why.OVERLAP
			elif f & NavApi.F.NODE or g.node_in_cell(cc):
				why = NavApi.Why.OVERLAP
			elif f & NavApi.F.WATER and (f & NavApi.F.STATIC or not link_kind):
				why = NavApi.Why.WATER
			elif f & NavApi.F.STATIC:
				why = NavApi.Why.SLOPE
		if why != NavApi.Why.OK and (worst == NavApi.Why.OK or Placement.ORDER.find(why) < Placement.ORDER.find(worst)):
			worst = why
	if worst != NavApi.Why.OK:
		return worst
	var place: Dictionary = d.b_place[wtype]
	if bool(place.get("territory", true)) and g.econ != null and g.econ.players != null \
			and player >= 0 and player < g.econ.players.count and not g.econ.in_territory(player, c):
		return NavApi.Why.NO_TERRITORY
	if g.port != null and g.port.units_near(team, c, d.b_link_len[wtype] * 0.5, true, 0, _units) > 0:
		return NavApi.Why.ENEMY_UNITS
	return NavApi.Why.OK


## Клетку можно продолжать: все её штампы — свои стены (для арыка — своя сеть)
func _joinable(g: NavGrid, c: int, team: int, link_kind: bool) -> bool:
	for bh in g.stamps_at(c):
		var rec := g.stamp_of(bh)
		if rec.is_empty() or rec[0] != team:
			return false
		var bt := rec[1]
		if link_kind:
			if bt < 0 or g.defs.b_flags[bt] & Defs.BF_NETWORK == 0:
				return false
		elif rec[2] & NavApi.F.WALL == 0:
			return false
	return true


func snap_on_wall(g: NavGrid, player: int, btype: int, p: Vector2) -> Dictionary:
	var out := {"why": NavApi.Why.NOT_ON_WALL, "center": p, "rot": 0.0, "removes": PackedInt32Array(),
		"a": p, "b": p}
	var d := g.defs
	if d == null or btype < 0 or btype >= d.b_ids.size():
		out["why"] = NavApi.Why.NOT_ALLOWED
		return out
	var mode := String(d.b_place[btype].get("on_wall", ""))
	if mode == "":
		return out
	var team := g.team_of_player(player)
	var link := _link_near(g, player, team, p)
	if mode == "replace":
		return _snap_tower(g, player, btype, p, team, link)
	if link == 0:
		return out
	var geo := _link_geo(g, link)
	if geo.is_empty():
		return out
	var la: Vector2 = geo[0]
	var dir: Vector2 = geo[1]
	var proj := la + dir * dir.dot(p - la)
	var half := d.b_size[btype].x * 0.5
	var ga := proj - dir * half
	var gb := proj + dir * half
	# звенья своей стены, которые ворота перекрывают по линии
	var removes := PackedInt32Array()
	var seen := {}
	var cells := g.link_cells(ga, gb)
	for c in _cells_around(g, cells):
		for bh in g.stamps_at(c):
			if seen.has(bh):
				continue
			seen[bh] = true
			var rec := g.stamp_of(bh)
			if rec.is_empty() or rec[0] != team or rec[2] & NavApi.F.WALL == 0:
				continue
			var lg := _link_geo(g, bh)
			if lg.is_empty():
				continue
			var a2: Vector2 = lg[0]
			var b2: Vector2 = lg[2]
			var ta := dir.dot(a2 - proj)
			var tb := dir.dot(b2 - proj)
			var mid := (a2 + b2) * 0.5
			var perp := absf(dir.x * (mid.y - proj.y) - dir.y * (mid.x - proj.x))
			var ov := minf(maxf(ta, tb), half) - maxf(minf(ta, tb), -half)
			if perp <= LINE_EPS and ov > d.b_link_overlap[rec[1]] + 0.05:
				removes.append(bh)
	removes.sort()
	out["center"] = proj
	out["rot"] = _link_rot(g, link)
	out["a"] = ga
	out["b"] = gb
	out["removes"] = removes
	if removes.is_empty():
		return out
	var why := NavApi.Why.OK
	for c in cells:
		var f := g.flags[c]
		for bh in g.stamps_at(c):
			if removes.find(bh) >= 0:
				continue
			var rec := g.stamp_of(bh)                  # соседние звенья своей стены примыкают к воротам
			if rec.is_empty() or rec[0] != team or rec[2] & NavApi.F.WALL == 0:
				why = NavApi.Why.OVERLAP
		if why == NavApi.Why.OK and (f & NavApi.F.NODE or g.node_in_cell(c)):
			why = NavApi.Why.OVERLAP
		elif why == NavApi.Why.OK and f & NavApi.F.WATER:
			why = NavApi.Why.WATER
		elif why == NavApi.Why.OK and f & NavApi.F.STATIC:
			why = NavApi.Why.SLOPE
		if why != NavApi.Why.OK:
			break
	if why == NavApi.Why.OK and g.port != null and g.port.units_near(team, proj, half, true, 0, _units) > 0:
		why = NavApi.Why.ENEMY_UNITS
	out["why"] = why
	return out


## Башня: в клетки у стены; свои звенья под следом уходят. Без стены — как обычная постройка
func _snap_tower(g: NavGrid, player: int, btype: int, p: Vector2, team: int, link: int) -> Dictionary:
	var d := g.defs
	var at := p
	if link != 0:
		var geo := _link_geo(g, link)
		if not geo.is_empty():
			var la: Vector2 = geo[0]
			var dir: Vector2 = geo[1]
			at = la + dir * dir.dot(p - la)
	var center := NavApi.snap_center(d, btype, at, 0, g.origin)
	var r := NavApi.footprint(d, btype, center, 0, g.origin)
	var removes := PackedInt32Array()
	var seen := {}
	for row in range(maxi(r.position.y, 0), mini(r.end.y, g.h)):
		for col in range(maxi(r.position.x, 0), mini(r.end.x, g.w)):
			for bh in g.stamps_at(row * g.w + col):
				if seen.has(bh):
					continue
				seen[bh] = true
				var rec := g.stamp_of(bh)
				if not rec.is_empty() and rec[0] == team and rec[2] & NavApi.F.WALL != 0:
					removes.append(bh)
	removes.sort()
	var why := g.placement.check_place(g, player, btype, center, 0)
	return {"why": why, "center": center, "rot": 0.0, "removes": removes, "a": center, "b": center}


## Ближайшее своё звено стены у p: EconApi.wall_link_at, иначе — по штампам навигации
func _link_near(g: NavGrid, player: int, team: int, p: Vector2) -> int:
	if g.econ != null and g.econ.players != null and player >= 0 and player < g.econ.players.count:
		var h := g.econ.wall_link_at(player, p, SNAP_R)
		if h != 0:
			return h
	var c0 := g.cell_of(g.clamp_pos(p))
	if c0 < 0:
		return 0
	var k := ceili(SNAP_R / NavApi.CELL)
	var best := 0
	var bd := SNAP_R * SNAP_R
	var cx := c0 % g.w
	var cy := c0 / g.w
	for y in range(maxi(cy - k, 0), mini(cy + k + 1, g.h)):
		for x in range(maxi(cx - k, 0), mini(cx + k + 1, g.w)):
			var c := y * g.w + x
			if g.flags[c] & NavApi.F.WALL == 0:
				continue
			for bh in g.stamps_at(c):
				var rec := g.stamp_of(bh)
				if rec.is_empty() or rec[0] != team or rec[2] & NavApi.F.WALL == 0:
					continue
				var dd := p.distance_squared_to(g.cell_center(c))
				if dd < bd or (dd == bd and bh < best):
					bd = dd
					best = bh
	return best


## Геометрия звена: [a, dir, b] по BuildingTable (концы, иначе центр и поворот); пусто — нет
func _link_geo(g: NavGrid, bh: int) -> Array:
	if g.econ == null or g.econ.buildings == null or not g.econ.buildings.valid(bh):
		return []
	var B := g.econ.buildings
	var b := B.slot(bh)
	var a := Vector2(B.ax[b], B.az[b])
	var e := Vector2(B.bx[b], B.bz[b])
	if a.distance_squared_to(e) < 0.01:
		var dir := Vector2(cos(B.rot[b]), -sin(B.rot[b]))
		var half := g.defs.b_link_len[B.btype[b]] * 0.5 if B.btype[b] >= 0 else 1.8
		var c := Vector2(B.x[b], B.z[b])
		a = c - dir * half
		e = c + dir * half
	return [a, (e - a).normalized(), e]


func _link_rot(g: NavGrid, bh: int) -> float:
	var B := g.econ.buildings
	return B.rot[B.slot(bh)]


## Клетки и их 4 соседа (без повторов, по возрастанию)
func _cells_around(g: NavGrid, cells: PackedInt32Array) -> PackedInt32Array:
	var seen := {}
	for c in cells:
		seen[c] = true
		var x := c % g.w
		var y := c / g.w
		if x > 0: seen[c - 1] = true
		if x < g.w - 1: seen[c + 1] = true
		if y > 0: seen[c - g.w] = true
		if y < g.h - 1: seen[c + g.w] = true
	var out := PackedInt32Array(seen.keys())
	out.sort()
	return out
