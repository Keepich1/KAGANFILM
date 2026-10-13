class_name NavGrid
extends NavApi
## Навигация «Города» (ARCHITECTURE §6.5, §7.2, §9, §10): сетка 4 м, штампы построек, пути,
## расстановка, стены. За ней — NavRegions (слои команд и граф секторов), PathService (очередь и
## решение), NavRaster (суперобложка), Placement (правила места), WallTool (стены, ворота, башни).
##
## Данные клетки c = row * w + col:
##   flags      NavApi.F: статика (STATIC — крутизна или глубокая вода, WATER, FORD — мелкая вода,
##              проходима с весом 2) | штампы (STRUCT, WALL, GATE, SOFT — поле, вес 1,5) | NODE — ядро жилы
##   team_of    команда постройки клетки (255 — нет); struct_of — описатель первой постройки клетки (0)
## Слои команды t: walk[t] (постройки и жилы сплошные, свои ворота — проход) и breach[t] (чужие
## постройки — вес W_BREACH = 4, свои — сплошные). Каждый штамп поднимает version и версию
## затронутых секторов (устаревание путей), правит оба слоя всех команд и помечает секторы для
## перемечивания графа (лениво: в service/find_now/reachable).
##
## Детерминизм: случайности нет; Dictionary — только с детерминированным порядком вставки;
## флаши графа и синхронизация жил — только из кода симуляции (service, find_now, reachable,
## штампы). Вызовы из вида и интерфейса (check_place, place_cells, plan_wall, snap…) состояние
## навигации не меняют.
##
## info — Terrain.info() (size, spacing, origin) + необязательные ключи NAV:
##   teams (2) — слои скольких команд построить сразу (остальные — по первому запросу, до 4);
##   flat (false) — без рельефа (тесты на больших сетках); rules — словарь правил (иначе GOROD).

const W_BREACH := 4.0
const W_WATER := 2.0
const W_SOFT := 1.5
const DEEP_WATER := 0.8           # м: глубже — непроходимо
const WET := 0.05                 # м: мельче — суша (= Terrain.is_water)
const MAX_SLOPE := 0.75           # подъём/шаг по клетке: круче — непроходимо
const SPD_WATER := 9              # ×16: мелкая вода 0,55
const MAX_TEAMS := 4
const NO_TEAM := 255

var flags := PackedByteArray()
var team_of := PackedByteArray()
var struct_of := PackedInt32Array()

var defs: Defs
var flat := false                            # без рельефа (info.flat)
## ECON и порт держат навигацию; навигация держит их слабо (иначе кольцо RefCounted не освобождается)
var econ: EconApi:
	get:
		return _econ_w.get_ref() as EconApi if _econ_w != null else null
	set(v):
		_econ_w = weakref(v) if v != null else null
var port: CombatPort:
	get:
		return _port_w.get_ref() as CombatPort if _port_w != null else null
	set(v):
		_port_w = weakref(v) if v != null else null
var rules := {}

var _econ_w: WeakRef
var _port_w: WeakRef

var _static_f := PackedByteArray()           # статические флаги (рельеф)
var _static_cells := PackedInt32Array()      # клетки с ненулевой статикой
var _spd := PackedByteArray()
var _wcode := PackedByteArray()              # вес клетки: 0 — 1, 1 — поле, 2 — вода
var _cnt := PackedByteArray()                # сколько штампов на клетке
var _multi := {}                             # клетка → PackedInt32Array описателей (при _cnt ≥ 2)
var _stamps := {}                            # описатель → PackedInt32Array [команда, тип, флаги, клетки…]
var _node_cnt := PackedByteArray()           # ядра жил на клетке
var _deposits := {}                          # слот узла → PackedInt32Array [gen, клетки…]
var _dep_hash := Vector2i(0, 0)
var _sector_ver := PackedInt32Array()
var _team_structs := PackedInt32Array()      # штампов STRUCT по командам
var _walk: Array[NavRegions] = []
var _breach: Array[NavRegions] = []
var _sw := 0
var _sh := 0

# индекс узлов по клеткам (деревья и жилы) — только для расстановки
var _n_head := PackedInt32Array()
var _n_next := PackedInt32Array()
var _n_hash := Vector2i(0, 0)

var paths := PathService.new()
var placement := Placement.new()
var walls := WallTool.new()


