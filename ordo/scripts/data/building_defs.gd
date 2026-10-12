class_name BuildingDefs
## Постройки Коканда и кыпчаков (ТЗ 5.2, 5.3, 6, 11.6; docs/ECONOMY.md).
## Схема — ведущий (M0, ARCHITECTURE §6.4), значения — ECON. Порядок записей = индекс Defs.
##
## Обязательные ключи: name, faction, kind, size. Остальные необязательны:
##   kind     "building" | "field" | "wall" | "gate" | "tower" | "link" | "dam"   (Defs.BKind)
##   size     Vector2 в плане, м (ТЗ 11.6); клетки навигации: ceili(size / 4 − 0.1)
##   tab      вкладка меню: "economy" («Хозяйство») | "fort" («Укрепления») | "" — не строится
##   hp, cost {ресурс: число}, build_time — с; pop_cap — мест населения
##   flags    ["hq", "drop", "house", "packable", "pen", "territory", "blocks", "round", "network",
##             "market", "walkable"]  (Defs.BF_*)
##   accepts  [ресурсы] — склад (с флагом "drop")
##   place    {max_slope 1.2 (м перепада по углам), water false, territory true,
##             near {nodes [типы узлов], r}, on_wall "align" | "replace", across_river}
##   territory_r — радиус своей земли вокруг (флаг "territory"), м
##   work     поле: {res, slots, per_worker_min, carry_to [здания]}
##   yield    [{field "water" | "grass", below 0..1000, mul}] — множители урожая по полю карты
##   link     звено линии: {len, overlap} — шаг len − overlap (devor/tosh 3,2 м, chep 3,0 м)
##   garrison {cap, range_mult, absorb, stone_range, platform_h} (этап 2)
##   herd     загон: {htype, start, cap}
##   aura     {gather_mult, r, res [ресурсы]}
##   network  {kind "water", coverage м | source true}
##   recipes  [RecipeDefs]; passive [{kind, …}] (подать базара и т. п.)
##   unpack_s — сколько встаёт юрта после переезда (көч), с
##   model    имя модели (по умолчанию — id): scenes/<faction>/<id>.tscn или assets/models/<faction>/<id>.glb
##   render   "scene" (узел на здание) | "multimesh" (стены, арыки, дома и юрты)
##   raid_value — ценность для набега (ARCHITECTURE §12: поле 3, склад 3, дом 1, ставка 0,5)
##   enabled  false — в ECONOMY.md ещё нет окончательных чисел (индекс занят, в меню не видно)
## HP и время стройки, которых нет в ТЗ, — стартовые [Свободно].

