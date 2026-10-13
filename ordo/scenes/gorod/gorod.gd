class_name GorodScene
extends Node3D
## Сцена «Города» (ARCHITECTURE §13, §19.5): мир + драйвер + виды + эффекты боя + камера стратегии
## + места под интерфейс (CityHud) и управление (RtsInput) — их ставит пакет UI.
## До I4 драйвер — FakeCityDriver (живой поддельный город); после I4 — GameDriver, виды не меняются.
##
## Выделение — SelectionModel (хранение; поведение даёт RtsInput из UI). Поставил RtsInput свою
## модель в SelectionView — сцена берёт её; нет — держит свою: selection.
##
## Ключи после «--»:
##   --skip=С            промотать город на С секунд при запуске (без отрисовки)
##   --series=DIR        серия кадров проверки вида (виды камер ниже) в папку DIR; --only=a,b — часть серии
##   --stress=N          нагрузка: довести юнитов до N и построек до 200 (замер вида)
##   --view=x,z,d,yaw    камера стратегии в эту точку (расстояние, азимут)
##   --perf_log          раз в секунду в консоль: время вида по частям, вызовы отрисовки, кадр
##   --perf_frames=N     замер N кадров, итог в консоль и выход (с --stress)
##   --perf_cpu          время вида — процессорное время потока (чужие процессы не мешают)
##   --perf_warm=N       сколько первых кадров не считать (загрузка, шейдеры), по умолчанию 30
##   --draw_parts        вызовы отрисовки по видам: все, без видов, без каждого вида по очереди
##                       (видимые / тени / 2D), итог в консоль и выход

signal series_done

## Набор кадров серии и сцены: &"city" — город (gorod.tscn), &"look" — ряды образцов построек
## (scenes/test/gorod_look.tscn: та же сцена, на ровном месте к югу — все постройки, стройки, руины)
@export var shot_set := &"city"

@onready var world: World = $World
@onready var driver: SimDriver = $Driver
@onready var units: UnitView = $Views/Units
@onready var buildings: BuildingView = $Views/Buildings
@onready var ghost: GhostView = $Views/Ghost
@onready var selection_view: SelectionView = $Views/Selection
@onready var overlay: OverlayView = $HUD/Overlay
@onready var camera: RtsCamera = $Cameras/CamRTS

## Выделение (до RtsInput из UI)
var selection := SelectionModel.new()

var _ordo: Node
var _series: Array = []
var _series_dir := ""
var _busy := false
var _wait := 0
var _perf_log := false
var _perf_frames := 0
var _perf_n := 0
var _perf_warm := 30
var _perf_sum := {}
var _perf_max := {}
var _log_t := 0.0


func _ready() -> void:
	_ordo = get_node_or_null("/root/Ordo")
	# своя модель — только если RtsInput (UI, его _ready раньше) не поставил свою
	if selection_view.selection == null:
		selection_view.selection = selection
	else:
		selection = selection_view.selection
	if _ordo and _ordo.has_arg("skip") and driver.sim:
		for i in int(float(_ordo.arg("skip")) * 30.0):
			driver.step()
	if _ordo and _ordo.has_arg("view"):
		# --view=x,z,расстояние,азимут — камера стратегии сразу туда
		var v := String(_ordo.arg("view")).split_floats(",")
		if v.size() == 4:
			camera.go_to(Vector4(v[0], v[1], v[2], v[3]), true)
	if shot_set == &"look":
		GorodShots.place_lineup(CityView.query_of(driver) as FakeCity)
	if _ordo and _ordo.has_arg("stress"):
		GorodStress.populate(CityView.query_of(driver) as FakeCity, int(_ordo.arg("stress")), 200)
	if _ordo:
		_perf_log = _ordo.has_arg("perf_log")
		_perf_frames = int(_ordo.arg("perf_frames", "0"))
		CityView.cpu_clock = _ordo.has_arg("perf_cpu")
		_perf_warm = int(_ordo.arg("perf_warm", "30"))
		if _perf_log or _perf_frames > 0:
			RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if _ordo and _ordo.has_arg("series"):
		_series_dir = String(_ordo.arg("series"))
		DirAccess.make_dir_recursive_absolute(_series_dir)
		var only := String(_ordo.arg("only", "")).split(",", false)
		for s: Array in GorodShots.shots(shot_set):
			if only.is_empty() or only.has(s[0]):
				_series.append(s)
		camera.interactive = false
		_wait = 3
	if _ordo and _ordo.has_arg("draw_parts"):
		_draw_parts()
	if _ordo and (_ordo.has_arg("series") or _ordo.has_arg("shot")):
		world.environment_node.environment.volumetric_fog_temporal_reprojection_enabled = false
		_fast = true


func _process(delta: float) -> void:
	if _perf_log or _perf_frames > 0:
		_perf(delta)
	_update_fast()
	if _series.is_empty() or _busy:
		return
	_wait -= 1
	if _wait > 0:
		return
	_shoot(_series.pop_front())


# ---------------------------------------------------------------- промотка при съёмке

## До кадра — дешёвая отрисовка (низкое разрешение 3D, без теней, фильтра и тумана), как у среза
const FAST_SCALE := 0.25
var _fast := false
var _fast_on := false
var _frames := 0


func _update_fast() -> void:
	_frames += 1
	if not _fast:
		return
	var want := true
	if not _series.is_empty() or _busy:
		want = _wait > 1 and not _busy
	elif _ordo and _ordo.has_arg("shot"):
		want = float(_ordo.get("scene_time")) < float(_ordo.arg("at", "1.0")) - 0.1
	else:
		want = false
	if _frames < 2:
		return          # качество мира ставится отложенно — промотку ставим поверх
	if want != _fast_on:
		_set_fast(want)
	if not want and _series.is_empty() and not _busy:
		_fast = _ordo != null and _ordo.has_arg("shot") and not _ordo.has_arg("series")


