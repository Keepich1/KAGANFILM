extends SceneTree
## Постройки «Города» (BuildingView, BuildingLook, NodeView, GhostView; ARCHITECTURE §13, §15 VIEW) без графики:
##   godot --headless --path ordo --script res://tests/test_building_view.gd
## • поиск модели по CONTRACT §10.8: есть glb — модель, нет — заместитель;
## • MultiMesh: число экземпляров по типам = готовые постройки этих типов в таблице; после постройки,
##   разрушения (руина), освобождения слота и новой стройки — пересчитывается; узлы — у строек и руин;
## • стройка: срез по прогрессу растёт;
## • стадии выработки жил; призрак: красный, если хоть одна клетка «нельзя»;
## • флаг сбора: у новой постройки (alloc: rally (0, 0), rally_h = 0) флага нет; точка — флаг в точке;
##   цель rally_h (узел) — флаг у цели;
## • руина из настоящей модели (боз үй) на высоком месте: срез от своего основания (base_y), тело видно.

var _fails := 0
var _checks := 0


func _init() -> void:
	var city := FakeCity.new()
	city.setup(1)
	_test_lookup(city)
	_test_counts(city)
	_test_misc(city)
	_test_rally(city)
	_test_ruin_base(city)
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
	_check(p == "" or p == "res://assets/models/kokand/urda.glb", "урда: модель Коканда или заместитель (%s)" % p)
	# псевдонимы имён арта и стадии поля
	if ResourceLoader.exists("res://assets/models/kokand/tugon.glb"):
		_check(BuildingLook.model_name(d, d.building(&"togon")) == "tugon", "тўғон → tugon.glb")
		_check(BuildingLook.model_name(d, d.building(&"aryk")) == "aryk", "ариқ (model «ariq») → aryk.glb")
		var dala := d.building(&"dala")
		_check(BuildingLook.model_path(d, dala, BuildingTable.State.ACTIVE, 0).ends_with("dala_s0.glb") and
			BuildingLook.model_path(d, dala, BuildingTable.State.ACTIVE, 2).ends_with("dala_s2.glb"), "поле: стадии урожая")
		_check(BuildingLook.model_path(d, urda, BuildingTable.State.SITE).ends_with("urda_site.glb"), "стройка урды — urda_site.glb")
		# метки обёртки: дым печи (тёмный), тандыр — только у двора 1
		var xum := BuildingLook.smoke_points(d, d.building(&"xumdon"))
		_check(xum.size() == 1 and bool(xum[0].dark), "печь: дым из метки обёртки, тёмный")
		var uy := d.building(&"uy")
		_check(BuildingLook.smoke_points(d, uy, 1).size() == 1 and BuildingLook.smoke_points(d, uy, 2).is_empty(),
			"дом: тандыр дымит только у двора 1")
		var parts := BuildingLook.parts_for(d, uy, 0)
		var vars := {}
		for pt: Dictionary in parts:
			vars[int(pt["var"])] = true
		_check(vars.has(0) and vars.has(1) and vars.has(2) and vars.has(3), "дом: части двора Var_1..3 и общие (%s)" % [vars.keys()])
		# части с одним материалом слиты: урда (9 мешей) — 3 части; дом — по меш на двор и общая земля
		_check(BuildingLook.parts_for(d, urda, 0).size() <= 4, "урда: части с одним материалом слиты (%d)" % BuildingLook.parts_for(d, urda, 0).size())
		var spin := false
		for pt: Dictionary in BuildingLook.parts_for(d, d.building(&"tegirmon"), 0):
			spin = spin or bool(pt.spin)
		_check(spin, "мельница: колесо — крутящаяся часть")
		var hn := BuildingLook.make(d, uy, BuildingTable.State.ACTIVE, 140.0, 2)
		var shown := 0
		for vn in hn.find_children("Var_*", "Node3D", true, false):
			if (vn as Node3D).visible:
				shown += 1
				_check(String(vn.name) == "Var_2", "дом-узел: виден только двор 2 (%s)" % vn.name)
		_check(shown >= 1, "дом-узел: двор виден")
		hn.free()
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
	# экземпляров LOD0 у первой общей части модели (не двора Var_k) — по всем группам типа
	var parts := BuildingLook.parts_for(v.defs, ty, 0)
	var pi := 0
	for i in parts.size():
		if int(parts[i]["var"]) == 0:
			pi = i
			break
	var s := 0
	for c in v.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("MM_%d_" % ty) and String(c.name).ends_with("_P%d_L0" % pi) \
				and not c.is_queued_for_deletion():
			s += (c as MultiMeshInstance3D).multimesh.instance_count
	return s


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
				(st == BuildingTable.State.ACTIVE and not v.uses_multimesh(bt.btype[b])):
			want_nodes += 1
	_check(v.scene_nodes() == want_nodes, "узлов построек %d = %d" % [v.scene_nodes(), want_nodes])
	# готовые «scene»-типы (модель арта или заместитель) — тоже MultiMesh; поле — MultiMesh по стадии,
	# если есть модель, иначе узел (полив на экземпляр)
	var urda := d.building(&"urda")
	var dala := d.building(&"dala")
	var ordo := d.building(&"ordo")
	_check(v.uses_multimesh(urda) and v.uses_multimesh(ordo), "урда и орда — MultiMesh")
	_check(v.uses_multimesh(dala) == (BuildingLook.model_name(d, dala) != ""), "поле: MultiMesh, если есть модель")
	for ty in [urda, ordo, dala, d.building(&"ombor"), d.building(&"kazarma"), d.building(&"tegirmon")]:
		_check(v.mm_instances(ty) == _active(bt, ty), "%s: MultiMesh %d = готовых %d" % [d.b_ids[ty], v.mm_instances(ty), _active(bt, ty)])
	# стадия поля: полив и работники — спелое, без работников — зелёное
	for b0 in bt.hw:
		if bt.state[b0] == BuildingTable.State.ACTIVE and bt.btype[b0] == dala and v.uses_multimesh(dala):
			var w0 := bt.workers_n[b0]
			var st0 := v.field_stage(b0, bt)
			bt.workers_n[b0] = 0 if w0 > 0 else 2
			for i in BuildingView.FIELD_EVERY:
				v.sync()
			var st1 := v.field_stage(b0, bt)
			_check(st0 == 0 or st1 != st0, "поле: стадия по работникам (%d → %d)" % [st0, st1])
			_check(v.mm_instances(dala) == _active(bt, dala), "поле сменило стадию: MultiMesh %d" % v.mm_instances(dala))
			var key := "%d:%d:" % [dala, st1]
			var found := false
			for c in v.get_children():
				if c is MultiMeshInstance3D and String(c.name).begins_with("MM_" + key.replace(":", "_")):
					found = true
			_check(found, "поле: группа стадии %d" % st1)
			bt.workers_n[b0] = w0
			break
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
	_check(v.node_of(b) != null and (v.node_of(b).get_node_or_null("Rubble") != null or bool(v.node_of(b).get_meta("exact"))),
		"руина — узел (модель _ruin или обломки)")
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
	# огонь: здоровье ниже половины — у постройки-узла (орда, модель) и у домов MultiMesh
	for id: String in ["ordo", "ombor", "uy"]:
		var ty := d.building(StringName(id))
		var tg := -1
		for k in bt.hw:
			if bt.state[k] == BuildingTable.State.ACTIVE and bt.btype[k] == ty:
				tg = k
		if tg < 0:
			continue
		var mm0 := v.mm_instances(ty)
		bt.hp_c[tg] = bt.hp_max_c[tg] / 3
		for i in 10:
			v.sync()
		var nd := v.node_of(tg)
		_check(nd != null and nd.get_node_or_null("Fire") != null, "%s горит при уроне > 50 %%" % id)
		if v.uses_multimesh(ty):
			_check(v.mm_instances(ty) == mm0 - 1, "%s горит: ушёл из MultiMesh в узел (%d → %d)" % [id, mm0, v.mm_instances(ty)])
			_check(_mm_total(v, ty) == mm0 - 1, "%s горит: экземпляров LOD0 %d (было %d)" % [id, _mm_total(v, ty), mm0])
		bt.hp_c[tg] = bt.hp_max_c[tg]
		for i in 10:
			v.sync()
		if v.uses_multimesh(ty):
			_check(v.node_of(tg) == null and v.mm_instances(ty) == mm0, "%s починили — снова в MultiMesh (%d)" % [id, v.mm_instances(ty)])
		else:
			var f := v.node_of(tg).get_node_or_null("Fire")
			_check(f == null or f.is_queued_for_deletion(), "%s починили — огонь погас" % id)
	# концы линий стены: столбы <имя>_end у звеньев без соседа
	var dv := d.building(&"devor")
	if BuildingLook.end_path(d, dv) != "":
		var ends := v.wall_ends(dv, bt)
		var n_links := 0
		var n_ends := 0
		for k in ends:
			n_ends += (ends[k] as Array).size()
		for b0 in bt.hw:
			if bt.btype[b0] == dv and bt.state[b0] != BuildingTable.State.FREE:
				n_links += 1
		_check(n_links == 0 or (n_ends >= 2 and n_ends < n_links * 2), "стена: концы линий %d у %d звеньев" % [n_ends, n_links])
		var posts := 0
		for c in v.get_children():
			if c is MultiMeshInstance3D and String(c.name).begins_with("MM_%d_" % dv) and "_E0_L0" in String(c.name) \
					and not c.is_queued_for_deletion():
				posts += (c as MultiMeshInstance3D).multimesh.instance_count
		var want_posts := 0
		for k in ends:
			if bt.state[k] == BuildingTable.State.ACTIVE:
				want_posts += (ends[k] as Array).size()
		_check(posts == want_posts, "стена: столбов на концах %d = %d" % [posts, want_posts])
	# дым юрт MultiMesh: один выпуск на группу, точек — по юртам группы
	var smokes := 0
	var points := 0
	var boz := d.building(&"boz")
	for c in v.get_children():
		if c is GPUParticles3D and String(c.name).begins_with("Smoke_%d_" % boz) and not c.is_queued_for_deletion():
			smokes += 1
			points += maxi(1, ((c as GPUParticles3D).process_material as ParticleProcessMaterial).emission_point_count)
	_check(points == v.mm_instances(boz) and smokes <= points and smokes > 0,
		"дым тюндюков: %d выпусков на %d юрт (точек %d)" % [smokes, v.mm_instances(boz), points])
	v.free()


