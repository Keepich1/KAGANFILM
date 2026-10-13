class_name PlayerTable
extends RefCounted
## Игроки «Города» (ARCHITECTURE §6.3): общая таблица-«структура массивов».
## Пишет только ECON (EconomySim); остальные читают. Игрок p — индекс 0..count−1.
## Ресурсы — в милли-единицах (1 еда = 1000), R = Defs.R; индекс [p * R + r].
## Читатели берут массивы в локальные переменные в начале функции и не хранят их в полях.
##
## Только ведущий меняет этот файл.

enum Ctrl { HUMAN, AI, NONE }
enum Stat { ATK, SPEED, STAM_REGEN, MORALE_REGEN, RANGE, GATHER, BUILD, UPKEEP, COUNT }

var count := 0
var R := 0                           # ресурсов на игрока (Defs.R), ставит add()
var team := PackedInt32Array()       # команда (BattleSim: сторона)
var faction := PackedInt32Array()    # индекс Defs.f_ids
var ctrl := PackedInt32Array()       # Ctrl
var alive := PackedInt32Array()      # 1 — в игре, 0 — побеждён
var hq_b := PackedInt32Array()       # описатель ставки (building handle), 0 — нет (свёрнута в арбу)
var pop_used := PackedInt32Array()
var pop_reserved := PackedInt32Array()   # заняли головы очередей найма
var pop_cap := PackedInt32Array()
var famine := PackedInt32Array()     # 1 — голод
var season := PackedInt32Array()     # индекс ModifierDefs.SEASONS (−1 — без сезонов)
var res := PackedInt64Array()        # [p * R + r] milli
var rate_acc := PackedInt64Array()   # [p * R + r] remainders of per-minute flows
var income := PackedInt32Array()     # [p * R + r] milli per minute, for the UI (updated at 1 Hz)
var stat := PackedFloat32Array()     # [p * Stat.COUNT + k] compiled modifiers (1.0 neutral)


## Новый игрок (ECON, MapSetup): все массивы растут вместе. r_count — Defs.R.
func add(p_team: int, p_faction: int, p_ctrl: int, r_count: int) -> int:
	if count == 0:
		R = r_count
	assert(r_count == R, "PlayerTable: другое число ресурсов")
	var p := count
	count += 1
	team.append(p_team)
	faction.append(p_faction)
	ctrl.append(p_ctrl)
	alive.append(1)
	hq_b.append(0)
	pop_used.append(0)
	pop_reserved.append(0)
	pop_cap.append(0)
	famine.append(0)
	season.append(-1)
	for r in R:
		res.append(0)
		rate_acc.append(0)
		income.append(0)
	for k in Stat.COUNT:
		stat.append(1.0)
	return p


## Запас ресурса r игрока p, милли
func res_of(p: int, r: int) -> int:
	return res[p * R + r]
