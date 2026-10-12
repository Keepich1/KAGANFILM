class_name KokandModels
extends RefCounted
## Живописные материалы моделей Коканда (assets/models/kokand/*.glb).
##
##   var urda := preload("res://assets/models/kokand/urda.glb").instantiate()
##   KokandModels.apply(urda)                                   # как Painterly.apply, плюс ткань, колосья, жар
##   KokandModels.apply(house, {"albedo_tint": Color(1, 0.96, 0.9)})   # оттенок глины дома
##
## Обычные части → Painterly.apply (painterly_surface с общим атласом, цвет вершин — нарисованная тень).
## Узлы «Banner*», «Awning*» → shaders/cloth.gdshader (колышутся от ordo_wind).
## Узлы «Crop*» (колосья, хлопок поля) → тот же cloth.gdshader: качаются стебли, волна ветра
##   бежит по полю (UV2.x — доля высоты стебля, UV2.y — фаза по месту в поле).
## Узлы «Embers*» → жар печи/горна (без освещения, ярче единицы — для свечения).
## Узлы «Ground*», «Water*», «Crop*» не отбрасывают тень.

const CLOTH := preload("res://shaders/cloth.gdshader")

## Настройки ткани по началу имени узла
const CLOTH_PRESETS := {
	"Banner": {"flutter": 0.24, "cloth_length": 2.0, "wave_length": 1.3, "follow_wind": false,
		"along_axis": Vector3(1, 0, 0), "droop": 0.25, "pin_power": 1.3, "translucency": 0.35},
	"Awning": {"flutter": 0.05, "cloth_length": 2.0, "wave_length": 2.4, "follow_wind": false,
		"along_axis": Vector3(0, 0, 1), "droop": 0.0, "pin_power": 1.6, "wave_speed": 3.0,
		"translucency": 0.25},
	"Crop": {"flutter": 0.07, "cloth_length": 1.0, "wave_length": 3.0, "wave_speed": 2.4,
		"follow_wind": false, "along_axis": Vector3(0, 1, 0), "droop": 0.0, "pin_power": 1.7,
		"translucency": 0.45, "back_shade": 0.95, "rim_strength": 0.9},
}

static var _cache := {}


static func apply(root: Node, opts := {}) -> void:
	Painterly.apply(root, opts)
	for mi in _mesh_instances(root):
		var n := String(mi.name)
		for prefix in CLOTH_PRESETS:
			if n.begins_with(prefix):
				for s in mi.mesh.get_surface_count():
					mi.set_surface_override_material(s, cloth_material(_albedo(mi, s), prefix, opts))
		if n.begins_with("Embers"):
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, ember_material(_albedo(mi, s)))
		if n.begins_with("Ground") or n.begins_with("Water") or n.begins_with("Crop") or n.begins_with("Embers"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Материал ткани/колосьев (кэшируется по текстуре, виду и опциям).
static func cloth_material(tex: Texture2D, preset := "Banner", opts := {}) -> ShaderMaterial:
	var key := ["cloth", tex, preset, opts.hash()]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = CLOTH
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("use_vertex_color", true)
	var p: Dictionary = CLOTH_PRESETS.get(preset, {})
	for k in p:
		m.set_shader_parameter(k, p[k])
	for k in opts:
		m.set_shader_parameter(k, opts[k])
	_cache[key] = m
	return m


## Жар: текстура атласа без освещения, ярче единицы — для свечения.
static func ember_material(tex: Texture2D) -> StandardMaterial3D:
	var key := ["embers", tex]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	m.albedo_color = Color(2.4, 1.6, 1.1)
	_cache[key] = m
	return m


static func _albedo(mi: MeshInstance3D, surface: int) -> Texture2D:
	var src := mi.mesh.surface_get_material(surface)
	if src is BaseMaterial3D:
		return (src as BaseMaterial3D).albedo_texture
	if src is ShaderMaterial:
		return (src as ShaderMaterial).get_shader_parameter("albedo_tex")
	return null


static func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_mesh_instances(c))
	return out
