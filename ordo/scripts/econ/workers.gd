class_name EconWorkers
extends RefCounted
## Работники (ARCHITECTURE §11, ECONOMY §1.1, §1.6, §2.2, §2.4, §3.4): машина работ на 10 Гц третями
## (работник w думает в такт, где w % 3 == tick % 3), тела — только через CombatPort.
##
##   IDLE ─gather─► TO_NODE (место из 8 у узла) ─► GATHER (рубит/копает, ноша растёт) ─► TO_DROP (ближний склад,
##        несёт) ─► сдал (RES_DELIVERED) ─► назад к тому же узлу; узел выработан — ближний того же вида ≤ 40 м
##   IDLE ─build─► TO_SITE ─► BUILD (n^0,75) ─► готово: поле — пахать, печь — жечь, звено — следующее звено
##        цепочки, иначе прежняя работа (w_prev_*) или IDLE + WORKER_IDLE
##   TO_FIELD ─► FARM (место 1..4) ─► ноша → Тегирмон/Урда ─► назад на своё место
##   TO_PEN ─► HERD (пастух короо, еда сразу в запас — EconHerds);  TO_KILN ─► KILN (Хумдон — EconProduction)
##   REPAIR — чинит целое здание; SHELTER — укрылся по тревоге.
##
## Модель ходки (тесты считают её из Defs): UnitEcon.gather — ЭФФЕКТИВНАЯ скорость при складе в 25 м
## (ECONOMY §1.1); сырая скорость у узла выводится так, чтобы ходка «ноша + 2 × 25 м пути» давала её.
## Каждые лишние 20 м пути — около −15% (при ноше 30 и беге 3,8 м/с).

enum Job { IDLE, TO_NODE, GATHER, TO_DROP, TO_SITE, BUILD, FARM, IN_ARBA, TO_FIELD, TO_PEN, HERD, TO_KILN, KILN,
	REPAIR, SHELTER }

const REF_M := 25.0                      # склад «рядом» (ECONOMY §1.1)
const JITTER := 31                       # разброс конца работы по номеру работника: одинаковые ходки
                                         # не сходятся в один такт (пик p99); в среднем 15 тактов
const OVERHEAD := 6 + 15                 # тактов на ходку сверх пути (такт мысли, прибытие, разброс)
const NEXT_NODE_R := 40.0                # узел выработан — следующий того же вида в 40 м
const AUTO_GATHER_R := 30.0              # построил склад — берётся за ближний узел в 30 м
const ARRIVE_R := 2.5
const MIN_MOVE_T := 4                    # прибытие — не раньше 4 тактов после приказа
const RETRY_T := 1800                    # шёл дольше 60 с — приказ повторяется
const NB_CELL := 32.0                    # корзины узлов
const RUN := true                        # работники ходят бегом (скорость UnitStats.speed)
const NEVER := 1 << 30                   # «не будить»
const BUILD_WAKE := 30                   # стройка, загон, печь: проверка раз в секунду
const DIR8 := [Vector2(0, 1), Vector2(0.7071, 0.7071), Vector2(1, 0), Vector2(0.7071, -0.7071), Vector2(0, -1),
	Vector2(-0.7071, -0.7071), Vector2(-1, 0), Vector2(-0.7071, 0.7071)]
const FIELD_SLOTS := [Vector2(-4, -4), Vector2(4, -4), Vector2(-4, 4), Vector2(4, 4), Vector2(0, 0), Vector2(0, -4),
	Vector2(0, 4), Vector2(-4, 0)]

var hw := 0
var thinks := 0                          # счётчик мыслей (замеры: пик работы за такт)
var w_unit := PackedInt32Array()         # описатель юнита, 0 — свободно
var w_owner := PackedInt32Array()
var w_utype := PackedInt32Array()
var w_job := PackedInt32Array()
var w_target := PackedInt32Array()       # узел / поле / загон / печь / стройка (описатель)
var w_spot := PackedInt32Array()         # место у узла или поля, −1
var w_carry_res := PackedInt32Array()
var w_carry := PackedInt32Array()        # милли
var w_frac := PackedInt32Array()         # микро-остаток (1/1000 милли)
var w_cap := PackedInt32Array()          # ноша, милли
var w_t := PackedInt32Array()            # такт начала состояния / приказа хода / учёта добычи
var w_wake := PackedInt32Array()         # такт, раньше которого работник не думает (ход по ETA, ноша)
var w_retry := PackedInt32Array()
var w_mult := PackedInt32Array()         # множитель добычи, милли (Кен, поле без воды, …)
var w_drop := PackedInt32Array()         # склад (описатель)
var w_prev_job := PackedInt32Array()
var w_prev_target := PackedInt32Array()
var w_tx := PackedFloat32Array()
var w_tz := PackedFloat32Array()
var _free := PackedInt32Array()

# модель ходки: сырая скорость у узла, микро (1/1000 милли) за такт
var raw := PackedInt32Array()            # [u * R + r]
var farm_raw := PackedInt32Array()       # [u * NB + bt] — поле
var speed := PackedFloat32Array()        # [u] м/с
var walk_ticks := PackedInt32Array()     # [u] тактов на 2 × 25 м пути + накладные (модель ходки)

# узлы: корзины 32 м и занятые места
var nb_w := 0
var nb_h := 0
var nb: Array[PackedInt32Array] = []
var n_spots := PackedInt32Array()        # [n] маска мест


