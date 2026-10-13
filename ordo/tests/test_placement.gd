extends SceneTree
## Правила места постройки (ARCHITECTURE §10, §15 NAV): вне карты, наложение, вода, крутизна,
## Кен у жилы (≤ 26 м), тўғон на реке (не на броде), зона воды Хумдона, своя земля, враг внутри,
## сторона и цена, совпадение check_place и place_cells, ядра жил в сетке, раскладка көч.
##   godot --headless --path ordo --script res://tests/test_placement.gd

const T := preload("res://tests/test_nav.gd")
const W := NavApi.Why


## ECON для проверки зоны воды и своей земли (EconStub даёт пустую воду и «везде своя земля»)
class ZoneEcon extends EconStub:
	var land_c := Vector2.ZERO
	var land_r := 1.0e9
	var water := PackedByteArray()

	func in_territory(p: int, pos: Vector2) -> bool:
		return pos.distance_to(land_c) <= land_r

	func water_grid() -> PackedByteArray:
		return water


func _init() -> void:
	_test_basic_reasons()
	_test_nodes()
	_test_dam()
	_test_zones()
	_test_units_and_rules()
	_test_consistency()
	_test_ring_slots()
	SimHarness.finish(self)


func _why_name(v: int) -> String:
	return W.keys()[v] if v >= 0 and v < W.size() else str(v)


func _test_basic_reasons() -> void:
	print("[причины: карта, наложение, вода, крутизна]")
	var k := T.make()
	var nav: NavGrid = k["nav"]
	var econ: EconStub = k["econ"]
	var d: Defs = k["defs"]
	var uy := d.building(&"uy")
	var urda := d.building(&"urda")
	var c := nav.snap(uy, SimHarness.flat_spot(), 0)
	SimHarness.check(nav.check_place(0, uy, c, 0) == W.OK, "Уй на ровном лугу — можно")
	SimHarness.check(nav.check_place(0, urda, Vector2(-509, 0), 0) == W.OUT_OF_MAP, "Урда у края карты — OUT_OF_MAP")
	econ.spawn_building(0, uy, c, 0)
	SimHarness.check(nav.check_place(0, uy, c + Vector2(4, 0), 0) == W.OVERLAP, "на другой дом — OVERLAP")
	SimHarness.check(nav.check_place(0, uy, c + Vector2(8, 0), 0) == W.OK, "вплотную рядом — можно")
	var ford := nav.snap(uy, Vector2(20, -157.39), 0)
	SimHarness.check(nav.check_place(0, uy, ford, 0) == W.WATER, "на броде — WATER")
	SimHarness.check(nav.check_place(0, uy, nav.snap(uy, Vector2(160, -170.5), 0), 0) == W.WATER, "в реке — WATER")
	# крутой склон (STATIC без воды) и перепад высот по углам следа
	var steep := Vector2.INF
	var spread := Vector2.INF
	for cy in range(8, nav.h - 8, 3):
		for cx in range(8, nav.w - 8, 3):
			var p := nav.cell_center(cy * nav.w + cx)
			var cells := nav.place_cells(0, uy, nav.snap(uy, p, 0), 0)
			if steep == Vector2.INF and nav.flags[cy * nav.w + cx] == NavApi.F.STATIC:
				steep = p
			if spread == Vector2.INF and not cells.is_empty() and cells[0] == W.SLOPE:
				var fp := NavApi.footprint(d, uy, nav.snap(uy, p, 0), 0, nav.origin)
				var clean := true
				for row in range(fp.position.y, fp.end.y):
					for col in range(fp.position.x, fp.end.x):
						clean = clean and nav.flags[row * nav.w + col] == 0
				if clean:
					spread = p
	SimHarness.check(steep != Vector2.INF and nav.check_place(0, uy, nav.snap(uy, steep, 0), 0) == W.SLOPE,
		"крутой склон — SLOPE (%s)" % str(steep))
	SimHarness.check(spread != Vector2.INF, "проходимые клетки, но перепад углов > 1,2 м — SLOPE (%s)" % str(spread))
	var cells := nav.place_cells(0, uy, nav.snap(uy, SimHarness.flat_spot() + Vector2(-2, 0), 0), 0)
	SimHarness.check(cells.size() == 4, "след Уй — 2×2 клетки (%d)" % cells.size())


