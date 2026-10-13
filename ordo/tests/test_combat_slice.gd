extends SceneTree
## Ворота среза для ядра (CORE, ARCHITECTURE §18): поведение боя среза не меняется ни на бит.
##   godot --headless --path ordo --script res://tests/test_combat_slice.gd
## Сверяет отпечатки состояния (позиции, курсы, скорости, HP, жизнь, действия, цели, мораль,
## выносливость, якоря строя) каждую секунду сценария среза (зёрна 1, 2, 3, 7; 44 с) и нагрузочной
## свалки 1213 юнитов (10 с) с записанными до работ «Города». Отпечатки сняты на коде f145492 (M0).
## Ключ --print печатает новые отпечатки (после намеренной смены поведения среза — только с ведущим).

## Отпечатки до работ «Города» (f145492)
const WANT := {"clash_1": 1514418571, "clash_2": 359334764, "clash_3": 979314233, "clash_7": 1144631844,
	"melee_3": 1052404614}

var _fails := 0


func _init() -> void:
	var show := "--print" in OS.get_cmdline_user_args()
	var got := {}
	for sd in [1, 2, 3, 7]:
		got["clash_%d" % sd] = _clash(sd)
	got["melee_3"] = _melee(3)
	for k: String in got:
		print("  %s: %d" % [k, got[k]])
		if not show:
			_check(WANT.get(k, -1) == got[k], "отпечаток %s совпадает со срезом" % k)
	print("")
	print("ИТОГ: ", "ВСЁ ПРОШЛО" if _fails == 0 else "ПРОВАЛОВ: %d" % _fails)
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _clash(sd: int) -> int:
	var sc := ScenarioClash.new()
	sc.loop = false
	sc.start(sd)
	var h := 17
	var steps := int(round(44.0 / BattleSim.DT))
	for i in steps:
		sc.step()
		if i % 30 == 29:
			h = _mix(h, _digest(sc.sim))
	h = _mix(h, sc.sim.winner + 7)
	sc.free()
	return h


func _melee(sd: int) -> int:
	var sim := BattleSim.new(sd)
	var squads_a: Array[int] = []
	var squads_b: Array[int] = []
	for k in 6:
		squads_a.append(sim.add_squad(0, "sarboz" if k % 2 == 0 else "nayzachi", 100,
			Vector2(60.0, -150.0 + k * 55.0), -PI / 2, BattleSim.Formation.LINE, 50, "yuzboshi"))
		squads_b.append(sim.add_squad(1, "sayisker" if k % 2 == 0 else "jooker", 100,
			Vector2(-20.0, -150.0 + k * 55.0), PI / 2, BattleSim.Formation.LINE, 50, "juz_bashy"))
	sim.add_general(1, "kolbashchy", Vector2(-40.0, 0.0), PI / 2)
	for k in 6:
		sim.order_attack(squads_b[k], squads_a[k], BattleSim.Gait.RUN)
		sim.allow_charge(squads_b[k])
		sim.set_fire(squads_a[k], squads_b[k], 70.0)
	var h := 17
	for i in 300:
		sim.step()
		if i % 30 == 29:
			h = _mix(h, _digest(sim))
	return h


static func _mix(h: int, v: int) -> int:
	return (h * 31 + v) & 0x7FFFFFFF


## Отпечаток состояния: всё, что видно и что решает дальше
static func _digest(sim: BattleSim) -> int:
	var h := sim.checksum()
	for u in sim.n:
		h = _mix(h, int(sim.u_h[u] * 10000.0))
		h = _mix(h, int(sim.u_vx[u] * 10000.0))
		h = _mix(h, int(sim.u_vz[u] * 10000.0))
		h = _mix(h, sim.u_act[u] * 7 + sim.u_target[u])
		h = _mix(h, int(sim.u_act_t[u] * 1000.0))
		h = _mix(h, sim.u_ammo[u] + sim.u_couched[u] * 3 + sim.u_charged[u] * 5)
	for s in sim.squads:
		h = _mix(h, int(sim.sq_x[s] * 1000.0))
		h = _mix(h, int(sim.sq_z[s] * 1000.0))
		h = _mix(h, int(sim.sq_h[s] * 10000.0))
		h = _mix(h, int(sim.sq_stam[s] * 100.0))
		h = _mix(h, sim.sq_order[s] * 11 + sim.sq_status[s] * 3 + sim.sq_melee[s])
	h = _mix(h, sim.rng.state & 0x7FFFFFFF)
	return h
