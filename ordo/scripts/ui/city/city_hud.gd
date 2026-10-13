class_name CityHud
extends CanvasLayer
## Интерфейс «Города» (ТЗ §12, ARCHITECTURE §14, §19.6): верхняя балка, нижняя панель (пояс-орнамент,
## миникарта, карточки или панель здания, вкладки и сетка приказов), записки с печатями, курсор-
## наконечник. Читает только GameQuery (FakeCity до I4) и SimEvents; приказы — через RtsInput (SimCmd).
## Обновление панелей 6–7 Гц, миникарты 4 Гц, записки — каждый кадр по курсору событий.
##
## Сборка в сцене «Города» (gorod.tscn, VIEW; образец — scripts/ui/city/city_look.gd):
##   var selection := SelectionModel.new()                      # его же читает SelectionView
##   var input := RtsInput.new(); add_child(input)              # ПОСЛЕ RtsCamera (колесо в режиме постройки)
##   input.set_ghost(ghost_view)                                # GhostView: show_building / show_wall / hide
##   input.setup(driver.query, selection, driver.local_player, driver.issue, camera, driver)
##   var hud := CityHud.new(); add_child(hud)
##   hud.setup(driver.query, driver, selection, driver.local_player, camera, input)
##   camera.presets_enabled = false                             # цифры — группы; виды — F5–F8
##   camera.edge_blocked = hud.blocks_edge_pan
##   input.overlay_toggled.connect(overlay_view.set_enabled)    # Tab — наложения (VIEW)
##   hud.restart_requested.connect(...); hud.quit_requested.connect(...)   # меню (иначе перезагрузка / выход)
## Меню (≡, F10, Esc при пустом выделении) ставит SimDriver на паузу и выключает ввод, пока открыто.
## Драйвер начал игру заново (сигнал started, новое окно чтения driver.query) — интерфейс и ввод
## перестраиваются сами (rebind). Перед чтением GameQuery зовётся driver.sync(), если он есть (GameDriver:
## шаг в фоне) — поэтому интерфейс читает 4–10 раз в секунду, а не каждый кадр.

signal tab_opened(tab: StringName)
## Меню: «Начать заново» / «Выйти» (никто не слушает — перезагрузка сцены / выход из игры)
signal restart_requested
signal quit_requested

const UI_HZ := 0.15
const MAP_HZ := 0.25
## Записки читают события 10 раз в секунду (курсор событий не теряет ни одного)
const NOTES_HZ := 0.1
## Тяжёлое (чистка выделения от мёртвых, сетка приказов) — при смене выделения/вкладки и раз в HEAVY_S
const HEAVY_S := 1.0
## Большое выделение (больше BIG_SEL описателей) — сводку карточек спрашиваем реже, раз в BIG_INFO_S
const BIG_SEL := 200
const BIG_INFO_S := 0.5

var query: GameQuery
var driver: SimDriver
var selection: SelectionModel
var player := 0
var camera: Camera3D
var input: RtsInput
var faction := &"kokand"

var root: Control
var top: CityTopBar
var bottom: CityBottomPanel
var notes: CityNotes
var menu: CityMenu
var info := {}

var _box: Control
var _box_rect := Rect2()
var _line := PackedVector2Array()
var _t_ui := 0.0
var _t_map := 0.0
var _t_heavy := 0.0
var _t_info := 0.0
var _t_notes := 0.0
var _ready_done := false
## У драйвера есть sync() (GameDriver: дождаться фонового шага перед чтением)
var _can_sync := false
var _in_refresh := false
## Выделение сменилось с прошлого обновления (сигнал SelectionModel.changed)
var _sel_dirty := true
## Всё выделенное — своё (пересчёт при смене выделения)
var _own := false


func setup(q: GameQuery, drv: SimDriver, sel: SelectionModel, p: int, cam: Camera3D = null, inp: RtsInput = null) -> void:
	query = q
	driver = drv
	selection = sel
	player = p
	camera = cam
	input = inp
	layer = 10
	name = "CityHud"
	_can_sync = driver != null and driver.has_method("sync")
	if driver and not driver.started.is_connected(_on_driver_started):
		driver.started.connect(_on_driver_started)
	if selection and not selection.changed.is_connected(_on_selection_changed):
		selection.changed.connect(_on_selection_changed)
	if input:
		input.hud = self
		if not input.armed_changed.is_connected(_on_armed_changed):
			input.armed_changed.connect(_on_armed_changed)
	_build()


