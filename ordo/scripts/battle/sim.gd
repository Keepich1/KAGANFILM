class_name BattleSim
extends RefCounted
## Ядро боя (ТЗ 4, 14): фиксированный шаг 1/30 с, без графики, без глобальных случайностей.
##
## Данные — массивы по полям (Packed*Array, «структура массивов»): u_* — юниты, sq_* — отряды.
## Отряды до 100 бойцов с офицером и знаменосцем, построения, выносливость, мораль, натиск
## конницы, мушкеты, стрелы, полководец с аурой и боевым кличем, условия победы.
##
##   var sim := BattleSim.new(7)
##   var a := sim.add_squad(0, "sarboz", 100, Vector2(115, 0), -PI / 2, BattleSim.Formation.LINE, 50, "yuzboshi")
##   var b := sim.add_squad(1, "sayisker", 60, Vector2(25, 10), PI / 2, BattleSim.Formation.LINE, 30, "juz_bashy")
##   sim.order_attack(b, a, BattleSim.Gait.RUN)
##   sim.step()   # 1/30 с
##
## Оси: +X — восток, −Z — север. Курс h (радианы): направление вперёд = (sin h, cos h),
## как у толпы: Basis(Vector3.UP, h). Высота земли — Terrain.height_at, вода — Terrain.is_water.
## Стороны: 0 — Коканд (оседлые), 1 — кыпчаки (кочевники).

signal shot(unit: int, muzzle: Vector3, dir: Vector3, hit: bool)  ## выстрел: дым и вспышка у дула
signal volley(squad: int, rank: int, center: Vector3, count: int)  ## первая пуля шеренги
signal charge_ordered(squad: int)                                  ## копья наперевес
signal impact(squad: int, pos: Vector3, strength: float)           ## первый удар натиска отряда
signal charge_hit(unit: int, target: int, pos: Vector3)            ## каждый удар натиска (пыль)
signal melee_hit(attacker: int, target: int, pos: Vector3)         ## удар в рукопашной (искры)
signal death(unit: int, pos: Vector3)
signal war_cry(unit: int, pos: Vector3)
signal rout(squad: int, pos: Vector3)
signal rallied(squad: int, pos: Vector3)
signal battle_over(winner: int)

const DT := 1.0 / 30.0

enum Formation { LINE, COLUMN, SQUARE, LOOSE }
enum Order { HOLD, MOVE, ATTACK }
enum Status { READY, FLEE }
enum Gait { WALK, TROT, RUN }
enum Life { ALIVE, DYING, DEAD }
enum Act { NONE, AIM, MELEE, CHEER }
enum Role { TROOPER, OFFICER, BANNER, GENERAL }

# ---------------------------------------------------------------- баланс (ТЗ 4)
const MORALE_FLEE_INF := 28.0
const MORALE_FLEE_CAV := 22.0
const MORALE_RALLY_GAP := 22.0       # бегущий отряд встаёт, когда мораль выше порога на столько
const MORALE_LOSS := 1.1             # за убитого (на отряд 100; меньше отряд — больнее)
const MORALE_CHARGE_SHOCK := 0.3     # за удар натиска (на отряд 100)
const MORALE_IMPACT := 10.0          # разом, когда натиск дошёл
const RAM_MAX := 2                   # таран: всадник сбивает до двух шеренг
const MORALE_OFFICER := 30.0
const MORALE_GENERAL := 20.0
const MORALE_RECOVER := 2.0          # в с, вдали от врага
const MORALE_AURA := 3.0             # в с, рядом с полководцем (в бою — четверть)
const AURA_RADIUS := 90.0
const WAR_CRY_COOLDOWN := 75.0
const WAR_CRY_BONUS := 25.0
const ENEMY_NEAR := 50.0             # «враг рядом» для восстановления морали
const STAMINA_NO_CHARGE := 20.0
const STAMINA_TIRED := 30.0
const CHARGE_COUCH_DIST := 38.0      # копья наперевес на этой дистанции
const SPEAR_ABSORB := 0.4            # копейщики гасят натиск
const SQUARE_ABSORB := 0.2           # по каре натиск почти не проходит
const HORSE_DOWN := 0.3              # [Свободно] пуля валит коня: доля попаданий по коннице
const MUSKET_PIERCE := 0.5           # [Свободно] огнестрел пробивает половину брони
const FLEE_VICTORY_TIME := 12.0
const ARMY_LEFT_LOSE := 0.08
const SHOOT_FIRE_DELAY: float = AnimSpec.SHOOT_FIRE_PHASE * 1.4       # вскидка: от начала SHOOT до выстрела (фаза 0.55 из 1.4 с)
const SHOOT_DURATION := 1.4
const MELEE_HIT_DELAY := 0.41        # удар: AnimSpec.MELEE_HIT_PHASE (0.46) × 0.9 с, округлено
const MELEE_DURATION := 0.9
const CHEER_DURATION := 2.0
const DEATH_DURATION_HUMAN := 1.3
const DEATH_DURATION_HORSE := 1.8
const SHOOT_MUZZLE := Vector3(-0.15, 1.38, 1.45)  # дуло в осях юнита (вперёд +Z)

const _GRID_ORIGIN := -512.0
const _CELL := 4.0
const _GRID_N := 256

var rng: BattleRng
var time := 0.0
var steps := 0
var winner := -1

# ---------------------------------------------------------------- типы (из UnitStats)
var type_ids := PackedStringArray()
var t_hp := PackedFloat32Array()
var t_speed := PackedFloat32Array()
var t_walk := PackedFloat32Array()
var t_armour := PackedFloat32Array()
var t_attack := PackedFloat32Array()
var t_reach := PackedFloat32Array()
var t_charge := PackedFloat32Array()
var t_vs_cav := PackedFloat32Array()
var t_missile := PackedFloat32Array()
var t_range := PackedFloat32Array()
var t_reload := PackedFloat32Array()
var t_ammo := PackedInt32Array()
var t_acc_near := PackedFloat32Array()
var t_acc_far := PackedFloat32Array()
var t_flags := PackedInt32Array()
var t_radius := PackedFloat32Array()
var t_mass := PackedFloat32Array()

# ---------------------------------------------------------------- юниты
var n := 0
var u_x := PackedFloat32Array()
var u_z := PackedFloat32Array()
var u_px := PackedFloat32Array()     # позиция на прошлом шаге (для плавности)
var u_pz := PackedFloat32Array()
var u_vx := PackedFloat32Array()
var u_vz := PackedFloat32Array()
var u_dvx := PackedFloat32Array()    # желаемая скорость
var u_dvz := PackedFloat32Array()
var u_kx := PackedFloat32Array()     # отброс (удар натиска)
var u_kz := PackedFloat32Array()
var u_h := PackedFloat32Array()      # курс
var u_ph := PackedFloat32Array()
var u_hp := PackedFloat32Array()
var u_type := PackedInt32Array()
var u_squad := PackedInt32Array()
var u_side := PackedInt32Array()
var u_role := PackedInt32Array()
var u_slot := PackedInt32Array()
var u_life := PackedInt32Array()
var u_act := PackedInt32Array()
var u_act_t := PackedFloat32Array()  # начало разового действия
var u_fire_t := PackedFloat32Array() # время выстрела (−1 — нет)
var u_aim := PackedInt32Array()      # цель выстрела
var u_reload_t := PackedFloat32Array() # перезарядка до
var u_ammo := PackedInt32Array()
var u_cool_t := PackedFloat32Array() # следующий удар не раньше
var u_hit_t := PackedFloat32Array()  # удар придёт в (−1 — нет)
var u_target := PackedInt32Array()   # цель в рукопашной
var u_couched := PackedInt32Array()  # копьё наперевес (идёт натиск)
var u_charged := PackedInt32Array()  # натиск окончен (удар нанесён или разгон потерян)
var u_rams := PackedInt32Array()     # сколько врагов сбито натиском (до RAM_MAX)
var u_death_t := PackedFloat32Array()
var u_fall := PackedInt32Array()     # на какой бок падает (0/1)
var u_var := PackedFloat32Array()    # вариант 0..1 (вид, разброс)

