extends SceneTree
## Управление «Города» (ARCHITECTURE §15, UI): синтетические InputEvent → точные массивы SimCmd.
## Матрица ПКМ (земля, враг, узел, своё поле, своя стройка, своё здание с наймом, башня, Ctrl — простая атака),
## двойной ПКМ, ПКМ с протяжкой (линия), Shift (очередь), инструмент стены ЛКМ-ЛКМ-ЛКМ-ПКМ, постройка с
## поворотом, клавиши H / F / U / R / G / K / V / N / Tab / P / + / − / «.», группы Ctrl+N / N, рамка и двойной
## щелчок, взведённые приказы с кнопок (ЛКМ по карте и миникарте), стойка и рецепт по кругу, курсор по смыслу,
## буквы вкладки стройки, меню (F10, Esc), карточки отрядов. Работает на FakeCity.
##   godot --headless --path ordo --script res://tests/test_input.gd

## Экран ↔ мир: 10 пикселей на метр, (0, 0) экрана — точка мира ORIGIN
const PX := 10.0
const ORIGIN := Vector2(-200.0, -300.0)

var city: FakeCity
var sel: SelectionModel
var inp: RtsInput
var out: Array[PackedInt32Array] = []
var t := 100.0


func _init() -> void:
	city = FakeCity.new()
	city.setup(1)
	for i in 30:
		city.step()
	sel = SelectionModel.new()
	inp = RtsInput.new()
	inp.to_world = func(s: Vector2) -> Vector3: return Vector3(ORIGIN.x + s.x / PX, 0.0, ORIGIN.y + s.y / PX)
	inp.to_screen = func(p: Vector3) -> Vector2: return (Vector2(p.x, p.z) - ORIGIN) * PX
	inp.view_rect = func() -> Rect2: return Rect2(_scr(Vector2(-60, -40)), Vector2(4000, 3000))
	inp.setup(city, sel, 0, func(c: PackedInt32Array) -> void: out.append(c))
	root.add_child(inp)
	inp.now_s = t
	_test_actions()
	_test_rmb_matrix()
	_test_rmb_variants()
	_test_keys()
	_test_groups()
	_test_box_and_double()
	_test_placement()
	_test_wall_tool()
	_test_idle()
	_test_armed()
	_test_city_keys()
	_test_kipchak()
	_test_cursor()
	_test_hud_blocks()
	_test_hud_extras()
	SimHarness.finish(self)


func _test_hud_blocks() -> void:
	print("[интерфейс заслоняет мир]")
	var hud := CityHud.new()
	root.add_child(hud)
	hud.setup(city, null, sel, 0, null, inp)
	var vs := hud.view_size()
	var sar := _squad_units(0, "sarboz")
	sel.set_selection(sar)
	_click(MOUSE_BUTTON_LEFT, Vector2(vs.x * 0.5, vs.y - 30))
	_click(MOUSE_BUTTON_RIGHT, Vector2(vs.x * 0.5, vs.y - 30))
	SimHarness.check(sel.selected == sar and _take().is_empty(), "щелчки по нижней панели не идут в мир (окно %s)" % vs)
	_click(MOUSE_BUTTON_RIGHT, Vector2(vs.x * 0.5, vs.y * 0.5))
	SimHarness.check(_take().size() == 1, "щелчок по миру над панелью — приказ")
	SimHarness.check(hud.blocks_edge_pan(Vector2(vs.x - 3, vs.y - 120)), "край экрана над сеткой приказов камеру не двигает")
	SimHarness.check(not hud.blocks_edge_pan(Vector2(vs.x * 0.5, vs.y - 1)), "самая нижняя кромка — двигает")
	SimHarness.check(not hud.blocks_edge_pan(Vector2(vs.x - 2, vs.y * 0.5)), "край над миром — двигает")
	hud.queue_free()


# ================================================================= помощники

func _scr(w: Vector2) -> Vector2:
	return (w - ORIGIN) * PX


func _w(s: Vector2) -> Vector2:
	return ORIGIN + s / PX


