class_name MapSetup
## Расстановка карты «Города» в начале игры (ARCHITECTURE §7.4; ТЗ 8; ECONOMY §1.1, §12.1).
## Порядок (детерминирован): игроки (EconApi.add_player) → деревья из ScatterData (порядок файла →
## scatter_ref) → жилы → у каждого игрока ставка, стартовые постройки и линии (Бош ариқ), стада загонов,
## стартовые работники → у игроков ИИ — база (AiDefs.BASE: постройки по site.layout, иначе поиском места),
## табун, отряды защиты (AiDefs.GARRISON) и контроллеры ИИ (GarrisonAi, RaidDirector).
## Места: игрок берёт первое свободное место своей стороны, иначе любое свободное.

const CLEAR_R := 26.0            # деревья ближе к ставке не ставятся (поляна под ставку)
const SEARCH_STEP := 8.0         # шаг поиска места для базы ИИ, м
const SEARCH_MAX_R := 150.0
const GARRISON_TOWERS := false   # этап 2 (R16): лучники в башнях; пока отряд стоит у башни
## Причины места, которые готовой базе ИИ не мешают (см. _free_spot)
const FREE_WHY := [NavApi.Why.OK, NavApi.Why.NO_RES, NavApi.Why.NOT_NEAR, NavApi.Why.NO_TERRITORY]


## Для CombatPort.setup: точки «домой» по командам (ставка первого игрока команды)
static func homes(map: Dictionary, players: Array) -> PackedVector2Array:
	var sites := assign_sites(map, players)
	var out := PackedVector2Array()
	for i in players.size():
		var team := int(players[i].get("team", i))
		while out.size() <= team:
			out.append(Vector2.ZERO)
		if sites[i] >= 0 and out[team] == Vector2.ZERO:
			out[team] = map["sites"][sites[i]]["hq"]
	return out


## Место (индекс map.sites) для каждого игрока; −1 — мест не хватило
static func assign_sites(map: Dictionary, players: Array) -> PackedInt32Array:
	var sites: Array = map.get("sites", [])
	var used := PackedByteArray()
	used.resize(sites.size())
	var out := PackedInt32Array()
	out.resize(players.size())
	out.fill(-1)
	for i in players.size():
		var f := String(players[i].get("faction", ""))
		for s in sites.size():
			if used[s] == 0 and String(sites[s].get("faction", "")) == f:
				used[s] = 1
				out[i] = s
				break
	for i in players.size():
		if out[i] >= 0:
			continue
		for s in sites.size():
			if used[s] == 0:
				used[s] = 1
				out[i] = s
				break
	return out


static func populate(game: GameSim, map: Dictionary, players: Array) -> void:
	var defs := game.defs
	var econ := game.econ
	var sites := assign_sites(map, players)
	var ids := PackedInt32Array()
	for i in players.size():
		var pc: Dictionary = players[i]
		ids.append(econ.add_player(int(pc.get("team", i)), StringName(str(pc.get("faction", "kokand"))),
			int(pc.get("ctrl", PlayerTable.Ctrl.HUMAN))))
	var hqs := PackedVector2Array()
	for i in players.size():
		hqs.append(map["sites"][sites[i]]["hq"] if sites[i] >= 0 else Vector2.INF)
	_spawn_trees(game, map, hqs)
	_spawn_deposits(game, map)
	var garrison := {}
	for i in players.size():
		if sites[i] < 0:
			push_warning("MapSetup: нет места для игрока %d" % i)
			continue
		var site: Dictionary = map["sites"][sites[i]]
		_spawn_base(game, ids[i], site)
		if int(players[i].get("ctrl", PlayerTable.Ctrl.HUMAN)) == PlayerTable.Ctrl.AI:
			garrison[i] = _spawn_ai_base(game, ids[i], site, map)
	# контроллеры ИИ — после всех баз (враг уже есть)
	for i in players.size():
		if not garrison.has(i):
			continue
		var p := ids[i]
		var site: Dictionary = map["sites"][sites[i]]
		var g: Dictionary = garrison[i]
		var gc: Dictionary = defs.ai.get("GARRISON", {})
		var gai := GarrisonAi.new()
		gai.setup(p, {"home": site["hq"], "base_r": float(gc.get("base_r", 90.0)), "squads": g["squads"],
			"posts": g["posts"], "period": int(gc.get("period", 30)), "phase": (p * 7 + 3) % int(gc.get("period", 30))},
			game.seed)
		game.ai.append(gai)
		if bool(game.rules.get("raids", false)):
			var raid: Dictionary = defs.ai.get("RAID", {})
			var rd := RaidDirector.new()
			var edges := PackedVector2Array()
			for e: Vector2 in map.get("raid_edges", []):
				edges.append(e)
			rd.setup(p, {"raid": raid, "difficulty": int(players[i].get("difficulty", 0)),
				"faction": econ.players.faction[p], "edges": edges, "bounds": map.get("bounds", Rect2(-512, -512, 1024, 1024)),
				"enemy": _enemy_of(econ.players, p), "phase": (p * 7 + 17) % int(raid.get("period", 30))}, game.seed)
			game.ai.append(rd)