func _set_fast(on: bool) -> void:
	_fast_on = on
	var vp := get_viewport()
	var q: String = _ordo.quality if _ordo else "high"
	if on:
		vp.scaling_3d_scale = FAST_SCALE
	else:
		WorldQuality.apply_viewport(vp, q)
	var p := WorldQuality.preset(q)
	world.sun.shadow_enabled = not on
	var post := world.painterly_post()
	if post:
		post.enabled = not on and p.post != "off"
	var env := world.environment_node.environment
	env.ssao_enabled = not on and bool(p.ssao)
	env.volumetric_fog_enabled = not on and bool(p.volfog)
	print("[город] %s, кадр %d, %d мс" % ["промотка" if on else "полное качество", _frames, Time.get_ticks_msec()])


## Кадр серии: поставить камеру и состояние (призрак, выделение), подождать два кадра, снять
func _shoot(s: Array) -> void:
	_busy = true
	GorodShots.setup(self, s)
	for i in 1:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_series_dir, String(s[0])]
	img.save_png(path)
	print("[город] кадр: %s t=%.2f, %d мс, вызовов отрисовки %s, юнитов %d" % [path, driver.time, Time.get_ticks_msec(),
		draw_calls_text(draw_calls()), driver.sim.n])
	_busy = false
	_wait = 1
	if _series.is_empty():
		series_done.emit()
		get_tree().quit()


# ---------------------------------------------------------------- замер

const PERF_KEYS := [&"view_units", &"view_buildings", &"view_nodes", &"view_herds", &"view_fields", &"view_select",
	&"view_overlay", &"view_cityfx", &"fx"]


func _perf(delta: float) -> void:
	var rid := get_viewport().get_viewport_rid()
	var vals := {}
	var total := 0.0
	for k: StringName in PERF_KEYS:
		var v := float(CityView.frame_ms.get(k, 0.0))
		vals[k] = v
		if k != &"fx":
			total += v
	vals[&"view_total"] = total
	vals[&"frame"] = delta * 1000.0
	vals[&"render_cpu"] = RenderingServer.viewport_get_measured_render_time_cpu(rid)
	vals[&"draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	CityView.frame_ms.clear()
	_perf_n += 1
	if _perf_n > _perf_warm:      # первые кадры — загрузка и компиляция шейдеров
		for k in vals:
			_perf_sum[k] = float(_perf_sum.get(k, 0.0)) + float(vals[k])
			_perf_max[k] = maxf(float(_perf_max.get(k, 0.0)), float(vals[k]))
	_log_t += delta
	if _perf_log and _log_t >= 1.0:
		_log_t = 0.0
		print("[город скорость] ", _perf_text())
	if _perf_frames > 0 and _perf_n >= _perf_frames + _perf_warm:
		print("[город итог] кадров %d, юнитов %d, построек %d" % [_perf_n - _perf_warm, driver.sim.n, _buildings_count()])
		print("[город итог] ", _perf_text())
		get_tree().quit()


func _perf_text() -> String:
	var n := maxi(_perf_n - _perf_warm, 1)
	var parts := PackedStringArray()
	for k in [&"view_total", &"view_units", &"view_buildings", &"view_nodes", &"view_herds", &"view_fields",
			&"view_select", &"view_overlay", &"view_cityfx", &"fx", &"render_cpu", &"draw_calls", &"frame"]:
		parts.append("%s %.2f (%.2f)" % [k, float(_perf_sum.get(k, 0.0)) / n, float(_perf_max.get(k, 0.0))])
	return " | ".join(parts)


## Вызовы отрисовки кадра: [всего, видимые, тени, 2D]
func draw_calls() -> PackedInt32Array:
	var rid := get_viewport().get_viewport_rid()
	var info := RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
	var v := RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, info)
	var sh := RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, info)
	var c := RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, info)
	return PackedInt32Array([int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), v, sh, c])


static func draw_calls_text(d: PackedInt32Array) -> String:
	return "%d (видимых %d, теней %d, 2D %d)" % [d[0], d[1], d[2], d[3]]


## --draw_parts: доля каждого вида в вызовах отрисовки (вид прячется на 4 кадра)
func _draw_parts() -> void:
	for i in 40:
		await get_tree().process_frame
	var views := $Views as Node3D
	var hud := $HUD as CanvasLayer
	var all := draw_calls()
	print("[город вызовы] все виды: ", draw_calls_text(all))
	views.visible = false
	hud.visible = false
	for i in 4:
		await get_tree().process_frame
	var none := draw_calls()
	print("[город вызовы] без видов (мир): ", draw_calls_text(none))
	views.visible = true
	hud.visible = true
	for c in views.get_children():
		if not c is Node3D:
			continue
		(c as Node3D).visible = false
		for i in 4:
			await get_tree().process_frame
		var d := draw_calls()
		print("[город вызовы] вид %s: %d (видимых %d, теней %d)" % [c.name, all[0] - d[0], all[1] - d[1], all[2] - d[2]])
		(c as Node3D).visible = true
	hud.visible = false
	for i in 4:
		await get_tree().process_frame
	var d2 := draw_calls()
	print("[город вызовы] HUD (2D): %d" % (all[0] - d2[0]))
	print("[город вызовы] доля видов: %d (видимых %d, теней %d)" % [all[0] - none[0], all[1] - none[1], all[2] - none[2]])
	get_tree().quit()


func _buildings_count() -> int:
	var q := CityView.query_of(driver)
	var bt := q.buildings()
	var c := 0
	for b in bt.hw:
		if bt.state[b] != BuildingTable.State.FREE:
			c += 1
	return c
