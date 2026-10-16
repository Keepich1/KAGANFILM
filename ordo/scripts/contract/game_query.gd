class_name GameQuery
extends RefCounted
## Окно чтения «Города» для VIEW, UI и ИИ (ARCHITECTURE §7.5). GAME делает GameQueryImpl;
## до I4 VIEW и UI работают на FakeCity (живой поддельный город). Этот класс — договор:
## методы пишут push_error и возвращают значения по умолчанию.
##
## Только чтение: массивы ядра и таблиц брать в локальные переменные в начале функции,
## никогда не писать в них и не хранить в полях. Подписи в словарях — по-русски (tr()).
##
## Словари ответов:
##   selection_info  {kind: "units" | "building" | "node" | "herd" | "none",
##                    cards: [{type, name, count, hp, morale, stamina, banner, squad}]}  (hp/morale/stamina 0..1)
##   building_panel  {handle, btype, name, hp, hp_max, state, progress, queue: [{utype, name, t}],
##                    trains: [{utype, name, cost, enabled, why}], recipe, herd: {heads, cap, grass}, water, gar}
##   build_menu      [{btype, name, cost: PackedInt32Array (милли), hotkey, enabled, why}]
##   orders_for      [{op: SimCmd.Op, label, key, enabled}]
##   minimap         {units: PackedVector3Array(x, z, team), buildings: PackedVector3Array(x, z, team),
##                    nodes: PackedVector3Array(x, z, res)}
## why — причина недоступности по-русски («Не хватает: дерево 40»), "" — доступно.
##
## Только ведущий меняет этот файл.

func tick() -> int:
	_todo("tick")
	return 0


func defs() -> Defs:
	_todo("defs")
	return null


func battle() -> BattleSim:                                   # kernel arrays: take into locals, never write, never store
	_todo("battle")
	return null


func players() -> PlayerTable:
	_todo("players")
	return null


func buildings() -> BuildingTable:
	_todo("buildings")
	return null


func nodes() -> NodeTable:
	_todo("nodes")
	return null


func herds() -> HerdTable:
	_todo("herds")
	return null


func events() -> SimEvents:
	_todo("events")
	return null


## Трава 16 м, байт на клетку (0..255)
func grass() -> PackedByteArray:
	_todo("grass")
	return PackedByteArray()


## Полив 8 м, байт на клетку (0..255)
func water() -> PackedByteArray:
	_todo("water")
	return PackedByteArray()


func field_dims() -> Vector4i:                               # gw, gh, ww, wh
	_todo("field_dims")
	return Vector4i.ZERO


func unit_handle(u: int) -> int:                             # индекс ядра → описатель
	_todo("unit_handle")
	return 0


func unit_index(h: int) -> int:                              # описатель → индекс ядра, −1 — недействителен
	_todo("unit_index")
	return -1


func pick(p: int, world: Vector2, r: float) -> int:           # unit, building, node or herd handle (own first)
	_todo("pick")
	return 0


func units_of(p: int) -> PackedInt32Array:                    # for box selection (UI projects positions itself)
	_todo("units_of")
	return PackedInt32Array()


func selection_info(hs: PackedInt32Array) -> Dictionary:
	_todo("selection_info")
	return {"kind": "none", "cards": []}


func building_panel(b_h: int) -> Dictionary:
	_todo("building_panel")
	return {}


func build_menu(p: int, tab: StringName) -> Array[Dictionary]:
	_todo("build_menu")
	return []


func orders_for(p: int, hs: PackedInt32Array) -> Array[Dictionary]:
	_todo("orders_for")
	return []


func check_place(p: int, btype: int, center: Vector2, rot_q: int) -> int:
	_todo("check_place")
	return NavApi.Why.NOT_ALLOWED


func place_cells(p: int, btype: int, center: Vector2, rot_q: int) -> PackedByteArray:
	_todo("place_cells")
	return PackedByteArray()


func plan_wall(p: int, wtype: int, pts: PackedVector2Array) -> Dictionary:
	_todo("plan_wall")
	return {}


func snap(btype: int, p: Vector2, rot_q: int) -> Vector2:
	_todo("snap")
	return p


func idle_workers(p: int) -> PackedInt32Array:
	_todo("idle_workers")
	return PackedInt32Array()


func raid_eta_ticks(p: int) -> int:                           # −1 none
	_todo("raid_eta_ticks")
	return -1


func minimap(p: int) -> Dictionary:
	_todo("minimap")
	return {}


func _todo(what: String) -> void:
	push_error("GameQuery.%s: не реализовано (%s)" % [what, get_script().resource_path])
