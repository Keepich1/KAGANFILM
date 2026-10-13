class_name RaidDirector
extends AiController
## Набеги ИИ (ТЗ 7; ARCHITECTURE §12; ECONOMY §10): мирный период 5 / 8 / 12 мин (AiDefs.RAID.peace_s по
## сложности), потом волна каждые 150–240 с, каждая в growth (×1,25) крупнее, до max_wave.
##   PEACE / COOLDOWN — ждём; за warn_s до волны — RAID_WARNING(eta) игроку-цели.
##   MUSTER   — волна даром (Op.SPAWN, rules.ai_free_waves) у края карты (raid_edges) с офицером на отряд;
##              RAID_STARTED. Юниты волны узнаём по UNIT_SPAWNED (b = 0) своего игрока.
##   MARCH    — ATTACK_MOVE к цели: клетка 32 м с наибольшим «ценность минус риск» (ECONOMY §10):
##              работник 10, табун 20 × коней, дом 20, тўғон 100 × полей, склад 10% запаса (талоо),
##              прочее — raid_value постройки; минус охрана и башни в risk_r (60 м); клетка пропускается,
##              если охраны больше skip_guard × волну. Ничья — меньший номер клетки.
##   STRIKE   — каждый отряд бьёт ближайшего работника (по одному на отряд), иначе идёт к отаре/табуну
##              (угон — ECON, по близости налётчиков; охраняемое 20 с — бросает), иначе ломает постройки:
##              поля, склады и тўғон, прочие, укрепления, ставка — последней и только у волн от HQ_MIN_WAVE;
##              целей рядом нет — новая цель по карте ценности.
##   RETREAT  — потери ≥ retreat.losses, охраны в 1,5 раза больше, предел времени набега, выносливость в бою
##              ниже retreat.stamina, угнанное стадо или целей нет (retreat_why):
##              назад к краю; дошедшие уходят из мира (NOTE_REMOVE; ECON зачитывает угнанное), RAID_ENDED.
## Только чтение GameQuery и приказы; события — через notes (пишет GameSim).

enum Phase { PEACE, MUSTER, MARCH, STRIKE, RETREAT, COOLDOWN }
## Почему волна ушла (последний отход; для тестов и записок)
enum Why { NONE, LOSSES, TIME, OUTNUMBERED, STAMINA, LOOT, NO_TARGET }

const CELL := 32.0
const STRIKE_R := 70.0           # цели удара — в этом радиусе от середины волны
const ARRIVE_R := 45.0           # дошли до цели
const EDGE_R := 30.0             # дошли до края карты
const EDGE_DIST := 300.0         # край выбирается на таком расстоянии от цели, м
const MUSTER_MAX_T := 150        # тактов ждём появления волны
const RETREAT_MAX_T := 3600      # отход дольше 2 мин — остаток уходит с карты
const MIN_GAP_T := 900           # между концом набега и следующей волной не меньше 30 с
const DEFENDER_PTS := 50         # охранник в risk_r, деци-очки
const HQ_PTS := 10               # ставка — последняя цель
const HQ_MIN_WAVE := 60          # ставку бьют только поздние большие волны (раньше набег — по хозяйству)
const HERD_GIVE_UP_T := 600      # стадо стоит у загона 20 с после первого приказа — охраняют, бросаем

var state := Phase.PEACE
var wave := 0                    # номер последней волны (1…)
var next_wave_t := 0
var warned := false
var scale_milli := 1000
var enemy := -1
var edge := Vector2.ZERO
var target := Vector2.ZERO
var wave_units := PackedInt32Array()
var size0 := 0
var expect := 0
var start_t := 0
var phase_t := 0
var survivors := 0
var retreat_why := Why.NONE
## Счётчики для тестов: приказы удара по видам целей
var strikes_worker := 0
var strikes_herd := 0
var strikes_building := 0

