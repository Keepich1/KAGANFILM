extends SceneTree
## Стены (ARCHITECTURE §10, §15 NAV; ТЗ §6): разметка звеньев, цена, причины по звеньям,
## продолжение своей стены, ворота заменяют звенья и встают по линии, башня на стене,
## диагональная стена без щелей, арык через мелкую воду.
##   godot --headless --path ordo --script res://tests/test_wall_tool.gd

const T := preload("res://tests/test_nav.gd")
const W := NavApi.Why


func _init() -> void:
	_test_plan()
	_test_reasons()
	_test_gate()
	_test_tower()
	_test_diagonal()
	SimHarness.finish(self)


func _test_plan() -> void:
	print("[разметка линии]")
	var k := T.make()
	var nav: NavGrid = k["nav"]
	var d: Defs = k["defs"]
	var dv := d.building(&"devor")
	var c := SimHarness.flat_spot()
	var plan := nav.plan_wall(0, dv, PackedVector2Array([c, c + Vector2(40, 0)]))
	var centers: PackedVector2Array = plan["centers"]
	var pitch := d.b_link_len[dv] - d.b_link_overlap[dv]
	var n := ceili(40.0 / pitch - 0.001)
	var max_gap := 0.0
	for i in range(1, centers.size()):
		max_gap = maxf(max_gap, centers[i].distance_to(centers[i - 1]))
	SimHarness.check(centers.size() == n and max_gap <= pitch + 0.001,
		"40 м пахсы: %d звеньев (⌈40 / %.1f⌉), шаг %.2f ≤ %.1f м" % [centers.size(), pitch, max_gap, pitch])
	var cost: PackedInt32Array = plan["cost"]
	SimHarness.check(cost[d.res(&"wood")] == d.b_cost[dv * d.R + d.res(&"wood")] * n, "цена: %d дерева (милли)" % cost[d.res(&"wood")])
	var why: PackedByteArray = plan["why"]
	SimHarness.check(why.count(W.OK) == n, "на лугу все звенья — можно")
	var rots: PackedFloat32Array = plan["rots"]
	SimHarness.check(absf(rots[0]) < 0.001, "звено вдоль +X — поворот 0")
	var a: PackedVector2Array = plan["a"]
	var b: PackedVector2Array = plan["b"]
	SimHarness.check(a.size() == n and absf(a[0].distance_to(b[0]) - d.b_link_len[dv]) < 0.001 and a[0].x < c.x,
		"концы звена: длина %.1f м, первое заходит за начало линии" % d.b_link_len[dv])
	var poly := nav.plan_wall(0, dv, PackedVector2Array([c, c + Vector2(20, 0), c + Vector2(20, 20), c + Vector2(0, 20)]))
	SimHarness.check((poly["centers"] as PackedVector2Array).size() == 3 * ceili(20.0 / pitch - 0.001),
		"ломаная из трёх отрезков — звенья по каждому")
	var chep := nav.plan_wall(1, d.building(&"chep"), PackedVector2Array([c, c + Vector2(30, 0)]))
	SimHarness.check((chep["centers"] as PackedVector2Array).size() == ceili(30.0 / 3.0 - 0.001), "чеп: шаг 3,0 м")


