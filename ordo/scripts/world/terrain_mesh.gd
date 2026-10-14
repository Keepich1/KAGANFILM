class_name TerrainMesh
extends Node3D
## Земля среза: дерево кусков (HLOD). Вблизи — куски 128 × 128 м с шагом сетки 2 м, дальше —
## блоки 256 м (шаг 4 м), ещё дальше — 512 м (шаг 8 м); у каждого куска одна сетка 64 × 64 клетки.
## Блок, к центру которого камера ближе его дальности, прячется, и вместо него видны его четыре
## куска помельче (visibility_parent — движок решает сам, без щелей и двойного покрытия).
## Дальности подобраны так, что каждая точка земли не грубее прежних уровней 2/4/8 м
## (220 и 500 м × lod_scale), а вызовов отрисовки (и в каждом каскаде теней) в разы меньше,
## чем у прежних 256 кусков по 64 м (ближняя земля подробная чуть дальше, чем раньше).
## Швы между уровнями закрыты «юбками». Вокруг карты — дальнее кольцо гор (far.bin, шаг 32 м)
## до ±2,5 км. Плюс тело столкновений (HeightMapShape3D) для выбора точки мышью.

const SHADER := preload("res://shaders/terrain.gdshader")

## Сторона самого подробного куска, м (блоки уровней — вдвое и вчетверо больше)
@export var chunk_size := 128.0
## Дальше какой дальности земля может стать грубее: 2 м → 4 м, 4 м → 8 м (последнее — без предела).
## Дальность считается от центра блока, поэтому к ней прибавляется полдиагонали блока.
@export var lod_ranges: PackedFloat32Array = PackedFloat32Array([220.0, 500.0, 1100.0])
## Уровней дерева (2 м, 4 м, 8 м)
const LEVELS := 3
## Глубина «юбки» под краем куска, м
@export var skirt := 3.0
@export var build_far_ring := true
@export var build_collision := true
## Множитель дальностей (качество «Низкое» уменьшает)
@export var lod_scale := 1.0

var material: ShaderMaterial
var _lod_nodes: Array[MeshInstance3D] = []
var _normals := PackedVector3Array()


func _ready() -> void:
	build()


func build() -> void:
	for c in get_children():
		c.queue_free()
	_lod_nodes.clear()
	material = make_material()
	var n := Terrain.size()
	if n == 0:
		return
	_compute_normals()
	var cells := int(chunk_size / Terrain.spacing())     # клеток сетки на самый подробный кусок (64)
	var chunks_root := Node3D.new()
	chunks_root.name = "Chunks"
	add_child(chunks_root)
	var o := Terrain.origin()
	# от грубых к подробным: родитель (блок) создаётся раньше своих четырёх кусков
	var parents := {}
	for level in range(LEVELS - 1, -1, -1):
		var block := cells << level                     # клеток на сторону блока уровня
		var step := 1 << level
		var count := (n - 1) / block
		var size := chunk_size * float(1 << level)
		var next := {}
		for cj in count:
			for ci in count:
				var mi := MeshInstance3D.new()
				mi.name = "L%d_%d_%d" % [level, ci, cj]
				mi.mesh = _chunk_mesh(ci * block, cj * block, block, step)
				mi.material_override = material
				mi.position = Vector3(o.x + (ci + 0.5) * size, 0.0, o.y + (cj + 0.5) * size)
				mi.set_meta("lod", level)
				mi.set_meta("half_diag", size * 0.5 * sqrt(2.0))
				chunks_root.add_child(mi)
				var parent: MeshInstance3D = parents.get(Vector2i(ci / 2, cj / 2))
				if parent:
					mi.visibility_parent = mi.get_path_to(parent)
				next[Vector2i(ci, cj)] = mi
				_lod_nodes.append(mi)
		parents = next
	apply_lod_ranges()
	if build_far_ring:
		_build_far_ring()
	if build_collision:
		_build_collision()


## Новый материал земли с картами и текстурами из assets/textures/world/.
static func make_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var t := "res://assets/textures/world/"
	m.set_shader_parameter("splat_map", load(t + "splat.png"))
	m.set_shader_parameter("grass_map", load(t + "grass.png"))
	m.set_shader_parameter("tex_grass", load(t + "ground_grass.png"))
	m.set_shader_parameter("tex_dry", load(t + "ground_dry.png"))
	m.set_shader_parameter("tex_earth", load(t + "ground_earth.png"))
	m.set_shader_parameter("tex_rock", load(t + "ground_rock.png"))
	m.set_shader_parameter("tex_sand", load(t + "ground_sand.png"))
	m.set_shader_parameter("brush_tex", load(t + "brush_world.png"))
	m.set_shader_parameter("water_level", Terrain.water_level())
	return m


