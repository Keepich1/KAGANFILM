class_name PathService
extends RefCounted
## Служба путей (ARCHITECTURE §9.4–§9.8): очередь билетов, бюджет счётом, решение запроса.
##
## Бюджет такта — rules.path_per_tick запросов (16) и rules.path_cells_per_tick оценённых клеток
## (8000, сумма октильных оценок). Очередь — FIFO (запросы с prio > 0 — вперёд обычных); не влезший
## запрос ждёт следующего такта, следующие за ним — тоже (без обгона). Первый запрос такта служится
## всегда. На любом процессоре — одинаковый порядок и результат.
##
## Решение (solve), для команды t:
##   a. оба конца — к ближайшей открытой клетке walk[t] (не дальше 40 м);
##   b. одна компонента walk[t]: прямая видимость → путь из одной точки; иначе одна область —
##      AStarGrid2D; иначе коридор по графу входов (AStar2D); коридор через ≤ 2 сектора — один A*,
##      длиннее — A* между соседними входами, склейка;
##   c. разные компоненты, у врага есть постройки и breach[t] связен: A* по breach[t] (чужие постройки
##      с весом 4); первая чужая клетка пути даёт breach_b, breach_wp — точка перед ней;
##   d. иначе — путь к ближайшей к цели клетке своей компоненты, no_route = true;
##   e. сглаживание: натягивание нити по точкам поворота с проверкой прямой видимости
##      (клетки открыты и не тяжелее концов отрезка — вода и поле не срезаются с суши);
##   f. rules.breach_ratio > 0: обход дороже ratio × октиль — сравнивается и путь с проломом.
## Кэш ходок (§9.8): готовые пути по ключу (команда, клетка от, клетка до), годны, пока секторы
## пути не менялись; обратный путь — тот же, развёрнутый.

const SNAP_R := 40.0
const CACHE_MAX := 256

var per_tick := 16
var cells_per_tick := 8000
var breach_ratio := 0.0
var use_cache := true

# замеры и тесты (не входят в контрольную сумму)
var last_served := 0
var last_cells := 0
var served_total := 0
var cache_hits := 0
var trace := false                 # тесты: журнал обслуженных [такт, команда, от, до, из кэша]
var trace_log: Array = []

var _next := 1
var _hi: Array[Array] = []         # [ticket, team, from, to, client, est]
var _lo: Array[Array] = []
var _hi_head := 0
var _lo_head := 0
var _results := {}                 # ticket → PathResult (null — в очереди)
var _cache := {}                   # ключ → [full: PackedVector2Array, sectors, ver, cost]
var _cache_keys := PackedInt64Array()


func setup(rules: Dictionary) -> void:
	per_tick = maxi(1, int(rules.get("path_per_tick", 16)))
	cells_per_tick = maxi(1, int(rules.get("path_cells_per_tick", 8000)))
	breach_ratio = float(rules.get("breach_ratio", 0.0))


func request(g: NavGrid, team: int, from: Vector2, to: Vector2, client: int, prio: int) -> int:
	var t := _next
	_next += 1
	_results[t] = null
	var e := [t, team, from, to, client, g.octile_cells(from, to)]
	if prio > 0:
		_hi.append(e)
	else:
		_lo.append(e)
	return t


func pending() -> int:
	return (_hi.size() - _hi_head) + (_lo.size() - _lo_head)


func service(g: NavGrid, tick: int) -> void:
	g.sync_for_paths()
	var served := 0
	var cells := 0
	while served < per_tick:
		var e: Array = []
		var hi := false
		if _hi_head < _hi.size():
			e = _hi[_hi_head]
			hi = true
		elif _lo_head < _lo.size():
			e = _lo[_lo_head]
		else:
			break
		var t: int = e[0]
		if not _results.has(t):          # отпущен до обслуживания — не считается
			_pop(hi)
			continue
		var est: int = e[5]
		if served > 0 and cells + est > cells_per_tick:
			break
		_pop(hi)
		var hits := cache_hits
		_results[t] = solve(g, e[1], e[2], e[3], use_cache)
		if trace:
			trace_log.append([tick, e[1], e[2], e[3], cache_hits != hits])
		served += 1
		cells += est
	last_served = served
	last_cells = cells
	served_total += served
	_compact()


