class_name EconomySim
extends EconApi
## Экономика «Города» (ARCHITECTURE §7.3, §11; docs/ECONOMY.md Сб. 1). ECON.
##
## Держит четыре общие таблицы (PlayerTable, BuildingTable, NodeTable, HerdTable) и частное
## состояние; тела двигает только через CombatPort, карту меняет только через NavApi.
## Подсистемы — отдельные классы без ссылки назад (сим передаётся параметром, циклов нет):
##   EconWorkers    workers.gd     работники: добыча, ходки к складу, стройка, поле, печь, пастухи
##   EconProduction production.gd  найм по одному: очередь, население, дверь, точка сбора; мастерские
##   EconPopulation population.gd  предел населения, содержание, голод и дезертирство, подать
##   EconHerds      herds.gd       отары и табуны: приплод, корм, кони как ресурс, перегон, возврат
##   EconFields     fields.gd      трава 16 м: выпас, отрастание, «Жайыт тозду», авто-перегон короо
##   EconNetwork    network.gd     вода: тўғон → ариқ → зона 24 м, места воды, засуха через 20 с
##   EconModifiers  modifiers.gd   множители игрока (голод, Ҳашар, сезоны) → PlayerTable.stat и ядро
##   EconCalendar   calendar.gd    сезоны (Сб. 2, по умолчанию выключены)
##   EconBounty     bounty.gd      олжо кочевников
##   EconNomad      nomad.gd       көч: свернуть, арбы, развернуть по кольцу
##   EconExchange   exchange.gd    обмен на Бозоре
##   EconRaids      raids.gd       действия с кругом прогресса: барымта, талоо, вытоптать поле
##   EconQuery      econ_query.gd  building_panel, build_menu, причины по-русски
##
## Детерминизм (ARCHITECTURE §5.2): только целые в правилах (милли, санти-HP, такты), квадраты
## расстояний, обход массивов по индексу, без randf/Time/Node. Тригонометрии нет.

const GRASS_CELL := 16.0                 # клетка травы, м (ARCHITECTURE §6.3)
const WATER_CELL := 8.0                  # клетка полива, м
const RUIN_TICKS := 1800                 # руины (кроме тўғона) убираются через 60 с
const DOOR_GAP := 1.5                    # дверь — в 1,5 м перед фасадом
## n^0,75 × 1000 (скорость стройки n работников, ECONOMY §1.6) — таблицей, без pow
const N075 := [0, 1000, 1682, 2280, 2828, 3344, 3834, 4304, 4757, 5196, 5623, 6040, 6447, 6846, 7238, 7622,
	8000, 8372, 8739, 9100, 9457, 9810, 10158, 10503, 10843, 11180, 11514, 11845, 12172, 12497, 12819, 13138,
	13454, 13768, 14080, 14390, 14697, 15002, 15305, 15606, 15905]
## Фасад +Z, повёрнутый на rot_q четвертей (рысканье rot_q · 90°): +Z, +X, −Z, −X
const DIR4 := [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0)]

## Режимы зданий (частное поле b_mode)
enum Mode { NONE, PACKING, UNPACK, ERECT, REBUILD, MOVING }

## Флажки b_flag
const BFL_PASTURE_WARNED := 1
const BFL_NO_FUEL := 2
const BFL_POP_CAPPED := 4
const BFL_NO_SPOT := 8

var defs: Defs
var rules := {}
var port: CombatPort
var nav: NavApi
var events: SimEvents
var rng: BattleRng
var seed_value := 1
var tick := 0
var R := 0
var origin := Vector2(-512.0, -512.0)
var extent := Vector2(1024.0, 1024.0)
var pop_max := 500

# индексы ресурсов (−1 — нет такого)
var r_food := -1
var r_wood := -1
var r_stone := -1
var r_gold := -1
var r_brick := -1
var r_horse := -1

# подсистемы
var wk := EconWorkers.new()
var prod := EconProduction.new()
var popn := EconPopulation.new()
var hd := EconHerds.new()
var fld := EconFields.new()
var net := EconNetwork.new()
var mods := EconModifiers.new()
var cal := EconCalendar.new()
var bty := EconBounty.new()
var nomad := EconNomad.new()
var ex := EconExchange.new()
var raid := EconRaids.new()
var qry := EconQuery.new()

# ---------------------------------------------------------------- частное по зданиям (слот = слот таблицы)
var b_work := PackedInt32Array()     # стройка: милли «работник·такт» сделано; мастерская: накопитель партии
var b_total := PackedInt32Array()    # стройка: милли «работник·такт» всего
var b_order := PackedInt32Array()    # порядок завершения (места воды раздаются по нему)
var b_water := PackedInt32Array()    # полив потребителя 0..1000 (поле, печь)
var b_net := PackedInt32Array()      # тўғон (слот), из которого пьёт потребитель, −1
var b_timer := PackedInt32Array()    # такт: руина уходит / лагерь свёрнут / короо встал на место
var b_mode := PackedInt32Array()     # Mode
var b_cd := PackedInt32Array()       # такт конца перезарядки (талоо, Мал союу, Ҳашар)
var b_cd2 := PackedInt32Array()      # такт конца действия (Ҳашар) / поле под паром (вытоптано)
var b_act := PackedInt32Array()      # прогресс действия набега, такты
var b_act_n := PackedInt32Array()    # всадников в начале действия
var b_slots := PackedInt32Array()    # занятые места работы (маска)
var b_otlar := PackedInt32Array()    # Отхона: угнанные кони
var b_auto := PackedInt32Array()     # короо: авто-перегон
var b_flag := PackedInt32Array()     # BFL_*
var b_dest := PackedVector2Array()   # көч / перегон: куда встать
var bq_disc := PackedInt32Array()    # [b * QMAX + i] скидка «отлар» на запись очереди (1 — была)
var _order_seq := 0

# ---------------------------------------------------------------- юниты экономики (по слоту ядра)
var un_gen := PackedInt32Array()     # поколение описателя, 0 — слот не наш
var un_owner := PackedInt32Array()
var un_type := PackedInt32Array()    # индекс Defs.unit_ids
var un_w := PackedInt32Array()       # индекс работника, −1
var un_cargo := PackedInt32Array()   # арба: слот здания + 1, 0

# ---------------------------------------------------------------- по игрокам
var p_upkeep := PackedInt32Array()   # содержание, милли еды в минуту (живые зарегистрированные)
var p_soldiers := PackedInt32Array()
var p_unique := PackedInt32Array()   # [p * U + u] такт, с которого снова можно (полководец), 0
var p_flow := PackedInt64Array()     # [p * R + r] приход/расход за текущую секунду, милли (доход для балки)
var p_hist := PackedInt64Array()     # [(p * R + r) * 60 + s] скользящее окно 60 с
var p_alarm := PackedInt32Array()    # 1 — тревога (Ноғора / Чакырык)

