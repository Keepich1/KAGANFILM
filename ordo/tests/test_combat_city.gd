extends SceneTree
## Ядро «Города» через CombatPortBattle (ARCHITECTURE §15, строка CORE):
##   godot --headless --path ordo --script res://tests/test_combat_city.gd
## • 5000 случайных spawn/kill/remove/шагов: описатели гаснут, n ограничен, смерть — одна запись;
## • отряд из 100 + офицер + знамя собирается из одиночек и распускается обратно;
## • 1000 одиночек без дела ≤ 2 мс/шаг (сон); свалка 1213 в городе не медленнее, чем в срезе;
## • за 60 с ходьбы через постройки и закрытые клетки никто не стоит внутри; пролом сквозь постройку;
## • урон по постройке ±10% от формулы (рукопашная и мушкеты);
## • работники (DEFENSIVE) не гонятся дальше 6 м; спящие просыпаются от врага;
## • прибытие — одна запись на приказ; два прогона — одна сумма; сохранение и загрузка — та же сумма.
## Числа замеров печатаются (процессорное время потока).

const NavStubScript := preload("res://scripts/contract/nav_stub.gd")

var _nav: NavApi


func _init() -> void:
	_test_lifecycle()
	_test_form_disband()
	_test_obstacles()
	_test_breach()
	_test_structure_dps()
	_test_defensive_and_sleep()
	_test_events()
	_test_ranged()
	_test_determinism_and_save()
	_test_perf()
	SimHarness.finish(self)


# ================================================================= помощники

func _make_port(extra := {}, nav: NavApi = null) -> CombatPortBattle:
	var defs := Defs.shared()
	_nav = nav if nav else NavStub.new()
	_nav.setup(Terrain.info(), defs, null, null)
	var port := CombatPortBattle.new()
	var cfg := {"teams": 2, "homes": PackedVector2Array([Vector2(400, 0), Vector2(-400, 0)]), "corpse_s": 30.0,
		"bounds_origin": _nav.origin, "bounds_size": Vector2(_nav.w, _nav.h) * NavApi.CELL, "seed": 5}
	cfg.merge(extra, true)
	port.setup(defs, _nav, cfg)
	return port


## Такт как в GameSim (§5.1): служба путей → доставка → шаг ядра
func _tick(port: CombatPortBattle, k := 1) -> void:
	for i in k:
		_nav.service(port.tick)
		port.deliver_paths()
		port.step()


func _cpu_us() -> int:
	var f := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
	if f:
		return int(f.get_line().split(" ")[0]) / 1000
	return Time.get_ticks_usec()


func _bh(slot: int) -> int:
	return Ids.make(Ids.Kind.BUILDING, slot, 1)


# ================================================================= жизнь слотов

func _test_lifecycle() -> void:
	print("[жизнь: 5000 случайных действий]")
	var port := _make_port({"corpse_s": 0.5})
	var sim := port.sim
	var rng := BattleRng.new(11)
	var base := SimHarness.flat_spot()
	var live: Array[int] = []          # описатели, которые должны быть живы
	var gone: Array[int] = []          # убраны (remove) — сразу недействительны
	var killed: Array[int] = []        # убиты — тело лежит, потом слот свободен
	var types := ["sarboz", "jooker", "dehqon", "sayisker"]
	var peak := 0
	var stale_ok := true
	var deaths := 0
	var kills := 0
	var spawned_since_step := 0
	var spawned_max := 0
	var bad_inv := ""
	for op in 5000:
		var r := rng.range_i(100)
		if r < 35 or live.size() < 5:
			var p := base + Vector2(rng.range_f(-60, 60), rng.range_f(-60, 60))
			if r % 7 == 0:
				var sh := port.spawn_squad(0, 0, types[rng.range_i(2)], 3 + rng.range_i(4), p, 0.0)
				for h in port.members(sh):
					live.append(h)
					spawned_since_step += 1
			else:
				live.append(port.spawn(0, 0, types[rng.range_i(types.size())], p, 0.0))
				spawned_since_step += 1
		elif r < 55:
			var i := rng.range_i(live.size())
			var h: int = live[i]
			live.remove_at(i)
			port.kill(h)
			killed.append(h)
			kills += 1
		elif r < 70:
			var i := rng.range_i(live.size())
			var h: int = live[i]
			live.remove_at(i)
			port.remove(h)
			gone.append(h)
			if port.valid(h):
				stale_ok = false
		else:
			spawned_max = maxi(spawned_max, spawned_since_step)
			spawned_since_step = 0
			_tick(port, 1 + rng.range_i(3))
			deaths += port.take_deaths().size() / 2
			if op % 50 == 0 and bad_inv == "":
				bad_inv = _city_invariants(sim)
		var used := 0
		for u in sim.n:
			if sim.u_life[u] != BattleSim.Life.FREE:
				used += 1
		peak = maxi(peak, used)
	# все тела успевают исчезнуть
	_tick(port, 120)
	deaths += port.take_deaths().size() / 2
	var live_ok := true
	for h in live:
		if not port.alive(h):
			live_ok = false
	for h in gone + killed:
		if port.valid(h):
			stale_ok = false
	SimHarness.check(live_ok, "живые описатели действительны и живы (%d)" % live.size())
	SimHarness.check(stale_ok, "убранные и истлевшие описатели недействительны (%d + %d)" % [gone.size(), killed.size()])
	SimHarness.check(sim.n <= peak + spawned_max, "n ограничен: n = %d, пик занятых %d, за такт рождалось ≤ %d" % [sim.n, peak, spawned_max])
	SimHarness.check(deaths == kills, "одна запись смерти на смерть (%d из %d)" % [deaths, kills])
	var used_squads := 0
	for s in sim.squads:
		used_squads += sim.sq_used[s]
	SimHarness.check(sim.squads <= peak + spawned_max, "отрядов-слотов %d, занято %d" % [sim.squads, used_squads])
	if bad_inv == "":
		bad_inv = _city_invariants(sim)
	SimHarness.check(bad_inv == "", "бодрые и хэш города сходятся с полным пересчётом %s" % bad_inv)


