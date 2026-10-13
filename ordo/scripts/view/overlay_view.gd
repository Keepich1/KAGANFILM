class_name OverlayView
extends Control
## Надписи над миром (ARCHITECTURE §13, ТЗ 11.2, 12 «не сайт»): таблички выделенных отрядов и построек
## (тёмный орех, латунная рамка, как SquadBars среза), полоски здоровья повреждённых построек и
## прогресс строек на виду, флаг места сбора подписан, всплывающие надписи «на бумаге» (добыча,
## доставка, «Построено») — их зовёт CityFx: float_text(pos, text, color).
## Рисуется в CanvasLayer, мышь не ловит. PerfMeter «view_overlay».

const WALNUT := Color(0.13, 0.085, 0.06, 0.88)
const BRASS := Color(0.78, 0.6, 0.3)
const HP_COL := Color(0.86, 0.27, 0.2)
const MORALE_COL := Color(0.95, 0.74, 0.3)
const STAMINA_COL := Color(0.45, 0.85, 0.78)
const BUILD_COL := Color(0.95, 0.78, 0.42)
const BAR_BG := Color(0.05, 0.04, 0.035, 0.95)
const PAPER := Color(0.93, 0.87, 0.74, 0.94)
const INK := Color(0.2, 0.13, 0.08)
const TEXT := Color(0.95, 0.9, 0.8)
const FONT_TEXT := "res://assets/ui/fonts/alegreya/Alegreya-VariableFont_wght.ttf"
const FONT_TITLE := "res://assets/ui/fonts/cormorant_unicase/CormorantUnicase-SemiBold.ttf"
const FLOAT_S := 1.8
## Полоски строек и повреждённых построек — ближе этого расстояния камеры, м
const BAR_RANGE := 220.0

@export var driver_path: NodePath = ^"../../Driver"
@export var selection_view_path: NodePath = ^"../../Views/Selection"

var query: GameQuery
var defs: Defs

var _sel: SelectionView
var _font: Font
var _title: Font
var _floats: Array = []       # [pos3, text, color, t]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_sel = get_node_or_null(selection_view_path) as SelectionView
	_font = load(FONT_TEXT) if ResourceLoader.exists(FONT_TEXT) else ThemeDB.fallback_font
	_title = load(FONT_TITLE) if ResourceLoader.exists(FONT_TITLE) else _font
	var d := get_node_or_null(driver_path)
	if d and d.has_signal("started"):
		d.connect("started", func(_s: int) -> void: set_query(CityView.query_of(d)))
	if CityView.query_of(d):
		set_query(CityView.query_of(d))


func set_query(q: GameQuery) -> void:
	query = q
	defs = q.defs() if q else null
	_floats.clear()


## Всплывающая надпись на бумаге над точкой мира (добыча, доставка, «Построено»)
func float_text(pos: Vector3, text: String, color := INK) -> void:
	if _floats.size() > 40:
		_floats.pop_front()
	_floats.append([pos, text, color, 0.0])


func _process(delta: float) -> void:
	for f: Array in _floats:
		f[3] += delta
	while not _floats.is_empty() and float(_floats[0][3]) > FLOAT_S:
		_floats.pop_front()
	queue_redraw()


func _draw() -> void:
	if query == null:
		return
	var t0 := CityView.now_usec()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_draw_buildings(cam)
	if _sel and _sel.selection:
		_draw_selected(cam)
	_draw_floats(cam)
	CityView.mark(&"view_overlay", t0)


