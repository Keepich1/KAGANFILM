extends SceneTree
## Проверка уровней качества без графики:
##   godot --headless --path ordo --script res://tests/test_quality.gd
## Порядок F2, числа уровней, выбор уровня по имени видеокарты (первый запуск).
## Ускорение видеокарты (perf2): сглаживание и тени «Высокого», тени толпы только в ближних каскадах,
## живописный фильтр в уменьшенном кадре на мониторах выше 1080p, дерево кусков земли — ни щелей,
## ни двойной земли, нигде не грубее прежнего.

var _fails := 0


func _init() -> void:
	print("[F2]")
	_check(WorldQuality.next_level("high") == "medium", "«Высокое» → «Среднее»")
	_check(WorldQuality.next_level("medium") == "low", "«Среднее» → «Низкое»")
	_check(WorldQuality.next_level("low") == "high", "«Низкое» → «Высокое»")
	_check(WorldQuality.level_name("medium") == "Среднее", "название «Среднее»")
	print("[уровни]")
	var h := WorldQuality.preset("high")
	# карта теней 4096 (было 8192) — мягкость тени та же в метрах (shadow_blur_for), см. [perf2]
	_check(h.scale == 1.0 and h.upscale == "bilinear" and h.post == "full" and h.volfog and h.shadow_splits == 4
		and h.shadow_atlas == 4096 and h.grass_density == 1.0 and h.fx == 1.0, "«Высокое» — как в срезе")
	var m := WorldQuality.preset("medium")
	var l := WorldQuality.preset("low")
	for k in ["scale", "grass_density", "crowd_lod", "fx", "shadow_dist"]:
		_check(float(h[k]) >= float(m[k]) and float(m[k]) >= float(l[k]), "%s: высокое ≥ среднее ≥ низкое" % k)
	_check(WorldQuality.preset("нет такого") == h, "неизвестный уровень — «Высокое»")
	print("[видеокарта → уровень]")
	var cases := {
		"NVIDIA GeForce RTX 5060 Ti": 2, "NVIDIA GeForce RTX 4090": 2, "NVIDIA GeForce RTX 3060": 2,
		"NVIDIA GeForce RTX 2070 SUPER": 2, "NVIDIA GeForce RTX 2060": 1, "NVIDIA GeForce RTX 3050 Laptop GPU": 1,
		"NVIDIA GeForce GTX 1660 SUPER": 1, "NVIDIA GeForce GTX 1080 Ti": 1, "NVIDIA GeForce GTX 1650": 0,
		"NVIDIA GeForce GTX 1060 6GB": 0, "NVIDIA GeForce MX450": 0,
		"AMD Radeon RX 9070 XT": 2, "AMD Radeon RX 7800 XT": 2, "AMD Radeon RX 6600": 2,
		"AMD Radeon RX 5700 XT": 1, "AMD Radeon RX 6500 XT": 0, "AMD Radeon RX 580 Series": 0,
		"Intel(R) Arc(TM) A770 Graphics": 1, "Intel(R) Arc(TM) A380 Graphics": 0, "Intel(R) UHD Graphics 630": 0,
		"Какая-то видеокарта": -1,
	}
	for name in cases:
		var got := WorldQuality.gpu_tier(name)
		_check(got == int(cases[name]), "%s → %d (ждали %d)" % [name, got, cases[name]])
	_check_perf2()
	_check_crowd_cascades()
	_check_post_scale()
	_check_terrain_tree()
	print("")
	print("ИТОГ: ", "ВСЁ ПРОШЛО" if _fails == 0 else "ПРОВАЛОВ: %d" % _fails)
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


