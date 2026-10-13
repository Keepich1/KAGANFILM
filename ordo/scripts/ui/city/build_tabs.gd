class_name CityBuildTabs
extends HBoxContainer
## Кожаные вкладки над сеткой: «Приказы», «Хозяйство», «Укрепления» (ТЗ §12). Вкладки стройки
## доступны всегда: без выделенных работников строит ближайший свободный (ARCHITECTURE §14).
## «Укрепления» (стены, ворота, башни — в Сб. 1 по решению ведущего): стены и частокол — инструмент стены
## PlacementMode (ЛКМ-ЛКМ-…-ПКМ), ворота и башни — обычный призрак; выключенное в Defs — с причиной «Ещё не готово».

signal tab_changed(tab: StringName)

const TABS := [[&"orders", "Приказы"], [&"economy", "Хозяйство"], [&"fort", "Укрепления"]]

var current := &"orders"
var _buttons := {}


func setup() -> void:
	name = "BuildTabs"
	add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	for t in TABS:
		var b := Button.new()
		b.theme_type_variation = "CityTab"
		b.text = tr(t[1])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(112, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = tr(t[1]) + (" (B)" if t[0] == &"economy" else "")
		var id: StringName = t[0]
		b.pressed.connect(func() -> void: select(id))
		add_child(b)
		_buttons[id] = b
	(_buttons[&"orders"] as Button).button_pressed = true


func select(tab: StringName) -> void:
	if not _buttons.has(tab):
		return
	(_buttons[tab] as Button).set_pressed_no_signal(true)
	if tab != current:
		current = tab
		tab_changed.emit(tab)
