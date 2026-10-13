class_name BattleFx
extends Node3D
## Рисованные эффекты боя (ТЗ 11.1): пороховой дым, вспышки выстрелов со вспышкой света,
## пыль из-под конницы и удара натиска, искры в рукопашной, пух ковыля и пепел в воздухе.
##
## Всё на GPUParticles3D; дым и пыль — рисованные клубы (shaders/fx/fx_puff.gdshader),
## освещены солнцем сцены (первый DirectionalLight3D): тёплая сторона к солнцу, бирюзовая тень,
## против солнца светятся края. Сносятся ветром ordo_wind, долго висят и тают с края.
## События приходят от сценария (SimDriver: ScenarioClash, GameDriver): shot, volley, impact, charge_hit, melee_hit,
## death, war_cry; пыль за скачущими конями — каждый кадр по скорости из симуляции.
## Скорость эффектов следует скорости боя (+/−, пауза). Частиц по уровню качества
## (WorldQuality.preset().fx): «Среднее» — ×0,75, «Низкое» — вдвое меньше. Время кадра — PerfMeter «fx»
## (каждый кадр и обработчики событий).
##
## Несколько боёв на одни эффекты: add_driver(сценарий, вид) — так срез подключает нагрузку F9
## (тысячи солдат). Общий запас частиц: у дыма, пыли и лучей — «ведро» клубов (сколько система
## может держать живыми: amount / средняя жизнь в секунду). Ближнее (ближе NEAR м от камеры)
## рисуется как раньше всегда; дальнее — пока в ведре есть запас, иначе крупнее и реже:
## дым залпа дальней шеренги — одной стеной крупных клубов вместо клубов от каждого ружья,
## пыль дальних коней — реже и крупнее. Вспышки, искры и свет дальних и невидимых выстрелов
## не рисуются (их не разглядеть). Пока бой маленький (срез), запаса хватает — вид прежний.

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

## Ближе этого (м от камеры) дым и пыль всегда как раньше, по клубу на ружьё и коня
const NEAR := 50.0
## Дальше этого залп при нехватке запаса дыма идёт одной стеной (запас на ближние залпы растёт с дальностью)
const MERGE_FROM := 50.0
## Вспышки выстрелов, свет и искры — только ближе и в кадре
const FLASH_DIST := 260.0
const LIGHT_DIST := 110.0
const SPARK_DIST := 70.0
## Пыль коней дальше этого не поднимается (с такой дали её не разглядеть)
const DUST_FAR := 300.0
## Сколько дыма успевает рассеяться у залпа, слитого в стену: окно, в которое выстрелы шеренги без своих клубов, с
const MERGE_WINDOW := 1.6

## Ведра: система → [запас клубов, вместимость, пополнение в секунду]
const BUCKET_SHARE := 0.92

@export var scenario_path: NodePath = ^"../Scenario"
## Вид боя (BattleView): у большого боя шаг считается в фоне — пыль коней читает его снимок
@export var view_path: NodePath = ^"../View"
## Солнце (пусто — первый DirectionalLight3D в сцене)
@export var sun_path: NodePath
## Пух ковыля и пепел вокруг камеры
@export var ambient_motes := true
## Пыль за скачущими конями: клубов в секунду на каждый м/с сверх рыси
@export var dust_rate := 0.6
@export var fx_seed := 5

var scenario: SimDriver
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
var _spark_budget := 0
var _fx_k := 1.0            # доля частиц по уровню качества
var _clock := 0.0           # своё время эффектов (идёт со скоростью боя)
var _puff_mats: Array[ShaderMaterial] = []
var _mote_mats: Array[ShaderMaterial] = []
var _ray_mat: ShaderMaterial
# бои: {driver, view, sim, mounted (PackedInt32Array), acc (пыль), merge_until (по отрядам), start}
var _drivers: Array[Dictionary] = []
# запас клубов: ключ — система
var _bucket := {}
# камера кадра
var _cam: Camera3D
var _cam_pos := Vector3(0.0, 1.0e6, 0.0)
## Счёт за прошлую секунду: клубов дыма и пыли пущено, залпов стеной (экран F9)
var stat := {"smoke": 0, "dust": 0, "merged": 0}
var _stat_acc := {"smoke": 0, "dust": 0, "merged": 0}
var _stat_t := 0.0


