extends Node3D
## Сцена проверки интерфейса «Города» (scenes/test/ui_city.tscn): живой поддельный город (FakeCityDriver),
## мир среза, лагерь, юниты (BattleView), RtsCamera, CityHud, RtsInput, запасной призрак.
## До I4 — вместо gorod.tscn (VIEW). Кадры:
##   tools/shot.sh res://scenes/test/ui_city.tscn out.png --at=6 -- --faction=kipchak --sel=building
## Параметры:
##   --faction=kokand|kipchak   за кого играем (игрок 0 / 1 в FakeCity)
##   --sel=none|squad|workers|building|hq|single|node|herd|enemy|<id постройки>   что выделить к кадру
##                              (enemy — ставка врага; id — своя постройка этого рода, например kazarma)
##   --bg=live|still|<путь.png>  live — мир и юниты (медленно на процессоре); still — кадр среза под интерфейсом
##   --tab=orders|economy|fort  открытая вкладка
##   --place=<id постройки>     показать режим постройки (призрак)
##   --skip=секунды             сразу промотать поддельный город (таймер набега, записки, стройки)
##   --menu=main|help           открыть меню / памятку клавиш
##   --armed=<приказ>           взвести кнопку сетки (move, attack_move, gather, assist, rally)
##   --view=x,z,расстояние,азимут   свой вид камеры вместо VIEWS

const STILLS := {"kokand": "res://docs/shots/03_rts.jpg", "kipchak": "res://docs/shots/02_camp_life.jpg"}
## Виды камеры по сторонам: (x, z, расстояние, азимут)
const VIEWS := {"kokand": Vector4(124.0, 66.0, 56.0, 32.0), "kipchak": Vector4(-62.0, 34.0, 112.0, 14.0)}

var driver: FakeCityDriver
var camera: RtsCamera
var hud: CityHud
var input: RtsInput
var selection := SelectionModel.new()
var faction := "kokand"
var player := 0
var _sel_mode := "none"
var _sel_done := false
var _t := 0.0
var _place := ""
var _tab := "orders"
var _menu := ""
var _armed := ""


func _ready() -> void:
	var ordo := get_node_or_null("/root/Ordo")
	var arg := func(n: String, d: String) -> String: return String(ordo.arg(n, d)) if ordo else d
	faction = arg.call("faction", "kokand")
	player = 1 if faction == "kipchak" else 0
	_sel_mode = arg.call("sel", "squad" if faction == "kokand" else "building")
	_place = arg.call("place", "")
	_tab = arg.call("tab", "orders")
	_menu = arg.call("menu", "")
	_armed = arg.call("armed", "")
	var bg: String = arg.call("bg", "live")
	if bg == "live":
		add_child(load("res://scenes/world/world.tscn").instantiate())
		add_child(load("res://scenes/camp/camp.tscn").instantiate())
	else:
		_still(STILLS[faction] if bg == "still" else bg)
	driver = FakeCityDriver.new()
	driver.name = "Driver"
	add_child(driver)
	camera = RtsCamera.new()
	camera.name = "CamCity"
	camera.fov = 50.0
	camera.far = 6000.0
	camera.presets_enabled = false
	var v: Vector4 = VIEWS[faction]
	var vs := String(arg.call("view", "")).split(",")
	if vs.size() == 4:
		v = Vector4(vs[0].to_float(), vs[1].to_float(), vs[2].to_float(), vs[3].to_float())
	camera.focus = Vector3(v.x, 0.0, v.y)
	camera.distance = v.z
	camera.yaw_deg = v.w
	camera.pitch_near = 30.0
	camera.pitch_far = 58.0
	camera.presets = [Vector4(184, 56, 140, 20), Vector4(-60, 30, 140, 12), Vector4(112, 120, 80, 0), Vector4(0, 40, 260, 15)]
	add_child(camera)
	camera.make_current()
	input = RtsInput.new()
	input.name = "RtsInput"
	add_child(input)
	var ghost := DebugGhost.new()
	ghost.name = "Ghost"
	add_child(ghost)
	input.set_ghost(ghost)
	var city := driver.city
	var p := player
	input.setup(driver.query, selection, player, func(c: PackedInt32Array) -> void: city.submit(p, c), camera, driver)
	hud = CityHud.new()
	add_child(hud)
	hud.setup(driver.query, driver, selection, player, camera, input)
	camera.edge_blocked = hud.blocks_edge_pan
	# промотать поддельный город (кадры: таймер набега, записки) — до вида юнитов, чтобы тот взял всех
	var skip := float(arg.call("skip", "0"))
	for i in roundi(skip * 30.0):
		driver.step()
	if bg == "live":
		var view := BattleView.new()
		view.name = "View"
		view.scenario_path = ^"../Driver"
		view.ambient_path = ^"../NoAmbient"
		add_child(view)


