class_name UnitStats
extends RefCounted
## Характеристики всех юнитов обеих фракций (ТЗ 3.1, 3.2) — данные для симуляции боя.
##
##   var s := UnitStats.get_stats("sarboz")   # {"hp": 100, "speed": 3.4, ...}
##   UnitStats.has_flag("sayisker", UnitStats.MOUNTED)
##
## Поля записи:
##   name, faction ("kokand" | "kipchak"), role — подписи
##   hp, speed (максимум: бег или галоп, м/с), walk (доля скорости шагом: пехота 0.62, конница 0.5)
##   armour — вычитается из урона; attack — урон в рукопашной; reach — досягаемость, м
##   charge — множитель натиска (1 — нет натиска); vs_cav — множитель урона по коннице
##   missile — урон выстрела/стрелы; range, min_range — м; reload — с; ammo — запас (-1 — без счёта)
##   acc_near, acc_far — точность вблизи и на пределе дальности; splash — радиус, м; vs_building — множитель
##   flags — биты ниже; formations — доступные построения (BattleSim.Formation)
##   cost — {food, wood, stone, gold}; time — время найма, с
##   visual — вид юнита для толпы (UnitRegistry/CrowdLayer), "" — модели пока нет
##   radius — радиус пятна на земле, м; mass — «вес» при расталкивании
## Значения, которых нет в ТЗ (рукопашная стрелков, перезарядка пушки, точность луков),
## помечены «[Свободно]» — это стартовые предложения, их можно менять.

## Флаги
const MOUNTED := 1
const SPEAR := 2        # копья: держат натиск, ×vs_cav по коннице
const SHIELD := 4       # щит: стрелы вдвое слабее
const GENERAL := 8      # полководец: аура морали, боевой клич
const OFFICER := 16     # офицер отряда (гибель: −30 морали)
const WORKER := 32      # работник: не бежит
const KACHYP := 64      # «качып атуу» — стреляет на отходе
const MUSKET := 128     # огнестрел: дым, пробитие, «конь падает»
const BOW := 256
const CANNON := 512
const WAGON := 1024
const LOOSE := 2048     # предпочитает рассыпной строй
const RAIDER := 4096    # налёты на работников и экономику

## Построения (совпадают с BattleSim.Formation)
const F_LINE := 0
const F_COLUMN := 1
const F_SQUARE := 2
const F_LOOSE := 3

const _INF := [F_LINE, F_COLUMN, F_SQUARE, F_LOOSE]
const _SHOOT := [F_LINE, F_COLUMN, F_LOOSE]
const _CAV := [F_LINE, F_COLUMN, F_LOOSE]
const _NONE := []

