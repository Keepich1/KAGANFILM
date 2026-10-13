class_name EconNetwork
extends RefCounted
## Вода Коканда (ARCHITECTURE §11; ECONOMY §2.2–2.4): тўғон — голова сети, ариқ — звенья 4 м.
##   • прокладка (ECONOMY §2.2.1): начало — у своего тўғона (≤ SNAP от следа) или на своём звене той же сети;
##     у звена запоминается его тўғон (EconomySim.b_root); звенья дальше range от тўғона не ставятся;
##   • сеть: готовые звенья, чей конец у тўғона или у звена той же сети; до 400 м от тўғона;
##   • зона воды — 24 м от каждого звена с водой (и от самого тўғона); сетка полива 8 м — для вида и Хумдона;
##   • места воды: у тўғона 8; поле и Хумдон занимают по 1 в порядке постройки; своими арыками пользуется
##     только хозяин; поле «у воды» — центр в зоне и есть место (100%), иначе «лалми» (25%);
##   • тўғон разрушен — сеть сохнет через dry_s (20 с): поля 25%, Хумдон 50%; восстановлен — вода сразу.
##
## Скорость (ARCHITECTURE §16): звенья лежат в корзинах по центру (клетка HCELL), соседство звеньев
## считается один раз — когда звено поставлено (и убирается при сносе); пересчёт сети — обход в ширину
## по готовому соседству, O(звенья + связи). Сетка полива докрашивается только для новых звеньев;
## целиком перекрашивается, лишь когда сеть что-то потеряла (засуха, снос, новый тўғон).
## Пересчёт — только когда изменились тўғон, звено или потребитель воды, и в срок засухи.

const SNAP := 6.0
const HCELL := 32.0                       # корзина звеньев, м

var ww := 0
var wh := 0
var bytes := PackedByteArray()           # 0 / 255 (полив) — GameQuery.water
var dry_at := PackedInt32Array()         # [слот тўғона] такт, когда сеть высохнет (руина), 0
var was_wet := PackedInt32Array()        # [слот тўғона] был ли с водой при прошлом пересчёте
var used := PackedInt32Array()           # [слот тўғона] занято мест
var link_net := PackedInt32Array()       # [слот звена] тўғон (слот), −1
var next_due := 0

# производное (из таблицы зданий; после загрузки — rebuild_topology)
var _src_t := PackedByteArray()          # [вид здания] голова водной сети
var _link_t := PackedByteArray()         # [вид здания] звено водной сети
var _zone := 24.0                        # зона воды звена, м
var _reach := 32.0                       # дальше этого от центра звена ничего не касается, м
var _org := Vector2.ZERO                 # угол карты
var _hw := 1                             # корзин по X
var _hh := 1
var _cells: Array[PackedInt32Array] = []  # [корзина] слоты звеньев (SITE и ACTIVE)
var _adj: Array[PackedInt32Array] = []    # [слот звена] соседние звенья того же хозяина
var _painted := PackedInt32Array()       # [слот звена] тўғон, под которым звено закрашено, −1
var _painted_list := PackedInt32Array()  # закрашенные звенья
var _painted_d := PackedByteArray()      # [слот тўғона] его след закрашен (сеть с водой)
var _repaint := true                     # перекрасить всё при следующем пересчёте


func setup(e: EconomySim) -> void:
	ww = maxi(1, int(e.extent.x / EconomySim.WATER_CELL))
	wh = maxi(1, int(e.extent.y / EconomySim.WATER_CELL))
	bytes.resize(ww * wh)
	var D := e.defs
	_src_t.resize(D.b_ids.size())
	_link_t.resize(D.b_ids.size())
	var max_len := 4.0
	for bt in D.b_ids.size():
		var nw: Dictionary = D.b_network[bt]
		if nw.get("kind", "") != "water":
			continue
		if bool(nw.get("source", false)):
			_src_t[bt] = 1
		elif D.b_kind[bt] == Defs.BKind.LINK:
			_link_t[bt] = 1
			_zone = float(nw.get("zone", 24.0))
			max_len = maxf(max_len, D.b_link_len[bt])
	_reach = maxf(_zone, SNAP) + max_len * 0.5
	_org = e.origin
	_hw = maxi(1, ceili(e.extent.x / HCELL))
	_hh = maxi(1, ceili(e.extent.y / HCELL))
	_cells.resize(_hw * _hh)
	for i in _cells.size():
		_cells[i] = PackedInt32Array()


func is_source(bt: int) -> bool:
	return bt >= 0 and bt < _src_t.size() and _src_t[bt] == 1