# ---------------------------------------------------------------- отряды
var squads := 0
var sq_side := PackedInt32Array()
var sq_type := PackedInt32Array()
var sq_members: Array[PackedInt32Array] = []
var sq_officer := PackedInt32Array()
var sq_banner := PackedInt32Array()
var sq_form := PackedInt32Array()
var sq_files := PackedInt32Array()
var sq_order := PackedInt32Array()
var sq_status := PackedInt32Array()
var sq_gait := PackedInt32Array()
var sq_x := PackedFloat32Array()     # якорь строя (центр первой шеренги)
var sq_z := PackedFloat32Array()
var sq_h := PackedFloat32Array()
var sq_vx := PackedFloat32Array()    # скорость якоря (бойцы держат её + поправка к месту)
var sq_vz := PackedFloat32Array()
var sq_tx := PackedFloat32Array()
var sq_tz := PackedFloat32Array()
var sq_th := PackedFloat32Array()    # курс по прибытии (NAN — по ходу)
var sq_target := PackedInt32Array()
var sq_morale := PackedFloat32Array()
var sq_stam := PackedFloat32Array()
var sq_flee_t := PackedFloat32Array()
var sq_init := PackedInt32Array()
var sq_alive := PackedInt32Array()
var sq_cx := PackedFloat32Array()    # центр живых
var sq_cz := PackedFloat32Array()
var sq_speed := PackedFloat32Array() # средняя скорость бойцов
var sq_lag := PackedFloat32Array()   # среднее отставание от мест в строю, м
var sq_melee := PackedInt32Array()   # строй распался в свалку
var sq_charge_ok := PackedInt32Array()
var sq_couched := PackedInt32Array()
var sq_impacted := PackedInt32Array()
var sq_fire_target := PackedInt32Array()
var sq_fire_dist := PackedFloat32Array()
var sq_volley_rank := PackedInt32Array()  # какая шеренга стреляет следующей (−1 — не готовы)
var sq_volley_t := PackedFloat32Array()
var sq_volley_seen := PackedInt32Array()  # о какой шеренге уже сообщили
var sq_cry_t := PackedFloat32Array()      # последний клич (у полководца)
var sq_single := PackedInt32Array()       # одиночка: полководец, не бежит

var side_init := PackedInt32Array([0, 0])
var side_flee_t := PackedFloat32Array([0.0, 0.0])
var general := PackedInt32Array([-1, -1])   # юнит-полководец стороны

var _head := PackedInt32Array()
var _next := PackedInt32Array()

# --- ускорители (только скорость; результат шага тот же бит в бит, test_sim сверяет сумму)
# стороны в клетках хэша и в блоках 4×4 клетки (бит 1 << сторона) — поиск врага пропускает пустое
const _BLK_SHIFT := 2
const _BLK_N := _GRID_N >> _BLK_SHIFT
var _cmask := PackedInt32Array()
var _bmask := PackedInt32Array()
# места в строю: смещения считаются один раз на отряд, пока не сменились строй и ширина
var _so_x := PackedFloat32Array()
var _so_y := PackedFloat32Array()
var _so_key := PackedInt64Array()
# суша в клетке хэша: 0 — не проверено, 1 — точно суша (вода не ближе 0,05 м по высоте), 2 — может быть вода
var _dry := PackedByteArray()


func _init(p_seed := 1) -> void:
	rng = BattleRng.new(p_seed)
	_head.resize(_GRID_N * _GRID_N)
	_head.fill(-1)
	_cmask.resize(_GRID_N * _GRID_N)
	_bmask.resize(_BLK_N * _BLK_N)
	_dry.resize(_GRID_N * _GRID_N)


# ================================================================= создание

## Индекс типа (UnitStats) в таблицах t_*
func type_index(type_id: String) -> int:
	var i := type_ids.find(type_id)
	if i >= 0:
		return i
	var s := UnitStats.get_stats(type_id)
	assert(not s.is_empty(), "нет юнита " + type_id)
	type_ids.append(type_id)
	t_hp.append(s["hp"])
	t_speed.append(s["speed"])
	t_walk.append(s["walk"])
	t_armour.append(s["armour"])
	t_attack.append(s["attack"])
	t_reach.append(s["reach"])
	t_charge.append(s["charge"])
	t_vs_cav.append(s["vs_cav"])
	t_missile.append(s["missile"])
	t_range.append(s["range"])
	t_reload.append(s["reload"])
	t_ammo.append(s["ammo"])
	t_acc_near.append(s["acc_near"])
	t_acc_far.append(s["acc_far"])
	t_flags.append(s["flags"])
	t_radius.append(s["radius"])
	t_mass.append(s["mass"])
	return type_ids.size() - 1


## Отряд: count бойцов типа type_id, якорь pos (центр первой шеренги), курс heading.
## files — ширина строя (0 — само), officer_type — офицер ("" — без), banner — знаменосец из бойцов.
## scatter — разброс начальных мест, м (отряд «собирается» в строй).
func add_squad(side: int, type_id: String, count: int, pos: Vector2, heading: float,
		formation := Formation.LINE, files := 0, officer_type := "", banner := true, scatter := 0.0) -> int:
	var s := _new_squad(side, type_index(type_id), pos, heading)
	sq_form[s] = formation
	sq_files[s] = files if files > 0 else maxi(1, ceili(count / 2.0))
	var members := PackedInt32Array()
	for k in count:
		var role := Role.BANNER if banner and k == count - 1 else Role.TROOPER
		members.append(_new_unit(s, sq_type[s], role, k if role == Role.TROOPER else -1))
	if officer_type != "":
		var o := _new_unit(s, type_index(officer_type), Role.OFFICER, -1)
		members.append(o)
		sq_officer[s] = o
	if banner and count > 0:
		sq_banner[s] = members[count - 1]
	sq_members[s] = members
	sq_init[s] = members.size()
	sq_alive[s] = members.size()
	side_init[side] += members.size()
	for u in members:
		var p := slot_point(s, u)
		var j := Vector2(rng.range_f(-1, 1), rng.range_f(-1, 1)) * scatter
		u_x[u] = p.x + j.x
		u_z[u] = p.y + j.y
		u_px[u] = u_x[u]
		u_pz[u] = u_z[u]
		u_h[u] = heading + rng.range_f(-0.3, 0.3) * minf(scatter, 1.0)
		u_ph[u] = u_h[u]
	_update_centroid(s)
	return s


## Полководец — отряд из одного юнита (не бежит, аура морали, боевой клич)
func add_general(side: int, type_id: String, pos: Vector2, heading: float) -> int:
	var s := _new_squad(side, type_index(type_id), pos, heading)
	sq_single[s] = 1
	sq_files[s] = 1
	var u := _new_unit(s, sq_type[s], Role.GENERAL, 0)
	sq_members[s] = PackedInt32Array([u])
	sq_officer[s] = u
	sq_init[s] = 1
	sq_alive[s] = 1
	side_init[side] += 1
	general[side] = u
	u_x[u] = pos.x
	u_z[u] = pos.y
	u_px[u] = pos.x
	u_pz[u] = pos.y
	u_h[u] = heading
	u_ph[u] = heading
	sq_cry_t[s] = -WAR_CRY_COOLDOWN
	_update_centroid(s)
	return s


func _new_squad(side: int, type_i: int, pos: Vector2, heading: float) -> int:
	var s := squads
	squads += 1
	sq_side.append(side)
	sq_type.append(type_i)
	sq_members.append(PackedInt32Array())
	sq_officer.append(-1)
	sq_banner.append(-1)
	sq_form.append(Formation.LINE)
	sq_files.append(1)
	sq_order.append(Order.HOLD)
	sq_status.append(Status.READY)
	sq_gait.append(Gait.WALK)
	sq_x.append(pos.x)
	sq_z.append(pos.y)
	sq_h.append(heading)
	sq_vx.append(0.0)
	sq_vz.append(0.0)
	sq_tx.append(pos.x)
	sq_tz.append(pos.y)
	sq_th.append(heading)
	sq_target.append(-1)
	sq_morale.append(100.0)
	sq_stam.append(100.0)
	sq_flee_t.append(0.0)
	sq_init.append(0)
	sq_alive.append(0)
	sq_cx.append(pos.x)
	sq_cz.append(pos.y)
	sq_speed.append(0.0)
	sq_lag.append(0.0)
	sq_melee.append(0)
	sq_charge_ok.append(0)
	sq_couched.append(0)
	sq_impacted.append(0)
	sq_fire_target.append(-1)
	sq_fire_dist.append(0.0)
	sq_volley_rank.append(-1)
	sq_volley_t.append(0.0)
	sq_volley_seen.append(-1)
	sq_cry_t.append(-1000.0)
	sq_single.append(0)
	_so_key.append(-1)
	return s


