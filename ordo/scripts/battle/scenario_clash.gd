class_name ScenarioClash
extends Node
## Сценарий среза «Столкновение» (~40 с): сарбозы Коканда против сайыскеров кыпчаков.
##
## Раскадровка (времена примерные — они получаются из симуляции):
##   0–2 с   отряды строятся; кокандская линия идёт шагом вперёд, встаёт, готовит ружья
##   ~3 с    Колбашчы выезжает перед конницей — боевой клич (CHEER)
##   5–9 с   конница: шаг → рысь → галоп; копья наперевес (CHARGE)
##   ~9 с    залп первой шеренги (дым!), через 1.7–2 с — второй; падают кони и всадники
##   12–15 с удар натиска, свалка
##   ~18 с   мораль Коканда ломается — бегство на восток; конница преследует, потом собирается
## Конец около 44 с; при loop — сначала.
##
## Узел шагает сам (_process, фиксированный шаг 1/30 с, скорость и пауза — time_scale, paused).
## Для тестов без графики: start(seed); step() в цикле.

signal started(seed: int)
signal finished
signal shot(unit: int, muzzle: Vector3, dir: Vector3, hit: bool)
signal volley(squad: int, rank: int, center: Vector3, count: int)
signal charge_ordered(squad: int)
signal impact(squad: int, pos: Vector3, strength: float)
signal charge_hit(unit: int, target: int, pos: Vector3)
signal melee_hit(attacker: int, target: int, pos: Vector3)
signal death(unit: int, pos: Vector3)
signal war_cry(unit: int, pos: Vector3)
signal rout(squad: int, pos: Vector3)
signal rallied(squad: int, pos: Vector3)
signal battle_over(winner: int)

const DT := BattleSim.DT

## Место и состав (CONTRACT §3: поле боя (90, 0) ±80 м)
const KOK_POS := Vector2(115.0, 0.0)
const KIP_POS := Vector2(25.0, 10.0)
const KOK_COUNT := 100
const KIP_COUNT := 60
const KOK_HALT_X := 106.0      # где кокандская линия встаёт
const FIRE_DIST := 64.0        # первая шеренга стреляет, когда конница ближе (≤ 90 м)
const WAR_CRY_AT := 3.0
const KIP_WALK_AT := 4.4
const KIP_TROT_AT := 5.6
const KIP_GALLOP_AT := 6.8
const PURSUE_TIME := 7.0       # сколько конница гонит бегущих
const RALLY_POS := Vector2(84.0, 6.0)
const END_TIME := 44.0

@export var autostart := true
@export var loop := true
## Зерно боя (аргумент --seed=N его заменяет)
@export var battle_seed := 1
## Новое зерно на каждом круге (иначе бой повторяется кадр в кадр)
@export var vary_seed_on_loop := false

var sim: BattleSim
var time: float:
	get:
		return sim.time if sim else 0.0
## Скорость времени (+/−) и пауза (P)
var time_scale := 1.0
var paused := false
## Доля шага для плавного движения между шагами (0..1)
var alpha := 0.0
var current_seed := 1

## Отряды сценария
var kok := -1
var kip := -1
var gen := -1

var _acc := 0.0
var _kok_phase := 0
var _kip_phase := 0
var _gen_phase := 0
var _rout_t := -1.0
var _over_t := -1.0
var _ended := false


func _ready() -> void:
	if not Engine.is_editor_hint() and autostart:
		var s := battle_seed
		var ordo := get_node_or_null("/root/Ordo")
		if ordo and ordo.has_arg("seed"):
			s = int(ordo.arg("seed"))
		start(s)


## Начать бой заново с зерном p_seed
func start(p_seed: int) -> void:
	current_seed = p_seed
	sim = BattleSim.new(p_seed)
	_acc = 0.0
	alpha = 0.0
	_kok_phase = 0
	_kip_phase = 0
	_gen_phase = 0
	_rout_t = -1.0
	_over_t = -1.0
	_ended = false
	# Коканд: «Сарбозлар», две шеренги по 50, юзбоши верхом сзади, знаменосец
	kok = sim.add_squad(0, "sarboz", KOK_COUNT, KOK_POS, -PI / 2, BattleSim.Formation.LINE, 50, "yuzboshi", true, 0.35)
	# Кыпчаки: «Сайыскерлер», две шеренги по 30, жүз башы впереди, туугчу; собираются из толпы
	kip = sim.add_squad(1, "sayisker", KIP_COUNT, KIP_POS, PI / 2, BattleSim.Formation.LINE, 30, "juz_bashy", true, 2.2)
	# полководец ждёт перед правым крылом и выезжает к центру строя
	gen = sim.add_general(1, "kolbashchy", KIP_POS + Vector2(11.0, 16.0), PI)
	_wire()
	started.emit(p_seed)


