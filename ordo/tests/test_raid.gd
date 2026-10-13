extends SceneTree
## Набеги ИИ (ТЗ 7; ARCHITECTURE §12, §15 GAME; ECONOMY §10):
##   • первая волна — в конец мирного периода ±2 с на каждой сложности; RAID_WARNING за 30 с;
##   • волны растут (×1,25), между началами волн 150–240 с, если набег кончился раньше;
##   • отход при потерях ≥ retreat.losses, выжившие уходят с края карты, RAID_ENDED;
##   • ≥ 60% убийств налётчиков — работники и стада, пока они есть: на настоящем ядре — по событиям
##     (UNIT_DIED с убийцей из волны по виду жертвы, HERD_STOLEN, BUILDING_DESTROYED налётчиком); на заглушке
##     боя нет — гибель и «урон» делает простая подмена боя (_proxy_combat);
##   • выбор цели: ценность минус риск, охраняемая клетка пропускается;
##   • ИИ ≤ 0.3 мс на такт в среднем.
## Реализации — GameSim.impl_for: по умолчанию настоящие (если они в проекте), --impl=stub или ORDO_IMPL=stub — заглушки.
##   godot --headless --path ordo --script res://tests/test_raid.gd [-- --impl=stub]


class Prof:
	var t0 := 0
	var acc := PackedInt64Array()
	var worst := PackedInt64Array()
	var _last := 0

	func _init() -> void:
		acc.resize(GameSim.Ph.COUNT)
		worst.resize(GameSim.Ph.COUNT)

	func begin() -> void:
		_last = Time.get_ticks_usec()

	func mark(ph: int) -> void:
		var now := Time.get_ticks_usec()
		var d := now - _last
		acc[ph] += d
		if d > worst[ph]:
			worst[ph] = d
		_last = now


var _impl := {}


func _init() -> void:
	_impl = GameSim.impl_for(OS.get_cmdline_user_args(), OS.get_environment("ORDO_IMPL"))
	print("реализации: ", _game(_pl(&"kokand", PlayerTable.Ctrl.HUMAN, &"kipchak", PlayerTable.Ctrl.AI)).impl_names())
	_test_first_raid()
	_test_waves_and_retreat()
	_test_targets_and_kills()
	_test_pick_target()
	SimHarness.finish(self)


func _game(players: Array, p_seed := 5) -> GameSim:
	var g := GameSim.new()
	g.impl = _impl.duplicate()
	g.setup(MapValley.MAP, players, p_seed)
	return g


func _pl(f0: StringName, c0: int, f1: StringName, c1: int, d := 0) -> Array:
	return [{"faction": f0, "team": 0, "ctrl": c0, "difficulty": d}, {"faction": f1, "team": 1, "ctrl": c1, "difficulty": d}]


func _director(g: GameSim, p: int) -> RaidDirector:
	for a in g.ai:
		if a is RaidDirector and a.player == p:
			return a
	return null


func _test_first_raid() -> void:
	print("[первая волна в конец мирного периода]")
	var peace: Array = Defs.shared().ai["RAID"]["peace_ticks"]
	var warn := int(Defs.shared().ai["RAID"]["warn_ticks"])
	for d in 3:
		var g := _game(_pl(&"kokand", PlayerTable.Ctrl.HUMAN, &"kipchak", PlayerTable.Ctrl.AI, d))
		var start_t := -1
		var warn_t := -1
		var warn_eta := -1
		var eta_ok := true
		var last_eta := 1 << 30
		var cursor := 0
		while g.tick < int(peace[d]) + 120 and start_t < 0:
			g.step()
			if g.tick % 300 == 0:
				var e := g.query.raid_eta_ticks(0)
				eta_ok = eta_ok and e >= 0 and e <= last_eta
				last_eta = e
			var r := g.events.range_since(cursor)
			for seq in range(r.x, r.y):
				var i := g.events.at(seq)
				match g.events.e_kind[i]:
					SimEvents.Ev.RAID_WARNING:
						warn_t = g.events.e_tick[i]
						warn_eta = g.events.e_a[i]
					SimEvents.Ev.RAID_STARTED:
						start_t = g.events.e_tick[i]
			cursor = r.y
		SimHarness.check_range((start_t - int(peace[d])) / 30.0, 0.0, 2.0,
			"сложность %d: первая волна на %.1f с (мир %d с)" % [d, start_t / 30.0, int(peace[d]) / 30])
		SimHarness.check(warn_t >= 0 and absi(warn_t + warn_eta - int(peace[d])) <= 30 and absi(warn_eta - warn) <= 30,
			"сложность %d: RAID_WARNING за %.1f с" % [d, warn_eta / 30.0])
		SimHarness.check(eta_ok, "сложность %d: raid_eta_ticks убывает в мирный период" % d)


