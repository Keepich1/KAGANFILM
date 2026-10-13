class_name BuildingTable
extends RefCounted
## Здания, стройки, звенья стен и арыков (ARCHITECTURE §6.3). Пишет только ECON, читают все.
## Слот b = индекс в массивах = индекс структуры в ядре (BattleSim.st_*), без таблицы соответствия.
## Слоты 0..hw−1; свободный слот — state FREE. Описатель — Ids.make(BUILDING, b, gen[b]).
## HP — в санти-единицах (hp_c = HP × 100), прогресс стройки 0..1000, таймеры — в тактах.
## Читатели берут массивы в локальные переменные в начале функции и не хранят их в полях.
##
## Только ведущий меняет этот файл.

enum State { FREE, SITE, ACTIVE, PACKED, RUIN }
const QMAX := 5

var hw := 0                                                # high-water mark (slots 0..hw-1)
var gen := PackedInt32Array()                              # поколение слота 1..4095
var btype := PackedInt32Array()                            # индекс Defs.b_ids
var owner := PackedInt32Array()                            # игрок
var team := PackedInt32Array()
var state := PackedInt32Array()                            # State
var rot_q := PackedInt32Array()                            # четверть оборота 0..3 (здания)
var chain := PackedInt32Array()                            # id цепочки стены/арыка, 0 — нет
var flags := PackedInt32Array()                            # Defs.BF_* типа (копия при создании)
var x := PackedFloat32Array()                              # center; rot radians (walls: any angle; buildings: rot_q · PI/2)
var z := PackedFloat32Array()
var rot := PackedFloat32Array()
var ax := PackedFloat32Array()                             # wall/aryk links: endpoints
var az := PackedFloat32Array()
var bx := PackedFloat32Array()
var bz := PackedFloat32Array()
var hp_c := PackedInt32Array()                             # centi-HP
var hp_max_c := PackedInt32Array()
var progress := PackedInt32Array()                         # стройка 0..1000 (ACTIVE — 1000)
var c0 := PackedInt32Array()                               # footprint rect in nav cells (links: bounding rect)
var r0 := PackedInt32Array()
var cw := PackedInt32Array()
var ch := PackedInt32Array()
var q := PackedInt32Array()                                # [b * QMAX + i] unit def index, −1 empty
var q_n := PackedInt32Array()                              # queue length
var q_t := PackedInt32Array()                              # ticks done on head
var rally_x := PackedFloat32Array()
var rally_z := PackedFloat32Array()
var rally_h := PackedInt32Array()                          # цель сбора (описатель), 0 — точка
var recipe := PackedInt32Array()                           # индекс Defs.rc_ids, −1 — нет
var recipe_t := PackedInt32Array()                         # тактов сделано на текущей партии
var workers_n := PackedInt32Array()                        # работников на стройке/в поле/в мастерской
var gar_n := PackedInt32Array()                            # гарнизон (этап 2)
var store_mask := PackedInt32Array()                       # какие ресурсы принимает (1 << r)
var hit_tick := PackedInt32Array()                         # такт последнего попадания, −1


func handle(b: int) -> int:
	return Ids.make(Ids.Kind.BUILDING, b, gen[b])


func valid(h: int) -> bool:
	var b := Ids.slot(h)
	return Ids.kind(h) == Ids.Kind.BUILDING and b < hw and gen[b] == Ids.gen(h) and state[b] != State.FREE


func slot(h: int) -> int:
	return Ids.slot(h)


## Новый слот (ECON): наименьший свободный или новый в конце; поколение растёт при повторе.
## Поля — по умолчанию, state = p_state. Возвращает слот.
func alloc(p_state := State.SITE) -> int:
	var b := state.find(State.FREE)
	if b < 0:
		b = hw
		hw += 1
		gen.append(0)
		for arr: Array in [_ints(), _floats()]:
			for a: Variant in arr:
				a.append(0)
		for i in QMAX:
			q.append(-1)
	gen[b] = Ids.next_gen(gen[b])
	btype[b] = -1; owner[b] = -1; team[b] = -1; state[b] = p_state; rot_q[b] = 0; chain[b] = 0; flags[b] = 0
	x[b] = 0.0; z[b] = 0.0; rot[b] = 0.0; ax[b] = 0.0; az[b] = 0.0; bx[b] = 0.0; bz[b] = 0.0
	hp_c[b] = 0; hp_max_c[b] = 0; progress[b] = 0; c0[b] = 0; r0[b] = 0; cw[b] = 0; ch[b] = 0
	q_n[b] = 0; q_t[b] = 0; rally_x[b] = 0.0; rally_z[b] = 0.0; rally_h[b] = 0
	recipe[b] = -1; recipe_t[b] = 0; workers_n[b] = 0; gar_n[b] = 0; store_mask[b] = 0; hit_tick[b] = -1
	for i in QMAX:
		q[b * QMAX + i] = -1
	return b


## Освободить слот (снесено, свёрнуто без возврата): описатель становится недействительным
func release(b: int) -> void:
	state[b] = State.FREE


## Сколько слотов в состоянии s
func count_state(s: int) -> int:
	return state.count(s)


func _ints() -> Array:
	return [btype, owner, team, state, rot_q, chain, flags, hp_c, hp_max_c, progress, c0, r0, cw, ch,
		q_n, q_t, rally_h, recipe, recipe_t, workers_n, gar_n, store_mask, hit_tick]


func _floats() -> Array:
	return [x, z, rot, ax, az, bx, bz, rally_x, rally_z]
