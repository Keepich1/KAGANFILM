class_name FogBanks
extends Node3D
## Туман в низинах (ТЗ 11.1: «туман в низинах»): объёмы тумана над руслом реки и в
## котловинах — из assets/world/scatter.json (ключ fog: x, y, z, rx, rz, толщина слоя).
## Плотнее у земли, кверху тает. Работает только с объёмным туманом (качество «Высокое»).

@export var density := 0.014
@export var height_falloff := 0.7
@export var albedo := Color(0.86, 0.88, 0.92)
@export var emission := Color(0.02, 0.03, 0.045)
## Дымка над полем и лагерем (пыль, дым очагов): в ней видны лучи солнца
@export var field_haze_density := 0.0038
@export var field_haze_falloff := 0.16
@export var field_haze_albedo := Color(0.95, 0.86, 0.76)

var _mat: FogMaterial
var _haze: FogMaterial


func _ready() -> void:
	var f := FileAccess.open("res://assets/world/scatter.json", FileAccess.READ)
	if f == null:
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var mat := FogMaterial.new()
	_mat = mat
	mat.density = density
	mat.albedo = albedo
	mat.emission = emission
	mat.height_falloff = height_falloff
	mat.edge_fade = 0.6
	# дымка над долиной: слой у земли, кверху тает
	var haze := FogMaterial.new()
	_haze = haze
	haze.density = field_haze_density
	haze.albedo = field_haze_albedo
	haze.height_falloff = field_haze_falloff
	haze.edge_fade = 0.25
	var hv := FogVolume.new()
	hv.name = "FieldHaze"
	hv.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	hv.size = Vector3(900.0, 60.0, 560.0)
	hv.position = Vector3(-20.0, 0.0, 70.0)
	hv.material = haze
	add_child(hv)
	var k := 0
	for it: Array in data.get("fog", []):
		var v := FogVolume.new()
		v.name = "Fog%d" % k
		k += 1
		v.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
		var th := float(it[5])
		v.size = Vector3(float(it[3]) * 2.0, th * 2.0, float(it[4]) * 2.0)
		v.position = Vector3(float(it[0]), float(it[1]), float(it[2]))
		v.material = mat
		add_child(v)


## Время суток (LightPresets fog_banks): днём туман в низинах тоньше, дымка над полем светлее и реже
func apply_light(p: Dictionary) -> void:
	density = float(p.get("density", density))
	albedo = p.get("albedo", albedo)
	emission = p.get("emission", emission)
	field_haze_density = float(p.get("haze_density", field_haze_density))
	field_haze_albedo = p.get("haze_albedo", field_haze_albedo)
	if _mat:
		_mat.density = density
		_mat.albedo = albedo
		_mat.emission = emission
	if _haze:
		_haze.density = field_haze_density
		_haze.albedo = field_haze_albedo
