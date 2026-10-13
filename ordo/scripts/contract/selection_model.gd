class_name SelectionModel
extends RefCounted
## Выделение и группы (ARCHITECTURE §7.6): только хранение и сигнал. Поведение (щелчок, рамка,
## двойной щелчок, Ctrl+N) — UI, scripts/input/selection_impl.gd; рисует SelectionView (VIEW).
## Хранит описатели (Ids): юниты (отряд выделяется своими бойцами), здания, узлы, стада.
## Группы: индекс 0..8 — клавиши 1…9 (ordo_group_1 → 0).
##
## Только ведущий меняет этот файл.

signal changed(handles: PackedInt32Array)

var selected := PackedInt32Array()
var groups: Array[PackedInt32Array] = []          # 9


func _init() -> void:
	for i in 9:
		groups.append(PackedInt32Array())


func set_selection(hs: PackedInt32Array) -> void:
	selected = hs.duplicate()
	changed.emit(selected)


func add(hs: PackedInt32Array) -> void:
	var grew := false
	for h in hs:
		if not selected.has(h):
			selected.append(h)
			grew = true
	if grew:
		changed.emit(selected)


## Убрать недействительные и мёртвые описатели (из выделения и групп); сигнал — если выделение изменилось
func prune(q: GameQuery) -> void:
	var keep := _alive_only(q, selected)
	for i in groups.size():
		groups[i] = _alive_only(q, groups[i])
	if keep != selected:
		selected = keep
		changed.emit(selected)


## Запомнить выделение в группе i (0..8)
func set_group(i: int) -> void:
	groups[i] = selected.duplicate()


## Выделить группу i (0..8) и вернуть её
func recall_group(i: int) -> PackedInt32Array:
	set_selection(groups[i])
	return selected


static func _alive_only(q: GameQuery, hs: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for h in hs:
		if _alive(q, h):
			out.append(h)
	return out


static func _alive(q: GameQuery, h: int) -> bool:
	match Ids.kind(h):
		Ids.Kind.UNIT:
			var u := q.unit_index(h)
			if u < 0:
				return false
			var bs := q.battle()
			return bs == null or bs.u_life[u] == BattleSim.Life.ALIVE
		Ids.Kind.SQUAD:
			var bs := q.battle()
			if bs == null:
				return true
			var s := Ids.slot(h)
			return s < bs.squads and bs.sq_gen[s] == Ids.gen(h) and bs.sq_alive[s] > 0
		Ids.Kind.BUILDING:
			var bt := q.buildings()
			return bt != null and bt.valid(h) and bt.state[bt.slot(h)] != BuildingTable.State.RUIN
		Ids.Kind.NODE:
			var nt := q.nodes()
			return nt != null and nt.valid(h) and nt.amount_milli[nt.slot(h)] != 0
		Ids.Kind.HERD:
			var ht := q.herds()
			return ht != null and ht.valid(h)
	return false
