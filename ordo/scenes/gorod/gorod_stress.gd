class_name GorodStress
extends RefCounted
## Нагрузка для замера вида «Города» (ARCHITECTURE §16: 1000 юнитов + 200 построек, вид ≤ 4 мс/кадр):
## добавляет в поддельный город (FakeCity — только для замера, это не правила игры) юнитов до units
## и построек до buildings на южном лугу. Юниты — как «город в покое»: ~60 % работников за работой
## (рубят, копают, строят, несут — Act.WORK), остальные — отряды в строю, часть ходит.

const AREA := Rect2(20, 190, 300, 150)

## Первый юнит нагрузки (−1 — нагрузки нет): серия кадров не берёт их в крупные планы работы
static var first_unit := -1


static func populate(city: FakeCity, units: int, buildings: int) -> void:
	if city == null:
		return
	var sim := city.sim
	first_unit = sim.n
	var rng := BattleRng.new(4242)
	var defs := city.defs()
	# постройки: дома (MultiMesh), юрты, склады, мастерские, звенья стены — сеткой по лугу
	var types := ["uy", "uy", "uy", "boz", "ombor", "tegirmon", "uy", "boz", "kazarma", "uy"]
	var bt := city.buildings()
	var have := 0
	for b in bt.hw:
		if bt.state[b] != BuildingTable.State.FREE:
			have += 1
	var i := 0
	while have < buildings:
		var col := i % 16
		var row := i / 16
		var p := AREA.position + Vector2(col * 18.0 + 6.0, row * 18.0 + 6.0)
		var id: String = types[i % types.size()]
		var owner := FakeCity.KOK if id != "boz" else FakeCity.KIP
		city.call("_add", owner, StringName(id), p, (i / 3) % 4)
		have += 1
		i += 1
	# юниты (все — Коканд, чтобы не завязался бой: замер вида, а не ядра): работники и отряды
	var aux := [AnimSpec.WORK_CHOP, AnimSpec.WORK_DIG, AnimSpec.WORK_BUILD, AnimSpec.WORK_CARRY]
	var troops := ["sarboz", "kilichboz", "sarboz", "nayzachi"]
	var k := 0
	while sim.n < units:
		var left := units - sim.n
		if k % 5 < 3 or left < 30:
			var p := AREA.position + Vector2(rng.range_f(0, AREA.size.x), rng.range_f(0, AREA.size.y))
			var s := sim.add_squad(FakeCity.KOK, "dehqon", 1, p, rng.range_f(-PI, PI), BattleSim.Formation.LINE, 1, "", false)
			sim.sq_single[s] = 1
			var u: int = sim.sq_members[s][0]
			var a: float = aux[k % 4]
			if a == AnimSpec.WORK_CARRY:
				sim.order_move(s, p + Vector2(rng.range_f(-40, 40), rng.range_f(-40, 40)), BattleSim.Gait.WALK)
			sim.u_work[u] = a
			sim.u_act[u] = BattleSim.Act.WORK
		else:
			var t: String = troops[k % troops.size()]
			var p := AREA.position + Vector2(rng.range_f(20, AREA.size.x - 20), AREA.size.y + 30.0 + rng.range_f(0, 60))
			var s := sim.add_squad(FakeCity.KOK, t, 30, p, PI, BattleSim.Formation.LINE, 10, "", true, 0.3)
			if k % 3 == 0:
				sim.order_move(s, p + Vector2(rng.range_f(-30, 30), rng.range_f(-20, 20)), BattleSim.Gait.WALK)
		k += 1
