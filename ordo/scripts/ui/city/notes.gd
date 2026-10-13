class_name CityNotes
extends Control
## Записки (ТЗ §12, ARCHITECTURE §14): полоска бумаги с сургучной печатью над нижней панелью справа.
## Красная — RAID_STARTED, BUILDING_DESTROYED, FAMINE, CMD_REJECTED, HERD_STOLEN; зелёная — BUILDING_DONE,
## TRAINED, LOOT, RAID_ENDED; золотая — POP_CAPPED, PASTURE_LOW, NOT_ENOUGH, SEASON, RAID_WARNING.
## Читает SimEvents своим курсором (не теряет событий при нескольких тактах за кадр). Одинаковые записки
## подряд складываются («×3»). Живёт 9 с и гаснет; щелчок — камера к месту события.

enum Seal { RED, GREEN, GOLD }

const MAX := 5
const LIFE := 9.0
const W := 420.0
const H := 62.0

var hud: CityHud
var _cursor := 0
var _notes: Array[Dictionary] = []       # {node, text, label, count, t, pos}


func setup(p_hud: CityHud) -> void:
	hud = p_hud
	name = "Notes"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ev := hud.query.events()
	_cursor = ev.head if ev else 0


## Разобрать новые события; вернуть число новых записок (тесты)
func poll() -> int:
	var ev := hud.query.events()
	if ev == null:
		return 0
	var r := ev.range_since(_cursor)
	var added := 0
	for seq in range(r.x, r.y):
		var i := ev.at(seq)
		var p := ev.e_player[i]
		if p != hud.player and p != -1:
			continue
		hud.on_event(ev.e_kind[i], ev.e_a[i], ev.e_b[i], ev.e_c[i], Vector2(ev.e_x[i], ev.e_z[i]))
		var n := describe(ev.e_kind[i], ev.e_a[i], ev.e_b[i], ev.e_c[i])
		if n.is_empty():
			continue
		push(n["text"], n["seal"], Vector2(ev.e_x[i], ev.e_z[i]))
		added += 1
	_cursor = r.y
	return added


## Текст и печать записки для события (пусто — без записки)
func describe(kind: int, a: int, b: int, c: int) -> Dictionary:
	var defs := hud.query.defs()
	var E := SimEvents.Ev
	match kind:
		E.RAID_STARTED:
			return {"text": tr("Набег! Враг идёт на нас"), "seal": Seal.RED}
		E.RAID_WARNING:
			return {"text": tr("Разведчики: набег через %s") % UiTheme.clock(a), "seal": Seal.GOLD}
		E.RAID_ENDED:
			return {"text": tr("Набег отбит"), "seal": Seal.GREEN}
		E.BUILDING_DESTROYED:
			return {"text": tr("Разрушено: %s") % tr(defs.b_name[b]) if b >= 0 and b < defs.b_name.size() else tr("Здание разрушено"), "seal": Seal.RED}
		E.BUILDING_DONE:
			if b >= 0 and b < defs.b_kind.size() and defs.b_kind[b] in [Defs.BKind.WALL, Defs.BKind.LINK]:
				return {}
			return {"text": tr("Построено: %s") % tr(defs.b_name[b]) if b >= 0 and b < defs.b_name.size() else tr("Построено"), "seal": Seal.GREEN}
		E.TRAINED:
			return {"text": tr("Готов: %s") % tr(defs.u_name[c]) if c >= 0 and c < defs.u_name.size() else tr("Юнит готов"), "seal": Seal.GREEN}
		E.FAMINE:
			return {"text": tr("Голод! Войско слабеет"), "seal": Seal.RED} if a == 1 else {"text": tr("Голод кончился"), "seal": Seal.GREEN}
		E.LOOT:
			return {"text": tr("Олжо: %s +%s") % [tr(defs.r_name[a]).to_lower(), UiTheme.amount(b)] if a >= 0 and a < defs.R else tr("Олжо"), "seal": Seal.GREEN}
		E.POP_CAPPED:
			return {"text": tr("Нет мест: нужно жильё (%d / %d)") % [b, c], "seal": Seal.GOLD}
		E.PASTURE_LOW:
			return {"text": tr("Трава вытоптана — пора перегнать"), "seal": Seal.GOLD}
		E.NOT_ENOUGH:
			return {"text": tr("Не хватает: %s %d") % [tr(defs.r_name[a]).to_lower(), ceili(b / 1000.0)] if a >= 0 and a < defs.R else tr("Не хватает ресурсов"), "seal": Seal.GOLD}
		E.SEASON:
			return {"text": tr("Пришёл сезон: %s") % tr(defs.s_name[a]) if a >= 0 and a < defs.s_name.size() else tr("Смена сезона"), "seal": Seal.GOLD}
		E.HERD_STOLEN:
			return {"text": tr("Угоняют табун!"), "seal": Seal.RED}
		E.HERD_RETURNED:
			return {"text": tr("Стадо вернулось"), "seal": Seal.GREEN}
		E.IRRIGATION_CHANGED:
			return {"text": tr("Вода в арыках изменилась"), "seal": Seal.GOLD}
		E.CMD_REJECTED:
			return {"text": reject_text(b), "seal": Seal.RED}
		E.PLAYER_DEFEATED:
			return {"text": tr("Поражение: ставка потеряна") if a == 0 else tr("Поражение: арба с ордо погибла"), "seal": Seal.RED}
		E.VICTORY:
			return {"text": tr("Победа!"), "seal": Seal.GREEN}
		E.WORKER_IDLE:
			return {"text": tr("Работник без дела («.» — найти)"), "seal": Seal.GOLD}
	return {}


