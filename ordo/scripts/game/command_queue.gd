class_name CommandQueue
extends RefCounted
## Очередь приказов «Города» (ARCHITECTURE §5.1, §7.4, §8; CONTRACT §10.4).
## push ставит в приказ игрока, такт исполнения (текущий + input_delay) и порядковый номер;
## take(tick) отдаёт приказы такта в порядке (такт, игрок, номер) и пишет их в журнал.
##
## Номера: у приказов извне (интерфейс, сценарий теста, сеть) — 0, 1, 2…; у приказов ИИ — с AI_SEQ.
## Так повтор (журнал внешних приказов + тот же ИИ, который снова сам думает) даёт те же номера и
## тот же порядок, даже если извне приказывали игроку-ИИ.

const AI_SEQ := 0x1000000
const MAX_PLAYERS := 64

var input_delay := 1
## Все исполненные приказы по порядку (копии; H_PLAYER, H_TICK, H_SEQ проставлены)
var log: Array[PackedInt32Array] = []

var _pending: Array[PackedInt32Array] = []
var _seq := PackedInt32Array()          # [игрок * 2 + (1 — ИИ)] следующий номер


## Приказ игрока player, отданный на такте tick_now (исполнится на tick_now + input_delay)
func push(player: int, tick_now: int, cmd: PackedInt32Array, from_ai := false) -> void:
	var c := cmd.duplicate()
	if c.size() < SimCmd.H_IDS:
		c.resize(SimCmd.H_IDS)          # испорченный приказ: Orders отклонит по форме
	c[SimCmd.H_PLAYER] = player
	c[SimCmd.H_TICK] = tick_now + input_delay
	c[SimCmd.H_SEQ] = _next_seq(player, from_ai)
	_pending.append(c)


## Приказы, уже с игроком, тактом и номером (повтор): встают в очередь как есть
func preload_cmds(cmds: Array[PackedInt32Array]) -> void:
	for c in cmds:
		if c.size() >= SimCmd.H_IDS:
			_pending.append(c.duplicate())


## Приказы такта tick (и опоздавшие), по порядку (такт, игрок, номер); попадают в журнал
func take(tick: int) -> Array[PackedInt32Array]:
	var due: Array[PackedInt32Array] = []
	if _pending.is_empty():
		return due
	var keep: Array[PackedInt32Array] = []
	for c in _pending:
		if c[SimCmd.H_TICK] <= tick:
			due.append(c)
		else:
			keep.append(c)
	_pending = keep
	if due.size() > 1:
		due.sort_custom(_before)
	log.append_array(due)
	return due


## Журнал приказов извне (без приказов ИИ) — для повтора
func external_log() -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for c in log:
		if c[SimCmd.H_SEQ] < AI_SEQ:
			out.append(c)
	return out


## Приказов ещё в очереди (в контрольную сумму не входит: в повторе внешние приказы лежат заранее)
func pending_count() -> int:
	return _pending.size()


func _next_seq(player: int, from_ai: bool) -> int:
	if player < 0 or player >= MAX_PLAYERS:
		return AI_SEQ - 1 if not from_ai else AI_SEQ * 2 - 1
	var k := player * 2 + (1 if from_ai else 0)
	if _seq.size() <= k:
		_seq.resize(k + 1)
	var s := _seq[k]
	_seq[k] = s + 1
	return s + (AI_SEQ if from_ai else 0)


static func _before(a: PackedInt32Array, b: PackedInt32Array) -> bool:
	if a[SimCmd.H_TICK] != b[SimCmd.H_TICK]:
		return a[SimCmd.H_TICK] < b[SimCmd.H_TICK]
	if a[SimCmd.H_PLAYER] != b[SimCmd.H_PLAYER]:
		return a[SimCmd.H_PLAYER] < b[SimCmd.H_PLAYER]
	return a[SimCmd.H_SEQ] < b[SimCmd.H_SEQ]
