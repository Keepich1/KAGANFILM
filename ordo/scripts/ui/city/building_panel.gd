class_name CityBuildingPanel
extends Control
## Панель здания (ARCHITECTURE §14): имя, состояние, прочность; очередь найма с ходом головы
## (щелчок по месту — отменить); кнопки найма с ценой и причиной недоступности по-русски;
## загон — отара и трава, поле — полив, башня — гарнизон; что здание даёт (из Defs).
## Данные — GameQuery.building_panel. Строение — при смене здания/набора кнопок и ширины; числа — каждое обновление.
## Чужое здание — только посмотреть: очередь без отмены, кнопок найма нет.
## Узкая бумага (холст 1600 при окне 1280×720), когда всё в ряд не влезает, — сжатая раскладка: медальон
## меньше, очередь найма — в левом столбце под прочностью, на бумаге две строки о здании; найм и обмен —
## во всю правую часть.

const SLOT := 48.0
const SLOT_COMPACT := 38.0
const TRAIN := 64.0
## Зазор между ценами разных ресурсов под кнопкой найма
const COST_GAP := 5.0
## Левый столбец (медальон, имя, прочность, строки о здании): обычный и сжатый
const LEFT_W := 400.0
const LEFT_COMPACT := 336.0
## Строк о здании на бумаге (остальные — в подсказке); в сжатой раскладке с очередью — EXTRA_LINES_COMPACT
const EXTRA_LINES := 3
const EXTRA_LINES_COMPACT := 2
## Обмен на базаре: партия (как rules.trade.lot в Сб. 1; панель ECON может дать trade_lot) и ширина столбца
const TRADE_LOT := 100
const TRADE_COL := 132.0

var hud: CityHud
var _sig := ""
var _handle := 0
var _state: Label
var _hp_bar: CityBar
var _hp_txt: Label
var _slots: Array[Dictionary] = []      # {icon: TextureRect, bar: CityBar}
var _extra: Label
var _grass: CityBar
## Состояние умения под кнопкой (по панели ECON: действует / через / готово)
var _ability_state: Label
## Сжатая раскладка (тесты и кадры) и строк о здании на бумаге
var compact := false
var _extra_lines := EXTRA_LINES


func setup(p_hud: CityHud) -> void:
	hud = p_hud
	name = "BuildingPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# окно сменило размер — при следующем показе собрать заново под новую ширину
	resized.connect(func() -> void: _sig = "")


func show_panel(d: Dictionary) -> void:
	if d.is_empty():
		return
	var own := is_own(int(d.get("handle", 0)))
	var sig := "%d|%d|%s|" % [int(d.get("handle", 0)), int(d.get("state", 0)), str(own)]
	if own:
		for t: Dictionary in d.get("trains", []):
			sig += "%d:%s:%s;" % [int(t.get("utype", -1)), str(t.get("enabled", false)), t.get("why", "")]
	sig += "|%d|%d|%s" % [(d.get("queue", []) as Array).size(), (d.get("trade", {}) as Dictionary).size(), str(d.has("ability"))]
	if sig != _sig:
		_sig = sig
		_rebuild(d)
	_update(d)


