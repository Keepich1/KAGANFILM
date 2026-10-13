class_name EconProduction
extends RefCounted
## Найм по одному и мастерские (ARCHITECTURE §11 «Production»; ECONOMY §1.4, §2.4, §2.7, §3.2–3.3).
##   • цена — при постановке в очередь (до 5), возврат — при отмене; конь кыпчакского всадника снимается
##     с табуна двора найма (или самого большого); Коканд: «отлар» Отхоны — −25 золота за коня;
##   • голова очереди занимает место населения, когда начинает; мест нет — очередь стоит (POP_CAPPED);
##   • в голод нельзя нанимать за еду (ECONOMY §1.5) — такие головы ждут;
##   • юнит выходит у двери (фасад +Z, повёрнутый на rot_q) и идёт к точке сбора; работник с точкой сбора
##     на узле/поле сразу берётся за работу; полководец — один, после гибели снова через 120 с;
##   • мастерская (Хумдон): партия рецепта на каждого работника; без дров стоит, без воды — 50%.


func setup(e: EconomySim) -> void:
	pass


## Причина, почему нельзя нанять utype в здании b (Err), 0 — можно (без цены)
func why_not(e: EconomySim, p: int, b: int, utype: int) -> int:
	var D := e.defs
	var B := e.buildings
	if B.owner[b] != p:
		return EconApi.Err.NOT_OWNER
	if not e.active(b):
		return EconApi.Err.BUSY
	if not D.b_trains[B.btype[b]].has(utype) or D.u_enabled[utype] == 0:
		return EconApi.Err.NOT_ALLOWED
	if not e.has_required(p, D.u_requires[utype]):
		return EconApi.Err.NOT_ALLOWED
	if D.u_unique[utype] == 1 and (_alive_or_queued(e, p, utype) > 0 or e.tick < e.p_unique[p * D.unit_ids.size() + utype]):
		return EconApi.Err.NOT_ALLOWED
	if e.players.famine[p] == 1 and bool(e.rule("famine", "no_food_hire", true)) and D.u_cost[utype * e.R + e.r_food] > 0:
		return EconApi.Err.NOT_ALLOWED
	if B.q_n[b] >= BuildingTable.QMAX:
		return EconApi.Err.QUEUE_FULL
	return 0


## Цена найма с учётом «отлар» (скидка золотом за коня в Отхоне); disc — сколько коней берётся
func cost_of(e: EconomySim, p: int, utype: int) -> PackedInt32Array:
	var cost := e.defs.unit_cost(utype)
	if _otlar_discount(e, p, utype) > 0 and e.r_gold >= 0:
		cost[e.r_gold] = maxi(0, cost[e.r_gold] - _otlar_discount(e, p, utype))
	return cost


func _otlar_discount(e: EconomySim, p: int, utype: int) -> int:
	if e.defs.u_flags[utype] & UnitStats.MOUNTED == 0 or e.r_horse < 0 or e.defs.u_cost[utype * e.R + e.r_horse] > 0:
		return 0
	var b := _otlar_building(e, p)
	if b < 0:
		return 0
	var ot: Dictionary = e.defs.b_otlar[e.buildings.btype[b]]
	return int(ot.get("discount_gold", 0)) * 1000


func _otlar_building(e: EconomySim, p: int) -> int:
	var B := e.buildings
	for b in B.hw:
		if B.owner[b] == p and e.active(b) and e.b_otlar[b] > 0:
			return b
	return -1


func train(e: EconomySim, p: int, b_h: int, utype: int, count: int) -> int:
	if not e.buildings.valid(b_h):
		return -EconApi.Err.STALE
	if utype < 0 or utype >= e.defs.unit_ids.size():
		return -EconApi.Err.INVALID
	var b := e.buildings.slot(b_h)
	var why := why_not(e, p, b, utype)
	if why != 0:
		return -why
	var B := e.buildings
	var added := 0
	for i in maxi(count, 1):
		if B.q_n[b] >= BuildingTable.QMAX:
			break
		if e.defs.u_unique[utype] == 1 and (added > 0 or _alive_or_queued(e, p, utype) > 0):
			break
		var disc := _otlar_discount(e, p, utype)
		var cost := cost_of(e, p, utype)
		if not e.can_pay(p, cost):
			if added == 0:
				e._not_enough(p, cost, SimCmd.Op.TRAIN)
				return -EconApi.Err.NO_RES
			break
		e.pay(p, cost, b)
		var k := B.q_n[b]
		B.q[b * BuildingTable.QMAX + k] = utype
		e.bq_disc[b * BuildingTable.QMAX + k] = 0
		if disc > 0:
			var ob := _otlar_building(e, p)
			e.b_otlar[ob] -= 1
			e.bq_disc[b * BuildingTable.QMAX + k] = mini(disc, e.defs.u_cost[utype * e.R + e.r_gold])
		B.q_n[b] += 1
		added += 1
	if added == 0:
		return -EconApi.Err.QUEUE_FULL
	if not e._queues.has(b):
		e._queues.append(b)
	e.events.push(SimEvents.Ev.QUEUE_CHANGED, p, b_h, B.q_n[b], 0, Vector2(B.x[b], B.z[b]))
	return EconApi.Err.OK