func _test_waves_and_retreat() -> void:
	print("[рост волн, промежутки, отход при потерях]")
	var g := _game(_pl(&"kokand", PlayerTable.Ctrl.HUMAN, &"kipchak", PlayerTable.Ctrl.AI))
	var rd := _director(g, 1)
	var raid: Dictionary = g.defs.ai["RAID"]
	var iv: Array = raid["interval_ticks"]
	var losses := float(raid["retreat"]["losses"])
	var starts := PackedInt32Array()
	var sizes := PackedInt32Array()
	var ends := PackedInt32Array()
	var survivors := PackedInt32Array()
	var killed_wave := -1
	var retreat_after := -1
	var cursor := 0
	var port := g.port
	while g.tick < 30 * 60 * 20 and starts.size() < 4:
		g.step()
		var r := g.events.range_since(cursor)
		for seq in range(r.x, r.y):
			var i := g.events.at(seq)
			match g.events.e_kind[i]:
				SimEvents.Ev.RAID_STARTED:
					starts.append(g.events.e_tick[i])
					sizes.append(g.events.e_b[i])
				SimEvents.Ev.RAID_ENDED:
					ends.append(g.events.e_tick[i])
					survivors.append(g.events.e_b[i])
		cursor = r.y
		# на месте удара убиваем 45% волны — должен начаться отход
		if rd.state == RaidDirector.Phase.STRIKE and killed_wave != rd.wave:
			killed_wave = rd.wave
			var n := ceili(rd.size0 * (losses + 0.05))
			for k in n:
				port.kill(rd.wave_units[k])
			retreat_after = g.tick
		if retreat_after >= 0 and rd.state == RaidDirector.Phase.RETREAT:
			SimHarness.check(g.tick - retreat_after <= 60, "волна %d: отход через %.1f с после потерь" % [rd.wave, (g.tick - retreat_after) / 30.0])
			retreat_after = -1
	SimHarness.check(starts.size() >= 3, "за 20 мин — не меньше трёх волн (%d)" % starts.size())
	var grow_ok := true
	for k in range(1, sizes.size()):
		var want := 0
		var sm := 1000
		for j in k:
			sm = sm * 1250 / 1000
		want = (10 * sm + 500) / 1000
		grow_ok = grow_ok and sizes[k] == want
	SimHarness.check(grow_ok, "волны растут ×1,25: %s" % str(sizes))
	var gap_ok := true
	for k in range(1, starts.size()):
		var gap := starts[k] - starts[k - 1]
		var lo := int(iv[0])
		var hi := int(iv[1]) + 30
		var after_end := ends.size() >= k and starts[k] - ends[k - 1] <= RaidDirector.MIN_GAP_T + 30
		gap_ok = gap_ok and ((gap >= lo and gap <= hi) or after_end)
	SimHarness.check(gap_ok, "между волнами 150–240 с: %s" % str(_diff_s(starts)))
	var surv_ok := survivors.size() >= 2
	for k in survivors.size():
		var alive_max := sizes[k] + 1 - ceili(sizes[k] * (losses + 0.05))
		surv_ok = surv_ok and survivors[k] > 0 and survivors[k] <= alive_max + 1
	SimHarness.check(surv_ok, "выжившие ушли с края карты, RAID_ENDED: %s" % str(survivors))
	SimHarness.check(rd.wave_units.is_empty() or rd.state != RaidDirector.Phase.COOLDOWN, "после отхода волна пуста")


