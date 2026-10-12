class_name UnitEcon
## Экономика юнитов (ТЗ 3, 5): цена и время найма, население, содержание, добыча, стройка.
## Схема — ведущий (M0), значения — ECON. Бой (HP, скорость, урон) — в UnitStats (CORE).
## cost/time — источник правды; UnitStats.cost/time — старое зеркало, tests/test_defs.gd
## проверяет, что они совпадают.
##
## Поля (все, кроме cost и time, необязательны):
##   cost {ресурс: число}, time — с; pop — мест населения (1); upkeep — еды в минуту;
##   carry — сколько несёт за ходку; gather {ресурс: в секунду}; build_rate — сила на стройке
##   (1 — один работник); trained_at [здания]; squad_max — бойцов этого рода в отряде (0 — не в отряд).
## Числа добычи — стартовые [Основа] до ECONOMY.md; содержание 0,7 еды/мин на бойца — ТЗ 5.1.

const UNITS := {
	# ---------------------------------------------------------------- Коканд (ТЗ 3.1, 5.2)
	"dehqon": {"cost": {"food": 50}, "time": 7, "pop": 1, "upkeep": 0.0, "carry": 10,
		"gather": {"food": 0.3, "wood": 0.45, "stone": 0.35, "gold": 0.35, "clay": 0.45},
		"build_rate": 1.0, "trained_at": ["urda"], "squad_max": 0},
	"yuzboshi": {"cost": {"food": 60, "gold": 60}, "time": 14, "pop": 1, "upkeep": 0.7,
		"trained_at": ["kazarma", "otxona"], "squad_max": 100},
	"sarboz": {"cost": {"food": 30, "wood": 10, "gold": 25}, "time": 9, "pop": 1, "upkeep": 0.7,
		"trained_at": ["kazarma"], "squad_max": 100},
	"zarbzan": {"cost": {"wood": 150, "gold": 120}, "time": 25, "pop": 1, "upkeep": 0.7,
		"trained_at": ["topxona"], "squad_max": 100},
	"kamonchi": {"cost": {"food": 30, "wood": 25}, "time": 8, "pop": 1, "upkeep": 0.7,
		"trained_at": ["kazarma"], "squad_max": 100},
	"nayzachi": {"cost": {"food": 30, "wood": 20}, "time": 8, "pop": 1, "upkeep": 0.7,
		"trained_at": ["kazarma"], "squad_max": 100},
	"kilichboz": {"cost": {"food": 35, "gold": 20}, "time": 9, "pop": 1, "upkeep": 0.7,
		"trained_at": ["kazarma"], "squad_max": 100},
	"navkar": {"cost": {"food": 60, "gold": 45}, "time": 12, "pop": 1, "upkeep": 0.7,
		"trained_at": ["otxona"], "squad_max": 100},
	# только в сражении (ТЗ 3.1: [Свободно: найм])
	"xos_navkar": {"cost": {}, "time": 0, "pop": 1, "upkeep": 0.7, "squad_max": 100},
	"lashkarboshi": {"cost": {}, "time": 0, "pop": 1, "upkeep": 0.7, "squad_max": 0},
	# ---------------------------------------------------------------- Кыпчаки (ТЗ 3.2, 5.3)
	"malchy": {"cost": {"food": 45}, "time": 6, "pop": 1, "upkeep": 0.0, "carry": 10,
		"gather": {"food": 0.3, "wood": 0.45, "stone": 0.35, "gold": 0.35},
		"build_rate": 1.0, "trained_at": ["ordo"], "squad_max": 0},
	"juz_bashy": {"cost": {"food": 60, "gold": 50}, "time": 12, "pop": 1, "upkeep": 0.7,
		"trained_at": ["jooker"], "squad_max": 100},
	# арба — свёрнутая юрта в пути: не нанимается, мест населения не занимает (ТЗ 5.4)
	"arba": {"cost": {}, "time": 0, "pop": 0, "upkeep": 0.0, "squad_max": 0},
	"atchan": {"cost": {"food": 40, "gold": 20}, "time": 9, "pop": 1, "upkeep": 0.7,
		"trained_at": ["jylky"], "squad_max": 100},
	"jooker": {"cost": {"food": 30, "wood": 15}, "time": 7, "pop": 1, "upkeep": 0.7,
		"trained_at": ["jooker"], "squad_max": 100},
	"mergen": {"cost": {"food": 30, "wood": 30}, "time": 9, "pop": 1, "upkeep": 0.7,
		"trained_at": ["jooker"], "squad_max": 100},
	"sayisker": {"cost": {"food": 60, "gold": 50}, "time": 12, "pop": 1, "upkeep": 0.7,
		"trained_at": ["jylky"], "squad_max": 100},
	"chabuulchu": {"cost": {"food": 40, "wood": 10}, "time": 8, "pop": 1, "upkeep": 0.7,
		"trained_at": ["jylky"], "squad_max": 100},
	"batyr": {"cost": {"food": 100, "gold": 100}, "time": 18, "pop": 1, "upkeep": 0.7,
		"trained_at": ["kurultai"], "squad_max": 100},
	"kolbashchy": {"cost": {"food": 100, "gold": 100}, "time": 18, "pop": 1, "upkeep": 0.7,
		"trained_at": ["kurultai"], "squad_max": 0},
}
