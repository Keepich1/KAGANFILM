class_name ResourceDefs
## Ресурсы (ТЗ 5.1; docs/ECONOMY.md §1.1–1.3). Схема — ведущий (M0), значения — ECON.
## Порядок записей = индекс ресурса в Defs (не переставлять: индексы в приказах и повторах;
## новые — только в конец). Правило автора: у стороны 1–2 своих ресурса.
##
## Поля: name — подпись; faction — "" общий, иначе сторона; icon — имя значка (assets/ui);
##   backing — стадо HerdDefs, чьи головы и есть запас (кони: сумма табунов и коновязи);
##   enabled — false: ресурса нет в текущей сборке или ECONOMY.md не делает его запасом
##   (индекс занят, верхняя балка его не показывает).

const RESOURCES := {
	"food": {"name": "Еда", "faction": "", "icon": "food"},
	"wood": {"name": "Дерево", "faction": "", "icon": "wood"},
	"stone": {"name": "Камень", "faction": "", "icon": "stone"},
	"gold": {"name": "Золото", "faction": "", "icon": "gold"},
	# ECONOMY §1.2: глина — не запас, Хумдон берёт её у воды сам (индекс оставлен по ARCHITECTURE §6.4)
	"clay": {"name": "Лой", "faction": "kokand", "icon": "clay", "enabled": false},
	# Ғишт — обожжённый кирпич Коканда: Бурж, Тош девор (ECONOMY §2.4)
	"brick": {"name": "Ғишт", "faction": "kokand", "icon": "brick"},
	# Жылкы — кони кыпчаков: 1 конь на всадника, табун растёт и угоняется (ECONOMY §3.3)
	"horse": {"name": "Жылкы", "faction": "kipchak", "icon": "horse", "backing": "horse"},
	# ECONOMY §3.5: шерсть копится на короо и в запас не идёт (индекс оставлен по ARCHITECTURE §6.4)
	"wool": {"name": "Жүн", "faction": "kipchak", "icon": "wool", "enabled": false},
	# Кийиз — войлок кыпчаков (Сб. 2)
	"felt": {"name": "Кийиз", "faction": "kipchak", "icon": "felt", "enabled": false},
}
