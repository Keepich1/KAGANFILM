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
@export_enum("auto", "establish", "war_cry", "charge", "volley", "lances", "impact", "general", "melee", "rout", "aftermath")
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
	var p: Vector3 = _clear_of_units(plan[0], 4.0)
	var l: Vector3 = plan[1]
	var f: float = plan[2]
	if cut:
		_pos = p
		_look = l
		_fov = f
	else:
		# слежение во времени боя: при ускорении (+) камера не отстаёт от отрядов
		var k := 1.0 - exp(-delta * maxf(scenario.time_scale, 1.0) * follow)
		_pos = _pos.lerp(p, k)
		_look = _look.lerp(l, k)
		_fov = lerpf(_fov, f, k)
	var pos := _clear_of_units(_pos, 2.5)
	pos.y = maxf(pos.y, Terrain.height_at(pos.x, pos.z) + 1.0)
	# тряска: затухающий шум
	_trauma = maxf(0.0, _trauma - delta * 1.4)
	_shake_seed += delta * 23.0
	var sh := _trauma * _trauma * shake_scale
	var jitter := Vector3(sin(_shake_seed * 1.3), sin(_shake_seed * 1.7 + 2.0), sin(_shake_seed * 1.1 + 4.0)) * 0.12 * sh
	global_position = pos + jitter
	look_at(_look + jitter * 0.5, Vector3.UP)
	fov = _fov


## Камера не входит в бойцов: отодвигается от живых юнитов ближе radius м и чуть поднимается
func _clear_of_units(p: Vector3, radius: float) -> Vector3:
	var sim := scenario.sim
	var push := Vector3.ZERO
	var r2 := radius * radius
	for u in sim.n:
		if sim.u_life[u] != BattleSim.Life.ALIVE:
			continue
		var dx := p.x - sim.u_x[u]
		var dz := p.z - sim.u_z[u]
		var d2 := dx * dx + dz * dz
		if d2 < r2:
			var d := sqrt(d2) + 0.001
			push += Vector3(dx / d, 0.0, dz / d) * (radius - d)
	if push == Vector3.ZERO:
		return p
	return p + push + Vector3(0.0, push.length() * 0.6, 0.0)