# ---------------------------------------------------------------- грязные флажки (пересчёт раз в такт)
var _pop_dirty := true
var _drops_dirty := true
var _net_dirty := true
var _drops: Array[PackedInt32Array] = []   # по игроку: слоты складов (ACTIVE, drop)
var _sites := PackedInt32Array()           # слоты строек (SITE)
var _queues := PackedInt32Array()          # слоты с очередью найма
var _deaths_seen := {}                     # описатель → true (этот такт; чтобы отличать «убит» от «убран»)


func setup(p_defs: Defs, p_rules: Dictionary, p_port: CombatPort, p_nav: NavApi, p_events: SimEvents, seed: int) -> void:
	defs = p_defs
	rules = p_rules
	port = p_port
	nav = p_nav
	events = p_events if p_events else SimEvents.new()
	seed_value = seed
	rng = BattleRng.new(seed * 0x9E37 + 1)
	players = PlayerTable.new()
	buildings = BuildingTable.new()
	nodes = NodeTable.new()
	herds = HerdTable.new()
	R = defs.R
	r_food = defs.res(&"food")
	r_wood = defs.res(&"wood")
	r_stone = defs.res(&"stone")
	r_gold = defs.res(&"gold")
	r_brick = defs.res(&"brick")
	r_horse = defs.res(&"horse")
	pop_max = int(rules.get("pop_max", 500))
	if nav:
		origin = nav.origin
		extent = Vector2(nav.w, nav.h) * NavApi.CELL
	if extent.x <= 0.0:
		extent = Vector2(1024.0, 1024.0)
	wk.setup(self)
	prod.setup(self)
	fld.setup(self)
	net.setup(self)
	hd.setup(self)
	raid.setup(self)


# ================================================================= расстановка карты (MapSetup)

func add_player(team: int, faction: StringName, ctrl: int) -> int:
	var f := defs.faction(faction)
	var p := players.add(team, f, ctrl, R)
	for r in R:
		players.res[p * R + r] = defs.f_start_res[f * R + r] if f >= 0 else 0
	p_upkeep.append(0)
	p_soldiers.append(0)
	p_alarm.append(0)
	for u in defs.unit_ids.size():
		p_unique.append(0)
	for r in R:
		p_flow.append(0)
		for s in 60:
			p_hist.append(0)
	_drops.append(PackedInt32Array())
	popn.add_player(self)
	mods.add_player(self, p)
	_pop_dirty = true
	return p


func spawn_building(p: int, btype: int, center: Vector2, rot_q: int, active := true) -> int:
	var b := _new_building(p, btype, center, rot_q, BuildingTable.State.ACTIVE if active else BuildingTable.State.SITE)
	var kind := defs.b_kind[btype]
	if kind == Defs.BKind.LINK or kind == Defs.BKind.WALL:
		# одиночное звено: концы — вдоль своей оси X, повёрнутой на rot_q
		var d: Vector2 = DIR4[(rot_q + 1) & 3]
		var half := defs.b_link_len[btype] * 0.5
		buildings.ax[b] = center.x - d.x * half
		buildings.az[b] = center.y - d.y * half
		buildings.bx[b] = center.x + d.x * half
		buildings.bz[b] = center.y + d.y * half
	_place_world(b)
	if active:
		_activate(b, false)
	else:
		_start_site(b, defs.b_build_ticks[btype])
	return buildings.handle(b)


func spawn_node(ntype: int, pos: Vector2, amount := -1, scatter_ref := -1) -> int:
	var N := nodes
	var n := N.alloc(ntype)
	N.res[n] = defs.n_res[ntype]
	N.amount_milli[n] = defs.n_amount_milli[ntype] if amount < 0 else amount
	N.workers_max[n] = defs.n_workers_max[ntype]
	N.scatter_ref[n] = scatter_ref
	N.cell[n] = nav.cell_of(pos) if nav else -1
	N.x[n] = pos.x
	N.z[n] = pos.y
	wk.node_added(self, n)
	return N.handle(n)


## Стадо у загона. У загона уже есть стадо этого вида (его ставит spawn_building) — задаёт число голов.
func spawn_herd(p: int, htype: int, pen_h: int, heads: int) -> int:
	return hd.spawn(self, p, htype, pen_h, heads)


func spawn_worker(p: int, pos: Vector2) -> int:
	if port == null or p < 0 or p >= players.count:
		return 0
	var u := defs.f_worker[players.faction[p]]
	var h := port.spawn(p, players.team[p], StringName(defs.unit_ids[u]), pos, 0.0)
	if h != 0:
		register_unit(h, p, u)
		events.push(SimEvents.Ev.UNIT_SPAWNED, p, h, 0, u, pos)
	return h


## Внести юнит в учёт экономики (население, содержание, работа). Найм и spawn_worker делают это сами;
## GAME зовёт для волн Op.SPAWN, если хочет, чтобы их кормили и считали (иначе они вне экономики).
func register_unit(u_h: int, p: int, utype: int) -> void:
	var s := Ids.slot(u_h)
	_grow_units(s)
	un_gen[s] = Ids.gen(u_h)
	un_owner[s] = p
	un_type[s] = utype
	un_w[s] = -1
	un_cargo[s] = 0
	players.pop_used[p] += defs.u_pop[utype]
	p_upkeep[p] += defs.u_upkeep_milli_min[utype]
	var fl := defs.u_flags[utype]
	if fl & UnitStats.WORKER and fl & UnitStats.WAGON == 0:
		un_w[s] = wk.add(self, u_h, p, utype)
	elif fl & UnitStats.WAGON == 0:
		p_soldiers[p] += 1


## Убрать юнит из учёта (смерть, ушёл в арбу, дезертировал). Тело — не трогает.
func unregister_unit(u_h: int) -> void:
	var s := Ids.slot(u_h)
	if not is_ours(u_h):
		return
	var p := un_owner[s]
	var u := un_type[s]
	players.pop_used[p] = maxi(0, players.pop_used[p] - defs.u_pop[u])
	p_upkeep[p] = maxi(0, p_upkeep[p] - defs.u_upkeep_milli_min[u])
	if un_w[s] >= 0:
		wk.remove(self, un_w[s])
	elif defs.u_flags[u] & UnitStats.WAGON == 0:
		p_soldiers[p] = maxi(0, p_soldiers[p] - 1)
	un_gen[s] = 0
	un_w[s] = -1
	un_cargo[s] = 0


func is_ours(u_h: int) -> bool:
	var s := Ids.slot(u_h)
	return Ids.kind(u_h) == Ids.Kind.UNIT and s < un_gen.size() and un_gen[s] == Ids.gen(u_h) and un_gen[s] != 0


# ================================================================= приказы

