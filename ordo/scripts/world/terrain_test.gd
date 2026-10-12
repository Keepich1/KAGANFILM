extends SceneTree
## Проверка Terrain без экрана:
##   godot --headless --path ordo --script res://scripts/world/terrain_test.gd
## Луг ровный и сухой, лагерь на плато, у брода мелко, река — вода, края — крутые горы.

var _fails := 0


func _init() -> void:
	_check(Terrain.size() == 513, "сетка высот 513²")
	# луг боя: ровный, без воды, уклон не больше 4°
	var lo := INF
	var hi := -INF
	var max_slope := 0.0
	for x in range(10, 171, 8):
		for z in range(-80, 81, 8):
			var h := Terrain.height_at(x, z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
			max_slope = maxf(max_slope, rad_to_deg(Terrain.normal_at(x, z).angle_to(Vector3.UP)))
			_check(not Terrain.is_water(x, z), "на лугу нет воды (%d, %d)" % [x, z], false)
	_check(max_slope < 4.0, "луг пологий: %.1f°" % max_slope)
	_check(hi - lo < 4.0, "перепад луга %.1f м" % (hi - lo))
	# лагерь: плато
	var camp := Terrain.marker("camp")
	_check(absf(camp.y - Terrain.height_at(camp.x, camp.z)) < 0.01, "метка лагеря на земле")
	for a in 12:
		var p := Vector2(camp.x, camp.z) + Vector2.from_angle(TAU * a / 12.0) * 45.0
		_check(absf(Terrain.height_at(p.x, p.y) - camp.y) < 1.0, "плато лагеря ровное", false)
	# брод: вода, но мелко
	var ford := Terrain.marker("ford")
	var d := Terrain.water_depth(ford.x, ford.z)
	_check(Terrain.is_water(ford.x, ford.z) and d < 0.6, "брод мелкий: %.2f м" % d)
	# река глубже брода в стороне
	var info := Terrain.info()
	var deepest := 0.0
	for p: Array in info.get("river", []):
		if absf(float(p[0]) - ford.x) > 120.0 and absf(float(p[0])) < 480.0:
			deepest = maxf(deepest, Terrain.water_depth(float(p[0]), float(p[1])))
	_check(deepest > 1.0, "река глубже брода: %.2f м" % deepest)
	# горы по краям: высоко и круто
	_check(Terrain.height_at(0.0, -490.0) > 40.0, "горы на севере: %.0f м" % Terrain.height_at(0.0, -490.0))
	var steep := 0
	var total := 0
	for x in range(-480, 481, 16):
		for z in range(-480, -339, 16):
			total += 1
			if rad_to_deg(Terrain.normal_at(x, z).angle_to(Vector3.UP)) > 25.0:
				steep += 1
	_check(steep > total / 4, "крутые склоны у северного края: %d%%" % (100 * steep / total))
	# билинейность: между узлами — среднее
	var h0 := Terrain.height_at(100.0, 100.0)
	var h1 := Terrain.height_at(102.0, 100.0)
	_check(absf(Terrain.height_at(101.0, 100.0) - (h0 + h1) * 0.5) < 1e-3, "билинейная высота")
	print("Terrain: ", "ОК" if _fails == 0 else "ошибок %d" % _fails)
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String, verbose := true) -> void:
	if not ok:
		_fails += 1
		print("  НЕТ: ", what)
	elif verbose:
		print("  да: ", what)
