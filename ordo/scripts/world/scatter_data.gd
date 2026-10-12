class_name ScatterData
extends RefCounted
## Деревья карты без графики (симуляция, тесты, MapSetup): те же записи и тот же порядок,
## что у WorldScatter (assets/world/scatter.json, делает tools/gen_world.py).
##
##   ScatterData.trees() -> Array    [[kind, index, x, z], …] в порядке файла: тополь, ива, арча, карагач
##   ScatterData.ref(kind, index)    scatter_ref = kind << 16 | index (NodeTable.scatter_ref, TREE_FELLED)
##
## kind — индекс в KINDS, index — номер дерева в списке своего вида в файле.
## Читается один раз через FileAccess (работает без монитора и в экспорте). Ведущий (M0).

const KINDS := ["poplar", "willow", "juniper", "elm"]
const PATH := "res://assets/world/scatter.json"

static var _trees: Array = []
static var _loaded := false


static func trees() -> Array:
	if not _loaded:
		_loaded = true
		_trees = _read()
	return _trees


static func ref(kind: int, index: int) -> int:
	return (kind << 16) | index


static func ref_kind(scatter_ref: int) -> int:
	return scatter_ref >> 16


static func ref_index(scatter_ref: int) -> int:
	return scatter_ref & 0xFFFF


static func _read() -> Array:
	var out: Array = []
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_warning("ScatterData: нет %s" % PATH)
		return out
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not data is Dictionary:
		push_warning("ScatterData: %s не читается" % PATH)
		return out
	for k in KINDS.size():
		var list: Array = data.get(KINDS[k], [])
		for i in list.size():
			var it: Array = list[i]
			out.append([k, i, float(it[0]), float(it[2])])
	return out
