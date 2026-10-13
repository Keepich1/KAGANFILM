class_name EconRaids
extends RefCounted
## Действия набега с кругом прогресса (ECONOMY §4.1; ARCHITECTURE §11 «Herds and theft»). Раз в секунду
## у каждой цели считаются вражеские всадники рядом (радиус — край следа + 12 м), одного игрока:
##   • барымта: табун (двор, коновязь ставки, «отлар» Отхоны) или отара короо; от 5 всадников, круг 6 с;
##     итог — 1 конь на 2 всадника (до 15) или 10 овец: стадо CAPTURED идёт за налётчиком (EconHerds);
##   • талоо (только кочевники, черта «loot»): Тегирмон — еда, Омбор и Бозор — золото; от 10 всадников,
##     круг 10 с; 10% запаса хозяина (до 300) — тюки едут на налётчике, дошёл домой — олжо, убит — назад;
##     одно здание — не чаще раза в 90 с;
##   • вытоптать поле: от 5 всадников, круг 5 с — поле не родит 45 с.
## Круг замирает, если в 30 м есть боевой юнит хозяина; срывается, если налётчиков ранили (рукопашная)
## или их стало меньше 80% от начала. Пока угнанное отсюда не уведено (банк или возврат) — новой барымты нет. Прогресс — EconomySim.b_act (вид и панель: raid_progress).

enum Act { NONE, HERD, TALOO, TRAMPLE }

var _buf := PackedInt32Array()
var _guard := PackedInt32Array()
var _target_t := PackedByteArray()       # [вид здания] бывает целью набега (поле, загон, Отхона, склад еды/золота, базар)
# тюки талоо на налётчиках
var l_unit := PackedInt32Array()
var l_owner := PackedInt32Array()
var l_victim := PackedInt32Array()
var l_res := PackedInt32Array()
var l_amt := PackedInt32Array()


func setup(e: EconomySim) -> void:
	var D := e.defs
	_target_t.resize(D.b_ids.size())
	for bt in D.b_ids.size():
		var fl := D.b_flags[bt]
		var store := D.b_accepts[bt]
		var t := D.b_kind[bt] == Defs.BKind.FIELD or D.b_herd[bt] >= 0 or not D.b_otlar[bt].is_empty() \
			or fl & Defs.BF_MARKET != 0 or (fl & Defs.BF_DROP != 0 and store & ((1 << e.r_gold) | (1 << e.r_food)) != 0)
		_target_t[bt] = 1 if t else 0


## Какое действие возможно по зданию b и сколько всадников нужно / тактов круга
func act_of(e: EconomySim, b: int) -> int:
	var B := e.buildings
	var bt := B.btype[b]
	var D := e.defs
	if D.b_kind[bt] == Defs.BKind.FIELD:
		return Act.TRAMPLE
	if e.b_otlar[b] > 0:
		return Act.HERD
	if D.b_herd[bt] >= 0:
		# двор, короо, коновязь ставки
		var h := e.hd.herd_at(e, b, -1)
		if h >= 0 and e.herds.heads_milli[h] >= 1000 and D.h_capturable[e.herds.htype[h]] == 1:
			return Act.HERD
		if B.flags[b] & Defs.BF_PEN:
			return Act.NONE
	if B.flags[b] & Defs.BF_HQ:
		return Act.NONE
	if B.flags[b] & Defs.BF_MARKET or (B.flags[b] & Defs.BF_DROP and B.store_mask[b] & (1 << e.r_gold)):
		return Act.TALOO
	if B.flags[b] & Defs.BF_DROP and B.store_mask[b] & (1 << e.r_food):
		return Act.TALOO
	return Act.NONE


func raid_progress(e: EconomySim, b: int) -> float:
	var need := _circle(e, act_of(e, b))
	return clampf(float(e.b_act[b]) / float(need), 0.0, 1.0) if need > 0 else 0.0


