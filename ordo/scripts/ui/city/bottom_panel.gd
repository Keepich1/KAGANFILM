class_name CityBottomPanel
extends Control
## Нижняя панель (ТЗ §12): пояс-орнамент стороны по верху (Коканд — бирюзовые изразцы с восьмиконечными
## звёздами, кыпчаки — красный войлок с «кочкор мүйүз»), ореховое тело; слева — миникарта в латунной
## раме, посередине на «самаркандской бумаге» — карточки / панель здания, справа — вкладки и сетка приказов.

const H := 256.0
const BELT := 34.0
const MAP := 216.0
const RIGHT_W := 362.0
## Самая узкая раскладка панели (проверена при окне 1280×720): холст уже (масштаб интерфейса больше
## 120 %) — панель раскладывается на MIN_W и ужимается целиком (fit), а не теснит карточки и найм;
## так же — верхняя балка и записки (одна мера на все полосы «Города»: bar_scale)
const MIN_W := 1600.0

var hud: CityHud
var minimap: CityMinimap
var cards: CityCards
var building: CityBuildingPanel
var tabs: CityBuildTabs
var grid: CityOrderGrid
var _info: Control
## Узел или стадо: медальон, имя, сколько осталось / голов, подсказка
var _other: Control
var _other_sig := ""
var _other_amount: Label
var _orders: Array[Dictionary] = []


func setup(p_hud: CityHud) -> void:
	hud = p_hud
	name = "BottomPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fit(hud.view_size())
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
	_other = Control.new()
	_other.name = "Other"
	_other.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_other.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	tabs.tab_changed.connect(func(_t: StringName) -> void: hud.refresh_now(true))
	grid = CityOrderGrid.new()
	grid.position = Vector2(1, 38)
	grid.size = Vector2(RIGHT_W, 172)
	right.add_child(grid)
	grid.setup(hud)


## Во всю ширину холста view у нижнего края; холст уже MIN_W — раскладка на MIN_W, панель ужата до ширины
## холста (щелчки по ней — в своих координатах, миникарта и кнопки попадают как прежде)
func fit(view: Vector2) -> void:
	var s := bar_scale(view)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	scale = Vector2(s, s)
	position = Vector2(0.0, view.y - H * s)
	size = Vector2(view.x / s, H)


## Ужатие полос «Города» (балка, панель, записки) на холсте view: уже MIN_W — меньше 1
static func bar_scale(view: Vector2) -> float:
	return clampf(view.x / MIN_W, 0.1, 1.0) if view.x > 0.0 else 1.0


## Высота на холсте (ужатая панель ниже H)
func screen_h() -> float:
	return H * scale.y


## heavy — спросить сетку приказов заново (смена выделения, вкладки; раз в секунду)
func refresh(info: Dictionary, sel: PackedInt32Array, heavy := true) -> void:
	var kind := String(info.get("kind", "none"))
	building.visible = kind == "building"
	cards.visible = kind == "units" or kind == "none"
	_other.visible = kind == "node" or kind == "herd"
	match kind:
		"building":
			building.show_panel(info.get("panel", hud.query.building_panel(sel[0]) if not sel.is_empty() else {}))
		"node", "herd":
			_show_other(info, sel[0] if not sel.is_empty() else 0)
		_:
			cards.show_info(info)
	var p := hud.player
	if tabs.current == &"orders":
		if heavy:
			_orders = hud.query.orders_for(p, sel) if hud.selection_is_own() else ([] as Array[Dictionary])
		grid.show_orders(_orders)
	else:
		grid.show_build(hud.query.build_menu(p, tabs.current))


## Узел (жила, лес, глина) или стадо: медальон со значком ресурса, имя, остаток / головы, что делать
func _show_other(info: Dictionary, h: int) -> void:
	var kind := String(info.get("kind", ""))
	var sig := "%s|%d" % [kind, h]
	var q := hud.query
	var defs := q.defs()
	if sig != _other_sig:
		_other_sig = sig
		for ch in _other.get_children():
			ch.queue_free()
		var icon: Texture2D = null
		var team := -1
		var hint := ""
		if kind == "node" and q.nodes() and q.nodes().valid(h):
			icon = UiTheme.res_icon(defs, q.nodes().res[q.nodes().slot(h)])
			hint = tr("Выберите работников и щёлкните ПКМ сюда — добывать")
		elif kind == "herd" and q.herds() and q.herds().valid(h):
			var hs := q.herds().slot(h)
			var back := defs.h_backing[q.herds().htype[hs]]
			icon = UiTheme.res_icon(defs, back) if back >= 0 else UiTheme.icon("bld", "pen")
			var o := q.herds().owner[hs]
			team = q.players().team[o] if o >= 0 else -1
			hint = tr("Своё стадо пасут работники (ПКМ); чужое угоняют всадники") if team >= 0 else ""
		var roundel := CityRoundel.new()
		roundel.color = UiTheme.TEAM[team % 4] if team >= 0 else Color("#7a5a32")
		roundel.icon = icon
		roundel.position = Vector2(4, 6)
		roundel.size = Vector2(112, 112)
		_other.add_child(roundel)
		var nm := UiTheme.label(String(info.get("name", "")), UiTheme.head_bold(), 30, true)
		nm.position = Vector2(134, 4)
		_other.add_child(nm)
		_other_amount = UiTheme.label("", UiTheme.text(700), 22, true)
		_other_amount.position = Vector2(136, 48)
		_other.add_child(_other_amount)
		var hl := UiTheme.label(hint, UiTheme.italic(500), 18, true)
		hl.position = Vector2(136, 86)
		hl.add_theme_color_override("font_color", UiTheme.INK_SOFT)
		_other.add_child(hl)
	if kind == "node":
		var amount := int(info.get("amount", 0))
		_other_amount.text = tr("Осталось: без конца") if amount < 0 else tr("Осталось: %d") % amount
	else:
		_other_amount.text = tr("Голов: %d") % int(info.get("heads", 0))
