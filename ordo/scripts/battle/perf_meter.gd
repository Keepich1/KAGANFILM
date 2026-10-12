class_name PerfMeter
extends RefCounted
## Счётчики времени для экрана проверки скорости (F9 в срезе): среднее и худшее за последнюю секунду.
##
##   PerfMeter.add_frame("view", ms)    # за кадр складывается (два вида боя — одна строка)
##   PerfMeter.add_sample("sim", ms)    # каждое значение отдельно (шаг симуляции)
##   PerfMeter.avg("sim"), PerfMeter.peak("sim")   # мс за прошлую полную секунду
## Только главный поток (фоновый шаг боя отдаёт своё время через SimStepper).

const WINDOW_MS := 1000

## имя → [кадр, сумма кадра, сумма окна, худшее окна, число окна, среднее, худшее, по кадрам?]
static var _m := {}
static var _window_start := 0


static func add_frame(name: StringName, ms: float) -> void:
	var e := _entry(name, true)
	var f := Engine.get_process_frames()
	if int(e[0]) != f:
		_close_frame(e)
		e[0] = f
	e[1] = float(e[1]) + ms


static func add_sample(name: StringName, ms: float) -> void:
	var e := _entry(name, false)
	e[2] = float(e[2]) + ms
	e[3] = maxf(float(e[3]), ms)
	e[4] = int(e[4]) + 1


## Среднее за прошлую секунду, мс
static func avg(name: StringName) -> float:
	_roll()
	var e: Array = _m.get(name, [])
	return float(e[5]) if not e.is_empty() else 0.0


## Худшее за прошлую секунду, мс
static func peak(name: StringName) -> float:
	_roll()
	var e: Array = _m.get(name, [])
	return float(e[6]) if not e.is_empty() else 0.0


static func has(name: StringName) -> bool:
	return _m.has(name)


static func _entry(name: StringName, per_frame: bool) -> Array:
	_roll()
	var e: Array = _m.get(name, [])
	if e.is_empty():
		e = [Engine.get_process_frames(), 0.0, 0.0, 0.0, 0, 0.0, 0.0, per_frame]
		_m[name] = e
	return e


static func _close_frame(e: Array) -> void:
	var v := float(e[1])
	e[1] = 0.0
	e[2] = float(e[2]) + v
	e[3] = maxf(float(e[3]), v)
	e[4] = int(e[4]) + 1


## Раз в секунду: окно → итог (среднее, худшее), новое окно
static func _roll() -> void:
	var now := Time.get_ticks_msec()
	if now - _window_start < WINDOW_MS:
		return
	_window_start = now
	var f := Engine.get_process_frames()
	for name in _m:
		var e: Array = _m[name]
		if bool(e[7]) and int(e[0]) != f:
			_close_frame(e)
			e[0] = f
		var c := int(e[4])
		e[5] = float(e[2]) / c if c > 0 else 0.0
		e[6] = float(e[3])
		e[2] = 0.0
		e[3] = 0.0
		e[4] = 0