func _test_misc(city: FakeCity) -> void:
	print("Жилы, призрак")
	_check(NodeView.stage_of(4000000, 4000000) == 3, "жила полная — стадия 3")
	_check(NodeView.stage_of(2000000, 4000000) == 2, "половина — стадия 2")
	_check(NodeView.stage_of(500000, 4000000) == 1, "остатки — стадия 1")
	_check(NodeView.stage_of(0, 4000000) == 0, "выработана — 0")
	_check(CityFx.amount_text(400) == "0,4" and CityFx.amount_text(3000) == "3" and CityFx.amount_text(12500) == "12",
		"надписи доставки: 0,4 / 3 / 12 (не «+0»)")
	if ResourceLoader.exists(NodeView.DEPOSIT_SCENE % "gold"):
		var nv := NodeView.new()
		nv.set_query(city)
		var dd := city.defs()
		var gold := -1
		for t in dd.n_ids.size():
			if dd.n_ids[t] == "gold":
				gold = t
		var dep := nv.call("_deposit", gold, 2, 1) as Node3D
		_check(dep is ResourceDeposit and int(dep.get("stage")) == 1, "жила золота: месторождение арта, стадия «половина»")
		dep.free()
		nv.free()
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
	# как зовёт UI (PlacementMode): show_building(тип стены) до первой точки, потом show_wall(plan) без типа
	var dv := d.building(&"devor")
	var c0 := city.snap(dv, Vector2(260, 200), 0)
	g.show_building(dv, c0, 0, city.place_cells(0, dv, c0, 0))
	g.show_wall(plan)
	var links := g.get_node("Links") as MultiMeshInstance3D
	_check(g.shown_btype == dv and not links.multimesh.mesh is BoxMesh, "show_wall(plan) без типа — звенья стены, а не коробки")
	g.hide_ghost()
	var g2 := GhostView.new()
	root.add_child(g2)
	g2.set_query(city)
	g2.show_wall(plan)
	_check(g2.shown_btype >= 0 and d.b_kind[g2.shown_btype] == Defs.BKind.WALL, "show_wall(plan) без типа и без показа стены — первая стена")
	g2.free()
	g.show_building(dv, c0, 0, city.place_cells(0, dv, c0, 0))
	g.hide()
	if not g.is_inside_tree():
		# вне дерева уведомление о видимости не приходит само (в игре — приходит)
		g.notification(Node3D.NOTIFICATION_VISIBILITY_CHANGED)
	_check(g.shown_btype == -1 and not g.visible, "hide() (Node3D) — спрятан и сброшен")
	g.free()


