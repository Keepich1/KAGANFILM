class_name GrassField
extends Node3D
## Степная трава и ковыль (ТЗ 11.1, 11.4): пучки на видеокарте.
##
## Каждый участок — MultiMeshInstance3D с общим MultiMesh (все экземпляры в начале
## координат). Где именно стоит пучок, считает вершинный шейдер (shaders/grass.gdshader)
## по номеру экземпляра и положению участка: высота — из текстуры высот, густота, рост
## и доля ковыля — из карты assets/textures/world/grass.png. Процессор только двигает
## сетку участков за камерой. Два кольца: ближнее густое и дальнее редкое (крупнее).
##
##   grass.set_clearings([Vector3(x, z, радиус), ...])  — убрать траву под юртами и т. п.
##   grass.density_scale = 0.4                            — меньше травы («Низкое» качество)

const SHADER := preload("res://shaders/grass.gdshader")
const MAX_CLEARINGS := 48

## Кольца: размер участка (м), участков по стороне, пучков на участок, сложность пучка,
## множитель роста и дальности видимости от камеры (м): [начало, конец]
@export var rings: Array[Dictionary] = [
	{"patch": 12.0, "count": 12, "instances": 420, "detail": 1, "scale": 1.0, "fade": Vector4(-1.0, 0.0, 60.0, 80.0)},
	{"patch": 24.0, "count": 12, "instances": 600, "detail": 0, "scale": 1.7, "fade": Vector4(60.0, 80.0, 190.0, 250.0)},
]
## Доля пучков (качество «Низкое» — меньше)
@export_range(0.05, 1.0) var density_scale := 1.0:
	set(v):
		density_scale = v
		_update_density()
## Дальность травы (качество «Низкое» — ближе)
@export_range(0.2, 1.0) var range_scale := 1.0:
	set(v):
		range_scale = v
		_update_density()

var material: ShaderMaterial
var _rings: Array = []           # [{root, patches: Array[MultiMeshInstance3D], center: Vector2i, cfg}]
var _clearings := PackedVector4Array()


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("height_tex", Terrain.height_texture())
	material.set_shader_parameter("grass_map", load("res://assets/textures/world/grass.png"))
	material.set_shader_parameter("splat_map", load("res://assets/textures/world/splat.png"))
	var o := Terrain.origin()
	material.set_shader_parameter("height_origin", o)
	material.set_shader_parameter("height_size", float(Terrain.size()))
	material.set_shader_parameter("height_spacing", Terrain.spacing())
	set_clearings([])
	for cfg in rings:
		_rings.append(_make_ring(cfg))
	_update_density()


func set_clearings(list: Array) -> void:
	_clearings.resize(MAX_CLEARINGS)
	for i in MAX_CLEARINGS:
		if i < list.size():
			var c: Vector3 = list[i]
			_clearings[i] = Vector4(c.x, c.y, c.z, 1.0)
		else:
			_clearings[i] = Vector4(0, 0, -1, 0)
	if material:
		material.set_shader_parameter("clearings", _clearings)
		material.set_shader_parameter("clearing_count", mini(list.size(), MAX_CLEARINGS))


## Материалы колец (у каждого кольца свой — разные размеры участков).
func ring_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for r in _rings:
		out.append(r.material)
	return out


func _update_density() -> void:
	for r in _rings:
		var cfg: Dictionary = r.cfg
		var mm: MultiMesh = r.multimesh
		mm.visible_instance_count = maxi(1, int(cfg.instances * density_scale))
		var mat: ShaderMaterial = r.material
		var f: Vector4 = cfg.fade
		mat.set_shader_parameter("fade", Vector4(f.x * range_scale, f.y * range_scale, f.z * range_scale, f.w * range_scale))
		mat.set_shader_parameter("density_comp", 1.0 / sqrt(density_scale))


