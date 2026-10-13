class_name EconFields
extends RefCounted
## Трава (ARCHITECTURE §6.3, §11; ECONOMY §3.3–3.4): сетка 16 м (на этой карте 64²), значение 0..1000
## (внутри — сотые доли промилле, чтобы шаг в 5 с был целым). fields_step — раз в 150 тактов (5 с):
##   • стадо у загона вытаптывает клетки в радиусе выпаса: отара 6%/мин, табун 3%/мин, не ниже 20%;
##   • клетка, где никто не пасётся, отрастает на 3%/мин (вода — травы нет);
##   • короо: трава ниже 40% — «Жайыт тозду» (PASTURE_LOW c=0); авто-перегон — на лучшую свободную
##     клетку в 80 м (PASTURE_LOW c=2), 30 с без еды; места нет — c=1 («Рядом нет пастбища — көч керек»).
## Короо ставится на траву от 50%, одна на клетку пастбища 40 м (центры короо не ближе 40 м).

const STEP_TICKS := 150
const FULL := 100000                     # 100% травы во внутренних единицах
const PEN_SPACING := 40.0                # клетка пастбища (ECONOMY §3.4)
const MOVE_RINGS := [40.0, 80.0]

var gw := 0
var gh := 0
var g := PackedInt32Array()              # трава, сотые промилле
var cap := PackedByteArray()             # 1 — клетка может зарасти (не вода)
var bytes := PackedByteArray()           # 0..255 для вида (GameQuery.grass)
var _tr := PackedInt32Array()            # вытаптывание за шаг (рабочий буфер)


func setup(e: EconomySim) -> void:
	gw = maxi(1, int(e.extent.x / EconomySim.GRASS_CELL))
	gh = maxi(1, int(e.extent.y / EconomySim.GRASS_CELL))
	g.resize(gw * gh)
	cap.resize(gw * gh)
	bytes.resize(gw * gh)
	_tr.resize(gw * gh)
	for j in gh:
		for i in gw:
			var c := e.origin + (Vector2(i, j) + Vector2(0.5, 0.5)) * EconomySim.GRASS_CELL
			var wet := Terrain.is_water(c.x, c.y)
			g[j * gw + i] = 0 if wet else FULL
			cap[j * gw + i] = 0 if wet else 1
	_bytes()


func cell_of(e: EconomySim, p: Vector2) -> int:
	var i := clampi(floori((p.x - e.origin.x) / EconomySim.GRASS_CELL), 0, gw - 1)
	var j := clampi(floori((p.y - e.origin.y) / EconomySim.GRASS_CELL), 0, gh - 1)
	return j * gw + i


## Трава 0..1000 в клетке точки
func grass_at(e: EconomySim, p: Vector2) -> int:
	return g[cell_of(e, p)] / 100


## Средняя трава 0..1000 по клеткам, чьи центры в радиусе r (не меньше клетки точки)
func avg_under(e: EconomySim, p: Vector2, r: float) -> int:
	var cells := cells_in(e, p, r)
	var sum := 0
	for c in cells:
		sum += g[c]
	return sum / maxi(cells.size(), 1) / 100


