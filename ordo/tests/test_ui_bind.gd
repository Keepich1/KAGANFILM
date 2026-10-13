extends SceneTree
## Привязка интерфейса «Города» к данным (ARCHITECTURE §15, UI): верхняя балка каждой стороны строится из
## FactionDefs.ui_res (свои ресурсы: у Коканда ғишт и нет коней, у кыпчаков кони и нет камня; списка в коде нет);
## сетка приказов = GameQuery.orders_for, вкладки стройки = build_menu; панель здания — кнопки найма;
## записки — цвет печати по событию; все строки — по-русски; замер времени обновления.
##   godot --headless --path ordo --script res://tests/test_ui_bind.gd

var city: FakeCity


func _init() -> void:
	city = FakeCity.new()
	city.setup(1)
	for i in 60:
		city.step()
	for p in 2:
		_test_side(p)
	SimHarness.finish(self)


func _make_hud(p: int) -> Array:
	var sel := SelectionModel.new()
	var inp := RtsInput.new()
	inp.to_world = func(s: Vector2) -> Vector3: return Vector3(s.x * 0.1, 0.0, s.y * 0.1)
	inp.to_screen = func(w: Vector3) -> Vector2: return Vector2(w.x, w.z) * 10.0
	inp.view_rect = func() -> Rect2: return Rect2(0, 0, 1920, 1080)
	var log: Array[PackedInt32Array] = []
	inp.setup(city, sel, p, func(c: PackedInt32Array) -> void: log.append(c))
	root.add_child(inp)
	var hud := CityHud.new()
	root.add_child(hud)
	hud.setup(city, null, sel, p, null, inp)
	return [hud, sel, inp, log]


