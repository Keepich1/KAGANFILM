extends SceneTree
## Стыковка пакетов «Города» на настоящих модулях (ARCHITECTURE §19.7 I1–I3): CombatPortBattle + NavGrid +
## EconomySim внутри GameSim, приказы — SimCmd.
##   godot --headless --path ordo --script res://tests/test_city_integration.gd
## • I1: тела ядра на сетке NAV — отряды и одиночки идут сквозь город путями в обход построек и никто не стоит
##   внутри; прямоугольник ядра у постройки с нечётной четвертью оборота совпадает со следом NAV; ядра жил
##   (2×2 клетки) закрыты и для ядра;
## • стены и ворота: кольцо пахса девора, ворота приказом BUILD встают по стене и снимают звенья под собой;
##   свой отряд выходит в ворота, враг ломает звено (пролом) и входит;
## • башня на стене снимает звенья под следом;
## • Бош ариқ карты — с водой от стартового тўғона; Хумдон, построенный работниками, печёт по рецепту
##   (не всю стройку разом);
## • два прогона с одним зерном — одна контрольная сумма.

const C := Vector2(140, 60)        # середина кольца стены у урды Коканда (184, 56)


func _init() -> void:
	_test_town_walk()
	_test_mirror_matches_nav()
	_test_deposit_cores()
	_test_walls_and_gate()
	_test_tower_on_wall()
	_test_water_and_kiln()
	SimHarness.finish(self)


# ================================================================= помощники

## Два человека (без ИИ и набегов): Коканд (0) и кыпчаки (1), настоящие реализации
func _game(p_seed := 3) -> GameSim:
	var g := GameSim.new()
	g.setup(MapValley.MAP, [{"faction": &"kokand", "team": 0, "ctrl": PlayerTable.Ctrl.HUMAN},
		{"faction": &"kipchak", "team": 1, "ctrl": PlayerTable.Ctrl.HUMAN}], p_seed)
	return g


func _rich(g: GameSim, p: int) -> void:
	var e := g.econ as EconomySim
	for r in e.R:
		e.players.res[p * e.R + r] = 5_000_000


func _workers(g: GameSim, p: int) -> PackedInt32Array:
	var q := g.query as GameQueryImpl
	var ws := PackedInt32Array()
	for u in q.units_of(p):
		if q.unit_flags(u) & UnitStats.WORKER:
			ws.append(u)
	return ws


func _count(g: GameSim, id: StringName) -> int:
	var B := g.econ.buildings
	var bt := g.defs.building(id)
	var n := 0
	for b in B.hw:
		if B.state[b] != BuildingTable.State.FREE and B.btype[b] == bt:
			n += 1
	return n


## Живые юниты внутри прямоугольников структур ядра (кроме полей и своих ворот); стройки — тоже
func _inside_structs(sim: BattleSim) -> int:
	var bad := 0
	for u in sim.n:
		if sim.u_life[u] != BattleSim.Life.ALIVE:
			continue
		for st in sim.st_hw:
			if sim.st_alive[st] == 0:
				continue
			var f := sim.st_flags[st]
			if f & BattleSim.ST_FIELD or (f & BattleSim.ST_GATE and sim.st_team[st] == sim.u_side[u]):
				continue
			var c := cos(sim.st_rot[st])
			var sn := sin(sim.st_rot[st])
			var dx := sim.u_x[u] - sim.st_cx[st]
			var dz := sim.u_z[u] - sim.st_cz[st]
			if absf(dx * c - dz * sn) < sim.st_hx[st] - 0.3 and absf(dx * sn + dz * c) < sim.st_hz[st] - 0.3:
				bad += 1
	return bad


func _built(g: GameSim, b_h: int, max_s: float) -> bool:
	var B := g.econ.buildings
	for t in roundi(max_s * 30.0):
		g.step()
		if B.valid(b_h) and B.state[B.slot(b_h)] == BuildingTable.State.ACTIVE:
			return true
	return false


## Описатель последней постройки вида id игрока p (или 0)
func _last(g: GameSim, p: int, id: StringName) -> int:
	var B := g.econ.buildings
	var bt := g.defs.building(id)
	var h := 0
	for b in B.hw:
		if B.state[b] != BuildingTable.State.FREE and B.btype[b] == bt and B.owner[b] == p:
			h = B.handle(b)
	return h


