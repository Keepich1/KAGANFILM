extends SceneTree
## Проверка перевода боя в анимации толпы (BattleView → AnimSpec) без графики:
##   godot --headless --path ordo --script res://tests/test_view.gd
## Клич → CHEER у полководца и конницы, залп → SHOOT у первой шеренги, разгон → CHARGE,
## погибшие → DYING, затем DEAD; фаза шага растёт на пройденный путь (ноги не скользят).

var _fails := 0


func _init() -> void:
	var sc := ScenarioClash.new()
	sc.loop = false
	sc.autostart = false
	var view := BattleView.new()
	view.force_debug = true
	sc.start(1)
	view.scenario = sc
	view._sim = sc.sim
	view._rebuild()
	var sim := sc.sim
	var seen := {"gen_cheer": false, "kip_cheer": false, "shoot": false, "reload": false, "charge": false,
		"gallop": false, "trot": false, "dying": false, "dead": false, "flee": false, "walk": false}
	var g := sim.general[1]
	var phase_ok := true
	while sim.time < 30.0:
		sc.step()
		var t := sim.time
		for u in sim.n:
			if view._u_layer[u] == "":
				continue
			var spd := Vector2(sim.u_vx[u], sim.u_vz[u]).length()
			var moved := spd * BattleSim.DT
			var c: Color
			if view._u_skel[u] == 0:
				var before := view._phase[u]
				c = view._human_custom(sim, u, t, spd, moved)
				var st := int(c.r)
				if st == AnimSpec.Human.SHOOT: seen["shoot"] = true
				if st == AnimSpec.Human.RELOAD: seen["reload"] = true
				if st == AnimSpec.Human.FLEE: seen["flee"] = true
				if st == AnimSpec.Human.WALK:
					seen["walk"] = true
					# фаза шага: прирост = путь / длина цикла
					var want := fposmod(before + moved / AnimSpec.STRIDE_HUMAN[AnimSpec.Human.WALK], 1.0)
					if absf(want - c.g) > 0.001:
						phase_ok = false
				if st == AnimSpec.Human.DYING: seen["dying"] = true
				if st == AnimSpec.Human.DEAD: seen["dead"] = true
			else:
				c = view._rider_custom(sim, u, t, spd, moved)
				var st := int(c.r)
				if st == AnimSpec.Horse.CHEER:
					if u == g:
						seen["gen_cheer"] = true
					else:
						seen["kip_cheer"] = true
				if st == AnimSpec.Horse.CHARGE: seen["charge"] = true
				if st == AnimSpec.Horse.GALLOP: seen["gallop"] = true
				if st == AnimSpec.Horse.TROT: seen["trot"] = true
				if st == AnimSpec.Horse.DYING: seen["dying"] = true
			if c.g < 0.0 or c.g > 1.0 or c.a < 0.0 or c.a > 1.0:
				_check(false, "фаза и вариант в 0..1 (юнит %d, t=%.2f)" % [u, t])
				break
	for k in seen:
		_check(seen[k], "состояние встречается: " + k)
	_check(phase_ok, "фаза шага идёт по пройденному пути")
	# слои: по одному на вид, ёмкость = число юнитов вида
	var counts: Dictionary = view._counts
	_check(counts.get("kok_sarboz", 0) == 99 and counts.get("kok_sarboz_banner", 0) == 1, "слои Коканда: 99 + знамя")
	_check(counts.get("kip_sayisker", 0) == 60 and counts.get("kip_sayisker_banner", 0) == 1, "слои кыпчаков: 59 + жүз башы, знамя")
	_check(counts.get("kip_kolbashchy", 0) == 1 and counts.get("kok_yuzboshi", 0) == 1, "полководец и юзбоши")
	view.free()
	sc.free()
	_test_loop()
	print("")
	print("ИТОГ: ", "ВСЁ ПРОШЛО" if _fails == 0 else "ПРОВАЛОВ: %d" % _fails)
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


## Бой по кругу: после конца сценарий начинается заново, вид пересобирает слои
func _test_loop() -> void:
	var sc := ScenarioClash.new()
	sc.loop = true
	sc.autostart = false
	root.add_child(sc)
	var starts := [0]
	sc.started.connect(func(_s: int) -> void: starts[0] += 1)
	sc.start(1)
	var view := BattleView.new()
	view.force_debug = true
	view.scenario = sc
	sc.started.connect(view._on_started)
	view._on_started(1)
	for i in int(46.0 / BattleSim.DT):
		sc.step()
	print("  (стартов: %d, время: %.2f, в дереве: %s)" % [starts[0], sc.time, sc.is_inside_tree()])
	_check(starts[0] == 2 and sc.time < 3.0, "бой начинается заново после %.0f с" % ScenarioClash.END_TIME)
	_check(view._sim == sc.sim and view._u_layer.size() == sc.sim.n, "вид пересобран под новый бой")
	view.free()
	sc.queue_free()
