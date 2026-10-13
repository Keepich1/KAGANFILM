class_name WorldScatter
extends Node3D
## Деревья и камни мира из assets/world/scatter.json (делает tools/gen_world.py):
## тополя и ивы вдоль реки, аллея тополей у арыка, арча на склонах, карагачи у лагеря,
## валуны на холмах. Каждый вид в каждой клетке 128 × 128 м — один MultiMeshInstance3D
## (мало вызовов отрисовки); ближе — подробная модель, дальше — _lod1.
##
##   scatter.trees_near(Vector3(x, 0, z), 20.0) -> Array[Vector3]   деревья рядом (ресурс «лес»)
##   scatter.hide_tree(kind, index)   спрятать срубленное дерево («Город», VIEW; kind — ScatterData.KINDS)

const FOLIAGE := preload("res://assets/models/world/foliage.gdshader")
const SURFACE := preload("res://shaders/painterly_surface.gdshader")
const CELL := 128.0

## Дальность подробных моделей деревьев и камней, м
@export var tree_lod_distance := 320.0
@export var rock_lod_distance := 160.0
@export var rock_max_distance := 900.0
## Множитель дальностей (качество «Низкое» уменьшает)
@export var lod_scale := 1.0:
	set(v):
		lod_scale = v
		_apply_ranges()

## Тон крон по видам (множитель к атласу)
const TINTS := {
	"poplar": Color(0.74, 0.76, 0.68),
	"elm": Color(0.62, 0.7, 0.6),
	"willow": Color(0.78, 0.8, 0.78),
	"juniper": Color(0.7, 0.75, 0.8),
}

var _data := {}
var _nodes: Array[MultiMeshInstance3D] = []
## Дерево → где оно нарисовано (для «Города»: срубленное прячется, ARCHITECTURE §13):
## kind → PackedInt32Array по номерам деревьев вида: (номер узла в _nodes LOD0) << 16 | номер экземпляра;
## LOD1 этого дерева — следующий узел в _nodes
var _tree_at := {}


func _ready() -> void:
	var f := FileAccess.open("res://assets/world/scatter.json", FileAccess.READ)
	if f == null:
		push_warning("WorldScatter: нет assets/world/scatter.json")
		return
	_data = JSON.parse_string(f.get_as_text())
	var atlas := load("res://assets/textures/world/trees.png")
	for kind in ["poplar", "willow", "juniper", "elm"]:
		var mat := ShaderMaterial.new()
		mat.shader = FOLIAGE
		mat.set_shader_parameter("albedo_tex", atlas)
		mat.set_shader_parameter("tint", TINTS[kind])
		if kind == "juniper":
			# плотная хвоя: почти не качается и не просвечивает
			mat.set_shader_parameter("sway", 0.12)
			mat.set_shader_parameter("translucency", 0.12)
			mat.set_shader_parameter("rim_strength", 0.25)
		_build_kind(kind, _data.get(kind, []), mat, false)
	var rock_mat := ShaderMaterial.new()
	rock_mat.shader = SURFACE
	rock_mat.set_shader_parameter("albedo_tex", load("res://assets/textures/world/ground_rock.png"))
	rock_mat.set_shader_parameter("albedo_tint", Color(0.62, 0.6, 0.58))
	rock_mat.set_shader_parameter("use_vertex_color", true)
	rock_mat.set_shader_parameter("rim_strength", 0.3)
	var rocks: Array = _data.get("rock", [])
	for v in 4:
		var subset := rocks.filter(func(r: Array) -> bool: return int(r[5]) == v)
		_build_kind("rock_%d" % v, subset, rock_mat, true)
	_apply_ranges()


## Спрятать дерево вида kind (номер в ScatterData.KINDS) с номером index в файле — срублено
## («Город», NodeView по TREE_FELLED). Оба LOD сжимаются в точку. show — вернуть.
func hide_tree(kind: int, index: int, show := false) -> bool:
	if kind < 0 or kind >= ScatterData.KINDS.size():
		return false
	var at: PackedInt32Array = _tree_at.get(ScatterData.KINDS[kind], PackedInt32Array())
	if index < 0 or index >= at.size() or at[index] < 0:
		return false
	var node_i := at[index] >> 16
	var inst := at[index] & 0xFFFF
	for lod in 2:
		if node_i + lod >= _nodes.size():
			break
		var mi := _nodes[node_i + lod]
		if int(mi.get_meta("lod")) != lod:
			break
		var mm := mi.multimesh
		var xf := mm.get_instance_transform(inst)
		if not mi.has_meta("orig"):
			mi.set_meta("orig", {})
		var orig: Dictionary = mi.get_meta("orig")
		if not show:
			if not orig.has(inst):
				orig[inst] = xf
			mm.set_instance_transform(inst, Transform3D(Basis.from_scale(Vector3.ZERO), xf.origin))
		elif orig.has(inst):
			mm.set_instance_transform(inst, orig[inst])
			orig.erase(inst)
	return true


