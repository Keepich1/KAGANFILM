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
##
## «Город» (ARCHITECTURE §6.2, R1–R15). Всё новое по умолчанию выключено — бой среза тот же бит в бит
## (tests/test_combat_slice.gd). Включает город CombatPortBattle (единственный, кто зовёт изменяющие методы):
##   • жизнь слотов: FREE, свободные списки, поколения u_gen/sq_gen; тела убираются через corpse_steps;
##     remove_unit — уход без смерти; слот снова выдаётся не раньше следующего шага (старые ссылки отмирают);
##   • одиночка = отряд из одного (sq_single = 1): без поиска ближайшего отряда, морали и отставания,
##     якорь разворачивается быстро (кроме полководца — он как в срезе); spawn_single, form_squad, disband_squad;
##   • u_side/sq_side — команда, u_owner/sq_owner — игрок; victory_mode, flee_mode, team_home;
##   • пути (set_path, await_path, sq_path/sq_wp), структуры (structure_set/clear, OBB-столкновения, цели
##     order_attack_structure, попадания в ev_st_*), сетки NAV (set_grids: _blk_static, _spd), стойки (sq_stance),
##     множители игроков (set_owner_mods), сон (sleep_enabled), работа (set_work), буферы ev_* (collect_events);
##   • пролом: путь с breach_st/breach_wp — у точки перед постройкой отряд ломает её, потом прежний приказ.
## Шаг города (sleep_enabled, ставить до юнитов): обходит только бодрых и падающих (_aw); спящие лежат в хэше
## и будятся врагом в 16 м (блоки _mixed), толчком (2 раза в с), приказом, уроном, сменой мест в отряде.
## Хэш города правится на месте (двусвязные списки клеток, маски); срез и город без сна собирают его целиком.
## Фон (SimStepper): во время step() массивы u_*/sq_*/st_* меняются только на месте, никогда не переприсваиваются;
## новые юниты и отряды (растут массивы) — только вне step(), со стороны порта. Хэш готов в конце шага
## (и при изменениях снаружи — лениво при запросе), поэтому запросы порта между шагами видят точные позиции;
## запросы тоже правят хэш — звать их только между шагами (или после BattleView.sync_sim()).

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
enum Life { ALIVE, DYING, DEAD, FREE }          # FREE — слот свободен («Город», R1)
enum Act { NONE, AIM, MELEE, CHEER, WORK }      # WORK — работа: вид в u_work (AnimSpec.WORK_*)
enum Role { TROOPER, OFFICER, BANNER, GENERAL }

# ---------------------------------------------------------------- «Город» (ARCHITECTURE §6.2): объявления M0.
# Поведение — у CORE (R1–R18); всё по умолчанию = срез, test_sim сверяет ту же контрольную сумму.
enum Stance { AGGRESSIVE, DEFENSIVE, HOLD, PASSIVE }
enum Victory { BATTLE, NONE }
enum FleeMode { DIR, HOME }
const MAX_TEAMS := 4
const ST_BLOCK := 1; const ST_WALL := 2; const ST_GATE := 4; const ST_TOWER := 8
const ST_FIELD := 16; const ST_HQ := 32; const ST_SITE := 64          # флаги структур
const MOD_ATK := 0; const MOD_SPEED := 1; const MOD_STAM := 2; const MOD_MORALE := 3; const MOD_RANGE := 4; const MOD_N := 5

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

const _CELL := 4.0
const _GRID_N_DEFAULT := 256         # срез: −512 м, 256 клеток по 4 м (set_bounds меняет)
const WAKE_CHECK_STEPS := 15         # спящие проверяют сдвиг с места раз в 0,5 с (вразнобой)
const SINGLE_TURN := 8.0             # рад/с: разворот якоря одиночки (R2)
const SINGLE_LEASH := 3.0            # м: якорь одиночки не уходит дальше от него (упёрся — ждёт)
const STUCK_STEPS := 60              # 2 с без хода у якоря-одиночки → ev_repath
const WP_REACH := 2.0                # м: точка пути пройдена (у одиночек — 1 м)
const ST_MELEE_COOL := 1.4           # с: удар по постройке (ECONOMY §1.6: «удар раз в 1,4 с»)
const ST_BUCKET := 32.0              # м: корзины структур для столкновений
const DEF_REACH_PAD := 1.0           # DEFENSIVE: цель не дальше досягаемости + 1 м
const DEF_LEASH := 6.0               # DEFENSIVE: дальше 6 м от места не гонится
const RAIDER_WORKER_K := 0.25        # RAIDER: работник «ближе» (×0,25 квадрата расстояния)

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
var t_vs_building := PackedFloat32Array()   # R8: множитель по постройкам
var t_splash := PackedFloat32Array()        # этап 2 (ядра)
var t_min_range := PackedFloat32Array()     # этап 2

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

var side_init := PackedInt32Array([0, 0, 0, 0])               # по MAX_TEAMS
var side_flee_t := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var general := PackedInt32Array([-1, -1, -1, -1])   # юнит-полководец стороны

# ---------------------------------------------------------------- «Город»: настройки (по умолчанию = срез)
var victory_mode := Victory.BATTLE
var flee_mode := FleeMode.DIR
var corpse_steps := -1                  # −1 — тела не исчезают (срез); город: 30 с × 30
var team_home := PackedVector2Array()   # цели бегства FleeMode.HOME
var sleep_enabled := false:             # сон (R12): город — да; срез — нет (бит в бит). Ставить до юнитов
	set(v):
		if v and not sleep_enabled:
			# включили при живых юнитах: все — в бодрые, хэш города — заново
			for u in n:
				if u_life[u] == Life.ALIVE or u_life[u] == Life.DYING:
					_aw_join(u)
			_hash_full = true
			_hash_dirty = true
		sleep_enabled = v
var collect_events := false             # буферы ev_* (R10): город — да (их забирает порт)

# юниты: новые массивы (растут в _new_unit со значениями по умолчанию)
var u_gen := PackedInt32Array()         # 1..4095
var u_owner := PackedInt32Array()       # игрок (по умолчанию = сторона)
var u_killer := PackedInt32Array()      # индекс убийцы в ядре, −1
var u_hurt_step := PackedInt32Array()   # шаг последнего урона, −1
var u_sleep := PackedByteArray()        # 1 — спит (R12)
var u_work := PackedFloat32Array()      # вид работы Act.WORK, −1 — нет
var u_garrison := PackedInt32Array()    # структура гарнизона, −1 (этап 2)

# отряды: новые массивы
var sq_gen := PackedInt32Array()
var sq_owner := PackedInt32Array()
var sq_stance := PackedInt32Array()
var sq_path: Array[PackedVector2Array] = []
var sq_wp := PackedInt32Array()         # следующая точка пути
var sq_breach_st := PackedInt32Array()  # структура, которую ломать у точки sq_breach_wp, −1
var sq_breach_wp := PackedInt32Array()
var sq_st_target := PackedInt32Array()  # цель-структура, −1
var sq_enemy := PackedInt32Array()      # ближайший вражеский отряд (раз за шаг, настоящие отряды)
var sq_trail: Array[PackedVector2Array] = []   # последние 8 точек якоря (ворота: бойцы идут по следу)
var sq_used := PackedByteArray()        # 1 — слот отряда занят, 0 — свободен (R1)
var sq_stuck := PackedInt32Array()      # шагов якорь-одиночка ждёт своего бойца (упёрся)
var sq_dorm := PackedByteArray()        # 1 — одиночка спит: шаг отряда и центр пропускаются (R12)
var _real_sq := PackedInt32Array()      # настоящие отряды (город: поиск ближайшего вражеского отряда)
var _rs_dirty := true
var _br_order := PackedInt32Array()     # пролом: приказ до него (вернётся, когда постройка падёт)
var _br_target := PackedInt32Array()
var _br_st := PackedInt32Array()

# зеркало структур (индекс = слот здания ECON)
var st_hw := 0
var st_ref := PackedInt32Array()
var st_team := PackedInt32Array()
var st_flags := PackedInt32Array()
var st_alive := PackedInt32Array()
var st_gar_cap := PackedInt32Array()
var st_gar_n := PackedInt32Array()
var st_cx := PackedFloat32Array()       # центр, полуразмеры, курс, высота площадки
var st_cz := PackedFloat32Array()
var st_hx := PackedFloat32Array()
var st_hz := PackedFloat32Array()
var st_rot := PackedFloat32Array()
var st_top := PackedFloat32Array()

# сетки земли (от NAV; пусто — путь Terrain.is_water, как в срезе)
var _blk_static := PackedByteArray()    # 1 — непроходимо (обрыв, глубокая вода)
var _spd := PackedByteArray()           # скорость ×16 на клетку 4 м (мелкая вода 0,55 → 9)

# множители по игрокам [owner * MOD_N + k], по умолчанию 1.0
var own_mods := PackedFloat32Array()

# буферы, которые забирает CombatPortBattle (заполняются за шаг)
var ev_dead := PackedInt32Array()       # пары (u, killer)
var ev_st_b := PackedInt32Array()
var ev_st_dmg := PackedFloat32Array()
var ev_st_by := PackedInt32Array()
var ev_arrived := PackedInt32Array()    # отряды, у которых закончился MOVE
var ev_repath := PackedInt32Array()     # отряды, которым нужен новый путь

# свободные слоты (R1): номер и шаг освобождения; слот выдаётся снова только на следующем шаге
var _u_free := PackedInt32Array()
var _u_free_at := PackedInt32Array()
var _sq_free := PackedInt32Array()
var _sq_free_at := PackedInt32Array()

# хэш: границы (R6), по умолчанию — срез
var _g_origin := -512.0
var _g_n := _GRID_N_DEFAULT
var _b_n := _GRID_N_DEFAULT >> 2
var _hash_dirty := true                 # что-то изменилось снаружи после последней сборки хэша

# сетки NAV (set_grids): клетки 4 м от своего начала
var _grid_origin := Vector2.ZERO
var _grid_w := 0
var _grid_h := 0

# структуры: корзины 32 м (списки номеров), число живых
var _sb_n := 0
var _sb_origin := Vector2.ZERO
var _sb: Array[PackedInt32Array] = []
var _st_live := 0

var _head := PackedInt32Array()
var _next := PackedInt32Array()

# --- ускорители (только скорость; результат шага тот же бит в бит, test_sim сверяет сумму)
# стороны в клетках хэша и в блоках 4×4 клетки (бит 1 << сторона) — поиск врага пропускает пустое
const _BLK_SHIFT := 2
var _cmask := PackedInt32Array()
var _bmask := PackedInt32Array()
var _bmask_n := PackedInt32Array()      # блок и его 8 соседей (сон: враг ближе ~16 м будит)
var _ublk := PackedInt32Array()         # блок юнита при последней сборке хэша (сон)
var _ucell := PackedInt32Array()        # клетка юнита при последней сборке (−1 — считать заново)
# места в строю: смещения считаются один раз на отряд, пока не сменились строй и ширина
var _so_x := PackedFloat32Array()
var _so_y := PackedFloat32Array()
var _so_key := PackedInt64Array()
# суша в клетке хэша: 0 — не проверено, 1 — точно суша (вода не ближе 0,05 м по высоте), 2 — может быть вода
var _dry := PackedByteArray()

# --- город (сон включён, R12): шаг идёт только по бодрым, хэш правится на месте (спящие в нём лежат)
var _aw := PackedInt32Array()           # бодрые (ALIVE без сна) и падающие (DYING), по возрастанию номера
var _aw_on := PackedByteArray()         # 1 — юнит в _aw
var _aw_add := PackedInt32Array()       # проснулись или родились после сборки _aw: войдут в начале шага
var _aw_q := PackedByteArray()          # 1 — уже в _aw_add
var _all := PackedInt32Array()          # 0..n−1: обход «всех» тем же кодом (срез, город без сна)
var _sq_list := PackedInt32Array()      # отряды шага: одиночки бодрых и все настоящие, по возрастанию
var _sq_act := PackedByteArray()        # у настоящего отряда есть бодрые на этом шаге (временная отметка)
var _sq_still := PackedByteArray()      # настоящий отряд: все спят, центр уже посчитан
var _hprev := PackedInt32Array()        # хэш города: предыдущий в списке клетки (−1 — голова)
var _hq := PackedInt32Array()           # юниты, которых переложить в хэше (родились, убиты вне шага)
var _hash_full := true                  # хэш города собрать целиком (границы, первый шаг)
var _mixed := PackedInt32Array()        # блоки 16 м, где рядом две команды и больше (будят спящих)
var _mx_on := PackedByteArray()         # 1 — блок в _mixed
var _corpse := PackedInt32Array()       # тела по порядку смерти парами [юнит, поколение] (corpse_steps)
var _corpse_h := 0                      # голова очереди тел


func _init(p_seed := 1) -> void:
	rng = BattleRng.new(p_seed)
	_alloc_grid()


func _alloc_grid() -> void:
	_ucell.fill(-1)
	_head.resize(_g_n * _g_n)
	_head.fill(-1)
	_cmask.resize(_g_n * _g_n)
	_cmask.fill(0)
	_bmask.resize(_b_n * _b_n)
	_bmask.fill(0)
	_bmask_n.resize(_b_n * _b_n)
	_bmask_n.fill(0)
	_mx_on.resize(_b_n * _b_n)
	_mx_on.fill(0)
	_mixed.clear()
	_dry.resize(_g_n * _g_n)
	_dry.fill(0)
	_hash_dirty = true
	_hash_full = true


# ================================================================= «Город»: настройка

