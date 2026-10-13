extends SceneTree
## Проверка и замер деления толпы на LOD по юнитам (CrowdLayer, без отрисовки):
##   godot --headless --path ordo --script res://tests/bench_crowd_lod.gd [-- --units=3000 --frames=120]
## Отряды по 100 на поле 400 × 300 м бегут вразнобой, камера летит низко над ними, солнце — как в срезе
## («Высокое»: 4 каскада до 700 м). Каждый кадр слой делит буфер на части (LOD0 с тенью, LOD0 без тени,
## LOD1, «Тень» облегчённой моделью), и проверяется: каждый видимый юнит попал в часть, чья полоса
## дальности его содержит (иначе шейдер его не нарисует — юнит пропал бы), а юнит ближе дальности
## теней — и в часть, что рисует его тень (подробной моделью в первом каскаде, дальше — облегчённой).
## Время деления — мс на кадр (процессорное время главного потока).

var _units := 3000
var _frames := 120
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--units="):
			_units = int(a.trim_prefix("--units="))
		elif a.begins_with("--frames="):
			_frames = int(a.trim_prefix("--frames="))
	var fails := _run()
	print("")
	print("ИТОГ: ", "ВСЁ ПРОШЛО" if fails == 0 else "ПРОВАЛОВ: %d" % fails)
	quit(1 if fails > 0 else 0)
	return true


## Процессорное время этого потока, мкс (Linux: /proc/thread-self/schedstat) — чужие процессы
## на машине замер не портят; где его нет — по часам
func _now_us() -> int:
	var f := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
	if f:
		return int(f.get_line().split(" ")[0]) / 1000
	return Time.get_ticks_usec()


func _run() -> int:
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(150.0, 25.0, 40.0)
	cam.make_current()
	# солнце мира (группа, по которой толпа берёт каскады): как в срезе
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_max_distance = 700.0
	root.add_child(sun)
	sun.add_to_group(CrowdLayer.SUN_GROUP)
	var layer := CrowdLayer.new()
	root.add_child(layer)
	layer.setup("kok_sarboz", _units)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pos := PackedVector3Array()
	var vel := PackedVector3Array()
	pos.resize(_units)
	vel.resize(_units)
	for i in _units:
		# отряды по 100 подряд по местам (как у BattleView): строй 25 × 4, отряды сеткой
		var s := i / 100
		var k := i % 100
		var c := Vector3(-60.0 + float(s % 6) * 70.0, 0.0, -40.0 + float(s / 6) * 60.0)
		pos[i] = c + Vector3(float(k % 25) * 1.1, 0.0, float(k / 25) * 1.4)
		vel[i] = Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-6.0, 6.0))
	layer.set_visible_count(_units)
	var fails := 0
	var t_sum := 0.0
	var t_max := 0.0
	var dt := 1.0 / 60.0
	var lod_d: float = layer._lod_d
	var sd: float = layer._shadow_end()
	var parts_sum := Vector4.ZERO
	var near_seen := 0.0
	for f in _frames:
		# юниты бегут; на трети пути отряды «рассыпаются» (бегство) — блоки растягиваются
		var buf := layer.buffer()
		for i in _units:
			var v := vel[i] * (3.0 if f > _frames / 3 and (i / 100) % 2 == 0 else 1.0)
			pos[i] += v * dt
			var o := i * 16
			buf[o] = 1.0
			buf[o + 5] = 1.0
			buf[o + 10] = 1.0
			buf[o + 3] = pos[i].x
			buf[o + 7] = pos[i].y
			buf[o + 11] = pos[i].z
			buf[o + 15] = float(i)      # номер юнита в INSTANCE_CUSTOM.w — узнать его в частях
		layer.expand_bounds(Vector3.ZERO, Vector3.ZERO)
		# камера летит (как прокрутка стратегической камеры) и иногда прыгает (смена кадра)
		cam.position += Vector3(-1.2, 0.0, 0.7)
		if f == _frames / 2:
			cam.position = Vector3(-200.0, 20.0, 200.0)
		var t0 := _now_us()
		layer._flush()
		var ms := (_now_us() - t0) / 1000.0
		t_sum += ms
		if f > 0:
			t_max = maxf(t_max, ms)
		else:
			print("  первый кадр (все блоки сразу): %.3f мс" % ms)
		# что ушло в каждую часть
		var where := PackedInt32Array()
		where.resize(_units)
		where.fill(0)
		var counts: PackedInt32Array = layer._counts
		parts_sum += Vector4(counts[0], counts[1], counts[2], counts[3])
		var near_d: float = layer.near_shadow_distance()
		near_seen = near_d
		for part in CrowdLayer.PARTS:
			var mm: MultiMesh = layer._mm[part]
			var n := counts[part]
			if n == 0:
				continue
			var data := RenderingServer.multimesh_get_buffer(mm.get_rid())
			if data.size() < n * 16:
				print("  FAIL кадр %d: буфер части %d короче (%d < %d) — проверить нельзя" % [f, part, data.size(), n * 16])
				return fails + 1
			for j in n:
				var u := int(data[j * 16 + 15])
				if u >= 0 and u < _units:
					where[u] |= 1 << part
		var bad := 0
		for i in _units:
			var d := cam.position.distance_to(pos[i])
			# в кадре: LOD0 с тенью / LOD0 без тени / LOD1; тень: LOD0 с тенью или «Тень»
			var need := 1 << (CrowdLayer.Part.LOD0_NEAR if d < near_d else (CrowdLayer.Part.LOD0 if d < lod_d
				else CrowdLayer.Part.LOD1))
			var need_shadow := 0
			if d < near_d:
				need_shadow = 1 << CrowdLayer.Part.LOD0_NEAR
			elif d < sd:
				need_shadow = 1 << CrowdLayer.Part.SHADOW
			if where[i] & need == 0 or (need_shadow != 0 and where[i] & need_shadow == 0):
				bad += 1
				if bad <= 3:
					print("  FAIL кадр %d: юнит %d (%.1f м) в частях %d" % [f, i, d, where[i]])
		if bad > 0:
			fails += 1
	parts_sum /= float(_frames)
	print("  ok   %d юнитов, %d кадров: в среднем LOD0 с тенью %d · LOD0 %d · LOD1 %d · тень LOD1 %d (по блокам)" % [
		_units, _frames, int(parts_sum.x), int(parts_sum.y), int(parts_sum.z), int(parts_sum.w)])
	print("  тень подробной моделью ближе %.0f м, облегчённой — до %.0f м" % [near_seen, sd])
	if near_seen >= lod_d - 0.5 or near_seen < 30.0:
		print("  FAIL тень подробной моделью должна кончаться за первым каскадом (≈52 м), а не на %.0f м" % near_seen)
		fails += 1
	print("  деление на LOD: %.3f мс/кадр в среднем, худший (кроме первого) %.3f мс" % [t_sum / _frames, t_max])
	# раскладка: пересчёт границ блоков и само деление с отправкой
	var ts := 0.0
	var tp := 0.0
	for f in 30:
		layer._dirty = true
		var a := _now_us()
		layer._scan_blocks()
		var b := _now_us()
		layer._partition(cam.position + Vector3(f, 0, 0))
		var c := _now_us()
		ts += (b - a) / 1000.0
		tp += (c - b) / 1000.0
	print("  из них: границы блоков %.3f мс, деление и отправка %.3f мс" % [ts / 30.0, tp / 30.0])
	if fails == 0:
		print("  ok   каждый юнит в части со своей полосой дальности")
	layer.queue_free()
	cam.queue_free()
	sun.queue_free()
	return fails
