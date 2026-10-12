class_name Ids
## Единые 32-битные описатели (handles) сущностей «Города» (ARCHITECTURE §6.1, CONTRACT §10).
##
##   биты 28..30 — вид (Kind), 16..27 — поколение (1..4095), 0..15 — слот в хранилище.
##   Живой описатель никогда не равен 0 (поколение 0 не выдаётся), NULL = 0 — «ничего».
##
## Проверка: владелец хранилища сравнивает store_gen[slot] == gen. Ядро (BattleSim) владеет
## юнитами и отрядами, ECON — зданиями, узлами ресурсов и стадами.
## Устаревший описатель в приказе → CMD_REJECTED с причиной STALE; интерфейс убирает такие
## из выделения при каждом обновлении.
##
## Только ведущий меняет этот файл.

enum Kind { NONE = 0, UNIT = 1, SQUAD = 2, BUILDING = 3, NODE = 4, HERD = 5 }

const NULL := 0


static func make(kind: int, slot: int, gen: int) -> int:   # gen 1..4095 (0 never used, so a live handle ≠ 0)
	return (kind << 28) | ((gen & 0xFFF) << 16) | (slot & 0xFFFF)


static func kind(h: int) -> int: return (h >> 28) & 0x7


static func slot(h: int) -> int: return h & 0xFFFF


static func gen(h: int) -> int: return (h >> 16) & 0xFFF


static func next_gen(g: int) -> int: return 1 if g >= 0xFFF else g + 1
