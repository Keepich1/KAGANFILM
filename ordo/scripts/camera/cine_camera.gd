class_name CineCamera
extends Camera3D
## Кинокамера боя: постановочные планы, привязанные к событиям сценария.
##
## shot = "auto" — режиссёр сам переключает планы по ходу боя:
##   establish  общий план: две армии на закатном лугу
##   war_cry    наезд на Колбашчы во время клича (ТЗ 11.4 [Свободно]: «кинематографичный зум»)
##   charge     низкий план сбоку вдоль разгоняющейся конницы
##   volley     из-за спин кокандской линии: залпы, дым, конница из дыма
##   lances     низкий план спереди: копья наперевес
##   impact     вдоль строя у фланга: удар натиска, пыль
##   melee      свалка с подъёмом камеры
##   rout       бегство и погоня
##   aftermath  после боя: тела, дым над полем, конница собирается, полководец ликует
## Любое другое значение — один план на всё время (так устроены CamCharge и CamVolley в сцене).
## Небольшая тряска на залпах и ударе.

signal shot_changed(name: String)

@export var scenario_path: NodePath = ^"../../Scenario"
@export_enum("auto", "establish", "war_cry", "charge", "volley", "lances", "impact", "melee", "rout", "aftermath")
var shot := "auto"
## Плавность слежения (больше — жёстче)
@export var follow := 3.5
@export var shake_scale := 1.0

var scenario: ScenarioClash
var current_shot := ""
var shot_time := 0.0

var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _fov := 45.0
var _trauma := 0.0
var _impact_t := -1.0
var _volleys: Array[float] = []
var _rout_t := -1.0
var _over_t := -1.0
var _cry_t := -1.0
var _shake_seed := 0.0


func _ready() -> void:
	scenario = get_node_or_null(scenario_path) as ScenarioClash
	if scenario:
		scenario.started.connect(_on_started)
		scenario.volley.connect(_on_volley)
		scenario.impact.connect(_on_impact)
		scenario.rout.connect(_on_rout)
		scenario.battle_over.connect(func(_w: int) -> void: _over_t = scenario.time)
		scenario.war_cry.connect(func(_u: int, _p: Vector3) -> void: _cry_t = scenario.time)
	_on_started(0)


func _on_started(_s: int) -> void:
	_impact_t = -1.0
	_volleys.clear()
	_rout_t = -1.0
	_over_t = -1.0
	_cry_t = -1.0
	current_shot = ""


func _on_volley(_s: int, _r: int, _c: Vector3, _n: int) -> void:
	_volleys.append(scenario.time)
	_trauma = minf(1.0, _trauma + 0.25)


func _on_impact(_s: int, _p: Vector3, _st: float) -> void:
	if _impact_t < 0.0:
		_impact_t = scenario.time
		_trauma = minf(1.0, _trauma + 0.7)


func _on_rout(s: int, _p: Vector3) -> void:
	if s == scenario.kok and _rout_t < 0.0:
		_rout_t = scenario.time


func _process(delta: float) -> void:
	if scenario == null or scenario.sim == null:
		return
	var t := scenario.time
	var want := shot if shot != "auto" else _direct(t)
	var cut := want != current_shot
	if cut:
		current_shot = want
		shot_time = 0.0
		shot_changed.emit(want)
	else:
		shot_time += delta * scenario.time_scale * (0.0 if scenario.paused else 1.0)
	var plan := _plan(current_shot, t, shot_time)
	var p: Vector3 = plan[0]
	var l: Vector3 = plan[1]
	var f: float = plan[2]
	if cut:
		_pos = p
		_look = l
		_fov = f
	else:
		var k := 1.0 - exp(-delta * follow)
		_pos = _pos.lerp(p, k)
		_look = _look.lerp(l, k)
		_fov = lerpf(_fov, f, k)
	var pos := _pos
	pos.y = maxf(pos.y, Terrain.height_at(pos.x, pos.z) + 1.0)
	# тряска: затухающий шум
	_trauma = maxf(0.0, _trauma - delta * 1.4)
	_shake_seed += delta * 23.0
	var sh := _trauma * _trauma * shake_scale
	var jitter := Vector3(sin(_shake_seed * 1.3), sin(_shake_seed * 1.7 + 2.0), sin(_shake_seed * 1.1 + 4.0)) * 0.12 * sh
	global_position = pos + jitter
	look_at(_look + jitter * 0.5, Vector3.UP)
	fov = _fov


## Режиссёр: какой план сейчас
func _direct(t: float) -> String:
	var sim := scenario.sim
	if _rout_t >= 0.0:
		if t - _rout_t < 1.5:
			return "melee"
		if t - _rout_t < 9.0:
			return "rout"
		return "aftermath"
	if _impact_t >= 0.0:
		return "impact" if t - _impact_t < 3.6 else "melee"
	if _volleys.size() >= 2 and t - _volleys[1] > 2.0:
		return "lances"
	if t < 2.6:
		return "establish"
	if t < 5.8:
		return "war_cry"
	var d := sim.front_distance(scenario.kok, scenario.kip)
	if d > 74.0 and _volleys.is_empty():
		return "charge"
	return "volley"