func _test_nodes() -> void:
	print("[жилы и деревья: Кен ≤ 26 м, ядро 2×2, деревья мешают стройке]")
	var k := T.make()
	var nav: NavGrid = k["nav"]
	var econ: EconStub = k["econ"]
	var d: Defs = k["defs"]
	var ken := d.building(&"ken")
	var base := SimHarness.flat_spot() + Vector2(0, -40)
	var nh := econ.spawn_node(d.node(&"stone"), base)
	nav.service(1)                                  # жилы ложатся в сетку в такте симуляции
	var core := 0
	var blocked := 0
	for dz in range(-2, 2):
		for dx in range(-2, 2):
			var c := nav.cell_of(base + Vector2(dx * 4.0 + 2.0, dz * 4.0 + 2.0))
			if nav.flags[c] & NavApi.F.NODE:
				core += 1
				if not nav.passable(0, c):
					blocked += 1
	SimHarness.check(core == 4 and blocked == 4, "ядро жилы — 2×2 клетки, непроходимо (%d/%d)" % [core, blocked])
	var near := nav.snap(ken, base + Vector2(20, 0), 0)
	var far := nav.snap(ken, base + Vector2(36, 0), 0)
	SimHarness.check(nav.check_place(1, ken, near, 0) == W.OK, "Кен в 20 м от камня — можно")
	SimHarness.check(nav.check_place(1, ken, far, 0) == W.NOT_NEAR, "Кен в 36 м — NOT_NEAR")
	SimHarness.check(nav.check_place(1, ken, nav.snap(ken, base, 0), 0) == W.OVERLAP, "Кен на жиле — OVERLAP")
	# выработанная жила всё ещё стоит (ядро), но Кен к ней не тянется
	econ.nodes.amount_milli[econ.nodes.slot(nh)] = 0
	SimHarness.check(nav.check_place(1, ken, near, 0) == W.NOT_NEAR, "у выработанной жилы — NOT_NEAR")
	# дерево в клетке мешает дому, срубленное — нет
	var uy := d.building(&"uy")
	var spot := nav.snap(uy, SimHarness.flat_spot() + Vector2(40, 40), 0)
	var th := econ.spawn_node(d.node(&"tree_poplar"), spot + Vector2(1, 1))
	SimHarness.check(nav.check_place(0, uy, spot, 0) == W.OVERLAP, "дерево под домом — OVERLAP")
	SimHarness.check(nav.passable(0, nav.cell_of(spot + Vector2(1, 1))), "деревья не мешают ходить")
	econ.nodes.amount_milli[econ.nodes.slot(th)] = 0
	SimHarness.check(nav.check_place(0, uy, spot, 0) == W.OK, "срубленное дерево — можно строить")
	# ядро снимается, когда ECON освобождает слот узла
	econ.nodes.release(econ.nodes.slot(nh))
	nav.service(2)
	SimHarness.check(nav.passable(0, nav.cell_of(base + Vector2(2, 2))), "слот жилы освобождён — ядро снято")


func _test_dam() -> void:
	print("[тўғон: на реке, не на броде]")
	var k := T.make()
	var nav: NavGrid = k["nav"]
	var d: Defs = k["defs"]
	var tg := d.building(&"togon")
	var sites: Array = MapValley.MAP["dam_sites"]
	var ok := 0
	for s: Vector2 in sites:
		if nav.check_place(0, tg, nav.snap(tg, s, 0), 0) == W.OK:
			ok += 1
	SimHarness.check(ok == sites.size(), "места под тўғон с карты — можно (%d/%d)" % [ok, sites.size()])
	SimHarness.check(nav.check_place(0, tg, nav.snap(tg, SimHarness.flat_spot(), 0), 0) == W.NOT_NEAR,
		"на сухом лугу — NOT_NEAR")
	SimHarness.check(nav.check_place(0, tg, nav.snap(tg, Vector2(20, -160), 0), 0) == W.NOT_ALLOWED,
		"на броде — NOT_ALLOWED")


func _test_zones() -> void:
	print("[своя земля и зона воды]")
	var defs := Defs.shared()
	var nav := NavGrid.new()
	var port := CombatPortStub.new()
	var econ := ZoneEcon.new()
	nav.setup(Terrain.info(), defs, econ, port)
	port.setup(defs, nav, {"teams": 2})
	econ.setup(defs, defs.rules_of(&"GOROD"), port, nav, SimEvents.new(), 1)
	econ.add_player(0, &"kokand", PlayerTable.Ctrl.HUMAN)
	for r in defs.R:
		econ.players.res[r] = 1000000
	var home := SimHarness.flat_spot()
	econ.land_c = home
	econ.land_r = 70.0
	var uy := defs.building(&"uy")
	SimHarness.check(nav.check_place(0, uy, nav.snap(uy, home + Vector2(30, 0), 0), 0) == W.OK, "в своей земле — можно")
	SimHarness.check(nav.check_place(0, uy, nav.snap(uy, home + Vector2(120, 0), 0), 0) == W.NO_TERRITORY,
		"за 70 м от ставки — NO_TERRITORY")
	var xum := defs.building(&"xumdon")
	SimHarness.check(nav.check_place(0, xum, nav.snap(xum, home + Vector2(20, 20), 0), 0) == W.OK,
		"без сетки воды (заглушка) — Хумдон можно")
	econ.water.resize(128 * 128)
	var wc := home + Vector2(-20, 30)
	for j in 128:
		for i in 128:
			var p := Vector2(-512 + (i + 0.5) * 8.0, -512 + (j + 0.5) * 8.0)
			econ.water[j * 128 + i] = 255 if p.distance_to(wc) < 24.0 else 0
	SimHarness.check(nav.check_place(0, xum, nav.snap(xum, wc, 0), 0) == W.OK, "Хумдон в зоне воды — можно")
	SimHarness.check(nav.check_place(0, xum, nav.snap(xum, home + Vector2(40, -30), 0), 0) == W.NOT_NEAR,
		"Хумдон вне зоны воды — NOT_NEAR")


