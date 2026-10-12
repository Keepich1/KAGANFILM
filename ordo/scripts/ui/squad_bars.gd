class_name SquadBars
extends Control
## Полоски выделенных отрядов (ТЗ 11.2: видны в любом освещении; ТЗ 12: не «сайт»):
## маленькая табличка над знаменем — тёмный орех, латунная рамка, название отряда,
## здоровье (киноварь), мораль (золото), выносливость (тонкая бирюзовая черта).
## Тёмная подложка и светлая кайма — полоски читаются и на закатном небе, и на тёмной земле.

const WALNUT := Color(0.13, 0.085, 0.06, 0.88)
const BRASS := Color(0.78, 0.6, 0.3)
const HP_COL := Color(0.86, 0.27, 0.2)
const MORALE_COL := Color(0.95, 0.74, 0.3)
const STAMINA_COL := Color(0.45, 0.85, 0.78)
const BAR_BG := Color(0.05, 0.04, 0.035, 0.95)
const FLEE_COL := Color(1.0, 0.45, 0.35)

@export var selection_path: NodePath
@export var plate_width := 104.0

var selection: SquadSelection
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	selection = get_node_or_null(selection_path) as SquadSelection
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if selection == null or selection.scenario == null or selection.scenario.sim == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var sim := selection.scenario.sim
	for s in selection.selected:
		if s < 0 or s >= sim.squads or sim.sq_alive[s] == 0:
			continue
		# над знаменосцем (если жив), иначе над центром отряда
		var anchor := Vector3(sim.sq_cx[s], 0.0, sim.sq_cz[s])
		var b := sim.sq_banner[s]
		if b >= 0 and sim.is_alive(b):
			anchor = Vector3(sim.u_x[b], 0.0, sim.u_z[b])
		anchor.y = Terrain.height_at(anchor.x, anchor.z) + 5.6
		if cam.is_position_behind(anchor):
			continue
		var p := cam.unproject_position(anchor)
		_plate(p, sim, s)


func _plate(p: Vector2, sim: BattleSim, s: int) -> void:
	var w := plate_width
	var h := 34.0
	var r := Rect2(p - Vector2(w * 0.5, h), Vector2(w, h))
	draw_rect(r, WALNUT)
	draw_rect(r, BRASS, false, 1.5)
	# заклёпки по углам
	for c in [r.position, r.position + Vector2(w, 0), r.position + Vector2(0, h), r.end]:
		draw_circle(c, 2.2, BRASS)
	# название отряда
	var title: String = UnitStats.get_stats(sim.type_ids[sim.sq_type[s]]).get("name", "")
	var col := FLEE_COL if sim.is_fleeing(s) else Color(0.95, 0.9, 0.8)
	draw_string(_font, r.position + Vector2(6, 12), title, HORIZONTAL_ALIGNMENT_LEFT, w - 30, 11, col)
	draw_string(_font, r.position + Vector2(w - 26, 12), str(sim.sq_alive[s]), HORIZONTAL_ALIGNMENT_RIGHT, 20, 11, Color(0.95, 0.9, 0.8))
	# здоровье: сумма живых к начальной
	var hp := 0.0
	var hp_max := 0.0
	for u in sim.sq_members[s]:
		hp_max += sim.t_hp[sim.u_type[u]]
		if sim.u_life[u] == BattleSim.Life.ALIVE:
			hp += sim.u_hp[u]
	_bar(Rect2(r.position + Vector2(6, 16), Vector2(w - 12, 6)), hp / maxf(hp_max, 1.0), HP_COL)
	_bar(Rect2(r.position + Vector2(6, 24), Vector2(w - 12, 4)), sim.sq_morale[s] / 100.0, MORALE_COL)
	_bar(Rect2(r.position + Vector2(6, 30), Vector2(w - 12, 2)), sim.sq_stam[s] / 100.0, STAMINA_COL)
	# хвостик-указатель к знамени
	draw_line(Vector2(p.x, r.end.y), p + Vector2(0, 6), BRASS, 1.5)


func _bar(r: Rect2, k: float, col: Color) -> void:
	draw_rect(r.grow(1.0), BAR_BG)
	var f := Rect2(r.position, Vector2(r.size.x * clampf(k, 0.0, 1.0), r.size.y))
	draw_rect(f, col)
	# светлая кромка сверху — «нарисованный» объём
	draw_line(f.position, f.position + Vector2(f.size.x, 0), col.lightened(0.35), 1.0)