func setup(e: EconomySim) -> void:
	var D := e.defs
	var U := D.unit_ids.size()
	var NB := D.b_ids.size()
	raw.resize(U * e.R)
	farm_raw.resize(U * NB)
	speed.resize(U)
	walk_ticks.resize(U)
	for u in U:
		var st := UnitStats.get_stats(D.unit_ids[u])
		speed[u] = float(st.get("speed", 3.5)) * (1.0 if RUN else float(st.get("walk", 0.62)))
		walk_ticks[u] = int(2.0 * REF_M / speed[u] * 30.0) + OVERHEAD
		var carry := D.u_carry_milli[u]
		if carry <= 0:
			continue
		for r in e.R:
			raw[u * e.R + r] = trip_raw(carry, D.u_gather[u * e.R + r], speed[u])
		for bt in NB:
			var wk: Dictionary = D.b_work[bt]
			if not wk.is_empty() and D.b_kind[bt] == Defs.BKind.FIELD:
				farm_raw[u * NB + bt] = trip_raw(carry, int(wk["per_worker_min_milli"]) / 60, speed[u])
	nb_w = maxi(1, ceili(e.extent.x / NB_CELL))
	nb_h = maxi(1, ceili(e.extent.y / NB_CELL))
	nb.clear()
	for i in nb_w * nb_h:
		nb.append(PackedInt32Array())


## Сырая скорость у узла (микро за такт): ходка «ноша / сырая + 2 × 25 м / скорость» даёт эффективную
static func trip_raw(carry_milli: int, eff_milli_s: int, v: float) -> int:
	if eff_milli_s <= 0 or carry_milli <= 0:
		return 0
	var cycle := float(carry_milli) * 30.0 / float(eff_milli_s)
	var walk := 2.0 * REF_M / v * 30.0
	var work := maxf(cycle - walk - OVERHEAD, cycle * 0.2)
	return roundi(float(carry_milli) * 1000.0 / work)


## Сырая скорость (микро за такт) для эффективной eff_milli_min при складе в 25 м — целочисленно.
## Множители (Кен, поле без воды, Ҳашар) масштабируют ЭФФЕКТИВНУЮ скорость (ECONOMY: лалми — 7,5 из 30).
func rate_for(utype: int, carry_milli: int, eff_milli_min: int) -> int:
	if eff_milli_min <= 0 or carry_milli <= 0:
		return 0
	var cycle := carry_milli * 1800 / eff_milli_min
	var work := maxi(cycle - walk_ticks[utype], cycle / 5)
	return carry_milli * 1000 / maxi(work, 1)


## Ожидаемая выработка (милли в минуту) при пути d м до склада — для тестов и подсказок
static func trip_model(carry_milli: int, raw_micro: int, v: float, d: float) -> float:
	if raw_micro <= 0:
		return 0.0
	var cycle := float(carry_milli) * 1000.0 / float(raw_micro) + 2.0 * d / v * 30.0 + OVERHEAD
	return float(carry_milli) / cycle * 1800.0


# ================================================================= учёт

func add(e: EconomySim, u_h: int, p: int, utype: int) -> int:
	var w := -1
	if _free.size() > 0:
		w = _free[_free.size() - 1]
		_free.remove_at(_free.size() - 1)
	else:
		w = hw
		hw += 1
		for a: Variant in [w_unit, w_owner, w_utype, w_job, w_target, w_spot, w_carry_res, w_carry, w_frac, w_cap, w_t,
				w_wake, w_retry, w_mult, w_drop, w_prev_job, w_prev_target]:
			a.append(0)
		w_tx.append(0.0)
		w_tz.append(0.0)
	w_unit[w] = u_h
	w_owner[w] = p
	w_utype[w] = utype
	w_job[w] = Job.IDLE
	w_target[w] = 0
	w_spot[w] = -1
	w_carry_res[w] = -1
	w_carry[w] = 0
	w_frac[w] = 0
	w_cap[w] = maxi(1000, e.defs.u_carry_milli[utype])
	w_t[w] = e.tick
	w_wake[w] = NEVER
	w_retry[w] = 0
	w_mult[w] = 1000
	w_drop[w] = 0
	w_prev_job[w] = Job.IDLE
	w_prev_target[w] = 0
	return w


func remove(e: EconomySim, w: int) -> void:
	_leave(e, w)
	w_unit[w] = 0
	w_job[w] = Job.IDLE
	_free.append(w)


## Другой приказ (бой, ход) снял работника с работы: ноша остаётся
func release(e: EconomySim, w: int) -> void:
	_leave(e, w)
	w_job[w] = Job.IDLE
	w_target[w] = 0
	w_prev_job[w] = Job.IDLE
	w_prev_target[w] = 0
	w_wake[w] = NEVER
	if e.port:
		e.port.set_work(w_unit[w], -1.0)