func cells_in(e: EconomySim, p: Vector2, r: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var s := EconomySim.GRASS_CELL
	var i0 := clampi(floori((p.x - r - e.origin.x) / s), 0, gw - 1)
	var i1 := clampi(floori((p.x + r - e.origin.x) / s), 0, gw - 1)
	var j0 := clampi(floori((p.y - r - e.origin.y) / s), 0, gh - 1)
	var j1 := clampi(floori((p.y + r - e.origin.y) / s), 0, gh - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var c := e.origin + (Vector2(i, j) + Vector2(0.5, 0.5)) * s
			if c.distance_squared_to(p) <= r * r:
				out.append(j * gw + i)
	if out.is_empty():
		out.append(cell_of(e, p))
	return out


func step(e: EconomySim) -> void:
	var pas: Dictionary = e.rules.get("pasture", {})
	var floor_v := int(pas.get("floor_pm", 200)) * 100
	var regrow := int(pas.get("regrow_pm", 30)) * 100 * STEP_TICKS / 1800
	_tr.fill(0)
	var H := e.herds
	for h in H.hw:
		if H.state[h] != HerdTable.State.PEN or H.heads_milli[h] <= 0:
			continue
		var per := e.defs.h_graze[H.htype[h]] * 100 * STEP_TICKS / 1800
		if per <= 0:
			continue
		for c in cells_in(e, Vector2(H.x[h], H.z[h]), H.graze_r[h]):
			_tr[c] += per
	for c in g.size():
		if cap[c] == 0:
			continue
		if _tr[c] > 0:
			if g[c] > floor_v:
				g[c] = maxi(floor_v, g[c] - _tr[c])
		else:
			g[c] = mini(FULL, g[c] + regrow)
	_bytes()
	_pens(e, pas)


## Короо: предупреждение и авто-перегон
func _pens(e: EconomySim, pas: Dictionary) -> void:
	var warn := int(pas.get("warn_pm", 400))
	var below := int(pas.get("auto_move_below_pm", 400))
	var H := e.herds
	var B := e.buildings
	for h in H.hw:
		if H.state[h] != HerdTable.State.PEN or not B.valid(H.pen_b[h]):
			continue
		var b := B.slot(H.pen_b[h])
		var bt := B.btype[b]
		if e.defs.b_herd_breed[bt] == 0 or not e.active(b) or e.b_mode[b] == EconomySim.Mode.MOVING:
			continue
		if e.defs.h_ids[H.htype[h]] != "sheep":
			continue
		var gr := avg_under(e, Vector2(H.x[h], H.z[h]), H.graze_r[h])
		if gr < warn and e.b_flag[b] & EconomySim.BFL_PASTURE_WARNED == 0:
			e.b_flag[b] |= EconomySim.BFL_PASTURE_WARNED
			e.events.push(SimEvents.Ev.PASTURE_LOW, B.owner[b], H.handle(h), gr, 0, Vector2(B.x[b], B.z[b]))
		elif gr >= warn + 100:
			e.b_flag[b] &= ~EconomySim.BFL_PASTURE_WARNED
		if gr < below and e.b_auto[b] == 1:
			_auto_move(e, b, h, gr, pas)


func _auto_move(e: EconomySim, b: int, h: int, gr: int, pas: Dictionary) -> void:
	var B := e.buildings
	var bt := B.btype[b]
	var c := Vector2(B.x[b], B.z[b])
	var best := Vector2.INF
	var best_g := int(pas.get("place_min_pm", 500)) - 1
	for rr: float in MOVE_RINGS:
		for d: Vector2 in EconWorkers.DIR8:
			var p := c + d * rr
			if e.nav:
				p = e.nav.snap(bt, p, B.rot_q[b])
			if not pen_spot_ok(e, bt, p, b):
				continue
			var gp := avg_under(e, p, e.defs.h_graze_r[e.herds.htype[h]])
			if gp <= best_g:
				continue
			if e.nav and _check_place_except(e, B.owner[b], bt, p, B.rot_q[b], b) != NavApi.Why.OK:
				continue
			best_g = gp
			best = p
	if best == Vector2.INF:
		if e.b_flag[b] & EconomySim.BFL_NO_SPOT == 0:
			e.b_flag[b] |= EconomySim.BFL_NO_SPOT
			e.events.push(SimEvents.Ev.PASTURE_LOW, B.owner[b], e.herds.handle(h), gr, 1, c)
		return
	e.b_flag[b] &= ~(EconomySim.BFL_NO_SPOT | EconomySim.BFL_PASTURE_WARNED)
	relocate(e, b, best)
	e.b_mode[b] = EconomySim.Mode.MOVING
	e.b_timer[b] = e.tick + int(pas.get("auto_move_pause_ticks", 900))
	e.events.push(SimEvents.Ev.PASTURE_LOW, B.owner[b], e.herds.handle(h), gr, 2, best)


## check_place без собственного штампа: снять, проверить, вернуть
func _check_place_except(e: EconomySim, p: int, bt: int, at: Vector2, rot_q: int, b: int) -> int:
	var h := e.buildings.handle(b)
	e.nav.unstamp(h)
	var why := e.nav.check_place(p, bt, at, rot_q)
	e.nav.stamp_building(h, e.buildings.team[b], Vector2(e.buildings.x[b], e.buildings.z[b]), bt, e.buildings.rot_q[b])
	return why


## Перенести постройку (штамп, зеркало, след, стадо и пастухи)
func relocate(e: EconomySim, b: int, to: Vector2) -> void:
	var B := e.buildings
	e._unplace_world(b)
	B.x[b] = to.x
	B.z[b] = to.y
	var rect := NavApi.footprint(e.defs, B.btype[b], to, B.rot_q[b], e.origin)
	B.c0[b] = rect.position.x
	B.r0[b] = rect.position.y
	B.cw[b] = rect.size.x
	B.ch[b] = rect.size.y
	e._place_world(b)
	var H := e.herds
	var bh := B.handle(b)
	for h in H.hw:
		if H.state[h] != HerdTable.State.FREE and H.pen_b[h] == bh and H.state[h] != HerdTable.State.CAPTURED:
			H.x[h] = to.x
			H.z[h] = to.y


## Можно ли поставить загон с отарой: трава от place_min_pm и не ближе PEN_SPACING к другим таким загонам
func pen_spot_ok(e: EconomySim, btype: int, at: Vector2, except_b: int) -> bool:
	var pas: Dictionary = e.rules.get("pasture", {})
	var hh := e.defs.b_herd[btype]
	var r := e.defs.h_graze_r[hh] if hh >= 0 else 20.0
	if avg_under(e, at, r) < int(pas.get("place_min_pm", 500)):
		return false
	var B := e.buildings
	for b in B.hw:
		if b == except_b or B.state[b] == BuildingTable.State.FREE or B.state[b] == BuildingTable.State.RUIN:
			continue
		if B.btype[b] != btype:
			continue
		var bc := e.b_dest[b] if B.state[b] == BuildingTable.State.PACKED else Vector2(B.x[b], B.z[b])
		if bc.distance_squared_to(at) < PEN_SPACING * PEN_SPACING:
			return false
	return true


func _bytes() -> void:
	for c in g.size():
		bytes[c] = g[c] * 255 / FULL
