extends SceneTree
## Постройки «Города» (BuildingView, BuildingLook, NodeView, GhostView; ARCHITECTURE §13, §15 VIEW) без графики:
##   godot --headless --path ordo --script res://tests/test_building_view.gd
## • поиск модели по CONTRACT §10.8: есть glb — модель, нет — заместитель;
## • MultiMesh: число экземпляров по типам = готовые постройки этих типов в таблице; после постройки,
##   разрушения (руина), освобождения слота и новой стройки — пересчитывается; узлы — у строек и руин;
## • стройка: срез по прогрессу растёт;
## • стадии выработки жил; призрак: красный, если хоть одна клетка «нельзя».

var _fails := 0
var _checks := 0


func _init() -> void:
	var city := FakeCity.new()
	city.setup(1)
	_test_lookup(city)
	_test_counts(city)
	_test_misc(city)
	print("")
	if _fails == 0:
		print("ИТОГ: ВСЁ ПРОШЛО (%d проверок)" % _checks)
		quit(0)
	else:
		print("ИТОГ: ПРОВАЛЕНО %d из %d" % [_fails, _checks])
		quit(1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL ", what)


func _test_lookup(city: FakeCity) -> void:
	print("Поиск моделей")
	var d := city.defs()
	var boz := d.building(&"boz")
	_check(BuildingLook.model_path(d, boz, BuildingTable.State.ACTIVE) == "res://assets/models/kipchak/boz.glb", "боз үй — своя модель")
	var urda := d.building(&"urda")
	var p := BuildingLook.model_path(d, urda, BuildingTable.State.ACTIVE)
	_check(p == "" or p.begins_with("res://assets/models/kokand/urda") or p.begins_with("res://scenes/kokand/urda"),
		"урда: модель Коканда или заместитель (%s)" % p)
	for id in d.b_ids:
		var m := BuildingLook.mesh_for(d, d.building(StringName(id)))
		_check(m != null and m.get_surface_count() == 1, "заместитель %s: один меш, одна поверхность" % id)
	var n := BuildingLook.make(d, urda, BuildingTable.State.SITE)
	_check(n.get_node_or_null("Scaffold") != null or bool(n.get_meta("exact", false)), "стройка урды: леса")
	n.free()
	var r := BuildingLook.make(d, boz, BuildingTable.State.RUIN)
	_check(r.get_node_or_null("Rubble") != null or bool(r.get_meta("exact", false)), "руина юрты: обломки")
	r.free()


## Сколько готовых построек типа ty в таблице
func _active(bt: BuildingTable, ty: int) -> int:
	var c := 0
	for b in bt.hw:
		if bt.btype[b] == ty and bt.state[b] == BuildingTable.State.ACTIVE:
			c += 1
	return c


func _mm_total(v: BuildingView, ty: int) -> int:
	# экземпляров LOD0 у MultiMeshInstance3D этого типа (каждой части модели — свой MultiMesh)
	var parts := BuildingLook.parts_for(v.defs, ty, 0).size()
	var s := 0
	for c in v.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("MM_%d_" % ty) and String(c.name).ends_with("_L0") \
				and not c.is_queued_for_deletion():
			s += (c as MultiMeshInstance3D).multimesh.instance_count
	return s / maxi(parts, 1)


func _test_counts(city: FakeCity) -> void:
	print("MultiMesh: постройка и разрушение")
	var v := BuildingView.new()
	root.add_child(v)
	v.set_query(city)
	var d := city.defs()
	var bt := city.buildings()
	var types := PackedInt32Array()
	for id in ["uy", "boz", "devor", "chep", "aryk"]:
		types.append(d.building(StringName(id)))
	for ty in types:
		_check(v.mm_instances(ty) == _active(bt, ty), "%s: MultiMesh %d = готовых %d" % [d.b_ids[ty], v.mm_instances(ty), _active(bt, ty)])
		_check(_mm_total(v, ty) == _active(bt, ty), "%s: экземпляров LOD0 %d = %d" % [d.b_ids[ty], _mm_total(v, ty), _active(bt, ty)])
	# у каждой стройки и руины — узел
	var want_nodes := 0
	for b in bt.hw:
		var st := bt.state[b]
		if st == BuildingTable.State.SITE or st == BuildingTable.State.RUIN or \
				(st == BuildingTable.State.ACTIVE and d.b_render[bt.btype[b]] == Defs.Render.SCENE):
			want_nodes += 1
	_check(v.scene_nodes() == want_nodes, "узлов построек %d = %d" % [v.scene_nodes(), want_nodes])
	# построили дом (ECON поставил бы стройку и довёл; здесь — сразу готовый)
	var uy := d.building(&"uy")
	var before := v.mm_instances(uy)
	var b := city.call("_add", FakeCity.KOK, &"uy", Vector2(240, 160), 0) as int
	v.sync()
	_check(v.mm_instances(uy) == before + 1, "дом построен: %d → %d" % [before, v.mm_instances(uy)])
	_check(_mm_total(v, uy) == before + 1, "дом построен: экземпляров LOD0 %d" % _mm_total(v, uy))
	# разрушен — руина (узел), из MultiMesh ушёл
	bt.state[b] = BuildingTable.State.RUIN
	v.sync()
	_check(v.mm_instances(uy) == before, "дом разрушен: MultiMesh снова %d" % v.mm_instances(uy))
	_check(v.node_of(b) != null and v.node_of(b).get_node_or_null("Rubble") != null, "руина — узел с обломками")
	# слот освобождён — ничего не рисуется; на нём новая стройка юрты
	bt.release(b)
	v.sync()
	_check(v.node_of(b) == null, "слот свободен — узла нет")
	var b2 := bt.alloc(BuildingTable.State.SITE)
	_check(b2 == b, "слот занят снова (%d)" % b2)
	bt.btype[b2] = d.building(&"boz")
	bt.owner[b2] = FakeCity.KIP
	bt.team[b2] = 1
	bt.x[b2] = 240.0
	bt.z[b2] = 160.0
	bt.progress[b2] = 100
	v.sync()
	var n := v.node_of(b2)
	_check(n != null and String(n.name).ends_with("boz"), "новое поколение слота: стройка юрты")
	# стройка растёт: срез по высоте
	if n:
		var body := n.get_node("Body")
		var mi := (body if body is MeshInstance3D else body.find_children("*", "MeshInstance3D", true, false)[0]) as GeometryInstance3D
		var h0 := float(mi.get_instance_shader_parameter("clip_h"))
		bt.progress[b2] = 700
		v.sync()
		var h1 := float(mi.get_instance_shader_parameter("clip_h"))
		_check(h1 > h0 + 0.5, "стройка выросла: срез %.2f → %.2f м" % [h0, h1])
		bt.state[b2] = BuildingTable.State.ACTIVE
		v.sync()
		_check(v.node_of(b2) == null and v.mm_instances(d.building(&"boz")) == _active(bt, d.building(&"boz")),
			"юрта готова: ушла в MultiMesh")
	# огонь: здоровье ниже половины
	var tg := -1
	for k in bt.hw:
		if bt.state[k] == BuildingTable.State.ACTIVE and d.b_ids[bt.btype[k]] == "ombor":
			tg = k
	if tg >= 0:
		bt.hp_c[tg] = bt.hp_max_c[tg] / 3
		for i in 10:
			v.sync()
		_check(v.node_of(tg).get_node_or_null("Fire") != null, "омбор горит при уроне > 50 %")
		bt.hp_c[tg] = bt.hp_max_c[tg]
		for i in 10:
			v.sync()
		var f := v.node_of(tg).get_node_or_null("Fire")
		_check(f == null or f.is_queued_for_deletion(), "починили — огонь погас")
	v.free()


func _test_misc(city: FakeCity) -> void:
	print("Жилы, призрак")
	_check(NodeView.stage_of(4000000, 4000000) == 3, "жила полная — стадия 3")
	_check(NodeView.stage_of(2000000, 4000000) == 2, "половина — стадия 2")
	_check(NodeView.stage_of(500000, 4000000) == 1, "остатки — стадия 1")
	_check(NodeView.stage_of(0, 4000000) == 0, "выработана — 0")
	var g := GhostView.new()
	root.add_child(g)
	g.set_query(city)
	var d := city.defs()
	var uy := d.building(&"uy")
	var ok_c := city.snap(uy, Vector2(300, 250), 0)
	g.show_building(uy, ok_c, 0, city.place_cells(0, uy, ok_c, 0))
	_check(g.shown_ok and g.shown_btype == uy, "свободное место — зелёный")
	var bad_c := city.snap(uy, Vector2(184, 56), 0)
	g.show_building(uy, bad_c, 0, city.place_cells(0, uy, bad_c, 0))
	_check(not g.shown_ok, "на урде — красный")
	var plan := city.plan_wall(0, d.building(&"devor"), PackedVector2Array([Vector2(260, 200), Vector2(300, 200)]))
	g.show_wall(plan, d.building(&"devor"))
	_check(g.shown_btype == d.building(&"devor") and (g.get_node("Links") as MultiMeshInstance3D).multimesh.instance_count == (plan["centers"] as PackedVector2Array).size(),
		"цепочка стены: звено на центр")
	g.hide_ghost()
	_check(g.shown_btype == -1, "спрятан")
	g.free()