func _new_unit(s: int, type_i: int, role: int, slot: int) -> int:
	var u := n
	n += 1
	u_x.append(0.0); u_z.append(0.0); u_px.append(0.0); u_pz.append(0.0)
	u_vx.append(0.0); u_vz.append(0.0); u_dvx.append(0.0); u_dvz.append(0.0)
	u_kx.append(0.0); u_kz.append(0.0); u_h.append(0.0); u_ph.append(0.0)
	u_act_t.append(-10.0); u_reload_t.append(0.0); u_cool_t.append(0.0); u_death_t.append(-1.0)
	u_hp.append(t_hp[type_i])
	u_type.append(type_i)
	u_squad.append(s)
	u_side.append(sq_side[s])
	u_role.append(role)
	u_slot.append(slot)
	u_life.append(Life.ALIVE)
	u_act.append(Act.NONE)
	u_fire_t.append(-1.0)
	u_aim.append(-1)
	u_ammo.append(t_ammo[type_i])
	u_hit_t.append(-1.0)
	u_target.append(-1)
	u_couched.append(0)
	u_charged.append(0)
	u_rams.append(0)
	u_fall.append(0)
	u_var.append(BattleRng.hash01(u * 7919 + 13))
	_so_x.append(0.0)
	_so_y.append(0.0)
	_so_key[s] = -1
	return u


# ================================================================= приказы (ИИ, игрок)

func order_hold(s: int, facing := NAN) -> void:
	sq_order[s] = Order.HOLD
	sq_tx[s] = sq_x[s]
	sq_tz[s] = sq_z[s]
	sq_th[s] = facing


func order_move(s: int, pos: Vector2, gait := Gait.WALK, facing := NAN) -> void:
	sq_order[s] = Order.MOVE
	sq_tx[s] = pos.x
	sq_tz[s] = pos.y
	sq_th[s] = facing
	sq_gait[s] = gait
	if sq_melee[s] == 1 or sq_status[s] == Status.FLEE:
		# из свалки строй собирается на ходу: якорь — центр живых, курс — к цели
		sq_x[s] = sq_cx[s]
		sq_z[s] = sq_cz[s]
		sq_h[s] = atan2(pos.x - sq_cx[s], pos.y - sq_cz[s])
	sq_melee[s] = 0
	for u in sq_members[s]:
		u_target[u] = -1
		u_couched[u] = 0


func order_attack(s: int, target: int, gait := Gait.RUN) -> void:
	sq_order[s] = Order.ATTACK
	sq_target[s] = target
	sq_gait[s] = gait


func set_gait(s: int, gait: int) -> void:
	sq_gait[s] = gait


func set_formation(s: int, f: int) -> void:
	sq_form[s] = f


## Конница: разрешить натиск (копья наперевес на CHARGE_COUCH_DIST от цели)
func allow_charge(s: int, ok := true) -> void:
	sq_charge_ok[s] = 1 if ok else 0
	if ok:
		sq_couched[s] = 0
		sq_impacted[s] = 0


## Стрелки: огонь шеренгами по отряду target, когда он ближе dist (не дальше дальности)
func set_fire(s: int, target: int, dist: float) -> void:
	sq_fire_target[s] = target
	sq_fire_dist[s] = minf(dist, t_range[sq_type[s]])
	if sq_volley_rank[s] < 0:
		sq_volley_rank[s] = 0
		sq_volley_seen[s] = -1


## Боевой клич полководца (раз в 75 с): +25 морали и выносливости отрядам рядом,
## бегущие возвращаются. Возвращает false, если клич ещё не готов.
func war_cry_now(gen_squad: int) -> bool:
	var g := sq_officer[gen_squad]
	if g < 0 or u_life[g] != Life.ALIVE or time - sq_cry_t[gen_squad] < WAR_CRY_COOLDOWN:
		return false
	sq_cry_t[gen_squad] = time
	var side := sq_side[gen_squad]
	_start_cheer(g, 0.0)
	for s in squads:
		if sq_side[s] != side or s == gen_squad or sq_alive[s] == 0:
			continue
		if Vector2(sq_cx[s] - u_x[g], sq_cz[s] - u_z[g]).length() > AURA_RADIUS:
			continue
		sq_morale[s] = minf(100.0, sq_morale[s] + WAR_CRY_BONUS)
		sq_stam[s] = minf(100.0, sq_stam[s] + WAR_CRY_BONUS)
		if sq_status[s] == Status.FLEE:
			sq_status[s] = Status.READY
			sq_flee_t[s] = 0.0
			sq_x[s] = sq_cx[s]
			sq_z[s] = sq_cz[s]
			order_hold(s, _heading_to_enemy(s))
			rallied.emit(s, Vector3(sq_cx[s], 0.0, sq_cz[s]))
		# бойцы отвечают на клич: поднимают оружие (вразнобой)
		for u in sq_members[s]:
			if u_life[u] == Life.ALIVE and u_act[u] == Act.NONE and u_fire_t[u] < 0.0:
				_start_cheer(u, 0.15 + 0.5 * u_var[u])
	war_cry.emit(g, _pos3(g))
	return true


## Ликование без бонуса (победа): юниты отряда s поднимают оружие
func cheer(s: int) -> void:
	for u in sq_members[s]:
		if u_life[u] == Life.ALIVE and u_act[u] == Act.NONE:
			_start_cheer(u, 0.4 * u_var[u])


func _start_cheer(u: int, delay: float) -> void:
	u_act[u] = Act.CHEER
	u_act_t[u] = time + delay


# ================================================================= запросы

func is_alive(u: int) -> bool:
	return u_life[u] == Life.ALIVE


func is_mounted(u: int) -> bool:
	return t_flags[u_type[u]] & UnitStats.MOUNTED != 0


func type_of(u: int) -> String:
	return type_ids[u_type[u]]


func speed_of(u: int) -> float:
	return Vector2(u_vx[u], u_vz[u]).length()


func max_speed_of(u: int) -> float:
	return t_speed[u_type[u]]


func squad_centroid(s: int) -> Vector2:
	return Vector2(sq_cx[s], sq_cz[s])


func squad_anchor(s: int) -> Vector2:
	return Vector2(sq_x[s], sq_z[s])


func squad_forward(s: int) -> Vector2:
	return Vector2(sin(sq_h[s]), cos(sq_h[s]))


func squad_alive(s: int) -> int:
	return sq_alive[s]


func side_alive(side: int) -> int:
	var c := 0
	for s in squads:
		if sq_side[s] == side:
			c += sq_alive[s]
	return c


func is_fleeing(s: int) -> bool:
	return sq_status[s] == Status.FLEE


## Ближайшее расстояние от строя s (по его курсу) до живых бойцов отряда t
func front_distance(s: int, t: int) -> float:
	var f := squad_forward(s)
	var best := INF
	for u in sq_members[t]:
		if u_life[u] != Life.ALIVE:
			continue
		var d := (u_x[u] - sq_x[s]) * f.x + (u_z[u] - sq_z[s]) * f.y
		best = minf(best, absf(d))
	return best


## Мировая точка места юнита в строю (x, z)
func slot_point(s: int, u: int) -> Vector2:
	# смещение из кэша отряда (те же числа, что дал бы _slot_offset)
	var key := (sq_form[s] * 4096 + sq_files[s]) * 65536 + sq_members[s].size()
	if _so_key[s] != key:
		_so_key[s] = key
		for m in sq_members[s]:
			var om := _slot_offset(s, m)
			_so_x[m] = om.x
			_so_y[m] = om.y
	var ox := _so_x[u]
	var oy := _so_y[u]
	var h := sq_h[s]
	var fx := sin(h)
	var fz := cos(h)
	# боковая ось: вправо от курса
	return Vector2(sq_x[s] - fz * ox + fx * oy, sq_z[s] + fx * ox + fz * oy)


