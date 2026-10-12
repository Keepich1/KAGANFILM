class_name ResourceDefs
## Ресурсы (ТЗ 5.1; docs/ECONOMY.md). Схема — ведущий (M0), значения — ECON.
## Порядок записей = индекс ресурса в Defs (не переставлять: индексы в приказах и повторах).
## Правило: у стороны 1–2 своих ресурса (ТЗ, журнал решений 2026-10-12).
##
## Поля: name — подпись; faction — "" общий, иначе сторона; icon — имя значка (assets/ui);
##   backing — стадо HerdDefs, чьи головы и есть запас (кони); enabled — false, пока в
##   ECONOMY.md нет окончательных чисел (индекс уже занят, интерфейс ресурс не показывает).

const RESOURCES := {
	"food": {"name": "Еда", "faction": "", "icon": "food"},
	"wood": {"name": "Дерево", "faction": "", "icon": "wood"},
	"stone": {"name": "Камень", "faction": "", "icon": "stone"},
	"gold": {"name": "Золото", "faction": "", "icon": "gold"},
	# Коканд: печь — глина → кирпич для каменных стен (ECONOMY.md)
	"clay": {"name": "Глина", "faction": "kokand", "icon": "clay", "enabled": false},
	"brick": {"name": "Кирпич", "faction": "kokand", "icon": "brick", "enabled": false},
	# Кыпчаки: кони — запас конницы (табун растёт, его можно угнать); шерсть → войлок → юрты
	"horse": {"name": "Кони", "faction": "kipchak", "icon": "horse", "backing": "horse", "enabled": false},
	"wool": {"name": "Шерсть", "faction": "kipchak", "icon": "wool", "enabled": false},
	"felt": {"name": "Войлок", "faction": "kipchak", "icon": "felt", "enabled": false},
}