func setup(info: Dictionary, p_defs: Defs, p_econ: EconApi, p_port: CombatPort) -> void:
	defs = p_defs
	econ = p_econ
	port = p_port
	rules = info.get("rules", defs.rules_of(&"GOROD") if defs else {})
	var n := int(info.get("size", 513))
	var spacing := float(info.get("spacing", 2.0))
	var o: Array = info.get("origin", [-512.0, -512.0])
	origin = Vector2(float(o[0]), float(o[1]))
	w = int((n - 1) * spacing / CELL)
	h = w
	version = 0
	_sw = ceili(float(w) / SECTOR)
	_sh = ceili(float(h) / SECTOR)
	var wh := w * h
	flags.resize(wh)
	flags.fill(0)
	team_of.resize(wh)
	team_of.fill(NO_TEAM)
	struct_of.resize(wh)
	struct_of.fill(0)
	_cnt.resize(wh)
	_cnt.fill(0)
	_node_cnt.resize(wh)
	_node_cnt.fill(0)
	_wcode.resize(wh)
	_wcode.fill(0)
	_spd.resize(wh)
	_spd.fill(16)
	_sector_ver.resize(_sw * _sh)
	_sector_ver.fill(0)
	_team_structs.resize(MAX_TEAMS)
	_team_structs.fill(0)
	_static_f.resize(wh)
	_static_f.fill(0)
	_multi.clear()
	_stamps.clear()
	_deposits.clear()
	_walk.clear()
	_breach.clear()
	flat = bool(info.get("flat", false)) or Terrain.size() == 0
	if not flat:
		_build_static()
	for c in _static_cells:
		flags[c] = _static_f[c]
		_wcode[c] = 2 if _static_f[c] & F.WATER else 0
	paths = PathService.new()
	paths.setup(rules)
	placement = Placement.new()
	walls = WallTool.new()
	for t in clampi(int(info.get("teams", 2)), 1, MAX_TEAMS):
		_ensure_team(t)
	_sync_deposits()
	for t in _walk.size():
		_walk[t].flush()
		_breach[t].flush()


# ================================================================= сетка

func passable(team: int, c: int) -> bool:
	if c < 0 or c >= w * h:
		return false
	return walk_layer(team).solid[c] == 0


func reachable(team: int, a: Vector2, b: Vector2) -> bool:
	sync_for_paths()
	var wl := walk_layer(team)
	var ca := snap_cell(wl, clamp_pos(a), PathService.SNAP_R)
	var cb := snap_cell(wl, clamp_pos(b), PathService.SNAP_R)
	return ca >= 0 and cb >= 0 and wl.comp_of(ca) == wl.comp_of(cb)


func nearest_passable(team: int, p: Vector2, max_r := 40.0) -> Vector2:
	var q := clamp_pos(p)
	var wl := walk_layer(team)
	var c := snap_cell(wl, q, max_r)
	if c < 0:
		return q
	return q if cell_of(q) == c else cell_center(c)


func structure_at(p: Vector2) -> int:
	var c := cell_of(p)
	return struct_of[c] if c >= 0 else 0


func static_grid() -> PackedByteArray:
	var g := PackedByteArray()
	g.resize(w * h)
	for c in _static_cells:
		if _static_f[c] & F.STATIC:
			g[c] = 1
	for k: int in _deposits:
		var rec: PackedInt32Array = _deposits[k]
		for i in range(1, rec.size()):
			g[rec[i]] = 1
	return g


func speed_grid() -> PackedByteArray:
	return _spd.duplicate()


func stamp_building(b_h: int, team: int, center: Vector2, btype: int, rot_q: int) -> Rect2i:
	_sync_deposits()
	var r := NavApi.footprint(defs, btype, center, rot_q, origin)
	var cells := PackedInt32Array()
	for row in range(maxi(r.position.y, 0), mini(r.end.y, h)):
		for col in range(maxi(r.position.x, 0), mini(r.end.x, w)):
			cells.append(row * w + col)
	_add_stamp(b_h, team, btype, cells)
	return r