## Где стоит дерево (kind, index): позиция у земли или Vector3.INF
func tree_position(kind: int, index: int) -> Vector3:
	if kind < 0 or kind >= ScatterData.KINDS.size():
		return Vector3.INF
	var list: Array = _data.get(ScatterData.KINDS[kind], [])
	if index < 0 or index >= list.size():
		return Vector3.INF
	var it: Array = list[index]
	return Vector3(float(it[0]), float(it[1]), float(it[2]))


func trees_near(p: Vector3, radius: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for kind in ["poplar", "willow", "juniper", "elm"]:
		for it: Array in _data.get(kind, []):
			var q := Vector3(it[0], it[1], it[2])
			if Vector2(q.x - p.x, q.z - p.z).length() <= radius:
				out.append(q)
	return out


func _mesh_of(path: String) -> Mesh:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var root := ps.instantiate()
	var mesh: Mesh = null
	for n in root.find_children("*", "MeshInstance3D", true, false):
		mesh = (n as MeshInstance3D).mesh
		break
	if mesh == null and root is MeshInstance3D:
		mesh = (root as MeshInstance3D).mesh
	root.free()
	return mesh


func _build_kind(kind: String, items: Array, mat: Material, is_rock: bool) -> void:
	if items.is_empty():
		return
	var base := "res://assets/models/world/%s" % kind
	var meshes := [_mesh_of(base + ".glb"), _mesh_of(base + "_lod1.glb")]
	if meshes[0] == null:
		push_warning("WorldScatter: нет модели %s" % kind)
		return
	var cells := {}
	var index_of := {}     # клетка → номера деревьев в файле (для hide_tree)
	for idx in items.size():
		var it: Array = items[idx]
		var key := Vector2i(floori(float(it[0]) / CELL), floori(float(it[2]) / CELL))
		if not cells.has(key):
			cells[key] = []
			index_of[key] = PackedInt32Array()
		cells[key].append(it)
		index_of[key].append(idx)
	var at := PackedInt32Array()
	if not is_rock:
		at.resize(items.size())
		at.fill(-1)
	var rs := RandomNumberGenerator.new()
	rs.seed = hash(kind)
	for key in cells:
		var list: Array = cells[key]
		var xforms: Array[Transform3D] = []
		var customs: Array[Color] = []
		for it: Array in list:
			var rot := deg_to_rad(float(it[3]))
			if kind == "willow" and it.size() > 5:
				# ива наклонена к воде: модель клонится в +X, река — к северу или югу
				rot = (PI * 0.5 if float(it[5]) > 0.0 else -PI * 0.5) + deg_to_rad(float(it[3]) - 180.0) * 0.15
			var s := float(it[4])
			var b := Basis(Vector3.UP, rot).scaled(Vector3(s, s, s))
			if is_rock:
				# валуны слегка наклонены и утоплены
				b = Basis(Vector3(1, 0, 0), rs.randf_range(-0.15, 0.15)) * b
			# валуны утоплены в землю примерно на треть высоты, стволы — чуть-чуть
			var y := float(it[1]) - (0.32 * s if is_rock else 0.15)
			xforms.append(Transform3D(b, Vector3(float(it[0]), y, float(it[2]))))
			customs.append(Color(rs.randf(), rs.randf(), rs.randf(), 1.0))
		if not is_rock:
			var ids: PackedInt32Array = index_of[key]
			for i in ids.size():
				at[ids[i]] = (_nodes.size() << 16) | i
		for lod in 2:
			if meshes[lod] == null:
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = meshes[lod]
			mm.instance_count = xforms.size()
			for i in xforms.size():
				mm.set_instance_transform(i, xforms[i])
				mm.set_instance_custom_data(i, customs[i])
			var mi := MultiMeshInstance3D.new()
			mi.name = "%s_%d_%d_L%d" % [kind, key.x, key.y, lod]
			mi.multimesh = mm
			mi.material_override = mat
			mi.set_meta("lod", lod)
			mi.set_meta("rock", is_rock)
			add_child(mi)
			_nodes.append(mi)
	if not is_rock:
		_tree_at[kind] = at


func _apply_ranges() -> void:
	for mi in _nodes:
		var lod: int = mi.get_meta("lod")
		var near := (rock_lod_distance if mi.get_meta("rock") else tree_lod_distance) * lod_scale
		var far := rock_max_distance * lod_scale if mi.get_meta("rock") else 0.0
		mi.visibility_range_begin = 0.0 if lod == 0 else near
		mi.visibility_range_end = near if lod == 0 else far
		mi.visibility_range_begin_margin = 10.0
		mi.visibility_range_end_margin = 10.0
		# дизеринг: без «щели» между LOD0 и LOD1, где дерево пропадало бы совсем
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
