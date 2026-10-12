class_name KipchakModels
extends RefCounted
## Живописные материалы моделей лагеря кыпчаков (assets/models/kipchak/*.glb).
##
##   var yurt := preload("res://assets/models/kipchak/boz.glb").instantiate()
##   KipchakModels.apply(yurt)                       # как Painterly.apply, плюс ткань и угли
##   KipchakModels.apply(yurt, {"albedo_tint": Color(1, 0.97, 0.92)})   # оттенок войлока
##
## Обычные части → Painterly.apply (painterly_surface с общим атласом).
## Узлы «Pennant*», «Awning*», «Banner*» → shaders/cloth.gdshader (колышутся от ordo_wind).
## Узлы «Embers*» → светящиеся угли (без освещения, для свечения костра).
## Узлы «Ground*» (пятна вытоптанной земли) не отбрасывают тень.

const CLOTH := preload("res://shaders/cloth.gdshader")

## Настройки ткани по началу имени узла
const CLOTH_PRESETS := {
	"Pennant": {"flutter": 0.32, "cloth_length": 3.2, "wave_length": 1.7, "follow_wind": true,
		"along_axis": Vector3(1, 0, 0), "droop": 0.5, "pin_power": 1.25, "translucency": 0.35},
	"Banner": {"flutter": 0.22, "cloth_length": 1.6, "wave_length": 1.2, "follow_wind": false,
		"along_axis": Vector3(1, 0, 0), "droop": 0.15, "pin_power": 1.3},
	"Awning": {"flutter": 0.06, "cloth_length": 2.2, "wave_length": 2.4, "follow_wind": false,
		"along_axis": Vector3(0, 0, 1), "droop": 0.0, "pin_power": 1.6, "wave_speed": 3.0,
		"translucency": 0.25},
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
		if n.begins_with("Ground"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if n.begins_with("Embers"):
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, ember_material(_albedo(mi, s)))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Материал ткани (кэшируется по текстуре, виду и опциям).
static func cloth_material(tex: Texture2D, preset := "Pennant", opts := {}) -> ShaderMaterial:
	var key := ["cloth", tex, preset, opts.hash()]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = CLOTH
	m.set_shader_parameter("albedo_tex", tex)
	var p: Dictionary = CLOTH_PRESETS.get(preset, {})
	for k in p:
		m.set_shader_parameter(k, p[k])
	for k in opts:
		m.set_shader_parameter(k, opts[k])
	_cache[key] = m
	return m


## Угли костра: текстура атласа без освещения, ярче единицы — для свечения.
static func ember_material(tex: Texture2D) -> StandardMaterial3D:
	var key := ["embers", tex]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	m.albedo_color = Color(2.2, 1.5, 1.1)
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