func stamp_link(b_h: int, team: int, a: Vector2, b: Vector2, btype: int) -> Rect2i:
	_sync_deposits()
	var cells := link_cells(a, b)
	_add_stamp(b_h, team, btype, cells)
	if cells.is_empty():
		return Rect2i()
	var lo := Vector2i(w, h)
	var hi := Vector2i(-1, -1)
	for c in cells:
		var v := Vector2i(c % w, c / w)
		lo = lo.min(v)
		hi = hi.max(v)
	return Rect2i(lo, hi - lo + Vector2i.ONE)


func unstamp(b_h: int) -> void:
	if not _stamps.has(b_h):
		return
	var rec: PackedInt32Array = _stamps[b_h]
	_stamps.erase(b_h)
	if rec[2] & F.STRUCT:
		_team_structs[rec[0]] -= 1
	version += 1
	for i in range(3, rec.size()):
		var c := rec[i]
		if _cnt[c] <= 1:
			_cnt[c] = 0
			struct_of[c] = 0
		else:
			var list: PackedInt32Array = _multi[c]
			var k := list.find(b_h)
			if k >= 0:
				list.remove_at(k)
			_cnt[c] -= 1
			struct_of[c] = list[0]
			if list.size() <= 1:
				_multi.erase(c)
			else:
				_multi[c] = list
		_refresh_cell(c)


## Клетки звена a→b (4-связная суперобложка, внутри карты)
func link_cells(a: Vector2, b: Vector2) -> PackedInt32Array:
	var raw := NavRaster.supercover4(a, b, origin, CELL)
	var out := PackedInt32Array()
	for k in range(0, raw.size(), 2):
		var col := raw[k]
		var row := raw[k + 1]
		if col >= 0 and row >= 0 and col < w and row < h:
			var c := row * w + col
			if out.is_empty() or out[out.size() - 1] != c:
				out.append(c)
	return out


# ================================================================= пути

func request(team: int, from: Vector2, to: Vector2, client: int, prio := 0) -> int:
	return paths.request(self, team, from, to, client, prio)


func service(tick: int) -> void:
	paths.service(self, tick)


func result(ticket: int) -> PathResult:
	return paths.result(ticket)


func release(ticket: int) -> void:
	paths.release(ticket)


func stale(r: PathResult) -> bool:
	return r != null and stale_sectors(r.sectors, r.issued_ver)


func find_now(team: int, from: Vector2, to: Vector2) -> PathResult:
	sync_for_paths()
	return paths.solve(self, team, from, to, false)


# ================================================================= расстановка и стены

func check_place(player: int, btype: int, center: Vector2, rot_q: int) -> int:
	return placement.check_place(self, player, btype, center, rot_q)


func place_cells(player: int, btype: int, center: Vector2, rot_q: int) -> PackedByteArray:
	return placement.place_cells(self, player, btype, center, rot_q)


func snap(btype: int, p: Vector2, rot_q: int) -> Vector2:
	return NavApi.snap_center(defs, btype, p, rot_q, origin)


func plan_wall(player: int, wtype: int, pts: PackedVector2Array) -> Dictionary:
	return walls.plan_wall(self, player, wtype, pts)


func snap_on_wall(player: int, btype: int, p: Vector2) -> Dictionary:
	return walls.snap_on_wall(self, player, btype, p)


func ring_slots(player: int, center: Vector2, btypes: PackedInt32Array) -> PackedVector2Array:
	return placement.ring_slots(self, player, center, btypes)


func checksum() -> int:
	var hsum := version * 1000003 + hash(flags)
	hsum = hsum * 31 + hash(team_of)
	hsum = hsum * 31 + hash(struct_of)
	hsum = hsum * 31 + paths.checksum()
	return hsum & 0x7FFFFFFFFFFF


# ================================================================= для PathService, Placement, WallTool

func walk_layer(t: int) -> NavRegions:
	_ensure_team(t)
	return _walk[t]


func breach_layer(t: int) -> NavRegions:
	_ensure_team(t)
	return _breach[t]


## Перед решением путей: жилы в сетку, перемечивание графа входов всех команд (только из
## симуляции). Слои breach перемечиваются лениво — при первом запросе компоненты.
func sync_for_paths() -> void:
	_sync_deposits()
	for t in _walk.size():
		_walk[t].flush()


func enemy_structs(t: int) -> bool:
	var own := _team_structs[t] if t >= 0 and t < MAX_TEAMS else 0
	var all := 0
	for k in MAX_TEAMS:
		all += _team_structs[k]
	return all - own > 0


