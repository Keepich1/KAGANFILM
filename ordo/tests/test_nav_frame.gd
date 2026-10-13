extends SceneTree
## Кадр проверки NAV (сверху, без отрисовки сцены — Image): «Долина» 256², город Коканда в кольце
## пахсы с Дарвозой на западе, лагерь кыпчаков с загоном в частоколе, жилы, брод; четыре пути:
## свой — через ворота (белый), враг — пролом (пурпурный, кружок — точка перед проломом), через брод
## (голубой), кыпчаки — в свой загон без ворот: «нет прохода» (тёмный, до ближайшей точки).
## Стены — только звенья с why == OK, постройки — только через check_place (кадр не показывает
## невозможного). Ворота — жёлтые клетки в чёрной рамке и жёлтое кольцо вокруг.
##   godot --headless --path ordo --script res://tests/test_nav_frame.gd  → renders/nav/nav_valley.png

const T := preload("res://tests/test_nav.gd")
const SC := 4                     # пикселей на клетку
const OUT := "res://renders/nav/nav_valley.png"

var img: Image
var nav: NavGrid


func _init() -> void:
	var k := T.make()
	nav = k["nav"]
	var econ: EconStub = k["econ"]
	var d: Defs = k["defs"]
	var kok := Vector2(184, 56)
	var kip := Vector2(-60, 20)
	var pen := Vector2(-160, 120)
	econ.spawn_building(0, d.building(&"urda"), nav.snap(d.building(&"urda"), kok, 3), 3)
	econ.spawn_building(1, d.building(&"ordo"), nav.snap(d.building(&"ordo"), kip, 0), 0)
	for dep: Array in MapValley.MAP["deposits"]:
		econ.spawn_node(d.node(StringName(dep[0])), dep[1])
	# сперва стены (только допустимые звенья), затем ворота, затем постройки через check_place
	var bad := [0]
	var ring := _wall_ok(k, 0, &"devor", T.ring_pts(kok, 120.0, 18), bad)
	var g := T.gate(k, 0, &"darvoza", kok + Vector2(-120, 0))
	var fence := _wall_ok(k, 1, &"chep", T.ring_pts(pen, 26.0, 10), bad)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var placed := 0
	var tries := 0
	while placed < 120 and tries < 4000:
		tries += 1
		var p := placed % 2
		var ids: Array = [&"uy", &"uy", &"tegirmon", &"ombor", &"dala", &"kazarma"] if p == 0 else [&"boz", &"boz", &"boz", &"koroo", &"jooker"]
		var bt := d.building(ids[rng.randi() % ids.size()])
		var rq := rng.randi() % 4
		var at := nav.snap(bt, (kok if p == 0 else kip) + Vector2(rng.randf_range(-110, 110), rng.randf_range(-110, 110)), rq)
		if nav.check_place(p, bt, at, rq) == NavApi.Why.OK:
			econ.spawn_building(p, bt, at, rq)
			placed += 1
	nav.service(1)
	SimHarness.check(ring.size() >= 100 and fence.size() >= 40 and g != 0 and placed == 120,
		"кольцо пахсы %d звеньев, частокол %d (отклонено и не поставлено %d), Дарвоза, %d построек через check_place" % [
		ring.size(), fence.size(), bad[0], placed])
	var mixed := 0                                   # клетки стены, на которых стоит и чужая постройка
	for c in nav.w * nav.h:
		if nav.flags[c] & NavApi.F.WALL:
			var teams := {}
			for bh in nav.stamps_at(c):
				teams[nav.stamp_of(bh)[0]] = true
			if teams.size() > 1:
				mixed += 1
	SimHarness.check(mixed == 0, "нет клеток стены под чужой постройкой (%d)" % mixed)
	img = Image.create(nav.w * SC, nav.h * SC, false, Image.FORMAT_RGB8)
	_cells()
	# пути
	var a_gate := kip + Vector2(40, 0)
	var r_gate := nav.find_now(0, a_gate, kok + Vector2(30, 20))
	var through := false
	for cc in T.path_cells(nav, a_gate, r_gate.pts):
		through = through or nav.struct_of[cc] == g
	var a_br := kip + Vector2(40, -40)
	var r_breach := nav.find_now(1, a_br, kok + Vector2(10, -30))
	var a_ford := Vector2(60, -110)
	var r_ford := nav.find_now(0, a_ford, Vector2(-40, -300))
	var a_pen := Vector2(-250, 200)
	var r_pen := nav.find_now(1, a_pen, pen)
	_path(a_gate, r_gate, Color(1, 1, 1))
	_path(a_br, r_breach, Color(1, 0.3, 1))
	_path(a_ford, r_ford, Color(0.3, 0.9, 1))
	_path(a_pen, r_pen, Color(0.15, 0.15, 0.15))
	_gate_marks()
	SimHarness.check(not r_gate.no_route and r_gate.breach_b == 0 and through, "свой путь — через ворота")
	SimHarness.check(r_breach.breach_b != 0 and ring.has(r_breach.breach_b) or r_breach.breach_b == g,
		"враг — пролом через кольцо (точка перед ним %d)" % r_breach.breach_wp)
	SimHarness.check(not r_ford.no_route and r_ford.breach_b == 0, "путь через реку — бродом: %s" % str(r_ford.pts))
	SimHarness.check(r_pen.no_route and r_pen.breach_b == 0, "в свой загон без ворот — нет прохода (не пролом)")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders/nav"))
	SimHarness.check(img.save_png(OUT) == OK, "кадр: %s" % ProjectSettings.globalize_path(OUT))
	SimHarness.finish(self)