## «Высокое» дешевле при том же виде: SMAA вместо MSAA, карта теней 4096 с прежней мягкостью в метрах
func _check_perf2() -> void:
	print("[perf2: сглаживание, тени, туман]")
	var h := WorldQuality.preset("high")
	_check(WorldQuality.aa_mode("high") == "smaa", "«Высокое» — SMAA (MSAA 4× проекта выключен)")
	_check(WorldQuality.aa_mode("medium") == "msaa", "«Среднее» — MSAA, как было")
	_check(WorldQuality.aa_mode("low") == "fxaa", "«Низкое» — FXAA, как было")
	_check(WorldQuality.aa_mode("high", "fsr2") == "off", "FSR 2 сглаживает сам")
	_check(is_equal_approx(WorldQuality.shadow_blur_for(1.5, 4096, "high"), 0.75),
		"«Высокое», карта 4096: размытие тени вдвое меньше в точках карты — та же мягкость в метрах")
	_check(is_equal_approx(WorldQuality.shadow_blur_for(1.5, 8192, "high"), 1.5), "карта 8192 — размытие сцены")
	_check(is_equal_approx(WorldQuality.shadow_blur_for(1.5, 4096, "medium"), 1.5), "«Среднее» — размытие как было")
	_check(int(h.post_cap) == 1080 and int(WorldQuality.preset("medium").post_cap) == 0,
		"фильтр «Высокого» — до 1080 точек по высоте, «Среднее» — половина, как было")
	_check(int(h.fog_grid) == 128 and int(h.fog_depth) == 64, "туман «Высокого»: 128 × 128, 64 слоя в глубину")
	for k in ["shadow_atlas", "fog_depth", "crowd_shadow"]:
		var hv := float(h[k])
		var mv := float(WorldQuality.preset("medium")[k])
		var lv := float(WorldQuality.preset("low")[k])
		_check(hv >= mv and mv >= lv, "%s: высокое ≥ среднее ≥ низкое" % k)


## Тени толпы — только в первых каскадах солнца (CrowdLayer.shadow_pass_limit → crowd_lod.w):
## порог полуширины прохода между каскадом, что покрывает дальность теней юнитов, и следующим
func _check_crowd_cascades() -> void:
	print("[толпа: тени только в ближних каскадах]")
	# солнце среза: 4 каскада, доли 0,06 / 0,18 / 0,45, смешивание каскадов; камера 50° по высоте, 16:9
	var splits := [0.06, 0.18, 0.45]
	var ty := tan(deg_to_rad(25.0))
	var tx := ty * 16.0 / 9.0
	for level in ["high", "medium", "low"]:
		var p := WorldQuality.preset(level)
		var count := int(p.shadow_splits)
		var dist := CrowdLayer.cascade_distances(0.05, 4000.0, float(p.shadow_dist), count, splits)
		var radii := CrowdLayer.cascade_radii(tx, ty, dist, true)
		var lim := CrowdLayer.shadow_pass_limit(radii, dist, float(p.crowd_shadow))
		print("    %s: дальности %s, полуширина %s, порог %.0f м" % [level, _round_all(dist), _round_all(radii), lim])
		var grows := true
		for i in radii.size() - 1:
			grows = grows and radii[i + 1] > radii[i] * 1.8
		_check(grows, "%s: каскады растут вдвое и больше — порог надёжно между ними" % level)
		if level == "low":
			_check(lim == 0.0, "«Низкое» (2 каскада, тени юнитов 60 м): юниты во всех каскадах, как было")
			continue
		# дальность теней юнитов покрывает второй каскад: юниты — в первом и втором, порог между вторым и третьим
		_check(dist[2] >= float(p.crowd_shadow) - 1.0 and dist[1] < float(p.crowd_shadow),
			"%s: тени юнитов (%.0f м) — в пределах второго каскада (%.0f м)" % [level, p.crowd_shadow, dist[2]])
		_check(lim > radii[1] * 1.3 and lim < radii[2] / 1.3,
			"%s: первые два каскада (до %.0f м) рисуют юнитов, третий и четвёртый (от %.0f м) — нет" % [level, radii[1], radii[2]])
	# без смешивания каскадов — тоже между вторым и третьим; узкая камера — тоже
	var d4 := CrowdLayer.cascade_distances(0.05, 4000.0, 700.0, 4, splits)
	for t in [Vector2(0.3, 0.17), Vector2(1.2, 0.68)]:
		for blend in [false, true]:
			var r := CrowdLayer.cascade_radii(t.x, t.y, d4, blend)
			var lim := CrowdLayer.shadow_pass_limit(r, d4, 126.0)
			_check(lim > r[1] and lim < r[2], "угол %.2f, смешивание %s: порог %.0f м между %.0f и %.0f" % [
				t.y, blend, lim, r[1], r[2]])
	# дальность теней юнитов дальше второго каскада — порог после третьего; дальше всех — без порога
	var r4 := CrowdLayer.cascade_radii(tx, ty, d4, true)
	var lim3 := CrowdLayer.shadow_pass_limit(r4, d4, 200.0)
	_check(lim3 > r4[2] and lim3 < r4[3], "тени юнитов 200 м — первые три каскада")
	_check(CrowdLayer.shadow_pass_limit(r4, d4, 400.0) == 0.0, "тени юнитов дальше третьего каскада — во всех")
	# камера ближе дальности теней (короткий far): каскады короче, порог тоже
	var dn := CrowdLayer.cascade_distances(0.05, 100.0, 700.0, 4, splits)
	_check(CrowdLayer.shadow_pass_limit(CrowdLayer.cascade_radii(tx, ty, dn, true), dn, 126.0) == 0.0,
		"камера видит не дальше 100 м — тени юнитов во всех каскадах")


