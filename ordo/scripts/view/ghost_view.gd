class_name GhostView
extends Node3D
## Призрак расстановки (ARCHITECTURE §13): полупрозрачная модель постройки цвета решения + клетки следа
## по ответу NavApi.place_cells (зелёная — можно, красная — нельзя), цепочка звеньев стены по plan_wall.
## API для UI (PlacementMode, ARCHITECTURE §13):
##   ghost.show_building(btype, center, rot_q, cells)   cells — PackedByteArray Why по клеткам следа
##   ghost.show_wall(plan)                               plan — GameQuery.plan_wall(...); звенья — модель
##                                                       стены, которую UI показал последней через
##                                                       show_building (PlacementMode так и делает до
##                                                       первой точки); можно и явно: show_wall(plan, wtype)
##   ghost.hide()                                        спрятать (Node3D.hide: сбрасывает и состояние)
## Дополнительно (не в договоре): hide_ghost() — то же, что hide(), но узел остаётся видимым.
## Модель — та же, что у BuildingView (BuildingLook), материал — shaders/view/ghost.gdshader.

const GHOST := preload("res://shaders/view/ghost.gdshader")
const CELLS := preload("res://shaders/view/ground_cells.gdshader")
const OK_COL := Color(0.36, 0.95, 0.52)
const BAD_COL := Color(1.0, 0.3, 0.22)
const CELL_OK := Color(0.4, 1.0, 0.55, 0.85)
const CELL_BAD := Color(1.0, 0.28, 0.2, 0.9)

@export var driver_path: NodePath = ^"../../Driver"

var query: GameQuery
var defs: Defs
## Что показано: -1 ничего, иначе тип постройки (стена — тип звена)
var shown_btype := -1
var shown_ok := false

var _model: Node3D
var _model_btype := -1
var _cells: MultiMeshInstance3D
var _links: MultiMeshInstance3D
var _mat: ShaderMaterial
var _mat_links: ShaderMaterial
## Тип стены/звена, показанный последним (show_wall(plan) без типа рисует его)
var _wall_btype := -1


func _ready() -> void:
	var d := get_node_or_null(driver_path)
	if d and d.has_signal("started"):
		d.connect("started", func(_s: int) -> void: set_query(CityView.query_of(d)))
	if CityView.query_of(d):
		set_query(CityView.query_of(d))
	_build()
	hide_ghost()


## Узлы призрака (создаются один раз; тесты зовут show_* без дерева сцены)
func _build() -> void:
	if _cells:
		return
	_mat = ShaderMaterial.new()
	_mat.shader = GHOST
	_mat.render_priority = 1
	_mat_links = _mat.duplicate() as ShaderMaterial
	_mat_links.set_shader_parameter("per_instance", true)
	var cm := ShaderMaterial.new()
	cm.shader = CELLS
	cm.render_priority = 1
	var q := QuadMesh.new()
	q.size = Vector2(NavApi.CELL - 0.15, NavApi.CELL - 0.15)
	q.orientation = PlaneMesh.FACE_Y
	q.material = cm
	_cells = MultiMeshInstance3D.new()
	_cells.name = "Cells"
	_cells.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = q
	_cells.multimesh = mm
	add_child(_cells)
	_links = MultiMeshInstance3D.new()
	_links.name = "Links"
	_links.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_links.material_override = _mat_links
	add_child(_links)


func set_query(q: GameQuery) -> void:
	query = q
	defs = q.defs() if q else null


## Призрак постройки: модель в center с поворотом rot_q и клетки следа (Why по клеткам, по строкам)
func show_building(btype: int, center: Vector2, rot_q: int, cells: PackedByteArray) -> void:
	if defs == null:
		return
	_build()
	visible = true
	_links.visible = false
	var ok := true
	for w in cells:
		if w != NavApi.Why.OK:
			ok = false
			break
	shown_btype = btype
	shown_ok = ok
	if _is_wall(btype):
		_wall_btype = btype
	if _model_btype != btype:
		if _model:
			_model.queue_free()
		_model = _make_model(btype)
		_model_btype = btype
		add_child(_model)
	var yaw := rot_q * PI * 0.5
	_model.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(center.x, Terrain.height_at(center.x, center.y) + 0.05, center.y))
	_model.visible = true
	for g in _model.find_children("*", "GeometryInstance3D", true, false) + ([_model] if _model is GeometryInstance3D else []):
		(g as GeometryInstance3D).set_instance_shader_parameter("ghost_col", OK_COL if ok else BAD_COL)
	# клетки следа
	var r := NavApi.footprint(defs, btype, center, rot_q, Terrain.origin())
	var mm := _cells.multimesh
	mm.instance_count = r.size.x * r.size.y
	var o := Terrain.origin()
	var i := 0
	for row in range(r.position.y, r.end.y):
		for col in range(r.position.x, r.end.x):
			var c := o + Vector2(col + 0.5, row + 0.5) * NavApi.CELL
			var why := cells[i] if i < cells.size() else NavApi.Why.OK
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(c.x, _cell_y(c), c.y)))
			mm.set_instance_color(i, CELL_OK if why == NavApi.Why.OK else CELL_BAD)
			i += 1
	_cells.visible = true


