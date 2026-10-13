extends SceneTree
## Навигация «Города» (ARCHITECTURE §9, §15 NAV): сетка, слои команд, ворота (и через stamp_building),
## пролом (не через статику), коридоры, суперобложка стен, связность по месту против полного пересчёта,
## устаревание путей (и на углу секторов), прямая видимость у воды, кэш, бюджет и детерминизм службы
## путей, неверные команды и потерянный EconApi, память 400².
##   godot --headless --path ordo --script res://tests/test_nav.gd
## Время: «проц.» — процессорное время потока (/proc/thread-self/schedstat; машину делят другие
## агенты, часы врут), «часы» — лучший из нескольких прогонов.
## Статические помощники (make, wall, cpu_us…) берут и test_placement, test_wall_tool.

const MAP_400 := {"size": 801, "spacing": 2.0, "origin": [-800.0, -800.0], "flat": true, "teams": 2}
const MAP_64 := {"size": 129, "spacing": 2.0, "origin": [-128.0, -128.0], "flat": true, "teams": 2}
const MAP_128 := {"size": 257, "spacing": 2.0, "origin": [-256.0, -256.0], "flat": true, "teams": 2}

static var _cpu_ok := true


func _init() -> void:
	_test_raster()
	_test_terrain()
	_test_gates()
	_test_gate_stamp_building()
	_test_breach_static()
	_test_components_fuzz()
	_test_enclosed_400()
	_test_detour_400()
	_test_breach_ratio()
	_test_random_walls()
	_test_stale()
	_test_los_water()
	_test_cache()
	_test_budget()
	_test_bad_inputs()
	_test_memory()
	SimHarness.finish(self)


# ================================================================= помощники (и для других тестов NAV)

## Связка: NavGrid + EconStub + CombatPortStub; игроки 0 (Коканд, команда 0) и 1 (кыпчаки, команда 1)
static func make(info: Dictionary = {}, players := true) -> Dictionary:
	var defs := Defs.shared()
	var rules := defs.rules_of(&"GOROD")
	var events := SimEvents.new()
	var nav := NavGrid.new()
	var port := CombatPortStub.new()
	var econ := EconStub.new()
	nav.setup(info if not info.is_empty() else Terrain.info(), defs, econ, port)
	port.setup(defs, nav, {"teams": 2, "homes": PackedVector2Array(), "corpse_s": -1,
		"bounds_origin": nav.origin, "bounds_size": Vector2(nav.w, nav.h) * NavApi.CELL})
	econ.setup(defs, rules, port, nav, events, 1)
	if players:
		econ.add_player(0, &"kokand", PlayerTable.Ctrl.HUMAN)
		econ.add_player(1, &"kipchak", PlayerTable.Ctrl.AI)
		for p in 2:
			for r in defs.R:
				econ.players.res[p * defs.R + r] = 1000000
	return {"defs": defs, "nav": nav, "econ": econ, "port": port, "events": events}


## Стена игрока по ломаной (как сделает ECON): звенья в BuildingTable + stamp_link. Описатели звеньев
static func wall(k: Dictionary, player: int, wid: StringName, pts: PackedVector2Array) -> PackedInt32Array:
	var nav: NavGrid = k["nav"]
	var econ: EconStub = k["econ"]
	var defs: Defs = k["defs"]
	var wt := defs.building(wid)
	var plan := nav.plan_wall(player, wt, pts)
	var out := PackedInt32Array()
	var B := econ.buildings
	var team := econ.players.team[player]
	var ca: PackedVector2Array = plan["a"]
	var cb: PackedVector2Array = plan["b"]
	var centers: PackedVector2Array = plan["centers"]
	var rots: PackedFloat32Array = plan["rots"]
	for i in centers.size():
		var b := B.alloc(BuildingTable.State.ACTIVE)
		B.btype[b] = wt
		B.owner[b] = player
		B.team[b] = team
		B.x[b] = centers[i].x
		B.z[b] = centers[i].y
		B.rot[b] = rots[i]
		B.ax[b] = ca[i].x
		B.az[b] = ca[i].y
		B.bx[b] = cb[i].x
		B.bz[b] = cb[i].y
		B.chain[b] = 1
		var h := B.handle(b)
		nav.stamp_link(h, team, ca[i], cb[i], wt)
		out.append(h)
	return out


## Ворота на стене (snap_on_wall → снять звенья → stamp_link ворот). Описатель ворот или 0
static func gate(k: Dictionary, player: int, gid: StringName, at: Vector2) -> int:
	var nav: NavGrid = k["nav"]
	var econ: EconStub = k["econ"]
	var defs: Defs = k["defs"]
	var gt := defs.building(gid)
	var s := nav.snap_on_wall(player, gt, at)
	if int(s["why"]) != NavApi.Why.OK:
		return 0
	var B := econ.buildings
	for rh in (s["removes"] as PackedInt32Array):
		nav.unstamp(rh)
		B.release(B.slot(rh))
	var b := B.alloc(BuildingTable.State.ACTIVE)
	B.btype[b] = gt
	B.owner[b] = player
	B.team[b] = econ.players.team[player]
	var c: Vector2 = s["center"]
	B.x[b] = c.x
	B.z[b] = c.y
	B.rot[b] = s["rot"]
	var a: Vector2 = s["a"]
	var e: Vector2 = s["b"]
	B.ax[b] = a.x
	B.az[b] = a.y
	B.bx[b] = e.x
	B.bz[b] = e.y
	var h := B.handle(b)
	nav.stamp_link(h, B.team[b], a, e, gt)
	return h


