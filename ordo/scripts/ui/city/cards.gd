class_name CityCards
extends Control
## Карточки выделенных (ТЗ §12): отряд — эмблема рода войск в кругу цвета стороны, имя, «×30»,
## полоски здоровья, морали и выносливости, знамя; одиночки — по роду с числом. Один юнит —
## большая карточка с числами из UnitStats. Пусто — герб стороны и подсказка управления.
## Строение карточек меняется только при смене выделения; полоски — каждое обновление.

const CARD := Vector2(128, 178)
const GAP := 8.0

var hud: CityHud
var _sig := ""
var _bars: Array[Dictionary] = []      # {hp, morale, stamina: Control (полоска), count: Label}
var _sum_count: Label
var _sum_lines: Label

const FORMS := ["линия", "колонна", "каре", "рассыпной"]


func setup(p_hud: CityHud) -> void:
	hud = p_hud
	name = "Cards"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_info(info: Dictionary) -> void:
	var cards: Array = info.get("cards", [])
	var sig := ""
	for c: Dictionary in cards:
		sig += "%s/%d/%d;" % [c.get("type", ""), c.get("squad", 0), 0 if cards.size() > 1 else int(c.get("count", 0))]
	if info.get("kind", "") != "units":
		sig = "none"
	if sig != _sig:
		_sig = sig
		_rebuild(info)
	for i in mini(_bars.size(), cards.size()):
		var c: Dictionary = cards[i]
		var b: Dictionary = _bars[i]
		(b["hp"] as CityBar).value = float(c.get("hp", 1.0))
		(b["morale"] as CityBar).value = float(c.get("morale", 1.0))
		(b["stamina"] as CityBar).value = float(c.get("stamina", 1.0))
		(b["count"] as Label).text = "×%d" % int(c.get("count", 1))
	if _sum_count and is_instance_valid(_sum_count):
		_update_summary(cards)


func _rebuild(info: Dictionary) -> void:
	for ch in get_children():
		ch.queue_free()
	_bars.clear()
	_sum_count = null
	_sum_lines = null
	var cards: Array = info.get("cards", [])
	if info.get("kind", "") != "units" or cards.is_empty():
		_empty()
		return
	if cards.size() == 1 and int(cards[0].get("count", 1)) == 1:
		_single(cards[0])
		return
	var n := mini(cards.size(), int((size.x - 300.0 + GAP) / (CARD.x + GAP)))
	for i in n:
		_card(cards[i], Vector2(i * (CARD.x + GAP), 4))
	if cards.size() > n:
		var more := UiTheme.label(tr("и ещё %d") % (cards.size() - n), UiTheme.italic(500), 18, true)
		more.position = Vector2(n * (CARD.x + GAP) - 80, CARD.y - 18)
		add_child(more)
	_summary()


## Сводка выделения справа: сколько бойцов, отрядов, строй, содержание (еда в минуту, из Defs)
func _summary() -> void:
	var box := Control.new()
	box.name = "Summary"
	box.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	box.offset_left = -290.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var line := ColorRect.new()
	line.color = Color(UiTheme.INK, 0.35)
	line.position = Vector2(-18, 8)
	line.size = Vector2(2, 160)
	box.add_child(line)
	box.add_child(_at(UiTheme.label(tr("Выбрано"), UiTheme.head_bold(), 21, true), Vector2(0, 2)))
	_sum_count = _at(UiTheme.label("0", UiTheme.text(800), 46, true), Vector2(0, 26))
	box.add_child(_sum_count)
	_sum_lines = _at(UiTheme.label("", UiTheme.italic(500), 18, true), Vector2(2, 88))
	_sum_lines.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	box.add_child(_sum_lines)


func _at(c: Control, p: Vector2) -> Control:
	c.position = p
	return c


func _update_summary(cards: Array) -> void:
	var defs := hud.query.defs()
	var total := 0
	var squads := 0
	var singles := 0
	var upkeep := 0
	var form := -1
	var bs := hud.query.battle()
	for c: Dictionary in cards:
		var n := int(c.get("count", 1))
		total += n
		var sq := int(c.get("squad", 0))
		if sq != 0:
			squads += 1
			if form < 0 and bs and Ids.slot(sq) < bs.squads:
				form = bs.sq_form[Ids.slot(sq)]
		else:
			singles += n
		var u := defs.unit(StringName(String(c.get("type", ""))))
		if u >= 0:
			upkeep += n * defs.u_upkeep_milli_min[u]
	_sum_count.text = str(total)
	var lines := PackedStringArray()
	lines.append(tr("Отрядов: %d · одиночек: %d") % [squads, singles])
	if form >= 0:
		lines.append(tr("Строй: %s") % tr(FORMS[form]))
	if upkeep > 0:
		lines.append(tr("Содержание: %s еды/мин") % String.num(upkeep / 1000.0, 1))
	_sum_lines.text = "\n".join(lines)


