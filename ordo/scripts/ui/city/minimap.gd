class_name CityMinimap
extends Control
## Миникарта «старая карта» (ТЗ §12): рельеф сепией по бумаге, река выцветшей тушью; постройки —
## квадраты цвета команды, юниты — точки, жилы — ромбики; рамка камеры. ЛКМ (и протяжка) — камера
## туда, ПКМ — приказ выделенным в эту точку. Обновление 4 Гц (CityHud).

const MAP_PX := 256

var hud: CityHud
var _base: ImageTexture
var _paper: Texture2D
var _units := PackedVector3Array()
var _blds := PackedVector3Array()
var _nodes := PackedVector3Array()
var _frustum := PackedVector2Array()
var _origin := Vector2(-512, -512)
var _extent := 1024.0
var _drag := false


func setup(p_hud: CityHud) -> void:
	hud = p_hud
	name = "Minimap"
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_paper = UiTheme.tex("map_paper")
	_origin = Terrain.origin()
	_extent = (Terrain.size() - 1) * Terrain.spacing()
	_base = _make_base()
	tooltip_text = tr("Миникарта: ЛКМ — камера, ПКМ — приказ")


## Рельеф: светотень по склонам, горы темнее, вода — выцветшая бирюзовая тушь
func _make_base() -> ImageTexture:
	var img := Image.create(MAP_PX, MAP_PX, false, Image.FORMAT_RGB8)
	var paper := Color("#d8c49a")
	var ink := Color("#5a4028")
	var water := Color("#5f8f8a")
	var step := _extent / MAP_PX
	for j in MAP_PX:
		for i in MAP_PX:
			var x := _origin.x + (i + 0.5) * step
			var z := _origin.y + (j + 0.5) * step
			var hgt := Terrain.height_at(x, z)
			var hx := Terrain.height_at(x + step, z) - hgt
			var hz := Terrain.height_at(x, z + step) - hgt
			var shade := clampf(0.5 - (hx + hz) * 0.08, 0.0, 1.0)
			var c := paper.lerp(ink, clampf(hgt / 90.0, 0.0, 0.55))
			c = c.darkened(clampf(0.5 - shade, 0.0, 0.5) * 0.7).lightened(clampf(shade - 0.5, 0.0, 0.5) * 0.35)
			if Terrain.is_water(x, z):
				c = paper.lerp(water, 0.7)
			img.set_pixel(i, j, c)
	return ImageTexture.create_from_image(img)


func world_to_map(p: Vector2) -> Vector2:
	return (p - _origin) / _extent * size


func map_to_world(m: Vector2) -> Vector2:
	return _origin + m / size * _extent


func refresh() -> void:
	var mm := hud.query.minimap(hud.player)
	_units = mm.get("units", PackedVector3Array())
	_blds = mm.get("buildings", PackedVector3Array())
	_nodes = mm.get("nodes", PackedVector3Array())
	_frustum = hud.camera_ground_quad()
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_texture_rect(_base, r, false)
	if _paper:
		draw_texture_rect(_paper, r, false, Color(1, 1, 1, 0.35))
	# жилы: золото — жёлтые, камень — серые, глина — рыжие
	var defs := hud.query.defs()
	for n in _nodes:
		var m := world_to_map(Vector2(n.x, n.y))
		var res := int(n.z)
		var col := Color("#e8c050") if res == defs.res(&"gold") else (Color("#a09888") if res == defs.res(&"stone") else Color("#b0703a"))
		draw_colored_polygon(PackedVector2Array([m + Vector2(0, -3), m + Vector2(3, 0), m + Vector2(0, 3), m + Vector2(-3, 0)]), col)
	var my_team := hud.query.players().team[hud.player]
	for b in _blds:
		var m := world_to_map(Vector2(b.x, b.y))
		var t := int(b.z)
		draw_rect(Rect2(m - Vector2(2.5, 2.5), Vector2(5, 5)), UiTheme.TEAM[t % 4].darkened(0.15))
		draw_rect(Rect2(m - Vector2(2.5, 2.5), Vector2(5, 5)), Color(0.15, 0.08, 0.03, 0.9), false, 1.0)
	for u in _units:
		var m := world_to_map(Vector2(u.x, u.y))
		var t := int(u.z)
		draw_rect(Rect2(m - Vector2(1, 1), Vector2(2, 2)), UiTheme.TEAM_LIGHT[t % 4] if t == my_team else UiTheme.TEAM[t % 4].lightened(0.2))
	# рамка камеры
	if _frustum.size() == 4:
		var pts := PackedVector2Array()
		for p in _frustum:
			pts.append(world_to_map(p))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.12, 0.06, 0.02, 0.7), 3.0)
		draw_polyline(pts, Color("#fff1cf"), 1.4)
	# роза ветров в углу
	var c := Vector2(size.x - 18, 18)
	var star := PackedVector2Array()
	for k in 16:
		var a := -PI / 2 + k * PI / 8
		var rr := 11.0 if k % 2 == 0 else 4.0
		if k % 4 == 2:
			rr = 7.0
		star.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(star, Color(0.35, 0.22, 0.12, 0.75))
	draw_string(UiTheme.head_bold(), c + Vector2(-4, -12), "С", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.18, 0.1))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
			if mb.pressed:
				hud.look_at_world(map_to_world(mb.position))
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if hud.input:
				hud.input.order_at(map_to_world(mb.position), mb.shift_pressed)
			accept_event()
	elif event is InputEventMouseMotion and _drag:
		hud.look_at_world(map_to_world((event as InputEventMouseMotion).position))
		accept_event()
