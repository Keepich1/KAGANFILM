class_name NavRegions
extends RefCounted
## Слой проходимости одной команды (ARCHITECTURE §6.5, §9): сетка AStarGrid2D + граф секторов.
## У команды два слоя: walk (свои постройки и чужое — сплошные, свои ворота — проход) и
## breach (чужие постройки — вес W_BREACH, без графа ворот).
##
## Граф секторов (HPA*): сетка режется на секторы 16 × 16 клеток; внутри сектора — метки
## 4-связных областей (lab, 255 — закрыто). Входы — отрезки общей границы соседних секторов,
## где обе клетки открыты; у каждого входа точка в AStar2D (только walk). Компоненты связности —
## номер у каждой области (rcomp[s * RMAX + метка], слияния — через _cpar): reachable за O(1).
## Правки клеток (set_cell) помечают сектор грязным; flush() перемечивает только грязные
## секторы и их границы (точки AStar2D — только у границ, чьи входы сменились), а компоненты правит
## по месту (_update_components): слияние — объединением номеров, возможный разрыв — попеременным
## обходом из частей, который останавливается, как только части встретились (обход вокруг конца
## стены) или одна исчерпана (она и отрезана). Полный пересчёт (_components) — только при первой
## разметке и при сжатии номеров (или если частей разрыва больше SPLIT_FRONTS).
## flush зовёт только код симуляции (NavGrid — в service/find_now/reachable): порядок правок
## AStar2D должен быть одинаков в каждом прогоне.

const S := 16                 # = NavApi.SECTOR
const RMAX := 256             # меток в секторе (байт); номер области — s * RMAX + метка
const SPLIT_FRONTS := 60      # частей разрыва больше — полный пересчёт (номер части — 6 бит)
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
var rcomp := PackedInt32Array()            # [s * RMAX + метка] → номер компоненты (корень — _cfind)
var flushes := 0                           # сколько раз перемечали (для замеров)
var full_passes := 0                       # полных пересчётов компонент (для замеров)
var split_visits := 0                      # областей пройдено проверками разрыва (для замеров)

var _comp_dirty := true
var _cpar := PackedInt32Array()            # объединения номеров компонент (слияния без перенумерации)
var _regions := 0                          # областей всего (порог сжатия _cpar)
var _vis := PackedInt32Array()             # отметки обхода: эпоха << 6 | часть (по требованию)
var _epoch := 0
var _l_map := {}                           # местные группы flush: номер области → местный номер
var _l_rk := PackedInt32Array()
var _l_par := PackedInt32Array()
var _l_anc := PackedByteArray()            # 1 — якорь (область чистого сектора за границей)
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
	rcomp.resize(ns * RMAX)
	rcomp.fill(-1)
	_cpar.clear()
	_vis.clear()
	_epoch = 0
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
	return _cfind(rcomp[sector_of(c) * RMAX + l])


