class_name CityTopBar
extends Control
## Верхняя балка (ТЗ §12, ECONOMY §1.3): резной орех с латунной полосой; слева — ячейки ресурсов из
## FactionDefs.ui_res (ресурсы с enabled false пропускаются; никакого списка в коде), население;
## посередине свисает табличка «Набег через 2:30»; справа — время, скорость, пауза, меню.
## Подсказка ячейки — приход в минуту; у еды ещё содержание войска (ECONOMY §1.3, §1.5: из Defs по живым своим).

const H := 54.0
const CHIP_W := 128.0
## Узкий холст (1600 при окне 1280×720): ячейки сужаются до CHIP_MIN, чтобы не заходить под герб.
## Холст уже 1600 (масштаб интерфейса больше 120 %) — балка, как нижняя панель, раскладывается на
## CityBottomPanel.MIN_W и ужимается целиком (fit): обе полосы интерфейса одного размера
const CHIP_MIN := 104.0
## Ячейки слева кончаются не ближе CREST_GAP к середине балки (герб — 80 в ширину)
const CREST_GAP := 54.0
const POP_EXTRA := 30.0

var hud: CityHud
## Индексы ресурсов на балке (по порядку) — тест test_ui_bind сверяет с FactionDefs
var shown_res := PackedInt32Array()

var _chips: Array[Dictionary] = []          # {r, value: Label, inc: Label, box: Control}
var _pop: Label
var _pop_box: Control
var _plaque: NinePatchRect
var _raid: Label
var _clock: Label
var _speed: Button
var _pause: Button
var _raid_on := false
var _season: Label
var _season_box: Control
## Содержание войска, милли еды в минуту (пересчёт по тяжёлому обновлению — раз в секунду)
var upkeep_milli := 0
var _upkeep_by_type := PackedInt32Array()


func setup(p_hud: CityHud) -> void:
	hud = p_hud
	name = "TopBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fit(hud.view_size())
	var beam := TextureRect.new()
	beam.name = "Beam"
	beam.texture = UiTheme.tex("beam")
	beam.stretch_mode = TextureRect.STRETCH_TILE
	beam.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	beam.offset_bottom = H + 6.0
	beam.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(beam)
	var defs := hud.query.defs()
	var f := hud.query.players().faction[hud.player]
	var x := 16.0
	for r in defs.f_ui_res[f]:
		if defs.r_enabled[r] == 0:
			continue
		shown_res.append(r)
		var chip := _chip(x, UiTheme.res_icon(defs, r))
		chip["r"] = r
		_chips.append(chip)
		x += CHIP_W
	# население
	var pc := _chip(x, UiTheme.icon("res", "people"))
	_pop = pc["value"]
	_pop_box = pc["box"]
	(pc["inc"] as Label).text = tr("население")
	(pc["inc"] as Label).add_theme_color_override("font_color", UiTheme.PARCH_DIM)
	_pop_box.custom_minimum_size.x = CHIP_W + POP_EXTRA
	x += CHIP_W + POP_EXTRA
	# сезон (Сб. 2: у сторон с чертой seasons, если сезоны включены)
	if defs.has_trait(f, "seasons") and defs.s_enabled.has(1):
		var sc := _chip(x, UiTheme.icon("res", "season"))
		_season = sc["value"]
		_season_box = sc["box"]
	# табличка набега
	_plaque = NinePatchRect.new()
	_plaque.name = "RaidPlaque"
	_plaque.texture = UiTheme.tex("plaque")
	_plaque.patch_margin_left = 30
	_plaque.patch_margin_right = 30
	_plaque.patch_margin_top = 10
	_plaque.patch_margin_bottom = 10
	_plaque.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_plaque.offset_left = -170.0
	_plaque.offset_right = 170.0
	_plaque.offset_top = 56.0
	_plaque.offset_bottom = 56.0 + 64.0
	_plaque.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_plaque)
	var ic := TextureRect.new()
	ic.texture = UiTheme.icon("res", "raid")
	ic.position = Vector2(38, 14)
	ic.size = Vector2(34, 34)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plaque.add_child(ic)
	_raid = UiTheme.label("", UiTheme.head_bold(), 26, true)
	_raid.position = Vector2(78, 12)
	_raid.size = Vector2(230, 38)
	_raid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_raid.add_theme_color_override("font_color", UiTheme.RED)
	_plaque.add_child(_raid)
	_plaque.visible = false
	# герб стороны посередине балки
	var crest := CityRoundel.new()
	crest.name = "Crest"
	crest.color = UiTheme.TEAM[hud.my_team() % 4]
	crest.icon = UiTheme.icon("crest", String(defs.f_ids[f]))
	crest.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	crest.offset_left = -40.0
	crest.offset_right = 40.0
	crest.offset_top = -4.0
	crest.offset_bottom = 76.0
	crest.tooltip_text = tr(defs.f_name[f])
	crest.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(crest)
	# справа: время, скорость, пауза, меню
	var right := HBoxContainer.new()
	right.name = "System"
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -320.0
	right.offset_right = -14.0
	right.offset_top = 6.0
	right.offset_bottom = 48.0
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 8)
	add_child(right)
	_clock = UiTheme.label("0:00", UiTheme.text(700), 24)
	_clock.custom_minimum_size = Vector2(90, 42)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clock.tooltip_text = tr("Время игры")
	_clock.mouse_filter = Control.MOUSE_FILTER_PASS
	right.add_child(_clock)
	_speed = _sys_button("", tr("Скорость игры\nЩелчок — по кругу; + и − — быстрее или медленнее"))
	_speed.text = "×1"
	_speed.custom_minimum_size = Vector2(58, 42)
	_speed.add_theme_font_override("font", UiTheme.text(700))
	_speed.add_theme_font_size_override("font_size", 19)
	_speed.pressed.connect(func() -> void: hud.cycle_speed())
	right.add_child(_speed)
	_pause = _sys_button("pause", tr("Пауза (P)\nОстановить игру и продолжить"))
	_pause.pressed.connect(func() -> void: hud.toggle_pause())
	right.add_child(_pause)
	var menu := _sys_button("menu", tr("Меню (F10, Esc)\nПродолжить, управление, начать заново, выйти"))
	menu.pressed.connect(func() -> void: hud.open_menu())
	right.add_child(menu)
	resized.connect(_layout)
	_layout()


