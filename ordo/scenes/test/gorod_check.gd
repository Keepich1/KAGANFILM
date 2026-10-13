extends SceneTree
## Сборка всех скриптов вида «Города» без графики (быстрая проверка разбора):
##   godot --headless --path ordo --script res://scenes/test/gorod_check.gd

const PATHS := ["res://scripts/view/city_view.gd", "res://scripts/view/unit_view.gd", "res://scripts/view/building_look.gd",
	"res://scripts/view/building_view.gd", "res://scripts/view/field_view.gd", "res://scripts/view/node_view.gd",
	"res://scripts/view/herd_view.gd", "res://scripts/view/ghost_view.gd", "res://scripts/view/selection_view.gd",
	"res://scripts/view/overlay_view.gd", "res://scripts/view/city_fx.gd", "res://scenes/gorod/gorod.gd",
	"res://scenes/gorod/gorod_shots.gd", "res://scenes/gorod/gorod_stress.gd", "res://scripts/world/world_scatter.gd",
	"res://scripts/world/grass_field.gd"]


func _init() -> void:
	var bad := 0
	for p in PATHS:
		var s := load(p) as Script
		var ok := s != null and s.can_instantiate()
		if not ok:
			bad += 1
		print(p, " -> ", "ok" if ok else "ОШИБКА")
	print("ИТОГ: ВСЁ ПРОШЛО" if bad == 0 else "ИТОГ: ОШИБОК %d" % bad)
	quit(0 if bad == 0 else 1)