## Подмена боя на заглушке: налётчик в 4 м от вражеского работника убивает его; у стада в радиусе выпаса —
## «угоняет» (считаем один раз на стадо); у постройки, которую его отряду велено ломать, — «бьёт» её
## (раз в 5 с на постройку)
func _proxy_combat(g: GameSim, rd: RaidDirector, tally: Dictionary, herds_seen: Dictionary, hit_t: Dictionary) -> void:
	var q := g.query as GameQueryImpl
	var victim := rd.enemy
	var workers := PackedInt32Array()
	for u in q.units_of(victim):
		if q.unit_flags(u) & UnitStats.WORKER:
			workers.append(u)
	var H := g.econ.herds
	var herds_left := 0
	for h in H.hw:
		if H.owner[h] == victim and H.state[h] == HerdTable.State.PEN and not herds_seen.has(h):
			herds_left += 1
	var assets := workers.size() + herds_left > 0
	var B := g.econ.buildings
	var ordered := {}
	for s: int in rd._orders:
		ordered[rd._orders[s]] = true
	for u in rd.wave_units:
		if not q.unit_alive(u):
			continue
		var p := q.unit_pos(u)
		for w in workers:
			if q.unit_alive(w) and q.unit_pos(w).distance_squared_to(p) <= 16.0:
				g.port.kill(w)
				if assets:
					tally["worker"] += 1
				break
		for h in H.hw:
			if H.owner[h] == victim and H.state[h] == HerdTable.State.PEN and not herds_seen.has(h):
				if Vector2(H.x[h], H.z[h]).distance_squared_to(p) <= H.graze_r[h] * H.graze_r[h]:
					herds_seen[h] = true
					if assets:
						tally["herd"] += 1
		for b in B.hw:
			if B.owner[b] != victim or B.state[b] != BuildingTable.State.ACTIVE or not ordered.has(B.handle(b)):
				continue
			var half := g.defs.b_size[B.btype[b]].x * 0.5 + 2.0
			if Vector2(B.x[b], B.z[b]).distance_squared_to(p) <= half * half and g.tick - int(hit_t.get(b, -999)) >= 150:
				hit_t[b] = g.tick
				if assets:
					tally["building"] += 1


## Убийства налётчиков на настоящем ядре — по событиям такта: UNIT_DIED с убийцей из волны (работник или
## прочий юнит — по виду жертвы), HERD_STOLEN налётчиком, BUILDING_DESTROYED игроком-налётчиком. Считаются,
## пока у жертвы есть работники или стада в загонах (assets — до шага). raiders — все юниты волн (из
## UNIT_SPAWNED без постройки).
func _real_kills(g: GameSim, rd: RaidDirector, cursor: int, assets: bool, tally: Dictionary, raiders: Dictionary) -> int:
	var victim := rd.enemy
	var E := g.events
	var r := E.range_since(cursor)
	for seq in range(r.x, r.y):
		var i := E.at(seq)
		match E.e_kind[i]:
			SimEvents.Ev.UNIT_SPAWNED:
				if E.e_player[i] == rd.player and E.e_b[i] == Ids.NULL:
					raiders[E.e_a[i]] = true
			SimEvents.Ev.UNIT_DIED:
				if assets and E.e_player[i] == victim and raiders.has(E.e_b[i]):
					var ut := E.e_c[i]
					var fl := g.defs.u_flags[ut] if ut >= 0 and ut < g.defs.u_flags.size() else 0
					tally["worker" if fl & UnitStats.WORKER else "other"] += 1
			SimEvents.Ev.HERD_STOLEN:
				if assets and raiders.has(E.e_b[i]):
					tally["herd"] += 1
			SimEvents.Ev.BUILDING_DESTROYED:
				if assets and E.e_c[i] == rd.player:
					tally["building"] += 1
	return r.y


## У игрока есть работники или стада в загонах
func _has_assets(g: GameSim, p: int) -> bool:
	if p < 0:
		return false
	var q := g.query as GameQueryImpl
	for u in q.units_of(p):
		if q.unit_flags(u) & UnitStats.WORKER:
			return true
	var H := g.econ.herds
	for h in H.hw:
		if H.owner[h] == p and H.state[h] == HerdTable.State.PEN and H.heads(h) > 0:
			return true
	return false