## Границы хэша (R6): начало карты и размер, м (Terrain.origin()/size). На карте среза — те же −512 / 256.
## Звать до первых юнитов (или между шагами: хэш соберётся заново).
func set_bounds(origin: Vector2, size: Vector2) -> void:
	_g_origin = minf(origin.x, origin.y)
	_g_n = maxi(1, ceili(maxf(size.x, size.y) / _CELL - 0.001))
	_b_n = (_g_n + 3) >> _BLK_SHIFT
	_alloc_grid()
	_make_buckets()


## Корзины структур под текущие границы (все живые структуры раскладываются заново)
func _make_buckets() -> void:
	_sb_origin = Vector2(_g_origin, _g_origin)
	_sb_n = maxi(1, ceili(_g_n * _CELL / ST_BUCKET))
	_sb.clear()
	_sb.resize(_sb_n * _sb_n)
	for i in _sb.size():
		_sb[i] = PackedInt32Array()
	for st in st_hw:
		if st_alive[st] == 1:
			_bucket_add(st)


## Сетки NAV (R7): клетки 4 м от origin, w × h. blk — 1 непроходимо (обрыв, глубокая вода),
## spd — скорость ×16 (16 = обычная, мелкая вода 9). Пустые — путь среза (Terrain.is_water).
func set_grids(origin: Vector2, w: int, h: int, blk: PackedByteArray, spd: PackedByteArray) -> void:
	_grid_origin = origin
	_grid_w = w
	_grid_h = h
	_blk_static = blk.duplicate() if blk.size() == w * h else PackedByteArray()
	_spd = spd.duplicate() if spd.size() == w * h else PackedByteArray()


## Заранее занять место под юнитов и отряды: массивы не растут (и не переезжают в памяти) до этих чисел
func reserve(units: int, p_squads: int) -> void:
	if units > u_x.size():
		_grow_units(units)
	if p_squads > sq_side.size():
		_grow_squads(p_squads)


## Множители игрока owner (R11): mods[MOD_*] (голод, времена года). Читаются через u_owner/sq_owner.
func set_owner_mods(owner: int, mods: PackedFloat32Array) -> void:
	if owner < 0:
		return
	var need := (owner + 1) * MOD_N
	if own_mods.size() < need:
		var old := own_mods.size()
		own_mods.resize(need)
		for i in range(old, need):
			own_mods[i] = 1.0
	for k in MOD_N:
		own_mods[owner * MOD_N + k] = mods[k] if k < mods.size() else 1.0


## Множитель MOD_k игрока owner (1 — нет)
func owner_mod(owner: int, k: int) -> float:
	var i := owner * MOD_N + k
	return own_mods[i] if owner >= 0 and i < own_mods.size() else 1.0


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
	t_vs_building.append(s.get("vs_building", 1.0))
	t_splash.append(s.get("splash", 0.0))
	t_min_range.append(s.get("min_range", 0.0))
	return type_ids.size() - 1


## Отряд: count бойцов типа type_id, якорь pos (центр первой шеренги), курс heading.
## files — ширина строя (0 — само), officer_type — офицер ("" — без), banner — знаменосец из бойцов.
## scatter — разброс начальных мест, м (отряд «собирается» в строй). owner — игрок (−1 — как side).
func add_squad(side: int, type_id: String, count: int, pos: Vector2, heading: float,
		formation := Formation.LINE, files := 0, officer_type := "", banner := true, scatter := 0.0,
		owner := -1) -> int:
	var s := _new_squad(side, type_index(type_id), pos, heading, owner)
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
	sq_members[s].append_array(members)  # на месте: читатели (вид) держат ссылку на список
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
func add_general(side: int, type_id: String, pos: Vector2, heading: float, owner := -1) -> int:
	var s := _new_squad(side, type_index(type_id), pos, heading, owner)
	sq_single[s] = 1
	sq_files[s] = 1
	var u := _new_unit(s, sq_type[s], Role.GENERAL, 0)
	sq_members[s].append(u)
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


## Одиночка (R2, «нанятый по одному»): отряд из одного, не бежит, якорь разворачивается быстро.
## Возвращает номер юнита (его отряд — u_squad[u]). general[team] не трогает (полководца — add_general).
func spawn_single(team: int, type_id: String, pos: Vector2, heading: float, owner := -1) -> int:
	var ti := type_index(type_id)
	var s := _new_squad(team, ti, pos, heading, owner)
	sq_single[s] = 1
	sq_files[s] = 1
	var role := Role.OFFICER if t_flags[ti] & UnitStats.OFFICER != 0 else Role.TROOPER
	var u := _new_unit(s, ti, role, 0)
	sq_members[s].append(u)
	sq_init[s] = 1
	sq_alive[s] = 1
	side_init[team] += 1
	u_x[u] = pos.x
	u_z[u] = pos.y
	u_px[u] = pos.x
	u_pz[u] = pos.y
	u_h[u] = heading
	u_ph[u] = heading
	_update_centroid(s)
	return u


## Юнит уходит из мира без смерти (сел в арбу, израсходован): слот свободен, в ev_dead не попадает
func remove_unit(u: int) -> void:
	if u < 0 or u >= n or u_life[u] == Life.FREE:
		return
	_free_unit(u)


## Убить юнита (тесты, инструменты): обычная смерть без убийцы (сигнал death, ev_dead [u, −1])
func kill_unit(u: int) -> void:
	if u >= 0 and u < n and u_life[u] == Life.ALIVE:
		_kill(u, -1)


## Офицер собирает отряд (R3): до 100 бойцов одного рода из members (род — первого годного),
## своей команды и своего игрока. Офицер — OFFICER, последний боец — знаменосец (BANNER). Прежние
## одиночки освобождаются, бойцы идут на места (тот же «сбор из толпы»). −1 — некого собрать.
func form_squad(officer: int, members: PackedInt32Array, formation := Formation.LINE, files := 0) -> int:
	if officer < 0 or officer >= n or u_life[officer] != Life.ALIVE:
		return -1
	var team := u_side[officer]
	var owner := u_owner[officer]
	var ti := -1
	var chosen := PackedInt32Array()
	for u in members:
		if u == officer or u < 0 or u >= n or u_life[u] != Life.ALIVE or u_side[u] != team or u_owner[u] != owner:
			continue
		if t_flags[u_type[u]] & (UnitStats.WORKER | UnitStats.GENERAL | UnitStats.OFFICER) != 0:
			continue
		if ti < 0:
			ti = u_type[u]
		if u_type[u] != ti or chosen.has(u):
			continue
		chosen.append(u)
		if chosen.size() >= 100:
			break
	if chosen.is_empty():
		return -1
	var c := Vector2.ZERO
	for u in chosen:
		c += Vector2(u_x[u], u_z[u])
	c /= chosen.size()
	var heading := u_h[officer]
	var s := _new_squad(team, ti, c, heading, owner)
	sq_form[s] = formation
	var count := chosen.size()
	sq_files[s] = files if files > 0 else maxi(1, ceili(count / 2.0))
	# якорь — центр первой шеренги: строй встаёт вокруг центра собравшихся
	var mounted := t_flags[ti] & UnitStats.MOUNTED != 0
	var ranks := ceili(float(count) / sq_files[s])
	var depth := (ranks - 1) * (4.2 if mounted else 1.5) * 0.5
	sq_x[s] = c.x + sin(heading) * depth
	sq_z[s] = c.y + cos(heading) * depth
	sq_tx[s] = sq_x[s]
	sq_tz[s] = sq_z[s]
	var m := sq_members[s]
	for k in count:
		var u := chosen[k]
		_leave_squad(u)
		u_squad[u] = s
		u_role[u] = Role.BANNER if k == count - 1 else Role.TROOPER
		u_slot[u] = k if k < count - 1 else -1
		m.append(u)
	sq_banner[s] = chosen[count - 1]
	_leave_squad(officer)
	u_squad[officer] = s
	u_role[officer] = Role.OFFICER
	u_slot[officer] = -1
	m.append(officer)
	sq_officer[s] = officer
	sq_init[s] = m.size()
	sq_alive[s] = m.size()
	_so_key[s] = -1
	_reslot(s)
	for u in m:
		_wake(u)
		u_target[u] = -1
	_update_centroid(s)
	return s


