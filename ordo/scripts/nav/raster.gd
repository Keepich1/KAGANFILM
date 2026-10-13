class_name NavRaster
extends RefCounted
## Растр отрезков на сетке навигации (ARCHITECTURE §9.2, §9.4e). Только статика, без состояния.
##   • supercover4 — 4-связная «суперобложка» отрезка: все клетки, которых касается отрезок,
##     соседние клетки делят ребро (звенья стен и арыков — без диагональных щелей);
##   • sectors_of — секторы, через которые идёт ломаная (устаревание путей).
## Целочисленно: концы переводятся в сантиметры от начала сетки, обход клеток — сравнением
## перекрёстных произведений (Amanatides–Woo без деления), поэтому результат не зависит от
## округлений с плавающей точкой.

const CM := 100.0


## Клетки (col, row) отрезка a→b парами [col0, row0, col1, row1, …], 4-связно, от a к b.
## Клетки вне сетки тоже возвращаются (обрезает вызывающий). cell — размер клетки, м.
static func supercover4(a: Vector2, b: Vector2, origin: Vector2, cell: float) -> PackedInt32Array:
	var s := roundi(cell * CM)
	var x0 := roundi((a.x - origin.x) * CM)
	var z0 := roundi((a.y - origin.y) * CM)
	var x1 := roundi((b.x - origin.x) * CM)
	var z1 := roundi((b.y - origin.y) * CM)
	return supercover4_cm(x0, z0, x1, z1, s)


## То же в целых сантиметрах (s — клетка, см)
static func supercover4_cm(x0: int, z0: int, x1: int, z1: int, s: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var cx := _fdiv(x0, s)
	var cz := _fdiv(z0, s)
	var ex := _fdiv(x1, s)
	var ez := _fdiv(z1, s)
	out.append(cx)
	out.append(cz)
	var dx := x1 - x0
	var dz := z1 - z0
	var sx := 1 if dx > 0 else (-1 if dx < 0 else 0)
	var sz := 1 if dz > 0 else (-1 if dz < 0 else 0)
	var adx := absi(dx)
	var adz := absi(dz)
	# ближайшие границы клеток по ходу отрезка
	var bx := (cx + 1) * s if sx > 0 else cx * s
	var bz := (cz + 1) * s if sz > 0 else cz * s
	var steps := absi(ex - cx) + absi(ez - cz)
	for i in steps:
		# t до границы x: |bx − x0| / adx; до границы z: |bz − z0| / adz — сравниваем крест-накрест
		var step_x: bool
		if sx == 0:
			step_x = false
		elif sz == 0:
			step_x = true
		else:
			step_x = absi(bx - x0) * adz <= absi(bz - z0) * adx    # на углу — сперва по x
		if step_x:
			cx += sx
			bx += sx * s
		else:
			cz += sz
			bz += sz * s
		out.append(cx)
		out.append(cz)
	return out


## Секторы (индексы sy * sw + sx) ломаной pts по порядку, без повторов; вне сетки — пропуск
static func sectors_of(pts: PackedVector2Array, origin: Vector2, cell: float, sector: int,
		w: int, h: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var sw := ceili(float(w) / sector)
	var sh := ceili(float(h) / sector)
	var seen := {}
	for i in range(1, pts.size()):
		var cells := supercover4(pts[i - 1], pts[i], origin, cell * sector)
		for k in range(0, cells.size(), 2):
			var sx := cells[k]
			var sy := cells[k + 1]
			if sx < 0 or sy < 0 or sx >= sw or sy >= sh:
				continue
			var si := sy * sw + sx
			if not seen.has(si):
				seen[si] = true
				out.append(si)
	if pts.size() == 1:
		var c := supercover4(pts[0], pts[0], origin, cell * sector)
		if c[0] >= 0 and c[1] >= 0 and c[0] < sw and c[1] < sh:
			out.append(c[1] * sw + c[0])
	return out


## Целочисленное деление с округлением вниз (и для отрицательных)
static func _fdiv(a: int, b: int) -> int:
	var q := a / b
	if (a % b != 0) and ((a < 0) != (b < 0)):
		q -= 1
	return q