## Перемечает грязные секторы, их границы, входы и компоненты. true — было что перемечать
func flush() -> bool:
	if _dirty_list.is_empty():
		return false
	flushes += 1
	var list := _dirty_list.duplicate()
	list.sort()
	var inc := not _comp_dirty                   # компоненты — по месту (иначе полный пересчёт по запросу)
	var same := inc
	for s in list:
		var before := reg_n[s]
		_relabel(s)
		_regions += reg_n[s] - before
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
	# граница с теми же входами (клетки и метки обеих сторон) не трогается: связи её точек с прочими
	# входами секторов зависят только от равенства меток, а метки те же. Перестраиваются только
	# сменившиеся границы: их точки снимаются (со связями) и ставятся заново
	var changed := PackedInt32Array()
	var old_anchor := PackedInt32Array()         # области чистых секторов, смежные с грязными до правки
	for k in bk:
		var old_e := _ent_e[k >> 1] if k & 1 == 0 else _ent_s[k >> 1]
		var ne := _border(k >> 1, k & 1)
		if ne == old_e:
			continue
		changed.append(k)
		if inc:
			same = same and _pairs(old_e) == _pairs(ne)
			_collect_anchors(k, old_e, old_anchor)
		if portals:
			for i in range(0, old_e.size(), 4):
				graph.remove_point(_ent_id(old_e[i], k & 1))
		if k & 1 == 0:
			_ent_e[k >> 1] = ne
		else:
			_ent_s[k >> 1] = ne
	if portals:
		for k in changed:
			var ent := _ent_e[k >> 1] if k & 1 == 0 else _ent_s[k >> 1]
			for i in range(0, ent.size(), 4):
				var ca := ent[i]
				var cb := ent[i + 1]
				var pa := Vector2(ca % w, ca / w)
				var pb := Vector2(cb % w, cb / w)
				graph.add_point(_ent_id(ca, k & 1), (pa + pb) * 0.5 + Vector2(0.5, 0.5))
		for k in changed:
			var ent := _ent_e[k >> 1] if k & 1 == 0 else _ent_s[k >> 1]
			var sa := k >> 1
			var sb := sa + 1 if k & 1 == 0 else sa + sw
			for i in range(0, ent.size(), 4):
				var id := _ent_id(ent[i], k & 1)
				_connect_region(id, sa, ent[i + 2])
				_connect_region(id, sb, ent[i + 3])
	# связность меняется, только если сменилось число областей или пары меток на границах
	if inc and not same:
		_update_components(list, bk, old_anchor)
	for s in list:
		_dirty[s] = 0
	_dirty_list.clear()
	if not _comp_dirty and _cpar.size() > 4 * _regions + 4096:
		_comp_dirty = true                       # сжатие номеров: полный пересчёт при следующем запросе
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
	var rb := s * RMAX
	var has := false
	for l in reg_n[s]:
		if _cfind(rcomp[rb + l]) == cid:
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
		if _cfind(rcomp[rb + l]) != cid:
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


## Компоненты заново: объединение областей через входы всех границ; номера — 0, 1, … по первой
## области компоненты (в порядке секторов и меток), _cpar — тождественный
func _components() -> void:
	_comp_dirty = false
	full_passes += 1
	var ns := sw * sh
	var base := PackedInt32Array()
	base.resize(ns + 1)
	var acc := 0
	for s in ns:
		base[s] = acc
		acc += reg_n[s]
	base[ns] = acc
	_regions = acc
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
	_cpar.clear()
	var cid := PackedInt32Array()
	cid.resize(acc)
	cid.fill(-1)
	for s in ns:
		var rb := s * RMAX
		var bs := base[s]
		for l in reg_n[s]:
			var r := bs + l
			while parent[r] != r:
				r = parent[r]
			if cid[r] < 0:
				cid[r] = _cpar.size()
				_cpar.append(cid[r])
			rcomp[rb + l] = cid[r]


## Номер компоненты-корня (сжатие пути делением пополам)
func _cfind(c: int) -> int:
	while _cpar[c] != c:
		var p := _cpar[_cpar[c]]
		_cpar[c] = p
		c = p
	return c


func _cnew() -> int:
	var id := _cpar.size()
	_cpar.append(id)
	return id


## Слияние компонент a и b (корень — меньший номер); ответ — корень
func _cunion(a: int, b: int) -> int:
	a = _cfind(a)
	b = _cfind(b)
	if a < b:
		_cpar[b] = a
		return a
	if b < a:
		_cpar[a] = b
	return b


## Якоря границы k: области её чистой стороны (её метки не менялись) из входов ent
func _collect_anchors(k: int, ent: PackedInt32Array, out: PackedInt32Array) -> void:
	var sa := k >> 1
	var sb := sa + 1 if k & 1 == 0 else sa + sw
	var da := _dirty[sa] != 0
	var db := _dirty[sb] != 0
	if da and db:
		return
	var pa := -1
	var pb := -1
	for i in range(0, ent.size(), 4):
		if ent[i + 2] == pa and ent[i + 3] == pb:
			continue
		pa = ent[i + 2]
		pb = ent[i + 3]
		if not da:
			out.append(sa * RMAX + pa)
		if not db:
			out.append(sb * RMAX + pb)