func _circle(e: EconomySim, act: int) -> int:
	match act:
		Act.HERD: return int(e.rule("herd_theft", "circle_ticks", 180))
		Act.TALOO: return int(e.rule("taloo", "circle_ticks", 300))
		Act.TRAMPLE: return int(e.rule("trample", "circle_ticks", 150))
	return 0


func _min_riders(e: EconomySim, act: int) -> int:
	match act:
		Act.HERD: return int(e.rule("herd_theft", "min_riders", 5))
		Act.TALOO: return int(e.rule("taloo", "min_riders", 10))
		Act.TRAMPLE: return int(e.rule("trample", "min_riders", 5))
	return 999999


func slow_step(e: EconomySim) -> void:
	_loot_second(e)
	if e.port == null:
		return
	var B := e.buildings
	var guard_r := float(e.rule("herd_theft", "guard_r", 30.0))
	var abort := roundi(float(e.rule("herd_theft", "abort_loss", 0.2)) * 1000.0)
	# только запросы договора с командой здания (CombatPort §7.1): сперва дешёвый enemy_near, потом всадники
	for b in B.hw:
		if _target_t[B.btype[b]] == 0 or not e.active(b):
			continue
		var act := act_of(e, b)
		var need := _circle(e, act)
		if act == Act.NONE or need <= 0:
			e.b_act[b] = 0
			continue
		if act == Act.TALOO and e.tick < e.b_cd[b]:
			continue
		if act == Act.TRAMPLE and e.tick < e.b_cd2[b]:
			continue
		var c := Vector2(B.x[b], B.z[b])
		var r := e.half_of(b).length() + 12.0
		var team := B.team[b]
		if not e.port.enemy_near(team, c, r):
			e.b_act[b] = 0
			continue
		e.port.units_near(team, c, r, true, UnitStats.MOUNTED, _buf)
		if _buf.is_empty():
			e.b_act[b] = 0
			continue
		var raider := _buf[0]
		var rp := e.port.owner(raider)
		var n := 0
		var hurt := false
		for u in _buf:
			if e.port.owner(u) == rp:
				n += 1
				if e.port.hurt_within(u, 45):
					hurt = true
		if act == Act.TALOO and not e.faction_has(rp, "loot"):
			continue
		if act == Act.HERD and _carrying_from(e, b, rp):
			continue                # сперва увести угнанное отсюда
		if n < _min_riders(e, act):
			e.b_act[b] = 0
			continue
		if e.b_act[b] > 0 and (hurt or n * 1000 < e.b_act_n[b] * (1000 - abort)):
			e.b_act[b] = 0          # сорвано
			continue
		if _guarded(e, team, c, guard_r):
			continue                # круг замирает
		if e.b_act[b] == 0:
			e.b_act_n[b] = n
		e.b_act[b] += 30
		if e.b_act[b] >= need:
			e.b_act[b] = 0
			_execute(e, b, act, raider, rp, n)


## Налётчики игрока rp ещё ведут стадо, угнанное из b
func _carrying_from(e: EconomySim, b: int, rp: int) -> bool:
	var H := e.herds
	var bh := e.buildings.handle(b)
	for h in H.hw:
		if H.state[h] == HerdTable.State.CAPTURED and H.pen_b[h] == bh and e.hd._captor_owner(e, h) == rp:
			return true
	return false


## Боевой юнит хозяина (не работник, не арба) в радиусе
func _guarded(e: EconomySim, team: int, c: Vector2, r: float) -> bool:
	e.port.units_near(team, c, r, false, 0, _guard)
	for u in _guard:
		var fl := int(UnitStats.get_stats(String(e.port.type_id(u))).get("flags", 0))
		if fl & (UnitStats.WORKER | UnitStats.WAGON) == 0:
			return true
	return false


