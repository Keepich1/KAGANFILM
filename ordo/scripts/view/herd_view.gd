class_name HerdView
extends Node3D
## Стада (ARCHITECTURE §13): min(голов, 80) животных на стадо, бродят как в лагере среза
## (код BattleAmbient: пасутся, переходят к новой траве, изредка пробежка, не стоят друг в друге).
## Стадо в загоне — больше половины внутри загона, остальные пасутся вокруг в graze_r;
## угнанное/перегоняемое (DRIVEN, CAPTURED) — все идут кучей за точкой стада (её двигает ECON).
## Свои слои толпы «sheep» и «horse». Детерминировано: зерно — описатель стада. PerfMeter «view_herds».

const DT := 1.0 / 30.0
const S := AnimSpec.Sheep
const R := AnimSpec.Horse
const MAX_PER_HERD := 80
const CROWD_LAYER_PATH := "res://scripts/units/crowd_layer.gd"

@export var driver_path: NodePath = ^"../../Driver"

var query: GameQuery
var defs: Defs
var count := 0

var _driver: SimDriver
var _layers: Array[Node3D] = []        # 0 овцы, 1 кони
var _acc := 0.0
var _time := 0.0
var _steps := 0
var _hgen := PackedInt32Array()        # поколение стада, которое нарисовано
var _hn := PackedInt32Array()          # сколько животных у стада
# по животным
var _herd := PackedInt32Array()
var _kind := PackedInt32Array()
var _x := PackedFloat32Array()
var _z := PackedFloat32Array()
var _h := PackedFloat32Array()
var _tx := PackedFloat32Array()
var _tz := PackedFloat32Array()
var _state := PackedInt32Array()
var _timer := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _var := PackedFloat32Array()
var _inpen := PackedByteArray()
var _members: Array[PackedInt32Array] = []   # стадо → его животные
var _rng := BattleRng.new(77)


func _ready() -> void:
	_driver = get_node_or_null(driver_path) as SimDriver
	if _driver:
		_driver.started.connect(func(_s: int) -> void: set_query(CityView.query_of(_driver)))
	if CityView.query_of(_driver):
		set_query(CityView.query_of(_driver))


func set_query(q: GameQuery) -> void:
	query = q
	defs = q.defs() if q else null
	count = 0
	for a: Variant in [_herd, _kind, _state, _x, _z, _h, _tx, _tz, _timer, _phase, _speed, _var, _hgen, _hn]:
		a.resize(0)
	_inpen.resize(0)
	_members.clear()
	if _layers.is_empty():
		for id: String in ["sheep", "horse"]:
			var l: Node3D
			if ResourceLoader.exists(CROWD_LAYER_PATH):
				l = (load(CROWD_LAYER_PATH) as Script).new() as Node3D
			else:
				l = (load("res://scripts/battle/debug_layer.gd") as Script).new() as Node3D
			l.name = "Layer_" + id
			add_child(l)
			l.call("setup", id, 128)
			_layers.append(l)
	for l in _layers:
		l.call("set_visible_count", 0)
	if q:
		_sync()


func _process(delta: float) -> void:
	if query == null:
		return
	var t0 := CityView.now_usec()
	var scale := 1.0
	if _driver:
		scale = 0.0 if _driver.paused else _driver.time_scale
	_acc += delta * scale
	var guard := 0
	while _acc >= DT and guard < 8:
		_acc -= DT
		_step()
		guard += 1
	_write()
	CityView.mark(&"view_herds", t0)


## Сверка со стадами: новые, пропавшие, изменилось число голов
func _sync() -> void:
	var ht := query.herds()
	if _hgen.size() < ht.hw:
		var old := _hgen.size()
		_hgen.resize(ht.hw)
		_hn.resize(ht.hw)
		for h in range(old, ht.hw):
			_hgen[h] = 0
			_hn[h] = 0
	var changed := false
	for h in ht.hw:
		var want := 0
		if ht.state[h] != HerdTable.State.FREE:
			want = mini(ht.heads(h), MAX_PER_HERD)
		if ht.gen[h] != _hgen[h] and _hn[h] > 0:
			_remove_herd(h)
			changed = true
		_hgen[h] = ht.gen[h]
		while _hn[h] < want:
			_add(h, ht)
			changed = true
		while _hn[h] > want:
			_remove_one(h)
			changed = true
	if changed or _members.size() != ht.hw:
		var n := [0, 0]
		for k in _kind:
			n[k] += 1
		for i in 2:
			var cap := int(_layers[i].get("capacity"))
			if n[i] > cap:
				_layers[i].call("setup", ["sheep", "horse"][i], maxi(cap * 2, n[i]))
			_layers[i].call("set_visible_count", n[i])
		# животные по стадам — расталкивание только внутри своего стада
		_members.clear()
		for h in ht.hw:
			_members.append(PackedInt32Array())
		for j in count:
			var m: PackedInt32Array = _members[_herd[j]]
			m.append(j)