var _raid := {}
var _faction := -1
var _edges := PackedVector2Array()
var _bounds := Rect2(-512, -512, 1024, 1024)
var _cursor := 0
var _orders := {}                # отряд → цель (описатель), порядок вставки детерминирован
var _herd_t := {}                # стадо → такт первого приказа на угон
var _buf := PackedInt32Array()
var _growth_milli := 1250
var _losses_milli := 400
var _outnumbered_milli := 1500
var _skip_guard_milli := 1500
var _risk_r := 60.0
var _tower_pen := 400            # деци-очки
var _v_worker := 100
var _v_horse := 200
var _v_house := 200
var _v_togon := 1000
var _taloo_pm := 100             # промилле запаса
var _interval := Vector2i(4500, 7200)


## params: {raid (скомпилированный AiDefs.RAID), difficulty, faction (индекс Defs), edges, bounds, enemy, phase}
func setup(p_player: int, p_params: Dictionary, p_seed: int) -> void:
	var prm := p_params.duplicate()
	_raid = prm.get("raid", {})
	if not prm.has("period"):
		prm["period"] = int(_raid.get("period", 30))
	super.setup(p_player, prm, p_seed)
	_faction = int(prm.get("faction", -1))
	_edges = prm.get("edges", PackedVector2Array())
	_bounds = prm.get("bounds", _bounds)
	enemy = int(prm.get("enemy", -1))
	var diff := clampi(int(prm.get("difficulty", 0)), 0, 2)
	var peace: Array = _raid.get("peace_ticks", [9000, 14400, 21600])
	next_wave_t = int(peace[mini(diff, peace.size() - 1)])
	var iv: Array = _raid.get("interval_ticks", [4500, 7200])
	_interval = Vector2i(int(iv[0]), int(iv[1]))
	_growth_milli = roundi(float(_raid.get("growth", 1.25)) * 1000.0)
	var rt: Dictionary = _raid.get("retreat", {})
	_losses_milli = roundi(float(rt.get("losses", 0.4)) * 1000.0)
	_outnumbered_milli = roundi(float(rt.get("outnumbered", 1.5)) * 1000.0)
	_skip_guard_milli = roundi(float(_raid.get("skip_guard", 1.5)) * 1000.0)
	_risk_r = float(_raid.get("risk_r", 60.0))
	_tower_pen = roundi(float(_raid.get("tower_penalty", 40.0)) * 10.0)
	var v: Dictionary = _raid.get("values", {})
	_v_worker = roundi(float(v.get("worker", 10.0)) * 10.0)
	_v_horse = roundi(float(v.get("horse", 20.0)) * 10.0)
	_v_house = roundi(float(v.get("house", 20.0)) * 10.0)
	_v_togon = roundi(float(v.get("togon_per_field", 100.0)) * 10.0)
	_taloo_pm = roundi(float(v.get("taloo_frac", 0.1)) * 1000.0)


## Тактов до следующей волны против игрока p: −1 — не ждём, 0 — набег идёт
func eta_for(p: int, tick: int) -> int:
	if p != enemy:
		return -1
	if state == Phase.PEACE or state == Phase.COOLDOWN:
		return maxi(next_wave_t - tick, 0)
	return 0


func think(tick: int, q: GameQuery, out: Array[PackedInt32Array]) -> void:
	var gq := q as GameQueryImpl
	if gq == null or gq.is_defeated(player):
		return
	match state:
		Phase.PEACE, Phase.COOLDOWN:
			if enemy < 0 or gq.is_defeated(enemy):
				enemy = AiController.enemy_of(q, player)
			if not warned and enemy >= 0 and tick >= next_wave_t - int(_raid.get("warn_ticks", 900)):
				warned = true
				note_event(SimEvents.Ev.RAID_WARNING, enemy, next_wave_t - tick, player, wave + 1, edge)
			if tick >= next_wave_t:
				_muster(tick, gq, out)
		Phase.MUSTER:
			_collect(gq)
			if wave_units.size() >= expect or tick - phase_t >= MUSTER_MAX_T:
				_march(tick, gq, out)
		Phase.MARCH:
			_prune(gq)
			var why := _should_retreat(tick, gq, false)
			if why != Why.NONE:
				_retreat(tick, gq, out, why)
			elif _centroid(gq).distance_squared_to(target) <= ARRIVE_R * ARRIVE_R:
				state = Phase.STRIKE
				phase_t = tick
				_strike(tick, gq, out)
			elif _all_idle(gq):
				emit(out, SimCmd.attack_move(wave_units, target))
		Phase.STRIKE:
			_prune(gq)
			var why := _should_retreat(tick, gq, true)
			if why != Why.NONE:
				_retreat(tick, gq, out, why)
			else:
				_strike(tick, gq, out)
		Phase.RETREAT:
			_prune(gq)
			_retreating(tick, gq, out)