func result(ticket: int) -> PathResult:
	return _results.get(ticket, null)


func release(ticket: int) -> void:
	_results.erase(ticket)


func checksum() -> int:
	return (_next * 7919 + pending() * 31 + _results.size()) & 0x7FFFFFFF


# ================================================================= решение

func solve(g: NavGrid, t: int, from: Vector2, to: Vector2, cached := false) -> PathResult:
	var r := PathResult.new()
	r.issued_ver = g.version
	var wl := g.walk_layer(t)
	var from_c := g.clamp_pos(from)
	var to_c := g.clamp_pos(to)
	var cs := g.snap_cell(wl, from_c, SNAP_R)
	if cs < 0:                                       # стоит в закрытом месте без выхода рядом
		r.no_route = true
		r.pts = PackedVector2Array([from_c])
		r.sectors = g.sectors_of(r.pts)
		return r
	var start_p := from_c if g.cell_of(from_c) == cs else g.cell_center(cs)
	var lead := start_p != from_c
	var cg := g.snap_cell(wl, to_c, SNAP_R)
	var cs_comp := wl.comp_of(cs)
	if cg >= 0 and wl.comp_of(cg) == cs_comp:
		var goal_p := to_c if g.cell_of(to_c) == cg else g.cell_center(cg)
		var key := ((t * g.w * g.h) + cs) * (g.w * g.h) + cg
		if cached and not lead and goal_p == to_c:
			var hit := _cache_get(g, key, t, cs, cg, goal_p)
			if hit != null:
				return hit
		var cells := walk_cells(g, wl, cs, cg)
		if breach_ratio > 0.0 and g.enemy_structs(t):
			var alt := _breach_alt(g, t, wl, cells, cs, to_c, goal_p, start_p, lead)
			if alt != null:
				return alt
		r.pts = smooth(g, wl, cells, 0, cells.size() - 1, goal_p)
		_finish(g, r, start_p, lead)
		if cached and not lead and goal_p == to_c:
			_cache_put(key, start_p, r)
		return r
	# c. пролом
	var bl := g.breach_layer(t)
	if g.enemy_structs(t):
		var bg := cg if cg >= 0 else g.snap_cell(bl, to_c, SNAP_R)
		if bg >= 0 and bl.comp_of(bg) == bl.comp_of(cs):
			var goal_p := to_c if g.cell_of(to_c) == bg else g.cell_center(bg)
			var bcells := astar_cells(bl, cs, bg)
			if not bcells.is_empty():
				_breach_pts(g, t, wl, r, bcells, goal_p)
				_finish(g, r, start_p, lead)
				return r
	# d. нет прохода: к ближайшей к цели клетке своей компоненты
	var gc := g.cell_of(to_c)
	var cn := wl.nearest_in_comp(cs_comp, gc)
	if cn < 0:
		cn = cs
	var ncells := walk_cells(g, wl, cs, cn)
	r.pts = smooth(g, wl, ncells, 0, ncells.size() - 1, g.cell_center(cn) if cn != cs else start_p)
	r.no_route = true
	_finish(g, r, start_p, lead)
	return r


