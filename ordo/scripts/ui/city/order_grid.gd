class_name CityOrderGrid
extends Control
## Сетка приказов 6×3 (ARCHITECTURE §14): квадратные ореховые кнопки в латуни, золочёный значок,
## клавиша в углу. Вкладка «Приказы» — GameQuery.orders_for(выделение); «Хозяйство» и «Укрепления» —
## build_menu(вкладка): кнопка постройки с ценой в подсказке и причиной недоступности по-русски.

const COLS := 6
const ROWS := 3
const CELL := 54.0
const GAP := 5.0

var hud: CityHud
var _sig := ""
var _buttons: Array[Button] = []


func setup(p_hud: CityHud) -> void:
	hud = p_hud
	name = "OrderGrid"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in COLS * ROWS:
		var b := Button.new()
		b.position = Vector2((i % COLS) * (CELL + GAP), (i / COLS) * (CELL + GAP))
		b.size = Vector2(CELL, CELL)
		b.focus_mode = Control.FOCUS_NONE
		var ic := TextureRect.new()
		ic.name = "Icon"
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.position = Vector2(7, 6)
		ic.size = Vector2(CELL - 14, CELL - 14)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
		var key := UiTheme.label("", UiTheme.text(800), 13)
		key.name = "Key"
		key.position = Vector2(CELL - 22, CELL - 22)
		key.size = Vector2(18, 16)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key.add_theme_color_override("font_color", UiTheme.GOLD_LIGHT)
		b.add_child(key)
		b.pressed.connect(_on_pressed.bind(i))
		add_child(b)
		_buttons.append(b)
	_clear_from(0)


## Приказы: [{op, label, key, enabled}]
func show_orders(list: Array[Dictionary]) -> void:
	var sig := "o"
	for o in list:
		sig += "%d%s;" % [int(o["op"]), str(o["enabled"])]
	if sig == _sig:
		return
	_sig = sig
	var n := mini(list.size(), _buttons.size())
	for i in n:
		var o: Dictionary = list[i]
		var key := String(o.get("key", ""))
		_fill(i, UiTheme.order_icon(int(o["op"])), "" if key == "ПКМ" else key,
			"%s%s" % [o.get("label", ""), (" (%s)" % key) if key != "" else ""], bool(o.get("enabled", true)),
			{"op": int(o["op"])})
	_clear_from(n)


## Постройки вкладки: [{btype, name, cost, hotkey, enabled, why}]
func show_build(list: Array[Dictionary]) -> void:
	var sig := "b"
	for o in list:
		sig += "%d%s%s;" % [int(o["btype"]), str(o["enabled"]), o.get("why", "")]
	if sig == _sig:
		return
	_sig = sig
	var defs := hud.query.defs()
	var n := mini(list.size(), _buttons.size())
	for i in n:
		var o: Dictionary = list[i]
		var bt := int(o["btype"])
		var tip := "%s (%s)\n%s: %s" % [o.get("name", ""), o.get("hotkey", ""), tr("Цена"),
			UiTheme.cost_text(defs, o.get("cost", PackedInt32Array()))]
		if defs.b_size.size() > bt:
			var sz := defs.b_size[bt]
			tip += "\n" + tr("Размер %d×%d м") % [roundi(sz.x), roundi(sz.y)]
		if o.get("why", "") != "":
			tip += "\n" + String(o["why"])
		_fill(i, UiTheme.building_icon(defs, bt), String(o.get("hotkey", "")), tip, bool(o.get("enabled", true)),
			{"btype": bt})
	_clear_from(n)


func _fill(i: int, icon: Texture2D, key: String, tip: String, enabled: bool, meta: Dictionary) -> void:
	var b := _buttons[i]
	b.visible = true
	b.disabled = not enabled
	b.tooltip_text = tip
	b.set_meta("act", meta)
	var ic := b.get_node("Icon") as TextureRect
	ic.texture = icon
	ic.modulate = Color(1, 1, 1) if enabled else Color(0.5, 0.46, 0.42, 0.8)
	(b.get_node("Key") as Label).text = key


func _clear_from(n: int) -> void:
	for i in range(n, _buttons.size()):
		var b := _buttons[i]
		b.disabled = true
		b.tooltip_text = ""
		b.set_meta("act", {})
		(b.get_node("Icon") as TextureRect).texture = null
		(b.get_node("Key") as Label).text = ""


func _on_pressed(i: int) -> void:
	var meta: Dictionary = _buttons[i].get_meta("act", {})
	if meta.has("op"):
		hud.order_button(int(meta["op"]))
	elif meta.has("btype"):
		hud.begin_place(int(meta["btype"]))


## Действие кнопки i (тесты): {op} или {btype}
func action_at(i: int) -> Dictionary:
	return _buttons[i].get_meta("act", {})
