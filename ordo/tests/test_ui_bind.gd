extends SceneTree
## Привязка интерфейса «Города» к данным (ARCHITECTURE §15, UI): верхняя балка каждой стороны строится из
## FactionDefs.ui_res (свои ресурсы: у Коканда ғишт и нет коней, у кыпчаков кони и нет камня; списка в коде нет);
## сетка приказов = GameQuery.orders_for, вкладки стройки = build_menu; панель здания — кнопки найма;
## записки — цвет печати по событию; все строки — по-русски; замер времени обновления; новая партия у драйвера
## (started) — интерфейс и ввод на новом окне чтения, перед чтением — driver.sync().
## Если в проекте уже есть настоящая игра (GameDriver, GameQueryImpl — главная ветка после слияния GAME),
## тот же интерфейс проверяется и на ней: приказы мышью доходят до игры и принимаются (без CMD_REJECTED).
##   godot --headless --path ordo --script res://tests/test_ui_bind.gd

var city: FakeCity


## Драйвер поддельного города с sync() (как GameDriver): считает вызовы
class SyncDriver extends FakeCityDriver:
	var syncs := 0

	func sync() -> void:
		syncs += 1


func _init() -> void:
	city = FakeCity.new()
	city.setup(1)
	for i in 60:
		city.step()
	for p in 2:
		_test_side(p)
	_test_big_city()
	_test_panel_extras()
	_test_restart()
	_test_real_game()
	SimHarness.finish(self)


## Добавки панели здания от ECON (сверх договора): тревоги впереди, места у воды, работники, отара без травы
func _test_panel_extras() -> void:
	print("[панель здания: добавки ECON]")
	var defs := city.defs()
	var bp := CityBuildingPanel.new()
	var tg := defs.building(&"togon")
	var lines := bp.info_lines(defs, {"btype": tg, "water_places": {"used": 6, "cap": 8}, "dry_in_s": 40,
		"workers": {"n": 2, "max": 4}, "raid": 0.5})
	SimHarness.check(lines.size() >= 4 and lines[0].contains("Разоряют") and lines[1].contains("высохнут")
		and lines.has(tr("Сув %d/%d — мест у воды") % [6, 8]) and lines.has(tr("Работников: %d / %d") % [2, 4]),
		"тревоги впереди, «Сув 6/8», «Работников 2/4»: %s" % " | ".join(lines))
	var kr := defs.building(&"koroo")
	lines = bp.info_lines(defs, {"btype": kr, "herd": {"heads": 12, "cap": 30, "grass": -1.0}})
	SimHarness.check(lines.has(tr("Отара: %d / %d голов") % [12, 30]), "отара без сведений о траве — без «трава −100%%»: %s" % " | ".join(lines))
	var old := bp.info_lines(defs, {"btype": tg, "net": {"used": 3, "places": 8}})
	SimHarness.check(old.has(tr("Сув %d/%d — мест у воды") % [3, 8]), "старое имя net {used, places} тоже читается")
	SimHarness.check(CityBuildingPanel.ability_state({"active_s": 20, "ready_s": 0}).contains("0:20")
		and CityBuildingPanel.ability_state({"active_s": 0, "ready_s": 70}).contains("1:10")
		and CityBuildingPanel.ability_state({}) == "", "умение: «действует 0:20», «через 1:10»")
	bp.free()
	# базар: цены от ECON (trade {r: {sell, buy}}) → кнопки «Продать / Купить» → SimCmd.trade партией 100
	var made := _make_hud(0)
	var hud: CityHud = made[0]
	var sel: SelectionModel = made[1]
	var log: Array = made[3]
	# Бозора в начале поддельного города ещё нет: раздел обмена строится по ценам в панели — берём своё
	# готовое здание без найма (Бозор, иначе любое) и даём ему цены
	var bz := defs.building(&"bozor")
	var bt := city.buildings()
	var bz_h := 0
	for b in bt.hw:
		if bt.owner[b] == 0 and bt.state[b] == BuildingTable.State.ACTIVE and defs.b_trains[bt.btype[b]].is_empty() \
				and (bz_h == 0 or bt.btype[b] == bz):
			bz_h = bt.handle(b)
	if bz_h == 0:
		SimHarness.check(false, "в поддельном городе есть своё готовое здание без найма")
	else:
		sel.set_selection(PackedInt32Array([bz_h]))
		hud.refresh_now(true)
		var d := city.building_panel(bz_h)
		var food := defs.res(&"food")
		var stone := defs.res(&"stone")
		var gold := defs.res(&"gold")
		d["trade"] = {food: {"sell": 40, "buy": 110}, stone: {"sell": 50, "buy": -1}}
		hud.bottom.building.show_panel(d)
		var sell := hud.bottom.building.get_node_or_null("Trade_food_sell") as Button
		var buy_stone := hud.bottom.building.get_node_or_null("Trade_stone_buy") as Button
		SimHarness.check(sell != null and buy_stone != null and buy_stone.disabled and sell.text.contains("40"),
			"базар: кнопки обмена по ценам ECON («%s»; купить камень — нельзя)" % (sell.text if sell else ""))
		log.clear()
		if sell:
			sell.emit_signal("pressed")
		var buy := hud.bottom.building.get_node_or_null("Trade_food_buy") as Button
		if buy:
			buy.emit_signal("pressed")
		SimHarness.check(log.size() == 2 and (log[0] as PackedInt32Array) == SimCmd.trade(bz_h, food, gold, 100000)
			and (log[1] as PackedInt32Array) == SimCmd.trade(bz_h, gold, food, 100000), "«Продать» / «Купить» → TRADE партией 100")
	hud.queue_free()
	(made[2] as Node).queue_free()


