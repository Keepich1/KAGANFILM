class_name DebugGhost
extends Node3D
## Запасной призрак постройки до GhostView (VIEW, I4): тот же API — show_building(btype, center, rot_q, cells),
## show_wall(plan), hide() (родной Node3D.hide). Полупрозрачная коробка по размеру из Defs: зелёная — можно, красная — нельзя;
## звенья стены — коробки по центрам плана.

var defs: Defs
var _boxes: Array[MeshInstance3D] = []
var _ok_mat: StandardMaterial3D
var _bad_mat: StandardMaterial3D


func _ready() -> void:
	if defs == null:
		defs = Defs.shared()
	_ok_mat = _mat(Color(0.35, 0.9, 0.45, 0.38))
	_bad_mat = _mat(Color(0.95, 0.25, 0.2, 0.42))


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func show_building(btype: int, center: Vector2, rot_q: int, cells: PackedByteArray) -> void:
	var ok := true
	for w in cells:
		if w != NavApi.Why.OK:
			ok = false
			break
	var sz := defs.b_size[btype]
	_use(1)
	_place(_boxes[0], center, Vector3(sz.x, 3.0, sz.y), rot_q * PI * 0.5, ok)


func show_wall(plan: Dictionary) -> void:
	var centers: PackedVector2Array = plan.get("centers", PackedVector2Array())
	var rots: PackedFloat32Array = plan.get("rots", PackedFloat32Array())
	var whys: PackedByteArray = plan.get("why", PackedByteArray())
	_use(centers.size())
	for i in centers.size():
		var r := rots[i] if i < rots.size() else 0.0
		var ok := i >= whys.size() or whys[i] == NavApi.Why.OK
		_place(_boxes[i], centers[i], Vector3(3.4, 3.5, 1.6), r, ok)


## hide() — родной Node3D.hide(): призрак прячется целиком (тот же API, что у GhostView)


func _use(n: int) -> void:
	show()
	while _boxes.size() < n:
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_boxes.append(mi)
	for i in _boxes.size():
		_boxes[i].visible = i < n


func _place(mi: MeshInstance3D, c: Vector2, size: Vector3, yaw: float, ok: bool) -> void:
	(mi.mesh as BoxMesh).size = size
	mi.material_override = _ok_mat if ok else _bad_mat
	mi.position = Vector3(c.x, Terrain.height_at(c.x, c.y) + size.y * 0.5, c.y)
	mi.rotation = Vector3(0, -yaw, 0)