## Стена по ломаной, как у ECON: ставятся только звенья с why == OK (остальные — в bad[0])
func _wall_ok(k: Dictionary, player: int, wid: StringName, pts: PackedVector2Array, bad: Array) -> PackedInt32Array:
	var econ: EconStub = k["econ"]
	var d: Defs = k["defs"]
	var wt := d.building(wid)
	var plan := nav.plan_wall(player, wt, pts)
	var why: PackedByteArray = plan["why"]
	var ca: PackedVector2Array = plan["a"]
	var cb: PackedVector2Array = plan["b"]
	var centers: PackedVector2Array = plan["centers"]
	var B := econ.buildings
	var out := PackedInt32Array()
	for i in centers.size():
		if why[i] != NavApi.Why.OK:
			bad[0] += 1
			continue
		var b := B.alloc(BuildingTable.State.ACTIVE)
		B.btype[b] = wt
		B.owner[b] = player
		B.team[b] = econ.players.team[player]
		B.x[b] = centers[i].x
		B.z[b] = centers[i].y
		B.ax[b] = ca[i].x
		B.az[b] = ca[i].y
		B.bx[b] = cb[i].x
		B.bz[b] = cb[i].y
		var h := B.handle(b)
		nav.stamp_link(h, B.team[b], ca[i], cb[i], wt)
		out.append(h)
	return out


## Клетки: рельеф, вода, статика, поля, жилы, постройки сторон (стены темнее), ворота — жёлтые в рамке
func _cells() -> void:
	for c in nav.w * nav.h:
		var f := nav.flags[c]
		var p := nav.cell_center(c)
		var hh := Terrain.height_at(p.x, p.y)
		var col := Color(0.42, 0.47, 0.30).lerp(Color(0.85, 0.82, 0.70), clampf(hh / 60.0, 0.0, 1.0))
		if f & NavApi.F.STATIC and f & NavApi.F.WATER:
			col = Color(0.12, 0.25, 0.55)
		elif f & NavApi.F.WATER:
			col = Color(0.45, 0.75, 0.85)
		elif f & NavApi.F.STATIC:
			col = Color(0.30, 0.28, 0.27)
		if f & NavApi.F.SOFT:
			col = Color(0.55, 0.80, 0.35)
		if f & NavApi.F.NODE:
			col = Color(0.55, 0.30, 0.70)
		if f & NavApi.F.STRUCT:
			col = Color(0.95, 0.55, 0.15) if nav.team_of[c] == 0 else Color(0.70, 0.15, 0.12)
			if f & NavApi.F.WALL:
				col = col.darkened(0.35)
		var gate := f & NavApi.F.GATE != 0
		if gate:
			col = Color(1.0, 0.92, 0.1)
		var x0 := (c % nav.w) * SC
		var y0 := (c / nav.w) * SC
		for dy in SC:
			for dx in SC:
				var cc := col
				if gate and (dx == 0 or dy == 0 or dx == SC - 1 or dy == SC - 1):
					cc = Color(0, 0, 0)
				elif (c % nav.w) % NavApi.SECTOR == 0 and dx == 0 or (c / nav.w) % NavApi.SECTOR == 0 and dy == 0:
					cc = cc.darkened(0.15)
				img.set_pixel(x0 + dx, y0 + dy, cc)


## Кольцо вокруг каждой клетки ворот (поверх путей — ворота видны и под линией пути)
func _gate_marks() -> void:
	for c in nav.w * nav.h:
		if nav.flags[c] & NavApi.F.GATE:
			_ring(nav.cell_center(c), Color(1.0, 0.92, 0.1), 3 * SC)


func _px(p: Vector2) -> Vector2:
	return (p - nav.origin) / NavApi.CELL * SC


func _put(x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)


func _line(a: Vector2, b: Vector2, col: Color) -> void:
	var pa := _px(a)
	var pb := _px(b)
	var n := int(pa.distance_to(pb)) + 1
	for i in n + 1:
		var p := pa.lerp(pb, float(i) / n)
		_put(int(p.x), int(p.y), col)
		_put(int(p.x) + 1, int(p.y), col)


func _dot(p: Vector2, col: Color, r: int) -> void:
	var c := _px(p)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				_put(int(c.x) + dx, int(c.y) + dy, col)


func _ring(p: Vector2, col: Color, r: int) -> void:
	var c := _px(p)
	for dy in range(-r - 1, r + 2):
		for dx in range(-r - 1, r + 2):
			var d2 := dx * dx + dy * dy
			if d2 >= (r - 1) * (r - 1) and d2 <= r * r:
				_put(int(c.x) + dx, int(c.y) + dy, col)


func _path(from: Vector2, r: PathResult, col: Color) -> void:
	var prev := from
	for i in r.pts.size():
		_line(prev, r.pts[i], col)
		prev = r.pts[i]
	_dot(from, col, 4)
	if r.breach_b != 0 and r.breach_wp >= 0:
		_ring(r.pts[r.breach_wp], Color(1, 0, 1), 7)
