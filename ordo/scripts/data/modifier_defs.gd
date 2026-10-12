class_name ModifierDefs
## Множители игроков, сезоны и зоны (ТЗ 5.1, 5.4; docs/ECONOMY.md §1.5, §3.6). Схема — ведущий (M0),
## значения — ECON. ECON собирает действующие множители в PlayerTable.stat и передаёт ядру через
## CombatPort.set_owner_mods (BattleSim.MOD_*).
##
## MODIFIERS {id: {stat, mul, add, when, enabled}}:
##   stat — "atk" | "speed" | "stam_regen" | "morale_regen" | "range" | "gather" | "build" | "upkeep"
##          (PlayerTable.Stat); mul — множитель, add — прибавка (к множителю 1.0);
##   when — "famine" | "season:<id>" | "always".
## SEASONS {id: {name, duration_s, first_s, mods [MODIFIERS], effects {…}, enabled}} — по кругу в порядке
##   записи, для всех сторон; first_s — длительность первого раза (лето до первой зимы).
## ZONES {id: {name, r, <сезон>: {koroo_food, trample, regrow_pm, horse_step, horse_mult, sheep_growth,
##   insulate}, enabled}} — пастбища кочевников: эффект получает постройка, стоящая в зоне.

const MODIFIERS := {
	# голод (ECONOMY §1.5): атака −20%, выносливость восстанавливается вдвое медленнее
	# (мораль не выше 70, дезертирство — GameRules.famine)
	"famine_atk": {"stat": "atk", "mul": 0.8, "add": 0.0, "when": "famine"},
	"famine_stam": {"stat": "stam_regen", "mul": 0.5, "add": 0.0, "when": "famine"},
}

## Сб. 2: зима каждые 10 минут на 3 минуты — 10:00–13:00, 20:00–23:00, … (ECONOMY §3.6)
const SEASONS := {
	"summer": {"name": "Жай", "duration_s": 420, "first_s": 600, "mods": [], "effects": {"fields_mult": 1.0},
		"enabled": false},
	"winter": {"name": "Кыш", "duration_s": 180, "mods": [], "effects": {"fields_mult": 0.7, "warn_s": 60},
		"enabled": false},
}

## Сб. 2: зоны пастбищ (ECONOMY §3.6); «степь» — вне зон
const ZONES := {
	"steppe": {"name": "Талаа", "r": 0.0,
		"summer": {"koroo_food": 1.0, "trample": 1.0, "regrow_pm": 30, "horse_step": 0, "horse_mult": 1.0, "sheep_growth": 2.0},
		"winter": {"koroo_food": 0.5, "trample": 1.0, "regrow_pm": 0, "horse_step": 0, "horse_mult": 0.0, "sheep_growth": 0.0,
			"insulate": true},
		"enabled": false},
	"jailoo": {"name": "Жайлоо", "r": 150.0,
		"summer": {"koroo_food": 1.25, "trample": 0.5, "regrow_pm": 30, "horse_step": 1, "horse_mult": 1.0, "sheep_growth": 3.0},
		"winter": {"koroo_food": 0.25, "trample": 1.0, "regrow_pm": 0, "horse_step": 0, "horse_mult": 0.0, "sheep_growth": 0.0,
			"insulate": true},
		"enabled": false},
	"kyshtoo": {"name": "Кыштоо", "r": 120.0,
		"summer": {"koroo_food": 1.0, "trample": 1.0, "regrow_pm": 15, "horse_step": 0, "horse_mult": 1.0, "sheep_growth": 2.0},
		"winter": {"koroo_food": 1.0, "trample": 0.0, "regrow_pm": 0, "horse_step": 0, "horse_mult": 0.5, "sheep_growth": 1.0},
		"enabled": false},
}