func place_site(p: int, btype: int, center: Vector2, rot_q: int, workers: PackedInt32Array) -> int:
	if p < 0 or p >= players.count or btype < 0 or btype >= defs.b_ids.size():
		return -Err.INVALID
	# тўғон на своих руинах — восстановление за полцены (ECONOMY §2.3)
	var ruin := _own_ruin_near(p, btype, center, 6.0)
	if ruin >= 0:
		return assign_build(p, workers, buildings.handle(ruin))
	var why := place_why(p, btype, center, rot_q)
	if why != 0:
		return -why
	var cost := defs.building_cost(btype)
	if not can_pay(p, cost):
		_not_enough(p, cost, SimCmd.Op.BUILD)
		return -Err.NO_RES
	pay(p, cost)
	var b := _new_building(p, btype, center, rot_q, BuildingTable.State.SITE)
	_place_world(b)
	_start_site(b, defs.b_build_ticks[btype])
	var h := buildings.handle(b)
	events.push(SimEvents.Ev.SITE_PLACED, p, h, btype, 0, center)
	wk.send_builders(self, p, workers, h)
	return h


## Причина отказа постройки до цены: 0 — можно; иначе Err (Err.NOT_ALLOWED …) или 100 + NavApi.Why.
## Правила экономики (сторона, предел, «нужно сначала», зона воды, трава короо, своя земля, у жилы)
## + NavApi.check_place (след, уклон, вода, край карты). Призрак интерфейса может звать то же.
func place_why(p: int, btype: int, center: Vector2, rot_q: int) -> int:
	if defs.b_enabled[btype] == 0 or defs.b_tab[btype] == "":
		return Err.NOT_ALLOWED
	if defs.b_faction[btype] != "" and defs.f_ids[players.faction[p]] != defs.b_faction[btype]:
		return Err.NOT_ALLOWED
	if not has_required(p, defs.b_requires[btype]):
		return Err.NOT_ALLOWED
	var mx := defs.b_max_per_player[btype]
	if mx > 0 and count_of(p, btype, true) >= mx:
		return Err.NOT_ALLOWED
	var why := econ_place_why(p, btype, center, rot_q)
	if why != NavApi.Why.OK:
		return 100 + why
	if nav:
		why = nav.check_place(p, btype, center, rot_q)
		if why != NavApi.Why.OK:
			return 100 + why
	return 0


## Правила расстановки, которые знает только экономика (NavApi.Why): своя земля, у жилы, зона воды,
## трава под короо и одна короо на клетку пастбища. NAV зовёт in_territory/node_near сам.
func econ_place_why(p: int, btype: int, center: Vector2, rot_q: int) -> int:
	var place: Dictionary = defs.b_place[btype]
	if bool(place.get("territory", true)) and not in_territory(p, center):
		return NavApi.Why.NO_TERRITORY
	var near: Dictionary = place.get("near", {})
	if not near.is_empty():
		var mask := 0
		for nt in (near["nodes"] as PackedInt32Array):
			if nt >= 0:
				mask |= 1 << defs.n_res[nt]
		if node_near(mask, center, float(near.get("r", 26.0))) == 0:
			return NavApi.Why.NOT_NEAR
	if bool(place.get("water_zone", false)) and not net.in_any_zone(self, p, center):
		return NavApi.Why.NOT_NEAR
	if defs.b_herd[btype] >= 0 and defs.b_herd_breed[btype] == 1 and defs.b_flags[btype] & Defs.BF_PEN:
		if not fld.pen_spot_ok(self, btype, center, -1):
			return NavApi.Why.NOT_ALLOWED
	return NavApi.Why.OK


func place_wall(p: int, wtype: int, pts: PackedVector2Array, workers: PackedInt32Array) -> int:
	if p < 0 or p >= players.count or wtype < 0 or nav == null or pts.size() < 2:
		return -Err.INVALID
	if defs.b_enabled[wtype] == 0 or (defs.b_faction[wtype] != "" and defs.f_ids[players.faction[p]] != defs.b_faction[wtype]):
		return -Err.NOT_ALLOWED
	if not has_required(p, defs.b_requires[wtype]):
		return -Err.NOT_ALLOWED
	var plan := nav.plan_wall(p, wtype, pts)
	var centers: PackedVector2Array = plan.get("centers", PackedVector2Array())
	var why: PackedByteArray = plan.get("why", PackedByteArray())
	var ok := PackedInt32Array()
	for i in centers.size():
		if i >= why.size() or why[i] == NavApi.Why.OK:
			ok.append(i)
	if ok.is_empty():
		return -(100 + (why[0] if why.size() > 0 else NavApi.Why.NOT_ALLOWED))
	var cost := defs.building_cost(wtype)
	for r in R:
		cost[r] *= ok.size()
	if not can_pay(p, cost):
		_not_enough(p, cost, SimCmd.Op.BUILD_WALL)
		return -Err.NO_RES
	pay(p, cost)
	var made := _make_links(p, wtype, pts, plan, ok, false)
	wk.send_builders(self, p, workers, made[1])
	return made[0]


## Звенья стартовой линии карты (Бош ариқ у тўғона, MapSetup): сразу готовые, даром. Вернёт id цепочки.
func spawn_links(p: int, wtype: int, pts: PackedVector2Array) -> int:
	if p < 0 or p >= players.count or wtype < 0 or pts.size() < 2:
		return 0
	var plan := nav.plan_wall(p, wtype, pts) if nav else {}
	var centers: PackedVector2Array = plan.get("centers", PackedVector2Array())
	var ok := PackedInt32Array()
	for i in centers.size():
		ok.append(i)
	return _make_links(p, wtype, pts, plan, ok, true)[0]


## Звенья по плану стены/арыка: [chain, описатель первого]
func _make_links(p: int, wtype: int, pts: PackedVector2Array, plan: Dictionary, ok: PackedInt32Array, active: bool) -> Array:
	var centers: PackedVector2Array = plan.get("centers", PackedVector2Array())
	var rots: PackedFloat32Array = plan.get("rots", PackedFloat32Array())
	_order_seq += 1
	var chain := _order_seq
	var half := defs.b_link_len[wtype] * 0.5
	var first := 0
	for i in ok:
		var c := centers[i]
		var dir := _polyline_dir(pts, c)
		var b := _new_building(p, wtype, c, 0, BuildingTable.State.ACTIVE if active else BuildingTable.State.SITE)
		var B := buildings
		B.chain[b] = chain
		B.rot[b] = rots[i] if i < rots.size() else 0.0
		B.ax[b] = c.x - dir.x * half
		B.az[b] = c.y - dir.y * half
		B.bx[b] = c.x + dir.x * half
		B.bz[b] = c.y + dir.y * half
		_place_world(b)
		if active:
			_activate(b, false)
		else:
			_start_site(b, defs.b_build_ticks[wtype])
			events.push(SimEvents.Ev.SITE_PLACED, p, B.handle(b), wtype, chain, c)
		if first == 0:
			first = B.handle(b)
	return [chain, first]


func assign_gather(p: int, workers: PackedInt32Array, source_h: int) -> int:
	return wk.assign_gather(self, p, workers, source_h)


