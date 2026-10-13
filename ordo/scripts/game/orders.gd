class_name Orders
extends RefCounted
## Исполнение приказов «Города» (ARCHITECTURE §8, CONTRACT §10.4).
## apply(cmd): форма (SimCmd.validate_shape) → игрок жив → каждый id действителен и свой (вид подходит
## приказу) → правила → обработчик: CombatPort.* (бой) или EconApi.* (хозяйство). Работники и арбы в
## боевом приказе сперва уходят с работы (EconApi.release_units).
## Отказ → событие CMD_REJECTED(player, a op, b причина, c seq): причина — EconApi.Err или 100 + NavApi.Why.
## Сам ничего не хранит, кроме счётчиков (applied / rejected) для тестов и замеров.

const Err := EconApi.Err
const Op := SimCmd.Op

var applied := 0
var rejected := 0
var last_reject := 0            # причина последнего отказа (тесты)

var _defs: Defs
var _rules := {}
var _port: CombatPort
var _econ: EconApi
var _events: SimEvents
var _victory: Victory


## Части игры (без ссылки на сам GameSim — иначе цикл ссылок RefCounted)
func setup(p_game: GameSim) -> void:
	_defs = p_game.defs
	_rules = p_game.rules
	_port = p_game.port
	_econ = p_game.econ
	_events = p_game.events
	_victory = p_game.victory


func apply(cmd: PackedInt32Array) -> void:
	var r := _apply(cmd)
	if r < 0:
		_reject(cmd, -r)
	else:
		applied += 1


# ================================================================= проверки