func _ready() -> void:
	_rng = BattleRng.new(fx_seed)
	var ordo := get_node_or_null("/root/Ordo")
	var q := String(ordo.get("quality")) if ordo != null and ordo.get("quality") != null else "high"
	_fx_k = float(WorldQuality.preset(q).get("fx", 1.0))
	var k := _fx_k
	smoke = _make_puffs("Smoke", int(1100 * k), 11.0, ATLAS_SMOKE, Vector2(4, 4), {
		"drag": 2.1, "buoyancy": 0.2, "wind_scale": 0.55, "grow": 3.4, "spin": 0.1},
		{"col_lit": Color(0.86, 0.76, 0.62), "col_mid": Color(0.5, 0.46, 0.47), "col_shade": Color(0.2, 0.31, 0.38),
		"col_glow": Color(1.0, 0.8, 0.5), "erode_start": 0.08, "erode_end": 0.7, "opacity": 0.78, "stretch": 1.45,
		"age_thin": 0.35, "glow_strength": 0.85})
	dust = _make_puffs("Dust", int(1600 * k), 4.5, ATLAS_DUST, Vector2(4, 2), {
		"drag": 2.0, "buoyancy": 0.3, "wind_scale": 0.7, "grow": 3.2, "spin": 0.05, "grow_curve": 3.0},
		{"col_lit": Color(0.84, 0.7, 0.5), "col_mid": Color(0.6, 0.5, 0.38), "col_shade": Color(0.36, 0.32, 0.3),
		"col_glow": Color(1.0, 0.8, 0.5), "glow_strength": 0.6, "erode_start": 0.1, "erode_end": 0.5,
		"opacity": 0.55, "stretch": 1.9, "lit_edge": 0.3, "shade_edge": -0.2, "edge": 0.05, "soft_dist": 1.6,
		"core_soft": 0.8,
		"age_thin": 0.85, "col_haze": Color(0.56, 0.5, 0.42), "near_fade": 14.0})
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
	# запас клубов: средняя жизнь клуба — около 0,8 общей (доля жизни w 0,45…1)
	_bucket = {smoke: _new_bucket(smoke, 0.8), dust: _new_bucket(dust, 0.75), rays: _new_bucket(rays, 0.8)}
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
	scenario = get_node_or_null(scenario_path) as SimDriver
	if scenario:
		scenario.started.connect(_on_started)
		add_driver(scenario, get_node_or_null(view_path) as BattleView)
	if ordo and ordo.has_signal("quality_changed"):
		ordo.connect("quality_changed", _on_quality)
	_find_sun()


## Смена качества (F2): число частиц по уровню и запас клубов (системы начинаются заново)
func _on_quality(level: String) -> void:
	_fx_k = float(WorldQuality.preset(level).get("fx", 1.0))
	smoke.amount = maxi(int(1100 * _fx_k), 8)
	dust.amount = maxi(int(1600 * _fx_k), 8)
	if fluff:
		fluff.amount = maxi(int(320 * _fx_k), 8)
	if ash:
		ash.amount = maxi(int(120 * _fx_k), 8)
	_bucket = {smoke: _new_bucket(smoke, 0.8), dust: _new_bucket(dust, 0.75), rays: _new_bucket(rays, 0.8)}


