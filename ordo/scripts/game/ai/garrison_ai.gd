class_name GarrisonAi
extends AiController
## Защита базы ИИ (ТЗ 7; ARCHITECTURE §12; AiDefs.GARRISON): отряды стоят у ставки на своих постах;
## враг в радиусе базы — ближние свободные отряды бьют ближайшего врага; врага нет — возвращаются на посты.
## Заодно держит базу «живой»: свободных работников ИИ отправляет на свои поля и короо, иначе — к дереву
## (полная экономика ИИ — позже, ТЗ 16.2). Этап 2: башни с лучниками (garrison) — TODO в MapSetup.
## Только чтение GameQuery и приказы.

const POST_R := 12.0             # отряд дальше от поста — вернуть
const WORKERS_EVERY := 5         # раз в столько раздумий — работники
const WORKERS_PER_THINK := 8

var home := Vector2.ZERO
var base_r := 90.0
var squads := PackedInt32Array()
var posts := PackedVector2Array()
var engaged := 0                 # отрядов в бою (для тестов)

var _targets := PackedInt32Array()   # [i] цель отряда i, 0
var _n := 0
var _buf := PackedInt32Array()


## params: {home: Vector2, base_r, squads: PackedInt32Array, posts: PackedVector2Array, period, phase}
func setup(p_player: int, p_params: Dictionary, p_seed: int) -> void:
	super.setup(p_player, p_params, p_seed)
	home = p_params.get("home", Vector2.ZERO)
	base_r = float(p_params.get("base_r", 90.0))
	squads = (p_params.get("squads", PackedInt32Array()) as PackedInt32Array).duplicate()
	posts = (p_params.get("posts", PackedVector2Array()) as PackedVector2Array).duplicate()
	while posts.size() < squads.size():
		posts.append(home)
	_targets.resize(squads.size())


func think(tick: int, q: GameQuery, out: Array[PackedInt32Array]) -> void:
	var gq := q as GameQueryImpl
	if gq == null or gq.is_defeated(player):
		return
	_n += 1
	var team := gq.players().team[player]
	gq.units_near(team, home, base_r, true, 0, _buf)
	var enemies := _buf.duplicate()
	engaged = 0
	for i in squads.size():
		var s := squads[i]
		if not gq.unit_alive_any(s):
			continue
		var sp := gq.unit_pos(s)
		if not enemies.is_empty():
			var cur := _targets[i]
			if cur != Ids.NULL and gq.unit_alive(cur) and gq.unit_pos(cur).distance_squared_to(home) <= base_r * base_r * 1.5:
				engaged += 1
				continue
			var t := _nearest(gq, enemies, sp)
			_targets[i] = t
			emit(out, SimCmd.attack(PackedInt32Array([s]), t, true))
			engaged += 1
		else:
			_targets[i] = Ids.NULL
			if sp.distance_squared_to(posts[i]) > POST_R * POST_R and gq.is_idle(s):
				emit(out, SimCmd.move(PackedInt32Array([s]), posts[i], false))
	if _n % WORKERS_EVERY == 1:
		_workers(gq, out)


func checksum() -> int:
	var h := super.checksum()
	h = AiController.mix(h, _n)
	for t in _targets:
		h = AiController.mix(h, t)
	return h


func _nearest(gq: GameQueryImpl, hs: PackedInt32Array, from: Vector2) -> int:
	var best := Ids.NULL
	var bd := INF
	for h in hs:
		var d := gq.unit_pos(h).distance_squared_to(from)
		if d < bd:
			bd = d
			best = h
	return best


## Свободные работники ИИ → своё поле / короо со свободным местом, иначе ближайшее дерево или жила
func _workers(gq: GameQueryImpl, out: Array[PackedInt32Array]) -> void:
	var idle := gq.idle_workers(player)
	if idle.is_empty():
		return
	var defs := gq.defs()
	var B := gq.buildings()
	var open_slots := {}                   # слот здания → свободных мест
	for b in B.hw:
		if B.owner[b] == player and B.state[b] == BuildingTable.State.ACTIVE:
			var slots := defs.b_work_slots[B.btype[b]]
			if slots > B.workers_n[b]:
				open_slots[b] = slots - B.workers_n[b]
	var k := 0
	for w in idle:
		if k >= WORKERS_PER_THINK:
			break
		var wp := gq.unit_pos(w)
		var best := -1
		var bd := INF
		for b: int in open_slots:
			if open_slots[b] <= 0:
				continue
			var d := Vector2(B.x[b], B.z[b]).distance_squared_to(wp)
			if d < bd:
				bd = d
				best = b
		var src := Ids.NULL
		if best >= 0:
			open_slots[best] -= 1
			src = B.handle(best)
		else:
			src = _nearest_node(gq, wp)
		if src != Ids.NULL:
			emit(out, SimCmd.gather(PackedInt32Array([w]), src))
			k += 1


func _nearest_node(gq: GameQueryImpl, from: Vector2) -> int:
	var N := gq.nodes()
	var best := Ids.NULL
	var bd := 120.0 * 120.0
	for n in N.hw:
		if N.ntype[n] < 0 or N.amount_milli[n] == 0 or N.workers_n[n] >= N.workers_max[n]:
			continue
		var d := Vector2(N.x[n], N.z[n]).distance_squared_to(from)
		if d < bd:
			bd = d
			best = N.handle(n)
	return best
