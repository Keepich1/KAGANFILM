extends SceneTree
## Детерминизм и скорость экономики (ARCHITECTURE §5.2, §15, §16):
##   godot --headless --path ordo --script res://tests/test_econ_determinism.gd
## 1) два прогона одной партии (оба города: добыча, поля у арыка, печь, найм, короо, табун, барымта, голод)
##    дают одинаковый журнал контрольных сумм;
## 2) save_into → load_from возвращает ту же сумму;
## 3) город на ~600 работников, 200 бойцов и ~120 построек: экономика ≤ 1 мс в среднем, худший такт — печать.

const KOK := Vector2(150, 0)
const KIP := Vector2(-60, 20)


func _init() -> void:
	var a := _run(7)
	var b := _run(7)
	print("  сумм: %d, последняя %d" % [a.size(), a[a.size() - 1]])
	SimHarness.check(a.size() == 240 and a == b, "два прогона по 4 мин — одинаковые суммы (раз в 30 тактов)")
	_save_load()
	_perf()
	SimHarness.finish(self)


## Партия на заглушках: журнал econ.checksum() ^ port.checksum() раз в 30 тактов
func _run(p_seed: int) -> PackedInt64Array:
	var k := _city(p_seed)
	var log := PackedInt64Array()
	for i in 240 * 30:
		k.step()
		if k.tick % 30 == 0:
			log.append(k.econ.checksum() * 31 + k.port.checksum())
	return log


func _city(p_seed: int) -> EconKit:
	var k := EconKit.make(p_seed)
	var e := k.econ
	var kok := k.kokand(KOK, 12)
	var kip := k.kipchak(KIP, 10)
	var ws := k.workers_of(kok)
	var wood := e.spawn_node(k.defs.node(&"tree_elm"), KOK + Vector2(-40, 40), 2_000_000)
	var stone := e.spawn_node(k.defs.node(&"stone"), KOK + Vector2(50, 30))
	k.build_now(kok, &"togon", KOK + Vector2(0, -110))
	e.place_wall(kok, k.b(&"aryk"), PackedVector2Array([KOK + Vector2(0, -104), KOK + Vector2(0, -20)]), PackedInt32Array([ws[0], ws[1]]))
	e.assign_gather(kok, PackedInt32Array([ws[2], ws[3], ws[4]]), wood)
	e.assign_gather(kok, PackedInt32Array([ws[5], ws[6]]), stone)
	e.place_site(kok, k.b(&"dala"), KOK + Vector2(22, -60), 0, PackedInt32Array([ws[7], ws[8]]))
	e.place_site(kok, k.b(&"tegirmon"), KOK + Vector2(-24, -40), 0, PackedInt32Array([ws[9]]))
	e.train(kok, e.players.hq_b[kok], k.u(&"dehqon"), 5)
	var wk := k.workers_of(kip)
	var gold := e.spawn_node(k.defs.node(&"gold"), KIP + Vector2(-60, -60))
	e.assign_gather(kip, PackedInt32Array([wk[0], wk[1], wk[2]]), gold)
	e.place_site(kip, k.b(&"koroo"), KIP + Vector2(-50, 60), 0, PackedInt32Array([wk[3]]))
	var yard := e.place_site(kip, k.b(&"jylky"), KIP + Vector2(40, 70), 0, PackedInt32Array([wk[4], wk[5]]))
	e.set_rally(kip, e.players.hq_b[kip], KIP + Vector2(-60, -50), gold)
	e.train(kip, e.players.hq_b[kip], k.u(&"malchy"), 4)
	e.assign_gather(kip, PackedInt32Array([wk[6]]), e.spawn_node(k.defs.node(&"tree_poplar"), KIP + Vector2(30, -30)))
	# налётчики у коновязи ставки и войско на содержании
	for i in 8:
		k.port.spawn(kok, 0, &"navkar", KIP + Vector2(-6 + i, -14), 0.0)
	for i in 30:
		k.unit(kok, &"sarboz", KOK + Vector2(30 + i % 6, 40 + i / 6))
	return k


func _save_load() -> void:
	print("[сохранение]")
	var k := _city(3)
	k.run_s(30.0)
	var d := {}
	k.econ.save_into(d)
	var c := k.econ.checksum()
	k.run_s(5.0)
	k.econ.load_from(d)
	SimHarness.check(k.econ.checksum() == c, "save_into → load_from: та же сумма")