func _add(h: int, ht: HerdTable) -> void:
	var j := count
	count += 1
	var kind := 1 if defs.h_ids[ht.htype[h]] == "horse" else 0
	_rng.reseed(ht.handle(h) * 977 + _hn[h] * 31 + 1)
	var inside := _hn[h] % 20 < 11 or kind == 1
	var p := _point(h, ht, inside)
	_herd.append(h)
	_kind.append(kind)
	_x.append(p.x)
	_z.append(p.y)
	_h.append(_rng.range_f(-PI, PI))
	_tx.append(p.x)
	_tz.append(p.y)
	_state.append(0)
	_timer.append(_rng.range_f(0.0, 6.0))
	_phase.append(_rng.next_float())
	_speed.append(0.0)
	_var.append(BattleRng.hash01(ht.handle(h) * 131 + _hn[h]))
	_inpen.append(1 if inside else 0)
	_hn[h] += 1


func _remove_one(h: int) -> void:
	for j in range(count - 1, -1, -1):
		if _herd[j] == h:
			_remove_at(j)
			_hn[h] -= 1
			return


func _remove_herd(h: int) -> void:
	for j in range(count - 1, -1, -1):
		if _herd[j] == h:
			_remove_at(j)
	_hn[h] = 0


func _remove_at(j: int) -> void:
	for a: Variant in [_herd, _kind, _state, _x, _z, _h, _tx, _tz, _timer, _phase, _speed, _var]:
		a.remove_at(j)
	_inpen.remove_at(j)
	count -= 1


## Точка для животного стада h: внутри загона или на пастбище вокруг (в graze_r)
func _point(h: int, ht: HerdTable, inside: bool) -> Vector2:
	var c := Vector2(ht.x[h], ht.z[h])
	if ht.state[h] != HerdTable.State.PEN:
		return c + Vector2(_rng.range_f(0.5, 5.0), 0.0).rotated(_rng.range_f(-PI, PI))
	var pen := _pen_rect(h, ht)
	if inside and pen.size.x > 0.0:
		var e := pen.size * 0.5 - Vector2(1.4, 1.4)
		return pen.position + Vector2(_rng.range_f(-e.x, e.x), _rng.range_f(-e.y, e.y))
	var r := maxf(ht.graze_r[h], 10.0)
	var half := pen.size.x * 0.5 + 3.0 if pen.size.x > 0.0 else 3.0
	return c + Vector2(_rng.range_f(half, r), 0.0).rotated(_rng.range_f(-PI, PI))


## Загон стада: центр (position) и размер (size) — ось-выровненно (загоны ставятся четвертями оборота)
func _pen_rect(h: int, ht: HerdTable) -> Rect2:
	var bt := query.buildings()
	if ht.pen_b[h] == 0 or not bt.valid(ht.pen_b[h]):
		return Rect2(Vector2(ht.x[h], ht.z[h]), Vector2.ZERO)
	var b := bt.slot(ht.pen_b[h])
	var sz := defs.b_size[bt.btype[b]]
	if bt.rot_q[b] % 2 == 1:
		sz = Vector2(sz.y, sz.x)
	return Rect2(Vector2(bt.x[b], bt.z[b]), sz)


func _step() -> void:
	_time += DT
	_steps += 1
	if _steps % 30 == 0:
		_sync()
	var ht := query.herds()
	for j in count:
		_timer[j] -= DT
		var h := _herd[j]
		if ht.state[h] != HerdTable.State.PEN:
			_follow(j, Vector2(ht.x[h], ht.z[h]))
		elif _kind[j] == 0:
			_step_sheep(j, h, ht)
		else:
			_step_horse(j, h, ht)
	_separate()


