class_name BattleFxGallery
extends Node3D
## Витрина эффектов для настройки без боя (scenes/test/battle_fx.tscn): по кругу —
## залп из 12 ружей, искры рукопашной, пыль скачущего коня, удар натиска, клич.
## Эффекты рисует обычный BattleFx (узел fx_path), события подаются напрямую.

@export var fx_path: NodePath = ^"../Fx"
@export var period := 6.0

var fx: BattleFx
var _t := 0.0
var _fired := {}
var _gallop_x := -14.0


func _ready() -> void:
	fx = get_node_or_null(fx_path) as BattleFx


func _process(delta: float) -> void:
	if fx == null:
		return
	_t += delta
	var c := fmod(_t, period)
	var cycle := int(_t / period)
	if c >= 0.3 and not _fired.has([cycle, 0]):
		_fired[[cycle, 0]] = true
		for i in 12:
			var p := Vector3(-6.0 + i * 1.0, 1.38, 0.0)
			fx._on_shot(-1, p, Vector3(-0.05, 0.02, -1.0).normalized(), false)
	if c >= 1.2 and not _fired.has([cycle, 1]):
		_fired[[cycle, 1]] = true
		for i in 6:
			fx._spark_budget = 40
			fx._on_melee_hit(-1, -1, Vector3(5.0 + i * 0.4, 1.4, -3.0))
	if c >= 2.0 and not _fired.has([cycle, 2]):
		_fired[[cycle, 2]] = true
		fx._on_impact(-1, Vector3(-3.0, 0.0, -9.0), 9.0)
	if c >= 3.0 and not _fired.has([cycle, 3]):
		_fired[[cycle, 3]] = true
		fx._on_war_cry(-1, Vector3(6.0, 0.0, -8.0))
	# скачущий конь: пыль по скорости
	_gallop_x += delta * 9.0
	if _gallop_x > 14.0:
		_gallop_x = -14.0
	if fmod(_t, 0.12) < delta:
		fx.puff(fx.dust, Vector3(_gallop_x - 1.0, 0.35, -14.0), Vector3(-1.5, 0.6, 0.0), 1.0, 0.7)
