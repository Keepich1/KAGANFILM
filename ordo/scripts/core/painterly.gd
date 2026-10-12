class_name Painterly
extends RefCounted
## Переводит материалы импортированных glb в живописные (shaders/painterly_*.gdshader).
##
##   var yurt := preload("res://assets/models/kipchak/boz.glb").instantiate()
##   Painterly.apply(yurt)
##
## Материал из glb с альфой MASK/BLEND становится вырезом (painterly_cutout),
## остальные — painterly_surface. Цвет вершин включается, если он есть в меше.

const SURFACE := preload("res://shaders/painterly_surface.gdshader")
const CUTOUT := preload("res://shaders/painterly_cutout.gdshader")

static var _cache := {}


static func apply(root: Node, opts := {}) -> void:
	for mi in _mesh_instances(root):
		var mesh := mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var src := mi.get_active_material(s)
			mi.set_surface_override_material(s, material_for(src, _has_colors(mesh, s), opts))


static func material_for(src: Material, vertex_colors := false, opts := {}) -> Material:
	if src is ShaderMaterial:
		return src
	var key := [src, vertex_colors, opts.hash()]
	if _cache.has(key):
		return _cache[key]
	var sm := ShaderMaterial.new()
	var cut := false
	if src is BaseMaterial3D:
		var bm := src as BaseMaterial3D
		cut = bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		sm.shader = CUTOUT if cut else SURFACE
		sm.set_shader_parameter("albedo_tex", bm.albedo_texture)
		sm.set_shader_parameter("albedo_tint", bm.albedo_color)
		if not cut:
			sm.set_shader_parameter("roughness", bm.roughness)
	else:
		sm.shader = SURFACE
	sm.set_shader_parameter("use_vertex_color", vertex_colors)
	for k in opts:
		sm.set_shader_parameter(k, opts[k])
	_cache[key] = sm
	return sm


static func _has_colors(mesh: Mesh, surface: int) -> bool:
	if mesh is ArrayMesh:
		return (mesh as ArrayMesh).surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR != 0
	return false


static func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_mesh_instances(c))
	return out