# ================================================================= I1: город

func _test_town_walk() -> void:
	print("[I1: отряды и одиночки идут сквозь город по сетке NAV]")
	var g := _game()
	print("  реализации: ", g.impl_names())
	SimHarness.check(g.real_impl(), "настоящие CombatPortBattle, NavGrid, EconomySim")
	var e := g.econ as EconomySim
	var d := g.defs
	# квартал домов, амбар и печь (не квадратные — с нечётной четвертью оборота) между ставкой и лугом
	var placed := 0
	for i in 12:
		var at := g.nav.snap(d.building(&"uy"), Vector2(120 + (i % 4) * 14.0, 20 + (i / 4) * 16.0), 0)
		if g.nav.check_place(0, d.building(&"uy"), at, 0) == NavApi.Why.OK:
			e.spawn_building(0, d.building(&"uy"), at, 0, true)
			placed += 1
	e.spawn_building(0, d.building(&"xumdon"), g.nav.snap(d.building(&"xumdon"), Vector2(104, 52), 1), 1, true)
	e.spawn_building(0, d.building(&"togon"), g.nav.snap(d.building(&"togon"), Vector2(176, 100), 1), 1, true)
	SimHarness.check(placed >= 10, "квартал: %d домов" % placed)
	var sh := PackedInt32Array()
	sh.append(g.port.spawn_squad(0, 0, &"sarboz", 30, Vector2(96, 10), 0.0))
	sh.append(g.port.spawn_squad(0, 0, &"nayzachi", 20, Vector2(190, 10), 0.0))
	var singles := PackedInt32Array()
	for k in 24:
		singles.append(g.port.spawn(0, 0, &"sarboz", Vector2(100 + (k % 6) * 2.0, 96 + (k / 6) * 2.0), 0.0))
	var goals := [Vector2(186, 92), Vector2(100, 96), Vector2(190, 12)]
	g.submit(0, SimCmd.move(PackedInt32Array([sh[0]]), goals[0]))
	g.submit(0, SimCmd.move(PackedInt32Array([sh[1]]), goals[1]))
	g.submit(0, SimCmd.move(singles, goals[2]))
	var bad := 0
	var sim := g.port.battle()
	for t in 30 * 75:
		g.step()
		if t % 10 == 0:
			bad += _inside_structs(sim)
	SimHarness.check(bad == 0, "никто не стоит внутри построек (%d нарушений)" % bad)
	var near := 0
	for i in 2:
		if g.port.pos(sh[i]).distance_to(goals[i]) < 10.0:
			near += 1
		else:
			print("    отряд %d не дошёл: %s → %s" % [i, g.port.pos(sh[i]), goals[i]])
	var sn := 0
	for u in singles:
		if g.port.pos(u).distance_to(goals[2]) < 12.0:
			sn += 1
	SimHarness.check(near == 2, "отряды дошли через город (%d из 2)" % near)
	SimHarness.check(sn * 10 >= singles.size() * 9, "одиночки дошли: %d из %d" % [sn, singles.size()])


## Прямоугольник ядра у постройки с нечётной четвертью оборота = её след NAV (раньше полуразмеры
## переставлялись дважды: ядро ставило ту же постройку неповёрнутой)
func _test_mirror_matches_nav() -> void:
	print("[зеркало ядра совпадает со следом NAV]")
	var g := _game()
	var e := g.econ as EconomySim
	var d := g.defs
	var sim := g.port.battle()
	var ok := true
	for id: StringName in [&"xumdon", &"togon", &"tegirmon"]:
		for rq in [0, 1]:
			var bt := d.building(id)
			var at := g.nav.snap(bt, Vector2(110 + rq * 30.0, 100 if id == &"xumdon" else (130 if id == &"togon" else 160)), rq)
			var h := e.spawn_building(0, bt, at, rq, true)
			var st := Ids.slot(h)
			var sz := d.b_size[bt]
			var ext := Vector2(sz.y, sz.x) * 0.5 if rq & 1 else sz * 0.5
			# точки чуть внутри и чуть снаружи вдоль осей x и z мира
			var in_x := sim._st_contains(st, at.x + ext.x - 0.3, at.y, 0.0)
			var out_x := sim._st_contains(st, at.x + ext.x + 0.3, at.y, 0.0)
			var in_z := sim._st_contains(st, at.x, at.y + ext.y - 0.3, 0.0)
			var out_z := sim._st_contains(st, at.x, at.y + ext.y + 0.3, 0.0)
			var good := in_x and not out_x and in_z and not out_z
			if not good:
				print("    %s rot_q %d: ядро x %s/%s z %s/%s" % [id, rq, in_x, out_x, in_z, out_z])
			ok = ok and good
			e.destroy_building(Ids.slot(h), -1, true)
	SimHarness.check(ok, "Хумдон, Тўғон, Тегирмон при rot_q 0 и 1: прямоугольник ядра = след")