## Помочь строить, восстановить тўғон на руинах (ECONOMY §2.3), починить (ECONOMY §1.6)
func assign_build(p: int, workers: PackedInt32Array, b_h: int) -> int:
	if not buildings.valid(b_h):
		return -Err.STALE
	var b := buildings.slot(b_h)
	if buildings.owner[b] != p:
		return -Err.NOT_OWNER
	var B := buildings
	match B.state[b]:
		BuildingTable.State.RUIN:
			var bt := B.btype[b]
			if defs.b_rebuild_ticks[bt] <= 0:
				return -Err.NOT_ALLOWED
			var cost := defs.b_rebuild_cost.slice(bt * R, bt * R + R)
			if not can_pay(p, cost):
				_not_enough(p, cost, SimCmd.Op.ASSIST)
				return -Err.NO_RES
			pay(p, cost)
			B.state[b] = BuildingTable.State.SITE
			b_mode[b] = Mode.REBUILD
			_place_world(b)
			_start_site(b, defs.b_rebuild_ticks[bt])
			events.push(SimEvents.Ev.SITE_PLACED, p, b_h, bt, 0, Vector2(B.x[b], B.z[b]))
		BuildingTable.State.SITE:
			pass
		BuildingTable.State.ACTIVE:
			if B.hp_c[b] >= B.hp_max_c[b] or B.flags[b] & Defs.BF_UNBREAKABLE:
				return -Err.NOT_ALLOWED
		_:
			return -Err.NOT_ALLOWED
	return wk.send_builders(self, p, workers, b_h)


func train(p: int, b_h: int, utype: int, count: int) -> int:
	return prod.train(self, p, b_h, utype, count)


func cancel_train(p: int, b_h: int, index: int) -> int:
	return prod.cancel(self, p, b_h, index)


func set_rally(p: int, b_h: int, at: Vector2, target_h: int) -> int:
	var b := _own(p, b_h)
	if b < 0:
		return b
	buildings.rally_x[b] = at.x
	buildings.rally_z[b] = at.y
	buildings.rally_h[b] = target_h
	return Err.OK


func demolish(p: int, b_h: int) -> int:
	var b := _own(p, b_h)
	if b < 0:
		return b
	var B := buildings
	if B.flags[b] & Defs.BF_HQ:
		return -Err.NOT_ALLOWED
	if B.state[b] == BuildingTable.State.SITE and b_mode[b] == Mode.NONE:
		# стройка: возврат за несделанную часть
		var cost := defs.building_cost(B.btype[b])
		var left := 1000 - B.progress[b]
		for r in R:
			cost[r] = cost[r] * left / 1000
		gain(p, cost, false)
	destroy_building(b, -1, true)
	return Err.OK


func set_recipe(p: int, b_h: int, recipe: int) -> int:
	var b := _own(p, b_h)
	if b < 0:
		return b
	if recipe >= 0 and (not defs.b_recipes[buildings.btype[b]].has(recipe) or defs.rc_enabled[recipe] == 0):
		return -Err.NOT_ALLOWED
	buildings.recipe[b] = recipe
	buildings.recipe_t[b] = 0
	return Err.OK


func trade(p: int, b_h: int, give: int, take: int, amount_milli: int) -> int:
	var b := _own(p, b_h)
	if b < 0:
		return b
	return ex.trade(self, p, b, give, take, amount_milli)


## Тўғон нельзя закрыть в Сб. 1 (шлюзы — позже): приказ принимается только как «открыт»
func set_dam(p: int, b_h: int, open: bool) -> int:
	var b := _own(p, b_h)
	if b < 0:
		return b
	if defs.b_kind[buildings.btype[b]] != Defs.BKind.DAM:
		return -Err.INVALID
	return Err.OK if open else -Err.NOT_ALLOWED


func pack(p: int, b_h: int) -> int:
	return nomad.pack(self, p, b_h)


func pack_all(p: int, hq_h: int) -> int:
	return nomad.pack_all(self, p, hq_h)


func unpack(p: int, arbas: PackedInt32Array, center: Vector2) -> int:
	return nomad.unpack(self, p, arbas, center)


func herd_move(p: int, herd_h: int, to: Vector2) -> int:
	return hd.herd_move(self, p, herd_h, to)


func release_units(units: PackedInt32Array) -> void:
	for h in units:
		if is_ours(h) and un_w[Ids.slot(h)] >= 0:
			wk.release(self, un_w[Ids.slot(h)])


# ---------------------------------------------------------------- приказы без своего Op (крючки для GAME/UI)

## Ҳашар (ECONOMY §2.6): кнопка ставки. Просьба к ведущему — маршрут Op.WAR_CRY с описателем здания сюда.
func use_ability(p: int, b_h: int) -> int:
	return mods.use_ability(self, p, b_h)


## «Мал союу» (ECONOMY §3.4): −10 овец, +120 еды; раз в 60 с на загон
func slaughter(p: int, pen_h: int) -> int:
	return hd.slaughter(self, p, pen_h)


## Авто-перегон короо (ECONOMY §3.4), по умолчанию включён
func set_auto_move(p: int, pen_h: int, on: bool) -> int:
	var b := _own(p, pen_h)
	if b < 0:
		return b
	b_auto[b] = 1 if on else 0
	return Err.OK


## Тревога N (ECONOMY §1.7): работники в 80 м от укрытий идут внутрь; повторно — назад к работе
func alarm(p: int, on: bool) -> int:
	return wk.alarm(self, p, on)


# ================================================================= такт (только GameSim, §5.1)

func pre_step(p_tick: int) -> void:
	tick = p_tick
	if _drops_dirty:
		_rebuild_drops()
	if _pop_dirty:
		popn.recompute_caps(self)
	wk.step(self)
	_sites_step()
	prod.step(self)
	if _net_dirty or net.due(self):
		net.recompute(self)
	# секундные системы — в своих фазах такта, чтобы не копились в один (ARCHITECTURE §16, p99)
	match p_tick % 30:
		10:
			hd.slow_step(self)
		20:
			raid.slow_step(self)
			nomad.slow_step(self)


func post_step(p_tick: int, deaths: PackedInt32Array, hits: PackedInt32Array, arrivals: PackedInt32Array) -> void:
	tick = p_tick
	_deaths_seen.clear()
	var i := 0
	while i + 1 < deaths.size():
		_on_death(deaths[i], deaths[i + 1])
		i += 2
	i = 0
	while i + 2 < hits.size():
		_on_hit(hits[i], hits[i + 1], hits[i + 2])
		i += 3
	if _pop_dirty:
		popn.recompute_caps(self)
	if _net_dirty:
		net.recompute(self)


func slow_step(p_tick: int) -> void:
	tick = p_tick
	popn.slow_step(self)
	prod.recipes_step(self)
	mods.slow_step(self)
	cal.slow_step(self)
	_ruins_step()
	_income_step()


func fields_step(p_tick: int) -> void:
	tick = p_tick
	fld.step(self)