## Дальности дерева кусков: блок уровня L (L ≥ 1) прячется (и видны его куски помельче), когда
## камера ближе его центра на lod_ranges[L − 1] × lod_scale + полдиагонали блока. Полдиагонали
## без множителя: любая точка блока ближе к его центру, поэтому земля нигде не грубее прежних
## кусков 64 м на любом уровне качества (tests/test_quality.gd проверяет по сетке положений камеры).
## Самые грубые блоки без родителя видны всегда, пока их не сменили куски помельче.
func apply_lod_ranges() -> void:
	for mi in _lod_nodes:
		var lod: int = mi.get_meta("lod")
		mi.visibility_range_end = 0.0
		mi.visibility_range_begin_margin = 0.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if lod == 0:
			mi.visibility_range_begin = 0.0
		else:
			mi.visibility_range_begin = lod_ranges[mini(lod - 1, lod_ranges.size() - 1)] * lod_scale \
				+ float(mi.get_meta("half_diag"))


## Куски дерева (для проверок): все уровни, у каждого meta «lod» и «half_diag»
func lod_nodes() -> Array[MeshInstance3D]:
	return _lod_nodes


func _compute_normals() -> void:
	var n := Terrain.size()
	var h := Terrain.heights()
	var s := Terrain.spacing()
	_normals.resize(n * n)
	for j in n:
		var jn := maxi(j - 1, 0)
		var js := mini(j + 1, n - 1)
		for i in n:
			var iw := maxi(i - 1, 0)
			var ie := mini(i + 1, n - 1)
			var dx := (h[j * n + ie] - h[j * n + iw]) / ((ie - iw) * s)
			var dz := (h[js * n + i] - h[jn * n + i]) / ((js - jn) * s)
			_normals[j * n + i] = Vector3(-dx, 1.0, -dz).normalized()