## Списки города против пересчёта с нуля (после шага): бодрые (_aw) — по возрастанию, без повторов, все
## бодрые живые и падающие в них (или в _aw_add); хэш — каждый живой в клетке своей позиции, списки
## клеток целы, маски клеток, блоков и «рядом» (_bmask_n) равны пересчитанным; смешанные блоки — в _mixed.
## Пусто — всё сходится, иначе — что не так.
func _city_invariants(sim: BattleSim) -> String:
	var aw := sim._aw
	for i in aw.size():
		if i > 0 and aw[i] <= aw[i - 1]:
			return "(_aw не по возрастанию)"
		if sim._aw_on[aw[i]] != 1:
			return "(_aw_on)"
	for u in sim.n:
		var lf := sim.u_life[u]
		var need := lf == BattleSim.Life.DYING or (lf == BattleSim.Life.ALIVE and sim.u_sleep[u] == 0)
		if need and sim._aw_on[u] == 0 and not sim._aw_add.has(u):
			return "(бодрый %d вне списков)" % u
	var gn := sim._g_n
	var go := sim._g_origin
	var cm := PackedInt32Array()
	cm.resize(gn * gn)
	var seen := 0
	for c in gn * gn:
		var v := sim._head[c]
		var p := -1
		while v >= 0:
			if sim._hprev[v] != p or sim._ucell[v] != c:
				return "(список клетки %d)" % c
			if sim.u_life[v] != BattleSim.Life.ALIVE:
				return "(в хэше не живой %d)" % v
			cm[c] |= 1 << sim.u_side[v]
			seen += 1
			p = v
			v = sim._next[v]
		if cm[c] != sim._cmask[c]:
			return "(маска клетки %d)" % c
	var alive := 0
	for u in sim.n:
		if sim.u_life[u] != BattleSim.Life.ALIVE:
			continue
		alive += 1
		var c2 := clampi(int((sim.u_z[u] - go) / 4.0), 0, gn - 1) * gn + clampi(int((sim.u_x[u] - go) / 4.0), 0, gn - 1)
		if sim._ucell[u] != c2:
			return "(юнит %d не в своей клетке)" % u
	if alive != seen:
		return "(живых %d, в хэше %d)" % [alive, seen]
	var bn := sim._b_n
	var bm := PackedInt32Array()
	bm.resize(bn * bn)
	for c in gn * gn:
		bm[((c / gn) >> 2) * bn + ((c % gn) >> 2)] |= cm[c]
	for b in bn * bn:
		if bm[b] != sim._bmask[b]:
			return "(маска блока %d)" % b
		var m := 0
		for z in range(maxi(b / bn - 1, 0), mini(b / bn + 1, bn - 1) + 1):
			for x in range(maxi(b % bn - 1, 0), mini(b % bn + 1, bn - 1) + 1):
				m |= bm[z * bn + x]
		if m != sim._bmask_n[b]:
			return "(«рядом» блока %d)" % b
		if m & (m - 1) != 0 and sim._mx_on[b] != 1:
			return "(смешанный блок %d не в _mixed)" % b
	return ""


# ================================================================= отряд из одиночек