func _rebuild(d: Dictionary) -> void:
	for ch in get_children():
		ch.queue_free()
	_slots.clear()
	_grass = null
	_ability_state = null
	_handle = int(d.get("handle", 0))
	var defs := hud.query.defs()
	var bt := int(d.get("btype", 0))
	var st := int(d.get("state", 0))
	# чужое здание — только посмотреть: очередь без отмены, найма нет (и не видно, что чужим по карману)
	var own := is_own(_handle)
	var trains: Array = d.get("trains", []) if own else []
	var queue: Array = d.get("queue", [])
	var has_queue := not trains.is_empty() or not queue.is_empty()
	var ab: Dictionary = defs.b_ability[bt] if bt >= 0 and bt < defs.b_ability.size() else {}
	var show_ab := not ab.is_empty() and own and st == BuildingTable.State.ACTIVE
	var rates: Dictionary = d.get("trade", {})
	var show_trade := not rates.is_empty() and own and st == BuildingTable.State.ACTIVE and trains.is_empty()
	# столбец найма не уже кнопки; цена шире столбца — в две строки (_cost_row)
	var col_min := TRAIN + 18.0
	# всё в ряд в обычной раскладке; не влезает в бумагу — сжатая
	var need := LEFT_W + (BuildingTable.QMAX * (SLOT + 6.0) + 28.0 if has_queue else 0.0) \
		+ trains.size() * col_min + (TRAIN + 40.0 if show_ab else 0.0) \
		+ (_trade_count(defs, rates) * TRADE_COL if show_trade else 0.0)
	compact = size.x > 0.0 and need > size.x
	var md := 80.0 if compact else 96.0
	var tx := md + 18.0
	var bar_w := 140.0 if compact else 180.0
	var roundel := CityRoundel.new()
	roundel.color = UiTheme.TEAM[hud.team_of_building(_handle) % 4]
	roundel.icon = UiTheme.building_icon(defs, bt)
	roundel.portrait = UiTheme.building_portrait(defs, bt)     # модель постройки, если снята; иначе значок
	roundel.position = Vector2(4, 6)
	roundel.size = Vector2(md, md)
	add_child(roundel)
	var nm := UiTheme.label(String(d.get("name", "")), UiTheme.head_bold(), 26 if compact else 28, true)
	nm.position = Vector2(tx - 2.0, 0)
	add_child(nm)
	_state = UiTheme.label("", UiTheme.italic(500), 18, true)
	_state.position = Vector2(tx, 34 if compact else 36)
	_state.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	add_child(_state)
	_hp_bar = CityBar.new()
	_hp_bar.color = UiTheme.HP
	_hp_bar.position = Vector2(tx, 64 if compact else 66)
	_hp_bar.size = Vector2(bar_w, 11)
	_hp_bar.tooltip_text = tr("Прочность")
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_hp_bar)
	_hp_txt = UiTheme.label("", UiTheme.text(600), 16, true)
	_hp_txt.position = Vector2(tx + bar_w + 6.0, _hp_bar.position.y - 6.0)
	add_child(_hp_txt)
	var herd: Dictionary = d.get("herd", {})
	if not herd.is_empty():
		_grass = CityBar.new()
		_grass.color = Color("#7a9a3a")
		_grass.position = Vector2(tx, 79 if compact else 84)
		_grass.size = Vector2(bar_w, 7 if compact else 9)
		_grass.tooltip_text = tr("Трава под отарой")
		_grass.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(_grass)
	var x := LEFT_COMPACT if compact else LEFT_W
	var extra_y := 108.0
	_extra_lines = EXTRA_LINES
	if has_queue:
		var s_sz := SLOT_COMPACT if compact else SLOT
		var gap := 4.0 if compact else 6.0
		# сжатая: ряд под прочностью в левом столбце (без заголовка; подсказки — у мест); обычная — свой столбец
		var q0 := Vector2(tx - 2.0, 88.0) if compact else Vector2(x, 32.0)
		if not compact:
			var qt := UiTheme.label(tr("Очередь найма"), UiTheme.head_bold(), 19, true)
			qt.position = Vector2(x, 0)
			add_child(qt)
		for i in BuildingTable.QMAX:
			var slot := Button.new()
			slot.position = q0 + Vector2(i * (s_sz + gap), 0)
			slot.size = Vector2(s_sz, s_sz)
			slot.focus_mode = Control.FOCUS_NONE
			slot.tooltip_text = tr("Пусто")
			if own:
				var idx := i
				slot.pressed.connect(func() -> void: hud.cancel_train(_handle, idx))
			else:
				slot.disabled = true
			add_child(slot)
			var ic := TextureRect.new()
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.position = Vector2(5, 5) if compact else Vector2(6, 6)
			ic.size = slot.size - ic.position * 2.0
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(ic)
			var bar := CityBar.new()
			bar.color = UiTheme.GOLD_LIGHT
			bar.position = slot.position + Vector2(0, s_sz + (2.0 if compact else 4.0))
			bar.size = Vector2(s_sz, 5 if compact else 7)
			bar.visible = i == 0 and not queue.is_empty()
			add_child(bar)
			_slots.append({"button": slot, "icon": ic, "bar": bar})
		if compact:
			extra_y = q0.y + s_sz + 10.0
			_extra_lines = EXTRA_LINES_COMPACT
		else:
			x += BuildingTable.QMAX * (SLOT + 6.0) + 28.0
	_extra = UiTheme.label("", UiTheme.text(500), 17, true)
	_extra.position = Vector2(8, extra_y)
	_extra.size = Vector2((LEFT_COMPACT - 12.0) if compact else 380.0, 178.0 - extra_y)
	_extra.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_extra)
	var step := 0.0
	if not trains.is_empty():
		var tt := UiTheme.label(tr("Нанять"), UiTheme.head_bold(), 19, true)
		tt.position = Vector2(x, 0)
		add_child(tt)
		step = clampf((size.x - x - (TRAIN + 40.0 if show_ab else 0.0)) / maxf(1.0, trains.size()), col_min, 124.0)
		var two_rows := false
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
			var nm2 := UiTheme.label(String(t.get("name", "")), UiTheme.text(700), 15, true)
			nm2.position = Vector2(bx + TRAIN * 0.5 - (step - 6.0) * 0.5, 96)
			nm2.size = Vector2(step - 6.0, 18)
			nm2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nm2.clip_text = true
			nm2.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			add_child(nm2)
			var row := _cost_row(defs, cost, b.disabled)
			two_rows = two_rows or _cost_width(cost) > step - 6.0
			row.position = Vector2(bx + TRAIN * 0.5 - (step - 6.0) * 0.5, 115)
			row.size = Vector2(step - 6.0, 18)
			add_child(row)
		# причина первой недоступной кнопки — строкой (подсказка — у каждой кнопки)
		for t: Dictionary in trains:
			if t.get("why", "") != "":
				var why := UiTheme.label(String(t["why"]), UiTheme.italic(600), 16, true)
				why.position = Vector2(x, 156 if two_rows else 140)
				why.add_theme_color_override("font_color", UiTheme.RED)
				add_child(why)
				break
	# умение здания (Ҳашар у Урды, ECONOMY §2.6): кнопка в панели, клавиша V
	if show_ab:
		var ax := x + trains.size() * step + 24.0
		var at := UiTheme.label(tr("Умение"), UiTheme.head_bold(), 19, true)
		at.position = Vector2(ax - 8.0, 0)
		add_child(at)
		var b := Button.new()
		b.name = "Ability"
		b.position = Vector2(ax, 30)
		b.size = Vector2(TRAIN, TRAIN)
		b.focus_mode = Control.FOCUS_NONE
		var nm_ab := RtsInput.ability_name(ab)
		b.tooltip_text = "%s (V)\n%s" % [nm_ab, tr("Действует %d с, перезарядка %d с") % [int(ab.get("duration_s", 0)), int(ab.get("cooldown_s", 0))]]
		if ab.has("build_mult"):
			b.tooltip_text += "\n" + tr("Стройка и ремонт ×%s") % String.num(float(ab["build_mult"]), 1)
		b.pressed.connect(func() -> void:
			if hud.input:
				hud.input.use_ability(_handle))
		add_child(b)
		var ic := TextureRect.new()
		ic.texture = UiTheme.icon("ord", "build")
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.position = Vector2(8, 8)
		ic.size = Vector2(TRAIN - 16, TRAIN - 16)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
		var key := UiTheme.label("V", UiTheme.text(800), 15)
		key.position = Vector2(TRAIN - 19, TRAIN - 22)
		key.add_theme_color_override("font_color", UiTheme.GOLD_LIGHT)
		b.add_child(key)
		var an := UiTheme.label(nm_ab, UiTheme.text(700), 15, true)
		an.position = Vector2(ax - 20.0, 96)
		an.size = Vector2(TRAIN + 40.0, 18)
		an.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(an)
		if d.has("ability"):
			_ability_state = UiTheme.label("", UiTheme.italic(500), 15, true)
			_ability_state.name = "AbilityState"
			_ability_state.position = Vector2(ax - 20.0, 115)
			_ability_state.size = Vector2(TRAIN + 40.0, 18)
			_ability_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_ability_state.add_theme_color_override("font_color", UiTheme.INK_SOFT)
			add_child(_ability_state)
	# базар: обмен за золото (своё готовое здание с ценами от ECON)
	if show_trade:
		_trade_section(defs, x, rates, int(d.get("trade_lot", TRADE_LOT)))


