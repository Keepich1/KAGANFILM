class_name BuildingDefs
## Постройки Коканда и кыпчаков (ТЗ 5.2, 5.3, 6, 11.6; docs/ECONOMY.md §1.4–1.7, §2, §3 — где цифры
## расходятся, верны цифры ECONOMY.md). Схема — ведущий (M0, ARCHITECTURE §6.4), значения — ECON.
## Порядок записей = индекс Defs (новые — только в конец).
##
## Обязательные ключи: name, faction, kind, size. Остальные необязательны:
##   kind     "building" | "field" | "wall" | "gate" | "tower" | "link" | "dam"   (Defs.BKind)
##   size     Vector2 в плане, м (ТЗ 11.6); клетки навигации: ceili(size / 4 − 0.1)
##   tab      вкладка меню: "economy" («Хозяйство») | "fort" («Укрепления») | "" — не строится
##   hp, cost {ресурс: число}, build_time — с для одного работника; pop_cap — мест населения
##   flags    ["hq", "drop", "house", "packable", "pen", "territory", "blocks", "round", "network",
##             "market", "walkable", "unbreakable"]  (Defs.BF_*; unbreakable — не ломается: поле, арык)
##   accepts  [ресурсы] — склад (с флагом "drop")
##   place    {max_slope 1.2 (м перепада по углам), water false, territory true, water_zone (в зоне воды),
##             near {nodes [типы узлов], r}, on_wall "align" | "replace", across_river (у реки, не на броде)}
##   requires [постройки] — нужны, чтобы строить (Тош девор и Бурж — после первого Хумдона)
##   max_per_player — предел на игрока (Бозор 1, Короо 10)
##   territory_r — радиус своей земли вокруг (флаг "territory"), м
##   work     работа на месте: {res, slots, per_worker_min, carry_to [здания] ([] — сразу в запас)}
##            (Дала — 4 работника; Короо — до 2 пастухов сверх отары)
##   yield    [{field "water" | "grass", below 0..1000, mul}] — множители выхода по полю карты
##   water_place — сколько мест воды тўғона занимает (Дала, Хумдон — 1)
##   link     звено линии: {len, overlap} — шаг len − overlap (devor/tosh 3,2 м, chep 3,0 м)
##   garrison {cap, range_mult, absorb, stone_range, platform_h} (этап 2)
##   herd     стадо при постройке: {htype, start, cap, breed} (breed false — коновязь без приплода)
##   aura     {gather_mult, r, res [ресурсы]}
##   network  вода: источник {kind "water", source, places, range, dry_s} или звено {kind "water", zone}
##   rebuild  восстановление на руинах: {cost, time}
##   recipes  [RecipeDefs]; tax_min — подать золотом в минуту, пока у игрока есть Бозор
##   shelter  сколько работников укрывает тревога (Ноғора / Чакырык, ECONOMY §1.7)
##   ability  кнопка постройки: {id, duration_s, cooldown_s, …} (Ҳашар у Урды)
##   otlar    запас угнанных коней Коканда: {cap, discount_gold, overflow_gold}
##   unpack_s — сколько встаёт после переезда (көч), с; arbas — во сколько арб сворачивается (1)
##   model    имя модели (по умолчанию — id): scenes/<faction>/<id>.tscn или assets/models/<faction>/<id>.glb
##   render   "scene" (узел на здание) | "multimesh" (стены, арыки, дома и юрты)
##   raid_value — ценность для набега (ARCHITECTURE §12)
##   enabled  false — нет окончательных чисел или постройка из следующих сборок ECONOMY.md (Сб. 2+)