# ================================================================= запросы

func res(p: int, r: int) -> int:
	return players.res[p * R + r]


func can_pay(p: int, cost: PackedInt32Array) -> bool:
	for r in mini(cost.size(), R):
		if cost[r] > 0 and cost[r] > players.res[p * R + r]:
			return false
	return true


func node_near(res_mask: int, pos: Vector2, r: float) -> int:
	var n := wk.node_near(self, res_mask, pos, r, -1)
	return nodes.handle(n) if n >= 0 else 0


func in_territory(p: int, pos: Vector2) -> bool:
	var B := buildings
	for b in B.hw:
		var st := B.state[b]
		if B.owner[b] != p or (st != BuildingTable.State.ACTIVE and st != BuildingTable.State.SITE):
			continue
		if B.flags[b] & Defs.BF_TERRITORY == 0:
			continue
		var tr := defs.b_territory_r[B.btype[b]]
		if defs.b_kind[B.btype[b]] == Defs.BKind.LINK:
			if seg_dist2(pos, Vector2(B.ax[b], B.az[b]), Vector2(B.bx[b], B.bz[b])) <= tr * tr:
				return true
		elif Vector2(B.x[b], B.z[b]).distance_squared_to(pos) <= tr * tr:
			return true
	return false


func wall_link_at(p: int, pos: Vector2, r: float) -> int:
	var B := buildings
	var best := 0
	var bd := r * r
	for b in B.hw:
		if B.owner[b] != p or B.state[b] == BuildingTable.State.FREE or B.state[b] == BuildingTable.State.RUIN:
			continue
		if defs.b_kind[B.btype[b]] != Defs.BKind.WALL:
			continue
		var d := seg_dist2(pos, Vector2(B.ax[b], B.az[b]), Vector2(B.bx[b], B.bz[b]))
		if d <= bd:
			bd = d
			best = B.handle(b)
	return best


func worker_job(u_h: int) -> int:
	if not is_ours(u_h):
		return -1
	var w := un_w[Ids.slot(u_h)]
	return wk.w_job[w] if w >= 0 else -1


func idle_workers(p: int) -> PackedInt32Array:
	return wk.idle_of(self, p)


func arba_cargo(u_h: int) -> int:
	if not is_ours(u_h):
		return 0
	var c := un_cargo[Ids.slot(u_h)]
	return buildings.handle(c - 1) if c > 0 and buildings.state[c - 1] != BuildingTable.State.FREE else 0


func grass_grid() -> PackedByteArray:
	return fld.bytes


func water_grid() -> PackedByteArray:
	return net.bytes


## Размеры сеток (gw, gh, ww, wh) — для GameQuery.field_dims
func field_dims() -> Vector4i:
	return Vector4i(fld.gw, fld.gh, net.ww, net.wh)


func building_panel(b_h: int) -> Dictionary:
	return qry.building_panel(self, b_h)


func build_menu(p: int, tab: StringName) -> Array[Dictionary]:
	return qry.build_menu(self, p, tab)


## Игрок выбыл (Victory, GAME): таблицы пишет только ECON — players.alive = 0, очереди и работа стоят
func defeat(p: int) -> void:
	if p < 0 or p >= players.count:
		return
	players.alive[p] = 0
	var B := buildings
	for b in B.hw:
		if B.owner[b] == p and B.q_n[b] > 0:
			prod.clear_queue(self, b)


## Круг прогресса набега над зданием 0..1 (барымта, талоо, вытаптывание) — для вида и панели
func raid_progress(b_h: int) -> float:
	return raid.raid_progress(self, buildings.slot(b_h)) if buildings.valid(b_h) else 0.0


## Есть ли у игрока ставка (стоит, строится или едет в арбе) — для Victory
func has_hq(p: int) -> bool:
	var B := buildings
	for b in B.hw:
		if B.owner[b] == p and B.flags[b] & Defs.BF_HQ:
			var st := B.state[b]
			if st == BuildingTable.State.ACTIVE or st == BuildingTable.State.SITE or st == BuildingTable.State.PACKED:
				return true
	return false


func checksum() -> int:
	var h := 0x1F3D5B79
	for v: Variant in [players.res, players.pop_used, players.pop_cap, players.famine, buildings.state, buildings.hp_c,
			buildings.progress, buildings.q_n, buildings.q_t, nodes.amount_milli, herds.heads_milli, herds.state,
			wk.w_job, wk.w_carry, b_work, b_water]:
		h = (h * 31 + hash(v)) & 0x7FFFFFFF
	h = (h * 31 + rng.state) & 0x7FFFFFFF
	return h


func save_into(d: Dictionary) -> void:
	var st := {}
	for k: String in _SAVED:
		st[k] = _copy(get(k))
	for t: String in ["players", "buildings", "nodes", "herds"]:
		var obj: Object = get(t)
		var td := {}
		for prop: Dictionary in obj.get_property_list():
			if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				td[prop["name"]] = _copy(obj.get(prop["name"]))
		st[t] = td
	for s: String in ["wk", "prod", "popn", "hd", "fld", "net", "mods", "raid", "nomad", "cal"]:
		var obj: Object = get(s)
		var sd := {}
		for prop: Dictionary in obj.get_property_list():
			if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				sd[prop["name"]] = _copy(obj.get(prop["name"]))
		st[s] = sd
	st["rng"] = rng.state
	d["econ"] = st


func load_from(d: Dictionary) -> void:
	var st: Dictionary = d.get("econ", {})
	for k: String in st:
		if k == "rng":
			rng.state = int(st[k])
		elif st[k] is Dictionary and k in ["players", "buildings", "nodes", "herds", "wk", "prod", "popn", "hd", "fld",
				"net", "mods", "raid", "nomad", "cal"]:
			var obj: Object = get(k)
			for prop: String in st[k]:
				obj.set(prop, _copy(st[k][prop]))
		else:
			set(k, _copy(st[k]))
	_pop_dirty = true
	_drops_dirty = true
	_net_dirty = true


const _SAVED := ["tick", "b_work", "b_total", "b_order", "b_water", "b_net", "b_timer", "b_mode", "b_cd", "b_cd2",
	"b_act", "b_act_n", "b_slots", "b_otlar", "b_auto", "b_flag", "b_dest", "bq_disc", "_order_seq", "un_gen",
	"un_owner", "un_type", "un_w", "un_cargo", "p_upkeep", "p_soldiers", "p_unique", "p_flow", "p_hist", "p_alarm",
	"_sites", "_queues"]


static func _copy(v: Variant) -> Variant:
	if v is Array or v is Dictionary:
		return v.duplicate(true)
	if typeof(v) >= TYPE_PACKED_BYTE_ARRAY and typeof(v) <= TYPE_PACKED_VECTOR4_ARRAY:
		return v.duplicate()
	return v


# ================================================================= ресурсы

