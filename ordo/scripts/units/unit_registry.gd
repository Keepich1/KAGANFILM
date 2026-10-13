class_name UnitRegistry
extends RefCounted
## Реестр юнитов толпы: скелет, оружие, размеры и сторона (для боя, расстановки, полосок здоровья).
##
##   var u := UnitRegistry.info("kok_sarboz")      # {"skeleton": "human", "weapon": "musket", ...}
##   var path := UnitRegistry.mesh_path("kip_sayisker", 1)   # облегчённая модель
##
## Поля записи:
##   skeleton — "human" | "rider" | "sheep" | "horse" (состояния: AnimSpec.Human / Horse / Sheep;
##              у "horse" — AnimSpec.Horse без всадника)
##   weapon   — "musket" | "saber" | "lance" | "sword" | "mace" | "staff" | "tool" | "none"
##              ("tool" — работник: топор, кетмень, молот, ноша — по WORK, см. crowd_human.gdshaderinc)
##   height   — высота фигуры с шапкой, м (над ней — полоска здоровья)
##   top      — самая высокая точка (знамя, копьё), м
##   radius   — радиус пятна на земле, м (для расталкивания и выделения)
##   side     — "kokand" | "kipchak" | "neutral"
##   item     — "none" | "shield" | "ramrod" | "sack" (вторая рука)
##   banner   — знаменосец: в правой руке древко (стрелять не может, машет знаменем)
##   scale    — масштаб модели (необязательно, по умолчанию 1; полководец 1.1 — крупнее)
##   name     — подпись в интерфейсе

const UNITS := {
	"kok_sarboz": {"skeleton": "human", "weapon": "musket", "height": 2.14, "top": 2.14, "radius": 0.35,
		"side": "kokand", "item": "ramrod", "banner": false, "name": "Сарбоз"},
	"kok_sarboz_banner": {"skeleton": "human", "weapon": "musket", "height": 2.14, "top": 3.62, "radius": 0.4,
		"side": "kokand", "item": "none", "banner": true, "name": "Сарбоз-знаменосец"},
	"kok_yuzboshi": {"skeleton": "rider", "weapon": "saber", "height": 2.78, "top": 2.78, "radius": 0.9,
		"side": "kokand", "item": "none", "banner": false, "name": "Юзбоши"},
	"kip_sayisker": {"skeleton": "rider", "weapon": "lance", "height": 2.75, "top": 4.11, "radius": 0.9,
		"side": "kipchak", "item": "shield", "banner": false, "name": "Сайыскер"},
	"kip_sayisker_banner": {"skeleton": "rider", "weapon": "lance", "height": 2.75, "top": 4.58, "radius": 0.9,
		"side": "kipchak", "item": "shield", "banner": true, "name": "Сайыскер-туугчу"},
	"kip_kolbashchy": {"skeleton": "rider", "weapon": "mace", "height": 3.3, "top": 3.3, "radius": 1.05,
		"side": "kipchak", "item": "none", "banner": false, "scale": 1.1, "name": "Колбашчы"},
	"kip_jooker": {"skeleton": "human", "weapon": "sword", "height": 2.07, "top": 2.07, "radius": 0.38,
		"side": "kipchak", "item": "shield", "banner": false, "name": "Жөө жоокер"},
	"kip_malchy": {"skeleton": "human", "weapon": "staff", "height": 2.07, "top": 2.07, "radius": 0.35,
		"side": "kipchak", "item": "sack", "banner": false, "name": "Малчы"},
	"kok_dehqon": {"skeleton": "human", "weapon": "tool", "height": 1.84, "top": 1.84, "radius": 0.35,
		"side": "kokand", "item": "sack", "banner": false, "name": "Деҳқон"},
	"sheep": {"skeleton": "sheep", "weapon": "none", "height": 0.84, "top": 0.84, "radius": 0.45,
		"side": "neutral", "item": "none", "banner": false, "name": "Кой"},
	"horse": {"skeleton": "horse", "weapon": "none", "height": 2.06, "top": 2.06, "radius": 0.9,
		"side": "neutral", "item": "none", "banner": false, "name": "Жылкы"},
}

## Номера для uniform шейдера толпы (shaders/crowd.gdshader)
const SKELETON_ID := {"human": 0, "rider": 1, "sheep": 2, "horse": 3}
const WEAPON_ID := {"musket": 0, "saber": 1, "lance": 2, "sword": 3, "mace": 4, "staff": 5, "none": 6, "tool": 7}
const ITEM_ID := {"none": 0, "shield": 1, "ramrod": 2, "sack": 3}

const MODEL_DIR := "res://assets/models/units/"


static func info(unit_id: String) -> Dictionary:
	if not UNITS.has(unit_id):
		push_error("UnitRegistry: неизвестный юнит «%s»" % unit_id)
		return {}
	return UNITS[unit_id]


static func mesh_path(unit_id: String, lod := 0) -> String:
	return MODEL_DIR + unit_id + ("_lod1" if lod > 0 else "") + ".glb"


static func has(unit_id: String) -> bool:
	return UNITS.has(unit_id)


static func ids() -> Array:
	return UNITS.keys()