func _test_form_disband() -> void:
	print("[сбор и роспуск отряда]")
	var port := _make_port()
	var sim := port.sim
	var base := SimHarness.flat_spot()
	var hs := PackedInt32Array()
	for k in 120:
		hs.append(port.spawn(0, 0, &"sarboz", base + Vector2((k % 12) * 2.0 - 12.0, (k / 12) * 2.0 - 10.0), 0.0))
	var off := port.spawn(0, 0, &"yuzboshi", base + Vector2(0, 14), 0.0)
	var old_sq := port.squad_of(hs[0])
	var s_h := port.form_squad(off, hs)
	var s := Ids.slot(s_h)
	var m := port.members(s_h)
	var banner := sim.sq_banner[s]
	SimHarness.check(s_h != 0 and m.size() == 101, "офицер + 100 бойцов (%d)" % m.size())
	SimHarness.check(sim.sq_officer[s] == Ids.slot(off) and sim.u_role[Ids.slot(off)] == BattleSim.Role.OFFICER, "офицер — OFFICER")
	SimHarness.check(banner >= 0 and sim.u_role[banner] == BattleSim.Role.BANNER, "знаменосец есть")
	SimHarness.check(not port.valid(old_sq), "прежний отряд одиночки освобождён")
	var singles_left := 0
	for h in hs:
		if sim.sq_single[sim.u_squad[Ids.slot(h)]] == 1:
			singles_left += 1
	SimHarness.check(singles_left == 20, "лишние 20 остались одиночками (%d)" % singles_left)
	port.move(PackedInt32Array([s_h]), base + Vector2(0, 40))
	_tick(port, 600)
	var lag := 0.0
	var cnt := 0
	for u in sim.sq_members[s]:
		if sim.u_role[u] == BattleSim.Role.TROOPER:
			lag += sim.slot_point(s, u).distance_to(Vector2(sim.u_x[u], sim.u_z[u]))
			cnt += 1
	SimHarness.check_range(lag / cnt, 0.0, 1.0, "строй собрался и дошёл: отставание, м")
	SimHarness.check(port.pos(s_h).distance_to(base + Vector2(0, 40)) < 8.0, "отряд у цели")
	var us := port.disband(s_h)
	var all_single := true
	for h in us:
		if not port.alive(h) or sim.sq_single[sim.u_squad[Ids.slot(h)]] != 1:
			all_single = false
	SimHarness.check(us.size() == 101 and all_single, "роспуск: 101 одиночка, те же описатели")
	SimHarness.check(not port.valid(s_h), "описатель распущенного отряда недействителен")
	_tick(port, 30)


# ================================================================= препятствия

func _test_obstacles() -> void:
	print("[препятствия: 60 с ходьбы]")
	var dn := DetourNav.new()
	var port := _make_port({}, dn)
	var sim := port.sim
	var base := SimHarness.flat_spot()
	dn.boxes = [[base, Vector2(5, 5), 0.0], [base + Vector2(-14, 18), Vector2(9, 3), 0.5],
		[base + Vector2(-24, -18), Vector2(6, 2), 0.0]]
	# постройки: дом, длинный амбар под углом, поле (по нему ходят), ворота команды 0
	port.structure_set(_bh(1), 1, base + Vector2(0, 0), Vector2(5, 5), 0.0, BattleSim.ST_BLOCK)
	port.structure_set(_bh(2), 1, base + Vector2(-14, 18), Vector2(9, 3), 0.5, BattleSim.ST_BLOCK)
	port.structure_set(_bh(3), 1, base + Vector2(16, -16), Vector2(8, 8), 0.0, BattleSim.ST_FIELD)
	port.structure_set(_bh(4), 0, base + Vector2(18, 16), Vector2(3, 1), 0.0, BattleSim.ST_GATE)
	# закрытые клетки земли: полоса 3 × 1 клетки
	var blk := PackedByteArray()
	blk.resize(_nav.w * _nav.h)
	var c0 := _nav.cell_of(base + Vector2(-30, -18))
	for k in 3:
		blk[c0 + k] = 1
	sim.set_grids(_nav.origin, _nav.w, _nav.h, blk, PackedByteArray())
	var groups: Array[PackedInt32Array] = []
	groups.append(PackedInt32Array([port.spawn_squad(0, 0, &"jooker", 40, base + Vector2(-40, -30), 0.0, &"", 0, 10)]))
	groups.append(PackedInt32Array([port.spawn_squad(0, 0, &"sayisker", 20, base + Vector2(40, -40), 0.0, &"", 0, 10)]))
	var singles := PackedInt32Array()
	for k in 30:
		singles.append(port.spawn(0, 0, &"dehqon" if k % 2 == 0 else &"sarboz", base + Vector2(-30 + k * 2.0, 35), PI))
	groups.append(singles)
	var goals := [[base + Vector2(30, 30), base + Vector2(-35, -32)], [base + Vector2(-40, 30), base + Vector2(35, -35)],
		[base + Vector2(0, -35), base + Vector2(-10, 38)]]
	var bad := 0
	for t in 1800:
		if t % 900 == 0:
			for g in groups.size():
				port.move(groups[g], goals[g][(t / 900) % 2], t % 1800 >= 900)
		_tick(port)
		for u in sim.n:
			if sim.u_life[u] != BattleSim.Life.ALIVE:
				continue
			var x := sim.u_x[u]
			var z := sim.u_z[u]
			for st in [1, 2]:
				if _inside(sim, st, x, z):
					bad += 1
			if sim.point_blocked(x, z, 0) and not _inside(sim, 4, x, z) and not _inside(sim, 3, x, z):
				var gx := floori((x - _nav.origin.x) / NavApi.CELL)
				var gz := floori((z - _nav.origin.y) / NavApi.CELL)
				if blk[gz * _nav.w + gx] == 1:
					bad += 1
	SimHarness.check(bad == 0, "никто не стоит внутри построек и закрытых клеток (нарушений %d)" % bad)
	var near := 0
	var total := 0
	for g in groups.size():
		for h in groups[g]:
			var goal: Vector2 = goals[g][1]
			total += 1
			if port.pos(h).distance_to(goal) < 14.0:
				near += 1
			else:
				print("    не дошёл: группа %d, %s → %s" % [g, port.pos(h), goal])
	SimHarness.check(near * 10 >= total * 9, "дошли до цели путями в обход: %d из %d" % [near, total])


