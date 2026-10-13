class_name EconModifiers
extends RefCounted
## Множители игроков (ARCHITECTURE §11 «Calendar + modifiers»; ECONOMY §1.5, §2.6):
## действующие ModifierDefs (голод, сезон) и кнопка Ҳашар собираются в PlayerTable.stat;
## боевая часть (ATK, SPEED, STAM_REGEN, MORALE_REGEN, RANGE = BattleSim.MOD_*) уходит в ядро
## через CombatPort.set_owner_mods, экономическая (GATHER, BUILD, UPKEEP) читается здесь же.
## Ҳашар: стройка и ремонт ×2, ремонт вдвое дешевле на 45 с, перезарядка 240 с.

var dirty := PackedInt32Array()          # 1 — пересобрать
var hashar_until := PackedInt32Array()   # такт конца Ҳашара
var hashar_ready := PackedInt32Array()   # такт, с которого снова можно


func add_player(e: EconomySim, p: int) -> void:
	dirty.append(1)
	hashar_until.append(0)
	hashar_ready.append(0)


func mark(e: EconomySim, p: int) -> void:
	dirty[p] = 1
	compile(e, p)


func slow_step(e: EconomySim) -> void:
	for p in e.players.count:
		if hashar_until[p] > 0 and e.tick >= hashar_until[p]:
			hashar_until[p] = 0
			dirty[p] = 1
		if dirty[p] == 1:
			compile(e, p)


## Собрать PlayerTable.stat игрока p и отдать боевую часть ядру
func compile(e: EconomySim, p: int) -> void:
	dirty[p] = 0
	var D := e.defs
	var P := e.players
	var K := PlayerTable.Stat.COUNT
	var st := PackedFloat32Array()
	st.resize(K)
	st.fill(1.0)
	for m in D.m_ids.size():
		if D.m_enabled[m] == 0 or D.m_stat[m] < 0:
			continue
		var when := D.m_when[m]
		var on := when == "always" or (when == "famine" and P.famine[p] == 1)
		if when.begins_with("season:") and P.season[p] >= 0:
			on = D.s_ids[P.season[p]] == when.trim_prefix("season:")
		if on:
			st[D.m_stat[m]] = st[D.m_stat[m]] * D.m_mul[m] + D.m_add[m]
	if hashar_until[p] > e.tick:
		var ab := _hashar_def(e, p)
		st[PlayerTable.Stat.BUILD] *= float(ab.get("build_mult", 2.0))
	for k in K:
		P.stat[p * K + k] = st[k]
	if e.port:
		var mods := PackedFloat32Array()
		mods.resize(BattleSim.MOD_N)
		for k in BattleSim.MOD_N:
			mods[k] = st[k]
		e.port.set_owner_mods(p, mods)


func gather_milli(e: EconomySim, p: int) -> int:
	return roundi(e.players.stat[p * PlayerTable.Stat.COUNT + PlayerTable.Stat.GATHER] * 1000.0)


func build_milli(e: EconomySim, p: int) -> int:
	if p < 0:
		return 1000
	return roundi(e.players.stat[p * PlayerTable.Stat.COUNT + PlayerTable.Stat.BUILD] * 1000.0)


func upkeep_milli(e: EconomySim, p: int) -> int:
	return roundi(e.players.stat[p * PlayerTable.Stat.COUNT + PlayerTable.Stat.UPKEEP] * 1000.0)


## Ремонт: доля цены (Ҳашар — repair_cost_mult)
func repair_cost_milli(e: EconomySim, p: int) -> int:
	if hashar_until[p] > e.tick:
		return roundi(float(_hashar_def(e, p).get("repair_cost_mult", 0.5)) * 1000.0)
	return 1000


func hashar_active(e: EconomySim, p: int) -> bool:
	return hashar_until[p] > e.tick


## Кнопка постройки (Ҳашар у Урды)
func use_ability(e: EconomySim, p: int, b_h: int) -> int:
	var b := e._own(p, b_h)
	if b < 0:
		return b
	var ab: Dictionary = e.defs.b_ability[e.buildings.btype[b]]
	if ab.is_empty() or not e.active(b):
		return -EconApi.Err.NOT_ALLOWED
	if e.tick < hashar_ready[p]:
		return -EconApi.Err.BUSY
	hashar_until[p] = e.tick + int(ab.get("duration_ticks", 1350))
	hashar_ready[p] = e.tick + int(ab.get("cooldown_ticks", 7200))
	mark(e, p)
	# TODO(ECON/CORE): деҳқоны в Ҳашар — атака +6, броня +2 (нужен множитель по виду юнита в ядре)
	return EconApi.Err.OK


func _hashar_def(e: EconomySim, p: int) -> Dictionary:
	var hq := e.defs.f_hq[e.players.faction[p]]
	return e.defs.b_ability[hq] if hq >= 0 else {}