func _execute(e: EconomySim, b: int, act: int, raider: int, rp: int, n: int) -> void:
	var B := e.buildings
	match act:
		Act.HERD:
			if e.b_otlar[b] > 0:
				var k := mini(n / maxi(int(e.rule("herd_theft", "horses_per_riders", 2)), 1), int(e.rule("herd_theft", "horses_max", 15)))
				e.hd.steal_otlar(e, b, k, raider, rp)
				return
			var h := e.hd.herd_at(e, b, -1)
			if h < 0:
				return
			var take := int(e.rule("herd_theft", "sheep", 10))
			if e.defs.h_backing[e.herds.htype[h]] >= 0:
				take = mini(n / maxi(int(e.rule("herd_theft", "horses_per_riders", 2)), 1), int(e.rule("herd_theft", "horses_max", 15)))
			e.hd.steal(e, h, take, raider, rp)
		Act.TALOO:
			var r := e.r_gold if (B.flags[b] & Defs.BF_MARKET or B.store_mask[b] & (1 << e.r_gold)) else e.r_food
			var victim := B.owner[b]
			var stock := e.players.res[victim * e.R + r]
			var amt := mini(stock * roundi(float(e.rule("taloo", "frac", 0.1)) * 1000.0) / 1000,
				int(e.rule("taloo", "max", 300)) * 1000)
			e.b_cd[b] = e.tick + int(e.rule("taloo", "cooldown_ticks", 2700))
			if amt <= 0:
				return
			e.players.res[victim * e.R + r] -= amt
			l_unit.append(raider)
			l_owner.append(rp)
			l_victim.append(victim)
			l_res.append(r)
			l_amt.append(amt)
			e.events.push(SimEvents.Ev.BUILDING_HIT, victim, B.handle(b), 0, raider, Vector2(B.x[b], B.z[b]))
		Act.TRAMPLE:
			e.b_cd2[b] = e.tick + int(e.rule("trample", "fallow_ticks", 1350))
			e.events.push(SimEvents.Ev.BUILDING_HIT, B.owner[b], B.handle(b), 0, raider, Vector2(B.x[b], B.z[b]))


## Тюки талоо: дошёл до своей ставки/загона/склада — олжо; ушёл с карты живым — тоже олжо
func _loot_second(e: EconomySim) -> void:
	var bank_r := float(e.rule("loot_carry", "bank_r", 30.0))
	var i := 0
	while i < l_unit.size():
		var u := l_unit[i]
		var done := false
		if e.port == null or not e.port.valid(u) or not e.port.alive(u):
			done = true
		else:
			var pos := e.port.pos(u)
			var B := e.buildings
			for b in B.hw:
				if B.owner[b] == l_owner[i] and e.active(b) and B.flags[b] & (Defs.BF_HQ | Defs.BF_PEN | Defs.BF_DROP) \
						and e.rect_dist2(b, pos) <= bank_r * bank_r:
					done = true
					break
		if done:
			e.add_res(l_owner[i], l_res[i], l_amt[i])
			e.events.push(SimEvents.Ev.LOOT, l_owner[i], l_res[i], l_amt[i], u, e.port.pos(u) if e.port and e.port.valid(u) else Vector2.ZERO)
			_drop(i)
		else:
			i += 1


## «Бросить»: тюки игрока p на units/sqs возвращаются хозяину склада
func drop(e: EconomySim, p: int, units: PackedInt32Array, sqs: PackedInt32Array) -> int:
	var n := 0
	var i := 0
	while i < l_unit.size():
		if l_owner[i] == p and e.led_by(l_unit[i], units, sqs):
			e.add_res(l_victim[i], l_res[i], l_amt[i], false)
			_drop(i)
			n += 1
		else:
			i += 1
	return n


## Налётчик убит (dead) — тюки возвращаются хозяину склада
func on_unit_gone(e: EconomySim, u_h: int, dead: bool) -> void:
	var i := 0
	while i < l_unit.size():
		if l_unit[i] == u_h and dead:
			e.add_res(l_victim[i], l_res[i], l_amt[i], false)
			_drop(i)
		else:
			i += 1


func _drop(i: int) -> void:
	l_unit.remove_at(i)
	l_owner.remove_at(i)
	l_victim.remove_at(i)
	l_res.remove_at(i)
	l_amt.remove_at(i)
