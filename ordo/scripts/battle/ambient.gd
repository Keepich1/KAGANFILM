class_name BattleAmbient
extends Node
## Жизнь лагеря (ТЗ 11.4 «Окружение»): малчы работают, отара пасётся и бродит у короо,
## кони топчутся в жылкы, жоокеры стоят на страже у входа. Детерминировано (своё зерно), дёшево.
##
## Места берутся из меток лагеря (scenes/camp): WorkSpot_*, SheepPen, HorsePen, GuardPost_*
## (ищутся по имени во всей сцене); если лагеря нет — координаты из CONTRACT §3.
##
## Для BattleView: count, unit_ids[i], xforms[i], customs[i] (AnimSpec.custom) — обновляются в _process.

const DT := 1.0 / 30.0
const H := AnimSpec.Human
const R := AnimSpec.Horse
const S := AnimSpec.Sheep

## Запасные места (CONTRACT §3, раскладка лагеря)
const SHEEP_PEN := Vector2(-115.0, 65.0)
const HORSE_PEN := Vector2(-25.0, 90.0)
const WORK_SPOTS := [Vector2(-19.3, 27.7), Vector2(-32.0, 15.7), Vector2(-46.8, -20.6), Vector2(-22.1, 17.9),
	Vector2(-38.4, -6.4), Vector2(-68.8, -21.9), Vector2(-104.0, 63.1), Vector2(-84.0, 4.0)]
const GUARD_POSTS := [Vector3(-21.5, 52.2, 0.785), Vector3(-27.8, 58.5, 0.785), Vector3(-48.0, 23.5, 0.785),
	Vector3(-56.1, 31.7, 0.785)]

@export var sheep_count := 70
@export var horse_count := 12
@export var worker_count := 8
@export var guard_count := 5
@export var ambient_seed := 11
## Сценарий: скорость времени и пауза — как у боя
@export var scenario_path: NodePath = ^"../Scenario"

var count := 0
var unit_ids := PackedStringArray()
var xforms: Array[Transform3D] = []
var customs := PackedColorArray()
var time := 0.0

var _rng: BattleRng
var _scenario: ScenarioClash
var _acc := 0.0
# по актёрам
var _kind := PackedInt32Array()      # 0 овца, 1 конь, 2 малчы, 3 страж
var _x := PackedFloat32Array()
var _z := PackedFloat32Array()
var _h := PackedFloat32Array()
var _tx := PackedFloat32Array()
var _tz := PackedFloat32Array()
var _state := PackedInt32Array()
var _timer := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _aux := PackedFloat32Array()     # вид работы, сторона загона
var _var := PackedFloat32Array()
var _home := PackedVector2Array()    # центр области
var _area: Array[Transform3D] = []   # область: базис (поворот) и центр; размер — в _size
var _size := PackedVector2Array()
var _spot_a := PackedVector2Array()  # для носильщиков: откуда и куда
var _spot_b := PackedVector2Array()
var _ready_done := false


func _ready() -> void:
	_scenario = get_node_or_null(scenario_path) as ScenarioClash
	_build()


func _find(marker_name: String) -> Node3D:
	var root := get_tree().current_scene if is_inside_tree() else null
	if root == null:
		return null
	return root.find_child(marker_name, true, false) as Node3D