## Списать цену. Ресурс с «подложкой» (кони) снимается головами из табунов (hint — здание найма).
func pay(p: int, cost: PackedInt32Array, hint_b := -1) -> void:
	for r in mini(cost.size(), R):
		if cost[r] == 0:
			continue
		if defs.r_backing[r] >= 0:
			hd.take_heads(self, p, defs.r_backing[r], cost[r] / 1000, hint_b)
		else:
			players.res[p * R + r] -= cost[r]


## Добавить ресурсы; flow — учесть в доходе для балки (добыча, подать, корм), иначе — возврат
func gain(p: int, amounts: PackedInt32Array, flow := true, hint_b := -1) -> void:
	for r in mini(amounts.size(), R):
		if amounts[r] != 0:
			add_res(p, r, amounts[r], flow, hint_b)


func add_res(p: int, r: int, milli: int, flow := true, hint_b := -1) -> void:
	if defs.r_backing[r] >= 0:
		if milli > 0:
			hd.give_heads(self, p, defs.r_backing[r], milli / 1000, hint_b)
		return
	players.res[p * R + r] += milli
	if flow:
		p_flow[p * R + r] += milli


func _not_enough(p: int, cost: PackedInt32Array, op: int) -> void:
	for r in mini(cost.size(), R):
		var lack := cost[r] - players.res[p * R + r]
		if lack > 0:
			events.push(SimEvents.Ev.NOT_ENOUGH, p, r, lack, op)
			return


## Доход в минуту для балки: окно 60 с (раз в секунду)
func _income_step() -> void:
	var s := (tick / 30) % 60
	for i in p_flow.size():
		var k := i * 60 + s
		var old := p_hist[k]
		p_hist[k] = p_flow[i]
		players.income[i] += int(p_flow[i] - old)
		p_flow[i] = 0


# ================================================================= здания: жизнь

func _new_building(p: int, btype: int, center: Vector2, rot_q: int, state: int) -> int:
	var B := buildings
	var b := B.alloc(state)
	_grow_b(b)
	B.btype[b] = btype
	B.owner[b] = p
	B.team[b] = players.team[p] if p >= 0 and p < players.count else -1
	B.rot_q[b] = rot_q & 3
	B.flags[b] = defs.b_flags[btype]
	B.x[b] = center.x
	B.z[b] = center.y
	B.rot[b] = (rot_q & 3) * PI * 0.5
	B.hp_max_c[b] = defs.b_hp_c[btype]
	B.hp_c[b] = defs.b_hp_c[btype]
	B.progress[b] = 1000 if state == BuildingTable.State.ACTIVE else 0
	B.store_mask[b] = defs.b_accepts[btype]
	B.recipe[b] = defs.b_recipes[btype][0] if not defs.b_recipes[btype].is_empty() else -1
	var rect := NavApi.footprint(defs, btype, center, rot_q & 3, origin)
	B.c0[b] = rect.position.x
	B.r0[b] = rect.position.y
	B.cw[b] = rect.size.x
	B.ch[b] = rect.size.y
	b_work[b] = 0
	b_total[b] = 0
	b_order[b] = 0
	b_water[b] = 0
	b_net[b] = -1
	b_timer[b] = 0
	b_mode[b] = Mode.NONE
	b_cd[b] = 0
	b_cd2[b] = 0
	b_act[b] = 0
	b_act_n[b] = 0
	b_slots[b] = 0
	b_otlar[b] = 0
	b_auto[b] = 1
	b_flag[b] = 0
	b_dest[b] = center
	for i in BuildingTable.QMAX:
		bq_disc[b * BuildingTable.QMAX + i] = 0
	return b


func _grow_b(b: int) -> void:
	while b_work.size() <= b:
		for a: Variant in [b_work, b_total, b_order, b_water, b_net, b_timer, b_mode, b_cd, b_cd2, b_act, b_act_n,
				b_slots, b_otlar, b_auto, b_flag]:
			a.append(0)
		b_dest.append(Vector2.ZERO)
		for i in BuildingTable.QMAX:
			bq_disc.append(0)


func _grow_units(s: int) -> void:
	while un_gen.size() <= s:
		un_gen.append(0)
		un_owner.append(-1)
		un_type.append(-1)
		un_w.append(-1)
		un_cargo.append(0)


## Полуразмеры следа с поворотом
func half_of(b: int) -> Vector2:
	var half := defs.b_size[buildings.btype[b]] * 0.5
	return Vector2(half.y, half.x) if buildings.rot_q[b] & 1 else half


## Штамп в навигации и зеркало в ядре (стройка — флаг ST_SITE)
func _place_world(b: int) -> void:
	var B := buildings
	var bt := B.btype[b]
	var h := B.handle(b)
	var kind := defs.b_kind[bt]
	if nav:
		if kind == Defs.BKind.LINK or kind == Defs.BKind.WALL:
			nav.stamp_link(h, B.team[b], Vector2(B.ax[b], B.az[b]), Vector2(B.bx[b], B.bz[b]), bt)
		else:
			nav.stamp_building(h, B.team[b], Vector2(B.x[b], B.z[b]), bt, B.rot_q[b])
	_mirror(b)


func _mirror(b: int) -> void:
	if port == null:
		return
	var B := buildings
	var bt := B.btype[b]
	# арык не мешает ходить и не ломается — в ядро не идёт
	if defs.b_kind[bt] == Defs.BKind.LINK and B.flags[b] & Defs.BF_WALKABLE:
		return
	var half := half_of(b)
	if defs.b_kind[bt] == Defs.BKind.WALL:
		half = defs.b_size[bt] * 0.5
	var active := B.state[b] == BuildingTable.State.ACTIVE
	port.structure_set(B.handle(b), B.team[b], Vector2(B.x[b], B.z[b]), half, B.rot[b], st_flags(bt, active),
		defs.b_platform_h[bt], defs.b_gar_cap[bt])


func _unplace_world(b: int) -> void:
	var h := buildings.handle(b)
	if nav:
		nav.unstamp(h)
	if port:
		port.structure_clear(h)


## Флаги структуры ядра (BattleSim.ST_*)
func st_flags(btype: int, active: bool) -> int:
	var f := 0
	match defs.b_kind[btype]:
		Defs.BKind.WALL: f |= BattleSim.ST_WALL
		Defs.BKind.GATE: f |= BattleSim.ST_GATE
		Defs.BKind.TOWER: f |= BattleSim.ST_TOWER
		Defs.BKind.FIELD: f |= BattleSim.ST_FIELD
	if defs.b_flags[btype] & Defs.BF_BLOCKS:
		f |= BattleSim.ST_BLOCK
	if defs.b_flags[btype] & Defs.BF_HQ:
		f |= BattleSim.ST_HQ
	if not active:
		f |= BattleSim.ST_SITE
	return f