func _test_side(p: int) -> void:
	var defs := city.defs()
	var f := city.players().faction[p]
	var fid := String(defs.f_ids[f])
	print("[%s]" % fid)
	var t_setup := Time.get_ticks_usec()
	var made := _make_hud(p)
	print("  замер: сборка интерфейса (с рельефом миникарты) %.1f мс" % ((Time.get_ticks_usec() - t_setup) / 1000.0))
	var hud: CityHud = made[0]
	var sel: SelectionModel = made[1]
	var log: Array = made[3]
	# балка: ресурсы из ui_res без выключенных, в том же порядке
	var want := PackedInt32Array()
	for r in defs.f_ui_res[f]:
		if defs.r_enabled[r] != 0:
			want.append(r)
	SimHarness.check(hud.top.shown_res == want and want.size() >= 4,
		"балка = ui_res без выключенных: %s" % ", ".join(Array(hud.top.shown_res).map(func(r: int) -> String: return defs.res_ids[r])))
	var own_unique := false
	var foreign := false
	for r in hud.top.shown_res:
		if defs.r_faction[r] == fid:
			own_unique = true
		elif defs.r_faction[r] != "":
			foreign = true
	SimHarness.check(own_unique and not foreign, "на балке свой особый ресурс и нет чужих")
	if fid == "kokand":
		SimHarness.check(hud.top.shown_res.has(defs.res(&"brick")) and not hud.top.shown_res.has(defs.res(&"horse")), "Коканд: ғишт есть, коней нет")
	else:
		SimHarness.check(hud.top.shown_res.has(defs.res(&"horse")) and not hud.top.shown_res.has(defs.res(&"stone")), "кыпчаки: кони есть, камня нет")
	# ничего не выбрано — сетка пуста, герб и подсказка
	hud.refresh_now()
	SimHarness.check(hud.bottom.grid.action_at(0).is_empty(), "без выделения сетка приказов пуста")
	# выделен отряд — сетка = orders_for
	var bs := city.sim
	var squad := PackedInt32Array()
	for u in bs.n:
		if bs.u_side[u] == city.players().team[p] and bs.u_life[u] == BattleSim.Life.ALIVE and bs.sq_single[bs.u_squad[u]] == 0 \
				and bs.sq_members[bs.u_squad[u]].size() > 1:
			squad.append(city.unit_handle(u))
	sel.set_selection(squad)
	var orders := city.orders_for(p, squad)
	var ok := orders.size() > 3
	for i in orders.size():
		ok = ok and int(hud.bottom.grid.action_at(i).get("op", -1)) == int(orders[i]["op"])
	SimHarness.check(ok, "сетка приказов = orders_for (%d кнопок)" % orders.size())
	SimHarness.check(hud.bottom.cards.visible and hud.info.get("kind") == "units", "карточки отрядов на бумаге")
	# вкладка «Хозяйство» = build_menu
	hud.open_tab(&"economy")
	var menu := city.build_menu(p, &"economy")
	ok = menu.size() > 3
	for i in mini(menu.size(), CityOrderGrid.COLS * CityOrderGrid.ROWS):
		ok = ok and int(hud.bottom.grid.action_at(i).get("btype", -1)) == int(menu[i]["btype"])
	SimHarness.check(ok, "вкладка «Хозяйство» = build_menu (%d построек)" % menu.size())
	# кнопка постройки → режим постройки
	(hud.bottom.grid._buttons[0] as Button).emit_signal("pressed")
	var inp: RtsInput = made[2]
	SimHarness.check(inp.placement.active() and inp.placement.btype == int(menu[0]["btype"]), "кнопка постройки включает призрак")
	inp.placement.cancel()
	hud.open_tab(&"orders")
	# ставка — панель здания: кнопки найма = trains, клавиша найма даёт TRAIN
	var hq := city.players().hq_b[p]
	sel.set_selection(PackedInt32Array([hq]))
	var panel := city.building_panel(hq)
	SimHarness.check(hud.bottom.building.visible, "выбрана ставка — панель здания")
	var trains := 0
	for ch in hud.bottom.building.get_children():
		if ch is Button and ch.size.x >= CityBuildingPanel.TRAIN:
			trains += 1
	SimHarness.check(trains == (panel.get("trains", []) as Array).size(), "кнопок найма = trains (%d)" % trains)
	log.clear()
	hud.train(hq, int(panel["trains"][0]["utype"]))
	SimHarness.check(log.size() == 1 and (log[0] as PackedInt32Array) == SimCmd.train(hq, int(panel["trains"][0]["utype"]), 1),
		"кнопка найма → TRAIN(ставка, работник, 1)")
	# записки: печать по событию
	var ev := city.events()
	hud.notes.poll()
	var before := hud.notes.visible_notes().size()
	ev.push(SimEvents.Ev.FAMINE, p, 1, 0, 0, Vector2(10, 10))
	ev.push(SimEvents.Ev.BUILDING_DONE, p, 0, defs.building(&"uy" if fid == "kokand" else &"boz"), 0, Vector2.ZERO)
	ev.push(SimEvents.Ev.POP_CAPPED, p, 0, 70, 70, Vector2.ZERO)
	ev.push(SimEvents.Ev.FAMINE, 1 - p, 1, 0, 0, Vector2.ZERO)         # чужая — не наша записка
	ev.push(SimEvents.Ev.CMD_REJECTED, p, SimCmd.Op.BUILD, 100 + NavApi.Why.SLOPE, 0, Vector2.ZERO)
	var added := hud.notes.poll()
	var notes := hud.notes.visible_notes()
	SimHarness.check(added == 4, "четыре свои записки (чужая пропущена): %d" % added)
	var seals := notes.slice(0, 4).map(func(n: Dictionary) -> int: return n["seal"])
	SimHarness.check(seals == [CityNotes.Seal.RED, CityNotes.Seal.GOLD, CityNotes.Seal.GREEN, CityNotes.Seal.RED],
		"печати: отказ — красная, предел — золотая, построено — зелёная, голод — красная")
	SimHarness.check(String(notes[0]["text"]).contains("склон"), "отказ по-русски: «%s»" % notes[0]["text"])
	SimHarness.check(before >= 0, "записки до проверки: %d" % before)
	ev.push(SimEvents.Ev.RAID_STARTED, p, 1 - p, 20, 1, Vector2(112, 132))
	hud.notes.poll()
	SimHarness.check(hud.bottom.minimap._pings.size() >= 1 and hud.top._raid_on, "набег: метка на миникарте и «Набег!» на балке")
	# все строки интерфейса по-русски
	var latin := _latin_texts(hud.root)
	SimHarness.check(latin.is_empty(), "все надписи по-русски%s" % ("" if latin.is_empty() else ": " + str(latin)))
	# скорость обновления
	var t0 := Time.get_ticks_usec()
	for i in 60:
		hud.refresh_now()
	var ui_ms := (Time.get_ticks_usec() - t0) / 60000.0
	t0 = Time.get_ticks_usec()
	for i in 30:
		hud.bottom.minimap.refresh()
	var map_ms := (Time.get_ticks_usec() - t0) / 30000.0
	t0 = Time.get_ticks_usec()
	for i in 600:
		hud.notes.poll()
	var notes_ms := (Time.get_ticks_usec() - t0) / 600000.0
	var si := SelectionImpl.new(city, sel, p)
	var nu := city.units_of(p).size()
	t0 = Time.get_ticks_usec()
	for i in 10:
		si.box(Rect2(-1e5, -1e5, 2e5, 2e5), false, func(w: Vector3) -> Vector2: return Vector2(w.x, w.z))
	var box_ms := (Time.get_ticks_usec() - t0) / 10000.0
	print("  замер: обновление панелей %.3f мс (6,7 Гц), миникарта %.3f мс (4 Гц), записки %.4f мс/кадр, рамка по %d юнитам %.2f мс" % [ui_ms, map_ms, notes_ms, nu, box_ms])
	SimHarness.check(ui_ms < 4.0 and map_ms < 4.0, "обновления дешёвые (панели %.2f мс, миникарта %.2f мс)" % [ui_ms, map_ms])
	hud.queue_free()
	(made[2] as Node).queue_free()


## Надписи с латиницей (кроме клавиш: одна буква, Del, Shift+K, F1…)
func _latin_texts(n: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var re := RegEx.create_from_string("[A-Za-z]{2,}")
	var keys := ["Del", "Shift", "Ctrl", "Esc", "Tab"]
	for c in n.get_children():
		var txt := ""
		if c is Label:
			txt = (c as Label).text
		elif c is Button:
			txt = (c as Button).text
		if txt != "":
			var s := txt
			for k in keys:
				s = s.replace(k, "")
			if re.search(s):
				out.append(txt)
		out.append_array(_latin_texts(c))
	return out
