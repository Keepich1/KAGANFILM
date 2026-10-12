class_name BattleFx
extends Node3D
## Рисованные эффекты боя (ТЗ 11.1): пороховой дым, вспышки выстрелов со вспышкой света,
## пыль из-под конницы и удара натиска, искры в рукопашной, пух ковыля и пепел в воздухе.
##
## Всё на GPUParticles3D; дым и пыль — рисованные клубы (shaders/fx/fx_puff.gdshader),
## освещены солнцем сцены (первый DirectionalLight3D): тёплая сторона к солнцу, бирюзовая тень,
## против солнца светятся края. Сносятся ветром ordo_wind, долго висят и тают с края.
## События приходят от сценария (ScenarioClash): shot, volley, impact, charge_hit, melee_hit,
## death, war_cry; пыль за скачущими конями — каждый кадр по скорости из симуляции.
## Скорость эффектов следует скорости боя (+/−, пауза). Качество low — вдвое меньше частиц.

const ATLAS_SMOKE := preload("res://assets/textures/fx/smoke_billow.png")
const ATLAS_DUST := preload("res://assets/textures/fx/dust_puff.png")
const ATLAS_FLASH := preload("res://assets/textures/fx/muzzle_flash.png")
const ATLAS_FLUFF := preload("res://assets/textures/fx/fluff.png")
const ATLAS_ASH := preload("res://assets/textures/fx/ash.png")
const SH_PUFF := preload("res://shaders/fx/fx_puff.gdshader")
const SH_DRIFT := preload("res://shaders/fx/fx_drift.gdshader")
const SH_FLASH := preload("res://shaders/fx/fx_flash.gdshader")
const SH_STILL := preload("res://shaders/fx/fx_still.gdshader")
const SH_SPARK := preload("res://shaders/fx/fx_spark.gdshader")
const SH_SPARK_MOVE := preload("res://shaders/fx/fx_spark_move.gdshader")
const SH_MOTE := preload("res://shaders/fx/fx_mote.gdshader")
const SH_MOTE_MOVE := preload("res://shaders/fx/fx_mote_move.gdshader")
const SH_RAY := preload("res://shaders/fx/fx_ray.gdshader")

const FLAGS := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY \
	| GPUParticles3D.EMIT_FLAG_COLOR | GPUParticles3D.EMIT_FLAG_CUSTOM

@export var scenario_path: NodePath = ^"../Scenario"
## Солнце (пусто — первый DirectionalLight3D в сцене)
@export var sun_path: NodePath
## Пух ковыля и пепел вокруг камеры
@export var ambient_motes := true
## Пыль за скачущими конями: клубов в секунду на каждый м/с сверх рыси
@export var dust_rate := 0.4
@export var fx_seed := 5

var scenario: ScenarioClash
var smoke: GPUParticles3D
var dust: GPUParticles3D
var flash: GPUParticles3D
var sparks: GPUParticles3D
var fluff: GPUParticles3D
var ash: GPUParticles3D
var rays: GPUParticles3D

var _sun: DirectionalLight3D
var _rng: BattleRng
var _lights: Array[OmniLight3D] = []
var _light_t := PackedFloat32Array()
var _light_i := 0
var _last_pop := -1.0
var _dust_acc := PackedFloat32Array()
var _spark_budget := 0
var _low := false
var _clock := 0.0           # своё время эффектов (идёт со скоростью боя)
var _puff_mats: Array[ShaderMaterial] = []
var _mote_mats: Array[ShaderMaterial] = []
var _ray_mat: ShaderMaterial