## Клетки пути от cs до cg по слою walk (одна компонента)
func walk_cells(g: NavGrid, wl: NavRegions, cs: int, cg: int) -> PackedInt32Array:
	if cs == cg:
		return PackedInt32Array([cs])
	if g.los(wl, cs, cg):
		return PackedInt32Array([cs, cg])
	if wl.sector_of(cs) == wl.sector_of(cg) and wl.lab[cs] == wl.lab[cg]:
		return astar_cells(wl, cs, cg)
	var cor := wl.corridor(cs, cg)
	if cor.size() <= 1:
		return astar_cells(wl, cs, cg)
	# уточнение по входам коридора
	var out := PackedInt32Array([cs])
	var cur := cs
	var cur_s := wl.sector_of(cs)
	var cur_l := wl.lab[cs]
	var n := cor.size()
	for i in n:
		var ec := wl.ent_cells(cor[i])
		var near := ec.x
		var far := ec.y
		if wl.sector_of(ec.y) == cur_s and wl.lab[ec.y] == cur_l:
			near = ec.y
			far = ec.x
		# следующий вход (или цель) в той же области — этот вход не пересекаем
		var nxt_in_cur := false
		if i + 1 < n:
			var en := wl.ent_cells(cor[i + 1])
			nxt_in_cur = (wl.sector_of(en.x) == cur_s and wl.lab[en.x] == cur_l) or \
				(wl.sector_of(en.y) == cur_s and wl.lab[en.y] == cur_l)
		else:
			nxt_in_cur = wl.sector_of(cg) == cur_s and wl.lab[cg] == cur_l
		if nxt_in_cur:
			continue
		_append_astar(out, wl, cur, near)
		if out[out.size() - 1] != far:
			out.append(far)
		cur = far
		cur_s = wl.sector_of(far)
		cur_l = wl.lab[far]
	_append_astar(out, wl, cur, cg)
	return out


func astar_cells(layer: NavRegions, a: int, b: int) -> PackedInt32Array:
	var out := PackedInt32Array([a])
	_append_astar(out, layer, a, b)
	return out


func _append_astar(out: PackedInt32Array, layer: NavRegions, a: int, b: int) -> void:
	if a == b:
		return
	var w := layer.w
	var path := layer.astar.get_id_path(Vector2i(a % w, a / w), Vector2i(b % w, b / w))
	if path.is_empty():
		out.append(b)                                # не должно быть (одна компонента)
		return
	for i in range(1, path.size()):
		var p: Vector2i = path[i]
		out.append(p.y * w + p.x)


