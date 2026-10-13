class_name CityBottomPanel
extends Control
## Нижняя панель (ТЗ §12): пояс-орнамент стороны по верху (Коканд — бирюзовые изразцы с восьмиконечными
## звёздами, кыпчаки — красный войлок с «кочкор мүйүз»), ореховое тело; слева — миникарта в латунной
## раме, посередине на «самаркандской бумаге» — карточки / панель здания, справа — вкладки и сетка приказов.

const H := 256.0
const BELT := 34.0
const MAP := 216.0
const RIGHT_W := 362.0

var hud: CityHud
var minimap: CityMinimap
var cards: CityCards
var building: CityBuildingPanel
var tabs: CityBuildTabs
var grid: CityOrderGrid
var _info: Control
var _other: Label


func setup(p_hud: CityHud) -> void:
	hud = p_hud
	name = "BottomPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -H
	var faction := String(hud.query.defs().f_ids[hud.query.players().faction[hud.player]])
	# ореховое тело
	var body := NinePatchRect.new()
	body.name = "Body"
	body.texture = UiTheme.tex("panel")
	for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		body.set(m, 22)
	body.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	body.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_top = BELT - 2.0
	body.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(body)
	# пояс-орнамент
	var belt := TextureRect.new()
	belt.name = "Belt"
	belt.texture = UiTheme.tex("belt_kipchak" if faction == "kipchak" else "belt_kokand")
	belt.stretch_mode = TextureRect.STRETCH_TILE
	belt.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	belt.offset_bottom = BELT
	belt.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(belt)
	# миникарта в латунной раме (заходит на пояс)
	var housing := NinePatchRect.new()
	housing.name = "MapHousing"
	housing.texture = UiTheme.tex("inset")
	for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		housing.set(m, 8)
	housing.position = Vector2(8, -26)
	housing.size = Vector2(MAP + 28, MAP + 28)
	housing.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(housing)
	minimap = CityMinimap.new()
	minimap.position = Vector2(22, -12)
	minimap.size = Vector2(MAP, MAP)
	add_child(minimap)
	minimap.setup(hud)
	var frame := NinePatchRect.new()
	frame.name = "MapFrame"
	frame.texture = UiTheme.tex("frame_brass")
	for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		frame.set(m, 14)
	frame.draw_center = false
	frame.position = Vector2(10, -24)
	frame.size = Vector2(MAP + 24, MAP + 24)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	# резные столбы между частями
	for x in [MAP + 34.0, -(RIGHT_W + 24.0)]:
		var post := CityPost.new()
		post.size = Vector2(14, H - BELT - 8)
		if x < 0.0:
			post.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			post.offset_left = x - 7.0
			post.offset_right = x + 7.0
			post.offset_top = BELT + 2.0
			post.offset_bottom = H - 4.0
		else:
			post.position = Vector2(x, BELT + 2.0)
		add_child(post)
	# бумага для сведений
	var paper := NinePatchRect.new()
	paper.name = "Paper"
	paper.texture = UiTheme.tex("paper")
	for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		paper.set(m, 30)
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.offset_left = MAP + 52.0
	paper.offset_right = -(RIGHT_W + 36.0)
	paper.offset_top = BELT + 10.0
	paper.offset_bottom = -10.0
	paper.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(paper)
	var pframe := NinePatchRect.new()
	pframe.texture = UiTheme.tex("frame_thin")
	for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		pframe.set(m, 8)
	pframe.draw_center = false
	pframe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pframe.offset_left = -4
	pframe.offset_top = -4
	pframe.offset_right = 4
	pframe.offset_bottom = 4
	pframe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_child(pframe)
	_info = Control.new()
	_info.name = "Info"
	_info.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_info.offset_left = 16
	_info.offset_top = 10
	_info.offset_right = -16
	_info.offset_bottom = -8
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_child(_info)
	cards = CityCards.new()
	cards.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_info.add_child(cards)
	cards.setup(hud)
	building = CityBuildingPanel.new()
	building.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_info.add_child(building)
	building.setup(hud)
	building.visible = false
	_other = UiTheme.label("", UiTheme.head_bold(), 26, true)
	_other.position = Vector2(8, 8)
	_info.add_child(_other)
	# справа: вкладки и сетка
	var right := Control.new()
	right.name = "Right"
	right.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_left = -(RIGHT_W + 12.0)
	right.offset_right = -12.0
	right.offset_top = BELT + 6.0
	right.offset_bottom = -6.0
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right)
	tabs = CityBuildTabs.new()
	tabs.position = Vector2(0, 0)
	tabs.size = Vector2(RIGHT_W, 30)
	right.add_child(tabs)
	tabs.setup()
	tabs.tab_changed.connect(func(_t: StringName) -> void: hud.refresh_now())
	grid = CityOrderGrid.new()
	grid.position = Vector2(1, 38)
	grid.size = Vector2(RIGHT_W, 172)
	right.add_child(grid)
	grid.setup(hud)


func refresh(info: Dictionary, sel: PackedInt32Array) -> void:
	var kind := String(info.get("kind", "none"))
	building.visible = kind == "building"
	cards.visible = kind == "units" or kind == "none"
	_other.visible = kind == "node" or kind == "herd"
	match kind:
		"building":
			building.show_panel(info.get("panel", hud.query.building_panel(sel[0]) if not sel.is_empty() else {}))
		"node":
			_other.text = "%s\n%s" % [info.get("name", ""), tr("Осталось: %d") % int(info.get("amount", 0))]
		"herd":
			_other.text = "%s\n%s" % [info.get("name", ""), tr("Голов: %d") % int(info.get("heads", 0))]
		_:
			cards.show_info(info)
	var p := hud.player
	if tabs.current == &"orders":
		grid.show_orders(hud.query.orders_for(p, sel) if hud.selection_is_own() else ([] as Array[Dictionary]))
	else:
		grid.show_build(hud.query.build_menu(p, tabs.current))
	if minimap.is_visible_in_tree():
		pass
