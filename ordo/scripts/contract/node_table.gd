class_name NodeTable
extends RefCounted
## Узлы ресурсов (ARCHITECTURE §6.3): деревья, залежи камня и золота, глиняные ямы.
## Пишет только ECON, читают все. Слот n — индекс; свободный слот — ntype −1.
## Описатель — Ids.make(NODE, n, gen[n]). Запас — милли (−1 — бесконечный).
## Дерево карты связано с WorldScatter через scatter_ref = kind << 16 | index (ScatterData).
##
## Только ведущий меняет этот файл.

var hw := 0
var gen := PackedInt32Array()
var ntype := PackedInt32Array()        # индекс Defs.n_ids, −1 — слот свободен
var res := PackedInt32Array()          # ресурс (Defs)
var amount_milli := PackedInt32Array() # осталось, милли; 0 — выработан; −1 — бесконечно
var workers_n := PackedInt32Array()
var workers_max := PackedInt32Array()
var owner_b := PackedInt32Array()      # здание-владелец (описатель; поле), 0 — узел карты
var scatter_ref := PackedInt32Array()  # дерево WorldScatter (kind << 16 | index), −1
var cell := PackedInt32Array()         # клетка навигации (NavApi.cell_of)
var x := PackedFloat32Array()
var z := PackedFloat32Array()


func handle(n: int) -> int:
	return Ids.make(Ids.Kind.NODE, n, gen[n])


func valid(h: int) -> bool:
	var n := Ids.slot(h)
	return Ids.kind(h) == Ids.Kind.NODE and n < hw and gen[n] == Ids.gen(h) and ntype[n] >= 0


func slot(h: int) -> int:
	return Ids.slot(h)


## Новый слот (ECON): наименьший свободный или новый; поля по умолчанию, ntype = p_ntype
func alloc(p_ntype: int) -> int:
	var n := ntype.find(-1)
	if n < 0:
		n = hw
		hw += 1
		for a: Variant in [gen, ntype, res, amount_milli, workers_n, workers_max, owner_b, scatter_ref, cell]:
			a.append(0)
		x.append(0.0)
		z.append(0.0)
	gen[n] = Ids.next_gen(gen[n])
	ntype[n] = p_ntype
	res[n] = 0; amount_milli[n] = 0; workers_n[n] = 0; workers_max[n] = 0; owner_b[n] = 0
	scatter_ref[n] = -1; cell[n] = 0; x[n] = 0.0; z[n] = 0.0
	return n


func release(n: int) -> void:
	ntype[n] = -1