## Во всю ширину холста view сверху; холст уже CityBottomPanel.MIN_W — раскладка на MIN_W, балка ужата
## до ширины холста (как нижняя панель — CityBottomPanel.fit)
func fit(view: Vector2) -> void:
	var s := CityBottomPanel.bar_scale(view)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	scale = Vector2(s, s)
	position = Vector2.ZERO
	size = Vector2(view.x / s, H + 46.0)


## Ячейки слева — по ширине балки: на узком холсте (1600) уже, чтобы не заходить под герб посередине
func _layout() -> void:
	var boxes: Array[Control] = []
	for c in _chips:
		boxes.append(c["box"] as Control)
	boxes.append(_pop_box)
	if _season_box:
		boxes.append(_season_box)
	var room := size.x * 0.5 - CREST_GAP - 16.0 - POP_EXTRA
	var w := clampf(room / boxes.size(), CHIP_MIN, CHIP_W) if size.x > 0.0 else CHIP_W
	var x := 16.0
	for b in boxes:
		var bw := w + (POP_EXTRA if b == _pop_box else 0.0)
		b.position.x = x
		# сначала наименьший размер: иначе size не сжимается ниже прежнего (CHIP_W)
		b.custom_minimum_size.x = bw
		b.size.x = bw
		x += bw
	queue_redraw()


func _chip(x: float, icon: Texture2D) -> Dictionary:
	var box := Control.new()
	box.position = Vector2(x, 2.0)
	box.size = Vector2(CHIP_W, H - 6.0)
	box.custom_minimum_size = box.size
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(box)
	var ic := TextureRect.new()
	ic.texture = icon
	ic.position = Vector2(0, 2)
	ic.size = Vector2(44, 44)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ic)
	var v := UiTheme.label("0", UiTheme.text(700), 25)
	v.position = Vector2(46, -2)
	box.add_child(v)
	var inc := UiTheme.label("", UiTheme.italic(500), 16)
	inc.position = Vector2(47, 25)
	box.add_child(inc)
	return {"box": box, "value": v, "inc": inc}


func _sys_button(icon: String, tip: String) -> Button:
	var b := CityTips.TipButton.new()
	b.custom_minimum_size = Vector2(44, 42)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	if icon != "":
		b.icon = UiTheme.icon("ord", icon)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_constant_override("icon_max_width", 28)
	return b


func _draw() -> void:
	# латунные розетки между ячейками
	var xs: Array[float] = []
	for c in _chips:
		xs.append((c["box"] as Control).position.x - 8.0)
	if _pop_box:
		xs.append(_pop_box.position.x - 8.0)
		xs.append(_pop_box.position.x + _pop_box.size.x - 4.0)
	for i in xs.size():
		if i == 0:
			continue
		var x: float = xs[i]
		draw_line(Vector2(x, 10), Vector2(x, H - 10), Color(0.12, 0.07, 0.03, 0.8), 3.0)
		draw_line(Vector2(x + 1.5, 10), Vector2(x + 1.5, H - 10), Color(0.85, 0.66, 0.32, 0.55), 1.0)
		draw_circle(Vector2(x + 0.5, H * 0.5 - 2.0), 3.2, Color(0.72, 0.54, 0.24))
		draw_circle(Vector2(x - 0.3, H * 0.5 - 3.0), 1.4, Color(1.0, 0.88, 0.6))


