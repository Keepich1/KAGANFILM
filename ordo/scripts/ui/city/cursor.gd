class_name CityCursor
extends RefCounted
## Курсор — наконечник стрелы (ТЗ §12) с вариантами по смыслу ПКМ: атака (красный), добыча (топор),
## стройка/помощь (молот), нельзя (серый с крестом), идти (флажок). Остриё — точка (2, 2).

enum Kind { DEFAULT, ATTACK, GATHER, BUILD, FORBID, MOVE }

const FILES := ["cursor", "cursor_attack", "cursor_gather", "cursor_build", "cursor_forbid", "cursor_move"]
const HOTSPOT := Vector2(2, 2)

static var current := -1


static func apply(kind: int) -> void:
	if kind == current:
		return
	current = kind
	var t := UiTheme.tex(FILES[clampi(kind, 0, FILES.size() - 1)])
	if t == null or DisplayServer.get_name() == "headless":
		return
	Input.set_custom_mouse_cursor(t, Input.CURSOR_ARROW, HOTSPOT)
	if kind == Kind.DEFAULT:
		# кнопки и записки — тот же наконечник
		Input.set_custom_mouse_cursor(t, Input.CURSOR_POINTING_HAND, HOTSPOT)