## Новая партия у драйвера (сигнал started, новое окно чтения): интерфейс и ввод перестраиваются сами;
## перед чтением GameQuery — driver.sync() (GameDriver: шаг в фоне)
func _test_restart() -> void:
	print("[новая партия, sync драйвера]")
	var drv := SyncDriver.new()
	drv.autostart = false
	root.add_child(drv)
	drv.start(1)
	for i in 30:
		drv.step()
	var sel := SelectionModel.new()
	var inp := RtsInput.new()
	inp.to_world = func(s: Vector2) -> Vector3: return Vector3(s.x * 0.1, 0.0, s.y * 0.1)
	inp.to_screen = func(w: Vector3) -> Vector2: return Vector2(w.x, w.z) * 10.0
	inp.view_rect = func() -> Rect2: return Rect2(0, 0, 1920, 1080)
	inp.setup(drv.query, sel, 0, drv.issue, null, drv)
	root.add_child(inp)
	var hud := CityHud.new()
	root.add_child(hud)
	hud.setup(drv.query, drv, sel, 0, null, inp)
	var old := drv.query
	var mine := old.units_of(0)
	sel.set_selection(mine.slice(0, 5))
	sel.set_group(2)
	inp.begin_place(old.defs().building(&"uy"))
	drv.syncs = 0
	hud.refresh_now()
	inp.order_button(SimCmd.Op.STOP)
	hud._process(CityHud.MAP_HZ + 0.01)
	SimHarness.check(drv.syncs >= 4, "перед чтением GameQuery — driver.sync() (%d раз)" % drv.syncs)
	drv.start(2)
	SimHarness.check(hud.query == drv.query and inp.query == drv.query and hud.query != old,
		"новая партия: интерфейс и ввод читают новое окно")
	SimHarness.check(sel.selected.is_empty() and sel.groups[2].is_empty() and not inp.placement.active(),
		"выделение, группы и постройка прошлой партии сброшены")
	SimHarness.check(hud.notes._cursor == drv.query.events().head and hud.notes.visible_notes().is_empty(),
		"записки читают события новой партии")
	sel.set_selection(drv.query.units_of(0).slice(0, 3))
	hud.refresh_now(true)
	SimHarness.check(hud.info.get("kind") == "units" and hud.bottom.cards.visible, "после новой партии выделение и карточки работают")
	hud.queue_free()
	inp.queue_free()
	drv.queue_free()


# ================================================================= настоящая игра (после слияния GAME)

## Экран ↔ мир для пробы на настоящей игре: 2 пикселя на метр, (0, 0) экрана — rg_origin
const RG_PX := 2.0
var rg_origin := Vector2.ZERO
var rg_log: Array[PackedInt32Array] = []
var rg_t := 100.0