func _ready() -> void:
	_rng = BattleRng.new(fx_seed)
	var ordo := get_node_or_null("/root/Ordo")
	_low = ordo != null and ordo.has_method("is_low") and ordo.is_low()
	var k := 0.5 if _low else 1.0
	smoke = _make_puffs("Smoke", int(1100 * k), 11.0, ATLAS_SMOKE, Vector2(4, 4), {
		"drag": 2.1, "buoyancy": 0.2, "wind_scale": 0.55, "grow": 3.4, "spin": 0.1},
		{"col_lit": Color(0.86, 0.76, 0.62), "col_mid": Color(0.5, 0.46, 0.47), "col_shade": Color(0.2, 0.31, 0.38),
		"col_glow": Color(1.0, 0.8, 0.5), "erode_start": 0.08, "erode_end": 0.7, "opacity": 0.97, "stretch": 1.45,
		"age_thin": 0.35, "glow_strength": 0.85})
	dust = _make_puffs("Dust", int(1600 * k), 4.5, ATLAS_DUST, Vector2(4, 2), {
		"drag": 2.0, "buoyancy": 0.3, "wind_scale": 0.7, "grow": 3.2, "spin": 0.05, "grow_curve": 3.0},
		{"col_lit": Color(0.84, 0.7, 0.5), "col_mid": Color(0.6, 0.5, 0.38), "col_shade": Color(0.36, 0.32, 0.3),
		"col_glow": Color(1.0, 0.8, 0.5), "glow_strength": 0.6, "erode_start": 0.1, "erode_end": 0.5,
		"opacity": 0.62, "stretch": 1.5, "lit_edge": 0.3, "shade_edge": -0.2, "edge": 0.05, "soft_dist": 1.6,
		"age_thin": 0.85, "col_haze": Color(0.56, 0.5, 0.42), "near_fade": 9.0})
	flash = _make_system("Flash", 160, 0.11, SH_STILL, {}, _material(SH_FLASH, {"atlas": ATLAS_FLASH}))
	_ray_mat = _material(SH_RAY, {})
	rays = _make_system("Rays", 64, 9.0, SH_STILL, {}, _ray_mat)
	sparks = _make_system("Sparks", 320, 0.5, SH_SPARK_MOVE, {}, _material(SH_SPARK, {}))
	if ambient_motes:
		# пылинки видны только вблизи: с высокой камеры они читались бы как сор по всему кадру
		var fm := _material(SH_MOTE, {"atlas": ATLAS_FLUFF, "glow": 2.4, "fade_dist": 38.0})
		fluff = _make_system("Fluff", int(320 * k), 14.0, SH_MOTE_MOVE, {
			"box": Vector3(44, 7, 44), "size_min": 0.07, "size_max": 0.15, "wind_scale": 1.8}, fm, true)
		_mote_mats.append(fm)
		var am := _material(SH_MOTE, {"atlas": ATLAS_ASH, "glow": 0.5, "fade_dist": 26.0,
			"tint_lit": Color(0.9, 0.8, 0.7), "tint_shade": Color(0.5, 0.5, 0.55)})
		ash = _make_system("Ash", int(120 * k), 12.0, SH_MOTE_MOVE, {
			"box": Vector3(50, 8, 50), "size_min": 0.03, "size_max": 0.07, "wind_scale": 1.2, "rise": 0.25}, am, true)
		_mote_mats.append(am)
	for i in 6:
		var l := OmniLight3D.new()
		l.name = "MuzzleLight%d" % i
		l.light_color = Color(1.0, 0.68, 0.32)
		l.omni_range = 9.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)
		_light_t.append(-1.0)
	scenario = get_node_or_null(scenario_path) as ScenarioClash
	if scenario:
		scenario.started.connect(_on_started)
		scenario.shot.connect(_on_shot)
		scenario.volley.connect(_on_volley)
		scenario.impact.connect(_on_impact)
		scenario.charge_hit.connect(_on_charge_hit)
		scenario.melee_hit.connect(_on_melee_hit)
		scenario.death.connect(_on_death)
		scenario.war_cry.connect(_on_war_cry)
	_find_sun()


func _find_sun() -> void:
	_sun = get_node_or_null(sun_path) as DirectionalLight3D if sun_path != NodePath() else null
	if _sun == null and get_tree().current_scene:
		var lights := get_tree().current_scene.find_children("*", "DirectionalLight3D", true, false)
		if not lights.is_empty():
			_sun = lights[0] as DirectionalLight3D


# ================================================================= системы

