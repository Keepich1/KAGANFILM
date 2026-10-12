class_name GrassClump
extends RefCounted
## Меш одного пучка травы (высота ≈1, основание в начале координат).
## Листья — изогнутые ленты, сужающиеся к кончику; ости ковыля — длинные дуги,
## пушистые во второй половине (их шейдер разворачивает по ветру и подсвечивает).
## Цвет вершины: r — 1 у остей ковыля, g — доля длины (0 у земли, 1 на кончике),
## b — случайное число листа. Детерминировано по seed.


static func build(detail: int, seed: int) -> ArrayMesh:
	var rs := RandomNumberGenerator.new()
	rs.seed = seed
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var blades := 6 if detail > 0 else 4
	var segs := 3 if detail > 0 else 2
	for b in blades:
		var yaw := TAU * (b + rs.randf_range(-0.3, 0.3)) / blades
		var lean := deg_to_rad(rs.randf_range(10.0, 38.0))
		var length := rs.randf_range(0.55, 1.0)
		var base := Vector3(cos(yaw), 0.0, sin(yaw)) * rs.randf_range(0.0, 0.06)
		# вдали листья шире: тонкие травинки мельче пикселя и пропадают
		var width := rs.randf_range(0.06, 0.09) if detail > 0 else rs.randf_range(0.2, 0.28)
		_ribbon(verts, norms, cols, uvs, idx, base, yaw, lean, length, width, segs, 0.0, rs.randf(), 1.6)
	var plumes := 4 if detail > 0 else 3
	var psegs := 5 if detail > 0 else 3
	for p in plumes:
		# ости смотрят примерно в одну сторону (+X), шейдер повернёт их по ветру
		var yaw := rs.randf_range(-0.55, 0.55)
		var lean := deg_to_rad(rs.randf_range(18.0, 34.0))
		var length := rs.randf_range(1.15, 1.55)
		var base := Vector3(rs.randf_range(-0.04, 0.04), 0.0, rs.randf_range(-0.04, 0.04))
		_ribbon(verts, norms, cols, uvs, idx, base, yaw, lean, length, 0.045 if detail > 0 else 0.11, psegs, 1.0, rs.randf(), 3.2)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Лента вдоль изогнутой оси: наклон растёт к кончику (curl — сила изгиба).
static func _ribbon(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray,
		uvs: PackedVector2Array, idx: PackedInt32Array, base: Vector3, yaw: float, lean: float,
		length: float, width: float, segs: int, plume: float, rnd: float, curl: float) -> void:
	var dir := Vector3(cos(yaw), 0.0, sin(yaw))
	var side := Vector3(-dir.z, 0.0, dir.x)
	var start := verts.size()
	var p := base
	var step := length / segs
	for i in segs + 1:
		var t := float(i) / segs
		var ang := lean * (1.0 + curl * t * t)
		var tangent := (Vector3.UP * cos(ang) + dir * sin(ang)).normalized()
		var w: float
		if plume > 0.5:
			# ость: тонкая у основания, пушистая во второй половине, к концу сходит на нет
			w = width * (0.25 + 1.2 * smoothstep(0.3, 0.7, t)) * (1.0 - smoothstep(0.85, 1.0, t) * 0.8)
		else:
			w = width * (1.0 - t * 0.92)
		var nrm := side.cross(tangent).normalized()
		verts.append(p - side * w * 0.5)
		verts.append(p + side * w * 0.5)
		norms.append(nrm)
		norms.append(nrm)
		cols.append(Color(plume, t, rnd, 1.0))
		cols.append(Color(plume, t, rnd, 1.0))
		uvs.append(Vector2(0.0, t))
		uvs.append(Vector2(1.0, t))
		if i < segs:
			p += tangent * step
	for i in segs:
		var a := start + i * 2
		idx.append_array(PackedInt32Array([a, a + 1, a + 3, a, a + 3, a + 2]))
