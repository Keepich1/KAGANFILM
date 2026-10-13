class_name EconBounty
extends RefCounted
## Олжо кочевников (ECONOMY §4.2, ТЗ 5.4): только сторонам с FactionDefs.bounty и при rules.loot.
##   убит боец — 4 золота, 6 еды; убит работник — 10 золота, 10 еды; разрушено здание — 30% его цены
##   золотом; разрушена ставка — 400 золота. Событие LOOT на каждый ресурс (над местом — «+4 / +6»).

var total := PackedInt64Array()          # [p] олжо за игру, милли (все ресурсы) — для панели игрока


func _ensure(p: int) -> void:
	while total.size() <= p:
		total.append(0)


func on_kill(e: EconomySim, killer_p: int, victim_utype: int, src_h: int, pos: Vector2) -> void:
	if not bool(e.rules.get("loot", false)) or killer_p < 0:
		return
	var f := e.players.faction[killer_p]
	var worker := e.defs.u_flags[victim_utype] & UnitStats.WORKER != 0 and e.defs.u_flags[victim_utype] & UnitStats.WAGON == 0
	var row := e.defs.f_bounty_worker if worker else e.defs.f_bounty_kill
	_give(e, killer_p, row.slice(f * e.R, f * e.R + e.R), src_h, pos)


func on_building(e: EconomySim, b: int, killer_p: int) -> void:
	if not bool(e.rules.get("loot", false)) or killer_p < 0 or killer_p == e.buildings.owner[b]:
		return
	var D := e.defs
	var f := e.players.faction[killer_p]
	var bt := e.buildings.btype[b]
	var amounts := PackedInt32Array()
	amounts.resize(e.R)
	if e.buildings.flags[b] & Defs.BF_HQ:
		amounts = D.f_bounty_hq.slice(f * e.R, f * e.R + e.R)
	elif D.f_bounty_share_pm[f] > 0 and e.r_gold >= 0:
		var sum := 0
		for r in e.R:
			sum += D.b_cost[bt * e.R + r]
		amounts[e.r_gold] = sum * D.f_bounty_share_pm[f] / 1000
	_give(e, killer_p, amounts, e.buildings.handle(b), Vector2(e.buildings.x[b], e.buildings.z[b]))


func _give(e: EconomySim, p: int, amounts: PackedInt32Array, src_h: int, pos: Vector2) -> void:
	_ensure(p)
	for r in mini(amounts.size(), e.R):
		if amounts[r] > 0:
			e.add_res(p, r, amounts[r])
			total[p] += amounts[r]
			e.events.push(SimEvents.Ev.LOOT, p, r, amounts[r], src_h, pos)
