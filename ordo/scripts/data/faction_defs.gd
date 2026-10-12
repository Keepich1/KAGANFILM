class_name FactionDefs
## Стороны «Города» (ТЗ 2, 5.1, 5.4; docs/ECONOMY.md). Схема — ведущий (M0), значения — ECON.
## Порядок записей = индекс Defs (PlayerTable.faction).
##
## Поля: name; hq — ставка; worker — работник; officer — офицер отрядов;
##   start_res {ресурс: число} (ТЗ 5.1); start_units {юнит: число} — у ставки;
##   traits [TRAITS] — механики стороны; ui_res [ресурсы] — фишки верхней балки (4 общих + 1–2 своих,
##   скрытые ресурсы с enabled false интерфейс пропускает); tabs {вкладка: [постройки по порядку кнопок]};
##   bounty — олжо (ТЗ 5.4): kill / worker {ресурс: за убитого}, building_share — доля цены разорённого
##   здания, hq {ресурс: за ставку}; color — цвет стороны (ТЗ 2.1, 2.2).

## Механики сторон (Defs.f_traits — битовая маска по этому порядку)
const TRAITS := ["irrigation", "bazaar", "loot", "koch", "seasons", "horses"]

const FACTIONS := {
	"kokand": {"name": "Коканд", "hq": "urda", "worker": "dehqon", "officer": "yuzboshi",
		"start_res": {"food": 500, "wood": 400, "stone": 250, "gold": 200},
		"start_units": {"dehqon": 6},
		"traits": ["irrigation", "bazaar"],
		"ui_res": ["food", "wood", "stone", "gold", "brick"],
		"tabs": {"economy": ["uy", "dala", "tegirmon", "ombor", "kazarma", "otxona", "topxona", "xumdon", "bozor",
				"aryk", "togon"],
			"fort": ["devor", "tosh", "darvoza", "burj"]},
		"bounty": {},
		"color": Color("#2f8f74")},
	"kipchak": {"name": "Кыпчаки", "hq": "ordo", "worker": "malchy", "officer": "juz_bashy",
		"start_res": {"food": 350, "wood": 380, "stone": 0, "gold": 150},
		"start_units": {"malchy": 6},
		"traits": ["loot", "koch", "seasons", "horses"],
		"ui_res": ["food", "wood", "stone", "gold", "horse", "felt"],
		"tabs": {"economy": ["boz", "koroo", "ken", "jooker", "jylky", "kurultai", "kiyiz"],
			"fort": ["chep", "darbaza", "munara"]},
		# олжо (ТЗ 5.4): 4 золота и 6 еды за убитого, 10 и 10 за работника, доля цены здания, 400 золота за ставку
		"bounty": {"kill": {"gold": 4, "food": 6}, "worker": {"gold": 10, "food": 10}, "building_share": 0.3,
			"hq": {"gold": 400}},
		"color": Color("#b0392f")},
}