const BUILDINGS := {
	# ================================================================ Коканд — хозяйство (ТЗ 5.2, ECONOMY §2.1)
	"urda": {"name": "Урда", "faction": "kokand", "tab": "", "kind": "building",
		"size": Vector2(18, 18), "hp": 4000, "cost": {}, "build_time": 0,
		"flags": ["hq", "drop", "blocks", "territory"], "accepts": ["food", "wood", "stone", "gold", "brick"],
		"pop_cap": 25, "territory_r": 90.0, "shelter": 20, "tax_min": 8,
		"ability": {"id": "hashar", "duration_s": 45, "cooldown_s": 240, "build_mult": 2.0, "repair_cost_mult": 0.5,
			"worker_attack": 6, "worker_armour": 2},
		"raid_value": 0.5},
	"uy": {"name": "Уй", "faction": "kokand", "tab": "economy", "kind": "building",
		"size": Vector2(8, 8), "hp": 800, "cost": {"wood": 80, "stone": 20}, "build_time": 25,
		"flags": ["house", "blocks", "territory"], "territory_r": 30.0, "pop_cap": 15, "shelter": 5, "tax_min": 4, "render": "multimesh", "raid_value": 1},
	"dala": {"name": "Дала", "faction": "kokand", "tab": "economy", "kind": "field",
		"size": Vector2(16, 16), "hp": 300, "cost": {"wood": 60}, "build_time": 15, "flags": ["walkable", "unbreakable"],
		"work": {"res": "food", "slots": 4, "per_worker_min": 30, "carry_to": ["tegirmon", "urda"]},
		# вне зоны воды или без места воды — «лалми», 25% (ECONOMY §2.2)
		"water_place": 1, "yield": [{"field": "water", "below": 500, "mul": 0.25}], "raid_value": 3},
	"tegirmon": {"name": "Тегирмон", "faction": "kokand", "tab": "economy", "kind": "building",
		"size": Vector2(9, 9), "hp": 900, "cost": {"wood": 120}, "build_time": 30,
		"flags": ["drop", "blocks", "territory"], "territory_r": 30.0, "accepts": ["food"], "raid_value": 3},
	"ombor": {"name": "Омбор", "faction": "kokand", "tab": "economy", "kind": "building",
		"size": Vector2(9, 9), "hp": 900, "cost": {"wood": 100}, "build_time": 25,
		"flags": ["drop", "blocks", "territory"], "territory_r": 30.0, "accepts": ["wood", "stone", "gold", "brick"],
		"raid_value": 3},
	# Тўғон — голова арыков, уязвимая жила Коканда (ECONOMY §2.3)
	"togon": {"name": "Тўғон", "faction": "kokand", "tab": "economy", "kind": "dam",
		"size": Vector2(10, 6), "hp": 2500, "cost": {"wood": 80, "stone": 40}, "build_time": 30,
		"flags": ["network", "blocks", "territory"], "territory_r": 40.0,
		"place": {"across_river": true, "water": true, "territory": false},
		"network": {"kind": "water", "source": true, "places": 8, "range": 400.0, "dry_s": 20},
		"rebuild": {"cost": {"wood": 40, "stone": 20}, "time": 15}, "raid_value": 5},
	"aryk": {"name": "Ариқ", "faction": "kokand", "tab": "economy", "kind": "link",
		"size": Vector2(4, 2), "hp": 100, "cost": {"wood": 2}, "build_time": 3, "flags": ["network", "walkable", "unbreakable", "territory"],
		"territory_r": 24.0, "place": {"territory": false}, "link": {"len": 4.0, "overlap": 0.0}, "network": {"kind": "water", "zone": 24.0},
		"model": "ariq", "render": "multimesh"},
	# Хумдон: 3 работника × 12 ғишт в минуту, 0,5 дерева на кирпич; только в зоне воды (ECONOMY §2.4)
	"xumdon": {"name": "Хумдон", "faction": "kokand", "tab": "economy", "kind": "building",
		"size": Vector2(10, 8), "hp": 1000, "cost": {"wood": 120, "stone": 60}, "build_time": 35,
		"flags": ["drop", "blocks"], "accepts": ["brick"], "recipes": ["brick"], "water_place": 1,
		"place": {"water_zone": true}, "raid_value": 2},
	# Бозор: подать с домов и обмен по постоянному курсу (ECONOMY §2.5, GameRules.market)
	"bozor": {"name": "Бозор", "faction": "kokand", "tab": "economy", "kind": "building",
		"size": Vector2(16, 16), "hp": 1600, "cost": {"wood": 150, "stone": 80}, "build_time": 45,
		"flags": ["market", "blocks"], "max_per_player": 1, "raid_value": 3},
	"kazarma": {"name": "Казарма", "faction": "kokand", "tab": "economy", "kind": "building",
		"size": Vector2(16, 12), "hp": 1800, "cost": {"wood": 200, "stone": 100}, "build_time": 50,
		"flags": ["blocks"], "raid_value": 1},
	"otxona": {"name": "Отхона", "faction": "kokand", "tab": "economy", "kind": "building",
		"size": Vector2(16, 12), "hp": 1700, "cost": {"wood": 220, "stone": 60}, "build_time": 50,
		"flags": ["blocks"], "otlar": {"cap": 20, "discount_gold": 25, "overflow_gold": 20}, "raid_value": 2},
	"topxona": {"name": "Тўпхона", "faction": "kokand", "tab": "economy", "kind": "building",
		"size": Vector2(14, 12), "hp": 2200, "cost": {"wood": 200, "stone": 200, "gold": 100}, "build_time": 60,
		"flags": ["blocks"], "raid_value": 1},
	# Сб. 2: кузница (улучшения ECONOMY §1.8)
	"temirchixona": {"name": "Темирчихона", "faction": "kokand", "tab": "economy", "kind": "building",
		"size": Vector2(10, 10), "hp": 1200, "cost": {"wood": 150, "stone": 50}, "build_time": 40,
		"flags": ["blocks"], "raid_value": 1, "enabled": false},
	# ================================================================ Коканд — укрепления (ТЗ 6, ECONOMY §2.9)
	# Башни — в Сб. 1 (решение ведущего 2026-10-13); стены и ворота — этап 2: enabled false
	"devor": {"name": "Пахса девор", "faction": "kokand", "tab": "fort", "kind": "wall",
		"size": Vector2(3.6, 1.8), "hp": 420, "cost": {"wood": 3}, "build_time": 4, "flags": ["blocks"],
		"link": {"len": 3.6, "overlap": 0.4}, "render": "multimesh", "enabled": false},
	"tosh": {"name": "Тош девор", "faction": "kokand", "tab": "fort", "kind": "wall",
		"size": Vector2(3.6, 2.2), "hp": 1200, "cost": {"brick": 6, "stone": 2}, "build_time": 8, "flags": ["blocks"],
		"requires": ["xumdon"], "link": {"len": 3.6, "overlap": 0.4}, "render": "multimesh", "enabled": false},
	"darvoza": {"name": "Дарвоза", "faction": "kokand", "tab": "fort", "kind": "gate",
		"size": Vector2(7.2, 3), "hp": 1600, "cost": {"wood": 40, "stone": 30}, "build_time": 25, "flags": ["blocks"],
		"place": {"on_wall": "align"}, "enabled": false},
	"burj": {"name": "Бурж", "faction": "kokand", "tab": "fort", "kind": "tower",
		"size": Vector2(7, 7), "hp": 2000, "cost": {"wood": 30, "stone": 30, "brick": 50}, "build_time": 45,
		"flags": ["blocks"], "requires": ["xumdon"],
		"garrison": {"cap": 10, "range_mult": 1.3, "absorb": 0.55, "stone_range": 32.0, "platform_h": 8.4},
		"place": {"on_wall": "replace"}},
	# ================================================================ Кыпчаки — лагерь (ТЗ 5.3, 5.4, ECONOMY §3.1)
	"ordo": {"name": "Хан ордосу", "faction": "kipchak", "tab": "", "kind": "building",
		"size": Vector2(14, 14), "hp": 2500, "cost": {}, "build_time": 0,
		"flags": ["hq", "drop", "blocks", "territory", "round", "packable"],
		"accepts": ["food", "wood", "stone", "gold", "felt"],
		"pop_cap": 25, "territory_r": 90.0, "shelter": 20, "unpack_s": 30, "arbas": 2,
		# коновязь: до 10 коней без приплода; с первым Жылкы короосу они уходят туда (ECONOMY §3.3)
		"herd": {"htype": "horse", "start": 6, "cap": 10, "breed": false}, "raid_value": 0.5},
	"boz": {"name": "Боз үй", "faction": "kipchak", "tab": "economy", "kind": "building",
		"size": Vector2(7, 7), "hp": 300, "cost": {"wood": 40}, "build_time": 12,
		"flags": ["house", "blocks", "round", "packable", "territory"], "territory_r": 30.0, "pop_cap": 10, "shelter": 3,
		"unpack_s": 12,
		"render": "multimesh", "raid_value": 1},
	# Короо: еда = (54 + 18 × пастухи) × трава × отара / 40; не больше 10 (ECONOMY §3.4)
	"koroo": {"name": "Короо", "faction": "kipchak", "tab": "economy", "kind": "building",
		"size": Vector2(14, 14), "hp": 400, "cost": {"wood": 60}, "build_time": 20,
		"flags": ["pen", "blocks", "packable", "territory"], "territory_r": 30.0,
		"herd": {"htype": "sheep", "start": 40, "cap": 40, "breed": true},
		"work": {"res": "food", "slots": 2, "per_worker_min": 18, "carry_to": []},
		"max_per_player": 10, "unpack_s": 15, "raid_value": 4},
	# Кен не сворачивается (ECONOMY §3)
	"ken": {"name": "Кен", "faction": "kipchak", "tab": "economy", "kind": "building",
		"size": Vector2(8, 8), "hp": 400, "cost": {"wood": 80}, "build_time": 15,
		"flags": ["drop", "blocks"], "accepts": ["stone", "gold"],
		"place": {"near": {"nodes": ["stone", "gold"], "r": 26.0}, "territory": false},
		"aura": {"gather_mult": 1.5, "r": 26.0, "res": ["stone", "gold"]}, "raid_value": 3},
	"jooker": {"name": "Жоокер үйү", "faction": "kipchak", "tab": "economy", "kind": "building",
		"size": Vector2(12, 10), "hp": 800, "cost": {"wood": 120}, "build_time": 30,
		"flags": ["blocks", "packable"], "unpack_s": 20, "raid_value": 1},
	"jylky": {"name": "Жылкы короосу", "faction": "kipchak", "tab": "economy", "kind": "building",
		"size": Vector2(16, 12), "hp": 800, "cost": {"wood": 150, "gold": 40}, "build_time": 35,
		"flags": ["pen", "blocks", "packable"], "herd": {"htype": "horse", "start": 0, "cap": 30, "breed": true},
		"unpack_s": 20, "raid_value": 4},
	"kurultai": {"name": "Курултай", "faction": "kipchak", "tab": "economy", "kind": "building",
		"size": Vector2(14, 14), "hp": 1600, "cost": {"wood": 200, "gold": 150}, "build_time": 60,
		"flags": ["blocks", "round", "packable"], "unpack_s": 30, "arbas": 2, "raid_value": 1},
	# Сб. 2: войлок и кузница (ECONOMY §3.5, §1.8); модель — kiyizchi (ECONOMY §11.3)
	"kiyiz": {"name": "Кийизчи үй", "faction": "kipchak", "tab": "economy", "kind": "building",
		"size": Vector2(8, 8), "hp": 300, "cost": {"wood": 60}, "build_time": 15,
		"flags": ["blocks", "round", "packable"], "recipes": ["felt"], "unpack_s": 12, "model": "kiyizchi",
		"raid_value": 2, "enabled": false},
	"temirchi": {"name": "Темирчи үй", "faction": "kipchak", "tab": "economy", "kind": "building",
		"size": Vector2(9, 9), "hp": 500, "cost": {"wood": 120, "gold": 40}, "build_time": 30,
		"flags": ["blocks", "round", "packable"], "unpack_s": 12, "raid_value": 1, "enabled": false},
	# ================================================================ Кыпчаки — укрепления (ТЗ 6, ECONOMY §3.9)
	# Күзөт мунарасы — в Сб. 1; частокол и ворота — этап 2: enabled false
	"chep": {"name": "Жыгач чеп", "faction": "kipchak", "tab": "fort", "kind": "wall",
		"size": Vector2(3.4, 1.2), "hp": 260, "cost": {"wood": 5}, "build_time": 3, "flags": ["blocks"],
		"link": {"len": 3.4, "overlap": 0.4}, "render": "multimesh", "enabled": false},
	"darbaza": {"name": "Дарбаза", "faction": "kipchak", "tab": "fort", "kind": "gate",
		"size": Vector2(6.4, 2.4), "hp": 700, "cost": {"wood": 45}, "build_time": 20, "flags": ["blocks"],
		"place": {"on_wall": "align"}, "enabled": false},
	"munara": {"name": "Күзөт мунарасы", "faction": "kipchak", "tab": "fort", "kind": "tower",
		"size": Vector2(5, 5), "hp": 700, "cost": {"wood": 70}, "build_time": 30, "flags": ["blocks", "packable"],
		"garrison": {"cap": 6, "range_mult": 1.3, "absorb": 0.55, "stone_range": 32.0, "platform_h": 7.0},
		"place": {"on_wall": "replace"}, "unpack_s": 15},
}
