class_name Slice
extends Node3D
## Срез стиля «Ордо» (этап 0 ТЗ): мир + лагерь кыпчаков + столкновение (scenes/slice.tscn).
##
## Мир даёт землю, небо, солнце заката, туман, траву, деревья, реку и живописный фильтр;
## лагерь стоит на настоящей земле; бой берёт свет из мира, метки — из лагеря, толпу — CrowdLayer.
## Своих WorldEnvironment и солнца у среза нет.
##
## Клавиши (ТЗ 10): камера — WASD, края экрана, колесо, Q/E, средняя кнопка; 1–4 — виды;
## C — кинокамера / стратегия; P — пауза; + / − — скорость; R — бой заново; F1 — подсказка;
## F2 — качество «Высокое» / «Низкое» (ТЗ 11.7).
##
## Кадры героев — камеры Cam* в узле Cameras (tools/shot.sh … --cam=CamRTS --at=19).
## Серия кадров за один прогон:  -- --hero=9.6@CamVolley,14@CamImpact --hero_out=/abs/dir [--hero_prefix=p_]
## При съёмке (--shot / --hero) время до кадра проматывается в облегчённом режиме
## (низкое разрешение 3D, без теней и фильтра), за 1,5 с до кадра всё включается обратно.

## Сколько секунд до кадра работать в полном качестве (туман и дым успевают устояться)
const FULL_BEFORE := 0.5
## Масштаб 3D при промотке
const FAST_SCALE := 0.34
## Скорость боя при промотке серии кадров (симуляция, частицы и камеры — вместе)
const FAST_SPEED := 4.0

@onready var world: World = $World
@onready var camp: KipchakCamp = $Camp
@onready var battle: BattleRoot = $Battle

var _ordo: Node
var _targets: Array = []          # [время, имя камеры] — серия кадров
var _hero_out := ""
var _hero_prefix := ""
var _busy := false
var _fast := false
var _shot_at := -1.0


func _ready() -> void:
	_ordo = get_node_or_null("/root/Ordo")
	camp.snap_to_terrain()
	_clear_grass()
	_place_cameras()
	if _ordo:
		if _ordo.has_arg("shot"):
			_shot_at = float(_ordo.arg("at", "1.0"))
		if _ordo.has_arg("hero"):
			for item in String(_ordo.arg("hero")).split(",", false):
				var kv := item.split("@")
				if kv.size() == 2:
					_targets.append([float(kv[0]), kv[1]])
			_targets.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
			_hero_out = _ordo.arg("hero_out", ProjectSettings.globalize_path("user://"))
			_hero_prefix = _ordo.arg("hero_prefix", "")
	_update_fast()
	# для ролика: бой начинается не с нуля (--battle_skip=секунды), шаги без отрисовки
	if _ordo and _ordo.has_arg("battle_skip") and battle.scenario:
		for i in int(float(_ordo.arg("battle_skip")) / ScenarioClash.DT):
			battle.scenario.step()


## Поляны без травы под юртами, загонами и предметами лагеря
func _clear_grass() -> void:
	var list: Array = []
	for n in camp.buildings():
		var r := float(n.get_meta("footprint", 0.0))
		if r > 0.0:
			list.append(Vector3(n.global_position.x, n.global_position.z, r + 0.8))
	world.set_grass_clearings(list.slice(0, 48))


# ---------------------------------------------------------------- камеры кадров

func _ground(x: float, z: float, up: float) -> Vector3:
	return Vector3(x, Terrain.height_at(x, z) + up, z)


func _aim(cam_name: String, from: Vector3, to: Vector3, fov_deg: float) -> void:
	var cam := get_node_or_null("Cameras/" + cam_name) as Camera3D
	if cam == null:
		return
	cam.global_position = from
	cam.look_at(to, Vector3.UP)
	cam.fov = fov_deg
	cam.near = 0.25
	cam.far = 6000.0


## Неподвижные камеры кадров (бойовые — CineCamera/RtsCamera, ставятся сами)
func _place_cameras() -> void:
	# 1 — долина на закате: лагерь с дымами в среднем плане, горы, блик реки
	_aim("CamEstablish", _ground(95.0, 120.0, 46.0), _ground(-95.0, -60.0, 8.0), 46.0)
	# 2 — внутри лагеря: ставка, туг, боз үй, малчы, костры, дым; низкое солнце сбоку
	_aim("CamCampLife", _ground(-28.0, 50.0, 3.4), _ground(-62.0, 22.0, 4.2), 50.0)


# ---------------------------------------------------------------- клавиши

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if (event as InputEventKey).physical_keycode == KEY_F2 and _ordo:
		_ordo.call("set_quality", Ordo.QUALITY_HIGH if _ordo.call("is_low") else Ordo.QUALITY_LOW)


# ---------------------------------------------------------------- съёмка

func _process(_delta: float) -> void:
	_update_fast()
	if _targets.is_empty() or _busy or battle.scenario == null:
		return
	# камера следующего кадра текущая заранее: частицы в её поле зрения живут как надо
	var cam := get_tree().current_scene.find_child(String(_targets[0][1]), true, false) as Camera3D
	if cam and not cam.current:
		cam.make_current()
	if battle.scenario.time + 0.07 >= float(_targets[0][0]):
		_capture(_targets.pop_front())


## Ближайший момент кадра (−1 — съёмки нет)
func _next_shot_time() -> float:
	if not _targets.is_empty():
		return float(_targets[0][0])
	return _shot_at


func _update_fast() -> void:
	var t_next := _next_shot_time()
	if t_next < 0.0:
		if _fast:
			_set_fast(false)
		return
	var want := t_next - _now() > FULL_BEFORE
	if want != _fast:
		_set_fast(want)


## Облегчённая промотка: те же события и частицы, но кадр дешёвый
func _set_fast(on: bool) -> void:
	_fast = on
	var vp := get_viewport()
	vp.scaling_3d_scale = FAST_SCALE if on else (0.75 if _ordo.call("is_low") else 1.0)
	world.sun.shadow_enabled = not on
	var post := world.painterly_post()
	if post:
		post.enabled = not on and not _ordo.call("is_low") and not _ordo.has_arg("nopost")
	var env := world.environment_node.environment
	env.ssao_enabled = not on and not _ordo.call("is_low")
	if not _targets.is_empty() and battle.scenario:
		battle.scenario.time_scale = FAST_SPEED if on else 1.0
	print("[срез] %s t=%.2f, %d мс" % ["промотка" if on else "полное качество", _now(), Time.get_ticks_msec()])


func _now() -> float:
	if not _targets.is_empty() and battle.scenario:
		return battle.scenario.time
	return float(_ordo.get("scene_time")) if _ordo else 0.0


func _capture(item: Array) -> void:
	_busy = true
	var cam := get_tree().current_scene.find_child(String(item[1]), true, false) as Camera3D
	if cam:
		cam.make_current()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s%s.png" % [_hero_out, _hero_prefix, String(item[1])]
	img.save_png(path)
	print("[срез] кадр: %s t=%.2f, %d мс" % [path, battle.scenario.time, Time.get_ticks_msec()])
	_busy = false
	if _targets.is_empty():
		# серия снята — дальше ждать кадра --shot незачем
		get_tree().quit()