func idle_of(e: EconomySim, p: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for w in hw:
		if w_unit[w] != 0 and w_owner[w] == p and w_job[w] == Job.IDLE:
			out.append(w_unit[w])
	return out


# ================================================================= узлы: корзины

func node_added(e: EconomySim, n: int) -> void:
	while n_spots.size() <= n:
		n_spots.append(0)
	n_spots[n] = 0
	var k := _bucket(e, Vector2(e.nodes.x[n], e.nodes.z[n]))
	if not nb[k].has(n):
		nb[k].append(n)


func _bucket(e: EconomySim, p: Vector2) -> int:
	var cx := clampi(floori((p.x - e.origin.x) / NB_CELL), 0, nb_w - 1)
	var cz := clampi(floori((p.y - e.origin.y) / NB_CELL), 0, nb_h - 1)
	return cz * nb_w + cx


## Ближайший узел с запасом по маске ресурсов (ntype ≥ 0 — только этого вида; free — со свободным местом)
func node_near(e: EconomySim, res_mask: int, pos: Vector2, r: float, ntype := -1, free := false) -> int:
	var N := e.nodes
	var best := -1
	var bd := r * r
	var c0 := clampi(floori((pos.x - r - e.origin.x) / NB_CELL), 0, nb_w - 1)
	var c1 := clampi(floori((pos.x + r - e.origin.x) / NB_CELL), 0, nb_w - 1)
	var r0 := clampi(floori((pos.y - r - e.origin.y) / NB_CELL), 0, nb_h - 1)
	var r1 := clampi(floori((pos.y + r - e.origin.y) / NB_CELL), 0, nb_h - 1)
	for cz in range(r0, r1 + 1):
		for cx in range(c0, c1 + 1):
			for n in nb[cz * nb_w + cx]:
				if N.ntype[n] < 0 or N.amount_milli[n] == 0 or res_mask & (1 << N.res[n]) == 0:
					continue
				if ntype >= 0 and N.ntype[n] != ntype:
					continue
				if free and N.workers_n[n] >= N.workers_max[n]:
					continue
				var d := Vector2(N.x[n], N.z[n]).distance_squared_to(pos)
				if d < bd or (d == bd and n < best):
					bd = d
					best = n
	return best


func _deplete(e: EconomySim, n: int) -> void:
	var N := e.nodes
	var h := N.handle(n)
	var pos := Vector2(N.x[n], N.z[n])
	if N.scatter_ref[n] >= 0:
		e.events.push(SimEvents.Ev.TREE_FELLED, -1, h, N.scatter_ref[n], N.ntype[n], pos)
	e.events.push(SimEvents.Ev.NODE_DEPLETED, -1, h, N.ntype[n], N.scatter_ref[n], pos)
	var k := _bucket(e, pos)
	var i := nb[k].find(n)
	if i >= 0:
		nb[k].remove_at(i)
	N.release(n)
	N.workers_n[n] = 0
	n_spots[n] = 0


## Место у узла: кольцо из 8 (дерево — 1,3 м, жила — край ядра 2×2 клетки + 1,2 м)
func _node_spot_pos(e: EconomySim, n: int, spot: int) -> Vector2:
	var N := e.nodes
	var bc := e.defs.n_blocks_cells[N.ntype[n]]
	var rr := 1.3 if bc == 0 else bc * NavApi.CELL * 0.5 + 1.2
	var d: Vector2 = DIR8[maxi(spot, 0) % 8]
	return Vector2(N.x[n], N.z[n]) + d * rr


## Занять место у узла: ближайшее к работнику свободное (−1 — все заняты)
func _reserve_node(e: EconomySim, n: int, from: Vector2) -> int:
	var N := e.nodes
	if N.workers_n[n] >= N.workers_max[n]:
		return -1
	var best := -1
	var bd := INF
	for s in 8:
		if n_spots[n] & (1 << s):
			continue
		var d := _node_spot_pos(e, n, s).distance_squared_to(from)
		if d < bd:
			bd = d
			best = s
	if best >= 0:
		n_spots[n] |= 1 << best
		N.workers_n[n] += 1
	return best


# ================================================================= приказы

func assign_gather(e: EconomySim, p: int, workers: PackedInt32Array, source_h: int) -> int:
	var done := 0
	for u_h in workers:
		if not e.is_ours(u_h) or e.un_owner[Ids.slot(u_h)] != p:
			continue
		var w := e.un_w[Ids.slot(u_h)]
		if w < 0:
			continue
		if _assign_one(e, w, source_h):
			done += 1
	return EconApi.Err.OK if done > 0 else -EconApi.Err.INVALID


func _assign_one(e: EconomySim, w: int, source_h: int) -> bool:
	var p := w_owner[w]
	match Ids.kind(source_h):
		Ids.Kind.NODE:
			if not e.nodes.valid(source_h):
				return false
			_leave(e, w)
			w_prev_job[w] = Job.IDLE
			_go_node(e, w, e.nodes.slot(source_h))
			return true
		Ids.Kind.HERD:
			if not e.herds.valid(source_h) or e.herds.owner[e.herds.slot(source_h)] != p:
				return false
			var pen := e.herds.pen_b[e.herds.slot(source_h)]
			return _assign_one(e, w, pen) if e.buildings.valid(pen) else false
		Ids.Kind.BUILDING:
			if not e.buildings.valid(source_h):
				return false
			var b := e.buildings.slot(source_h)
			var B := e.buildings
			if B.owner[b] != p:
				return false
			var bt := B.btype[b]
			if B.state[b] == BuildingTable.State.SITE or (B.state[b] == BuildingTable.State.ACTIVE
					and B.hp_c[b] < B.hp_max_c[b] and B.flags[b] & Defs.BF_UNBREAKABLE == 0 and not e.defs.b_work[bt].has("res")
					and e.defs.b_recipes[bt].is_empty()):
				return send_builders(e, p, PackedInt32Array([w_unit[w]]), source_h) == EconApi.Err.OK
			if not e.active(b):
				return false
			if e.defs.b_kind[bt] == Defs.BKind.FIELD:
				return _go_field(e, w, b)
			if not e.defs.b_work[bt].is_empty():
				return _go_station(e, w, b, Job.TO_PEN)
			if not e.defs.b_recipes[bt].is_empty():
				return _go_station(e, w, b, Job.TO_KILN)
	return false


## Отправить строителей (пусто — ближайший свободный работник игрока)
func send_builders(e: EconomySim, p: int, workers: PackedInt32Array, b_h: int) -> int:
	if not e.buildings.valid(b_h):
		return -EconApi.Err.INVALID
	var b := e.buildings.slot(b_h)
	var list := PackedInt32Array()
	for u_h in workers:
		if e.is_ours(u_h) and e.un_owner[Ids.slot(u_h)] == p and e.un_w[Ids.slot(u_h)] >= 0:
			list.append(e.un_w[Ids.slot(u_h)])
	if workers.is_empty():
		var c := Vector2(e.buildings.x[b], e.buildings.z[b])
		var best := -1
		var bd := INF
		for w in hw:
			if w_unit[w] != 0 and w_owner[w] == p and w_job[w] == Job.IDLE:
				var d := e.port.pos(w_unit[w]).distance_squared_to(c) if e.port else 0.0
				if d < bd:
					bd = d
					best = w
		if best >= 0:
			list.append(best)
	for w in list:
		var j := w_job[w]
		if j in [Job.TO_NODE, Job.GATHER, Job.TO_FIELD, Job.FARM, Job.TO_PEN, Job.HERD, Job.TO_KILN, Job.KILN] or \
				(j == Job.TO_DROP and w_target[w] != 0):
			w_prev_job[w] = j
			w_prev_target[w] = w_target[w]
		elif j != Job.TO_SITE and j != Job.BUILD and j != Job.REPAIR:
			w_prev_job[w] = Job.IDLE
			w_prev_target[w] = 0
		_leave(e, w)
		w_job[w] = Job.TO_SITE
		w_target[w] = b_h
		_go(e, w, e.edge_point(b, _upos(e, w), 0.8))
	return EconApi.Err.OK if not list.is_empty() or workers.is_empty() else -EconApi.Err.INVALID


## Тревога: работники в радиусе от укрытий прячутся у двери; повторно — назад к прежней работе
func alarm(e: EconomySim, p: int, on: bool) -> int:
	if p < 0 or p >= e.players.count:
		return -EconApi.Err.INVALID
	e.p_alarm[p] = 1 if on else 0
	var r := float(e.rule("alarm", "r", 80.0))
	var B := e.buildings
	for w in hw:
		if w_unit[w] == 0 or w_owner[w] != p:
			continue
		if on and w_job[w] != Job.SHELTER:
			var pos := _upos(e, w)
			var best := -1
			var bd := r * r
			for b in B.hw:
				if B.owner[b] == p and e.active(b) and e.defs.b_shelter[B.btype[b]] > B.gar_n[b]:
					var d := Vector2(B.x[b], B.z[b]).distance_squared_to(pos)
					if d < bd:
						bd = d
						best = b
			if best >= 0:
				var j := w_job[w]
				w_prev_job[w] = j if j != Job.TO_DROP else (Job.FARM if Ids.kind(w_target[w]) == Ids.Kind.BUILDING else Job.GATHER)
				w_prev_target[w] = w_target[w]
				_leave(e, w)
				B.gar_n[best] += 1
				w_job[w] = Job.SHELTER
				w_target[w] = B.handle(best)
				_go(e, w, e.door_of(best))
		elif not on and w_job[w] == Job.SHELTER:
			if B.valid(w_target[w]):
				B.gar_n[B.slot(w_target[w])] = maxi(0, B.gar_n[B.slot(w_target[w])] - 1)
			w_job[w] = Job.IDLE
			w_target[w] = 0
			_resume(e, w)
	return EconApi.Err.OK


# ================================================================= такт

func step(e: EconomySim) -> void:
	var t := e.tick
	var w := t % 3
	while w < hw:
		if w_wake[w] <= t and w_unit[w] != 0:
			thinks += 1
			_think(e, w)
		w += 3


func _think(e: EconomySim, w: int) -> void:
	match w_job[w]:
		Job.IDLE, Job.IN_ARBA, Job.SHELTER:
			w_wake[w] = NEVER
		Job.TO_NODE:
			if not e.nodes.valid(w_target[w]):
				_node_lost(e, w)
			elif w_spot[w] < 0:
				var n := e.nodes.slot(w_target[w])
				w_spot[w] = _reserve_node(e, n, _upos(e, w))
				if w_spot[w] >= 0:
					_go(e, w, _node_spot_pos(e, n, w_spot[w]))
				else:
					w_wake[w] = e.tick + BUILD_WAKE
			elif _arrived(e, w):
				_start_gather(e, w)
		Job.GATHER:
			_gather(e, w)
		Job.TO_DROP:
			if not e.buildings.valid(w_drop[w]) or not e.active(e.buildings.slot(w_drop[w])):
				_to_drop(e, w)
			elif _arrived(e, w):
				_deposit(e, w)
		Job.TO_SITE:
			var b_h := w_target[w]
			if not e.buildings.valid(b_h):
				_resume(e, w)
				return
			var b := e.buildings.slot(b_h)
			var st := e.buildings.state[b]
			if st != BuildingTable.State.SITE and not (st == BuildingTable.State.ACTIVE and e.buildings.hp_c[b] < e.buildings.hp_max_c[b]):
				_after_build(e, w, b_h)
			elif _arrived(e, w):
				e.buildings.workers_n[b] += 1
				w_job[w] = Job.BUILD if st == BuildingTable.State.SITE else Job.REPAIR
				w_t[w] = e.tick
				w_wake[w] = e.tick + BUILD_WAKE
				e.port.set_work(w_unit[w], AnimSpec.WORK_BUILD)
		Job.BUILD:
			var b_h := w_target[w]
			if not e.buildings.valid(b_h) or e.buildings.state[e.buildings.slot(b_h)] != BuildingTable.State.SITE:
				if e.buildings.valid(b_h):
					var b := e.buildings.slot(b_h)
					e.buildings.workers_n[b] = maxi(0, e.buildings.workers_n[b] - 1)
				w_job[w] = Job.IDLE
				_after_build(e, w, b_h)
			else:
				w_wake[w] = e.tick + BUILD_WAKE
		Job.REPAIR:
			_repair(e, w)
		Job.TO_FIELD:
			if not e.buildings.valid(w_target[w]) or not e.active(e.buildings.slot(w_target[w])):
				_leave(e, w)
				_set_idle(e, w)
			elif _arrived(e, w):
				w_job[w] = Job.FARM
				w_t[w] = e.tick
				w_mult[w] = _field_mult(e, e.buildings.slot(w_target[w]))
				_wake_full(e, w, _farm_rate(e, w))
				w_wake[w] = mini(w_wake[w], e.tick + 90)
				e.port.set_work(w_unit[w], AnimSpec.WORK_DIG)
		Job.FARM:
			_farm(e, w)
		Job.TO_PEN, Job.TO_KILN:
			if not e.buildings.valid(w_target[w]) or not e.active(e.buildings.slot(w_target[w])):
				_set_idle(e, w)
			elif _arrived(e, w):
				var b := e.buildings.slot(w_target[w])
				var bt := e.buildings.btype[b]
				var cap := int(e.defs.b_work[bt].get("slots", 0)) if w_job[w] == Job.TO_PEN else _kiln_cap(e, b)
				if e.buildings.workers_n[b] >= cap:
					_set_idle(e, w)
				else:
					e.buildings.workers_n[b] += 1
					w_job[w] = Job.HERD if w_job[w] == Job.TO_PEN else Job.KILN
					w_t[w] = e.tick
					w_wake[w] = e.tick + BUILD_WAKE
					e.port.set_work(w_unit[w], -1.0 if w_job[w] == Job.HERD else AnimSpec.WORK_DIG)
		Job.HERD, Job.KILN:
			var b_h := w_target[w]
			if not e.buildings.valid(b_h) or not e.active(e.buildings.slot(b_h)):
				_leave(e, w)
				_set_idle(e, w)
			else:
				w_wake[w] = e.tick + BUILD_WAKE


func _kiln_cap(e: EconomySim, b: int) -> int:
	var rc := e.buildings.recipe[b]
	return e.defs.rc_workers[rc] if rc >= 0 else 0


# ---------------------------------------------------------------- добыча

func _go_node(e: EconomySim, w: int, n: int) -> void:
	var from := _upos(e, w)
	var spot := _reserve_node(e, n, from)
	if spot < 0:
		# все места заняты — ближний такой же узел со свободным местом
		var alt := node_near(e, 1 << e.nodes.res[n], Vector2(e.nodes.x[n], e.nodes.z[n]), NEXT_NODE_R,
			e.nodes.ntype[n], true)
		if alt >= 0:
			n = alt
			spot = _reserve_node(e, n, from)
	w_job[w] = Job.TO_NODE
	w_target[w] = e.nodes.handle(n)
	w_spot[w] = spot
	_go(e, w, _node_spot_pos(e, n, spot) if spot >= 0 else Vector2(e.nodes.x[n], e.nodes.z[n]))
	if w_carry[w] > 0 and w_carry_res[w] != e.nodes.res[n]:
		w_carry[w] = 0           # другая ноша бросается (как в RTS)
		w_frac[w] = 0


func _start_gather(e: EconomySim, w: int) -> void:
	var n := e.nodes.slot(w_target[w])
	var r := e.nodes.res[n]
	w_job[w] = Job.GATHER
	w_t[w] = e.tick
	w_carry_res[w] = r
	w_mult[w] = _gather_mult(e, w_owner[w], r, Vector2(e.nodes.x[n], e.nodes.z[n]))
	_wake_full(e, w, _gather_rate(e, w, r))
	e.port.set_work(w_unit[w], e.defs.n_work_aux[e.nodes.ntype[n]])


## Сырая скорость работника у узла с множителем, микро за такт
func _gather_rate(e: EconomySim, w: int, r: int) -> int:
	var u := w_utype[w]
	if w_mult[w] == 1000:
		return raw[u * e.R + r]
	return rate_for(u, w_cap[w], e.defs.u_gather[u * e.R + r] * 60 * w_mult[w] / 1000)


func _farm_rate(e: EconomySim, w: int) -> int:
	if not e.buildings.valid(w_target[w]):
		return 0
	var u := w_utype[w]
	var bt := e.buildings.btype[e.buildings.slot(w_target[w])]
	if w_mult[w] == 1000:
		return farm_raw[u * e.defs.b_ids.size() + bt]
	return rate_for(u, w_cap[w], int(e.defs.b_work[bt].get("per_worker_min_milli", 0)) * w_mult[w] / 1000)


## Разбудить, когда ноша наполнится (скорость 0 — проверить через 3 с)
func _wake_full(e: EconomySim, w: int, rate: int) -> void:
	if rate <= 0:
		w_wake[w] = e.tick + 90
		return
	var need := (w_cap[w] - w_carry[w]) * 1000 - w_frac[w]
	w_wake[w] = e.tick + maxi(1, (need + rate - 1) / rate) + (w * 13) % JITTER


## Учёт добычи с w_t по сей такт: ноша растёт, запас узла убывает (поле — бесконечно)
func _account(e: EconomySim, w: int, rate: int) -> void:
	var dt := e.tick - w_t[w]
	w_t[w] = e.tick
	if dt <= 0 or rate <= 0:
		return
	var micro := rate * dt + w_frac[w]
	var milli := micro / 1000
	w_frac[w] = micro % 1000
	var room := w_cap[w] - w_carry[w]
	if milli >= room:
		milli = room
		w_frac[w] = 0
	if w_job[w] == Job.GATHER and e.nodes.valid(w_target[w]):
		var n := e.nodes.slot(w_target[w])
		var left := e.nodes.amount_milli[n]
		if left >= 0:
			milli = mini(milli, left)
			e.nodes.amount_milli[n] = left - milli
	w_carry[w] += milli


## Множитель добычи: Кен (+50% в 26 м от жилы) × множитель игрока (PlayerTable.Stat.GATHER)
func _gather_mult(e: EconomySim, p: int, r: int, at: Vector2) -> int:
	var m := 1000
	var B := e.buildings
	for b in B.hw:
		if B.owner[b] != p or not e.active(b):
			continue
		var au: Dictionary = e.defs.b_aura[B.btype[b]]
		if au.is_empty() or int(au["res_mask"]) & (1 << r) == 0:
			continue
		var rr := float(au["r"])
		if Vector2(B.x[b], B.z[b]).distance_squared_to(at) <= rr * rr:
			m = maxi(m, roundi(float(au["gather_mult"]) * 1000.0))
	return m * e.mods.gather_milli(e, p) / 1000


func _gather(e: EconomySim, w: int) -> void:
	var N := e.nodes
	if not N.valid(w_target[w]):
		_node_lost(e, w)
		return
	var n := N.slot(w_target[w])
	var rate := _gather_rate(e, w, N.res[n])
	_account(e, w, rate)
	if N.amount_milli[n] == 0:
		_deplete(e, n)
		_to_drop(e, w)
	elif w_carry[w] >= w_cap[w]:
		_to_drop(e, w)
	else:
		_wake_full(e, w, rate)


func _node_lost(e: EconomySim, w: int) -> void:
	# узел выработан или исчез: ноша — на склад, потом ближний такой же
	w_spot[w] = -1
	if w_carry[w] > 0:
		_to_drop(e, w)
		return
	_next_node(e, w)


func _next_node(e: EconomySim, w: int) -> void:
	var r := w_carry_res[w]
	var pos := _upos(e, w)
	var n := node_near(e, 1 << r, pos, NEXT_NODE_R, -1, true) if r >= 0 else -1
	if n < 0:
		_set_idle(e, w)
		return
	_go_node(e, w, n)


# ---------------------------------------------------------------- склад

func _to_drop(e: EconomySim, w: int) -> void:
	var r := w_carry_res[w]
	var carry_to := PackedInt32Array()
	if Ids.kind(w_target[w]) == Ids.Kind.BUILDING and e.buildings.valid(w_target[w]):
		var wkd: Dictionary = e.defs.b_work[e.buildings.btype[e.buildings.slot(w_target[w])]]
		carry_to = wkd.get("carry_to", PackedInt32Array())
	var pos := _upos(e, w)
	var best := -1
	var bd := INF
	for b in e.drops_of(w_owner[w]):
		if e.buildings.store_mask[b] & (1 << r) == 0:
			continue
		if not carry_to.is_empty() and not carry_to.has(e.buildings.btype[b]):
			continue
		var d := e.rect_dist2(b, pos)
		if d < bd:
			bd = d
			best = b
	if best < 0:
		# склада нет — ждать с ношей
		w_job[w] = Job.TO_DROP
		w_drop[w] = 0
		w_wake[w] = e.tick + 90
		if (e.tick - w_t[w]) % 900 < 90:
			e.events.push(SimEvents.Ev.WORKER_IDLE, w_owner[w], w_unit[w], 0, 0, pos)
		return
	w_job[w] = Job.TO_DROP
	w_drop[w] = e.buildings.handle(best)
	_go(e, w, e.edge_point(best, pos, 1.0))
	e.port.set_work(w_unit[w], AnimSpec.WORK_CARRY)


func _deposit(e: EconomySim, w: int) -> void:
	var b := e.buildings.slot(w_drop[w])
	var p := w_owner[w]
	var r := w_carry_res[w]
	if w_carry[w] > 0 and r >= 0:
		e.add_res(p, r, w_carry[w])
		e.events.push(SimEvents.Ev.RES_DELIVERED, p, r, w_carry[w], w_drop[w], Vector2(e.buildings.x[b], e.buildings.z[b]))
	w_carry[w] = 0
	w_drop[w] = 0
	e.port.set_work(w_unit[w], -1.0)
	var t := w_target[w]
	match Ids.kind(t):
		Ids.Kind.NODE:
			if e.nodes.valid(t) and w_spot[w] >= 0:
				var n := e.nodes.slot(t)
				w_job[w] = Job.TO_NODE
				_go(e, w, _node_spot_pos(e, n, w_spot[w]))
			else:
				w_spot[w] = -1
				w_target[w] = 0
				_next_node(e, w)
		Ids.Kind.BUILDING:
			if e.buildings.valid(t) and e.active(e.buildings.slot(t)) and w_spot[w] >= 0:
				var f := e.buildings.slot(t)
				w_job[w] = Job.TO_FIELD
				_go(e, w, _field_slot_pos(e, f, w_spot[w]))
			else:
				_leave(e, w)
				_set_idle(e, w)
		_:
			_set_idle(e, w)


# ---------------------------------------------------------------- поле

func _go_field(e: EconomySim, w: int, b: int) -> bool:
	var slots := e.defs.b_work_slots[e.buildings.btype[b]]
	var s := -1
	for k in mini(slots, FIELD_SLOTS.size()):
		if e.b_slots[b] & (1 << k) == 0:
			s = k
			break
	if s < 0:
		return false
	_leave(e, w)
	w_prev_job[w] = Job.IDLE
	e.b_slots[b] |= 1 << s
	e.buildings.workers_n[b] += 1
	w_job[w] = Job.TO_FIELD
	w_target[w] = e.buildings.handle(b)
	w_spot[w] = s
	var wkd: Dictionary = e.defs.b_work[e.buildings.btype[b]]
	if w_carry_res[w] != int(wkd["res"]):
		w_carry[w] = 0
		w_frac[w] = 0
	w_carry_res[w] = int(wkd["res"])
	_go(e, w, _field_slot_pos(e, b, s))
	return true


func _field_slot_pos(e: EconomySim, b: int, s: int) -> Vector2:
	var half := e.half_of(b)
	var off: Vector2 = FIELD_SLOTS[s % FIELD_SLOTS.size()]
	off = Vector2(off.x * half.x / 8.0, off.y * half.y / 8.0)
	return Vector2(e.buildings.x[b], e.buildings.z[b]) + off


## Множитель поля: выход по полям карты (вода: «лалми» 25%), вытоптано — 0
func _field_mult(e: EconomySim, b: int) -> int:
	if e.b_cd2[b] > e.tick:
		return 0
	var m := 1000
	for y: Dictionary in e.defs.b_yield[e.buildings.btype[b]]:
		if not bool(y["enabled"]):
			continue
		var v := e.b_water[b] if y["field"] == "water" else e.fld.grass_at(e, Vector2(e.buildings.x[b], e.buildings.z[b]))
		if v < int(y["below"]):
			m = m * roundi(float(y["mul"]) * 1000.0) / 1000
	return m * e.mods.gather_milli(e, w_owner_of_field(e, b)) / 1000


func w_owner_of_field(e: EconomySim, b: int) -> int:
	return e.buildings.owner[b]


func _farm(e: EconomySim, w: int) -> void:
	var t := w_target[w]
	if not e.buildings.valid(t) or not e.active(e.buildings.slot(t)):
		_leave(e, w)
		_set_idle(e, w)
		return
	var b := e.buildings.slot(t)
	_account(e, w, _farm_rate(e, w))
	w_mult[w] = _field_mult(e, b)            # вода и пар меняются — пересчёт на каждом пробуждении
	if w_carry[w] >= w_cap[w]:
		_to_drop(e, w)
	else:
		_wake_full(e, w, _farm_rate(e, w))
		w_wake[w] = mini(w_wake[w], e.tick + 90)


# ---------------------------------------------------------------- загон, печь

func _go_station(e: EconomySim, w: int, b: int, job: int) -> bool:
	_leave(e, w)
	w_prev_job[w] = Job.IDLE
	w_job[w] = job
	w_target[w] = e.buildings.handle(b)
	w_spot[w] = -1
	_go(e, w, e.edge_point(b, _upos(e, w), 1.0) if job == Job.TO_PEN else e.door_of(b))
	return true


# ---------------------------------------------------------------- стройка и ремонт

func _after_build(e: EconomySim, w: int, b_h: int) -> void:
	var B := e.buildings
	e.port.set_work(w_unit[w], -1.0)
	if B.valid(b_h):
		var b := B.slot(b_h)
		var bt := B.btype[b]
		# звено за звеном: следующее звено той же цепочки
		if B.chain[b] != 0:
			var nxt := _next_link(e, b)
			if nxt >= 0:
				w_job[w] = Job.TO_SITE
				w_target[w] = B.handle(nxt)
				_go(e, w, e.edge_point(nxt, _upos(e, w), 0.8))
				return
		if e.active(b) and w_prev_job[w] == Job.IDLE:
			if e.defs.b_kind[bt] == Defs.BKind.FIELD and _go_field(e, w, b):
				return
			if not e.defs.b_recipes[bt].is_empty() and B.workers_n[b] < _kiln_cap(e, b):
				_go_station(e, w, b, Job.TO_KILN)
				return
			if B.flags[b] & Defs.BF_DROP and B.flags[b] & Defs.BF_HQ == 0:
				var mask := B.store_mask[b] & ~(1 << e.r_food)
				var n := node_near(e, mask, Vector2(B.x[b], B.z[b]), AUTO_GATHER_R, -1, true)
				if n >= 0:
					_go_node(e, w, n)
					return
	_resume(e, w)


func _next_link(e: EconomySim, b: int) -> int:
	var B := e.buildings
	var best := -1
	var bd := INF
	var c := Vector2(B.x[b], B.z[b])
	for k in B.hw:
		if k != b and B.chain[k] == B.chain[b] and B.owner[k] == B.owner[b] and B.state[k] == BuildingTable.State.SITE:
			var d := Vector2(B.x[k], B.z[k]).distance_squared_to(c)
			if d < bd:
				bd = d
				best = k
	return best


## Прежняя работа (TZ: «возвращается к прежней работе»), иначе IDLE
func _resume(e: EconomySim, w: int) -> void:
	var j := w_prev_job[w]
	var t := w_prev_target[w]
	w_prev_job[w] = Job.IDLE
	w_prev_target[w] = 0
	w_job[w] = Job.IDLE
	w_target[w] = 0
	if j != Job.IDLE and t != 0 and _assign_one(e, w, t):
		return
	_set_idle(e, w)


## Ремонт целого здания: скорость стройки, цена — repair_cost × цена × доля HP (Ҳашар — вдвое дешевле)
func _repair(e: EconomySim, w: int) -> void:
	var B := e.buildings
	var t := w_target[w]
	if not B.valid(t) or B.state[B.slot(t)] != BuildingTable.State.ACTIVE:
		if B.valid(t):
			B.workers_n[B.slot(t)] = maxi(0, B.workers_n[B.slot(t)] - 1)
		_resume(e, w)
		return
	var b := B.slot(t)
	var bt := B.btype[b]
	var bticks := maxi(e.defs.b_build_ticks[bt], 30)
	var dt := maxi(e.tick - w_t[w], 0)
	w_t[w] = e.tick
	w_wake[w] = e.tick + BUILD_WAKE
	var dhp := B.hp_max_c[b] * dt * e.mods.build_milli(e, w_owner[w]) / 1000 / bticks
	dhp = mini(dhp, B.hp_max_c[b] - B.hp_c[b])
	var rc := roundi(float(e.rules.get("repair_cost", 0.5)) * 1000.0) * e.mods.repair_cost_milli(e, w_owner[w]) / 1000
	var cost := e.defs.building_cost(bt)
	for r in e.R:
		cost[r] = int(cost[r] * rc / 1000 * dhp / maxi(B.hp_max_c[b], 1))
	if not e.can_pay(w_owner[w], cost):
		B.workers_n[b] = maxi(0, B.workers_n[b] - 1)
		_set_idle(e, w)
		return
	e.pay(w_owner[w], cost)
	B.hp_c[b] += dhp
	if B.hp_c[b] >= B.hp_max_c[b]:
		B.workers_n[b] = maxi(0, B.workers_n[b] - 1)
		_resume(e, w)


# ================================================================= общее

func on_building_gone(e: EconomySim, b: int) -> void:
	pass   # работники видят недействительный описатель на своей мысли


## Уйти с текущей работы: освободить место у узла/поля, счётчик здания
func _leave(e: EconomySim, w: int) -> void:
	var t := w_target[w]
	var j := w_job[w]
	if j == Job.GATHER and e.nodes.valid(t):
		_account(e, w, _gather_rate(e, w, e.nodes.res[e.nodes.slot(t)]))
		if e.nodes.amount_milli[e.nodes.slot(t)] == 0:
			_deplete(e, e.nodes.slot(t))
	elif j == Job.FARM:
		_account(e, w, _farm_rate(e, w))
	match Ids.kind(t):
		Ids.Kind.NODE:
			if w_spot[w] >= 0 and e.nodes.valid(t):
				var n := e.nodes.slot(t)
				n_spots[n] &= ~(1 << w_spot[w])
				e.nodes.workers_n[n] = maxi(0, e.nodes.workers_n[n] - 1)
		Ids.Kind.BUILDING:
			if e.buildings.valid(t):
				var b := e.buildings.slot(t)
				if (j == Job.TO_FIELD or j == Job.FARM or j == Job.TO_DROP) and w_spot[w] >= 0:
					e.b_slots[b] &= ~(1 << w_spot[w])
					e.buildings.workers_n[b] = maxi(0, e.buildings.workers_n[b] - 1)
				elif j == Job.BUILD or j == Job.REPAIR or j == Job.HERD or j == Job.KILN:
					e.buildings.workers_n[b] = maxi(0, e.buildings.workers_n[b] - 1)
				elif j == Job.SHELTER:
					e.buildings.gar_n[b] = maxi(0, e.buildings.gar_n[b] - 1)
	w_spot[w] = -1
	w_drop[w] = 0


func _set_idle(e: EconomySim, w: int) -> void:
	var was := w_job[w]
	w_job[w] = Job.IDLE
	w_target[w] = 0
	w_spot[w] = -1
	w_wake[w] = NEVER
	if e.port:
		e.port.set_work(w_unit[w], -1.0)
	if was != Job.IDLE:
		e.events.push(SimEvents.Ev.WORKER_IDLE, w_owner[w], w_unit[w], 0, 0, _upos(e, w))


## Идти к точке; думать — не раньше расчётного прибытия (прямая / скорость)
func _go(e: EconomySim, w: int, to: Vector2) -> void:
	w_tx[w] = to.x
	w_tz[w] = to.y
	w_t[w] = e.tick
	w_retry[w] = 0
	var eta := 0
	if e.port:
		var from := e.port.pos(w_unit[w])
		eta = int(from.distance_to(to) / speed[w_utype[w]] * 30.0)
		e.port.move(PackedInt32Array([w_unit[w]]), to, RUN)
	w_wake[w] = e.tick + maxi(MIN_MOVE_T, eta - 2)


func _arrived(e: EconomySim, w: int) -> bool:
	if e.tick - w_t[w] < MIN_MOVE_T:
		return false
	var u := w_unit[w]
	var goal := Vector2(w_tx[w], w_tz[w])
	if not e.port.is_idle(u):
		if e.tick - w_t[w] > RETRY_T:
			_go(e, w, goal)
		return false
	var p := e.port.pos(u)
	if p.distance_squared_to(goal) <= ARRIVE_R * ARRIVE_R:
		return true
	# встал не там (путь до ближайшей проходимой клетки) — повторить, потом принять
	w_retry[w] += 1
	if w_retry[w] > 2:
		return true
	var r := w_retry[w]
	_go(e, w, goal)
	w_retry[w] = r
	return false


func _upos(e: EconomySim, w: int) -> Vector2:
	return e.port.pos(w_unit[w]) if e.port else Vector2(w_tx[w], w_tz[w])
