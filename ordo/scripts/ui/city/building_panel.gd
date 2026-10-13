class_name CityBuildingPanel
extends Control
## Панель здания (ARCHITECTURE §14): имя, состояние, прочность; очередь найма с ходом головы
## (щелчок по месту — отменить); кнопки найма с ценой и причиной недоступности по-русски;
## загон — отара и трава, поле — полив, башня — гарнизон; что здание даёт (из Defs).
## Данные — GameQuery.building_panel. Строение — при смене здания/набора кнопок; числа — каждое обновление.

const SLOT := 48.0
const TRAIN := 64.0

var hud: CityHud
var _sig := ""
var _handle := 0
var _state: Label
var _hp_bar: CityBar
var _hp_txt: Label
var _slots: Array[Dictionary] = []      # {icon: TextureRect, bar: CityBar}
var _extra: Label
var _grass: CityBar


func setup(p_hud: CityHud) -> void:
	hud = p_hud
	name = "BuildingPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_panel(d: Dictionary) -> void:
	if d.is_empty():
		return
	var sig := "%d|%d|" % [int(d.get("handle", 0)), int(d.get("state", 0))]
	for t: Dictionary in d.get("trains", []):
		sig += "%d:%s:%s;" % [int(t.get("utype", -1)), str(t.get("enabled", false)), t.get("why", "")]
	sig += "|%d" % (d.get("queue", []) as Array).size()
	if sig != _sig:
		_sig = sig
		_rebuild(d)
	_update(d)


func _rebuild(d: Dictionary) -> void:
	for ch in get_children():
		ch.queue_free()
	_slots.clear()
	_grass = null
	_handle = int(d.get("handle", 0))
	var defs := hud.query.defs()
	var bt := int(d.get("btype", 0))
	var roundel := CityRoundel.new()
	roundel.color = UiTheme.TEAM[hud.team_of_building(_handle) % 4]
	roundel.icon = UiTheme.building_icon(defs, bt)
	roundel.position = Vector2(4, 6)
	roundel.size = Vector2(96, 96)
	add_child(roundel)
	var nm := UiTheme.label(String(d.get("name", "")), UiTheme.head_bold(), 28, true)
	nm.position = Vector2(112, 0)
	add_child(nm)
	_state = UiTheme.label("", UiTheme.italic(500), 18, true)
	_state.position = Vector2(114, 36)
	_state.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	add_child(_state)
	_hp_bar = CityBar.new()
	_hp_bar.color = UiTheme.HP
	_hp_bar.position = Vector2(114, 66)
	_hp_bar.size = Vector2(180, 11)
	_hp_bar.tooltip_text = tr("Прочность")
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_hp_bar)
	_hp_txt = UiTheme.label("", UiTheme.text(600), 16, true)
	_hp_txt.position = Vector2(300, 60)
	add_child(_hp_txt)
	_extra = UiTheme.label("", UiTheme.text(500), 17, true)
	_extra.position = Vector2(8, 108)
	_extra.size = Vector2(380, 70)
	add_child(_extra)
	var herd: Dictionary = d.get("herd", {})
	if not herd.is_empty():
		_grass = CityBar.new()
		_grass.color = Color("#7a9a3a")
		_grass.position = Vector2(114, 84)
		_grass.size = Vector2(180, 9)
		_grass.tooltip_text = tr("Трава под отарой")
		_grass.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(_grass)
	var x := 400.0
	var trains: Array = d.get("trains", [])
	var queue: Array = d.get("queue", [])
	if not trains.is_empty() or not queue.is_empty():
		var qt := UiTheme.label(tr("Очередь найма"), UiTheme.head_bold(), 19, true)
		qt.position = Vector2(x, 0)
		add_child(qt)
		for i in BuildingTable.QMAX:
			var slot := Button.new()
			slot.position = Vector2(x + i * (SLOT + 6), 32)
			slot.size = Vector2(SLOT, SLOT)
			slot.focus_mode = Control.FOCUS_NONE
			slot.tooltip_text = tr("Пусто")
			var idx := i
			slot.pressed.connect(func() -> void: hud.cancel_train(_handle, idx))
			add_child(slot)
			var ic := TextureRect.new()
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.position = Vector2(6, 6)
			ic.size = Vector2(SLOT - 12, SLOT - 12)
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(ic)
			var bar := CityBar.new()
			bar.color = UiTheme.GOLD_LIGHT
			bar.position = Vector2(x + i * (SLOT + 6), 32 + SLOT + 4)
			bar.size = Vector2(SLOT, 7)
			bar.visible = i == 0 and not queue.is_empty()
			add_child(bar)
			_slots.append({"button": slot, "icon": ic, "bar": bar})
		x += BuildingTable.QMAX * (SLOT + 6) + 28.0
	if not trains.is_empty():
		var tt := UiTheme.label(tr("Нанять"), UiTheme.head_bold(), 19, true)
		tt.position = Vector2(x, 0)
		add_child(tt)
		var step := clampf((size.x - x) / maxf(1.0, trains.size()), TRAIN + 18.0, 124.0)
		for i in trains.size():
			var t: Dictionary = trains[i]
			var bx := x + i * step + (step - TRAIN) * 0.5 - 8.0
			var b := Button.new()
			b.position = Vector2(bx, 30)
			b.size = Vector2(TRAIN, TRAIN)
			b.focus_mode = Control.FOCUS_NONE
			b.disabled = not t.get("enabled", false)
			var cost: PackedInt32Array = t.get("cost", PackedInt32Array())
			var tip := "%s\n%s: %s" % [t.get("name", ""), tr("Цена"), UiTheme.cost_text(defs, cost)]
			if t.get("why", "") != "":
				tip += "\n" + String(t["why"])
			b.tooltip_text = tip
			var ut := int(t.get("utype", -1))
			var utype_id := defs.unit_ids[ut] if ut >= 0 else ""
			b.pressed.connect(func() -> void: hud.train(_handle, ut))
			add_child(b)
			var ic := TextureRect.new()
			ic.texture = UiTheme.unit_face(utype_id)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.position = Vector2(6, 6)
			ic.size = Vector2(TRAIN - 12, TRAIN - 12)
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if b.disabled:
				ic.modulate = Color(0.55, 0.5, 0.45)
			b.add_child(ic)
			var nm2 := UiTheme.label(String(t.get("name", "")), UiTheme.text(700), 14, true)
			nm2.position = Vector2(bx + TRAIN * 0.5 - (step - 6.0) * 0.5, 96)
			nm2.size = Vector2(step - 6.0, 18)
			nm2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nm2.clip_text = true
			add_child(nm2)
			var row := _cost_row(defs, cost, b.disabled)
			row.position = Vector2(bx + TRAIN * 0.5 - (step - 6.0) * 0.5, 115)
			row.size = Vector2(step - 6.0, 18)
			add_child(row)
		# причина первой недоступной кнопки — строкой (подсказка — у каждой кнопки)
		for t: Dictionary in trains:
			if t.get("why", "") != "":
				var why := UiTheme.label(String(t["why"]), UiTheme.italic(600), 16, true)
				why.position = Vector2(x, 140)
				why.add_theme_color_override("font_color", UiTheme.RED)
				add_child(why)
				break