## Призрак стены: звенья по plan_wall (centers, rots, why), каждое своего цвета.
## keep_building — не прятать призрак постройки (башня/ворота на стене вместе с цепочкой)
func show_wall(plan: Dictionary, wtype := -1, keep_building := false) -> void:
	if defs == null or plan.is_empty():
		return
	_build()
	if wtype < 0:
		wtype = _wall_btype if _wall_btype >= 0 else _first_wall()
	elif _is_wall(wtype):
		_wall_btype = wtype
	visible = true
	if not keep_building:
		if _model:
			_model.visible = false
		_cells.visible = false
	var centers: PackedVector2Array = plan.get("centers", PackedVector2Array())
	var rots: PackedFloat32Array = plan.get("rots", PackedFloat32Array())
	var why: PackedByteArray = plan.get("why", PackedByteArray())
	# части модели звена (glb — несколько мешей; заместитель — один), у каждой свой MultiMesh:
	# первая — в Links, остальные — дочерние Links/Part<k>
	var parts: Array = BuildingLook.parts_for(defs, wtype, 0) if wtype >= 0 else []
	if parts.is_empty():
		var bm := BoxMesh.new()
		bm.size = Vector3(3.6, 4.0, 1.8)
		parts = [{"mesh": bm, "xform": Transform3D(Basis(), Vector3(0, 2, 0))}]
	var base: Array[Transform3D] = []
	var cols := PackedColorArray()
	shown_ok = shown_ok if keep_building else true
	for i in centers.size():
		var c := centers[i]
		var ok := i >= why.size() or why[i] == NavApi.Why.OK
		shown_ok = shown_ok and ok
		var rot := rots[i] if i < rots.size() else 0.0
		base.append(Transform3D(Basis(Vector3.UP, rot), Vector3(c.x, Terrain.height_at(c.x, c.y), c.y)))
		cols.append(OK_COL if ok else BAD_COL)
	for k in parts.size():
		var p: Dictionary = parts[k]
		var px: Transform3D = p.xform
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = p.mesh
		mm.instance_count = base.size()
		for i in base.size():
			mm.set_instance_transform(i, base[i] * px)
			mm.set_instance_color(i, cols[i])
		var mi := _links if k == 0 else _links.get_node_or_null("Part%d" % k) as MultiMeshInstance3D
		if mi == null:
			mi = MultiMeshInstance3D.new()
			mi.name = "Part%d" % k
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.material_override = _mat_links
			_links.add_child(mi)
		mi.multimesh = mm
		mi.visible = true
	for c in _links.get_children():
		if int(String(c.name).trim_prefix("Part")) >= parts.size():
			(c as Node3D).visible = false
	_links.visible = true
	if not keep_building:
		shown_btype = wtype


## Тип — стена или звено (его рисует цепочка show_wall)
func _is_wall(btype: int) -> bool:
	if defs == null or btype < 0:
		return false
	var k := defs.b_kind[btype]
	return k == Defs.BKind.WALL or k == Defs.BKind.LINK


## Запасной тип звена, если UI ещё не показывал стену: первая стена в описаниях
func _first_wall() -> int:
	for t in defs.b_ids.size():
		if defs.b_kind[t] == Defs.BKind.WALL:
			return t
	return -1


## hide() (Node3D) из UI: спрятан узел — сбросить и состояние призрака
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible and shown_btype != -1:
		hide_ghost()


func hide_ghost() -> void:
	shown_btype = -1
	if _model:
		_model.visible = false
	if _cells:
		_cells.visible = false
	if _links:
		_links.visible = false


func _make_model(btype: int) -> Node3D:
	var path := BuildingLook.model_path(defs, btype, BuildingTable.State.ACTIVE)
	var n: Node3D
	if path != "":
		n = BuildingLook.instance_model(path, 0.0, false)
		BuildingLook.pick_variant(n, 1)
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = BuildingLook.mesh_for(defs, btype)
		n = mi
	for g in n.find_children("*", "GeometryInstance3D", true, false) + ([n] if n is GeometryInstance3D else []):
		var gi := g as GeometryInstance3D
		gi.material_override = _mat
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for p in n.find_children("*", "GPUParticles3D", true, false):
		p.queue_free()
	n.name = "Model"
	return n


func _cell_y(c: Vector2) -> float:
	var h := Terrain.height_at(c.x, c.y)
	for k in 4:
		var d := Vector2(1.6 if k % 2 == 0 else -1.6, 1.6 if k < 2 else -1.6)
		h = maxf(h, Terrain.height_at(c.x + d.x, c.y + d.y))
	return h + 0.06