## Стройки — тонкая полоса прогресса; повреждённые — здоровье (только вблизи камеры)
func _draw_buildings(cam: Camera3D) -> void:
	var bt := query.buildings()
	var cp := cam.global_position
	var r2 := BAR_RANGE * BAR_RANGE
	for b in bt.hw:
		var st := bt.state[b]
		if st != BuildingTable.State.SITE and not (st == BuildingTable.State.ACTIVE and bt.hp_c[b] < bt.hp_max_c[b]):
			continue
		var ty := bt.btype[b]
		if ty < 0 or defs.b_kind[ty] == Defs.BKind.WALL or defs.b_kind[ty] == Defs.BKind.LINK:
			continue
		var p := Vector3(bt.x[b], 0.0, bt.z[b])
		if Vector2(p.x - cp.x, p.z - cp.z).length_squared() > r2:
			continue
		p.y = Terrain.height_at(p.x, p.z) + _top(ty)
		if cam.is_position_behind(p):
			continue
		var s := cam.unproject_position(p)
		var w := 46.0
		if st == BuildingTable.State.SITE:
			_bar(Rect2(s - Vector2(w * 0.5, 0), Vector2(w, 4)), bt.progress[b] / 1000.0, BUILD_COL)
		else:
			_bar(Rect2(s - Vector2(w * 0.5, 0), Vector2(w, 4)), float(bt.hp_c[b]) / maxi(bt.hp_max_c[b], 1), HP_COL)


func _draw_selected(cam: Camera3D) -> void:
	var sim := query.battle()
	var bt := query.buildings()
	var squads := {}
	var singles := 0
	var single_u := -1
	for h in _sel.selection.selected:
		match Ids.kind(h):
			Ids.Kind.UNIT:
				var u := query.unit_index(h)
				if u < 0 or sim == null or sim.u_life[u] != BattleSim.Life.ALIVE:
					continue
				var s := sim.u_squad[u]
				if sim.sq_single[s] == 1 or sim.sq_members[s].size() <= 1:
					singles += 1
					single_u = u
				else:
					squads[s] = true
			Ids.Kind.BUILDING:
				if bt.valid(h):
					_building_plate(cam, bt.slot(h))
	for s: int in squads:
		_squad_plate(cam, sim, s)
	if singles == 1 and single_u >= 0:
		_unit_plate(cam, sim, single_u)


func _squad_plate(cam: Camera3D, sim: BattleSim, s: int) -> void:
	var anchor := Vector3(sim.sq_cx[s], 0.0, sim.sq_cz[s])
	var bn := sim.sq_banner[s]
	if bn >= 0 and sim.is_alive(bn):
		anchor = Vector3(sim.u_x[bn], 0.0, sim.u_z[bn])
	anchor.y = Terrain.height_at(anchor.x, anchor.z) + 5.6
	if cam.is_position_behind(anchor):
		return
	var p := cam.unproject_position(anchor)
	var title: String = UnitStats.get_stats(sim.type_ids[sim.sq_type[s]]).get("name", "")
	var hp := 0.0
	var hp_max := 0.0
	for u in sim.sq_members[s]:
		hp_max += sim.t_hp[sim.u_type[u]]
		if sim.u_life[u] == BattleSim.Life.ALIVE:
			hp += sim.u_hp[u]
	var r := _plate(p, tr(title), str(sim.sq_alive[s]), 38.0)
	_bar(Rect2(r.position + Vector2(6, 20), Vector2(r.size.x - 12, 6)), hp / maxf(hp_max, 1.0), HP_COL)
	_bar(Rect2(r.position + Vector2(6, 28), Vector2(r.size.x - 12, 4)), sim.sq_morale[s] / 100.0, MORALE_COL)
	_bar(Rect2(r.position + Vector2(6, 34), Vector2(r.size.x - 12, 2)), sim.sq_stam[s] / 100.0, STAMINA_COL)


func _unit_plate(cam: Camera3D, sim: BattleSim, u: int) -> void:
	var anchor := Vector3(sim.u_x[u], 0.0, sim.u_z[u])
	anchor.y = Terrain.height_at(anchor.x, anchor.z) + 3.0
	if cam.is_position_behind(anchor):
		return
	var p := cam.unproject_position(anchor)
	var title: String = UnitStats.get_stats(sim.type_of(u)).get("name", "")
	var r := _plate(p, tr(title), "", 28.0)
	_bar(Rect2(r.position + Vector2(6, 20), Vector2(r.size.x - 12, 5)), sim.u_hp[u] / maxf(sim.t_hp[sim.u_type[u]], 1.0), HP_COL)


