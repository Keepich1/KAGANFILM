class_name NodeView
extends Node3D
## Узлы ресурсов (ARCHITECTURE §13): деревья и жилы.
##
## Деревья рисует мир (WorldScatter); срубленное (TREE_FELLED или запас 0) прячется
## WorldScatter.hide_tree (согласованная правка Мира), на его месте — пень.
## Жилы камня и золота — месторождения арта scenes/kipchak2/deposit_<id>.tscn (ResourceDeposit:
## три стадии выработки, свой трипланарный материал, LOD1; выработанная — не видна). Нет сцены —
## модель assets/models/world/<model>.glb (стадии — <model>_s2.glb, <model>_s1.glb), нет и её —
## заместитель из валунов мира (выработанная — пятно щебня). Стадия: > 2/3 запаса, > 1/3, > 0, 0.

const ROCK_TEX := "res://assets/textures/world/ground_rock.png"
const DEPOSIT_SCENE := "res://scenes/kipchak2/deposit_%s.tscn"
const SURFACE := preload("res://shaders/painterly_surface.gdshader")

@export var driver_path: NodePath = ^"../../Driver"
@export var scatter_path: NodePath = ^"../../World/Scatter"

var query: GameQuery
var defs: Defs
var felled := 0

var _scatter: WorldScatter
var _cursor := 0
var _stage := PackedInt32Array()
var _node: Array[Node3D] = []
var _stumps: MultiMeshInstance3D
var _stump_pos := PackedVector3Array()
var _hidden := {}
var _frame := 0
static var _rock_meshes: Array[Mesh] = []
static var _rock_mat: ShaderMaterial
static var _gold_mat: ShaderMaterial


func _ready() -> void:
	_scatter = get_node_or_null(scatter_path) as WorldScatter
	var d := get_node_or_null(driver_path)
	if d and d.has_signal("started"):
		d.connect("started", func(_s: int) -> void: set_query(CityView.query_of(d)))
	if CityView.query_of(d):
		set_query(CityView.query_of(d))


func set_query(q: GameQuery) -> void:
	for n in _node:
		if n:
			n.queue_free()
	_node.clear()
	_stage.resize(0)
	_stump_pos.resize(0)
	for k: int in _hidden:
		if _scatter:
			_scatter.hide_tree(ScatterData.ref_kind(k), ScatterData.ref_index(k), true)
	_hidden.clear()
	query = q
	defs = q.defs() if q else null
	if q == null:
		return
	_cursor = q.events().head
	_sync_all()


func _process(_delta: float) -> void:
	if query == null:
		return
	var t0 := CityView.now_usec()
	_frame += 1
	var ev := query.events()
	var r := ev.range_since(_cursor)
	for seq in range(r.x, r.y):
		var i := ev.at(seq)
		if ev.e_kind[i] == SimEvents.Ev.TREE_FELLED:
			_fell(ev.e_b[i], Vector2(ev.e_x[i], ev.e_z[i]))
		elif ev.e_kind[i] == SimEvents.Ev.NODE_DEPLETED:
			_frame = 0
	_cursor = r.y
	if _frame % 15 == 0:
		_sync_deposits()
	CityView.mark(&"view_nodes", t0)


func _sync_all() -> void:
	var nt := query.nodes()
	for n in nt.hw:
		if nt.ntype[n] >= 0 and nt.scatter_ref[n] >= 0 and nt.amount_milli[n] == 0:
			_fell(nt.scatter_ref[n], Vector2(nt.x[n], nt.z[n]))
	_sync_deposits()


## Дерево срублено: спрятать в мире, поставить пень
func _fell(scatter_ref: int, pos: Vector2) -> void:
	if scatter_ref < 0 or _hidden.has(scatter_ref):
		return
	_hidden[scatter_ref] = true
	felled += 1
	if _scatter:
		_scatter.hide_tree(ScatterData.ref_kind(scatter_ref), ScatterData.ref_index(scatter_ref))
	_stump_pos.append(Vector3(pos.x, Terrain.height_at(pos.x, pos.y), pos.y))
	_rebuild_stumps()


func _rebuild_stumps() -> void:
	if _stumps == null:
		_stumps = MultiMeshInstance3D.new()
		_stumps.name = "Stumps"
		_stumps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_stumps)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var k := BuildingLook.Kit.new()
		k.cyl(Vector3(0, -0.1, 0), 0.32, 0.26, 0.55, 8, "bark", Color(0.85, 0.75, 0.65))
		k.cyl(Vector3(0.0, 0.42, 0.0), 0.25, 0.25, 0.02, 8, "logend", Color(1.0, 0.92, 0.8))
		k.box(Vector3(0.9, 0.12, 0.2), Vector3(0.7, 0.1, 0.1), "bark", Color(0.8, 0.7, 0.6), 0.5)
		mm.mesh = k.commit()
		_stumps.multimesh = mm
		_stumps.material_override = BuildingLook.kit_material()
	var mm2 := _stumps.multimesh
	mm2.instance_count = _stump_pos.size()
	for i in _stump_pos.size():
		var p := _stump_pos[i]
		mm2.set_instance_transform(i, Transform3D(Basis(Vector3.UP, BattleRng.hash01(i * 13 + 7) * TAU), p))