## Компоненты после перемечивания секторов list (границы bk уже новые). Местные группы: области
## грязных секторов и якоря (области чистых соседей, смежные с грязными до или после правки),
## объединённые по новым входам. Группа с якорями разных компонент — их слияние; группа без якорей —
## новая компонента; компонента, чьи якоря оказались в нескольких группах, могла распасться —
## её проверяет _split. Остальные компоненты правка не задела: их пути в грязные секторы не входят.
func _update_components(list: PackedInt32Array, bk: PackedInt32Array, old_anchor: PackedInt32Array) -> void:
	_l_map.clear()
	_l_rk.clear()
	_l_par.clear()
	_l_anc.clear()
	for s in list:
		for l in reg_n[s]:
			_loc(s * RMAX + l, 0)
	for rk in old_anchor:
		_loc(rk, 1)
	for k in bk:
		var e := _ent_e[k >> 1] if k & 1 == 0 else _ent_s[k >> 1]
		var sa := k >> 1
		var sb := sa + 1 if k & 1 == 0 else sa + sw
		var anc_a := 0 if _dirty[sa] != 0 else 1
		var anc_b := 0 if _dirty[sb] != 0 else 1
		var pa := -1
		var pb := -1
		for i in range(0, e.size(), 4):
			if e[i + 2] == pa and e[i + 3] == pb:
				continue
			pa = e[i + 2]
			pb = e[i + 3]
			var ia := _loc(sa * RMAX + pa, anc_a)
			var ib := _loc(sb * RMAX + pb, anc_b)
			var ra := _find(_l_par, ia)
			var rb := _find(_l_par, ib)
			if ra < rb:
				_l_par[rb] = ra
			elif rb < ra:
				_l_par[ra] = rb
	var n := _l_rk.size()
	var grp := PackedInt32Array()
	grp.resize(n)
	var gcomp := PackedInt32Array()               # компонента группы (−1 — без якорей)
	var g_of_root := {}
	for i in n:
		var r := _find(_l_par, i)
		if not g_of_root.has(r):
			g_of_root[r] = gcomp.size()
			gcomp.append(-1)
		var gi: int = g_of_root[r]
		grp[i] = gi
		if _l_anc[i] != 0:
			var c := _cfind(rcomp[_l_rk[i]])
			gcomp[gi] = c if gcomp[gi] < 0 else _cunion(gcomp[gi], c)
	var ng := gcomp.size()
	var by_c := {}                                 # компонента → её группы с якорями (по порядку)
	for gi in ng:
		if gcomp[gi] < 0:
			gcomp[gi] = _cnew()
			continue
		var c := _cfind(gcomp[gi])
		gcomp[gi] = c
		if not by_c.has(c):
			by_c[c] = PackedInt32Array()
		var lst: PackedInt32Array = by_c[c]
		lst.append(gi)
		by_c[c] = lst
	for i in n:
		if _l_anc[i] == 0:
			rcomp[_l_rk[i]] = gcomp[grp[i]]
	for c: int in by_c:
		var gs: PackedInt32Array = by_c[c]
		if gs.size() < 2:
			continue
		var seeds: Array[PackedInt32Array] = []
		var slot := {}
		for gi in gs:
			slot[gi] = seeds.size()
			seeds.append(PackedInt32Array())
		for i in n:
			if slot.has(grp[i]):
				var si: int = slot[grp[i]]
				var sd: PackedInt32Array = seeds[si]
				sd.append(_l_rk[i])
				seeds[si] = sd
		_split(seeds)
		if _comp_dirty:
			return


