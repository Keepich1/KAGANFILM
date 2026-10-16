class_name GorodPlaythrough
extends Node
## Проверка первой играбельной сборки (ARCHITECTURE §19.7 I4): настоящая партия «Города» за выбранную сторону
## по сценарию. Приказы идут тем же путём, что из интерфейса (GameDriver.issue → очередь игры → Orders),
## призрак постройки — через RtsInput.begin_place; между сценами игра промотана без отрисовки. На каждой
## сцене — кадр с интерфейсом и строка состояния (ресурсы, население, события) в консоль.
##   tools/shot.sh res://scenes/gorod/gorod.tscn out.png -- --faction=kokand --playthrough=/abs/dir [--only=a,b]
## Для скорости показа сценарий в начале добавляет запас (ресурсы на казарму, отряд, стены) — в строке
## «запас». Победа и поражение показываются концом партии: ставку врага (или свою) сносит сам сценарий.

const Op := SimCmd.Op

var scene: GorodScene
var driver: GameDriver
var out_dir := ""
var only := PackedStringArray()
var faction := "kokand"
var _ev := 0
var _counts := {}
var _done := false
var _mem := {}


static func start(p_scene: GorodScene, dir: String, p_only: PackedStringArray) -> GorodPlaythrough:
	var pt := GorodPlaythrough.new()
	pt.name = "Playthrough"
	pt.scene = p_scene
	pt.driver = p_scene.driver as GameDriver
	pt.out_dir = dir
	pt.only = p_only
	p_scene.add_child(pt)
	return pt


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var q := driver.query
	faction = String(q.defs().f_ids[q.players().faction[driver.local_player]])
	scene.camera.interactive = false
	_run.call_deferred()


# ================================================================= сценарии

func _beats() -> Array:
	if faction == "kokand":
		return [
			[1.0, _boost, "", {}],
			[2.0, _start_economy, "01_start", {"select": "hq"}],
			# подсказки на кадре (CityTips): найм, стройка, укрепления
			[2.0, _noop, "01t_tip_hire", {"select": "hq", "tip": "hire:1"}],
			[2.0, _noop, "01u_tip_build", {"select": "hq", "tip": "build:economy:8"}],
			[2.0, _noop, "01v_tip_fort", {"select": "hq", "tip": "build:fort:3"}],
			[6.0, _ghosts, "02_ghost", {}],
			[6.5, _ghost_bad, "02b_ghost_bad", {}],
			[7.0, _build_farm_house, "", {}],
			[50.0, _noop, "03_chop", {"work": 0.0}],
			[52.0, _noop, "04_dig", {"work": 0.25}],
			[60.0, _farm, "", {}],
			[80.0, _farm, "", {}],
			[115.0, _noop, "05_farm", {"near_type": "dala", "dist": 46.0, "pitch": 40.0}],
			[100.0, _kiln, "", {}],
			[116.0, _walls, "", {}],
			[150.0, _gate_tower, "", {}],
			[160.0, _barracks, "", {}],
			[215.0, _tower, "", {}],
			[235.0, _noop, "06_walls", {"near_wall": true, "dist": 60.0, "pitch": 34.0}],
			[240.0, _train_squad, "", {}],
			[285.0, _noop, "07_raid_warning", {"select": "hq"}],
			[300.0, _form_squad, "", {}],
			[310.0, _noop, "08_squad", {"select": "squad", "near_squad": true, "dist": 40.0, "pitch": 36.0}],
			[310.0, _noop, "08t_tip_order", {"select": "squad", "near_squad": true, "dist": 40.0, "pitch": 36.0, "tip": "order:3"}],
			[310.0, _noop, "08u_tip_card", {"select": "squad", "near_squad": true, "dist": 40.0, "pitch": 36.0, "tip": "card:0"}],
			[325.0, _noop, "09_raid", {"near_raid": true, "dist": 58.0, "pitch": 38.0}],
			[345.0, _disband, "", {}],
			[350.0, _noop, "10_disband", {"near_squad": true, "dist": 40.0, "pitch": 36.0}],
			[351.0, _pause_menu, "10b_pause_menu", {"keep": true}],
			[351.5, _close_menu, "", {}],
			[352.0, _win, "", {}],
			[356.0, _noop, "11_victory", {"select": "none"}],
		]
	return [
		[1.0, _boost, "", {}],
		[2.0, _start_economy, "01_start", {"select": "hq"}],
		[2.0, _noop, "01t_tip_hire", {"select": "hq", "tip": "hire:0"}],
		[2.0, _noop, "01u_tip_build", {"select": "hq", "tip": "build:economy:4"}],
		[6.0, _ghosts, "02_ghost", {}],
		[7.0, _build_farm_house, "", {}],
		[50.0, _noop, "03_chop", {"work": 0.0}],
		[60.0, _noop, "04_herd", {"select": "herd", "near_type": "koroo", "dist": 40.0, "pitch": 34.0}],
		[62.0, _walls, "", {}],
		[110.0, _gate_tower, "", {}],
		[120.0, _train_raiders, "", {}],
		[160.0, _noop, "05_walls", {"near_wall": true, "dist": 60.0, "pitch": 34.0}],
		[205.0, _raid_out, "", {}],
		[206.0, _pack, "", {}],
		[222.0, _noop, "06_pack", {"near_hq": true, "dist": 70.0, "pitch": 40.0}],
		[224.0, _unpack, "", {}],
		[244.0, _noop, "07_unpack", {"near_mem": "camp", "dist": 90.0, "pitch": 42.0}],
		[285.0, _noop, "08_raid_warning", {"select": "hq"}],
		[300.0, _noop, "09_olzho", {"near_raiders": true, "dist": 46.0, "pitch": 38.0}],
		[345.0, _noop, "10_raid", {"near_raid": true, "dist": 58.0, "pitch": 38.0}],
		[352.0, _lose, "", {}],
		[356.0, _noop, "11_defeat", {"select": "none"}],
	]