## Многоугольник (замкнутый) с центром c и радиусом r, n вершин
static func ring_pts(c: Vector2, r: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


## Процессорное время потока, мкс (или часы)
static func cpu_us() -> int:
	if _cpu_ok:
		var f := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
		if f:
			return int(f.get_line().split(" ")[0]) / 1000
		_cpu_ok = false
	return Time.get_ticks_usec()


## Часы потока без ожидания процессора, мкс: часы минус run_delay из /proc/thread-self/schedstat
## (ядро дописывает его при каждом возвращении потока на процессор). Процессорное время там же
## обновляется лишь на переключениях (шаг 1–4 мс) — для отдельного такта оно не годится, а это —
## точно до мкс и не растёт, пока поток ждёт в очереди (машину делят другие агенты)
static func net_us() -> int:
	if _cpu_ok:
		var f := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
		if f:
			return Time.get_ticks_usec() - int(f.get_line().split(" ")[1]) / 1000
		_cpu_ok = false
	return Time.get_ticks_usec()


## Лучшее время (часы, мс) из reps прогонов f
static func best_ms(f: Callable, reps: int) -> float:
	var best := INF
	for i in reps:
		var t0 := Time.get_ticks_usec()
		f.call()
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
	return best


## Клетка 4-связной заливкой из a по открытым клеткам слоя достигает b?
static func flood_reaches(nav: NavGrid, layer: NavRegions, a: int, b: int) -> bool:
	var seen := PackedByteArray()
	seen.resize(nav.w * nav.h)
	var st := PackedInt32Array([a])
	seen[a] = 1
	var solid := layer.solid
	while not st.is_empty():
		var c: int = st[st.size() - 1]
		st.resize(st.size() - 1)
		if c == b:
			return true
		var x := c % nav.w
		for nb in [c - 1 if x > 0 else -1, c + 1 if x < nav.w - 1 else -1, c - nav.w, c + nav.w]:
			if nb >= 0 and nb < nav.w * nav.h and seen[nb] == 0 and solid[nb] == 0:
				seen[nb] = 1
				st.append(nb)
	return false


## Проходит ли ломаная (start + pts) через клетку c
static func path_cells(nav: NavGrid, start: Vector2, pts: PackedVector2Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var poly := PackedVector2Array([start])
	poly.append_array(pts)
	for i in range(1, poly.size()):
		out.append_array(nav.link_cells(poly[i - 1], poly[i]))
	return out


## Разбиение областей слоя по компонентам (правки по месту) — то же, что у полного пересчёта
## (_components)? И счёт областей тот же. Состояние слоя после сравнения восстанавливается — цепочка
## правок по месту продолжается
static func comps_match_full(L: NavRegions) -> bool:
	var ns := L.sw * L.sh
	var inc := PackedInt32Array()
	for s in ns:
		for l in L.reg_n[s]:
			inc.append(L._cfind(L.rcomp[s * NavRegions.RMAX + l]))
	var rc := L.rcomp.duplicate()
	var cp := L._cpar.duplicate()
	var rg := L._regions
	var fp := L.full_passes
	L._components()
	var ok := L._regions == rg
	var f2i := {}
	var i2f := {}
	var j := 0
	for s in ns:
		for l in L.reg_n[s]:
			var a := inc[j]
			var b := L.rcomp[s * NavRegions.RMAX + l]
			j += 1
			if int(f2i.get(b, a)) != a or int(i2f.get(a, b)) != b:
				ok = false
			f2i[b] = a
			i2f[a] = b
	L.rcomp = rc
	L._cpar = cp
	L._regions = rg
	L.full_passes = fp
	return ok


## Слой, построенный заново по тем же закрытым клеткам: метки, входы и граф входов те же?
static func graph_matches_fresh(L: NavRegions) -> bool:
	var F := NavRegions.new()
	F.setup(L.w, L.h, L.portals)
	for c in L.w * L.h:
		if L.solid[c] != 0:
			F.set_cell(c, true, 1.0, 0)
	F.flush()
	if F.lab != L.lab or F.reg_n != L.reg_n:
		return false
	for s in L.sw * L.sh:
		if F._ent_e[s] != L._ent_e[s] or F._ent_s[s] != L._ent_s[s]:
			return false
	if not L.portals:
		return true
	var ids_l := L.graph.get_point_ids()
	var ids_f := F.graph.get_point_ids()
	ids_l.sort()
	ids_f.sort()
	if ids_l != ids_f:
		return false
	for id in ids_l:
		var a := L.graph.get_point_connections(id)
		var b := F.graph.get_point_connections(id)
		a.sort()
		b.sort()
		if a != b:
			return false
	return true


# ================================================================= тесты

## Суперобложка: начало и конец, 4-связность, покрытие всех точек отрезка
func _test_raster() -> void:
	print("[растр: 4-связная суперобложка]")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var bad_ends := 0
	var bad_conn := 0
	var bad_cover := 0
	for i in 2000:
		var a := Vector2(rng.randf_range(-50, 50), rng.randf_range(-50, 50))
		var b := Vector2(rng.randf_range(-50, 50), rng.randf_range(-50, 50))
		if i % 7 == 0:
			b = Vector2(a.x + rng.randi_range(-8, 8) * 4.0, a.y + rng.randi_range(-8, 8) * 4.0)   # углы клеток
		var cells := NavRaster.supercover4(a, b, Vector2.ZERO, 4.0)
		var set := {}
		for k in range(0, cells.size(), 2):
			set[Vector2i(cells[k], cells[k + 1])] = true
		# концы — в целых сантиметрах, как в NavRaster
		var c0 := Vector2i(floori(roundi(a.x * 100.0) / 400.0), floori(roundi(a.y * 100.0) / 400.0))
		var c1 := Vector2i(floori(roundi(b.x * 100.0) / 400.0), floori(roundi(b.y * 100.0) / 400.0))
		if Vector2i(cells[0], cells[1]) != c0 or Vector2i(cells[cells.size() - 2], cells[cells.size() - 1]) != c1:
			bad_ends += 1
		for k in range(2, cells.size(), 2):
			if absi(cells[k] - cells[k - 2]) + absi(cells[k + 1] - cells[k - 1]) != 1:
				bad_conn += 1
		for s in 400:
			var p := a.lerp(b, (s + 0.5) / 400.0)
			if not set.has(Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))):
				bad_cover += 1
	SimHarness.check(bad_ends == 0 and bad_conn == 0 and bad_cover == 0,
		"2000 отрезков: концы %d, разрывы %d, непокрытые точки %d" % [bad_ends, bad_conn, bad_cover])


