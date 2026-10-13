extends SceneTree
## Навигация «Города» (ARCHITECTURE §9, §15 NAV): сетка, слои команд, ворота, пролом, коридоры,
## суперобложка стен, устаревание путей, бюджет и детерминизм службы путей, память 400².
##   godot --headless --path ordo --script res://tests/test_nav.gd
## Время: «проц.» — процессорное время потока (/proc/thread-self/schedstat; машину делят другие
## агенты, часы врут), «часы» — лучший из нескольких прогонов.
## Статические помощники (make, wall, cpu_us…) берут и test_placement, test_wall_tool.

const MAP_400 := {"size": 801, "spacing": 2.0, "origin": [-800.0, -800.0], "flat": true, "teams": 2}
const MAP_64 := {"size": 129, "spacing": 2.0, "origin": [-128.0, -128.0], "flat": true, "teams": 2}

static var _cpu_ok := true


func _init() -> void:
	_test_raster()
	_test_terrain()
	_test_gates()
	_test_enclosed_400()
	_test_detour_400()
	_test_random_walls()
	_test_stale()
	_test_budget()
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
			"бюджет %d: порядок обслуживания и пути совпали в двух прогонах (сумма %d)" % [cells_budget, sums[0]])
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