func _inside(sim: BattleSim, st: int, x: float, z: float) -> bool:
	var c := cos(sim.st_rot[st])
	var sn := sin(sim.st_rot[st])
	var dx := x - sim.st_cx[st]
	var dz := z - sim.st_cz[st]
	return absf(dx * c - dz * sn) < sim.st_hx[st] - 0.01 and absf(dx * sn + dz * c) < sim.st_hz[st] - 0.01


# ================================================================= пролом

func _test_breach() -> void:
	print("[пролом: путь сквозь вражескую постройку]")
	var bnav := BreachNav.new()
	var port := _make_port({}, bnav)
	var sim := port.sim
	var base := SimHarness.flat_spot()
	var b := _bh(9)
	# постройка команды 0 поперёк дороги; обхода нет — путь кыпчаков ломает её (NAV §9 c)
	port.structure_set(b, 0, base, Vector2(3, 10), 0.0, BattleSim.ST_BLOCK)
	bnav.breach_h = b
	bnav.breach_pt = base + Vector2(-6, 0)
	var sh := port.spawn_squad(1, 1, &"chabuulchu", 20, base + Vector2(-40, 0), PI / 2, &"", 0, 10)
	var goal := base + Vector2(30, 0)
	port.move(PackedInt32Array([sh]), goal, true)
	var hp := 60000   # санти-HP постройки (её ведёт ECON; здесь — тест)
	var hits := 0
	var broke := false
	var arrived := false
	var inside := 0
	for t in 2400:
		_tick(port)
		var hs := port.take_structure_hits()
		for i in range(0, hs.size(), 3):
			if hs[i] == b:
				hits += 1
				hp -= hs[i + 1]
		if not broke:
			for u in sim.sq_members[Ids.slot(sh)]:
				if sim.u_life[u] == BattleSim.Life.ALIVE and _inside(sim, 9, sim.u_x[u], sim.u_z[u]):
					inside += 1
			if hp <= 0:
				broke = true
				bnav.breach_h = 0   # обход больше не нужен: путь прямо
				port.structure_clear(b)
		for h in port.take_arrivals():
			arrived = arrived or h == sh
		if arrived:
			break
	SimHarness.check(hits > 0 and broke, "у точки пролома ломают постройку (%d ударов)" % hits)
	SimHarness.check(inside == 0, "сквозь целую постройку не прошли (%d)" % inside)
	SimHarness.check(arrived and port.pos(sh).distance_to(goal) < 8.0, "постройка пала — прежний приказ, дошли до цели")


# ================================================================= урон по постройкам

func _test_structure_dps() -> void:
	print("[урон по постройке]")
	for case in [["chabuulchu", 20, false, 1.0], ["jooker", 20, false, 1.0], ["sarboz", 20, true, 1.0],
			["jooker", 20, false, 0.75]]:
		var port := _make_port()
		var sim := port.sim
		var base := SimHarness.flat_spot()
		var b := _bh(7)
		port.structure_set(b, 0, base, Vector2(4, 4), 0.3, BattleSim.ST_BLOCK)
		var tid: String = case[0]
		var n: int = case[1]
		var ranged: bool = case[2]
		var atk: float = case[3]
		if atk != 1.0:
			# голод игрока 1 (R11): атака × 0,75
			port.set_owner_mods(1, PackedFloat32Array([atk, 1.0, 1.0, 1.0, 1.0]))
		var sh := port.spawn_squad(1, 1, StringName(tid), n, base + Vector2(-50, 0), PI / 2, &"", 0, 10)
		port.attack(PackedInt32Array([sh]), b, not ranged)
		var first := -1
		var dmg := 0
		for t in 2400:
			_tick(port)
			var hits := port.take_structure_hits()
			for i in range(0, hits.size(), 3):
				if hits[i] == b:
					if first < 0:
						first = t
					dmg += hits[i + 1]
		var st := UnitStats.get_stats(tid)
		var per := 0.0
		if ranged:
			# выстрел: перезарядка + вскидка (SHOOT_FIRE_DELAY) + разброс начала (0,125) и выстрела (0,06) в среднем
			per = float(st["missile"]) * float(st["vs_building"]) / (float(st["reload"]) + BattleSim.SHOOT_FIRE_DELAY + 0.185)
		else:
			per = float(st["attack"]) * float(st["vs_building"]) / BattleSim.ST_MELEE_COOL
		var secs := (2400 - first) / 30.0
		var dps := dmg / 100.0 / maxf(secs, 0.1)
		var want := per * n * atk
		print("  %s ×%d (атака ×%.2f): %.2f HP/с, формула %.2f HP/с (первое попадание на %.1f с)" % [tid, n, atk, dps, want, first / 30.0])
		SimHarness.check_range(dps / want, 0.9, 1.1, "%s ×%.2f: урон по постройке / формула" % [tid, atk])
		SimHarness.check(sim.st_alive[7] == 1, "ядро само HP постройки не меняет")


