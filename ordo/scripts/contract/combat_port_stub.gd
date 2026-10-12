class_name CombatPortStub
extends CombatPort
## Заглушка порта тел (ARCHITECTURE §19.0 #6) для тестов ECON и GAME до I1/I2:
##   • кинематические массивы (позиция, владелец, команда, тип, жив), без боя;
##   • move/attack_move/attack — прямо к цели со скоростью UnitStats (шагом — × walk);
##     отряд идёт целиком (члены держат смещение от центра), одиночки вместе — сеткой 1,5 м;
##   • прибытие — описатель отряда в take_arrivals, когда дошли все;
##   • kill() → take_deaths [unit_h, 0]; убитый слот освобождается на следующем step();
##   • structure_set/clear, set_owner_mods, garrison, upgrade_type — только запоминаются;
##   • battle() — null. Детерминирована (порядок по индексам).
## Для тестов: test_hit_structure(...) кладёт попадание в take_structure_hits, test_hurt(u_h) — «ранен».

const DT := 1.0 / 30.0
const _FREE := 0
const _ALIVE := 1
const _DEAD := 2

var tick := 0
var defs: Defs
var nav: NavApi
var cfg := {}

# юниты
var n := 0
var u_gen := PackedInt32Array()
var u_state := PackedInt32Array()
var u_owner := PackedInt32Array()
var u_team := PackedInt32Array()
var u_squad := PackedInt32Array()
var u_flags := PackedInt32Array()
var u_hurt_tick := PackedInt32Array()
var u_moving := PackedInt32Array()
var u_type := PackedStringArray()
var u_x := PackedFloat32Array()
var u_z := PackedFloat32Array()
var u_heading := PackedFloat32Array()
var u_tx := PackedFloat32Array()
var u_tz := PackedFloat32Array()
var u_speed := PackedFloat32Array()
var u_work := PackedFloat32Array()       # AnimSpec.WORK_*, −1 — нет
# отряды
var squads := 0
var sq_gen := PackedInt32Array()
var sq_state := PackedInt32Array()
var sq_owner := PackedInt32Array()
var sq_team := PackedInt32Array()
var sq_moving := PackedInt32Array()
var sq_stance := PackedInt32Array()
var sq_gait := PackedInt32Array()
var sq_form := PackedInt32Array()
var sq_members: Array[PackedInt32Array] = []
# записанное
var structures := {}                     # b_h → {team, center, half, rot, flags, top, gar_cap}
var owner_mods := {}                     # owner → PackedFloat32Array
var garrisons := {}                      # b_h → PackedInt32Array (unit handles)
var upgrades: Array = []                 # [owner, type_id, overrides]

var _deaths := PackedInt32Array()
var _hits := PackedInt32Array()
var _arrivals := PackedInt32Array()


func setup(p_defs: Defs, p_nav: NavApi, p_cfg: Dictionary) -> void:
	defs = p_defs
	nav = p_nav
	cfg = p_cfg


func battle() -> BattleSim:
	return null


# ---------------------------------------------------------------- жизнь

func spawn(owner: int, team: int, type_id: StringName, pos: Vector2, heading: float) -> int:
	var s := _new_squad(owner, team)
	var u := _new_unit(s, owner, team, type_id, pos, heading)
	sq_members[s] = PackedInt32Array([u])
	return _uh(u)


func spawn_squad(owner: int, team: int, type_id: StringName, count: int, pos: Vector2, heading: float,
		officer_type: StringName = &"", formation := 0, files := 0) -> int:
	var s := _new_squad(owner, team)
	sq_form[s] = formation
	var f := files if files > 0 else maxi(1, ceili(count / 2.0))
	var fwd := Vector2(sin(heading), cos(heading))
	var right := Vector2(-fwd.y, fwd.x)
	var m := PackedInt32Array()
	for k in count:
		var p := pos + right * ((k % f) - (f - 1) * 0.5) * 1.5 - fwd * (k / f) * 1.5
		m.append(_new_unit(s, owner, team, type_id, p, heading))
	if officer_type != &"":
		m.append(_new_unit(s, owner, team, officer_type, pos + fwd * 4.0, heading))
	sq_members[s] = m
	return _sh(s)