## Смещение места в строю: x — вбок (вправо), y — вперёд (в шеренгах — назад, минус)
func _slot_offset(s: int, u: int) -> Vector2:
	var ti := sq_type[s]
	var mounted := t_flags[ti] & UnitStats.MOUNTED != 0
	var sx := 2.1 if mounted else 1.0
	var sz := 4.2 if mounted else 1.5
	var files := maxi(sq_files[s], 1)
	var count := sq_members[s].size()
	var troops := count - (1 if sq_officer[s] >= 0 and sq_single[s] == 0 else 0) - (1 if sq_banner[s] >= 0 else 0)
	var ranks := maxi(1, ceili(float(troops) / files))
	match u_role[u]:
		Role.GENERAL:
			return Vector2.ZERO
		Role.OFFICER:
			return Vector2(0.0, 4.6) if mounted else Vector2(0.0, -float(ranks) * sz - 3.5)
		Role.BANNER:
			return Vector2(2.6, 2.6) if mounted else Vector2(0.6, -float(ranks - 1) * sz - 1.6)
	var k := u_slot[u]
	var f := sq_form[s]
	if f == Formation.COLUMN:
		files = 4 if not mounted else 3
	elif f == Formation.SQUARE:
		# пустое каре: бойцы по периметру лицом наружу
		var side_n := maxi(1, ceili(troops / 4.0))
		var side_len := side_n * sx
		var e := k / side_n
		var p := (k % side_n - (side_n - 1) * 0.5) * sx
		match e:
			0: return Vector2(p, side_len * 0.5)
			1: return Vector2(side_len * 0.5, -p)
			2: return Vector2(-p, -side_len * 0.5)
			_: return Vector2(-side_len * 0.5, p)
	var r := k / files
	var c := k % files
	var in_rank := mini(files, troops - r * files)
	var off := Vector2((c - (in_rank - 1) * 0.5) * sx, -r * sz)
	if f == Formation.LOOSE:
		off *= 2.2
		off += Vector2(u_var[u] - 0.5, BattleRng.hash01(u * 31 + 5) - 0.5) * 1.6
	elif f == Formation.COLUMN:
		off.y = -r * (sz * 0.9)
	# живой строй: лёгкий разброс
	off += Vector2(u_var[u] - 0.5, 0.0) * 0.12
	return off


## Шеренга юнита (0 — первая)
func rank_of(u: int) -> int:
	var s := u_squad[u]
	if u_role[u] != Role.TROOPER:
		return 99
	return u_slot[u] / maxi(sq_files[s], 1)


# ================================================================= шаг

func step() -> void:
	time += DT
	steps += 1
	for u in n:
		u_px[u] = u_x[u]
		u_pz[u] = u_z[u]
		u_ph[u] = u_h[u]
	_rebuild_hash()
	for s in squads:
		_update_centroid(s)
	for s in squads:
		_squad_step(s)
	_units_think()
	_resolve_actions()
	_integrate()
	_victory_check()


func _rebuild_hash() -> void:
	_head.fill(-1)
	_cmask.fill(0)
	_bmask.fill(0)
	if _next.size() < n:
		_next.resize(n)
	for u in n:
		if u_life[u] != Life.ALIVE:
			continue
		# то же, что _cell(); заодно отмечаем сторону в клетке и в блоке
		var cx := clampi(int((u_x[u] - _GRID_ORIGIN) / _CELL), 0, _GRID_N - 1)
		var cz := clampi(int((u_z[u] - _GRID_ORIGIN) / _CELL), 0, _GRID_N - 1)
		var c := cz * _GRID_N + cx
		_next[u] = _head[c]
		_head[c] = u
		var bit := 1 << u_side[u]
		_cmask[c] |= bit
		_bmask[(cz >> _BLK_SHIFT) * _BLK_N + (cx >> _BLK_SHIFT)] |= bit


func _cell(x: float, z: float) -> int:
	var cx := clampi(int((x - _GRID_ORIGIN) / _CELL), 0, _GRID_N - 1)
	var cz := clampi(int((z - _GRID_ORIGIN) / _CELL), 0, _GRID_N - 1)
	return cz * _GRID_N + cx


## Точно суша: в клетке хэша (4 м) нет высот ниже воды + 0,05 м (тогда Terrain.is_water — false).
## Проверка клетки — один раз, по узлам сетки высот с запасом в узел (за краем карты — край).
func _surely_dry(x: float, z: float) -> bool:
	var c := _cell(x, z)
	var d := _dry[c]
	if d == 0:
		d = 2
		var hs := Terrain.heights()
		var hn := Terrain.size()
		if hn > 1:
			var sp := Terrain.spacing()
			var o := Terrain.origin()
			var cx := c % _GRID_N
			var cz := c / _GRID_N
			var wx := _GRID_ORIGIN + cx * _CELL
			var wz := _GRID_ORIGIN + cz * _CELL
			var i0 := clampi(floori((wx - o.x) / sp) - 1, 0, hn - 1)
			var i1 := clampi(ceili((wx + _CELL - o.x) / sp) + 1, 0, hn - 1)
			var j0 := clampi(floori((wz - o.y) / sp) - 1, 0, hn - 1)
			var j1 := clampi(ceili((wz + _CELL - o.y) / sp) + 1, 0, hn - 1)
			# точка за краем карты берёт высоту края — край тоже в проверке
			if cx == 0: i0 = 0
			if cz == 0: j0 = 0
			if cx == _GRID_N - 1: i1 = hn - 1
			if cz == _GRID_N - 1: j1 = hn - 1
			var lo := INF
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					lo = minf(lo, hs[j * hn + i])
			if lo > Terrain.water_level() - 0.05 + 0.01:
				d = 1
		_dry[c] = d
	return d == 1


## Ближайший живой враг юнита u в радиусе r (−1 — нет). Только впереди, если front > −1.
func nearest_enemy(u: int, r: float, front := -2.0) -> int:
	var x := u_x[u]
	var z := u_z[u]
	var side := u_side[u]
	var cr := ceili(r / _CELL)
	var cx := clampi(int((x - _GRID_ORIGIN) / _CELL), 0, _GRID_N - 1)
	var cz := clampi(int((z - _GRID_ORIGIN) / _CELL), 0, _GRID_N - 1)
	var x0 := maxi(cx - cr, 0)
	var x1 := mini(cx + cr, _GRID_N - 1)
	var z0 := maxi(cz - cr, 0)
	var z1 := mini(cz + cr, _GRID_N - 1)
	var foe := ~(1 << side)
	# в блоках вокруг нет чужих — искать нечего (тот же ответ −1, без обхода клеток)
	var any := false
	for bz in range(z0 >> _BLK_SHIFT, (z1 >> _BLK_SHIFT) + 1):
		for bx in range(x0 >> _BLK_SHIFT, (x1 >> _BLK_SHIFT) + 1):
			if _bmask[bz * _BLK_N + bx] & foe != 0:
				any = true
				break
		if any:
			break
	if not any:
		return -1
	if cr >= 3:
		return _nearest_rings(u, r, front, cx, cz, x0, x1, z0, z1)
	var best := -1
	var bd := r * r
	var fx := sin(u_h[u])
	var fz := cos(u_h[u])
	for gz in range(z0, z1 + 1):
		for gx in range(x0, x1 + 1):
			var c := gz * _GRID_N + gx
			if _cmask[c] & foe == 0:
				continue  # в клетке только свои
			var v := _head[c]
			while v >= 0:
				if u_side[v] != side:
					var dx := u_x[v] - x
					var dz := u_z[v] - z
					var d2 := dx * dx + dz * dz
					if d2 < bd:
						if front <= -2.0 or (dx * fx + dz * fz) > front * sqrt(d2):
							bd = d2
							best = v
				v = _next[v]
	return best


