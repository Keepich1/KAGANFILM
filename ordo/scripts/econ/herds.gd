class_name EconHerds
extends RefCounted
## Отары и табуны (ARCHITECTURE §11; ECONOMY §3.3, §3.4, §4.1): стадо — счёт голов у загона, не тела ядра.
##   • корм короо в минуту = (54 + 18 × пастухи) × трава × отара / 40 (HerdDefs.yield × голов + работа загона),
##     сразу в запас (раз в секунду, остатки — PlayerTable.rate_acc); в перегоне и в көче — 0;
##   • приплод раз в growth_period_s по ступеням голов (кони 0/+1/+2/+3 за 20 с), до предела загона,
##     не ниже min_grass травы; коновязь ставки — без приплода;
##   • кони — ресурс «horse»: запас = Σ голов табунов игрока (держится в PlayerTable.res); найм всадника
##     снимает голову с табуна двора найма (или самого большого); дворы делят коней поровну, с первым
##     двором кони коновязи уходят туда;
##   • угнанное стадо (CAPTURED) идёт за налётчиком; налётчик убит — стадо бежит домой (DRIVEN,
##     HERD_RETURNED); дошёл до своей ставки/двора/короо/Отхоны (30 м) или ушёл с карты — добыча хозяину
##     налётчика: кони — в табуны (сверх предела — 15 золота) или Коканду «отлар» в Отхону (до 20, сверх —
##     20 золота); овцы — в свои короо до 40, остальные — по 12 еды.

var _acc_t := 0


func setup(e: EconomySim) -> void:
	pass


## Стадо у загона pen_h (если у загона уже есть стадо этого вида — задать ему число голов)
func spawn(e: EconomySim, p: int, htype: int, pen_h: int, heads: int) -> int:
	var H := e.herds
	if e.buildings.valid(pen_h):
		var have := herd_at(e, e.buildings.slot(pen_h), htype)
		if have >= 0:
			H.heads_milli[have] = heads * 1000
			_sync(e, p)
			return H.handle(have)
	var h := H.alloc(HerdTable.State.PEN)
	H.htype[h] = htype
	H.owner[h] = p
	H.pen_b[h] = pen_h
	H.heads_milli[h] = heads * 1000
	H.graze_r[h] = e.defs.h_graze_r[htype]
	if e.buildings.valid(pen_h):
		var b := e.buildings.slot(pen_h)
		H.x[h] = e.buildings.x[b]
		H.z[h] = e.buildings.z[b]
	_sync(e, p)
	return H.handle(h)


func has_herd(e: EconomySim, b: int) -> bool:
	return herd_at(e, b, -1) >= 0


## Стадо загона b (htype −1 — любое)
func herd_at(e: EconomySim, b: int, htype: int) -> int:
	var H := e.herds
	var bh := e.buildings.handle(b)
	for h in H.hw:
		if H.state[h] != HerdTable.State.FREE and H.state[h] != HerdTable.State.CAPTURED and H.pen_b[h] == bh \
				and (htype < 0 or H.htype[h] == htype):
			return h
	return -1


# ================================================================= секунда

func slow_step(e: EconomySim) -> void:
	var H := e.herds
	var B := e.buildings
	var D := e.defs
	var R := e.R
	var pas_r := float(e.rule("loot_carry", "bank_r", 30.0))
	for b in B.hw:
		if e.b_mode[b] == EconomySim.Mode.MOVING and e.tick >= e.b_timer[b]:
			e.b_mode[b] = EconomySim.Mode.NONE
	for h in H.hw:
		match H.state[h]:
			HerdTable.State.PEN:
				_pen_second(e, h)
			HerdTable.State.CAPTURED:
				_captured_second(e, h, pas_r)
			HerdTable.State.DRIVEN:
				_driven_second(e, h)
	for p in e.players.count:
		_equalize_horses(e, p)
		_sync(e, p)