func remove(u_h: int) -> void:
	if not valid(u_h):
		return
	var u := Ids.slot(u_h)
	_leave_squad(u)
	u_state[u] = _FREE


func kill(u_h: int) -> void:
	if not alive(u_h):
		return
	var u := Ids.slot(u_h)
	u_state[u] = _DEAD
	u_moving[u] = 0
	_deaths.append(u_h)
	_deaths.append(0)


func valid(h: int) -> bool:
	var i := Ids.slot(h)
	match Ids.kind(h):
		Ids.Kind.UNIT:
			return i < n and u_gen[i] == Ids.gen(h) and u_state[i] != _FREE
		Ids.Kind.SQUAD:
			return i < squads and sq_gen[i] == Ids.gen(h) and sq_state[i] != _FREE
	return false


# ---------------------------------------------------------------- чтение

func alive(u_h: int) -> bool:
	return Ids.kind(u_h) == Ids.Kind.UNIT and valid(u_h) and u_state[Ids.slot(u_h)] == _ALIVE


func pos(h: int) -> Vector2:
	if not valid(h):
		return Vector2.ZERO
	var i := Ids.slot(h)
	if Ids.kind(h) == Ids.Kind.UNIT:
		return Vector2(u_x[i], u_z[i])
	var c := Vector2.ZERO
	var k := 0
	for u in sq_members[i]:
		if u_state[u] == _ALIVE:
			c += Vector2(u_x[u], u_z[u])
			k += 1
	return c / k if k > 0 else c


func owner(h: int) -> int:
	if not valid(h):
		return -1
	return u_owner[Ids.slot(h)] if Ids.kind(h) == Ids.Kind.UNIT else sq_owner[Ids.slot(h)]


func team(h: int) -> int:
	if not valid(h):
		return -1
	return u_team[Ids.slot(h)] if Ids.kind(h) == Ids.Kind.UNIT else sq_team[Ids.slot(h)]


func type_id(u_h: int) -> StringName:
	return StringName(u_type[Ids.slot(u_h)]) if valid(u_h) and Ids.kind(u_h) == Ids.Kind.UNIT else &""


func squad_of(u_h: int) -> int:
	if not valid(u_h) or Ids.kind(u_h) != Ids.Kind.UNIT:
		return 0
	var s := u_squad[Ids.slot(u_h)]
	return _sh(s) if s >= 0 else 0


