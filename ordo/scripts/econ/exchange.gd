class_name EconExchange
extends RefCounted
## Обмен на Бозоре (ECONOMY §2.5): постоянный курс, сделка лотом по 100 (GameRules.trade).
##   продать 100 еды/дерева/камня/ғишт → 40/40/50/60 золота; купить 100 ← 110/110/140 золота; ғишт не купить.
## trade(give, take, amount_milli): amount_milli — сколько НЕ-золотого ресурса (кратно лоту, округляется вниз).


func trade(e: EconomySim, p: int, b: int, give: int, take: int, amount_milli: int) -> int:
	if not e.active(b) or e.buildings.flags[b] & Defs.BF_MARKET == 0:
		return -EconApi.Err.NOT_ALLOWED
	if give < 0 or take < 0 or give >= e.R or take >= e.R or give == take:
		return -EconApi.Err.INVALID
	var tr: Dictionary = e.rules.get("trade", {})
	var lot := int(tr.get("lot", 100)) * 1000
	var lots := amount_milli / lot
	if lots <= 0:
		return -EconApi.Err.INVALID
	var g := e.r_gold
	if take == g:
		# продать ресурс give
		var price := int(tr.get("sell", {}).get(e.defs.res_ids[give], -1))
		if price < 0:
			return -EconApi.Err.NOT_ALLOWED
		var need := lots * lot
		if e.players.res[p * e.R + give] < need:
			e.events.push(SimEvents.Ev.NOT_ENOUGH, p, give, need - e.players.res[p * e.R + give], SimCmd.Op.TRADE)
			return -EconApi.Err.NO_RES
		e.players.res[p * e.R + give] -= need
		e.add_res(p, g, lots * price * 1000, false)
		return EconApi.Err.OK
	if give == g:
		# купить ресурс take
		var price := int(tr.get("buy", {}).get(e.defs.res_ids[take], -1))
		if price < 0:
			return -EconApi.Err.NOT_ALLOWED
		var cost := lots * price * 1000
		if e.players.res[p * e.R + g] < cost:
			e.events.push(SimEvents.Ev.NOT_ENOUGH, p, g, cost - e.players.res[p * e.R + g], SimCmd.Op.TRADE)
			return -EconApi.Err.NO_RES
		e.players.res[p * e.R + g] -= cost
		e.add_res(p, take, lots * lot, false)
		return EconApi.Err.OK
	return -EconApi.Err.NOT_ALLOWED


## Курс для панели: {res: {sell, buy}} золота за лот (−1 — нельзя)
func rates(e: EconomySim) -> Dictionary:
	var tr: Dictionary = e.rules.get("trade", {})
	var out := {}
	for r in e.R:
		if r == e.r_gold or e.defs.r_enabled[r] == 0:
			continue
		var id := e.defs.res_ids[r]
		var s := int(tr.get("sell", {}).get(id, -1))
		var b := int(tr.get("buy", {}).get(id, -1))
		if s >= 0 or b >= 0:
			out[r] = {"sell": s, "buy": b}
	return out
