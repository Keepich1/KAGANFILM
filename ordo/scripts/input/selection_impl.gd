class_name SelectionImpl
extends RefCounted
## Поведение выделения (ARCHITECTURE §14, ТЗ §10) поверх SelectionModel (хранение — договор):
##   • щелчок — свой юнит (отряд выделяется всеми бойцами), здание, узел, стадо или чужой юнит (посмотреть);
##     Shift — добавить/убрать;
##   • рамка — свои юниты, чьи точки на экране внутри (отряды целиком); Shift — добавить;
##   • двойной щелчок — все свои того же рода, видимые на экране.
## Экранные координаты даёт RtsInput (to_screen), чтобы тесты обходились без камеры.

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


## Рамка (экранный прямоугольник): свои юниты внутри, отряды целиком
func box(rect: Rect2, shift: bool, to_screen: Callable) -> int:
	rect = rect.abs()
	var bs := query.battle()
	var found := PackedInt32Array()
	var seen_sq := {}
	for h in query.units_of(player):
		var u := query.unit_index(h)
		if u < 0:
			continue
		var p := _screen_of(bs, u, to_screen)
		if not rect.has_point(p):
			continue
		if bs != null:
			var s := bs.u_squad[u]
			if seen_sq.has(s):
				continue
			seen_sq[s] = true
		for x in expand(h):
			found.append(x)
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
	var t := bs.u_type[u0]
	var found := PackedInt32Array()
	for x in query.units_of(player):
		var u := query.unit_index(x)
		if u >= 0 and bs.u_type[u] == t and view.has_point(_screen_of(bs, u, to_screen)):
			found.append(x)
	model.set_selection(found)
	return found.size()


## Описатель → что выделять: юнит отряда — все живые бойцы отряда; прочее — сам описатель
func expand(h: int) -> PackedInt32Array:
	var out := PackedInt32Array([h])
	if Ids.kind(h) != Ids.Kind.UNIT:
		return out
	var bs := query.battle()
	var u := query.unit_index(h)
	if bs == null or u < 0:
		return out
	var s := bs.u_squad[u]
	if s < 0 or bs.sq_single[s] == 1:
		return out
	out.clear()
	for m in bs.sq_members[s]:
		if bs.u_life[m] == BattleSim.Life.ALIVE:
			out.append(query.unit_handle(m))
	if out.is_empty():
		out.append(h)
	return out


func _screen_of(bs: BattleSim, u: int, to_screen: Callable) -> Vector2:
	var x := bs.u_x[u] if bs else 0.0
	var z := bs.u_z[u] if bs else 0.0
	return to_screen.call(Vector3(x, Terrain.height_at(x, z) + 1.0, z))


func _all_own(hs: PackedInt32Array) -> bool:
	return RtsInput.owns_all(query, player, hs)


func _units_only(hs: PackedInt32Array) -> bool:
	for h in hs:
		if Ids.kind(h) != Ids.Kind.UNIT:
			return false
	return true
