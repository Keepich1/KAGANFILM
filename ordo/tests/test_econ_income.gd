extends SceneTree
## T10 (ECONOMY §9.2–9.3): доход по модели без боёв —
##   Коканд 1150–1400 в минуту на 10-й мин (лето), 1550–1800 на 20-й; кыпчаки 1100–1450 и 1300–1700.
##   godot --headless --path ordo --script res://tests/test_econ_income.gd
##
## Снимок §9.2 «по ставкам §1.1»: постройки и работники расставлены по таблицам §9.2 (распределение «ИИ-строителя»,
## склады не дальше 25 м), сим идёт 90 с до установившихся ходок, потом три минуты; доход — PlayerTable.income
## (окно 60 с, чистыми: дрова печей уже вычтены) в конце каждой из трёх минут, среднее; сумма еды, дерева, камня,
## золота с податью и ғишта. Ноша 30 сдаётся раз в 60–85 с, поэтому ходки работников одного дела разнесены по
## фазе (начальная ноша j·30/n) — как у работников, нанятых в разное время; иначе минутное окно ловит 0 или 1 ношу.
## Кони кыпчаков (приплод) в «Итого» §9.2 не входят — печатаются отдельно. Трава под короо в окне замера —
## средняя из §9.2 (85% / 80%). Успеет ли ИИ к 10:00 к такому распределению — проверка ИИ (GAME, T12).

const KOK := Vector2(0, 0)
const KIP := Vector2(-60, 20)


func _init() -> void:
	_kokand(10)
	_kokand(20)
	_kipchak(10)
	_kipchak(20)
	SimHarness.finish(self)


## Коканд по §9.2: 10 мин — 47 деҳқонов (поля 24 / печь 3 / дерево 10 / камень 3 / золото 7), 6 полей, 1 тўғон,
## 1 Хумдон, 6 домов, Бозор; 20 мин — 62 (32 / 6 / 10 / 3 / 11), 8 полей, 2 тўғона, 2 Хумдона, 16 домов
func _kokand(minute: int) -> void:
	var late := minute >= 20
	print("[T10: Коканд, %d-я минута]" % minute)
	var k := EconKit.make()
	var p := k.kokand(KOK, 0)
	var e := k.econ
	k.set_res(p, "wood", 2000.0)
	# вода: тўғон A и арык вдоль x = 30 к полям; на 20-й — тўғон B и арык вдоль x = −30 к печам
	k.build_now(p, &"togon", Vector2(30, -160))
	e.spawn_links(p, k.b(&"aryk"), PackedVector2Array([Vector2(30, -154), Vector2(30, -40)]))
	if late:
		k.build_now(p, &"togon", Vector2(-30, -160))
		e.spawn_links(p, k.b(&"aryk"), PackedVector2Array([Vector2(-30, -154), Vector2(-30, -110)]))
	# поля в два ряда у арыка, мельница между ними (до полей не дальше 25 м)
	var fields: Array[int] = []
	for row in (4 if late else 3):
		for side in [12.5, 47.5]:
			fields.append(k.build_now(p, &"dala", Vector2(side, -50 - row * 20)))
	k.build_now(p, &"tegirmon", Vector2(30, -80))
	var kilns: Array[int] = []
	if late:
		kilns.append(k.build_now(p, &"xumdon", Vector2(-12, -132)))
		kilns.append(k.build_now(p, &"xumdon", Vector2(-48, -132)))
	else:
		kilns.append(k.build_now(p, &"xumdon", Vector2(12, -132)))
	# дома и Бозор (подать: Уй 4, Урда 8 в минуту)
	for i in (16 if late else 6):
		k.build_now(p, &"uy", Vector2(-50 + (i % 8) * 12.0, 40 + (i / 8) * 12.0))
	k.build_now(p, &"bozor", Vector2(60, 60))
	# склады у жил и у рощи
	k.build_now(p, &"ombor", Vector2(100, 0))
	k.build_now(p, &"ombor", Vector2(-60, 0))
	var gold1 := e.spawn_node(k.defs.node(&"gold"), Vector2(100, 22), 3_000_000)
	var gold2 := e.spawn_node(k.defs.node(&"gold"), Vector2(122, 0), 3_000_000)
	var stone := e.spawn_node(k.defs.node(&"stone"), Vector2(100, -22), 4_000_000)
	var trees: Array[int] = []
	for at in [Vector2(-60, 20), Vector2(-60, -20), Vector2(-82, 0), Vector2(-80, 18), Vector2(-80, -18)]:
		trees.append(e.spawn_node(k.defs.node(&"tree_poplar"), at, 9_000_000))
	k.step()
	# работники по §9.2
	var at_field := 24 if not late else 32
	var at_kiln := 3 * kilns.size()
	var n_gold := 11 if late else 7
	var ws := _hire(k, p, at_field + at_kiln + 10 + 3 + n_gold)
	var i := 0
	for f in fields:
		e.assign_gather(p, ws.slice(i, i + 4), f)
		i += 4
	_phase(k, ws.slice(0, i))
	for kb in kilns:
		e.assign_gather(p, ws.slice(i, i + 3), kb)
		i += 3
	var i0 := i
	for t in trees:
		e.assign_gather(p, ws.slice(i, i + 2), t)
		i += 2
	_phase(k, ws.slice(i0, i))
	e.assign_gather(p, ws.slice(i, i + 3), stone)
	_phase(k, ws.slice(i, i + 3))
	i += 3
	i0 = i
	e.assign_gather(p, ws.slice(i, i + mini(n_gold, 8)), gold1)
	i += mini(n_gold, 8)
	if n_gold > 8:
		e.assign_gather(p, ws.slice(i, i + n_gold - 8), gold2)
	_phase(k, ws.slice(i0, i0 + n_gold))
	var wet := 0
	for f in fields:
		wet += 1 if e.b_water[e.buildings.slot(f)] == 1000 else 0
	for kb in kilns:
		wet += 1 if e.b_water[e.buildings.slot(kb)] == 1000 else 0
	SimHarness.check(wet == fields.size() + kilns.size(), "все поля и печи у воды (%d)" % wet)
	k.run_s(90.0)
	var total := _measure(k, p, ["food", "wood", "stone", "gold", "brick"])
	var lo := 1550.0 if late else 1150.0
	var hi := 1800.0 if late else 1400.0
	SimHarness.check_range(total, lo, hi, "Коканд, %d-я мин: доход %.0f в минуту (T10: %.0f–%.0f)" % [minute, total, lo, hi])


