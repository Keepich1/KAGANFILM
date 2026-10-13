class_name PlacementMode
extends RefCounted
## Режим постройки (ARCHITECTURE §10, §14): призрак за курсором (GameQuery.snap + place_cells), колесо или R —
## поворот на 90°, ЛКМ — поставить (SimCmd.build: выделенные работники, иначе ближайший свободный — пустой
## список), Shift — ставить ещё. Стены и арыки (kind WALL / LINK) — инструмент стены: ЛКМ — начало, каждое
## следующее ЛКМ — точка и продолжение от конца, ПКМ или Esc — закончить (SimCmd.build_wall).
## Призрак — объект с API GhostView: show_building(btype, center, rot_q, cells), show_wall(plan), hide().

var query: GameQuery
var player := 0
var ghost: Object

var btype := -1
var rot_q := 0
var is_wall := false
var pts := PackedVector2Array()
var hover := Vector2.INF
## Последняя проверка места (NavApi.Why) — для курсора «нельзя»
var why := NavApi.Why.OK


func _init(q: GameQuery = null, p := 0) -> void:
	query = q
	player = p


func active() -> bool:
	return btype >= 0


func begin(p_btype: int) -> void:
	btype = p_btype
	rot_q = 0
	pts.clear()
	var k := query.defs().b_kind[btype]
	is_wall = k == Defs.BKind.WALL or k == Defs.BKind.LINK
	if hover != Vector2.INF:
		move(hover)


func cancel() -> void:
	btype = -1
	pts.clear()
	is_wall = false
	if ghost:
		ghost.call("hide")


func rotate(dir: int) -> void:
	rot_q = posmod(rot_q + dir, 4)
	if hover != Vector2.INF:
		move(hover)


## Курсор над точкой мира: обновить призрак
func move(world: Vector2) -> void:
	hover = world
	if not active():
		return
	if is_wall:
		var line := pts.duplicate()
		line.append(world)
		if line.size() >= 2:
			var plan := query.plan_wall(player, btype, line)
			why = NavApi.Why.OK
			for w in plan.get("why", PackedByteArray()):
				if w != NavApi.Why.OK:
					why = w
					break
			if ghost:
				ghost.call("show_wall", plan)
		else:
			why = NavApi.Why.OK
			var c := query.snap(btype, world, 0)
			if ghost:
				ghost.call("show_building", btype, c, 0, query.place_cells(player, btype, c, 0))
		return
	var c := query.snap(btype, world, rot_q)
	why = query.check_place(player, btype, c, rot_q)
	if ghost:
		ghost.call("show_building", btype, c, rot_q, query.place_cells(player, btype, c, rot_q))


## ЛКМ: здание — приказ BUILD (пусто, если место негодно); стена — точка в цепь (приказа ещё нет)
func click(world: Vector2, workers: PackedInt32Array, shift: bool) -> PackedInt32Array:
	if not active():
		return PackedInt32Array()
	if is_wall:
		pts.append(world)
		move(world)
		return PackedInt32Array()
	var c := query.snap(btype, world, rot_q)
	why = query.check_place(player, btype, c, rot_q)
	if why != NavApi.Why.OK:
		return PackedInt32Array()
	var cmd := SimCmd.build(workers, btype, c, rot_q)
	if not shift:
		cancel()
	return cmd


## ПКМ / Esc в инструменте стены: приказ BUILD_WALL по точкам (пусто, если точек меньше двух)
func finish(workers: PackedInt32Array) -> PackedInt32Array:
	var cmd := PackedInt32Array()
	if is_wall and pts.size() >= 2:
		cmd = SimCmd.build_wall(workers, btype, pts)
	cancel()
	return cmd