## Распустить отряд (R3): каждый живой — новый одиночка на своём месте. Павшие остаются без отряда.
## Возвращает номера юнитов (те же юниты, описатели не меняются).
func disband_squad(s: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if s < 0 or s >= squads or sq_used[s] == 0:
		return out
	var old := sq_members[s].duplicate()
	var morale := sq_morale[s]
	var stam := sq_stam[s]
	for u in old:
		if u_life[u] != Life.ALIVE:
			u_squad[u] = -1
			continue
		var ns := _new_squad(sq_side[s], u_type[u], Vector2(u_x[u], u_z[u]), u_h[u], sq_owner[s])
		sq_single[ns] = 1
		sq_files[ns] = 1
		sq_morale[ns] = morale
		sq_stam[ns] = stam
		sq_members[ns].append(u)
		sq_init[ns] = 1
		sq_alive[ns] = 1
		u_squad[u] = ns
		u_role[u] = Role.OFFICER if t_flags[u_type[u]] & UnitStats.OFFICER != 0 else Role.TROOPER
		u_slot[u] = 0
		_wake(u)
		_update_centroid(ns)
		out.append(u)
	sq_members[s].clear()
	_free_squad(s)
	return out


## Новый слот отряда: из свободных (освобождён на прошлых шагах) или в конец
func _new_squad(side: int, type_i: int, pos: Vector2, heading: float, owner := -1) -> int:
	var s := _take_free(_sq_free, _sq_free_at)
	if s < 0:
		s = squads
		squads += 1
		if s >= sq_side.size():
			_grow_squads(s + 1)
	sq_side[s] = side
	sq_type[s] = type_i
	sq_members[s].clear()
	sq_officer[s] = -1
	sq_banner[s] = -1
	sq_form[s] = Formation.LINE
	sq_files[s] = 1
	sq_order[s] = Order.HOLD
	sq_status[s] = Status.READY
	sq_gait[s] = Gait.WALK
	sq_x[s] = pos.x
	sq_z[s] = pos.y
	sq_h[s] = heading
	sq_vx[s] = 0.0
	sq_vz[s] = 0.0
	sq_tx[s] = pos.x
	sq_tz[s] = pos.y
	sq_th[s] = heading
	sq_target[s] = -1
	sq_morale[s] = 100.0
	sq_stam[s] = 100.0
	sq_flee_t[s] = 0.0
	sq_init[s] = 0
	sq_alive[s] = 0
	sq_cx[s] = pos.x
	sq_cz[s] = pos.y
	sq_speed[s] = 0.0
	sq_lag[s] = 0.0
	sq_melee[s] = 0
	sq_charge_ok[s] = 0
	sq_couched[s] = 0
	sq_impacted[s] = 0
	sq_fire_target[s] = -1
	sq_fire_dist[s] = 0.0
	sq_volley_rank[s] = -1
	sq_volley_t[s] = 0.0
	sq_volley_seen[s] = -1
	sq_cry_t[s] = -1000.0
	sq_single[s] = 0
	_so_key[s] = -1
	sq_gen[s] = Ids.next_gen(sq_gen[s])
	sq_owner[s] = owner if owner >= 0 else side
	var tf := t_flags[type_i]
	sq_stance[s] = Stance.PASSIVE if tf & UnitStats.WAGON != 0 else (Stance.DEFENSIVE if tf & UnitStats.WORKER != 0 else Stance.AGGRESSIVE)
	sq_path[s].clear()
	sq_wp[s] = 0
	sq_breach_st[s] = -1
	sq_breach_wp[s] = -1
	sq_st_target[s] = -1
	sq_enemy[s] = -1
	sq_trail[s].clear()
	sq_used[s] = 1
	sq_stuck[s] = 0
	sq_dorm[s] = 0
	_sq_still[s] = 0
	_rs_dirty = true
	return s


## Новый слот юнита: из свободных (освобождён на прошлых шагах) или в конец
func _new_unit(s: int, type_i: int, role: int, slot: int) -> int:
	var u := _take_free(_u_free, _u_free_at)
	if u < 0:
		u = n
		n += 1
		if u >= u_x.size():
			_grow_units(u + 1)
	u_x[u] = 0.0; u_z[u] = 0.0; u_px[u] = 0.0; u_pz[u] = 0.0
	u_vx[u] = 0.0; u_vz[u] = 0.0; u_dvx[u] = 0.0; u_dvz[u] = 0.0
	u_kx[u] = 0.0; u_kz[u] = 0.0; u_h[u] = 0.0; u_ph[u] = 0.0
	u_act_t[u] = -10.0; u_reload_t[u] = 0.0; u_cool_t[u] = 0.0; u_death_t[u] = -1.0
	u_hp[u] = t_hp[type_i]
	u_type[u] = type_i
	u_squad[u] = s
	u_side[u] = sq_side[s]
	u_role[u] = role
	u_slot[u] = slot
	u_life[u] = Life.ALIVE
	u_act[u] = Act.NONE
	u_fire_t[u] = -1.0
	u_aim[u] = -1
	u_ammo[u] = t_ammo[type_i]
	u_hit_t[u] = -1.0
	u_target[u] = -1
	u_couched[u] = 0
	u_charged[u] = 0
	u_rams[u] = 0
	u_fall[u] = 0
	u_var[u] = BattleRng.hash01(u * 7919 + 13)
	_so_x[u] = 0.0
	_so_y[u] = 0.0
	_so_key[s] = -1
	u_gen[u] = Ids.next_gen(u_gen[u])
	u_owner[u] = sq_owner[s]
	u_killer[u] = -1
	u_hurt_step[u] = -1
	u_sleep[u] = 0
	u_work[u] = -1.0
	u_garrison[u] = -1
	_hash_dirty = true
	if sleep_enabled:
		# город: в хэш — при ближайшей сборке (позицию ставит вызывающий), в бодрые — с начала шага
		_hq.append(u)
		_aw_join(u)
	return u


## Свободный слот, освобождённый раньше этого шага (FIFO), или −1
func _take_free(list: PackedInt32Array, at: PackedInt32Array) -> int:
	if list.is_empty() or at[0] >= steps:
		return -1
	var i := list[0]
	list.remove_at(0)
	at.remove_at(0)
	return i


func _grow_units(cap: int) -> void:
	var old := _ucell.size()
	for a: Variant in [u_x, u_z, u_px, u_pz, u_vx, u_vz, u_dvx, u_dvz, u_kx, u_kz, u_h, u_ph, u_hp,
			u_type, u_squad, u_side, u_role, u_slot, u_life, u_act, u_act_t, u_fire_t, u_aim, u_reload_t,
			u_ammo, u_cool_t, u_hit_t, u_target, u_couched, u_charged, u_rams, u_death_t, u_fall, u_var,
			_so_x, _so_y, u_gen, u_owner, u_killer, u_hurt_step, u_sleep, u_work, u_garrison,
			_ucell, _ublk, _hprev, _aw_on, _aw_q]:
		a.resize(cap)
	if _next.size() < cap:
		_next.resize(cap)
	for u in range(old, cap):
		_ucell[u] = -1  # не в хэше


func _grow_squads(cap: int) -> void:
	var old := sq_side.size()
	for a: Variant in [sq_side, sq_type, sq_officer, sq_banner, sq_form, sq_files, sq_order, sq_status, sq_gait,
			sq_x, sq_z, sq_h, sq_vx, sq_vz, sq_tx, sq_tz, sq_th, sq_target, sq_morale, sq_stam, sq_flee_t,
			sq_init, sq_alive, sq_cx, sq_cz, sq_speed, sq_lag, sq_melee, sq_charge_ok, sq_couched, sq_impacted,
			sq_fire_target, sq_fire_dist, sq_volley_rank, sq_volley_t, sq_volley_seen, sq_cry_t, sq_single,
			_so_key, sq_gen, sq_owner, sq_stance, sq_wp, sq_breach_st, sq_breach_wp, sq_st_target, sq_enemy,
			sq_used, sq_stuck, sq_dorm, _sq_act, _sq_still, _br_order, _br_target, _br_st]:
		a.resize(cap)
	sq_members.resize(cap)
	sq_path.resize(cap)
	sq_trail.resize(cap)
	for s in range(old, cap):
		sq_members[s] = PackedInt32Array()
		sq_path[s] = PackedVector2Array()
		sq_trail[s] = PackedVector2Array()


## Освободить юнита (R1): из отряда (тот сдвигает места или освобождается), слот — в свободные
func _free_unit(u: int) -> void:
	var was_alive := u_life[u] == Life.ALIVE
	var s := u_squad[u]
	if s >= 0 and s < squads and sq_used[s] == 1:
		var m := sq_members[s]
		var k := m.find(u)
		if k >= 0:
			m.remove_at(k)
			if sq_officer[s] == u:
				sq_officer[s] = -1
			if sq_banner[s] == u:
				sq_banner[s] = -1
			_so_key[s] = -1
			if m.is_empty():
				_free_squad(s)
			else:
				if was_alive:
					sq_alive[s] = maxi(sq_alive[s] - 1, 0)
				_reslot(s)
	var t := u_side[u]
	if t >= 0 and t < MAX_TEAMS and general[t] == u:
		general[t] = -1
	u_life[u] = Life.FREE
	u_squad[u] = -1
	u_sleep[u] = 0
	u_act[u] = Act.NONE
	u_work[u] = -1.0
	u_target[u] = -1
	u_aim[u] = -1
	u_fire_t[u] = -1.0
	u_hit_t[u] = -1.0
	u_couched[u] = 0
	u_vx[u] = 0.0
	u_vz[u] = 0.0
	u_dvx[u] = 0.0
	u_dvz[u] = 0.0
	u_kx[u] = 0.0
	u_kz[u] = 0.0
	u_garrison[u] = -1
	if sleep_enabled and _ucell[u] >= 0:
		_hash_unlink(u)
	_u_free.append(u)
	_u_free_at.append(steps)
	_hash_dirty = true


## Освободить отряд: на него больше никто не целится; слот — в свободные
func _free_squad(s: int) -> void:
	sq_used[s] = 0
	_rs_dirty = true
	sq_members[s].clear()
	sq_alive[s] = 0
	sq_order[s] = Order.HOLD
	sq_target[s] = -1
	sq_st_target[s] = -1
	sq_fire_target[s] = -1
	sq_officer[s] = -1
	sq_banner[s] = -1
	sq_path[s].clear()
	sq_trail[s].clear()
	sq_wp[s] = 0
	for t in squads:
		if sq_target[t] == s:
			sq_target[t] = -1
		if _br_target[t] == s:
			_br_target[t] = -1  # пролом вернёт приказ без этой цели
		if sq_fire_target[t] == s:
			sq_fire_target[t] = -1
			sq_volley_rank[t] = -1
	_sq_free.append(s)
	_sq_free_at.append(steps)


## Юнит уходит из своего отряда (form_squad): пустой отряд освобождается, иначе места сдвигаются
func _leave_squad(u: int) -> void:
	var s := u_squad[u]
	if s < 0 or s >= squads or sq_used[s] == 0:
		return
	var m := sq_members[s]
	var k := m.find(u)
	if k < 0:
		return
	m.remove_at(k)
	if sq_officer[s] == u:
		sq_officer[s] = -1
	if sq_banner[s] == u:
		sq_banner[s] = -1
	_so_key[s] = -1
	if u_life[u] == Life.ALIVE:
		sq_alive[s] = maxi(sq_alive[s] - 1, 0)
	if m.is_empty():
		_free_squad(s)
	else:
		_reslot(s)


## Места в строю по проекциям (R3): живые бойцы — вперёд по шеренгам (кто впереди — в первую),
## в шеренге — слева направо по боковому смещению; пути не пересекаются. Павшие — в конец.
func _reslot(s: int) -> void:
	var files := maxi(sq_files[s], 1)
	var fx := sin(sq_h[s])
	var fz := cos(sq_h[s])
	var alive: Array = []
	var dead := PackedInt32Array()
	for u in sq_members[s]:
		if u_role[u] != Role.TROOPER:
			continue
		if u_life[u] != Life.ALIVE:
			dead.append(u)
			continue
		var dx := u_x[u] - sq_x[s]
		var dz := u_z[u] - sq_z[s]
		alive.append([-(dx * fx + dz * fz), dx * -fz + dz * fx, u])
	alive.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] or (a[0] == b[0] and a[2] < b[2]))
	var k := 0
	var r0 := 0
	while r0 < alive.size():
		var rank := alive.slice(r0, mini(r0 + files, alive.size()))
		rank.sort_custom(func(a: Array, b: Array) -> bool:
			return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))
		for e: Array in rank:
			u_slot[e[2]] = k
			k += 1
		r0 += files
	for u in dead:
		u_slot[u] = k
		k += 1
	_so_key[s] = -1
	_wake_squad(s)  # места сменились: спящие идут на новые


# ================================================================= приказы (ИИ, игрок)

## Приказы отряду (s — номер отряда). Город: каждый приказ будит отряд и сбрасывает путь и цель-постройку;
## работу (Act.WORK) приказы ядра не трогают — её снимает порт (CombatPortBattle) или set_work(u, −1).
func order_hold(s: int, facing := NAN) -> void:
	sq_order[s] = Order.HOLD
	sq_tx[s] = sq_x[s]
	sq_tz[s] = sq_z[s]
	sq_th[s] = facing
	_clear_route(s)


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
	_clear_route(s)


func order_attack(s: int, target: int, gait := Gait.RUN) -> void:
	sq_order[s] = Order.ATTACK
	sq_target[s] = target
	sq_gait[s] = gait
	if sq_st_target[s] >= 0 or sq_path[s].size() > 0:
		_clear_route(s)
	_wake_squad(s)


## Атака постройки st (зеркало структур, R8): ближний бой — к ближней точке OBB, стрелки — с дистанции.
## Попадания — в ev_st_* (ядро их не применяет: HP у ECON).
func order_attack_structure(s: int, st: int, gait := Gait.RUN) -> void:
	if st < 0 or st >= st_hw or st_alive[st] == 0:
		return
	_clear_route(s)
	sq_order[s] = Order.ATTACK
	sq_target[s] = -1
	sq_st_target[s] = st
	sq_gait[s] = gait
	sq_melee[s] = 0
	for u in sq_members[s]:
		u_target[u] = -1


func set_gait(s: int, gait: int) -> void:
	sq_gait[s] = gait
	_wake_squad(s)


func set_formation(s: int, f: int) -> void:
	sq_form[s] = f
	_wake_squad(s)


## Ширина строя (порт: линия по ПКМ-протяжке)
func set_files(s: int, files: int) -> void:
	sq_files[s] = maxi(1, files)
	_reslot(s)
	_wake_squad(s)


## Стойка отряда (R9): AGGRESSIVE (срез), DEFENSIVE (работники), HOLD, PASSIVE (арбы)
func set_stance(s: int, stance: int) -> void:
	sq_stance[s] = stance
	_wake_squad(s)


## Строй снова держит места (сценарий среза после погони; R13 — вместо записи sq_melee снаружи)
func clear_melee(s: int) -> void:
	sq_melee[s] = 0


## Путь для отряда (R7, от NAV): якорь идёт по точкам; последняя — цель приказа (sq_tx, sq_tz).
## breach_st/breach_wp — этап 2 (пролом у точки breach_wp).
func set_path(s: int, pts: PackedVector2Array, breach_st := -1, breach_wp := -1) -> void:
	var path := sq_path[s]
	path.clear()
	path.append_array(pts)
	sq_wp[s] = 0
	var cur := sq_breach_st[s]
	if cur >= 0 and sq_st_target[s] == cur and breach_st != cur:
		_breach_undo(s)  # шёл на пролом, новый путь — без него: прежний приказ
	sq_breach_st[s] = breach_st
	sq_breach_wp[s] = breach_wp
	sq_stuck[s] = 0
	# путь — от бойцов: якорь, ушедший вперёд (упёрлись), встаёт к ним
	if sq_alive[s] > 0 and (sq_single[s] == 1 or sq_lag[s] > 6.0):
		sq_x[s] = sq_cx[s]
		sq_z[s] = sq_cz[s]
	if pts.size() > 0 and sq_order[s] == Order.MOVE:
		var g := pts[pts.size() - 1]
		sq_tx[s] = g.x
		sq_tz[s] = g.y
	_wake_squad(s)


## Приказ отдан, путь ещё не пришёл: якорь стоит (приказ MOVE остаётся)
func await_path(s: int) -> void:
	sq_wp[s] = -1


## Пролом: отряд ломает постройку пути (sq_breach_st); прежний приказ запомнен — когда постройка
## падёт (structure_clear), он вернётся, путь — заново (ev_repath)
func _breach_start(s: int) -> void:
	var st := sq_breach_st[s]
	if st >= st_hw or st_alive[st] == 0:
		sq_breach_st[s] = -1  # уже снесена: идём дальше
		sq_breach_wp[s] = -1
		return
	_br_order[s] = sq_order[s]
	_br_target[s] = sq_target[s]
	_br_st[s] = sq_st_target[s]
	sq_order[s] = Order.ATTACK
	sq_target[s] = -1
	sq_st_target[s] = st
	sq_melee[s] = 0
	for u in sq_members[s]:
		u_target[u] = -1


## Пролом окончен (постройка пала или путь сменился): прежний приказ и цель
func _breach_undo(s: int) -> void:
	sq_order[s] = _br_order[s]
	sq_target[s] = _br_target[s]
	var old := _br_st[s]
	sq_st_target[s] = old if old >= 0 and old < st_hw and st_alive[old] == 1 else -1
	sq_melee[s] = 0
	sq_breach_st[s] = -1
	sq_breach_wp[s] = -1


## Работа (R15): Act.WORK + u_work = aux (AnimSpec.WORK_*); aux < 0 — снять. Не будит спящего.
func set_work(u: int, aux: float) -> void:
	if u < 0 or u >= n or u_life[u] != Life.ALIVE:
		return
	if aux >= 0.0:
		u_act[u] = Act.WORK
		u_work[u] = aux
	else:
		if u_act[u] == Act.WORK:
			u_act[u] = Act.NONE
		u_work[u] = -1.0


## Повернуться (одиночка): якорь держит курс heading (работник лицом к дереву)
func face(u: int, heading: float) -> void:
	if u < 0 or u >= n or u_life[u] != Life.ALIVE:
		return
	var s := u_squad[u]
	if s < 0 or sq_single[s] == 0:
		return
	if sq_order[s] == Order.HOLD:
		sq_th[s] = heading
	_wake(u)


func _clear_route(s: int) -> void:
	if sq_path[s].size() > 0:
		sq_path[s].clear()
	sq_wp[s] = 0
	sq_st_target[s] = -1
	sq_breach_st[s] = -1
	sq_breach_wp[s] = -1
	sq_stuck[s] = 0
	_wake_squad(s)


func _wake_squad(s: int) -> void:
	for u in sq_members[s]:
		if u_sleep[u] == 1:
			_wake(u)
	sq_dorm[s] = 0


## Разбудить юнита (R12): и его отряд-одиночку; город — в бодрые с начала следующего шага
func _wake(u: int) -> void:
	u_sleep[u] = 0
	var s := u_squad[u]
	if s >= 0:
		sq_dorm[s] = 0
	if sleep_enabled:
		_aw_join(u)


## В бодрые (город): войдёт в _aw в начале шага, если жив и не спит (или падает)
func _aw_join(u: int) -> void:
	if _aw_on[u] == 0 and _aw_q[u] == 0:
		_aw_q[u] = 1
		_aw_add.append(u)