## План: [позиция, точка взгляда, угол обзора]
func _plan(name: String, t: float, st: float) -> Array:
	var sim := scenario.sim
	var kip := scenario.kip
	var kok := scenario.kok
	var kc := sim.squad_centroid(kip)
	var ka := sim.squad_anchor(kip)
	var kf := sim.squad_forward(kip)
	var oc := sim.squad_centroid(kok)
	var oa := sim.squad_anchor(kok)
	var of := sim.squad_forward(kok)
	match name:
		"establish":
			# высоко с юга, видно обе армии; медленный наезд
			var p := Vector3(58.0 + st * 1.2, 24.0 - st * 0.9, 96.0 - st * 2.0)
			return [p, Vector3(64.0 + st * 0.8, 0.0, 6.0), 48.0]
		"war_cry":
			var g := sim.general[1]
			var gp := Vector3(sim.u_x[g], 0.0, sim.u_z[g])
			var gf := Vector3(sin(sim.u_h[g]), 0.0, cos(sim.u_h[g]))
			var gr := Vector3(gf.z, 0.0, -gf.x)
			# спереди-сбоку (с юго-востока), чуть снизу; наезд — сужение угла
			var p := gp + gf * 9.0 - gr * 4.5 + Vector3(0.0, 1.6, 0.0)
			var fv := lerpf(40.0, 22.0, smoothstep(0.0, 2.8, st))
			return [p, gp + Vector3(0.0, 2.35, 0.0), fv]
		"charge":
			# низко сбоку (юг), чуть впереди первой шеренги
			var side := Vector3(-kf.y, 0.0, kf.x)
			var half := sim.sq_files[kip] * 2.1 * 0.5
			var front := Vector3(ka.x, 0.0, ka.y)
			var center := Vector3(kc.x, 0.0, kc.y)
			var p := center + Vector3(kf.x, 0.0, kf.y) * 12.0 + side * (half + 9.0) + Vector3(0.0, 1.8, 0.0)
			return [p, front + Vector3(kf.x, 0.0, kf.y) * 4.0 + Vector3(0.0, 1.9, 0.0), 48.0]
		"volley":
			# из-за спин стрелков, над плечами, против солнца
			var back := Vector3(-of.x, 0.0, -of.y)
			var right := Vector3(of.y, 0.0, -of.x)
			var a := Vector3(oa.x, 0.0, oa.y)
			var p := a + back * 6.5 + right * 9.0 + Vector3(0.0, 2.6, 0.0)
			return [p, a + Vector3(of.x, 0.0, of.y) * 45.0 + right * 2.0 + Vector3(0.0, 1.4, 0.0), 50.0]
		"lances":
			# спереди-сбоку, низко: всадники несутся на камеру
			var fwd := Vector3(kf.x, 0.0, kf.y)
			var side := Vector3(kf.y, 0.0, -kf.x)
			var front := Vector3(ka.x, 0.0, ka.y)
			var p := front + fwd * 16.0 + side * -14.0 + Vector3(0.0, 1.3, 0.0)
			return [p, front + Vector3(0.0, 1.6, 0.0) - side * 4.0, 44.0]
		"impact":
			# у южного фланга кокандской линии, вдоль строя
			var a := Vector3(oa.x, 0.0, oa.y)
			var p := a + Vector3(-5.0, 1.7, 33.0) + Vector3(st * 0.4, st * 0.25, 0.0)
			return [p, a + Vector3(-1.0, 1.2, -2.0), 46.0]
		"melee":
			var mid := Vector3((kc.x + oc.x) * 0.5, 0.0, (kc.y + oc.y) * 0.5)
			var p := mid + Vector3(10.0, 7.0 + st * 0.6, 34.0)
			return [p, mid + Vector3(0.0, 1.0, 0.0), 44.0]
		"rout":
			var c := Vector3(oc.x, 0.0, oc.y)
			var p := c + Vector3(-18.0, 9.0, 34.0)
			return [p, c + Vector3(-6.0, 1.0, 0.0), 46.0]
		"aftermath":
			# медленный подъём над полем: тела, дым, конница с полководцем
			var k := smoothstep(0.0, 14.0, st)
			var p := Vector3(112.0, 5.0, 34.0).lerp(Vector3(118.0, 16.0, 46.0), k)
			return [p, Vector3(92.0, 1.5, 4.0), 44.0]
	return [Vector3(60.0, 30.0, 80.0), Vector3(70.0, 0.0, 0.0), 45.0]