## Жилы: стадия выработки по запасу; изменилась — новый узел
func _sync_deposits() -> void:
	var nt := query.nodes()
	if _stage.size() < nt.hw:
		var old := _stage.size()
		_stage.resize(nt.hw)
		_node.resize(nt.hw)
		for n in range(old, nt.hw):
			_stage[n] = -1
	for n in nt.hw:
		var ty := nt.ntype[n]
		if ty < 0 or defs.n_scatter_kind[ty] >= 0:
			if _node[n]:
				_node[n].queue_free()
				_node[n] = null
				_stage[n] = -1
			continue
		var full := defs.n_amount_milli[ty]
		var amt := nt.amount_milli[n]
		var st := stage_of(amt, full)
		if st == _stage[n]:
			continue
		_stage[n] = st
		if _node[n]:
			_node[n].queue_free()
		var node := _deposit(ty, st, n)
		node.position = Vector3(nt.x[n], Terrain.height_at(nt.x[n], nt.z[n]), nt.z[n])
		add_child(node)
		_node[n] = node


## Стадия выработки: 3 — полная (> 2/3), 2 — наполовину, 1 — остатки, 0 — выработана
static func stage_of(amount_milli: int, full_milli: int) -> int:
	if amount_milli < 0:
		return 3
	if amount_milli == 0:
		return 0
	if full_milli <= 0:
		return 3
	var k := float(amount_milli) / full_milli
	return 3 if k > 0.6667 else (2 if k > 0.3333 else 1)


func _deposit(ty: int, st: int, seed: int) -> Node3D:
	var scene := DEPOSIT_SCENE % defs.n_ids[ty]
	if ResourceLoader.exists(scene):
		# стадии арта: 0 — полное, 1 — половина, 2 — почти выработано; выработанное не видно
		var rd := (load(scene) as PackedScene).instantiate() as Node3D
		rd.set("stage", clampi(3 - st, 0, 2))
		rd.visible = st > 0
		rd.name = "Deposit"
		return rd
	var model := defs.n_model[ty]
	var suf := "" if st == 3 else "_s%d" % st
	var path := "res://assets/models/world/%s%s.glb" % [model, suf]
	if model != "" and st > 0 and ResourceLoader.exists(path):
		return BuildingLook.instance_model(path, 160.0, false)
	return _placeholder(defs.n_ids[ty] == "gold", st, seed)


## Заместитель жилы: валуны мира (rock_0..3) кучей, у золота — тёплые прожилки и самородки
func _placeholder(gold: bool, st: int, seed: int) -> Node3D:
	_load_rocks()
	var root := Node3D.new()
	root.name = "Deposit"
	var rng := BattleRng.new(seed * 31 + 5)
	var count: int = [0, 3, 6, 10][st]
	var scale: float = [0.0, 0.55, 0.8, 1.0][st]
	# валуны сливаются в один меш на материал (камень, золотая жила): мало вызовов отрисовки
	var tools: Array[SurfaceTool] = [SurfaceTool.new(), SurfaceTool.new()]
	var used := [false, false]
	for t in tools:
		t.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in count:
		var mesh: Mesh = _rock_meshes[rng.range_i(_rock_meshes.size())] if not _rock_meshes.is_empty() else BoxMesh.new()
		var which := 1 if gold and i % 3 == 0 else 0
		var a := rng.range_f(-PI, PI)
		var r := rng.range_f(0.0, 3.2) * scale
		var s := rng.range_f(0.7, 1.5) * scale * (1.4 if i == 0 else 1.0)
		var xf := Transform3D(Basis(Vector3.UP, rng.range_f(-PI, PI)).scaled(Vector3(s, s * rng.range_f(0.7, 1.2), s)),
			Vector3(sin(a) * r, -0.25 * s, cos(a) * r))
		for surf in mesh.get_surface_count():
			tools[which].append_from(mesh, surf, xf)
		used[which] = true
	for w in 2:
		if not used[w]:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = tools[w].commit()
		mi.material_override = _gold_mat if w == 1 else _rock_mat
		root.add_child(mi)
	# щебень и (у золота) самородки
	var k := BuildingLook.Kit.new()
	var n := 6 + st * 4
	for i in n:
		var a := rng.range_f(-PI, PI)
		var r := rng.range_f(1.5, 4.5)
		var s := rng.range_f(0.12, 0.3)
		var tint := Color(1.0, 0.8, 0.3) if gold and i % 2 == 0 else Color(0.85, 0.82, 0.8)
		k.box(Vector3(sin(a) * r, s * 0.5, cos(a) * r), Vector3(s, s * 0.6, s), "stones", tint, a)
	var gr := MeshInstance3D.new()
	gr.mesh = k.commit()
	gr.material_override = BuildingLook.kit_material()
	gr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(gr)
	return root


static func _load_rocks() -> void:
	if _rock_mat:
		return
	_rock_mat = ShaderMaterial.new()
	_rock_mat.shader = SURFACE
	_rock_mat.set_shader_parameter("albedo_tex", load(ROCK_TEX))
	_rock_mat.set_shader_parameter("albedo_tint", Color(0.66, 0.63, 0.6))
	_rock_mat.set_shader_parameter("use_vertex_color", true)
	_rock_mat.set_shader_parameter("rim_strength", 0.4)
	_gold_mat = _rock_mat.duplicate() as ShaderMaterial
	_gold_mat.set_shader_parameter("albedo_tint", Color(0.95, 0.78, 0.42))
	_gold_mat.set_shader_parameter("emission", Color(0.9, 0.62, 0.2))
	_gold_mat.set_shader_parameter("emission_energy", 0.12)
	for i in 4:
		var p := "res://assets/models/world/rock_%d.glb" % i
		if not ResourceLoader.exists(p):
			continue
		var n := (load(p) as PackedScene).instantiate()
		for c in n.find_children("*", "MeshInstance3D", true, false):
			_rock_meshes.append((c as MeshInstance3D).mesh)
			break
		n.free()
