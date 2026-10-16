class_name EconQuery
extends RefCounted
## Данные панели здания и меню стройки (ARCHITECTURE §7.3, §14; формат — GameQuery). Подписи — tr("…").
##
## building_panel(b_h) → {handle, btype, name, hp, hp_max, state, progress,
##     queue: [{utype, name, t}], trains: [{utype, name, cost, enabled, why}], recipe, herd: {heads, cap, grass,
##     growth (голов за период), period_s, next (0..1)}, water (0..1, −1 — не поле), gar: {n, cap},
##   и сверх договора: workers: {n, max}, water_places: {used, cap} (тўғон — «Сув 6/8»), dry_in_s (засуха),
##     fuel (печь: есть дрова), otlar: {n, cap}, tax_min (золота в минуту), trade: {res: {sell, buy}},
##     ability: {id, active_s, ready_s}, raid: 0..1 (круг набега), slaughter_s, auto_move, mode}
## build_menu(p, tab) → [{btype, name, cost (милли), hotkey, enabled, why, count, max}]
## why — по-русски («Не хватает: дерево 40», «Сначала: Хумдон», «Не больше 10»), "" — можно.

const HOTKEYS := ["Q", "W", "E", "R", "T", "A", "S", "D", "F", "G", "Z", "X", "C", "V"]


func building_panel(e: EconomySim, b_h: int) -> Dictionary:
	var B := e.buildings
	if not B.valid(b_h):
		return {}
	var D := e.defs
	var b := B.slot(b_h)
	var bt := B.btype[b]
	var p := B.owner[b]
	var queue: Array = []
	for i in B.q_n[b]:
		var u := B.q[b * BuildingTable.QMAX + i]
		queue.append({"utype": u, "name": tr(D.u_name[u]),
			"t": float(B.q_t[b]) / maxi(D.u_train_ticks[u], 1) if i == 0 else 0.0})
	var trains: Array = []
	for u in D.b_trains[bt]:
		if D.u_enabled[u] == 0:
			continue
		var cost := e.prod.cost_of(e, p, u)
		trains.append({"utype": u, "name": tr(D.u_name[u]), "cost": cost, "enabled": false, "why": ""})
		var why := train_why(e, p, b, u, cost)
		trains[trains.size() - 1]["why"] = why
		trains[trains.size() - 1]["enabled"] = why == ""
	var herd := {}
	var h := e.hd.herd_at(e, b, -1)
	if h >= 0:
		var H := e.herds
		var period := maxi(D.h_growth_ticks[H.htype[h]], 30)
		herd = {"handle": H.handle(h), "heads": H.heads(h), "cap": D.b_herd_cap[bt],
			"grass": float(e.fld.avg_under(e, Vector2(H.x[h], H.z[h]), H.graze_r[h])) / 1000.0,
			"growth": _growth_per_period(e, h, b), "period_s": period / 30,
			"next": float(e.tick % period) / float(period), "breed": D.b_herd_breed[bt] == 1}
	var water := -1.0
	if D.b_water_place[bt] > 0:
		water = float(e.b_water[b]) / 1000.0
	var out := {"handle": b_h, "btype": bt, "name": tr(D.b_name[bt]),
		"hp": B.hp_c[b] / 100, "hp_max": B.hp_max_c[b] / 100,
		"state": B.state[b], "progress": B.progress[b] / 1000.0,
		"queue": queue, "trains": trains,
		"recipe": tr(D.rc_name[B.recipe[b]]) if B.recipe[b] >= 0 else "",
		"herd": herd, "water": water,
		"gar": {"n": B.gar_n[b], "cap": maxi(D.b_gar_cap[bt], D.b_shelter[bt])},
		"workers": {"n": B.workers_n[b], "max": _work_cap(e, b)},
		"mode": e.b_mode[b], "raid": e.raid.raid_progress(e, b)}
	var nw: Dictionary = D.b_network[bt]
	if bool(nw.get("source", false)):
		var used := e.net.used[b] if b < e.net.used.size() else 0
		out["water_places"] = {"used": used, "cap": int(nw.get("places", 8))}
		if B.state[b] == BuildingTable.State.RUIN and b < e.net.dry_at.size() and e.net.dry_at[b] > e.tick:
			out["dry_in_s"] = (e.net.dry_at[b] - e.tick) / 30
	if B.recipe[b] >= 0:
		out["fuel"] = e.b_flag[b] & EconomySim.BFL_NO_FUEL == 0
	if not D.b_otlar[bt].is_empty():
		out["otlar"] = {"n": e.b_otlar[b], "cap": int(D.b_otlar[bt].get("cap", 20))}
	if D.b_tax_milli_min[bt] > 0:
		out["tax_min"] = D.b_tax_milli_min[bt] / 1000
	if B.flags[b] & Defs.BF_MARKET:
		out["trade"] = e.ex.rates(e)
	var ab: Dictionary = D.b_ability[bt]
	if not ab.is_empty() and p >= 0:
		out["ability"] = {"id": ab.get("id", ""), "active_s": maxi(0, e.mods.hashar_until[p] - e.tick) / 30,
			"ready_s": maxi(0, e.mods.hashar_ready[p] - e.tick) / 30}
	if h >= 0 and D.b_herd_breed[bt] == 1 and D.h_backing[e.herds.htype[h]] < 0:
		out["slaughter_s"] = maxi(0, e.b_cd[b] - e.tick) / 30
		out["auto_move"] = e.b_auto[b] == 1
	return out