const BUILDINGS := {
	# ================================================================ Коканд — хозяйство (ТЗ 5.2)
	"urda": {"name": "Урда", "faction": "kokand", "tab": "", "kind": "building",
		"size": Vector2(18, 18), "hp": 3000, "cost": {}, "build_time": 0,
		"flags": ["hq", "drop", "blocks", "territory"], "accepts": ["food", "wood", "stone", "gold", "clay", "brick"],
		"pop_cap": 25, "territory_r": 70.0, "raid_value": 0.5},
	"uy": {"name": "Уй", "faction": "kokand", "tab": "economy", "kind": "building",
		"size": Vector2(8, 8), "hp": 600, "cost": {"wood": 80, "stone": 20}, "build_time": 25,
		"flags": ["house", "blocks"], "pop_cap": 15, "render": "multimesh", "raid_value": 1},
	"dala": {"name": "Дала", "faction": "kokand", "tab": "economy", "kind": "field",
		"size": Vector2(16, 16), "hp": 300, "cost": {"wood": 60}, "build_time": 20, "flags": ["walkable"],
		"work": {"res": "food", "slots": 4, "per_worker_min": 18, "carry_to": ["tegirmon", "urda"]},
		# арыки (ECONOMY.md): без воды урожай ×0,25 — включится вместе с поливом
		"yield": [{"field": "water", "below": 500, "mul": 0.25, "enabled": false}], "raid_value": 3},
	"tegirmon": {"name": "Тегирмон", "faction": "kokand", "tab": "economy", "kind": "building",
		"size": Vector2(9, 9), "hp": 900, "cost": {"wood": 120}, "build_time": 30,
		"flags": ["drop", "blocks"], "accepts": ["food"], "raid_value": 3},
	"ombor": {"name": "Омбор", "faction": "kokand", "tab": "economy", "kind": "building",
		"size": Vector2(9, 9), "hp": 900, "cost": {"wood": 100}, "build_time": 30,
		"flags": ["drop", "blocks"], "accepts": ["wood", "stone", "gold", "clay", "brick"], "raid_value": 3},
	"kazarma": {"name": "Казарма", "faction": "kokand", "tab": "economy", "kind": "building",
		"size": Vector2(16, 12), "hp": 1500, "cost": {"wood": 200, "stone": 100}, "build_time": 50,
		"flags": ["blocks"], "raid_value": 1},
	"otxona": {"name": "Отхона", "faction": "kokand", "tab": "economy", "kind": "building",
		"size": Vector2(16, 12), "hp": 1500, "cost": {"wood": 220, "stone": 60}, "build_time": 50,
		"flags": ["blocks"], "raid_value": 1},
	"topxona": {"name": "Тўпхона", "faction": "kokand", "tab": "economy", "kind": "building",
		"size": Vector2(14, 12), "hp": 1600, "cost": {"wood": 200, "stone": 200, "gold": 100}, "build_time": 60,
		"flags": ["blocks"], "raid_value": 1},
	# ECONOMY.md: печь, базар, арыки и запруда — числа ещё не окончательные
	"xumdon": {"name": "Хумдон", "faction": "kokand", "tab": "economy", "kind": "building",
		"size": Vector2(9, 9), "hp": 800, "cost": {"wood": 100, "stone": 40}, "build_time": 30,
		"flags": ["blocks"], "recipes": ["brick"], "raid_value": 2, "enabled": false},
	"bozor": {"name": "Бозор", "faction": "kokand", "tab": "economy", "kind": "building",
		"size": Vector2(14, 14), "hp": 1200, "cost": {"wood": 150, "gold": 50}, "build_time": 45,
		"flags": ["market", "blocks"], "passive": [{"kind": "tax", "res": "gold", "per_pop_min": 0.05}],
		"raid_value": 2, "enabled": false},
	"aryk": {"name": "Арык", "faction": "kokand", "tab": "economy", "kind": "link",
		"size": Vector2(4, 1.2), "hp": 200, "cost": {"wood": 2}, "build_time": 3, "flags": ["network", "walkable"],
		"link": {"len": 4.0, "overlap": 0.0}, "network": {"kind": "water", "coverage": 8.0},
		"render": "multimesh", "enabled": false},
	"togon": {"name": "Тўғон", "faction": "kokand", "tab": "economy", "kind": "dam",
		"size": Vector2(12, 4), "hp": 1500, "cost": {"wood": 60, "stone": 40}, "build_time": 30,
		"flags": ["network", "blocks"], "place": {"across_river": true, "water": true, "territory": false},
		"network": {"kind": "water", "source": true}, "raid_value": 2, "enabled": false},
	# ================================================================ Коканд — укрепления (ТЗ 6)
	"devor": {"name": "Пахса девор", "faction": "kokand", "tab": "fort", "kind": "wall",
		"size": Vector2(3.6, 1.8), "hp": 420, "cost": {"wood": 3}, "build_time": 4, "flags": ["blocks"],
		"link": {"len": 3.6, "overlap": 0.4}, "render": "multimesh"},
	"tosh": {"name": "Тош девор", "faction": "kokand", "tab": "fort", "kind": "wall",
		"size": Vector2(3.6, 2.2), "hp": 1200, "cost": {"stone": 8}, "build_time": 8, "flags": ["blocks"],
		"link": {"len": 3.6, "overlap": 0.4}, "render": "multimesh"},
	"darvoza": {"name": "Дарвоза", "faction": "kokand", "tab": "fort", "kind": "gate",
		"size": Vector2(7.2, 3), "hp": 1600, "cost": {"wood": 40, "stone": 30}, "build_time": 20, "flags": ["blocks"],
		"place": {"on_wall": "align"}},
	"burj": {"name": "Бурж", "faction": "kokand", "tab": "fort", "kind": "tower",
		"size": Vector2(7, 7), "hp": 2000, "cost": {"stone": 80, "wood": 30}, "build_time": 40, "flags": ["blocks"],
		"garrison": {"cap": 10, "range_mult": 1.3, "absorb": 0.55, "stone_range": 32.0, "platform_h": 8.4},
		"place": {"on_wall": "replace"}},
	# ================================================================ Кыпчаки — лагерь (ТЗ 5.3, 5.4)
	"ordo": {"name": "Хан ордосу", "faction": "kipchak", "tab": "", "kind": "building",
		"size": Vector2(14, 14), "hp": 2000, "cost": {}, "build_time": 0,
		"flags": ["hq", "drop", "blocks", "territory", "round", "packable"],
		"accepts": ["food", "wood", "stone", "gold", "wool", "felt"],
		"pop_cap": 25, "territory_r": 60.0, "unpack_s": 30, "raid_value": 0.5},
	"boz": {"name": "Боз үй", "faction": "kipchak", "tab": "economy", "kind": "building",
		"size": Vector2(7, 7), "hp": 300, "cost": {"wood": 40}, "build_time": 12,
		"flags": ["house", "blocks", "round", "packable"], "pop_cap": 10, "unpack_s": 12,
		"render": "multimesh", "raid_value": 1},
	"koroo": {"name": "Короо", "faction": "kipchak", "tab": "economy", "kind": "building",
		"size": Vector2(14, 14), "hp": 400, "cost": {"wood": 60}, "build_time": 20,
		"flags": ["pen", "blocks", "packable"], "herd": {"htype": "sheep", "start": 20, "cap": 40},
		"unpack_s": 15, "raid_value": 4},
	"ken": {"name": "Кен", "faction": "kipchak", "tab": "economy", "kind": "building",
		"size": Vector2(8, 8), "hp": 500, "cost": {"wood": 80}, "build_time": 20,
		"flags": ["drop", "blocks", "packable"], "accepts": ["stone", "gold"],
		"place": {"near": {"nodes": ["stone", "gold"], "r": 26.0}, "territory": false},
		"aura": {"gather_mult": 1.5, "r": 26.0, "res": ["stone", "gold"]}, "unpack_s": 12, "raid_value": 3},
	"jooker": {"name": "Жоокер үйү", "faction": "kipchak", "tab": "economy", "kind": "building",
		"size": Vector2(12, 10), "hp": 800, "cost": {"wood": 120}, "build_time": 30,
		"flags": ["blocks", "packable"], "unpack_s": 20, "raid_value": 1},
	"jylky": {"name": "Жылкы короосу", "faction": "kipchak", "tab": "economy", "kind": "building",
		"size": Vector2(16, 12), "hp": 800, "cost": {"wood": 150, "gold": 40}, "build_time": 35,
		"flags": ["pen", "blocks", "packable"], "herd": {"htype": "horse", "start": 10, "cap": 30},
		"unpack_s": 20, "raid_value": 4},
	"kurultai": {"name": "Курултай", "faction": "kipchak", "tab": "economy", "kind": "building",
		"size": Vector2(14, 14), "hp": 1200, "cost": {"wood": 200, "gold": 150}, "build_time": 50,
		"flags": ["blocks", "round", "packable"], "unpack_s": 30, "raid_value": 1},
	# ECONOMY.md: войлочный двор — шерсть → войлок
	"kiyiz": {"name": "Кийиз үйү", "faction": "kipchak", "tab": "economy", "kind": "building",
		"size": Vector2(10, 8), "hp": 400, "cost": {"wood": 60}, "build_time": 20,
		"flags": ["blocks", "packable"], "recipes": ["felt"], "unpack_s": 15, "raid_value": 2, "enabled": false},
	# ================================================================ Кыпчаки — укрепления (ТЗ 6)
	"chep": {"name": "Жыгач чеп", "faction": "kipchak", "tab": "fort", "kind": "wall",
		"size": Vector2(3.4, 1.2), "hp": 260, "cost": {"wood": 5}, "build_time": 3, "flags": ["blocks"],
		"link": {"len": 3.4, "overlap": 0.4}, "render": "multimesh"},
	"darbaza": {"name": "Дарбаза", "faction": "kipchak", "tab": "fort", "kind": "gate",
		"size": Vector2(6.4, 2.4), "hp": 700, "cost": {"wood": 45}, "build_time": 15, "flags": ["blocks"],
		"place": {"on_wall": "align"}},
	"munara": {"name": "Күзөт мунарасы", "faction": "kipchak", "tab": "fort", "kind": "tower",
		"size": Vector2(5, 5), "hp": 700, "cost": {"wood": 70}, "build_time": 20, "flags": ["blocks", "packable"],
		"garrison": {"cap": 6, "range_mult": 1.3, "absorb": 0.55, "stone_range": 32.0, "platform_h": 7.0},
		"place": {"on_wall": "replace"}, "unpack_s": 15},
}