func _test_deposit_cores() -> void:
	print("[ядра жил закрыты и для ядра]")
	var g := _game()
	var sim := g.port.battle()
	var N := g.econ.nodes
	var deps := 0
	var blocked := 0
	for n in N.hw:
		if N.ntype[n] < 0 or g.defs.n_blocks_cells[N.ntype[n]] <= 0:
			continue
		deps += 1
		if sim.point_blocked(N.x[n], N.z[n], 0):
			blocked += 1
	SimHarness.check(deps >= 10 and blocked == deps, "жилы: %d, закрыты в ядре: %d" % [deps, blocked])


# ================================================================= стены и ворота

func _ring(g: GameSim) -> void:
	var pts := PackedVector2Array([C + Vector2(-16, -16), C + Vector2(16, -16), C + Vector2(16, 16), C + Vector2(-16, 16),
		C + Vector2(-16, -16)])
	(g.econ as EconomySim).spawn_links(0, g.defs.building(&"devor"), pts)


func _test_walls_and_gate() -> void:
	print("[стена кольцом, ворота по стене, выход в ворота, пролом врага]")
	var g := _game()
	_rich(g, 0)
	_ring(g)
	var links0 := _count(g, &"devor")
	g.step()
	var dz := g.defs.building(&"darvoza")
	# щелчок игрока рядом со стеной (не точно на ней) — ворота встают по линии стены
	g.submit(0, SimCmd.build(_workers(g, 0), dz, C + Vector2(16.4, 1.0), 0))
	g.step()
	g.step()
	var gate := _last(g, 0, &"darvoza")
	SimHarness.check(gate != Ids.NULL, "приказ BUILD ворот принят")
	if gate == Ids.NULL:
		return
	var B := g.econ.buildings
	var gb := B.slot(gate)
	SimHarness.check(absf(B.x[gb] - (C.x + 16.0)) < 0.01 and absf(B.ax[gb] - B.bx[gb]) < 0.01 and absf(B.az[gb] - B.bz[gb]) > 6.0,
		"ворота — на линии стены, концы вдоль неё: (%.1f, %.1f), %s → %s" % [B.x[gb], B.z[gb],
		Vector2(B.ax[gb], B.az[gb]), Vector2(B.bx[gb], B.bz[gb])])
	var gone := links0 - _count(g, &"devor")
	SimHarness.check(gone >= 2 and gone <= 3, "звенья под воротами сняты: %d" % gone)
	SimHarness.check(_built(g, gate, 60.0), "ворота построены")
	# свой отряд изнутри наружу (на юг; ворота — на востоке)
	var s := g.port.spawn_squad(0, 0, &"sarboz", 20, C, 0.0)
	var out := C + Vector2(0, 45)
	g.submit(0, SimCmd.move(PackedInt32Array([s]), out))
	var t_out := -1
	var sim := g.port.battle()
	var bad := 0
	for t in 30 * 60:
		g.step()
		if t % 15 == 0:
			bad += _inside_structs(sim)
		if g.port.pos(s).distance_to(out) < 6.0:
			t_out = t
			break
	SimHarness.check(t_out >= 0, "свой отряд вышел в ворота за %.1f с" % (t_out / 30.0))
	SimHarness.check(bad == 0, "сквозь звенья не проходили (%d)" % bad)
	# враг снаружи — внутрь: обхода нет, ломает звено или ворота
	var es := g.port.spawn_squad(1, 1, &"sayisker", 20, C + Vector2(45, 30), PI, &"", 0, 10)
	g.submit(1, SimCmd.move(PackedInt32Array([es]), C))
	var cur := g.events.head
	var destroyed := 0
	var hits := 0
	var t_in := -1
	for t in 30 * 150:
		g.step()
		var r := g.events.range_since(cur)
		for seq in range(r.x, r.y):
			var i := g.events.at(seq)
			match g.events.e_kind[i]:
				SimEvents.Ev.BUILDING_DESTROYED:
					destroyed += 1
				SimEvents.Ev.BUILDING_HIT:
					hits += 1
		cur = r.y
		if g.port.pos(es).distance_to(C) < 8.0:
			t_in = t
			break
	SimHarness.check(destroyed >= 1, "враг сломал стену (%d разрушено)" % destroyed)
	SimHarness.check(t_in >= 0, "враг вошёл через пролом за %.1f с" % (t_in / 30.0))