## Подключить ещё один бой к этим эффектам (нагрузка F9): сигналы сценария и пыль его коней.
## view — его BattleView (снимок шагов, если бой считается в фоне); бой уходит сам, когда узел удалён.
func add_driver(d: SimDriver, view: BattleView = null) -> void:
	if d == null:
		return
	for e in _drivers:
		if is_instance_valid(e.driver) and e.driver == d:
			return
	_drivers.append({"driver": d, "view": view, "sim": null, "mounted": PackedInt32Array(), "n": -1,
		"acc": PackedFloat32Array(), "merge_until": PackedFloat32Array(), "start": 0})
	d.shot.connect(_on_shot.bind(d))
	d.volley.connect(_on_volley.bind(d))
	d.impact.connect(_on_impact.bind(d))
	d.charge_hit.connect(_on_charge_hit.bind(d))
	d.melee_hit.connect(_on_melee_hit.bind(d))
	d.death.connect(_on_death.bind(d))
	d.war_cry.connect(_on_war_cry.bind(d))


func _new_bucket(p: GPUParticles3D, mean_life: float) -> Array:
	var rate := float(p.amount) / maxf(p.lifetime * mean_life, 0.05) * BUCKET_SHARE
	var cap := float(p.amount) * 0.5
	return [cap, cap, rate]


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
	var b: Array = _bucket.get(sys, [])
	if not b.is_empty():
		b[0] = float(b[0]) - 1.0
	if sys == smoke:
		_stat_acc.smoke += 1
	elif sys == dust:
		_stat_acc.dust += 1


## Сколько клубов система ещё может принять без вытеснения (запас ведра)
func room(sys: GPUParticles3D) -> float:
	var b: Array = _bucket.get(sys, [])
	return float(b[0]) if not b.is_empty() else 1.0e9


## Дальний клуб: только если в ведре есть запас (ближние идут всегда)
func _far_puff(sys: GPUParticles3D, pos: Vector3, vel: Vector3, size: float, life: float, tint := Color(1, 1, 1, 1)) -> bool:
	if room(sys) < 1.0:
		return false
	puff(sys, pos, vel, size, life, tint)
	return true


func _dist(p: Vector3) -> float:
	return _cam_pos.distance_to(p)


func _in_view(p: Vector3) -> bool:
	return _cam == null or _cam.is_position_in_frustum(p)


# ================================================================= события боя

func _on_started(_s: int) -> void:
	for p in [smoke, dust, flash, sparks, rays]:
		p.restart()
		p.emitting = false
	for e in _drivers:
		e.sim = null


func _on_shot(u: int, muzzle: Vector3, dir: Vector3, _hit: bool, drv: SimDriver = null) -> void:
	var t0 := Time.get_ticks_usec()
	var d := dir.normalized()
	var dist := _dist(muzzle)
	var seen := dist < FLASH_DIST and (dist < 12.0 or _in_view(muzzle))
	if seen:
		# вспышка вдоль ствола
		var x := d * _rng.range_f(0.9, 1.25)
		var b := Basis(x, Vector3.UP, x.cross(Vector3.UP).normalized())
		flash.emit_particle(Transform3D(b, muzzle + d * 0.05), Vector3.ZERO, Color.WHITE,
			Color(0, 0, 1, _rng.range_f(0.7, 1.0)), FLAGS)
	# дым: крупный клуб у дула и тугая струя вперёд; иногда ленивый клуб над стрелком.
	# Залп дальней шеренги при нехватке дыма уже лёг одной стеной (_on_volley) — своих клубов нет
	if not _merged(drv, u):
		var side := Vector3(d.z, 0.0, -d.x)
		puff(smoke, muzzle + d * 0.5, d * _rng.range_f(5.5, 8.0) + Vector3(0, 0.35, 0), _rng.range_f(1.0, 1.45), _rng.range_f(0.8, 1.0))
		puff(smoke, muzzle + d * 1.4 + side * _rng.range_f(-0.4, 0.4), d * _rng.range_f(13.0, 18.0) + Vector3(0, 0.5, 0),
			_rng.range_f(0.55, 0.8), _rng.range_f(0.55, 0.85))
		if _rng.chance(0.3):
			puff(smoke, muzzle + Vector3(0, 0.3, 0) - d * 0.2, d * 1.0 + Vector3(0, 0.6, 0), _rng.range_f(0.6, 0.85),
				_rng.range_f(0.7, 1.0), Color(0.92, 0.92, 0.95, 0.9))
	# тлеющий пыж и угольки
	if seen and dist < SPARK_DIST:
		for i in _rng.range_i(3):
			var v := d * _rng.range_f(4.0, 9.0) + Vector3(_rng.range_f(-1, 1), _rng.range_f(0.5, 2.5), _rng.range_f(-1, 1))
			sparks.emit_particle(Transform3D(Basis(), muzzle + d * 0.3), v, Color.WHITE, Color(0, 0, 1, _rng.range_f(0.5, 1.0)), FLAGS)
	if seen and dist < LIGHT_DIST:
		_pop_light(muzzle + d * 0.4)
	PerfMeter.add_frame(&"fx", (Time.get_ticks_usec() - t0) / 1000.0)


