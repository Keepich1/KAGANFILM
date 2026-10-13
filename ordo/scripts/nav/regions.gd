class_name NavRegions
extends RefCounted
## Слой проходимости одной команды (ARCHITECTURE §6.5, §9): сетка AStarGrid2D + граф секторов.
## У команды два слоя: walk (свои постройки и чужое — сплошные, свои ворота — проход) и
## breach (чужие постройки — вес W_BREACH, без графа ворот).
##
## Граф секторов (HPA*): сетка режется на секторы 16 × 16 клеток; внутри сектора — метки
## 4-связных областей (lab, 255 — закрыто). Входы — отрезки общей границы соседних секторов,
## где обе клетки открыты; у каждого входа точка в AStar2D (только walk). Компоненты связности
## (comp) — объединением областей через входы: reachable за O(1).
## Правки клеток (set_cell) помечают сектор грязным; flush() перемечивает только грязные
## секторы и их границы. flush зовёт только код симуляции (NavGrid — в service/find_now/reachable):
## порядок правок AStar2D должен быть одинаков в каждом прогоне.

const S := 16                 # = NavApi.SECTOR
const RMAX := 256             # меток в секторе (байт)
const CLOSED := 255
const RUN_SPLIT := 6          # длиннее — вход у каждого конца отрезка, короче — один посередине

var w := 0
var h := 0
var sw := 0
var sh := 0
var portals := false
var astar: AStarGrid2D
var graph: AStar2D                         # входы (только walk)
var solid := PackedByteArray()             # 1 — закрыто
var code := PackedByteArray()              # для прямой видимости: 255 — закрыто, иначе код веса (0 — 1)
var sec_solid := PackedInt32Array()        # закрытых клеток в секторе
var sec_busy := PackedInt32Array()         # клеток с code ≠ 0 в секторе (0 — сектор чист)
var lab := PackedByteArray()               # метка области в секторе, CLOSED
var reg_n := PackedInt32Array()            # областей в секторе
var reg_base := PackedInt32Array()         # плотный номер первой области сектора
var comp := PackedInt32Array()             # [reg_base[сектор] + метка] → компонента (меньший плотный номер)
var flushes := 0                           # сколько раз перемечали (для замеров)

var _comp_dirty := true
var _dirty := PackedByteArray()
var _dirty_list := PackedInt32Array()
var _ent_e: Array[PackedInt32Array] = []   # входы на восточной границе сектора: [cA, cB, lA, lB] × n
var _ent_s: Array[PackedInt32Array] = []   # на южной
var _tmp_s := 0
var _tmp_g := 0


func setup(p_w: int, p_h: int, p_portals: bool) -> void:
	w = p_w
	h = p_h
	sw = ceili(float(w) / S)
	sh = ceili(float(h) / S)
	portals = p_portals
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(1, 1)
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	solid.resize(w * h)
	solid.fill(0)
	code.resize(w * h)
	code.fill(0)
	lab.resize(w * h)
	lab.fill(CLOSED)
	var ns := sw * sh
	sec_solid.resize(ns)
	sec_solid.fill(0)
	sec_busy.resize(ns)
	sec_busy.fill(0)
	reg_n.resize(ns)
	reg_n.fill(0)
	reg_base.resize(ns + 1)
	reg_base.fill(0)
	_dirty.resize(ns)
	_dirty.fill(0)
	_ent_e.resize(ns)
	_ent_s.resize(ns)
	for s in ns:
		_ent_e[s] = PackedInt32Array()
		_ent_s[s] = PackedInt32Array()
	if portals:
		graph = AStar2D.new()
		graph.reserve_space(ns * 8)
	_tmp_s = w * h * 2
	_tmp_g = w * h * 2 + 1
	for s in ns:
		_mark_sector(s)


## Клетка c: закрыта ли, её вес для A* и код веса для прямой видимости (0 — вес 1)
func set_cell(c: int, is_solid: bool, weight: float, wcode: int) -> void:
	var v := 1 if is_solid else 0
	var id := Vector2i(c % w, c / w)
	var s := (id.y / S) * sw + id.x / S
	if solid[c] != v:
		solid[c] = v
		sec_solid[s] += 1 if is_solid else -1
		astar.set_point_solid(id, is_solid)
		_mark_sector(s)
	var cd := 255 if is_solid else wcode
	if code[c] != cd:
		if code[c] == 0:
			sec_busy[s] += 1
		elif cd == 0:
			sec_busy[s] -= 1
		code[c] = cd
	if not is_solid and astar.get_point_weight_scale(id) != weight:
		astar.set_point_weight_scale(id, weight)


func dirty() -> bool:
	return not _dirty_list.is_empty()


func sector_of(c: int) -> int:
	return ((c / w) / S) * sw + (c % w) / S


