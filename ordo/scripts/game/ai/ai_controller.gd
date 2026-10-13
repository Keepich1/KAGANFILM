class_name AiController
extends RefCounted
## ИИ игрока «Города» (ARCHITECTURE §5.1, §7.4, §12): думает внутри симуляции раз в period тактов
## (со сдвигом phase, чтобы разные ИИ думали в разные такты), читает только GameQuery и пишет только
## приказы SimCmd в out (исполнятся на такте + input_delay). Своё состояние — только здесь.
## Генератор — BattleRng с зерном seed · 0x9E37 + 100 + player (CONTRACT §10.2).
##
## Выход, который не приказ (предупреждение о набеге, уход выживших с края карты), ИИ кладёт в notes:
##   [NOTE_EVENT, kind, player, a, b, c, pos]  — GameSim пишет событие в SimEvents;
##   [NOTE_REMOVE, handles]                    — GameSim убирает юнитов из мира (CombatPort.remove).

const NOTE_EVENT := 0
const NOTE_REMOVE := 1

var player := -1
var period := 30
var phase := 0
var rng: BattleRng
var params := {}
var notes: Array = []


func setup(p_player: int, p_params: Dictionary, p_seed: int) -> void:
	player = p_player
	params = p_params
	period = maxi(1, int(params.get("period", 30)))
	phase = int(params.get("phase", (p_player * 7) % period)) % period
	rng = BattleRng.new(p_seed * 0x9E37 + 100 + p_player)


func think(tick: int, q: GameQuery, out: Array[PackedInt32Array]) -> void:
	pass


func checksum() -> int:
	return (rng.state * 31 + player) & 0x7FFFFFFF if rng else player


## Приказ от имени своего игрока
func emit(out: Array[PackedInt32Array], cmd: PackedInt32Array) -> void:
	cmd[SimCmd.H_PLAYER] = player
	out.append(cmd)


func note_event(kind: int, to_player: int, a := 0, b := 0, c := 0, pos := Vector2.ZERO) -> void:
	notes.append([NOTE_EVENT, kind, to_player, a, b, c, pos])


func note_remove(hs: PackedInt32Array) -> void:
	if not hs.is_empty():
		notes.append([NOTE_REMOVE, hs.duplicate()])


# ---------------------------------------------------------------- общие помощники (целые и квадраты расстояний)

## Смешать число в контрольную сумму
static func mix(h: int, v: int) -> int:
	return (h * 31 + (v & 0x7FFFFFFF)) & 0x7FFFFFFF


## Курс по сторонам света (без тригонометрии): +Z = 0, +X = PI/2, −Z = PI, −X = −PI/2
static func cardinal(d: Vector2) -> float:
	if absf(d.x) >= absf(d.y):
		return PI * 0.5 if d.x >= 0.0 else -PI * 0.5
	return 0.0 if d.y >= 0.0 else PI


## Первый живой игрок другой команды (−1 — нет)
static func enemy_of(q: GameQuery, p: int) -> int:
	var P := q.players()
	var g := q as GameQueryImpl
	for e in P.count:
		if P.team[e] != P.team[p] and P.alive[e] == 1 and P.ctrl[e] != PlayerTable.Ctrl.NONE \
				and (g == null or not g.is_defeated(e)):
			return e
	return -1


## Центр ставки игрока (или Vector2.INF)
static func hq_pos(q: GameQuery, p: int) -> Vector2:
	var P := q.players()
	var B := q.buildings()
	var h := P.hq_b[p]
	if h == Ids.NULL or not B.valid(h):
		return Vector2.INF
	var b := B.slot(h)
	return Vector2(B.x[b], B.z[b])