func _run() -> void:
	await get_tree().process_frame
	for b: Array in _beats():
		var t: float = b[0]
		_advance_to(t)
		(b[1] as Callable).call()
		var name: String = b[2]
		if name != "" and (only.is_empty() or only.has(name)):
			await _frame(name, b[3])
		_log(name if name != "" else "· %.0f с" % t)
	print("[проход] готово: %s" % out_dir)
	get_tree().quit()


func _advance_to(t: float) -> void:
	var want := roundi(t * 30.0)
	while driver.game.tick < want and not driver.game.over:
		driver.step()


## Кадр: камера, выделение, призрак; два кадра полной отрисовки — снять
func _frame(name: String, cfg: Dictionary) -> void:
	var q := driver.query
	var view := _view(cfg)
	var shot_cfg := {"view": Vector4(view.x, view.y, view.z, view.w)}
	if cfg.has("pitch"):
		shot_cfg["pitch"] = cfg["pitch"]
	if cfg.has("work"):
		shot_cfg = {"work": cfg["work"], "near": AiController.hq_pos(q, driver.local_player), "dist": 12.0, "pitch": 18.0}
	var keep_ghost := name.begins_with("02") or bool(cfg.get("keep", false))
	if not keep_ghost:
		GorodShots.setup(scene, [name, shot_cfg])
	_select(String(cfg.get("select", "")))
	scene.call("_set_fast", false)
	for i in 3:
		await get_tree().process_frame
	if cfg.has("tip"):
		await _hover(String(cfg["tip"]))
	if name.ends_with("victory") or name.ends_with("defeat"):
		await get_tree().create_timer(GorodPlay.END_FADE + 0.4).timeout     # экран конца проявился
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var path := "%s/%s_%s.png" % [out_dir, faction, name]
	var img := get_viewport().get_texture().get_image() if DisplayServer.get_name() != "headless" else null
	if img:
		img.save_png(path)
	print("[проход] кадр %s (такт %d)" % [path, driver.game.tick])
	scene.call("_set_fast", true)
	if cfg.has("tip"):
		_unhover()
	if scene.play and scene.play.input and scene.play.input.placement and scene.play.input.placement.active():
		scene.play.input.placement.cancel()
	scene.ghost.hide_ghost()


