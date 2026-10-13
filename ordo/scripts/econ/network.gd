class_name EconNetwork
extends RefCounted
## Вода Коканда (ARCHITECTURE §11; ECONOMY §2.2–2.4): тўғон — голова сети, ариқ — звенья 4 м.
##   • сеть: звенья, чей конец у тўғона (≤ 4 м от следа) или у звена той же сети; до 400 м от тўғона;
##   • зона воды — 24 м от каждого звена с водой (и от самого тўғона); сетка полива 8 м — для вида и Хумдона;
##   • места воды: у тўғона 8; поле и Хумдон занимают по 1 в порядке постройки; своими арыками пользуется
##     только хозяин; поле «у воды» — центр в зоне и есть место (100%), иначе «лалми» (25%);
##   • тўғон разрушен — сеть сохнет через dry_s (20 с): поля 25%, Хумдон 50%; восстановлен — вода сразу.
## Пересчёт — только когда что-то изменилось (постройка, разрушение, срок засухи).

const SNAP := 6.0

var ww := 0
var wh := 0
var bytes := PackedByteArray()           # 0 / 255 (полив) — GameQuery.water
var dry_at := PackedInt32Array()         # [слот тўғона] такт, когда сеть высохнет (руина), 0
var was_wet := PackedInt32Array()        # [слот тўғона] был ли с водой при прошлом пересчёте
var used := PackedInt32Array()           # [слот тўғона] занято мест
var link_net := PackedInt32Array()       # [слот звена] тўғон (слот), −1
var next_due := 0


func setup(e: EconomySim) -> void:
	ww = maxi(1, int(e.extent.x / EconomySim.WATER_CELL))
	wh = maxi(1, int(e.extent.y / EconomySim.WATER_CELL))
	bytes.resize(ww * wh)


func _grow(n: int) -> void:
	while dry_at.size() < n:
		dry_at.append(0)
		was_wet.append(0)
		used.append(0)
		link_net.append(-1)


func due(e: EconomySim) -> bool:
	return next_due > 0 and e.tick >= next_due


func on_dam_destroyed(e: EconomySim, b: int) -> void:
	_grow(e.buildings.hw)
	var dry := roundi(float(e.defs.b_network[e.buildings.btype[b]].get("dry_s", 20)) * Defs.TICKS_PER_S)
	dry_at[b] = e.tick + dry
	e._net_dirty = true


## Полив 0..1000 в точке (по сетке 8 м)
func water_at(e: EconomySim, p: Vector2) -> int:
	var i := clampi(floori((p.x - e.origin.x) / EconomySim.WATER_CELL), 0, ww - 1)
	var j := clampi(floori((p.y - e.origin.y) / EconomySim.WATER_CELL), 0, wh - 1)
	return bytes[j * ww + i] * 1000 / 255


## Тўғон с водой: стоит, или разрушен, но срок засухи не вышел
func dam_wet(e: EconomySim, d: int) -> bool:
	var st := e.buildings.state[d]
	if st == BuildingTable.State.ACTIVE:
		return true
	return st == BuildingTable.State.RUIN and d < dry_at.size() and e.tick < dry_at[d]