func is_enemy_struct(t: int, c: int) -> bool:
	return flags[c] & F.STRUCT != 0 and team_of[c] != t


func struct_at_cell(c: int) -> int:
	return struct_of[c]


func clamp_pos(p: Vector2) -> Vector2:
	var lo := origin + Vector2(0.01, 0.01)
	var hi := origin + Vector2(w, h) * CELL - Vector2(0.01, 0.01)
	return p.clamp(lo, hi)


## Ближайшая к p открытая клетка слоя (не дальше max_r), −1 — нет. Ничьи — меньший индекс
func snap_cell(layer: NavRegions, p: Vector2, max_r: float) -> int:
	var c := cell_of(p)
	if c < 0:
		return -1
	var solid := layer.solid
	if solid[c] == 0:
		return c
	var cx := c % w
	var cy := c / w
	var kmax := ceili(max_r / CELL)
	var best := -1
	var bd := max_r * max_r
	for k in range(1, kmax + 1):
		var lb := (k - 0.5) * CELL
		if best >= 0 and lb * lb > bd:
			break
		for dy in range(-k, k + 1):
			var y := cy + dy
			if y < 0 or y >= h:
				continue
			var step := 1 if (dy == -k or dy == k) else 2 * k
			var dx := -k
			while dx <= k:
				var x := cx + dx
				if x >= 0 and x < w:
					var cc := y * w + x
					if solid[cc] == 0:
						var d := p.distance_squared_to(origin + Vector2(x + 0.5, y + 0.5) * CELL)
						if d < bd or (d == bd and cc < best):
							bd = d
							best = cc
				dx += step
	return best


## Прямая видимость центр→центр: все клетки открыты и не тяжелее концов (на углах — обе соседние).
## Сначала — по секторам: если линия идёт только через чистые секторы (без закрытых и тяжёлых
## клеток), клетки не проверяются.
func los(layer: NavRegions, c0: int, c1: int) -> bool:
	var code := layer.code
	var k0 := code[c0]
	var k1 := code[c1]
	if k0 == 255 or k1 == 255:
		return false
	var wmax := maxi(k0, k1)
	var x0 := c0 % w
	var y0 := c0 / w
	var dx := c1 % w - x0
	var dy := c1 / w - y0
	if _sectors_clean(layer, x0, y0, x0 + dx, y0 + dy):
		return true
	var sx := 1 if dx > 0 else -1
	var syw := w if dy > 0 else -w
	var ax := absi(dx)
	var ay := absi(dy)
	var ix := 0
	var iy := 0
	var ex := ay                 # (1 + 2·ix)·ay
	var ez := ax                 # (1 + 2·iy)·ax
	var c := c0
	while ix < ax or iy < ay:
		if ex == ez:
			if code[c + sx] > wmax or code[c + syw] > wmax:
				return false
			c += sx + syw
			ix += 1
			iy += 1
			ex += 2 * ay
			ez += 2 * ax
		elif ex < ez:
			c += sx
			ix += 1
			ex += 2 * ay
		else:
			c += syw
			iy += 1
			ez += 2 * ax
		if code[c] > wmax:
			return false
	return true


## Линия между центрами клеток проходит только через чистые секторы слоя (на углах — оба соседа)
func _sectors_clean(layer: NavRegions, x0: int, y0: int, x1: int, y1: int) -> bool:
	var busy := layer.sec_busy
	var ss := SECTOR * 2                       # в полуклетках
	var px := 2 * x0 + 1
	var pz := 2 * y0 + 1
	var qx := 2 * x1 + 1
	var qz := 2 * y1 + 1
	var cx := px / ss
	var cz := pz / ss
	var ex := qx / ss
	var ez := qz / ss
	if busy[cz * _sw + cx] != 0:
		return false
	var dx := qx - px
	var dz := qz - pz
	var sx := 1 if dx > 0 else (-1 if dx < 0 else 0)
	var sz := 1 if dz > 0 else (-1 if dz < 0 else 0)
	var adx := absi(dx)
	var adz := absi(dz)
	var bx := (cx + 1) * ss if sx > 0 else cx * ss
	var bz := (cz + 1) * ss if sz > 0 else cz * ss
	while cx != ex or cz != ez:
		var lhs := absi(bx - px) * adz
		var rhs := absi(bz - pz) * adx
		if sx != 0 and sz != 0 and lhs == rhs:
			if busy[cz * _sw + cx + sx] != 0 or busy[(cz + sz) * _sw + cx] != 0:
				return false
			cx += sx
			cz += sz
			bx += sx * ss
			bz += sz * ss
		elif sz == 0 or (sx != 0 and lhs < rhs):
			cx += sx
			bx += sx * ss
		else:
			cz += sz
			bz += sz * ss
		if busy[cz * _sw + cx] != 0:
			return false
	return true