func _apply(cmd: PackedInt32Array) -> int:
	if not SimCmd.validate_shape(cmd):
		return -Err.INVALID
	var op := cmd[SimCmd.H_OP]
	var p := cmd[SimCmd.H_PLAYER]
	var P := _econ.players
	if p < 0 or p >= P.count or P.alive[p] == 0 or _victory.is_defeated(p):
		return -Err.NOT_ALLOWED
	var ids := SimCmd.ids(cmd)
	var want := _id_kind(op)
	for h in ids:
		var e := _check_own(p, h, want)
		if e != Err.OK:
			return -e
	match op:
		Op.MOVE:
			_release(ids)
			_port.move(ids, SimCmd.arg_pos(cmd, 0), SimCmd.arg(cmd, 2) == 1, SimCmd.arg_angle(cmd, 3))
			# TODO(ARCH §14): queue (Shift) — CombatPort.move без очереди путей
		Op.MOVE_LINE:
			_release(ids)
			var a := SimCmd.arg_pos(cmd, 0)
			var b := SimCmd.arg_pos(cmd, 2)
			_port.move(ids, a, SimCmd.arg(cmd, 4) == 1, NAN, b)
		Op.ATTACK:
			var t := SimCmd.arg(cmd, 0)
			var e := _check_target(p, t)
			if e != Err.OK:
				return -e
			_release(ids)
			_port.attack(ids, t, SimCmd.arg(cmd, 1) == 1)
		Op.ATTACK_MOVE:
			_release(ids)
			_port.attack_move(ids, SimCmd.arg_pos(cmd, 0))
		Op.STOP:
			_release(ids)
			_port.stop(ids)
		Op.HOLD:
			_release(ids)
			_port.hold(ids, SimCmd.arg_angle(cmd, 0))
		Op.STANCE:
			_port.set_stance(ids, SimCmd.arg(cmd, 0))
		Op.GAIT:
			_port.set_gait(ids, SimCmd.arg(cmd, 0))
		Op.FORMATION:
			_port.set_formation(ids, SimCmd.arg(cmd, 0))
		Op.FIRE_MODE:
			_port.set_fire_mode(ids, SimCmd.arg(cmd, 0))
		Op.KACHYP:
			_port.set_kachyp(ids, SimCmd.arg(cmd, 0) == 1)
		Op.WAR_CRY:
			if _unit_flags(ids[0]) & UnitStats.GENERAL == 0:
				return -Err.NOT_ALLOWED
			if not _port.war_cry(ids[0]):
				return -Err.BUSY
		Op.FORM_SQUAD:
			return _form_squad(p, ids)
		Op.DISBAND:
			var s := ids[0] if Ids.kind(ids[0]) == Ids.Kind.SQUAD else _port.squad_of(ids[0])
			var n := _port.members(s).size()
			if n < 2:
				return -Err.INVALID
			var pos := _port.pos(s)
			var singles := _port.disband(s)
			if singles.is_empty():
				return -Err.INVALID
			_events.push(SimEvents.Ev.SQUAD_DISBANDED, p, s, 0, singles.size(), pos)
		Op.GARRISON:
			var b := SimCmd.arg(cmd, 0)
			var e := _check_own(p, b, Ids.Kind.BUILDING)
			if e != Err.OK:
				return -e
			var bs := _econ.buildings.slot(b)
			if _econ.buildings.state[bs] != BuildingTable.State.ACTIVE or _defs.b_gar_cap[_econ.buildings.btype[bs]] <= 0:
				return -Err.NOT_ALLOWED
			_release(ids)
			_port.garrison(ids, b)
		Op.UNGARRISON:
			var bs := _econ.buildings.slot(ids[0])
			_port.ungarrison(ids[0], Vector2(_econ.buildings.x[bs], _econ.buildings.z[bs]))
		Op.GATHER:
			var src := SimCmd.arg(cmd, 0)
			if not _valid_any(src):
				return -Err.STALE
			if not _all_workers(ids):
				return -Err.NOT_ALLOWED
			return _econ_result(_econ.assign_gather(p, ids, src))
		Op.BUILD:
			var bt := SimCmd.arg(cmd, 0)
			var e := _check_btype(p, bt)
			if e != Err.OK:
				return -e
			if not _all_workers(ids):
				return -Err.NOT_ALLOWED
			var at := SimCmd.arg_pos(cmd, 1)
			var ws := ids if not ids.is_empty() else _nearest_idle(p, at)
			return _econ_result(_econ.place_site(p, bt, at, SimCmd.arg(cmd, 3), ws))
		Op.BUILD_WALL:
			var wt := SimCmd.arg(cmd, 0)
			var e := _check_btype(p, wt)
			if e != Err.OK:
				return -e
			var k := _defs.b_kind[wt]
			if k != Defs.BKind.WALL and k != Defs.BKind.LINK:
				return -Err.NOT_ALLOWED
			if not _all_workers(ids):
				return -Err.NOT_ALLOWED
			var pts := SimCmd.wall_points(cmd)
			var ws := ids if not ids.is_empty() else _nearest_idle(p, pts[0])
			return _econ_result(_econ.place_wall(p, wt, pts, ws))
		Op.ASSIST:
			var b := SimCmd.arg(cmd, 0)
			var e := _check_own(p, b, Ids.Kind.BUILDING)
			if e != Err.OK:
				return -e
			if not _all_workers(ids):
				return -Err.NOT_ALLOWED
			return _econ_result(_econ.assign_build(p, ids, b))
		Op.DEMOLISH:
			return _econ_result(_econ.demolish(p, ids[0]))
		Op.TRAIN:
			var u := SimCmd.arg(cmd, 0)
			if u >= _defs.unit_ids.size() or _defs.u_enabled[u] == 0:
				return -Err.INVALID
			return _econ_result(_econ.train(p, ids[0], u, SimCmd.arg(cmd, 1)))
		Op.CANCEL_TRAIN:
			return _econ_result(_econ.cancel_train(p, ids[0], SimCmd.arg(cmd, 0)))
		Op.RALLY:
			var t := SimCmd.arg(cmd, 2)
			if t != Ids.NULL and not _valid_any(t):
				return -Err.STALE
			return _econ_result(_econ.set_rally(p, ids[0], SimCmd.arg_pos(cmd, 0), t))
		Op.SET_RECIPE:
			var rc := SimCmd.arg(cmd, 0)
			if rc >= _defs.rc_ids.size() or _defs.rc_enabled[rc] == 0:
				return -Err.INVALID
			return _econ_result(_econ.set_recipe(p, ids[0], rc))
		Op.TRADE:
			if SimCmd.arg(cmd, 0) >= _defs.R or SimCmd.arg(cmd, 1) >= _defs.R:
				return -Err.INVALID
			return _econ_result(_econ.trade(p, ids[0], SimCmd.arg(cmd, 0), SimCmd.arg(cmd, 1), SimCmd.arg(cmd, 2)))
		Op.SET_DAM:
			return _econ_result(_econ.set_dam(p, ids[0], SimCmd.arg(cmd, 0) == 1))
		Op.PACK:
			return _econ_result(_econ.pack(p, ids[0]))
		Op.PACK_ALL:
			return _econ_result(_econ.pack_all(p, ids[0]))
		Op.UNPACK:
			for h in ids:
				if _unit_flags(h) & UnitStats.WAGON == 0:
					return -Err.NOT_ALLOWED
			return _econ_result(_econ.unpack(p, ids, SimCmd.arg_pos(cmd, 0)))
		Op.HERD_MOVE:
			return _econ_result(_econ.herd_move(p, ids[0], SimCmd.arg_pos(cmd, 0)))
		Op.SPAWN:
			return _spawn(p, cmd)
	return Err.OK