func _test_rally(city: FakeCity) -> void:
	print("Флаг места сбора")
	var d := city.defs()
	var bt := city.buildings()
	var trainer := -1
	for ty in d.b_ids.size():
		if not d.b_trains[ty].is_empty() and d.b_faction[ty] == "kokand":
			trainer = ty
			break
	_check(trainer >= 0, "есть постройка, которая обучает")
	if trainer < 0:
		return
	var b := bt.alloc(BuildingTable.State.ACTIVE)
	bt.btype[b] = trainer
	bt.owner[b] = FakeCity.KOK
	bt.team[b] = 0
	bt.x[b] = 250.0
	bt.z[b] = 120.0
	bt.hp_c[b] = 1000
	bt.hp_max_c[b] = 1000
	var sv := SelectionView.new()
	root.add_child(sv)
	sv.set_query(city)
	sv.selection = SelectionModel.new()
	sv.selection.set_selection(PackedInt32Array([bt.handle(b)]))
	sv._update()
	var flag := sv.get_node("RallyFlag") as Node3D
	_check(not flag.visible, "новая постройка (rally (0, 0), без цели): флага нет")
	_check(SelectionView.rally_point(city, b) == null, "rally_point: null")
	bt.rally_x[b] = 236.0
	bt.rally_z[b] = 131.0
	sv._update()
	_check(flag.visible and Vector2(flag.position.x, flag.position.z).distance_to(Vector2(236, 131)) < 0.01,
		"точка сбора: флаг в (236, 131), а не в начале мира (%s)" % flag.position)
	var nt := city.nodes()
	var nn := -1
	for k in nt.hw:
		if nt.ntype[k] >= 0:
			nn = k
			break
	if nn >= 0:
		bt.rally_h[b] = nt.handle(nn)
		sv._update()
		_check(flag.visible and Vector2(flag.position.x, flag.position.z).distance_to(Vector2(nt.x[nn], nt.z[nn])) < 0.01,
			"сбор у узла: флаг у цели (%s)" % flag.position)
	bt.release(b)
	sv.free()