## Конница: разрешить натиск (копья наперевес на CHARGE_COUCH_DIST от цели)
func allow_charge(s: int, ok := true) -> void:
	sq_charge_ok[s] = 1 if ok else 0
	if ok:
		sq_couched[s] = 0
		sq_impacted[s] = 0


## Стрелки: огонь шеренгами по отряду target, когда он ближе dist (не дальше дальности)
func set_fire(s: int, target: int, dist: float) -> void:
	sq_fire_target[s] = target
	if target < 0:
		return
	var rmax := t_range[sq_type[s]]
	if own_mods.size() > 0:
		rmax *= owner_mod(sq_owner[s], MOD_RANGE)
	sq_fire_dist[s] = minf(dist, rmax)
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
	if u_sleep[u] == 1:
		_wake(u)


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
	if sq_single[s] == 1:
		return Vector2.ZERO  # одиночка (и полководец) стоит на якоре
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


# ================================================================= «Город»: запросы, буферы, структуры

## Слот юнита занят (не FREE)
func unit_used(u: int) -> bool:
	return u >= 0 and u < n and u_life[u] != Life.FREE


func squad_used(s: int) -> bool:
	return s >= 0 and s < squads and sq_used[s] == 1


## Отряд «без дела»: стоит (HOLD), не в свалке, не бежит, путь не ждёт, цели нет
func squad_idle(s: int) -> bool:
	if not squad_used(s) or sq_order[s] != Order.HOLD or sq_melee[s] == 1 or sq_status[s] == Status.FLEE:
		return false
	for u in sq_members[s]:
		if u_life[u] == Life.ALIVE and u_target[u] >= 0:
			return false
	return true


## Живые юниты команды team (enemies — других команд) в радиусе r от pos; flags_any — UnitStats.*
## (0 — любые). Пишет номера в out (очищает), возвращает их число. Порядок — по клеткам хэша.
func units_in_radius(team: int, pos: Vector2, r: float, enemies: bool, flags_any: int, out: PackedInt32Array) -> int:
	out.clear()
	if _hash_dirty:
		_rebuild_hash()
	var gn := _g_n
	var go := _g_origin
	var cx0 := clampi(int((pos.x - r - go) / _CELL), 0, gn - 1)
	var cx1 := clampi(int((pos.x + r - go) / _CELL), 0, gn - 1)
	var cz0 := clampi(int((pos.y - r - go) / _CELL), 0, gn - 1)
	var cz1 := clampi(int((pos.y + r - go) / _CELL), 0, gn - 1)
	var want := (~(1 << team) & 0xF) if enemies else (1 << team)
	var r2 := r * r
	for gz in range(cz0, cz1 + 1):
		for gx in range(cx0, cx1 + 1):
			var c := gz * gn + gx
			if _cmask[c] & want == 0:
				continue
			var v := _head[c]
			while v >= 0:
				if (u_side[v] != team) == enemies and (flags_any == 0 or t_flags[u_type[v]] & flags_any != 0):
					var dx := u_x[v] - pos.x
					var dz := u_z[v] - pos.y
					if dx * dx + dz * dz <= r2:
						out.append(v)
				v = _next[v]
	return out.size()


## Есть ли живой враг команды team ближе r к pos
func enemy_within(team: int, pos: Vector2, r: float) -> bool:
	return nearest_enemy_at(team, pos, r) >= 0


## Ближайший живой враг команды team в радиусе r от pos (−1 — нет)
func nearest_enemy_at(team: int, pos: Vector2, r: float) -> int:
	if _hash_dirty:
		_rebuild_hash()
	return _nearest_enemy_pos(team, pos, r)


## То же без пересборки хэша (внутри шага)
func _nearest_enemy_pos(team: int, pos: Vector2, r: float) -> int:
	var gn := _g_n
	var go := _g_origin
	var foe := ~(1 << team)
	var cx0 := clampi(int((pos.x - r - go) / _CELL), 0, gn - 1)
	var cx1 := clampi(int((pos.x + r - go) / _CELL), 0, gn - 1)
	var cz0 := clampi(int((pos.y - r - go) / _CELL), 0, gn - 1)
	var cz1 := clampi(int((pos.y + r - go) / _CELL), 0, gn - 1)
	var any := false
	var bn := _b_n
	for bz in range(cz0 >> _BLK_SHIFT, (cz1 >> _BLK_SHIFT) + 1):
		for bx in range(cx0 >> _BLK_SHIFT, (cx1 >> _BLK_SHIFT) + 1):
			if _bmask[bz * bn + bx] & foe != 0:
				any = true
				break
		if any:
			break
	if not any:
		return -1
	var best := -1
	var bd := r * r
	for gz in range(cz0, cz1 + 1):
		for gx in range(cx0, cx1 + 1):
			var c := gz * gn + gx
			if _cmask[c] & foe == 0:
				continue
			var v := _head[c]
			while v >= 0:
				if u_side[v] != team:
					var dx := u_x[v] - pos.x
					var dz := u_z[v] - pos.y
					var d2 := dx * dx + dz * dz
					if d2 <= bd:
						bd = d2
						best = v
				v = _next[v]
	return best


# ---------------------------------------------------------------- буферы (R10): забирает порт

## Пары [u, убийца] за шаги с прошлого забора (убийца −1 — нет); буфер очищается на месте
func take_dead() -> PackedInt32Array:
	var out := ev_dead.duplicate()
	ev_dead.clear()
	return out


## Попадания по постройкам: [st, урон × 100 (санти-HP, округлено), атакующий юнит] тройками
func take_st_hits() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in ev_st_b.size():
		out.append(ev_st_b[i])
		out.append(roundi(ev_st_dmg[i] * 100.0))
		out.append(ev_st_by[i])
	ev_st_b.clear()
	ev_st_dmg.clear()
	ev_st_by.clear()
	return out


func take_arrived() -> PackedInt32Array:
	var out := ev_arrived.duplicate()
	ev_arrived.clear()
	return out


func take_repath() -> PackedInt32Array:
	var out := ev_repath.duplicate()
	ev_repath.clear()
	return out


# ---------------------------------------------------------------- зеркало структур (R7, R8)

## Структура st (= слот здания ECON; ref — описатель здания): команда, центр, полуразмеры (по своим осям),
## курс rot (как Node3D.rotation.y: локальная X → (cos, −sin), Z → (sin, cos)), флаги ST_*, площадка, гарнизон.
func structure_set(st: int, ref: int, team: int, center: Vector2, half: Vector2, rot: float, flags: int,
		top := 0.0, gar_cap := 0) -> void:
	if st < 0:
		return
	if st >= st_hw:
		var cap := st + 1
		for a: Variant in [st_ref, st_team, st_flags, st_alive, st_gar_cap, st_gar_n, st_cx, st_cz, st_hx, st_hz,
				st_rot, st_top]:
			a.resize(cap)
		st_hw = cap
	elif st_alive[st] == 1:
		_bucket_remove(st)
		_st_live -= 1
	st_ref[st] = ref
	st_team[st] = team
	st_flags[st] = flags
	st_alive[st] = 1
	st_gar_cap[st] = gar_cap
	st_gar_n[st] = 0
	st_cx[st] = center.x
	st_cz[st] = center.y
	st_hx[st] = half.x
	st_hz[st] = half.y
	st_rot[st] = rot
	st_top[st] = top
	_st_live += 1
	if _sb_n == 0:
		_make_buckets()
	_bucket_add(st)
	# пути, которые теперь идут сквозь постройку, — заново (R7)
	if collect_events and flags & ST_FIELD == 0:
		for s in squads:
			if sq_used[s] == 0 or sq_path[s].is_empty() or sq_wp[s] < 0:
				continue
			var path := sq_path[s]
			for i in range(sq_wp[s], path.size()):
				if _st_contains(st, path[i].x, path[i].y, 1.0):
					ev_repath.append(s)
					break


## Структура снесена или свёрнута: цели и пути, которые на неё смотрели, — заново
func structure_clear(st: int) -> void:
	if st < 0 or st >= st_hw or st_alive[st] == 0:
		return
	_bucket_remove(st)
	st_alive[st] = 0
	_st_live -= 1
	for s in squads:
		if sq_used[s] == 1 and (sq_st_target[s] == st or sq_breach_st[s] == st):
			if sq_breach_st[s] == st:
				if collect_events:
					ev_repath.append(s)
				sq_breach_st[s] = -1
				sq_breach_wp[s] = -1
				if sq_st_target[s] == st:
					# пролом готов: прежний приказ, путь — заново (порт просит его к запомненной цели)
					_breach_undo(s)
					if collect_events:
						sq_wp[s] = -1  # ждёт новый путь от порта
					_wake_squad(s)
					continue
			if sq_st_target[s] == st:
				sq_st_target[s] = -1
				if sq_order[s] == Order.ATTACK and sq_target[s] < 0:
					order_hold(s)


## Ближайшая к (x, z) точка прямоугольника структуры (на границе или внутри)
func st_nearest(st: int, x: float, z: float) -> Vector2:
	var c := cos(st_rot[st])
	var sn := sin(st_rot[st])
	var dx := x - st_cx[st]
	var dz := z - st_cz[st]
	var lx := clampf(dx * c - dz * sn, -st_hx[st], st_hx[st])
	var lz := clampf(dx * sn + dz * c, -st_hz[st], st_hz[st])
	return Vector2(st_cx[st] + lx * c + lz * sn, st_cz[st] - lx * sn + lz * c)


## Точка внутри прямоугольника структуры, расширенного на pad
func _st_contains(st: int, x: float, z: float, pad: float) -> bool:
	var c := cos(st_rot[st])
	var sn := sin(st_rot[st])
	var dx := x - st_cx[st]
	var dz := z - st_cz[st]
	return absf(dx * c - dz * sn) < st_hx[st] + pad and absf(dx * sn + dz * c) < st_hz[st] + pad


## Точка закрыта для юнита команды team: непроходимая клетка земли или постройка (кроме полей и своих ворот)
func point_blocked(x: float, z: float, team: int) -> bool:
	if _blk_static.size() > 0:
		var gx := floori((x - _grid_origin.x) / _CELL)
		var gz := floori((z - _grid_origin.y) / _CELL)
		if gx < 0 or gz < 0 or gx >= _grid_w or gz >= _grid_h or _blk_static[gz * _grid_w + gx] != 0:
			return true
	if _st_live > 0:
		var b := _bucket_of(x, z)
		if b >= 0:
			for st in _sb[b]:
				var f := st_flags[st]
				if f & ST_FIELD != 0 or (f & ST_GATE != 0 and st_team[st] == team):
					continue
				if _st_contains(st, x, z, 0.0):
					return true
	return false


func _bucket_of(x: float, z: float) -> int:
	var bx := floori((x - _sb_origin.x) / ST_BUCKET)
	var bz := floori((z - _sb_origin.y) / ST_BUCKET)
	if bx < 0 or bz < 0 or bx >= _sb_n or bz >= _sb_n:
		return -1
	return bz * _sb_n + bx


## Корзины, которые задевает прямоугольник структуры (+2 м на радиус юнита)
func _bucket_range(st: int) -> Rect2i:
	var c := absf(cos(st_rot[st]))
	var sn := absf(sin(st_rot[st]))
	var ex := st_hx[st] * c + st_hz[st] * sn + 2.0
	var ez := st_hx[st] * sn + st_hz[st] * c + 2.0
	var x0 := clampi(floori((st_cx[st] - ex - _sb_origin.x) / ST_BUCKET), 0, _sb_n - 1)
	var x1 := clampi(floori((st_cx[st] + ex - _sb_origin.x) / ST_BUCKET), 0, _sb_n - 1)
	var z0 := clampi(floori((st_cz[st] - ez - _sb_origin.y) / ST_BUCKET), 0, _sb_n - 1)
	var z1 := clampi(floori((st_cz[st] + ez - _sb_origin.y) / ST_BUCKET), 0, _sb_n - 1)
	return Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1)


func _bucket_add(st: int) -> void:
	var r := _bucket_range(st)
	for bz in range(r.position.y, r.end.y):
		for bx in range(r.position.x, r.end.x):
			_sb[bz * _sb_n + bx].append(st)


func _bucket_remove(st: int) -> void:
	var r := _bucket_range(st)
	for bz in range(r.position.y, r.end.y):
		for bx in range(r.position.x, r.end.x):
			var list := _sb[bz * _sb_n + bx]
			var k := list.find(st)
			if k >= 0:
				list.remove_at(k)


# ================================================================= шаг

func step() -> void:
	time += DT
	steps += 1
	if sleep_enabled:
		_step_city()
		return
	for u in n:
		u_px[u] = u_x[u]
		u_pz[u] = u_z[u]
		u_ph[u] = u_h[u]
	# хэш собран в конце прошлого шага; заново — только если снаружи что-то менялось (тот же результат)
	if _hash_dirty:
		_rebuild_hash()
	for s in squads:
		_update_centroid(s)
	for s in squads:
		_squad_step(s)
	_units_think()
	_resolve_actions()
	_integrate()
	_victory_check()
	# хэш по позициям конца шага: его читают запросы порта между шагами и следующий шаг
	_rebuild_hash()


## Шаг города (сон, R12): только бодрые и падающие (_aw); спящие лежат в хэше и будятся
## врагом рядом (блоки _mixed), толчком, приказом, уроном, сменой мест в отряде
func _step_city() -> void:
	if _hash_dirty:
		_rebuild_hash()
	_wake_pass()
	_aw_merge()
	# спящие стоят: их прошлый шаг уже равен этому (_try_sleep)
	for u: int in _aw:
		u_px[u] = u_x[u]
		u_pz[u] = u_z[u]
		u_ph[u] = u_h[u]
	_squads_city()
	_units_think()
	_resolve_actions()
	_integrate()
	_victory_check()
	# хэш: переложить тех, кто мог сдвинуться (бодрые, разбуженные на шаге, родившиеся и убитые)
	_hash_dirty = false
	_hash_relink_list(_aw)
	_hash_relink_list(_aw_add)
	_hash_relink_list(_hq)
	_hq.clear()