func _still(path: String) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(img) if img else null
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	layer.add_child(tr)
	# чтобы мир не рисовался вовсе — пустая камера
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CANVAS
	add_child(env)


func _process(delta: float) -> void:
	_t += delta
	if not _sel_done and _t > 0.6:
		_sel_done = true
		_preset_selection()
		if _tab != "orders":
			hud.open_tab(StringName(_tab))
		if _place != "":
			var defs := driver.query.defs()
			input.begin_place(defs.building(StringName(_place)))
			var v: Vector4 = VIEWS[faction]
			input.placement.move(Vector2(v.x + 10.0, v.y - 6.0))
		if _armed != "":
			input.order_button(SimCmd.Op.get(_armed.to_upper(), SimCmd.Op.NONE))
		if _menu != "":
			hud.open_menu()
			if _menu == "help":
				hud.menu.show_help()


## Выделение к кадру
func _preset_selection() -> void:
	var q := driver.query
	var bs := q.battle()
	var team := q.players().team[player]
	var hs := PackedInt32Array()
	# массивы ядра — в локальные (CONTRACT §10.2 п. 9)
	var side := bs.u_side
	var life := bs.u_life
	var usq := bs.u_squad
	var types := bs.u_type
	var tf := bs.t_flags
	var single := bs.sq_single
	var members := bs.sq_members
	match _sel_mode:
		"squad":
			# все отряды своей стороны (не одиночки)
			for u in bs.n:
				if side[u] == team and life[u] == BattleSim.Life.ALIVE and single[usq[u]] == 0 and members[usq[u]].size() > 1:
					hs.append(q.unit_handle(u))
		"workers", "single":
			for u in bs.n:
				if side[u] == team and life[u] == BattleSim.Life.ALIVE and tf[types[u]] & UnitStats.WORKER:
					hs.append(q.unit_handle(u))
					if _sel_mode == "single":
						break
		"building", "hq":
			var bt := q.buildings()
			var defs := q.defs()
			var want := defs.f_hq[q.players().faction[player]]
			for b in bt.hw:
				if bt.owner[b] != player or bt.state[b] != BuildingTable.State.ACTIVE:
					continue
				if _sel_mode == "hq" and bt.btype[b] == want:
					hs.append(bt.handle(b))
					break
				if _sel_mode == "building" and not defs.b_trains[bt.btype[b]].is_empty() and bt.btype[b] != want:
					hs.append(bt.handle(b))
					break
			if hs.is_empty():
				hs.append(q.players().hq_b[player])
		"node":
			# ближайшая к виду жила (не дерево)
			var nt := q.nodes()
			var v: Vector4 = VIEWS[faction]
			var best := 1e9
			for n in nt.hw:
				if nt.ntype[n] >= 0 and nt.scatter_ref[n] < 0 and nt.amount_milli[n] != 0:
					var d := Vector2(nt.x[n], nt.z[n]).distance_to(Vector2(v.x, v.y))
					if d < best:
						best = d
						hs = PackedInt32Array([nt.handle(n)])
		"herd":
			var ht := q.herds()
			for h in ht.hw:
				if ht.state[h] != HerdTable.State.FREE and ht.owner[h] == player:
					hs.append(ht.handle(h))
					break
		"enemy":
			hs.append(q.players().hq_b[1 - player])
		_:
			var want := q.defs().building(StringName(_sel_mode))
			var bt := q.buildings()
			for b in bt.hw:
				if want >= 0 and bt.owner[b] == player and bt.btype[b] == want and bt.state[b] != BuildingTable.State.FREE:
					hs.append(bt.handle(b))
					break
	selection.set_selection(hs)
