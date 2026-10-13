class_name CombatPortBattle
extends CombatPort
## Порт тел над настоящим ядром (ARCHITECTURE §7.1, §17 d): единственный, кто зовёт изменяющие методы
## BattleSim в «Городе». Описатели на входе и выходе (Ids): юнит — UNIT, отряд — SQUAD, здание — BUILDING
## (номер структуры в ядре = слот здания ECON, описатель — в st_ref).
##
## Пути: приказ запоминается по отряду (цель, аллюр, курс); путь просится у NavApi — один на отряд,
## один на группу одиночек (из их центра; последняя точка каждого — своя клетка сетки 1,5 м у цели).
## Пока путь не пришёл, якорь стоит (await_path); deliver_paths() отдаёт пути ядру (set_path).
## Новый путь: устаревший (nav.stale после on_nav_changed), ev_repath ядра (упёрся, путь сквозь новую
## постройку, цель пролома снесена), цель атаки ушла дальше 8 м.
## attack_move: идёт к цели, раз в 10 тактов ищет врага в 40 м и бьёт его, потом идёт дальше.
## Работу (Act.WORK) снимает любой приказ тел; ECON ставит set_work после move (WORK_CARRY в пути).
##
## Буферы ядра забираются при take_*: смерти [unit_h, killer_h] (убийца 0 — нет), попадания по постройкам
## [building_h, урон в санти-HP, attacker_h], прибытия [squad_h].
## Фон (SimStepper): между шагами сюда не заходить без BattleView.sync_sim() (приказы игрока).
## Этап 2–3: гарнизоны, огонь/рукопашная, качып, улучшения родов — заглушки с TODO.

const PITCH := 1.5                  # м: сетка одиночек у цели
const AMOVE_PERIOD := 10            # тактов между поисками врага у attack_move
const AMOVE_R := 40.0               # м: радиус поиска врага у attack_move
const AMOVE_DONE := 3.0             # м: attack_move закончен у цели
const TRACK_PERIOD := 15            # тактов между проверками ушедшей цели атаки
const TRACK_MOVED := 8.0            # м: цель ушла — новый путь
const RESERVE := 2048               # юнитов и отрядов по умолчанию (cfg reserve_units / reserve_squads)

enum K { NONE, MOVE, ATTACK, ATTACK_ST, AMOVE, FIRE }   # FIRE — стрелки бьют отряд с дистанции

var sim: BattleSim
var defs: Defs
var nav: NavApi
var cfg := {}
var tick := 0

# приказы по слоту отряда (растут вместе с sim.squads)
var _o_kind := PackedInt32Array()
var _o_gen := PackedInt32Array()       # sq_gen, когда отдан приказ
var _o_goal := PackedVector2Array()
var _o_gait := PackedInt32Array()
var _o_facing := PackedFloat32Array()
var _o_target := PackedInt32Array()    # описатель цели атаки
var _o_tpos := PackedVector2Array()    # где была цель атаки, когда просили путь
var _o_ticket := PackedInt32Array()    # ждём этот билет (0 — нет)
var _o_res: Array = []                 # PathResult последнего пути (для nav.stale) или null
# билеты: [ticket, squads, goals, gens, to]
var _req: Array = []

var _deaths := PackedInt32Array()
var _hits := PackedInt32Array()
var _arrivals := PackedInt32Array()
var _tmp := PackedInt32Array()