func _pen_second(e: EconomySim, h: int) -> void:
	var H := e.herds
	var B := e.buildings
	var D := e.defs
	if not B.valid(H.pen_b[h]):
		return
	var b := B.slot(H.pen_b[h])
	if not e.active(b) or e.b_mode[b] == EconomySim.Mode.MOVING:
		return
	var p := H.owner[h]
	var ht := H.htype[h]
	var bt := B.btype[b]
	var gr := e.fld.avg_under(e, Vector2(H.x[h], H.z[h]), H.graze_r[h])
	var heads := H.heads_milli[h] / 1000
	var cap := maxi(D.b_herd_cap[bt], 1)
	# корм (милли в минуту): голов × выход × трава + пастухи × работа × трава × голов / предел
	for r in e.R:
		var y := D.h_yield[ht * e.R + r]
		if y <= 0 or D.r_enabled[r] == 0:
			continue
		var rate := heads * y * gr / 1000
		var wk: Dictionary = D.b_work[bt]
		if not wk.is_empty() and int(wk["res"]) == r:
			rate += mini(B.workers_n[b], int(wk["slots"])) * int(wk["per_worker_min_milli"]) * gr / 1000 * heads / cap
		_flow(e, p, r, rate)
	# приплод
	var period := maxi(D.h_growth_ticks[ht], 30)
	var crossed := e.tick / period != (e.tick - 30) / period      # раз в период (зовётся раз в секунду)
	if D.b_herd_breed[bt] == 1 and crossed and heads < cap and gr >= D.h_min_grass[ht]:
		var per_min := 0
		var steps := D.h_growth_steps[ht]
		var i := 0
		while i + 1 < steps.size():
			if heads >= steps[i]:
				per_min = steps[i + 1]
			i += 2
		var add := per_min * period / 1800
		H.heads_milli[h] = mini(H.heads_milli[h] + add, cap * 1000)


## Поток «в минуту» раз в секунду через остаток PlayerTable.rate_acc
func _flow(e: EconomySim, p: int, r: int, rate_milli_min: int) -> void:
	var i := p * e.R + r
	e.players.rate_acc[i] += rate_milli_min
	var g := e.players.rate_acc[i] / 60
	if g > 0:
		e.players.rate_acc[i] -= g * 60
		e.add_res(p, r, g)


func _captured_second(e: EconomySim, h: int, bank_r: float) -> void:
	var H := e.herds
	var cap := H.captor_u[h]
	H.capture_t[h] += 30
	if e.port == null or not e.port.valid(cap) or not e.port.alive(cap):
		# налётчик ушёл с карты живым (смерть ловит on_captor_gone) — добыча его хозяину
		_bank(e, h, H.capture_t[h] >= 0 and e.port != null and e.port.valid(cap), -1)
		return
	var pos := e.port.pos(cap)
	H.x[h] = pos.x
	H.z[h] = pos.y
	var cp := e.port.owner(cap)
	if cp >= 0 and _near_home(e, cp, pos, bank_r):
		_bank(e, h, true, cp)


## Довёл до своей ставки, загона или Отхоны
func _near_home(e: EconomySim, p: int, pos: Vector2, r: float) -> bool:
	var B := e.buildings
	for b in B.hw:
		if B.owner[b] == p and e.active(b) and (B.flags[b] & (Defs.BF_HQ | Defs.BF_PEN) or not e.defs.b_otlar[B.btype[b]].is_empty()):
			if e.rect_dist2(b, pos) <= r * r:
				return true
	return false


## Добыча — хозяину налётчика (p_to; −1 — по владельцу налётчика из описателя, если он ещё читается)
func _bank(e: EconomySim, h: int, ok: bool, p_to: int) -> void:
	var H := e.herds
	var to := p_to
	if to < 0 and e.port and e.port.valid(H.captor_u[h]):
		to = e.port.owner(H.captor_u[h])
	if to < 0:
		to = _captor_owner(e, h)
	var heads := H.heads_milli[h] / 1000
	var ht := H.htype[h]
	H.release(h)
	if to < 0 or heads <= 0:
		return
	var pos := Vector2(H.x[h], H.z[h])
	var D := e.defs
	if D.h_backing[ht] >= 0:
		# кони
		var left := heads
		if e.faction_has(to, "horses"):
			left = give_heads(e, to, ht, heads, -1)
			if heads - left > 0:
				e.events.push(SimEvents.Ev.LOOT, to, D.h_backing[ht], (heads - left) * 1000, H.handle(h), pos)
		else:
			var ob := _otxona(e, to)
			if ob >= 0:
				var ot: Dictionary = D.b_otlar[e.buildings.btype[ob]]
				var room := maxi(0, int(ot.get("cap", 20)) - e.b_otlar[ob])
				var put := mini(room, left)
				e.b_otlar[ob] += put
				left -= put
				if left > 0:
					var g := left * int(ot.get("overflow_gold", 20)) * 1000
					e.add_res(to, e.r_gold, g)
					e.events.push(SimEvents.Ev.LOOT, to, e.r_gold, g, H.handle(h), pos)
				return
		if left > 0:
			var g := left * D.h_head_value[ht * e.R + e.r_gold]
			if g > 0:
				e.add_res(to, e.r_gold, g)
				e.events.push(SimEvents.Ev.LOOT, to, e.r_gold, g, H.handle(h), pos)
		return
	# овцы: в свои короо до предела, остальные — едой
	var left := give_heads(e, to, ht, heads, -1) if e.faction_has(to, "koch") else heads
	if left > 0:
		for r in e.R:
			var v := D.h_head_value[ht * e.R + r]
			if v > 0:
				e.add_res(to, r, v * left)
				e.events.push(SimEvents.Ev.LOOT, to, r, v * left, H.handle(h), pos)