func is_link(bt: int) -> bool:
	return bt >= 0 and bt < _link_t.size() and _link_t[bt] == 1


func _grow(n: int) -> void:
	while dry_at.size() < n:
		dry_at.append(0)
		was_wet.append(0)
		used.append(0)
		link_net.append(-1)
		_painted.append(-1)
		_painted_d.append(0)
		_adj.append(PackedInt32Array())


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


# ================================================================= прокладка и соседство звеньев

## Описатель тўғона, от которого можно законно вести звено сети, начатое в точке at (ECONOMY §2.2.1):
## у своего тўғона (стоит, строится или руина) или на своём звене той же сети, у которого есть тўғон. 0 — нельзя.
func root_at(e: EconomySim, p: int, at: Vector2) -> int:
	var B := e.buildings
	for b in B.hw:
		var st := B.state[b]
		if B.owner[b] != p or not is_source(B.btype[b]):
			continue
		if st == BuildingTable.State.ACTIVE or st == BuildingTable.State.SITE or st == BuildingTable.State.RUIN:
			if e.rect_dist2(b, at) <= SNAP * SNAP:
				return B.handle(b)
	for c in _cells_near(at, SNAP + _reach - _zone):
		for l in _cells[c]:
			if B.owner[l] != p or not root_ok(e, l):
				continue
			if EconomySim.seg_dist2(at, Vector2(B.ax[l], B.az[l]), Vector2(B.bx[l], B.bz[l])) <= SNAP * SNAP:
				return e.b_root[l]
	return 0


## У звена l есть живой тўғон того же хозяина (цепочка начата законно)
func root_ok(e: EconomySim, l: int) -> bool:
	var r := e.b_root[l] if l < e.b_root.size() else 0
	if r == 0 or not e.buildings.valid(r):
		return false
	return e.buildings.owner[e.buildings.slot(r)] == e.buildings.owner[l]


## Ближайший свой тўғон в пределах его сети (только для звеньев, которые ставит карта: MapSetup, spawn_*)
func nearest_root(e: EconomySim, p: int, at: Vector2) -> int:
	var B := e.buildings
	var best := 0
	var bd := INF
	for b in B.hw:
		if B.owner[b] != p or not is_source(B.btype[b]) or B.state[b] == BuildingTable.State.FREE:
			continue
		var rng_m := float(e.defs.b_network[B.btype[b]].get("range", 400.0))
		var d := e.rect_dist2(b, at)
		if d <= rng_m * rng_m and d < bd:
			bd = d
			best = B.handle(b)
	return best


## Центр звена в пределах сети тўғона root_h
func in_range(e: EconomySim, root_h: int, c: Vector2) -> bool:
	if not e.buildings.valid(root_h):
		return false
	var d := e.buildings.slot(root_h)
	var rng_m := float(e.defs.b_network[e.buildings.btype[d]].get("range", 400.0))
	return Vector2(e.buildings.x[d], e.buildings.z[d]).distance_squared_to(c) <= rng_m * rng_m


## Звено поставлено (концы уже заданы): в корзину и соседство с ближними звеньями того же хозяина
func link_added(e: EconomySim, l: int) -> void:
	var B := e.buildings
	_grow(B.hw)
	link_net[l] = -1
	_painted[l] = -1
	_adj[l] = PackedInt32Array()
	var c := Vector2(B.x[l], B.z[l])
	var la := Vector2(B.ax[l], B.az[l])
	var lb := Vector2(B.bx[l], B.bz[l])
	var reach := 2.0 * (_reach - _zone) + SNAP      # центры соседей не дальше двух полузвеньев и SNAP
	for ci in _cells_near(c, reach):
		for n in _cells[ci]:
			if n == l or B.owner[n] != B.owner[l]:
				continue
			if _touch(la, lb, Vector2(B.ax[n], B.az[n]), Vector2(B.bx[n], B.bz[n])):
				_adj[l].append(n)
				_adj[n].append(l)
	_cells[_cell_of(c)].append(l)


## Звено снесено: из корзины и из соседства; сеть перекрасится целиком
func link_removed(e: EconomySim, l: int) -> void:
	_grow(e.buildings.hw)
	var ci := _cell_of(Vector2(e.buildings.x[l], e.buildings.z[l]))
	var i := _cells[ci].find(l)
	if i >= 0:
		_cells[ci].remove_at(i)
	for n in _adj[l]:
		var j := _adj[n].find(l)
		if j >= 0:
			_adj[n].remove_at(j)
	_adj[l] = PackedInt32Array()
	link_net[l] = -1
	_repaint = true
	e._net_dirty = true


