class_name FogBanks
extends Node3D
## Туман в низинах (ТЗ 11.1: «туман в низинах»): объёмы тумана над руслом реки и в
## котловинах — из assets/world/scatter.json (ключ fog: x, y, z, rx, rz, толщина слоя).
## Плотнее у земли, кверху тает. Работает только с объёмным туманом (качество «Высокое»).

@export var density := 0.035
@export var height_falloff := 0.35
@export var albedo := Color(0.86, 0.88, 0.92)
@export var emission := Color(0.02, 0.03, 0.045)


func _ready() -> void:
	var f := FileAccess.open("res://assets/world/scatter.json", FileAccess.READ)
	if f == null:
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var mat := FogMaterial.new()
	mat.density = density
	mat.albedo = albedo
	mat.emission = emission
	mat.height_falloff = height_falloff
	mat.edge_fade = 0.6
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