var _captor_owner_of := {}               # описатель угнанного стада → игрок-налётчик (на случай ухода)


func _captor_owner(e: EconomySim, h: int) -> int:
	return int(_captor_owner_of.get(e.herds.handle(h), -1))


func _otxona(e: EconomySim, p: int) -> int:
	var B := e.buildings
	for b in B.hw:
		if B.owner[b] == p and e.active(b) and not e.defs.b_otlar[B.btype[b]].is_empty():
			return b
	return -1


func _driven_second(e: EconomySim, h: int) -> void:
	var H := e.herds
	var B := e.buildings
	var pen := H.pen_b[h]
	var goal := Vector2(H.x[h], H.z[h])
	var home := H.captor_u[h] == 0 and H.capture_t[h] < 0   # бежит домой после гибели налётчика
	if B.valid(pen):
		var b := B.slot(pen)
		if B.state[b] == BuildingTable.State.PACKED:
			return                                          # едет с арбой (EconNomad)
		goal = Vector2(B.x[b], B.z[b]) if home else e.b_dest[b]
	elif home:
		H.release(h)
		return
	var pos := Vector2(H.x[h], H.z[h])
	var v := float(e.rule("loot_carry", "flee_home_speed", 6.0)) if home else 3.0
	var d := goal - pos
	if d.length_squared() <= v * v:
		H.x[h] = goal.x
		H.z[h] = goal.y
		if home and B.valid(pen):
			var into := herd_at(e, B.slot(pen), H.htype[h])
			var heads := H.heads_milli[h] / 1000
			if into >= 0 and into != h:
				H.heads_milli[into] += H.heads_milli[h]
				H.release(h)
				e.events.push(SimEvents.Ev.HERD_RETURNED, H.owner[into], H.handle(into), pen, heads, goal)
			else:
				H.state[h] = HerdTable.State.PEN
				H.capture_t[h] = 0
				e.events.push(SimEvents.Ev.HERD_RETURNED, H.owner[h], H.handle(h), pen, heads, goal)
		else:
			H.state[h] = HerdTable.State.PEN
	else:
		var step := d.normalized() * v
		H.x[h] = pos.x + step.x
		H.z[h] = pos.y + step.y


# ================================================================= кони как ресурс

## Снять n голов вида htype у игрока p: сперва с загона hint_b, потом с самых больших стад
func take_heads(e: EconomySim, p: int, htype: int, n: int, hint_b: int) -> void:
	var H := e.herds
	var left := n
	if hint_b >= 0:
		var h := herd_at(e, hint_b, htype)
		if h >= 0:
			var k := mini(left, H.heads_milli[h] / 1000)
			H.heads_milli[h] -= k * 1000
			left -= k
	while left > 0:
		var best := -1
		for h in H.hw:
			if H.state[h] == HerdTable.State.PEN and H.owner[h] == p and H.htype[h] == htype and H.heads_milli[h] >= 1000:
				if best < 0 or H.heads_milli[h] > H.heads_milli[best]:
					best = h
		if best < 0:
			break
		H.heads_milli[best] -= 1000
		left -= 1
	_sync(e, p)


## Добавить n голов: в загон hint_b, иначе в стада с местом (меньшие первыми); вернуть, сколько не влезло
func give_heads(e: EconomySim, p: int, htype: int, n: int, hint_b: int) -> int:
	var H := e.herds
	var B := e.buildings
	var left := n
	if hint_b >= 0:
		var h := herd_at(e, hint_b, htype)
		if h >= 0:
			var room := e.defs.b_herd_cap[B.btype[hint_b]] - H.heads_milli[h] / 1000
			var k := mini(left, maxi(room, 0))
			H.heads_milli[h] += k * 1000
			left -= k
	while left > 0:
		var best := -1
		for h in H.hw:
			if H.state[h] != HerdTable.State.PEN or H.owner[h] != p or H.htype[h] != htype or not B.valid(H.pen_b[h]):
				continue
			var cap := e.defs.b_herd_cap[B.btype[B.slot(H.pen_b[h])]]
			if H.heads_milli[h] / 1000 >= cap:
				continue
			# сперва дворы с приплодом, потом коновязь
			var breed := e.defs.b_herd_breed[B.btype[B.slot(H.pen_b[h])]]
			if best < 0:
				best = h
			else:
				var bb := e.defs.b_herd_breed[B.btype[B.slot(H.pen_b[best])]]
				if breed > bb or (breed == bb and H.heads_milli[h] < H.heads_milli[best]):
					best = h
		if best < 0:
			break
		H.heads_milli[best] += 1000
		left -= 1
	_sync(e, p)
	return left