## Рельеф карты: река непроходима, брод проходим; статика и скорость для ядра
func _test_terrain() -> void:
	print("[рельеф: река, брод, крутизна]")
	var t0 := cpu_us()
	var k := make()
	var nav: NavGrid = k["nav"]
	print("  setup 256² с рельефом: %.0f мс проц." % ((cpu_us() - t0) / 1000.0))
	var fd: Array = Terrain.info().get("ford", [20.0, -157.39])
	var ford := Vector2(float(fd[0]), float(fd[1]))
	var fc := nav.cell_of(ford)
	SimHarness.check(nav.flags[fc] & NavApi.F.FORD != 0 and nav.passable(0, fc), "брод — мелкая вода, проходим")
	var deep := nav.cell_of(Vector2(160, -170.5))
	SimHarness.check(nav.flags[deep] & NavApi.F.STATIC != 0 and nav.flags[deep] & NavApi.F.WATER != 0 \
		and not nav.passable(0, deep), "глубокая вода у тўғона — непроходима")
	var sg := nav.static_grid()
	var spd := nav.speed_grid()
	SimHarness.check(sg[deep] == 1 and sg[nav.cell_of(Vector2(90, 0))] == 0 and spd[fc] == NavGrid.SPD_WATER \
		and spd[nav.cell_of(Vector2(90, 0))] == 16, "static_grid и speed_grid (вода ×0,55 → 9)")
	var north := Vector2(100, -100)
	var south := Vector2(100, -260)
	SimHarness.check(nav.reachable(0, north, south), "через реку — достижимо (брод)")
	var r := nav.find_now(0, north, south)
	var cross := false
	var poly := PackedVector2Array([north])
	poly.append_array(r.pts)
	for i in range(1, poly.size()):
		var a := poly[i - 1]
		var b := poly[i]
		for s in 64:
			var p := a.lerp(b, s / 64.0)
			if Terrain.water_depth(p.x, p.y) > 0.3 and absf(p.x - ford.x) < 24.0:
				cross = true
	SimHarness.check(not r.no_route and r.breach_b == 0 and cross, "путь через реку идёт бродом: %s" % str(r.pts))
	var on_slope := -1
	for c in nav.w * nav.h:
		if nav.flags[c] == NavApi.F.STATIC:
			on_slope = c
			break
	SimHarness.check(on_slope >= 0 and not nav.passable(0, on_slope), "крутые склоны — STATIC, непроходимы")


## Свои ворота пропускают, чужие — нет (пролом через звено или ворота)
func _test_gates() -> void:
	print("[ворота: свои проходят, враг ломает]")
	var k := make()
	var nav: NavGrid = k["nav"]
	var defs: Defs = k["defs"]
	var c := SimHarness.flat_spot()
	var sq := PackedVector2Array([c + Vector2(-24, -24), c + Vector2(24, -24), c + Vector2(24, 24),
		c + Vector2(-24, 24), c + Vector2(-24, -24)])
	var links := wall(k, 0, &"devor", sq)
	var inside := c
	var outside := c + Vector2(0, 80)
	SimHarness.check(not nav.reachable(0, outside, inside) and not nav.reachable(1, outside, inside),
		"глухое кольцо (%d звеньев): внутрь не пройти никому" % links.size())
	var g := gate(k, 0, &"darvoza", c + Vector2(0, 24))
	SimHarness.check(g != 0, "Дарвоза встала на стену (звенья под ней сняты)")
	SimHarness.check(nav.reachable(0, outside, inside), "свои ворота — проход для своих")
	var r0 := nav.find_now(0, outside, inside)
	var through := false
	for cc in path_cells(nav, outside, r0.pts):
		through = through or nav.struct_of[cc] == g
	SimHarness.check(not r0.no_route and r0.breach_b == 0 and through, "путь своих — через ворота")
	SimHarness.check(not nav.reachable(1, outside, inside), "чужие ворота — закрыты для врага")
	var r1 := nav.find_now(1, outside, inside)
	var bt := -1
	if r1.breach_b != 0:
		bt = nav.stamp_of(r1.breach_b)[1]
	SimHarness.check(r1.breach_b != 0 and r1.breach_wp >= 0 and r1.breach_wp < r1.pts.size() \
		and (bt == defs.building(&"devor") or bt == defs.building(&"darvoza")),
		"враг: пролом через %s, точка перед ним %d" % [defs.b_ids[bt] if bt >= 0 else "—", r1.breach_wp])
	# свои — вокруг своего же кольца без ворот: нет прохода (no_route), а не пролом
	var k2 := make()
	var nav2: NavGrid = k2["nav"]
	wall(k2, 0, &"devor", sq)
	var r2 := nav2.find_now(0, outside, inside)
	SimHarness.check(r2.no_route and r2.breach_b == 0 and r2.pts.size() > 0,
		"своё кольцо без ворот: no_route, путь — к ближайшей точке (%s)" % str(r2.pts[r2.pts.size() - 1]))


