extends SceneTree
## Проверка уровней качества без графики:
##   godot --headless --path ordo --script res://tests/test_quality.gd
## Порядок F2, числа уровней, выбор уровня по имени видеокарты (первый запуск).

var _fails := 0


func _init() -> void:
	print("[F2]")
	_check(WorldQuality.next_level("high") == "medium", "«Высокое» → «Среднее»")
	_check(WorldQuality.next_level("medium") == "low", "«Среднее» → «Низкое»")
	_check(WorldQuality.next_level("low") == "high", "«Низкое» → «Высокое»")
	_check(WorldQuality.level_name("medium") == "Среднее", "название «Среднее»")
	print("[уровни]")
	var h := WorldQuality.preset("high")
	_check(h.scale == 1.0 and h.upscale == "bilinear" and h.post == "full" and h.volfog and h.shadow_splits == 4
		and h.shadow_atlas == 8192 and h.grass_density == 1.0 and h.fx == 1.0, "«Высокое» — как в срезе")
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
	print("")
	print("ИТОГ: ", "ВСЁ ПРОШЛО" if _fails == 0 else "ПРОВАЛОВ: %d" % _fails)
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1
