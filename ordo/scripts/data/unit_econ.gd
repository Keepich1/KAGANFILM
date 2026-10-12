class_name UnitEcon
## Экономика юнитов (ТЗ 3, 5; docs/ECONOMY.md §1.1, §1.4–1.5, §2.7, §3.2): найм, население,
## содержание, добыча, стройка. Схема — ведущий (M0), значения — ECON.
## Бой (HP, скорость, урон) — в UnitStats (CORE). cost/time — источник правды; UnitStats.cost/time —
## старое зеркало (только еда/дерево/камень/золото), tests/test_defs.gd проверяет, что они совпадают.
##
## Поля (cost и time обязательны):
##   cost {ресурс: число} (конь кыпчакского всадника — "horse": 1, берётся из табуна), time — с;
##   pop — мест населения (1; пушка с расчётом — 3; арба — 0); upkeep — еды в минуту;
##   carry — сколько несёт за ходку; gather {ресурс: в секунду} (эффективно, склад ≤ 25 м);
##   build_rate — сила на стройке (1 — один работник; n работников — n^0,75); trained_at [здания];
##   squad_max — бойцов этого рода в отряде (0 — не в отряд); requires [здания] — нужны для найма;
##   unique — один на игрока; respawn_s — после гибели снова через; enabled.
## Добыча (ECONOMY §1.1): еда с поля 30, дерево 30, камень 24, золото 21 в минуту.
## Содержание (§1.5): пехота 0,7; всадники Коканда 1,4 (кони на зерне); всадники кыпчаков 0,7;
## пушка 1,0; работники 0.

const UNITS := {
	# ---------------------------------------------------------------- Коканд (ТЗ 3.1, ECONOMY §2.7)
	"dehqon": {"cost": {"food": 50}, "time": 7, "pop": 1, "upkeep": 0.0, "carry": 10,
		"gather": {"food": 0.5, "wood": 0.5, "stone": 0.4, "gold": 0.35},
		"build_rate": 1.0, "trained_at": ["urda"], "squad_max": 0},
	"yuzboshi": {"cost": {"food": 60, "gold": 60}, "time": 14, "pop": 1, "upkeep": 1.4,
		"trained_at": ["kazarma", "otxona"], "squad_max": 100},
	"sarboz": {"cost": {"food": 30, "wood": 10, "gold": 25}, "time": 9, "pop": 1, "upkeep": 0.7,
		"trained_at": ["kazarma"], "squad_max": 100},
	"zarbzan": {"cost": {"wood": 150, "gold": 120}, "time": 25, "pop": 3, "upkeep": 1.0,
		"trained_at": ["topxona"], "squad_max": 100},
	"kamonchi": {"cost": {"food": 30, "wood": 25}, "time": 8, "pop": 1, "upkeep": 0.7,
		"trained_at": ["kazarma"], "squad_max": 100},
	"nayzachi": {"cost": {"food": 30, "wood": 20}, "time": 8, "pop": 1, "upkeep": 0.7,
		"trained_at": ["kazarma"], "squad_max": 100},
	"kilichboz": {"cost": {"food": 35, "gold": 20}, "time": 9, "pop": 1, "upkeep": 0.7,
		"trained_at": ["kazarma"], "squad_max": 100},
	"navkar": {"cost": {"food": 60, "gold": 45}, "time": 12, "pop": 1, "upkeep": 1.4,
		"trained_at": ["otxona"], "squad_max": 100},
	# гвардия в «Городе» (ECONOMY §2.7): Хос навкарлар — при Отхоне и Тўпхоне; Лашкарбоши — один
	"xos_navkar": {"cost": {"food": 100, "gold": 100}, "time": 18, "pop": 1, "upkeep": 1.4,
		"trained_at": ["urda"], "requires": ["otxona", "topxona"], "squad_max": 100},
	"lashkarboshi": {"cost": {"food": 150, "gold": 150}, "time": 30, "pop": 1, "upkeep": 1.4,
		"trained_at": ["urda"], "unique": true, "respawn_s": 120, "squad_max": 0},
	# ---------------------------------------------------------------- Кыпчаки (ТЗ 3.2, ECONOMY §3.2)
	"malchy": {"cost": {"food": 45}, "time": 6, "pop": 1, "upkeep": 0.0, "carry": 10,
		"gather": {"food": 0.5, "wood": 0.5, "stone": 0.4, "gold": 0.35},
		"build_rate": 1.0, "trained_at": ["ordo"], "squad_max": 0},
	"juz_bashy": {"cost": {"food": 60, "gold": 50, "horse": 1}, "time": 12, "pop": 1, "upkeep": 0.7,
		"trained_at": ["jooker", "jylky"], "squad_max": 100},
	# арба — свёрнутая юрта в пути: не нанимается и мест не занимает (ТЗ 5.4, ECONOMY §1.4)
	"arba": {"cost": {}, "time": 0, "pop": 0, "upkeep": 0.0, "squad_max": 0},
	"atchan": {"cost": {"food": 40, "gold": 20, "horse": 1}, "time": 9, "pop": 1, "upkeep": 0.7,
		"trained_at": ["jylky"], "squad_max": 100},
	"jooker": {"cost": {"food": 30, "wood": 15}, "time": 7, "pop": 1, "upkeep": 0.7,
		"trained_at": ["jooker"], "squad_max": 100},
	"mergen": {"cost": {"food": 30, "wood": 30}, "time": 9, "pop": 1, "upkeep": 0.7,
		"trained_at": ["jooker"], "squad_max": 100},
	"sayisker": {"cost": {"food": 60, "gold": 50, "horse": 1}, "time": 12, "pop": 1, "upkeep": 0.7,
		"trained_at": ["jylky"], "squad_max": 100},
	"chabuulchu": {"cost": {"food": 40, "wood": 10, "horse": 1}, "time": 8, "pop": 1, "upkeep": 0.7,
		"trained_at": ["jylky"], "squad_max": 100},
	"batyr": {"cost": {"food": 100, "gold": 100, "horse": 1}, "time": 18, "pop": 1, "upkeep": 0.7,
		"trained_at": ["kurultai"], "squad_max": 100},
	"kolbashchy": {"cost": {"food": 150, "gold": 150, "horse": 1}, "time": 30, "pop": 1, "upkeep": 0.7,
		"trained_at": ["kurultai"], "unique": true, "respawn_s": 120, "squad_max": 0},
}