# ================================================================= стойки и сон

func _test_defensive_and_sleep() -> void:
	print("[работники DEFENSIVE и сон]")
	var port := _make_port()
	var sim := port.sim
	var base := SimHarness.flat_spot()
	var workers := PackedInt32Array()
	var home: Array[Vector2] = []
	for k in 12:
		var p := base + Vector2((k % 4) * 3.0, (k / 4) * 3.0)
		workers.append(port.spawn(0, 0, &"dehqon", p, 0.0))
		home.append(p)
	_tick(port, 150)
	var asleep := 0
	for h in workers:
		asleep += sim.u_sleep[Ids.slot(h)]
	SimHarness.check(asleep == workers.size(), "работники без дела засыпают (%d из %d)" % [asleep, workers.size()])
	SimHarness.check(sim.sq_stance[sim.u_squad[Ids.slot(workers[0])]] == BattleSim.Stance.DEFENSIVE, "работник — DEFENSIVE")
	# всадник налетает на работника и уходит; работники бьют в ответ, но не гонятся
	var raider := port.spawn(1, 1, &"chabuulchu", base + Vector2(-60, 4), PI / 2)
	port.attack(PackedInt32Array([raider]), workers[5])
	var woke := false
	var fought := false
	var max_d := 0.0
	for t in 900:
		if t == 330:
			port.move(PackedInt32Array([raider]), base + Vector2(-80, 40), true)
		_tick(port)
		for k in workers.size():
			var u := Ids.slot(workers[k])
			if sim.u_life[u] != BattleSim.Life.ALIVE:
				continue
			if sim.u_sleep[u] == 0:
				woke = true
			if sim.u_target[u] >= 0:
				fought = true
			max_d = maxf(max_d, Vector2(sim.u_x[u], sim.u_z[u]).distance_to(home[k]))
	SimHarness.check(woke, "враг рядом будит спящих")
	SimHarness.check(fought, "работники отвечают ударом")
	SimHarness.check(max_d <= BattleSim.DEF_LEASH + 1.0, "не гонятся дальше 6 м (дальше всех %.2f м)" % max_d)
	_tick(port, 300)
	var back := 0
	var alive := 0
	for k in workers.size():
		var u := Ids.slot(workers[k])
		if sim.u_life[u] == BattleSim.Life.ALIVE:
			alive += 1
			if Vector2(sim.u_x[u], sim.u_z[u]).distance_to(home[k]) < 1.0:
				back += 1
	SimHarness.check(back == alive, "вернулись на места (%d из %d)" % [back, alive])


# ================================================================= буферы

