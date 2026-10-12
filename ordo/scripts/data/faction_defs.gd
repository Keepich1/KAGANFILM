class_name FactionDefs
## Стороны «Города» (ТЗ 2, 5.1, 5.4; docs/ECONOMY.md §1.3, §2, §3, §4.2). Схема — ведущий (M0),
## значения — ECON. Порядок записей = индекс Defs (PlayerTable.faction). Цин и Джунгары — позже.
##
## Поля: name; hq — ставка; worker — работник; officer — офицер отрядов;
##   start_res {ресурс: число} (ТЗ 5.1); start_units {юнит: число} — у ставки (стартовые постройки,
##   стада и арыки — в карте, MapValley); traits [TRAITS] — механики стороны;
##   ui_res [ресурсы] — ячейки верхней балки слева направо (ECONOMY §1.3; ресурсы с enabled false
##   интерфейс пропускает); tabs {вкладка: [постройки по порядку кнопок]};
##   bounty — олжо (ТЗ 5.4, ECONOMY §4.2): kill / worker {ресурс: за убитого}, building_share — доля
##   цены разорённого здания золотом, hq {ресурс: за ставку}; alarm — имя тревоги (ECONOMY §1.7);
##   color — цвет стороны (ТЗ 2.1, 2.2).

## Механики сторон (Defs.f_traits — битовая маска по этому порядку; новые — в конец)
const TRAITS := ["irrigation", "bazaar", "loot", "koch", "seasons", "horses", "hashar"]

const FACTIONS := {
	"kokand": {"name": "Коканд", "hq": "urda", "worker": "dehqon", "officer": "yuzboshi",
		"start_res": {"food": 500, "wood": 400, "stone": 250, "gold": 200},
		"start_units": {"dehqon": 6},
		"traits": ["irrigation", "bazaar", "hashar"],
		"ui_res": ["food", "wood", "stone", "gold", "brick"],
		"tabs": {"economy": ["uy", "dala", "tegirmon", "ombor", "togon", "aryk", "xumdon", "bozor", "kazarma", "otxona",
				"topxona", "temirchixona"],
			"fort": ["devor", "tosh", "darvoza", "burj"]},
		"bounty": {},
		"alarm": "Ноғора",
		"color": Color("#2f8f74")},
	"kipchak": {"name": "Кыпчаки", "hq": "ordo", "worker": "malchy", "officer": "juz_bashy",
		"start_res": {"food": 350, "wood": 380, "stone": 0, "gold": 150},
		"start_units": {"malchy": 6},
		"traits": ["loot", "koch", "seasons", "horses"],
		# камня на балке нет: кыпчакам он не нужен (ECONOMY §1.3)
		"ui_res": ["food", "wood", "gold", "horse", "felt"],
		"tabs": {"economy": ["boz", "koroo", "ken", "jooker", "jylky", "kurultai", "kiyiz", "temirchi"],
			"fort": ["chep", "darbaza", "munara"]},
		"bounty": {"kill": {"gold": 4, "food": 6}, "worker": {"gold": 10, "food": 10}, "building_share": 0.3,
			"hq": {"gold": 400}},
		"alarm": "Чакырык",
		"color": Color("#b0392f")},
}
