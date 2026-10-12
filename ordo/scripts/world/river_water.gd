class_name RiverWater
extends MeshInstance3D
## Вода реки: сетка на уровне воды только над руслом (клетки 4 м, где земля ниже уровня
## воды + запас) и продолжение реки в ущельях за краем карты. В цвете вершин — направление
## течения (rg) и скорость (b): быстрее на стремнине и на перекате у брода.
## Шейдер — shaders/water.gdshader.

const SHADER := preload("res://shaders/water.gdshader")
const CELL := 4.0

## Как далеко за край карты тянуть реку, м
@export var beyond_edge := 420.0


func _ready() -> void:
	build()


func build() -> void:
	var wl := Terrain.water_level()
	var info := Terrain.info()
	var river: Array = info.get("river", [])
	if river.is_empty():
		return
	var ford: Array = info.get("ford", [20.0, -157.0])
	var half := -Terrain.origin().x
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var map := {}
	var x0 := -half - beyond_edge
	var nx := int((2.0 * (half + beyond_edge)) / CELL)
	for ix in nx:
		var x := x0 + ix * CELL
		var zc := _river_z(river, x + CELL * 0.5)
		var hw := _river_hw(river, x + CELL * 0.5)
		var inside := absf(x) < half and absf(x + CELL) < half
		var span := hw + 14.0 if inside else hw + 4.0
		var z0 := floorf((zc - span) / CELL) * CELL
		var z1 := ceilf((zc + span) / CELL) * CELL
		var z := z0
		while z < z1:
			var wet := true
			if inside:
				# клетка нужна, если хоть один угол ниже уровня воды (с запасом)
				wet = minf(minf(Terrain.height_at(x, z), Terrain.height_at(x + CELL, z)),
					minf(Terrain.height_at(x, z + CELL), Terrain.height_at(x + CELL, z + CELL))) < wl + 0.25
			if wet:
				var ids := []
				for c: Vector2 in [Vector2(x, z), Vector2(x + CELL, z), Vector2(x + CELL, z + CELL), Vector2(x, z + CELL)]:
					var key := Vector2i(roundi(c.x), roundi(c.y))
					if not map.has(key):
						map[key] = verts.size()
						verts.append(Vector3(c.x, wl, c.y))
						cols.append(_flow_color(river, ford, c.x, c.y))
					ids.append(map[key])
				idx.append_array(PackedInt32Array([ids[0], ids[1], ids[2], ids[0], ids[2], ids[3]]))
			z += CELL
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh = m
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("water_level", wl)
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Ось реки z(x) по ломаной из height.json (с продолжением прямо за концами).
static func _river_z(river: Array, x: float) -> float:
	return _interp(river, x, 1)


static func _river_hw(river: Array, x: float) -> float:
	return _interp(river, x, 2)


static func _interp(river: Array, x: float, k: int) -> float:
	var n := river.size()
	if x <= float(river[0][0]):
		return float(river[0][k])
	if x >= float(river[n - 1][0]):
		return float(river[n - 1][k])
	for i in n - 1:
		var a: Array = river[i]
		var b: Array = river[i + 1]
		if x <= float(b[0]):
			var t := (x - float(a[0])) / (float(b[0]) - float(a[0]))
			return lerpf(float(a[k]), float(b[k]), t)
	return float(river[n - 1][k])


## Течение с востока на запад (как Сырдарья в Фергане): касательная к оси реки.
static func _flow_color(river: Array, ford: Array, x: float, z: float) -> Color:
	var dz := _river_z(river, x + 3.0) - _river_z(river, x - 3.0)
	var dir := Vector2(-6.0, -dz).normalized()
	var zc := _river_z(river, x)
	var hw := _river_hw(river, x)
	var across := clampf(absf(z - zc) / maxf(hw, 1.0), 0.0, 1.5)
	var speed := clampf(1.0 - across * across * 0.6, 0.15, 1.0)
	var at_ford := exp(-pow((x - float(ford[0])) / 30.0, 2.0))
	speed = clampf(speed * (0.75 + 0.6 * at_ford), 0.0, 1.0)
	return Color(dir.x * 0.5 + 0.5, dir.y * 0.5 + 0.5, speed, at_ford)
