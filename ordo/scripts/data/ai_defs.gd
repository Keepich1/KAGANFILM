class_name AiDefs
## ИИ набегов и базы (ТЗ 7; ARCHITECTURE §12; docs/ECONOMY.md §9.1, §10, §12.1). Схема — ведущий (M0),
## значения — GAME. difficulty — индекс в списках по сложности (peace_s[difficulty]: 5, 8 или 12 мин).
##
## RAID:
##   peace_s [difficulty] — мирный период, с; interval_s [от, до] — между волнами;
##   growth — во сколько раз крупнее каждая следующая волна; max_wave — предел бойцов в волне;
##   first_wave {сторона налётчика: {юнит: число}} — состав первой волны; officer_per — офицер на столько бойцов;
##   values — очки целей «ценность минус риск» (ECONOMY §10): togon_per_field (× полей в сети), worker,
##     taloo_frac (× запаса склада), horse (× коней), house; risk_r — охрана в этом радиусе;
##     skip_guard — цель пропускается, если охрана сильнее отряда во столько раз; tower_penalty — за башню;
##   retreat {losses — доля потерь, stamina — ниже этой выносливости, outnumbered, time_s — предел набега};
##   warn_s — за сколько секунд RAID_WARNING; period — раз в сколько тактов думает ИИ (1 Гц);
##   difficulty {gather_mult, alarm_s} — по сложности.
## BASE {сторона: {buildings {постройка: число}, herds, towers}} — база ИИ, чтобы было что грабить (ECONOMY §12.1).
## GARRISON — защита базы ИИ: радиус базы, отряды у ставки.

const RAID := {
	"peace_s": [300, 480, 720],
	"interval_s": [150, 240],
	"growth": 1.25,
	"max_wave": 120,
	"first_wave": {
		"kipchak": {"chabuulchu": 10},
		"kokand": {"navkar": 6, "kilichboz": 8},
	},
	"officer_per": 100,
	"values": {"togon_per_field": 100.0, "worker": 10.0, "taloo_frac": 0.1, "horse": 20.0, "house": 20.0},
	"risk_r": 60.0,
	"skip_guard": 1.5,
	"tower_penalty": 40.0,
	"retreat": {"losses": 0.4, "stamina": 30.0, "outnumbered": 1.5, "time_s": 240},
	"warn_s": 30,
	"period": 30,
	"difficulty": {"gather_mult": [0.8, 1.0, 1.2], "alarm_s": [6, 3, 1]},
}

const BASE := {
	"kokand": {"buildings": {"togon": 1, "dala": 6, "xumdon": 1, "bozor": 1, "uy": 4, "tegirmon": 1, "ombor": 1},
		"towers": {"burj": 2}, "tower_garrison": {"kamonchi": 10}},
	"kipchak": {"buildings": {"koroo": 6, "jylky": 2, "boz": 6}, "herds": {"horse": 20},
		"towers": {"munara": 2}, "tower_garrison": {"mergen": 6}},
}

const GARRISON := {
	"base_r": 90.0,
	"squads": {"kokand": {"sarboz": 20, "nayzachi": 20}, "kipchak": {"jooker": 20, "mergen": 15}},
	"period": 30,
}
