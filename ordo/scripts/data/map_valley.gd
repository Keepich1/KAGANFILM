class_name MapValley
## Карта «Долина» для «Города» (ТЗ 8; CONTRACT §3; ARCHITECTURE §6.4). Схема — ведущий (M0),
## значения — GAME. Земля — assets/world/height.json (1024 × 1024 м, центр (0, 0)).
## Координаты — (x, z) мира, м; rot_q — четверть оборота (фасад +Z повёрнут на rot_q · 90°).
##
##   sites      — стартовые места: faction (для какой стороны), hq + hq_rot_q, buildings [[id, (x, z), rot_q]],
##                workers — где стоят стартовые работники (FactionDefs.start_units)
##                Кыпчаки — раскладка лагеря среза (CONTRACT §3; Terrain.marker camp/koroo/jylky);
##                Коканд — урда на восточном лугу (ровное место за полем боя)
##   trees      — "scatter": деревья карты из ScatterData (порядок файла → scatter_ref)
##   deposits   — залежи [[узел NodeDefs, (x, z)]] (ТЗ 8: 5 камня и 5 золота)
##   clay       — глиняные ямы у реки (ECONOMY.md)
##   dam_sites  — где реку можно перегородить запрудой (арыки Коканда)
##   raid_edges — края карты, откуда приходят набеги
##   zones      — пастбища сезонов: jailoo / kyshtoo [Vector3(x, z, r)]
##   ai_base    — база ИИ (ТЗ 7): башни по сторонам и их места относительно ставки

const MAP := {
	"id": "valley",
	"name": "Долина",
	"bounds": Rect2(-512, -512, 1024, 1024),
	"sites": [
		{"faction": "kipchak", "hq": Vector2(-60, 20), "hq_rot_q": 0,
			"buildings": [
				["boz", Vector2(-23.88, 30.53), 0], ["boz", Vector2(-28.98, 12.24), 0],
				["boz", Vector2(-36.52, -11.22), 0], ["boz", Vector2(-51.31, -17.11), 0],
				["boz", Vector2(-74.30, -19.38), 0], ["boz", Vector2(-89.98, 0.84), 0],
				["boz", Vector2(-99.72, 13.64), 0], ["boz", Vector2(-90.05, 34.35), 0],
				["boz", Vector2(-82.46, 57.77), 0], ["boz", Vector2(-63.16, 56.12), 0],
				["koroo", Vector2(-115, 65), 3], ["jylky", Vector2(-25, 90), 2]],
			"workers": Vector2(-44, 36)},
		{"faction": "kokand", "hq": Vector2(184, 56), "hq_rot_q": 3,
			"buildings": [["uy", Vector2(206, 30), 3], ["uy", Vector2(206, 82), 3]],
			"workers": Vector2(166, 48)},
	],
	"trees": "scatter",
	"deposits": [
		["stone", Vector2(-206, 12)], ["stone", Vector2(266, -66)], ["stone", Vector2(-114, -268)],
		["stone", Vector2(-18, 316)], ["stone", Vector2(270, 284)],
		["gold", Vector2(-56, 168)], ["gold", Vector2(206, 168)], ["gold", Vector2(38, -292)],
		["gold", Vector2(94, 316)], ["gold", Vector2(-306, 180)],
	],
	"clay": [Vector2(142, -132), Vector2(-32, -126), Vector2(206, -90)],
	"dam_sites": [Vector2(160, -170.5), Vector2(208, -178.3)],
	"raid_edges": [Vector2(-340, 40), Vector2(-200, 300), Vector2(120, 300), Vector2(280, 140), Vector2(120, -290)],
	"zones": {"jailoo": [Vector3(-60, -270, 60)], "kyshtoo": [Vector3(-120, 230, 70)]},
	"ai_base": {"towers": {"kokand": "burj", "kipchak": "munara"},
		"tower_offsets": [Vector2(-28, -20), Vector2(-28, 20)]},
}