## heavy — пересчитать содержание войска (перебор своих юнитов)
func refresh(heavy := true) -> void:
	var q := hud.query
	var pt := q.players()
	var defs := q.defs()
	var p := hud.player
	var R := defs.R
	if heavy:
		upkeep_milli = army_upkeep()
	var food := defs.res(&"food")
	for c in _chips:
		var r: int = c["r"]
		var v: Label = c["value"]
		var inc: Label = c["inc"]
		var milli := pt.res[p * R + r]
		v.text = UiTheme.amount(milli)
		var per_min := pt.income[p * R + r]
		var famine := r == defs.res(&"food") and pt.famine[p] == 1
		v.add_theme_color_override("font_color", UiTheme.RED_LIGHT if famine else UiTheme.PARCH)
		if per_min != 0:
			inc.text = ("+" if per_min > 0 else "−") + str(absi(per_min) / 1000) + tr("/мин")
			inc.add_theme_color_override("font_color", UiTheme.GREEN_LIGHT if per_min > 0 else UiTheme.RED_LIGHT)
		else:
			inc.text = ""
		var tip := "%s: %s" % [tr(defs.r_name[r]), UiTheme.amount(milli)]
		if per_min != 0:
			tip += "\n" + tr("Приход: %s в минуту") % (("+" if per_min > 0 else "−") + str(absi(per_min) / 1000))
		if r == food and upkeep_milli > 0:
			tip += "\n" + tr("Содержание войска: −%s в минуту") % String.num(upkeep_milli / 1000.0, 1)
		if famine:
			tip += "\n" + tr("Голод! Войско слабеет")
		(c["box"] as Control).tooltip_text = tip
	var used := pt.pop_used[p]
	var cap := pt.pop_cap[p]
	_pop.text = "%d / %d" % [used, cap]
	_pop.add_theme_color_override("font_color", UiTheme.RED_LIGHT if used >= cap else UiTheme.PARCH)
	_pop_box.tooltip_text = tr("Население: %d из %d (предел 500)") % [used, cap]
	# набег: > 0 — отсчёт; 0 — набег идёт (GameQueryImpl: RaidDirector.eta_for в сборе, походе, ударе,
	# отходе); −1 — набега нет (FakeCity даёт −1 и во время набега — тогда по событию RAID_STARTED)
	var eta := q.raid_eta_ticks(p)
	if eta > 0:
		_plaque.visible = true
		_raid.text = tr("Набег через %s") % UiTheme.clock(eta)
		_plaque.tooltip_text = tr("Набег приближается: соберите войско, уведите работников")
	elif eta == 0 or _raid_on:
		_plaque.visible = true
		_raid.text = tr("Набег!")
		_plaque.tooltip_text = tr("Набег идёт: защищайте поля, стада и склады")
	else:
		_plaque.visible = false
	if _season:
		var s := pt.season[p]
		_season.text = tr(defs.s_name[s]) if s >= 0 and s < defs.s_name.size() else ""
	_clock.text = UiTheme.clock(q.tick())
	if hud.driver:
		_speed.text = "×%s" % str(snappedf(hud.driver.time_scale, 0.01)).trim_suffix(".0")
		_pause.icon = UiTheme.icon("ord", "play" if hud.driver.paused else "pause")
	queue_redraw()


## Сколько еды в минуту съедает войско игрока (милли): Defs.u_upkeep_milli_min по живым своим юнитам
func army_upkeep() -> int:
	var bs := hud.query.battle()
	if bs == null:
		return 0
	var defs := hud.query.defs()
	while _upkeep_by_type.size() < bs.type_ids.size():
		var u := defs.unit(StringName(bs.type_ids[_upkeep_by_type.size()]))
		_upkeep_by_type.append(defs.u_upkeep_milli_min[u] if u >= 0 else 0)
	var owner := bs.u_owner
	var life := bs.u_life
	var types := bs.u_type
	var total := 0
	for u in bs.n:
		if owner[u] == hud.player and life[u] == BattleSim.Life.ALIVE:
			total += _upkeep_by_type[types[u]]
	return total


## Набег начался / кончился (CityHud — по событиям)
func set_raid_active(on: bool) -> void:
	_raid_on = on
