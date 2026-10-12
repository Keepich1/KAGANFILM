class_name GameRules
## Правила режимов (ARCHITECTURE §5, §9, §11, §12). Схема — ведущий (M0).
## Значения: ключи экономики — ECON, остальные — GAME. Defs.rules_of(&"GOROD") отдаёт
## скомпилированную копию (секунды → такты: ключи *_s получают пару *_ticks).
##
## Ключи экономики (ECON):
##   econ — экономика включена; pop_max — предел населения (ТЗ 5.1); upkeep — содержание армии;
##   famine {mods [ModifierDefs], end_min — голод кончается, когда еды на столько минут содержания};
##   loot — олжо включено (трейт стороны); trade {spread, drift_per_min} — базар; tax — подать;
##   herd_theft {r, guard_r, time_s, per_raider} — угон скота (ARCHITECTURE §11);
##   pack_r — радиус «свернуть весь лагерь», м; worker_resume_r — работа продолжается, когда врага нет ближе, м.
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
	"famine": {"mods": ["famine_atk", "famine_speed", "famine_morale"], "end_min": 1.0},
	"loot": true,
	"trade": {"spread": 0.2, "drift_per_min": 0.02, "enabled": false},
	"tax": {"enabled": false},
	"herd_theft": {"r": 12.0, "guard_r": 25.0, "time_s": 3, "per_raider": 10},
	"pack_r": 170.0,
	"worker_resume_r": 12.0,
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
	"famine": {"mods": [], "end_min": 1.0},
	"loot": false,
	"trade": {"spread": 0.0, "drift_per_min": 0.0, "enabled": false},
	"tax": {"enabled": false},
	"herd_theft": {"r": 0.0, "guard_r": 0.0, "time_s": 0, "per_raider": 0},
	"pack_r": 0.0,
	"worker_resume_r": 12.0,
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