## Столбцов обмена (все ресурсы с ценами, кроме золота)
func _trade_count(defs: Defs, rates: Dictionary) -> int:
	var gold := defs.res(&"gold")
	var n := 0
	for r: int in rates:
		if r != gold and r >= 0 and r < defs.R:
			n += 1
	return n


## Обмен на базаре (ECONOMY, Бозор): по ресурсу — значок, «Продать» за золото и «Купить» за золото партией
## lot. Цены — из панели ECON (trade {r: {sell, buy}}, −1 — нельзя); нет цен — раздела нет.
func _trade_section(defs: Defs, x: float, rates: Dictionary, lot: int) -> void:
	var gold := defs.res(&"gold")
	var tt := UiTheme.label(tr("Обмен по %d") % lot, UiTheme.head_bold(), 19, true)
	tt.position = Vector2(x, 0)
	add_child(tt)
	var keys := rates.keys()
	keys.sort()
	var col := 0
	for r: int in keys:
		if r == gold or r < 0 or r >= defs.R:
			continue
		var pr: Dictionary = rates[r]
		var cx := x + col * TRADE_COL
		var ic := TextureRect.new()
		ic.texture = UiTheme.res_icon(defs, r)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.position = Vector2(cx + (TRADE_COL - 12.0) * 0.5 - 17.0, 26)
		ic.size = Vector2(34, 34)
		ic.tooltip_text = tr(defs.r_name[r])
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(ic)
		var rows := [[int(pr.get("sell", -1)), r, gold, tr("Продать"), "+%d"], [int(pr.get("buy", -1)), gold, r, tr("Купить"), "−%d"]]
		for k in rows.size():
			var row: Array = rows[k]
			var price: int = row[0]
			var b := Button.new()
			b.name = "Trade_%s_%s" % [defs.res_ids[r], "sell" if k == 0 else "buy"]
			b.position = Vector2(cx, 64 + k * 34)
			b.size = Vector2(TRADE_COL - 12.0, 30)
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 15)
			b.disabled = price < 0
			if price >= 0:
				# монета справа: «Продать +40 ◉» — золото приходит, «Купить −110 ◉» — уходит
				b.icon = UiTheme.res_icon(defs, gold)
				b.expand_icon = true
				b.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				b.add_theme_constant_override("icon_max_width", 18)
			b.text = "%s %s" % [row[3], (row[4] as String) % price] if price >= 0 else row[3]
			b.tooltip_text = (tr("Продать %d %s за %d золота") if k == 0 else tr("Купить %d %s за %d золота")) % [
				lot, tr(defs.r_name[r]).to_lower(), price] if price >= 0 else tr("Этим здесь не торгуют")
			var give: int = row[1]
			var take: int = row[2]
			b.pressed.connect(func() -> void: hud.trade(_handle, give, take, lot * 1000))
			add_child(b)
		col += 1