## Выстрел из шеренги, чей залп лёг стеной: у него своих клубов нет
func _merged(drv: SimDriver, u: int) -> bool:
	if drv == null or u < 0:
		return false
	var e := _entry(drv)
	if e.is_empty():
		return false
	var mu: PackedFloat32Array = e.merge_until
	var sim := drv.sim
	if sim == null or u >= sim.u_squad.size():
		return false
	var s := sim.u_squad[u]
	return s < mu.size() and mu[s] > _clock


func _entry(drv: SimDriver) -> Dictionary:
	for e in _drivers:
		if is_instance_valid(e.driver) and e.driver == drv:
			return e
	return {}


## Залп шеренги: дальний при нехватке дыма — одной стеной крупных клубов перед строем;
## лучи сквозь дым — ленты по солнечному лучу вдоль дымовой стены
func _on_volley(s: int, _rank: int, center: Vector3, count: int, drv: SimDriver = null) -> void:
	var t0 := Time.get_ticks_usec()
	var d := drv if drv else scenario
	var sim := d.sim if d else null
	if sim == null:
		return
	var f := sim.squad_forward(s)
	var fw := Vector3(f.x, 0.0, f.y)
	var side := Vector3(-f.y, 0.0, f.x)
	var half := sim.sq_files[s] * 0.5
	var dist := _dist(center)
	# по клубу на ружьё (2,3 клуба) — если запас дыма это позволяет; чем дальше залп, тем больше
	# запаса оставляем ближним
	var need := count * 2.3
	var keep := float(smoke.amount) * 0.5 * clampf((dist - MERGE_FROM) / 200.0, 0.0, 1.0) * 0.6
	if dist > MERGE_FROM and room(smoke) < need + keep:
		_merge_volley(d, s, center, count, fw, side, half)
	# лучи сквозь дым видны только против солнца: иначе 64 больших полотна рисуются впустую
	var cam := _cam
	if cam and _sun and (-cam.global_basis.z).dot(_sun.global_basis.z.normalized()) < 0.1:
		PerfMeter.add_frame(&"fx", (Time.get_ticks_usec() - t0) / 1000.0)
		return
	for i in clampi(count / 5, 3, 12):
		if dist > NEAR and room(rays) < 1.0:
			break
		var p := center + fw * _rng.range_f(5.0, 14.0) + side * _rng.range_f(-half, half)
		p.y += _rng.range_f(1.5, 3.5)
		var b := Basis.from_scale(Vector3(_rng.range_f(26.0, 40.0), _rng.range_f(2.0, 4.5), 1.0))
		rays.emit_particle(Transform3D(b, p), Vector3.ZERO, Color.WHITE,
			Color(_rng.range_f(0.0, 10.0), 0.0, 1.0, _rng.range_f(0.6, 1.0)), FLAGS)
		var rb: Array = _bucket[rays]
		rb[0] = float(rb[0]) - 1.0
	PerfMeter.add_frame(&"fx", (Time.get_ticks_usec() - t0) / 1000.0)


