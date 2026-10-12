class_name EconStub
extends EconApi
## Заглушка экономики (ARCHITECTURE §19.0 #8) для NAV и GAME до I2/I3:
##   • таблицы созданы; add_player кладёт стартовые ресурсы стороны (FactionDefs.start_res);
##   • spawn_* заполняют таблицы (здания штампуются в NavApi и зеркалятся в CombatPort, если они есть);
##   • place_site платит и создаёт стройку (SITE) — возвращает описатель; place_wall — звенья цепочки;
##   • прочие приказы только записываются в calls и возвращают OK; такты ничего не делают;
##   • запросы — значения по умолчанию (in_territory — true, node_near — ближайший узел по ресурсу).
## calls: [[имя, аргументы…], …] — для тестов маршрутизации приказов (Orders).

var defs: Defs
var rules := {}
var port: CombatPort
var nav: NavApi
var events: SimEvents
var seed_value := 1
var calls: Array = []
var _chain := 0


func setup(p_defs: Defs, p_rules: Dictionary, p_port: CombatPort, p_nav: NavApi, p_events: SimEvents, seed: int) -> void:
	defs = p_defs
	rules = p_rules
	port = p_port
	nav = p_nav
	events = p_events
	seed_value = seed
	players = PlayerTable.new()
	buildings = BuildingTable.new()
	nodes = NodeTable.new()
	herds = HerdTable.new()


func add_player(team: int, faction: StringName, ctrl: int) -> int:
	var f := defs.faction(faction)
	var p := players.add(team, f, ctrl, defs.R)
	for r in defs.R:
		players.res[p * defs.R + r] = defs.f_start_res[f * defs.R + r] if f >= 0 else 0
	return p


func spawn_building(p: int, btype: int, center: Vector2, rot_q: int, active := true) -> int:
	var B := buildings
	var b := B.alloc(BuildingTable.State.ACTIVE if active else BuildingTable.State.SITE)
	B.btype[b] = btype
	B.owner[b] = p
	B.team[b] = players.team[p] if p >= 0 and p < players.count else -1
	B.rot_q[b] = rot_q
	B.flags[b] = defs.b_flags[btype]
	B.x[b] = center.x
	B.z[b] = center.y
	B.rot[b] = rot_q * PI * 0.5
	B.hp_max_c[b] = defs.b_hp_c[btype]
	B.hp_c[b] = defs.b_hp_c[btype] if active else maxi(1, defs.b_hp_c[btype] / 10)
	B.progress[b] = 1000 if active else 0
	B.store_mask[b] = defs.b_accepts[btype]
	var o := nav.origin if nav else Vector2(-512.0, -512.0)
	var rect := NavApi.footprint(defs, btype, center, rot_q, o)
	B.c0[b] = rect.position.x
	B.r0[b] = rect.position.y
	B.cw[b] = rect.size.x
	B.ch[b] = rect.size.y
	var h := B.handle(b)
	if active and p >= 0 and p < players.count:
		players.pop_cap[p] = mini(players.pop_cap[p] + defs.b_pop_cap[btype], int(rules.get("pop_max", 500)))
		if defs.b_flags[btype] & Defs.BF_HQ:
			players.hq_b[p] = h
	if nav:
		nav.stamp_building(h, B.team[b], center, btype, rot_q)
	if port:
		var half := defs.b_size[btype] * 0.5
		if rot_q & 1:
			half = Vector2(half.y, half.x)
		port.structure_set(h, B.team[b], center, half, B.rot[b], _st_flags(btype, active))
	return h


func spawn_node(ntype: int, pos: Vector2, amount := -1, scatter_ref := -1) -> int:
	var N := nodes
	var n := N.alloc(ntype)
	N.res[n] = defs.n_res[ntype]
	N.amount_milli[n] = defs.n_amount_milli[ntype] if amount < 0 else amount
	N.workers_max[n] = defs.n_workers_max[ntype]
	N.scatter_ref[n] = scatter_ref
	N.cell[n] = nav.cell_of(pos) if nav else -1
	N.x[n] = pos.x
	N.z[n] = pos.y
	return N.handle(n)


func spawn_herd(p: int, htype: int, pen_h: int, heads: int) -> int:
	var H := herds
	var h := H.alloc(HerdTable.State.PEN)
	H.htype[h] = htype
	H.owner[h] = p
	H.pen_b[h] = pen_h
	H.heads_milli[h] = heads * 1000
	H.graze_r[h] = defs.h_graze_r[htype]
	if buildings.valid(pen_h):
		var b := buildings.slot(pen_h)
		H.x[h] = buildings.x[b]
		H.z[h] = buildings.z[b]
	return H.handle(h)


func spawn_worker(p: int, pos: Vector2) -> int:
	calls.append(["spawn_worker", p, pos])
	if port == null:
		return 0
	var f := players.faction[p]
	var u := defs.f_worker[f]
	players.pop_used[p] += defs.u_pop[u]
	return port.spawn(p, players.team[p], StringName(defs.unit_ids[u]), pos, 0.0)


func place_site(p: int, btype: int, center: Vector2, rot_q: int, workers: PackedInt32Array) -> int:
	calls.append(["place_site", p, btype, center, rot_q, workers])
	var cost := defs.building_cost(btype)
	if not can_pay(p, cost):
		return -Err.NO_RES
	if nav:
		var why := nav.check_place(p, btype, center, rot_q)
		if why != NavApi.Why.OK:
			return -(100 + why)
	_pay(p, cost)
	var h := spawn_building(p, btype, center, rot_q, false)
	if events:
		events.push(SimEvents.Ev.SITE_PLACED, p, h, btype, 0, center)
	return h


