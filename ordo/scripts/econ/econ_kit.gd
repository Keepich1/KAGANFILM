class_name EconKit
extends RefCounted
## Связка для тестов экономики (ARCHITECTURE §15, ECON): EconomySim на CombatPortStub + NavStub, такт —
## в порядке GameSim.step (§5.1, без приказов и ИИ). На I2 те же тесты идут на CombatPortBattle + NavGrid:
## make(…, port, nav) принимает настоящие реализации.
##
##   var k := EconKit.make()
##   var p := k.kokand(Vector2(90, 0))         # Урда + 6 деҳқонов
##   k.run_s(60.0)

var defs: Defs
var rules := {}
var events: SimEvents
var nav: NavApi
var port: CombatPort
var econ: EconomySim
var tick := 0
var _nav_seen := 0
var _extra_hits := PackedInt32Array()


static func make(p_seed := 1, overrides := {}, p_port: CombatPort = null, p_nav: NavApi = null) -> EconKit:
	var k := EconKit.new()
	k.defs = Defs.shared() if overrides.is_empty() else Defs.build(overrides)
	k.rules = k.defs.rules_of(&"GOROD")
	k.events = SimEvents.new()
	# I2 (ARCHITECTURE §19.7): те же тесты на настоящем движении — ORDO_IMPL=real или «-- --impl=real»
	var real := p_port == null and p_nav == null and want_real()
	k.nav = p_nav if p_nav else (NavGrid.new() if real else NavStub.new())
	k.port = p_port if p_port else (CombatPortBattle.new() if real else CombatPortStub.new())
	k.econ = EconomySim.new()
	# настоящая сетка — без рельефа (info.flat): тесты экономики писаны на открытое поле NavStub (места у реки,
	# склоны), а I2 проверяет движение — пути, ядро, двери, ходки
	var info := Terrain.info()
	if real:
		info = info.duplicate()
		info["flat"] = true
	k.nav.setup(info, k.defs, k.econ, k.port)
	k.port.setup(k.defs, k.nav, {"teams": 2, "homes": PackedVector2Array(), "corpse_s": k.rules.get("corpse_s", -1),
		"bounds_origin": k.nav.origin, "bounds_size": Vector2(k.nav.w, k.nav.h) * NavApi.CELL, "seed": p_seed})
	k.econ.setup(k.defs, k.rules, k.port, k.nav, k.events, p_seed)
	return k


## Тесты экономики на настоящих CombatPortBattle + NavGrid: переменная окружения ORDO_IMPL=real или ключ
## --impl=real после «--» (только для тестов; симуляция окружения не читает)
static func want_real() -> bool:
	if OS.get_environment("ORDO_IMPL").strip_edges().to_lower() == "real":
		return true
	for a in OS.get_cmdline_user_args():
		if a == "--impl=real":
			return true
	return false


## Настоящие порт и навигация (не заглушки)
func is_real() -> bool:
	return not (port is CombatPortStub) and not (nav is NavStub)


func step() -> void:
	tick += 1
	events.tick = tick
	if tick == 1 and port.has_method("sync_grids"):
		port.call("sync_grids")          # ядра жил, поставленных тестом после make()
	econ.pre_step(tick)
	if nav.version != _nav_seen:
		_nav_seen = nav.version
		port.on_nav_changed()
	nav.service(tick)
	port.deliver_paths()
	port.step()
	var hits := port.take_structure_hits()
	if not _extra_hits.is_empty():
		hits.append_array(_extra_hits)
		_extra_hits.clear()
	econ.post_step(tick, port.take_deaths(), hits, port.take_arrivals())
	if tick % 30 == 0:
		econ.slow_step(tick)
	if tick % 150 == 75:
		econ.fields_step(tick)


func run_s(s: float) -> void:
	for i in roundi(s * 30.0):
		step()