func recompute(e: EconomySim) -> void:
	e._net_dirty = false
	var B := e.buildings
	var D := e.defs
	_grow(B.hw)
	bytes.fill(0)
	next_due = 0
	# тўғоны и звенья
	var dams := PackedInt32Array()
	var links := PackedInt32Array()
	for b in B.hw:
		var st := B.state[b]
		if st == BuildingTable.State.FREE:
			continue
		var nw: Dictionary = D.b_network[B.btype[b]]
		if nw.get("kind", "") != "water":
			continue
		if bool(nw.get("source", false)):
			if st == BuildingTable.State.ACTIVE or st == BuildingTable.State.RUIN:
				dams.append(b)
				if st == BuildingTable.State.RUIN and dry_at[b] > e.tick and (next_due == 0 or dry_at[b] < next_due):
					next_due = dry_at[b]
		elif st == BuildingTable.State.ACTIVE and D.b_kind[B.btype[b]] == Defs.BKind.LINK:
			links.append(b)
	for l in links:
		link_net[l] = -1
	# связность: от тўғона по звеньям того же хозяина
	for d in dams:
		used[d] = 0
		var rng_m := float(D.b_network[B.btype[d]].get("range", 400.0))
		var dc := Vector2(B.x[d], B.z[d])
		var frontier := PackedInt32Array()
		for l in links:
			if link_net[l] < 0 and B.owner[l] == B.owner[d] and \
					(e.rect_dist2(d, Vector2(B.ax[l], B.az[l])) <= SNAP * SNAP or e.rect_dist2(d, Vector2(B.bx[l], B.bz[l])) <= SNAP * SNAP):
				link_net[l] = d
				frontier.append(l)
		while not frontier.is_empty():
			var i: int = frontier[frontier.size() - 1]
			frontier.remove_at(frontier.size() - 1)
			var ia := Vector2(B.ax[i], B.az[i])
			var ib := Vector2(B.bx[i], B.bz[i])
			for l in links:
				if link_net[l] >= 0 or B.owner[l] != B.owner[d]:
					continue
				if Vector2(B.x[l], B.z[l]).distance_squared_to(dc) > rng_m * rng_m:
					continue
				var la := Vector2(B.ax[l], B.az[l])
				var lb := Vector2(B.bx[l], B.bz[l])
				if EconomySim.seg_dist2(la, ia, ib) <= SNAP * SNAP or EconomySim.seg_dist2(lb, ia, ib) <= SNAP * SNAP \
						or EconomySim.seg_dist2(ia, la, lb) <= SNAP * SNAP or EconomySim.seg_dist2(ib, la, lb) <= SNAP * SNAP:
					link_net[l] = d
					frontier.append(l)
	# потребители по порядку постройки
	var cons := PackedInt32Array()
	for b in B.hw:
		if B.state[b] == BuildingTable.State.ACTIVE and D.b_water_place[B.btype[b]] > 0:
			cons.append(b)
		elif B.state[b] != BuildingTable.State.FREE and D.b_water_place[B.btype[b]] > 0:
			e.b_water[b] = 0
			e.b_net[b] = -1
	for i in range(1, cons.size()):
		var j := i
		while j > 0 and e.b_order[cons[j - 1]] > e.b_order[cons[j]]:
			var t := cons[j]; cons[j] = cons[j - 1]; cons[j - 1] = t
			j -= 1
	for c in cons:
		var cp := Vector2(B.x[c], B.z[c])
		var got := -1
		for d in dams:
			if B.owner[d] != B.owner[c] or not dam_wet(e, d):
				continue
			var places := int(D.b_network[B.btype[d]].get("places", 8))
			if used[d] + D.b_water_place[B.btype[c]] > places:
				continue
			if _in_zone(e, d, cp, links):
				got = d
				break
		e.b_net[c] = got
		e.b_water[c] = 1000 if got >= 0 else 0
		if got >= 0:
			used[got] += D.b_water_place[B.btype[c]]
	# сетка полива и события
	for d in dams:
		var wet := dam_wet(e, d)
		var cells := 0
		if wet:
			var zone := _zone_r(e, links, d)
			cells += _paint_rect(e, d, zone)
			for l in links:
				if link_net[l] == d:
					cells += _paint_seg(e, Vector2(B.ax[l], B.az[l]), Vector2(B.bx[l], B.bz[l]), _link_zone(e, l))
		var w := 1 if wet else 0
		if w != was_wet[d] or wet:
			if w != was_wet[d]:
				e.events.push(SimEvents.Ev.IRRIGATION_CHANGED, B.owner[d], B.handle(d), cells, w, Vector2(B.x[d], B.z[d]))
			was_wet[d] = w


## Точка в зоне воды своей сети с водой (точно, не по сетке 8 м) — для расстановки Хумдона
func in_any_zone(e: EconomySim, p: int, pos: Vector2) -> bool:
	var B := e.buildings
	var links := PackedInt32Array()
	for l in link_net.size():
		if l < B.hw and link_net[l] >= 0 and B.state[l] == BuildingTable.State.ACTIVE:
			links.append(l)
	for d in mini(B.hw, dry_at.size()):
		var nw: Dictionary = e.defs.b_network[B.btype[d]] if B.state[d] != BuildingTable.State.FREE else {}
		if not bool(nw.get("source", false)) or B.owner[d] != p or not dam_wet(e, d):
			continue
		if _in_zone(e, d, pos, links):
			return true
	return false


func _link_zone(e: EconomySim, l: int) -> float:
	return float(e.defs.b_network[e.buildings.btype[l]].get("zone", 24.0))


func _zone_r(e: EconomySim, links: PackedInt32Array, d: int) -> float:
	for l in links:
		return _link_zone(e, l)
	return 24.0


func _in_zone(e: EconomySim, d: int, p: Vector2, links: PackedInt32Array) -> bool:
	var B := e.buildings
	var z := _zone_r(e, links, d)
	if e.rect_dist2(d, p) <= z * z:
		return true
	for l in links:
		if link_net[l] == d:
			var zl := _link_zone(e, l)
			if EconomySim.seg_dist2(p, Vector2(B.ax[l], B.az[l]), Vector2(B.bx[l], B.bz[l])) <= zl * zl:
				return true
	return false


func _paint_seg(e: EconomySim, a: Vector2, b: Vector2, r: float) -> int:
	var s := EconomySim.WATER_CELL
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(r, r)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(r, r)
	var n := 0
	for j in range(clampi(floori((lo.y - e.origin.y) / s), 0, wh - 1), clampi(floori((hi.y - e.origin.y) / s), 0, wh - 1) + 1):
		for i in range(clampi(floori((lo.x - e.origin.x) / s), 0, ww - 1), clampi(floori((hi.x - e.origin.x) / s), 0, ww - 1) + 1):
			var c := e.origin + (Vector2(i, j) + Vector2(0.5, 0.5)) * s
			if bytes[j * ww + i] == 0 and EconomySim.seg_dist2(c, a, b) <= r * r:
				bytes[j * ww + i] = 255
				n += 1
	return n


func _paint_rect(e: EconomySim, d: int, r: float) -> int:
	var c := Vector2(e.buildings.x[d], e.buildings.z[d])
	return _paint_seg(e, c, c, r + e.half_of(d).length())