func _find_prefix(prefix: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var root := get_tree().current_scene if is_inside_tree() else null
	if root == null:
		return out
	for n in root.find_children(prefix + "*", "Node3D", true, false):
		out.append(n as Node3D)
	out.sort_custom(func(a: Node3D, b: Node3D) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return out


func _area_of(marker_name: String, fallback: Vector2, fallback_size: Vector2) -> Array:
	var m := _find(marker_name)
	if m:
		var sz: Variant = m.get("size")
		return [m.global_transform, sz if sz is Vector2 else fallback_size]
	return [Transform3D(Basis(), Vector3(fallback.x, 0.0, fallback.y)), fallback_size]


func _build() -> void:
	_rng = BattleRng.new(ambient_seed)
	var pen := _area_of("SheepPen", SHEEP_PEN, Vector2(12, 12))
	var hpen := _area_of("HorsePen", HORSE_PEN, Vector2(14, 10))
	var spots: Array[Vector2] = []
	for m in _find_prefix("WorkSpot_"):
		spots.append(Vector2(m.global_position.x, m.global_position.z))
	if spots.is_empty():
		for p in WORK_SPOTS:
			spots.append(p)
	var posts: Array[Vector3] = []
	for m in _find_prefix("GuardPost_"):
		var f := m.global_transform.basis.z
		posts.append(Vector3(m.global_position.x, m.global_position.z, atan2(f.x, f.z)))
	if posts.is_empty():
		for p in GUARD_POSTS:
			posts.append(p)
	# отара: часть в загоне, часть пасётся рядом
	var pen_xf: Transform3D = pen[0]
	var pen_size: Vector2 = pen[1]
	var inside := int(sheep_count * 0.55)
	for i in sheep_count:
		if i < inside:
			_add(0, "sheep", pen_xf, pen_size - Vector2(1.2, 1.2))
		else:
			# пасутся снаружи: пятно у входа в загон (локальный +Z)
			var out_xf := pen_xf.translated_local(Vector3(0.0, 0.0, pen_size.y * 0.5 + 12.0))
			_add(0, "sheep", out_xf, Vector2(26.0, 18.0))
	var hpen_xf: Transform3D = hpen[0]
	var hpen_size: Vector2 = hpen[1]
	for i in horse_count:
		_add(1, "horse", hpen_xf, hpen_size - Vector2(2.0, 2.0))
	# малчы: работают у мест; двое носят груз между местами
	for i in worker_count:
		var spot: Vector2 = spots[i % spots.size()]
		var j := _add(2, "kip_malchy", Transform3D(Basis(), Vector3(spot.x, 0.0, spot.y)), Vector2(1.5, 1.5))
		_aux[j] = [0.0, 0.25, 0.5, 0.0, 0.25, 0.5][i % 6]
		if i >= worker_count - 2 and spots.size() > 1:
			_aux[j] = 0.75  # носит
			_spot_a[j] = spot
			_spot_b[j] = spots[(i + 3) % spots.size()]
			_tx[j] = _spot_b[j].x
			_tz[j] = _spot_b[j].y
			_state[j] = H.WORK
		_h[j] = _rng.range_f(-PI, PI)
	# стража у входа
	for i in guard_count:
		var p: Vector3 = posts[i % posts.size()]
		var off := Vector2(1.6, 0.0).rotated(-p.z) * float(i / posts.size())
		var j := _add(3, "kip_jooker", Transform3D(Basis(), Vector3(p.x + off.x, 0.0, p.y + off.y)), Vector2(0.2, 0.2))
		_h[j] = p.z
		_home[j] = Vector2(p.x + off.x, p.y + off.y)
	_ready_done = true
	_write_all()


func _add(kind: int, unit_id: String, area: Transform3D, size: Vector2) -> int:
	var j := count
	count += 1
	unit_ids.append(unit_id)
	_kind.append(kind)
	_area.append(area)
	_size.append(size)
	var local := Vector3(_rng.range_f(-0.5, 0.5) * size.x, 0.0, _rng.range_f(-0.5, 0.5) * size.y)
	var p := area * local
	_x.append(p.x)
	_z.append(p.z)
	_h.append(_rng.range_f(-PI, PI))
	_tx.append(p.x)
	_tz.append(p.z)
	_state.append(0)
	_timer.append(_rng.range_f(0.0, 6.0))
	_phase.append(_rng.next_float())
	_speed.append(0.0)
	_aux.append(0.0)
	_var.append(BattleRng.hash01(j * 977 + ambient_seed))
	_home.append(Vector2(area.origin.x, area.origin.z))
	_spot_a.append(Vector2.ZERO)
	_spot_b.append(Vector2.ZERO)
	xforms.append(Transform3D())
	customs.append(Color())
	match kind:
		2: _state[j] = H.WORK
		3: _state[j] = H.IDLE
	return j


func _process(delta: float) -> void:
	if not _ready_done:
		return
	var scale := 1.0
	if _scenario:
		if _scenario.paused:
			return
		scale = _scenario.time_scale
	_acc += delta * scale
	var guard := 0
	while _acc >= DT and guard < 8:
		_acc -= DT
		_step()
		guard += 1
	_write_all()


func _step() -> void:
	time += DT
	for j in count:
		_timer[j] -= DT
		match _kind[j]:
			0: _step_sheep(j)
			1: _step_horse(j)
			2: _step_worker(j)
			3: _step_guard(j)
	_separate_sheep()


## Случайная точка области актёра (в мире)
func _area_point(j: int, margin := 0.0) -> Vector2:
	var sz := _size[j] - Vector2(margin, margin)
	var p := _area[j] * Vector3(_rng.range_f(-0.5, 0.5) * sz.x, 0.0, _rng.range_f(-0.5, 0.5) * sz.y)
	return Vector2(p.x, p.z)


func _inside(j: int, x: float, z: float) -> bool:
	var l := _area[j].affine_inverse() * Vector3(x, 0.0, z)
	return absf(l.x) <= _size[j].x * 0.5 and absf(l.z) <= _size[j].y * 0.5


func _step_sheep(j: int) -> void:
	if _timer[j] <= 0.0:
		var r := _rng.next_float()
		if r < 0.62:
			_state[j] = S.GRAZE
			_timer[j] = _rng.range_f(3.0, 11.0)
			_speed[j] = 0.0
		else:
			# пара шагов к новой траве; изредка — пробежка
			var p := Vector2(_x[j], _z[j]) + Vector2(_rng.range_f(1.5, 5.0), 0.0).rotated(_rng.range_f(-PI, PI))
			if not _inside(j, p.x, p.y):
				p = _area_point(j)
			_tx[j] = p.x
			_tz[j] = p.y
			var run := r > 0.96
			_state[j] = S.RUN if run else S.WALK
			_speed[j] = 1.6 if run else 0.45
			_timer[j] = 12.0
	_move_to(j, AnimSpec.STRIDE_SHEEP.get(_state[j], 1.0), 2.4, S.GRAZE)


func _step_horse(j: int) -> void:
	if _timer[j] <= 0.0:
		var r := _rng.next_float()
		if r < 0.55:
			_state[j] = R.IDLE
			_timer[j] = _rng.range_f(4.0, 12.0)
			_speed[j] = 0.0
		else:
			var p := _area_point(j)
			_tx[j] = p.x
			_tz[j] = p.y
			var trot := r > 0.9
			_state[j] = R.TROT if trot else R.WALK
			_speed[j] = 3.2 if trot else 1.3
			_timer[j] = 15.0
	_move_to(j, AnimSpec.STRIDE_HORSE.get(_state[j], 1.0), 1.6, R.IDLE)


func _step_worker(j: int) -> void:
	if _aux[j] < 0.7:
		# работает на месте, изредка переступает
		_phase[j] = fposmod(_phase[j] + DT / 1.6, 1.0)
		if _timer[j] <= 0.0:
			_timer[j] = _rng.range_f(6.0, 14.0)
			_h[j] = BattleSim.rotate_toward(_h[j], _h[j] + _rng.range_f(-0.6, 0.6), 1.0)
		return
	# носильщик: туда-обратно между местами, передых на месте
	var dx := _tx[j] - _x[j]
	var dz := _tz[j] - _z[j]
	var d := sqrt(dx * dx + dz * dz)
	if _state[j] == H.IDLE:
		_phase[j] = fposmod(time / AnimSpec.IDLE_PERIOD + _var[j], 1.0)
		if _timer[j] <= 0.0:
			_state[j] = H.WORK
			var to := _spot_a[j] if Vector2(_tx[j], _tz[j]).distance_to(_spot_b[j]) < 0.1 else _spot_b[j]
			_tx[j] = to.x
			_tz[j] = to.y
		return
	if d < 0.4:
		_state[j] = H.IDLE
		_timer[j] = _rng.range_f(2.0, 4.0)
		return
	var v := 1.2
	_x[j] += dx / d * v * DT
	_z[j] += dz / d * v * DT
	_h[j] = BattleSim.rotate_toward(_h[j], atan2(dx, dz), 3.0 * DT)
	_phase[j] = fposmod(_phase[j] + v * DT / AnimSpec.STRIDE_HUMAN[H.WALK], 1.0)


func _step_guard(j: int) -> void:
	_phase[j] = fposmod(time / AnimSpec.IDLE_PERIOD + _var[j], 1.0)
	if _timer[j] <= 0.0:
		_timer[j] = _rng.range_f(5.0, 12.0)
		_tx[j] = _rng.range_f(-0.35, 0.35)
	# стражник поглядывает по сторонам
	_h[j] = BattleSim.rotate_toward(_h[j], _h[j] + _tx[j], 0.3 * DT)
	_tx[j] *= 0.995


func _move_to(j: int, stride: float, turn: float, rest_state: int) -> void:
	if _speed[j] <= 0.0:
		_phase[j] = fposmod(_phase[j] + DT / AnimSpec.IDLE_PERIOD, 1.0)
		return
	var dx := _tx[j] - _x[j]
	var dz := _tz[j] - _z[j]
	var d := sqrt(dx * dx + dz * dz)
	if d < 0.15:
		_state[j] = rest_state
		_speed[j] = 0.0
		_timer[j] = _rng.range_f(2.0, 8.0)
		return
	var want := atan2(dx, dz)
	_h[j] = BattleSim.rotate_toward(_h[j], want, turn * DT)
	var align := clampf(cos(angle_difference(_h[j], want)), 0.0, 1.0)
	var step := minf(d, _speed[j] * DT * align)
	_x[j] += sin(_h[j]) * step
	_z[j] += cos(_h[j]) * step
	_phase[j] = fposmod(_phase[j] + step / stride, 1.0)


func _separate_sheep() -> void:
	# раз в два шага: овцы не стоят друг в друге (только идущие против всех)
	if int(time / DT) % 2 != 0:
		return
	for a in count:
		if _kind[a] != 0 or _speed[a] <= 0.0:
			continue
		for b in count:
			if b == a or _kind[b] > 1:
				continue
			var dx := _x[b] - _x[a]
			var dz := _z[b] - _z[a]
			var rr := 0.8 if _kind[b] == 0 else 1.6
			var d2 := dx * dx + dz * dz
			if d2 < rr * rr and d2 > 0.0001:
				var d := sqrt(d2)
				var k := (rr - d) / d * 0.5
				_x[a] -= dx * k
				_z[a] -= dz * k


func _write_all() -> void:
	for j in count:
		var x := _x[j]
		var z := _z[j]
		xforms[j] = Transform3D(Basis(Vector3.UP, _h[j]), Vector3(x, Terrain.height_at(x, z), z))
		var st := _state[j]
		var aux := 1.0
		match _kind[j]:
			2:
				aux = _aux[j] if st == H.WORK else 0.0
			3:
				aux = 0.0
		if _kind[j] == 0 and st == S.GRAZE or _kind[j] == 1 and st == R.IDLE:
			aux = 0.0
		customs[j] = AnimSpec.custom(st, _phase[j], aux, _var[j])