## Тот же поиск для большого радиуса (погоня, свалка): клетки кольцами от юнита, стоп, когда
## кольцо заведомо дальше лучшего. Ответ тот же, что у обхода прямоугольника по строкам:
## ближайший по d2, при равном d2 — тот, кого обход по строкам встретил бы первым
## (клетка с меньшим номером, в клетке — больший номер юнита: списки идут по убыванию).
func _nearest_rings(u: int, r: float, front: float, cx: int, cz: int, x0: int, x1: int, z0: int, z1: int) -> int:
	var x := u_x[u]
	var z := u_z[u]
	var side := u_side[u]
	var foe := ~(1 << side)
	var best := -1
	var best_c := 0
	var bd := r * r
	var fx := sin(u_h[u])
	var fz := cos(u_h[u])
	var kmax := maxi(maxi(cx - x0, x1 - cx), maxi(cz - z0, z1 - cz))
	for k in kmax + 1:
		if best >= 0 and k >= 2:
			# до клеток кольца k не ближе (k − 1) клеток; запас 1 см на округление
			var gap := (k - 1) * _CELL - 0.01
			if gap * gap > bd:
				break
		for gz in range(maxi(cz - k, z0), mini(cz + k, z1) + 1):
			# верхний и нижний ряды кольца — целиком, средние — только две крайние клетки
			var full := gz == cz - k or gz == cz + k
			var gx := maxi(cx - k, x0) if full else cx - k
			var gx_end := mini(cx + k, x1) if full else cx + k
			var gstep := 1 if full else 2 * k
			while gx <= gx_end:
				var c := gz * _GRID_N + gx
				var inside := gx >= x0 and gx <= x1
				gx += gstep
				if not inside or _cmask[c] & foe == 0:
					continue
				var v := _head[c]
				while v >= 0:
					if u_side[v] != side:
						var dx := u_x[v] - x
						var dz := u_z[v] - z
						var d2 := dx * dx + dz * dz
						if d2 < bd or (d2 == bd and best >= 0 and (c < best_c or (c == best_c and v > best))):
							if front <= -2.0 or (dx * fx + dz * fz) > front * sqrt(d2):
								bd = d2
								best = v
								best_c = c
					v = _next[v]
	return best


func _update_centroid(s: int) -> void:
	var cx := 0.0
	var cz := 0.0
	var sp := 0.0
	var c := 0
	for u in sq_members[s]:
		if u_life[u] != Life.ALIVE:
			continue
		cx += u_x[u]
		cz += u_z[u]
		sp += sqrt(u_vx[u] * u_vx[u] + u_vz[u] * u_vz[u])
		c += 1
	sq_alive[s] = c
	if c > 0:
		sq_cx[s] = cx / c
		sq_cz[s] = cz / c
		sq_speed[s] = sp / c


func _nearest_enemy_squad(s: int) -> int:
	var best := -1
	var bd := INF
	for t in squads:
		if sq_side[t] == sq_side[s] or sq_alive[t] == 0:
			continue
		var d := Vector2(sq_cx[t] - sq_cx[s], sq_cz[t] - sq_cz[s]).length_squared()
		if d < bd:
			bd = d
			best = t
	return best


func _heading_to_enemy(s: int) -> float:
	var e := _nearest_enemy_squad(s)
	if e < 0:
		return sq_h[s]
	return atan2(sq_cx[e] - sq_cx[s], sq_cz[e] - sq_cz[s])


func _flee_threshold(s: int) -> float:
	return MORALE_FLEE_CAV if t_flags[sq_type[s]] & UnitStats.MOUNTED != 0 else MORALE_FLEE_INF


func _tired(s: int) -> float:
	# 1 — свежий; уставший отряд медленнее и бьёт слабее
	var st := sq_stam[s]
	return 1.0 if st >= STAMINA_TIRED else 0.7 + 0.3 * st / STAMINA_TIRED


## Скорость строя: тип × аллюр × построение × усталость
func squad_speed(s: int) -> float:
	var ti := sq_type[s]
	var v := t_speed[ti]
	match sq_gait[s]:
		Gait.WALK: v *= t_walk[ti]
		Gait.TROT: v *= 0.72
	match sq_form[s]:
		Formation.COLUMN: v *= 1.15
		Formation.SQUARE: v *= 0.35
	return v * _tired(s)


func _squad_step(s: int) -> void:
	if sq_alive[s] == 0:
		return
	var ti := sq_type[s]
	var mounted := t_flags[ti] & UnitStats.MOUNTED != 0
	var enemy := _nearest_enemy_squad(s)
	var enemy_d := INF
	if enemy >= 0:
		enemy_d = Vector2(sq_cx[enemy] - sq_cx[s], sq_cz[enemy] - sq_cz[s]).length()
	var near := enemy_d < ENEMY_NEAR
	# --- мораль: восстановление и аура полководца
	if sq_single[s] == 0:
		if not near:
			sq_morale[s] += MORALE_RECOVER * DT
		var g := general[sq_side[s]]
		if g >= 0 and u_life[g] == Life.ALIVE:
			if Vector2(u_x[g] - sq_cx[s], u_z[g] - sq_cz[s]).length() < AURA_RADIUS:
				sq_morale[s] += MORALE_AURA * DT * (0.25 if near else 1.0)
		sq_morale[s] = clampf(sq_morale[s], 0.0, 100.0)
	# --- выносливость: бег и галоп тратят, кони устают быстрее, стоя — отдых
	var frac := sq_speed[s] / maxf(t_speed[ti], 0.1)
	var ds := 0.0
	if mounted:
		if frac > 0.8:
			ds = -2.6 if sq_couched[s] == 1 else -2.0
		elif frac > 0.55:
			ds = -0.5
		elif frac > 0.1:
			ds = 0.6
		else:
			ds = 3.0
	else:
		if frac > 0.7:
			ds = -1.2
		elif frac > 0.1:
			ds = 0.5
		else:
			ds = 2.5
	if sq_melee[s] == 1:
		ds -= 0.4
	sq_stam[s] = clampf(sq_stam[s] + ds * DT, 0.0, 100.0)
	# --- бегство и возвращение
	if sq_status[s] == Status.FLEE:
		sq_flee_t[s] += DT
		sq_x[s] = sq_cx[s]
		sq_z[s] = sq_cz[s]
		if sq_morale[s] >= _flee_threshold(s) + MORALE_RALLY_GAP and enemy_d > 45.0:
			sq_status[s] = Status.READY
			sq_flee_t[s] = 0.0
			sq_melee[s] = 0
			sq_h[s] = _heading_to_enemy(s)
			order_hold(s, sq_h[s])
			rallied.emit(s, Vector3(sq_cx[s], 0.0, sq_cz[s]))
		return
	if sq_single[s] == 0 and sq_morale[s] < _flee_threshold(s):
		sq_status[s] = Status.FLEE
		sq_flee_t[s] = 0.0
		sq_melee[s] = 0
		sq_couched[s] = 0
		for u in sq_members[s]:
			u_couched[u] = 0
			u_target[u] = -1
			u_fire_t[u] = -1.0
			if u_act[u] == Act.AIM:
				u_act[u] = Act.NONE
		rout.emit(s, Vector3(sq_cx[s], 0.0, sq_cz[s]))
		return
	# --- движение якоря строя
	var spd := squad_speed(s)
	# отставание бойцов от мест в строю (раз в 3 шага — дорого)
	if (steps + s) % 3 == 0:
		var lag_sum := 0.0
		var cnt := 0
		for u in sq_members[s]:
			if u_life[u] == Life.ALIVE and u_role[u] == Role.TROOPER:
				lag_sum += slot_point(s, u).distance_to(Vector2(u_x[u], u_z[u]))
				cnt += 1
		sq_lag[s] = lag_sum / cnt if cnt > 0 else 0.0
	var lag := sq_lag[s]
	if lag > 2.5 and sq_couched[s] == 0:
		spd *= clampf(1.0 - (lag - 2.5) * 0.15, 0.35, 1.0)
	var tx := sq_tx[s]
	var tz := sq_tz[s]
	var tgt := sq_target[s]
	if sq_order[s] == Order.ATTACK:
		if tgt < 0 or sq_alive[tgt] == 0:
			order_hold(s)
		else:
			tx = sq_cx[tgt]
			tz = sq_cz[tgt]
			# натиск: копья наперевес на подходе
			if mounted and sq_charge_ok[s] == 1 and sq_couched[s] == 0 and sq_impacted[s] == 0 \
					and sq_gait[s] == Gait.RUN and sq_stam[s] >= STAMINA_NO_CHARGE \
					and front_distance(s, tgt) < CHARGE_COUCH_DIST:
				sq_couched[s] = 1
				for u in sq_members[s]:
					if u_life[u] == Life.ALIVE:
						u_couched[u] = 1
						u_charged[u] = 0
						u_rams[u] = 0
				charge_ordered.emit(s)
			# строй распадается в свалку, когда враг рядом
			var engaged := 0
			for u in sq_members[s]:
				if u_life[u] == Life.ALIVE and (u_target[u] >= 0 or u_charged[u] == 1):
					engaged += 1
			if engaged * 3 > sq_alive[s] or sq_status[tgt] == Status.FLEE and enemy_d < 30.0:
				sq_melee[s] = 1
	var ox := sq_x[s]
	var oz := sq_z[s]
	sq_vx[s] = 0.0
	sq_vz[s] = 0.0
	if sq_melee[s] == 1:
		sq_x[s] = sq_cx[s]
		sq_z[s] = sq_cz[s]
		if tgt >= 0:
			sq_h[s] = rotate_toward(sq_h[s], atan2(sq_cx[tgt] - sq_cx[s], sq_cz[tgt] - sq_cz[s]), 1.5 * DT)
		return
	var dx := tx - sq_x[s]
	var dz := tz - sq_z[s]
	var dist := sqrt(dx * dx + dz * dz)
	if sq_order[s] != Order.HOLD and dist > 0.3:
		var want := atan2(dx, dz)
		var turn := 1.1 if mounted else 0.7
		sq_h[s] = rotate_toward(sq_h[s], want, turn * DT)
		# строй разворачивается на месте, потом идёт
		var align := clampf(cos(angle_difference(sq_h[s], want)), 0.0, 1.0)
		var stepd := minf(dist, spd * DT * align * align)
		sq_x[s] += dx / dist * stepd
		sq_z[s] += dz / dist * stepd
	elif sq_order[s] == Order.MOVE:
		order_hold(s, sq_th[s])
	if sq_order[s] == Order.HOLD and not is_nan(sq_th[s]):
		sq_h[s] = rotate_toward(sq_h[s], sq_th[s], (1.0 if mounted else 0.6) * DT)
	sq_vx[s] = (sq_x[s] - ox) / DT
	sq_vz[s] = (sq_z[s] - oz) / DT
	# --- огонь шеренгами
	_fire_control(s)