func _test_events() -> void:
	print("[буферы: смерти, прибытия; бегство домой]")
	# дома команд — на юге и на севере (не по оси X, как бегство среза)
	var port := _make_port({"homes": PackedVector2Array([Vector2(90, 400), Vector2(90, -400)])})
	var sim := port.sim
	var base := SimHarness.flat_spot()
	var a := port.spawn_squad(0, 0, &"kilichboz", 30, base + Vector2(10, 0), -PI / 2, &"", 0, 15)
	var b := port.spawn_squad(1, 1, &"jooker", 30, base + Vector2(-10, 0), PI / 2, &"", 0, 15)
	var signals := {}                  # описатель → сколько раз пришёл сигнал (лямбда пишет в общий словарь)
	var on_death := func(u: int, _p: Vector3) -> void:
		var h := Ids.make(Ids.Kind.UNIT, u, sim.u_gen[u])
		signals[h] = int(signals.get(h, 0)) + 1
	sim.death.connect(on_death)
	port.attack(PackedInt32Array([a]), b)
	port.attack(PackedInt32Array([b]), a)
	var recs := {}
	var rec_dup := false
	var killer_ok := true
	var flee_start := {}     # отряд → [такт, z центра] в начале бегства
	var flee_ok := 0
	var flee_seen := 0
	for t in 1500:
		_tick(port)
		for sq in [Ids.slot(a), Ids.slot(b)]:
			if sim.sq_status[sq] == BattleSim.Status.FLEE and sim.sq_alive[sq] > 0:
				if not flee_start.has(sq):
					flee_start[sq] = [t, sim.sq_cz[sq]]
				elif t - int(flee_start[sq][0]) == 60:
					flee_seen += 1
					var home_z := 400.0 if sim.sq_side[sq] == 0 else -400.0
					if absf(home_z - sim.sq_cz[sq]) < absf(home_z - float(flee_start[sq][1])) - 3.0:
						flee_ok += 1
		var d := port.take_deaths()
		for i in range(0, d.size(), 2):
			rec_dup = rec_dup or recs.has(d[i])
			recs[d[i]] = true
			if d[i + 1] != 0 and port.team(d[i + 1]) == port.team(d[i]):
				killer_ok = false
	var dup := false
	for h: int in signals:
		dup = dup or signals[h] != 1 or not recs.has(h)
	SimHarness.check(signals.size() > 10 and recs.size() == signals.size() and not dup and not rec_dup,
		"одна запись на смерть (%d записей, %d сигналов)" % [recs.size(), signals.size()])
	SimHarness.check(killer_ok, "убийца — из другой команды")
	SimHarness.check(flee_seen >= 1 and flee_ok == flee_seen, "бегут домой (FleeMode.HOME): %d из %d" % [flee_ok, flee_seen])
	sim.death.disconnect(on_death)  # иначе цикл ссылок «ядро → сигнал → лямбда → ядро»
	# прибытие: одна запись на приказ
	var s := port.spawn(0, 0, &"dehqon", base + Vector2(0, 60), 0.0)
	var sq := port.squad_of(s)
	port.move(PackedInt32Array([s]), base + Vector2(20, 60))
	var arr := 0
	for t in 600:
		_tick(port)
		for h in port.take_arrivals():
			if h == sq:
				arr += 1
	SimHarness.check(arr == 1, "прибытие — одна запись (%d)" % arr)
	SimHarness.check(port.pos(s).distance_to(base + Vector2(20, 60)) < 1.0 and port.is_idle(s), "одиночка у цели и без дела")


# ================================================================= стрелки

func _test_ranged() -> void:
	print("[стрелки: атака отряда с дистанции]")
	var port := _make_port()
	var sim := port.sim
	var base := SimHarness.flat_spot()
	var sar := port.spawn_squad(0, 0, &"sarboz", 40, base + Vector2(70, 0), -PI / 2, &"yuzboshi", 0, 20)
	var joo := port.spawn_squad(1, 1, &"jooker", 30, base + Vector2(-60, 0), PI / 2, &"", 0, 15)
	var shots := {"n": 0}
	var on_shot := func(_u: int, _m: Vector3, _d: Vector3, _h: bool) -> void:
		shots["n"] = int(shots["n"]) + 1
	sim.shot.connect(on_shot)
	port.attack(PackedInt32Array([sar]), joo)
	var min_d := INF
	for t in 1500:
		_tick(port)
		port.take_deaths()
		min_d = minf(min_d, port.pos(sar).distance_to(port.pos(joo)))
	sim.shot.disconnect(on_shot)
	var lost := 30 - sim.sq_alive[Ids.slot(joo)]
	print("  выстрелов %d, у врага пало %d, ближе всего %.1f м" % [shots["n"], lost, min_d])
	SimHarness.check(shots["n"] >= 40 and lost > 0, "стреляют залпами и попадают")
	SimHarness.check(min_d > 45.0, "в рукопашную не лезут (держат дистанцию)")


# ================================================================= детерминизм, сохранение

func _city_run(port: CombatPortBattle, from_t: int, to_t: int, sums: PackedInt64Array) -> void:
	var base := SimHarness.flat_spot()
	for t in range(from_t, to_t):
		if t == 0:
			port.structure_set(_bh(2), 1, base + Vector2(0, 30), Vector2(4, 4), 0.0, BattleSim.ST_BLOCK)
			for k in 40:
				port.spawn(0, 0, &"dehqon", base + Vector2(k % 8 * 2.0, k / 8 * 2.0 - 40.0), 0.0)
			port.spawn_squad(0, 0, &"nayzachi", 40, base + Vector2(40, 0), -PI / 2, &"", 0, 20)
			port.spawn_squad(1, 1, &"chabuulchu", 30, base + Vector2(-60, 0), PI / 2, &"juz_bashy", 0, 15)
		if t == 30:
			var raiders := PackedInt32Array([Ids.make(Ids.Kind.SQUAD, 41, port.sim.sq_gen[41])])
			port.attack_move(raiders, base + Vector2(10, -35))
			var ws := PackedInt32Array()
			for k in 20:
				ws.append(Ids.make(Ids.Kind.UNIT, k, port.sim.u_gen[k]))
			port.move(ws, base + Vector2(0, 50))
		if t == 200:
			port.attack(PackedInt32Array([Ids.make(Ids.Kind.SQUAD, 40, port.sim.sq_gen[40])]),
				Ids.make(Ids.Kind.SQUAD, 41, port.sim.sq_gen[41]))
		_tick(port)
		port.take_deaths()
		port.take_arrivals()
		port.take_structure_hits()
		if t % 30 == 29:
			sums.append(port.checksum())