## Строки о здании по-русски, тревоги впереди. Кроме договорных полей (herd, water, gar, recipe) читает и
## добавки панели ECON, если они есть: raid (разоряют), fuel (печь без топлива), dry_in_s (тўғон разрушен),
## workers {n, max}, water_places {used, cap} (сеть тўғона; старое имя — net {used, places}), otlar {n, cap},
## tax_min (подать), herd.growth / period_s (приплод). У FakeCity их нет — тогда строки по Defs.
func info_lines(defs: Defs, d: Dictionary) -> PackedStringArray:
	var alarm := PackedStringArray()
	var lines := PackedStringArray()
	var bt := int(d.get("btype", 0))
	var raid := float(d.get("raid", 0.0))
	if raid > 0.0:
		alarm.append(tr("Разоряют! %d%%") % int(raid * 100.0))
	if d.has("fuel") and not bool(d["fuel"]):
		alarm.append(tr("Нет топлива — печь стоит"))
	if int(d.get("dry_in_s", 0)) > 0:
		alarm.append(tr("Поля высохнут через %s") % UiTheme.clock(int(d["dry_in_s"]) * 30))
	var wk: Dictionary = d.get("workers", {})
	if int(wk.get("max", 0)) > 0:
		lines.append(tr("Работников: %d / %d") % [int(wk.get("n", 0)), int(wk.get("max", 0))])
	elif defs.b_work_slots[bt] > 0:
		lines.append(tr("Работников: до %d") % defs.b_work_slots[bt])
	var herd: Dictionary = d.get("herd", {})
	if not herd.is_empty():
		var s := tr("Отара: %d / %d голов") % [int(herd.get("heads", 0)), int(herd.get("cap", 0))]
		var grass := float(herd.get("grass", -1.0))
		if grass >= 0.0:
			s += tr(" · трава %d%%") % int(grass * 100.0)
		if int(herd.get("growth", 0)) > 0 and int(herd.get("period_s", 0)) > 0:
			s += tr(" · приплод +%d за %d с") % [int(herd["growth"]), int(herd["period_s"])]
		lines.append(s)
	var water := float(d.get("water", -1.0))
	if water >= 0.0:
		lines.append(tr("Полив: есть — урожай полный") if water > 0.5 else tr("Сухо (лалми) — урожай четверть"))
	# сеть воды тўғона: «Сув 6/8» (занято / мест; ECONOMY §2.3)
	var wp: Dictionary = d.get("water_places", {})
	var net: Dictionary = d.get("net", {})
	var places := int(wp.get("cap", net.get("places", 0)))
	if places > 0:
		lines.append(tr("Сув %d/%d — мест у воды") % [int(wp.get("used", net.get("used", 0))), places])
	var otlar: Dictionary = d.get("otlar", {})
	if int(otlar.get("cap", 0)) > 0:
		lines.append(tr("Отлар: %d / %d") % [int(otlar.get("n", 0)), int(otlar.get("cap", 0))])
	var gar: Dictionary = d.get("gar", {})
	if int(gar.get("cap", 0)) > 0:
		lines.append(tr("Гарнизон: %d / %d") % [int(gar.get("n", 0)), int(gar.get("cap", 0))])
	if String(d.get("recipe", "")) != "":
		lines.append(tr("Делает: %s") % d["recipe"])
	if defs.b_pop_cap[bt] > 0:
		lines.append(tr("+%d населения") % defs.b_pop_cap[bt])
	if defs.b_accepts[bt] != 0:
		# только ресурсы стороны хозяина (её балка, FactionDefs.ui_res): у кыпчаков нет камня
		var own_res := _owner_res(defs, int(d.get("handle", 0)))
		var acc := PackedStringArray()
		for r in defs.R:
			if defs.b_accepts[bt] & (1 << r) and defs.r_enabled[r] != 0 and (own_res.is_empty() or own_res.has(r)):
				acc.append(tr(defs.r_name[r]).to_lower())
		if not acc.is_empty():
			lines.append(tr("Принимает: %s") % ", ".join(acc))
	if int(d.get("tax_min", 0)) > 0:
		lines.append(tr("Подать: %d золота в минуту, пока есть Бозор") % int(d["tax_min"]))
	alarm.append_array(lines)
	return alarm