func _test_units_and_rules() -> void:
	print("[враг в следе, сторона, цена]")
	var k := T.make()
	var nav: NavGrid = k["nav"]
	var econ: EconStub = k["econ"]
	var port: CombatPortStub = k["port"]
	var d: Defs = k["defs"]
	var uy := d.building(&"uy")
	var c := nav.snap(uy, SimHarness.flat_spot() + Vector2(0, 30), 0)
	port.spawn(0, 0, &"dehqon", c + Vector2(1, 1), 0.0)
	SimHarness.check(nav.check_place(0, uy, c, 0) == W.OK, "свой работник в следе — можно (его вытолкнут)")
	var eh := port.spawn(1, 1, &"malchy", c + Vector2(-1, 1), 0.0)
	SimHarness.check(nav.check_place(0, uy, c, 0) == W.ENEMY_UNITS, "враг в следе — ENEMY_UNITS")
	port.kill(eh)
	SimHarness.check(nav.check_place(0, uy, c, 0) == W.OK, "враг убит — можно")
	SimHarness.check(nav.check_place(1, uy, c, 0) == W.NOT_ALLOWED, "кыпчак ставит Уй — NOT_ALLOWED")
	SimHarness.check(nav.check_place(0, d.building(&"temirchixona"), c, 0) == W.NOT_ALLOWED,
		"выключенная постройка (Сб. 2) — NOT_ALLOWED")
	for r in d.R:
		econ.players.res[r] = 0
	SimHarness.check(nav.check_place(0, uy, c, 0) == W.NO_RES, "без ресурсов — NO_RES")
	var cells := nav.place_cells(0, uy, c, 0)
	SimHarness.check(not cells.is_empty() and cells.count(W.OK) == cells.size(), "place_cells цену не смотрит (призрак)")


## check_place = OK ⇔ все клетки place_cells = OK; худшая причина — первая по порядку
func _test_consistency() -> void:
	print("[check_place и place_cells согласованы]")
	var k := T.make()
	var nav: NavGrid = k["nav"]
	var econ: EconStub = k["econ"]
	var d: Defs = k["defs"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 40:
		var p := Vector2(rng.randf_range(-200, 260), rng.randf_range(-260, 200))
		var bt := d.building(&"uy") if i % 2 == 0 else d.building(&"tegirmon")
		if nav.check_place(0, bt, nav.snap(bt, p, 0), 0) == W.OK:
			econ.spawn_building(0, bt, nav.snap(bt, p, 0), 0)
	var bad := 0
	var n_ok := 0
	var ids := [&"uy", &"tegirmon", &"kazarma", &"urda", &"togon", &"dala", &"bozor"]
	for i in 600:
		var bt := d.building(ids[i % ids.size()])
		var rq := i % 4
		var p := nav.snap(bt, Vector2(rng.randf_range(-500, 500), rng.randf_range(-500, 500)), rq)
		var why := nav.check_place(0, bt, p, rq)
		var cells := nav.place_cells(0, bt, p, rq)
		var all_ok := cells.count(W.OK) == cells.size()
		var worst := W.OK
		for v in cells:
			if v != W.OK and (worst == W.OK or Placement.ORDER.find(v) < Placement.ORDER.find(worst)):
				worst = v
		if (why == W.OK) != all_ok or (why != W.OK and why != worst):
			bad += 1
		if why == W.OK:
			n_ok += 1
	SimHarness.check(bad == 0 and n_ok > 30, "600 мест (поворот 0..3): расхождений %d, годных %d" % [bad, n_ok])


func _test_ring_slots() -> void:
	print("[көч: места по кольцам]")
	var k := T.make()
	var nav: NavGrid = k["nav"]
	var econ: EconStub = k["econ"]
	var d: Defs = k["defs"]
	var center := Vector2(-60, 20)
	econ.spawn_building(1, d.building(&"koroo"), nav.snap(d.building(&"koroo"), Vector2(-115, 65), 3), 3)
	var bts := PackedInt32Array([d.building(&"ordo")])
	for i in 10:
		bts.append(d.building(&"boz"))
	bts.append(d.building(&"jylky"))
	bts.append(d.building(&"kurultai"))
	var slots := nav.ring_slots(1, center, bts)
	var rects: Array[Rect2i] = []
	var bad := 0
	for i in slots.size():
		var r := NavApi.footprint(d, bts[i], slots[i], 0, nav.origin)
		for q in rects:
			if q.intersects(r):
				bad += 1
		rects.append(r)
		var why := nav.check_place(1, bts[i], slots[i], 0)
		if why != W.OK:
			bad += 1
			print("    слот %d (%s) %s: %s" % [i, d.b_ids[bts[i]], str(slots[i]), _why_name(why)])
	SimHarness.check(slots.size() == bts.size() and bad == 0 and slots[0] == nav.snap(bts[0], center, 0),
		"%d мест: ставка в центре, без наложений, все можно поставить" % slots.size())
	var again := nav.ring_slots(1, center, bts)
	SimHarness.check(again == slots, "раскладка повторяется")
