class_name GameQueryImpl
extends GameQuery
## Окно чтения настоящего «Города» (ARCHITECTURE §7.5) для VIEW, UI и ИИ: GameSim + его порт, навигация и
## экономика. Только чтение. Юниты — через CombatPort (работает и на заглушке, где ядра нет); полоски HP,
## морали и выносливости — из массивов ядра, когда оно есть (battle() != null).
## Панель здания и меню стройки отдаёт ECON (EconApi.building_panel / build_menu); пока ECON — заглушка и
## отдаёт пустое, здесь — запасной вариант по Defs (как в FakeCity).
## Сверх договора (для ИИ GAME): unit_pos/unit_alive/unit_owner/unit_flags/units_near/is_idle/squad_of/members,
## is_defeated, rules.

const HOTKEYS := ["Q", "W", "E", "R", "T", "A", "S", "D", "F", "G", "Z", "X", "C", "V"]
const ALL_R := 1.0e6            # «вся карта» для units_near

var _defs: Defs
var _rules := {}
var _port: CombatPort
var _nav: NavApi
var _econ: EconApi
var _events: SimEvents
var _victory: Victory
var _ai: Array[AiController] = []
var _buf := PackedInt32Array()


## Части игры (без ссылки на сам GameSim — иначе цикл ссылок RefCounted)
func _init(p_game: GameSim = null) -> void:
	if p_game == null:
		return
	_defs = p_game.defs
	_rules = p_game.rules
	_port = p_game.port
	_nav = p_game.nav
	_econ = p_game.econ
	_events = p_game.events
	_victory = p_game.victory
	_ai = p_game.ai


func tick() -> int:
	return _events.tick


func defs() -> Defs:
	return _defs


func battle() -> BattleSim:
	return _port.battle()


func players() -> PlayerTable:
	return _econ.players


func buildings() -> BuildingTable:
	return _econ.buildings


func nodes() -> NodeTable:
	return _econ.nodes


func herds() -> HerdTable:
	return _econ.herds


func events() -> SimEvents:
	return _events


func grass() -> PackedByteArray:
	return _econ.grass_grid()


func water() -> PackedByteArray:
	return _econ.water_grid()


## Размеры полей (квадратная карта): трава 16 м, полив 8 м; пустые поля — 0
func field_dims() -> Vector4i:
	if _econ.has_method("field_dims"):
		return _econ.call("field_dims")
	var g := _side(_econ.grass_grid().size())
	var w := _side(_econ.water_grid().size())
	return Vector4i(g, g, w, w)


func unit_handle(u: int) -> int:
	var sim := battle()
	if sim != null:
		var gen := sim.u_gen
		return Ids.make(Ids.Kind.UNIT, u, gen[u]) if u >= 0 and u < gen.size() else Ids.NULL
	var st := _port as CombatPortStub
	if st != null and u >= 0 and u < st.n:
		return Ids.make(Ids.Kind.UNIT, u, st.u_gen[u])
	return Ids.NULL


func unit_index(h: int) -> int:
	if Ids.kind(h) != Ids.Kind.UNIT or not _port.valid(h):
		return -1
	return Ids.slot(h)


func pick(p: int, world: Vector2, r: float) -> int:
	var P := players()
	var team := P.team[p]
	var port := _port
	# свой юнит, потом чужой
	for own in [true, false]:
		port.units_near(team, world, r, not own, 0, _buf)
		var best := Ids.NULL
		var bd := INF
		for u in _buf:
			if own and port.owner(u) != p:
				continue
			var d := port.pos(u).distance_squared_to(world)
			if d < bd:
				bd = d
				best = u
		if best != Ids.NULL:
			return best
	# здание под точкой (след в клетках навигации; звенья — по близости к оси)
	var B := buildings()
	var bstate := B.state
	for b in B.hw:
		if bstate[b] != BuildingTable.State.FREE and _in_footprint(B, b, world):
			return B.handle(b)
	var N := nodes()
	var nb := Ids.NULL
	var nd := maxf(r, 3.0) * maxf(r, 3.0)
	for n in N.hw:
		if N.ntype[n] >= 0 and N.amount_milli[n] != 0:
			var d := Vector2(N.x[n], N.z[n]).distance_squared_to(world)
			if d <= nd:
				nd = d
				nb = N.handle(n)
	if nb != Ids.NULL:
		return nb
	var H := herds()
	for h in H.hw:
		if H.state[h] != HerdTable.State.FREE:
			var gr := H.graze_r[h]
			if Vector2(H.x[h], H.z[h]).distance_squared_to(world) <= gr * gr:
				return H.handle(h)
	return Ids.NULL