## Здание игрока (найм, отмена очереди, умение, обмен — только у своего)
func is_own(b_h: int) -> bool:
	var bt := hud.query.buildings()
	return bt.valid(b_h) and bt.owner[bt.slot(b_h)] == hud.player


## Ресурсы стороны хозяина здания (FactionDefs.ui_res); пусто — не знаем (без интерфейса, чужое без хозяина)
func _owner_res(defs: Defs, b_h: int) -> PackedInt32Array:
	if hud == null or b_h == 0:
		return PackedInt32Array()
	var bt := hud.query.buildings()
	if not bt.valid(b_h):
		return PackedInt32Array()
	var o := bt.owner[bt.slot(b_h)]
	var pt := hud.query.players()
	if o < 0 or o >= pt.count:
		return PackedInt32Array()
	return defs.f_ui_res[pt.faction[o]]


## Состояние умения по панели ECON {active_s, ready_s}: «действует 0:20» / «через 1:10» / «готово»
static func ability_state(ab: Dictionary) -> String:
	if ab.is_empty():
		return ""
	if int(ab.get("active_s", 0)) > 0:
		return TranslationServer.translate("действует %s") % UiTheme.clock(int(ab["active_s"]) * 30)
	if int(ab.get("ready_s", 0)) > 0:
		return TranslationServer.translate("через %s") % UiTheme.clock(int(ab["ready_s"]) * 30)
	return TranslationServer.translate("готово")