## Стоимость пути по клеткам (как у A*: шаг × вес клетки входа)
func cells_cost(layer: NavRegions, cells: PackedInt32Array, breach: bool, t: int) -> float:
	var cost := 0.0
	for i in range(1, cells.size()):
		var a := cells[i - 1]
		var b := cells[i]
		var dx := a % w - b % w
		var dy := a / w - b / w
		var wt := 1.0
		if breach and is_enemy_struct(t, b):
			wt = W_BREACH
		elif _wcode[b] == 2:
			wt = W_WATER
		elif _wcode[b] == 1:
			wt = W_SOFT
		cost += sqrt(float(dx * dx + dy * dy)) * wt   # соседние: 1 или √2; прямая видимость — длина
	return cost


## Октильная оценка в клетках между двумя точками (бюджет путей)
func octile_cells(a: Vector2, b: Vector2) -> int:
	var ca := cell_of(clamp_pos(a))
	var cb := cell_of(clamp_pos(b))
	return octile_cell(ca, cb) + 1


func octile_cell(ca: int, cb: int) -> int:
	var dx := absi(ca % w - cb % w)
	var dy := absi(ca / w - cb / w)
	return maxi(dx, dy) + (mini(dx, dy) * 414) / 1000


func stale_sectors(sectors: PackedInt32Array, ver: int) -> bool:
	for s in sectors:
		if _sector_ver[s] > ver:
			return true
	return false


func sectors_of(pts: PackedVector2Array) -> PackedInt32Array:
	return NavRaster.sectors_of(pts, origin, CELL, SECTOR, w, h)


## Команда игрока (по таблице игроков ECON; без неё — номер игрока)
func team_of_player(p: int) -> int:
	if econ != null and econ.players != null and p >= 0 and p < econ.players.count:
		return econ.players.team[p]
	return p


## Есть ли живой узел (дерево или жила) в клетке c — для расстановки (индекс — sync_node_index)
func node_in_cell(c: int) -> bool:
	if _n_head.is_empty() or econ == null:
		return false
	var N := econ.nodes
	var ntype := N.ntype
	var amount := N.amount_milli
	var n := _n_head[c]
	while n >= 0:
		if n < N.hw and ntype[n] >= 0 and amount[n] != 0:
			return true
		n = _n_next[n]
	return false


func stamp_count() -> int:
	return _stamps.size()


## Описатели штампов клетки c (первый — struct_of[c]); пусто — свободна
func stamps_at(c: int) -> PackedInt32Array:
	var bh := struct_of[c]
	if bh == 0:
		return PackedInt32Array()
	if _cnt[c] <= 1:
		return PackedInt32Array([bh])
	return _multi.get(c, PackedInt32Array([bh]))


## Запись штампа: [команда, тип, флаги, клетки…] (пусто — нет)
func stamp_of(b_h: int) -> PackedInt32Array:
	return _stamps.get(b_h, PackedInt32Array())


# ================================================================= внутреннее

func _ensure_team(t: int) -> void:
	t = clampi(t, 0, MAX_TEAMS - 1)
	while _walk.size() <= t:
		var k := _walk.size()
		var wl := NavRegions.new()
		wl.setup(w, h, true)
		var bl := NavRegions.new()
		bl.setup(w, h, false)
		_walk.append(wl)
		_breach.append(bl)
		for c in _static_cells:
			_apply_team(k, c)
		for b_h: int in _stamps:
			var rec: PackedInt32Array = _stamps[b_h]
			for i in range(3, rec.size()):
				_apply_team(k, rec[i])
		for n: int in _deposits:
			var dr: PackedInt32Array = _deposits[n]
			for i in range(1, dr.size()):
				_apply_team(k, dr[i])


