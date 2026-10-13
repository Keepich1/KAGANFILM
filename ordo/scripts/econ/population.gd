class_name EconPopulation
extends RefCounted
## Население, содержание, голод, подать (ARCHITECTURE §11; ECONOMY §1.4, §1.5, §2.5).
##   • предел = min(500, Σ pop_cap готовых построек; свёрнутые и сворачиваемые — 0);
##   • содержание — Σ UnitEcon.upkeep живых бойцов, списывается раз в upkeep_every_s (остаток копится);
##   • голод: еды не хватило на списание → еда 0, famine = 1, FAMINE(1), множители голода в ядро;
##     через desert_after_s — дезертирство: каждые desert_every_s каждый отряд теряет 3% (не меньше 1),
##     первыми — дальние от ставки; одиночки считаются одним отрядом (иначе ушли бы все разом); конец — когда еды снова end_food (50) и больше: FAMINE(0);
##   • подать: пока есть Бозор, раз в tax.every_s — tax_min целых (HP ≥ 50%) Уй и Урды; в голод — нет.

var upk_acc := PackedInt64Array()        # остаток содержания (милли·с/мин)
var famine_t := PackedInt32Array()       # такт начала голода
var desert_next := PackedInt32Array()    # такт следующего дезертирства


func add_player(e: EconomySim) -> void:
	upk_acc.append(0)
	famine_t.append(0)
	desert_next.append(0)


func recompute_caps(e: EconomySim) -> void:
	e._pop_dirty = false
	var P := e.players
	var B := e.buildings
	var caps := PackedInt32Array()
	caps.resize(P.count)
	for b in B.hw:
		var p := B.owner[b]
		if p >= 0 and p < P.count and e.active(b):
			caps[p] += e.defs.b_pop_cap[B.btype[b]]
	for p in P.count:
		P.pop_cap[p] = mini(caps[p], e.pop_max)


func slow_step(e: EconomySim) -> void:
	var P := e.players
	var every := maxi(int(e.rules.get("upkeep_every_ticks", 300)), 30)
	var upkeep_on := bool(e.rules.get("upkeep", true))
	var end_food := int(e.rule("famine", "end_food", 50)) * 1000
	for p in P.count:
		if P.alive[p] == 0:
			continue
		if upkeep_on and e.tick % every == 0:
			_charge(e, p, every)
		if P.famine[p] == 1:
			if P.res[p * e.R + e.r_food] >= end_food:
				_end_famine(e, p)
			elif e.tick >= desert_next[p] and desert_next[p] > 0:
				_desert(e, p)
				var de := int(e.rule("famine", "desert_every_ticks", 900))
				desert_next[p] = e.tick + maxi(de, 30) if de > 0 else 0
	var tax_every := int(e.rule("tax", "every_ticks", 900))
	if tax_every > 0 and e.tick % tax_every == 0:
		_tax(e, tax_every)


## Списать содержание за every тактов: Σ милли/мин × (every / 1800), остаток — в upk_acc
func _charge(e: EconomySim, p: int, every: int) -> void:
	var P := e.players
	var need_x := int(e.p_upkeep[p]) * every + upk_acc[p]     # милли × такты/мин
	var charge := need_x / 1800
	upk_acc[p] = need_x - charge * 1800
	if charge <= 0:
		return
	charge = charge * e.mods.upkeep_milli(e, p) / 1000
	var i := p * e.R + e.r_food
	e.p_flow[i] -= charge
	if P.res[i] >= charge:
		P.res[i] -= charge
	else:
		P.res[i] = 0
		if P.famine[p] == 0:
			_start_famine(e, p)


func _start_famine(e: EconomySim, p: int) -> void:
	var P := e.players
	P.famine[p] = 1
	famine_t[p] = e.tick
	var da := int(e.rule("famine", "desert_after_ticks", 1800))
	desert_next[p] = e.tick + da if da >= 0 else 0
	e.events.push(SimEvents.Ev.FAMINE, p, 1, da, 0, _hq_pos(e, p))
	e.mods.mark(e, p)