## Дымовая стена залпа: по крупному клубу на три ружья и струи вперёд — вместо клубов от каждого
func _merge_volley(d: SimDriver, s: int, center: Vector3, count: int, fw: Vector3, side: Vector3, half: float) -> void:
	var e := _entry(d)
	if not e.is_empty():
		var mu: PackedFloat32Array = e.merge_until
		if mu.size() <= s:
			var old := mu.size()
			mu.resize(s + 1)
			for i in range(old, s + 1):
				mu[i] = -1.0
		mu[s] = _clock + MERGE_WINDOW
		e.merge_until = mu
	_stat_acc.merged += 1
	# по клубу на три ружья; запаса совсем нет — меньше клубов, но крупнее (стена всё равно видна)
	var want := clampi(int(ceil(count / 3.0)), 3, 18)
	var n := clampi(int(room(smoke)), 3, want)
	var grow := minf(sqrt(float(want) / float(n)), 1.5)
	var y := center.y + 1.4
	for i in n:
		var k := (float(i) + _rng.range_f(0.2, 0.8)) / float(n)
		var p := center + side * lerpf(-half, half, k) + fw * _rng.range_f(0.6, 2.2)
		p.y = y + _rng.range_f(-0.1, 0.3)
		puff(smoke, p, fw * _rng.range_f(4.5, 7.5) + Vector3(0, 0.4, 0), _rng.range_f(1.8, 2.5) * grow, _rng.range_f(0.8, 1.0))
		if i % 2 == 0:
			var q := p + fw * _rng.range_f(1.5, 3.0)
			puff(smoke, q, fw * _rng.range_f(11.0, 15.0) + Vector3(0, 0.5, 0), _rng.range_f(1.0, 1.4), _rng.range_f(0.55, 0.85))


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


func _on_impact(_s: int, pos: Vector3, _strength: float, _drv: SimDriver = null) -> void:
	var t0 := Time.get_ticks_usec()
	# удар натиска: тяжёлая пыль низом во все стороны (дальний — меньше клубов, крупнее)
	var near := _dist(pos) <= NEAR
	var n := 26 if near else 12
	var grow := 1.0 if near else 1.45
	for i in n:
		var a := _rng.range_f(-PI, PI)
		var r := _rng.range_f(0.5, 5.0)
		var p := pos + Vector3(cos(a) * r, 0.5, sin(a) * r * 1.6)
		var v := Vector3(cos(a), 0.0, sin(a)) * _rng.range_f(2.0, 6.0) + Vector3(0, _rng.range_f(0.6, 2.0), 0)
		if near or i < 4:
			puff(dust, p, v, _rng.range_f(1.0, 1.8) * grow, _rng.range_f(0.8, 1.0), Color(0.82, 0.72, 0.6, 1.0))
		elif not _far_puff(dust, p, v, _rng.range_f(1.0, 1.8) * grow, _rng.range_f(0.8, 1.0), Color(0.82, 0.72, 0.6, 1.0)):
			break
	PerfMeter.add_frame(&"fx", (Time.get_ticks_usec() - t0) / 1000.0)


func _on_charge_hit(_u: int, _t: int, pos: Vector3, _drv: SimDriver = null) -> void:
	var t0 := Time.get_ticks_usec()
	if _dist(pos) <= NEAR:
		for i in 3:
			var p := pos + Vector3(_rng.range_f(-1.0, 1.0), 0.4, _rng.range_f(-1.0, 1.0))
			puff(dust, p, Vector3(_rng.range_f(-2, 2), _rng.range_f(0.8, 2.2), _rng.range_f(-2, 2)),
				_rng.range_f(0.8, 1.3), _rng.range_f(0.6, 0.9))
	else:
		# дальний удар: один клуб крупнее
		_far_puff(dust, pos + Vector3(_rng.range_f(-1.0, 1.0), 0.5, _rng.range_f(-1.0, 1.0)),
			Vector3(_rng.range_f(-2, 2), _rng.range_f(0.8, 2.2), _rng.range_f(-2, 2)), _rng.range_f(1.3, 1.9), _rng.range_f(0.6, 0.9))
	PerfMeter.add_frame(&"fx", (Time.get_ticks_usec() - t0) / 1000.0)