## Корзины и соседство заново (после загрузки сохранения)
func rebuild_topology(e: EconomySim) -> void:
	var B := e.buildings
	_grow(B.hw)
	for i in _cells.size():
		_cells[i] = PackedInt32Array()
	for b in B.hw:
		_adj[b] = PackedInt32Array()
	for b in B.hw:
		if B.state[b] != BuildingTable.State.FREE and is_link(B.btype[b]):
			link_added(e, b)
	_repaint = true


static func _touch(ia: Vector2, ib: Vector2, la: Vector2, lb: Vector2) -> bool:
	var s2 := SNAP * SNAP
	return EconomySim.seg_dist2(la, ia, ib) <= s2 or EconomySim.seg_dist2(lb, ia, ib) <= s2 \
		or EconomySim.seg_dist2(ia, la, lb) <= s2 or EconomySim.seg_dist2(ib, la, lb) <= s2


func _cell_of(c: Vector2) -> int:
	var i := clampi(floori((c.x - _org.x) / HCELL), 0, _hw - 1)
	var j := clampi(floori((c.y - _org.y) / HCELL), 0, _hh - 1)
	return j * _hw + i


## Корзины, где могут лежать центры звеньев ближе r к точке p
func _cells_near(p: Vector2, r: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var i0 := clampi(floori((p.x - r - _org.x) / HCELL), 0, _hw - 1)
	var i1 := clampi(floori((p.x + r - _org.x) / HCELL), 0, _hw - 1)
	var j0 := clampi(floori((p.y - r - _org.y) / HCELL), 0, _hh - 1)
	var j1 := clampi(floori((p.y + r - _org.y) / HCELL), 0, _hh - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			out.append(j * _hw + i)
	return out


# ================================================================= пересчёт

func recompute(e: EconomySim) -> void:
	e._net_dirty = false
	var B := e.buildings
	var D := e.defs
	_grow(B.hw)
	next_due = 0
	# тўғоны, готовые звенья и потребители — одним проходом
	var dams := PackedInt32Array()
	var cons := PackedInt32Array()
	for b in B.hw:
		var st := B.state[b]
		if st == BuildingTable.State.FREE:
			continue
		var bt := B.btype[b]
		if _src_t[bt] == 1:
			if st == BuildingTable.State.ACTIVE or st == BuildingTable.State.RUIN:
				dams.append(b)
				if st == BuildingTable.State.RUIN and dry_at[b] > e.tick and (next_due == 0 or dry_at[b] < next_due):
					next_due = dry_at[b]
		elif _link_t[bt] == 1:
			link_net[b] = -1
		elif D.b_water_place[bt] > 0:
			if st == BuildingTable.State.ACTIVE:
				cons.append(b)
			else:
				e.b_water[b] = 0
				e.b_net[b] = -1
	# связность: от тўғона в ширину по соседству звеньев того же хозяина
	var frontier := PackedInt32Array()
	for d in dams:
		used[d] = 0
		var rng_m := float(D.b_network[B.btype[d]].get("range", 400.0))
		var r2 := rng_m * rng_m
		var dc := Vector2(B.x[d], B.z[d])
		var own := B.owner[d]
		frontier.clear()
		for ci in _cells_near(dc, e.half_of(d).length() + SNAP + (_reach - _zone)):
			for l in _cells[ci]:
				if link_net[l] < 0 and B.owner[l] == own and B.state[l] == BuildingTable.State.ACTIVE and \
						(e.rect_dist2(d, Vector2(B.ax[l], B.az[l])) <= SNAP * SNAP or e.rect_dist2(d, Vector2(B.bx[l], B.bz[l])) <= SNAP * SNAP):
					link_net[l] = d
					frontier.append(l)
		var k := 0
		while k < frontier.size():
			var i: int = frontier[k]
			k += 1
			for l in _adj[i]:
				if link_net[l] >= 0 or B.state[l] != BuildingTable.State.ACTIVE:
					continue
				if Vector2(B.x[l], B.z[l]).distance_squared_to(dc) > r2:
					continue
				link_net[l] = d
				frontier.append(l)
	# потребители по порядку постройки
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
			if _in_zone(e, d, cp):
				got = d
				break
		e.b_net[c] = got
		e.b_water[c] = 1000 if got >= 0 else 0
		if got >= 0:
			used[got] += D.b_water_place[B.btype[c]]
	_paint(e, dams)


## Сетка полива: докрасить новые звенья; перекрасить всё, если сеть что-то потеряла или сменилась вода у тўғона
func _paint(e: EconomySim, dams: PackedInt32Array) -> void:
	var B := e.buildings
	var full := _repaint
	_repaint = false
	if not full:
		for d in dams:
			if _painted_d[d] != (1 if dam_wet(e, d) else 0):
				full = true
				break
	if not full:
		for l in _painted_list:
			if link_net[l] != _painted[l] or _painted_d[_painted[l]] == 0:
				full = true
				break
	if not full:
		for d in _painted_d.size():
			if _painted_d[d] == 1 and not dams.has(d):
				full = true                     # тўғон снесён
				break
	if not full:
		# докрасить звенья, которые только что вошли в сеть
		for d in dams:
			if _painted_d[d] == 0:
				continue
			_paint_new(e, d)
		return
	bytes.fill(0)
	for l in _painted_list:
		_painted[l] = -1
	_painted_list.clear()
	_painted_d.fill(0)
	for d in dams:
		var wet := dam_wet(e, d)
		var cells := 0
		if wet:
			_painted_d[d] = 1
			cells += _paint_rect(e, d, _zone)
			cells += _paint_new(e, d)
		var w := 1 if wet else 0
		if w != was_wet[d]:
			e.events.push(SimEvents.Ev.IRRIGATION_CHANGED, B.owner[d], B.handle(d), cells, w, Vector2(B.x[d], B.z[d]))
		was_wet[d] = w


## Закрасить звенья сети d, ещё не закрашенные; вернёт число новых клеток
func _paint_new(e: EconomySim, d: int) -> int:
	var B := e.buildings
	var cells := 0
	for l in B.hw:
		if l < link_net.size() and link_net[l] == d and _painted[l] < 0:
			cells += _paint_seg(e, Vector2(B.ax[l], B.az[l]), Vector2(B.bx[l], B.bz[l]), _zone)
			_painted[l] = d
			_painted_list.append(l)
	return cells


## Потребитель btype игрока p с центром pos получил бы воду: зона своей сети с водой и свободное место у тўғона
## (по раздаче последнего пересчёта) — для призрака поля
func would_water(e: EconomySim, p: int, btype: int, pos: Vector2) -> bool:
	var B := e.buildings
	var need := e.defs.b_water_place[btype]
	for d in mini(B.hw, dry_at.size()):
		if B.state[d] == BuildingTable.State.FREE or not is_source(B.btype[d]) or B.owner[d] != p or not dam_wet(e, d):
			continue
		if used[d] + need > int(e.defs.b_network[B.btype[d]].get("places", 8)):
			continue
		if _in_zone(e, d, pos):
			return true
	return false


## Точка в зоне воды своей сети с водой (точно, не по сетке 8 м) — для расстановки Хумдона
func in_any_zone(e: EconomySim, p: int, pos: Vector2) -> bool:
	var B := e.buildings
	for d in mini(B.hw, dry_at.size()):
		if B.state[d] == BuildingTable.State.FREE or not is_source(B.btype[d]) or B.owner[d] != p or not dam_wet(e, d):
			continue
		if _in_zone(e, d, pos):
			return true
	return false


func _in_zone(e: EconomySim, d: int, p: Vector2) -> bool:
	var B := e.buildings
	var z2 := _zone * _zone
	if e.rect_dist2(d, p) <= z2:
		return true
	for ci in _cells_near(p, _reach):
		for l in _cells[ci]:
			if link_net[l] == d and EconomySim.seg_dist2(p, Vector2(B.ax[l], B.az[l]), Vector2(B.bx[l], B.bz[l])) <= z2:
				return true
	return false


func _paint_seg(e: EconomySim, a: Vector2, b: Vector2, r: float) -> int:
	var s := EconomySim.WATER_CELL
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(r, r)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(r, r)
	var n := 0
	var r2 := r * r
	for j in range(clampi(floori((lo.y - e.origin.y) / s), 0, wh - 1), clampi(floori((hi.y - e.origin.y) / s), 0, wh - 1) + 1):
		var row := j * ww
		for i in range(clampi(floori((lo.x - e.origin.x) / s), 0, ww - 1), clampi(floori((hi.x - e.origin.x) / s), 0, ww - 1) + 1):
			if bytes[row + i] != 0:
				continue
			var c := e.origin + (Vector2(i, j) + Vector2(0.5, 0.5)) * s
			if EconomySim.seg_dist2(c, a, b) <= r2:
				bytes[row + i] = 255
				n += 1
	return n


func _paint_rect(e: EconomySim, d: int, r: float) -> int:
	var c := Vector2(e.buildings.x[d], e.buildings.z[d])
	return _paint_seg(e, c, c, r + e.half_of(d).length())