func _test_real_game() -> void:
	var path := _global_class_path(&"GameDriver")
	if path == "" or _global_class_path(&"GameQueryImpl") == "":
		print("[настоящая игра] пропущено: GameDriver ещё не в проекте (ветка пакета; после слияния с GAME проверка идёт сама)")
		return
	var drv: SimDriver = (load(path) as GDScript).new()
	drv.set("autostart", false)
	root.add_child(drv)
	var sel := SelectionModel.new()
	var inp := RtsInput.new()
	var hud := CityHud.new()
	var first := true
	for f: StringName in [&"kokand", &"kipchak"]:
		print("[настоящая игра: %s]" % f)
		drv.call("start_game", 3, f, 0)        # вторая партия — через started → CityHud.rebind
		var q: GameQuery = drv.get("query")
		print("  реализации: ", (drv.get("game") as Object).call("impl_names"))
		for i in 30:
			drv.step()
		var bt := q.buildings()
		var hq := q.players().hq_b[0]
		var hqp := Vector2(bt.x[bt.slot(hq)], bt.z[bt.slot(hq)])
		rg_origin = hqp - Vector2(960, 540) / RG_PX
		if first:
			first = false
			inp.to_world = func(s: Vector2) -> Vector3: return Vector3(rg_origin.x + s.x / RG_PX, 0.0, rg_origin.y + s.y / RG_PX)
			inp.to_screen = func(w: Vector3) -> Vector2: return (Vector2(w.x, w.z) - rg_origin) * RG_PX
			inp.view_rect = func() -> Rect2: return Rect2(0, 0, 1920, 1080)
			var issue := Callable(drv, "issue")
			inp.setup(q, sel, 0, func(c: PackedInt32Array) -> void:
				rg_log.append(c)
				issue.call(c), null, drv)
			root.add_child(inp)
			root.add_child(hud)
			hud.setup(q, drv, sel, 0, null, inp)
		inp.now_s = rg_t
		SimHarness.check(hud.query == q and inp.query == q and hud.faction == f, "интерфейс на окне чтения игры (%s)" % hud.faction)
		var ev := q.events()
		var cur := ev.head
		var defs := q.defs()
		var fi := q.players().faction[0]
		var want := PackedInt32Array()
		for r in defs.f_ui_res[fi]:
			if defs.r_enabled[r] != 0:
				want.append(r)
		SimHarness.check(hud.top.shown_res == want, "балка = ui_res стороны: %s" % ", ".join(Array(hud.top.shown_res).map(func(r: int) -> String: return defs.res_ids[r])))
		# работники: выделение, карточки, сетка = orders_for
		var workers := PackedInt32Array()
		var bs := q.battle()
		for h in q.units_of(0):
			if bs.t_flags[bs.u_type[q.unit_index(h)]] & UnitStats.WORKER:
				workers.append(h)
		sel.set_selection(workers)
		hud.refresh_now(true)
		var orders := q.orders_for(0, workers)
		var ok: bool = not workers.is_empty() and hud.info.get("kind") == "units" and orders.size() >= 3
		for i in orders.size():
			ok = ok and int(hud.bottom.grid.action_at(i).get("op", -1)) == int(orders[i]["op"])
		SimHarness.check(ok, "работники (%d): карточки и сетка = orders_for (%d)" % [workers.size(), orders.size()])
		# ПКМ по ближайшей жиле → GATHER
		var N := q.nodes()
		var node := 0
		var bd := INF
		for n in N.hw:
			if N.ntype[n] >= 0 and N.amount_milli[n] != 0 and defs.n_scatter_kind[N.ntype[n]] < 0:
				var d := Vector2(N.x[n], N.z[n]).distance_to(hqp)
				if d < bd:
					bd = d
					node = N.handle(n)
		var np := Vector2(N.x[N.slot(node)], N.z[N.slot(node)])
		_rg_click(inp, MOUSE_BUTTON_RIGHT, _rg_scr(np))
		var got := _rg_take()
		SimHarness.check(got.size() == 1 and got[0][0] == SimCmd.Op.GATHER and SimCmd.arg(got[0], 0) == node,
			"ПКМ по жиле в %.0f м → GATHER" % bd)
		# ставка: панель здания, найм
		sel.set_selection(PackedInt32Array([hq]))
		hud.refresh_now(true)
		var trains: Array = q.building_panel(hq).get("trains", [])
		SimHarness.check(hud.bottom.building.visible and not trains.is_empty(), "ставка — панель здания, найм: %d" % trains.size())
		if not defs.b_ability[defs.f_hq[fi]].is_empty():
			var st_lab: Label = hud.bottom.building._ability_state
			SimHarness.check(st_lab != null and st_lab.text != "", "умение ставки по панели ECON: «%s»" % (st_lab.text if st_lab else ""))
		hud.train(hq, int(trains[0]["utype"]))
		got = _rg_take()
		SimHarness.check(got.size() == 1 and got[0] == SimCmd.train(hq, int(trains[0]["utype"]), 1), "кнопка найма → TRAIN")
		# «Хозяйство»: первая доступная постройка у ставки → BUILD
		sel.set_selection(workers)
		hud.open_tab(&"economy")
		var placed := false
		for b: Dictionary in q.build_menu(0, &"economy"):
			if not b["enabled"]:
				continue
			var spot := _rg_spot(q, int(b["btype"]), hqp)
			if spot == Vector2.INF:
				continue
			hud.begin_place(int(b["btype"]))
			inp.handle(_rg_motion(_rg_scr(spot)))
			_rg_click(inp, MOUSE_BUTTON_LEFT, _rg_scr(spot))
			got = _rg_take()
			placed = got.size() == 1 and got[0][0] == SimCmd.Op.BUILD and SimCmd.arg(got[0], 0) == int(b["btype"])
			print("  постройка: %s" % b["name"])
			break
		SimHarness.check(placed, "вкладка «Хозяйство»: ЛКМ по месту → BUILD")
		# «Укрепления»: стена ЛКМ-ЛКМ-ПКМ → BUILD_WALL
		hud.open_tab(&"fort")
		var walled := false
		for b: Dictionary in q.build_menu(0, &"fort"):
			if not b["enabled"] or defs.b_kind[int(b["btype"])] != Defs.BKind.WALL:
				continue
			hud.begin_place(int(b["btype"]))
			var a := hqp + Vector2(40, 30)
			var c := hqp + Vector2(70, 30)
			for pt in [a, c]:
				inp.handle(_rg_motion(_rg_scr(pt)))
				_rg_click(inp, MOUSE_BUTTON_LEFT, _rg_scr(pt))
			_rg_click(inp, MOUSE_BUTTON_RIGHT, _rg_scr(c))
			got = _rg_take()
			walled = got.size() == 1 and got[0][0] == SimCmd.Op.BUILD_WALL and SimCmd.wall_points(got[0]).size() == 2
			print("  стена: %s" % b["name"])
			break
		SimHarness.check(walled, "вкладка «Укрепления»: стена ЛКМ-ЛКМ-ПКМ → BUILD_WALL")
		hud.open_tab(&"orders")
		# 30 с игры: приказы приняты, записка о найме
		for i in 900:
			drv.step()
		hud.notes.poll()
		hud.refresh_now(true)
		hud.bottom.minimap.refresh()
		var rej := PackedStringArray()
		var r := ev.range_since(cur)
		for s in range(r.x, r.y):
			var i := ev.at(s)
			if ev.e_kind[i] == SimEvents.Ev.CMD_REJECTED and ev.e_player[i] == 0:
				rej.append("%s/%d" % [SimCmd.name_of(ev.e_a[i]), ev.e_b[i]])
		SimHarness.check(rej.is_empty(), "игра приняла все приказы интерфейса%s" % ("" if rej.is_empty() else ": отказы " + str(rej)))
		var green := hud.notes.visible_notes().filter(func(n: Dictionary) -> bool: return n["seal"] == CityNotes.Seal.GREEN)
		SimHarness.check(not green.is_empty(), "записка о найме: «%s»" % (green[0]["text"] if not green.is_empty() else ""))
		sel.set_selection(PackedInt32Array())
		var idle := q.idle_workers(0)
		inp.handle(_rg_key(KEY_PERIOD))
		SimHarness.check(sel.selected.size() == mini(1, idle.size()) and (idle.is_empty() or sel.selected[0] == idle[0]),
			"«.» — свободный работник (свободных %d)" % idle.size())
		var latin := _latin_texts(hud.root)
		SimHarness.check(latin.is_empty(), "все надписи по-русски%s" % ("" if latin.is_empty() else ": " + str(latin)))
		# замеры на настоящем окне чтения
		var t0 := Time.get_ticks_usec()
		for i in 30:
			hud.refresh_now()
		var ui_ms := (Time.get_ticks_usec() - t0) / 30000.0
		t0 = Time.get_ticks_usec()
		for i in 20:
			hud.bottom.minimap.refresh()
		var map_ms := (Time.get_ticks_usec() - t0) / 20000.0
		t0 = Time.get_ticks_usec()
		for i in 100:
			q.pick(0, hqp + Vector2(i * 0.3, 5.0), 2.5)
		var pick_ms := (Time.get_ticks_usec() - t0) / 100000.0
		print("  замер: панели %.3f мс, миникарта %.3f мс, pick %.3f мс (%d юнитов в игре)" % [ui_ms, map_ms, pick_ms, bs.n])
		SimHarness.check(ui_ms < 4.0 and map_ms < 4.0, "обновления дешёвые и на настоящей игре")
	hud.queue_free()
	inp.queue_free()
	drv.queue_free()