func _on_melee_hit(_a: int, _t: int, pos: Vector3, _drv: SimDriver = null) -> void:
	if _spark_budget <= 0 or not _rng.chance(0.55):
		return
	if _dist(pos) > SPARK_DIST or not _in_view(pos):
		return
	var n := 2 + _rng.range_i(4)
	_spark_budget -= n
	for i in n:
		var v := Vector3(_rng.range_f(-3.5, 3.5), _rng.range_f(0.5, 4.0), _rng.range_f(-3.5, 3.5))
		sparks.emit_particle(Transform3D(Basis(), pos + Vector3(0, _rng.range_f(-0.2, 0.3), 0)), v, Color.WHITE,
			Color(0, 0, 1, _rng.range_f(0.4, 1.0)), FLAGS)


func _on_death(u: int, pos: Vector3, drv: SimDriver = null) -> void:
	var d := drv if drv else scenario
	var sim := d.sim if d else null
	if sim == null:
		return
	var t0 := Time.get_ticks_usec()
	var near := _dist(pos) <= NEAR
	if sim.is_mounted(u):
		# конь валится на бок: пыль низом
		var v := Vector3(sim.u_vx[u], 0.0, sim.u_vz[u]) * 0.4
		for i in (5 if near else 2):
			var p := pos + Vector3(_rng.range_f(-1.4, 1.4), 0.35, _rng.range_f(-1.4, 1.4))
			var w := v + Vector3(_rng.range_f(-1.5, 1.5), _rng.range_f(0.4, 1.2), _rng.range_f(-1.5, 1.5))
			if near:
				puff(dust, p, w, _rng.range_f(0.8, 1.3), _rng.range_f(0.6, 0.9))
			elif not _far_puff(dust, p, w, _rng.range_f(1.1, 1.7), _rng.range_f(0.6, 0.9)):
				break
	elif near:
		puff(dust, pos + Vector3(0, 0.3, 0), Vector3(_rng.range_f(-1, 1), 0.6, _rng.range_f(-1, 1)), 0.6, 0.5)
	else:
		_far_puff(dust, pos + Vector3(0, 0.3, 0), Vector3(_rng.range_f(-1, 1), 0.6, _rng.range_f(-1, 1)), 0.7, 0.5)
	PerfMeter.add_frame(&"fx", (Time.get_ticks_usec() - t0) / 1000.0)


func _on_war_cry(_u: int, pos: Vector3, _drv: SimDriver = null) -> void:
	# конь полководца встаёт на дыбы — пыль из-под копыт
	for i in 5:
		var a := float(i) / 5.0 * TAU + _rng.range_f(-0.3, 0.3)
		puff(dust, pos + Vector3(cos(a) * 1.0, 0.2, sin(a) * 1.0), Vector3(cos(a), 0.25, sin(a)) * 1.4,
			_rng.range_f(0.45, 0.65), _rng.range_f(0.4, 0.6), Color(1, 1, 1, 0.75))


# ================================================================= каждый кадр

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_frame(delta)
	PerfMeter.add_frame(&"fx", (Time.get_ticks_usec() - t0) / 1000.0)


func _frame(delta: float) -> void:
	_spark_budget = 40
	var scale := 1.0
	if scenario:
		scale = 0.0 if scenario.paused else scenario.time_scale
	for p in [smoke, dust, flash, sparks, fluff, ash, rays]:
		if p:
			p.speed_scale = scale
	_cam = get_viewport().get_camera_3d()
	if _cam:
		_cam_pos = _cam.global_position
	_refill(delta * scale)
	_update_sun()
	_update_lights(delta * scale)
	_follow_camera()
	# бои, чьи узлы удалены (нагрузка F9 выключена), — из списка
	for i in range(_drivers.size() - 1, -1, -1):
		if not is_instance_valid(_drivers[i].driver):
			_drivers.remove_at(i)
	if scale > 0.0:
		for e in _drivers:
			_gallop_dust(e, delta * scale)
	_stat_t += delta
	if _stat_t >= 1.0:
		_stat_t = 0.0
		stat = _stat_acc.duplicate()
		for k in _stat_acc:
			_stat_acc[k] = 0


