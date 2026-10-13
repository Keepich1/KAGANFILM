class_name GameRules
## Правила режимов (ARCHITECTURE §5, §9, §11, §12; docs/ECONOMY.md §1, §2.5, §3.4, §4.1). Схема — ведущий (M0).
## Значения: ключи экономики — ECON, остальные — GAME. Defs.rules_of(&"GOROD") отдаёт скомпилированную
## копию: ключи *_s (секунды) получают пару *_ticks.
##
## Экономика (ECON):
##   econ — экономика включена; pop_max — предел населения (ТЗ 5.1); upkeep — содержание армии,
##   upkeep_every_s — как часто списывается; build_exp — скорость стройки n^build_exp (n работников);
##   repair_cost — доля цены за полный ремонт; famine {mods [ModifierDefs], morale_cap, desert_after_s,
##   desert_every_s, desert_frac, end_food, no_food_hire, no_tax} — голод (ECONOMY §1.5);
##   loot — олжо включено (у сторон с FactionDefs.bounty); trade {lot, sell {ресурс: золота за лот},
##   buy {…}} — обмен на Бозоре по постоянному курсу; tax {every_s, min_hp} — подать (tax_min построек);
##   water {lalmi, xumdon_dry} — поле без воды и печь без воды; pasture {regrow_pm, floor_pm, warn_pm,
##   place_min_pm, auto_move_below_pm, auto_move_r, auto_move_pause_s} — трава 0..1000 (промилле);
##   herds {slaughter_heads, slaughter_food, slaughter_cd_s} — «Мал союу»;
##   herd_theft — барымта (круг прогресса, ECONOMY §4.1): {guard_r, abort_loss, min_riders, circle_s,
##   horses_per_riders, horses_max, sheep}; taloo — грабёж склада; trample — вытоптать поле;
##   loot_carry {speed, flee_home_speed, bank_r} — увод добычи;
##   alarm {r, fire_per, fire_every_s, fire_dmg, fire_range} — тревога (ECONOMY §1.7);
##   pack_r — радиус «свернуть весь лагерь», м; pack_s — сколько сворачивается лагерь;
##   worker_resume_r — работа продолжается, когда врага нет ближе, м; seasons — сезоны (Сб. 2);
##   bld_dmg {melee_inf, melee_cav, raider_econ} — рукопашная по зданиям (ECONOMY §1.6; стрелы, пули и
##   ядра умножает ядро по UnitStats.vs_building) — ключ ECON сверх схемы M0.
## Остальные (GAME):
##   corpse_s — тела исчезают через, с (−1 никогда); path_per_tick, path_cells_per_tick — бюджет путей;
##   breach_ratio — сравнивать путь с проломом, когда обход дороже ratio × прямой (0 — выкл);
##   input_delay — тактов задержки приказа; ai_free_waves — ИИ получает волны набега даром (Op.SPAWN);
##   raids — набеги ИИ; victory — "hq" (потеря ставки или арбы с ордо) | "battle" (ТЗ 4).

const GOROD := {
	# --- ECON
	"econ": true,
	"pop_max": 500,
	"upkeep": true,
	"upkeep_every_s": 10,
	"build_exp": 0.75,
	"repair_cost": 0.5,
	"famine": {"mods": ["famine_atk", "famine_stam"], "morale_cap": 70, "desert_after_s": 60, "desert_every_s": 30,
		"desert_frac": 0.03, "end_food": 50, "no_food_hire": true, "no_tax": true},
	"loot": true,
	"trade": {"lot": 100, "sell": {"food": 40, "wood": 40, "stone": 50, "brick": 60},
		"buy": {"food": 110, "wood": 110, "stone": 140}},
	"tax": {"every_s": 30, "min_hp": 0.5},
	"water": {"lalmi": 0.25, "xumdon_dry": 0.5},
	"pasture": {"regrow_pm": 30, "floor_pm": 200, "warn_pm": 400, "place_min_pm": 500, "auto_move_below_pm": 400,
		"auto_move_r": 80.0, "auto_move_pause_s": 30},
	"herds": {"slaughter_heads": 10, "slaughter_food": 120, "slaughter_cd_s": 60},
	"herd_theft": {"guard_r": 30.0, "abort_loss": 0.2, "min_riders": 5, "circle_s": 6, "horses_per_riders": 2,
		"horses_max": 15, "sheep": 10},
	"taloo": {"min_riders": 10, "circle_s": 10, "frac": 0.1, "max": 300, "cooldown_s": 90},
	"trample": {"min_riders": 5, "circle_s": 5, "fallow_s": 45},
	"loot_carry": {"speed": 8.0, "flee_home_speed": 6.0, "bank_r": 30.0},
	"alarm": {"r": 80.0, "fire_per": 5, "fire_every_s": 2, "fire_dmg": 13, "fire_range": 80.0},
	"pack_r": 170.0,
	"pack_s": 15,
	"worker_resume_r": 12.0,
	"seasons": false,
	"bld_dmg": {"melee_inf": 0.5, "melee_cav": 0.3, "raider_econ": 0.4},
	# --- GAME
	"corpse_s": 30,
	"path_per_tick": 16,
	"path_cells_per_tick": 8000,
	"breach_ratio": 0.0,
	"input_delay": 1,
	"ai_free_waves": true,
	"raids": true,
	"victory": "hq",
}

const BATTLE := {
	# --- ECON
	"econ": false,
	"pop_max": 500,
	"upkeep": false,
	"upkeep_every_s": 10,
	"build_exp": 0.75,
	"repair_cost": 0.5,
	"famine": {"mods": [], "morale_cap": 100, "desert_after_s": -1, "desert_every_s": -1, "desert_frac": 0.0,
		"end_food": 0, "no_food_hire": false, "no_tax": false},
	"loot": false,
	"trade": {"lot": 100, "sell": {}, "buy": {}},
	"tax": {"every_s": -1, "min_hp": 0.5},
	"water": {"lalmi": 1.0, "xumdon_dry": 1.0},
	"pasture": {"regrow_pm": 0, "floor_pm": 0, "warn_pm": 0, "place_min_pm": 0, "auto_move_below_pm": 0,
		"auto_move_r": 0.0, "auto_move_pause_s": 0},
	"herds": {"slaughter_heads": 0, "slaughter_food": 0, "slaughter_cd_s": -1},
	"herd_theft": {"guard_r": 0.0, "abort_loss": 0.0, "min_riders": 0, "circle_s": -1, "horses_per_riders": 0,
		"horses_max": 0, "sheep": 0},
	"taloo": {"min_riders": 0, "circle_s": -1, "frac": 0.0, "max": 0, "cooldown_s": -1},
	"trample": {"min_riders": 0, "circle_s": -1, "fallow_s": -1},
	"loot_carry": {"speed": 8.0, "flee_home_speed": 6.0, "bank_r": 30.0},
	"alarm": {"r": 0.0, "fire_per": 0, "fire_every_s": -1, "fire_dmg": 0, "fire_range": 0.0},
	"pack_r": 0.0,
	"pack_s": 15,
	"worker_resume_r": 12.0,
	"seasons": false,
	"bld_dmg": {"melee_inf": 1.0, "melee_cav": 1.0, "raider_econ": 1.0},
	# --- GAME
	"corpse_s": -1,
	"path_per_tick": 16,
	"path_cells_per_tick": 8000,
	"breach_ratio": 0.0,
	"input_delay": 1,
	"ai_free_waves": false,
	"raids": false,
	"victory": "battle",
}