## Причина отказа приказа по-русски (EconApi.Err или 100 + NavApi.Why)
func reject_text(reason: int) -> String:
	if reason >= 100:
		match reason - 100:
			NavApi.Why.OVERLAP: return tr("Здесь не встанет: занято")
			NavApi.Why.SLOPE: return tr("Здесь не встанет: крутой склон")
			NavApi.Why.WATER: return tr("Здесь не встанет: вода")
			NavApi.Why.OUT_OF_MAP: return tr("За краем карты")
			NavApi.Why.NOT_NEAR: return tr("Нужно ближе к жиле")
			NavApi.Why.NOT_ON_WALL: return tr("Ставится только на стену")
			NavApi.Why.NO_TERRITORY: return tr("Далеко от ставки")
			NavApi.Why.ENEMY_UNITS: return tr("Мешают враги")
			NavApi.Why.NO_RES: return tr("Не хватает ресурсов")
		return tr("Здесь строить нельзя")
	match reason:
		EconApi.Err.NO_RES: return tr("Не хватает ресурсов")
		EconApi.Err.POP_CAP: return tr("Нет мест: нужно жильё")
		EconApi.Err.QUEUE_FULL: return tr("Очередь полна")
		EconApi.Err.BAD_PLACE: return tr("Здесь строить нельзя")
		EconApi.Err.BUSY: return tr("Занято")
		EconApi.Err.NOT_ALLOWED: return tr("Так нельзя")
		EconApi.Err.STALE: return tr("Цель уже исчезла")
		EconApi.Err.NOT_OWNER: return tr("Это не наше")
	return tr("Приказ не выполнен")


func push(text: String, seal: int, pos := Vector2.INF) -> void:
	if not _notes.is_empty() and _notes[0]["text"] == text:
		var top: Dictionary = _notes[0]
		top["count"] += 1
		top["t"] = 0.0
		(top["label"] as Label).text = "%s  ×%d" % [text, top["count"]]
		return
	var node := NinePatchRect.new()
	node.texture = UiTheme.tex("note")
	node.patch_margin_left = 26
	node.patch_margin_right = 26
	node.patch_margin_top = 20
	node.patch_margin_bottom = 20
	node.size = Vector2(W, H)
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.tooltip_text = tr("Щелчок — показать место") if pos != Vector2.INF else ""
	add_child(node)
	var lab := UiTheme.label(text, UiTheme.text(600), 19, true)
	lab.position = Vector2(64, 8)
	lab.size = Vector2(W - 80, H - 18)
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.clip_text = true
	if seal == Seal.RED:
		lab.add_theme_color_override("font_color", Color("#6a140e"))
	node.add_child(lab)
	var s := TextureRect.new()
	s.texture = UiTheme.tex(["seal_red", "seal_green", "seal_gold"][seal])
	s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	s.position = Vector2(4, 2)
	s.size = Vector2(58, 58)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(s)
	var note := {"node": node, "text": text, "label": lab, "count": 1, "t": 0.0, "pos": pos, "seal": seal}
	node.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and note["pos"] != Vector2.INF:
			hud.look_at_world(note["pos"]))
	_notes.push_front(note)
	while _notes.size() > MAX:
		var old: Dictionary = _notes.pop_back()
		(old["node"] as Node).queue_free()
	_layout()


func _layout() -> void:
	for i in _notes.size():
		var n: Control = _notes[i]["node"]
		n.position = Vector2(size.x - W, size.y - (i + 1) * (H + 4))


## Записки на экране (тесты): [{text, seal}]
func visible_notes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in _notes:
		out.append({"text": n["text"], "seal": n["seal"], "count": n["count"]})
	return out


func tick(delta: float) -> void:
	var gone := false
	for i in range(_notes.size() - 1, -1, -1):
		var n: Dictionary = _notes[i]
		n["t"] += delta
		var node: Control = n["node"]
		node.modulate.a = clampf((LIFE - n["t"]) / 1.5, 0.0, 1.0)
		if n["t"] >= LIFE:
			node.queue_free()
			_notes.remove_at(i)
			gone = true
	if gone:
		_layout()