## cfg: {teams, homes: PackedVector2Array, corpse_s, bounds_origin, bounds_size}; дополнительно
## seed (зерно ядра, по умолчанию 1), sleep (сон, по умолчанию да), reserve_units / reserve_squads (2048).
func setup(p_defs: Defs, p_nav: NavApi, p_cfg: Dictionary) -> void:
	defs = p_defs
	nav = p_nav
	cfg = p_cfg
	tick = 0
	sim = BattleSim.new(int(cfg.get("seed", 1)))
	sim.victory_mode = BattleSim.Victory.NONE
	sim.collect_events = true
	sim.sleep_enabled = bool(cfg.get("sleep", true))
	var cs := float(cfg.get("corpse_s", 30.0))
	sim.corpse_steps = roundi(cs / BattleSim.DT) if cs >= 0.0 else -1
	var homes: PackedVector2Array = cfg.get("homes", PackedVector2Array())
	if homes.size() > 0:
		sim.team_home = homes.duplicate()
		sim.flee_mode = BattleSim.FleeMode.HOME
	if cfg.has("bounds_origin") and cfg.has("bounds_size"):
		sim.set_bounds(cfg["bounds_origin"], cfg["bounds_size"])
	else:
		var o := Terrain.origin()
		var n := Terrain.size()
		if n > 1:
			sim.set_bounds(o, Vector2.ONE * (n - 1) * Terrain.spacing())
	if nav and nav.w > 0:
		sim.set_grids(nav.origin, nav.w, nav.h, nav.static_grid(), nav.speed_grid())
	# места заранее: массивы ядра не переезжают в памяти, пока юнитов меньше (шаг в фоне — SimStepper)
	sim.reserve(int(cfg.get("reserve_units", RESERVE)), int(cfg.get("reserve_squads", RESERVE)))
	_o_kind.clear()
	_req.clear()


func battle() -> BattleSim:
	return sim


# ---------------------------------------------------------------- жизнь

func spawn(owner: int, team: int, type_id: StringName, pos: Vector2, heading: float) -> int:
	var t := String(type_id)
	var st := UnitStats.get_stats(t)
	if st.is_empty():
		push_error("CombatPortBattle.spawn: нет юнита %s" % t)
		return 0
	var u := -1
	if int(st["flags"]) & UnitStats.GENERAL != 0:
		var s := sim.add_general(team, t, pos, heading, owner)
		u = sim.sq_members[s][0]
	else:
		u = sim.spawn_single(team, t, pos, heading, owner)
	_ensure()
	_reset_order(sim.u_squad[u])
	return _uh(u)


func spawn_squad(owner: int, team: int, type_id: StringName, count: int, pos: Vector2, heading: float,
		officer_type: StringName = &"", formation := 0, files := 0) -> int:
	var t := String(type_id)
	if UnitStats.get_stats(t).is_empty() or (officer_type != &"" and UnitStats.get_stats(String(officer_type)).is_empty()):
		push_error("CombatPortBattle.spawn_squad: нет юнита %s / %s" % [t, officer_type])
		return 0
	var s := sim.add_squad(team, t, maxi(count, 1), pos, heading, formation, files, String(officer_type), true, 0.0, owner)
	_ensure()
	_reset_order(s)
	return _sh(s)


func remove(u_h: int) -> void:
	if Ids.kind(u_h) == Ids.Kind.UNIT and valid(u_h):
		sim.remove_unit(Ids.slot(u_h))


func kill(u_h: int) -> void:
	if alive(u_h):
		sim.kill_unit(Ids.slot(u_h))


func valid(h: int) -> bool:
	var i := Ids.slot(h)
	match Ids.kind(h):
		Ids.Kind.UNIT:
			return i < sim.n and sim.u_gen[i] == Ids.gen(h) and sim.u_life[i] != BattleSim.Life.FREE
		Ids.Kind.SQUAD:
			return i < sim.squads and sim.sq_gen[i] == Ids.gen(h) and sim.sq_used[i] == 1
		Ids.Kind.BUILDING:
			return i < sim.st_hw and sim.st_alive[i] == 1 and sim.st_ref[i] == h
	return false


# ---------------------------------------------------------------- чтение

func alive(u_h: int) -> bool:
	return Ids.kind(u_h) == Ids.Kind.UNIT and valid(u_h) and sim.u_life[Ids.slot(u_h)] == BattleSim.Life.ALIVE


func pos(h: int) -> Vector2:
	if not valid(h):
		return Vector2.ZERO
	var i := Ids.slot(h)
	match Ids.kind(h):
		Ids.Kind.UNIT:
			return Vector2(sim.u_x[i], sim.u_z[i])
		Ids.Kind.SQUAD:
			return sim.squad_centroid(i) if sim.sq_alive[i] > 0 else sim.squad_anchor(i)
	return Vector2(sim.st_cx[i], sim.st_cz[i])


