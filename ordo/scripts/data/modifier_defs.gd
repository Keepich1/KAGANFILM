class_name ModifierDefs
## Множители игроков (голод, сезоны; ТЗ 5.1, 5.4; docs/ECONOMY.md). Схема — ведущий (M0),
## значения — ECON. ECON собирает действующие в PlayerTable.stat и передаёт ядру
## через CombatPort.set_owner_mods (BattleSim.MOD_*).
##
## MODIFIERS {id: {stat, mul, add, when}}:
##   stat — "atk" | "speed" | "stam_regen" | "morale_regen" | "range" | "gather" | "build" | "upkeep"
##          (PlayerTable.Stat); mul — множитель, add — прибавка (к множителю 1.0);
##   when — "famine" | "season:<id>" | "always"; enabled.
## SEASONS {id: {name, duration_s, mods [MODIFIERS]}} — по кругу, в порядке записи (кыпчаки: трейт seasons).

const MODIFIERS := {
	# голод (ТЗ 5.1; ARCHITECTURE §11): атака ×0,75, скорость ×0,9, мораль не восстанавливается
	"famine_atk": {"stat": "atk", "mul": 0.75, "add": 0.0, "when": "famine"},
	"famine_speed": {"stat": "speed", "mul": 0.9, "add": 0.0, "when": "famine"},
	"famine_morale": {"stat": "morale_regen", "mul": 0.0, "add": 0.0, "when": "famine"},
	# сезоны кочевников (ECONOMY.md) — числа ещё не окончательные
	"jailoo_gather": {"stat": "gather", "mul": 1.1, "add": 0.0, "when": "season:jailoo", "enabled": false},
	"kyshtoo_upkeep": {"stat": "upkeep", "mul": 1.2, "add": 0.0, "when": "season:kyshtoo", "enabled": false},
}

const SEASONS := {
	"jailoo": {"name": "Жайлоо", "duration_s": 480, "mods": ["jailoo_gather"]},
	"kyshtoo": {"name": "Кыштоо", "duration_s": 240, "mods": ["kyshtoo_upkeep"]},
}
