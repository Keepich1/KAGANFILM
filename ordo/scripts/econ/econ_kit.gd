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


static func make(p_seed := 1, overrides := {}, p_port: CombatPort = null, p_nav: NavApi = null) -> EconKit:
	var k := EconKit.new()
	k.defs = Defs.shared() if overrides.is_empty() else Defs.build(overrides)
	k.rules = k.defs.rules_of(&"GOROD")
	k.events = SimEvents.new()
	k.nav = p_nav if p_nav else NavStub.new()
	k.port = p_port if p_port else CombatPortStub.new()
	k.econ = EconomySim.new()
	k.nav.setup(Terrain.info(), k.defs, k.econ, k.port)
	k.port.setup(k.defs, k.nav, {"teams": 2, "homes": PackedVector2Array(), "corpse_s": k.rules.get("corpse_s", -1),
		"bounds_origin": k.nav.origin, "bounds_size": Vector2(k.nav.w, k.nav.h) * NavApi.CELL})
	k.econ.setup(k.defs, k.rules, k.port, k.nav, k.events, p_seed)
	return k


func step() -> void:
	tick += 1
	events.tick = tick
	econ.pre_step(tick)
	nav.service(tick)
	port.deliver_paths()
	port.step()
	econ.post_step(tick, port.take_deaths(), port.take_structure_hits(), port.take_arrivals())
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
