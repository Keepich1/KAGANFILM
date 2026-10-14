class_name StressScenario
extends ScenarioClash
## Нагрузочный бой для среза (F9): дополнительные отряды сарбозов и сайыскеров на южной части
## луга, рядом с основным столкновением. Та же симуляция и та же толпа, что у основного боя, —
## автор проверяет, сколько солдат тянет его компьютер (ТЗ 11.5: 1000+ в бою).
##
## soldiers — сколько добавить (≈60% сарбозов отрядами по 100, ≈40% сайыскеров по 60).
##
## Сигналы ядра (выстрелы, залпы, смерти…) идут эффектам (BattleFx в срезе). Большой бой SimStepper
## считает в фоне, а сигнал узла из фонового потока движок не пропускает («caller thread can't call
## emit_signalp»), поэтому сигналы фонового шага копятся здесь и выходят на главном потоке — когда
## фон свободен (SimStepper спрашивает restarts_next() перед следующим фоновым шагом) или следующим
## шагом на главном потоке, в том же порядке. Состояние боя от этого не меняется.

## Сколько солдат добавить
var soldiers := 1000

## Сигналы ядра, которые узел передаёт дальше
const RELAYED: Array[StringName] = [&"shot", &"volley", &"charge_ordered", &"impact", &"charge_hit",
	&"melee_hit", &"death", &"war_cry", &"rout", &"rallied", &"battle_over"]

var _kok_sq: Array[int] = []
var _kip_sq: Array[int] = []
var _ordered := false
var _ev: Array = []               # [имя, аргументы] — сигналы фонового шага
var _ev_lock := Mutex.new()
var _main_tid := OS.get_main_thread_id()
var _stepping := false


func _ready() -> void:
	# стартует срез (start), а не сам узел
	autostart = false
	loop = true
	super._ready()


func start(p_seed: int) -> void:
	current_seed = p_seed
	sim = BattleSim.new(p_seed)
	alpha = 0.0
	_acc = 0.0
	_ended = false
	_ordered = false
	_kok_sq.clear()
	_kip_sq.clear()
	var kok_n := maxi(1, roundi(soldiers * 0.6 / 100.0))
	var kip_n := maxi(1, roundi(soldiers * 0.4 / 60.0))
	# Коканд — колонны отрядов на востоке, лицом на запад; кыпчаки — на западе, лицом на восток
	for i in kok_n:
		var p := Vector2(150.0 + float(i / 6) * 16.0, 48.0 + float(i % 6) * 26.0)
		_kok_sq.append(sim.add_squad(0, "sarboz", 100, p, -PI / 2, BattleSim.Formation.LINE, 25, "", i % 3 == 0, 0.35))
	for i in kip_n:
		var p := Vector2(40.0 - float(i / 7) * 16.0, 44.0 + float(i % 7) * 23.0)
		_kip_sq.append(sim.add_squad(1, "sayisker", 60, p, PI / 2, BattleSim.Formation.LINE, 20, "", i % 3 == 0, 1.2))
	kok = _kok_sq[0]
	kip = _kip_sq[0]
	gen = -1
	# сигналы ядра — эффектам (дым залпов, вспышки, пыль натиска; срез подключает BattleFx)
	_ev_lock.lock()
	_ev.clear()
	_ev_lock.unlock()
	wire_sim(sim)
	started.emit(p_seed)


## Сигналы ядра → сигналы узла через _relay (фоновый шаг — в очередь, главный поток — сразу)
func wire_sim(s: BattleSim) -> void:
	for name in RELAYED:
		s.connect(name, _relay.bind(name))


func step() -> void:
	_stepping = true
	super.step()
	_stepping = false


## SimStepper зовёт это на главном потоке, когда фоновый шаг принят и следующий ещё не начат
func restarts_next() -> bool:
	_flush_events()
	return super.restarts_next()


func _relay(...args: Array) -> void:
	var name: StringName = args.pop_back()
	if OS.get_thread_caller_id() != _main_tid:
		_ev_lock.lock()
		var first := _ev.is_empty()
		_ev.append([name, args])
		_ev_lock.unlock()
		if first:
			_flush_events.call_deferred()
		return
	_flush_events()     # сначала то, что накопил фоновый шаг
	_emit(name, args)


## Накопленные сигналы — на главном потоке, пока фоновый шаг не идёт
func _flush_events() -> void:
	if OS.get_thread_caller_id() != _main_tid or _stepping:
		return
	_ev_lock.lock()
	var q := _ev
	_ev = []
	_ev_lock.unlock()
	for item in q:
		_emit(item[0], item[1])


func _emit(name: StringName, args: Array) -> void:
	match name:
		&"rout":
			_on_rout(args[0], args[1])
		&"battle_over":
			_on_over(args[0])
		_:
			callv("emit_signal", [name] + args)


func _ai() -> void:
	var t := sim.time
	if _ordered or t < 1.5:
		return
	_ordered = true
	for s in _kip_sq:
		sim.order_attack(s, _nearest(s, _kok_sq), BattleSim.Gait.RUN)
		sim.allow_charge(s, true)
	for s in _kok_sq:
		sim.set_fire(s, _nearest(s, _kip_sq), 64.0)


func _nearest(s: int, list: Array[int]) -> int:
	var c := sim.squad_centroid(s)
	var best := list[0]
	var bd := INF
	for o in list:
		var d := c.distance_squared_to(sim.squad_centroid(o))
		if d < bd:
			bd = d
			best = o
	return best
