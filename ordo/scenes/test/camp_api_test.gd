extends SceneTree
## Проверка API лагеря без графики:
##   godot --headless --path ordo --script res://scenes/test/camp_api_test.gd
## Загружает scenes/camp/camp.tscn, проверяет метки, загоны и постройки, печатает итог.

func _init() -> void:
	var camp := (load("res://scenes/camp/camp.tscn") as PackedScene).instantiate() as KipchakCamp
	root.add_child(camp)
	await process_frame
	var errors := 0
	var pen := camp.sheep_pen()
	var horses := camp.horse_pen()
	errors += _check(pen != null and pen.size.x > 10.0, "SheepPen с размером")
	errors += _check(horses != null and horses.size.x > 10.0, "HorsePen с размером")
	errors += _check(pen.contains(pen.global_position), "SheepPen.contains(центр)")
	errors += _check(_xz(pen).distance_to(Vector2(-115, 65)) < 0.5, "загон в (−115, 65)")
	errors += _check(_xz(horses).distance_to(Vector2(-25, 90)) < 0.5, "конный двор в (−25, 90)")
	errors += _check(camp.marker("BannerPos") != null, "BannerPos")
	errors += _check(camp.markers("Fire_").size() >= 4, "Fire_1..N")
	errors += _check(camp.markers("GuardPost_").size() >= 2, "GuardPost_1..N")
	errors += _check(camp.markers("WorkSpot_").size() >= 4, "WorkSpot_1..N")
	var yurts := 0
	for b in camp.buildings():
		if String(b.name).begins_with("Boz_"):
			yurts += 1
	errors += _check(yurts >= 8 and yurts <= 10, "8–10 боз үй (%d)" % yurts)
	var ordo := camp.get_node("Buildings/Ordo") as Node3D
	errors += _check(_xz(ordo).distance_to(Vector2(-60, 20)) < 0.5, "Хан ордосу в (−60, 20)")
	errors += _check(ordo.get_node_or_null("LOD1") != null, "у ордо есть LOD1")
	print("[camp] меток: ", camp.get_node("Markers").get_child_count(), ", построек: ", camp.buildings().size(),
		", ошибок: ", errors)
	quit(1 if errors > 0 else 0)


func _check(ok: bool, what: String) -> int:
	print(("  ok  " if ok else "  НЕТ ") + what)
	return 0 if ok else 1


## Место в плане (x, z): высоту задаёт настоящая земля мира (Terrain.height_at)
func _xz(n: Node3D) -> Vector2:
	return Vector2(n.global_position.x, n.global_position.z)
