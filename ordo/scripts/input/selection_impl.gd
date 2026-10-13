class_name SelectionImpl
extends RefCounted
## Поведение выделения (ARCHITECTURE §14, ТЗ §10) поверх SelectionModel (хранение — договор):
##   • щелчок — свой юнит (отряд выделяется всеми бойцами), здание, узел, стадо или чужой юнит (посмотреть);
##     Shift — добавить/убрать;
##   • рамка — свои юниты, чьи точки на экране внутри (отряды целиком); Shift — добавить;
##   • двойной щелчок — все свои того же рода, видимые на экране.
## Экранные координаты даёт RtsInput (to_screen), чтобы тесты обходились без камеры.

## Запас отсечения рамки, м: голова юнита на холме проецируется дальше своей точки на земле
const CULL_M := 8.0

var query: GameQuery
var model: SelectionModel
var player := 0


func _init(q: GameQuery = null, m: SelectionModel = null, p := 0) -> void:
	query = q
	model = m
	player = p


## Щелчок в мире: подобрать сущность в радиусе r (м)
func click(world: Vector2, shift: bool, r := 2.5) -> int:
	var h := query.pick(player, world, r)
	if h == 0:
		if not shift:
			model.set_selection(PackedInt32Array())
		return 0
	var hs := expand(h)
	var own := RtsInput.owner_of(query, h) == player
	if shift and own and _all_own(model.selected) and Ids.kind(h) == Ids.Kind.UNIT and _units_only(model.selected):
		var cur := model.selected.duplicate()
		if cur.has(h):
			for x in hs:
				var i := cur.find(x)
				if i >= 0:
					cur.remove_at(i)
			model.set_selection(cur)
		else:
			model.add(hs)
	else:
		model.set_selection(hs)
	return h


## Рамка (экранный прямоугольник): свои юниты внутри, отряды целиком. to_world (экран → мир, Vector3) —
## если задан и все углы рамки попадают в землю, юниты вне мирового прямоугольника под рамкой (+ запас)
## отсекаются без проекции на экран: рамка по 1000 юнитам стоит доли миллисекунды, а не десятки.
## Массивы ядра — в локальные один раз за вызов (CONTRACT §10.2 п. 9: у BattleCore чтение свойства копирует массив).
func box(rect: Rect2, shift: bool, to_screen: Callable, to_world := Callable()) -> int:
	rect = rect.abs()
	var bs := query.battle()
	var found := PackedInt32Array()
	if bs != null:
		var ux := bs.u_x
		var uz := bs.u_z
		var usq := bs.u_squad
		var life := bs.u_life
		var single := bs.sq_single
		var members := bs.sq_members
		var seen_sq := {}
		var cull := _ground_rect(rect, to_world)
		for u in _own_indices(bs):
			var x := ux[u]
			var z := uz[u]
			if cull.size.x > 0.0 and not cull.has_point(Vector2(x, z)):
				continue
			if not rect.has_point(_screen_at(x, z, to_screen)):
				continue
			var s := usq[u]
			if seen_sq.has(s):
				continue
			seen_sq[s] = true
			found.append_array(_squad_handles(u, s, single, members, life))
	if shift and _all_own(model.selected) and _units_only(model.selected):
		model.add(found)
	elif not found.is_empty() or not shift:
		model.set_selection(found)
	return found.size()


## Двойной щелчок: все свои того же рода в видимой области view
func same_type(h: int, view: Rect2, to_screen: Callable) -> int:
	var bs := query.battle()
	var u0 := query.unit_index(h)
	if bs == null or u0 < 0 or RtsInput.owner_of(query, h) != player:
		return 0
	var types := bs.u_type
	var ux := bs.u_x
	var uz := bs.u_z
	var t := types[u0]
	var found := PackedInt32Array()
	for u in _own_indices(bs):
		if types[u] == t and view.has_point(_screen_at(ux[u], uz[u], to_screen)):
			found.append(query.unit_handle(u))
	model.set_selection(found)
	return found.size()


## Описатель → что выделять: юнит отряда — все живые бойцы отряда; прочее — сам описатель
func expand(h: int) -> PackedInt32Array:
	if Ids.kind(h) != Ids.Kind.UNIT:
		return PackedInt32Array([h])
	var bs := query.battle()
	var u := query.unit_index(h)
	if bs == null or u < 0:
		return PackedInt32Array([h])
	return _squad_handles(u, bs.u_squad[u], bs.sq_single, bs.sq_members, bs.u_life)


## Живые бойцы отряда s юнита u (одиночка или пустой отряд — сам юнит); массивы ядра — от вызывающего
func _squad_handles(u: int, s: int, single: PackedInt32Array, members: Array[PackedInt32Array],
		life: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	if s >= 0 and single[s] != 1:
		for m in members[s]:
			if life[m] == BattleSim.Life.ALIVE:
				out.append(query.unit_handle(m))
	if out.is_empty():
		out.append(query.unit_handle(u))
	return out


## Индексы ядра живых своих юнитов: прямо по массивам BattleSim (u_owner, u_life) — без описателя на
## каждого; без ядра — через GameQuery.units_of
func _own_indices(bs: BattleSim) -> PackedInt32Array:
	var out := PackedInt32Array()
	if bs == null:
		for h in query.units_of(player):
			var u := query.unit_index(h)
			if u >= 0:
				out.append(u)
		return out
	var owner := bs.u_owner
	var life := bs.u_life
	for u in bs.n:
		if owner[u] == player and life[u] == BattleSim.Life.ALIVE:
			out.append(u)
	return out


## Мировой прямоугольник (x, z) под экранной рамкой с запасом CULL_M; пусто — угол мимо земли
func _ground_rect(rect: Rect2, to_world: Callable) -> Rect2:
	if not to_world.is_valid():
		return Rect2()
	var out := Rect2()
	for i in 4:
		var c := rect.position + rect.size * Vector2(i % 2, i / 2)
		var w: Vector3 = to_world.call(c)
		if w.x == INF:
			return Rect2()
		out = Rect2(w.x, w.z, 0, 0) if i == 0 else out.expand(Vector2(w.x, w.z))
	return out.grow(CULL_M)


func _screen_at(x: float, z: float, to_screen: Callable) -> Vector2:
	return to_screen.call(Vector3(x, Terrain.height_at(x, z) + 1.0, z))


func _all_own(hs: PackedInt32Array) -> bool:
	return RtsInput.owns_all(query, player, hs)


func _units_only(hs: PackedInt32Array) -> bool:
	for h in hs:
		if Ids.kind(h) != Ids.Kind.UNIT:
			return false
	return true