## Цель в кольце стены на 400²: пролом — через звено, ≤ 1,5 мс
func _test_enclosed_400() -> void:
	print("[400²: цель в кольце — пролом]")
	var k := make(MAP_400)
	var nav: NavGrid = k["nav"]
	var defs: Defs = k["defs"]
	var goal := Vector2(100, 100)
	var links := wall(k, 0, &"devor", ring_pts(goal, 60.0, 12))
	nav.sync_for_paths()
	var from := Vector2(-600, -600)
	var r := nav.find_now(1, from, goal)
	var bt := nav.stamp_of(r.breach_b)[1] if r.breach_b != 0 else -1
	SimHarness.check(r.breach_b != 0 and links.has(r.breach_b) and defs.b_kind[bt] == Defs.BKind.WALL,
		"пролом через звено стены (%d звеньев)" % links.size())
	nav.find_now(1, from, goal)
	var ms := best_ms(func() -> void: nav.find_now(1, from, goal), 7)
	var t0 := cpu_us()
	for i in 20:
		nav.find_now(1, from, goal)
	var cpu := (cpu_us() - t0) / 20000.0
	SimHarness.check(ms <= 1.5 or cpu <= 1.5, "пролом на 400²: %.3f мс часы (лучший), %.3f мс проц. (среднее) ≤ 1,5" % [ms, cpu])


## Стена через всю карту 400² с воротами у края: обход найден, ≤ 3 мс
func _test_detour_400() -> void:
	print("[400²: стена через карту, ворота у края — обход]")
	var k := make(MAP_400)
	var nav: NavGrid = k["nav"]
	var t0 := cpu_us()
	wall(k, 0, &"devor", PackedVector2Array([Vector2(2, -799), Vector2(2, 799)]))
	var g := gate(k, 0, &"darvoza", Vector2(2, 700))
	nav.sync_for_paths()
	print("  стена 1600 м + ворота + перемечивание: %.1f мс проц." % ((cpu_us() - t0) / 1000.0))
	var a := Vector2(-40, 0)
	var b := Vector2(40, 0)
	var r := nav.find_now(0, a, b)
	var far := false
	for p in r.pts:
		far = far or p.y > 650.0
	SimHarness.check(g != 0 and not r.no_route and r.breach_b == 0 and far,
		"обход через ворота: %d точек, %.0f м" % [r.pts.size(), r.cost])
	var re := nav.find_now(1, a, b)
	SimHarness.check(re.breach_b != 0, "враг у той же стены — пролом")
	var ms := best_ms(func() -> void: nav.find_now(0, a, b), 7)
	t0 = cpu_us()
	for i in 20:
		nav.find_now(0, a, b)
	var cpu := (cpu_us() - t0) / 20000.0
	var wl := nav.walk_layer(0)
	var t1 := Time.get_ticks_usec()
	wl.astar.get_id_path(Vector2i(nav.cell_of(a) % nav.w, nav.cell_of(a) / nav.w), Vector2i(nav.cell_of(b) % nav.w, nav.cell_of(b) / nav.w))
	var direct := (Time.get_ticks_usec() - t1) / 1000.0
	SimHarness.check(ms <= 3.0 or cpu <= 3.0,
		"обход на 400²: %.3f мс часы (лучший), %.3f мс проц. ≤ 3 (A* без коридора: %.1f мс часы)" % [ms, cpu, direct])


## rules.breach_ratio: обход через дальнюю щель дороже ratio × октиль — враг ломает стену
func _test_breach_ratio() -> void:
	print("[breach_ratio: обход против пролома]")
	var k := make(MAP_400)
	var nav: NavGrid = k["nav"]
	wall(k, 0, &"devor", PackedVector2Array([Vector2(2, -799), Vector2(2, 600)]))    # щель у края
	nav.sync_for_paths()
	var a := Vector2(-40, 0)
	var b := Vector2(40, 0)
	var r0 := nav.find_now(1, a, b)
	nav.paths.breach_ratio = 1.5
	var r1 := nav.find_now(1, a, b)
	nav.paths.breach_ratio = 40.0
	var r2 := nav.find_now(1, a, b)
	SimHarness.check(r0.breach_b == 0 and not r0.no_route and r0.cost > 1000.0,
		"ratio 0 (выкл.): враг обходит через щель (%.0f м)" % r0.cost)
	SimHarness.check(r1.breach_b != 0 and r1.cost < 200.0, "ratio 1,5: обход в %.0f раз длиннее — пролом (%.0f м)" % [
		r0.cost / maxf(a.distance_to(b), 1.0), r1.cost])
	SimHarness.check(r2.breach_b == 0, "ratio 40: обход дешевле порога — без пролома")