func checksum() -> int:
	var h := super.checksum()
	for v in [state, wave, next_wave_t, scale_milli, enemy, size0, survivors, SimCmd.cm(target.x), SimCmd.cm(target.y)]:
		h = AiController.mix(h, v)
	for u in wave_units:
		h = AiController.mix(h, u)
	return h


# ================================================================= фазы

func _muster(tick: int, gq: GameQueryImpl, out: Array[PackedInt32Array]) -> void:
	if enemy < 0 or not bool(gq.rules().get("ai_free_waves", false)):
		next_wave_t = tick + _next_interval()     # TODO(ТЗ 16.2): волны из своего войска, когда будет экономика ИИ
		warned = false
		return
	wave += 1
	if wave > 1:
		scale_milli = scale_milli * _growth_milli / 1000
	var comp := _composition(gq.defs())
	var total := 0
	for i in range(1, comp.size(), 2):
		total += comp[i]
	if not _pick_target(gq, total):
		var hq := AiController.hq_pos(gq, enemy)
		target = hq if hq != Vector2.INF else _bounds.get_center()
	edge = _pick_edge(target)
	var heading := AiController.cardinal(target - edge)
	var side := _side_of(heading)
	var officer: int = gq.defs().f_officer[_faction] if _faction >= 0 else -1
	var per := maxi(1, int(_raid.get("officer_per", 100)))
	expect = 0
	var k := 0
	for i in range(0, comp.size(), 2):
		var left := comp[i + 1]
		while left > 0:
			var n := mini(left, per)
			left -= n
			var at := edge + side * (k * 14.0 - 7.0 * float(comp.size() / 2 - 1))
			emit(out, SimCmd.spawn(comp[i], n, at, heading, officer))
			expect += n + (1 if officer >= 0 else 0)
			k += 1
	wave_units.clear()
	_orders.clear()
	_herd_t.clear()
	size0 = 0
	survivors = 0
	_cursor = gq.events().head
	state = Phase.MUSTER
	phase_t = tick
	start_t = tick
	note_event(SimEvents.Ev.RAID_STARTED, enemy, player, total, wave, edge)


func _collect(gq: GameQueryImpl) -> void:
	var E := gq.events()
	var r := E.range_since(_cursor)
	var kind := E.e_kind
	var pl := E.e_player
	var ea := E.e_a
	var eb := E.e_b
	for seq in range(r.x, r.y):
		var i := E.at(seq)
		if kind[i] == SimEvents.Ev.UNIT_SPAWNED and pl[i] == player and eb[i] == Ids.NULL:
			# работники (ECON.spawn_worker тоже пишет b = 0) и арбы — не волна
			if gq.unit_flags(ea[i]) & (UnitStats.WORKER | UnitStats.WAGON) == 0 and not wave_units.has(ea[i]):
				wave_units.append(ea[i])
	_cursor = r.y


func _march(tick: int, gq: GameQueryImpl, out: Array[PackedInt32Array]) -> void:
	_collect(gq)
	_prune(gq)
	size0 = wave_units.size()
	if size0 == 0:
		_end_raid(tick)
		return
	if not _pick_target(gq, size0):
		_retreat(tick, gq, out, Why.NO_TARGET)
		return
	emit(out, SimCmd.attack_move(wave_units, target))
	state = Phase.MARCH
	phase_t = tick