# ================================================================= мир

static func _spawn_trees(game: GameSim, map: Dictionary, hqs: PackedVector2Array) -> void:
	if String(map.get("trees", "")) != "scatter":
		return
	var defs := game.defs
	var by_kind := PackedInt32Array()
	by_kind.resize(ScatterData.KINDS.size())
	by_kind.fill(-1)
	for n in defs.n_ids.size():
		var k := defs.n_scatter_kind[n]
		if k >= 0 and k < by_kind.size() and defs.n_enabled[n] == 1:
			by_kind[k] = n
	var r2 := CLEAR_R * CLEAR_R
	for t: Array in ScatterData.trees():
		var kind := int(t[0])
		var nt := by_kind[kind] if kind >= 0 and kind < by_kind.size() else -1
		if nt < 0:
			continue
		var p := Vector2(float(t[2]), float(t[3]))
		var near := false
		for c in hqs:
			if c.distance_squared_to(p) < r2:
				near = true
				break
		if not near:
			game.econ.spawn_node(nt, p, -1, ScatterData.ref(kind, int(t[1])))


static func _spawn_deposits(game: GameSim, map: Dictionary) -> void:
	var defs := game.defs
	for it: Array in map.get("deposits", []):
		var nt := defs.node(StringName(str(it[0])))
		if nt < 0 or defs.n_enabled[nt] == 0:
			continue
		var amount := int(it[2]) if it.size() > 2 else -1
		game.econ.spawn_node(nt, it[1], amount * 1000 if amount >= 0 else -1, -1)


# ================================================================= база игрока

static func _spawn_base(game: GameSim, p: int, site: Dictionary) -> void:
	var defs := game.defs
	var econ := game.econ
	var P := econ.players
	var f := P.faction[p]
	var fid := defs.f_ids[f]
	var hq := econ.spawn_building(p, defs.f_hq[f], site["hq"], int(site.get("hq_rot_q", 0)), true)
	_herd_for(game, p, hq)
	for it: Array in site.get("buildings", []):
		var bt := defs.building(StringName(str(it[0])))
		if bt < 0 or (defs.b_faction[bt] != "" and defs.b_faction[bt] != fid):
			continue
		var b := econ.spawn_building(p, bt, it[1], int(it[2]), true)
		_herd_for(game, p, b)
	for it: Array in site.get("links", []):
		var bt := defs.building(StringName(str(it[0])))
		if bt < 0 or (defs.b_faction[bt] != "" and defs.b_faction[bt] != fid):
			continue
		var pts := PackedVector2Array()
		for v: Vector2 in it[1]:
			pts.append(v)
		_spawn_link(game, p, bt, pts)
	# стартовые юниты: работники — через ECON (он их ведёт), прочие — сразу в ядро
	var at: Vector2 = site.get("workers", site["hq"])
	var su: PackedInt32Array = defs.f_start_units[f]
	var k := 0
	for i in range(0, su.size(), 2):
		var u := su[i]
		for j in su[i + 1]:
			var pos := at + Vector2((k % 4) * 2.0 - 3.0, (k / 4) * 2.0)
			k += 1
			if u == defs.f_worker[f]:
				econ.spawn_worker(p, pos)
			else:
				var h := game.port.spawn(p, P.team[p], StringName(defs.unit_ids[u]), pos, 0.0)
				game.events.push(SimEvents.Ev.UNIT_SPAWNED, p, h, hq, u, pos)


## Стадо загона: heads < 0 — стартовое (короо — отара 40, ставка кыпчаков — 6 коней на коновязи), если
## ECON сам не завёл его в spawn_building; heads ≥ 0 — задать число голов (EconomySim.spawn_herd у загона
## со стадом задаёт число, заглушка — заводит стадо)
static func _herd_for(game: GameSim, p: int, b_h: int, heads := -1) -> void:
	var defs := game.defs
	var B := game.econ.buildings
	if not B.valid(b_h):
		return
	var bt := B.btype[B.slot(b_h)]
	var ht := defs.b_herd[bt]
	var n := heads if heads >= 0 else defs.b_herd_start[bt]
	if ht < 0 or n <= 0:
		return
	if heads < 0:
		var H := game.econ.herds
		for h in H.hw:
			if H.state[h] != HerdTable.State.FREE and H.pen_b[h] == b_h:
				return
	game.econ.spawn_herd(p, ht, b_h, n)


