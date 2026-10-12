class_name HerdDefs
## Стада (ТЗ 5.3, 5.4; docs/ECONOMY.md): счёт голов у загона, не тела ядра.
## Схема — ведущий (M0), значения — ECON. Порядок записей = индекс Defs.
##
## Поля: name; yield {ресурс: за голову в минуту на свежей траве} (выход × средняя трава под стадом);
##   growth — прирост голов в минуту на голову (доля); graze — сколько травы съедает голова в минуту
##   (0..1000 клетки 16 м); graze_r — радиус выпаса, м; backing — ресурс, запас которого и есть
##   головы (кони); capturable — можно угнать (ARCHITECTURE §11); flock_max — сколько животных
##   рисует HerdView; model — вид толпы (assets/models/units/<model>.glb); enabled.
## Короо ≈54 еды/мин на свежей траве (ТЗ 5.3) при 20 овцах → 2,7 еды на голову.

const HERDS := {
	"sheep": {"name": "Отара", "yield": {"food": 2.7, "wool": 0.1}, "growth": 0.01, "graze": 6.0,
		"graze_r": 22.0, "capturable": true, "flock_max": 80, "model": "sheep"},
	# ECONOMY.md: кони — ресурс конницы, табун растёт, его можно угнать
	"horse": {"name": "Табун", "yield": {}, "growth": 0.008, "graze": 8.0, "graze_r": 26.0,
		"backing": "horse", "capturable": true, "flock_max": 40, "model": "horse", "enabled": false},
}
