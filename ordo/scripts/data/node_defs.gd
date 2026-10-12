class_name NodeDefs
## Узлы ресурсов карты (ТЗ 5.1, 8, 11.2; docs/ECONOMY.md §1.1): деревья и жилы.
## Схема — ведущий (M0), значения — ECON. Порядок записей = индекс Defs (новые — в конец).
##
## Поля: name; res — ресурс; amount — запас (−1 — бесконечный; карта может задать свой);
##   workers_max — мест у узла (кольцо из 8 мест у жилы, ARCHITECTURE §11); work_aux — вид работы
##   (AnimSpec.WORK_*); blocks_cells — сколько клеток 4 м перекрывает ядро (0 — не мешает ходить;
##   жила — 2×2); scatter — вид дерева WorldScatter (ScatterData.KINDS), "" — не дерево;
##   model — модель (деревья — из WorldScatter; жилы — 3 стадии выработки, ARCHITECTURE §13); enabled.

const NODES := {
	"tree_poplar": {"name": "Тополь", "res": "wood", "amount": 100, "workers_max": 2, "work_aux": 0.0,
		"blocks_cells": 0, "scatter": "poplar", "model": ""},
	"tree_willow": {"name": "Ива", "res": "wood", "amount": 100, "workers_max": 2, "work_aux": 0.0,
		"blocks_cells": 0, "scatter": "willow", "model": ""},
	"tree_juniper": {"name": "Арча", "res": "wood", "amount": 100, "workers_max": 2, "work_aux": 0.0,
		"blocks_cells": 0, "scatter": "juniper", "model": ""},
	"tree_elm": {"name": "Карагач", "res": "wood", "amount": 100, "workers_max": 2, "work_aux": 0.0,
		"blocks_cells": 0, "scatter": "elm", "model": ""},
	"stone": {"name": "Каменная жила", "res": "stone", "amount": 4000, "workers_max": 8, "work_aux": 0.25,
		"blocks_cells": 2, "scatter": "", "model": "stone_outcrop"},
	"gold": {"name": "Золотая жила", "res": "gold", "amount": 3000, "workers_max": 8, "work_aux": 0.25,
		"blocks_cells": 2, "scatter": "", "model": "gold_vein"},
	# ECONOMY §1.2: глину Хумдон берёт у воды сам — ям на карте нет (узел оставлен по ARCHITECTURE §6.4)
	"clay": {"name": "Глиняная яма", "res": "clay", "amount": 2500, "workers_max": 6, "work_aux": 0.25,
		"blocks_cells": 0, "scatter": "", "model": "clay_pit", "enabled": false},
}