func _step_sheep(j: int, h: int, ht: HerdTable) -> void:
	if _timer[j] <= 0.0:
		var r := _rng.next_float()
		if r < 0.62:
			_state[j] = S.GRAZE
			_timer[j] = _rng.range_f(3.0, 11.0)
			_speed[j] = 0.0
		else:
			var p := Vector2(_x[j], _z[j]) + Vector2(_rng.range_f(1.5, 5.0), 0.0).rotated(_rng.range_f(-PI, PI))
			if not _ok(j, h, ht, p):
				p = _point(h, ht, _inpen[j] == 1)
			_tx[j] = p.x
			_tz[j] = p.y
			var run := r > 0.96
			_state[j] = S.RUN if run else S.WALK
			_speed[j] = 1.6 if run else 0.45
			_timer[j] = 12.0
	_move_to(j, AnimSpec.STRIDE_SHEEP.get(_state[j], 1.0), 2.4, S.GRAZE)


func _step_horse(j: int, h: int, ht: HerdTable) -> void:
	if _timer[j] <= 0.0:
		var r := _rng.next_float()
		if r < 0.55:
			_state[j] = R.IDLE
			_timer[j] = _rng.range_f(4.0, 12.0)
			_speed[j] = 0.0
		else:
			var p := _point(h, ht, _inpen[j] == 1)
			_tx[j] = p.x
			_tz[j] = p.y
			var trot := r > 0.9
			_state[j] = R.TROT if trot else R.WALK
			_speed[j] = 3.2 if trot else 1.3
			_timer[j] = 15.0
	_move_to(j, AnimSpec.STRIDE_HORSE.get(_state[j], 1.0), 1.6, R.IDLE)


## Угнанное или перегоняемое: к точке стада со своим смещением, рысью/бегом
func _follow(j: int, c: Vector2) -> void:
	var off := Vector2(2.0 + 5.0 * _var[j], 0.0).rotated(_var[j] * 97.0)
	var want := c + off
	var d := Vector2(_x[j], _z[j]).distance_to(want)
	if d > 1.0:
		_tx[j] = want.x
		_tz[j] = want.y
		var run := d > 6.0
		if _kind[j] == 0:
			_state[j] = S.RUN if run else S.WALK
		else:
			_state[j] = R.GALLOP if run else R.TROT
		_speed[j] = (3.2 if run else 1.4) * (2.0 if _kind[j] == 1 else 1.0)
	_move_to(j, AnimSpec.STRIDE_SHEEP.get(_state[j], 1.0) if _kind[j] == 0 else AnimSpec.STRIDE_HORSE.get(_state[j], 2.0),
		3.0, S.GRAZE if _kind[j] == 0 else R.IDLE)


func _ok(j: int, h: int, ht: HerdTable, p: Vector2) -> bool:
	var pen := _pen_rect(h, ht)
	var inside := absf(p.x - pen.position.x) < pen.size.x * 0.5 - 1.2 and absf(p.y - pen.position.y) < pen.size.y * 0.5 - 1.2
	if _inpen[j] == 1:
		return inside
	var r := maxf(ht.graze_r[h], 10.0)
	return not inside and p.distance_to(Vector2(ht.x[h], ht.z[h])) < r and \
		not (absf(p.x - pen.position.x) < pen.size.x * 0.5 + 1.0 and absf(p.y - pen.position.y) < pen.size.y * 0.5 + 1.0)


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


func _separate() -> void:
	if _steps % 2 != 0:
		return
	for a in count:
		if _speed[a] <= 0.0 or _herd[a] >= _members.size():
			continue
		for b in _members[_herd[a]]:
			if b == a:
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


func _write() -> void:
	var slot := [0, 0]
	for j in count:
		var k := _kind[j]
		var x := _x[j]
		var z := _z[j]
		var st := _state[j]
		var aux := 1.0
		if k == 0 and st == S.GRAZE or k == 1 and st == R.IDLE:
			aux = 0.0
		_layers[k].call("set_instance", slot[k], Transform3D(Basis(Vector3.UP, _h[j]), Vector3(x, Terrain.height_at(x, z), z)),
			AnimSpec.custom(st, _phase[j], aux, _var[j]))
		slot[k] += 1