func _round_all(a: PackedFloat32Array) -> String:
	var out: Array[String] = []
	for v in a:
		out.append(str(roundi(v)))
	return "[%s]" % ", ".join(out)


## Живописный фильтр: в каком кадре считаются мазки
func _check_post_scale() -> void:
	print("[живописный фильтр: уменьшенный кадр]")
	var post := PainterlyPost.new()
	post.max_height = 1080
	_check(post.work_scale(1080) == 1.0, "1080p — полный кадр, прежний путь")
	_check(post.work_scale(900) == 1.0, "ниже 1080p — полный кадр")
	_check(is_equal_approx(post.work_scale(1440), 0.75), "1440p — кадр 1080 по высоте")
	_check(post.work_scale(2160) == 0.5, "4K — половина (1080 по высоте)")
	_check(post.work_scale(4320) == 0.5, "выше 4K — не меньше половины")
	_check(PainterlyPost.work_size(Vector2i(2560, 1440), 0.75) == Vector2i(1920, 1080), "2560 × 1440 → 1920 × 1080")
	_check(PainterlyPost.work_size(Vector2i(1921, 1081), 0.5) == Vector2i(961, 541), "половина — с округлением вверх, как было")
	post.max_height = 0
	_check(post.work_scale(2160) == 1.0, "без предела — всегда полный кадр")
	post.half_res = true
	_check(post.work_scale(1080) == 0.5 and post.work_scale(720) == 0.5, "half_res — половина при любом кадре")