func _strike(tick: int, gq: GameQueryImpl, out: Array[PackedInt32Array]) -> void:
	var c := _centroid(gq)
	var my_team := gq.players().team[player]
	# работники врага рядом
	var workers := PackedInt32Array()
	gq.units_near(my_team, c, STRIKE_R, true, UnitStats.WORKER, _buf)
	for u in _buf:
		if gq.unit_owner(u) == enemy:
			workers.append(u)
	var herds := PackedInt32Array()
	for hh in _herds_near(gq, c):
		if tick - int(_herd_t.get(hh, tick)) < HERD_GIVE_UP_T:
			herds.append(hh)
	var blds := _buildings_near(gq, c)
	# угнанное стадо уже идёт за нашими — уводим добычу
	if _has_loot(gq):
		_retreat(tick, gq, out, Why.LOOT)
		return
	if workers.is_empty() and herds.is_empty() and blds.is_empty():
		if _pick_target(gq, wave_units.size()):
			emit(out, SimCmd.attack_move(wave_units, target))
			state = Phase.MARCH
			phase_t = tick
		else:
			_retreat(tick, gq, out, Why.NO_TARGET)
		return
	var taken := {}
	for s in _wave_squads(gq):
		var cur: int = _orders.get(s, Ids.NULL)
		if cur != Ids.NULL and _target_alive(gq, cur) and not gq.is_idle(s):
			taken[cur] = true
			continue
		var sp := gq.unit_pos(s)
		var pick := _nearest_free(gq, workers, sp, taken)
		if pick != Ids.NULL:
			strikes_worker += 1
			emit(out, SimCmd.attack(PackedInt32Array([s]), pick, true))
		elif not herds.is_empty():
			pick = herds[0]
			for hh in herds:
				if not taken.has(hh):
					pick = hh
					break
			strikes_herd += 1
			if not _herd_t.has(pick):
				_herd_t[pick] = tick
			var H := gq.herds()
			var hs := H.slot(pick)
			emit(out, SimCmd.move(PackedInt32Array([s]), Vector2(H.x[hs], H.z[hs]), true))
		elif not blds.is_empty():
			pick = blds[0]
			strikes_building += 1
			emit(out, SimCmd.attack(PackedInt32Array([s]), pick, true))
		if pick != Ids.NULL:
			taken[pick] = true
			_orders[s] = pick


func _retreat(tick: int, gq: GameQueryImpl, out: Array[PackedInt32Array], why: int) -> void:
	retreat_why = why
	state = Phase.RETREAT
	phase_t = tick
	_orders.clear()
	if not wave_units.is_empty():
		emit(out, SimCmd.move(wave_units, edge, true))


func _retreating(tick: int, gq: GameQueryImpl, out: Array[PackedInt32Array]) -> void:
	var gone := PackedInt32Array()
	var stay := PackedInt32Array()
	var all := tick - phase_t >= RETREAT_MAX_T
	for u in wave_units:
		if all or gq.unit_pos(u).distance_squared_to(edge) <= EDGE_R * EDGE_R:
			gone.append(u)
		else:
			stay.append(u)
	survivors += gone.size()
	note_remove(gone)
	wave_units = stay
	if wave_units.is_empty():
		_end_raid(tick)
	elif _all_idle(gq):
		emit(out, SimCmd.move(wave_units, edge, true))


func _end_raid(tick: int) -> void:
	note_event(SimEvents.Ev.RAID_ENDED, enemy, player, survivors, wave, edge)
	state = Phase.COOLDOWN
	phase_t = tick
	warned = false
	wave_units.clear()
	_orders.clear()
	next_wave_t = maxi(start_t + _next_interval(), tick + MIN_GAP_T)


## Причина уйти (Why.NONE — остаёмся). Выносливость — только в бою (striking): на марше бегом она
## падает у всех, это не повод разворачиваться.
func _should_retreat(tick: int, gq: GameQueryImpl, striking: bool) -> int:
	var alive := wave_units.size()
	if alive == 0 or alive * 1000 <= size0 * (1000 - _losses_milli):
		return Why.LOSSES
	var rt: Dictionary = _raid.get("retreat", {})
	if tick - start_t >= int(rt.get("time_ticks", 7200)):
		return Why.TIME
	var c := _centroid(gq)
	var my_team := gq.players().team[player]
	gq.units_near(my_team, c, _risk_r, true, 0, _buf)
	var guards := 0
	for u in _buf:
		if gq.unit_flags(u) & (UnitStats.WORKER | UnitStats.WAGON) == 0:
			guards += 1
	if guards * 1000 >= alive * _outnumbered_milli:
		return Why.OUTNUMBERED
	# выносливость отрядов (ядро; на заглушке её нет)
	var sim := gq.battle()
	if striking and sim != null:
		var stam_lim := float(rt.get("stamina", 30.0))
		var sum := 0.0
		var k := 0
		var stam := sim.sq_stam
		for s in _wave_squads(gq):
			var i := Ids.slot(s)
			if i < stam.size():
				sum += stam[i]
				k += 1
		if k > 0 and sum / k < stam_lim:
			return Why.STAMINA
	return Why.NONE