## Какого вида должны быть ids приказа
func _id_kind(op: int) -> int:
	match op:
		Op.GATHER, Op.BUILD, Op.BUILD_WALL, Op.ASSIST, Op.UNPACK, Op.WAR_CRY:
			return Ids.Kind.UNIT
		Op.DEMOLISH, Op.TRAIN, Op.CANCEL_TRAIN, Op.RALLY, Op.SET_RECIPE, Op.TRADE, Op.SET_DAM, Op.PACK, Op.PACK_ALL, \
				Op.UNGARRISON:
			return Ids.Kind.BUILDING
		Op.HERD_MOVE:
			return Ids.Kind.HERD
	return -1          # юнит или отряд


## Свой и действительный описатель: OK, STALE (устарел), NOT_OWNER (чужой), INVALID (не тот вид)
func _check_own(p: int, h: int, want: int) -> int:
	var k := Ids.kind(h)
	if want >= 0 and k != want:
		return Err.INVALID
	if want < 0 and k != Ids.Kind.UNIT and k != Ids.Kind.SQUAD:
		return Err.INVALID
	match k:
		Ids.Kind.UNIT, Ids.Kind.SQUAD:
			if not _port.valid(h) or (k == Ids.Kind.UNIT and not _port.alive(h)):
				return Err.STALE
			return Err.OK if _port.owner(h) == p else Err.NOT_OWNER
		Ids.Kind.BUILDING:
			var B := _econ.buildings
			if not B.valid(h):
				return Err.STALE
			return Err.OK if B.owner[B.slot(h)] == p else Err.NOT_OWNER
		Ids.Kind.HERD:
			var H := _econ.herds
			if not H.valid(h):
				return Err.STALE
			return Err.OK if H.owner[H.slot(h)] == p else Err.NOT_OWNER
	return Err.INVALID


## Цель атаки: действительная и чужой команды (юнит, отряд, здание)
func _check_target(p: int, t: int) -> int:
	var team := _econ.players.team[p]
	match Ids.kind(t):
		Ids.Kind.UNIT, Ids.Kind.SQUAD:
			if not _port.valid(t):
				return Err.STALE
			return Err.OK if _port.team(t) != team else Err.NOT_ALLOWED
		Ids.Kind.BUILDING:
			var B := _econ.buildings
			if not B.valid(t):
				return Err.STALE
			return Err.OK if B.team[B.slot(t)] != team else Err.NOT_ALLOWED
	return Err.INVALID


func _valid_any(h: int) -> bool:
	match Ids.kind(h):
		Ids.Kind.UNIT, Ids.Kind.SQUAD:
			return _port.valid(h)
		Ids.Kind.BUILDING:
			return _econ.buildings.valid(h)
		Ids.Kind.NODE:
			return _econ.nodes.valid(h)
		Ids.Kind.HERD:
			return _econ.herds.valid(h)
	return false


## Постройка своей стороны и включена (enabled; Сб. 2+ — нет)
func _check_btype(p: int, bt: int) -> int:
	if bt < 0 or bt >= _defs.b_ids.size():
		return Err.INVALID
	if _defs.b_enabled[bt] == 0:
		return Err.NOT_ALLOWED
	var f := _econ.players.faction[p]
	if _defs.b_faction[bt] != "" and f >= 0 and _defs.b_faction[bt] != _defs.f_ids[f]:
		return Err.NOT_ALLOWED
	return Err.OK


func _unit_flags(h: int) -> int:
	var k := Ids.kind(h)
	if k == Ids.Kind.SQUAD:
		var m := _port.members(h)
		return _unit_flags(m[0]) if m.size() == 1 else 0
	var u := _defs.unit(_port.type_id(h))
	return _defs.u_flags[u] if u >= 0 else 0