## 1000 случайных диагональных стен поперёк карты: ни одной щели
func _test_random_walls() -> void:
	print("[1000 диагональных стен: без щелей]")
	var k := make(MAP_64)
	var nav: NavGrid = k["nav"]
	var econ: EconStub = k["econ"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var leaks := 0
	var flood_leaks := 0
	var floods := 0
	var breach_bad := 0
	var breaches := 0
	var lo := nav.origin.x + 0.1
	var hi := nav.origin.x + nav.w * NavApi.CELL - 0.1
	var t0 := cpu_us()
	for i in 1000:
		var za := rng.randf_range(lo + 20.0, hi - 20.0)
		var zb := rng.randf_range(lo + 20.0, hi - 20.0)
		var a := Vector2(lo, za)
		var b := Vector2(hi, zb)
		if i % 2 == 1:                                  # и поперёк, сверху вниз
			a = Vector2(za, lo)
			b = Vector2(zb, hi)
		var links := wall(k, 1, &"chep", PackedVector2Array([a, b]))
		# точки по обе стороны от середины линии
		var mid := (a + b) * 0.5
		var nrm := (b - a).normalized().orthogonal()
		var p1 := mid + nrm * 14.0
		var p2 := mid - nrm * 14.0
		if nav.reachable(0, p1, p2):
			leaks += 1
		if i % 10 == 0:
			floods += 1
			var wl := nav.walk_layer(0)
			var c1 := nav.snap_cell(wl, p1, 40.0)
			var c2 := nav.snap_cell(wl, p2, 40.0)
			if c1 >= 0 and c2 >= 0 and flood_reaches(nav, wl, c1, c2):
				flood_leaks += 1
		if i % 50 == 0:
			breaches += 1
			var r := nav.find_now(0, p1, p2)
			if r.breach_b == 0 or not links.has(r.breach_b):
				breach_bad += 1
		for h in links:
			nav.unstamp(h)
			econ.buildings.release(econ.buildings.slot(h))
	var ms := (cpu_us() - t0) / 1000.0
	SimHarness.check(leaks == 0 and flood_leaks == 0 and breach_bad == 0,
		"щелей по графу: %d; по заливке (%d проверок): %d; пролом не через звено (%d): %d — %.0f мс проц." % [
		leaks, floods, flood_leaks, breaches, breach_bad, ms])


## Штамп на пути делает путь устаревшим; штамп в стороне — нет
func _test_stale() -> void:
	print("[устаревание путей]")
	var k := make()
	var nav: NavGrid = k["nav"]
	var econ: EconStub = k["econ"]
	var defs: Defs = k["defs"]
	var a := Vector2(40, -20)
	var b := Vector2(150, 30)
	var r := nav.find_now(0, a, b)
	var far := nav.find_now(0, Vector2(-300, 250), Vector2(-250, 300))
	SimHarness.check(not nav.stale(r) and not nav.stale(far) and r.sectors.size() >= 2, "свежие пути не устарели")
	econ.spawn_building(0, defs.building(&"uy"), nav.snap(defs.building(&"uy"), (a + b) * 0.5, 0), 0)
	SimHarness.check(nav.stale(r), "дом на пути — путь устарел (секторы %s)" % str(r.sectors))
	SimHarness.check(not nav.stale(far), "путь в другом конце карты — не устарел")
	var r2 := nav.find_now(0, a, b)
	SimHarness.check(not nav.stale(r2) and r2.issued_ver == nav.version, "новый путь — свежий")
	# путь ровно через угол секторов: в sectors оба боковых сектора (заслон в угловой клетке заметен)
	var k3 := make(MAP_128)
	var n3: NavGrid = k3["nav"]
	var rc := n3.find_now(0, n3.cell_center(60 * n3.w + 60), n3.cell_center(68 * n3.w + 68))
	var corner := 64 * n3.w + 63
	var s_l := n3.walk_layer(0).sector_of(corner)
	var s_u := n3.walk_layer(0).sector_of(63 * n3.w + 64)
	SimHarness.check(rc.pts.size() == 1 and rc.sectors.has(s_l) and rc.sectors.has(s_u),
		"путь через угол секторов: оба боковых сектора в %s" % str(rc.sectors))
	n3.stamp_link(999999, 1, n3.cell_center(corner), n3.cell_center(corner), defs.building(&"uy"))
	SimHarness.check(n3.stale(rc), "заслон в угловой клетке — путь устарел")


## Бюджет: 64 запроса за 4 такта — одинаковый порядок и результаты в двух прогонах
func _test_budget() -> void:
	print("[бюджет и детерминизм службы путей]")
	for cells_budget in [8000, 1500]:
		var logs: Array[String] = []
		var sums: Array[int] = []
		var max_req := 0
		var over := 0
		for run in 2:
			var k := make()
			var nav: NavGrid = k["nav"]
			var econ: EconStub = k["econ"]
			var defs: Defs = k["defs"]
			nav.paths.cells_per_tick = cells_budget
			# немного города: дома, мельница, стена с воротами
			var c := SimHarness.flat_spot()
			for i in 6:
				econ.spawn_building(0, defs.building(&"uy"), nav.snap(defs.building(&"uy"), c + Vector2(-40 + i * 14, -30), 0), 0)
			wall(k, 1, &"chep", PackedVector2Array([c + Vector2(-60, 40), c + Vector2(60, 40)]))
			var rng := RandomNumberGenerator.new()
			rng.seed = 99
			var tickets := PackedInt32Array()
			var log := ""
			var tick := 0
			var served := {}
			while tick < 40:
				tick += 1
				if tick <= 4:
					for i in 16:
						var f := Vector2(rng.randf_range(-400, 400), rng.randf_range(-400, 400))
						var t := Vector2(rng.randf_range(-400, 400), rng.randf_range(-400, 400))
						if i % 4 == 0:
							t = f + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))
						tickets.append(nav.request(i % 2, f, t, i, 1 if i == 15 else 0))
				nav.service(tick)
				max_req = maxi(max_req, nav.paths.last_served)
				if nav.paths.last_served > 1 and nav.paths.last_cells > cells_budget:
					over += 1
				for tk in tickets:
					var res := nav.result(tk)
					if res != null and not served.has(tk):
						served[tk] = true
						log += "%d@%d:%s/%d/%d/%s;" % [tk, tick, str(res.pts), res.breach_b, res.breach_wp, res.no_route]
				if served.size() == tickets.size() and tick >= 4:
					break
			logs.append(log)
			sums.append(nav.checksum())
			SimHarness.check(served.size() == 64, "бюджет %d клеток: все 64 обслужены за %d тактов" % [cells_budget, tick])
		SimHarness.check(logs[0] == logs[1] and sums[0] == sums[1] and logs[0].length() > 100,
			"бюджет %d: порядок обслуживания и пути совпали в двух прогонах (сумма %d, журнал %d)" % [
			cells_budget, sums[0], hash(logs[0])])
		SimHarness.check(max_req <= 16 and over == 0, "за такт ≤ 16 запросов (макс. %d) и ≤ %d клеток" % [max_req, cells_budget])