## Игрок стороны со ставкой в hq и стартовыми работниками (FactionDefs.start_units)
func player(faction: StringName, team: int, hq: Vector2, workers := -1) -> int:
	var p := econ.add_player(team, faction, PlayerTable.Ctrl.HUMAN)
	var f := defs.faction(faction)
	econ.spawn_building(p, defs.f_hq[f], hq, 0)
	var n := workers
	if n < 0:
		var su := defs.f_start_units[f]
		n = su[1] if su.size() >= 2 else 0
	for i in n:
		econ.spawn_worker(p, hq + Vector2(-6.0 + (i % 4) * 4.0, 14.0 + (i / 4) * 3.0))
	return p


func kokand(hq: Vector2, workers := -1, team := 0) -> int:
	return player(&"kokand", team, hq, workers)


func kipchak(hq: Vector2, workers := -1, team := 1) -> int:
	return player(&"kipchak", team, hq, workers)


func b(id: StringName) -> int:
	return defs.building(id)


func u(id: StringName) -> int:
	return defs.unit(id)


func r(id: StringName) -> int:
	return defs.res(id)


## Запас ресурса, целых
func res(p: int, id: StringName) -> float:
	return econ.res(p, defs.res(id)) / 1000.0


func set_res(p: int, id: StringName, v: float) -> void:
	econ.players.res[p * econ.R + defs.res(id)] = roundi(v * 1000.0)


## Готовая постройка (сразу ACTIVE)
func build_now(p: int, id: StringName, at: Vector2, rot_q := 0) -> int:
	return econ.spawn_building(p, defs.building(id), at, rot_q, true)


## Юнит игрока в учёте экономики (население, содержание)
func unit(p: int, id: StringName, at: Vector2) -> int:
	var h := port.spawn(p, econ.players.team[p], id, at, 0.0)
	econ.register_unit(h, p, defs.unit(id))
	return h


func workers_of(p: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for w in econ.wk.hw:
		if econ.wk.w_unit[w] != 0 and econ.wk.w_owner[w] == p:
			out.append(econ.wk.w_unit[w])
	return out


## Сколько событий вида kind с номера from (и игрока p, −1 — любого)
func count_ev(kind: int, from := 0, p := -1) -> int:
	var n := 0
	var rr := events.range_since(from)
	for seq in range(rr.x, rr.y):
		var i := events.at(seq)
		if events.e_kind[i] == kind and (p < 0 or events.e_player[i] == p):
			n += 1
	return n


## Последнее событие вида kind: индекс в e_* или −1
func last_ev(kind: int, from := 0) -> int:
	var rr := events.range_since(from)
	var found := -1
	for seq in range(rr.x, rr.y):
		var i := events.at(seq)
		if events.e_kind[i] == kind:
			found = i
	return found


# ---------------------------------------------------------------- одинаково на заглушке и на настоящем ядре

## Попадание по постройке (как из ядра): заглушке — test_hit_structure, настоящему — в post_step следующего такта
func hit(b_h: int, dmg_centi: int, attacker_h: int) -> void:
	if port is CombatPortStub:
		(port as CombatPortStub).test_hit_structure(b_h, dmg_centi, attacker_h)
	else:
		_extra_hits.append_array(PackedInt32Array([b_h, dmg_centi, attacker_h]))


## Флаги зеркала постройки в ядре (BattleSim.ST_*); −1 — зеркала нет
func structure_flags(b_h: int) -> int:
	if port is CombatPortStub:
		var st: Dictionary = (port as CombatPortStub).structures.get(b_h, {})
		return int(st["flags"]) if not st.is_empty() else -1
	var sim := port.battle()
	var i := Ids.slot(b_h)
	if sim == null or i >= sim.st_hw or sim.st_alive[i] == 0 or sim.st_ref[i] != b_h:
		return -1
	return sim.st_flags[i]


## Множители игрока в ядре (BattleSim.MOD_*), пусто — не задавались
func owner_mods(p: int) -> PackedFloat32Array:
	if port is CombatPortStub:
		return (port as CombatPortStub).owner_mods.get(p, PackedFloat32Array())
	var sim := port.battle()
	var out := PackedFloat32Array()
	for k in BattleSim.MOD_N:
		out.append(sim.owner_mod(p, k))
	return out