func _fire_control(s: int) -> void:
	var t := sq_fire_target[s]
	var r := sq_volley_rank[s]
	if t < 0 or r < 0 or sq_alive[t] == 0 or sq_status[t] == Status.FLEE and r == 0:
		return
	var ti := sq_type[s]
	if t_flags[ti] & (UnitStats.MUSKET | UnitStats.BOW) == 0:
		return
	var ranks := ceili(float(sq_members[s].size()) / maxi(sq_files[s], 1))
	if r == 0:
		if front_distance(s, t) > sq_fire_dist[s]:
			return
		_fire_rank(s, 0)
		sq_volley_rank[s] = 1
		sq_volley_t[s] = time + 1.7 + rng.range_f(0.0, 0.3)
	elif r < ranks and r < 4:
		if time < sq_volley_t[s]:
			return
		_fire_rank(s, r)
		sq_volley_rank[s] = r + 1
		sq_volley_t[s] = time + 1.7 + rng.range_f(0.0, 0.3)
	else:
		# все шеренги выстрелили: ждём перезарядку первой
		if time > sq_volley_t[s] + t_reload[ti] - 1.5:
			sq_volley_rank[s] = 0
			sq_volley_seen[s] = -1


func _fire_rank(s: int, r: int) -> void:
	var t := sq_fire_target[s]
	var ti := sq_type[s]
	var rng_max := t_range[ti]
	for u in sq_members[s]:
		if u_life[u] != Life.ALIVE or u_role[u] != Role.TROOPER or rank_of(u) != r:
			continue
		if u_reload_t[u] > time or u_fire_t[u] >= 0.0 or u_ammo[u] == 0:
			continue
		if u_target[u] >= 0:
			continue  # дерётся вплотную
		var aim := _pick_shot_target(u, t, rng_max)
		if aim < 0:
			continue
		var start := time + rng.range_f(0.0, 0.25)
		u_act[u] = Act.AIM
		u_act_t[u] = start
		u_fire_t[u] = start + SHOOT_FIRE_DELAY + rng.range_f(0.0, 0.12)
		u_aim[u] = aim


## Цель выстрела: враг отряда t напротив стрелка (по боковому смещению), с разбросом
func _pick_shot_target(u: int, t: int, max_range: float) -> int:
	var fx := sin(u_h[u])
	var fz := cos(u_h[u])
	var best := -1
	var bscore := INF
	for v in sq_members[t]:
		if u_life[v] != Life.ALIVE:
			continue
		var dx := u_x[v] - u_x[u]
		var dz := u_z[v] - u_z[u]
		var fwd := dx * fx + dz * fz
		if fwd <= 1.0 or fwd > max_range:
			continue
		var lat := absf(-dx * fz + dz * fx)
		var score := lat + fwd * 0.15 + rng.next_float() * 6.0
		if score < bscore:
			bscore = score
			best = v
	return best


func _units_think() -> void:
	var seek_phase := steps % 6
	for u in n:
		if u_life[u] != Life.ALIVE:
			u_dvx[u] = 0.0
			u_dvz[u] = 0.0
			continue
		var s := u_squad[u]
		var ti := u_type[u]
		var mounted := t_flags[ti] & UnitStats.MOUNTED != 0
		var vmax := t_speed[ti] * _tired(s)
		if not _surely_dry(u_x[u], u_z[u]) and Terrain.is_water(u_x[u], u_z[u]):
			vmax *= 0.55
		var x := u_x[u]
		var z := u_z[u]
		var gx := x
		var gz := z
		var spd := 0.0
		var stop := 0.15
		# --- бегство: прочь от врага, к своему краю поля
		if sq_status[s] == Status.FLEE:
			var e := _nearest_enemy_squad(s)
			var away := Vector2(1.0 if u_side[u] == 0 else -1.0, 0.0)
			if e >= 0:
				var d := Vector2(x - sq_cx[e], z - sq_cz[e])
				if d.length() > 0.1:
					away = (away + d.normalized() * 1.3).normalized()
			away = away.rotated((u_var[u] - 0.5) * 0.9)
			gx = x + away.x * 10.0
			gz = z + away.y * 10.0
			spd = vmax * (0.82 + 0.18 * u_var[u])
			u_target[u] = -1
			_set_desire(u, gx, gz, spd, stop)
			continue
		# --- поиск цели (вразнобой, раз в 6 шагов)
		var tg := u_target[u]
		if tg >= 0 and (u_life[tg] != Life.ALIVE):
			tg = -1
		var engage_r := 4.0
		if sq_order[s] == Order.ATTACK:
			engage_r = 9.0 if mounted else 6.0
		if sq_melee[s] == 1:
			engage_r = 16.0
			var st := sq_target[s]
			if st >= 0 and sq_status[st] == Status.FLEE:
				engage_r = 36.0  # погоня
		if (u + seek_phase) % 6 == 0 or tg < 0 and u_couched[u] == 0:
			if u_couched[u] == 1 and u_charged[u] == 0:
				tg = -1  # на разгоне не отвлекаемся
			else:
				var c := nearest_enemy(u, engage_r)
				# бегущих гонят только по приказу атаки
				if c >= 0 and sq_status[u_squad[c]] == Status.FLEE and sq_order[s] != Order.ATTACK:
					c = -1
					tg = -1
				if c >= 0:
					tg = c
				elif tg >= 0 and Vector2(u_x[tg] - x, u_z[tg] - z).length() > engage_r * 1.5:
					tg = -1
		u_target[u] = tg
		# --- натиск: таранный удар о врага впереди (до двух шеренг, пока есть разгон)
		if u_couched[u] == 1 and u_charged[u] == 0:
			var hv := sqrt(u_vx[u] * u_vx[u] + u_vz[u] * u_vz[u])
			if hv > t_speed[ti] * 0.45:
				var c2 := nearest_enemy(u, t_radius[ti] + 1.6, 0.35)
				if c2 >= 0 and c2 != u_target[u]:
					_charge_hit(u, c2, hv / t_speed[ti])
					tg = c2
					u_target[u] = c2
			elif u_target[u] >= 0:
				# разгон потерян: натиск кончился
				u_charged[u] = 1
				u_couched[u] = 0
		# --- куда идти
		if u_couched[u] == 1 and u_charged[u] == 0:
			# сквозь строй: место в строю, вынесенное далеко вперёд
			var p := slot_point(s, u)
			var f := squad_forward(s)
			gx = p.x + f.x * 30.0
			gz = p.y + f.y * 30.0
			spd = vmax
		elif tg >= 0:
			var rr := t_radius[ti] + t_radius[u_type[tg]]
			gx = u_x[tg]
			gz = u_z[tg]
			stop = rr + t_reach[ti] * 0.55
			spd = vmax * (0.45 if mounted else 0.8)
			if sq_status[u_squad[tg]] == Status.FLEE:
				spd = vmax  # погоня
			_try_melee(u, tg, rr)
		else:
			# место в строю: скорость якоря + поправка к месту
			var p2 := slot_point(s, u)
			var ex := p2.x - x
			var ez := p2.y - z
			var vx := sq_vx[s] + ex * 1.4
			var vz := sq_vz[s] + ez * 1.4
			var vl := sqrt(vx * vx + vz * vz)
			if vl > vmax:
				vx *= vmax / vl
				vz *= vmax / vl
			if ex * ex + ez * ez < 0.04 and sq_vx[s] == 0.0 and sq_vz[s] == 0.0:
				vx = 0.0
				vz = 0.0
			u_dvx[u] = vx
			u_dvz[u] = vz
			continue
		_set_desire(u, gx, gz, spd, stop)