## Компонента клетки, −1 — закрыта. Слой без графа входов перемечивается здесь же (лениво:
## это чистая функция сетки); слой walk — только через flush из симуляции.
func comp_of(c: int) -> int:
	if not _dirty_list.is_empty():
		flush()
	if _comp_dirty:
		_components()
	var l := lab[c]
	if l == CLOSED:
		return -1
	return comp[reg_base[sector_of(c)] + l]


## Перемечает грязные секторы, их границы, входы и компоненты. true — было что перемечать
func flush() -> bool:
	if _dirty_list.is_empty():
		return false
	flushes += 1
	var list := _dirty_list.duplicate()
	list.sort()
	var same := not _comp_dirty
	for s in list:
		var before := reg_n[s]
		_relabel(s)
		same = same and reg_n[s] == before
	# границы вокруг грязных секторов: ключ = сектор * 2 + (0 — восточная, 1 — южная)
	var keys := {}
	for s in list:
		var sx := s % sw
		var sy := s / sw
		if sx < sw - 1:
			keys[s * 2] = true
		if sy < sh - 1:
			keys[s * 2 + 1] = true
		if sx > 0:
			keys[(s - 1) * 2] = true
		if sy > 0:
			keys[(s - sw) * 2 + 1] = true
	var bk := PackedInt32Array(keys.keys())
	bk.sort()
	if portals:
		for k in bk:
			var ent := _ent_e[k >> 1] if k & 1 == 0 else _ent_s[k >> 1]
			for i in range(0, ent.size(), 4):
				graph.remove_point(_ent_id(ent[i], k & 1))
	for k in bk:
		var old_e := _ent_e[k >> 1] if k & 1 == 0 else _ent_s[k >> 1]
		var ne := _border(k >> 1, k & 1)
		same = same and _pairs(old_e) == _pairs(ne)
		if k & 1 == 0:
			_ent_e[k >> 1] = ne
		else:
			_ent_s[k >> 1] = ne
	if portals:
		for k in bk:
			var ent := _ent_e[k >> 1] if k & 1 == 0 else _ent_s[k >> 1]
			for i in range(0, ent.size(), 4):
				var ca := ent[i]
				var cb := ent[i + 1]
				var pa := Vector2(ca % w, ca / w)
				var pb := Vector2(cb % w, cb / w)
				graph.add_point(_ent_id(ca, k & 1), (pa + pb) * 0.5 + Vector2(0.5, 0.5))
		for k in bk:
			var ent := _ent_e[k >> 1] if k & 1 == 0 else _ent_s[k >> 1]
			var sa := k >> 1
			var sb := sa + 1 if k & 1 == 0 else sa + sw
			for i in range(0, ent.size(), 4):
				var id := _ent_id(ent[i], k & 1)
				_connect_region(id, sa, ent[i + 2])
				_connect_region(id, sb, ent[i + 3])
	for s in list:
		_dirty[s] = 0
	_dirty_list.clear()
	# связность меняется, только если сменилось число областей или пары меток на границах
	if not same:
		_comp_dirty = true
	return true