## Память: 2 команды × (walk + breach) на 400² ≤ 96 МБ
func _test_memory() -> void:
	print("[память 400²]")
	var m0 := Performance.get_monitor(Performance.MEMORY_STATIC)
	var nav := NavGrid.new()
	var t0 := cpu_us()
	nav.setup(MAP_400, Defs.shared(), null, null)
	var setup_ms := (cpu_us() - t0) / 1000.0
	var m1 := Performance.get_monitor(Performance.MEMORY_STATIC)
	var mb := (m1 - m0) / 1048576.0
	SimHarness.check(mb <= 96.0, "NavGrid 400², 2 команды × (walk + breach): %.1f МБ ≤ 96 (setup %.0f мс проц.)" % [mb, setup_ms])


## Ворота, поставленные через stamp_building, на косой стене 30–60° (обе стороны: Дарвоза на пахсе,
## Дарбаза на чепе): NAV штампует их линией по стене — враг не проходит, свои проходят. Три способа:
## как EconStub/ECON (концов в BuildingTable нет — линия по своей стене у центра), с концами ax…bz
## из snap_on_wall, и ворота до снятия звеньев под ними
func _test_gate_stamp_building() -> void:
	print("[ворота через stamp_building на косой стене]")
	var n := 0
	var leaks := 0
	var own_block := 0
	var rect := 0
	var bad_snap := 0
	for ai in 13:
		for mode in 3:
			var p := (ai + mode) % 2
			var ang := deg_to_rad(30.0 + ai * 2.5)
			var dir := Vector2(cos(ang), sin(ang))
			var nrm := dir.orthogonal()
			var po := nrm * ((ai % 4) * 0.9)
			var k := make(MAP_128)
			var nav: NavGrid = k["nav"]
			var econ: EconStub = k["econ"]
			var d: Defs = k["defs"]
			var B := econ.buildings
			wall(k, p, &"devor" if p == 0 else &"chep", PackedVector2Array([po - dir * 420.0, po + dir * 420.0]))
			var gt := d.building(&"darvoza" if p == 0 else &"darbaza")
			var s := nav.snap_on_wall(p, gt, po + dir * (1.7 + 5.3 * mode))
			if int(s["why"]) != NavApi.Why.OK:
				bad_snap += 1
				continue
			var removes: PackedInt32Array = s["removes"]
			if mode != 2:
				for rh in removes:
					nav.unstamp(rh)
					B.release(B.slot(rh))
			var rq := posmod(roundi(float(s["rot"]) / (PI / 2.0)), 4)
			var center := nav.snap(gt, s["center"], rq)
			var h: int
			if mode == 1:
				var b := B.alloc(BuildingTable.State.ACTIVE)
				B.btype[b] = gt
				B.owner[b] = p
				B.team[b] = p
				B.x[b] = center.x
				B.z[b] = center.y
				B.rot_q[b] = rq
				var ga: Vector2 = s["a"]
				var gb: Vector2 = s["b"]
				B.ax[b] = ga.x
				B.az[b] = ga.y
				B.bx[b] = gb.x
				B.bz[b] = gb.y
				h = B.handle(b)
				nav.stamp_building(h, p, center, gt, rq)
			else:
				h = econ.spawn_building(p, gt, center, rq)
			if mode == 2:
				for rh in removes:
					nav.unstamp(rh)
					B.release(B.slot(rh))
			n += 1
			if nav.link_ends(h).size() != 2:
				rect += 1
			var p1 := po + nrm * 20.0
			var p2 := po - nrm * 20.0
			if nav.reachable(1 - p, p1, p2):
				leaks += 1
			if not nav.reachable(p, p1, p2):
				own_block += 1
	SimHarness.check(n == 39 and bad_snap == 0 and rect == 0,
		"ворота на стене (%d из 39) — штамп линией по стене, не прямоугольником (прямоугольников %d)" % [n, rect])
	SimHarness.check(leaks == 0 and own_block == 0,
		"30–60°, три способа: враг проходит %d раз, свои не проходят %d раз" % [leaks, own_block])


