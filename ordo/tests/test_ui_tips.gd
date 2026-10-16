extends SceneTree
## Подсказки кнопок (просьба автора 2026-10-15: «на каждую кнопку описание, особенно для стройки и воинов»):
##   godot --headless --path ordo --script res://tests/test_ui_tips.gd
## CityTips: у каждой постройки меню стройки и каждого воина найма — подсказка из таблиц (цена и время —
## те же, что в Defs; здоровье, броня, удар — из UnitStats), у каждого приказа — что он делает; записка
## переносит строки по ширине MAX_W. В «Городе» кнопки сетки, найма, вкладок, балки и меню паузы — записки.

var city: FakeCity


func _init() -> void:
	city = FakeCity.new()
	city.setup(1)
	for i in 30:
		city.step()
	_test_texts()
	_test_panel()
	process_frame.connect(_in_tree, CONNECT_ONE_SHOT)


func _in_tree() -> void:
	_test_hud()
	SimHarness.finish(self)


func _test_texts() -> void:
	print("[тексты из таблиц]")
	var defs := city.defs()
	var bad := PackedStringArray()
	var n_b := 0
	for f in defs.f_ids.size():
		for tab: String in defs.f_tabs[f]:
			for b in defs.f_tabs[f][tab]:
				n_b += 1
				var t := CityTips.building(defs, b, "X", "")
				var lines := t.split("\n")
				var cost := CityTips._cost_of(defs, defs.b_cost, b)
				if lines[0] != "%s (X)" % defs.b_name[b]:
					bad.append("%s: заголовок «%s»" % [defs.b_ids[b], lines[0]])
				if cost != "" and not (t.contains("Цена") and t.contains(": " + cost)):
					bad.append("%s: нет цены «%s»" % [defs.b_ids[b], cost])
				if defs.b_build_ticks[b] > 0 and not t.contains("стройка %s с" % CityTips._num(defs.b_build_ticks[b] / 30.0)):
					bad.append("%s: нет времени стройки" % defs.b_ids[b])
				for r in defs.b_requires[b]:
					if not t.contains(defs.b_name[r]):
						bad.append("%s: не сказано, что сначала %s" % [defs.b_ids[b], defs.b_name[r]])
				if defs.b_pop_cap[b] > 0 and not t.contains("Население: +%d" % defs.b_pop_cap[b]):
					bad.append("%s: нет населения" % defs.b_ids[b])
	SimHarness.check(n_b > 10 and bad.is_empty(), "постройки меню (%d): заголовок, цена, время, что нужно, население — по Defs %s" % [n_b, bad])
	bad = PackedStringArray()
	var n_u := 0
	var plus := 0
	var minus := 0
	for b in defs.b_name.size():
		for u in defs.b_trains[b]:
			n_u += 1
			var t := CityTips.unit(defs, u, "нет денег")
			var st := UnitStats.get_stats(String(defs.unit_ids[u]))
			if not t.begins_with(defs.u_name[u]):
				bad.append("%s: заголовок" % defs.unit_ids[u])
			if not t.contains("Здоровье %d · броня %d · атака %d" % [int(st["hp"]), int(st["armour"]), int(st["attack"])]):
				bad.append("%s: нет здоровья, брони, атаки" % defs.unit_ids[u])
			var cost := CityTips._cost_of(defs, defs.u_cost, u)
			if cost != "" and not t.contains("Цена: " + cost):
				bad.append("%s: нет цены" % defs.unit_ids[u])
			if int(st.get("missile", 0)) > 0 and not t.contains("Стрельба: урон %d, дальность %d м" % [int(st["missile"]), int(st["range"])]):
				bad.append("%s: нет выстрела" % defs.unit_ids[u])
			if t.get_slice("\n", 1) != "! нет денег":
				bad.append("%s: причина «нельзя» не сразу под заголовком" % defs.unit_ids[u])
			if t.contains("площади") or t.contains("на отходе"):
				bad.append("%s: обещает то, чего ещё нет (ядра по площади, качып атуу)" % defs.unit_ids[u])
			plus += t.count("\n+ ")
			minus += t.count("\n− ")
	SimHarness.check(n_u > 8 and bad.is_empty() and plus > n_u and minus > n_u / 2,
		"воины найма (%d): цена, здоровье, броня, удар, выстрел — по таблицам; сильных сторон %d, слабых %d %s" % [
		n_u, plus, minus, bad])
	var sp := CityTips.strengths("nayzachi")
	var cav := CityTips.weaknesses("navkar")
	SimHarness.check(sp.size() > 0 and sp[0].contains("коннице") and cav.size() > 0 and cav[0].contains("копьям"),
		"копейщики — против конницы, конница — боится копий")
	bad = PackedStringArray()
	for op: int in CityTips.ORDER_TEXT:
		var t := CityTips.order(op, "Приказ", "K", false)
		if not t.begins_with("Приказ (K)\n! ") or t.count("\n") < 2:
			bad.append(str(op))
		if (op in CityTips.NOT_YET) != t.contains("следующих сборках"):
			bad.append("%d: «в следующих сборках»" % op)
	var why := CityTips.order(SimCmd.Op.FORMATION, "Строй", "F", false)
	SimHarness.check(bad.is_empty() and why.contains("только у отряда") and why.contains("линия → колонна"),
		"приказы (%d): заголовок с клавишей, своя причина «нельзя», что делает; заглушки — «в следующих сборках» %s" % [
		CityTips.ORDER_TEXT.size(), bad])