## Стройка: HP от 10%, работа — build_ticks × 1000 милли «работник·такт»
func _start_site(b: int, build_ticks: int) -> void:
	var B := buildings
	B.state[b] = BuildingTable.State.SITE
	B.progress[b] = 0
	B.hp_c[b] = maxi(1, B.hp_max_c[b] / 10)
	b_work[b] = 0
	b_total[b] = maxi(1, build_ticks) * 1000
	if not _sites.has(b):
		_sites.append(b)
	if build_ticks <= 0:
		b_work[b] = b_total[b]


## Стройки: прогресс += Σ n^0,75 × Ҳашар / build_ticks; HP растёт вместе с прогрессом
func _sites_step() -> void:
	var B := buildings
	var i := 0
	while i < _sites.size():
		var b := _sites[i]
		if B.state[b] != BuildingTable.State.SITE:
			_sites.remove_at(i)
			continue
		var n := B.workers_n[b]
		var rate: int = N075[mini(n, N075.size() - 1)]
		if n >= N075.size():
			rate = N075[N075.size() - 1] + (n - N075.size() + 1) * 300
		if n > 0:
			rate = rate * mods.build_milli(self, B.owner[b]) / 1000
		if b_mode[b] == Mode.ERECT:
			rate += 1000          # юрта после көча встаёт сама, работники ускоряют
		if rate > 0:
			var old_p := B.progress[b]
			b_work[b] = mini(b_work[b] + rate, b_total[b])
			B.progress[b] = int(int(b_work[b]) * 1000 / b_total[b])
			if B.progress[b] != old_p:
				var hmax := B.hp_max_c[b]
				var base := hmax / 10
				B.hp_c[b] = mini(hmax, B.hp_c[b] + (hmax - base) * (B.progress[b] - old_p) / 1000)
		if b_work[b] >= b_total[b]:
			_sites.remove_at(i)
			_activate(b, true)
			continue
		i += 1


## Здание готово (или стоит с начала карты)
func _activate(b: int, from_site: bool) -> void:
	var B := buildings
	var bt := B.btype[b]
	var p := B.owner[b]
	B.state[b] = BuildingTable.State.ACTIVE
	B.progress[b] = 1000
	if not from_site or b_mode[b] == Mode.ERECT or b_mode[b] == Mode.REBUILD:
		B.hp_c[b] = B.hp_max_c[b]
	var was := b_mode[b]
	b_mode[b] = Mode.NONE
	_order_seq += 1
	b_order[b] = _order_seq
	if B.flags[b] & Defs.BF_HQ and p >= 0:
		players.hq_b[p] = B.handle(b)
	_mirror(b)
	if was == Mode.ERECT:
		hd.on_unpacked(self, b)
	elif defs.b_herd[bt] >= 0 and not hd.has_herd(self, b):
		hd.spawn(self, p, defs.b_herd[bt], B.handle(b), defs.b_herd_start[bt])
	if defs.b_otlar[bt].size() > 0:
		b_otlar[b] = 0
	_pop_dirty = true
	_drops_dirty = true
	if defs.b_kind[bt] in [Defs.BKind.DAM, Defs.BKind.LINK, Defs.BKind.FIELD] or defs.b_water_place[bt] > 0:
		_net_dirty = true
	if from_site:
		if was == Mode.ERECT:
			events.push(SimEvents.Ev.UNPACKED, p, B.handle(b), 0, bt, Vector2(B.x[b], B.z[b]))
		else:
			events.push(SimEvents.Ev.BUILDING_DONE, p, B.handle(b), bt, 0, Vector2(B.x[b], B.z[b]))


## Разрушено (attacker — игрок или −1) или снесено своими (own). Руина остаётся у всех, кроме полей и
## звеньев; руина тўғона ждёт восстановления, прочие уходят через 60 с.
func destroy_building(b: int, attacker: int, own := false) -> void:
	var B := buildings
	var bt := B.btype[b]
	var p := B.owner[b]
	var h := B.handle(b)
	var pos := Vector2(B.x[b], B.z[b])
	var was_active := B.state[b] == BuildingTable.State.ACTIVE
	if B.state[b] != BuildingTable.State.PACKED:
		_unplace_world(b)
	prod.clear_queue(self, b)
	wk.on_building_gone(self, b)
	hd.on_pen_gone(self, b)
	if B.flags[b] & Defs.BF_HQ and p >= 0 and players.hq_b[p] == h:
		players.hq_b[p] = 0
	if not own and attacker >= 0 and was_active:
		bty.on_building(self, b, attacker)
	events.push(SimEvents.Ev.BUILDING_DESTROYED, p, h, bt, attacker, pos)
	var kind := defs.b_kind[bt]
	B.workers_n[b] = 0
	b_slots[b] = 0
	B.q_n[b] = 0
	if kind == Defs.BKind.FIELD or kind == Defs.BKind.LINK or B.state[b] == BuildingTable.State.PACKED or own:
		B.release(b)
	else:
		B.state[b] = BuildingTable.State.RUIN
		B.hp_c[b] = 0
		B.progress[b] = 0
		b_mode[b] = Mode.NONE
		b_timer[b] = 0 if defs.b_rebuild_ticks[bt] > 0 else tick + RUIN_TICKS
	if defs.b_network[bt].get("source", false):
		net.on_dam_destroyed(self, b)
	_pop_dirty = true
	_drops_dirty = true
	_net_dirty = true


func _ruins_step() -> void:
	var B := buildings
	for b in B.hw:
		if B.state[b] == BuildingTable.State.RUIN and b_timer[b] > 0 and tick >= b_timer[b]:
			B.release(b)


func _own_ruin_near(p: int, btype: int, center: Vector2, r: float) -> int:
	var B := buildings
	for b in B.hw:
		if B.state[b] == BuildingTable.State.RUIN and B.owner[b] == p and B.btype[b] == btype \
				and Vector2(B.x[b], B.z[b]).distance_squared_to(center) <= r * r:
			return b
	return -1


# ================================================================= смерти и попадания

func _on_death(u_h: int, killer_h: int) -> void:
	_deaths_seen[u_h] = true
	var s := Ids.slot(u_h)
	var ours := is_ours(u_h)
	var p := un_owner[s] if ours else (port.owner(u_h) if port else -1)
	var utype := un_type[s] if ours else defs.unit(port.type_id(u_h) if port else &"")
	var pos := port.pos(u_h) if port and port.valid(u_h) else Vector2.ZERO
	if ours:
		if un_cargo[s] > 0:
			nomad.arba_died(self, u_h, un_cargo[s] - 1)
		if utype >= 0 and defs.u_unique[utype] == 1 and p >= 0:
			p_unique[p * defs.unit_ids.size() + utype] = tick + defs.u_respawn_ticks[utype]
		unregister_unit(u_h)
	raid.on_unit_gone(self, u_h, true)
	hd.on_captor_gone(self, u_h, true)
	var kp := port.owner(killer_h) if port and killer_h != 0 and port.valid(killer_h) else -1
	if kp >= 0 and p >= 0 and kp != p and utype >= 0:
		if pos == Vector2.ZERO:
			pos = port.pos(killer_h)
		bty.on_kill(self, kp, utype, u_h, pos)
	events.push(SimEvents.Ev.UNIT_DIED, p, u_h, killer_h, utype, pos)


