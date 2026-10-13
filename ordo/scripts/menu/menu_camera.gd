class_name MenuCamera
extends Camera3D
## Камера главного меню: медленный пролёт над долиной и лагерем кыпчаков на закате (ТЗ §12 [Свободно]:
## «меню со сценой лагеря на фоне»). Камера плывёт маятником по дуге вокруг лагеря, чуть дышит по высоте;
## лагерь держится в правой части кадра (слева — доска меню). Время — своё (кадры для shot.sh повторяемы).

## Середина лагеря среза (CONTRACT §3: ставка (−60, 20))
@export var center := Vector2(-62.0, 26.0)
## Курс от лагеря к камере, градусы (0 — на +X, 90 — на +Z); 33° — как у одобренного кадра CamEstablish
@export var bearing_deg := 33.0
## Размах маятника, градусы, и его период, с
@export var sweep_deg := 22.0
@export var period_s := 150.0
## Расстояние до лагеря и высота над землёй, м
@export var radius := 112.0
@export var height := 34.0
@export var height_wave := 6.0
## На сколько повернуть взгляд влево от лагеря, градусы (лагерь уходит вправо, под доской меню — небо и степь)
@export var offset_deg := 11.0
## Куда смотреть по высоте над землёй лагеря, м
@export var look_up := 4.0

var t := 0.0


func _ready() -> void:
	# кадры проверки: --menu_t=секунды — с какого места пути начать
	var o := get_node_or_null("/root/Ordo")
	if o and o.has_arg("menu_t"):
		t = float(o.arg("menu_t"))
	fov = 44.0
	near = 0.25
	far = 6000.0
	make_current()
	_place()


func _process(delta: float) -> void:
	t += delta
	_place()


func _place() -> void:
	var ph := TAU * t / period_s
	var a := deg_to_rad(bearing_deg + sweep_deg * sin(ph))
	var p := center + Vector2(cos(a), sin(a)) * radius
	var ground := Terrain.height_at(p.x, p.y)
	var h := height + height_wave * sin(ph * 0.5 + 0.7)
	var eye := Vector3(p.x, ground + h, p.y)
	var target := Vector3(center.x, Terrain.height_at(center.x, center.y) + look_up, center.y)
	global_position = eye
	look_at(target, Vector3.UP)
	rotate_y(deg_to_rad(offset_deg))