## Записка: заголовок, строки «+»/«−»/«!» цветом, ни одна строка не шире MAX_W
func _test_panel() -> void:
	print("[записка]")
	var defs := city.defs()
	var t := CityTips.unit(defs, defs.unit(&"xos_navkar"), "Сначала: Отхона")
	var p := CityTips.panel(t)
	var widest := 0.0
	var cols := {}
	for ch in p.get_children():
		var l := ch as Label
		if l:
			widest = maxf(widest, l.get_combined_minimum_size().x)
			cols[l.get_theme_color("font_color").to_html(false)] = true
	SimHarness.check(widest <= CityTips.MAX_W + 4.0, "строки не шире записки: %.0f из %.0f" % [widest, CityTips.MAX_W])
	SimHarness.check(cols.has(CityTips.PLUS.to_html(false)) and cols.has(CityTips.MINUS.to_html(false)) and cols.has(CityTips.WHY.to_html(false)),
		"сильные, слабые стороны и причина — своим цветом")
	SimHarness.check(CityTips.panel("") == null, "пустая подсказка — без записки")
	var long := CityTips.panel("Заголовок\n" + "очень длинная строка подсказки ".repeat(8))
	var lines := 0
	for ch in long.get_children():
		if ch is Label:
			lines += (ch as Label).text.count("\n") + 1
	SimHarness.check(lines >= 3, "длинная строка переносится (%d строк)" % lines)
	p.free()
	long.free()


## «Город»: кнопки сетки (приказы и стройка), найма, вкладок, балки, меню паузы — записки с текстом
func _test_hud() -> void:
	print("[кнопки «Города»]")
	var sel := SelectionModel.new()
	var inp := RtsInput.new()
	inp.to_world = func(s: Vector2) -> Vector3: return Vector3(s.x * 0.1, 0.0, s.y * 0.1)
	inp.to_screen = func(w: Vector3) -> Vector2: return Vector2(w.x, w.z) * 10.0
	inp.view_rect = func() -> Rect2: return Rect2(0, 0, 1920, 1080)
	inp.setup(city, sel, 0, func(_c: PackedInt32Array) -> void: pass)
	root.add_child(inp)
	var hud := CityHud.new()
	root.add_child(hud)
	hud.setup(city, null, sel, 0, null, inp)
	var defs := city.defs()
	# стройка: вкладка «Хозяйство»
	hud.bottom.tabs.select(&"economy")
	hud.refresh_now(true)
	var n := 0
	var bad := PackedStringArray()
	for b in hud.bottom.grid.get_children():
		var btn := b as Button
		if btn and btn.visible and btn.tooltip_text != "":
			n += 1
			if not (btn is CityTips.TipButton) or not btn.tooltip_text.contains("Цена"):
				bad.append(btn.tooltip_text.get_slice("\n", 0))
	SimHarness.check(n > 3 and bad.is_empty(), "кнопки стройки (%d) — записки с ценой %s" % [n, bad])
	# приказы своего здания со своим наймом
	var bt := city.buildings()
	var hq := -1
	for b in bt.hw:
		if bt.owner[b] == 0 and bt.state[b] != BuildingTable.State.FREE and not defs.b_trains[bt.btype[b]].is_empty():
			hq = b
			break
	sel.set_selection(PackedInt32Array([bt.handle(hq)]))
	hud.bottom.tabs.select(&"orders")
	hud.refresh_now(true)
	var hire := 0
	bad = PackedStringArray()
	for ch in hud.bottom.building.get_children():
		var btn := ch as Button
		if btn and btn is CityTips.TipButton and btn.size.x >= CityBuildingPanel.TRAIN - 0.5 and btn.name != "Ability":
			hire += 1
			if not btn.tooltip_text.contains("Здоровье"):
				bad.append(btn.tooltip_text.get_slice("\n", 0))
	SimHarness.check(hire > 0 and bad.is_empty(), "кнопки найма (%d) — записки: кто это, здоровье, удар %s" % [hire, bad])
	var orders := 0
	for b in hud.bottom.grid.get_children():
		var btn := b as Button
		if btn and btn.tooltip_text != "":
			orders += 1
			if not (btn is CityTips.TipButton) or btn.tooltip_text.count("\n") < 1:
				bad.append(btn.tooltip_text)
	SimHarness.check(orders > 0 and bad.is_empty(), "кнопки приказов (%d) — записки: название, что делает %s" % [orders, bad])
	var tabs_ok := true
	for t in hud.bottom.tabs.get_children():
		tabs_ok = tabs_ok and t is CityTips.TipButton and (t as Button).tooltip_text.count("\n") >= 1
	var sys_ok := hud.top._speed is CityTips.TipButton and hud.top._pause.tooltip_text.contains("(P)")
	var menu_ok := true
	for b in hud.menu.find_children("*", "Button", true, false):
		if (b as Button).text in ["Продолжить", "Начать заново", "В главное меню"]:
			menu_ok = menu_ok and (b as Button).tooltip_text.count("\n") >= 1
	SimHarness.check(tabs_ok and sys_ok and menu_ok, "вкладки, кнопки балки и меню паузы — с подсказками")
	hud.free()
	inp.free()
