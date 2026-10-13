class_name SimDriver
extends Node
## Узел, который шагает симуляцию (ARCHITECTURE §7.6, §18): фиксированный шаг 1/30 с, не больше 12 шагов
## за кадр, пауза и скорость (локальны), доля шага alpha для плавного движения между шагами.
## Сигналы ядра (BattleSim) переходят в сигналы узла — только для эффектов (BattleFx, кинокамера):
## кто их слушает, не меняет состояние симуляции.
##
## Наследники: ScenarioClash (срез), GameDriver (GAME, «Город»), FakeCityDriver (поддельный город VIEW/UI).
## Вид и оболочка боя (BattleView, BattleFx, BattleHud, BattleRoot, BattleAmbient, SimStepper) типизированы
## этим классом. Когда шаги ведёт вид (SimStepper), _process узла выключен, а счёт времени тот же.
##
## Создал ведущий (M0); дальше владелец — CORE.

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

var _acc := 0.0


## Начать заново с зерном p_seed (наследник создаёт sim, зовёт wire_sim и started.emit)
func start(p_seed: int) -> void:
	current_seed = p_seed


## Один шаг симуляции
func step() -> void:
	if sim:
		sim.step()


## Заново с тем же зерном (клавиша R в срезе)
func restart() -> void:
	start(current_seed)


## Сигналы ядра → сигналы узла (наследник может направить часть через свои обработчики)
func wire_sim(s: BattleSim) -> void:
	s.shot.connect(shot.emit)
	s.volley.connect(volley.emit)
	s.charge_ordered.connect(charge_ordered.emit)
	s.impact.connect(impact.emit)
	s.charge_hit.connect(charge_hit.emit)
	s.melee_hit.connect(melee_hit.emit)
	s.death.connect(death.emit)
	s.war_cry.connect(war_cry.emit)
	s.rout.connect(rout.emit)
	s.rallied.connect(rallied.emit)
	s.battle_over.connect(battle_over.emit)


## true — после следующего шага начнётся новая симуляция (sim заменится): SimStepper делает такой шаг
## на главном потоке, не в фоне
func restarts_next() -> bool:
	return false


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