## Подсказка на кадре: «навести мышь» на кнопку интерфейса — событие движения прямо в окно (настоящая
## мышь не двигается), потом ждать, пока Godot покажет подсказку. spec: «hire:N» — N-я кнопка найма в панели
## здания, «build:вкладка:N» — N-я кнопка стройки вкладки, «order:N» — N-я кнопка приказа, «card:N» — карточка
func _hover(spec: String) -> void:
	var hud: CityHud = scene.play.hud if scene.play else null
	if hud == null:
		return
	# пауза на время кадра: иначе очередь найма сдвинется, панель пересоберёт кнопки и подсказка пропадёт
	_was_paused = driver.paused
	driver.paused = true
	# интерфейс обновляется по таймеру — сейчас же, чтобы кнопки не пересобрались под «мышью»
	hud.refresh_now(true)
	await get_tree().process_frame
	var p := spec.split(":")
	var target: Control = null
	match p[0]:
		"build", "order":
			hud.bottom.tabs.select(StringName(p[1]) if p[0] == "build" else &"orders")
			hud.refresh_now(true)
			await get_tree().process_frame
			var i := int(p[p.size() - 1])
			if i < hud.bottom.grid.get_child_count():
				target = hud.bottom.grid.get_child(i) as Control
		"hire":
			var n := 0
			for ch in hud.bottom.building.get_children():
				if ch is CityTips.TipButton and ch.name != "Ability" and (ch as Control).size.x >= CityBuildingPanel.TRAIN - 0.5:
					if n == int(p[1]):
						target = ch
						break
					n += 1
		"card":
			var n := 0
			for ch in hud.bottom.cards.get_children():
				if ch is CityTips.TipNine:
					if n == int(p[1]):
						target = ch
						break
					n += 1
	if target == null or not target.is_visible_in_tree():
		print("[проход] подсказка: нет кнопки %s" % spec)
		return
	var ev := InputEventMouseMotion.new()
	ev.position = target.get_global_rect().get_center()
	ev.global_position = ev.position
	# настоящий курсор может быть вне окна съёмки — окно должно считать, что мышь над ним
	get_viewport().notification(NOTIFICATION_VP_MOUSE_ENTER)
	get_viewport().push_input(ev, true)
	await get_tree().create_timer(float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5)) + 0.4).timeout


var _was_paused := false


## Увести «мышь» с кнопки (подсказка прячется), вернуть вкладку приказов и ход игры
func _unhover() -> void:
	driver.paused = _was_paused
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5, 200.0)
	ev.global_position = ev.position
	get_viewport().push_input(ev, true)
	if scene.play and scene.play.hud:
		scene.play.hud.bottom.tabs.select(&"orders")


func _view(cfg: Dictionary) -> Vector4:
	var q := driver.query
	var p := driver.local_player
	var at := AiController.hq_pos(q, p)
	if at == Vector2.INF:
		at = _mem.get("camp", Vector2(184, 56))
	if cfg.has("near_type"):
		var bt := q.defs().building(StringName(cfg["near_type"]))
		var B := q.buildings()
		for b in B.hw:
			if B.owner[b] == p and B.btype[b] == bt and B.state[b] != BuildingTable.State.FREE:
				at = Vector2(B.x[b], B.z[b])
				break
	if cfg.has("near_wall") and _mem.has("wall_mid"):
		at = _mem["wall_mid"]
	if cfg.has("near_mem") and _mem.has(cfg["near_mem"]):
		at = _mem[cfg["near_mem"]]
	if cfg.has("near_squad") and _mem.has("squad") and q.unit_alive_any(_mem["squad"]):
		at = (q as GameQueryImpl).unit_pos(_mem["squad"])
	if cfg.has("near_raiders"):
		var c := _centroid(_mem.get("raiders", PackedInt32Array()))
		if c != Vector2.INF:
			at = c
	if cfg.has("near_raid"):
		var c := _enemy_units_near(at, 160.0)
		if c != Vector2.INF:
			at = c
	var dist := float(cfg.get("dist", 110.0))
	var yaw := -58.0 if faction == "kokand" else 122.0
	return Vector4(at.x, at.y, dist, yaw)


func _select(what: String) -> void:
	var q := driver.query
	var p := driver.local_player
	var hs := PackedInt32Array()
	match what:
		"hq":
			hs.append(q.players().hq_b[p])
		"herd":
			var H := q.herds()
			for h in H.hw:
				if H.owner[h] == p and H.state[h] != HerdTable.State.FREE and H.heads(h) > 10:
					hs.append(H.handle(h))
					break
		"squad":
			if _mem.has("squad"):
				hs = q.members(_mem["squad"]) if Ids.kind(_mem["squad"]) == Ids.Kind.SQUAD else PackedInt32Array([_mem["squad"]])
		"none":
			pass
		_:
			return
	scene.selection.set_selection(hs)


# ================================================================= действия (как из интерфейса)