func cancel(e: EconomySim, p: int, b_h: int, index: int) -> int:
	if not e.buildings.valid(b_h):
		return -EconApi.Err.STALE
	var b := e.buildings.slot(b_h)
	var B := e.buildings
	if B.owner[b] != p:
		return -EconApi.Err.NOT_OWNER
	if index < 0 or index >= B.q_n[b]:
		return -EconApi.Err.INVALID
	_drop_entry(e, b, index, true)
	e.events.push(SimEvents.Ev.QUEUE_CHANGED, p, b_h, B.q_n[b], 0, Vector2(B.x[b], B.z[b]))
	return EconApi.Err.OK


## Убрать запись очереди (refund — вернуть цену)
func _drop_entry(e: EconomySim, b: int, index: int, refund: bool) -> void:
	var B := e.buildings
	var Q := BuildingTable.QMAX
	var p := B.owner[b]
	var u := B.q[b * Q + index]
	if refund and u >= 0:
		var cost := e.defs.unit_cost(u)
		if e.bq_disc[b * Q + index] > 0:
			cost[e.r_gold] = maxi(0, cost[e.r_gold] - e.bq_disc[b * Q + index])
			var ob := _any_otxona(e, p)
			if ob >= 0:
				e.b_otlar[ob] += 1
		e.gain(p, cost, false, b)
	if index == 0 and B.q_t[b] > 0 and u >= 0:
		e.players.pop_reserved[p] = maxi(0, e.players.pop_reserved[p] - e.defs.u_pop[u])
		B.q_t[b] = 0
	for i in range(index, B.q_n[b] - 1):
		B.q[b * Q + i] = B.q[b * Q + i + 1]
		e.bq_disc[b * Q + i] = e.bq_disc[b * Q + i + 1]
	B.q_n[b] -= 1
	B.q[b * Q + B.q_n[b]] = -1
	e.bq_disc[b * Q + B.q_n[b]] = 0


func _any_otxona(e: EconomySim, p: int) -> int:
	var B := e.buildings
	for b in B.hw:
		if B.owner[b] == p and B.state[b] == BuildingTable.State.ACTIVE and not e.defs.b_otlar[B.btype[b]].is_empty():
			return b
	return -1


## Здание разрушено/свёрнуто: очередь возвращается
func clear_queue(e: EconomySim, b: int) -> void:
	var B := e.buildings
	while B.q_n[b] > 0:
		_drop_entry(e, b, B.q_n[b] - 1, true)
	B.q_t[b] = 0


func _alive_or_queued(e: EconomySim, p: int, utype: int) -> int:
	var n := 0
	for s in e.un_gen.size():
		if e.un_gen[s] != 0 and e.un_owner[s] == p and e.un_type[s] == utype:
			n += 1
	var B := e.buildings
	for b in e._queues:
		if B.owner[b] == p:
			for i in B.q_n[b]:
				if B.q[b * BuildingTable.QMAX + i] == utype:
					n += 1
	return n


# ================================================================= такт