## Бодрые на этот шаг: из прошлых — кто не уснул, не умер и не освобождён; плюс проснувшиеся (по номеру)
func _aw_merge() -> void:
	var keep := 0
	for i in _aw.size():
		var u := _aw[i]
		var lf := u_life[u]
		if lf == Life.DYING or (lf == Life.ALIVE and u_sleep[u] == 0):
			_aw[keep] = u
			keep += 1
		else:
			_aw_on[u] = 0
	_aw.resize(keep)
	if _aw_add.is_empty():
		return
	var grew := false
	for u: int in _aw_add:
		_aw_q[u] = 0
		if _aw_on[u] == 1:
			continue
		var lf := u_life[u]
		if lf == Life.DYING or (lf == Life.ALIVE and u_sleep[u] == 0):
			_aw_on[u] = 1
			_aw.append(u)
			grew = true
	_aw_add.clear()
	if grew:
		_aw.sort()


## Будильник города (R12): спящие в блоках, где рядом враг (≈16 м), и каждый 15-й по номеру —
## сдвинут ли с места больше чем на 0,5 м (2 раза в с, вразнобой)
func _wake_pass() -> void:
	if not _mixed.is_empty():
		var keep := 0
		for i in _mixed.size():
			var b := _mixed[i]
			var m := _bmask_n[b]
			if m & (m - 1) == 0:
				_mx_on[b] = 0
				continue
			_mixed[keep] = b
			keep += 1
			if _bmask[b] != 0:
				_wake_block(b)
		_mixed.resize(keep)
	var u := (WAKE_CHECK_STEPS - steps % WAKE_CHECK_STEPS) % WAKE_CHECK_STEPS
	while u < n:
		if u_sleep[u] == 1 and u_life[u] == Life.ALIVE and _pushed_off(u):
			_wake(u)
		u += WAKE_CHECK_STEPS


## Разбудить всех спящих в клетках блока b
func _wake_block(b: int) -> void:
	var bn := _b_n
	var gn := _g_n
	var cx0 := (b % bn) << _BLK_SHIFT
	var cz0 := (b / bn) << _BLK_SHIFT
	for gz in range(cz0, mini(cz0 + (1 << _BLK_SHIFT), gn)):
		for gx in range(cx0, mini(cx0 + (1 << _BLK_SHIFT), gn)):
			var v := _head[gz * gn + gx]
			while v >= 0:
				if u_sleep[v] == 1:
					_wake(v)
				v = _next[v]


## Отряды города: одиночки бодрых и все настоящие (R1, R12). Настоящий отряд, где все спят,
## центр не пересчитывает (никто не сдвинулся) — один раз после засыпания, потом пропуск.
func _squads_city() -> void:
	if _rs_dirty:
		_real_sq_rebuild()
	var list := _sq_list
	list.clear()
	for u: int in _aw:
		var s := u_squad[u]
		if s < 0 or sq_used[s] == 0:
			continue
		if sq_single[s] == 1:
			list.append(s)
		else:
			_sq_act[s] = 1
	list.append_array(_real_sq)
	list.sort()
	# список отрядов шага не меняется в шаге (form/disband — только снаружи)
	for s: int in list:
		if sq_single[s] == 1:
			# одиночка: то же, что _update_centroid (прямая копия), без вызова
			var m := sq_members[s]
			if m.size() == 1:
				var u0 := m[0]
				if u_life[u0] == Life.ALIVE:
					sq_alive[s] = 1
					sq_cx[s] = u_x[u0]
					sq_cz[s] = u_z[u0]
					sq_speed[s] = sqrt(u_vx[u0] * u_vx[u0] + u_vz[u0] * u_vz[u0])
				else:
					sq_alive[s] = 0
			else:
				_update_centroid(s)
		elif _sq_act[s] == 1:
			_update_centroid(s)
			_sq_still[s] = 0
		elif _sq_still[s] == 0:
			_update_centroid(s)
			_sq_still[s] = 1
	for s: int in list:
		_squad_step(s)
		_sq_act[s] = 0


func _real_sq_rebuild() -> void:
	_rs_dirty = false
	_real_sq.clear()
	for t in squads:
		if sq_used[t] == 1 and sq_single[t] == 0:
			_real_sq.append(t)


## Хэш: полная сборка (срез, город без сна — каждый шаг; город — при смене границ).
## Город между шагами: переложить только родившихся и убитых (_hq).
func _rebuild_hash() -> void:
	_hash_dirty = false
	if sleep_enabled:
		if _hash_full:
			_hash_build_city()
		else:
			_hash_relink_list(_hq)
			_hq.clear()
		return
	_head.fill(-1)
	_cmask.fill(0)
	_bmask.fill(0)
	if _next.size() < n:
		_next.resize(n)
	var go := _g_origin
	var gn := _g_n
	var bn := _b_n
	var gmax := gn - 1
	for u in n:
		if u_life[u] != Life.ALIVE:
			continue
		# то же, что _cell(); заодно отмечаем сторону в клетке и в блоке
		var cx := clampi(int((u_x[u] - go) / _CELL), 0, gmax)
		var cz := clampi(int((u_z[u] - go) / _CELL), 0, gmax)
		var c := cz * gn + cx
		_next[u] = _head[c]
		_head[c] = u
		var bit := 1 << u_side[u]
		_cmask[c] |= bit
		_bmask[(cz >> _BLK_SHIFT) * bn + (cx >> _BLK_SHIFT)] |= bit


## Хэш города целиком: все живые по номеру (списки клеток — по убыванию, как в срезе); маски клеток
## и блоков, блоки «рядом враг» (_bmask_n: блок и 8 соседей) и список смешанных (_mixed)
func _hash_build_city() -> void:
	_hash_full = false
	_head.fill(-1)
	_cmask.fill(0)
	_bmask.fill(0)
	_bmask_n.fill(0)
	_mx_on.fill(0)
	_mixed.clear()
	_ucell.fill(-1)
	for u in n:
		if u_life[u] == Life.ALIVE:
			_hash_link(u, _cell(u_x[u], u_z[u]))
	_hq.clear()


## Переложить юнитов списка в хэше (город): живой — в клетку своей позиции, остальные — вон
func _hash_relink_list(list: PackedInt32Array) -> void:
	var go := _g_origin
	var gn := _g_n
	var gmax := gn - 1
	for u: int in list:
		var c := _ucell[u]
		if u_life[u] != Life.ALIVE:
			if c >= 0:
				_hash_unlink(u)
			continue
		var nc := clampi(int((u_z[u] - go) / _CELL), 0, gmax) * gn + clampi(int((u_x[u] - go) / _CELL), 0, gmax)
		if nc == c:
			continue
		if c >= 0:
			_hash_unlink(u)
		_hash_link(u, nc)


## В голову списка клетки c; бит команды — в клетку, блок и блоки вокруг
func _hash_link(u: int, c: int) -> void:
	var h := _head[c]
	_next[u] = h
	_hprev[u] = -1
	if h >= 0:
		_hprev[h] = u
	_head[c] = u
	_ucell[u] = c
	var gn := _g_n
	var b := ((c / gn) >> _BLK_SHIFT) * _b_n + ((c % gn) >> _BLK_SHIFT)
	_ublk[u] = b
	var bit := 1 << u_side[u]
	if _cmask[c] & bit == 0:
		_cmask[c] |= bit
		if _bmask[b] & bit == 0:
			_bmask[b] |= bit
			_bn_add(b, bit)


## Из списка клетки; последний своей команды в клетке (блоке) снимает её бит
func _hash_unlink(u: int) -> void:
	var c := _ucell[u]
	var p := _hprev[u]
	var nx := _next[u]
	if p >= 0:
		_next[p] = nx
	else:
		_head[c] = nx
	if nx >= 0:
		_hprev[nx] = p
	_ucell[u] = -1
	var side := u_side[u]
	var v := _head[c]
	while v >= 0:
		if u_side[v] == side:
			return
		v = _next[v]
	var bit := 1 << side
	_cmask[c] &= ~bit
	var gn := _g_n
	var cx0 := ((c % gn) >> _BLK_SHIFT) << _BLK_SHIFT
	var cz0 := ((c / gn) >> _BLK_SHIFT) << _BLK_SHIFT
	for gz in range(cz0, mini(cz0 + (1 << _BLK_SHIFT), gn)):
		for gx in range(cx0, mini(cx0 + (1 << _BLK_SHIFT), gn)):
			if _cmask[gz * gn + gx] & bit != 0:
				return
	var b := _ublk[u]
	_bmask[b] &= ~bit
	_bn_remove(b, bit)


## Бит команды пришёл в блок b: блоки вокруг (3 × 3) знают «рядом команда»; две и больше — смешанный
func _bn_add(b: int, bit: int) -> void:
	var bn := _b_n
	var bx := b % bn
	var bz := b / bn
	for z in range(maxi(bz - 1, 0), mini(bz + 1, bn - 1) + 1):
		for x in range(maxi(bx - 1, 0), mini(bx + 1, bn - 1) + 1):
			var nb := z * bn + x
			var m := _bmask_n[nb] | bit
			_bmask_n[nb] = m
			if m & (m - 1) != 0 and _mx_on[nb] == 0:
				_mx_on[nb] = 1
				_mixed.append(nb)


## Бит команды ушёл из блока b: у блоков вокруг он остаётся, только если есть ещё в их 3 × 3
func _bn_remove(b: int, bit: int) -> void:
	var bn := _b_n
	var bx := b % bn
	var bz := b / bn
	for z in range(maxi(bz - 1, 0), mini(bz + 1, bn - 1) + 1):
		for x in range(maxi(bx - 1, 0), mini(bx + 1, bn - 1) + 1):
			var keep := false
			for z2 in range(maxi(z - 1, 0), mini(z + 1, bn - 1) + 1):
				for x2 in range(maxi(x - 1, 0), mini(x + 1, bn - 1) + 1):
					if _bmask[z2 * bn + x2] & bit != 0:
						keep = true
			if not keep:
				_bmask_n[z * bn + x] &= ~bit


func _cell(x: float, z: float) -> int:
	var go := _g_origin
	var gn := _g_n
	var cx := clampi(int((x - go) / _CELL), 0, gn - 1)
	var cz := clampi(int((z - go) / _CELL), 0, gn - 1)
	return cz * gn + cx


## Точно суша: в клетке хэша (4 м) нет высот ниже воды + 0,05 м (тогда Terrain.is_water — false).
## Проверка клетки — один раз, по узлам сетки высот с запасом в узел (за краем карты — край).
func _surely_dry(x: float, z: float) -> bool:
	var c := _cell(x, z)
	var d := _dry[c]
	if d == 0:
		var go := _g_origin
		var gn := _g_n
		d = 2
		var hs := Terrain.heights()
		var hn := Terrain.size()
		if hn > 1:
			var sp := Terrain.spacing()
			var o := Terrain.origin()
			var cx := c % gn
			var cz := c / gn
			var wx := go + cx * _CELL
			var wz := go + cz * _CELL
			var i0 := clampi(floori((wx - o.x) / sp) - 1, 0, hn - 1)
			var i1 := clampi(ceili((wx + _CELL - o.x) / sp) + 1, 0, hn - 1)
			var j0 := clampi(floori((wz - o.y) / sp) - 1, 0, hn - 1)
			var j1 := clampi(ceili((wz + _CELL - o.y) / sp) + 1, 0, hn - 1)
			# точка за краем карты берёт высоту края — край тоже в проверке
			if cx == 0: i0 = 0
			if cz == 0: j0 = 0
			if cx == gn - 1: i1 = hn - 1
			if cz == gn - 1: j1 = hn - 1
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
	var gn := _g_n
	var go := _g_origin
	var bn := _b_n
	var cr := ceili(r / _CELL)
	var cx := clampi(int((x - go) / _CELL), 0, gn - 1)
	var cz := clampi(int((z - go) / _CELL), 0, gn - 1)
	var x0 := maxi(cx - cr, 0)
	var x1 := mini(cx + cr, gn - 1)
	var z0 := maxi(cz - cr, 0)
	var z1 := mini(cz + cr, gn - 1)
	var foe := ~(1 << side)
	# в блоках вокруг нет чужих — искать нечего (тот же ответ −1, без обхода клеток)
	var any := false
	for bz in range(z0 >> _BLK_SHIFT, (z1 >> _BLK_SHIFT) + 1):
		for bx in range(x0 >> _BLK_SHIFT, (x1 >> _BLK_SHIFT) + 1):
			if _bmask[bz * bn + bx] & foe != 0:
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
			var c := gz * gn + gx
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
	var gn := _g_n
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
				var c := gz * gn + gx
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
	if sq_single[s] == 1:
		# одиночка (R2): прямая копия — то же, что сумма из одного (x / 1 == x)
		var m := sq_members[s]
		if m.size() == 1:
			var u0 := m[0]
			if u_life[u0] == Life.ALIVE:
				sq_alive[s] = 1
				sq_cx[s] = u_x[u0]
				sq_cz[s] = u_z[u0]
				sq_speed[s] = sqrt(u_vx[u0] * u_vx[u0] + u_vz[u0] * u_vz[u0])
			else:
				sq_alive[s] = 0
			return
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
	if sleep_enabled:
		return _nearest_enemy_squad_city(s)
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


