class_name RtsCamera
extends Camera3D
## Камера стратегии (ТЗ 10, ПК): WASD и края экрана — сдвиг, колесо — приближение,
## Q/E — поворот, средняя кнопка — поворот и наклон мышью; наклон растёт с отдалением.
## Клавиши 1–4 — готовые виды. Камера не уходит под землю (Terrain.height_at).
##
## Точка взгляда focus лежит на земле; камера на расстоянии distance, азимут yaw
## (0 — камера к югу от точки и смотрит на север), наклон pitch считается из distance.

signal moved_by_player

## Точка взгляда (x, z) и начальные параметры
@export var focus := Vector3(94.0, 0.0, 6.0)
@export var distance := 70.0
@export_range(-180.0, 180.0) var yaw_deg := 12.0
@export var min_distance := 14.0
@export var max_distance := 260.0
## Наклон вблизи и вдали, градусы (на ~70 м — около 50°)
@export var pitch_near := 30.0
@export var pitch_far := 64.0
@export var pan_speed := 1.1          # доля расстояния в секунду
@export var edge_margin := 6
@export var rotate_speed := 90.0      # градусов в секунду
## Управление с клавиатуры и мыши (выключается при съёмке кадра)
@export var interactive := true
## Виды 1–4 с клавиш (срез — да; в «Городе» цифры — группы, виды — F5–F8 через RtsInput)
@export var presets_enabled := true
## Сдвиг WASD и поворот Q/E с клавиш (интерфейс «Города» гасит их, пока открыта вкладка стройки с буквами)
var pan_keys := true
## Экран над интерфейсом: Callable(pos: Vector2) -> bool; true — край экрана здесь не двигает камеру
var edge_blocked: Callable
## Готовые виды 1–4: (x, z, расстояние, азимут)
@export var presets: Array[Vector4] = [
	Vector4(78.0, 4.0, 110.0, 12.0),     # 1 — всё поле боя
	Vector4(104.0, 0.0, 42.0, -58.0),    # 2 — кокандская линия
	Vector4(30.0, 10.0, 46.0, 38.0),     # 3 — конница кыпчаков
	Vector4(-62.0, 30.0, 150.0, 20.0),   # 4 — лагерь
]

var _t_focus: Vector3
var _t_distance: float
var _t_yaw: float
var _pitch_off := 0.0
var _t_pitch_off := 0.0
var _drag := false


func _ready() -> void:
	var ordo := get_node_or_null("/root/Ordo")
	if ordo and (ordo.has_arg("shot") or ordo.has_arg("movie")):
		interactive = false
	_t_focus = focus
	_t_distance = distance
	_t_yaw = yaw_deg
	_apply()


## Перейти к виду (x, z, расстояние, азимут); instant — без плавного перелёта
func go_to(view: Vector4, instant := false) -> void:
	_t_focus = Vector3(view.x, 0.0, view.y)
	_t_distance = clampf(view.z, min_distance, max_distance)
	_t_yaw = view.w
	_t_pitch_off = 0.0
	if instant:
		focus = _t_focus
		distance = _t_distance
		yaw_deg = _t_yaw
		_pitch_off = 0.0
		_apply()


func pitch_for(dist: float) -> float:
	var k := clampf((dist - min_distance) / (max_distance - min_distance), 0.0, 1.0)
	return lerpf(pitch_near, pitch_far, sqrt(k)) + _pitch_off


func _unhandled_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_t_distance = maxf(min_distance, _t_distance * 0.88)
			moved_by_player.emit()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_t_distance = minf(max_distance, _t_distance * 1.12)
			moved_by_player.emit()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = mb.pressed
	elif event is InputEventMouseMotion and _drag:
		var mm := event as InputEventMouseMotion
		# сдвиг мыши — без множителя холста (масштаб интерфейса, Ordo): поворот на тот же путь мыши тот же
		var rel := mm.relative * get_window().content_scale_factor
		_t_yaw -= rel.x * 0.3
		_t_pitch_off = clampf(_t_pitch_off + rel.y * 0.15, -20.0, 20.0)
		moved_by_player.emit()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if presets_enabled and k >= KEY_1 and k <= KEY_4 and k - KEY_1 < presets.size():
			go_to(presets[k - KEY_1])
			moved_by_player.emit()


func _process(delta: float) -> void:
	if interactive:
		_read_controls(delta)
	var k := 1.0 - exp(-delta * 8.0)
	focus = focus.lerp(_t_focus, k)
	distance = lerpf(distance, _t_distance, k)
	yaw_deg = lerpf(yaw_deg, _t_yaw, k)
	_pitch_off = lerpf(_pitch_off, _t_pitch_off, k)
	_apply()


func _read_controls(delta: float) -> void:
	var move := Vector2.ZERO
	if pan_keys:
		if Input.is_physical_key_pressed(KEY_W): move.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S): move.y += 1.0
		if Input.is_physical_key_pressed(KEY_A): move.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D): move.x += 1.0
	var vp := get_viewport()
	# края экрана — только когда эта камера уже текущая (иначе мышь у края сбивала бы кино)
	if current and vp and DisplayServer.window_is_focused():
		var m := vp.get_mouse_position()
		var size := vp.get_visible_rect().size
		var over_hud := edge_blocked.is_valid() and bool(edge_blocked.call(m))
		# кромка — та же на экране при любом масштабе интерфейса (точки холста = пиксели / множитель)
		var em := edge_margin / maxf(get_window().content_scale_factor, 0.01)
		if m.x >= 0 and m.y >= 0 and m.x <= size.x and m.y <= size.y and not over_hud:
			if m.x < em: move.x -= 1.0
			if m.x > size.x - em: move.x += 1.0
			if m.y < em: move.y -= 1.0
			if m.y > size.y - em: move.y += 1.0
	if move != Vector2.ZERO:
		var r := move.normalized().rotated(-deg_to_rad(yaw_deg))
		_t_focus += Vector3(r.x, 0.0, r.y) * pan_speed * maxf(distance, 30.0) * delta
		moved_by_player.emit()
	var rot := 0.0
	if pan_keys:
		if Input.is_physical_key_pressed(KEY_Q): rot += 1.0
		if Input.is_physical_key_pressed(KEY_E): rot -= 1.0
	if rot != 0.0:
		_t_yaw += rot * rotate_speed * delta
		moved_by_player.emit()


func _apply() -> void:
	focus.y = Terrain.height_at(focus.x, focus.z)
	var p := deg_to_rad(pitch_for(distance))
	var y := deg_to_rad(yaw_deg)
	var off := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * distance
	var pos := focus + off
	# не под землю: запас над рельефом
	pos.y = maxf(pos.y, Terrain.height_at(pos.x, pos.z) + 2.5)
	global_position = pos
	look_at(focus + Vector3(0.0, 1.2, 0.0), Vector3.UP)