func _test_ruin_base(city: FakeCity) -> void:
	print("Руина на возвышении: срез от основания")
	var d := city.defs()
	var bt := city.buildings()
	var v := BuildingView.new()
	root.add_child(v)
	v.set_query(city)
	var b := bt.alloc(BuildingTable.State.RUIN)
	bt.btype[b] = d.building(&"boz")
	bt.owner[b] = FakeCity.KIP
	bt.team[b] = 1
	bt.x[b] = 300.0
	bt.z[b] = 250.0
	v.sync()
	var n := v.node_of(b)
	_check(n != null, "руина юрты — узел")
	if n:
		var y := n.position.y
		_check(y > 1.5, "место на возвышении (%.2f м)" % y)
		var body := n.get_node("Body")
		var mis := body.find_children("*", "MeshInstance3D", true, false)
		if body is MeshInstance3D:
			mis.append(body)
		var bad := 0
		for mi: MeshInstance3D in mis:
			var by: Variant = mi.get_instance_shader_parameter("base_y")
			var ch: Variant = mi.get_instance_shader_parameter("clip_h")
			if by == null or absf(float(by) - y) > 0.01 or ch == null or float(ch) < 0.5:
				bad += 1
		_check(not mis.is_empty() and bad == 0, "у всех частей base_y = %.2f и срез выше основания (не так у %d из %d)" % [y, bad, mis.size()])
	bt.release(b)
	v.sync()
	v.free()