## Ведра пополняются со скоростью, с которой клубы рассеиваются
func _refill(dt: float) -> void:
	for sys in _bucket:
		var b: Array = _bucket[sys]
		b[0] = minf(float(b[0]) + float(b[2]) * dt, float(b[1]))


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
	var cam := _cam
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


## Пыль за скачущими конями одного боя. Большой бой (шаг в фоне) — по снимку SimStepper.
## Ближние кони пылят как раньше; дальние — реже и крупнее, пока есть запас пыли; обход
## каждый кадр начинается с другого коня, чтобы запаса хватало всем по очереди.
func _gallop_dust(e: Dictionary, dt: float) -> void:
	var drv: SimDriver = e.driver
	var sim := drv.sim
	if sim == null:
		return
	var view: BattleView = e.view if is_instance_valid(e.view) else null
	var st := view.stepper() if view else null
	var snap := st != null and st.uses_snapshot()
	var xs := st.s_x if snap else sim.u_x
	var zs := st.s_z if snap else sim.u_z
	var vxs := st.s_vx if snap else sim.u_vx
	var vzs := st.s_vz if snap else sim.u_vz
	var lifes := st.s_life if snap else sim.u_life
	var n := mini(xs.size(), lifes.size())
	if e.sim != sim or int(e.n) != n:
		# список конных: тип юнита после создания не меняется
		e.sim = sim
		e.n = n
		var m := PackedInt32Array()
		for u in n:
			if sim.is_mounted(u):
				m.append(u)
		e.mounted = m
		var acc := PackedFloat32Array()
		acc.resize(n)
		e.acc = acc
		e.merge_until = PackedFloat32Array()
	var mounted: PackedInt32Array = e.mounted
	var acc: PackedFloat32Array = e.acc
	var cnt := mounted.size()
	if cnt == 0:
		return
	var start: int = int(e.start) % cnt
	e.start = start + 7
	var rate := dust_rate * dt * _fx_k
	var cam := _cam_pos
	var b: Array = _bucket[dust]
	for k in cnt:
		var u := mounted[(start + k) % cnt]
		if u >= n or lifes[u] != BattleSim.Life.ALIVE:
			continue
		var vx := vxs[u]
		var vz := vzs[u]
		var sp2 := vx * vx + vz * vz
		if sp2 < 16.0:
			continue
		var x := xs[u]
		var z := zs[u]
		var dx := x - cam.x
		var dz := z - cam.z
		var d2 := dx * dx + dz * dz
		if d2 > DUST_FAR * DUST_FAR:
			continue
		var sp := sqrt(sp2)
		var near := d2 <= NEAR * NEAR
		# дальние: вдвое реже, клуб крупнее (та же пыльная полоса за отрядом)
		acc[u] += (sp - 4.0) * rate * (1.0 if near else 0.5)
		while acc[u] >= 1.0:
			acc[u] -= 1.0
			if not near and float(b[0]) < 1.0:
				acc[u] = 0.0
				break
			var f := Vector3(vx, 0.0, vz) / sp
			var side := Vector3(f.z, 0.0, -f.x)
			var p := Vector3(x, 0.0, z) - f * _rng.range_f(0.3, 2.4) + side * _rng.range_f(-0.9, 0.9)
			p.y = Terrain.height_at(p.x, p.z) + _rng.range_f(0.2, 0.5)
			var v := -f * _rng.range_f(0.8, 2.2) + side * _rng.range_f(-0.8, 0.8) + Vector3(0, _rng.range_f(0.3, 0.9), 0)
			puff(dust, p, v, _rng.range_f(0.7, 1.8) * (1.0 if near else 1.4), _rng.range_f(0.45, 0.95))
	e.acc = acc
