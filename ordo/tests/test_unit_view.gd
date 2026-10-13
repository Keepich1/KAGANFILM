extends SceneTree
## Юниты «Города» (UnitView, ARCHITECTURE §13, §15 VIEW) без графики:
##   godot --headless --path ordo --script res://tests/test_unit_view.gd
## • места в слоях: 10 000 случайных рождений/освобождений/смертей (как R1: FREE, новое поколение,
##   другой тип на том же индексе) — после каждой сверки места плотные (0..count−1), slot_of ↔ unit_of_slot,
##   свободные мест не держат, число мест = числу живых и павших с видом; слой растёт с 512 вдвое;
## • работа: Act.WORK → AnimSpec.Human.WORK с видом работы (рубит/копает/строит — цикл по времени,
##   несёт — фаза шага по пройденному пути), идущий к работе с инструментом — WALK, павший — не WORK;
## • заместители: деҳқон рисуется малчы в кокандском атласе, юнит без вида и заместителя — без места;
## • тела перед уборкой (corpse_steps) уходят в землю за последние 3 с.

const H := AnimSpec.Human

var _fails := 0
var _checks := 0


func _init() -> void:
	_test_slots()
	_test_work()
	_test_sink()
	print("")
	if _fails == 0:
		print("ИТОГ: ВСЁ ПРОШЛО (%d проверок)" % _checks)
		quit(0)
	else:
		print("ИТОГ: ПРОВАЛЕНО %d из %d" % [_fails, _checks])
		quit(1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL ", what)


func _view(sim: BattleSim) -> UnitView:
	var v := UnitView.new()
	v.force_debug = true
	v.cull = false
	root.add_child(v)
	v.bind(sim)
	return v


## Число юнитов, которым положено место (не FREE, есть вид или заместитель)
func _expected(sim: BattleSim, v: UnitView) -> int:
	var c := 0
	for u in sim.n:
		if sim.u_life[u] != BattleSim.Life.FREE and v.layer_key(sim.type_of(u), sim.u_role[u] == BattleSim.Role.BANNER) != "":
			c += 1
	return c


func _test_slots() -> void:
	print("Места в слоях (10 000 операций)")
	var sim := BattleSim.new(3)
	var types := ["sarboz", "jooker", "dehqon", "malchy", "kilichboz", "yuzboshi"]
	for t in types:
		sim.add_squad(0, t, 1, Vector2(10, 10), 0.0, BattleSim.Formation.LINE, 1, "", false)
	var tidx := PackedInt32Array()
	for t in types:
		tidx.append(sim.type_index(t))
	var v := _view(sim)
	var rng := BattleRng.new(99)
	# рост слоя: 1200 одного вида сразу (512 → 1024 → 2048)
	for i in 1200:
		sim.add_squad(0, "dehqon", 1, Vector2(rng.range_f(-50, 50), rng.range_f(-50, 50)), 0.0, BattleSim.Formation.LINE, 1, "", false)
	v.sync_slots()
	var err := v.check_slots()
	_check(err == "", "после 1200 рождений: " + err)
	_check(v.used_slots() == _expected(sim, v), "мест %d, ожидалось %d" % [v.used_slots(), _expected(sim, v)])
	var li := v.l_key.find("kip_malchy|kokand")
	_check(li >= 0, "деҳқон рисуется заместителем kip_malchy|kokand")
	if li >= 0:
		_check(int(v.l_node[li].get("capacity")) >= 1024, "слой вырос вдвое: ёмкость %d" % int(v.l_node[li].get("capacity")))
	var bad_once := ""
	for op in 10000:
		var r := rng.range_i(100)
		if r < 40:
			# рождение: свободный индекс (как R1) или новый в конце
			var free := -1
			if rng.range_i(2) == 0:
				for k in 20:
					var u := rng.range_i(sim.n)
					if sim.u_life[u] == BattleSim.Life.FREE:
						free = u
						break
			if free >= 0:
				sim.u_life[free] = BattleSim.Life.ALIVE
				sim.u_gen[free] = Ids.next_gen(sim.u_gen[free])
				sim.u_type[free] = tidx[rng.range_i(tidx.size())]
				sim.u_act[free] = BattleSim.Act.NONE
			else:
				sim.add_squad(rng.range_i(2), types[rng.range_i(types.size())], 1,
					Vector2(rng.range_f(-80, 80), rng.range_f(-80, 80)), 0.0, BattleSim.Formation.LINE, 1, "", false)
		elif r < 80:
			# уборка тела / освобождение
			var u := rng.range_i(sim.n)
			sim.u_life[u] = BattleSim.Life.FREE
		elif r < 95:
			var u := rng.range_i(sim.n)
			if sim.u_life[u] == BattleSim.Life.ALIVE:
				sim.u_life[u] = BattleSim.Life.DEAD
				sim.u_death_t[u] = sim.time
		else:
			# смена поколения без FREE между сверками (освободили и тут же заняли)
			var u := rng.range_i(sim.n)
			if sim.u_life[u] != BattleSim.Life.FREE:
				sim.u_gen[u] = Ids.next_gen(sim.u_gen[u])
				sim.u_type[u] = tidx[rng.range_i(tidx.size())]
		if op % 7 == 0 or op == 9999:
			v.sync_slots()
			var e := v.check_slots()
			if e == "" and v.used_slots() != _expected(sim, v):
				e = "мест %d, ожидалось %d" % [v.used_slots(), _expected(sim, v)]
			if e != "" and bad_once == "":
				bad_once = "операция %d: %s" % [op, e]
		if op % 500 == 0:
			v.update_view()
	_check(bad_once == "", "инварианты мест: " + bad_once)
	# видимых — ровно занятых
	var vis := 0
	for l in v.l_node:
		vis += int(l.call("get_visible_count"))
	_check(vis == v.used_slots(), "видимых экземпляров %d = мест %d" % [vis, v.used_slots()])
	print("  юнитов ядра %d, мест %d, слоёв %d" % [sim.n, v.used_slots(), v.l_node.size()])
	v.free()


func _test_work() -> void:
	print("Работа → AnimSpec.Human.WORK")
	var sim := BattleSim.new(5)
	var s := sim.add_squad(0, "dehqon", 1, Vector2(0, 0), 0.0, BattleSim.Formation.LINE, 1, "", false)
	var u: int = sim.sq_members[s][0]
	var v := _view(sim)
	v.sync_slots()
	var t := 10.0
	for aux: float in [AnimSpec.WORK_CHOP, AnimSpec.WORK_DIG, AnimSpec.WORK_BUILD]:
		sim.u_act[u] = BattleSim.Act.WORK
		sim.u_work[u] = aux
		var c := v.custom_for(u, t, 0.0, 0.0)
		_check(int(c.r) == H.WORK, "вид %.2f: состояние WORK (%d)" % [aux, int(c.r)])
		_check(is_equal_approx(c.b, aux), "вид %.2f: z = вид работы (%.2f)" % [aux, c.b])
		_check(c.g >= 0.0 and c.g < 1.0, "вид %.2f: фаза в 0..1" % aux)
		var c2 := v.custom_for(u, t + 0.4, 0.0, 0.0)
		_check(not is_equal_approx(c.g, c2.g), "вид %.2f: цикл идёт по времени" % aux)
		# к работе идёт с инструментом — шагает
		var cw := v.custom_for(u, t, 1.2, 0.04)
		_check(int(cw.r) == H.WALK, "вид %.2f в пути: WALK (%d)" % [aux, int(cw.r)])
	sim.u_work[u] = AnimSpec.WORK_CARRY
	var before := v.custom_for(u, t, 0.0, 0.0).g
	var cc := v.custom_for(u, t, 1.2, 0.3)
	_check(int(cc.r) == H.WORK and is_equal_approx(cc.b, AnimSpec.WORK_CARRY), "несёт: WORK с видом CARRY")
	var want := fposmod(before + 0.3 / AnimSpec.STRIDE_HUMAN[H.WALK], 1.0)
	_check(absf(cc.g - want) < 0.001, "несёт: фаза шага по пути (%.3f ≈ %.3f)" % [cc.g, want])
	var still := v.custom_for(u, t + 1.0, 0.0, 0.0)
	_check(is_equal_approx(still.g, cc.g), "несёт, стоит: фаза не бежит")
	sim.u_act[u] = BattleSim.Act.NONE
	_check(int(v.custom_for(u, t, 0.0, 0.0).r) == H.IDLE, "без работы: IDLE")
	sim.u_act[u] = BattleSim.Act.WORK
	sim.u_life[u] = BattleSim.Life.DEAD
	_check(int(v.custom_for(u, t, 0.0, 0.0).r) == H.DEAD, "павший работник: DEAD, не WORK")
	# заместители и юниты без вида
	_check(v.layer_key("dehqon", false) == "kip_malchy|kokand", "деҳқон → kip_malchy в атласе Коканда")
	_check(v.layer_key("sarboz", true) == "kok_sarboz_banner|", "знаменосец сарбозов → свой вид")
	_check(v.layer_key("arba", false) == "", "арба — не слой толпы (своя модель)")
	v.free()


func _test_sink() -> void:
	print("Тела уходят в землю перед уборкой")
	var sim := BattleSim.new(7)
	sim.corpse_steps = 30 * 30
	var s := sim.add_squad(0, "dehqon", 1, Vector2(20, 20), 0.0, BattleSim.Formation.LINE, 1, "", false)
	var u: int = sim.sq_members[s][0]
	var v := _view(sim)
	sim.u_life[u] = BattleSim.Life.DEAD
	sim.time = 100.0
	var ground := Terrain.height_at(20, 20)
	var ys := []
	for age: float in [5.0, 28.5, 29.9]:
		sim.u_death_t[u] = sim.time - age
		v.update_view()
		var li := v.layer_of[u]
		var buf: PackedFloat32Array = v.l_node[li].get("_buf")
		ys.append(buf[v.slot_of[u] * 16 + 7])
	_check(absf(float(ys[0]) - ground) < 0.01, "за 25 с до уборки — на земле (%.2f ≈ %.2f)" % [ys[0], ground])
	_check(float(ys[1]) < ground - 0.1 and float(ys[2]) < float(ys[1]), "в последние 3 с — уходит вниз (%.2f → %.2f)" % [ys[1], ys[2]])
	v.free()