## Город: ближайший вражеский отряд — среди настоящих отрядов (список) и одиночек ближе ENEMY_NEAR
## (хэш); одиночки дальше 50 м не в счёт (их сотни — работники)
func _nearest_enemy_squad_city(s: int) -> int:
	if _rs_dirty:
		_real_sq_rebuild()
	var best := -1
	var bd := INF
	var side := sq_side[s]
	var cx := sq_cx[s]
	var cz := sq_cz[s]
	for t in _real_sq:
		if sq_side[t] == side or sq_alive[t] == 0:
			continue
		var d := Vector2(sq_cx[t] - cx, sq_cz[t] - cz).length_squared()
		if d < bd or (d == bd and t < best):
			bd = d
			best = t
	if bd > ENEMY_NEAR * ENEMY_NEAR:
		var e := _nearest_enemy_pos(side, Vector2(cx, cz), ENEMY_NEAR)
		if e >= 0:
			var t2 := u_squad[e]
			if t2 >= 0 and sq_single[t2] == 1:
				var d2 := Vector2(sq_cx[t2] - cx, sq_cz[t2] - cz).length_squared()
				if d2 < bd:
					best = t2
	else:
		var e2 := _nearest_enemy_pos(side, Vector2(cx, cz), sqrt(bd))
		if e2 >= 0:
			var t3 := u_squad[e2]
			if t3 >= 0 and sq_single[t3] == 1:
				var d3 := Vector2(sq_cx[t3] - cx, sq_cz[t3] - cz).length_squared()
				if d3 < bd:
					best = t3
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


## Скорость строя: тип × аллюр × построение × усталость (× множитель игрока, R11)
func squad_speed(s: int) -> float:
	var ti := sq_type[s]
	var v := t_speed[ti]
	match sq_gait[s]:
		Gait.WALK: v *= t_walk[ti]
		Gait.TROT: v *= 0.72
	match sq_form[s]:
		Formation.COLUMN: v *= 1.15
		Formation.SQUARE: v *= 0.35
	if own_mods.size() > 0:
		v *= owner_mod(sq_owner[s], MOD_SPEED)
	return v * _tired(s)


## Стреляет ли род ti (мушкет, лук, пушка) — для порта и ядра
func is_ranged_type(ti: int) -> bool:
	return t_flags[ti] & (UnitStats.MUSKET | UnitStats.BOW | UnitStats.CANNON) != 0 and t_range[ti] > 0.0


func _squad_step(s: int) -> void:
	if sq_alive[s] == 0:
		return
	var ti := sq_type[s]
	var mounted := t_flags[ti] & UnitStats.MOUNTED != 0
	var single := sq_single[s] == 1
	var has_mods := own_mods.size() > 0
	var enemy := -1
	var enemy_d := INF
	if not single:
		enemy = _nearest_enemy_squad(s)
		if enemy >= 0:
			enemy_d = Vector2(sq_cx[enemy] - sq_cx[s], sq_cz[enemy] - sq_cz[s]).length()
	else:
		# одиночка (R2): ближайший отряд не ищет (мораль и бегство ему не нужны); для свалки — цель приказа
		var t0 := sq_target[s]
		if sq_order[s] == Order.ATTACK and t0 >= 0 and sq_alive[t0] > 0:
			enemy_d = Vector2(sq_cx[t0] - sq_cx[s], sq_cz[t0] - sq_cz[s]).length()
	sq_enemy[s] = enemy
	var near := enemy_d < ENEMY_NEAR
	# --- мораль: восстановление и аура полководца
	if not single:
		var mreg := owner_mod(sq_owner[s], MOD_MORALE) if has_mods else 1.0
		if not near:
			sq_morale[s] += MORALE_RECOVER * DT * mreg
		var g := general[sq_side[s]]
		if g >= 0 and u_life[g] == Life.ALIVE:
			if Vector2(u_x[g] - sq_cx[s], u_z[g] - sq_cz[s]).length() < AURA_RADIUS:
				sq_morale[s] += MORALE_AURA * DT * (0.25 if near else 1.0) * mreg
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
	if has_mods and ds > 0.0:
		ds *= owner_mod(sq_owner[s], MOD_STAM)
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
	if not single and sq_morale[s] < _flee_threshold(s):
		sq_status[s] = Status.FLEE
		sq_flee_t[s] = 0.0
		sq_melee[s] = 0
		sq_couched[s] = 0
		for u in sq_members[s]:
			u_couched[u] = 0
			u_target[u] = -1
			u_fire_t[u] = -1.0
			if u_sleep[u] == 1:
				_wake(u)
			if u_act[u] == Act.AIM:
				u_act[u] = Act.NONE
		sq_dorm[s] = 0
		rout.emit(s, Vector3(sq_cx[s], 0.0, sq_cz[s]))
		return
	# --- движение якоря строя: скорость — как squad_speed(s), без вызовов
	var spd := t_speed[ti]
	var gait := sq_gait[s]
	if gait == Gait.WALK:
		spd *= t_walk[ti]
	elif gait == Gait.TROT:
		spd *= 0.72
	var fm := sq_form[s]
	if fm == Formation.COLUMN:
		spd *= 1.15
	elif fm == Formation.SQUARE:
		spd *= 0.35
	if has_mods:
		spd *= owner_mod(sq_owner[s], MOD_SPEED)
	var stam := sq_stam[s]
	spd *= 1.0 if stam >= STAMINA_TIRED else 0.7 + 0.3 * stam / STAMINA_TIRED
	if not single:
		# отставание бойцов от мест в строю (раз в 3 шага — дорого); у одиночки его нет (R2);
		# город: отряд, где все спят и стоят (центр не менялся), не пересчитывает — никто не сдвинулся
		if (steps + s) % 3 == 0 and (_sq_still[s] == 0 or sq_order[s] != Order.HOLD):
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
		# город: строй отстал от якоря на пути (упёрся) 2 с — новый путь (R7)
		if collect_events and sq_order[s] == Order.MOVE and sq_path[s].size() > 0:
			if lag > 6.0:
				sq_stuck[s] += 1
				if sq_stuck[s] >= STUCK_STEPS:
					sq_stuck[s] = 0
					ev_repath.append(s)
			else:
				sq_stuck[s] = 0
	var tx := sq_tx[s]
	var tz := sq_tz[s]
	var tgt := sq_target[s]
	var st := sq_st_target[s]
	var ranged_st := false
	var face_st := 0.0
	if sq_order[s] == Order.ATTACK:
		if st >= 0:
			# цель — постройка (R8): ближний бой — к ближней точке и в свалку, стрелки — на дистанцию
			if st_alive[st] == 0:
				order_hold(s)
			else:
				var p := st_nearest(st, sq_cx[s], sq_cz[s])
				var dpx := p.x - sq_cx[s]
				var dpz := p.y - sq_cz[s]
				var dp := sqrt(dpx * dpx + dpz * dpz)
				face_st = atan2(dpx, dpz)
				if is_ranged_type(ti):
					var rmax := t_range[ti] * (owner_mod(sq_owner[s], MOD_RANGE) if has_mods else 1.0)
					if dp <= rmax * 0.8:
						tx = sq_x[s]
						tz = sq_z[s]
						ranged_st = true
					else:
						tx = p.x
						tz = p.y
				else:
					tx = p.x
					tz = p.y
					if dp < 6.0 + t_radius[ti]:
						sq_melee[s] = 1
		elif tgt < 0 or sq_alive[tgt] == 0:
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
	# --- путь (R7): промежуточные точки; последняя — цель приказа. wp < 0 — путь ещё не пришёл
	var path_wait := false
	if sq_order[s] != Order.HOLD and sq_melee[s] == 0:
		var wp := sq_wp[s]
		if wp < 0:
			path_wait = true
		else:
			var path := sq_path[s]
			var last := path.size() - 1
			if wp < last and (sq_order[s] == Order.MOVE or (tx - sq_x[s]) * (tx - sq_x[s]) + (tz - sq_z[s]) * (tz - sq_z[s]) > 625.0):
				var reach := 1.0 if single else WP_REACH
				var p := path[wp]
				while wp < last and (p.x - sq_x[s]) * (p.x - sq_x[s]) + (p.y - sq_z[s]) * (p.y - sq_z[s]) < reach * reach:
					wp += 1
					p = path[wp]
				sq_wp[s] = wp
				if wp < last:
					tx = p.x
					tz = p.y
			# пролом (§9 NAV): якорь у точки перед вражеской постройкой — ломать её (R8)
			var bst := sq_breach_st[s]
			if bst >= 0 and sq_st_target[s] != bst and last >= 0:
				var bw := mini(maxi(sq_breach_wp[s], 0), last)
				var bp := path[bw]
				if wp > bw or (bp.x - sq_x[s]) * (bp.x - sq_x[s]) + (bp.y - sq_z[s]) * (bp.y - sq_z[s]) < 4.0 * WP_REACH * WP_REACH:
					_breach_start(s)
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
	if path_wait:
		return
	var fast := single and sq_officer[s] < 0
	var dx := tx - sq_x[s]
	var dz := tz - sq_z[s]
	var dist := sqrt(dx * dx + dz * dz)
	if sq_order[s] != Order.HOLD and dist > 0.3:
		var want := atan2(dx, dz)
		if fast:
			# одиночка (R2): разворот 8 рад/с без ожидания; якорь на поводке у бойца
			sq_h[s] += clampf(angle_difference(sq_h[s], want), -SINGLE_TURN * DT, SINGLE_TURN * DT)
			var stepd := minf(dist, spd * DT)
			var m0 := sq_members[s][0]
			var lx := u_x[m0] - sq_x[s]
			var lz := u_z[m0] - sq_z[s]
			var leash := SINGLE_LEASH + spd / 1.4
			if lx * lx + lz * lz > leash * leash:
				stepd = 0.0
				sq_stuck[s] += 1
				if sq_stuck[s] >= STUCK_STEPS:
					sq_stuck[s] = 0
					if collect_events and sq_path[s].size() > 0:
						ev_repath.append(s)
			else:
				sq_stuck[s] = 0
			sq_x[s] += dx / dist * stepd
			sq_z[s] += dz / dist * stepd
		else:
			var turn := 1.1 if mounted else 0.7
			sq_h[s] = rotate_toward(sq_h[s], want, turn * DT)
			# строй разворачивается на месте, потом идёт
			var align := clampf(cos(angle_difference(sq_h[s], want)), 0.0, 1.0)
			var stepd := minf(dist, spd * DT * align * align)
			sq_x[s] += dx / dist * stepd
			sq_z[s] += dz / dist * stepd
	elif sq_order[s] == Order.MOVE:
		var m1 := sq_members[s][0] if fast else -1
		if m1 >= 0 and (u_x[m1] - sq_x[s]) * (u_x[m1] - sq_x[s]) + (u_z[m1] - sq_z[s]) * (u_z[m1] - sq_z[s]) > 1.0 \
				and sq_stuck[s] < 90:
			sq_stuck[s] += 1  # одиночка: прибытие — когда сам боец у цели (или через 3 с: место занято)
		else:
			order_hold(s, sq_th[s])
			if collect_events:
				ev_arrived.append(s)
	if sq_order[s] == Order.HOLD and not is_nan(sq_th[s]):
		sq_h[s] = rotate_toward(sq_h[s], sq_th[s], (SINGLE_TURN if fast else (1.0 if mounted else 0.6)) * DT)
	if ranged_st:
		sq_h[s] = rotate_toward(sq_h[s], face_st, (SINGLE_TURN if fast else 1.0) * DT)
	sq_vx[s] = (sq_x[s] - ox) / DT
	sq_vz[s] = (sq_z[s] - oz) / DT
	if collect_events and not single and (sq_vx[s] != 0.0 or sq_vz[s] != 0.0):
		_trail_push(s)
	# --- огонь шеренгами
	if sq_fire_target[s] >= 0:
		_fire_control(s)
	if ranged_st:
		_fire_control_st(s, st)


## След якоря (R7): точка каждые 2 м, последние 8
func _trail_push(s: int) -> void:
	var tr := sq_trail[s]
	var p := Vector2(sq_x[s], sq_z[s])
	if tr.is_empty() or tr[tr.size() - 1].distance_squared_to(p) >= 4.0:
		tr.append(p)
		if tr.size() > 8:
			tr.remove_at(0)


## Куда идти бойцу, чьё место в строю внутри препятствия: по следу якоря (ворота, проходы — колонной)
func _trail_target(s: int, x: float, z: float) -> Vector2:
	var tr := sq_trail[s]
	if tr.is_empty():
		return Vector2(sq_x[s], sq_z[s])
	var best := 0
	var bd := INF
	for i in tr.size():
		var d := tr[i].distance_squared_to(Vector2(x, z))
		if d < bd:
			bd = d
			best = i
	if bd < 4.0:
		if best + 1 < tr.size():
			best += 1
		else:
			return Vector2(sq_x[s], sq_z[s])
	return tr[best]


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


## Стрелки по постройке (R8): каждый, кто заряжен и достаёт до стены, стреляет сам (не шеренгами)
func _fire_control_st(s: int, st: int) -> void:
	var ti := sq_type[s]
	var rmax := t_range[ti]
	if own_mods.size() > 0:
		rmax *= owner_mod(sq_owner[s], MOD_RANGE)
	for u in sq_members[s]:
		if u_life[u] != Life.ALIVE or u_role[u] != Role.TROOPER and sq_single[s] == 0:
			continue
		if u_reload_t[u] > time or u_fire_t[u] >= 0.0 or u_ammo[u] == 0 or u_target[u] >= 0:
			continue
		var p := st_nearest(st, u_x[u], u_z[u])
		var dx := p.x - u_x[u]
		var dz := p.y - u_z[u]
		if dx * dx + dz * dz > rmax * rmax:
			continue
		var start := time + rng.range_f(0.0, 0.25)
		u_act[u] = Act.AIM
		u_act_t[u] = start
		u_fire_t[u] = start + SHOOT_FIRE_DELAY + rng.range_f(0.0, 0.12)
		u_aim[u] = -2 - st
		if u_sleep[u] == 1:
			_wake(u)