func _noop() -> void:
	pass


## Запас для показа: дерево, камень, золото, еда (кирпич Коканду — на Бурж)
func _boost() -> void:
	var e := driver.game.econ as EconomySim
	var p := driver.local_player
	for id in ["food", "wood", "stone", "gold", "brick"]:
		var r := driver.game.defs.res(StringName(id))
		if r >= 0 and driver.game.defs.r_enabled[r] == 1:
			e.players.res[p * e.R + r] += 2_000_000 if id != "brick" else 300_000
	print("[проход] запас: +2000 еды, дерева, камня, золота; +300 кирпича (для показа)")


## Нанять работников, послать на дерево, камень и золото
func _start_economy() -> void:
	var q := driver.query as GameQueryImpl
	var p := driver.local_player
	var defs := q.defs()
	var f := q.players().faction[p]
	var hq := q.players().hq_b[p]
	driver.issue(SimCmd.train(hq, defs.f_worker[f], 5))
	var ws := _workers()
	var hq_pos := AiController.hq_pos(q, p)
	if ws.size() >= 6:
		driver.issue(SimCmd.gather(ws.slice(0, 2), _nearest_node(hq_pos, true)))
		driver.issue(SimCmd.gather(ws.slice(2, 4), _nearest_node(hq_pos, false, &"stone")))
		driver.issue(SimCmd.gather(ws.slice(4, 5), _nearest_node(hq_pos, false, &"gold")))
	driver.issue(SimCmd.rally(hq, hq_pos + Vector2(-20 if faction == "kokand" else 20, 14)))


## Призрак: дом в хорошем месте (зелёный) и в плохом (на ставке — красный)
func _ghosts() -> void:
	var q := driver.query
	var input := scene.play.input
	var house := q.defs().building(&"uy" if faction == "kokand" else &"boz")
	input.begin_place(house)
	var hq := AiController.hq_pos(q, driver.local_player)
	var good := _free_spot(house, hq + Vector2(-26 if faction == "kokand" else 26, 30))
	input.placement.move(good)
	_mem["house_spot"] = good
	var plan_pts := PackedVector2Array([hq + Vector2(-34, -6), hq + Vector2(-34, 30)]) if faction == "kokand" \
		else PackedVector2Array([hq + Vector2(34, -6), hq + Vector2(34, 30)])
	var wt := q.defs().building(&"devor" if faction == "kokand" else &"chep")
	scene.ghost.show_wall(q.plan_wall(driver.local_player, wt, plan_pts), wt, true)
	scene.camera.go_to(Vector4(good.x, good.y, 54.0, -58.0 if faction == "kokand" else 122.0), true)


## Призрак на ставке — красный (место занято)
func _ghost_bad() -> void:
	var q := driver.query
	var input := scene.play.input
	var big := q.defs().building(&"kazarma" if faction == "kokand" else &"jylky")
	var hq := AiController.hq_pos(q, driver.local_player)
	scene.ghost.hide_ghost()
	input.begin_place(big)
	input.placement.move(hq + Vector2(4, 6))
	scene.camera.go_to(Vector4(hq.x, hq.y, 64.0, -58.0 if faction == "kokand" else 122.0), true)


## Esc — меню паузы
func _pause_menu() -> void:
	scene.play.hud.open_menu()


func _close_menu() -> void:
	if scene.play.hud.menu.visible:
		scene.play.hud.menu.close()


## Поле (Коканд — у арыка) или короо (кыпчаки) и дом
func _build_farm_house() -> void:
	var q := driver.query
	var defs := q.defs()
	var hq := AiController.hq_pos(q, driver.local_player)
	var ws := _workers()
	var house := defs.building(&"uy" if faction == "kokand" else &"boz")
	driver.issue(SimCmd.build(ws.slice(5, 6), house, _mem.get("house_spot", hq + Vector2(-26, 30)), 0))
	if faction == "kokand":
		var dala := defs.building(&"dala")
		var at := _free_spot(dala, Vector2(146, -30))
		_mem["field"] = at
		driver.issue(SimCmd.build(ws.slice(5, 6), dala, at, 0))
	else:
		var koroo := defs.building(&"koroo")
		var at := _free_spot(koroo, hq + Vector2(40, 50))
		driver.issue(SimCmd.build(ws.slice(5, 6), koroo, at, 0))
		# жылкы короосу — кони (ресурс конницы) и найм чабуулов
		var yard := defs.building(&"jylky")
		driver.issue(SimCmd.build(ws.slice(4, 6), yard, _free_spot(yard, hq + Vector2(30, -40)), 0))


