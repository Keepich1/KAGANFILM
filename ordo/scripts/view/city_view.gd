class_name CityView
extends RefCounted
## Общие мелочи видов «Города» (VIEW, ARCHITECTURE §13): откуда брать GameQuery, прямоугольник
## земли под камерой, цвета сторон. Виды читают только GameQuery и массивы ядра (в локальные
## переменные в начале функции, не храня их в полях — CONTRACT §10.2 п. 9).

## Цвета сторон для колец, табличек и призраков (команда 0 — Коканд, 1 — кыпчаки, дальше — запас)
const TEAM_COLORS := [Color(0.24, 0.78, 0.74), Color(0.86, 0.3, 0.22), Color(0.85, 0.72, 0.3), Color(0.55, 0.5, 0.85)]
## Земля под камерой: дальше этой длины луч к горизонту обрезается, м
const RAY_MAX := 700.0


## GameQuery драйвера: FakeCityDriver.query (до I4) или GameDriver.game.query (после I4)
static func query_of(driver: Node) -> GameQuery:
	if driver == null:
		return null
	var q: Variant = driver.get("query")
	if q is GameQuery:
		return q
	var g: Variant = driver.get("game")
	if g is Object and (g as Object).get("query") is GameQuery:
		return (g as Object).get("query")
	return null


static func team_color(team: int) -> Color:
	return TEAM_COLORS[clampi(team, 0, TEAM_COLORS.size() - 1)]


## Прямоугольник земли (x, z), который видит камера, с запасом pad метров.
## Углы экрана — лучи до плоскости земли под точкой взгляда; луч к небу обрезается RAY_MAX.
static func camera_ground_rect(cam: Camera3D, pad: float) -> Rect2:
	if cam == null:
		return Rect2(-1.0e6, -1.0e6, 2.0e6, 2.0e6)
	var vp := cam.get_viewport()
	var size := vp.get_visible_rect().size if vp else Vector2(1920, 1080)
	var p := cam.global_position
	var fwd := -cam.global_basis.z
	var ground := Terrain.height_at(p.x, p.z)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c: Vector2 in [Vector2.ZERO, Vector2(size.x, 0.0), Vector2(0.0, size.y), size, size * 0.5]:
		var o := cam.project_ray_origin(c)
		var d := cam.project_ray_normal(c)
		var t := RAY_MAX
		if d.y < -0.01:
			t = minf((o.y - ground) / -d.y, RAY_MAX)
		var q := o + d * t
		lo = lo.min(Vector2(q.x, q.z))
		hi = hi.max(Vector2(q.x, q.z))
	lo = lo.min(Vector2(p.x, p.z))
	hi = hi.max(Vector2(p.x, p.z))
	if fwd.y > -0.02:
		# камера смотрит к горизонту: берём круг RAY_MAX
		lo = Vector2(p.x, p.z) - Vector2(RAY_MAX, RAY_MAX)
		hi = Vector2(p.x, p.z) + Vector2(RAY_MAX, RAY_MAX)
	return Rect2(lo - Vector2(pad, pad), hi - lo + Vector2(pad, pad) * 2.0)


## Время частей вида за текущий кадр (сцена «Города» читает и очищает: замер --perf_log)
static var frame_ms := {}
## Замер по процессорному времени потока (Linux: /proc/thread-self/schedstat) — чужие процессы
## на машине не портят числа (как tests/bench_battle.gd); включает сцена по ключу --perf_cpu
static var cpu_clock := false


## Метка времени для mark(): часы или процессорное время потока, мкс
static func now_usec() -> int:
	if cpu_clock:
		var f := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
		if f:
			return int(f.get_line().split(" ")[0]) / 1000
		cpu_clock = false
	return Time.get_ticks_usec()


## Записать время части вида с момента t0_usec (и в PerfMeter — экран F9)
static func mark(key: StringName, t0_usec: int) -> void:
	var ms := (now_usec() - t0_usec) / 1000.0
	frame_ms[key] = float(frame_ms.get(key, 0.0)) + ms
	PerfMeter.add_frame(key, ms)