func _end_famine(e: EconomySim, p: int) -> void:
	e.players.famine[p] = 0
	desert_next[p] = 0
	e.events.push(SimEvents.Ev.FAMINE, p, 0, 0, 0, _hq_pos(e, p))
	e.mods.mark(e, p)


## Дезертирство: каждый отряд бойцов теряет desert_frac (не меньше 1); первыми — дальние от ставки
func _desert(e: EconomySim, p: int) -> void:
	if e.port == null:
		return
	var frac := roundi(float(e.rule("famine", "desert_frac", 0.03)) * 1000.0)
	var hq := _hq_pos(e, p)
	# отряды игрока (по слотам юнитов — детерминированно), дальние первыми
	var squads := PackedInt32Array()
	var dist := PackedFloat32Array()
	for s in e.un_gen.size():
		if e.un_gen[s] == 0 or e.un_owner[s] != p or e.un_w[s] >= 0 or e.un_cargo[s] > 0:
			continue
		var u_h := Ids.make(Ids.Kind.UNIT, s, e.un_gen[s])
		var sq := e.port.squad_of(u_h)
		if sq != 0 and not squads.has(sq):
			squads.append(sq)
			dist.append(e.port.pos(sq).distance_squared_to(hq))
	# сортировка вставками по убыванию расстояния (отрядов немного)
	for i in range(1, squads.size()):
		var j := i
		while j > 0 and dist[j - 1] < dist[j]:
			var td := dist[j]; dist[j] = dist[j - 1]; dist[j - 1] = td
			var ts := squads[j]; squads[j] = squads[j - 1]; squads[j - 1] = ts
			j -= 1
	# одиночки (нанятые по одному) — одной группой: 3% от всех, не меньше 1, дальние первыми
	var singles := PackedInt32Array()
	for sq in squads:
		var m := e.port.members(sq)
		if m.size() == 1:
			singles.append(m[0])
			continue
		var k := maxi(1, m.size() * frac / 1000)
		for i in mini(k, m.size()):
			_leave_army(e, p, m[m.size() - 1 - i])
	if not singles.is_empty():
		for i in maxi(1, singles.size() * frac / 1000):
			_leave_army(e, p, singles[i])


func _leave_army(e: EconomySim, p: int, u_h: int) -> void:
	var pos := e.port.pos(u_h)
	e.unregister_unit(u_h)
	e.events.push(SimEvents.Ev.UNIT_DIED, p, u_h, 0, -1, pos)
	e.port.remove(u_h)


## Подать: пока у игрока есть Бозор (флаг market) и нет голода
func _tax(e: EconomySim, every: int) -> void:
	var P := e.players
	var B := e.buildings
	var min_hp := roundi(float(e.rule("tax", "min_hp", 0.5)) * 1000.0)
	var no_tax := bool(e.rule("famine", "no_tax", true))
	for p in P.count:
		if P.alive[p] == 0 or (no_tax and P.famine[p] == 1):
			continue
		var market := -1
		for b in B.hw:
			if B.owner[b] == p and e.active(b) and B.flags[b] & Defs.BF_MARKET:
				market = b
				break
		if market < 0:
			continue
		var sum := 0
		for b in B.hw:
			if B.owner[b] != p or not e.active(b):
				continue
			var t := e.defs.b_tax_milli_min[B.btype[b]]
			if t > 0 and B.hp_c[b] * 1000 >= B.hp_max_c[b] * min_hp:
				sum += t
		var gold := sum * every / 1800
		if gold > 0:
			e.add_res(p, e.r_gold, gold)
			e.events.push(SimEvents.Ev.RES_DELIVERED, p, e.r_gold, gold, B.handle(market), Vector2(B.x[market], B.z[market]))


func _hq_pos(e: EconomySim, p: int) -> Vector2:
	var h := e.players.hq_b[p]
	if e.buildings.valid(h):
		var b := e.buildings.slot(h)
		return Vector2(e.buildings.x[b], e.buildings.z[b])
	return Vector2.ZERO
