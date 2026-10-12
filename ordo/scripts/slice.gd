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
## F2 — качество «Высокое» / «Низкое» (ТЗ 11.7); F9 — нагрузочная проверка: +1000 / +3000 солдат
## на южной части луга и счётчик кадров (выкл → 1000 → 3000 → выкл).
##
## Кадры героев — камеры Cam* в узле Cameras (tools/shot.sh … --cam=CamRTS --at=19).
## Серия кадров за один прогон:  -- --hero=9.6@CamVolley,14@CamImpact --hero_out=/abs/dir [--hero_prefix=p_]
## При съёмке (--shot / --hero) время до кадра проматывается в облегчённом режиме
## (низкое разрешение 3D, без теней и фильтра), за 1,5 с до кадра всё включается обратно.

## Сколько секунд до кадра работать в полном качестве (туман и дым успевают устояться)
const FULL_BEFORE := 0.1
## Масштаб 3D при промотке
const FAST_SCALE := 0.34
## Скорость боя при промотке серии кадров (симуляция, частицы и камеры — вместе)
const FAST_SPEED := 5.0

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
var _frames := 0
var _help: PanelContainer
var _stats: Label
var _help_t := 10.0
var _stress_level := 0
var _stress: Node3D
var _quiet := false              # съёмка кадра или ролика: без подсказок

const STRESS_LEVELS := [0, 1000, 3000]
const HELP_TEXT := """Управление (ТЗ 10)

Камера:  W A S D, края экрана — сдвиг;  колесо — ближе / дальше;
         Q / E — поворот;  средняя кнопка мыши — поворот и наклон
1 – 4    готовые виды: всё поле, кокандская линия, конница, лагерь
C        кинокамера ↔ камера стратегии
ЛКМ      выбрать отряд (двойной щелчок — все такие)
P        пауза        + / −  скорость боя        R  бой заново
F2       качество: «Высокое» / «Низкое»
F9       нагрузка: +1000 → +3000 солдат → выкл (с счётчиком кадров)
F1       показать / скрыть эту подсказку"""


func _ready() -> void:
	_ordo = get_node_or_null("/root/Ordo")
	_quiet = _ordo != null and (_ordo.has_arg("shot") or _ordo.has_arg("movie") or _ordo.has_arg("hero"))
	camp.snap_to_terrain()
	_build_hud()
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
	# 2 — внутри лагеря: ставка, туг, боз үй, малчы, костры, дым; низкое солнце сбоку-сзади
	_aim("CamCampLife", _ground(-28.0, 48.0, 2.6), _ground(-74.0, 36.0, 4.5), 52.0)
	# пробные камеры для подбора кадра: --cams=Имя@x,высота,z@x,высота,z@угол;…  (высота — над землёй)
	if _ordo and _ordo.has_arg("cams"):
		for item in String(_ordo.arg("cams")).split(";", false):
			var f := item.split("@")
			if f.size() < 4:
				continue
			var a := f[1].split_floats(",")
			var b := f[2].split_floats(",")
			var cam := Camera3D.new()
			cam.name = f[0]
			$Cameras.add_child(cam)
			_aim(f[0], _ground(a[0], a[2], a[1]), _ground(b[0], b[2], b[1]), float(f[3]))


# ---------------------------------------------------------------- подсказка и счётчик

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SliceHud"
	layer.layer = 6
	add_child(layer)
	_help = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.075, 0.05, 0.86)      # тёмный орех
	sb.border_color = Color(0.72, 0.56, 0.3, 0.9)     # латунь
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(16)
	_help.add_theme_stylebox_override("panel", sb)
	_help.position = Vector2(24, 24)
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = HELP_TEXT
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.95, 0.89, 0.76))
	_help.add_child(l)
	layer.add_child(_help)
	_help.visible = not _quiet
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 18)
	_stats.add_theme_color_override("font_color", Color(1.0, 0.93, 0.78))
	_stats.add_theme_color_override("font_shadow_color", Color(0.05, 0.03, 0.02, 0.95))
	_stats.add_theme_constant_override("shadow_offset_x", 1)
	_stats.add_theme_constant_override("shadow_offset_y", 1)
	_stats.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stats.offset_left = -440.0
	_stats.offset_right = -20.0
	_stats.offset_top = 16.0
	_stats.offset_bottom = 90.0
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats.visible = false
	layer.add_child(_stats)
	# своя подсказка боя не нужна — её заменяет эта
	var hud := battle.get_node_or_null("HUD")
	if hud and hud.get("show_help") != null:
		hud.set("show_help", false)
		var h: Variant = hud.get("_help")
		if h is Label:
			(h as Label).visible = false


func _update_hud(delta: float) -> void:
	if _help.visible and not _quiet and _help_t > 0.0:
		_help_t -= delta
		if _help_t <= 0.0:
			_help.visible = false
	if _stats.visible:
		var units: int = battle.scenario.sim.n if battle.scenario and battle.scenario.sim else 0
		if _stress and _stress.get_node_or_null("Scenario"):
			var ss := _stress.get_node("Scenario") as ScenarioClash
			if ss.sim:
				units += ss.sim.n
		_stats.text = "Кадров в секунду: %d\nСолдат в бою: %d   (F9 — дальше)\nВызовов отрисовки: %d" % [
			Engine.get_frames_per_second(), units,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))]


## Нагрузочная проверка: выкл → +1000 → +3000 солдат → выкл
func _cycle_stress() -> void:
	_stress_level = (_stress_level + 1) % STRESS_LEVELS.size()
	if _stress:
		_stress.queue_free()
		_stress = null
	var n: int = STRESS_LEVELS[_stress_level]
	_stats.visible = n > 0
	if n == 0:
		return
	_stress = Node3D.new()
	_stress.name = "Stress"
	add_child(_stress)
	var sc := StressScenario.new()
	sc.name = "Scenario"
	sc.soldiers = n
	_stress.add_child(sc)
	var view := BattleView.new()
	view.name = "View"
	view.ambient_path = ^"../NoAmbient"
	_stress.add_child(view)
	sc.start(7)


# ---------------------------------------------------------------- клавиши

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).physical_keycode:
		KEY_F1:
			_help.visible = not _help.visible
			_help_t = 0.0
		KEY_F2:
			if _ordo:
				_ordo.call("set_quality", Ordo.QUALITY_HIGH if _ordo.call("is_low") else Ordo.QUALITY_LOW)
		KEY_F9:
			_cycle_stress()


# ---------------------------------------------------------------- съёмка

func _process(delta: float) -> void:
	_update_hud(delta)
	_frames += 1
	if _frames == 2 and _fast:
		# WorldQuality применяет качество отложенно (после _ready) — промотку ставим поверх
		_set_fast(true)
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
	if _busy:
		return  # кадр серии ещё снимается — качество не трогаем
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
	# объёмный туман без накопления по кадрам: считается сразу, промотке он не нужен
	env.volumetric_fog_temporal_reprojection_enabled = false
	env.volumetric_fog_enabled = not on and not _ordo.call("is_low") and not _ordo.has_arg("nofog") \
		and not _ordo.has_arg("novolfog")
	var grass := world.get_node_or_null("Grass") as Node3D
	if grass and not _ordo.has_arg("nograss"):
		grass.visible = not on
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
	if String(item[1]) == "CamRTS":
		# выделение нужно только кадру стратегии — дальше кольца не мешают кино
		var sel := battle.get_node_or_null("Selection") as SquadSelection
		if sel:
			sel._select(PackedInt32Array())
	_busy = false
	if _targets.is_empty():
		# серия снята — дальше ждать кадра --shot незачем
		get_tree().quit()