## Новая игра у драйвера (GameDriver.start_game, restart; FakeCityDriver.start): своё окно чтения
func _on_driver_started(_seed: int) -> void:
	var q: Variant = driver.get("query")
	if q is GameQuery and q != query:
		var lp: Variant = driver.get("local_player")
		rebind(q as GameQuery, int(lp) if lp != null else player)


## Перестроить интерфейс и ввод на новое окно чтения (новая партия): выделение и группы прошлой игры
## сброшены, записки и метки — тоже; сторона могла смениться — балка и пояс строятся заново
func rebind(q: GameQuery, p: int) -> void:
	if menu and menu.visible:
		menu.close()                  # вернуть паузу и ввод, как были
	_ready_done = false
	query = q
	player = p
	if selection:
		for i in selection.groups.size():
			selection.groups[i] = PackedInt32Array()
		selection.set_selection(PackedInt32Array())
	if input:
		input.rebind(q, p)
	if root:
		remove_child(root)
		root.queue_free()
	_t_ui = 0.0
	_t_map = 0.0
	_t_heavy = 0.0
	_t_info = 0.0
	_t_notes = 0.0
	_sel_dirty = true
	_build()


func _on_armed_changed(_op: int) -> void:
	refresh_now()


## Собрать части интерфейса под сторону игрока (setup и rebind)
func _build() -> void:
	faction = StringName(query.defs().f_ids[query.players().faction[player]])
	root = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.make(faction)
	add_child(root)
	_box = Control.new()
	_box.name = "SelectBox"
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.draw.connect(_draw_box)
	root.add_child(_box)
	notes = CityNotes.new()
	notes.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	notes.offset_right = -14.0
	notes.offset_bottom = -(CityBottomPanel.H + 6.0)
	notes.offset_top = 120.0
	root.add_child(notes)
	notes.setup(self)
	bottom = CityBottomPanel.new()
	root.add_child(bottom)
	bottom.setup(self)
	top = CityTopBar.new()
	root.add_child(top)
	top.setup(self)
	menu = CityMenu.new()
	root.add_child(menu)
	menu.setup(self)
	CityCursor.apply(CityCursor.Kind.DEFAULT)
	_ready_done = true
	refresh_now()
	bottom.minimap.refresh()


func _process(delta: float) -> void:
	if not _ready_done:
		return
	notes.tick(delta)
	_t_ui += delta
	_t_map += delta
	_t_heavy += delta
	_t_info += delta
	_t_notes += delta
	if _t_notes >= NOTES_HZ:
		_t_notes = 0.0
		sync_driver()
		notes.poll()
	if _t_ui >= UI_HZ:
		_t_ui = 0.0
		refresh_now()
	if _t_map >= MAP_HZ:
		_t_map = 0.0
		sync_driver()
		bottom.minimap.refresh()


## Дождаться фонового шага драйвера (GameDriver.sync), прежде чем читать GameQuery; без фона — ничего
func sync_driver() -> void:
	if _can_sync:
		driver.call("sync")


func _on_selection_changed(_h: PackedInt32Array) -> void:
	_sel_dirty = true
	if not _in_refresh:
		refresh_now()