func _building_plate(cam: Camera3D, b: int) -> void:
	var bt := query.buildings()
	var ty := bt.btype[b]
	var anchor := Vector3(bt.x[b], 0.0, bt.z[b])
	anchor.y = Terrain.height_at(anchor.x, anchor.z) + _top(ty) + 1.5
	if cam.is_position_behind(anchor):
		return
	var p := cam.unproject_position(anchor)
	var site := bt.state[b] == BuildingTable.State.SITE
	var right := "%d / %d" % [bt.hp_c[b] / 100, bt.hp_max_c[b] / 100]
	var r := _plate(p, tr(defs.b_name[ty]), right, 38.0 if site else 30.0)
	_bar(Rect2(r.position + Vector2(6, 20), Vector2(r.size.x - 12, 6)), float(bt.hp_c[b]) / maxi(bt.hp_max_c[b], 1), HP_COL)
	if site:
		_bar(Rect2(r.position + Vector2(6, 30), Vector2(r.size.x - 12, 4)), bt.progress[b] / 1000.0, BUILD_COL)


## Табличка: орех, латунь, заклёпки, название слева и число справа; возвращает прямоугольник
func _plate(p: Vector2, title: String, right: String, h: float) -> Rect2:
	var fs := 15
	var tw := _title.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var rw := _font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x if right != "" else 0.0
	var w := maxf(104.0, tw + rw + 30.0)
	var r := Rect2(p - Vector2(w * 0.5, h), Vector2(w, h))
	draw_rect(r, WALNUT)
	draw_rect(r, BRASS, false, 1.5)
	for c: Vector2 in [r.position, r.position + Vector2(w, 0), r.position + Vector2(0, h), r.end]:
		draw_circle(c, 2.2, BRASS)
	draw_string(_title, r.position + Vector2(7, 15), title, HORIZONTAL_ALIGNMENT_LEFT, w - rw - 18, fs, TEXT)
	if right != "":
		draw_string(_font, r.position + Vector2(w - rw - 7, 15), right, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT)
	draw_line(Vector2(p.x, r.end.y), p + Vector2(0, 6), BRASS, 1.5)
	return r


func _bar(r: Rect2, k: float, col: Color) -> void:
	draw_rect(r.grow(1.0), BAR_BG)
	var f := Rect2(r.position, Vector2(r.size.x * clampf(k, 0.0, 1.0), r.size.y))
	draw_rect(f, col)
	draw_line(f.position, f.position + Vector2(f.size.x, 0), col.lightened(0.35), 1.0)


## Всплывающие надписи: клочок бумаги, поднимается и тает
func _draw_floats(cam: Camera3D) -> void:
	for f: Array in _floats:
		var k := float(f[3]) / FLOAT_S
		var pos: Vector3 = f[0] + Vector3(0, 2.5 + k * 3.0, 0)
		if cam.is_position_behind(pos):
			continue
		var s := cam.unproject_position(pos)
		var text: String = f[1]
		var fs := 15
		var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var a := 1.0 - smoothstep(0.65, 1.0, k)
		var r := Rect2(s - Vector2(sz.x * 0.5 + 7, sz.y * 0.5 + 3), Vector2(sz.x + 14, sz.y + 6))
		var paper := PAPER
		paper.a *= a
		draw_rect(r, paper)
		var edge := Color(0.55, 0.42, 0.28, 0.8 * a)
		draw_rect(r, edge, false, 1.0)
		var col: Color = f[2]
		col.a = a
		draw_string(_font, r.position + Vector2(7, sz.y * 0.5 + 3 + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _top(ty: int) -> float:
	var sz := defs.b_size[ty]
	return clampf(maxf(sz.x, sz.y) * 0.45, 3.0, 10.0)