## Пары меток (lA, lB) входов границы — без повторов, по порядку (для сравнения связности)
func _pairs(ent: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(0, ent.size(), 4):
		var v := ent[i + 2] * RMAX + ent[i + 3]
		if out.find(v) < 0:
			out.append(v)
	out.sort()
	return out


## Коридор входов от клетки cs к клетке cg (одна компонента, разные области):
## id входов по порядку (см. ent_cells); пусто — нет пути по графу
func corridor(cs: int, cg: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	if not portals:
		return out
	graph.add_point(_tmp_s, Vector2(cs % w, cs / w) + Vector2(0.5, 0.5))
	graph.add_point(_tmp_g, Vector2(cg % w, cg / w) + Vector2(0.5, 0.5))
	_connect_region(_tmp_s, sector_of(cs), lab[cs])
	_connect_region(_tmp_g, sector_of(cg), lab[cg])
	var path := graph.get_id_path(_tmp_s, _tmp_g)
	graph.remove_point(_tmp_s)
	graph.remove_point(_tmp_g)
	if path.size() >= 2:
		out = path.slice(1, path.size() - 1)
	return out


## Клетки входа по id: Vector2i(cA, cB)
func ent_cells(id: int) -> Vector2i:
	var ca := id >> 1
	return Vector2i(ca, ca + 1 if id & 1 == 0 else ca + w)


## Ближайшая к клетке goal открытая клетка компоненты cid (по прямой; ничьи — меньший индекс).
## Секторы — кольцами вокруг сектора цели, пока нижняя оценка кольца не больше лучшего.
## Открытый сектор этой компоненты — за O(1) (ближайшая клетка — проекция цели на сектор).
func nearest_in_comp(cid: int, goal: int) -> int:
	if _comp_dirty or not _dirty_list.is_empty():
		comp_of(goal)
	var gx := goal % w
	var gy := goal / w
	var gsx := gx / S
	var gsy := gy / S
	var best := -1
	var bd := 1 << 60
	for k in maxi(sw, sh):
		var lb := maxi(0, (k - 1) * S + 1)
		if best >= 0 and lb * lb > bd:
			break
		for sy in range(gsy - k, gsy + k + 1):
			if sy < 0 or sy >= sh:
				continue
			var step := 1 if (sy == gsy - k or sy == gsy + k) else 2 * k
			var sx := gsx - k
			while sx <= gsx + k:
				if sx >= 0 and sx < sw:
					var c := _nearest_in_sector(sy * sw + sx, cid, gx, gy, bd, best)
					if c >= 0:
						var dx := c % w - gx
						var dy := c / w - gy
						var d := dx * dx + dy * dy
						if d < bd or (d == bd and c < best):
							bd = d
							best = c
				sx += maxi(step, 1)
	return best


## Ближайшая к (gx, gy) клетка компоненты cid в секторе s, если лучше bd; −1 — нет
func _nearest_in_sector(s: int, cid: int, gx: int, gy: int, bd: int, best: int) -> int:
	var rb := reg_base[s]
	var has := false
	for l in reg_n[s]:
		if comp[rb + l] == cid:
			has = true
			break
	if not has:
		return -1
	var x0 := (s % sw) * S
	var y0 := (s / sw) * S
	var x1 := mini(x0 + S, w)
	var y1 := mini(y0 + S, h)
	if sec_solid[s] == 0:                         # весь сектор — одна открытая область
		var cx := clampi(gx, x0, x1 - 1)
		var cy := clampi(gy, y0, y1 - 1)
		return cy * w + cx
	# строки — от ближайшей к цели наружу (стоп по лучшему); в строке ближайшие слева и справа
	# от столбца цели ищутся find/rfind по срезу строки
	var out := -1
	var od := bd
	var ob := best
	var yc := clampi(gy, y0, y1 - 1)
	var xi := clampi(gx, x0, x1 - 1) - x0
	var ady := absi(yc - gy)
	for l in reg_n[s]:
		if comp[rb + l] != cid:
			continue
		for k in 2 * S:
			var y := yc - (k + 1) / 2 if k % 2 == 1 else yc + k / 2
			if y < y0 or y >= y1:
				continue
			var dy := absi(y - yc) + ady
			var dy2 := dy * dy
			if dy2 > od:
				continue
			var row := lab.slice(y * w + x0, y * w + x1)
			for x_rel in [row.find(l, xi), row.rfind(l, xi)]:
				if x_rel < 0:
					continue
				var x: int = x0 + x_rel
				var c := y * w + x
				var d := (x - gx) * (x - gx) + dy2
				if d < od or (d == od and c < ob):
					od = d
					ob = c
					out = c
	return out


func checksum() -> int:
	return hash(solid)


# ---------------------------------------------------------------- внутреннее

func _mark_sector(s: int) -> void:
	if _dirty[s] == 0:
		_dirty[s] = 1
		_dirty_list.append(s)


func _ent_id(ca: int, dir: int) -> int:
	return ca * 2 + dir


## Метки 4-связных областей сектора s: отрезки строк, объединённые с перекрывающимися отрезками
## строки выше; номер области — по первой клетке в порядке строк (как у заливки с затравками по строкам)
func _relabel(s: int) -> void:
	var x0 := (s % sw) * S
	var y0 := (s / sw) * S
	var x1 := mini(x0 + S, w)
	var y1 := mini(y0 + S, h)
	var ncell := (x1 - x0) * (y1 - y0)
	if sec_solid[s] == 0 or sec_solid[s] == ncell:
		var l := 0 if sec_solid[s] == 0 else CLOSED
		for y in range(y0, y1):
			var base := y * w
			for x in range(x0, x1):
				lab[base + x] = l
		reg_n[s] = 1 if l == 0 else 0
		return
	var rs := PackedInt32Array()
	var re := PackedInt32Array()
	var ry := PackedInt32Array()
	var parent := PackedInt32Array()
	var prev0 := 0
	for y in range(y0, y1):
		var row0 := rs.size()
		var base := y * w
		var x := x0
		while x < x1:
			if solid[base + x] != 0:
				lab[base + x] = CLOSED
				x += 1
				continue
			var xs := x
			while x < x1 and solid[base + x] == 0:
				x += 1
			var r := rs.size()
			rs.append(xs)
			re.append(x - 1)
			ry.append(y)
			parent.append(r)
			for q in range(prev0, row0):
				if re[q] >= xs and rs[q] < x:
					_union(parent, r, q)
		prev0 = row0
	var lbl := PackedInt32Array()
	lbl.resize(rs.size())
	lbl.fill(-1)
	var n := 0
	for r in rs.size():
		var root := _find(parent, r)
		if lbl[root] < 0:
			lbl[root] = n
			n += 1
		var l := lbl[root]
		var base := ry[r] * w
		for x in range(rs[r], re[r] + 1):
			lab[base + x] = l
	reg_n[s] = n


## Входы границы сектора s: dir 0 — с восточным соседом, 1 — с южным. [cA, cB, lA, lB] × n
func _border(s: int, dir: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var x0 := (s % sw) * S
	var y0 := (s / sw) * S
	var n: int
	var ca0: int
	var step: int
	var off: int
	if dir == 0:
		var xa := mini(x0 + S, w) - 1
		n = mini(y0 + S, h) - y0
		ca0 = y0 * w + xa
		step = w
		off = 1
	else:
		var ya := mini(y0 + S, h) - 1
		n = mini(x0 + S, w) - x0
		ca0 = ya * w + x0
		step = 1
		off = w
	var run_start := -1
	var run_la := -1
	var run_lb := -1
	for i in n + 1:
		var la := -1
		var lb := -1
		if i < n:
			var ca := ca0 + i * step
			if solid[ca] == 0 and solid[ca + off] == 0:
				la = lab[ca]
				lb = lab[ca + off]
		if run_start >= 0 and (la != run_la or lb != run_lb):
			var run_end := i - 1
			var ln := run_end - run_start + 1
			if ln > RUN_SPLIT:
				_push_ent(out, ca0 + (run_start + 1) * step, off, run_la, run_lb)
				_push_ent(out, ca0 + (run_end - 1) * step, off, run_la, run_lb)
			else:
				_push_ent(out, ca0 + (run_start + (ln - 1) / 2) * step, off, run_la, run_lb)
			run_start = -1
		if la >= 0 and run_start < 0:
			run_start = i
			run_la = la
			run_lb = lb
	return out


func _push_ent(out: PackedInt32Array, ca: int, off: int, la: int, lb: int) -> void:
	out.append(ca)
	out.append(ca + off)
	out.append(la)
	out.append(lb)


## Соединяет точку id со всеми входами области (сектор s, метка l)
func _connect_region(id: int, s: int, l: int) -> void:
	var sx := s % sw
	var sy := s / sw
	# восточная и южная границы: сторона A — этот сектор
	_connect_list(id, _ent_e[s], 0, 2, l)
	_connect_list(id, _ent_s[s], 1, 2, l)
	# западная и северная: сторона B
	if sx > 0:
		_connect_list(id, _ent_e[s - 1], 0, 3, l)
	if sy > 0:
		_connect_list(id, _ent_s[s - sw], 1, 3, l)


func _connect_list(id: int, ent: PackedInt32Array, dir: int, li: int, l: int) -> void:
	for i in range(0, ent.size(), 4):
		if ent[i + li] != l:
			continue
		var other := _ent_id(ent[i], dir)
		if other != id and not graph.are_points_connected(id, other):
			graph.connect_points(id, other)


## Компоненты: объединение областей через входы всех границ (корень — меньший плотный номер)
func _components() -> void:
	_comp_dirty = false
	var ns := sw * sh
	var base := reg_base
	var acc := 0
	for s in ns:
		base[s] = acc
		acc += reg_n[s]
	base[ns] = acc
	var parent := PackedInt32Array()
	parent.resize(acc)
	for i in acc:
		parent[i] = i
	for s in ns:
		for dir in 2:
			var e := _ent_e[s] if dir == 0 else _ent_s[s]
			if e.is_empty():
				continue
			var s2 := s + 1 if dir == 0 else s + sw
			var pa := -1
			var pb := -1
			for i in range(0, e.size(), 4):
				if e[i + 2] == pa and e[i + 3] == pb:
					continue
				pa = e[i + 2]
				pb = e[i + 3]
				var a := base[s] + pa
				var b := base[s2] + pb
				while parent[a] != a:
					parent[a] = parent[parent[a]]
					a = parent[a]
				while parent[b] != b:
					parent[b] = parent[parent[b]]
					b = parent[b]
				if a < b:
					parent[b] = a
				elif b < a:
					parent[a] = b
	comp.resize(acc)
	for i in acc:
		var r := i
		while parent[r] != r:
			r = parent[r]
		parent[i] = r
		comp[i] = r


func _find(parent: PackedInt32Array, k: int) -> int:
	var r := k
	while parent[r] != r:
		r = parent[r]
	while parent[k] != r:
		var nx := parent[k]
		parent[k] = r
		k = nx
	return r


func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra < rb:
		parent[rb] = ra
	elif rb < ra:
		parent[ra] = rb
