class_name GorodPlay
extends Node
## Игра в «Городе» (ARCHITECTURE §19.7 I4): настоящая GameSim за GameDriver, интерфейс (CityHud) и
## управление (RtsInput) поверх видов сцены gorod.tscn. Местный игрок — сторона из меню (--faction или
## Ordo.set_arg("faction")), ИИ — другая. Esc / ≡ / F10 — меню паузы («Продолжить», «Управление»,
## «Начать заново», «В главное меню»); конец партии — экран победы или поражения.
## Ставит сцена (GorodScene._ready), если её драйвер — GameDriver.

const END_FADE := 0.6
## Лист экрана конца партии (без латунной рамки); место — CityHud.add_dialog: между балкой и нижней панелью
const END_SIZE := Vector2(640, 360)

var scene: Node3D
var driver: GameDriver
var camera: RtsCamera
var input: RtsInput
var hud: CityHud
var _end: Control


## Собрать игру поверх сцены: ввод — после камеры (колесо в режиме постройки), интерфейс — сверху
static func attach(p_scene: Node3D, p_driver: GameDriver, p_camera: RtsCamera, ghost: Object,
		selection: SelectionModel, overlay: Node) -> GorodPlay:
	var play := GorodPlay.new()
	play.name = "Play"
	play.scene = p_scene
	play.driver = p_driver
	play.camera = p_camera
	p_scene.add_child(play)
	play._wire(ghost, selection, overlay)
	return play


func _wire(ghost: Object, selection: SelectionModel, overlay: Node) -> void:
	var q := driver.query
	input = RtsInput.new()
	input.name = "RtsInput"
	scene.add_child(input)
	if ghost:
		input.set_ghost(ghost)
	input.setup(q, selection, driver.local_player, driver.issue, camera, driver)
	hud = CityHud.new()
	scene.add_child(hud)
	hud.setup(q, driver, selection, driver.local_player, camera, input)
	camera.presets_enabled = false
	camera.edge_blocked = hud.blocks_edge_pan
	if overlay and overlay.has_method("set_enabled"):
		input.overlay_toggled.connect(Callable(overlay, "set_enabled"))
	hud.restart_requested.connect(_restart)
	hud.quit_requested.connect(_to_menu)
	driver.battle_over.connect(_on_over)
	driver.started.connect(func(_s: int) -> void: _on_started())
	_on_started()


## Новая партия (и «Начать заново»): камера — к своей ставке, экран конца — спрятать
func _on_started() -> void:
	if _end:
		_end.queue_free()
		_end = null
	var q := driver.query
	var hq := AiController.hq_pos(q, driver.local_player)
	if hq != Vector2.INF:
		# смотреть со стороны врага на свою ставку (враг — дальше по оси долины)
		var e := AiController.enemy_of(q, driver.local_player)
		var ehq := AiController.hq_pos(q, e) if e >= 0 else Vector2.INF
		var yaw := -58.0 if ehq == Vector2.INF or ehq.x < hq.x else 122.0
		camera.go_to(Vector4(hq.x, hq.y + 6.0, 120.0, yaw), true)
		# F5–F8 (RtsInput): своя ставка, ближе к ставке, вся долина, ставка врага
		var mid := (hq + ehq) * 0.5 if ehq != Vector2.INF else hq
		var presets: Array[Vector4] = [Vector4(hq.x, hq.y + 6.0, 120.0, yaw), Vector4(hq.x, hq.y, 60.0, yaw),
			Vector4(mid.x, mid.y + 40.0, 260.0, yaw), Vector4(ehq.x, ehq.y, 140.0, yaw) if ehq != Vector2.INF else Vector4(hq.x, hq.y, 200.0, yaw)]
		camera.presets = presets


func _restart() -> void:
	driver.paused = false
	driver.restart()


func _to_menu() -> void:
	var o := get_node_or_null("/root/Ordo")
	if o == null or not o.call("to_menu"):
		get_tree().quit()


# ================================================================= конец партии

func _on_over(winner_team: int) -> void:
	if _end:
		return
	var q := driver.query
	var my_team := q.players().team[driver.local_player]
	var won := winner_team == my_team
	_end = _build_end(won)
	if hud.root:
		hud.root.add_child(_end)          # тема интерфейса (кнопки — орех и латунь)
		hud.add_dialog(_end.get_node("Sheet") as Control, END_SIZE)
	else:
		hud.add_child(_end)
	_end.modulate.a = 0.0
	create_tween().tween_property(_end, "modulate:a", 1.0, END_FADE)


func _build_end(won: bool) -> Control:
	var root := Control.new()
	root.name = "EndScreen"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var w := END_SIZE.x
	var h := END_SIZE.y
	var sheet := NinePatchRect.new()
	sheet.texture = UiTheme.tex("paper")
	for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		sheet.set(m, 30)
	sheet.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sheet.offset_left = -w * 0.5
	sheet.offset_right = w * 0.5
	sheet.offset_top = -h * 0.5
	sheet.offset_bottom = h * 0.5
	sheet.name = "Sheet"
	root.add_child(sheet)
	var frame := NinePatchRect.new()
	frame.texture = UiTheme.tex("frame_brass")
	for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		frame.set(m, 14)
	frame.draw_center = false
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = -10
	frame.offset_top = -10
	frame.offset_right = 10
	frame.offset_bottom = 10
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(frame)
	var seal := TextureRect.new()
	seal.texture = UiTheme.tex("seal_green" if won else "seal_red")
	seal.position = Vector2(w * 0.5 - 40, -34)
	seal.size = Vector2(80, 80)
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sheet.add_child(seal)
	var title := UiTheme.label(tr("Победа") if won else tr("Поражение"), UiTheme.head_bold(), 64, true)
	title.position = Vector2(0, 58)
	title.size = Vector2(w, 76)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sheet.add_child(title)
	var faction := String(driver.query.defs().f_ids[driver.query.players().faction[driver.local_player]])
	var text := ""
	if won:
		text = tr("Ставка врага пала. Долина — ваша.")
	else:
		text = tr("Урда пала.") if faction == "kokand" else tr("Ордо пало.")
	var sub := UiTheme.label(text, UiTheme.italic(), 26, true)
	sub.position = Vector2(40, 140)
	sub.size = Vector2(w - 80, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sheet.add_child(sub)
	var time := UiTheme.label(tr("Время партии: %s") % _clock(driver.game.tick), UiTheme.text(500), 22, true)
	time.position = Vector2(40, 182)
	time.size = Vector2(w - 80, 32)
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sheet.add_child(time)
	var row := HBoxContainer.new()
	row.position = Vector2(60, h - 104)
	row.size = Vector2(w - 120, 60)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	sheet.add_child(row)
	for it in [[tr("Ещё раз"), _restart], [tr("В главное меню"), _to_menu]]:
		var b := Button.new()
		b.text = it[0]
		b.custom_minimum_size = Vector2(230, 58)
		b.add_theme_font_override("font", UiTheme.head_bold())
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(it[1])
		row.add_child(b)
	return root


static func _clock(t: int) -> String:
	var s := t / 30
	return "%d:%02d" % [s / 60, s % 60]
