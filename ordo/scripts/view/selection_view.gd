class_name SelectionView
extends Node3D
## Выделение на земле (ARCHITECTURE §13): читает SelectionModel (описатели).
##   юниты — кольцо цвета стороны под каждым (ui_ring.gdshader; раненый краснеет);
##   постройка — рамка по следу (sel_frame.gdshader) и флаг места сбора (kipchak/tug.glb);
##   узел и стадо — кольцо по месту.
## Таблички (название, здоровье, мораль) рисует OverlayView. PerfMeter «view_select».

const RING_SHADER := preload("res://shaders/fx/ui_ring.gdshader")
const FRAME_SHADER := preload("res://shaders/view/sel_frame.gdshader")
const SIDE_LIGHT := [Color("#2fe0c0"), Color("#ff5a3c"), Color("#e8c050"), Color("#9a8cff")]
const WOUNDED := Color(1.0, 0.25, 0.18)
const NEUTRAL := Color(0.95, 0.88, 0.6)
const FLAG_MODEL := "res://assets/models/kipchak/tug.glb"
const MAX_FRAMES := 8

@export var driver_path: NodePath = ^"../../Driver"

var query: GameQuery
var defs: Defs
## Модель выделения (сцена ставит; после I4 — от RtsInput)
var selection: SelectionModel

var _mm: MultiMesh
var _frames: Array[MeshInstance3D] = []
var _flag: Node3D
var _radius := {}


func _ready() -> void:
	var d := get_node_or_null(driver_path)
	if d and d.has_signal("started"):
		d.connect("started", func(_s: int) -> void: set_query(CityView.query_of(d)))
	if CityView.query_of(d):
		set_query(CityView.query_of(d))
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.orientation = PlaneMesh.FACE_Y
	var m := ShaderMaterial.new()
	m.shader = RING_SHADER
	m.render_priority = 2
	q.material = m
	_mm.mesh = q
	_mm.instance_count = 512
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Rings"
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	var fm := ShaderMaterial.new()
	fm.shader = FRAME_SHADER
	fm.render_priority = 2
	for i in MAX_FRAMES:
		var f := MeshInstance3D.new()
		f.name = "Frame%d" % i
		var pm := PlaneMesh.new()
		pm.size = Vector2(1, 1)
		pm.subdivide_width = 6
		pm.subdivide_depth = 6
		f.mesh = pm
		f.material_override = fm
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.visible = false
		add_child(f)
		_frames.append(f)
	if ResourceLoader.exists(FLAG_MODEL):
		_flag = BuildingLook.instance_model(FLAG_MODEL, 0.0, false)
	else:
		_flag = BuildingLook.box(Vector3(0.2, 4.0, 0.2), Color(0.8, 0.3, 0.2))
	_flag.name = "RallyFlag"
	_flag.visible = false
	add_child(_flag)


func set_query(q: GameQuery) -> void:
	query = q
	defs = q.defs() if q else null


func _process(_delta: float) -> void:
	if query == null or selection == null:
		return
	var t0 := Time.get_ticks_usec()
	_update()
	CityView.mark(&"view_select", t0)


func _update() -> void:
	var sim := query.battle()
	var bt := query.buildings()
	var nt := query.nodes()
	var ht := query.herds()
	var n := 0
	var fi := 0
	var flag := false
	var cap := _mm.instance_count
	for h in selection.selected:
		match Ids.kind(h):
			Ids.Kind.UNIT:
				if sim == null:
					continue
				var u := query.unit_index(h)
				if u < 0 or sim.u_life[u] != BattleSim.Life.ALIVE:
					continue
				if n >= cap:
					cap *= 2
					_grow(cap)
				var x := sim.u_x[u]
				var z := sim.u_z[u]
				var r := _unit_radius(sim, u) * 2.0 + 0.5
				var hp := sim.u_hp[u] / maxf(sim.t_hp[sim.u_type[u]], 1.0)
				var col: Color = SIDE_LIGHT[clampi(sim.u_side[u], 0, 3)]
				col = WOUNDED.lerp(col, clampf(hp * 1.4 - 0.2, 0.0, 1.0))
				_mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(r, 1, r)), Vector3(x, Terrain.height_at(x, z) + 0.08, z)))
				_mm.set_instance_color(n, col)
				n += 1
			Ids.Kind.BUILDING:
				if not bt.valid(h) or fi >= MAX_FRAMES:
					continue
				var b := bt.slot(h)
				var sz := defs.b_size[bt.btype[b]] + Vector2(2.0, 2.0)
				var f := _frames[fi]
				fi += 1
				var y := Terrain.height_at(bt.x[b], bt.z[b])
				for k in 4:
					var c := Vector2(sz.x * (0.5 if k % 2 == 0 else -0.5), sz.y * (0.5 if k < 2 else -0.5)).rotated(-bt.rot[b])
					y = maxf(y, Terrain.height_at(bt.x[b] + c.x, bt.z[b] + c.y))
				y += 0.15
				f.transform = Transform3D(Basis(Vector3.UP, bt.rot[b]).scaled(Vector3(sz.x, 1, sz.y)), Vector3(bt.x[b], y, bt.z[b]))
				f.set_instance_shader_parameter("size", sz)
				f.set_instance_shader_parameter("frame_col", SIDE_LIGHT[clampi(bt.team[b], 0, 3)])
				f.visible = true
				if not defs.b_trains[bt.btype[b]].is_empty() and not flag:
					var rx := bt.rally_x[b]
					var rz := bt.rally_z[b]
					_flag.position = Vector3(rx, Terrain.height_at(rx, rz), rz)
					flag = true
			Ids.Kind.NODE:
				if not nt.valid(h) or n >= cap:
					continue
				var s := nt.slot(h)
				_mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(7, 1, 7)),
					Vector3(nt.x[s], Terrain.height_at(nt.x[s], nt.z[s]) + 0.1, nt.z[s])))
				_mm.set_instance_color(n, NEUTRAL)
				n += 1
			Ids.Kind.HERD:
				if not ht.valid(h) or n >= cap:
					continue
				var s := ht.slot(h)
				var r := ht.graze_r[s] * 2.0
				_mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(r, 1, r)),
					Vector3(ht.x[s], Terrain.height_at(ht.x[s], ht.z[s]) + 0.1, ht.z[s])))
				_mm.set_instance_color(n, NEUTRAL)
				n += 1
	_mm.visible_instance_count = n
	for i in range(fi, MAX_FRAMES):
		_frames[i].visible = false
	_flag.visible = flag


func _grow(cap: int) -> void:
	var old := _mm.instance_count
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	for i in old:
		xf.append(_mm.get_instance_transform(i))
		cols.append(_mm.get_instance_color(i))
	_mm.visible_instance_count = -1
	_mm.instance_count = cap
	for i in old:
		_mm.set_instance_transform(i, xf[i])
		_mm.set_instance_color(i, cols[i])


func _unit_radius(sim: BattleSim, u: int) -> float:
	var t := sim.u_type[u]
	if not _radius.has(t):
		_radius[t] = float(UnitStats.get_stats(sim.type_ids[t]).get("radius", 0.4))
	return _radius[t]