func _test_determinism_and_save() -> void:
	print("[детерминизм и сохранение]")
	var a := PackedInt64Array()
	var b := PackedInt64Array()
	var pa := _make_port()
	_city_run(pa, 0, 900, a)
	var pb := _make_port()
	_city_run(pb, 0, 900, b)
	SimHarness.check(a == b and a.size() == 30, "два прогона — одни суммы (%d)" % a.size())
	# сохранение на 15 с и загрузка в новый порт: дальше то же
	var pc := _make_port()
	var c := PackedInt64Array()
	_city_run(pc, 0, 450, c)
	var d := {}
	pc.save_into(d)
	var pd := _make_port()
	pd.load_from(d)
	SimHarness.check(pd.checksum() == pc.checksum(), "после загрузки сумма та же")
	var rest := PackedInt64Array()
	_city_run(pd, 450, 900, rest)
	SimHarness.check(rest == a.slice(15), "после загрузки бой идёт так же")
	var alive := 0
	for u in pa.sim.n:
		if pa.sim.u_life[u] == BattleSim.Life.ALIVE:
			alive += 1
	print("  живых после 30 с: %d из %d" % [alive, pa.sim.n])


# ================================================================= скорость

func _test_perf() -> void:
	print("[скорость]")
	var port := _make_port()
	var sim := port.sim
	var base := SimHarness.flat_spot() + Vector2(-60, -60)
	for k in 1000:
		port.spawn(k % 2, 0, &"dehqon" if k % 3 != 0 else &"jooker", base + Vector2((k % 32) * 3.5, (k / 32) * 3.5), 0.0)
	_tick(port, 300)
	var asleep := 0
	for u in sim.n:
		asleep += sim.u_sleep[u]
	var t0 := _cpu_us()
	var worst := 0
	for i in 300:
		var s0 := _cpu_us()
		_tick(port)
		worst = maxi(worst, _cpu_us() - s0)
	var avg := (_cpu_us() - t0) / 300.0 / 1000.0
	print("  1000 одиночек без дела: %.2f мс/шаг (худший %.2f), спят %d" % [avg, worst / 1000.0, asleep])
	SimHarness.check(asleep >= 990, "спят почти все (%d)" % asleep)
	# цель — 2 мс; на общей машине разброс замеров ~20%, ворота — 2,4 мс
	SimHarness.check(avg <= 2.4, "1000 одиночек без дела: цель 2 мс/шаг, предел 2,4 (%.2f)" % avg)
	_city_at_rest()
	# свалка 1213: срез (ядро по умолчанию) и город (сон, буферы, тела) — тот же бой
	var base_ms := _melee(false)
	var city_ms := _melee(true)
	print("  свалка 1213: срез %.2f мс/шаг, город %.2f мс/шаг" % [base_ms, city_ms])
	SimHarness.check(city_ms <= base_ms * 1.15, "свалка в городе не медленнее среза (±15%% на шум)")


## Город в покое (§16): 600 работников за работой, 300 бойцов в строю стоят, 100 одиночек ходят туда-обратно
func _city_at_rest() -> void:
	var port := _make_port({"reserve_units": 1200, "reserve_squads": 800})
	var sim := port.sim
	var base := SimHarness.flat_spot() + Vector2(-100, -100)
	var aux := [AnimSpec.WORK_CHOP, AnimSpec.WORK_DIG, AnimSpec.WORK_BUILD]
	for k in 600:
		# город Коканда и стан кыпчаков в 250 м друг от друга (враг ближе 16 м будит спящих)
		var t := k % 2
		var h := port.spawn(t, t, &"dehqon" if t == 0 else &"malchy",
			base + Vector2((k / 2 % 15) * 4.0 + t * 250.0, (k / 30) * 4.0), 0.0)
		port.set_work(h, aux[k % 3])
	for k in 3:
		port.spawn_squad(0, 0, &"sarboz" if k != 1 else &"nayzachi", 100, base + Vector2(30 + k * 60, 120), 0.0, &"yuzboshi", 0, 50)
	var walkers := PackedInt32Array()
	for k in 100:
		walkers.append(port.spawn(0, 0, &"jooker", base + Vector2(180 + (k % 10) * 2.0, (k / 10) * 2.0), 0.0))
	_tick(port, 240)
	var t0 := _cpu_us()
	var worst := 0
	for i in 600:
		if i % 150 == 0:
			for k in walkers.size():
				var h := walkers[k]
				port.move(PackedInt32Array([h]), base + Vector2(180 + (k % 10) * 2.0, (k / 10) * 2.0 + (40.0 if (i / 150) % 2 == 0 else 0.0)))
		var s0 := _cpu_us()
		_tick(port)
		worst = maxi(worst, _cpu_us() - s0)
	var avg := (_cpu_us() - t0) / 600.0 / 1000.0
	var asleep := 0
	for u in sim.n:
		asleep += sim.u_sleep[u]
	print("  город в покое (600 работают, 300 в строю, 100 ходят): %.2f мс/шаг (худший %.2f), спят %d из %d" % [
		avg, worst / 1000.0, asleep, sim.n])
	# цель §16 — 3 мс; на общей машине разброс замеров ~20%, ворота — 3,6 мс
	SimHarness.check(avg <= 3.6, "город в покое: цель 3 мс/шаг, предел 3,6 (%.2f)" % avg)


