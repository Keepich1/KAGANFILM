class_name HerdTable
extends RefCounted
## Стада (ARCHITECTURE §6.3): овцы и кони — не тела ядра, а счёт голов у загона.
## Пишет только ECON, читают все (HerdView рисует min(голов, 80) животных стаей).
## Слот h; свободный слот — state FREE. Описатель — Ids.make(HERD, h, gen[h]). Головы — милли.
##   PEN      пасётся у загона pen_b в радиусе graze_r вокруг (x, z)
##   DRIVEN   в пути: перегон (HERD_MOVE) или возвращается к загону; captor_u = 0
##   CAPTURED угнано: идёт за налётчиком captor_u (HERD_STOLEN); capture_t — тактов в угоне
## Переходы решает ECON (herds.gd).
##
## Только ведущий меняет этот файл.

enum State { FREE, PEN, DRIVEN, CAPTURED }

var hw := 0
var gen := PackedInt32Array()
var htype := PackedInt32Array()        # индекс Defs.h_ids
var owner := PackedInt32Array()        # игрок
var pen_b := PackedInt32Array()        # загон (описатель здания), 0 — нет
var heads_milli := PackedInt32Array()  # голов × 1000 (прирост копится дробно)
var state := PackedInt32Array()        # State
var captor_u := PackedInt32Array()     # налётчик (описатель юнита), 0
var capture_t := PackedInt32Array()    # тактов (угон или отсчёт угрозы)
var x := PackedFloat32Array()
var z := PackedFloat32Array()
var graze_r := PackedFloat32Array()


func handle(h: int) -> int:
	return Ids.make(Ids.Kind.HERD, h, gen[h])


func valid(h: int) -> bool:
	var s := Ids.slot(h)
	return Ids.kind(h) == Ids.Kind.HERD and s < hw and gen[s] == Ids.gen(h) and state[s] != State.FREE


func slot(h: int) -> int:
	return Ids.slot(h)


## Новый слот (ECON): наименьший свободный или новый; поля по умолчанию
func alloc(p_state := State.PEN) -> int:
	var h := state.find(State.FREE)
	if h < 0:
		h = hw
		hw += 1
		for a: Variant in [gen, htype, owner, pen_b, heads_milli, state, captor_u, capture_t]:
			a.append(0)
		for a: Variant in [x, z, graze_r]:
			a.append(0.0)
	gen[h] = Ids.next_gen(gen[h])
	htype[h] = -1; owner[h] = -1; pen_b[h] = 0; heads_milli[h] = 0; state[h] = p_state
	captor_u[h] = 0; capture_t[h] = 0; x[h] = 0.0; z[h] = 0.0; graze_r[h] = 0.0
	return h


func release(h: int) -> void:
	state[h] = State.FREE


## Голов (целых)
func heads(h: int) -> int:
	return heads_milli[h] / 1000