func _all_workers(ids: PackedInt32Array) -> bool:
	for h in ids:
		if _unit_flags(h) & UnitStats.WORKER == 0:
			return false
	return true


## Работники и арбы из боевого приказа уходят с работы
func _release(ids: PackedInt32Array) -> void:
	var out := PackedInt32Array()
	for h in ids:
		if Ids.kind(h) == Ids.Kind.UNIT and _unit_flags(h) & (UnitStats.WORKER | UnitStats.WAGON) != 0:
			out.append(h)
	if not out.is_empty():
		_econ.release_units(out)


## BUILD без работников: ближайший свободный работник игрока (по квадрату расстояния, при равенстве — по порядку)
func _nearest_idle(p: int, at: Vector2) -> PackedInt32Array:
	var best := Ids.NULL
	var bd := INF
	for h in _econ.idle_workers(p):
		if not _port.alive(h):
			continue
		var d := _port.pos(h).distance_squared_to(at)
		if d < bd:
			bd = d
			best = h
	return PackedInt32Array([best]) if best != Ids.NULL else PackedInt32Array()


## Ответ обработчика ECON: ≥ 0 — успех (описатель, номер цепочки или OK), < 0 — отказ
func _econ_result(r: int) -> int:
	return r if r < 0 else Err.OK


func _form_squad(p: int, ids: PackedInt32Array) -> int:
	var officer := ids[0]
	if Ids.kind(officer) != Ids.Kind.UNIT or _unit_flags(officer) & UnitStats.OFFICER == 0:
		return -Err.NOT_ALLOWED
	var cands := PackedInt32Array()
	for i in range(1, ids.size()):
		if Ids.kind(ids[i]) == Ids.Kind.UNIT and _unit_flags(ids[i]) & (UnitStats.WORKER | UnitStats.WAGON | UnitStats.OFFICER | UnitStats.GENERAL) == 0:
			cands.append(ids[i])
	if cands.is_empty():
		return -Err.INVALID
	var s := _port.form_squad(officer, cands)
	if s == Ids.NULL:
		return -Err.INVALID
	_events.push(SimEvents.Ev.SQUAD_FORMED, p, s, officer, _port.members(s).size() - 1, _port.pos(s))
	return Err.OK


## SPAWN — только ИИ при rules.ai_free_waves (волны набега даром); якорь — точка из приказа
func _spawn(p: int, cmd: PackedInt32Array) -> int:
	var P := _econ.players
	if P.ctrl[p] != PlayerTable.Ctrl.AI or not bool(_rules.get("ai_free_waves", false)):
		return -Err.NOT_ALLOWED
	var u := SimCmd.arg(cmd, 0)
	var count := SimCmd.arg(cmd, 1)
	var officer := SimCmd.arg(cmd, 5)
	if u >= _defs.unit_ids.size() or officer >= _defs.unit_ids.size() or count > SimCmd.MAX_IDS:
		return -Err.INVALID
	var at := SimCmd.arg_pos(cmd, 2)
	var heading := SimCmd.arg_angle(cmd, 4)
	if is_nan(heading):
		heading = 0.0
	var off_id: StringName = StringName(_defs.unit_ids[officer]) if officer >= 0 else &""
	var s := _port.spawn_squad(p, P.team[p], StringName(_defs.unit_ids[u]), count, at, heading, off_id)
	if s == Ids.NULL:
		return -Err.INVALID
	for m in _port.members(s):
		var mt := _defs.unit(_port.type_id(m))
		_events.push(SimEvents.Ev.UNIT_SPAWNED, p, m, Ids.NULL, mt, _port.pos(m))
	return Err.OK


func _reject(cmd: PackedInt32Array, reason: int) -> void:
	rejected += 1
	last_reject = reason
	var op := cmd[SimCmd.H_OP] if cmd.size() > SimCmd.H_OP else 0
	var p := cmd[SimCmd.H_PLAYER] if cmd.size() > SimCmd.H_PLAYER else -1
	var seq := cmd[SimCmd.H_SEQ] if cmd.size() > SimCmd.H_SEQ else 0
	_events.push(SimEvents.Ev.CMD_REJECTED, p, op, reason, seq)