func _material(shader: Shader, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	for key in params:
		m.set_shader_parameter(key, params[key])
	return m


func _make_system(nm: String, amount: int, lifetime: float, process: Shader, pparams: Dictionary,
		draw: ShaderMaterial, continuous := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = nm
	p.amount = maxi(amount, 8)
	p.lifetime = lifetime
	p.local_coords = false
	p.process_material = _material(process, pparams)
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = draw
	p.draw_pass_1 = q
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.visibility_aabb = AABB(Vector3(-700, -60, -700), Vector3(1400, 260, 1400))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	p.fixed_fps = 0
	p.interpolate = false
	p.emitting = continuous
	if continuous:
		p.preprocess = lifetime
	add_child(p)
	return p


func _make_puffs(nm: String, amount: int, lifetime: float, atlas: Texture2D, grid: Vector2,
		pparams: Dictionary, dparams: Dictionary) -> GPUParticles3D:
	var d := dparams.duplicate()
	d["atlas"] = atlas
	d["grid"] = grid
	var m := _material(SH_PUFF, d)
	_puff_mats.append(m)
	return _make_system(nm, amount, lifetime, SH_DRIFT, pparams, m)


## Клуб дыма/пыли: позиция, скорость, размер при рождении, доля жизни (0..1), оттенок.
## Поворот спрайта небольшой: клубы ложатся полосой по горизонту, как мазки
func puff(sys: GPUParticles3D, pos: Vector3, vel: Vector3, size: float, life: float, tint := Color(1, 1, 1, 1)) -> void:
	sys.emit_particle(Transform3D(Basis.from_scale(Vector3.ONE * size), pos), vel, tint,
		Color(_rng.range_f(-0.4, 0.4), 0.0, size, clampf(life, 0.05, 1.0)), FLAGS)


# ================================================================= события боя

func _on_started(_s: int) -> void:
	for p in [smoke, dust, flash, sparks, rays]:
		p.restart()
		p.emitting = false
	_dust_acc.resize(0)


func _on_shot(_u: int, muzzle: Vector3, dir: Vector3, _hit: bool) -> void:
	var d := dir.normalized()
	# вспышка вдоль ствола
	var x := d * _rng.range_f(0.9, 1.25)
	var b := Basis(x, Vector3.UP, x.cross(Vector3.UP).normalized())
	flash.emit_particle(Transform3D(b, muzzle + d * 0.05), Vector3.ZERO, Color.WHITE,
		Color(0, 0, 1, _rng.range_f(0.7, 1.0)), FLAGS)
	# дым: крупный клуб у дула и тугая струя вперёд; иногда ленивый клуб над стрелком
	var side := Vector3(d.z, 0.0, -d.x)
	puff(smoke, muzzle + d * 0.5, d * _rng.range_f(5.5, 8.0) + Vector3(0, 0.35, 0), _rng.range_f(1.0, 1.45), _rng.range_f(0.8, 1.0))
	puff(smoke, muzzle + d * 1.4 + side * _rng.range_f(-0.4, 0.4), d * _rng.range_f(13.0, 18.0) + Vector3(0, 0.5, 0),
		_rng.range_f(0.55, 0.8), _rng.range_f(0.55, 0.85))
	if _rng.chance(0.3):
		puff(smoke, muzzle + Vector3(0, 0.3, 0) - d * 0.2, d * 1.0 + Vector3(0, 0.6, 0), _rng.range_f(0.6, 0.85),
			_rng.range_f(0.7, 1.0), Color(0.92, 0.92, 0.95, 0.9))
	# тлеющий пыж и угольки
	for i in _rng.range_i(3):
		var v := d * _rng.range_f(4.0, 9.0) + Vector3(_rng.range_f(-1, 1), _rng.range_f(0.5, 2.5), _rng.range_f(-1, 1))
		sparks.emit_particle(Transform3D(Basis(), muzzle + d * 0.3), v, Color.WHITE, Color(0, 0, 1, _rng.range_f(0.5, 1.0)), FLAGS)
	_pop_light(muzzle + d * 0.4)


## Лучи сквозь дым залпа: ленты по солнечному лучу вдоль дымовой стены перед шеренгой
func _on_volley(s: int, _rank: int, center: Vector3, count: int) -> void:
	var sim := scenario.sim
	var f := sim.squad_forward(s)
	var fw := Vector3(f.x, 0.0, f.y)
	var side := Vector3(-f.y, 0.0, f.x)
	var half := sim.sq_files[s] * 0.5
	for i in clampi(count / 5, 3, 12):
		var p := center + fw * _rng.range_f(5.0, 14.0) + side * _rng.range_f(-half, half)
		p.y += _rng.range_f(1.5, 3.5)
		var b := Basis.from_scale(Vector3(_rng.range_f(26.0, 40.0), _rng.range_f(2.0, 4.5), 1.0))
		rays.emit_particle(Transform3D(b, p), Vector3.ZERO, Color.WHITE,
			Color(_rng.range_f(0.0, 10.0), 0.0, 1.0, _rng.range_f(0.6, 1.0)), FLAGS)


func _pop_light(pos: Vector3) -> void:
	var t := _clock
	# соседние выстрелы делят одну вспышку света
	if t - _last_pop < 0.05:
		return
	_last_pop = t
	var l := _lights[_light_i]
	_light_t[_light_i] = t
	_light_i = (_light_i + 1) % _lights.size()
	l.global_position = pos + Vector3(0, 0.3, 0)
	l.visible = true
	l.light_energy = 3.2


func _on_impact(_s: int, pos: Vector3, _strength: float) -> void:
	# удар натиска: тяжёлая пыль низом во все стороны
	for i in 26:
		var a := _rng.range_f(-PI, PI)
		var r := _rng.range_f(0.5, 5.0)
		var p := pos + Vector3(cos(a) * r, 0.5, sin(a) * r * 1.6)
		var v := Vector3(cos(a), 0.0, sin(a)) * _rng.range_f(2.0, 6.0) + Vector3(0, _rng.range_f(0.6, 2.0), 0)
		puff(dust, p, v, _rng.range_f(1.0, 1.8), _rng.range_f(0.8, 1.0), Color(0.82, 0.72, 0.6, 1.0))


func _on_charge_hit(_u: int, _t: int, pos: Vector3) -> void:
	for i in 3:
		var p := pos + Vector3(_rng.range_f(-1.0, 1.0), 0.4, _rng.range_f(-1.0, 1.0))
		puff(dust, p, Vector3(_rng.range_f(-2, 2), _rng.range_f(0.8, 2.2), _rng.range_f(-2, 2)),
			_rng.range_f(0.8, 1.3), _rng.range_f(0.6, 0.9))


func _on_melee_hit(_a: int, _t: int, pos: Vector3) -> void:
	if _spark_budget <= 0 or not _rng.chance(0.55):
		return
	var n := 2 + _rng.range_i(4)
	_spark_budget -= n
	for i in n:
		var v := Vector3(_rng.range_f(-3.5, 3.5), _rng.range_f(0.5, 4.0), _rng.range_f(-3.5, 3.5))
		sparks.emit_particle(Transform3D(Basis(), pos + Vector3(0, _rng.range_f(-0.2, 0.3), 0)), v, Color.WHITE,
			Color(0, 0, 1, _rng.range_f(0.4, 1.0)), FLAGS)


func _on_death(u: int, pos: Vector3) -> void:
	var sim := scenario.sim
	if sim.is_mounted(u):
		# конь валится на бок: пыль низом
		var v := Vector3(sim.u_vx[u], 0.0, sim.u_vz[u]) * 0.4
		for i in 5:
			puff(dust, pos + Vector3(_rng.range_f(-1.4, 1.4), 0.35, _rng.range_f(-1.4, 1.4)),
				v + Vector3(_rng.range_f(-1.5, 1.5), _rng.range_f(0.4, 1.2), _rng.range_f(-1.5, 1.5)),
				_rng.range_f(0.8, 1.3), _rng.range_f(0.6, 0.9))
	else:
		puff(dust, pos + Vector3(0, 0.3, 0), Vector3(_rng.range_f(-1, 1), 0.6, _rng.range_f(-1, 1)), 0.6, 0.5)


func _on_war_cry(_u: int, pos: Vector3) -> void:
	# конь полководца встаёт на дыбы — пыль из-под копыт
	for i in 5:
		var a := float(i) / 5.0 * TAU + _rng.range_f(-0.3, 0.3)
		puff(dust, pos + Vector3(cos(a) * 1.0, 0.2, sin(a) * 1.0), Vector3(cos(a), 0.25, sin(a)) * 1.4,
			_rng.range_f(0.45, 0.65), _rng.range_f(0.4, 0.6), Color(1, 1, 1, 0.75))


# ================================================================= каждый кадр

func _process(delta: float) -> void:
	_spark_budget = 40
	var scale := 1.0
	if scenario:
		scale = 0.0 if scenario.paused else scenario.time_scale
	for p in [smoke, dust, flash, sparks, fluff, ash, rays]:
		if p:
			p.speed_scale = scale
	_update_sun()
	_update_lights(delta * scale)
	_follow_camera()
	if scenario and scenario.sim and scale > 0.0:
		_gallop_dust(delta * scale)


func _update_sun() -> void:
	if _sun == null or not is_instance_valid(_sun):
		_find_sun()
		if _sun == null:
			return
	var d := _sun.global_basis.z.normalized()
	var c := Vector3(_sun.light_color.r, _sun.light_color.g, _sun.light_color.b)
	var e := clampf(_sun.light_energy / 2.0, 0.4, 1.6)
	for m in _puff_mats:
		m.set_shader_parameter("sun_dir", d)
		m.set_shader_parameter("sun_color", c)
		m.set_shader_parameter("sun_energy", e)
	for m in _mote_mats:
		m.set_shader_parameter("sun_dir", d)
		m.set_shader_parameter("sun_color", c)
	_ray_mat.set_shader_parameter("sun_dir", d)
	_ray_mat.set_shader_parameter("sun_color", c)


func _update_lights(dt: float) -> void:
	_clock += dt
	var t := _clock
	for i in _lights.size():
		var l := _lights[i]
		if not l.visible:
			continue
		var age := t - _light_t[i]
		if age > 0.16 or age < 0.0:
			l.visible = false
			l.light_energy = 0.0
		else:
			l.light_energy = 3.2 * exp(-age * 22.0)


func _follow_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	var f := -cam.global_basis.z
	# коробка пылинок — немного впереди камеры, у земли
	var c := p + Vector3(f.x, 0.0, f.z).normalized() * 16.0
	c.y = Terrain.height_at(c.x, c.z)
	if fluff:
		fluff.global_position = c
	if ash:
		ash.global_position = c


func _gallop_dust(dt: float) -> void:
	var sim := scenario.sim
	if _dust_acc.size() != sim.n:
		_dust_acc.resize(sim.n)
		_dust_acc.fill(0.0)
	for u in sim.n:
		if sim.u_life[u] != BattleSim.Life.ALIVE or not sim.is_mounted(u):
			continue
		var vx := sim.u_vx[u]
		var vz := sim.u_vz[u]
		var sp := sqrt(vx * vx + vz * vz)
		if sp < 4.0:
			continue
		_dust_acc[u] += (sp - 4.0) * dust_rate * dt * (0.5 if _low else 1.0)
		while _dust_acc[u] >= 1.0:
			_dust_acc[u] -= 1.0
			var f := Vector3(vx, 0.0, vz) / sp
			var side := Vector3(f.z, 0.0, -f.x)
			var x := sim.u_x[u]
			var z := sim.u_z[u]
			var p := Vector3(x, 0.0, z) - f * _rng.range_f(0.6, 1.4) + side * _rng.range_f(-0.45, 0.45)
			p.y = Terrain.height_at(p.x, p.z) + 0.35
			var v := -f * _rng.range_f(0.8, 2.2) + side * _rng.range_f(-0.8, 0.8) + Vector3(0, _rng.range_f(0.3, 0.9), 0)
			puff(dust, p, v, _rng.range_f(0.9, 1.4), _rng.range_f(0.55, 0.9))