func _fire_rank(s: int, r: int) -> void:
	var t := sq_fire_target[s]
	var ti := sq_type[s]
	var rng_max := t_range[ti]
	if own_mods.size() > 0:
		rng_max *= owner_mod(sq_owner[s], MOD_RANGE)
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
		if u_sleep[u] == 1:
			_wake(u)


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
	var sleep_on := sleep_enabled
	var has_mods := own_mods.size() > 0
	var has_spd := _spd.size() > 0
	var obstacles := _st_live > 0 or _blk_static.size() > 0
	var go := _g_origin
	var gmax := _g_n - 1
	var gn := _g_n
	var gro := _grid_origin
	# город — только бодрые (спящих будит _wake_pass), срез — все по номеру
	for u: int in (_aw if sleep_on else _all_units()):
		if u_life[u] != Life.ALIVE:
			u_dvx[u] = 0.0
			u_dvz[u] = 0.0
			continue
		if sleep_on and u_sleep[u] == 1:
			continue
		var s := u_squad[u]
		var ti := u_type[u]
		var mounted := t_flags[ti] & UnitStats.MOUNTED != 0
		# то же, что t_speed × _tired(s) × _spd_at / вода (без вызовов: горячий цикл)
		var stam := sq_stam[s]
		var vmax := t_speed[ti] * (1.0 if stam >= STAMINA_TIRED else 0.7 + 0.3 * stam / STAMINA_TIRED)
		if has_spd:
			var sgx := floori((u_x[u] - gro.x) / _CELL)
			var sgz := floori((u_z[u] - gro.y) / _CELL)
			if sgx >= 0 and sgz >= 0 and sgx < _grid_w and sgz < _grid_h:
				vmax *= _spd[sgz * _grid_w + sgx] / 16.0
		else:
			var dc := _dry[clampi(int((u_z[u] - go) / _CELL), 0, gmax) * gn + clampi(int((u_x[u] - go) / _CELL), 0, gmax)]
			if dc != 1 and (dc == 2 or not _surely_dry(u_x[u], u_z[u])) and Terrain.is_water(u_x[u], u_z[u]):
				vmax *= 0.55
		if has_mods:
			vmax *= owner_mod(u_owner[u], MOD_SPEED)
		var x := u_x[u]
		var z := u_z[u]
		var gx := x
		var gz := z
		var spd := 0.0
		var stop := 0.15
		# --- бегство: прочь от врага, к своему краю поля (или домой — FleeMode.HOME)
		if sq_status[s] == Status.FLEE:
			# ближайший отряд посчитан в шаге отряда; если он погиб в этом же шаге — заново (тот же ответ)
			var e := sq_enemy[s]
			if e < 0 or sq_alive[e] == 0:
				e = _nearest_enemy_squad(s)
			var away := Vector2(1.0 if u_side[u] == 0 else -1.0, 0.0)
			if flee_mode == FleeMode.HOME and u_side[u] < team_home.size():
				var hv := team_home[u_side[u]] - Vector2(x, z)
				if hv.length_squared() < 64.0:
					u_target[u] = -1
					_set_desire(u, x, z, 0.0, stop)
					continue
				away = hv.normalized()
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
		# --- стойки (R9): DEFENSIVE (работники), HOLD, PASSIVE — своя короткая логика
		var stance := sq_stance[s]
		if stance != Stance.AGGRESSIVE:
			_think_guard(u, s, ti, vmax, stance, obstacles)
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
				var c := -1
				# город: в блоке юнита и соседних (≥ 16 м вокруг) чужих нет — искать нечего (тот же ответ −1)
				if not sleep_on or engage_r > 16.0 or _bmask_n[_ublk[u]] & ~(1 << u_side[u]) != 0:
					c = _nearest_enemy_raider(u, engage_r) if t_flags[ti] & UnitStats.RAIDER != 0 else nearest_enemy(u, engage_r)
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
		elif sq_st_target[s] >= 0 and (sq_melee[s] == 1 or sq_single[s] == 1) and not is_ranged_type(ti):
			# ломать постройку (R8): к ближней точке стены
			var sst := sq_st_target[s]
			var sp := st_nearest(sst, x, z)
			gx = sp.x
			gz = sp.y
			stop = t_radius[ti] + t_reach[ti] * 0.55
			spd = vmax * 0.8
			_try_melee_st(u, sst, sp)
		else:
			# место в строю: скорость якоря + поправка к месту (одиночка — сам якорь: смещение 0)
			var p2 := Vector2(sq_x[s], sq_z[s]) if sq_single[s] == 1 else slot_point(s, u)
			if obstacles and sq_single[s] == 0 and (sq_vx[s] != 0.0 or sq_vz[s] != 0.0) \
					and point_blocked(p2.x, p2.y, u_side[u]):
				p2 = _trail_target(s, x, z)
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


## Стойки DEFENSIVE / HOLD / PASSIVE (R9): цель — только вплотную (досягаемость + 1 м; HOLD — досягаемость),
## DEFENSIVE не гонится дальше 6 м от своего места и возвращается; HOLD бьёт, не сходя с места; PASSIVE не бьёт.
func _think_guard(u: int, s: int, ti: int, vmax: float, stance: int, obstacles: bool) -> void:
	var x := u_x[u]
	var z := u_z[u]
	var tg := u_target[u]
	if tg >= 0 and u_life[tg] != Life.ALIVE:
		tg = -1
	var p := slot_point(s, u)
	if stance == Stance.PASSIVE:
		tg = -1
	else:
		var reach := t_radius[ti] + t_reach[ti] + 0.5
		if stance == Stance.DEFENSIVE:
			reach += DEF_REACH_PAD
		if tg < 0 and (u + steps) % 3 == 0 and (not sleep_enabled or _bmask_n[_ublk[u]] & ~(1 << u_side[u]) != 0):
			var c := nearest_enemy(u, reach)
			if c >= 0 and sq_status[u_squad[c]] != Status.FLEE:
				tg = c
		if tg >= 0:
			if stance == Stance.DEFENSIVE:
				var ax := x - p.x
				var az := z - p.y
				if ax * ax + az * az > DEF_LEASH * DEF_LEASH:
					tg = -1  # дальше 6 м от места не гонится
			else:
				var hx := u_x[tg] - x
				var hz := u_z[tg] - z
				if hx * hx + hz * hz > (reach + 0.5) * (reach + 0.5):
					tg = -1
	u_target[u] = tg
	if tg >= 0:
		var rr := t_radius[ti] + t_radius[u_type[tg]]
		if stance == Stance.DEFENSIVE:
			_set_desire(u, u_x[tg], u_z[tg], vmax * 0.8, rr + t_reach[ti] * 0.55)
		else:
			u_dvx[u] = 0.0
			u_dvz[u] = 0.0
		_try_melee(u, tg, rr)
		return
	# место (у одиночки — якорь): скорость якоря + поправка к месту
	if obstacles and sq_single[s] == 0 and (sq_vx[s] != 0.0 or sq_vz[s] != 0.0) and point_blocked(p.x, p.y, u_side[u]):
		p = _trail_target(s, x, z)
	var ex := p.x - x
	var ez := p.y - z
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


## RAIDER (R9): ближайший враг, но работник «ближе» (×0,25 квадрата расстояния)
func _nearest_enemy_raider(u: int, r: float) -> int:
	var x := u_x[u]
	var z := u_z[u]
	var side := u_side[u]
	var gn := _g_n
	var go := _g_origin
	var cr := ceili(r / _CELL)
	var cx := clampi(int((x - go) / _CELL), 0, gn - 1)
	var cz := clampi(int((z - go) / _CELL), 0, gn - 1)
	var foe := ~(1 << side)
	var best := -1
	var bs := r * r
	for gz in range(maxi(cz - cr, 0), mini(cz + cr, gn - 1) + 1):
		for gx in range(maxi(cx - cr, 0), mini(cx + cr, gn - 1) + 1):
			var c := gz * gn + gx
			if _cmask[c] & foe == 0:
				continue
			var v := _head[c]
			while v >= 0:
				if u_side[v] != side:
					var dx := u_x[v] - x
					var dz := u_z[v] - z
					var d2 := dx * dx + dz * dz
					if d2 <= r * r:
						var sc := d2 * (RAIDER_WORKER_K if t_flags[u_type[v]] & UnitStats.WORKER != 0 else 1.0)
						if sc < bs:
							bs = sc
							best = v
				v = _next[v]
	return best


## Скорость земли (×16 → доля) в клетке NAV
func _spd_at(x: float, z: float) -> float:
	var gx := floori((x - _grid_origin.x) / _CELL)
	var gz := floori((z - _grid_origin.y) / _CELL)
	if gx < 0 or gz < 0 or gx >= _grid_w or gz >= _grid_h:
		return 1.0
	return _spd[gz * _grid_w + gx] / 16.0


## Спящего сдвинули с места больше чем на 0,5 м (место одиночки — якорь)
func _pushed_off(u: int) -> bool:
	var s := u_squad[u]
	var dx := 0.0
	var dz := 0.0
	if sq_single[s] == 1:
		dx = sq_x[s] - u_x[u]
		dz = sq_z[s] - u_z[u]
	else:
		var p := slot_point(s, u)
		dx = p.x - u_x[u]
		dz = p.y - u_z[u]
	return dx * dx + dz * dz > 0.25


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


## Удар по постройке: ровно раз в ST_MELEE_COOL (стена не уворачивается — без промахов)
func _try_melee_st(u: int, st: int, p: Vector2) -> void:
	if time < u_cool_t[u] or u_hit_t[u] >= 0.0 or u_fire_t[u] >= 0.0:
		return
	var ti := u_type[u]
	var dx := p.x - u_x[u]
	var dz := p.y - u_z[u]
	var rr := t_radius[ti] + t_reach[ti]
	if dx * dx + dz * dz > rr * rr:
		return
	u_act[u] = Act.MELEE
	u_act_t[u] = time
	u_hit_t[u] = time + MELEE_HIT_DELAY
	u_cool_t[u] = time + ST_MELEE_COOL


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
	var atk := t_attack[ti]
	if own_mods.size() > 0:
		atk *= owner_mod(u_owner[u], MOD_ATK)
		counter *= owner_mod(u_owner[tg], MOD_ATK)
	var dmg := maxf(1.0, atk * mult - t_armour[tti])
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


## 0..n−1 одним массивом (обход «всех» тем же кодом, что и обход бодрых)
func _all_units() -> PackedInt32Array:
	var old := _all.size()
	if old != n:
		_all.resize(n)
		for u in range(old, n):
			_all[u] = u
	return _all


## Город: тела по очереди смертей — слот свободен через corpse_t после смерти (ещё падает — ждём)
func _corpse_pass(corpse_t: float) -> void:
	var q := _corpse
	var h := _corpse_h
	while h < q.size():
		var u := q[h]
		var life := u_life[u]
		if u_gen[u] != q[h + 1] or (life != Life.DEAD and life != Life.DYING):
			h += 2  # слот уже свободен (убран) или занят новым
			continue
		if time - u_death_t[u] < corpse_t or life == Life.DYING:
			break
		h += 2
		_free_unit(u)
	if h >= _corpse.size():
		_corpse.clear()
		h = 0
	elif h >= 512 and h * 2 >= _corpse.size():
		_corpse = _corpse.slice(h)  # голова ушла далеко: сжать (массив свой, вид его не читает)
		h = 0
	_corpse_h = h


func _resolve_actions() -> void:
	var sleep_on := sleep_enabled
	var recycle := corpse_steps >= 0
	var corpse_t := corpse_steps * DT
	if sleep_on and recycle:
		_corpse_pass(corpse_t)
	for u: int in (_aw if sleep_on else _all_units()):
		var life := u_life[u]
		if life == Life.DYING:
			var dur := DEATH_DURATION_HORSE if t_flags[u_type[u]] & UnitStats.MOUNTED != 0 else DEATH_DURATION_HUMAN
			if time - u_death_t[u] >= dur:
				u_life[u] = Life.DEAD
			continue
		if life != Life.ALIVE:
			# тело лежит corpse_steps шагов, потом слот свободен (R1; город — очередью тел)
			if recycle and not sleep_on and life == Life.DEAD and time - u_death_t[u] >= corpse_t:
				_free_unit(u)
			continue
		if sleep_on and u_sleep[u] == 1:
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
	var rmax := t_range[ti]
	if own_mods.size() > 0:
		rmax *= owner_mod(u_owner[u], MOD_RANGE)
	if tg <= -2:
		# по постройке (R8): попадает всегда, урон × vs_building — в ev_st_* (ядро HP не меняет)
		var st := -2 - tg
		if st < st_hw and st_alive[st] == 1:
			var p := st_nearest(st, u_x[u], u_z[u])
			var d := Vector2(p.x - u_x[u], p.y - u_z[u])
			var dist := d.length()
			if dist <= rmax * 1.05:
				if dist > 0.01:
					dir = Vector3(d.x / dist, 0.02, d.y / dist)
				hit = true
				var dmg := t_missile[ti] * t_vs_building[ti]
				if own_mods.size() > 0:
					dmg *= owner_mod(u_owner[u], MOD_ATK)
				_st_hit(st, dmg, u)
	elif tg >= 0 and u_life[tg] == Life.ALIVE:
		var d := Vector2(u_x[tg] - u_x[u], u_z[tg] - u_z[u])
		var dist := d.length()
		if dist <= rmax * 1.05:
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
	if own_mods.size() > 0:
		dmg *= owner_mod(u_owner[u], MOD_ATK)
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
	if tg < 0:
		_melee_hit_st(u)
		return
	if u_life[tg] != Life.ALIVE:
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
	if own_mods.size() > 0:
		dmg *= owner_mod(u_owner[u], MOD_ATK)
	if t_flags[tti] & UnitStats.MOUNTED != 0:
		dmg *= t_vs_cav[ti]
	if fleeing:
		dmg *= 1.2
	var pos := Vector3((u_x[u] + u_x[tg]) * 0.5, 0.0, (u_z[u] + u_z[tg]) * 0.5)
	pos.y = Terrain.height_at(pos.x, pos.z) + (1.7 if t_flags[ti] & UnitStats.MOUNTED != 0 else 1.2)
	melee_hit.emit(u, tg, pos)
	_damage(tg, maxf(1.0, dmg - t_armour[tti]), u)