## Чужая постройка на статике (глубокая вода, обрыв): в слое breach её клетки остаются сплошными
## (§9.3) — пролома через непроходимое нет
func _test_breach_static() -> void:
	print("[пролом не открывает статику под чужой постройкой]")
	var k := make()
	var nav: NavGrid = k["nav"]
	var econ: EconStub = k["econ"]
	var d: Defs = k["defs"]
	var dam := d.building(&"togon")
	var at := nav.snap(dam, Vector2(160, -170.5), 0)
	var h := econ.spawn_building(0, dam, at, 0)
	var rec := nav.stamp_of(h)
	var on_static := 0
	var open := 0
	for i in range(3, rec.size()):
		var c := rec[i]
		if nav.flags[c] & NavApi.F.STATIC:
			on_static += 1
			if nav.breach_layer(1).solid[c] == 0:
				open += 1
	SimHarness.check(on_static > 0 and open == 0,
		"тўғон в глубокой воде: клеток на статике %d, открыто в breach врага %d" % [on_static, open])
	# обрыв поперёк карты (статика вручную) и дом команды 0 на нём: враг не ломится через обрыв
	var k2 := make(MAP_128)
	var n2: NavGrid = k2["nav"]
	var e2: EconStub = k2["econ"]
	for row in n2.h:
		for col in [63, 64]:
			var c: int = row * n2.w + col
			n2._static_f[c] = NavApi.F.STATIC
			n2._static_cells.append(c)
			n2._refresh_cell(c)
	e2.spawn_building(0, d.building(&"uy"), n2.cell_center(32 * n2.w + 64) + Vector2(-2, -2), 0)
	var r := n2.find_now(1, Vector2(-40, 0), Vector2(40, 0))
	SimHarness.check(r.breach_b == 0 and r.no_route, "обрыв с чужим домом: пролома нет, no_route (%s)" % str(r.pts))


## Связность по месту: 300 шагов случайных правок (кольца и отрезки стен, дома, ворота, снос) на 128²;
## после каждого шага — разбиение областей walk и breach обеих команд как у полного пересчёта, каждые
## 20 шагов — метки, входы и граф входов как у слоя, построенного заново
func _test_components_fuzz() -> void:
	print("[связность по месту против полного пересчёта: случайные правки]")
	var k := make(MAP_128)
	var nav: NavGrid = k["nav"]
	var econ: EconStub = k["econ"]
	var d: Defs = k["defs"]
	var B := econ.buildings
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	nav.sync_for_paths()
	var layers: Array[NavRegions] = [nav.walk_layer(0), nav.walk_layer(1), nav.breach_layer(0), nav.breach_layer(1)]
	for L in layers:
		L.comp_of(0)
	var full0 := 0
	var split0 := 0
	for L in layers:
		full0 += L.full_passes
		split0 += L.split_visits
	var live := PackedInt32Array()
	var bad := 0
	var bad_graph := 0
	var checks := 0
	var t0 := cpu_us()
	for step in 300:
		for o in 1 + rng.randi() % 3:
			var p := rng.randi() % 2
			var r := rng.randi() % 10
			var at := Vector2(rng.randf_range(-200, 200), rng.randf_range(-200, 200))
			var wid := &"devor" if p == 0 else &"chep"
			if r < 3 and not live.is_empty():
				var i := rng.randi() % live.size()
				nav.unstamp(live[i])
				B.release(B.slot(live[i]))
				live.remove_at(i)
			elif r < 5:
				live.append_array(wall(k, p, wid, ring_pts(at, rng.randf_range(8.0, 40.0), 6 + rng.randi() % 6)))
			elif r < 7:
				var b2 := at + Vector2(rng.randf_range(-80, 80), rng.randf_range(-80, 80))
				live.append_array(wall(k, p, wid, PackedVector2Array([at, b2])))
			elif r < 9:
				var bt := d.building(&"uy") if p == 0 else d.building(&"boz")
				var rq := rng.randi() % 4
				live.append(econ.spawn_building(p, bt, nav.snap(bt, at, rq), rq))
			elif not live.is_empty():
				var sl := B.slot(live[rng.randi() % live.size()])
				var g := gate(k, B.owner[sl], &"darvoza" if B.owner[sl] == 0 else &"darbaza", Vector2(B.x[sl], B.z[sl]))
				if g != 0:
					live.append(g)
		var keep := PackedInt32Array()                 # звенья, снятые воротами, — из списка
		for h in live:
			if not nav.stamp_of(h).is_empty():
				keep.append(h)
		live = keep
		nav.sync_for_paths()
		for L in layers:
			L.comp_of(0)
			checks += 1
			if not comps_match_full(L):
				bad += 1
		if step % 20 == 19:
			for L in layers:
				if not graph_matches_fresh(L):
					bad_graph += 1
	var full := -full0
	var split := -split0
	for L in layers:
		full += L.full_passes
		split += L.split_visits
	SimHarness.check(bad == 0 and bad_graph == 0,
		"%d сверок компонент: расхождений %d; графа входов (60 сверок): %d — %.0f мс проц." % [
		checks, bad, bad_graph, (cpu_us() - t0) / 1000.0])
	SimHarness.check(full <= 4 and split > 0,
		"полных пересчётов за 300 шагов: %d (по месту; областей в проверках разрыва %d)" % [full, split])


## Прямая видимость у воды (§9.4e): путь из мелкой воды на сушу не срезается по воде мимо сухого
## обхода, найденного A* (вода — вес 2); между двумя точками в воде — напрямик по воде можно.
## Всё в одном секторе (путь — один A* по весам)
func _test_los_water() -> void:
	print("[прямая видимость: из воды на сушу — не напрямик по воде]")
	var k := make(MAP_128)
	var nav: NavGrid = k["nav"]
	for row in range(70, 73):                          # полоса мелкой воды в секторе (4, 4)
		for col in range(66, 78):
			var c := row * nav.w + col
			nav._static_f[c] = NavApi.F.WATER | NavApi.F.FORD
			nav._static_cells.append(c)
			nav._refresh_cell(c)
	nav.sync_for_paths()
	var a := nav.cell_center(71 * nav.w + 67)
	var b := nav.cell_center(71 * nav.w + 79)
	var r := nav.find_now(0, a, b)
	var wet := 0
	for c in path_cells(nav, a, r.pts):
		if nav.flags[c] & NavApi.F.WATER:
			wet += 1
	SimHarness.check(not r.no_route and r.pts.size() >= 2 and wet <= 5,
		"из воды на сушу: клеток воды на пути %d — выход A* из воды (напрямик — 11): %s" % [wet, str(r.pts)])
	var r2 := nav.find_now(0, a, nav.cell_center(71 * nav.w + 76))
	SimHarness.check(r2.pts.size() == 1, "оба конца в воде: напрямик (%s)" % str(r2.pts))