func _farm() -> void:
	if faction != "kokand":
		return
	var q := driver.query
	var B := q.buildings()
	var dala := q.defs().building(&"dala")
	for b in B.hw:
		if B.owner[b] == driver.local_player and B.btype[b] == dala and B.state[b] == BuildingTable.State.ACTIVE:
			var free := 4 - B.workers_n[b]
			var idle := q.idle_workers(driver.local_player)
			if idle.size() > 0 and free > 0:
				driver.issue(SimCmd.gather(idle.slice(0, free), B.handle(b)))
			print("[проход] на поле: +%d работников" % mini(idle.size(), maxi(free, 0)))
			return
	print("[проход] поле ещё не готово")


## Линия стены поперёк пути врага: 3 работника
func _walls() -> void:
	var q := driver.query
	var p := driver.local_player
	var hq := AiController.hq_pos(q, p)
	var e := AiController.enemy_of(q, p)
	var ehq := AiController.hq_pos(q, e)
	var fwd := Vector2(signf(ehq.x - hq.x), 0.0)
	var mid := hq + fwd * (40.0 if faction == "kokand" else 44.0) + Vector2(0, 4)
	var a := mid + Vector2(0, -22)
	var b := mid + Vector2(0, 22)
	_mem["wall_mid"] = mid
	_mem["wall_a"] = a
	_mem["wall_b"] = b
	var wt := q.defs().building(&"devor" if faction == "kokand" else &"chep")
	driver.issue(SimCmd.build_wall(_near_workers(mid, 3), wt, PackedVector2Array([a, b])))


func _gate_tower() -> void:
	var q := driver.query
	var defs := q.defs()
	var gt := defs.building(&"darvoza" if faction == "kokand" else &"darbaza")
	# ворота — ближе к середине стены, где можно (звено могло не встать: дерево, жила)
	var a: Vector2 = _mem["wall_a"]
	var b: Vector2 = _mem["wall_b"]
	var at: Vector2 = _mem["wall_mid"]
	for k in [0.5, 0.42, 0.58, 0.34, 0.66, 0.26, 0.74]:
		var c: Vector2 = a + (b - a) * float(k)
		if q.check_place(driver.local_player, gt, c, 0) == NavApi.Why.OK:
			at = c
			break
	_mem["gate"] = at
	driver.issue(SimCmd.build(_near_workers(at, 3), gt, at, 0))
	if faction != "kokand":
		_tower()           # Бурж Коканда — позже, когда Хумдон готов


## Башня на стене: первое место вдоль линии, где можно (Бурж — после Хумдона)
func _tower() -> void:
	var q := driver.query
	var defs := q.defs()
	var tt := defs.building(&"burj" if faction == "kokand" else &"munara")
	var a: Vector2 = _mem["wall_a"]
	var b: Vector2 = _mem["wall_b"]
	for k in [0.15, 0.85, 0.3, 0.7]:
		var at := q.snap(tt, a + (b - a) * k, 0)
		if q.check_place(driver.local_player, tt, at, 0) == NavApi.Why.OK:
			driver.issue(SimCmd.build(_near_workers(at, 3), tt, at, 0))
			return
	print("[проход] башне нет места на стене")


## Коканд: Хумдон у арыка (кирпич на Бурж)
func _kiln() -> void:
	if faction != "kokand":
		return
	var q := driver.query
	var xd := q.defs().building(&"xumdon")
	var at := _free_spot(xd, Vector2(152, -20))
	driver.issue(SimCmd.build(_near_workers(at, 3), xd, at, 0))


func _barracks() -> void:
	var q := driver.query
	var kz := q.defs().building(&"kazarma")
	var hq := AiController.hq_pos(q, driver.local_player)
	var at := _free_spot(kz, hq + Vector2(-2, 40))
	_mem["barracks_at"] = at
	driver.issue(SimCmd.build(_near_workers(at, 4), kz, at, 0))


func _train_squad() -> void:
	var q := driver.query
	var defs := q.defs()
	var B := q.buildings()
	var kz := defs.building(&"kazarma")
	for b in B.hw:
		if B.owner[b] == driver.local_player and B.btype[b] == kz and B.state[b] == BuildingTable.State.ACTIVE:
			driver.issue(SimCmd.train(B.handle(b), defs.unit(&"sarboz"), 4))
			driver.issue(SimCmd.train(B.handle(b), defs.unit(&"yuzboshi"), 1))
			return
	print("[проход] казарма не готова")