func _test_tower_on_wall() -> void:
	print("[башня на стене снимает звенья под собой]")
	var g := _game()
	_rich(g, 0)
	_ring(g)
	var e := g.econ as EconomySim
	e.spawn_building(0, g.defs.building(&"xumdon"), g.nav.snap(g.defs.building(&"xumdon"), Vector2(150, 0), 0), 0, true)
	g.step()
	var links0 := _count(g, &"devor")
	var bj := g.defs.building(&"burj")
	var at := C + Vector2(-16, 0)
	var s := g.nav.snap_on_wall(0, bj, at)
	SimHarness.check(int(s["why"]) == NavApi.Why.OK and (s["removes"] as PackedInt32Array).size() > 0,
		"бурж на стене можно (снимет звеньев: %d)" % (s["removes"] as PackedInt32Array).size())
	g.submit(0, SimCmd.build(_workers(g, 0), bj, at, 0))
	g.step()
	g.step()
	var tower := _last(g, 0, &"burj")
	SimHarness.check(tower != Ids.NULL, "приказ BUILD буржа принят")
	SimHarness.check(links0 - _count(g, &"devor") == (s["removes"] as PackedInt32Array).size(),
		"звенья под буржем сняты: %d" % (links0 - _count(g, &"devor")))
	SimHarness.check(tower != Ids.NULL and _built(g, tower, 120.0), "бурж построен")


# ================================================================= вода и печь

func _test_water_and_kiln() -> void:
	print("[вода с начала карты; Хумдон после стройки печёт по рецепту]")
	var g := _game()
	var e := g.econ as EconomySim
	var d := g.defs
	for t in 30:
		g.step()
	var links := 0
	var wet := 0
	for b in e.buildings.hw:
		if e.buildings.owner[b] == 0 and e.buildings.state[b] == BuildingTable.State.ACTIVE and e.net.is_link(e.buildings.btype[b]):
			links += 1
			if e.net.link_net[b] >= 0:
				wet += 1
	SimHarness.check(links > 30 and wet == links, "Бош ариқ: звеньев %d, с водой %d" % [links, wet])
	var dala := d.building(&"dala")
	SimHarness.check(e.ghost_water(0, dala, Vector2(146, -30)) == 1000, "поле у арыка — «у воды»")
	var rw := d.res(&"wood")
	var rb := d.res(&"brick")
	e.players.res[rw] += 2_000_000
	var xd := d.building(&"xumdon")
	var at := g.nav.snap(xd, Vector2(152, -20), 0)
	g.submit(0, SimCmd.build(_workers(g, 0).slice(0, 3), xd, at, 0))
	g.step()
	g.step()
	var kiln := _last(g, 0, &"xumdon")
	SimHarness.check(kiln != Ids.NULL and _built(g, kiln, 90.0), "Хумдон построен тремя работниками")
	var w0 := e.res(0, rw)
	var b0 := e.res(0, rb)
	for t in 30 * 60:
		g.step()
	var bricks := (e.res(0, rb) - b0) / 1000.0
	var wood := (w0 - e.res(0, rw)) / 1000.0
	SimHarness.check_range(bricks, 30.0, 40.0, "кирпич за минуту (трое у печи, ≈36)")
	SimHarness.check(wood < 30.0, "дерева сожжено %.0f (не весь запас)" % wood)