func _test_targets_and_kills() -> void:
	var real := _game(_pl(&"kokand", PlayerTable.Ctrl.HUMAN, &"kipchak", PlayerTable.Ctrl.AI)).real_impl()
	print("[налётчики бьют работников и стада, пока они есть — %s]" % ("настоящий бой, по событиям" if real else "подмена боя на заглушке"))
	for pair in [[&"kokand", &"kipchak"], [&"kipchak", &"kokand"]]:
		var g := _game(_pl(pair[0], PlayerTable.Ctrl.HUMAN, pair[1], PlayerTable.Ctrl.AI), 9)
		var rd := _director(g, 1)
		var tally := {"worker": 0, "herd": 0, "building": 0, "other": 0}
		var herds_seen := {}
		var hit_t := {}
		var raiders := {}
		var cursor := 0
		var prof := Prof.new()
		g.prof = prof
		var ticks := 0
		# первая волна и 200 с после её начала (next_wave_t сдвигается после каждого набега — не гонимся за ним)
		var end_t := rd.next_wave_t + 30 * 200
		while g.tick < end_t:
			var assets := real and _has_assets(g, rd.enemy)
			prof.begin()
			g.step()
			ticks += 1
			if real:
				cursor = _real_kills(g, rd, cursor, assets, tally, raiders)
			elif g.tick % 10 == 0 and (rd.state == RaidDirector.Phase.MARCH or rd.state == RaidDirector.Phase.STRIKE):
				_proxy_combat(g, rd, tally, herds_seen, hit_t)
		var good: int = tally["worker"] + tally["herd"]
		var total: int = good + tally["building"] + tally["other"]
		SimHarness.check(total > 0 and good * 100 >= total * 60,
			"%s грабят %s: работники %d, стада %d, постройки %d, прочие %d (пока есть работники и стада)" % [pair[1],
			pair[0], tally["worker"], tally["herd"], tally["building"], tally["other"]])
		var ai_ms := prof.acc[GameSim.Ph.AI] / 1000.0 / ticks
		SimHarness.check(ai_ms <= 0.3, "ИИ в среднем %.4f мс/такт (худший такт %.2f мс)" % [ai_ms, prof.worst[GameSim.Ph.AI] / 1000.0])


func _test_pick_target() -> void:
	print("[выбор цели: ценность минус риск]")
	var g := _game(_pl(&"kokand", PlayerTable.Ctrl.HUMAN, &"kipchak", PlayerTable.Ctrl.AI))
	var rd := _director(g, 1)
	var q := g.query as GameQueryImpl
	var econ := g.econ
	var ws := PackedInt32Array()
	for u in q.units_of(0):
		if q.unit_flags(u) & UnitStats.WORKER:
			ws.append(u)
	var wc := Vector2.ZERO
	for w in ws:
		wc += q.unit_pos(w)
	wc /= ws.size()
	SimHarness.check(rd._pick_target(q, 10) and rd.target.distance_to(wc) < 12.0,
		"цель — работники у урды (%.0f м от их середины)" % rd.target.distance_to(wc))
	# два дома в стороне: 40 очков против 60 у работников — работники всё ещё дороже
	econ.spawn_building(0, g.defs.building(&"uy"), Vector2(210, 140), 0)
	econ.spawn_building(0, g.defs.building(&"uy"), Vector2(222, 140), 0)
	rd._pick_target(q, 10)
	SimHarness.check(rd.target.distance_to(wc) < 12.0, "работники (60) дороже двух домов (40)")
	# 30 бойцов у работников: охраны больше 1,5 × 10 — клетка пропускается, цель — дома
	g.port.spawn_squad(0, 0, &"nayzachi", 30, wc + Vector2(0, 6), 0.0)
	rd._pick_target(q, 10)
	SimHarness.check(rd.target.distance_to(Vector2(216, 140)) < 12.0, "охраняемая клетка пропущена — цель дома (%s)" % str(rd.target))
	# большой волне (30) охрана не страшна, но вычитается: 60 − 30 × 5 < 40 — всё равно дома
	rd._pick_target(q, 30)
	SimHarness.check(rd.target.distance_to(Vector2(216, 140)) < 12.0, "охрана вычитается из ценности")


func _diff_s(a: PackedInt32Array) -> Array:
	var out: Array = []
	for k in range(1, a.size()):
		out.append(snappedf((a[k] - a[k - 1]) / 30.0, 0.1))
	return out
