class_name RecipeDefs
## Мастерские (docs/ECONOMY.md): что из чего делается. Схема — ведущий (M0), значения — ECON.
## Порядок записей = индекс Defs (номер рецепта в SimCmd.set_recipe).
##
## Поля: name; in {ресурс: число}, out {ресурс: число} за партию; time — с на партию;
##   workers — сколько работников нужно в мастерской; enabled. Где варится — ключ "recipes" здания.

const RECIPES := {
	"brick": {"name": "Кирпич", "in": {"clay": 4, "wood": 1}, "out": {"brick": 2}, "time": 10, "workers": 2,
		"enabled": false},
	"felt": {"name": "Войлок", "in": {"wool": 4}, "out": {"felt": 1}, "time": 10, "workers": 2,
		"enabled": false},
}