# ================================================================= выбор цели (карта ценности, ECONOMY §10)

func _pick_target(gq: GameQueryImpl, wave_size: int) -> bool:
	if enemy < 0:
		return false
	var defs := gq.defs()
	var gw := ceili(_bounds.size.x / CELL)
	var gh := ceili(_bounds.size.y / CELL)
	var val := PackedInt32Array()
	val.resize(gw * gh)
	var best_v := PackedInt32Array()
	best_v.resize(gw * gh)
	var best_p := PackedVector2Array()
	best_p.resize(gw * gh)
	var guard := PackedInt32Array()
	guard.resize(gw * gh)
	var tower := PackedInt32Array()
	tower.resize(gw * gh)
	# юниты врага: работники — ценность, бойцы — охрана
	for u in gq.units_of(enemy):
		var f := gq.unit_flags(u)
		var p := gq.unit_pos(u)
		var c := _cell(p, gw, gh)
		if c < 0:
			continue
		if f & UnitStats.WORKER:
			_add(val, best_v, best_p, c, _v_worker, p)
		elif f & UnitStats.WAGON == 0:
			guard[c] += 1
	# постройки
	var B := gq.buildings()
	var bstate := B.state
	var bowner := B.owner
	var btype := B.btype
	var bx := B.x
	var bz := B.z
	var fields := 0
	for b in B.hw:
		if bowner[b] == enemy and bstate[b] == BuildingTable.State.ACTIVE and defs.b_kind[btype[b]] == Defs.BKind.FIELD:
			fields += 1
	for b in B.hw:
		if bowner[b] != enemy or (bstate[b] != BuildingTable.State.ACTIVE and bstate[b] != BuildingTable.State.SITE):
			continue
		var p := Vector2(bx[b], bz[b])
		var c := _cell(p, gw, gh)
		if c < 0:
			continue
		var bt := btype[b]
		if defs.b_kind[bt] == Defs.BKind.TOWER:
			if bstate[b] == BuildingTable.State.ACTIVE:
				tower[c] += 1
			continue
		_add(val, best_v, best_p, c, _building_value(gq, b, bt, fields, wave_size), p)
	# стада
	var H := gq.herds()
	for h in H.hw:
		if H.owner[h] != enemy or H.state[h] != HerdTable.State.PEN:
			continue
		var p := Vector2(H.x[h], H.z[h])
		var c := _cell(p, gw, gh)
		if c < 0:
			continue
		var heads := H.heads(h)
		var v := heads * _v_horse if defs.h_backing[H.htype[h]] >= 0 else heads * 25 / 10
		_add(val, best_v, best_p, c, v, p)
	# счёт: ценность − охрана − башни в risk_r; охраны больше skip_guard × волну — мимо
	var rc := ceili(_risk_r / CELL)
	var r2 := _risk_r * _risk_r
	var best := -1
	var best_score := 0
	for c in gw * gh:
		if val[c] <= 0:
			continue
		var cc := best_p[c]
		var cx := c % gw
		var cz := c / gw
		var g := 0
		var t := 0
		for dz in range(-rc, rc + 1):
			var z := cz + dz
			if z < 0 or z >= gh:
				continue
			for dx in range(-rc, rc + 1):
				var x := cx + dx
				if x < 0 or x >= gw:
					continue
				var k := z * gw + x
				if guard[k] == 0 and tower[k] == 0:
					continue
				var center := _bounds.position + (Vector2(x, z) + Vector2(0.5, 0.5)) * CELL
				if center.distance_squared_to(cc) <= r2:
					g += guard[k]
					t += tower[k]
		if g * 1000 >= _skip_guard_milli * maxi(wave_size, 1):
			continue
		var score := val[c] - g * DEFENDER_PTS - t * _tower_pen
		if score > best_score:
			best_score = score
			best = c
	if best < 0:
		return false
	target = best_p[best]
	return true


