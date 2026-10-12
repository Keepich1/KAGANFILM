class_name SquadSelection
extends Node3D
## Выделение отрядов (ТЗ 10, 11.2): ЛКМ по юниту — его отряд, двойной клик — все отряды
## того же вида и стороны, ЛКМ по пустой земле — снять выделение.
## Под каждым бойцом выделенных отрядов — кольцо цвета стороны (раненые краснеют).
## Полоски здоровья и морали рисует SquadBars по списку selected.
##
## Для кадра без мыши: аргумент --select=kok или --select=kip (отряд сценария).

signal selection_changed(squads: PackedInt32Array)

const RING_SHADER := preload("res://shaders/fx/ui_ring.gdshader")
const SIDE_LIGHT := [Color("#7fe8c8"), Color("#ffa597")]   # ТЗ 2.1, 2.2: светлые цвета сторон
const WOUNDED := Color(1.0, 0.25, 0.18)

@export var scenario_path: NodePath = ^"../Scenario"
@export var pick_radius := 3.0

var scenario: ScenarioClash
var selected := PackedInt32Array()

var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _last_click := -1.0


func _ready() -> void:
	scenario = get_node_or_null(scenario_path) as ScenarioClash
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.orientation = PlaneMesh.FACE_Y
	var m := ShaderMaterial.new()
	m.shader = RING_SHADER
	m.render_priority = 2
	q.material = m
	_mm.mesh = q
	_mm.instance_count = 256
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Rings"
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	if scenario:
		scenario.started.connect(func(_s: int) -> void: _select(PackedInt32Array()))
		var ordo := get_node_or_null("/root/Ordo")
		if ordo and ordo.has_arg("select"):
			_auto_select.call_deferred(String(ordo.arg("select")))


func _auto_select(which: String) -> void:
	if scenario.sim == null:
		return
	match which:
		"kok": _select(PackedInt32Array([scenario.kok]))
		"kip": _select(PackedInt32Array([scenario.kip]))
		"all": _select(PackedInt32Array([scenario.kok, scenario.kip]))


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed or scenario == null or scenario.sim == null:
		return
	var hit: Variant = _ground_hit(mb.position)
	if hit == null:
		return
	var u := _unit_at(hit as Vector3)
	var now := Time.get_ticks_msec() / 1000.0
	var double := mb.double_click or now - _last_click < 0.35
	_last_click = now
	if u < 0:
		_select(PackedInt32Array())
		return
	var sim := scenario.sim
	var s := sim.u_squad[u]
	if double:
		# все отряды того же вида и стороны
		var out := PackedInt32Array()
		for k in sim.squads:
			if sim.sq_side[k] == sim.sq_side[s] and sim.sq_type[k] == sim.sq_type[s] and sim.sq_alive[k] > 0:
				out.append(k)
		_select(out)
	else:
		_select(PackedInt32Array([s]))


func _select(squads: PackedInt32Array) -> void:
	selected = squads
	selection_changed.emit(selected)


## Точка на земле под курсором (луч камеры, уточнение по рельефу)
func _ground_hit(screen: Vector2) -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if d.y > -0.01:
		return null
	var y := 0.0
	var p := o
	for i in 4:
		var t := (y - o.y) / d.y
		p = o + d * t
		y = Terrain.height_at(p.x, p.z)
	return p


func _unit_at(p: Vector3) -> int:
	var sim := scenario.sim
	var best := -1
	var bd := pick_radius * pick_radius
	for u in sim.n:
		if sim.u_life[u] != BattleSim.Life.ALIVE:
			continue
		var dx := sim.u_x[u] - p.x
		var dz := sim.u_z[u] - p.z
		var d2 := dx * dx + dz * dz
		if d2 < bd:
			bd = d2
			best = u
	return best


func _process(_delta: float) -> void:
	if scenario == null or scenario.sim == null:
		_mm.visible_instance_count = 0
		return
	var sim := scenario.sim
	var a := scenario.alpha
	var i := 0
	for s in selected:
		if s < 0 or s >= sim.squads:
			continue
		var side_col: Color = SIDE_LIGHT[clampi(sim.sq_side[s], 0, 1)]
		for u in sim.sq_members[s]:
			if sim.u_life[u] != BattleSim.Life.ALIVE or i >= _mm.instance_count:
				continue
			var x := lerpf(sim.u_px[u], sim.u_x[u], a)
			var z := lerpf(sim.u_pz[u], sim.u_z[u], a)
			var r := sim.t_radius[sim.u_type[u]] * 2.7
			var xf := Transform3D(Basis.from_scale(Vector3(r, 1.0, r)), Vector3(x, Terrain.height_at(x, z) + 0.06, z))
			_mm.set_instance_transform(i, xf)
			var hp := sim.u_hp[u] / maxf(sim.t_hp[sim.u_type[u]], 1.0)
			_mm.set_instance_color(i, side_col.lerp(WOUNDED, clampf(1.0 - hp, 0.0, 1.0) * 0.85))
			i += 1
	_mm.visible_instance_count = i