func _work_cap(e: EconomySim, b: int) -> int:
	var D := e.defs
	var bt := e.buildings.btype[b]
	if D.b_work_slots[bt] > 0:
		return D.b_work_slots[bt]
	var rc := e.buildings.recipe[b]
	return D.rc_workers[rc] if rc >= 0 else 0


func _growth_per_period(e: EconomySim, h: int, b: int) -> int:
	var D := e.defs
	var H := e.herds
	if D.b_herd_breed[e.buildings.btype[b]] == 0:
		return 0
	var heads := H.heads(h)
	var steps := D.h_growth_steps[H.htype[h]]
	var per_min := 0
	var i := 0
	while i + 1 < steps.size():
		if heads >= steps[i]:
			per_min = steps[i + 1]
		i += 2
	return per_min * maxi(D.h_growth_ticks[H.htype[h]], 30) / 1800 / 1000


func train_why(e: EconomySim, p: int, b: int, u: int, cost: PackedInt32Array) -> String:
	var D := e.defs
	var B := e.buildings
	if B.state[b] == BuildingTable.State.SITE:
		return tr("Здание ещё строится")
	if not e.active(b):
		return tr("Здание не работает")
	for req in D.u_requires[u]:
		if not e.has_required(p, PackedInt32Array([req])):
			return tr("Сначала: %s") % tr(D.b_name[req])
	var code := e.prod.why_not(e, p, b, u)
	if code == EconApi.Err.QUEUE_FULL:
		return tr("Очередь полна")
	if code == EconApi.Err.NOT_ALLOWED:
		if D.u_unique[u] == 1:
			var left := e.p_unique[p * D.unit_ids.size() + u] - e.tick
			return tr("Снова через %d с") % (left / 30) if left > 0 else tr("Уже есть")
		if e.players.famine[p] == 1:
			return tr("Голод: за еду не нанять")
		return tr("Нельзя")
	if e.r_horse >= 0 and cost[e.r_horse] > e.players.res[p * e.R + e.r_horse]:
		return tr("Нет коней в табуне")
	var w := why_cost(e, p, cost)
	if w != "":
		return w
	var P := e.players
	if P.pop_used[p] + P.pop_reserved[p] + D.u_pop[u] > P.pop_cap[p]:
		return tr("Нет мест: нужен дом")
	return ""


func build_menu(e: EconomySim, p: int, tab: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if p < 0 or p >= e.players.count:
		return out
	var D := e.defs
	var tabs: Dictionary = D.f_tabs[e.players.faction[p]]
	var list: PackedInt32Array = tabs.get(String(tab), PackedInt32Array())
	var k := 0
	for b in list:
		if b < 0 or D.b_enabled[b] == 0:
			continue
		var cost := D.building_cost(b)
		var why := ""
		for req in D.b_requires[b]:
			if not e.has_required(p, PackedInt32Array([req])):
				why = tr("Сначала: %s") % tr(D.b_name[req])
				break
		var mx := D.b_max_per_player[b]
		var n := e.count_of(p, b, true)
		if why == "" and mx > 0 and n >= mx:
			why = tr("Не больше %d") % mx
		if why == "":
			why = why_cost(e, p, cost)
		out.append({"btype": b, "name": tr(D.b_name[b]), "cost": cost,
			"hotkey": HOTKEYS[k] if k < HOTKEYS.size() else "", "enabled": why == "", "why": why,
			"count": n, "max": mx})
		k += 1
	return out


func why_cost(e: EconomySim, p: int, cost: PackedInt32Array) -> String:
	var miss := PackedStringArray()
	for r in mini(cost.size(), e.R):
		var lack := cost[r] - e.players.res[p * e.R + r]
		if cost[r] > 0 and lack > 0:
			miss.append("%s %d" % [tr(e.defs.r_name[r]).to_lower(), ceili(lack / 1000.0)])
	return "" if miss.is_empty() else tr("Не хватает: %s") % " · ".join(miss)