## Ширина цены значками в одну строку (как _cost_row: [значок 17 + число] через COST_GAP)
func _cost_width(cost: PackedInt32Array) -> float:
	var f := UiTheme.text(700)
	var w := 0.0
	var n := 0
	for r in cost.size():
		if cost[r] > 0:
			w += 18.0 + f.get_string_size(str(ceili(cost[r] / 1000.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			n += 1
	return w + maxf(0.0, (n - 1) * COST_GAP)


## Цена значками: [значок ресурса][число] по порядку ресурсов, по середине столбца; не влезает в ширину —
## переносится второй строкой (не залезает на соседний найм)
func _cost_row(defs: Defs, cost: PackedInt32Array, bad: bool) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.name = "Cost"
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", int(COST_GAP))
	row.add_theme_constant_override("v_separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for r in cost.size():
		if cost[r] <= 0:
			continue
		var one := HBoxContainer.new()
		one.add_theme_constant_override("separation", 1)
		one.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := TextureRect.new()
		ic.texture = UiTheme.res_icon(defs, r)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.custom_minimum_size = Vector2(17, 17)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		one.add_child(ic)
		var n := UiTheme.label(str(ceili(cost[r] / 1000.0)), UiTheme.text(700), 15, true)
		n.add_theme_color_override("font_color", UiTheme.RED if bad else UiTheme.INK)
		one.add_child(n)
		row.add_child(one)
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
	var lines := info_lines(defs, d)
	# на бумаге — три первых строки (тревоги впереди), все — в подсказке
	_extra.text = "\n".join(lines.slice(0, _extra_lines))
	_extra.tooltip_text = "\n".join(lines) if lines.size() > _extra_lines else ""
	var herd: Dictionary = d.get("herd", {})
	if _grass and not herd.is_empty():
		_grass.value = maxf(0.0, float(herd.get("grass", 0.0)))
	if _ability_state:
		var ab: Dictionary = d.get("ability", {})
		_ability_state.text = ability_state(ab)
	var queue: Array = d.get("queue", [])
	for i in _slots.size():
		var s: Dictionary = _slots[i]
		var ic: TextureRect = s["icon"]
		var bar: CityBar = s["bar"]
		if i < queue.size():
			var qd: Dictionary = queue[i]
			var ut := int(qd.get("utype", -1))
			ic.texture = UiTheme.unit_face(defs.unit_ids[ut] if ut >= 0 else "")
			var btn := s["button"] as Button
			btn.tooltip_text = String(qd.get("name", "")) if btn.disabled else tr("%s — щелчок отменяет") % qd.get("name", "")
			bar.value = float(qd.get("t", 0.0)) if i == 0 else 0.0
		else:
			ic.texture = null
			(s["button"] as Button).tooltip_text = tr("Пусто")
			bar.value = 0.0