const UNITS := {
	# ---------------------------------------------------------------- Коканд (ТЗ 3.1)
	"dehqon": {"name": "Деҳқон", "faction": "kokand", "role": "работник",
		"hp": 60, "speed": 3.8, "walk": 0.62, "armour": 0, "attack": 4, "reach": 1.2, "charge": 1.0, "vs_cav": 1.0,
		"missile": 0, "range": 0, "min_range": 0, "reload": 0, "ammo": -1, "acc_near": 0.0, "acc_far": 0.0,
		"splash": 0, "vs_building": 1.0, "flags": WORKER, "formations": _NONE,
		"cost": {"food": 50}, "time": 7, "visual": "", "radius": 0.35, "mass": 1.0},
	"yuzboshi": {"name": "Юзбоши", "faction": "kokand", "role": "конный офицер",
		"hp": 170, "speed": 8.5, "walk": 0.5, "armour": 4, "attack": 16, "reach": 1.8, "charge": 2.0, "vs_cav": 1.0,
		"missile": 0, "range": 0, "min_range": 0, "reload": 0, "ammo": -1, "acc_near": 0.0, "acc_far": 0.0,
		"splash": 0, "vs_building": 1.0, "flags": MOUNTED | OFFICER, "formations": _NONE, "squad_max": 100,
		"cost": {"food": 60, "gold": 60}, "time": 14, "visual": "kok_yuzboshi", "radius": 0.9, "mass": 6.0},
	"sarboz": {"name": "Сарбозлар", "faction": "kokand", "role": "пехота с мылтыками",
		# рукопашная прикладом — 9 [Свободно]
		"hp": 100, "speed": 3.4, "walk": 0.62, "armour": 1, "attack": 9, "reach": 1.3, "charge": 1.0, "vs_cav": 1.0,
		"missile": 50, "range": 90, "min_range": 0, "reload": 11.0, "ammo": -1, "acc_near": 0.45, "acc_far": 0.08,
		"splash": 0, "vs_building": 0.3, "flags": MUSKET, "formations": _INF,
		"cost": {"food": 30, "wood": 10, "gold": 25}, "time": 9, "visual": "kok_sarboz", "radius": 0.4, "mass": 1.0},
	"zarbzan": {"name": "Зарбзанлар", "faction": "kokand", "role": "лёгкие пушки",
		# перезарядка 9 с, точность — [Свободно]
		"hp": 220, "speed": 2.3, "walk": 0.62, "armour": 4, "attack": 6, "reach": 1.2, "charge": 1.0, "vs_cav": 1.0,
		"missile": 100, "range": 300, "min_range": 30, "reload": 9.0, "ammo": -1, "acc_near": 0.6, "acc_far": 0.2,
		"splash": 5.5, "vs_building": 3.0, "flags": CANNON, "formations": _NONE,
		"cost": {"wood": 150, "gold": 120}, "time": 25, "visual": "", "radius": 1.4, "mass": 8.0},
	"kamonchi": {"name": "Камончилар", "faction": "kokand", "role": "пешие лучники",
		# рукопашная 8, точность — [Свободно]
		"hp": 90, "speed": 3.6, "walk": 0.62, "armour": 1, "attack": 8, "reach": 1.2, "charge": 1.0, "vs_cav": 1.0,
		"missile": 13, "range": 125, "min_range": 0, "reload": 4.2, "ammo": 24, "acc_near": 0.6, "acc_far": 0.15,
		"splash": 0, "vs_building": 0.3, "flags": BOW, "formations": _SHOOT,
		"cost": {"food": 30, "wood": 25}, "time": 8, "visual": "", "radius": 0.35, "mass": 1.0},
	"nayzachi": {"name": "Найзачилар", "faction": "kokand", "role": "копейщики",
		"hp": 120, "speed": 3.5, "walk": 0.62, "armour": 3, "attack": 15, "reach": 2.8, "charge": 1.0, "vs_cav": 2.4,
		"missile": 0, "range": 0, "min_range": 0, "reload": 0, "ammo": -1, "acc_near": 0.0, "acc_far": 0.0,
		"splash": 0, "vs_building": 1.0, "flags": SPEAR, "formations": _INF,
		"cost": {"food": 30, "wood": 20}, "time": 8, "visual": "", "radius": 0.38, "mass": 1.2},
	"kilichboz": {"name": "Киличбозлар", "faction": "kokand", "role": "мечники со щитами",
		"hp": 130, "speed": 3.7, "walk": 0.62, "armour": 4, "attack": 17, "reach": 1.3, "charge": 1.0, "vs_cav": 1.0,
		"missile": 0, "range": 0, "min_range": 0, "reload": 0, "ammo": -1, "acc_near": 0.0, "acc_far": 0.0,
		"splash": 0, "vs_building": 1.0, "flags": SHIELD, "formations": _INF,
		"cost": {"food": 35, "gold": 20}, "time": 9, "visual": "", "radius": 0.4, "mass": 1.2},
	"navkar": {"name": "Навкарлар", "faction": "kokand", "role": "конница с саблями",
		"hp": 150, "speed": 9.0, "walk": 0.5, "armour": 3, "attack": 17, "reach": 1.8, "charge": 2.2, "vs_cav": 1.0,
		"missile": 0, "range": 0, "min_range": 0, "reload": 0, "ammo": -1, "acc_near": 0.0, "acc_far": 0.0,
		"splash": 0, "vs_building": 1.0, "flags": MOUNTED, "formations": _CAV,
		"cost": {"food": 60, "gold": 45}, "time": 12, "visual": "", "radius": 0.9, "mass": 6.0},
	"xos_navkar": {"name": "Хос навкарлар", "faction": "kokand", "role": "сверхтяжёлая гвардия",
		"hp": 280, "speed": 7.6, "walk": 0.5, "armour": 7, "attack": 24, "reach": 1.8, "charge": 3.2, "vs_cav": 1.0,
		"missile": 0, "range": 0, "min_range": 0, "reload": 0, "ammo": -1, "acc_near": 0.0, "acc_far": 0.0,
		"splash": 0, "vs_building": 1.0, "flags": MOUNTED, "formations": _CAV,
		"cost": {}, "time": 0, "visual": "", "radius": 0.95, "mass": 7.0},
	"lashkarboshi": {"name": "Лашкарбоши", "faction": "kokand", "role": "полководец",
		"hp": 280, "speed": 7.6, "walk": 0.5, "armour": 7, "attack": 24, "reach": 1.8, "charge": 3.2, "vs_cav": 1.0,
		"missile": 0, "range": 0, "min_range": 0, "reload": 0, "ammo": -1, "acc_near": 0.0, "acc_far": 0.0,
		"splash": 0, "vs_building": 1.0, "flags": MOUNTED | GENERAL, "formations": _NONE,
		"cost": {}, "time": 0, "visual": "", "radius": 1.0, "mass": 7.0},
	# ---------------------------------------------------------------- Кыпчаки (ТЗ 3.2)
	"malchy": {"name": "Малчы", "faction": "kipchak", "role": "работник",
		"hp": 65, "speed": 4.0, "walk": 0.62, "armour": 0, "attack": 5, "reach": 1.2, "charge": 1.0, "vs_cav": 1.0,
		"missile": 0, "range": 0, "min_range": 0, "reload": 0, "ammo": -1, "acc_near": 0.0, "acc_far": 0.0,
		"splash": 0, "vs_building": 1.0, "flags": WORKER, "formations": _NONE,
		"cost": {"food": 45}, "time": 6, "visual": "kip_malchy", "radius": 0.35, "mass": 1.0},
	"juz_bashy": {"name": "Жүз башы", "faction": "kipchak", "role": "конный сотник",
		# своей модели пока нет — рисуется как сайыскер
		"hp": 170, "speed": 9.0, "walk": 0.5, "armour": 4, "attack": 16, "reach": 1.8, "charge": 2.0, "vs_cav": 1.0,
		"missile": 0, "range": 0, "min_range": 0, "reload": 0, "ammo": -1, "acc_near": 0.0, "acc_far": 0.0,
		"splash": 0, "vs_building": 1.0, "flags": MOUNTED | OFFICER, "formations": _NONE, "squad_max": 100,
		"cost": {"food": 60, "gold": 50}, "time": 12, "visual": "kip_sayisker", "radius": 0.9, "mass": 6.0},
	"arba": {"name": "Арба", "faction": "kipchak", "role": "свёрнутая юрта в пути",
		"hp": 260, "speed": 3.4, "walk": 0.62, "armour": 3, "attack": 0, "reach": 0.0, "charge": 1.0, "vs_cav": 1.0,
		"missile": 0, "range": 0, "min_range": 0, "reload": 0, "ammo": -1, "acc_near": 0.0, "acc_far": 0.0,
		"splash": 0, "vs_building": 1.0, "flags": WAGON | WORKER, "formations": _NONE,
		"cost": {}, "time": 0, "visual": "", "radius": 1.6, "mass": 10.0},
	"atchan": {"name": "Атчан жаачылар", "faction": "kipchak", "role": "конные лучники",
		# стрела 14; сабля 12; точность — [Свободно]
		"hp": 115, "speed": 9.5, "walk": 0.5, "armour": 1, "attack": 12, "reach": 1.8, "charge": 1.0, "vs_cav": 1.0,
		"missile": 14, "range": 100, "min_range": 0, "reload": 3.0, "ammo": 15, "acc_near": 0.55, "acc_far": 0.12,
		"splash": 0, "vs_building": 0.3, "flags": MOUNTED | BOW | KACHYP, "formations": _CAV,
		"cost": {"food": 40, "gold": 20}, "time": 9, "visual": "", "radius": 0.9, "mass": 5.0},
	"jooker": {"name": "Жөө жоокерлер", "faction": "kipchak", "role": "пехота с мечом и щитом",
		"hp": 115, "speed": 3.8, "walk": 0.62, "armour": 3, "attack": 15, "reach": 1.3, "charge": 1.0, "vs_cav": 1.0,
		"missile": 0, "range": 0, "min_range": 0, "reload": 0, "ammo": -1, "acc_near": 0.0, "acc_far": 0.0,
		"splash": 0, "vs_building": 1.0, "flags": SHIELD, "formations": _INF,
		"cost": {"food": 30, "wood": 15}, "time": 7, "visual": "kip_jooker", "radius": 0.4, "mass": 1.2},
	"mergen": {"name": "Мергендер", "faction": "kipchak", "role": "меткие пешие стрелки",
		# рукопашная 7, точность — [Свободно]
		"hp": 85, "speed": 4.0, "walk": 0.62, "armour": 0, "attack": 7, "reach": 1.2, "charge": 1.0, "vs_cav": 1.0,
		"missile": 20, "range": 135, "min_range": 0, "reload": 4.5, "ammo": 20, "acc_near": 0.7, "acc_far": 0.2,
		"splash": 0, "vs_building": 0.3, "flags": BOW | LOOSE, "formations": _SHOOT,
		"cost": {"food": 30, "wood": 30}, "time": 9, "visual": "", "radius": 0.35, "mass": 1.0},
	"sayisker": {"name": "Сайыскерлер", "faction": "kipchak", "role": "тяжёлые конные копейщики",
		"hp": 200, "speed": 9.0, "walk": 0.5, "armour": 4, "attack": 19, "reach": 2.4, "charge": 3.0, "vs_cav": 1.0,
		"missile": 0, "range": 0, "min_range": 0, "reload": 0, "ammo": -1, "acc_near": 0.0, "acc_far": 0.0,
		"splash": 0, "vs_building": 1.0, "flags": MOUNTED, "formations": _CAV,
		"cost": {"food": 60, "gold": 50}, "time": 12, "visual": "kip_sayisker", "radius": 0.9, "mass": 6.0},
	"chabuulchu": {"name": "Чабуулчулар", "faction": "kipchak", "role": "лёгкая конница",
		"hp": 110, "speed": 11.0, "walk": 0.5, "armour": 1, "attack": 13, "reach": 1.8, "charge": 1.8, "vs_cav": 1.0,
		"missile": 0, "range": 0, "min_range": 0, "reload": 0, "ammo": -1, "acc_near": 0.0, "acc_far": 0.0,
		"splash": 0, "vs_building": 1.0, "flags": MOUNTED | RAIDER, "formations": _CAV,
		"cost": {"food": 40, "wood": 10}, "time": 8, "visual": "", "radius": 0.85, "mass": 5.0},
	"batyr": {"name": "Батырлар", "faction": "kipchak", "role": "сверхтяжёлая гвардия",
		"hp": 290, "speed": 7.8, "walk": 0.5, "armour": 7, "attack": 25, "reach": 1.8, "charge": 3.2, "vs_cav": 1.0,
		"missile": 0, "range": 0, "min_range": 0, "reload": 0, "ammo": -1, "acc_near": 0.0, "acc_far": 0.0,
		"splash": 0, "vs_building": 1.0, "flags": MOUNTED, "formations": _CAV,
		"cost": {"food": 100, "gold": 100}, "time": 18, "visual": "", "radius": 0.95, "mass": 7.0},
	"kolbashchy": {"name": "Колбашчы", "faction": "kipchak", "role": "полководец",
		"hp": 290, "speed": 7.8, "walk": 0.5, "armour": 7, "attack": 25, "reach": 1.8, "charge": 3.2, "vs_cav": 1.0,
		"missile": 0, "range": 0, "min_range": 0, "reload": 0, "ammo": -1, "acc_near": 0.0, "acc_far": 0.0,
		"splash": 0, "vs_building": 1.0, "flags": MOUNTED | GENERAL, "formations": _NONE,
		"cost": {"food": 100, "gold": 100}, "time": 18, "visual": "kip_kolbashchy", "radius": 1.05, "mass": 7.0},
}

## Знаменосец отряда рисуется своим видом (флаг в руке), характеристики — как у бойцов
const BANNER_VISUAL := {"sarboz": "kok_sarboz_banner", "sayisker": "kip_sayisker_banner"}


static func get_stats(type_id: String) -> Dictionary:
	return UNITS.get(type_id, {})


static func has_flag(type_id: String, flag: int) -> bool:
	return int(UNITS.get(type_id, {}).get("flags", 0)) & flag != 0


## Вид для толпы: знаменосец — свой вид, остальные — поле visual
static func visual_for(type_id: String, banner := false) -> String:
	if banner and BANNER_VISUAL.has(type_id):
		return BANNER_VISUAL[type_id]
	return String(UNITS.get(type_id, {}).get("visual", ""))


## Все юниты фракции
static func of_faction(faction: String) -> PackedStringArray:
	var out := PackedStringArray()
	for k in UNITS:
		if UNITS[k]["faction"] == faction:
			out.append(k)
	return out