func _global_class_path(cls: StringName) -> String:
	for c: Dictionary in ProjectSettings.get_global_class_list():
		if c["class"] == cls:
			return c["path"]
	return ""


## Место для постройки у точки c (кругами), INF — нет
func _rg_spot(q: GameQuery, btype: int, c: Vector2) -> Vector2:
	for r in range(20, 120, 6):
		for k in 16:
			var a := TAU * k / 16.0
			var p := q.snap(btype, c + Vector2(cos(a), sin(a)) * r, 0)
			if q.check_place(0, btype, p, 0) == NavApi.Why.OK:
				return p
	return Vector2.INF


func _rg_scr(w: Vector2) -> Vector2:
	return (w - rg_origin) * RG_PX


func _rg_take() -> Array[PackedInt32Array]:
	var o := rg_log.duplicate()
	rg_log.clear()
	return o


func _rg_click(inp: RtsInput, button: int, at: Vector2) -> void:
	rg_t += 1.0
	inp.now_s = rg_t
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = at
		inp.handle(e)


func _rg_motion(at: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	return e


func _rg_key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	return e


## Город на 1000+ своих юнитов (ARCHITECTURE §16): рамка, двойной щелчок, сводка выделения и сетка — дёшево
func _test_big_city() -> void:
	print("[город на 1000+ юнитов]")
	for i in 32:
		city.sim.add_squad(0, "sarboz", 30, Vector2(-300.0 + (i % 8) * 70.0, -300.0 + (i / 8) * 60.0), 0.0,
			BattleSim.Formation.LINE, 15, "", true, 0.3)
	var made := _make_hud(0)
	var hud: CityHud = made[0]
	var sel: SelectionModel = made[1]
	var inp: RtsInput = made[2]
	var n := city.units_of(0).size()
	var si := SelectionImpl.new(city, sel, 0)
	# экран ↔ мир как в _make_hud: 10 пикселей на метр
	var to_s := func(w: Vector3) -> Vector2: return Vector2(w.x, w.z) * 10.0
	var to_w := func(sp: Vector2) -> Vector3: return Vector3(sp.x * 0.1, 0.0, sp.y * 0.1)
	var small := Rect2(Vector2(-300, -300) * 10.0, Vector2(80, 60) * 10.0)
	var t0 := Time.get_ticks_usec()
	var got := 0
	for i in 10:
		got = si.box(small, false, to_s, to_w)
	var box_cull := (Time.get_ticks_usec() - t0) / 10000.0
	t0 = Time.get_ticks_usec()
	for i in 10:
		si.box(small, false, to_s)
	var box_full := (Time.get_ticks_usec() - t0) / 10000.0
	var same := sel.selected.size() == got and got >= 30
	t0 = Time.get_ticks_usec()
	si.box(Rect2(-1e5, -1e5, 2e5, 2e5), false, to_s, to_w)
	var all_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var all_n := sel.selected.size()
	t0 = Time.get_ticks_usec()
	for i in 10:
		hud.refresh_now()
	var ui_ms := (Time.get_ticks_usec() - t0) / 10000.0
	# курсор по смыслу (12 раз в секунду) и протяжка ПКМ при 1000 выделенных
	inp.cursor_kind(Vector2(900, 500))
	t0 = Time.get_ticks_usec()
	for i in 100:
		inp.cursor_kind(Vector2(900 + i, 500))
	var cur_ms := (Time.get_ticks_usec() - t0) / 100000.0
	# из них поиск цели под курсором — GameQuery.pick (FakeCity перебирает всех; у GAME — своя цена)
	t0 = Time.get_ticks_usec()
	for i in 100:
		city.pick(0, Vector2(90.0 + i * 0.1, 50.0), 2.5)
	var pick_ms := (Time.get_ticks_usec() - t0) / 100000.0
	cur_ms = maxf(0.0, cur_ms - pick_ms)
	print("  замер: %d своих юнитов; рамка с отсечением %.2f мс (без него %.2f мс), рамка на всех %.1f мс (%d), панели с выделением всех %.2f мс, курсор %.3f мс без pick (pick FakeCity %.3f мс)" % [
		n, box_cull, box_full, all_ms, all_n, ui_ms, cur_ms, pick_ms])
	SimHarness.check(n >= 1000 and same and box_cull < box_full, "рамка с отсечением выделяет то же (%d) и быстрее" % got)
	# пределы с запасом на загруженную машину (на свободной: рамка ~2 мс, панели ~0,4 мс, курсор ~0,1 мс)
	SimHarness.check(box_cull < 20.0 and ui_ms < 8.0 and cur_ms < 2.0, "рамка %.2f мс, панели %.2f мс, курсор %.3f мс при %d юнитах" % [box_cull, ui_ms, cur_ms, n])
	hud.queue_free()
	inp.queue_free()


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
	# содержание войска — из Defs по живым своим юнитам
	var want_up := 0
	var bs0 := city.sim
	for u in bs0.n:
		if bs0.u_owner[u] == p and bs0.u_life[u] == BattleSim.Life.ALIVE:
			var ui := defs.unit(StringName(bs0.type_ids[bs0.u_type[u]]))
			want_up += defs.u_upkeep_milli_min[ui] if ui >= 0 else 0
	hud.refresh_now(true)
	SimHarness.check(hud.top.upkeep_milli == want_up and want_up > 0, "содержание войска на балке: %s еды/мин" % String.num(want_up / 1000.0, 1))
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
		if ch is Button and ch.size.x >= CityBuildingPanel.TRAIN and ch.name != "Ability":
			trains += 1
	SimHarness.check(trains == (panel.get("trains", []) as Array).size(), "кнопок найма = trains (%d)" % trains)
	log.clear()
	hud.train(hq, int(panel["trains"][0]["utype"]))
	SimHarness.check(log.size() == 1 and (log[0] as PackedInt32Array) == SimCmd.train(hq, int(panel["trains"][0]["utype"]), 1),
		"кнопка найма → TRAIN(ставка, работник, 1)")
	# умение ставки: у Урды — кнопка Ҳашара (из Defs.b_ability), у кыпчаков — нет
	var abtn := hud.bottom.building.get_node_or_null("Ability") as Button
	var has_ab := not defs.b_ability[defs.f_hq[f]].is_empty()
	SimHarness.check((abtn != null) == has_ab, "кнопка умения ставки: %s" % ("есть" if has_ab else "нет"))
	if abtn:
		log.clear()
		abtn.emit_signal("pressed")
		var said := hud.notes.visible_notes()
		SimHarness.check(log.size() == 1 if RtsInput.has_builder("ability") else (not said.is_empty() and String(said[0]["text"]).contains("Ҳашар")),
			"кнопка Ҳашара — приказ или записка «ещё не готово»")
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
	if fid == "kokand":
		# тўғон: удар — «под ударом!» один раз за 15 с, разрушение — «поля сохнут»
		var tg := defs.building(&"togon")
		var tg_h := 0
		var btab := city.buildings()
		for b in btab.hw:
			if btab.owner[b] == p and btab.btype[b] == tg:
				tg_h = btab.handle(b)
		for k in 3:
			ev.push(SimEvents.Ev.BUILDING_HIT, p, tg_h, 5000, 0, Vector2(30, 40))
		var hit_added := hud.notes.poll()
		ev.push(SimEvents.Ev.BUILDING_DESTROYED, p, tg_h, tg, 0, Vector2(30, 40))
		hud.notes.poll()
		var top_text := String(hud.notes.visible_notes()[0]["text"])
		SimHarness.check(hit_added == 1 and top_text.contains("сохнут"), "тўғон: «под ударом» один раз (%d), затем «%s»" % [hit_added, top_text])
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


## Надписи с латиницей (кроме клавиш: одна буква, WASD, Del, Shift+K, F1…)
func _latin_texts(n: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var re := RegEx.create_from_string("[A-Za-z]{2,}")
	var keys := ["WASD", "Del", "Shift", "Ctrl", "Esc", "Tab"]
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
