class_name AiDefs
## ИИ набегов (ТЗ 7; ARCHITECTURE §12). Схема — ведущий (M0), значения — GAME.
## difficulty — индекс в списках по сложности (peace_s[difficulty]: 5, 8 или 12 мин).
##
## RAID:
##   peace_s [difficulty] — мирный период, с (ТЗ 7: 5, 8 или 12 мин); interval_s [от, до] — между волнами;
##   growth — во сколько раз крупнее каждая следующая волна; max_wave — предел бойцов в волне;
##   first_wave {сторона налётчика: {юнит: число}} — состав первой волны; officer_per — офицер на столько бойцов;
##   weights — ценность целей (тепловая карта 32 м): worker, herd, field, store, house, hq;
##   tower_penalty — вычет за прикрытие башней; defender_r — свои защитники в этом радиусе вычитаются;
##   retreat {losses — доля потерь, outnumbered — защитников больше во столько раз, time_s — предел набега};
##   warn_s — за сколько секунд RAID_WARNING; period — раз в сколько тактов думает ИИ (1 Гц).
## GARRISON: защита базы ИИ — радиус базы, отряды у ставки.

const RAID := {
	"peace_s": [300, 480, 720],
	"interval_s": [150, 240],
	"growth": 1.25,
	"max_wave": 120,
	"first_wave": {
		"kipchak": {"chabuulchu": 8, "jooker": 6},
		"kokand": {"navkar": 6, "kilichboz": 8},
	},
	"officer_per": 100,
	"weights": {"worker": 5.0, "herd": 4.0, "field": 3.0, "store": 3.0, "house": 1.0, "hq": 0.5},
	"tower_penalty": 4.0,
	"defender_r": 60.0,
	"retreat": {"losses": 0.5, "outnumbered": 1.5, "time_s": 240},
	"warn_s": 30,
	"period": 30,
}

const GARRISON := {
	"base_r": 90.0,
	"squads": {"kokand": {"sarboz": 20, "nayzachi": 20}, "kipchak": {"jooker": 20, "mergen": 15}},
	"period": 30,
}
