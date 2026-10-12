class_name SimEvents
extends RefCounted
## События симуляции «Города» (ARCHITECTURE §7.7, CONTRACT §10): кольцевой буфер с курсорами.
## Только выход: события не входят в контрольную сумму и не сохраняются. Пишут ECON и GAME
## (ядро боя — нет: у него свои буферы ev_* и сигналы для эффектов). Читают интерфейс, CityFx, тесты.
##
## Читатель держит свой курсор (номер следующего события) и не теряет события, даже если
## драйвер сделал несколько тактов за кадр:
##   var r := events.range_since(_cursor)
##   for seq in range(r.x, r.y):
##       var i := events.at(seq)
##       match events.e_kind[i]: …
##   _cursor = r.y
## Если читатель отстал больше чем на CAP событий, самые старые пропадают (r.x > _cursor).
##
## Полезная нагрузка (player — чей это игрок, −1 — общее; a/b/c — целые; pos — место (м)):
##   UNIT_SPAWNED       a unit_h, b building_h (откуда, 0), c utype (Defs)
##   UNIT_DIED          a unit_h, b killer unit_h (0), c utype
##   SQUAD_FORMED       a squad_h, b officer unit_h, c число бойцов
##   SQUAD_DISBANDED    a squad_h, c число бойцов
##   SITE_PLACED        a building_h, b btype, c chain (0 — не стена)
##   BUILDING_DONE      a building_h, b btype
##   BUILDING_HIT       a building_h, b урон (санти-HP), c attacker unit_h
##   BUILDING_DESTROYED a building_h, b btype, c attacker player (−1)
##   GATE_BREACHED      a building_h, b btype, c attacker team
##   PACKED             a building_h, b arba unit_h, c btype
##   UNPACKED           a building_h, b arba unit_h, c btype
##   NODE_DEPLETED      a node_h, b ntype, c scatter_ref (−1)
##   TREE_FELLED        a node_h, b scatter_ref (kind << 16 | index), c ntype
##   RES_DELIVERED      a ресурс (Defs), b милли, c building_h
##   TRAINED            a unit_h, b building_h, c utype
##   QUEUE_CHANGED      a building_h, b длина очереди
##   POP_CAPPED         a building_h, b pop_used, c pop_cap
##   NOT_ENOUGH         a ресурс, b нехватка (милли), c op
##   WORKER_IDLE        a unit_h
##   FAMINE             a 1 — начался, 0 — кончился
##   PASTURE_LOW        a herd_h, b трава 0..1000
##   HERD_STOLEN        a herd_h (угнанное стадо), b captor unit_h, c голов
##   HERD_RETURNED      a herd_h, b pen building_h, c голов
##   LOOT               a ресурс, b милли, c источник (unit_h или building_h)
##   SEASON             a сезон (ModifierDefs.SEASONS по порядку), b тактов до смены
##   IRRIGATION_CHANGED a building_h (запруда/арык), b клеток полива
##   RAID_WARNING       a ETA в тактах, b игрок-налётчик, c номер волны
##   RAID_STARTED       a игрок-налётчик, b размер волны, c номер волны
##   RAID_ENDED         a игрок-налётчик, b выжило, c номер волны
##   CMD_REJECTED       a op, b причина (EconApi.Err или 100 + NavApi.Why), c seq приказа
##   PLAYER_DEFEATED    a причина (0 ставка, 1 арба с ордо), b team
##   VICTORY            a team
##
## Только ведущий меняет этот файл.

enum Ev { NONE,
	UNIT_SPAWNED, UNIT_DIED, SQUAD_FORMED, SQUAD_DISBANDED,
	SITE_PLACED, BUILDING_DONE, BUILDING_HIT, BUILDING_DESTROYED, GATE_BREACHED, PACKED, UNPACKED,
	NODE_DEPLETED, TREE_FELLED, RES_DELIVERED, TRAINED, QUEUE_CHANGED, POP_CAPPED, NOT_ENOUGH, WORKER_IDLE,
	FAMINE, PASTURE_LOW, HERD_STOLEN, HERD_RETURNED, LOOT, SEASON, IRRIGATION_CHANGED,
	RAID_WARNING, RAID_STARTED, RAID_ENDED, CMD_REJECTED, PLAYER_DEFEATED, VICTORY }

const CAP := 8192                                 # степень двойки

var tick := 0                                     # такт, который ставится событиям (GameSim.step)
var head := 0                                     # total pushed, monotonic
var e_tick := PackedInt32Array()
var e_kind := PackedInt32Array()
var e_player := PackedInt32Array()
var e_a := PackedInt32Array()
var e_b := PackedInt32Array()
var e_c := PackedInt32Array()
var e_x := PackedFloat32Array()
var e_z := PackedFloat32Array()


func _init() -> void:
	e_tick.resize(CAP)
	e_kind.resize(CAP)
	e_player.resize(CAP)
	e_a.resize(CAP)
	e_b.resize(CAP)
	e_c.resize(CAP)
	e_x.resize(CAP)
	e_z.resize(CAP)


func push(kind: int, player: int, a := 0, b := 0, c := 0, pos := Vector2.ZERO) -> void:
	var i := head & (CAP - 1)
	e_tick[i] = tick
	e_kind[i] = kind
	e_player[i] = player
	e_a[i] = a
	e_b[i] = b
	e_c[i] = c
	e_x[i] = pos.x
	e_z[i] = pos.y
	head += 1


## [from, to) — номера событий после курсора, ещё лежащие в кольце
func range_since(cursor: int) -> Vector2i:
	return Vector2i(clampi(cursor, maxi(head - CAP, 0), head), head)


## Индекс в массивах e_* для номера события
func at(seq: int) -> int:
	return seq & (CAP - 1)


## Имя события (журналы, тесты)
static func name_of(kind: int) -> String:
	var keys := Ev.keys()
	return keys[kind] if kind >= 0 and kind < keys.size() else "?"
