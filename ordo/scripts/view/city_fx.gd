class_name CityFx
extends Node
## Эффекты «Города» по событиям SimEvents (ARCHITECTURE §13): свой курсор, событий не теряет.
## Частицы — системы BattleFx (те же рисованные клубы дыма и пыли, свет солнца, ветер):
##   BUILDING_HIT       — пыль от удара по стене
##   BUILDING_DESTROYED — столб дыма и пыльное кольцо обрушения
##   BUILDING_DONE      — облачко пыли и надпись «Построено»
##   TREE_FELLED        — пыль и щепа у комля
##   LOOT, RES_DELIVERED, TRAINED — надписи на бумаге (OverlayView.float_text): «+4 золото» и т. п.
## Надписи доставки — только своему игроку (local_player). PerfMeter «view_cityfx».

const GOLD_INK := Color(0.55, 0.36, 0.05)
const GREEN_INK := Color(0.12, 0.38, 0.16)
const RED_INK := Color(0.55, 0.12, 0.08)
const INK := Color(0.2, 0.13, 0.08)

@export var driver_path: NodePath = ^"../../Driver"
@export var fx_path: NodePath = ^"../../Fx"
@export var overlay_path: NodePath = ^"../../HUD/Overlay"
## Чьи доставки подписывать
@export var local_player := 0

var query: GameQuery
var defs: Defs
var handled := 0

var _fx: BattleFx
var _overlay: OverlayView
var _cursor := 0
var _rng := BattleRng.new(91)


func _ready() -> void:
	_fx = get_node_or_null(fx_path) as BattleFx
	_overlay = get_node_or_null(overlay_path) as OverlayView
	var d := get_node_or_null(driver_path)
	if d and d.has_signal("started"):
		d.connect("started", func(_s: int) -> void: set_query(CityView.query_of(d)))
	if CityView.query_of(d):
		set_query(CityView.query_of(d))


func set_query(q: GameQuery) -> void:
	query = q
	defs = q.defs() if q else null
	_cursor = q.events().head if q else 0


func _process(_delta: float) -> void:
	if query == null:
		return
	var t0 := CityView.now_usec()
	var ev := query.events()
	var r := ev.range_since(_cursor)
	for seq in range(r.x, r.y):
		_handle(ev, ev.at(seq))
	_cursor = r.y
	CityView.mark(&"view_cityfx", t0)


func _handle(ev: SimEvents, i: int) -> void:
	var kind := ev.e_kind[i]
	var p2 := Vector2(ev.e_x[i], ev.e_z[i])
	var p := Vector3(p2.x, Terrain.height_at(p2.x, p2.y), p2.y)
	handled += 1
	match kind:
		SimEvents.Ev.BUILDING_HIT:
			_dust(p + Vector3(0, 1.5, 0), 3, 1.2)
		SimEvents.Ev.BUILDING_DESTROYED:
			_dust(p, 10, 3.5)
			_smoke(p + Vector3(0, 2.0, 0), 8)
			_text(p, tr("Разрушено"), RED_INK)
		SimEvents.Ev.BUILDING_DONE:
			_dust(p, 5, 2.5)
			if ev.e_player[i] == local_player:
				_text(p, tr("Построено"), GREEN_INK)
		SimEvents.Ev.TREE_FELLED:
			_dust(p + Vector3(0, 0.4, 0), 4, 1.5)
			if _fx and _fx.sparks:
				for k in 6:
					var v := Vector3(_rng.range_f(-2, 2), _rng.range_f(1.5, 3.5), _rng.range_f(-2, 2))
					_fx.puff(_fx.dust, p + Vector3(0, 0.8, 0), v, _rng.range_f(0.15, 0.3), 0.5, Color(0.75, 0.55, 0.35, 1))
		SimEvents.Ev.LOOT:
			var res := ev.e_a[i]
			_text(p, "+%d %s" % [ev.e_b[i] / 1000, _res_name(res)], GOLD_INK)
		SimEvents.Ev.RES_DELIVERED:
			if ev.e_player[i] == local_player:
				_text(p, "+%d %s" % [ev.e_b[i] / 1000, _res_name(ev.e_a[i])], INK)
		SimEvents.Ev.TRAINED:
			if ev.e_player[i] == local_player and defs and ev.e_c[i] >= 0 and ev.e_c[i] < defs.u_name.size():
				_text(p, tr(defs.u_name[ev.e_c[i]]), GREEN_INK)


func _dust(p: Vector3, n: int, spread: float) -> void:
	if _fx == null or _fx.dust == null:
		return
	for k in n:
		var o := Vector3(_rng.range_f(-spread, spread), _rng.range_f(0.2, 0.8), _rng.range_f(-spread, spread))
		var v := Vector3(o.x * 0.4, _rng.range_f(0.3, 1.0), o.z * 0.4)
		_fx.puff(_fx.dust, p + o, v, _rng.range_f(1.0, 2.4), _rng.range_f(0.5, 1.0))


func _smoke(p: Vector3, n: int) -> void:
	if _fx == null or _fx.smoke == null:
		return
	for k in n:
		var o := Vector3(_rng.range_f(-2, 2), k * 0.6, _rng.range_f(-2, 2))
		_fx.puff(_fx.smoke, p + o, Vector3(0, _rng.range_f(0.8, 1.8), 0), _rng.range_f(2.0, 3.6), _rng.range_f(0.6, 1.0),
			Color(0.55, 0.5, 0.48, 1))


func _text(p: Vector3, text: String, col: Color) -> void:
	if _overlay:
		_overlay.float_text(p, text, col)


func _res_name(r: int) -> String:
	if defs == null or r < 0 or r >= defs.r_name.size():
		return ""
	return tr(defs.r_name[r]).to_lower()