func _set_desire(u: int, gx: float, gz: float, spd: float, stop: float) -> void:
	var dx := gx - u_x[u]
	var dz := gz - u_z[u]
	var d := sqrt(dx * dx + dz * dz)
	if d <= stop or spd <= 0.0:
		u_dvx[u] = 0.0
		u_dvz[u] = 0.0
		return
	# у цели замедляемся
	var v := minf(spd, (d - stop) * 1.6)
	u_dvx[u] = dx / d * v
	u_dvz[u] = dz / d * v


func _try_melee(u: int, tg: int, rr: float) -> void:
	if time < u_cool_t[u] or u_hit_t[u] >= 0.0 or u_fire_t[u] >= 0.0:
		return
	var ti := u_type[u]
	var d := Vector2(u_x[tg] - u_x[u], u_z[tg] - u_z[u]).length()
	if d > rr + t_reach[ti]:
		return
	u_act[u] = Act.MELEE
	u_act_t[u] = time
	u_hit_t[u] = time + MELEE_HIT_DELAY
	u_cool_t[u] = time + 1.35 + rng.range_f(0.0, 0.5)


func _charge_hit(u: int, tg: int, speed_frac: float) -> void:
	u_rams[u] += 1
	if u_rams[u] >= RAM_MAX:
		u_charged[u] = 1
		u_couched[u] = 0
	var s := u_squad[u]
	var ti := u_type[u]
	var ts := u_squad[tg]
	var tti := u_type[tg]
	var mult := t_charge[ti] * _tired(s) * clampf(speed_frac * 1.1, 0.5, 1.0)
	if sq_form[ts] == Formation.SQUARE:
		mult = maxf(1.0, mult * SQUARE_ABSORB)
	var counter := 0.0
	if t_flags[tti] & UnitStats.SPEAR != 0 and sq_status[ts] != Status.FLEE:
		mult = maxf(1.0, mult * SPEAR_ABSORB)
		counter = t_attack[tti] * t_vs_cav[tti]
	var dmg := maxf(1.0, t_attack[ti] * mult - t_armour[tti])
	var f := Vector2(u_vx[u], u_vz[u])
	var spd := f.length()
	f = f / maxf(spd, 0.01)
	# отброс пехоты, конь теряет разгон
	var push := 5.5 / maxf(t_mass[tti], 1.0)
	u_kx[tg] += f.x * push + (u_var[tg] - 0.5) * 2.0
	u_kz[tg] += f.y * push + (BattleRng.hash01(tg) - 0.5) * 2.0
	u_vx[u] *= 0.68
	u_vz[u] *= 0.68
	var pos := Vector3((u_x[u] + u_x[tg]) * 0.5, 0.0, (u_z[u] + u_z[tg]) * 0.5)
	pos.y = Terrain.height_at(pos.x, pos.z)
	if sq_impacted[s] == 0:
		sq_impacted[s] = 1
		sq_morale[ts] = maxf(0.0, sq_morale[ts] - MORALE_IMPACT)
		impact.emit(s, pos, spd)
	sq_morale[ts] = maxf(0.0, sq_morale[ts] - MORALE_CHARGE_SHOCK * 100.0 / maxf(sq_init[ts], 1))
	charge_hit.emit(u, tg, pos)
	_damage(tg, dmg, u)
	if counter > 0.0:
		_damage(u, maxf(1.0, counter - t_armour[ti]), tg)


func _resolve_actions() -> void:
	for u in n:
		var life := u_life[u]
		if life == Life.DYING:
			var dur := DEATH_DURATION_HORSE if t_flags[u_type[u]] & UnitStats.MOUNTED != 0 else DEATH_DURATION_HUMAN
			if time - u_death_t[u] >= dur:
				u_life[u] = Life.DEAD
			continue
		if life != Life.ALIVE:
			continue
		# выстрел
		if u_fire_t[u] >= 0.0 and time >= u_fire_t[u]:
			_fire(u)
		# удар
		if u_hit_t[u] >= 0.0 and time >= u_hit_t[u]:
			u_hit_t[u] = -1.0
			_melee_hit(u)
		# конец разовых действий
		match u_act[u]:
			Act.MELEE:
				if time - u_act_t[u] >= MELEE_DURATION:
					u_act[u] = Act.NONE
			Act.CHEER:
				if time - u_act_t[u] >= CHEER_DURATION:
					u_act[u] = Act.NONE
			Act.AIM:
				if u_fire_t[u] < 0.0 and time - u_act_t[u] >= SHOOT_DURATION:
					u_act[u] = Act.NONE


func _fire(u: int) -> void:
	u_fire_t[u] = -1.0
	var ti := u_type[u]
	var s := u_squad[u]
	u_reload_t[u] = time + t_reload[ti]
	if u_ammo[u] > 0:
		u_ammo[u] -= 1
	var tg := u_aim[u]
	var h := u_h[u]
	var fx := sin(h)
	var fz := cos(h)
	var m := SHOOT_MUZZLE
	var muzzle := Vector3(u_x[u] + fz * m.x + fx * m.z, 0.0, u_z[u] - fx * m.x + fz * m.z)
	muzzle.y = Terrain.height_at(u_x[u], u_z[u]) + m.y
	var dir := Vector3(fx, 0.02, fz)
	var hit := false
	if tg >= 0 and u_life[tg] == Life.ALIVE:
		var d := Vector2(u_x[tg] - u_x[u], u_z[tg] - u_z[u])
		var dist := d.length()
		if dist <= t_range[ti] * 1.05:
			dir = Vector3(d.x / dist, 0.02, d.y / dist)
			var k := clampf((dist - 10.0) / maxf(t_range[ti] - 10.0, 1.0), 0.0, 1.0)
			var acc := lerpf(t_acc_near[ti], t_acc_far[ti], k)
			if sq_form[u_squad[tg]] == Formation.LOOSE:
				acc *= 0.6
			if rng.next_float() < acc:
				hit = true
				_missile_hit(u, tg)
	var r := rank_of(u)
	if r > sq_volley_seen[s] and r < 99:
		sq_volley_seen[s] = r
		var c := Vector3.ZERO
		var cnt := 0
		for v in sq_members[s]:
			if u_role[v] == Role.TROOPER and rank_of(v) == r and u_life[v] == Life.ALIVE:
				c += Vector3(u_x[v], 0.0, u_z[v])
				cnt += 1
		if cnt > 0:
			c /= cnt
		c.y = Terrain.height_at(c.x, c.z)
		volley.emit(s, r, c, cnt)
	shot.emit(u, muzzle, dir, hit)


func _missile_hit(u: int, tg: int) -> void:
	var ti := u_type[u]
	var tti := u_type[tg]
	var dmg := t_missile[ti]
	var armour := t_armour[tti]
	var musket := t_flags[ti] & UnitStats.MUSKET != 0
	if musket:
		armour *= MUSKET_PIERCE
		# пуля валит коня
		if t_flags[tti] & UnitStats.MOUNTED != 0 and rng.next_float() < HORSE_DOWN:
			_damage(tg, u_hp[tg] + 1.0, u)
			return
	elif t_flags[tti] & UnitStats.SHIELD != 0:
		dmg *= 0.5
	_damage(tg, maxf(1.0, dmg - armour), u)