func _building_value(gq: GameQueryImpl, b: int, bt: int, fields: int, wave_size: int) -> int:
	var defs := gq.defs()
	var flags := defs.b_flags[bt]
	if flags & Defs.BF_HQ:
		return HQ_PTS if wave_size >= HQ_MIN_WAVE else 0
	if defs.b_kind[bt] == Defs.BKind.DAM:
		return maxi(_v_togon * mini(fields, 8), defs.b_raid_value[bt] * 2)
	if flags & Defs.BF_HOUSE:
		return _v_house
	if flags & Defs.BF_DROP:
		# талоо: доля запаса тех ресурсов, что принимает склад (в очках = единицах ресурса), до 300
		var P := gq.players()
		var stock := 0
		var mask := defs.b_accepts[bt]
		for r in defs.R:
			if mask & (1 << r):
				stock += int(P.res[enemy * P.R + r] / 1000)
		return mini(stock * _taloo_pm / 1000, 300) * 10 + defs.b_raid_value[bt] * 2
	return defs.b_raid_value[bt] * 2


func _add(val: PackedInt32Array, best_v: PackedInt32Array, best_p: PackedVector2Array, c: int, v: int, p: Vector2) -> void:
	val[c] += v
	if v > best_v[c]:
		best_v[c] = v
		best_p[c] = p


func _cell(p: Vector2, gw: int, gh: int) -> int:
	var x := floori((p.x - _bounds.position.x) / CELL)
	var z := floori((p.y - _bounds.position.y) / CELL)
	if x < 0 or z < 0 or x >= gw or z >= gh:
		return -1
	return z * gw + x


## Край карты на расстоянии ~EDGE_DIST от цели (из двух лучших — случайно)
func _pick_edge(to: Vector2) -> Vector2:
	if _edges.is_empty():
		return _bounds.position
	var want := EDGE_DIST * EDGE_DIST
	var a := -1
	var b := -1
	var ka := INF
	var kb := INF
	for i in _edges.size():
		var k := absf(_edges[i].distance_squared_to(to) - want)
		if k < ka:
			b = a
			kb = ka
			a = i
			ka = k
		elif k < kb:
			b = i
			kb = k
	if b >= 0 and rng.range_i(2) == 1:
		return _edges[b]
	return _edges[a]


# ================================================================= помощники

func _composition(defs: Defs) -> PackedInt32Array:
	var out := PackedInt32Array()
	var fw: Dictionary = _raid.get("first_wave", {})
	var fid := defs.f_ids[_faction] if _faction >= 0 else ""
	var base: Dictionary = fw.get(fid, {})
	var total := 0
	for id: Variant in base:
		var u := defs.unit(StringName(str(id)))
		if u < 0:
			continue
		var n := maxi(1, (int(base[id]) * scale_milli + 500) / 1000)
		out.append(u)
		out.append(n)
		total += n
	var cap := int(_raid.get("max_wave", 120))
	if total > cap:
		for i in range(1, out.size(), 2):
			out[i] = maxi(1, out[i] * cap / total)
	return out


func _next_interval() -> int:
	return _interval.x + rng.range_i(_interval.y - _interval.x + 1)


func _side_of(heading: float) -> Vector2:
	# поперёк курса (курс — по сторонам света)
	if absf(heading) < 0.1 or absf(absf(heading) - PI) < 0.1:
		return Vector2(1, 0)
	return Vector2(0, 1)


func _prune(gq: GameQueryImpl) -> void:
	var keep := PackedInt32Array()
	for u in wave_units:
		if gq.unit_alive(u):
			keep.append(u)
	wave_units = keep


func _centroid(gq: GameQueryImpl) -> Vector2:
	if wave_units.is_empty():
		return edge
	var c := Vector2.ZERO
	for u in wave_units:
		c += gq.unit_pos(u)
	return c / wave_units.size()


