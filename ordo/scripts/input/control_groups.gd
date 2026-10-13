class_name ControlGroups
extends RefCounted
## Группы Ctrl+1…9 (ТЗ §10): Ctrl+N — запомнить выделение, N — вызвать, двойное N — ещё и камеру туда,
## Shift+N — добавить группу к выделению. Хранение — SelectionModel.groups (договор).

const DOUBLE_S := 0.4

var model: SelectionModel
var _last_i := -1
var _last_t := -10.0


func _init(m: SelectionModel = null) -> void:
	model = m


func store(i: int) -> void:
	model.set_group(i)


## Вызвать группу; true — повторное нажатие (центрировать камеру)
func recall(i: int, now: float) -> bool:
	var again := i == _last_i and now - _last_t <= DOUBLE_S
	_last_i = i
	_last_t = now
	if model.groups[i].is_empty():
		return false
	model.recall_group(i)
	return again


func add(i: int) -> void:
	model.add(model.groups[i])