## Кыпчаки по §9.2: 10 мин — 30 малчы (пастухи 9 / дерево 12 / золото 9 у Кена), 9 короо, трава 85%;
## 20 мин — 42 (20 / 12 / 10), 10 короо, трава 80%
func _kipchak(minute: int) -> void:
	var late := minute >= 20
	print("[T10: кыпчаки, %d-я минута]" % minute)
	var k := EconKit.make()
	var p := k.kipchak(KIP, 0)
	var e := k.econ
	var n_pens := 10 if late else 9
	var per_pen := 2 if late else 1
	var pens: Array[int] = []
	for j in n_pens:
		var a := TAU * j / n_pens
		pens.append(k.build_now(p, &"koroo", KIP + Vector2(cos(a), sin(a)) * 115.0))
	k.build_now(p, &"jylky", KIP + Vector2(0, 55), 2)
	var ken_at := KIP + Vector2(70, 0)
	k.build_now(p, &"ken", ken_at)
	var gold1 := e.spawn_node(k.defs.node(&"gold"), ken_at + Vector2(0, 20), 3_000_000)
	var gold2 := e.spawn_node(k.defs.node(&"gold"), ken_at + Vector2(0, -20), 3_000_000)
	var trees: Array[int] = []
	for at in [Vector2(-30, 14), Vector2(-30, -14), Vector2(-34, 0), Vector2(14, -30), Vector2(-14, -30), Vector2(0, -34)]:
		trees.append(e.spawn_node(k.defs.node(&"tree_poplar"), KIP + at, 9_000_000))
	k.step()
	var n_gold := 10 if late else 9
	var ws := _hire(k, p, n_pens * per_pen + 12 + n_gold)
	var i := 0
	for pen in pens:
		e.assign_gather(p, ws.slice(i, i + per_pen), pen)
		i += per_pen
	var i0 := i
	for t in trees:
		e.assign_gather(p, ws.slice(i, i + 2), t)
		i += 2
	_phase(k, ws.slice(i0, i))
	i0 = i
	var g1 := (n_gold + 1) / 2
	e.assign_gather(p, ws.slice(i, i + g1), gold1)
	i += g1
	e.assign_gather(p, ws.slice(i, i + n_gold - g1), gold2)
	_phase(k, ws.slice(i0, i0 + n_gold))
	k.run_s(90.0)
	var horses0 := k.res(p, "horse")
	# трава под короо в окнах замера держится на средней из §9.2 (здесь замер дохода; пастбище — test_econ_herds_fields)
	var grass := 80000 if late else 85000
	var total := _measure(k, p, ["food", "wood", "gold"], grass)
	print("  кони: %.0f → %.0f за 3 мин (приплод, вне «Итого»)" % [horses0, k.res(p, "horse")])
	var lo := 1300.0 if late else 1100.0
	var hi := 1700.0 if late else 1450.0
	SimHarness.check_range(total, lo, hi, "кыпчаки, %d-я мин: доход %.0f в минуту (T10: %.0f–%.0f)" % [minute, total, lo, hi])


## n работников стороны у ставки
func _hire(k: EconKit, p: int, n: int) -> PackedInt32Array:
	var hq := k.econ.buildings.slot(k.econ.players.hq_b[p])
	var c := Vector2(k.econ.buildings.x[hq], k.econ.buildings.z[hq])
	for j in n:
		k.econ.spawn_worker(p, c + Vector2(-10.0 + (j % 8) * 2.5, 12.0 + (j / 8) * 2.5))
	return k.workers_of(p)


## Ходки работников одного дела — вразнобой: начальная ноша j·30/n (как у нанятых в разное время)
func _phase(k: EconKit, ws: PackedInt32Array) -> void:
	var e := k.econ
	for j in ws.size():
		var w := e.un_w[Ids.slot(ws[j])]
		e.wk.w_carry[w] = e.wk.w_cap[w] * j / maxi(ws.size(), 1)


## Доход в минуту по ресурсам: PlayerTable.income (окно 60 с) в конце каждой из трёх минут, среднее; и сумма.
## grass > 0 — держать траву (сотые промилле) на этом уровне
func _measure(k: EconKit, p: int, ids: Array, grass := 0) -> float:
	var e := k.econ
	var sums := PackedFloat64Array()
	sums.resize(ids.size())
	for m in 3:
		for t in 1800:
			if grass > 0 and t % 150 == 0:
				for c in e.fld.g.size():
					if e.fld.cap[c] == 1:
						e.fld.g[c] = grass
			k.step()
		for j in ids.size():
			sums[j] += e.players.income[p * e.R + k.r(StringName(ids[j]))] / 1000.0 / 3.0
	var total := 0.0
	var parts := PackedStringArray()
	for j in ids.size():
		total += sums[j]
		parts.append("%s %.0f" % [ids[j], sums[j]])
	print("  в минуту: %s; итого %.0f" % [", ".join(parts), total])
	return total