## Местный номер области rk (новый — с отметкой якоря anc)
func _loc(rk: int, anc: int) -> int:
	var i: int = _l_map.get(rk, -1)
	if i >= 0:
		if anc != 0:
			_l_anc[i] = 1
		return i
	i = _l_rk.size()
	_l_map[rk] = i
	_l_rk.append(rk)
	_l_par.append(i)
	_l_anc.append(anc)
	return i


## Разрыв компоненты: части seeds (области, связные внутри каждой части) обходятся по графу областей
## попеременно, по одной области. Встретились — одна часть; исчерпана, пока другие живы, — отрезана:
## её области получают новый номер. Последняя живая часть сохраняет номер компоненты.
func _split(seeds: Array[PackedInt32Array]) -> void:
	var k := seeds.size()
	if k > SPLIT_FRONTS:
		_comp_dirty = true
		return
	if _vis.size() != rcomp.size():
		_vis.resize(rcomp.size())
		_vis.fill(0)
		_epoch = 0
	_epoch += 1
	if _epoch >= (1 << 24):
		_vis.fill(0)
		_epoch = 1
	var base := _epoch << 6
	var qu: Array[PackedInt32Array] = []          # очередь части
	var vl: Array[PackedInt32Array] = []          # пройденные области части
	var head := PackedInt32Array()
	var fpar := PackedInt32Array()
	var alive := PackedByteArray()
	for f in k:
		var seed: PackedInt32Array = seeds[f]
		for rk in seed:
			_vis[rk] = base | f
		qu.append(seed.duplicate())
		vl.append(seed.duplicate())
		head.append(0)
		fpar.append(f)
		alive.append(1)
	var active := k
	var budget := 2 * _regions + 64               # страховка: столько областей — уже полный обход
	while active > 1:
		for f in k:
			if active <= 1:
				break
			if alive[f] == 0:
				continue
			var q: PackedInt32Array = qu[f]
			var vf: PackedInt32Array = vl[f]
			if head[f] >= q.size():
				var id := _cnew()                      # исчерпана: отрезанная компонента
				for rk in vf:
					rcomp[rk] = id
				alive[f] = 0
				active -= 1
				continue
			var rk := q[head[f]]
			head[f] += 1
			split_visits += 1
			budget -= 1
			if budget < 0:
				_comp_dirty = true
				return
			var s := rk >> 8
			var l := rk & 255
			var sx := s % sw
			for side in 4:
				var e: PackedInt32Array
				var mine: int
				var nb_s: int
				if side == 0:
					e = _ent_e[s]
					mine = 2
					nb_s = s + 1
				elif side == 1:
					e = _ent_s[s]
					mine = 2
					nb_s = s + sw
				elif side == 2:
					if sx == 0:
						continue
					e = _ent_e[s - 1]
					mine = 3
					nb_s = s - 1
				else:
					if s < sw:
						continue
					e = _ent_s[s - sw]
					mine = 3
					nb_s = s - sw
				var other := 5 - mine
				for i in range(0, e.size(), 4):
					if e[i + mine] != l:
						continue
					var nb := nb_s * RMAX + e[i + other]
					var v := _vis[nb]
					if v >> 6 != _epoch:
						_vis[nb] = base | f
						q.append(nb)
						vf.append(nb)
						continue
					var o := _find(fpar, v & 63)
					if o == f:
						continue
					# встреча: часть o вливается в f — сразу, с каждой встреченной частью (иначе смежность
					# с другой частью, уже пройденной с обеих сторон, потерялась бы — ложный разрыв)
					var oq: PackedInt32Array = qu[o]
					q.append_array(oq.slice(head[o]))
					vf.append_array(vl[o])
					fpar[o] = f
					alive[o] = 0
					qu[o] = PackedInt32Array()
					vl[o] = PackedInt32Array()
					active -= 1
			qu[f] = q
			vl[f] = vf


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