func _card(c: Dictionary, at: Vector2) -> void:
	var bg := NinePatchRect.new()
	bg.texture = UiTheme.tex("card")
	bg.patch_margin_left = 12
	bg.patch_margin_right = 12
	bg.patch_margin_top = 12
	bg.patch_margin_bottom = 12
	bg.position = at
	bg.size = CARD
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.tooltip_text = "%s\n%s" % [c.get("name", ""), tr("Отряд со знаменем") if c.get("banner", false) else tr("Одиночки")]
	add_child(bg)
	var team := hud.selection_team()
	var roundel := CityRoundel.new()
	roundel.color = UiTheme.TEAM[team % 4]
	roundel.icon = UiTheme.unit_icon(String(c.get("type", "")))
	roundel.portrait = UiTheme.unit_portrait(String(c.get("type", "")))
	roundel.position = Vector2(CARD.x * 0.5 - 34, 8)
	roundel.size = Vector2(68, 68)
	bg.add_child(roundel)
	if c.get("banner", false):
		var fl := TextureRect.new()
		fl.texture = UiTheme.icon("ord", "form_squad")
		fl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fl.position = Vector2(CARD.x - 36, 6)
		fl.size = Vector2(28, 28)
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(fl)
	var nm := UiTheme.label(String(c.get("name", "")), UiTheme.head_bold(), 17, true)
	nm.position = Vector2(4, 78)
	nm.size = Vector2(CARD.x - 8, 22)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	bg.add_child(nm)
	var cnt := UiTheme.label("×%d" % int(c.get("count", 1)), UiTheme.text(800), 22, true)
	cnt.position = Vector2(4, 98)
	cnt.size = Vector2(CARD.x - 8, 26)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bg.add_child(cnt)
	var bars := {"count": cnt}
	var y := 130.0
	for k in [["hp", UiTheme.HP, tr("Здоровье")], ["morale", UiTheme.MORALE, tr("Мораль")], ["stamina", UiTheme.STAMINA, tr("Выносливость")]]:
		var bar := CityBar.new()
		bar.color = k[1]
		bar.position = Vector2(12, y)
		bar.size = Vector2(CARD.x - 24, 9)
		bar.tooltip_text = k[2]
		bar.mouse_filter = Control.MOUSE_FILTER_PASS
		bg.add_child(bar)
		bars[k[0]] = bar
		y += 14.0
	_bars.append(bars)


func _single(c: Dictionary) -> void:
	var type_id := String(c.get("type", ""))
	var st := UnitStats.get_stats(type_id)
	var team := hud.selection_team()
	var roundel := CityRoundel.new()
	roundel.color = UiTheme.TEAM[team % 4]
	roundel.icon = UiTheme.unit_icon(type_id)
	roundel.portrait = UiTheme.unit_portrait(type_id)
	roundel.position = Vector2(6, 8)
	roundel.size = Vector2(112, 112)
	add_child(roundel)
	var nm := UiTheme.label(String(c.get("name", type_id)), UiTheme.head_bold(), 30, true)
	nm.position = Vector2(136, 2)
	add_child(nm)
	var role := UiTheme.label(String(st.get("role", "")), UiTheme.italic(500), 19, true)
	role.position = Vector2(138, 40)
	role.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	add_child(role)
	var lines := PackedStringArray()
	lines.append(tr("Здоровье %d") % int(round(float(c.get("hp", 1.0)) * float(st.get("hp", 0)))) + " / %d" % int(st.get("hp", 0)))
	lines.append(tr("Атака %d · Броня %d · Скорость %s м/с") % [int(st.get("attack", 0)), int(st.get("armour", 0)),
		String.num(float(st.get("speed", 0.0)), 1)])
	if int(st.get("missile", 0)) > 0:
		lines.append(tr("Выстрел %d на %d м") % [int(st.get("missile", 0)), int(st.get("range", 0))])
	var t := UiTheme.label("\n".join(lines), UiTheme.text(500), 19, true)
	t.position = Vector2(138, 70)
	add_child(t)
	var bars := {"count": UiTheme.label("", UiTheme.text(500), 1, true)}
	add_child(bars["count"])
	var y := 136.0
	for k in [["hp", UiTheme.HP], ["morale", UiTheme.MORALE], ["stamina", UiTheme.STAMINA]]:
		var bar := CityBar.new()
		bar.color = k[1]
		bar.position = Vector2(12, y)
		bar.size = Vector2(100, 10)
		add_child(bar)
		bars[k[0]] = bar
		y += 16.0
	_bars.append(bars)


func _empty() -> void:
	var f := hud.query.players().faction[hud.player]
	var defs := hud.query.defs()
	var crest := TextureRect.new()
	crest.texture = UiTheme.icon("crest", String(defs.f_ids[f]))
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.position = Vector2(10, 18)
	crest.size = Vector2(150, 150)
	crest.modulate = Color(1, 1, 1, 0.85)
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crest)
	var nm := UiTheme.label(tr(defs.f_name[f]), UiTheme.head_bold(), 34, true)
	nm.position = Vector2(184, 14)
	add_child(nm)
	var hint := UiTheme.label("\n".join([tr("ЛКМ — выбрать, рамка — несколько, двойной щелчок — все такие"),
		tr("ПКМ — идти, бить, добывать, строить; протянуть ПКМ — линия строя"),
		tr("Ctrl+1…9 — запомнить группу, 1…9 — вызвать, «.» — свободный работник")]), UiTheme.italic(500), 19, true)
	hint.position = Vector2(186, 62)
	hint.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	add_child(hint)