func _melee(city: bool) -> float:
	var best := INF
	for rep in 2:
		var sim := BattleSim.new(3)
		if city:
			sim.sleep_enabled = true
			sim.collect_events = true
			sim.corpse_steps = 900
			sim.victory_mode = BattleSim.Victory.NONE
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
		var t0 := _cpu_us()
		for i in 300:
			sim.step()
			sim.take_dead()
		best = minf(best, (_cpu_us() - t0) / 300.0 / 1000.0)
	return best


## Навигация для теста: путь через точку перед постройкой breach_h (пролом), пока она стоит
class BreachNav extends NavStub:
	var breach_h := 0
	var breach_pt := Vector2.ZERO

	func _straight(from: Vector2, to: Vector2) -> PathResult:
		var r := PathResult.new()
		if breach_h != 0:
			r.pts.append(breach_pt)
			r.breach_b = breach_h
			r.breach_wp = 0
		r.pts.append(to)
		r.issued_ver = version
		return r


## Навигация для теста: прямо к цели, а если прямая задевает препятствие — через угол в обход (как путь NAV)
class DetourNav extends NavStub:
	var boxes: Array = []   # [центр, полуразмеры, курс]

	func _straight(from: Vector2, to: Vector2) -> PathResult:
		var r := PathResult.new()
		var cur := from
		var used := PackedVector2Array()
		for guard in 8:
			var hit := -1
			for i in boxes.size():
				if _seg_hits(i, cur, to, 0.3):
					hit = i
					break
			if hit < 0:
				break
			var best := Vector2.INF
			var bd := INF
			for corner in _corners(hit, 3.0):
				if corner.distance_to(cur) < 0.5 or used.has(corner):
					continue
				var blocked := false
				for i in boxes.size():
					if _seg_hits(i, cur, corner, 0.3):
						blocked = true
				if blocked:
					continue
				var d := cur.distance_to(corner) + corner.distance_to(to)
				if d < bd:
					bd = d
					best = corner
			if best == Vector2.INF:
				break
			r.pts.append(best)
			used.append(best)
			cur = best
		r.pts.append(to)
		r.issued_ver = version
		return r

	func _corners(i: int, pad: float) -> PackedVector2Array:
		var c: Vector2 = boxes[i][0]
		var hh: Vector2 = boxes[i][1] + Vector2(pad, pad)
		var rot: float = boxes[i][2]
		var out := PackedVector2Array()
		for k in 4:
			var lx := hh.x * (1.0 if k % 2 == 0 else -1.0)
			var lz := hh.y * (1.0 if k < 2 else -1.0)
			out.append(Vector2(c.x + lx * cos(rot) + lz * sin(rot), c.y - lx * sin(rot) + lz * cos(rot)))
		return out

	func _seg_hits(i: int, a: Vector2, b: Vector2, pad: float) -> bool:
		var c: Vector2 = boxes[i][0]
		var hh: Vector2 = boxes[i][1] + Vector2(pad, pad)
		var rot: float = boxes[i][2]
		var cs := cos(rot)
		var sn := sin(rot)
		var ax := (a.x - c.x) * cs - (a.y - c.y) * sn
		var az := (a.x - c.x) * sn + (a.y - c.y) * cs
		var bx := (b.x - c.x) * cs - (b.y - c.y) * sn
		var bz := (b.x - c.x) * sn + (b.y - c.y) * cs
		var t0 := 0.0
		var t1 := 1.0
		for axis in 2:
			var p0 := ax if axis == 0 else az
			var d := (bx - ax) if axis == 0 else (bz - az)
			var e: float = hh.x if axis == 0 else hh.y
			if absf(d) < 1e-6:
				if absf(p0) > e:
					return false
				continue
			var ta := (-e - p0) / d
			var tb := (e - p0) / d
			if ta > tb:
				var tmp := ta
				ta = tb
				tb = tmp
			t0 = maxf(t0, ta)
			t1 = minf(t1, tb)
			if t0 > t1:
				return false
		return true