## Кэш ходок: устаревшая запись уходит и из очереди вытеснения (ключи без повторов, по записи на ключ)
func _test_cache() -> void:
	print("[кэш путей: устаревшие записи]")
	var k := make(MAP_128)
	var nav: NavGrid = k["nav"]
	var econ: EconStub = k["econ"]
	var d: Defs = k["defs"]
	var a := Vector2(-100, -3)
	var b := Vector2(100, 5)
	var hits0 := nav.paths.cache_hits
	var uy := d.building(&"uy")
	for i in 3:
		nav.paths.solve(nav, 0, a, b, true)
		nav.paths.solve(nav, 0, a, b, true)
		econ.spawn_building(0, uy, nav.snap(uy, Vector2(-60 + 40 * i, 0), 0), 0)
		nav.sync_for_paths()
	nav.paths.solve(nav, 0, a, b, true)
	var keys := nav.paths._cache_keys
	var uniq := {}
	for key in keys:
		uniq[key] = true
	SimHarness.check(nav.paths.cache_hits - hits0 == 3 and keys.size() == nav.paths._cache.size() and uniq.size() == keys.size(),
		"3 попадания, 3 устаревания: ключей в очереди %d, записей %d, разных ключей %d" % [
		keys.size(), nav.paths._cache.size(), uniq.size()])


## Неверные команды: предупреждение и «нет пути», слоёв не прибавляется; ничья постройка (команда −1) —
## чужая всем; звено без концов — не стена для ворот (без тригонометрии); потерянный EconApi —
## расстановка NOT_ALLOWED
func _test_bad_inputs() -> void:
	print("[неверные команды, ничьи постройки, звено без концов, потерянный EconApi]")
	var k := make(MAP_128)
	var nav: NavGrid = k["nav"]
	var econ: EconStub = k["econ"]
	var d: Defs = k["defs"]
	var uy := d.building(&"uy")
	econ.spawn_building(-1, uy, nav.snap(uy, Vector2(0.5, 0.5), 0), 0)
	var c := nav.cell_of(Vector2(0.5, 0.5))
	SimHarness.check(nav.team_of[c] == NavGrid.NO_TEAM and nav.walk_layer(0).solid[c] == 1 and nav.walk_layer(1).solid[c] == 1 \
		and nav.breach_layer(0).solid[c] == 0 and nav.breach_layer(1).solid[c] == 0 and nav.enemy_structs(0) and nav.enemy_structs(1),
		"ничья постройка: team_of 255, сплошная в walk, ломается обеими командами")
	var ok := true
	for t in [-1, 2, 4, 255]:
		var r := nav.find_now(t, Vector2(-100, -100), Vector2(100, 100))
		ok = ok and r != null and r.no_route and r.pts.size() == 1
		ok = ok and not nav.reachable(t, Vector2(-100, -100), Vector2(-90, -100)) and not nav.passable(t, 0)
		var tk := nav.request(t, Vector2(-100, -100), Vector2(100, 100), 1)
		nav.service(1)
		var rr := nav.result(tk)
		ok = ok and rr != null and rr.no_route
		nav.release(tk)
	SimHarness.check(ok and nav._walk.size() == 2 and nav._breach.size() == 2,
		"команды −1, 2, 4, 255 при teams = 2: «нет пути», слоёв по-прежнему %d" % nav._walk.size())
	# звено стены прямоугольником, без концов (ни в штампе, ни в BuildingTable): ворота на него не встают
	var B := econ.buildings
	var dv := d.building(&"devor")
	var b := B.alloc(BuildingTable.State.ACTIVE)
	B.btype[b] = dv
	B.owner[b] = 0
	B.team[b] = 0
	B.x[b] = 60.0
	B.z[b] = 60.0
	B.rot[b] = 0.3
	nav.stamp_building(B.handle(b), 0, Vector2(60, 60), dv, 0)
	var s := nav.snap_on_wall(0, d.building(&"darvoza"), Vector2(60, 60))
	SimHarness.check(int(s["why"]) == NavApi.Why.NOT_ON_WALL, "звено без концов: ворота — NOT_ON_WALL (%d)" % int(s["why"]))
	# потерянный EconApi: был дан в setup и освобождён — расстановка не пропускает молча
	var nav2 := NavGrid.new()
	var e2 := EconStub.new()
	e2.setup(d, d.rules_of(&"GOROD"), null, nav2, SimEvents.new(), 1)
	nav2.setup(MAP_64, d, e2, null)
	var at := nav2.snap(uy, Vector2(10, 10), 0)
	var before := nav2.check_place(0, uy, at, 0)
	e2 = null
	var after := nav2.check_place(0, uy, at, 0)
	var cells := nav2.place_cells(0, uy, at, 0)
	var plan := nav2.plan_wall(0, dv, PackedVector2Array([Vector2(0, 0), Vector2(20, 0)]))
	var pw: PackedByteArray = plan["why"]
	SimHarness.check(before == NavApi.Why.OK and nav2.econ == null and after == NavApi.Why.NOT_ALLOWED \
		and cells.count(NavApi.Why.NOT_ALLOWED) == cells.size() and pw.count(NavApi.Why.NOT_ALLOWED) == pw.size(),
		"EconApi освобождён: check_place %d → %d, клетки и звенья — NOT_ALLOWED" % [before, after])