## Обновить панели сейчас (по часам 6–7 Гц, смена выделения, вкладки, взведённый приказ). heavy — пересчитать
## и тяжёлое: при 1000 выделенных чистка от мёртвых и сетка приказов стоят миллисекунды, поэтому — по смене
## выделения и раз в секунду; свежее выделение не чистим (его только что собрали из живых).
func refresh_now(heavy := false) -> void:
	if not _ready_done or _in_refresh:
		return
	_in_refresh = true
	sync_driver()
	heavy = heavy or _sel_dirty or _t_heavy >= HEAVY_S
	if heavy:
		_t_heavy = 0.0
		if selection and not _sel_dirty:
			selection.prune(query)            # кто-то погиб — сигнал поднимет _sel_dirty
	var sel := selection.selected if selection else PackedInt32Array()
	if _sel_dirty:
		_own = not sel.is_empty() and RtsInput.owns_all(query, player, sel)
	if _sel_dirty or sel.size() <= BIG_SEL or _t_info >= BIG_INFO_S:
		_t_info = 0.0
		info = query.selection_info(sel)
	_sel_dirty = false
	bottom.refresh(info, sel, heavy)
	top.refresh(heavy)
	# на вкладке стройки буквы — постройки: WASD и Q/E камеры молчат
	if camera and camera.get("pan_keys") != null:
		camera.set("pan_keys", bottom.tabs.current == &"orders")
	_in_refresh = false


# ================================================================= для частей интерфейса

func my_team() -> int:
	return query.players().team[player]


## Команда выделенного (чужие юниты тоже можно рассматривать)
func selection_team() -> int:
	if selection and not selection.selected.is_empty():
		var t := RtsInput.team_of(query, selection.selected[0])
		if t >= 0:
			return t
	return my_team()


func team_of_building(h: int) -> int:
	var bt := query.buildings()
	return bt.team[bt.slot(h)] if bt.valid(h) else my_team()


## Всё выделенное — своё (приказы только своим; пересчёт при смене выделения)
func selection_is_own() -> bool:
	return _own and selection != null and not selection.selected.is_empty()


func look_at_world(p: Vector2) -> void:
	if camera and camera.has_method("go_to"):
		var dist: float = camera.get("distance") if camera.get("distance") != null else 80.0
		var yaw: float = camera.get("yaw_deg") if camera.get("yaw_deg") != null else 0.0
		camera.call("go_to", Vector4(p.x, p.y, dist, yaw))


## Углы видимой земли (для рамки на миникарте), мировые x/z
func camera_ground_quad() -> PackedVector2Array:
	var out := PackedVector2Array()
	if camera == null or not camera.is_inside_tree():
		return out
	var vs := view_size()
	var top_y := CityTopBar.H
	var bot_y := vs.y - CityBottomPanel.H
	for s in [Vector2(0, top_y), Vector2(vs.x, top_y), Vector2(vs.x, bot_y), Vector2(0, bot_y)]:
		var screen: Vector2 = s * (camera.get_viewport().get_visible_rect().size / vs)
		out.append(RtsInput.ground_point(camera, screen, 900.0))
	return out


func order_button(op: int) -> void:
	if input:
		input.order_button(op)


func begin_place(btype: int) -> void:
	if input:
		input.begin_place(btype)


func train(b_h: int, utype: int) -> void:
	if input:
		input.issue_cmd(SimCmd.train(b_h, utype, 1))


func cancel_train(b_h: int, index: int) -> void:
	if input:
		input.issue_cmd(SimCmd.cancel_train(b_h, index))


## Обмен на базаре: give → take партией amount_milli (одна сторона — золото)
func trade(b_h: int, give: int, take: int, amount_milli: int) -> void:
	if input:
		input.issue_cmd(SimCmd.trade(b_h, give, take, amount_milli))


func cycle_speed() -> void:
	if driver:
		var speeds := [1.0, 2.0, 3.0, 0.5]
		var i := speeds.find(driver.time_scale)
		driver.time_scale = speeds[(i + 1) % speeds.size()]
		refresh_now()


func toggle_pause() -> void:
	if driver:
		driver.paused = not driver.paused
		refresh_now()


func open_menu() -> void:
	menu.open()


func request_restart() -> void:
	if restart_requested.get_connections().is_empty():
		if is_inside_tree():
			get_tree().reload_current_scene()
	else:
		restart_requested.emit()


func request_quit() -> void:
	if quit_requested.get_connections().is_empty():
		if is_inside_tree():
			get_tree().quit()
	else:
		quit_requested.emit()