## Натягивание нити по клеткам cells[i0..i1]: точки (без начальной), последняя — last_p
func smooth(g: NavGrid, layer: NavRegions, cells: PackedInt32Array, i0: int, i1: int,
		last_p: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	if i1 <= i0:
		out.append(last_p)
		return out
	# точки поворота
	var tp := PackedInt32Array([i0])
	for i in range(i0 + 1, i1):
		if cells[i] - cells[i - 1] != cells[i + 1] - cells[i]:
			tp.append(i)
	tp.append(i1)
	var last := tp.size() - 1
	var a := 0
	while a < last:
		var ca := cells[tp[a]]
		var best := a + 1
		if g.los(layer, ca, cells[tp[last]]):
			best = last
		else:
			# скачками вперёд, затем делением пополам
			var ok := a + 1
			var bad := last
			var step := 1
			while true:
				var j := a + 1 + step
				if j >= last:
					break
				if g.los(layer, ca, cells[tp[j]]):
					ok = j
					step *= 2
				else:
					bad = j
					break
			while bad - ok > 1:
				var m := (ok + bad) / 2
				if g.los(layer, ca, cells[tp[m]]):
					ok = m
				else:
					bad = m
			best = ok
		out.append(last_p if best == last else g.cell_center(cells[tp[best]]))
		a = best
	return out


## Путь с проломом: до первой чужой постройки — сглажен, дальше — точки поворота
func _breach_pts(g: NavGrid, t: int, wl: NavRegions, r: PathResult, cells: PackedInt32Array,
		goal_p: Vector2) -> void:
	var k := -1
	for i in cells.size():
		if g.is_enemy_struct(t, cells[i]):
			k = i
			break
	if k <= 0:                                       # без чужих клеток (не должно быть) — как обычный
		r.pts = smooth(g, wl, cells, 0, cells.size() - 1, goal_p)
		return
	var pts := PackedVector2Array()
	if k - 1 > 0:
		pts = smooth(g, wl, cells, 0, k - 1, g.cell_center(cells[k - 1]))
	else:
		pts.append(g.cell_center(cells[0]))
	r.breach_wp = pts.size() - 1
	r.breach_b = g.struct_at_cell(cells[k])
	for i in range(k, cells.size() - 1):
		if i == k or cells[i] - cells[i - 1] != cells[i + 1] - cells[i]:
			pts.append(g.cell_center(cells[i]))
	pts.append(goal_p)
	r.pts = pts


## f. обход дороже ratio × октиль — путь с проломом, если он дешевле
func _breach_alt(g: NavGrid, t: int, wl: NavRegions, cells: PackedInt32Array, cs: int, to_c: Vector2,
		goal_p: Vector2, start_p: Vector2, lead: bool) -> PathResult:
	var cg := cells[cells.size() - 1]
	var walk_cost := g.cells_cost(wl, cells, false, t)
	var oct := float(g.octile_cell(cs, cg))
	if walk_cost <= breach_ratio * oct:
		return null
	var bl := g.breach_layer(t)
	var bcells := astar_cells(bl, cs, cg)
	if bcells.is_empty() or g.cells_cost(bl, bcells, true, t) >= walk_cost:
		return null
	var r := PathResult.new()
	r.issued_ver = g.version
	_breach_pts(g, t, wl, r, bcells, goal_p)
	if r.breach_b == 0:
		return null
	_finish(g, r, start_p, lead)
	return r


func _finish(g: NavGrid, r: PathResult, start_p: Vector2, lead: bool) -> void:
	if lead:
		r.pts.insert(0, start_p)
		if r.breach_wp >= 0:
			r.breach_wp += 1
	var poly := PackedVector2Array([start_p])
	poly.append_array(r.pts)
	var cost := 0.0
	for i in range(1, poly.size()):
		cost += poly[i - 1].distance_to(poly[i])
	r.cost = cost
	r.sectors = g.sectors_of(poly)


# ================================================================= очередь и кэш

func _pop(hi: bool) -> void:
	if hi:
		_hi_head += 1
	else:
		_lo_head += 1


func _compact() -> void:
	if _hi_head > 64 and _hi_head * 2 > _hi.size():
		_hi = _hi.slice(_hi_head)
		_hi_head = 0
	if _lo_head > 64 and _lo_head * 2 > _lo.size():
		_lo = _lo.slice(_lo_head)
		_lo_head = 0
	if _hi_head == _hi.size() and _hi_head > 0:
		_hi.clear()
		_hi_head = 0
	if _lo_head == _lo.size() and _lo_head > 0:
		_lo.clear()
		_lo_head = 0


func _cache_get(g: NavGrid, key: int, t: int, cs: int, cg: int, goal_p: Vector2) -> PathResult:
	var rev := false
	var e: Array = _cache.get(key, [])
	if e.is_empty():
		var rkey := ((t * g.w * g.h) + cg) * (g.w * g.h) + cs
		e = _cache.get(rkey, [])
		if e.is_empty():
			return null
		rev = true
		key = rkey
	var sectors: PackedInt32Array = e[1]
	if g.stale_sectors(sectors, e[2]):
		_cache.erase(key)
		return null
	var full: PackedVector2Array = e[0]
	if rev:
		full = full.duplicate()
		full.reverse()
	var r := PathResult.new()
	r.issued_ver = g.version
	r.pts = full.slice(1)
	r.pts[r.pts.size() - 1] = goal_p
	r.cost = e[3]
	r.sectors = sectors
	cache_hits += 1
	return r


func _cache_put(key: int, start_p: Vector2, r: PathResult) -> void:
	if _cache.has(key):
		return
	var full := PackedVector2Array([start_p])
	full.append_array(r.pts)
	_cache[key] = [full, r.sectors, r.issued_ver, r.cost]
	_cache_keys.append(key)
	if _cache_keys.size() > CACHE_MAX:
		_cache.erase(_cache_keys[0])
		_cache_keys = _cache_keys.slice(1)