## Земля: дерево кусков (HLOD). При любом положении камеры каждый участок покрыт ровно одним видимым
## куском, и нигде земля не грубее прежних кусков 64 м с уровнями 2/4/8/16 м (220/500/1100 м × lod_scale).
## Правило движка (visibility_parent): кусок виден, если его родитель «спрятан вблизи» (камера ближе
## его visibility_range_begin), а сам он не спрятан; без родителя — если не спрятан сам.
func _check_terrain_tree() -> void:
	print("[земля: дерево кусков]")
	var tm := TerrainMesh.new()
	tm.build_far_ring = false
	tm.build_collision = false
	tm.build()
	var nodes := tm.lod_nodes()
	var per_level := [0, 0, 0]
	var wired := true
	for mi in nodes:
		var lod: int = mi.get_meta("lod")
		per_level[lod] += 1
		var parent := mi.get_node_or_null(mi.visibility_parent) as MeshInstance3D if not mi.visibility_parent.is_empty() else null
		if lod == TerrainMesh.LEVELS - 1:
			wired = wired and parent == null
		else:
			# родитель — блок уровнем выше, и кусок лежит внутри него
			var half := float(parent.get_meta("half_diag")) / sqrt(2.0) if parent else 0.0
			wired = wired and parent != null and int(parent.get_meta("lod")) == lod + 1 \
				and absf(mi.position.x - parent.position.x) < half and absf(mi.position.z - parent.position.z) < half
	print("    кусков по уровням 2/4/8 м: %s, всего %d (было 256 × 4)" % [per_level, nodes.size()])
	_check(per_level == [64, 16, 4], "куски 128 м, блоки 256 и 512 м")
	_check(wired, "у каждого куска родитель — блок, внутри которого он лежит")
	var o := Terrain.origin()
	var n := Terrain.size()
	var h := Terrain.heights()
	var old_cells := 32
	var old_count := (n - 1) / old_cells
	for scale in [1.0, 0.8, 0.6]:
		tm.lod_scale = scale
		tm.apply_lod_ranges()
		var double := 0
		var coarser := 0
		var worst := 0.0
		var cams := 0
		for cz in range(-600, 601, 150):
			for cx in range(-600, 601, 150):
				for up in [4.0, 60.0, 220.0]:
					var cam := Vector3(float(cx), Terrain.height_at(float(cx), float(cz)) + up, float(cz))
					cams += 1
					var vis := _visible_terrain(nodes, cam)
					# каждый кусок 128 м покрыт ровно одним видимым узлом (он сам, его блок или блок блока)
					for mi in nodes:
						if int(mi.get_meta("lod")) != 0:
							continue
						var cover := 0
						var node: MeshInstance3D = mi
						while node != null:
							cover += 1 if vis.has(node) else 0
							node = node.get_node_or_null(node.visibility_parent) as MeshInstance3D if not node.visibility_parent.is_empty() else null
						if cover != 1:
							double += 1
					# каждый прежний кусок 64 м: шаг видимой земли над ним не грубее прежнего
					for oj in old_count:
						for oi in old_count:
							var p := Vector3(o.x + (oi + 0.5) * 64.0, 0.0, o.y + (oj + 0.5) * 64.0)
							var old_step := _old_step(h, n, oi * old_cells, oj * old_cells, old_cells, p, cam, scale)
							var new_step := 0.0
							for mi in vis:
								var half := float(mi.get_meta("half_diag")) / sqrt(2.0)
								if absf(p.x - mi.position.x) < half and absf(p.z - mi.position.z) < half:
									new_step = 2.0 * float(1 << int(mi.get_meta("lod")))
							if new_step > old_step:
								coarser += 1
								worst = maxf(worst, new_step / old_step)
		_check(double == 0, "lod_scale %.1f: %d положений камеры — каждый участок покрыт ровно одним куском" % [scale, cams])
		_check(coarser == 0, "lod_scale %.1f: нигде не грубее прежнего (грубее: %d, хуже всего ×%.0f)" % [scale, coarser, worst])
	tm.free()


## Видимые куски дерева при камере cam — по правилу движка для visibility_parent (от грубых к подробным)
func _visible_terrain(nodes: Array[MeshInstance3D], cam: Vector3) -> Dictionary:
	var close := {}
	var vis := {}
	for level in range(TerrainMesh.LEVELS - 1, -1, -1):
		for mi in nodes:
			if int(mi.get_meta("lod")) != level:
				continue
			if not mi.visibility_parent.is_empty() and not close.has(mi.get_node(mi.visibility_parent)):
				continue        # родитель виден или сам спрятан своим родителем — кусок не рисуется
			var d := cam.distance_to(mi.position + mi.mesh.get_aabb().get_center())
			if mi.visibility_range_begin > 0.0 and d < mi.visibility_range_begin:
				close[mi] = true
			elif mi.visibility_range_end <= 0.0 or d <= mi.visibility_range_end:
				vis[mi] = true
	return vis


## Шаг земли, м, над прежним куском 64 м (уровни 2/4/8/16 м, дальности 220/500/1100 м × scale,
## расстояние — до середины рамки куска уровня, как считал движок; юбка опускала низ рамки на 3 × шаг)
func _old_step(h: PackedFloat32Array, n: int, i0: int, j0: int, cells: int, p: Vector3, cam: Vector3, scale: float) -> float:
	var lo := INF
	var hi := -INF
	for j in range(j0, j0 + cells + 1, 4):
		for i in range(i0, i0 + cells + 1, 4):
			var v := h[j * n + i]
			lo = minf(lo, v)
			hi = maxf(hi, v)
	var ranges := [220.0, 500.0, 1100.0]
	for lod in 4:
		var step := 1 << lod
		var c := Vector3(p.x, (hi + lo - 3.0 * step) * 0.5, p.z)
		var d := cam.distance_to(c)
		var begin := 0.0 if lod == 0 else float(ranges[lod - 1]) * scale
		var end := INF if lod == 3 else float(ranges[lod]) * scale
		if d >= begin and d < end:
			return 2.0 * step
	return 32.0