## Попадание по зданию: множители урона по родам (ECONOMY §1.6) — рукопашная пехоты ×0,5, конницы ×0,3,
## налётчиков по хозяйственным ×0,4; стрелы/пули/ядра уже умножены ядром на vs_building
func _on_hit(b_h: int, dmg_c: int, att_h: int) -> void:
	if not buildings.valid(b_h):
		return
	var b := buildings.slot(b_h)
	var B := buildings
	if B.flags[b] & Defs.BF_UNBREAKABLE or B.state[b] == BuildingTable.State.RUIN or B.state[b] == BuildingTable.State.PACKED:
		return
	var mul := 1000
	var ap := -1
	if port and att_h != 0 and port.valid(att_h):
		ap = port.owner(att_h)
		var fl := int(UnitStats.get_stats(String(port.type_id(att_h))).get("flags", 0))
		if fl & (UnitStats.BOW | UnitStats.MUSKET | UnitStats.CANNON) == 0:
			var dm: Dictionary = rules.get("bld_dmg", {})
			if fl & UnitStats.RAIDER and is_economic(b):
				mul = roundi(float(dm.get("raider_econ", 0.4)) * 1000.0)
			elif fl & UnitStats.MOUNTED:
				mul = roundi(float(dm.get("melee_cav", 0.3)) * 1000.0)
			else:
				mul = roundi(float(dm.get("melee_inf", 0.5)) * 1000.0)
	var dmg := dmg_c * mul / 1000
	B.hp_c[b] -= dmg
	B.hit_tick[b] = tick
	events.push(SimEvents.Ev.BUILDING_HIT, B.owner[b], b_h, dmg, att_h, Vector2(B.x[b], B.z[b]))
	if B.hp_c[b] <= 0:
		destroy_building(b, ap)


# ================================================================= служебное

## Хозяйственное здание (ECONOMY §1.6): дома, юрты, склады, мельница, тўғон, хумдон, базар, короо, кен —
## не ставка, не укрепление и не место найма бойцов
func is_economic(b: int) -> bool:
	var bt := buildings.btype[b]
	var kind := defs.b_kind[bt]
	if buildings.flags[b] & Defs.BF_HQ or (kind != Defs.BKind.BUILDING and kind != Defs.BKind.DAM):
		return false
	for u in defs.b_trains[bt]:
		if defs.u_flags[u] & UnitStats.WORKER == 0:
			return false
	return true


## Слот своего живого здания или −Err
func _own(p: int, b_h: int) -> int:
	if not buildings.valid(b_h):
		return -Err.STALE
	var b := buildings.slot(b_h)
	if buildings.owner[b] != p:
		return -Err.NOT_OWNER
	return b


func active(b: int) -> bool:
	return buildings.state[b] == BuildingTable.State.ACTIVE and b_mode[b] != Mode.PACKING


## Сколько у игрока построек вида (с недостроенными — для предела)
func count_of(p: int, btype: int, with_sites: bool) -> int:
	var B := buildings
	var n := 0
	for b in B.hw:
		if B.owner[b] == p and B.btype[b] == btype:
			var st := B.state[b]
			if st == BuildingTable.State.ACTIVE or st == BuildingTable.State.PACKED or (with_sites and st == BuildingTable.State.SITE):
				n += 1
	return n


func has_required(p: int, req: PackedInt32Array) -> bool:
	for bt in req:
		var found := false
		var B := buildings
		for b in B.hw:
			if B.owner[b] == p and B.btype[b] == bt and B.state[b] == BuildingTable.State.ACTIVE:
				found = true
				break
		if not found:
			return false
	return true


func _rebuild_drops() -> void:
	_drops_dirty = false
	for p in _drops.size():
		_drops[p] = PackedInt32Array()
	var B := buildings
	for b in B.hw:
		if B.state[b] == BuildingTable.State.ACTIVE and B.flags[b] & Defs.BF_DROP and B.owner[b] >= 0 \
				and B.owner[b] < _drops.size() and b_mode[b] != Mode.PACKING:
			_drops[B.owner[b]].append(b)


func drops_of(p: int) -> PackedInt32Array:
	return _drops[p] if p >= 0 and p < _drops.size() else PackedInt32Array()


## Дверь: перед фасадом (+Z, повёрнутым на rot_q), на проходимой клетке
func door_of(b: int) -> Vector2:
	var B := buildings
	var q := B.rot_q[b]
	var depth := defs.b_size[B.btype[b]].y * 0.5
	var d: Vector2 = DIR4[q]
	var p := Vector2(B.x[b], B.z[b]) + d * (depth + DOOR_GAP)
	return nav.nearest_passable(B.team[b], p) if nav else p


## Ближайшая к from точка у края следа здания (отступ gap)
func edge_point(b: int, from: Vector2, gap := 1.0) -> Vector2:
	var c := Vector2(buildings.x[b], buildings.z[b])
	var half := half_of(b) + Vector2(gap, gap)
	var rel := from - c
	var q := Vector2(clampf(rel.x, -half.x, half.x), clampf(rel.y, -half.y, half.y))
	if absf(q.x) < half.x and absf(q.y) < half.y:
		# внутри — на ближайшую сторону
		if half.x - absf(q.x) < half.y - absf(q.y):
			q.x = half.x if q.x >= 0.0 else -half.x
		else:
			q.y = half.y if q.y >= 0.0 else -half.y
	return c + q


## Квадрат расстояния от точки до прямоугольника следа здания
func rect_dist2(b: int, p: Vector2) -> float:
	var c := Vector2(buildings.x[b], buildings.z[b])
	var half := half_of(b)
	var dx := maxf(absf(p.x - c.x) - half.x, 0.0)
	var dz := maxf(absf(p.y - c.y) - half.y, 0.0)
	return dx * dx + dz * dz


static func seg_dist2(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 0.000001:
		return p.distance_squared_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_squared_to(a + ab * t)


## Направление ломаной у точки c (ближайший отрезок)
static func _polyline_dir(pts: PackedVector2Array, c: Vector2) -> Vector2:
	var best := Vector2(1, 0)
	var bd := INF
	for i in range(1, pts.size()):
		var d := seg_dist2(c, pts[i - 1], pts[i])
		if d < bd and pts[i] != pts[i - 1]:
			bd = d
			best = (pts[i] - pts[i - 1]).normalized()
	return best


func team_of(p: int) -> int:
	return players.team[p] if p >= 0 and p < players.count else -1


func faction_has(p: int, trait_id: String) -> bool:
	return p >= 0 and p < players.count and defs.has_trait(players.faction[p], trait_id)


func rule(path: String, key: String, def: Variant) -> Variant:
	var d: Variant = rules.get(path, {})
	return d.get(key, def) if d is Dictionary else def
