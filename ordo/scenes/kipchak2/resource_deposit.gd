class_name ResourceDeposit
extends Node3D
## Месторождение камня или золота (ТЗ 5.1: камень ~4000, золото ~3000 единиц).
##
##   var d := preload("res://scenes/kipchak2/deposit_gold.tscn").instantiate() as ResourceDeposit
##   add_child(d)
##   d.set_amount(remaining / total)   # 1 → полное (_d0), ≤ 0.66 → половина (_d1), ≤ 0.33 → почти всё (_d2),
##                                     # 0 → выработано: модель прячется (узел остаётся)
##
## Модели: assets/models/world/deposit_<kind>_d<stage>[_lod1].glb, материал — deposit.gdshader
## (трипланарные рисованные плитки, у золота жилы светятся и искрят). Начало — центр основания.
## Метаданные: kind, footprint (Vector2, м) — для поиска пути и мест работников.

const MODEL_DIR := "res://assets/models/world/"
const SHADER := preload("res://scenes/kipchak2/deposit.gdshader")
const TEX := "res://assets/textures/world/deposit_%s.png"

## Плитки и свечение по виду
const LOOK := {
	"stone": {"face": "stone_face", "cut": "stone_cut", "vein": "stone_vein", "spoil": "spoil",
		"vein_glow": 0.0, "glint": 0.0, "glint_far": 0.0, "tint": Color(1, 1, 1), "rim": 0.55},
	"gold": {"face": "gold_rock", "cut": "gold_quartz", "vein": "gold_vein", "spoil": "gold_spoil",
		"vein_glow": 0.55, "glint": 0.9, "glint_far": 2.6, "tint": Color(1, 1, 1), "rim": 0.7},
}

@export_enum("stone", "gold") var kind := "stone":
	set(value):
		kind = value
		if is_inside_tree():
			_rebuild()
## 0 — полное, 1 — половина, 2 — почти выработано
@export_range(0, 2) var stage := 0:
	set(value):
		stage = clampi(value, 0, 2)
		if is_inside_tree():
			_rebuild()
@export var lod_distance := 160.0

var _model: Node3D
static var _materials := {}


func _ready() -> void:
	var o := get_node_or_null("/root/Ordo")
	if o and bool(o.call("is_low")):
		lod_distance = minf(lod_distance, 90.0)
	_rebuild()


## Доля оставшегося ресурса 0..1 → стадия модели; 0 — месторождение выработано (скрыто)
func set_amount(fraction: float) -> void:
	visible = fraction > 0.0
	var s := 0 if fraction > 0.66 else (1 if fraction > 0.33 else 2)
	if s != stage:
		stage = s


## Материал вида (общий на все месторождения этого вида)
static func material(p_kind: String) -> ShaderMaterial:
	if _materials.has(p_kind):
		return _materials[p_kind]
	var look: Dictionary = LOOK.get(p_kind, LOOK["stone"])
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("tex_face", load(TEX % look["face"]))
	m.set_shader_parameter("tex_cut", load(TEX % look["cut"]))
	m.set_shader_parameter("tex_vein", load(TEX % look["vein"]))
	m.set_shader_parameter("tex_spoil", load(TEX % look["spoil"]))
	m.set_shader_parameter("vein_glow", look["vein_glow"])
	m.set_shader_parameter("glint", look["glint"])
	m.set_shader_parameter("glint_far", look["glint_far"])
	m.set_shader_parameter("tint", look["tint"])
	m.set_shader_parameter("rim_strength", look["rim"])
	_materials[p_kind] = m
	return m


func _rebuild() -> void:
	if _model:
		_model.free()
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var base := MODEL_DIR + "deposit_%s_d%d" % [kind, stage]
	var mat := material(kind)
	var l0 := _instance(base + ".glb", "LOD0", mat)
	var l1 := _instance(base + "_lod1.glb", "LOD1", mat)
	if l0 and l1:
		_set_range(l0, 0.0, lod_distance)
		_set_range(l1, lod_distance, 0.0)


func _instance(path: String, node_name: String, mat: Material) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var n := (load(path) as PackedScene).instantiate() as Node3D
	n.name = node_name
	_model.add_child(n)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
	return n


func _set_range(root: Node, begin: float, end: float) -> void:
	if root is GeometryInstance3D:
		var g := root as GeometryInstance3D
		g.visibility_range_begin = begin
		g.visibility_range_end = end
		g.visibility_range_begin_margin = 4.0 if begin > 0.0 else 0.0
		g.visibility_range_end_margin = 4.0 if end > 0.0 else 0.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for c in root.get_children():
		_set_range(c, begin, end)