## Флаги штампа по типу постройки
func _dyn_flags(btype: int) -> int:
	if btype < 0 or defs == null or btype >= defs.b_kind.size():
		return F.STRUCT
	match defs.b_kind[btype]:
		Defs.BKind.WALL:
			return F.STRUCT | F.WALL
		Defs.BKind.GATE:
			return F.STRUCT | F.GATE
		Defs.BKind.FIELD:
			return F.SOFT
	if defs.b_flags[btype] & Defs.BF_WALKABLE:
		return 0
	return F.STRUCT


func _add_stamp(b_h: int, team: int, btype: int, cells: PackedInt32Array) -> void:
	if _stamps.has(b_h):
		unstamp(b_h)
	team = clampi(team, 0, MAX_TEAMS - 1)
	_ensure_team(team)
	var dyn := _dyn_flags(btype)
	var rec := PackedInt32Array([team, btype, dyn])
	rec.append_array(cells)
	_stamps[b_h] = rec
	if dyn & F.STRUCT:
		_team_structs[team] += 1
	version += 1
	for c in cells:
		if _cnt[c] == 0:
			struct_of[c] = b_h
			_cnt[c] = 1
		else:
			var list: PackedInt32Array = _multi.get(c, PackedInt32Array([struct_of[c]]))
			list.append(b_h)
			_multi[c] = list
			_cnt[c] = mini(_cnt[c] + 1, 255)
		_refresh_cell(c)


## Пересчёт флагов клетки по рельефу, жилам и штампам; правка слоёв всех команд
func _refresh_cell(c: int) -> void:
	var f := _static_f[c]
	if _node_cnt[c] > 0:
		f |= F.NODE
	var bh := struct_of[c]
	if bh != 0:
		if _cnt[c] <= 1:
			f |= (_stamps[bh] as PackedInt32Array)[2]
		else:
			var wall := false                  # ворота поверх звена стены — клетка остаётся стеной
			for hh in (_multi[c] as PackedInt32Array):
				var df: int = (_stamps[hh] as PackedInt32Array)[2]
				f |= df
				wall = wall or (df & F.STRUCT != 0 and df & F.GATE == 0)
			if wall:
				f &= ~F.GATE
		team_of[c] = (_stamps[bh] as PackedInt32Array)[0]
	else:
		team_of[c] = NO_TEAM
	flags[c] = f
	_wcode[c] = 2 if f & F.WATER else (1 if f & F.SOFT else 0)
	for t in _walk.size():
		_apply_team(t, c)
	var s := ((c / w) / SECTOR) * _sw + (c % w) / SECTOR
	_sector_ver[s] = version


func _apply_team(t: int, c: int) -> void:
	var f := flags[c]
	var blocked := f & (F.STATIC | F.NODE) != 0
	var st := f & F.STRUCT != 0
	var own := team_of[c] == t
	var gate := f & F.GATE != 0
	var wc := _wcode[c]
	var wt := W_WATER if wc == 2 else (W_SOFT if wc == 1 else 1.0)
	_walk[t].set_cell(c, blocked or (st and not (gate and own)), wt, wc)
	if st and not own:
		_breach[t].set_cell(c, false, W_BREACH, 3)
	else:
		_breach[t].set_cell(c, blocked or (st and own and not gate), wt, wc)