func step(e: EconomySim) -> void:
	var B := e.buildings
	var P := e.players
	var Q := BuildingTable.QMAX
	var i := 0
	while i < e._queues.size():
		var b := e._queues[i]
		if B.q_n[b] <= 0 or B.state[b] == BuildingTable.State.FREE:
			e._queues.remove_at(i)
			continue
		i += 1
		if not e.active(b):
			continue
		var p := B.owner[b]
		var u := B.q[b * Q]
		var need := e.defs.u_pop[u]
		if B.q_t[b] == 0:
			# голод: за еду не нанимают
			if P.famine[p] == 1 and bool(e.rule("famine", "no_food_hire", true)) and e.defs.u_cost[u * e.R + e.r_food] > 0:
				continue
			if P.pop_used[p] + P.pop_reserved[p] + need > P.pop_cap[p]:
				if e.b_flag[b] & EconomySim.BFL_POP_CAPPED == 0:
					e.b_flag[b] |= EconomySim.BFL_POP_CAPPED
					e.events.push(SimEvents.Ev.POP_CAPPED, p, B.handle(b), P.pop_used[p], P.pop_cap[p], Vector2(B.x[b], B.z[b]))
				continue
			e.b_flag[b] &= ~EconomySim.BFL_POP_CAPPED
			P.pop_reserved[p] += need
		B.q_t[b] += 1
		if B.q_t[b] >= maxi(e.defs.u_train_ticks[u], 1):
			P.pop_reserved[p] = maxi(0, P.pop_reserved[p] - need)
			B.q_t[b] = 0
			for k in range(0, B.q_n[b] - 1):
				B.q[b * Q + k] = B.q[b * Q + k + 1]
				e.bq_disc[b * Q + k] = e.bq_disc[b * Q + k + 1]
			B.q_n[b] -= 1
			B.q[b * Q + B.q_n[b]] = -1
			e.bq_disc[b * Q + B.q_n[b]] = 0
			_spawn(e, b, u)
			e.events.push(SimEvents.Ev.QUEUE_CHANGED, p, B.handle(b), B.q_n[b], 0, Vector2(B.x[b], B.z[b]))


func _spawn(e: EconomySim, b: int, u: int) -> void:
	var B := e.buildings
	var p := B.owner[b]
	var door := e.door_of(b)
	var h := e.port.spawn(p, B.team[b], StringName(e.defs.unit_ids[u]), door, B.rot[b])
	if h == 0:
		return
	e.register_unit(h, p, u)
	var b_h := B.handle(b)
	e.events.push(SimEvents.Ev.UNIT_SPAWNED, p, h, b_h, u, door)
	e.events.push(SimEvents.Ev.TRAINED, p, h, b_h, u, door)
	# точка сбора
	var rh := B.rally_h[b]
	var w := e.un_w[Ids.slot(h)]
	if rh != 0 and w >= 0 and e.wk.assign_gather(e, p, PackedInt32Array([h]), rh) == EconApi.Err.OK:
		return
	if rh != 0 and Ids.kind(rh) == Ids.Kind.BUILDING and w >= 0 and e.buildings.valid(rh) \
			and e.buildings.state[e.buildings.slot(rh)] == BuildingTable.State.SITE:
		e.wk.send_builders(e, p, PackedInt32Array([h]), rh)
		return
	if B.rally_x[b] != 0.0 or B.rally_z[b] != 0.0:
		e.port.move(PackedInt32Array([h]), Vector2(B.rally_x[b], B.rally_z[b]), false)


# ================================================================= мастерские (раз в секунду)

## Хумдон: каждая партия рецепта на работника; дерево из запаса игрока, ғишт — в запас.
## Без воды печь работает на xumdon_dry (50%), без дров стоит (BFL_NO_FUEL — значок «нет дров»).
func recipes_step(e: EconomySim) -> void:
	var B := e.buildings
	var D := e.defs
	var R := e.R
	for b in B.hw:
		var rc := B.recipe[b]
		if rc < 0 or B.workers_n[b] <= 0 or not e.active(b) or D.rc_enabled[rc] == 0:
			continue
		var p := B.owner[b]
		var wet := 1000
		if D.b_water_place[B.btype[b]] > 0 and e.b_water[b] < 500:
			wet = roundi(float(e.rule("water", "xumdon_dry", 0.5)) * 1000.0)
		var n := mini(B.workers_n[b], D.rc_workers[rc])
		e.b_work[b] += n * wet * 30 / 1000          # тактов партии за секунду
		var per := D.rc_ticks[rc]
		while e.b_work[b] >= per:
			var cin := D.rc_in.slice(rc * R, rc * R + R)
			if not e.can_pay(p, cin):
				e.b_work[b] = per
				if e.b_flag[b] & EconomySim.BFL_NO_FUEL == 0:
					e.b_flag[b] |= EconomySim.BFL_NO_FUEL
					e._not_enough(p, cin, SimCmd.Op.SET_RECIPE)
				break
			e.b_flag[b] &= ~EconomySim.BFL_NO_FUEL
			e.b_work[b] -= per
			e.pay(p, cin)
			for r in R:
				if cin[r] > 0:
					e.p_flow[p * R + r] -= cin[r]
			e.gain(p, D.rc_out.slice(rc * R, rc * R + R), true, b)
			B.recipe_t[b] += 1