## Режиссёр: какой план сейчас
func _direct(t: float) -> String:
	var sim := scenario.sim
	if _rout_t >= 0.0:
		if t - _rout_t < 1.2:
			return "melee"
		if t - _rout_t < 6.5:
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
			# с юга, высоко: обе армии в кадре — орда кыпчаков слева, кокандская линия справа,
			# луг между ними; солнце слева сбоку, медленный наезд с опусканием
			var p := Vector3(70.0 + st * 0.6, 17.0 - st * 1.2, 74.0 - st * 2.4)
			return [p, Vector3(68.0, 1.0, 6.0), 50.0]
		"war_cry":
			var g := sim.general[1]
			var gp := Vector3(sim.u_x[g], 0.0, sim.u_z[g])
			# полководец смотрит на врага: камера перед ним, чуть сбоку
			var gf := Vector3(oc.x - gp.x, 0.0, oc.y - gp.z).normalized()
			var gr := Vector3(gf.z, 0.0, -gf.x)
			# спереди-сбоку (с юго-востока), чуть снизу; наезд — сужение угла
			var p := gp + gf * 9.0 - gr * 4.5 + Vector3(0.0, 1.6, 0.0)
			var fv := lerpf(40.0, 22.0, smoothstep(0.0, 2.8, st))
			return [p, gp + Vector3(0.0, 2.35, 0.0), fv]
		"charge":
			# низко у правого (южного) края первой шеренги, взгляд наискось вдоль строя
			var side := Vector3(-kf.y, 0.0, kf.x)
			var fwd := Vector3(kf.x, 0.0, kf.y)
			var half := sim.sq_files[kip] * 2.1 * 0.5
			var front := Vector3(ka.x, 0.0, ka.y)
			# сбоку, чуть позади первой шеренги: пыль из-под копыт тянется за строем, солнце сзади
			var p := front - fwd * 3.0 + side * (half + 10.0) + Vector3(0.0, 1.5, 0.0)
			return [p, front + side * (half * 0.2) + fwd * 1.0 + Vector3(0.0, 1.9, 0.0), 46.0]
		"volley":
			# из-за спин стрелков, над плечами, против солнца
			var back := Vector3(-of.x, 0.0, -of.y)
			var right := Vector3(of.y, 0.0, -of.x)
			var a := Vector3(oa.x, 0.0, oa.y)
			var p := a + back * 6.5 + right * 9.0 + Vector3(0.0, 2.6, 0.0)
			return [p, a + Vector3(of.x, 0.0, of.y) * 45.0 + right * 2.0 + Vector3(0.0, 1.4, 0.0), 50.0]
		"lances":
			# у южного края строя, впереди: всадники проносятся мимо с копьями наперевес;
			# камера не заходит в дым у кокандской линии
			var fwd := Vector3(kf.x, 0.0, kf.y)
			var side := Vector3(-kf.y, 0.0, kf.x)
			var half := sim.sq_files[kip] * 2.1 * 0.5
			var front := Vector3(ka.x, 0.0, ka.y)
			var p := front + fwd * 7.0 + side * (half + 5.0) + Vector3(0.0, 1.4, 0.0)
			var lim := oa.x - 24.0
			if p.x > lim:
				p.x = lim
			return [p, front + side * (half * 0.35) + Vector3(0.0, 1.8, 0.0), 42.0]
		"impact":
			# у южного фланга кокандской линии, вдоль строя
			var a := Vector3(oa.x, 0.0, oa.y)
			var p := a + Vector3(-7.0, 2.6, 35.0) + Vector3(st * 0.4, st * 0.25, 0.0)
			return [p, a + Vector3(-3.0, 1.3, -2.0), 44.0]
		"general":
			# из-за плеча полководца: он на первом плане слева, за ним длинным объективом — удар
			# конницы о кокандскую линию во всю ширину кадра; солнце за спиной камеры
			var g := sim.general[1]
			var gp := Vector3(sim.u_x[g], 0.0, sim.u_z[g])
			var mid := Vector3((kc.x + oc.x) * 0.5, 0.0, (kc.y + oc.y) * 0.5)
			var d := Vector3(mid.x - gp.x, 0.0, mid.z - gp.z).normalized()
			var sd := Vector3(-d.z, 0.0, d.x)
			var p := gp - d * (7.5 + st * 0.2) + sd * 2.2 + Vector3(0.0, 2.1, 0.0)
			return [p, mid + Vector3(0.0, 1.2, 0.0), 30.0]
		"melee":
			var mid := Vector3((kc.x + oc.x) * 0.5, 0.0, (kc.y + oc.y) * 0.5)
			var p := mid + Vector3(8.0 + st * 0.3, 3.2 + st * 0.25, 24.0)
			return [p, mid + Vector3(0.0, 1.4, 0.0), 46.0]
		"rout":
			# впереди бегущих (с востока), против солнца: бегут на камеру, за ними — погоня в пыли
			var c := Vector3(oc.x, 0.0, oc.y)
			var p := c + Vector3(24.0 + st * 1.5, 3.2, 13.0)
			return [p, c + Vector3(-10.0, 1.6, -2.0), 44.0]
		"aftermath":
			# с востока против солнца: тела на переднем плане, остатки дыма светятся,
			# конница собирается вокруг полководца; медленный подъём
			var k := smoothstep(0.0, 14.0, st)
			# начинается выше и южнее пути погони (конница ещё возвращается) и опускается
			var p := Vector3(131.0, 8.5, 33.0).lerp(Vector3(127.0, 6.0, 23.0), k)
			return [p, Vector3(88.0, 2.0, 4.0), 46.0]
	return [Vector3(60.0, 30.0, 80.0), Vector3(70.0, 0.0, 0.0), 45.0]