func place_wall(p: int, wtype: int, pts: PackedVector2Array, workers: PackedInt32Array) -> int:
	calls.append(["place_wall", p, wtype, pts, workers])
	if nav == null:
		return -Err.NOT_ALLOWED
	var plan := nav.plan_wall(p, wtype, pts)
	if not can_pay(p, plan["cost"]):
		return -Err.NO_RES
	_pay(p, plan["cost"])
	_chain += 1
	var centers: PackedVector2Array = plan["centers"]
	for i in centers.size():
		var h := spawn_building(p, wtype, centers[i], 0, false)
		var b := buildings.slot(h)
		buildings.chain[b] = _chain
		buildings.rot[b] = plan["rots"][i]
	return _chain


func assign_gather(p: int, workers: PackedInt32Array, source_h: int) -> int:
	calls.append(["assign_gather", p, workers, source_h])
	return Err.OK


func assign_build(p: int, workers: PackedInt32Array, b_h: int) -> int:
	calls.append(["assign_build", p, workers, b_h])
	return Err.OK


func train(p: int, b_h: int, utype: int, count: int) -> int:
	calls.append(["train", p, b_h, utype, count])
	return Err.OK


func cancel_train(p: int, b_h: int, index: int) -> int:
	calls.append(["cancel_train", p, b_h, index])
	return Err.OK


func set_rally(p: int, b_h: int, at: Vector2, target_h: int) -> int:
	calls.append(["set_rally", p, b_h, at, target_h])
	return Err.OK


func demolish(p: int, b_h: int) -> int:
	calls.append(["demolish", p, b_h])
	return Err.OK


func set_recipe(p: int, b_h: int, recipe: int) -> int:
	calls.append(["set_recipe", p, b_h, recipe])
	return Err.OK


func trade(p: int, b_h: int, give: int, take: int, amount_milli: int) -> int:
	calls.append(["trade", p, b_h, give, take, amount_milli])
	return Err.OK


func set_dam(p: int, b_h: int, open: bool) -> int:
	calls.append(["set_dam", p, b_h, open])
	return Err.OK


func pack(p: int, b_h: int) -> int:
	calls.append(["pack", p, b_h])
	return Err.OK


func pack_all(p: int, hq_h: int) -> int:
	calls.append(["pack_all", p, hq_h])
	return Err.OK


func unpack(p: int, arbas: PackedInt32Array, center: Vector2) -> int:
	calls.append(["unpack", p, arbas, center])
	return Err.OK


func herd_move(p: int, herd_h: int, to: Vector2) -> int:
	calls.append(["herd_move", p, herd_h, to])
	return Err.OK


func release_units(units: PackedInt32Array) -> void:
	calls.append(["release_units", units])


func pre_step(tick: int) -> void:
	pass


func post_step(tick: int, deaths: PackedInt32Array, hits: PackedInt32Array, arrivals: PackedInt32Array) -> void:
	pass


func slow_step(tick: int) -> void:
	pass


func fields_step(tick: int) -> void:
	pass


func res(p: int, r: int) -> int:
	return players.res[p * players.R + r]


func can_pay(p: int, cost: PackedInt32Array) -> bool:
	for r in cost.size():
		if cost[r] > players.res[p * players.R + r]:
			return false
	return true


func node_near(res_mask: int, pos: Vector2, r: float) -> int:
	var best := 0
	var bd := r * r
	for n in nodes.hw:
		if nodes.ntype[n] < 0 or nodes.amount_milli[n] == 0 or res_mask & (1 << nodes.res[n]) == 0:
			continue
		var d := Vector2(nodes.x[n], nodes.z[n]).distance_squared_to(pos)
		if d <= bd:
			bd = d
			best = nodes.handle(n)
	return best


func in_territory(p: int, pos: Vector2) -> bool:
	return true


func wall_link_at(p: int, pos: Vector2, r: float) -> int:
	return 0


func worker_job(u_h: int) -> int:
	return 0


func idle_workers(p: int) -> PackedInt32Array:
	return PackedInt32Array()


func arba_cargo(u_h: int) -> int:
	return 0


func grass_grid() -> PackedByteArray:
	return PackedByteArray()


func water_grid() -> PackedByteArray:
	return PackedByteArray()


func building_panel(b_h: int) -> Dictionary:
	return {}


func build_menu(p: int, tab: StringName) -> Array[Dictionary]:
	return []


func checksum() -> int:
	var h := 23
	for v in players.res:
		h = (h * 31 + v) & 0x7FFFFFFF
	for b in buildings.hw:
		h = (h * 31 + buildings.state[b] * 7 + buildings.progress[b]) & 0x7FFFFFFF
	return h


func save_into(d: Dictionary) -> void:
	d["econ_stub"] = {"res": players.res.duplicate(), "chain": _chain}


func load_from(d: Dictionary) -> void:
	var st: Dictionary = d.get("econ_stub", {})
	if st.has("res"):
		players.res = st["res"].duplicate()
	_chain = int(st.get("chain", 0))


func _pay(p: int, cost: PackedInt32Array) -> void:
	for r in cost.size():
		players.res[p * players.R + r] -= cost[r]


## Флаги структуры ядра (BattleSim.ST_*: BLOCK 1, WALL 2, GATE 4, TOWER 8, FIELD 16, HQ 32, SITE 64)
func _st_flags(btype: int, active: bool) -> int:
	var f := 0
	match defs.b_kind[btype]:
		Defs.BKind.WALL: f |= 2
		Defs.BKind.GATE: f |= 4
		Defs.BKind.TOWER: f |= 8
		Defs.BKind.FIELD: f |= 16
	if defs.b_flags[btype] & Defs.BF_BLOCKS:
		f |= 1
	if defs.b_flags[btype] & Defs.BF_HQ:
		f |= 32
	if not active:
		f |= 64
	return f