func _all_idle(gq: GameQueryImpl) -> bool:
	for u in wave_units:
		if not gq.is_idle(u):
			return false
	return true


## Отряды волны (по порядку юнитов)
func _wave_squads(gq: GameQueryImpl) -> PackedInt32Array:
	var out := PackedInt32Array()
	for u in wave_units:
		var s := gq.squad_of(u)
		if s != Ids.NULL and not out.has(s):
			out.append(s)
	return out


func _target_alive(gq: GameQueryImpl, h: int) -> bool:
	match Ids.kind(h):
		Ids.Kind.UNIT:
			return gq.unit_alive(h)
		Ids.Kind.HERD:
			var H := gq.herds()
			return H.valid(h) and H.state[H.slot(h)] == HerdTable.State.PEN
		Ids.Kind.BUILDING:
			var B := gq.buildings()
			if not B.valid(h):
				return false
			var s := B.state[B.slot(h)]
			return s == BuildingTable.State.ACTIVE or s == BuildingTable.State.SITE
	return false


func _nearest_free(gq: GameQueryImpl, hs: PackedInt32Array, from: Vector2, taken: Dictionary) -> int:
	var best := Ids.NULL
	var bd := INF
	for h in hs:
		if taken.has(h):
			continue
		var d := gq.unit_pos(h).distance_squared_to(from)
		if d < bd:
			bd = d
			best = h
	if best == Ids.NULL and not hs.is_empty():
		best = hs[0]                       # отрядов больше, чем работников — вдвоём на одного
	return best


## Стада врага у загонов в STRIKE_R (ближние первыми)
func _herds_near(gq: GameQueryImpl, c: Vector2) -> PackedInt32Array:
	var H := gq.herds()
	var out := PackedInt32Array()
	var ds := PackedFloat32Array()
	for h in H.hw:
		if H.owner[h] != enemy or H.state[h] != HerdTable.State.PEN or H.heads_milli[h] < 1000:
			continue
		var d := Vector2(H.x[h], H.z[h]).distance_squared_to(c)
		var r := STRIKE_R + H.graze_r[h]
		if d <= r * r:
			_insert_sorted(out, ds, H.handle(h), d)
	return out


## Постройки врага в STRIKE_R: поля, потом склады и тўғон, потом прочие, укрепления, ставка — последней;
## внутри разряда — ближние
func _buildings_near(gq: GameQueryImpl, c: Vector2) -> PackedInt32Array:
	var defs := gq.defs()
	var B := gq.buildings()
	var out := PackedInt32Array()
	var ds := PackedFloat32Array()
	for b in B.hw:
		if B.owner[b] != enemy:
			continue
		var st := B.state[b]
		if st != BuildingTable.State.ACTIVE and st != BuildingTable.State.SITE:
			continue
		var d := Vector2(B.x[b], B.z[b]).distance_squared_to(c)
		if d > STRIKE_R * STRIKE_R:
			continue
		var bt := B.btype[b]
		var k := defs.b_kind[bt]
		if k == Defs.BKind.LINK:
			continue
		var fl := defs.b_flags[bt]
		if fl & Defs.BF_HQ and wave_units.size() < HQ_MIN_WAVE:
			continue
		var rank := 1.0e6
		if k == Defs.BKind.FIELD:
			rank = 0.0
		elif fl & Defs.BF_HQ:
			rank = 3.0e6
		elif fl & Defs.BF_DROP or k == Defs.BKind.DAM:
			rank = 0.5e6
		elif k == Defs.BKind.TOWER or k == Defs.BKind.WALL or k == Defs.BKind.GATE:
			rank = 2.0e6
		_insert_sorted(out, ds, B.handle(b), rank + d)
	return out


static func _insert_sorted(out: PackedInt32Array, ds: PackedFloat32Array, h: int, d: float) -> void:
	var i := ds.bsearch(d, false)
	ds.insert(i, d)
	out.insert(i, h)


## Наши юниты уже ведут угнанное стадо
func _has_loot(gq: GameQueryImpl) -> bool:
	var H := gq.herds()
	for h in H.hw:
		if H.state[h] == HerdTable.State.CAPTURED and wave_units.has(H.captor_u[h]):
			return true
	return false