func _mb(button: int, pressed: bool, at: Vector2, shift := false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = at
	e.shift_pressed = shift
	return e


func _motion(at: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	return e


func _key(code: int, ctrl := false, shift := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	return e


func _click(button: int, at: Vector2, shift := false) -> void:
	t += 1.0
	inp.now_s = t
	inp.handle(_mb(button, true, at, shift))
	inp.handle(_mb(button, false, at, shift))


func _take() -> Array[PackedInt32Array]:
	var o := out.duplicate()
	out.clear()
	return o


func _same(got: Array[PackedInt32Array], want: Array, what: String) -> void:
	var ok := got.size() == want.size()
	for i in mini(got.size(), want.size()):
		ok = ok and got[i] == (want[i] as PackedInt32Array)
	SimHarness.check(ok, what)
	if not ok:
		print("    получено: ", got.map(func(c: PackedInt32Array) -> String: return SimCmd.name_of(c[0]) + str(c)))
		print("    ожидалось: ", want.map(func(c: PackedInt32Array) -> String: return SimCmd.name_of(c[0]) + str(c)))


## Отряд стороны team (не одиночка), его бойцы-описатели
func _squad_units(team: int, type_id: String) -> PackedInt32Array:
	var bs := city.sim
	for s in bs.squads:
		if bs.sq_side[s] == team and bs.sq_single[s] == 0 and bs.type_ids[bs.sq_type[s]] == type_id and bs.sq_alive[s] > 1:
			var hs := PackedInt32Array()
			for m in bs.sq_members[s]:
				if bs.u_life[m] == BattleSim.Life.ALIVE:
					hs.append(city.unit_handle(m))
			return hs
	return PackedInt32Array()


func _workers(team: int, n: int) -> PackedInt32Array:
	var bs := city.sim
	var hs := PackedInt32Array()
	for u in bs.n:
		if bs.u_side[u] == team and bs.u_life[u] == BattleSim.Life.ALIVE and bs.t_flags[bs.u_type[u]] & UnitStats.WORKER:
			hs.append(city.unit_handle(u))
			if hs.size() >= n:
				break
	return hs


func _building(p: int, id: StringName, state := BuildingTable.State.ACTIVE) -> int:
	var bt := city.buildings()
	var want := city.defs().building(id)
	for b in bt.hw:
		if bt.owner[b] == p and bt.btype[b] == want and bt.state[b] == state:
			return bt.handle(b)
	return 0


func _bpos(h: int) -> Vector2:
	var bt := city.buildings()
	return Vector2(bt.x[bt.slot(h)], bt.z[bt.slot(h)])


# ================================================================= проверки

func _test_actions() -> void:
	print("[действия InputMap]")
	var miss := PackedStringArray()
	for a in ["ordo_select", "ordo_order", "ordo_stop", "ordo_formation", "ordo_kachyp", "ordo_fire_mode", "ordo_war_cry",
			"ordo_squad", "ordo_pack", "ordo_idle_worker", "ordo_group_1", "ordo_group_9", "ordo_pause", "ordo_speed_up",
			"ordo_speed_down", "ordo_mute"]:
		if not InputMap.has_action(a):
			miss.append(a)
	SimHarness.check(miss.is_empty(), "все действия ordo_* есть (%s)" % ("нет: " + str(miss) if not miss.is_empty() else "ок"))


func _test_rmb_matrix() -> void:
	print("[ПКМ по смыслу цели]")
	var sar := _squad_units(0, "sarboz")
	SimHarness.check(sar.size() > 10, "отряд сарбозов найден (%d)" % sar.size())
	var rep := PackedInt32Array([sar[0]])
	sel.set_selection(sar)
	# земля → MOVE: один описатель на отряд (compact), шагом, без угла, без очереди
	var g := Vector2(60.0, -150.0)
	_click(MOUSE_BUTTON_RIGHT, _scr(g))
	_same(_take(), [SimCmd.move(rep, _w(_scr(g)), false, NAN, false)], "ПКМ по земле → MOVE (описатель отряда один)")
	# враг → ATTACK (дозор кыпчаков)
	var kip := _squad_units(1, "jooker")
	var u := city.unit_index(kip[0])
	var ep := Vector2(city.sim.u_x[u], city.sim.u_z[u])
	_click(MOUSE_BUTTON_RIGHT, _scr(ep))
	var got := _take()
	SimHarness.check(got.size() == 1 and got[0][SimCmd.H_OP] == SimCmd.Op.ATTACK and SimCmd.ids(got[0]) == rep
		and Ids.kind(SimCmd.arg(got[0], 0)) == Ids.Kind.UNIT and city.sim.u_side[city.unit_index(SimCmd.arg(got[0], 0))] == 1
		and SimCmd.arg(got[0], 1) == 1, "ПКМ по врагу → ATTACK(враг, бегом)")
	# работники: узел (глина) → GATHER
	var wk := _workers(0, 3)
	sel.set_selection(wk)
	var clay := Vector2(142, -132)
	var clay_h := city.pick(0, clay, 2.5)
	_click(MOUSE_BUTTON_RIGHT, _scr(clay))
	_same(_take(), [SimCmd.gather(wk, clay_h)], "работники + ПКМ по залежи → GATHER")
	SimHarness.check(Ids.kind(clay_h) == Ids.Kind.NODE, "под точкой — узел")
	# работники: своя стройка → ASSIST
	var site := _building(0, &"kazarma", BuildingTable.State.SITE)
	if site == 0:
		site = _building(0, &"bozor", BuildingTable.State.SITE)
	_click(MOUSE_BUTTON_RIGHT, _scr(_bpos(site)))
	_same(_take(), [SimCmd.assist(wk, site)], "работники + ПКМ по своей стройке → ASSIST")
	# работники: своё поле (лалми, без работников) → GATHER
	var dala := 0
	var bt := city.buildings()
	for b in bt.hw:
		if bt.owner[b] == 0 and bt.btype[b] == city.defs().building(&"dala") and is_equal_approx(bt.z[b], 98.0):
			dala = bt.handle(b)
	_click(MOUSE_BUTTON_RIGHT, _scr(_bpos(dala)))
	_same(_take(), [SimCmd.gather(wk, dala)], "работники + ПКМ по своему полю → GATHER")
	# смешанное выделение: работники добывают, бойцы идут
	var mixed := wk.duplicate()
	mixed.append_array(sar)
	sel.set_selection(mixed)
	_click(MOUSE_BUTTON_RIGHT, _scr(clay))
	_same(_take(), [SimCmd.gather(wk, clay_h), SimCmd.move(rep, _w(_scr(clay)), false, NAN, false)],
		"работники + бойцы по залежи → GATHER работникам, MOVE бойцам")
	# своё здание с наймом → RALLY
	var urda := _building(0, &"urda")
	sel.set_selection(PackedInt32Array([urda]))
	_click(MOUSE_BUTTON_RIGHT, _scr(g))
	_same(_take(), [SimCmd.rally(urda, _w(_scr(g)), 0)], "выбрана Урда + ПКМ → RALLY")
	# чужой юнит выделен — приказов нет
	sel.set_selection(PackedInt32Array([kip[0]]))
	_click(MOUSE_BUTTON_RIGHT, _scr(g))
	SimHarness.check(_take().is_empty(), "чужое выделение — ПКМ ничего не приказывает")


func _test_rmb_variants() -> void:
	print("[двойной ПКМ, Shift, протяжка]")
	var sar := _squad_units(0, "sarboz")
	var rep := PackedInt32Array([sar[0]])
	sel.set_selection(sar)
	var a := _scr(Vector2(70, -140))
	# двойной ПКМ: второй щелчок в пределах 0,35 с → бегом
	t += 5.0
	inp.now_s = t
	inp.handle(_mb(MOUSE_BUTTON_RIGHT, true, a))
	inp.handle(_mb(MOUSE_BUTTON_RIGHT, false, a))
	inp.now_s = t + 0.2
	inp.handle(_mb(MOUSE_BUTTON_RIGHT, true, a))
	inp.handle(_mb(MOUSE_BUTTON_RIGHT, false, a))
	_same(_take(), [SimCmd.move(rep, _w(a), false, NAN, false), SimCmd.move(rep, _w(a), true, NAN, false)],
		"двойной ПКМ → MOVE, затем MOVE бегом")
	# Shift — в очередь
	_click(MOUSE_BUTTON_RIGHT, a, true)
	_same(_take(), [SimCmd.move(rep, _w(a), false, NAN, true)], "Shift+ПКМ → MOVE в очередь")
	# протяжка ПКМ → MOVE_LINE
	var b := a + Vector2(300, 40)
	t += 5.0
	inp.now_s = t
	inp.handle(_mb(MOUSE_BUTTON_RIGHT, true, a))
	inp.handle(_motion(a + Vector2(100, 10)))
	inp.handle(_motion(b))
	inp.handle(_mb(MOUSE_BUTTON_RIGHT, false, b))
	_same(_take(), [SimCmd.move_line(rep, _w(a), _w(b), false)], "ПКМ с протяжкой → MOVE_LINE (фронт и разворот)")


func _test_keys() -> void:
	print("[клавиши]")
	var sar := _squad_units(0, "sarboz")
	var rep := PackedInt32Array([sar[0]])
	sel.set_selection(sar)
	inp.handle(_key(KEY_H))
	_same(_take(), [SimCmd.stop(rep)], "H → STOP")
	var s := city.sim.u_squad[city.unit_index(sar[0])]
	inp.handle(_key(KEY_F))
	_same(_take(), [SimCmd.formation(rep, (city.sim.sq_form[s] + 1) % 4)], "F → FORMATION (следующий строй)")
	inp.handle(_key(KEY_U))
	_same(_take(), [SimCmd.disband(Ids.make(Ids.Kind.SQUAD, s, city.sim.sq_gen[s]))], "U с отрядом → DISBAND")
	inp.handle(_key(KEY_R))
	_same(_take(), [SimCmd.fire_mode(rep, SimCmd.FIRE_MELEE)], "R → FIRE_MODE рукопашная")
	inp.handle(_key(KEY_G))
	_same(_take(), [SimCmd.kachyp(rep, true)], "G → KACHYP")
	# Shift+K без ставки в выделении — сворачивается своя ставка (у Коканда — тоже приказ; ECON откажет)
	inp.handle(_key(KEY_K, false, true))
	_same(_take(), [SimCmd.pack_all(city.players().hq_b[0])], "Shift+K → PACK_ALL ставки")
	# Del по своему зданию
	var uy := _building(0, &"uy")
	sel.set_selection(PackedInt32Array([uy]))
	inp.handle(_key(KEY_DELETE))
	_same(_take(), [SimCmd.demolish(uy)], "Del по своему дому → DEMOLISH")
	# Esc — снять выделение
	inp.handle(_key(KEY_ESCAPE))
	SimHarness.check(sel.selected.is_empty(), "Esc снимает выделение")


func _test_groups() -> void:
	print("[группы Ctrl+N]")
	var sar := _squad_units(0, "sarboz")
	sel.set_selection(sar)
	inp.handle(_key(KEY_3, true))
	sel.set_selection(PackedInt32Array())
	inp.now_s = 500.0
	inp.handle(_key(KEY_3))
	SimHarness.check(sel.selected == sar, "Ctrl+3, затем 3 — группа вернулась (%d)" % sel.selected.size())
	var wk := _workers(0, 2)
	sel.set_selection(wk)
	inp.handle(_key(KEY_3, false, true))
	SimHarness.check(sel.selected.size() == wk.size() + sar.size(), "Shift+3 — группа добавлена к выделению")
	SimHarness.check(sel.groups[2] == sar, "группа 3 хранится в SelectionModel.groups[2]")


func _test_box_and_double() -> void:
	print("[рамка, двойной щелчок]")
	var sar := _squad_units(0, "sarboz")
	var bs := city.sim
	var u := city.unit_index(sar[0])
	var c := Vector2(bs.u_x[u], bs.u_z[u])
	var a := _scr(c - Vector2(30, 30))
	var b := _scr(c + Vector2(30, 30))
	sel.set_selection(PackedInt32Array())
	t += 5.0
	inp.now_s = t
	inp.handle(_mb(MOUSE_BUTTON_LEFT, true, a))
	inp.handle(_motion(a + Vector2(20, 20)))
	inp.handle(_motion(b))
	inp.handle(_mb(MOUSE_BUTTON_LEFT, false, b))
	var want := PackedInt32Array()
	for x in city.units_of(0):
		var k := city.unit_index(x)
		var p := Vector2(bs.u_x[k], bs.u_z[k])
		if Rect2(c - Vector2(30, 30), Vector2(60, 60)).has_point(p):
			want.append(x)
	var all_in := true
	for x in want:
		all_in = all_in and sel.selected.has(x)
	SimHarness.check(sel.selected.size() >= sar.size() and all_in, "рамка выделила своих внутри (%d)" % sel.selected.size())
	var only_own := true
	for x in sel.selected:
		only_own = only_own and RtsInput.owner_of(city, x) == 0
	SimHarness.check(only_own, "в рамке только свои")
	# двойной щелчок по работнику — все работники на экране
	var wk := _workers(0, 1)
	var wu := city.unit_index(wk[0])
	var wp := _scr(Vector2(bs.u_x[wu], bs.u_z[wu]))
	t += 5.0
	inp.now_s = t
	inp.handle(_mb(MOUSE_BUTTON_LEFT, true, wp))
	inp.handle(_mb(MOUSE_BUTTON_LEFT, false, wp))
	inp.now_s = t + 0.2
	inp.handle(_mb(MOUSE_BUTTON_LEFT, true, wp))
	inp.handle(_mb(MOUSE_BUTTON_LEFT, false, wp))
	var same := sel.selected.size() > 3
	for x in sel.selected:
		same = same and bs.u_type[city.unit_index(x)] == bs.u_type[wu]
	SimHarness.check(same, "двойной щелчок — все деҳқоны на экране (%d)" % sel.selected.size())


func _test_placement() -> void:
	print("[постройка]")
	var defs := city.defs()
	var wk := _workers(0, 2)
	sel.set_selection(wk)
	var uy := defs.building(&"uy")
	var spot := Vector2(100, 200)
	inp.handle(_motion(_scr(spot)))
	inp.begin_place(uy)
	SimHarness.check(inp.placement.active() and not inp.placement.is_wall, "режим постройки уй")
	inp.handle(_key(KEY_R))
	var wheel := _mb(MOUSE_BUTTON_WHEEL_UP, true, _scr(spot))
	SimHarness.check(inp.handle(wheel), "колесо в режиме постройки съедено (камера не приближает)")
	SimHarness.check(inp.placement.rot_q == 2, "R и колесо — поворот на 90° дважды (rot_q 2)")
	SimHarness.check(_take().is_empty(), "R в режиме постройки — не приказ огня")
	var w := _w(_scr(spot))
	_click(MOUSE_BUTTON_LEFT, _scr(spot))
	_same(_take(), [SimCmd.build(wk, uy, city.snap(uy, w, 2), 2)], "ЛКМ → BUILD(работники, уй, место, поворот)")
	SimHarness.check(not inp.placement.active(), "без Shift режим постройки закончился")
	# Shift — ставить ещё
	inp.begin_place(uy)
	var s2 := Vector2(130, 230)
	_click(MOUSE_BUTTON_LEFT, _scr(s2), true)
	SimHarness.check(_take().size() == 1 and inp.placement.active(), "Shift+ЛКМ — поставлен, режим остаётся")
	inp.handle(_key(KEY_ESCAPE))
	SimHarness.check(not inp.placement.active(), "Esc — режим постройки снят")
	# занятое место — приказа нет
	inp.begin_place(uy)
	_click(MOUSE_BUTTON_LEFT, _scr(_bpos(_building(0, &"urda"))))
	SimHarness.check(_take().is_empty() and inp.placement.active(), "на занятом месте приказа нет")
	_click(MOUSE_BUTTON_RIGHT, _scr(spot))
	SimHarness.check(not inp.placement.active() and _take().is_empty(), "ПКМ — отмена постройки")


func _test_wall_tool() -> void:
	print("[инструмент стены]")
	var defs := city.defs()
	var wk := _workers(0, 2)
	sel.set_selection(wk)
	var dv := defs.building(&"devor")
	inp.begin_place(dv)
	SimHarness.check(inp.placement.is_wall, "девор — инструмент стены")
	var pts := [Vector2(60, 220), Vector2(90, 222), Vector2(95, 250)]
	var want := PackedVector2Array()
	for p: Vector2 in pts:
		_click(MOUSE_BUTTON_LEFT, _scr(p))
		want.append(_w(_scr(p)))
	SimHarness.check(_take().is_empty(), "ЛКМ-ЛКМ-ЛКМ — точки цепи, приказа ещё нет")
	_click(MOUSE_BUTTON_RIGHT, _scr(Vector2(0, 0)))
	_same(_take(), [SimCmd.build_wall(wk, dv, want)], "ПКМ — BUILD_WALL(работники, девор, 3 точки)")
	# одна точка и Esc — ничего
	inp.begin_place(dv)
	_click(MOUSE_BUTTON_LEFT, _scr(Vector2(60, 220)))
	inp.handle(_key(KEY_ESCAPE))
	SimHarness.check(_take().is_empty() and not inp.placement.active(), "одна точка + Esc — без приказа")


func _test_idle() -> void:
	print("[свободный работник]")
	sel.set_selection(PackedInt32Array())
	inp.handle(_key(KEY_PERIOD))
	var idle := city.idle_workers(0)
	SimHarness.check(not idle.is_empty() and sel.selected == PackedInt32Array([idle[0]]), "«.» — выделен свободный работник")


func _test_armed() -> void:
	print("[взведённые приказы с кнопок]")
	var sar := _squad_units(0, "sarboz")
	var rep := PackedInt32Array([sar[0]])
	sel.set_selection(sar)
	var g := Vector2(64.0, -146.0)
	inp.order_button(SimCmd.Op.ATTACK_MOVE)
	SimHarness.check(inp.armed == SimCmd.Op.ATTACK_MOVE and _take().is_empty(), "кнопка «В атаку» взводит приказ, сама не приказывает")
	_click(MOUSE_BUTTON_LEFT, _scr(g))
	_same(_take(), [SimCmd.attack_move(rep, _w(_scr(g)))], "затем ЛКМ по земле → ATTACK_MOVE")
	SimHarness.check(inp.armed == SimCmd.Op.NONE and sel.selected == sar, "после приказа снят, выделение то же")
	inp.order_button(SimCmd.Op.MOVE)
	_click(MOUSE_BUTTON_LEFT, _scr(g), true)
	_click(MOUSE_BUTTON_LEFT, _scr(g + Vector2(10, 0)), true)
	_same(_take(), [SimCmd.move(rep, _w(_scr(g)), false, NAN, true), SimCmd.move(rep, _w(_scr(g + Vector2(10, 0))), false, NAN, true)],
		"«Идти» + Shift+ЛКМ дважды → два MOVE в очередь, приказ взведён")
	_click(MOUSE_BUTTON_RIGHT, _scr(g))
	SimHarness.check(inp.armed == SimCmd.Op.NONE and _take().is_empty(), "ПКМ снимает взведённый приказ без приказа")
	# работники: «Добывать» по пустой земле — нет приказа, взведён; по жиле — GATHER
	var wk := _workers(0, 2)
	sel.set_selection(wk)
	inp.order_button(SimCmd.Op.GATHER)
	_click(MOUSE_BUTTON_LEFT, _scr(g))
	SimHarness.check(_take().is_empty() and inp.armed == SimCmd.Op.GATHER, "«Добывать» по пустой земле — ничего, приказ ждёт")
	var clay := Vector2(142, -132)
	_click(MOUSE_BUTTON_LEFT, _scr(clay))
	_same(_take(), [SimCmd.gather(wk, city.pick(0, clay, 2.5))], "«Добывать» + ЛКМ по залежи → GATHER")
	var site := _building(0, &"kazarma", BuildingTable.State.SITE)
	inp.order_button(SimCmd.Op.ASSIST)
	_click(MOUSE_BUTTON_LEFT, _scr(_bpos(site)))
	_same(_take(), [SimCmd.assist(wk, site)], "«Помочь строить» + ЛКМ по стройке → ASSIST")
	# Esc и постройка снимают
	inp.order_button(SimCmd.Op.MOVE)
	inp.handle(_key(KEY_ESCAPE))
	SimHarness.check(inp.armed == SimCmd.Op.NONE and sel.selected == wk, "Esc снимает взведённый приказ (выделение остаётся)")
	inp.order_button(SimCmd.Op.MOVE)
	inp.begin_place(city.defs().building(&"uy"))
	SimHarness.check(inp.armed == SimCmd.Op.NONE and inp.placement.active(), "постройка снимает взведённый приказ")
	inp.placement.cancel()
	# Урда: «Место сбора» + ЛКМ → RALLY
	var urda := _building(0, &"urda")
	sel.set_selection(PackedInt32Array([urda]))
	inp.order_button(SimCmd.Op.RALLY)
	_click(MOUSE_BUTTON_LEFT, _scr(g))
	_same(_take(), [SimCmd.rally(urda, _w(_scr(g)), 0)], "«Место сбора» + ЛКМ → RALLY")
	# без своего выделения кнопка ничего не взводит
	sel.set_selection(PackedInt32Array())
	inp.order_button(SimCmd.Op.MOVE)
	SimHarness.check(inp.armed == SimCmd.Op.NONE, "без выделения кнопка не взводит")


func _test_city_keys() -> void:
	print("[стойка, рецепт, башня, Ctrl+ПКМ, N, V, Tab, P, + / −]")
	var sar := _squad_units(0, "sarboz")
	var rep := PackedInt32Array([sar[0]])
	sel.set_selection(sar)
	var s := city.sim.u_squad[city.unit_index(sar[0])]
	inp.order_button(SimCmd.Op.STANCE)
	_same(_take(), [SimCmd.stance(rep, (city.sim.sq_stance[s] + 1) % 4)], "кнопка «Стойка» → STANCE (следующая по кругу)")
	# пехота по своей башне → GARRISON
	var burj := _building(0, &"burj")
	_click(MOUSE_BUTTON_RIGHT, _scr(_bpos(burj)))
	var foot := PackedInt32Array()
	for h in sar:
		if city.sim.t_flags[city.sim.u_type[city.unit_index(h)]] & UnitStats.MOUNTED == 0:
			foot.append(h)
	_same(_take(), [SimCmd.garrison(foot, burj)], "пехота + ПКМ по своему буржу → GARRISON (пешие, %d из %d)" % [foot.size(), sar.size()])
	# Ctrl+ПКМ по врагу — та же атака (простая, без набега)
	var kip := _squad_units(1, "jooker")
	var u := city.unit_index(kip[0])
	var ep := _scr(Vector2(city.sim.u_x[u], city.sim.u_z[u]))
	t += 1.0
	inp.now_s = t
	var down := _mb(MOUSE_BUTTON_RIGHT, true, ep)
	down.ctrl_pressed = true
	var up := _mb(MOUSE_BUTTON_RIGHT, false, ep)
	up.ctrl_pressed = true
	inp.handle(down)
	inp.handle(up)
	var got := _take()
	SimHarness.check(got.size() == 1 and got[0][SimCmd.H_OP] == SimCmd.Op.ATTACK, "Ctrl+ПКМ по врагу → ATTACK")
	# рецепт печи по кругу
	var bt := city.buildings()
	var kiln := 0
	for b in bt.hw:
		if bt.owner[b] == 0 and bt.state[b] == BuildingTable.State.ACTIVE and not city.defs().b_recipes[bt.btype[b]].is_empty():
			kiln = bt.handle(b)
			break
	sel.set_selection(PackedInt32Array([kiln]))
	inp.order_button(SimCmd.Op.SET_RECIPE)
	got = _take()
	SimHarness.check(kiln != 0 and got.size() == 1 and got[0] == SimCmd.set_recipe(kiln, city.defs().b_recipes[bt.btype[bt.slot(kiln)]][0]),
		"кнопка «Рецепт» у хумдона → SET_RECIPE (первый рецепт)")
	# V у Урды — не клич (Ҳашар ждёт договора), N — тревога (ждёт договора): приказов нет
	sel.set_selection(PackedInt32Array([_building(0, &"urda")]))
	inp.handle(_key(KEY_V))
	inp.handle(_key(KEY_N))
	SimHarness.check(_take().is_empty() == not (RtsInput.has_builder("ability") or RtsInput.has_builder("alarm")),
		"V у Урды и N — без приказа, пока нет SimCmd.ability / alarm")
	SimHarness.check(RtsInput.future_cmd("stop", [rep]) == SimCmd.stop(rep) and RtsInput.future_cmd("nope", []).is_empty(),
		"future_cmd находит строителя SimCmd по имени")
	# Tab — наложения
	var seen: Array[bool] = []
	inp.overlay_toggled.connect(func(on: bool) -> void: seen.append(on))
	inp.handle(_key(KEY_TAB))
	inp.handle(_key(KEY_TAB))
	SimHarness.check(seen == [true, false], "Tab включает и выключает наложения (%s)" % str(seen))
	# P, + / − — пауза и скорость
	var drv := FakeCityDriver.new()
	inp.driver = drv
	inp.handle(_key(KEY_P))
	var paused := drv.paused
	inp.handle(_key(KEY_P))
	inp.handle(_key(KEY_EQUAL))
	var fast := drv.time_scale
	inp.handle(_key(KEY_MINUS))
	inp.handle(_key(KEY_MINUS))
	SimHarness.check(paused and not drv.paused and is_equal_approx(fast, 2.0) and is_equal_approx(drv.time_scale, 0.5),
		"P — пауза и обратно, + — ×2, − − — ×0,5")
	inp.driver = null
	drv.free()


## За кыпчаков (игрок 1): всадники и цели набега, K / Shift+K
func _test_kipchak() -> void:
	print("[кыпчаки: набег, K / Shift+K]")
	var keep := inp
	var sel1 := SelectionModel.new()
	var inp1 := RtsInput.new()
	inp1.to_world = keep.to_world
	inp1.to_screen = keep.to_screen
	inp1.view_rect = keep.view_rect
	inp1.setup(city, sel1, 1, func(c: PackedInt32Array) -> void: out.append(c))
	root.add_child(inp1)
	inp = inp1
	var jook := _squad_units(1, "jooker")
	var rep := PackedInt32Array([jook[0]])
	sel1.set_selection(jook)
	var dala := _building(0, &"dala")
	var koroo := _building(1, &"koroo")
	var sheep := 0
	for h in city.herds().hw:
		if city.herds().owner[h] == 1:
			sheep = city.herds().handle(h)
			break
	SimHarness.check(inp1.is_raid_target(dala) and not inp1.is_raid_target(koroo) and not inp1.is_raid_target(sheep),
		"цель набега: чужое поле — да, свой загон и своё стадо — нет")
	SimHarness.check(keep.is_raid_target(sheep) and keep.is_raid_target(koroo), "для Коканда кыпчакские стадо и короо — цели набега")
	_click(MOUSE_BUTTON_RIGHT, _scr(_bpos(dala)))
	var got := _take()
	var want_op := SimCmd.Op.ATTACK if not RtsInput.has_builder("raid") else int(RtsInput.future_cmd("raid", [rep, dala])[SimCmd.H_OP])
	SimHarness.check(got.size() == 1 and got[0][SimCmd.H_OP] == want_op, "всадники + ПКМ по чужому полю → %s" % SimCmd.name_of(want_op))
	# K по юрте — PACK, Shift+K — PACK_ALL ставки
	var boz := _building(1, &"boz")
	sel1.set_selection(PackedInt32Array([boz]))
	inp1.handle(_key(KEY_K))
	_same(_take(), [SimCmd.pack(boz)], "K по боз үй → PACK")
	inp1.handle(_key(KEY_K, false, true))
	_same(_take(), [SimCmd.pack_all(city.players().hq_b[1])], "Shift+K → PACK_ALL ставки")
	# своё стадо: ПКМ по земле — перегон (HERD_MOVE)
	sel1.set_selection(PackedInt32Array([sheep]))
	var pasture := Vector2(-150, 90)
	_click(MOUSE_BUTTON_RIGHT, _scr(pasture))
	_same(_take(), [SimCmd.herd_move(sheep, _w(_scr(pasture)))], "своё стадо + ПКМ → HERD_MOVE")
	inp = keep
	inp1.queue_free()


func _test_cursor() -> void:
	print("[курсор по смыслу]")
	var K := CityCursor.Kind
	var sar := _squad_units(0, "sarboz")
	sel.set_selection(sar)
	var kip := _squad_units(1, "jooker")
	var u := city.unit_index(kip[0])
	var ep := _scr(Vector2(city.sim.u_x[u], city.sim.u_z[u]))
	var ground := _scr(Vector2(64.0, -146.0))
	SimHarness.check(inp.cursor_kind(ep) == K.ATTACK and inp.cursor_kind(ground) == K.DEFAULT, "бойцы: над врагом — атака, над землёй — простой")
	var wk := _workers(0, 2)
	sel.set_selection(wk)
	var clay := _scr(Vector2(142, -132))
	var site := _scr(_bpos(_building(0, &"kazarma", BuildingTable.State.SITE)))
	SimHarness.check(inp.cursor_kind(clay) == K.GATHER and inp.cursor_kind(site) == K.BUILD, "работники: жила — добыча, стройка — молот")
	inp.order_button(SimCmd.Op.GATHER)
	SimHarness.check(inp.cursor_kind(ground) == K.FORBID and inp.cursor_kind(clay) == K.GATHER, "взведено «Добывать»: земля — нельзя, жила — добыча")
	inp.disarm()
	inp.begin_place(city.defs().building(&"uy"))
	inp.placement.move(_bpos(_building(0, &"urda")))
	SimHarness.check(inp.cursor_kind(ground) == K.FORBID, "призрак на занятом месте — курсор «нельзя»")
	inp.placement.cancel()


## Интерфейс вместе с вводом: буквы вкладки, меню, миникарта, карточки, записки умений
func _test_hud_extras() -> void:
	print("[вкладки, меню, миникарта, карточки]")
	var hud := CityHud.new()
	root.add_child(hud)
	var drv := FakeCityDriver.new()
	hud.setup(city, drv, sel, 0, null, inp)
	inp.driver = drv
	# буква на вкладке «Хозяйство» — постройка
	var wk := _workers(0, 2)
	sel.set_selection(wk)
	hud.open_tab(&"economy")
	var menu := city.build_menu(0, &"economy")
	var first: Dictionary = {}
	for b in menu:
		if b["enabled"] and String(b["hotkey"]) != "":
			first = b
			break
	inp.handle(_key(OS.find_keycode_from_string(String(first["hotkey"]))))
	SimHarness.check(inp.placement.active() and inp.placement.btype == int(first["btype"]),
		"вкладка «Хозяйство»: буква %s — призрак «%s»" % [first["hotkey"], first["name"]])
	inp.placement.cancel()
	hud.open_tab(&"orders")
	# кнопка сетки взведена — горит
	var sar := _squad_units(0, "sarboz")
	sel.set_selection(sar)
	inp.order_button(SimCmd.Op.MOVE)
	hud.refresh_now()
	var lit := false
	for i in CityOrderGrid.COLS * CityOrderGrid.ROWS:
		if int(hud.bottom.grid.action_at(i).get("op", -1)) == SimCmd.Op.MOVE:
			lit = hud.bottom.grid._buttons[i].modulate.r > 1.0
	SimHarness.check(lit, "взведённая кнопка «Идти» подсвечена")
	# миникарта: ЛКМ со взведённым приказом — приказ в точку карты; ПКМ — приказ по смыслу
	var mm := hud.bottom.minimap
	var at := Vector2(120, 90)
	var e := _mb(MOUSE_BUTTON_LEFT, true, at)
	mm._gui_input(e)
	var rep := PackedInt32Array([sar[0]])
	_same(_take(), [SimCmd.move(rep, mm.map_to_world(at), false, NAN, false)], "миникарта: взведённое «Идти» + ЛКМ → MOVE в точку карты")
	mm._gui_input(_mb(MOUSE_BUTTON_RIGHT, true, at))
	_same(_take(), [SimCmd.move(rep, mm.map_to_world(at), false, NAN, false)], "миникарта: ПКМ → MOVE в точку карты")
	# карточки: щелчок — только этот отряд, Shift — без него
	var both := sar.duplicate()
	var kil := _squad_units(0, "kilichboz")
	both.append_array(kil)
	sel.set_selection(both)
	var info := city.selection_info(both)
	var card: Dictionary = {}
	for c: Dictionary in info["cards"]:
		if c["type"] == "sarboz":
			card = c
	hud.select_card(card, false)
	SimHarness.check(sel.selected == sar, "карточка сарбозов — в выделении только они (%d)" % sel.selected.size())
	sel.set_selection(both)
	hud.select_card(card, true)
	SimHarness.check(sel.selected == kil, "Shift+карточка — сарбозы убраны (%d)" % sel.selected.size())
	# V у Урды: записка «Ҳашар — ещё не готово», пока нет SimCmd.ability
	sel.set_selection(PackedInt32Array([_building(0, &"urda")]))
	inp.handle(_key(KEY_V))
	var notes := hud.notes.visible_notes()
	SimHarness.check(RtsInput.has_builder("ability") or (not notes.is_empty() and String(notes[0]["text"]).contains("Ҳашар")),
		"V у Урды — записка о Ҳашаре: «%s»" % (notes[0]["text"] if not notes.is_empty() else ""))
	_take()
	# меню: Esc при пустом выделении и F10; пауза и ввод выключены; Esc закрывает
	sel.set_selection(PackedInt32Array())
	inp.handle(_key(KEY_ESCAPE))
	SimHarness.check(hud.menu.is_open() and drv.paused and not inp.enabled, "Esc при пустом выделении — меню, игра на паузе, ввод выключен")
	hud.menu.show_help()
	SimHarness.check(hud.menu.help_open(), "«Управление» — памятка клавиш")
	hud.menu._unhandled_input(_key(KEY_ESCAPE))
	SimHarness.check(hud.menu.is_open() and not hud.menu.help_open(), "Esc в памятке — назад в меню")
	hud.menu._unhandled_input(_key(KEY_ESCAPE))
	SimHarness.check(not hud.menu.is_open() and not drv.paused and inp.enabled, "Esc в меню — закрыто, пауза снята, ввод вернулся")
	inp.handle(_key(KEY_F10))
	var by_f10 := hud.menu.is_open()
	hud.menu.close()
	SimHarness.check(by_f10, "F10 — меню")
	var quit := [0]
	hud.quit_requested.connect(func() -> void: quit[0] += 1)
	hud.request_quit()
	SimHarness.check(quit[0] == 1, "«Выйти» — сигнал quit_requested (слушает сцена игры)")
	inp.driver = null
	hud.queue_free()
	drv.free()