## Удар по постройке-цели отряда (R8): атака × усталость × vs_building × множитель игрока → ev_st_*
func _melee_hit_st(u: int) -> void:
	var s := u_squad[u]
	if s < 0:
		return
	var st := sq_st_target[s]
	if st < 0 or st_alive[st] == 0:
		return
	var ti := u_type[u]
	var p := st_nearest(st, u_x[u], u_z[u])
	var dx := p.x - u_x[u]
	var dz := p.y - u_z[u]
	var rr := t_radius[ti] + t_reach[ti] + 0.8
	if dx * dx + dz * dz > rr * rr:
		return
	var dmg := t_attack[ti] * _tired(s) * t_vs_building[ti]
	if own_mods.size() > 0:
		dmg *= owner_mod(u_owner[u], MOD_ATK)
	_st_hit(st, dmg, u)


func _st_hit(st: int, dmg: float, by: int) -> void:
	if collect_events:
		ev_st_b.append(st)
		ev_st_dmg.append(dmg)
		ev_st_by.append(by)


func _damage(tg: int, dmg: float, attacker: int) -> void:
	if u_life[tg] != Life.ALIVE:
		return
	u_hurt_step[tg] = steps
	if u_sleep[tg] == 1:
		_wake(tg)
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
	if u_sleep[u] == 1:
		_wake(u)
	u_killer[u] = attacker
	_hash_dirty = true
	if sleep_enabled:
		_hq.append(u)  # вон из хэша при ближайшей сборке
		if corpse_steps >= 0:
			_corpse.append(u)
			_corpse.append(u_gen[u])
	if collect_events:
		ev_dead.append(u)
		ev_dead.append(attacker)
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
	var sleep_on := sleep_enabled
	for u: int in (_aw if sleep_on else _all_units()):
		var life := u_life[u]
		if life == Life.DEAD or life == Life.FREE:
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
		if sleep_on and u_sleep[u] == 1:
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
		var hstep := rate * DT
		u_h[u] += clampf(angle_difference(u_h[u], want), -hstep, hstep)  # rotate_toward без вызова
		if sleep_on and sp < 0.05:
			_try_sleep(u)
	if sleep_on:
		_separate_city()
	else:
		_separate()
	if _st_live > 0 or _blk_static.size() > 0:
		_collide()


## Засыпает (R12): стоит на месте (скорость < 0,05, желаемая 0), без цели, выстрела, удара и натиска,
## отряд держит место (HOLD, не бежит, не в свалке), курс устоялся; одиночка ещё и отдохнул.
func _try_sleep(u: int) -> void:
	if u_dvx[u] != 0.0 or u_dvz[u] != 0.0 or u_target[u] >= 0 or u_fire_t[u] >= 0.0 or u_hit_t[u] >= 0.0:
		return
	var a := u_act[u]
	if (a != Act.NONE and a != Act.WORK) or u_couched[u] == 1 or absf(u_kx[u]) + absf(u_kz[u]) > 0.01:
		return
	var s := u_squad[u]
	if sq_order[s] != Order.HOLD or sq_status[s] != Status.READY or sq_melee[s] == 1:
		return
	if sq_single[s] == 1 and sq_stam[s] < 100.0:
		return
	if absf(angle_difference(u_h[u], sq_h[s])) > 0.02:
		return
	# враг рядом (блок 16 м и соседи) — не спит: иначе будильник поднимет его на следующем шаге
	if _ucell[u] >= 0 and _bmask_n[_ublk[u]] & ~(1 << u_side[u]) != 0:
		return
	u_vx[u] = 0.0
	u_vz[u] = 0.0
	u_sleep[u] = 1
	if sq_single[s] == 1:
		sq_dorm[s] = 1
	# в хэш его переложит сборка конца шага (он ещё в _aw)
	# спит на месте: прошлый шаг = этот (вид не качает его между ними; шаг начала его пропускает)
	u_px[u] = u_x[u]
	u_pz[u] = u_z[u]
	u_ph[u] = u_h[u]


## Расталкивание: никто не стоит друг в друге (пространственный хэш, одна итерация)
func _separate() -> void:
	var rmax := 0.0
	for r in t_radius:
		rmax = maxf(rmax, r)
	var gn := _g_n
	var go := _g_origin
	var gmax := gn - 1
	for u in n:
		if u_life[u] != Life.ALIVE:
			continue
		var x := u_x[u]
		var z := u_z[u]
		var ru := t_radius[u_type[u]]
		var mu := t_mass[u_type[u]]
		var lim := ru + rmax
		var xu := x
		var zu := z
		var cx := clampi(int((x - go) / _CELL), 0, gmax)
		var cz := clampi(int((z - go) / _CELL), 0, gmax)
		for gz in range(maxi(cz - 1, 0), mini(cz + 1, gmax) + 1):
			for gx in range(maxi(cx - 1, 0), mini(cx + 1, gmax) + 1):
				# списки клеток идут по убыванию номера: после v <= u пар (v > u) в клетке больше нет
				var v := _head[gz * gn + gx]
				while v > u:
					# дальше суммы радиусов по x или z — не касаются (|dx| ≥ rr ⇒ d2 ≥ rr²): не считаем
					var dx := u_x[v] - xu
					if dx >= lim or dx <= -lim:
						v = _next[v]
						continue
					var dz := u_z[v] - zu
					if dz >= lim or dz <= -lim:
						v = _next[v]
						continue
					if u_life[v] == Life.ALIVE:
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
							xu = u_x[u]
							zu = u_z[u]
					v = _next[v]


## Расталкивание города (сон включён): пары бодрых из _aw — один раз (у меньшего номера),
## «бодрый — прочий» (спящий, разбуженный на этом шаге) — у бодрого; спящие между собой не толкаются
func _separate_city() -> void:
	var rmax := 0.0
	for r in t_radius:
		rmax = maxf(rmax, r)
	var gn := _g_n
	var go := _g_origin
	var gmax := gn - 1
	for u: int in _aw:
		if u_life[u] != Life.ALIVE or u_sleep[u] == 1:
			continue
		var ru := t_radius[u_type[u]]
		var mu := t_mass[u_type[u]]
		var lim := ru + rmax
		var xu := u_x[u]
		var zu := u_z[u]
		var cx := clampi(int((xu - go) / _CELL), 0, gmax)
		var cz := clampi(int((zu - go) / _CELL), 0, gmax)
		# только клетки ближе lim (+1 м: хэш — по позициям конца прошлого шага), не дальше соседних
		var pad := lim + 1.0
		var x0 := maxi(clampi(int((xu - pad - go) / _CELL), 0, gmax), cx - 1)
		var x1 := mini(clampi(int((xu + pad - go) / _CELL), 0, gmax), cx + 1)
		var z0 := maxi(clampi(int((zu - pad - go) / _CELL), 0, gmax), cz - 1)
		var z1 := mini(clampi(int((zu + pad - go) / _CELL), 0, gmax), cz + 1)
		for gz in range(z0, z1 + 1):
			for gx in range(x0, x1 + 1):
				var v := _head[gz * gn + gx]
				while v >= 0:
					if v == u or (v < u and _aw_on[v] == 1 and u_sleep[v] == 0):
						v = _next[v]
						continue
					var dx := u_x[v] - xu
					if dx >= lim or dx <= -lim:
						v = _next[v]
						continue
					var dz := u_z[v] - zu
					if dz >= lim or dz <= -lim:
						v = _next[v]
						continue
					if u_life[v] == Life.ALIVE:
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
							xu = u_x[u]
							zu = u_z[u]
							if u_sleep[v] == 1:
								_wake(v)  # толкнули спящего — проснётся и вернётся на место
					v = _next[v]


## Столкновения с препятствиями (R7): точное выталкивание из прямоугольников построек (поля и свои
## ворота пропускают), клетки земли — скольжение по осям (иначе назад на место начала шага)
func _collide() -> void:
	var has_st := _st_live > 0
	var has_blk := _blk_static.size() > 0
	var sbo := _sb_origin
	var sbn := _sb_n
	var gro := _grid_origin
	var gw := _grid_w
	var gh := _grid_h
	for u: int in (_aw if sleep_enabled else _all_units()):
		if u_life[u] != Life.ALIVE or u_sleep[u] == 1:
			continue
		var x := u_x[u]
		var z := u_z[u]
		if has_st:
			var bx := floori((x - sbo.x) / ST_BUCKET)
			var bz := floori((z - sbo.y) / ST_BUCKET)
			if bx >= 0 and bz >= 0 and bx < sbn and bz < sbn:
				var list := _sb[bz * sbn + bx]
				if not list.is_empty():
					var r := t_radius[u_type[u]]
					var team := u_side[u]
					for st in list:
						var f := st_flags[st]
						if f & ST_FIELD != 0 or (f & ST_GATE != 0 and st_team[st] == team):
							continue
						var c := cos(st_rot[st])
						var sn := sin(st_rot[st])
						var dx := x - st_cx[st]
						var dz := z - st_cz[st]
						var lx := dx * c - dz * sn
						var lz := dx * sn + dz * c
						var ex := st_hx[st] + r
						var ez := st_hz[st] + r
						if absf(lx) >= ex or absf(lz) >= ez:
							continue
						if ex - absf(lx) < ez - absf(lz):
							lx = ex if lx >= 0.0 else -ex
						else:
							lz = ez if lz >= 0.0 else -ez
						x = st_cx[st] + lx * c + lz * sn
						z = st_cz[st] - lx * sn + lz * c
					u_x[u] = x
					u_z[u] = z
		if has_blk:
			var cx := floori((x - gro.x) / _CELL)
			var cz := floori((z - gro.y) / _CELL)
			if cx < 0 or cz < 0 or cx >= gw or cz >= gh or _blk_static[cz * gw + cx] == 0:
				continue
			var px := u_px[u]
			var pz := u_pz[u]
			var pcx := floori((px - gro.x) / _CELL)
			var pcz := floori((pz - gro.y) / _CELL)
			if pcx < 0 or pcz < 0 or pcx >= gw or pcz >= gh:
				u_x[u] = px
				u_z[u] = pz
				continue
			if _blk_static[pcz * gw + pcx] != 0:
				continue  # уже стоял на закрытой клетке — выпускаем
			if _blk_static[pcz * gw + cx] == 0:
				u_z[u] = pz
			elif _blk_static[cz * gw + pcx] == 0:
				u_x[u] = px
			else:
				u_x[u] = px
				u_z[u] = pz


func _victory_check() -> void:
	if winner >= 0 or victory_mode == Victory.NONE:
		return
	for side in MAX_TEAMS:
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
			winner = 1 - side if side < 2 else _other_team(side)
			battle_over.emit(winner)
			return


func _other_team(side: int) -> int:
	for t in MAX_TEAMS:
		if t != side and side_init[t] > 0:
			return t
	return -1


# ================================================================= служебное

func _pos3(u: int) -> Vector3:
	return Vector3(u_x[u], Terrain.height_at(u_x[u], u_z[u]), u_z[u])


## Контрольная сумма состояния (проверка детерминизма). «Город» (R14): поколения, игроки, сон, стойки,
## точки пути, структуры и свободные списки подмешиваются, только когда они не как в срезе — сумма среза та же.
func checksum() -> int:
	var h := 17
	for u in n:
		h = (h * 31 + int(u_x[u] * 1000.0)) & 0x7FFFFFFF
		h = (h * 31 + int(u_z[u] * 1000.0)) & 0x7FFFFFFF
		h = (h * 31 + int(u_hp[u] * 100.0)) & 0x7FFFFFFF
		h = (h * 31 + u_life[u]) & 0x7FFFFFFF
	for s in squads:
		h = (h * 31 + int(sq_morale[s] * 100.0)) & 0x7FFFFFFF
	for u in n:
		if u_gen[u] != 1 or u_owner[u] != u_side[u] or u_sleep[u] != 0:
			h = (h * 31 + u * 8191 + u_gen[u] * 127 + u_owner[u] * 7 + u_sleep[u]) & 0x7FFFFFFF
	for s in squads:
		if sq_gen[s] != 1 or sq_owner[s] != sq_side[s] or sq_stance[s] != Stance.AGGRESSIVE or sq_wp[s] != 0 \
				or sq_used[s] == 0:
			h = (h * 31 + s * 8191 + sq_gen[s] * 127 + sq_owner[s] * 31 + sq_stance[s] * 7 + sq_wp[s] * 3
				+ sq_used[s]) & 0x7FFFFFFF
	for st in st_hw:
		h = (h * 31 + st * 3 + st_alive[st]) & 0x7FFFFFFF
	for u in _u_free:
		h = (h * 31 + u) & 0x7FFFFFFF
	for s in _sq_free:
		h = (h * 31 + s) & 0x7FFFFFFF
	return h


static func rotate_toward(from: float, to: float, max_step: float) -> float:
	var d := angle_difference(from, to)
	return from + clampf(d, -max_step, max_step)