func _test_reasons() -> void:
	print("[причины по звеньям]")
	var k := T.make()
	var nav: NavGrid = k["nav"]
	var econ: EconStub = k["econ"]
	var d: Defs = k["defs"]
	var dv := d.building(&"devor")
	var c := SimHarness.flat_spot()
	econ.spawn_building(0, d.building(&"uy"), nav.snap(d.building(&"uy"), c + Vector2(20, 0), 0), 0)
	var why: PackedByteArray = nav.plan_wall(0, dv, PackedVector2Array([c, c + Vector2(40, 0)]))["why"]
	SimHarness.check(why.count(W.OVERLAP) >= 2 and why[0] == W.OK and why[why.size() - 1] == W.OK,
		"через дом — звенья на нём OVERLAP (%d), остальные можно" % why.count(W.OVERLAP))
	var edge: PackedByteArray = nav.plan_wall(0, dv, PackedVector2Array([Vector2(-500, 0), Vector2(-520, 0)]))["why"]
	SimHarness.check(edge.has(W.OUT_OF_MAP), "за краем карты — OUT_OF_MAP")
	var river: PackedByteArray = nav.plan_wall(0, dv, PackedVector2Array([Vector2(150, -150), Vector2(150, -190)]))["why"]
	SimHarness.check(river.has(W.WATER), "через реку — WATER")
	# продолжение своей стены от её конца — можно; чужой — нет
	var line := PackedVector2Array([c + Vector2(0, 40), c + Vector2(30, 40)])
	T.wall(k, 0, &"devor", line)
	var cont: PackedByteArray = nav.plan_wall(0, dv, PackedVector2Array([c + Vector2(30, 40), c + Vector2(60, 40)]))["why"]
	SimHarness.check(cont.count(W.OK) == cont.size(), "продолжение своей стены от конца — можно")
	var foe: PackedByteArray = nav.plan_wall(1, d.building(&"chep"), PackedVector2Array([c + Vector2(30, 40), c + Vector2(60, 40)]))["why"]
	SimHarness.check(foe[0] == W.OVERLAP, "чужую стену продолжать нельзя — OVERLAP")
	# арык (звено LINK): через мелкую воду можно, через глубокую — нет
	var ar := d.building(&"aryk")
	var shallow := Vector2(20, -150)
	var aw: PackedByteArray = nav.plan_wall(0, ar, PackedVector2Array([shallow + Vector2(0, -6), shallow + Vector2(0, 6)]))["why"]
	var dw: PackedByteArray = nav.plan_wall(0, ar, PackedVector2Array([Vector2(160, -160), Vector2(160, -180)]))["why"]
	SimHarness.check(aw.count(W.OK) == aw.size() and dw.has(W.WATER), "арык: мелкая вода — можно, глубокая — WATER")
	var off: PackedByteArray = nav.plan_wall(0, d.building(&"temirchixona"), PackedVector2Array([c, c + Vector2(10, 0)]))["why"]
	SimHarness.check(off.is_empty(), "не звено — пустой план")


func _test_gate() -> void:
	print("[ворота на стене]")
	var k := T.make()
	var nav: NavGrid = k["nav"]
	var d: Defs = k["defs"]
	var dz := d.building(&"darvoza")
	var c := SimHarness.flat_spot()
	var links := T.wall(k, 0, &"devor", PackedVector2Array([c + Vector2(-40, 0), c + Vector2(40, 0)]))
	var s := nav.snap_on_wall(0, dz, c + Vector2(1.3, 2.5))
	var center: Vector2 = s["center"]
	var removes: PackedInt32Array = s["removes"]
	SimHarness.check(int(s["why"]) == W.OK and absf(center.y - c.y) < 0.01 and absf(center.x - c.x - 1.3) < 0.01,
		"Дарвоза у стены: встала на линию в %s" % str(center))
	var all_links := true
	for h in removes:
		all_links = all_links and links.has(h)
	SimHarness.check(removes.size() >= 2 and all_links, "заменяет звенья под собой: %d" % removes.size())
	SimHarness.check(absf(float(s["rot"])) < 0.001, "поворот — по стене")
	SimHarness.check(nav.check_place(0, dz, c + Vector2(1.3, 2.5), 0) == W.OK, "check_place ворот — через snap_on_wall")
	SimHarness.check(int(nav.snap_on_wall(0, dz, c + Vector2(0, 30))["why"]) == W.NOT_ON_WALL, "вдали от стены — NOT_ON_WALL")
	SimHarness.check(int(nav.snap_on_wall(1, d.building(&"darbaza"), c + Vector2(0, 1))["why"]) == W.NOT_ON_WALL,
		"на чужой стене — NOT_ON_WALL")
	var g := T.gate(k, 0, &"darvoza", c + Vector2(1.3, 2.5))
	var above := c + Vector2(0, -30)
	var below := c + Vector2(0, 30)
	# стена 80 м посреди луга обходится; закроем обход длинными крыльями
	T.wall(k, 0, &"devor", PackedVector2Array([c + Vector2(-40, 0), c + Vector2(-40, 300)]))
	T.wall(k, 0, &"devor", PackedVector2Array([c + Vector2(40, 0), c + Vector2(40, 300)]))
	var r0 := nav.find_now(0, above, below)
	var through := false
	for cc in T.path_cells(nav, above, r0.pts):
		through = through or nav.struct_of[cc] == g
	SimHarness.check(g != 0 and not r0.no_route and r0.breach_b == 0 and through, "свои — через ворота")
	var r1 := nav.find_now(1, above, below)
	var foe_through := false
	for cc in T.path_cells(nav, above, r1.pts.slice(0, r1.breach_wp + 1) if r1.breach_b != 0 else r1.pts):
		foe_through = foe_through or nav.struct_of[cc] == g
	var foe_reach := nav.reachable(1, above, below)
	SimHarness.check(not foe_through and foe_reach == (r1.breach_b == 0),
		"враг в ворота не входит: %s" % ("пролом" if r1.breach_b != 0 else "обход вокруг крыльев"))