## Офицер + свободные сарбозы → отряд (U)
func _form_squad() -> void:
	var q := driver.query as GameQueryImpl
	var officer := 0
	var men := PackedInt32Array()
	for u in q.units_of(driver.local_player):
		var t := q.unit_type(u)
		if t == &"yuzboshi" and officer == 0:
			officer = u
		elif t == &"sarboz":
			men.append(u)
	if officer == 0 or men.is_empty():
		print("[проход] отряд не собрать: офицер %d, сарбозов %d" % [officer, men.size()])
		return
	var ids := PackedInt32Array([officer])
	ids.append_array(men)
	driver.issue(SimCmd.form_squad(officer, men))
	_mem["squad"] = officer


func _disband() -> void:
	var q := driver.query
	if not _mem.has("squad"):
		return
	var s: int = q.squad_of(_mem["squad"])
	if s != Ids.NULL:
		driver.issue(SimCmd.disband(s))


## Кыпчаки: свернуть весь лагерь (Shift+K)
func _pack() -> void:
	var q := driver.query
	var hq := q.players().hq_b[driver.local_player]
	_mem["camp"] = AiController.hq_pos(q, driver.local_player)
	driver.issue(SimCmd.pack_all(hq))


## Развернуть арбы в 50 м восточнее (K у курсора)
func _unpack() -> void:
	var q := driver.query as GameQueryImpl
	var arbas := PackedInt32Array()
	for u in q.units_of(driver.local_player):
		if q.unit_type(u) == &"arba":
			arbas.append(u)
	var to: Vector2 = _mem.get("camp", Vector2(-170, 110)) + Vector2(50, 0)
	_mem["camp"] = to
	if not arbas.is_empty():
		driver.issue(SimCmd.unpack(arbas, to))
	else:
		print("[проход] арб нет")


## Кыпчаки: чабуулы из жылкы короосу (кони — ресурс)
func _train_raiders() -> void:
	var q := driver.query
	var defs := q.defs()
	var B := q.buildings()
	var p := driver.local_player
	var e := driver.game.econ as EconomySim
	var r := defs.res(&"horse")
	if r >= 0:
		e.players.res[p * e.R + r] += 12_000      # кони для показа (табуны ещё малы)
	for b in B.hw:
		if B.owner[b] == p and B.state[b] == BuildingTable.State.ACTIVE and defs.b_trains[B.btype[b]].has(defs.unit(&"chabuulchu")):
			driver.issue(SimCmd.train(B.handle(b), defs.unit(&"chabuulchu"), 5))
			driver.issue(SimCmd.train(B.handle(b), defs.unit(&"chabuulchu"), 5))
			return
	print("[проход] негде нанять чабуулов")


## Набег кыпчаков на поля Коканда: atack-move к ближайшим работникам врага
func _raid_out() -> void:
	var q := driver.query as GameQueryImpl
	var raiders := PackedInt32Array()
	for u in q.units_of(driver.local_player):
		if q.unit_type(u) == &"chabuulchu":
			raiders.append(u)
	_mem["raiders"] = raiders
	var e := AiController.enemy_of(q, driver.local_player)
	var target := AiController.hq_pos(q, e)
	for u in q.units_of(e):
		if q.unit_flags(u) & UnitStats.WORKER:
			target = q.unit_pos(u)
			break
	if not raiders.is_empty():
		driver.issue(SimCmd.attack_move(raiders, target))


func _win() -> void:
	var q := driver.query
	var e := AiController.enemy_of(q, driver.local_player)
	_destroy_hq(e)


func _lose() -> void:
	_destroy_hq(driver.local_player)


func _destroy_hq(p: int) -> void:
	var g := driver.game
	var hq := g.econ.players.hq_b[p]
	if hq != Ids.NULL and g.econ.buildings.valid(hq):
		print("[проход] ставка игрока %d снесена сценарием (показ конца партии)" % p)
		(g.econ as EconomySim).destroy_building(g.econ.buildings.slot(hq), 1 - p)
	for i in 3:
		driver.step()


# ================================================================= помощники