func _melee_hit(u: int) -> void:
	var tg := u_target[u]
	if tg < 0 or u_life[tg] != Life.ALIVE:
		return
	var ti := u_type[u]
	var tti := u_type[tg]
	var rr := t_radius[ti] + t_radius[tti]
	var d := Vector2(u_x[tg] - u_x[u], u_z[tg] - u_z[u]).length()
	if d > rr + t_reach[ti] + 0.8:
		return
	var fleeing := sq_status[u_squad[tg]] == Status.FLEE
	if rng.next_float() > (0.75 if fleeing else 0.62):
		return
	var dmg := t_attack[ti] * _tired(u_squad[u])
	if t_flags[tti] & UnitStats.MOUNTED != 0:
		dmg *= t_vs_cav[ti]
	if fleeing:
		dmg *= 1.2
	var pos := Vector3((u_x[u] + u_x[tg]) * 0.5, 0.0, (u_z[u] + u_z[tg]) * 0.5)
	pos.y = Terrain.height_at(pos.x, pos.z) + (1.7 if t_flags[ti] & UnitStats.MOUNTED != 0 else 1.2)
	melee_hit.emit(u, tg, pos)
	_damage(tg, maxf(1.0, dmg - t_armour[tti]), u)


func _damage(tg: int, dmg: float, attacker: int) -> void:
	if u_life[tg] != Life.ALIVE:
		return
	u_hp[tg] -= dmg
	if u_hp[tg] <= 0.0:
		_kill(tg, attacker)


func _kill(u: int, attacker: int) -> void:
	u_life[u] = Life.DYING
	u_death_t[u] = time
	u_hp[u] = 0.0
	u_fire_t[u] = -1.0
	u_hit_t[u] = -1.0
	u_act[u] = Act.NONE
	u_couched[u] = 0
	# падает на бок, противоположный удару
	var side := 0
	if attacker >= 0:
		var h := u_h[u]
		var lx := cos(h)
		var lz := -sin(h)
		side = 1 if (u_x[attacker] - u_x[u]) * lx + (u_z[attacker] - u_z[u]) * lz > 0.0 else 0
	u_fall[u] = side
	var s := u_squad[u]
	sq_alive[s] = maxi(sq_alive[s] - 1, 0)
	if sq_single[s] == 0:
		sq_morale[s] = maxf(0.0, sq_morale[s] - MORALE_LOSS * 100.0 / maxf(sq_init[s], 1))
	if u_role[u] == Role.OFFICER:
		sq_morale[s] = maxf(0.0, sq_morale[s] - MORALE_OFFICER)
	if u_role[u] == Role.GENERAL:
		for t in squads:
			if sq_side[t] == u_side[u]:
				sq_morale[t] = maxf(0.0, sq_morale[t] - MORALE_GENERAL)
	death.emit(u, _pos3(u))


func _integrate() -> void:
	var decay := exp(-6.0 * DT)
	for u in n:
		var life := u_life[u]
		if life == Life.DEAD:
			continue
		var ti := u_type[u]
		var mounted := t_flags[ti] & UnitStats.MOUNTED != 0
		if life == Life.DYING:
			# по инерции, тело/конь скользит и встаёт
			var k := exp(-(2.2 if mounted else 4.0) * DT)
			u_vx[u] *= k
			u_vz[u] *= k
			u_x[u] += (u_vx[u] + u_kx[u]) * DT
			u_z[u] += (u_vz[u] + u_kz[u]) * DT
			u_kx[u] *= decay
			u_kz[u] *= decay
			continue
		var acc := (4.2 if mounted else 4.0) * DT
		var ax := u_dvx[u] - u_vx[u]
		var az := u_dvz[u] - u_vz[u]
		var al := sqrt(ax * ax + az * az)
		# тормозим резче, чем разгоняемся
		var lim := acc * (1.6 if u_dvx[u] * u_vx[u] + u_dvz[u] * u_vz[u] < u_vx[u] * u_vx[u] + u_vz[u] * u_vz[u] else 1.0)
		if al > lim:
			ax *= lim / al
			az *= lim / al
		u_vx[u] += ax
		u_vz[u] += az
		u_x[u] += (u_vx[u] + u_kx[u]) * DT
		u_z[u] += (u_vz[u] + u_kz[u]) * DT
		u_kx[u] *= decay
		u_kz[u] *= decay
		# курс: по ходу, на месте — к цели или по строю
		var sp := sqrt(u_vx[u] * u_vx[u] + u_vz[u] * u_vz[u])
		var want := u_h[u]
		var tg := u_target[u]
		if sp > 0.6:
			want = atan2(u_vx[u], u_vz[u])
		elif tg >= 0 and u_life[tg] == Life.ALIVE:
			want = atan2(u_x[tg] - u_x[u], u_z[tg] - u_z[u])
		elif sq_status[u_squad[u]] == Status.READY:
			want = sq_h[u_squad[u]]
		var rate := (2.6 if mounted else 5.0) * (1.6 if sp < 1.0 else 1.0)
		u_h[u] = rotate_toward(u_h[u], want, rate * DT)
	_separate()


## Расталкивание: никто не стоит друг в друге (пространственный хэш, одна итерация)
func _separate() -> void:
	for u in n:
		if u_life[u] != Life.ALIVE:
			continue
		var x := u_x[u]
		var z := u_z[u]
		var ru := t_radius[u_type[u]]
		var mu := t_mass[u_type[u]]
		var cx := clampi(int((x - _GRID_ORIGIN) / _CELL), 0, _GRID_N - 1)
		var cz := clampi(int((z - _GRID_ORIGIN) / _CELL), 0, _GRID_N - 1)
		for gz in range(maxi(cz - 1, 0), mini(cz + 1, _GRID_N - 1) + 1):
			for gx in range(maxi(cx - 1, 0), mini(cx + 1, _GRID_N - 1) + 1):
				# списки клеток идут по убыванию номера: после v <= u пар (v > u) в клетке больше нет
				var v := _head[gz * _GRID_N + gx]
				while v > u:
					if u_life[v] == Life.ALIVE:
						var dx := u_x[v] - u_x[u]
						var dz := u_z[v] - u_z[u]
						var rr := ru + t_radius[u_type[v]]
						var d2 := dx * dx + dz * dz
						if d2 < rr * rr:
							var d := sqrt(d2)
							if d < 0.001:
								dx = BattleRng.hash01(u * 7 + v) - 0.5
								dz = BattleRng.hash01(v * 13 + u) - 0.5
								d = sqrt(dx * dx + dz * dz)
							var over := (rr - d) / d
							var mv := t_mass[u_type[v]]
							var ku := mv / (mu + mv)
							var kv := 1.0 - ku
							u_x[u] -= dx * over * ku
							u_z[u] -= dz * over * ku
							u_x[v] += dx * over * kv
							u_z[v] += dz * over * kv
					v = _next[v]


func _victory_check() -> void:
	if winner >= 0:
		return
	for side in 2:
		if side_init[side] == 0:
			continue
		var alive := 0
		var all_flee := true
		var any := false
		for s in squads:
			if sq_side[s] != side or sq_alive[s] == 0:
				continue
			alive += sq_alive[s]
			if sq_single[s] == 1:
				continue
			any = true
			if sq_status[s] != Status.FLEE:
				all_flee = false
		if any and all_flee:
			side_flee_t[side] += DT
		else:
			side_flee_t[side] = 0.0
		if float(alive) < ARMY_LEFT_LOSE * side_init[side] or side_flee_t[side] > FLEE_VICTORY_TIME:
			winner = 1 - side
			battle_over.emit(winner)
			return


# ================================================================= служебное

func _pos3(u: int) -> Vector3:
	return Vector3(u_x[u], Terrain.height_at(u_x[u], u_z[u]), u_z[u])


## Контрольная сумма состояния (проверка детерминизма)
func checksum() -> int:
	var h := 17
	for u in n:
		h = (h * 31 + int(u_x[u] * 1000.0)) & 0x7FFFFFFF
		h = (h * 31 + int(u_z[u] * 1000.0)) & 0x7FFFFFFF
		h = (h * 31 + int(u_hp[u] * 100.0)) & 0x7FFFFFFF
		h = (h * 31 + u_life[u]) & 0x7FFFFFFF
	for s in squads:
		h = (h * 31 + int(sq_morale[s] * 100.0)) & 0x7FFFFFFF
	return h


static func rotate_toward(from: float, to: float, max_step: float) -> float:
	var d := angle_difference(from, to)
	return from + clampf(d, -max_step, max_step)