## Запас ресурсов-«подложек» (кони) = Σ голов стад игрока (у загонов и на перегоне)
func _sync(e: EconomySim, p: int) -> void:
	if p < 0 or p >= e.players.count:
		return
	var H := e.herds
	for r in e.R:
		var ht := e.defs.r_backing[r]
		if ht < 0:
			continue
		var sum := 0
		for h in H.hw:
			if H.owner[h] == p and H.htype[h] == ht and (H.state[h] == HerdTable.State.PEN or
					(H.state[h] == HerdTable.State.DRIVEN and H.captor_u[h] == 0 and H.capture_t[h] >= 0)):
				sum += H.heads_milli[h] / 1000
		e.players.res[p * e.R + r] = sum * 1000


## Дворы делят коней поровну; с первым двором кони коновязи переходят туда
func _equalize_horses(e: EconomySim, p: int) -> void:
	var H := e.herds
	var B := e.buildings
	var D := e.defs
	var ht := D.herd(&"horse")
	if ht < 0:
		return
	var yards := PackedInt32Array()
	var posts := PackedInt32Array()
	var total := 0
	for h in H.hw:
		if H.state[h] != HerdTable.State.PEN or H.owner[h] != p or H.htype[h] != ht or not B.valid(H.pen_b[h]):
			continue
		var b := B.slot(H.pen_b[h])
		if not e.active(b):
			continue
		total += H.heads_milli[h]
		if D.b_herd_breed[B.btype[b]] == 1:
			yards.append(h)
		else:
			posts.append(h)
	if yards.is_empty():
		return
	var left := total
	for h in posts:
		H.heads_milli[h] = 0
	var n := yards.size()
	for i in n:
		var h := yards[i]
		var cap := D.b_herd_cap[B.btype[B.slot(H.pen_b[h])]] * 1000
		var share := total / n + (1 if i < (total % n) else 0)
		H.heads_milli[h] = mini(share, cap)
		left -= H.heads_milli[h]
	# сверх пределов дворов — обратно на коновязь, потом в дворы с местом
	for h in posts:
		if left <= 0:
			break
		var cap := D.b_herd_cap[B.btype[B.slot(H.pen_b[h])]] * 1000
		var put := mini(left, cap)
		H.heads_milli[h] = put
		left -= put
	for h in yards:
		if left <= 0:
			break
		H.heads_milli[h] += left
		left = 0


# ================================================================= приказы и события

func herd_move(e: EconomySim, p: int, herd_h: int, to: Vector2) -> int:
	var H := e.herds
	if not H.valid(herd_h):
		return -EconApi.Err.STALE
	var h := H.slot(herd_h)
	if H.owner[h] != p:
		return -EconApi.Err.NOT_OWNER
	if H.state[h] != HerdTable.State.PEN or not e.buildings.valid(H.pen_b[h]):
		return -EconApi.Err.BUSY
	var b := e.buildings.slot(H.pen_b[h])
	var r := float(e.rule("pasture", "auto_move_r", 80.0))
	if Vector2(e.buildings.x[b], e.buildings.z[b]).distance_squared_to(to) > r * r:
		return -EconApi.Err.NOT_ALLOWED
	e.b_dest[b] = to
	H.state[h] = HerdTable.State.DRIVEN
	H.captor_u[h] = 0
	H.capture_t[h] = 0
	return EconApi.Err.OK


## «Мал союу»: −10 овец, +120 еды, раз в 60 с на загон
func slaughter(e: EconomySim, p: int, pen_h: int) -> int:
	var b := e._own(p, pen_h)
	if b < 0:
		return b
	var hs: Dictionary = e.rules.get("herds", {})
	var n := int(hs.get("slaughter_heads", 10))
	var h := herd_at(e, b, -1)
	if h < 0 or n <= 0 or not e.active(b):
		return -EconApi.Err.NOT_ALLOWED
	if e.tick < e.b_cd[b]:
		return -EconApi.Err.BUSY
	if e.herds.heads_milli[h] < n * 1000:
		return -EconApi.Err.NO_RES
	e.herds.heads_milli[h] -= n * 1000
	e.add_res(p, e.r_food, int(hs.get("slaughter_food", 120)) * 1000)
	e.b_cd[b] = e.tick + int(hs.get("slaughter_cd_ticks", 1800))
	e.events.push(SimEvents.Ev.LOOT, p, e.r_food, int(hs.get("slaughter_food", 120)) * 1000, pen_h,
		Vector2(e.buildings.x[b], e.buildings.z[b]))
	return EconApi.Err.OK


