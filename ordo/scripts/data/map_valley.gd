class_name MapValley
## Карта «Долина» для «Города» (ТЗ 8; CONTRACT §3; ARCHITECTURE §6.4; docs/ECONOMY.md §1.1, §2, §3, §12.1).
## Схема — ведущий (M0), значения — GAME. Земля — assets/world/height.json (1024 × 1024 м, центр (0, 0)).
## Координаты — (x, z) мира, м; rot_q — четверть оборота (фасад +Z повёрнут на rot_q · 90°).
##
##   sites      — стартовые места: faction (для какой стороны), hq + hq_rot_q,
##                buildings [[id, (x, z), rot_q]] — стоят с начала (ECONOMY: у Коканда — Тўғон;
##                у кыпчаков — один короо с отарой 40; кони — на коновязи ставки),
##                links [[id, [точки…]]] — линии с начала (Бош ариқ от тўғона к городу, ~150 м),
##                workers — где стоят стартовые работники (FactionDefs.start_units),
##                layout [[id, (x, z), rot_q]] — места для базы ИИ и подсказка игроку
##                (у кыпчаков — раскладка лагеря среза: кольцо боз үй и жылкы, CONTRACT §3)
##   trees      — "scatter": деревья карты из ScatterData (порядок файла → scatter_ref)
##   deposits   — жилы [[узел NodeDefs, (x, z), запас (−1 — из NodeDefs)]]: у каждой ставки в ~120 м — золото
##                и камень, на полпути (~300 м) — ещё по паре, в центре — спорное богатое золото (5000),
##                пятый камень — у реки, спорный (ECONOMY §1.1)
##   dam_sites  — места под тўғон на берегу (не на броде), второе — не ближе 150 м к первому
##   raid_edges — края карты, откуда приходят набеги
##   zones      — пастбища сезонов (Сб. 2): jailoo / kyshtoo [Vector3(x, z, r)]
##   ai_base    — где строится база ИИ (AiDefs.BASE): башни по сторонам от ставки

const MAP := {
	"id": "valley",
	"name": "Долина",
	"bounds": Rect2(-512, -512, 1024, 1024),
	"sites": [
		{"faction": "kipchak", "hq": Vector2(-60, 20), "hq_rot_q": 0,
			"buildings": [["koroo", Vector2(-115, 65), 3]],
			"links": [],
			"workers": Vector2(-44, 36),
			"layout": [
				["boz", Vector2(-23.88, 30.53), 0], ["boz", Vector2(-28.98, 12.24), 0],
				["boz", Vector2(-36.52, -11.22), 0], ["boz", Vector2(-51.31, -17.11), 0],
				["boz", Vector2(-74.30, -19.38), 0], ["boz", Vector2(-89.98, 0.84), 0],
				["boz", Vector2(-99.72, 13.64), 0], ["boz", Vector2(-90.05, 34.35), 0],
				["boz", Vector2(-82.46, 57.77), 0], ["boz", Vector2(-63.16, 56.12), 0],
				["jylky", Vector2(-25, 90), 2]]},
		{"faction": "kokand", "hq": Vector2(184, 56), "hq_rot_q": 3,
			"buildings": [["togon", Vector2(160, -170.5), 0]],
			"links": [["aryk", [Vector2(162, -152), Vector2(166, -80), Vector2(170, -10)]]],
			"workers": Vector2(166, 48),
			"layout": [["uy", Vector2(206, 30), 3], ["uy", Vector2(206, 82), 3], ["dala", Vector2(150, -40), 0],
				["dala", Vector2(186, -40), 0], ["tegirmon", Vector2(168, 10), 3], ["ombor", Vector2(150, 70), 3]]},
	],
	"trees": "scatter",
	"deposits": [
		["gold", Vector2(-120, -60), -1], ["stone", Vector2(-176, 24), -1],
		["stone", Vector2(248, -28), -1], ["gold", Vector2(188, 164), -1],
		["stone", Vector2(-280, -160), -1], ["gold", Vector2(-252, 224), -1],
		["gold", Vector2(96, 324), -1], ["stone", Vector2(156, -256), -1],
		["gold", Vector2(36, 120), 5000],
		["stone", Vector2(-32, -126), -1],
	],
	"dam_sites": [Vector2(160, -170.5), Vector2(320, -187.8)],
	"raid_edges": [Vector2(-340, 40), Vector2(-200, 300), Vector2(120, 300), Vector2(280, 140), Vector2(120, -290)],
	"zones": {"jailoo": [Vector3(-60, -270, 150)], "kyshtoo": [Vector3(-120, 230, 120)]},
	"ai_base": {"tower_offsets": [Vector2(-28, -20), Vector2(-28, 20)]},
}