## Щелчок по карточке: оставить в выделении только этот отряд (одиночек этого рода); Shift — убрать их;
## двойной щелчок — ещё и камера к ним
func select_card(card: Dictionary, shift := false, double := false) -> void:
	if selection == null:
		return
	sync_driver()
	var bs := query.battle()
	var sq := int(card.get("squad", 0))
	var type_id := String(card.get("type", ""))
	var keep := PackedInt32Array()
	for h in selection.selected:
		var u := query.unit_index(h)
		var mine := false
		if u >= 0 and bs:
			var s := bs.u_squad[u]
			if sq != 0:
				mine = Ids.make(Ids.Kind.SQUAD, s, bs.sq_gen[s]) == sq
			else:
				mine = (bs.sq_single[s] == 1 or bs.sq_members[s].size() == 1) and bs.type_ids[bs.u_type[u]] == type_id
		if mine != shift:
			keep.append(h)
	if keep.is_empty():
		return
	selection.set_selection(keep)
	if double and input:
		input.center_on(keep)


func open_tab(tab: StringName) -> void:
	bottom.tabs.select(tab)
	tab_opened.emit(tab)
	refresh_now(true)


func current_tab() -> StringName:
	return bottom.tabs.current


## Событие для балки (набег начался/кончился) и метки на миникарте
func on_event(kind: int, _a: int, _b: int, _c: int, pos := Vector2.INF) -> void:
	var E := SimEvents.Ev
	if kind == E.RAID_STARTED:
		top.set_raid_active(true)
	elif kind == E.RAID_ENDED:
		top.set_raid_active(false)
	if pos != Vector2.INF and kind in [E.RAID_WARNING, E.RAID_STARTED, E.BUILDING_DESTROYED, E.HERD_STOLEN, E.BUILDING_HIT]:
		bottom.minimap.ping(pos, UiTheme.RED_LIGHT if kind != E.RAID_WARNING else UiTheme.GOLD_LIGHT)


# ================================================================= для ввода и камеры

## Точка экрана над панелями интерфейса (щелчки туда не идут в мир)
func blocks(pos: Vector2) -> bool:
	if not _ready_done:
		return false
	if menu.visible:
		return true
	var c := root.get_viewport().gui_get_hovered_control() if root.is_inside_tree() else null
	if c != null and c != root and c != _box and c != notes and c != top and c != bottom:
		return true
	var vs := view_size()
	return pos.y >= vs.y - CityBottomPanel.H + CityBottomPanel.BELT * 0.5 or pos.y <= CityTopBar.H


## Край экрана над интерфейсом: сдвиг камеры только у самой кромки (RtsCamera.edge_blocked)
func blocks_edge_pan(pos: Vector2) -> bool:
	var vs := view_size()
	if pos.y <= 1.0 or pos.y >= vs.y - 2.0:
		return false
	return blocks(pos)


## Размер холста интерфейса (1920×1080 по проекту; вне дерева — он же)
func view_size() -> Vector2:
	return root.get_viewport_rect().size if root and root.is_inside_tree() else Vector2(1920, 1080)


func show_box(r: Rect2) -> void:
	_box_rect = r.abs()
	_line = PackedVector2Array()
	_box.queue_redraw()


func show_line(a: Vector2, b: Vector2) -> void:
	_line = PackedVector2Array([a, b])
	_box_rect = Rect2()
	_box.queue_redraw()


func hide_box() -> void:
	_box_rect = Rect2()
	_line = PackedVector2Array()
	_box.queue_redraw()


func _draw_box() -> void:
	if _box_rect.size != Vector2.ZERO:
		_box.draw_rect(_box_rect, Color(1.0, 0.86, 0.5, 0.08))
		_box.draw_rect(_box_rect.grow(1.0), Color(0.1, 0.05, 0.02, 0.6), false, 3.0)
		_box.draw_rect(_box_rect, Color("#f2d68a"), false, 1.5)
	if _line.size() == 2:
		_box.draw_line(_line[0], _line[1], Color(0.1, 0.05, 0.02, 0.6), 5.0)
		_box.draw_line(_line[0], _line[1], Color("#f2d68a"), 2.0)
		for p in _line:
			_box.draw_circle(p, 4.0, Color("#f2d68a"))