## Загон разрушен/снесён: кони уходят в другие табуны игрока (что не влезло — пропало), отара пропадает
func on_pen_gone(e: EconomySim, b: int) -> void:
	var H := e.herds
	var bh := e.buildings.handle(b)
	var packed := e.buildings.state[b] == BuildingTable.State.PACKED
	for h in H.hw:
		if H.state[h] == HerdTable.State.FREE or H.pen_b[h] != bh or H.state[h] == HerdTable.State.CAPTURED:
			continue
		var p := H.owner[h]
		var heads := H.heads_milli[h] / 1000
		H.release(h)
		if not packed and e.defs.h_backing[H.htype[h]] >= 0:
			give_heads(e, p, H.htype[h], heads, -1)
		_sync(e, p)


## Налётчик с угнанным стадом убит (dead) — стадо бежит домой; убран с карты живым — добыча его хозяину
func on_captor_gone(e: EconomySim, u_h: int, dead: bool) -> void:
	var H := e.herds
	for h in H.hw:
		if H.state[h] != HerdTable.State.CAPTURED or H.captor_u[h] != u_h:
			continue
		if dead:
			H.state[h] = HerdTable.State.DRIVEN
			H.captor_u[h] = 0
			H.capture_t[h] = -1
		else:
			_bank(e, h, true, -1)


## Угнать heads голов из стада h налётчиком captor (барымта): новое стадо CAPTURED
func steal(e: EconomySim, h: int, heads: int, captor: int, captor_p: int) -> int:
	var H := e.herds
	var take := mini(heads, H.heads_milli[h] / 1000)
	if take <= 0:
		return 0
	H.heads_milli[h] -= take * 1000
	var s := H.alloc(HerdTable.State.CAPTURED)
	H.htype[s] = H.htype[h]
	H.owner[s] = H.owner[h]
	H.pen_b[s] = H.pen_b[h]
	H.heads_milli[s] = take * 1000
	H.captor_u[s] = captor
	H.capture_t[s] = 0
	H.graze_r[s] = H.graze_r[h]
	H.x[s] = H.x[h]
	H.z[s] = H.z[h]
	_captor_owner_of[H.handle(s)] = captor_p
	_sync(e, H.owner[h])
	e.events.push(SimEvents.Ev.HERD_STOLEN, H.owner[h], H.handle(s), captor, take, Vector2(H.x[h], H.z[h]))
	return H.handle(s)


## Угнать коней «отлар» из Отхоны (у Коканда это не стадо): стадо CAPTURED без загона
func steal_otlar(e: EconomySim, b: int, n: int, captor: int, captor_p: int) -> int:
	var take := mini(n, e.b_otlar[b])
	var ht := e.defs.herd(&"horse")
	if take <= 0 or ht < 0:
		return 0
	e.b_otlar[b] -= take
	var H := e.herds
	var s := H.alloc(HerdTable.State.CAPTURED)
	H.htype[s] = ht
	H.owner[s] = e.buildings.owner[b]
	H.pen_b[s] = e.buildings.handle(b)
	H.heads_milli[s] = take * 1000
	H.captor_u[s] = captor
	H.graze_r[s] = e.defs.h_graze_r[ht]
	H.x[s] = e.buildings.x[b]
	H.z[s] = e.buildings.z[b]
	_captor_owner_of[H.handle(s)] = captor_p
	e.events.push(SimEvents.Ev.HERD_STOLEN, H.owner[s], H.handle(s), captor, take, Vector2(H.x[s], H.z[s]))
	return H.handle(s)


## Загон встал после көча: стада снова пасутся у него
func on_unpacked(e: EconomySim, b: int) -> void:
	var H := e.herds
	var bh := e.buildings.handle(b)
	for h in H.hw:
		if H.state[h] != HerdTable.State.FREE and H.pen_b[h] == bh and H.state[h] != HerdTable.State.CAPTURED:
			H.state[h] = HerdTable.State.PEN
			H.x[h] = e.buildings.x[b]
			H.z[h] = e.buildings.z[b]
	_sync(e, e.buildings.owner[b])