func _make_ring(cfg: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = "Ring%d" % _rings.size()
	add_child(root)
	var mesh := GrassClump.build(int(cfg.detail), 7 + _rings.size())
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = int(cfg.instances)
	var buf := PackedFloat32Array()
	buf.resize(12 * int(cfg.instances))
	for i in int(cfg.instances):
		buf[i * 12 + 0] = 1.0
		buf[i * 12 + 5] = 1.0
		buf[i * 12 + 10] = 1.0
	mm.buffer = buf
	var mat: ShaderMaterial = material.duplicate()
	mat.set_shader_parameter("patch_size", float(cfg.patch))
	mat.set_shader_parameter("grid_n", int(ceil(sqrt(float(cfg.instances)))))
	mat.set_shader_parameter("clump_scale", float(cfg.scale))
	var patches: Array[MultiMeshInstance3D] = []
	var n := int(cfg.count)
	for k in n * n:
		var p := MultiMeshInstance3D.new()
		p.multimesh = mm
		p.material_override = mat
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visible = false
		root.add_child(p)
		patches.append(p)
	return {"root": root, "patches": patches, "center": Vector2i(1 << 30, 0), "cfg": cfg,
		"multimesh": mm, "material": mat}


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var focus := _focus(cam)
	var cp := cam.global_position
	for r in _rings:
		var size: float = r.cfg.patch
		var c := Vector2i(floori(focus.x / size), floori(focus.y / size))
		if c != r.center:
			r.center = c
			_place_ring(r)
		_cull_ring(r, cp)


## Участки, целиком дальше конца кольца или ближе его начала, не рисуем вовсе
## (иначе видеокарта зря считает вершины пучков, сжатых в точку).
func _cull_ring(r: Dictionary, cp: Vector3) -> void:
	var f: Vector4 = r.cfg.fade
	var near := f.x * range_scale
	var far := f.w * range_scale
	for p: MultiMeshInstance3D in r.patches:
		if not p.get_meta("in_map", false):
			continue
		var box := p.custom_aabb
		var lo := p.position + box.position
		var hi := lo + box.size
		var q := cp.clamp(lo, hi)
		var dmin := cp.distance_to(q)
		var dmax := 0.0
		for corner in [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z)]:
			dmax = maxf(dmax, cp.distance_to(corner))
		p.visible = dmin < far and dmax > near


## Точка интереса: куда смотрит камера на земле (или чуть впереди камеры).
func _focus(cam: Camera3D) -> Vector2:
	var p := cam.global_position
	var fwd := -cam.global_basis.z
	var flat := Vector2(fwd.x, fwd.z)
	if flat.length() < 0.01:
		return Vector2(p.x, p.z)
	flat = flat.normalized()
	var ground := Terrain.height_at(p.x, p.z)
	var dist := 70.0
	if fwd.y < -0.05:
		dist = clampf((p.y - ground) / -fwd.y * sqrt(1.0 - fwd.y * fwd.y), 10.0, 160.0)
	return Vector2(p.x, p.z) + flat * dist


func _place_ring(r: Dictionary) -> void:
	var size: float = r.cfg.patch
	var n: int = r.cfg.count
	var c: Vector2i = r.center
	var half := Terrain.origin().x
	var k := 0
	for j in n:
		for i in n:
			var p: MultiMeshInstance3D = r.patches[k]
			k += 1
			var gx := float(c.x - n / 2 + i) * size
			var gz := float(c.y - n / 2 + j) * size
			# half = −512: участок целиком за краем карты
			if gx + size < half or gz + size < half or gx > -half or gz > -half:
				p.visible = false
				p.set_meta("in_map", false)
				continue
			p.set_meta("in_map", true)
			var lo := INF
			var hi := -INF
			for b in 3:
				for a in 3:
					var h := Terrain.height_at(gx + a * size * 0.5, gz + b * size * 0.5)
					lo = minf(lo, h)
					hi = maxf(hi, h)
			p.position = Vector3(gx, 0.0, gz)
			p.custom_aabb = AABB(Vector3(-1.0, lo - 2.0, -1.0), Vector3(size + 2.0, hi - lo + 5.0, size + 2.0))
			p.visible = true