func _wire() -> void:
	sim.shot.connect(shot.emit)
	sim.volley.connect(volley.emit)
	sim.charge_ordered.connect(charge_ordered.emit)
	sim.impact.connect(impact.emit)
	sim.charge_hit.connect(charge_hit.emit)
	sim.melee_hit.connect(melee_hit.emit)
	sim.death.connect(death.emit)
	sim.war_cry.connect(war_cry.emit)
	sim.rout.connect(_on_rout)
	sim.rallied.connect(rallied.emit)
	sim.battle_over.connect(_on_over)


func _on_rout(s: int, pos: Vector3) -> void:
	if s == kok and _rout_t < 0.0:
		_rout_t = sim.time
	rout.emit(s, pos)


func _on_over(w: int) -> void:
	_over_t = sim.time
	battle_over.emit(w)


func _process(delta: float) -> void:
	if sim == null or paused:
		return
	_acc += delta * time_scale
	var guard := 0
	while _acc >= DT and guard < 12:
		_acc -= DT
		step()
		guard += 1
	if guard >= 12:
		_acc = 0.0
	alpha = clampf(_acc / DT, 0.0, 1.0)


## Один шаг: решения ИИ, затем симуляция
func step() -> void:
	if sim == null:
		return
	_ai()
	sim.step()
	if not _ended and sim.time >= END_TIME:
		_ended = true
		finished.emit()
		if loop and is_inside_tree():
			start(current_seed + 1 if vary_seed_on_loop else current_seed)


## Перезапуск (клавиша R)
func restart() -> void:
	start(current_seed)


# ---------------------------------------------------------------- ИИ сценария

func _ai() -> void:
	var t := sim.time
	_ai_kokand(t)
	_ai_kipchak(t)
	_ai_general(t)


func _ai_kokand(t: float) -> void:
	if sim.is_fleeing(kok):
		return
	match _kok_phase:
		0:
			# строятся
			if t >= 1.6:
				sim.order_move(kok, Vector2(KOK_HALT_X, KOK_POS.y), BattleSim.Gait.WALK, -PI / 2)
				_kok_phase = 1
		1:
			if sim.sq_order[kok] == BattleSim.Order.HOLD:
				_kok_phase = 2
				_kok_ready_t = t + 1.0
		2:
			# встали, «готовь!» — ружья к бою
			if t >= _kok_ready_t:
				sim.set_fire(kok, kip, FIRE_DIST)
				_kok_phase = 3


var _kok_ready_t := 0.0


func _ai_kipchak(t: float) -> void:
	if sim.is_fleeing(kip):
		return
	match _kip_phase:
		0:
			if t >= KIP_WALK_AT:
				sim.order_attack(kip, kok, BattleSim.Gait.WALK)
				_kip_phase = 1
		1:
			if t >= KIP_TROT_AT:
				sim.set_gait(kip, BattleSim.Gait.TROT)
				_kip_phase = 2
		2:
			if t >= KIP_GALLOP_AT:
				sim.set_gait(kip, BattleSim.Gait.RUN)
				sim.allow_charge(kip, true)
				_kip_phase = 3
		3:
			# преследуем бегущих, потом собираемся
			if _rout_t >= 0.0 and (t - _rout_t > PURSUE_TIME or sim.squad_alive(kok) == 0):
				sim.order_move(kip, RALLY_POS, BattleSim.Gait.TROT, PI / 2)
				sim.sq_melee[kip] = 0
				_kip_phase = 4
		4:
			if sim.sq_order[kip] == BattleSim.Order.HOLD:
				sim.cheer(kip)
				_kip_phase = 5


func _ai_general(t: float) -> void:
	var g := sim.general[1]
	if g < 0 or not sim.is_alive(g):
		return
	match _gen_phase:
		0:
			# выезжает перед строем, лицом к врагу
			if t >= 0.3:
				sim.order_move(gen, KIP_POS + Vector2(12.0, 1.0), BattleSim.Gait.RUN, PI / 2)
				_gen_phase = 1
		1:
			if t >= WAR_CRY_AT:
				sim.war_cry_now(gen)
				_gen_phase = 2
		2:
			# уходит на правый фланг, пропуская конницу
			if t >= KIP_WALK_AT - 0.2:
				sim.order_move(gen, KIP_POS + Vector2(16.0, 22.0), BattleSim.Gait.RUN, PI / 2)
				_gen_phase = 3
		3:
			# держится позади своих (ТЗ 7), раз в секунду поправляет место
			if sim.steps % 30 == 0:
				var c := sim.squad_centroid(kip)
				var target := Vector2(c.x - 26.0, c.y + 14.0)
				if _over_t >= 0.0 or _kip_phase >= 4:
					target = RALLY_POS + Vector2(10.0, 0.0)
				sim.order_move(gen, target, BattleSim.Gait.TROT, PI / 2)
			if _kip_phase >= 5:
				_gen_phase = 4
		4:
			if sim.sq_order[gen] == BattleSim.Order.HOLD:
				sim.cheer(gen)
				_gen_phase = 5