func members(s_h: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if valid(s_h) and Ids.kind(s_h) == Ids.Kind.SQUAD:
		for u in sq_members[Ids.slot(s_h)]:
			out.append(_uh(u))
	return out


func is_idle(h: int) -> bool:
	if not valid(h):
		return false
	var i := Ids.slot(h)
	return (u_moving[i] if Ids.kind(h) == Ids.Kind.UNIT else sq_moving[i]) == 0


func hurt_within(u_h: int, ticks: int) -> bool:
	if not valid(u_h):
		return false
	var t := u_hurt_tick[Ids.slot(u_h)]
	return t >= 0 and tick - t <= ticks


func units_near(team: int, pos: Vector2, r: float, enemies: bool, flags_any: int, out: PackedInt32Array) -> int:
	out.clear()
	var r2 := r * r
	for u in n:
		if u_state[u] != _ALIVE or (u_team[u] != team) != enemies:
			continue
		if flags_any != 0 and u_flags[u] & flags_any == 0:
			continue
		var dx := u_x[u] - pos.x
		var dz := u_z[u] - pos.y
		if dx * dx + dz * dz <= r2:
			out.append(_uh(u))
	return out.size()


func enemy_near(team: int, pos: Vector2, r: float) -> bool:
	var r2 := r * r
	for u in n:
		if u_state[u] == _ALIVE and u_team[u] != team:
			var dx := u_x[u] - pos.x
			var dz := u_z[u] - pos.y
			if dx * dx + dz * dz <= r2:
				return true
	return false


# ---------------------------------------------------------------- приказы

func move(hs: PackedInt32Array, to: Vector2, run := false, facing := NAN, line_to := Vector2(NAN, NAN)) -> void:
	var sqs := _squads_of(hs)
	var singles := PackedInt32Array()
	for s in sqs:
		if sq_members[s].size() == 1:
			singles.append(s)
	var side := ceili(sqrt(float(singles.size())))
	for s in sqs:
		var goal := to
		var k := singles.find(s)
		if singles.size() > 1 and k >= 0:
			goal = to + Vector2((k % side) - (side - 1) * 0.5, (k / side) - (side - 1) * 0.5) * 1.5
		_move_squad(s, goal, run)


func attack(hs: PackedInt32Array, target_h: int, run := true) -> void:
	var to := Vector2.ZERO
	if Ids.kind(target_h) == Ids.Kind.BUILDING:
		if not structures.has(target_h):
			return
		to = structures[target_h]["center"]
	elif valid(target_h):
		to = pos(target_h)
	else:
		return
	move(hs, to, run)


func attack_move(hs: PackedInt32Array, to: Vector2) -> void:
	move(hs, to, true)


func stop(hs: PackedInt32Array) -> void:
	for s in _squads_of(hs):
		sq_moving[s] = 0
		for u in sq_members[s]:
			u_moving[u] = 0
			u_work[u] = -1.0


func hold(hs: PackedInt32Array, facing := NAN) -> void:
	stop(hs)
	if not is_nan(facing):
		for s in _squads_of(hs):
			for u in sq_members[s]:
				u_heading[u] = facing


func set_stance(hs: PackedInt32Array, stance: int) -> void:
	for s in _squads_of(hs):
		sq_stance[s] = stance


func set_gait(hs: PackedInt32Array, gait: int) -> void:
	for s in _squads_of(hs):
		sq_gait[s] = gait


func set_formation(hs: PackedInt32Array, formation: int) -> void:
	for s in _squads_of(hs):
		sq_form[s] = formation


func set_fire_mode(hs: PackedInt32Array, mode: int) -> void:
	pass


func set_kachyp(hs: PackedInt32Array, on: bool) -> void:
	pass


func war_cry(general_h: int) -> bool:
	return false


func form_squad(officer_h: int, candidates: PackedInt32Array, formation := 0) -> int:
	if not alive(officer_h):
		return 0
	var o := Ids.slot(officer_h)
	var s := _new_squad(u_owner[o], u_team[o])
	sq_form[s] = formation
	var m := PackedInt32Array()
	for h in candidates:
		if alive(h) and h != officer_h:
			var u := Ids.slot(h)
			_leave_squad(u)
			u_squad[u] = s
			m.append(u)
	_leave_squad(o)
	u_squad[o] = s
	m.append(o)
	sq_members[s] = m
	return _sh(s)


func disband(s_h: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not valid(s_h) or Ids.kind(s_h) != Ids.Kind.SQUAD:
		return out
	var old := Ids.slot(s_h)
	for u in sq_members[old].duplicate():
		var s := _new_squad(u_owner[u], u_team[u])
		sq_members[s] = PackedInt32Array([u])
		u_squad[u] = s
		out.append(_uh(u))
	sq_members[old] = PackedInt32Array()
	sq_state[old] = _FREE
	return out


func set_work(u_h: int, aux: float) -> void:
	if valid(u_h):
		u_work[Ids.slot(u_h)] = aux if aux >= 0.0 else -1.0


func face(u_h: int, heading: float) -> void:
	if valid(u_h):
		u_heading[Ids.slot(u_h)] = heading


func garrison(hs: PackedInt32Array, b_h: int) -> void:
	garrisons[b_h] = hs.duplicate()


func ungarrison(b_h: int, at: Vector2) -> void:
	garrisons.erase(b_h)


# ---------------------------------------------------------------- зеркало мира

func structure_set(b_h: int, team: int, center: Vector2, half: Vector2, rot: float, flags: int,
		top := 0.0, gar_cap := 0) -> void:
	structures[b_h] = {"team": team, "center": center, "half": half, "rot": rot, "flags": flags,
		"top": top, "gar_cap": gar_cap}


func structure_clear(b_h: int) -> void:
	structures.erase(b_h)


func set_owner_mods(owner: int, mods: PackedFloat32Array) -> void:
	owner_mods[owner] = mods.duplicate()


func upgrade_type(owner: int, type_id: StringName, overrides: Dictionary) -> void:
	upgrades.append([owner, type_id, overrides.duplicate(true)])


func on_nav_changed() -> void:
	pass


# ---------------------------------------------------------------- такт

func deliver_paths() -> void:
	pass


func step() -> void:
	tick += 1
	# убитые прошлого такта освобождают слоты
	for u in n:
		if u_state[u] == _DEAD:
			_leave_squad(u)
			u_state[u] = _FREE
	for u in n:
		if u_state[u] != _ALIVE or u_moving[u] == 0:
			continue
		var dx := u_tx[u] - u_x[u]
		var dz := u_tz[u] - u_z[u]
		var d2 := dx * dx + dz * dz
		var st := u_speed[u] * DT
		if d2 <= st * st:
			u_x[u] = u_tx[u]
			u_z[u] = u_tz[u]
			u_moving[u] = 0
		else:
			var d := sqrt(d2)
			u_x[u] += dx / d * st
			u_z[u] += dz / d * st
			u_heading[u] = atan2(dx, dz)
	for s in squads:
		if sq_state[s] == _FREE or sq_moving[s] == 0:
			continue
		var done := true
		for u in sq_members[s]:
			if u_moving[u] == 1 and u_state[u] == _ALIVE:
				done = false
				break
		if done:
			sq_moving[s] = 0
			_arrivals.append(_sh(s))


func take_deaths() -> PackedInt32Array:
	var out := _deaths
	_deaths = PackedInt32Array()
	return out


func take_structure_hits() -> PackedInt32Array:
	var out := _hits
	_hits = PackedInt32Array()
	return out


func take_arrivals() -> PackedInt32Array:
	var out := _arrivals
	_arrivals = PackedInt32Array()
	return out


func checksum() -> int:
	var h := 17
	for u in n:
		h = (h * 31 + u_state[u]) & 0x7FFFFFFF
		h = (h * 31 + int(u_x[u] * 1000.0)) & 0x7FFFFFFF
		h = (h * 31 + int(u_z[u] * 1000.0)) & 0x7FFFFFFF
	for s in squads:
		h = (h * 31 + sq_state[s] + sq_moving[s] * 2) & 0x7FFFFFFF
	return h


func save_into(d: Dictionary) -> void:
	var st := {}
	for k in _SAVED:
		var v: Variant = get(k)
		st[k] = v.duplicate(true) if v is Array or v is Dictionary else (v.duplicate() if _is_packed(v) else v)
	d["combat_port_stub"] = st


func load_from(d: Dictionary) -> void:
	var st: Dictionary = d.get("combat_port_stub", {})
	for k: String in st:
		var v: Variant = st[k]
		if k == "sq_members":
			sq_members.clear()
			for m: PackedInt32Array in v:
				sq_members.append(m.duplicate())
		else:
			set(k, v.duplicate(true) if v is Array or v is Dictionary else (v.duplicate() if _is_packed(v) else v))


# ---------------------------------------------------------------- для тестов

func test_hit_structure(b_h: int, dmg_centi: int, attacker_h: int) -> void:
	_hits.append(b_h)
	_hits.append(dmg_centi)
	_hits.append(attacker_h)


func test_hurt(u_h: int) -> void:
	if valid(u_h):
		u_hurt_tick[Ids.slot(u_h)] = tick


# ---------------------------------------------------------------- служебное

const _SAVED := ["tick", "n", "u_gen", "u_state", "u_owner", "u_team", "u_squad", "u_flags", "u_hurt_tick",
	"u_moving", "u_type", "u_x", "u_z", "u_heading", "u_tx", "u_tz", "u_speed", "u_work", "squads", "sq_gen",
	"sq_state", "sq_owner", "sq_team", "sq_moving", "sq_stance", "sq_gait", "sq_form", "sq_members",
	"structures", "owner_mods", "garrisons"]


static func _is_packed(v: Variant) -> bool:
	return typeof(v) >= TYPE_PACKED_BYTE_ARRAY and typeof(v) <= TYPE_PACKED_VECTOR4_ARRAY


func _uh(u: int) -> int:
	return Ids.make(Ids.Kind.UNIT, u, u_gen[u])


func _sh(s: int) -> int:
	return Ids.make(Ids.Kind.SQUAD, s, sq_gen[s])


func _new_squad(owner: int, team: int) -> int:
	var s := sq_state.find(_FREE)
	if s < 0:
		s = squads
		squads += 1
		for a: Variant in [sq_gen, sq_state, sq_owner, sq_team, sq_moving, sq_stance, sq_gait, sq_form]:
			a.append(0)
		sq_members.append(PackedInt32Array())
	sq_gen[s] = Ids.next_gen(sq_gen[s])
	sq_state[s] = _ALIVE
	sq_owner[s] = owner
	sq_team[s] = team
	sq_moving[s] = 0
	sq_stance[s] = 0
	sq_gait[s] = 0
	sq_form[s] = 0
	sq_members[s] = PackedInt32Array()
	return s


func _new_unit(s: int, owner: int, team: int, type_id: StringName, p: Vector2, heading: float) -> int:
	var u := u_state.find(_FREE)
	if u < 0:
		u = n
		n += 1
		for a: Variant in [u_gen, u_state, u_owner, u_team, u_squad, u_flags, u_hurt_tick, u_moving]:
			a.append(0)
		for a: Variant in [u_x, u_z, u_heading, u_tx, u_tz, u_speed, u_work]:
			a.append(0.0)
		u_type.append("")
	var st := UnitStats.get_stats(String(type_id))
	u_gen[u] = Ids.next_gen(u_gen[u])
	u_state[u] = _ALIVE
	u_owner[u] = owner
	u_team[u] = team
	u_squad[u] = s
	u_flags[u] = int(st.get("flags", 0))
	u_hurt_tick[u] = -1
	u_moving[u] = 0
	u_type[u] = String(type_id)
	u_x[u] = p.x
	u_z[u] = p.y
	u_heading[u] = heading
	u_tx[u] = p.x
	u_tz[u] = p.y
	u_speed[u] = 0.0
	u_work[u] = -1.0
	return u


func _leave_squad(u: int) -> void:
	var s := u_squad[u]
	if s < 0 or s >= squads:
		return
	var m := sq_members[s]
	var k := m.find(u)
	if k >= 0:
		m.remove_at(k)
	if m.is_empty() and sq_state[s] != _FREE:
		sq_state[s] = _FREE
	u_squad[u] = -1


func _squads_of(hs: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for h in hs:
		if not valid(h):
			continue
		var s := Ids.slot(h) if Ids.kind(h) == Ids.Kind.SQUAD else u_squad[Ids.slot(h)]
		if s >= 0 and not out.has(s):
			out.append(s)
	return out


func _move_squad(s: int, goal: Vector2, run: bool) -> void:
	var c := pos(_sh(s))
	for u in sq_members[s]:
		if u_state[u] != _ALIVE:
			continue
		var st := UnitStats.get_stats(u_type[u])
		var v := float(st.get("speed", 3.0)) * (1.0 if run else float(st.get("walk", 0.62)))
		var t := goal + (Vector2(u_x[u], u_z[u]) - c)
		u_tx[u] = t.x
		u_tz[u] = t.y
		u_speed[u] = v
		u_moving[u] = 1
		u_work[u] = -1.0
	sq_moving[s] = 1
	sq_gait[s] = 2 if run else 0
