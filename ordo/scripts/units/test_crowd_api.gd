extends SceneTree
## Проверка API толпы без графики: реестр, пути моделей, слой, скорость set_instance.
##   godot --headless --path ordo --script res://scripts/units/test_crowd_api.gd

func _init() -> void:
	var ok := true
	for id in UnitRegistry.ids():
		var u := UnitRegistry.info(id)
		for key in ["skeleton", "weapon", "height", "radius", "side"]:
			if not u.has(key):
				printerr("нет поля ", key, " у ", id)
				ok = false
		for lod in 2:
			var p := UnitRegistry.mesh_path(id, lod)
			if not ResourceLoader.exists(p):
				printerr("нет модели ", p)
				ok = false
	var root := Node3D.new()
	get_root().add_child(root)
	var layer := CrowdLayer.new()
	root.add_child(layer)
	layer.setup("kok_sarboz", 1000)
	layer.set_visible_count(1000)
	var t0 := Time.get_ticks_usec()
	for i in 1000:
		var dir := Vector3(sin(i), 0, cos(i))
		var xf := Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), Vector3(i % 40, 0, i / 40))
		layer.set_instance(i, xf, AnimSpec.custom(AnimSpec.Human.WALK, fposmod(i * 0.1, 1.0), 1.0, fposmod(i * 0.618, 1.0)))
	var us := Time.get_ticks_usec() - t0
	print("[api] 1000 × set_instance: %.2f мс" % (us / 1000.0))
	t0 = Time.get_ticks_usec()
	layer._flush()
	print("[api] отправка буфера и границ: %.2f мс" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var mmi := layer.get_child(0) as MultiMeshInstance3D
	print("[api] LOD0: ", mmi.multimesh.mesh.get_faces().size() / 3, " треуг., границы ", mmi.multimesh.custom_aabb)
	if CrowdAnim.gait("rider", 9.0, true) != AnimSpec.Horse.CHARGE or CrowdAnim.gait("human", 1.0) != AnimSpec.Human.WALK:
		printerr("CrowdAnim.gait")
		ok = false
	if absf(CrowdAnim.advance(0.9, 0.3, 1.5) - 0.1) > 1e-5:
		printerr("CrowdAnim.advance")
		ok = false
	print("[api] итог: ", "ok" if ok else "ОШИБКИ")
	quit(0 if ok else 1)