## Цена значками: [значок ресурса][число] по порядку ресурсов
func _cost_row(defs: Defs, cost: PackedInt32Array, bad: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 1)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for r in cost.size():
		if cost[r] <= 0:
			continue
		var ic := TextureRect.new()
		ic.texture = UiTheme.res_icon(defs, r)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.custom_minimum_size = Vector2(17, 17)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ic)
		var n := UiTheme.label(str(ceili(cost[r] / 1000.0)), UiTheme.text(700), 14, true)
		n.add_theme_color_override("font_color", UiTheme.RED if bad else UiTheme.INK)
		row.add_child(n)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(4, 1)
		row.add_child(gap)
	return row


func _update(d: Dictionary) -> void:
	var defs := hud.query.defs()
	var st := int(d.get("state", BuildingTable.State.ACTIVE))
	var prog := float(d.get("progress", 1.0))
	match st:
		BuildingTable.State.SITE:
			_state.text = tr("Стройка — %d%%") % int(prog * 100.0)
		BuildingTable.State.RUIN:
			_state.text = tr("Руины")
		BuildingTable.State.PACKED:
			_state.text = tr("Свёрнуто в арбу")
		_:
			_state.text = tr("Готово")
	var hp := int(d.get("hp", 0))
	var hpm := maxi(1, int(d.get("hp_max", 1)))
	_hp_bar.value = float(hp) / hpm
	_hp_txt.text = "%d / %d" % [hp, hpm]
	var lines := PackedStringArray()
	var bt := int(d.get("btype", 0))
	if defs.b_pop_cap[bt] > 0:
		lines.append(tr("+%d населения") % defs.b_pop_cap[bt])
	if defs.b_accepts[bt] != 0:
		var acc := PackedStringArray()
		for r in defs.R:
			if defs.b_accepts[bt] & (1 << r) and defs.r_enabled[r] != 0:
				acc.append(tr(defs.r_name[r]).to_lower())
		lines.append(tr("Принимает: %s") % ", ".join(acc))
	if defs.b_work_slots[bt] > 0:
		lines.append(tr("Работников: до %d") % defs.b_work_slots[bt])
	var herd: Dictionary = d.get("herd", {})
	if not herd.is_empty():
		lines.append(tr("Отара: %d / %d голов · трава %d%%") % [int(herd.get("heads", 0)), int(herd.get("cap", 0)),
			int(float(herd.get("grass", 0.0)) * 100.0)])
		if _grass:
			_grass.value = float(herd.get("grass", 0.0))
	var water := float(d.get("water", -1.0))
	if water >= 0.0:
		lines.append(tr("Полив: есть — урожай полный") if water > 0.5 else tr("Сухо (лалми) — урожай четверть"))
	var gar: Dictionary = d.get("gar", {})
	if int(gar.get("cap", 0)) > 0:
		lines.append(tr("Гарнизон: %d / %d") % [int(gar.get("n", 0)), int(gar.get("cap", 0))])
	if String(d.get("recipe", "")) != "":
		lines.append(tr("Делает: %s") % d["recipe"])
	_extra.text = "\n".join(lines)
	var queue: Array = d.get("queue", [])
	for i in _slots.size():
		var s: Dictionary = _slots[i]
		var ic: TextureRect = s["icon"]
		var bar: CityBar = s["bar"]
		if i < queue.size():
			var qd: Dictionary = queue[i]
			var ut := int(qd.get("utype", -1))
			ic.texture = UiTheme.unit_face(defs.unit_ids[ut] if ut >= 0 else "")
			(s["button"] as Button).tooltip_text = tr("%s — щелчок отменяет") % qd.get("name", "")
			bar.value = float(qd.get("t", 0.0)) if i == 0 else 0.0
		else:
			ic.texture = null
			(s["button"] as Button).tooltip_text = tr("Пусто")
			bar.value = 0.0