## Статика по рельефу: крутизна и вода (один раз при setup)
func _build_static() -> void:
	var hs := Terrain.heights()
	var tn := Terrain.size()
	var sp := Terrain.spacing()
	var to := Terrain.origin()
	var wl := Terrain.water_level()
	var k := roundi(CELL / sp)
	var direct := is_equal_approx(k * sp, CELL) and is_equal_approx(fmod(origin.x - to.x, sp), 0.0) \
		and is_equal_approx(fmod(origin.y - to.y, sp), 0.0)
	var i_off := roundi((origin.x - to.x) / sp)
	var j_off := roundi((origin.y - to.y) / sp)
	_static_cells.clear()
	for cy in h:
		for cx in w:
			var h00: float
			var h10: float
			var h01: float
			var h11: float
			var hc: float
			var i0 := i_off + cx * k
			var j0 := j_off + cy * k
			if direct and i0 >= 0 and j0 >= 0 and i0 + k < tn and j0 + k < tn:
				h00 = hs[j0 * tn + i0]
				h10 = hs[j0 * tn + i0 + k]
				h01 = hs[(j0 + k) * tn + i0]
				h11 = hs[(j0 + k) * tn + i0 + k]
				hc = hs[(j0 + k / 2) * tn + i0 + k / 2] if k % 2 == 0 else (h00 + h10 + h01 + h11) * 0.25
			else:
				var x0 := origin.x + cx * CELL
				var z0 := origin.y + cy * CELL
				h00 = Terrain.height_at(x0, z0)
				h10 = Terrain.height_at(x0 + CELL, z0)
				h01 = Terrain.height_at(x0, z0 + CELL)
				h11 = Terrain.height_at(x0 + CELL, z0 + CELL)
				hc = Terrain.height_at(x0 + CELL * 0.5, z0 + CELL * 0.5)
			var gx := ((h10 + h11) - (h00 + h01)) * 0.5 / CELL
			var gz := ((h01 + h11) - (h00 + h10)) * 0.5 / CELL
			var f := 0
			if gx * gx + gz * gz > MAX_SLOPE * MAX_SLOPE:
				f |= F.STATIC
			var depth := wl - hc
			if depth > WET:
				f |= F.WATER
				if depth > DEEP_WATER:
					f |= F.STATIC
				else:
					f |= F.FORD
			if f != 0:
				var c := cy * w + cx
				_static_f[c] = f
				_static_cells.append(c)
				if f & F.WATER:
					_spd[c] = SPD_WATER


## Ядра жил (blocks_cells > 0) из таблицы узлов ECON в сетку; только из симуляции
func _sync_deposits() -> void:
	if econ == null or econ.nodes == null or defs == null:
		return
	var N := econ.nodes
	var hv := Vector2i(hash(N.gen), hash(N.ntype))
	if hv == _dep_hash:
		return
	_dep_hash = hv
	var gen := N.gen
	var ntype := N.ntype
	var nx := N.x
	var nz := N.z
	# снятые и переназначенные слоты
	var keys := PackedInt32Array(_deposits.keys())
	keys.sort()
	for n in keys:
		var rec: PackedInt32Array = _deposits[n]
		if n >= N.hw or ntype[n] < 0 or gen[n] != rec[0]:
			_deposits.erase(n)
			version += 1
			for i in range(1, rec.size()):
				_node_cnt[rec[i]] -= 1
				_refresh_cell(rec[i])
	for n in N.hw:
		var nt := ntype[n]
		if nt < 0 or nt >= defs.n_blocks_cells.size() or defs.n_blocks_cells[nt] <= 0 or _deposits.has(n):
			continue
		var k := defs.n_blocks_cells[nt]
		var c0 := roundi((nx[n] - origin.x) / CELL - k * 0.5)
		var r0 := roundi((nz[n] - origin.y) / CELL - k * 0.5)
		var rec := PackedInt32Array([gen[n]])
		for row in range(maxi(r0, 0), mini(r0 + k, h)):
			for col in range(maxi(c0, 0), mini(c0 + k, w)):
				rec.append(row * w + col)
		_deposits[n] = rec
		version += 1
		for i in range(1, rec.size()):
			_node_cnt[rec[i]] = mini(_node_cnt[rec[i]] + 1, 255)
			_refresh_cell(rec[i])


## Индекс узлов по клеткам (списки через _n_next); перестраивается при смене слотов.
## Состояние навигации не меняет — зовут в начале каждого запроса расстановки.
func sync_node_index() -> void:
	if econ == null or econ.nodes == null:
		return
	var N := econ.nodes
	var hv := Vector2i(hash(N.gen), hash(N.ntype))
	if hv == _n_hash and not _n_head.is_empty():
		return
	_n_hash = hv
	_n_head.resize(w * h)
	_n_head.fill(-1)
	_n_next.resize(N.hw)
	_n_next.fill(-1)
	var ntype := N.ntype
	var nx := N.x
	var nz := N.z
	for n in range(N.hw - 1, -1, -1):
		if ntype[n] < 0:
			continue
		var c := cell_of(Vector2(nx[n], nz[n]))
		if c < 0:
			continue
		_n_next[n] = _n_head[c]
		_n_head[c] = n