func units_of(p: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var sim := battle()
	if sim != null:
		var life := sim.u_life
		var own := sim.u_owner
		var gen := sim.u_gen
		for u in sim.n:
			if life[u] == BattleSim.Life.ALIVE and own[u] == p:
				out.append(Ids.make(Ids.Kind.UNIT, u, gen[u]))
		return out
	var P := players()
	if p < 0 or p >= P.count:
		return out
	_port.units_near(P.team[p], Vector2.ZERO, ALL_R, false, 0, _buf)
	for u in _buf:
		if _port.owner(u) == p:
			out.append(u)
	return out


func selection_info(hs: PackedInt32Array) -> Dictionary:
	if hs.is_empty():
		return {"kind": "none", "cards": []}
	match Ids.kind(hs[0]):
		Ids.Kind.BUILDING:
			return {"kind": "building", "cards": [], "panel": building_panel(hs[0])}
		Ids.Kind.NODE:
			var N := nodes()
			if not N.valid(hs[0]):
				return {"kind": "none", "cards": []}
			var n := N.slot(hs[0])
			return {"kind": "node", "cards": [], "name": tr(_defs.n_name[N.ntype[n]]),
				"amount": N.amount_milli[n] / 1000}
		Ids.Kind.HERD:
			var H := herds()
			if not H.valid(hs[0]):
				return {"kind": "none", "cards": []}
			var h := H.slot(hs[0])
			return {"kind": "herd", "cards": [], "name": tr(_defs.h_name[H.htype[h]]), "heads": H.heads(h)}
	var port := _port
	var sim := battle()
	var cards: Array = []
	var seen := {}
	var singles := {}                    # тип → [число, сумма hp]
	for h in hs:
		if not unit_alive_any(h):
			continue
		var s := h if Ids.kind(h) == Ids.Kind.SQUAD else port.squad_of(h)
		var m := port.members(s)
		if m.size() <= 1:
			var u := m[0] if m.size() == 1 else h
			var t := String(port.type_id(u))
			if not singles.has(t):
				singles[t] = [0, 0.0]
			singles[t][0] += 1
			singles[t][1] += _hp01(sim, u)
		elif not seen.has(s):
			seen[s] = true
			var alive := 0
			var hp := 0.0
			var t := ""
			for mu in m:
				if port.alive(mu):
					alive += 1
					hp += _hp01(sim, mu)
					if t == "" or _flags_of(String(port.type_id(mu))) & UnitStats.OFFICER == 0:
						t = String(port.type_id(mu))
			var card := {"type": t, "name": tr(UnitStats.get_stats(t).get("name", t)), "count": alive,
				"hp": hp / maxi(alive, 1), "morale": 1.0, "stamina": 1.0, "banner": false, "squad": s}
			if sim != null:
				var i := Ids.slot(s)
				card["morale"] = sim.sq_morale[i] / 100.0
				card["stamina"] = sim.sq_stam[i] / 100.0
				card["banner"] = sim.sq_banner[i] >= 0
				card["type"] = sim.type_ids[sim.sq_type[i]]
				card["name"] = tr(UnitStats.get_stats(card["type"]).get("name", card["type"]))
			cards.append(card)
	for t: String in singles:
		cards.append({"type": t, "name": tr(UnitStats.get_stats(t).get("name", t)), "count": singles[t][0],
			"hp": singles[t][1] / singles[t][0], "morale": 1.0, "stamina": 1.0, "banner": false, "squad": 0})
	return {"kind": "units", "cards": cards}


func building_panel(b_h: int) -> Dictionary:
	var d := _econ.building_panel(b_h)
	if not d.is_empty():
		return d
	return _panel_fallback(b_h)


func build_menu(p: int, tab: StringName) -> Array[Dictionary]:
	var m := _econ.build_menu(p, tab)
	if not m.is_empty():
		return m
	return _menu_fallback(p, tab)


func orders_for(p: int, hs: PackedInt32Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if hs.is_empty():
		return out
	var defs := _defs
	if Ids.kind(hs[0]) == Ids.Kind.BUILDING:
		var B := buildings()
		if not B.valid(hs[0]):
			return out
		var bt := B.btype[B.slot(hs[0])]
		out.append(_order(SimCmd.Op.RALLY, "Место сбора", "ПКМ", not defs.b_trains[bt].is_empty()))
		if defs.b_flags[bt] & Defs.BF_PACKABLE:
			out.append(_order(SimCmd.Op.PACK, "Свернуть", "K", true))
		if defs.b_flags[bt] & Defs.BF_HQ and defs.b_flags[bt] & Defs.BF_PACKABLE:
			out.append(_order(SimCmd.Op.PACK_ALL, "Свернуть лагерь", "Shift+K", true))
		if not defs.b_recipes[bt].is_empty():
			out.append(_order(SimCmd.Op.SET_RECIPE, "Рецепт", "", true))
		if defs.b_kind[bt] == Defs.BKind.DAM:
			out.append(_order(SimCmd.Op.SET_DAM, "Запруда", "", true))
		if defs.b_flags[bt] & Defs.BF_MARKET:
			out.append(_order(SimCmd.Op.TRADE, "Обмен", "", true))
		if defs.b_gar_cap[bt] > 0:
			out.append(_order(SimCmd.Op.UNGARRISON, "Спустить гарнизон", "", B.gar_n[B.slot(hs[0])] > 0))
		out.append(_order(SimCmd.Op.DEMOLISH, "Снести", "Del", defs.b_flags[bt] & Defs.BF_HQ == 0))
		return out
	if Ids.kind(hs[0]) == Ids.Kind.HERD:
		out.append(_order(SimCmd.Op.HERD_MOVE, "Перегнать", "ПКМ", true))
		return out
	var flags := 0
	var soldiers := false
	var squad := false
	for h in hs:
		if not unit_alive_any(h):
			continue
		var s := h if Ids.kind(h) == Ids.Kind.SQUAD else _port.squad_of(h)
		var m := _port.members(s)
		if m.size() > 1:
			squad = true
		for u in (m if Ids.kind(h) == Ids.Kind.SQUAD else PackedInt32Array([h])):
			var f := unit_flags(u)
			flags |= f
			if f & (UnitStats.WORKER | UnitStats.WAGON) == 0:
				soldiers = true
	out.append(_order(SimCmd.Op.MOVE, "Идти", "ПКМ", true))
	out.append(_order(SimCmd.Op.STOP, "Стой", "H", true))
	if soldiers:
		out.append(_order(SimCmd.Op.ATTACK_MOVE, "В атаку", "ПКМ", true))
		out.append(_order(SimCmd.Op.FORMATION, "Строй", "F", squad))
		out.append(_order(SimCmd.Op.STANCE, "Стойка", "", true))
		out.append(_order(SimCmd.Op.KACHYP, "Качып атуу", "G", flags & UnitStats.KACHYP != 0))
		out.append(_order(SimCmd.Op.FIRE_MODE, "Стрельба / рукопашная", "R", flags & (UnitStats.BOW | UnitStats.MUSKET) != 0))
		out.append(_order(SimCmd.Op.WAR_CRY, "Боевой клич", "V", flags & UnitStats.GENERAL != 0))
		out.append(_order(SimCmd.Op.DISBAND if squad else SimCmd.Op.FORM_SQUAD,
			"Распустить отряд" if squad else "Собрать отряд", "U", squad or flags & UnitStats.OFFICER != 0))
	if flags & UnitStats.WORKER and flags & UnitStats.WAGON == 0:
		out.append(_order(SimCmd.Op.GATHER, "Добывать", "ПКМ", true))
		out.append(_order(SimCmd.Op.BUILD, "Строить", "B", true))
		out.append(_order(SimCmd.Op.ASSIST, "Помочь строить", "ПКМ", true))
	if flags & UnitStats.WAGON:
		out.append(_order(SimCmd.Op.UNPACK, "Развернуть", "K", true))
	return out


func check_place(p: int, btype: int, center: Vector2, rot_q: int) -> int:
	return _nav.check_place(p, btype, center, rot_q)


func place_cells(p: int, btype: int, center: Vector2, rot_q: int) -> PackedByteArray:
	return _nav.place_cells(p, btype, center, rot_q)


func plan_wall(p: int, wtype: int, pts: PackedVector2Array) -> Dictionary:
	return _nav.plan_wall(p, wtype, pts)


func snap(btype: int, p: Vector2, rot_q: int) -> Vector2:
	return _nav.snap(btype, p, rot_q)


func idle_workers(p: int) -> PackedInt32Array:
	return _econ.idle_workers(p)


## Тактов до набега на игрока p: ближайшая волна любого ИИ, −1 — набегов не ждём, 0 — набег идёт
func raid_eta_ticks(p: int) -> int:
	var best := -1
	for a in _ai:
		var rd := a as RaidDirector
		if rd == null:
			continue
		var e := rd.eta_for(p, _events.tick)
		if e >= 0 and (best < 0 or e < best):
			best = e
	return best


func minimap(p: int) -> Dictionary:
	var units := PackedVector3Array()
	var sim := battle()
	if sim != null:
		var life := sim.u_life
		var x := sim.u_x
		var z := sim.u_z
		var side := sim.u_side
		for u in sim.n:
			if life[u] == BattleSim.Life.ALIVE:
				units.append(Vector3(x[u], z[u], side[u]))
	else:
		var P := players()
		var teams := PackedInt32Array()
		for q in P.count:
			if not teams.has(P.team[q]):
				teams.append(P.team[q])
		for t in teams:
			_port.units_near(t, Vector2.ZERO, ALL_R, false, 0, _buf)
			for u in _buf:
				var pos := _port.pos(u)
				units.append(Vector3(pos.x, pos.y, t))
	var B := buildings()
	var bl := PackedVector3Array()
	for b in B.hw:
		if B.state[b] != BuildingTable.State.FREE:
			bl.append(Vector3(B.x[b], B.z[b], B.team[b]))
	var N := nodes()
	var nl := PackedVector3Array()
	var sk := _defs.n_scatter_kind
	for n in N.hw:
		if N.ntype[n] >= 0 and N.amount_milli[n] != 0 and sk[N.ntype[n]] < 0:
			nl.append(Vector3(N.x[n], N.z[n], N.res[n]))
	return {"units": units, "buildings": bl, "nodes": nl}


# ================================================================= сверх договора (ИИ GAME, тесты)

func rules() -> Dictionary:
	return _rules


func is_defeated(p: int) -> bool:
	return _victory.is_defeated(p)


## Позиция юнита или центр отряда
func unit_pos(h: int) -> Vector2:
	return _port.pos(h)


func unit_alive(h: int) -> bool:
	return _port.alive(h)


## Юнит жив или отряд действителен и не пуст
func unit_alive_any(h: int) -> bool:
	if Ids.kind(h) == Ids.Kind.SQUAD:
		return _port.valid(h) and not _port.members(h).is_empty()
	return _port.alive(h)


func unit_owner(h: int) -> int:
	return _port.owner(h)


func unit_type(h: int) -> StringName:
	return _port.type_id(h)


func unit_flags(h: int) -> int:
	return _flags_of(String(_port.type_id(h)))


func units_near(team: int, pos: Vector2, r: float, enemies: bool, flags_any: int, out: PackedInt32Array) -> int:
	return _port.units_near(team, pos, r, enemies, flags_any, out)


func is_idle(h: int) -> bool:
	return _port.is_idle(h)


func squad_of(u_h: int) -> int:
	return u_h if Ids.kind(u_h) == Ids.Kind.SQUAD else _port.squad_of(u_h)


func members(s_h: int) -> PackedInt32Array:
	return _port.members(s_h)


# ================================================================= служебное

func _flags_of(type_id: String) -> int:
	var u := _defs.unit(StringName(type_id))
	return _defs.u_flags[u] if u >= 0 else 0


func _hp01(sim: BattleSim, u_h: int) -> float:
	if sim == null:
		return 1.0
	var u := Ids.slot(u_h)
	return sim.u_hp[u] / maxf(sim.t_hp[sim.u_type[u]], 1.0)


static func _side(n: int) -> int:
	var s := int(sqrt(float(n)))
	while s * s < n:
		s += 1
	while s * s > n:
		s -= 1
	return s


func _in_footprint(B: BuildingTable, b: int, p: Vector2) -> bool:
	var k := _defs.b_kind[B.btype[b]]
	if k == Defs.BKind.WALL or k == Defs.BKind.LINK:
		var half := _defs.b_size[B.btype[b]] * 0.5
		return Vector2(B.x[b], B.z[b]).distance_squared_to(p) <= half.x * half.x
	var o := _nav.origin
	var cx := floori((p.x - o.x) / NavApi.CELL)
	var cz := floori((p.y - o.y) / NavApi.CELL)
	return cx >= B.c0[b] and cx < B.c0[b] + B.cw[b] and cz >= B.r0[b] and cz < B.r0[b] + B.ch[b]


func _panel_fallback(b_h: int) -> Dictionary:
	var B := buildings()
	if not B.valid(b_h):
		return {}
	var defs := _defs
	var P := players()
	var b := B.slot(b_h)
	var bt := B.btype[b]
	var p := B.owner[b]
	var queue: Array = []
	for i in B.q_n[b]:
		var u := B.q[b * BuildingTable.QMAX + i]
		queue.append({"utype": u, "name": tr(defs.u_name[u]),
			"t": float(B.q_t[b]) / maxi(defs.u_train_ticks[u], 1) if i == 0 else 0.0})
	var trains: Array = []
	for u in defs.b_trains[bt]:
		var cost := defs.unit_cost(u)
		var why := _why_cost(p, cost)
		if B.state[b] != BuildingTable.State.ACTIVE:
			why = tr("Здание ещё строится")
		elif P.pop_used[p] + P.pop_reserved[p] + defs.u_pop[u] > P.pop_cap[p]:
			why = tr("Нет мест: нужен дом")
		trains.append({"utype": u, "name": tr(defs.u_name[u]), "cost": cost, "enabled": why == "", "why": why})
	var herd := {}
	var H := herds()
	for h in H.hw:
		if H.state[h] != HerdTable.State.FREE and H.pen_b[h] == b_h:
			herd = {"heads": H.heads(h), "cap": defs.b_herd_cap[bt], "grass": -1.0}
	return {"handle": b_h, "btype": bt, "name": tr(defs.b_name[bt]),
		"hp": B.hp_c[b] / 100, "hp_max": B.hp_max_c[b] / 100,
		"state": B.state[b], "progress": B.progress[b] / 1000.0,
		"queue": queue, "trains": trains,
		"recipe": tr(defs.rc_name[B.recipe[b]]) if B.recipe[b] >= 0 else "",
		"herd": herd, "water": -1.0,
		"gar": {"n": B.gar_n[b], "cap": defs.b_gar_cap[bt]}}


func _menu_fallback(p: int, tab: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var P := players()
	if p < 0 or p >= P.count:
		return out
	var defs := _defs
	var tabs: Dictionary = defs.f_tabs[P.faction[p]]
	var list: PackedInt32Array = tabs.get(String(tab), PackedInt32Array())
	for i in list.size():
		var b := list[i]
		var cost := defs.building_cost(b)
		var why := tr("Ещё не готово") if defs.b_enabled[b] == 0 else _why_cost(p, cost)
		out.append({"btype": b, "name": tr(defs.b_name[b]), "cost": cost,
			"hotkey": HOTKEYS[i] if i < HOTKEYS.size() else "", "enabled": why == "", "why": why})
	return out


func _why_cost(p: int, cost: PackedInt32Array) -> String:
	var defs := _defs
	var P := players()
	var miss := PackedStringArray()
	for r in cost.size():
		var lack := cost[r] - P.res[p * P.R + r]
		if lack > 0:
			miss.append("%d %s" % [ceili(lack / 1000.0), tr(defs.r_name[r]).to_lower()])
	return "" if miss.is_empty() else tr("Нужно: %s") % ", ".join(miss)


func _order(op: int, label: String, key: String, enabled: bool) -> Dictionary:
	return {"op": op, "label": tr(label), "key": key, "enabled": enabled}
