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

signal tab_opened(tab: StringName)

const UI_HZ := 0.15
const MAP_HZ := 0.25

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
var info := {}

var _box: Control
var _box_rect := Rect2()
var _line := PackedVector2Array()
var _t_ui := 0.0
var _t_map := 0.0
var _ready_done := false


func setup(q: GameQuery, drv: SimDriver, sel: SelectionModel, p: int, cam: Camera3D = null, inp: RtsInput = null) -> void:
	query = q
	driver = drv
	selection = sel
	player = p
	camera = cam
	input = inp
	layer = 10
	name = "CityHud"
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
	if selection:
		selection.changed.connect(func(_h: PackedInt32Array) -> void: refresh_now())
	if input:
		input.hud = self
	CityCursor.apply(CityCursor.Kind.DEFAULT)
	_ready_done = true
	refresh_now()
	bottom.minimap.refresh()


func _process(delta: float) -> void:
	if not _ready_done:
		return
	notes.poll()
	notes.tick(delta)
	_t_ui += delta
	_t_map += delta
	if _t_ui >= UI_HZ:
		_t_ui = 0.0
		refresh_now()
	if _t_map >= MAP_HZ:
		_t_map = 0.0
		bottom.minimap.refresh()


## Обновить панели сейчас (смена выделения, вкладки)
func refresh_now() -> void:
	if not _ready_done:
		return
	var sel := PackedInt32Array()
	if selection:
		selection.prune(query)
		sel = selection.selected
	info = query.selection_info(sel)
	bottom.refresh(info, sel)
	top.refresh()
	# на вкладке стройки буквы — постройки: WASD камеры молчат
	if camera and camera.get("pan_keys") != null:
		camera.set("pan_keys", bottom.tabs.current == &"orders")


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


## Всё выделенное — своё (приказы только своим)
func selection_is_own() -> bool:
	if selection == null or selection.selected.is_empty():
		return false
	return RtsInput.owns_all(query, player, selection.selected)


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


func open_tab(tab: StringName) -> void:
	bottom.tabs.select(tab)
	tab_opened.emit(tab)
	refresh_now()


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