## Сетка одного куска: узлы (i0..i0+cells) с шагом step + юбка по краю.
func _chunk_mesh(i0: int, j0: int, cells: int, step: int) -> ArrayMesh:
	var n := Terrain.size()
	var h := Terrain.heights()
	var s := Terrain.spacing()
	var q := cells / step
	var row := q + 1
	var half := cells * s * 0.5
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(row * row)
	norms.resize(row * row)
	for b in row:
		for a in row:
			var gi := i0 + a * step
			var gj := j0 + b * step
			var k := gj * n + gi
			verts[b * row + a] = Vector3(a * step * s - half, h[k], b * step * s - half)
			norms[b * row + a] = _normals[k]
	var idx := PackedInt32Array()
	idx.resize(q * q * 6)
	var w := 0
	for b in q:
		for a in q:
			var p := b * row + a
			# диагональ чередуется — меньше заметна «ёлочка»
			if (a + b) % 2 == 0:
				idx[w] = p; idx[w + 1] = p + 1; idx[w + 2] = p + row + 1
				idx[w + 3] = p; idx[w + 4] = p + row + 1; idx[w + 5] = p + row
			else:
				idx[w] = p; idx[w + 1] = p + 1; idx[w + 2] = p + row
				idx[w + 3] = p + 1; idx[w + 4] = p + row + 1; idx[w + 5] = p + row
			w += 6
	# юбка: обход края против часовой (вид сверху), опущенные копии вершин
	var ring := PackedInt32Array()
	for a in row:
		ring.append(a)                       # север (b = 0), запад → восток
	for b in range(1, row):
		ring.append(b * row + q)             # восток, север → юг
	for a in range(q - 1, -1, -1):
		ring.append(q * row + a)             # юг, восток → запад
	for b in range(q - 1, 0, -1):
		ring.append(b * row)                 # запад, юг → север
	var drop := skirt * step
	var base := verts.size()
	for r in ring.size():
		var v := verts[ring[r]]
		verts.append(Vector3(v.x, v.y - drop, v.z))
		norms.append(norms[ring[r]])
	var m := ring.size()
	for r in m:
		var t0 := ring[r]
		var t1 := ring[(r + 1) % m]
		var b0 := base + r
		var b1 := base + (r + 1) % m
		# наружу смотрящая стенка (видна снаружи куска)
		idx.append_array(PackedInt32Array([t0, b0, t1, t1, b0, b1]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Дальнее кольцо гор за краем карты (до ±2,5 км), шаг 32 м.
func _build_far_ring() -> void:
	var info := Terrain.info()
	var fh := Terrain.read_floats(String(info.get("files", {}).get("far", "far.bin")))
	var fn := int(info.get("far_size", 0))
	if fh.size() != fn * fn or fn == 0:
		return
	var fs := float(info.get("far_spacing", 32.0))
	var fo: Array = info.get("far_origin", [-2560.0, -2560.0])
	var half := -Terrain.origin().x
	# нормали дальнего кольца
	var fnorm := PackedVector3Array()
	fnorm.resize(fn * fn)
	# сглаженные (по соседям ±1 и ±2 клетки): свет ложится по форме хребта, а не по граням сетки
	for j in fn:
		for i in fn:
			var dx1 := (fh[j * fn + mini(i + 1, fn - 1)] - fh[j * fn + maxi(i - 1, 0)]) / (2.0 * fs)
			var dz1 := (fh[mini(j + 1, fn - 1) * fn + i] - fh[maxi(j - 1, 0) * fn + i]) / (2.0 * fs)
			var dx2 := (fh[j * fn + mini(i + 2, fn - 1)] - fh[j * fn + maxi(i - 2, 0)]) / (4.0 * fs)
			var dz2 := (fh[mini(j + 2, fn - 1) * fn + i] - fh[maxi(j - 2, 0) * fn + i]) / (4.0 * fs)
			fnorm[j * fn + i] = Vector3(-(dx1 + dx2 * 2.0) / 3.0, 1.0, -(dz1 + dz2 * 2.0) / 3.0).normalized()
	# 4 части (север, юг, запад, восток) — для отсечения по видимости
	var parts := {"FarN": [], "FarS": [], "FarW": [], "FarE": []}
	for j in fn - 1:
		for i in fn - 1:
			var x0: float = fo[0] + i * fs
			var z0: float = fo[1] + j * fs
			var x1 := x0 + fs
			var z1 := z0 + fs
			# клетки целиком внутри карты (с запасом в одну клетку) не нужны
			if x0 >= -half + fs and x1 <= half - fs and z0 >= -half + fs and z1 <= half - fs:
				continue
			var cx := (x0 + x1) * 0.5
			var cz := (z0 + z1) * 0.5
			var key := "FarN" if cz < -absf(cx) else ("FarS" if cz > absf(cx) else ("FarW" if cx < 0 else "FarE"))
			(parts[key] as Array).append(Vector2i(i, j))
	for key in parts:
		var cells: Array = parts[key]
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var idx := PackedInt32Array()
		var map := {}
		for c: Vector2i in cells:
			var corners := [Vector2i(c.x, c.y), Vector2i(c.x + 1, c.y), Vector2i(c.x + 1, c.y + 1), Vector2i(c.x, c.y + 1)]
			var ids := []
			for g: Vector2i in corners:
				if not map.has(g):
					var x: float = fo[0] + g.x * fs
					var z: float = fo[1] + g.y * fs
					var y := fh[g.y * fn + g.x]
					# внутри карты кольцо прячется под основной землёй
					if absf(x) < half - 1.0 and absf(z) < half - 1.0:
						y -= 2.5
					map[g] = verts.size()
					verts.append(Vector3(x, y, z))
					norms.append(fnorm[g.y * fn + g.x])
				ids.append(map[g])
			idx.append_array(PackedInt32Array([ids[0], ids[1], ids[2], ids[0], ids[2], ids[3]]))
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.name = key
		mi.mesh = mesh
		mi.material_override = material
		add_child(mi)


func _build_collision() -> void:
	var n := Terrain.size()
	var s := Terrain.spacing()
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	# фигура масштабируется равномерно на шаг сетки, поэтому высоты делим на шаг
	var data := Terrain.heights().duplicate()
	for k in data.size():
		data[k] /= s
	shape.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(s, s, s)
	var o := Terrain.origin()
	cs.position = Vector3(o.x + (n - 1) * s * 0.5, 0.0, o.y + (n - 1) * s * 0.5)
	body.add_child(cs)
	add_child(body)