func owner(h: int) -> int:
	if not valid(h):
		return -1
	match Ids.kind(h):
		Ids.Kind.UNIT:
			return sim.u_owner[Ids.slot(h)]
		Ids.Kind.SQUAD:
			return sim.sq_owner[Ids.slot(h)]
	return -1


func team(h: int) -> int:
	if not valid(h):
		return -1
	match Ids.kind(h):
		Ids.Kind.UNIT:
			return sim.u_side[Ids.slot(h)]
		Ids.Kind.SQUAD:
			return sim.sq_side[Ids.slot(h)]
	return sim.st_team[Ids.slot(h)]


func type_id(u_h: int) -> StringName:
	if Ids.kind(u_h) != Ids.Kind.UNIT or not valid(u_h):
		return &""
	return StringName(sim.type_ids[sim.u_type[Ids.slot(u_h)]])


func squad_of(u_h: int) -> int:
	if Ids.kind(u_h) != Ids.Kind.UNIT or not valid(u_h):
		return 0
	var s := sim.u_squad[Ids.slot(u_h)]
	return _sh(s) if s >= 0 else 0


## Все члены отряда (и павшие, пока тело лежит)
func members(s_h: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if Ids.kind(s_h) == Ids.Kind.SQUAD and valid(s_h):
		for u in sim.sq_members[Ids.slot(s_h)]:
			out.append(_uh(u))
	return out


func is_idle(h: int) -> bool:
	var s := _squad_index(h)
	if s < 0:
		return false
	_ensure()
	return sim.squad_idle(s) and _o_kind[s] != K.AMOVE and _o_kind[s] != K.FIRE and _o_ticket[s] == 0


func hurt_within(u_h: int, ticks: int) -> bool:
	if Ids.kind(u_h) != Ids.Kind.UNIT or not valid(u_h):
		return false
	var t := sim.u_hurt_step[Ids.slot(u_h)]
	return t >= 0 and sim.steps - t <= ticks


func units_near(p_team: int, p_pos: Vector2, r: float, enemies: bool, flags_any: int, out: PackedInt32Array) -> int:
	out.clear()
	sim.units_in_radius(p_team, p_pos, r, enemies, flags_any, _tmp)
	for u in _tmp:
		out.append(_uh(u))
	return out.size()


func enemy_near(p_team: int, p_pos: Vector2, r: float) -> bool:
	return sim.enemy_within(p_team, p_pos, r)


# ---------------------------------------------------------------- приказы

func move(hs: PackedInt32Array, to: Vector2, run := false, facing := NAN, line_to := Vector2(NAN, NAN)) -> void:
	var sqs := _squads_of(hs)
	if sqs.is_empty():
		return
	var gait := BattleSim.Gait.RUN if run else BattleSim.Gait.WALK
	if not is_nan(line_to.x) and not is_nan(line_to.y) and to.distance_to(line_to) >= 1.0:
		_move_line(sqs, to, line_to, gait)
		return
	_move_group(sqs, to, gait, facing, K.MOVE)


func attack(hs: PackedInt32Array, target_h: int, run := true) -> void:
	var sqs := _squads_of(hs)
	if sqs.is_empty() or not valid(target_h):
		return
	var gait := BattleSim.Gait.RUN if run else BattleSim.Gait.WALK
	var kind := Ids.kind(target_h)
	if kind == Ids.Kind.BUILDING:
		var st := Ids.slot(target_h)
		var c := Vector2(sim.st_cx[st], sim.st_cz[st])
		for s in sqs:
			if sim.st_team[st] == sim.sq_side[s]:
				continue
			_clear_work(s)
			sim.order_attack_structure(s, st, gait)
			_set_order(s, K.ATTACK_ST, c, gait, NAN, target_h)
			_request(PackedInt32Array([s]), PackedVector2Array([c]), c)
		return
	var ts := Ids.slot(target_h) if kind == Ids.Kind.SQUAD else sim.u_squad[Ids.slot(target_h)]
	if ts < 0:
		return
	var tp := pos(target_h)
	for s in sqs:
		if sim.sq_side[ts] == sim.sq_side[s] or ts == s:
			continue
		_clear_work(s)
		var ti := sim.sq_type[s]
		if sim.is_ranged_type(ti):
			# стрелки: встают на 0,75 дальности и бьют залпами (как сарбозы среза)
			_fire_at(s, ts, target_h, gait)
			continue
		sim.order_attack(s, ts, gait)
		if sim.t_charge[ti] > 1.0 and sim.t_flags[ti] & UnitStats.MOUNTED != 0:
			sim.allow_charge(s, true)
		_set_order(s, K.ATTACK, tp, gait, NAN, target_h)
		_o_tpos[s] = tp
		_request(PackedInt32Array([s]), PackedVector2Array([tp]), tp)


func attack_move(hs: PackedInt32Array, to: Vector2) -> void:
	var sqs := _squads_of(hs)
	if sqs.is_empty():
		return
	_move_group(sqs, to, -1, NAN, K.AMOVE)


func stop(hs: PackedInt32Array) -> void:
	hold(hs)


func hold(hs: PackedInt32Array, facing := NAN) -> void:
	for s in _squads_of(hs):
		_clear_work(s)
		sim.order_hold(s, facing)
		_reset_order(s)


func set_stance(hs: PackedInt32Array, stance: int) -> void:
	for s in _squads_of(hs):
		sim.set_stance(s, stance)


func set_gait(hs: PackedInt32Array, gait: int) -> void:
	for s in _squads_of(hs):
		sim.set_gait(s, gait)


func set_formation(hs: PackedInt32Array, formation: int) -> void:
	for s in _squads_of(hs):
		if sim.sq_single[s] == 0:
			sim.set_formation(s, formation)


func set_fire_mode(hs: PackedInt32Array, mode: int) -> void:
	pass  # TODO этап 2 (R18): огонь / рукопашная


func set_kachyp(hs: PackedInt32Array, on: bool) -> void:
	pass  # TODO этап 2 (R18): качып атуу


func war_cry(general_h: int) -> bool:
	var s := _squad_index(general_h)
	return s >= 0 and sim.war_cry_now(s)


func form_squad(officer_h: int, candidates: PackedInt32Array, formation := 0) -> int:
	if not alive(officer_h):
		return 0
	var m := PackedInt32Array()
	for h in candidates:
		if alive(h):
			m.append(Ids.slot(h))
	var o := Ids.slot(officer_h)
	var s := sim.form_squad(o, m, formation)
	if s < 0:
		return 0
	_ensure()
	for u in sim.sq_members[s]:
		sim.set_work(u, -1.0)
	_reset_order(s)
	return _sh(s)


func disband(s_h: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if Ids.kind(s_h) != Ids.Kind.SQUAD or not valid(s_h):
		return out
	var s := Ids.slot(s_h)
	if sim.sq_single[s] == 1:
		return out
	_reset_order(s)
	for u in sim.disband_squad(s):
		out.append(_uh(u))
	_ensure()
	for h in out:
		_reset_order(sim.u_squad[Ids.slot(h)])
	return out


func set_work(u_h: int, aux: float) -> void:
	if Ids.kind(u_h) == Ids.Kind.UNIT and valid(u_h):
		sim.set_work(Ids.slot(u_h), aux)


func face(u_h: int, heading: float) -> void:
	if Ids.kind(u_h) == Ids.Kind.UNIT and valid(u_h):
		sim.face(Ids.slot(u_h), heading)


func garrison(hs: PackedInt32Array, b_h: int) -> void:
	pass  # TODO этап 2 (R16): гарнизон в башне


func ungarrison(b_h: int, at: Vector2) -> void:
	pass  # TODO этап 2 (R16)


# ---------------------------------------------------------------- зеркало мира

func structure_set(b_h: int, p_team: int, center: Vector2, half: Vector2, rot: float, flags: int,
		top := 0.0, gar_cap := 0) -> void:
	if Ids.kind(b_h) != Ids.Kind.BUILDING:
		return
	sim.structure_set(Ids.slot(b_h), b_h, p_team, center, half, rot, flags, top, gar_cap)


func structure_clear(b_h: int) -> void:
	var st := Ids.slot(b_h)
	if Ids.kind(b_h) == Ids.Kind.BUILDING and st < sim.st_hw and sim.st_ref[st] == b_h:
		sim.structure_clear(st)


func set_owner_mods(p_owner: int, mods: PackedFloat32Array) -> void:
	sim.set_owner_mods(p_owner, mods)


func upgrade_type(p_owner: int, p_type_id: StringName, overrides: Dictionary) -> void:
	pass  # TODO этап 3 (R11): type_variant / retype (кузница, кремнёвый замок)


## Постройки появились или исчезли: пути через изменённые сектора — заново
func on_nav_changed() -> void:
	_ensure()
	for s in sim.squads:
		var r: PathResult = _o_res[s]
		if r == null or sim.sq_used[s] == 0 or sim.sq_gen[s] != _o_gen[s]:
			continue
		if _o_kind[s] != K.NONE and nav.stale(r):
			_repath(s)


# ---------------------------------------------------------------- такт

func deliver_paths() -> void:
	if _req.is_empty():
		return
	var keep: Array = []
	for e: Array in _req:
		var ticket: int = e[0]
		var r := nav.result(ticket)
		if r == null:
			keep.append(e)
			continue
		var sqs: PackedInt32Array = e[1]
		var goals: PackedVector2Array = e[2]
		var gens: PackedInt32Array = e[3]
		var to: Vector2 = e[4]
		var bst := Ids.slot(r.breach_b) if r.breach_b != 0 else -1
		for i in sqs.size():
			var s := sqs[i]
			if sim.sq_used[s] == 0 or sim.sq_gen[s] != gens[i] or _o_ticket[s] != ticket:
				continue
			var pts := r.pts.duplicate()
			if pts.is_empty():
				pts.append(goals[i])
			else:
				pts[pts.size() - 1] = pts[pts.size() - 1] + (goals[i] - to)
			sim.set_path(s, pts, bst, r.breach_wp)
			_o_res[s] = r
			_o_ticket[s] = 0
		nav.release(ticket)
	_req = keep


func step() -> void:
	tick += 1
	_ensure()
	_amove_scan()
	_track_targets()
	sim.step()
	_ensure()
	for s in sim.take_repath():
		if s < sim.squads and sim.sq_used[s] == 1 and _o_kind[s] != K.NONE:
			_repath(s)
	_drain()


func take_deaths() -> PackedInt32Array:
	_drain()
	var out := _deaths
	_deaths = PackedInt32Array()
	return out


func take_structure_hits() -> PackedInt32Array:
	_drain()
	var out := _hits
	_hits = PackedInt32Array()
	return out


func take_arrivals() -> PackedInt32Array:
	_drain()
	var out := _arrivals
	_arrivals = PackedInt32Array()
	return out


func checksum() -> int:
	var h := sim.checksum()
	for s in _o_kind.size():
		if _o_kind[s] != K.NONE:
			h = (h * 31 + s * 5 + _o_kind[s]) & 0x7FFFFFFF
			h = (h * 31 + int(_o_goal[s].x * 100.0) + int(_o_goal[s].y * 10.0)) & 0x7FFFFFFF
	return (h * 31 + _req.size()) & 0x7FFFFFFF


## Сохранение (этап 3): всё состояние ядра — массивы и счётчики — и приказы порта
func save_into(d: Dictionary) -> void:
	var k := {}
	for p: Dictionary in sim.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var name: String = p["name"]
		if name == "rng":
			continue
		k[name] = _copy(sim.get(name))
	k["rng_state"] = sim.rng.state
	var po := {}
	for name in ["tick", "_o_kind", "_o_gen", "_o_goal", "_o_gait", "_o_facing", "_o_target", "_o_tpos"]:
		po[name] = _copy(get(name))
	d["combat_port_battle"] = {"sim": k, "port": po}


func load_from(d: Dictionary) -> void:
	var all: Dictionary = d.get("combat_port_battle", {})
	if all.is_empty():
		return
	var k: Dictionary = all["sim"]
	for name: String in k:
		if name == "rng_state":
			continue
		var v: Variant = k[name]
		var cur: Variant = sim.get(name)
		if cur is Array:
			(cur as Array).clear()
			for e: Variant in v:
				(cur as Array).append(_copy(e))
		else:
			sim.set(name, _copy(v))
	sim.rng.state = int(k.get("rng_state", sim.rng.state))
	var po: Dictionary = all["port"]
	for name: String in po:
		set(name, _copy(po[name]))
	_req.clear()
	_o_ticket.resize(_o_kind.size())
	_o_ticket.fill(0)
	_o_res.resize(_o_kind.size())
	_o_res.fill(null)
	_ensure()
	# пути ядра сохранены; пропали только билеты в очереди — кто ждал путь, просит заново
	for s in sim.squads:
		if sim.sq_used[s] == 1 and _o_kind[s] != K.NONE and sim.sq_wp[s] < 0:
			_repath(s)


# ---------------------------------------------------------------- служебное

func _uh(u: int) -> int:
	return Ids.make(Ids.Kind.UNIT, u, sim.u_gen[u])


func _sh(s: int) -> int:
	return Ids.make(Ids.Kind.SQUAD, s, sim.sq_gen[s])


## Отряд описателя: отряд — сам, юнит — его отряд; −1 — недействителен
func _squad_index(h: int) -> int:
	if not valid(h):
		return -1
	match Ids.kind(h):
		Ids.Kind.SQUAD:
			return Ids.slot(h)
		Ids.Kind.UNIT:
			return sim.u_squad[Ids.slot(h)]
	return -1


## Отряды приказа: без повторов, по порядку описателей; пустые и чужие слоты — мимо
func _squads_of(hs: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for h in hs:
		var s := _squad_index(h)
		if s >= 0 and sim.sq_alive[s] > 0 and not out.has(s):
			out.append(s)
	_ensure()
	return out


## Массивы приказов — по числу слотов отрядов ядра
func _ensure() -> void:
	var n := sim.squads
	var old := _o_kind.size()
	if old >= n:
		return
	for a: Variant in [_o_kind, _o_gen, _o_gait, _o_target, _o_ticket]:
		a.resize(n)
	_o_goal.resize(n)
	_o_facing.resize(n)
	_o_tpos.resize(n)
	_o_res.resize(n)
	for s in range(old, n):
		_o_kind[s] = K.NONE
		_o_ticket[s] = 0
		_o_res[s] = null


func _reset_order(s: int) -> void:
	if s < 0:
		return
	_ensure()
	_o_kind[s] = K.NONE
	_o_gen[s] = sim.sq_gen[s]
	_o_ticket[s] = 0
	_o_res[s] = null
	_o_target[s] = 0


func _set_order(s: int, kind: int, goal: Vector2, gait: int, facing: float, target_h := 0) -> void:
	_o_kind[s] = kind
	_o_gen[s] = sim.sq_gen[s]
	_o_goal[s] = goal
	_o_gait[s] = gait
	_o_facing[s] = facing
	_o_target[s] = target_h
	_o_res[s] = null


func _clear_work(s: int) -> void:
	for u in sim.sq_members[s]:
		if sim.u_act[u] == BattleSim.Act.WORK or sim.u_work[u] >= 0.0:
			sim.set_work(u, -1.0)


## Ход группы: отряды — каждый своим путём; одиночки вместе — одним путём, у цели сеткой 1,5 м.
## gait −1 — свой для attack_move (конница рысью, пешие шагом).
func _move_group(sqs: PackedInt32Array, to: Vector2, gait: int, facing: float, kind: int) -> void:
	var singles := PackedInt32Array()
	for s in sqs:
		if sim.sq_single[s] == 1:
			singles.append(s)
		else:
			var g := gait if gait >= 0 else _amove_gait(s)
			_order_move(s, to, g, facing, kind)
			_request(PackedInt32Array([s]), PackedVector2Array([to]), to)
	if singles.is_empty():
		return
	var k := singles.size()
	var side := ceili(sqrt(float(k)))
	var goals := PackedVector2Array()
	for i in k:
		var g2 := to
		if k > 1:
			g2 = to + Vector2((i % side) - (side - 1) * 0.5, (i / side) - (side - 1) * 0.5) * PITCH
		goals.append(g2)
		var g := gait if gait >= 0 else _amove_gait(singles[i])
		_order_move(singles[i], g2, g, facing, kind)
	_request(singles, goals, to)


## Линия ПКМ-протяжкой: отряды делят отрезок по числу бойцов, фронт — от отрядов к линии
func _move_line(sqs: PackedInt32Array, a: Vector2, b: Vector2, gait: int) -> void:
	var seg := b - a
	var length := seg.length()
	var dir := seg / length
	var nrm := Vector2(-dir.y, dir.x)
	var c := Vector2.ZERO
	var total := 0
	for s in sqs:
		c += sim.squad_centroid(s)
		total += maxi(sim.sq_alive[s], 1)
	c /= sqs.size()
	if nrm.dot((a + b) * 0.5 - c) < 0.0:
		nrm = -nrm
	var facing := atan2(nrm.x, nrm.y)
	var t0 := 0.0
	for s in sqs:
		var share := float(maxi(sim.sq_alive[s], 1)) / total
		var mid := a + seg * (t0 + share * 0.5)
		t0 += share
		if sim.sq_single[s] == 0:
			var spacing := 2.1 if sim.t_flags[sim.sq_type[s]] & UnitStats.MOUNTED != 0 else 1.0
			sim.set_files(s, clampi(roundi(length * share / spacing), 1, maxi(sim.sq_alive[s], 1)))
		_order_move(s, mid, gait, facing, K.MOVE)
		_request(PackedInt32Array([s]), PackedVector2Array([mid]), mid)


## Стрелки по отряду ts: дальше 0,75 дальности — подойти на неё (лицом к цели), ближе — стоять; огонь шеренгами
func _fire_at(s: int, ts: int, target_h: int, gait: int) -> void:
	var ti := sim.sq_type[s]
	var rmax := sim.t_range[ti] * sim.owner_mod(sim.sq_owner[s], BattleSim.MOD_RANGE)
	var me := sim.squad_centroid(s)
	var tp := sim.squad_centroid(ts)
	var d := me.distance_to(tp)
	var facing := atan2(tp.x - me.x, tp.y - me.y)
	sim.set_fire(s, ts, rmax)
	if d > rmax * 0.8:
		var goal := tp + (me - tp) / maxf(d, 0.01) * rmax * 0.75
		_order_move(s, goal, gait, facing, K.FIRE)
		_request(PackedInt32Array([s]), PackedVector2Array([goal]), goal)
	else:
		sim.order_hold(s, facing)
		_set_order(s, K.FIRE, me, gait, facing)
	_o_target[s] = target_h
	_o_tpos[s] = tp


func _amove_gait(s: int) -> int:
	return BattleSim.Gait.TROT if sim.t_flags[sim.sq_type[s]] & UnitStats.MOUNTED != 0 else BattleSim.Gait.WALK


func _order_move(s: int, goal: Vector2, gait: int, facing: float, kind: int) -> void:
	_clear_work(s)
	sim.order_move(s, goal, gait, facing)
	sim.await_path(s)
	_set_order(s, kind, goal, gait, facing)


## Просьба пути: от центра отрядов к to; каждый отряд потом получает свою последнюю точку goals[i]
func _request(sqs: PackedInt32Array, goals: PackedVector2Array, to: Vector2) -> void:
	var from := Vector2.ZERO
	var gens := PackedInt32Array()
	for s in sqs:
		from += sim.squad_centroid(s)
		gens.append(sim.sq_gen[s])
	from /= sqs.size()
	var ticket := nav.request(sim.sq_side[sqs[0]], from, to, _sh(sqs[0]))
	if ticket <= 0:
		# навигация не дала билет — прямо к цели
		for i in sqs.size():
			sim.set_path(sqs[i], PackedVector2Array([goals[i]]))
		return
	for s in sqs:
		_o_ticket[s] = ticket
	_req.append([ticket, sqs.duplicate(), goals.duplicate(), gens, to])


## Новый путь к запомненной цели (один отряд)
func _repath(s: int) -> void:
	var goal := _o_goal[s]
	if _o_kind[s] == K.ATTACK and valid(_o_target[s]):
		goal = pos(_o_target[s])
		_o_tpos[s] = goal
	if _o_kind[s] == K.MOVE or _o_kind[s] == K.AMOVE:
		if sim.sq_order[s] == BattleSim.Order.MOVE:
			sim.await_path(s)
	_request(PackedInt32Array([s]), PackedVector2Array([goal]), goal)


## attack_move: стоит или идёт — ищет врага рядом и бьёт; цель пала — снова к своей цели
func _amove_scan() -> void:
	for s in _o_kind.size():
		if _o_kind[s] != K.AMOVE or (s + tick) % AMOVE_PERIOD != 0:
			continue
		if sim.sq_used[s] == 0 or sim.sq_gen[s] != _o_gen[s] or sim.sq_alive[s] == 0:
			_o_kind[s] = K.NONE
			continue
		if sim.sq_order[s] == BattleSim.Order.ATTACK:
			continue
		var c := sim.squad_centroid(s)
		var e := sim.nearest_enemy_at(sim.sq_side[s], c, AMOVE_R)
		if e >= 0 and sim.u_squad[e] >= 0:
			_clear_work(s)
			sim.order_attack(s, sim.u_squad[e], BattleSim.Gait.RUN)
			continue
		if sim.sq_order[s] == BattleSim.Order.HOLD:
			if c.distance_to(_o_goal[s]) <= AMOVE_DONE:
				_o_kind[s] = K.NONE
			else:
				var g := _o_gait[s]
				_order_move(s, _o_goal[s], g, NAN, K.AMOVE)
				_request(PackedInt32Array([s]), PackedVector2Array([_o_goal[s]]), _o_goal[s])


## Цель атаки ушла дальше 8 м от того места, куда просили путь — путь заново; стрелки — новое место
func _track_targets() -> void:
	for s in _o_kind.size():
		if _o_kind[s] == K.FIRE and (s + tick) % TRACK_PERIOD == 0 and _o_ticket[s] == 0:
			var th := _o_target[s]
			var ts := _squad_index(th)
			if sim.sq_used[s] == 0 or sim.sq_gen[s] != _o_gen[s] or ts < 0 or sim.sq_alive[ts] == 0:
				_o_kind[s] = K.NONE
				if sim.sq_used[s] == 1:
					sim.set_fire(s, -1, 0.0)
			elif sim.squad_centroid(ts).distance_to(_o_tpos[s]) > TRACK_MOVED:
				_fire_at(s, ts, th, _o_gait[s])
			continue
		if _o_kind[s] != K.ATTACK or (s + tick) % TRACK_PERIOD != 0 or _o_ticket[s] != 0:
			continue
		if sim.sq_order[s] != BattleSim.Order.ATTACK or not valid(_o_target[s]):
			_o_kind[s] = K.NONE
			continue
		if pos(_o_target[s]).distance_to(_o_tpos[s]) > TRACK_MOVED:
			_repath(s)


## Буферы ядра → описатели (убийца, атакующий — описатели юнитов; 0 — нет)
func _drain() -> void:
	var dead := sim.take_dead()
	for i in range(0, dead.size(), 2):
		_deaths.append(_uh(dead[i]))
		_deaths.append(_uh(dead[i + 1]) if dead[i + 1] >= 0 else 0)
	var hits := sim.take_st_hits()
	for i in range(0, hits.size(), 3):
		_hits.append(sim.st_ref[hits[i]])
		_hits.append(hits[i + 1])
		var by := hits[i + 2]
		_hits.append(_uh(by) if by >= 0 and sim.u_life[by] != BattleSim.Life.FREE else 0)
	var arr := sim.take_arrived()
	for s in arr:
		if _o_kind.size() > s and _o_kind[s] == K.MOVE:
			_o_kind[s] = K.NONE
		_arrivals.append(_sh(s))


static func _copy(v: Variant) -> Variant:
	if v is Array or v is Dictionary:
		return v.duplicate(true)
	if typeof(v) >= TYPE_PACKED_BYTE_ARRAY and typeof(v) <= TYPE_PACKED_VECTOR4_ARRAY:
		return v.duplicate()
	return v