func _perf() -> void:
	print("[город: 600 работников, 200 бойцов]")
	var k := EconKit.make(5)
	var e := k.econ
	var kok := k.kokand(Vector2(150, 0), 0)
	var kip := k.kipchak(Vector2(-150, 0), 0)
	for p in [kok, kip]:
		var c := Vector2(150, 0) if p == kok else Vector2(-150, 0)
		e.players.res[p * e.R + k.r(&"wood")] = 1_000_000_000
		for i in 40:
			var at := c + Vector2(-100 + (i % 8) * 25.0, -110 + (i / 8) * 25.0 + (0.0 if i < 20 else 120.0))
			k.build_now(p, &"uy" if p == kok else &"boz", at)
		for i in 15:
			var a := c + Vector2(-120 + (i % 5) * 60.0, -170 + (i / 5) * 170.0)
			var n := e.spawn_node(k.defs.node(&"stone") if i % 2 == 0 else k.defs.node(&"gold"), a, 90_000_000)
			for j in 20:
				var w := e.spawn_worker(p, a + Vector2(-8 + j % 5 * 4.0, 8 + j / 5 * 3.0))
				e.assign_gather(p, PackedInt32Array([w]), n)
		k.build_now(p, &"ombor" if p == kok else &"ken", c + Vector2(0, 60))
		for i in 100:
			k.unit(p, &"sarboz" if p == kok else &"jooker", c + Vector2(i % 10 * 2.0, -40 - i / 10 * 2.0))
	if true:
		for i in 6:
			k.build_now(kip, &"koroo", Vector2(-260 + i * 45.0, 200))
	k.run_s(70.0)
	var times := PackedInt32Array()
	var cpu := 0
	var th := PackedInt32Array()
	var cpu_pre := 0
	for i in 1800:
		k.tick += 1
		k.events.tick = k.tick
		var c0 := _now_us()
		var t0 := Time.get_ticks_usec()
		var n0 := e.wk.thinks
		e.pre_step(k.tick)
		th.append(e.wk.thinks - n0)
		var t1 := Time.get_ticks_usec()
		var c1 := _now_us()
		k.nav.service(k.tick)
		k.port.step()
		var deaths := k.port.take_deaths()
		var hits := k.port.take_structure_hits()
		var arr := k.port.take_arrivals()
		var c2 := _now_us()
		var t2 := Time.get_ticks_usec()
		e.post_step(k.tick, deaths, hits, arr)
		if k.tick % 30 == 0:
			e.slow_step(k.tick)
		if k.tick % 150 == 75:
			e.fields_step(k.tick)
		var t3 := Time.get_ticks_usec()
		cpu += (c1 - c0) + (_now_us() - c2)
		cpu_pre += c1 - c0
		times.append((t1 - t0) + (t3 - t2))
	var sum := 0
	for t in times:
		sum += t
	var sorted := times.duplicate()
	sorted.sort()
	var avg := cpu / float(times.size()) / 1000.0
	var wall := sum / float(times.size()) / 1000.0
	var p99 := sorted[int(sorted.size() * 0.99)] / 1000.0
	print("  экономика: %.3f мс процессора в среднем (часы %.3f), p99 по часам %.2f мс, худший %.2f мс (работников %d, построек %d)" % [avg, wall, p99,
		sorted[sorted.size() - 1] / 1000.0, e.wk.hw, e.buildings.hw])
	SimHarness.check(avg <= 1.0, "≤ 1 мс на такт в среднем (ARCHITECTURE §16)")
	# p99 по часам на общей машине (загрузка 30 на 4 ядра) — шум; оценка пика — по работе: мыслей работников
	# за такт × средняя цена мысли (процессор) + секундные системы (они разнесены по фазам такта)
	var ths := th.duplicate()
	ths.sort()
	var tot_th := 0
	for x in th:
		tot_th += x
	var per := float(cpu_pre) / maxf(float(tot_th), 1.0)
	var est := ths[int(ths.size() * 0.99)] * per / 1000.0
	print("  мыслей за такт: в среднем %.1f, p99 %d, пик %d; мысль ≤ %.1f мкс → пик работников ≈ %.2f мс" % [
		tot_th / float(th.size()), ths[int(ths.size() * 0.99)], ths[ths.size() - 1], per, est])
	SimHarness.check(est <= 2.0, "оценка p99 работников ≤ 2 мс")
	SimHarness.check(p99 <= 20.0, "p99 по часам без провалов (≤ 20 мс на загруженной машине)")


## Процессорное время этого потока, мкс (/proc/thread-self/schedstat, как bench_battle) — чужие процессы
## на машине не портят замер; без него — часы
var _cpu_file := true


func _now_us() -> int:
	if _cpu_file:
		var f := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
		if f:
			return int(f.get_line().split(" ")[0]) / 1000
		_cpu_file = false
	return Time.get_ticks_usec()