## Линия с начала (Бош ариқ): EconomySim.spawn_links (готовые звенья даром; просьба внести в договор),
## иначе звенья постройками по шагу plan_wall с четвертью оборота по направлению отрезка
static func _spawn_link(game: GameSim, p: int, bt: int, pts: PackedVector2Array) -> void:
	if game.econ.has_method("spawn_links"):
		game.econ.call("spawn_links", p, bt, pts)
		return
	var plan := game.nav.plan_wall(p, bt, pts)
	var centers: PackedVector2Array = plan.get("centers", PackedVector2Array())
	var seg := 0
	for c in centers:
		# отрезок, на котором лежит центр звена
		while seg < pts.size() - 2 and _t_on(pts[seg], pts[seg + 1], c) > 1.0:
			seg += 1
		var d := pts[seg + 1] - pts[seg]
		game.econ.spawn_building(p, bt, c, 0 if absf(d.x) >= absf(d.y) else 1, true)


static func _t_on(a: Vector2, b: Vector2, c: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	return (c - a).dot(ab) / l2 if l2 > 0.0 else 0.0


# ================================================================= база ИИ

## Постройки AiDefs.BASE, табун, отряды защиты. Возвращает {squads, posts} для GarrisonAi.
static func _spawn_ai_base(game: GameSim, p: int, site: Dictionary, map: Dictionary) -> Dictionary:
	var defs := game.defs
	var econ := game.econ
	var P := econ.players
	var fid := defs.f_ids[P.faction[p]]
	var base: Dictionary = defs.ai.get("BASE", {}).get(fid, {})
	var hq: Vector2 = site["hq"]
	var want := {}
	for id: Variant in base.get("buildings", {}):
		want[String(id)] = int(base["buildings"][id])
	for id: Variant in base.get("towers", {}):
		want[String(id)] = int(base["towers"][id])
	# уже стоят (стартовые)
	var have := {}
	var B := econ.buildings
	for b in B.hw:
		if B.owner[b] == p and B.state[b] != BuildingTable.State.FREE:
			var id := defs.b_ids[B.btype[b]]
			have[id] = int(have.get(id, 0)) + 1
	# сначала места из layout по порядку, потом поиск
	var placed: Array = []          # [id, handle]
	for it: Array in site.get("layout", []):
		var id := String(it[0])
		if int(have.get(id, 0)) >= int(want.get(id, 0)):
			continue
		var h := _place(game, p, defs.building(StringName(id)), it[1], int(it[2]), hq)
		if h != Ids.NULL:
			have[id] = int(have.get(id, 0)) + 1
			placed.append([id, h])
	var offs: Array = map.get("ai_base", {}).get("tower_offsets", [])
	var to := 0
	for id: String in want:
		var bt := defs.building(StringName(id))
		if bt < 0:
			continue
		while int(have.get(id, 0)) < int(want[id]):
			var guess := hq
			if defs.b_kind[bt] == Defs.BKind.TOWER and to < offs.size():
				guess = hq + offs[to]
				to += 1
			var h := _place(game, p, bt, guess, 0, hq)
			have[id] = int(have.get(id, 0)) + 1          # не нашли места — пропускаем, без зацикливания
			if h != Ids.NULL:
				placed.append([id, h])
	for pair: Array in placed:
		_herd_for(game, p, pair[1])
	# табун (AiDefs.BASE.herds): поровну по своим загонам этого стада
	for hid: Variant in base.get("herds", {}):
		var ht := defs.herd(StringName(str(hid)))
		var total := int(base["herds"][hid])
		var pens := PackedInt32Array()
		for b in B.hw:
			if B.owner[b] == p and B.state[b] == BuildingTable.State.ACTIVE and defs.b_herd[B.btype[b]] == ht \
					and defs.b_flags[B.btype[b]] & Defs.BF_HQ == 0:
				pens.append(B.handle(b))
		for i in pens.size():
			var share := total / pens.size() + (1 if i < total % pens.size() else 0)
			_herd_for(game, p, pens[i], share)
	# отряды защиты у ставки (лицом к врагу) и у башен
	var squads := PackedInt32Array()
	var posts := PackedVector2Array()
	var enemy := _enemy_of(P, p)
	var face := Vector2(1, 0)
	if enemy >= 0 and P.hq_b[enemy] != Ids.NULL and B.valid(P.hq_b[enemy]):
		var eb := B.slot(P.hq_b[enemy])
		face = Vector2(B.x[eb], B.z[eb]) - hq
	var heading := AiController.cardinal(face)
	var fwd := Vector2(1, 0) if absf(face.x) >= absf(face.y) else Vector2(0, 1)
	if (fwd.x != 0.0 and face.x < 0.0) or (fwd.y != 0.0 and face.y < 0.0):
		fwd = -fwd
	var side := Vector2(-fwd.y, fwd.x)
	var gc: Dictionary = defs.ai.get("GARRISON", {})
	var k := 0
	for id: Variant in gc.get("squads", {}).get(fid, {}):
		var n := int(gc["squads"][fid][id])
		var post := hq + fwd * 22.0 + side * ((k % 2) * 2 - 1) * 14.0 * (1 + k / 2)
		var s := game.port.spawn_squad(p, P.team[p], StringName(str(id)), n, post, heading)
		_spawned(game, p, s, P.hq_b[p])
		squads.append(s)
		posts.append(post)
		k += 1
	for tid: Variant in base.get("tower_garrison", {}):
		var n := int(base["tower_garrison"][tid])
		for pair: Array in placed:
			var b_h: int = pair[1]
			if defs.b_kind[B.btype[B.slot(b_h)]] != Defs.BKind.TOWER:
				continue
			var tb := B.slot(b_h)
			var post := Vector2(B.x[tb], B.z[tb]) + fwd * 8.0
			var s := game.port.spawn_squad(p, P.team[p], StringName(str(tid)), n, post, heading)
			_spawned(game, p, s, b_h)
			if GARRISON_TOWERS:
				game.port.garrison(game.port.members(s), b_h)
			squads.append(s)
			posts.append(post)
	return {"squads": squads, "posts": posts}


## Поставить постройку базы ИИ: в точке (прижатой к сетке), иначе по спирали вокруг неё (шаг 8 м, до 150 м)
static func _place(game: GameSim, p: int, bt: int, at: Vector2, rot_q: int, hq: Vector2) -> int:
	if bt < 0 or game.defs.b_enabled[bt] == 0:
		return Ids.NULL
	var nav := game.nav
	var c := nav.snap(bt, at, rot_q)
	if _free_spot(nav, p, bt, c, rot_q):
		return game.econ.spawn_building(p, bt, c, rot_q, true)
	var rings := int(SEARCH_MAX_R / SEARCH_STEP)
	for ring in range(1, rings + 1):
		# квадратное кольцо: обход по сторонам, начиная с северо-запада (детерминированно)
		for i in ring * 8:
			var side := i / (ring * 2)
			var t := i % (ring * 2)
			var d := Vector2.ZERO
			match side:
				0: d = Vector2(-ring + t, -ring)
				1: d = Vector2(ring, -ring + t)
				2: d = Vector2(ring - t, ring)
				_: d = Vector2(-ring, ring - t)
			var q := nav.snap(bt, at + d * SEARCH_STEP, rot_q)
			if q.distance_squared_to(hq) < 20.0 * 20.0:
				continue
			if _free_spot(nav, p, bt, q, rot_q):
				return game.econ.spawn_building(p, bt, q, rot_q, true)
	return Ids.NULL


## Место для готовой постройки базы ИИ: годится по земле (карта, наложение, вода, уклон, на стене, враг).
## Правила хозяйства игрока здесь не в счёт — база ставится даром до первого такта: NO_RES (у ИИ нет кирпича
## на бурж), NOT_NEAR (зону воды Хумдона ECON считает позже, в шаге), NO_TERRITORY.
static func _free_spot(nav: NavApi, p: int, bt: int, c: Vector2, rot_q: int) -> bool:
	var why := nav.check_place(p, bt, c, rot_q)
	if why == NavApi.Why.OK:
		return true
	if not FREE_WHY.has(why):
		return false
	var cells := nav.place_cells(p, bt, c, rot_q)
	for v in cells:
		if not FREE_WHY.has(int(v)):
			return false
	return not cells.is_empty()


static func _spawned(game: GameSim, p: int, s_h: int, from_b: int) -> void:
	for m in game.port.members(s_h):
		game.events.push(SimEvents.Ev.UNIT_SPAWNED, p, m, from_b, game.defs.unit(game.port.type_id(m)), game.port.pos(m))


static func _enemy_of(P: PlayerTable, p: int) -> int:
	for e in P.count:
		if P.team[e] != P.team[p] and P.ctrl[e] != PlayerTable.Ctrl.NONE:
			return e
	return -1