## n работников, ближайших к точке (свободные — первыми): строители не идут через всю карту
func _near_workers(at: Vector2, n: int) -> PackedInt32Array:
	var q := driver.query as GameQueryImpl
	var idle := q.idle_workers(driver.local_player)
	var list: Array = []
	for u in _workers():
		var d := q.unit_pos(u).distance_squared_to(at) - (1.0e6 if idle.has(u) else 0.0)
		list.append([d, u])
	list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out := PackedInt32Array()
	for it: Array in list.slice(0, n):
		out.append(int(it[1]))
	return out


func _workers() -> PackedInt32Array:
	var q := driver.query as GameQueryImpl
	var out := PackedInt32Array()
	for u in q.units_of(driver.local_player):
		if q.unit_flags(u) & UnitStats.WORKER:
			out.append(u)
	return out


func _nearest_node(from: Vector2, tree: bool, res := &"") -> int:
	var q := driver.query
	var N := q.nodes()
	var defs := q.defs()
	var best := Ids.NULL
	var bd := INF
	for n in N.hw:
		var nt := N.ntype[n]
		if nt < 0 or N.amount_milli[n] == 0:
			continue
		if (defs.n_scatter_kind[nt] >= 0) != tree:
			continue
		if res != &"" and defs.n_ids[nt] != String(res):
			continue
		var d := Vector2(N.x[n], N.z[n]).distance_squared_to(from)
		if d < bd:
			bd = d
			best = N.handle(n)
	return best


## Свободное место для постройки у точки (по спирали, шаг 6 м); поле — только «у воды» (призрак синий)
func _free_spot(bt: int, near: Vector2) -> Vector2:
	var q := driver.query
	var p := driver.local_player
	var e := driver.game.econ as EconomySim
	var wet := q.defs().b_water_place[bt] > 0
	for ring in 12:
		for k in maxi(1, ring * 8):
			var a := TAU * k / maxi(1, ring * 8)
			var c := q.snap(bt, near + Vector2(cos(a), sin(a)) * ring * 6.0, 0)
			if q.check_place(p, bt, c, 0) == NavApi.Why.OK and (not wet or e.ghost_water(p, bt, c) == 1000):
				return c
	return q.snap(bt, near, 0)


func _centroid(hs: PackedInt32Array) -> Vector2:
	var q := driver.query as GameQueryImpl
	var c := Vector2.ZERO
	var n := 0
	for h in hs:
		if q.unit_alive(h):
			c += q.unit_pos(h)
			n += 1
	return c / n if n > 0 else Vector2.INF


func _enemy_units_near(at: Vector2, r: float) -> Vector2:
	var q := driver.query as GameQueryImpl
	var e := AiController.enemy_of(q, driver.local_player)
	var c := Vector2.ZERO
	var n := 0
	for u in q.units_of(e):
		var p := q.unit_pos(u)
		if p.distance_to(at) < r and q.unit_alive(u):
			c += p
			n += 1
	return c / n if n > 0 else Vector2.INF


## Строка состояния: такт, ресурсы, население, события с прошлой сцены
func _log(name: String) -> void:
	var q := driver.query
	var p := driver.local_player
	var defs := q.defs()
	var P := q.players()
	var e := driver.game.econ as EconomySim
	var res := []
	for r in defs.R:
		if defs.r_enabled[r] == 1:
			res.append("%s %d" % [defs.res_ids[r], e.res(p, r) / 1000])
	var E := q.events()
	var rr := E.range_since(_ev)
	var seen := {}
	for seq in range(rr.x, rr.y):
		var i := E.at(seq)
		if E.e_player[i] == p or E.e_kind[i] in [SimEvents.Ev.RAID_WARNING, SimEvents.Ev.RAID_STARTED, SimEvents.Ev.VICTORY,
				SimEvents.Ev.PLAYER_DEFEATED]:
			var k: String = SimEvents.Ev.keys()[E.e_kind[i]]
			if E.e_kind[i] == SimEvents.Ev.CMD_REJECTED:
				k = "CMD_REJECTED(%s, %d)" % [SimCmd.Op.keys()[E.e_a[i]], E.e_b[i]]
			seen[k] = int(seen.get(k, 0)) + 1
	_ev = rr.y
	print("[проход] %s | %s | население %d/%d | юнитов %d | события: %s" % [name, ", ".join(res), P.pop_used[p], P.pop_cap[p],
		(q as GameQueryImpl).units_of(p).size(), str(seen)])