func _test_tower() -> void:
	print("[башня на стене]")
	var k := T.make()
	var nav: NavGrid = k["nav"]
	var d: Defs = k["defs"]
	var bj := d.building(&"burj")
	var c := SimHarness.flat_spot()
	var links := T.wall(k, 0, &"devor", PackedVector2Array([c + Vector2(-30, 0), c + Vector2(30, 0)]))
	var s := nav.snap_on_wall(0, bj, c + Vector2(0.5, 1.0))
	var removes: PackedInt32Array = s["removes"]
	var all_links := true
	for h in removes:
		all_links = all_links and links.has(h)
	SimHarness.check(int(s["why"]) == W.OK and removes.size() >= 2 and all_links,
		"Бурж на стене: можно, уходят %d звеньев" % removes.size())
	SimHarness.check(nav.check_place(0, bj, s["center"], 0) == W.OK, "check_place башни на своих звеньях — можно")
	var free := nav.snap_on_wall(0, bj, c + Vector2(0, 60))
	SimHarness.check(int(free["why"]) == W.OK and (free["removes"] as PackedInt32Array).is_empty(),
		"Бурж в стороне от стены — обычная постройка")
	SimHarness.check(nav.check_place(1, d.building(&"munara"), s["center"], 0) == W.OVERLAP,
		"чужая башня на этой стене — OVERLAP")


func _test_diagonal() -> void:
	print("[диагональная стена без щелей]")
	var k := T.make()
	var nav: NavGrid = k["nav"]
	var c := SimHarness.flat_spot()
	# замкнутый косой ромб: внутрь не пройти никому, своему — no_route, врагу — пролом
	var pts := PackedVector2Array([c + Vector2(0, -37), c + Vector2(29, 3), c + Vector2(-3, 41), c + Vector2(-33, -1),
		c + Vector2(0, -37)])
	var links := T.wall(k, 0, &"chep", pts)
	var wl := nav.walk_layer(1)
	nav.sync_for_paths()
	var inside := nav.cell_of(c)
	var outside := nav.cell_of(c + Vector2(0, 80))
	SimHarness.check(not T.flood_reaches(nav, wl, outside, inside) and not nav.reachable(0, c + Vector2(0, 80), c),
		"ромб из %d звеньев: заливка внутрь не проходит" % links.size())
	var r := nav.find_now(1, c + Vector2(0, 80), c)
	SimHarness.check(r.breach_b != 0 and links.has(r.breach_b), "враг ломает звено ромба")
