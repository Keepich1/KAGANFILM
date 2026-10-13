class_name RtsInput
extends Node
## Управление «Города» на ПК (ТЗ §10, ARCHITECTURE §14): мышь и клавиши → SimCmd (единственный вход симуляции).
##   ЛКМ / рамка / двойной щелчок — выбрать / свои в рамке / всех такого рода на экране;
##   ПКМ — по смыслу (GameQuery.pick): враг → ATTACK; узел, своё поле, своё стадо + работники → GATHER;
##     своя стройка или повреждённое здание + работники → ASSIST; своя башня/ворота + пехота → GARRISON;
##     всадники по чужому табуну, загону, полю, складу → набег (ECONOMY §4.1; Ctrl+ПКМ — простая атака);
##     земля → MOVE (Shift — в очередь); выбрано своё здание с наймом → RALLY; своё стадо → HERD_MOVE;
##   протянуть ПКМ — MOVE_LINE; двойной ПКМ — бегом/галопом;
##   H стоп, F строй по кругу, G качып, R стрельба/рукопашная, V клич (у Урды — Ҳашар), U собрать/распустить
##   отряд, K свернуть / Shift+K свернуть лагерь / K с арбами — развернуть у курсора, «.» свободный работник,
##   N тревога (Ноғора / Чакырык), Tab — наложения на карту (сами — при своём здании воды / загоне и его
##   постройке), Ctrl+1…9 / 1…9 / Shift+1…9 группы (двойное — камера), P пауза, + / − скорость, M звук
##   (выключенный клавишей включается при выходе из «Города»), B — вкладка «Хозяйство», буквы на открытой вкладке — постройки,
##   Del — снести, Esc — отмена (пустое выделение — меню), F10 — меню, F5–F8 — виды камеры (1–4 — группы).
## Кнопки сетки с целью (идти, в атаку, добывать, помочь, место сбора, в гарнизон) «взводят» приказ: следующий
## ЛКМ по миру или миникарте отдаёт его (Shift — ещё), ПКМ или Esc — снимает.
## Постройка — PlacementMode (призрак, поворот колесом или R, стены ЛКМ-ЛКМ-…-ПКМ).
## Приказы, которых ещё нет в SimCmd (тревога, Ҳашар, набег), ищутся по имени строителя (future_cmd):
## появятся в договоре — заработают без правки здесь.
##
## Узел ставится в сцене ПОСЛЕ RtsCamera (свой _unhandled_input получает раньше камеры: колесо в режиме
## постройки поворачивает, а не приближает). Тесты подают события в handle() и задают to_world / to_screen.
## Перед чтением GameQuery (щелчок, клавиша, курсор 12 Гц, кнопки) — driver.sync(), если он есть (GameDriver,
## шаг в фоне). Новую партию (CityHud.rebind) ввод принимает через rebind().

signal issued(cmd: PackedInt32Array)
## Взведён / снят приказ с кнопки (NONE — снят)
signal armed_changed(op: int)
## Наложения на карту (ECONOMY §1.3): kind — OVERLAY_WATER (арыки, зона воды, сухие поля) или OVERLAY_GRASS
## (трава пастбищ клетками). Вкл/выкл — Tab (вид — по стороне); сами — пока выбрано одно своё здание воды или
## загон и пока ставится такое здание; снято выделение — снова как по Tab. (true, kind) — показать kind (прежний
## вид убрать), (false, kind) — убрать. Слушатель — VIEW: предложено FieldView.set_overlay(on, kind); у OverlayView
## (таблички, надписи) такого нет — к нему не подключать.
signal overlay_toggled(on: bool, kind: StringName)

const DRAG_PX := 8.0
const LINE_PX := 16.0
const DOUBLE_S := 0.35
## Приказы, которые взводит кнопка сетки (ждут точки на карте)
const ARMABLE := [SimCmd.Op.MOVE, SimCmd.Op.ATTACK_MOVE, SimCmd.Op.GATHER, SimCmd.Op.ASSIST, SimCmd.Op.RALLY,
	SimCmd.Op.GARRISON]
## Имена умений построек (Defs.b_ability хранит только id)
const ABILITY_NAMES := {"hashar": "Ҳашар"}
## Виды наложений на карту (overlay_toggled)
const OVERLAY_WATER := &"water"
const OVERLAY_GRASS := &"grass"

var query: GameQuery
var selection: SelectionModel
var player := 0
## Куда отдавать приказы: GameDriver.issue (или запись в тестах)
var issue: Callable
var camera: Camera3D
var driver: SimDriver
var hud: CityHud
var ghost: Object
## Экран → мир (Vector3; INF — мимо земли) и мир → экран; по умолчанию — через camera
var to_world: Callable
var to_screen: Callable
## Видимая часть мира на экране (для двойного щелчка); по умолчанию — окно
var view_rect: Callable
## Часы для двойных нажатий: ≥ 0 — подставные (тесты), иначе время движка
var now_s := -1.0
var enabled := true
## Взведённый приказ с кнопки сетки (SimCmd.Op; NONE — нет)
var armed := SimCmd.Op.NONE
## Наложения на карту включены клавишей Tab
var overlay := false
## Что показано сейчас (Tab или само — по выбранному зданию / постройке) и какого вида
var overlay_on := false
var overlay_kind := &""

var sel: SelectionImpl
var groups: ControlGroups
var placement: PlacementMode

var _lmb := false
var _lmb_from := Vector2.ZERO
var _boxing := false
var _rmb := false
var _rmb_from := Vector2.ZERO
var _lining := false
var _click_t := -10.0
var _click_pos := Vector2.ZERO
var _rmb_t := -10.0
var _rmb_pos := Vector2.ZERO
var _idle_i := -1
var _kachyp := false
var _melee := false
var _mouse := Vector2.ZERO
var _hover_t := 0.0
## Звук выключен клавишей M (при выходе из «Города» — включить обратно)
var _muted_by_key := false
var _rmb_line_ok := false
var _cur_key := ""
var _cur_t := -10.0
## Своё выделение и флаги его родов (UnitStats) — пересчёт по SelectionModel.changed: курсор 12 раз в секунду
## и протяжка ПКМ не перебирают 1000 описателей каждый раз
var _own_cache := PackedInt32Array()
var _own_flags := 0
var _own_dirty := true
## У драйвера есть sync() (GameDriver: шаг в фоне)
var _can_sync := false
## Наложение по выбранному своему зданию (пересчёт по смене выделения) и вид наложения стороны для Tab
var _overlay_sel := &""
var _overlay_side := OVERLAY_GRASS


func setup(q: GameQuery, sel_model: SelectionModel, p: int, issue_fn: Callable, cam: Camera3D = null,
		drv: SimDriver = null) -> void:
	query = q
	selection = sel_model
	player = p
	issue = issue_fn
	camera = cam
	driver = drv
	sel = SelectionImpl.new(q, sel_model, p)
	if not sel_model.changed.is_connected(_on_selection_changed):
		sel_model.changed.connect(_on_selection_changed)
	_own_dirty = true
	groups = ControlGroups.new(sel_model)
	placement = PlacementMode.new(q, p)
	placement.ghost = ghost
	if not to_world.is_valid():
		to_world = _cam_to_world
	if not to_screen.is_valid():
		to_screen = _cam_to_screen
	if not view_rect.is_valid():
		view_rect = _view_rect
	_can_sync = driver != null and driver.has_method("sync")
	_overlay_side = side_overlay(q, p)
	_overlay_sel = &""


## Новая партия (CityHud.rebind): своё окно чтения; постройка, взведённый приказ, группы и счётчики сброшены
func rebind(q: GameQuery, p: int) -> void:
	if placement:
		placement.cancel()
	disarm()
	_lmb = false
	_rmb = false
	_boxing = false
	_lining = false
	_idle_i = -1
	_kachyp = false
	_melee = false
	_cur_key = ""
	overlay = false
	setup(q, selection, p, issue, camera, driver)
	update_overlay()


## Дождаться фонового шага драйвера (GameDriver.sync) перед чтением GameQuery; без фона — ничего
func sync_driver() -> void:
	if _can_sync:
		driver.call("sync")


func set_ghost(g: Object) -> void:
	ghost = g
	if placement:
		placement.ghost = g


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or query == null:
		return
	# движение мыши читает мир только в режиме постройки (призрак)
	if not (event is InputEventMouseMotion) or placement.active():
		sync_driver()
	if handle(event):
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_hover_t += delta
	if _hover_t >= 0.08 and query and enabled:
		_hover_t = 0.0
		_update_cursor()
		update_overlay()              # постройка кончилась (поставлена, снята) — наложение как было


## Выход из «Города» (главное меню, «Сражение»): звук, выключенный клавишей M, — обратно (если громкость в
## настройках Ordo не ноль: тогда шину держит выключенной он)
func _exit_tree() -> void:
	if not _muted_by_key:
		return
	_muted_by_key = false
	var bus := AudioServer.get_bus_index("Master")
	var ordo := get_node_or_null("/root/Ordo")
	var vol: Variant = ordo.get("volume") if ordo else null
	if bus >= 0 and AudioServer.is_bus_mute(bus) and not (vol is float and float(vol) <= 0.001):
		AudioServer.set_bus_mute(bus, false)


# ================================================================= события

## Разобрать событие ввода; true — съедено
func handle(e: InputEvent) -> bool:
	var used := false
	if e is InputEventMouseButton:
		used = _mouse_button(e as InputEventMouseButton)
	elif e is InputEventMouseMotion:
		return _mouse_motion(e as InputEventMouseMotion)
	elif e is InputEventKey:
		var k := e as InputEventKey
		if k.pressed and not k.echo:
			used = _key(k)
	update_overlay()                  # щелчок или клавиша могли начать / кончить постройку
	return used


func _mouse_button(mb: InputEventMouseButton) -> bool:
	_mouse = mb.position
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if hud and hud.blocks(mb.position):
					return false
				if placement.active():
					var w := _world(mb.position)
					if w != Vector2.INF:
						var cmd := placement.click(w, _own_workers(), mb.shift_pressed)
						if not cmd.is_empty():
							issue_cmd(cmd)
						elif not placement.is_wall and hud:
							hud.notes.push(tr("Здесь не встанет"), CityNotes.Seal.RED)
					return true
				if armed != SimCmd.Op.NONE:
					var aw := _world(mb.position)
					if aw != Vector2.INF:
						fire_armed(aw, mb.shift_pressed)
					return true
				_lmb = true
				_lmb_from = mb.position
				_boxing = false
				return true
			if not _lmb:
				return false
			_lmb = false
			if _boxing:
				_boxing = false
				if hud:
					hud.hide_box()
				sel.box(Rect2(_lmb_from, mb.position - _lmb_from), mb.shift_pressed, to_screen, to_world)
				return true
			var w := _world(mb.position)
			var t := _now()
			var double := t - _click_t <= DOUBLE_S and mb.position.distance_to(_click_pos) <= 6.0
			_click_t = t
			_click_pos = mb.position
			if w == Vector2.INF:
				return true
			var h := sel.click(w, mb.shift_pressed and not double, _pick_r())
			if double and h != 0 and Ids.kind(h) == Ids.Kind.UNIT:
				sel.same_type(h, view_rect.call(), to_screen)
				_click_t = -10.0
			return true
		MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				if hud and hud.blocks(mb.position):
					return false
				if placement.active():
					if placement.is_wall:
						var cmd := placement.finish(_own_workers())
						if not cmd.is_empty():
							issue_cmd(cmd)
					else:
						placement.cancel()
					return true
				if armed != SimCmd.Op.NONE:
					disarm()
					return true
				_rmb = true
				_rmb_from = mb.position
				_lining = false
				_rmb_line_ok = not _own_units().is_empty()
				return true
			if not _rmb:
				return false
			_rmb = false
			if _lining:
				_lining = false
				if hud:
					hud.hide_box()
				var a := _world(_rmb_from)
				var b := _world(mb.position)
				var units := _own_units()
				if a != Vector2.INF and b != Vector2.INF and not units.is_empty():
					issue_cmd(SimCmd.move_line(compact(units), a, b, false))
				return true
			var t := _now()
			var run := t - _rmb_t <= DOUBLE_S and mb.position.distance_to(_rmb_pos) <= 10.0
			_rmb_t = -10.0 if run else t
			_rmb_pos = mb.position
			var w := _world(mb.position)
			if w != Vector2.INF:
				order_at(w, mb.shift_pressed, run, mb.ctrl_pressed)
			return true
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if placement.active() and mb.pressed:
				placement.rotate(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
				return true
	return false


func _mouse_motion(mm: InputEventMouseMotion) -> bool:
	_mouse = mm.position
	if placement.active():
		var w := _world(mm.position)
		if w != Vector2.INF:
			placement.move(w)
	if _lmb and not _boxing and mm.position.distance_to(_lmb_from) > DRAG_PX:
		_boxing = true
	if _boxing and hud:
		hud.show_box(Rect2(_lmb_from, mm.position - _lmb_from))
	if _rmb and not _lining and _rmb_line_ok and mm.position.distance_to(_rmb_from) > LINE_PX:
		_lining = true
	if _lining and hud:
		hud.show_line(_rmb_from, mm.position)
	return false


func _key(k: InputEventKey) -> bool:
	var code := k.physical_keycode
	# режим постройки: R — поворот, Esc — отмена/конец стены
	if placement.active():
		if code == KEY_R:
			placement.rotate(1)
			return true
		if code == KEY_ESCAPE:
			if placement.is_wall:
				var cmd := placement.finish(_own_workers())
				if not cmd.is_empty():
					issue_cmd(cmd)
			else:
				placement.cancel()
			return true
	if armed != SimCmd.Op.NONE and code == KEY_ESCAPE:
		disarm()
		return true
	if code == KEY_F10:
		if hud:
			hud.open_menu()
		return true
	# открытая вкладка стройки: буквы — постройки
	if hud and hud.current_tab() != &"orders" and not k.ctrl_pressed:
		var key := OS.get_keycode_string(code)
		for b in query.build_menu(player, hud.current_tab()):
			if String(b.get("hotkey", "")) == key and key != "":
				if b.get("enabled", false):
					begin_place(int(b["btype"]))
				elif hud:
					hud.notes.push(String(b.get("why", tr("Нельзя"))), CityNotes.Seal.GOLD)
				return true
	if code == KEY_ESCAPE:
		if hud and hud.current_tab() != &"orders":
			hud.open_tab(&"orders")
		elif not selection.selected.is_empty():
			selection.set_selection(PackedInt32Array())
		elif hud:
			hud.open_menu()
		return true
	if code >= KEY_F5 and code <= KEY_F8 and camera and camera.get("presets") != null:
		var presets: Array = camera.get("presets")
		var i := code - KEY_F5
		if i < presets.size():
			camera.call("go_to", presets[i])
		return true
	for i in 9:
		if k.is_action_pressed("ordo_group_%d" % (i + 1), false, false) or code == KEY_1 + i:
			if k.ctrl_pressed:
				groups.store(i)
			elif k.shift_pressed:
				groups.add(i)
			elif groups.recall(i, _now()):
				center_on(selection.selected)
			return true
	if _is(k, "ordo_stop", KEY_H):
		var u := _own_units()
		if not u.is_empty():
			issue_cmd(SimCmd.stop(compact(u)))
		return true
	if _is(k, "ordo_formation", KEY_F):
		var u := _own_units()
		if not u.is_empty():
			issue_cmd(SimCmd.formation(compact(u), _next_formation(u)))
		return true
	if _is(k, "ordo_kachyp", KEY_G):
		var u := _own_units()
		if not u.is_empty():
			_kachyp = not _kachyp
			issue_cmd(SimCmd.kachyp(compact(u), _kachyp))
		return true
	if _is(k, "ordo_fire_mode", KEY_R):
		var u := _own_units()
		if not u.is_empty():
			_melee = not _melee
			issue_cmd(SimCmd.fire_mode(compact(u), SimCmd.FIRE_MELEE if _melee else SimCmd.FIRE_AUTO))
		return true
	if _is(k, "ordo_war_cry", KEY_V):
		var ab := _ability_building()
		if ab != 0:
			use_ability(ab)
			return true
		var g := _general()
		if g != 0:
			issue_cmd(SimCmd.war_cry(g))
		return true
	if _is(k, "ordo_alarm", KEY_N):
		alarm()
		return true
	if _is(k, "ordo_overlay", KEY_TAB):
		overlay = not overlay
		update_overlay()
		return true
	if _is(k, "ordo_squad", KEY_U):
		_squad_key()
		return true
	if _is(k, "ordo_pack", KEY_K):
		_pack_key(k.shift_pressed)
		return true
	if _is(k, "ordo_idle_worker", KEY_PERIOD):
		next_idle_worker()
		return true
	if _is(k, "ordo_pause", KEY_P):
		if driver:
			driver.paused = not driver.paused
		return true
	if _is(k, "ordo_speed_up", KEY_EQUAL) or code == KEY_KP_ADD:
		if driver:
			driver.time_scale = minf(driver.time_scale * 2.0, 4.0)
		return true
	if _is(k, "ordo_speed_down", KEY_MINUS) or code == KEY_KP_SUBTRACT:
		if driver:
			driver.time_scale = maxf(driver.time_scale * 0.5, 0.25)
		return true
	if _is(k, "ordo_mute", KEY_M):
		toggle_mute()
		return true
	if code == KEY_B:
		if hud:
			hud.open_tab(&"economy")
		return true
	if code == KEY_DELETE:
		var own := _own_selection()
		if own.size() == 1 and Ids.kind(own[0]) == Ids.Kind.BUILDING:
			issue_cmd(SimCmd.demolish(own[0]))
		return true
	return false


## M: звук вкл/выкл (главная шина). Состояние — у AudioServer, а не своё: громкость 0 в настройках Ordo тоже
## держит шину выключенной, и первое M в новой партии не «пропадает»
func toggle_mute() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	var mute := not AudioServer.is_bus_mute(bus)
	AudioServer.set_bus_mute(bus, mute)
	_muted_by_key = mute


func _is(k: InputEventKey, action: String, fallback: int) -> bool:
	if InputMap.has_action(action):
		return k.is_action_pressed(action, false, false)
	return k.physical_keycode == fallback


# ================================================================= приказы

func issue_cmd(cmd: PackedInt32Array) -> void:
	if cmd.is_empty():
		return
	if issue.is_valid():
		issue.call(cmd)
	issued.emit(cmd)


## ПКМ в точке мира (и с миникарты): приказ по смыслу цели под точкой; plain (Ctrl) — без набега, простая атака
func order_at(world: Vector2, shift := false, run := false, plain := false) -> void:
	sync_driver()
	var own := _own_selection()
	if own.is_empty():
		return
	var target := query.pick(player, world, _pick_r())
	if Ids.kind(own[0]) == Ids.Kind.BUILDING:
		var bt := query.buildings()
		var b := bt.slot(own[0])
		if bt.valid(own[0]) and not query.defs().b_trains[bt.btype[b]].is_empty():
			var t := target if target != 0 and Ids.kind(target) != Ids.Kind.UNIT else 0
			issue_cmd(SimCmd.rally(own[0], world, t))
		return
	if Ids.kind(own[0]) == Ids.Kind.HERD:
		# своё стадо — перегнать на траву (HERD_MOVE)
		issue_cmd(SimCmd.herd_move(own[0], world))
		return
	var units := _units_of(own)
	if units.is_empty():
		return
	var workers := _filter(units, UnitStats.WORKER, true)
	var rest := _without(units, workers)
	if target != 0:
		# всадники по чужому табуну, загону, полю, складу — набег (барымта, вытоптать, талоо; ECONOMY §4.1)
		if not plain and is_raid_target(target):
			var riders := _filter(rest, UnitStats.MOUNTED, true)
			var raid := future_cmd("raid", [compact(riders), target]) if not riders.is_empty() else PackedInt32Array()
			if not raid.is_empty():
				issue_cmd(raid)
				var others := _without(units, riders)
				if not others.is_empty():
					issue_cmd(SimCmd.move(compact(others), world, run, NAN, shift))
				return
		if is_enemy(target):
			issue_cmd(SimCmd.attack(compact(units), target, true))
			return
		if not workers.is_empty():
			var job := PackedInt32Array()
			if needs_hands(target):
				job = SimCmd.assist(workers, target)
			elif gatherable(target):
				job = SimCmd.gather(workers, target)
			if not job.is_empty():
				issue_cmd(job)
				if not rest.is_empty():
					issue_cmd(SimCmd.move(compact(rest), world, run, NAN, shift))
				return
		var foot := _foot(rest)
		if can_garrison(target) and not foot.is_empty():
			issue_cmd(SimCmd.garrison(foot, target))
			return
	issue_cmd(SimCmd.move(compact(units), world, run, NAN, shift))


## Взвести приказ кнопки (ждёт ЛКМ по карте); постройка снимается
func arm(op: int) -> void:
	if placement.active():
		placement.cancel()
	armed = op
	armed_changed.emit(op)


func disarm() -> void:
	if armed == SimCmd.Op.NONE:
		return
	armed = SimCmd.Op.NONE
	armed_changed.emit(armed)


## ЛКМ по миру (или миникарте) со взведённым приказом; true — приказ отдан. Цель не подходит — приказ
## остаётся взведённым и записка объясняет; Shift — взведён и после приказа.
func fire_armed(world: Vector2, shift := false) -> bool:
	if armed == SimCmd.Op.NONE:
		return false
	sync_driver()
	var own := _own_selection()
	var units := _units_of(own)
	var target := query.pick(player, world, _pick_r())
	var cmd := PackedInt32Array()
	var miss := ""
	match armed:
		SimCmd.Op.MOVE:
			if not units.is_empty():
				cmd = SimCmd.move(compact(units), world, false, NAN, shift)
			elif own.size() == 1 and Ids.kind(own[0]) == Ids.Kind.HERD:
				cmd = SimCmd.herd_move(own[0], world)
		SimCmd.Op.ATTACK_MOVE:
			if not units.is_empty():
				cmd = SimCmd.attack(compact(units), target, true) if is_enemy(target) else SimCmd.attack_move(compact(units), world)
		SimCmd.Op.GATHER:
			var wk := _filter(units, UnitStats.WORKER, true)
			if not wk.is_empty() and gatherable(target):
				cmd = SimCmd.gather(wk, target)
			else:
				miss = tr("Здесь нечего добывать")
		SimCmd.Op.ASSIST:
			var wk := _filter(units, UnitStats.WORKER, true)
			if not wk.is_empty() and needs_hands(target):
				cmd = SimCmd.assist(wk, target)
			else:
				miss = tr("Здесь нечего строить и чинить")
		SimCmd.Op.RALLY:
			if own.size() == 1 and Ids.kind(own[0]) == Ids.Kind.BUILDING:
				cmd = SimCmd.rally(own[0], world, target if target != 0 and Ids.kind(target) != Ids.Kind.UNIT else 0)
		SimCmd.Op.GARRISON:
			var foot := _foot(units)
			if not foot.is_empty() and can_garrison(target):
				cmd = SimCmd.garrison(foot, target)
			else:
				miss = tr("Сюда не войти")
	if cmd.is_empty():
		if miss != "" and hud:
			hud.notes.push(miss, CityNotes.Seal.GOLD)
		return false
	issue_cmd(cmd)
	if not shift:
		disarm()
	return true


# ================================================================= цели под курсором

## Чужой юнит или здание (враждебная команда)
func is_enemy(h: int) -> bool:
	var k := Ids.kind(h)
	if h == 0 or (k != Ids.Kind.UNIT and k != Ids.Kind.BUILDING):
		return false
	var t := team_of(query, h)
	return t >= 0 and t != query.players().team[player]


## Работникам есть что добывать: узел, своё стадо, своё готовое поле
func gatherable(h: int) -> bool:
	match Ids.kind(h):
		Ids.Kind.NODE:
			return query.nodes() == null or query.nodes().valid(h)
		Ids.Kind.HERD:
			return owner_of(query, h) == player
		Ids.Kind.BUILDING:
			var bt := query.buildings()
			if not bt.valid(h) or bt.owner[bt.slot(h)] != player:
				return false
			return query.defs().b_kind[bt.btype[bt.slot(h)]] == Defs.BKind.FIELD
	return false


## Своя стройка или повреждённое своё здание (руки работников: ASSIST)
func needs_hands(h: int) -> bool:
	if Ids.kind(h) != Ids.Kind.BUILDING:
		return false
	var bt := query.buildings()
	if not bt.valid(h) or bt.owner[bt.slot(h)] != player:
		return false
	var b := bt.slot(h)
	return bt.state[b] == BuildingTable.State.SITE or (bt.state[b] != BuildingTable.State.PACKED and bt.hp_c[b] < bt.hp_max_c[b])


## Своя башня или ворота с местами для гарнизона (этап 2)
func can_garrison(h: int) -> bool:
	if Ids.kind(h) != Ids.Kind.BUILDING:
		return false
	var bt := query.buildings()
	if not bt.valid(h) or bt.owner[bt.slot(h)] != player:
		return false
	var defs := query.defs()
	var t := bt.btype[bt.slot(h)]
	return (defs.b_kind[t] == Defs.BKind.TOWER or defs.b_kind[t] == Defs.BKind.GATE) and defs.b_gar_cap[t] > 0


## Цель набега всадников (ECONOMY §4.1): чужое стадо; чужой загон, двор с конями, поле, склад, базар
func is_raid_target(h: int) -> bool:
	match Ids.kind(h):
		Ids.Kind.HERD:
			var o := owner_of(query, h)
			return o >= 0 and query.players().team[o] != query.players().team[player]
		Ids.Kind.BUILDING:
			if not is_enemy(h):
				return false
			var bt := query.buildings()
			var defs := query.defs()
			var t := bt.btype[bt.slot(h)]
			return defs.b_flags[t] & (Defs.BF_PEN | Defs.BF_DROP | Defs.BF_MARKET) != 0 or defs.b_kind[t] == Defs.BKind.FIELD \
				or not defs.b_otlar[t].is_empty()
	return false


## Приказ, которого может ещё не быть в SimCmd (raid, alarm, ability): строитель SimCmd.<name>(args…),
## если ведущий его добавил; иначе пустой массив
static func future_cmd(builder: String, args: Array) -> PackedInt32Array:
	if not has_builder(builder):
		return PackedInt32Array()
	return (SimCmd as GDScript).callv(builder, args)


static var _builders := {}


## Есть ли в SimCmd строитель с таким именем (кэш)
static func has_builder(builder: String) -> bool:
	if _builders.is_empty():
		for m in (SimCmd as GDScript).get_script_method_list():
			_builders[String(m["name"])] = true
	return _builders.has(builder)


## Кнопка сетки приказов
func order_button(op: int) -> void:
	sync_driver()
	var own := _own_selection()
	var units := _units_of(own)
	match op:
		SimCmd.Op.STOP:
			if not units.is_empty():
				issue_cmd(SimCmd.stop(compact(units)))
		SimCmd.Op.HOLD:
			if not units.is_empty():
				issue_cmd(SimCmd.hold(compact(units)))
		SimCmd.Op.FORMATION:
			if not units.is_empty():
				issue_cmd(SimCmd.formation(compact(units), _next_formation(units)))
		SimCmd.Op.STANCE:
			if not units.is_empty():
				issue_cmd(SimCmd.stance(compact(units), _next_stance(units)))
		SimCmd.Op.KACHYP:
			if not units.is_empty():
				_kachyp = not _kachyp
				issue_cmd(SimCmd.kachyp(compact(units), _kachyp))
		SimCmd.Op.FIRE_MODE:
			if not units.is_empty():
				_melee = not _melee
				issue_cmd(SimCmd.fire_mode(compact(units), SimCmd.FIRE_MELEE if _melee else SimCmd.FIRE_AUTO))
		SimCmd.Op.WAR_CRY:
			var g := _general()
			if g != 0:
				issue_cmd(SimCmd.war_cry(g))
		SimCmd.Op.FORM_SQUAD, SimCmd.Op.DISBAND:
			_squad_key()
		SimCmd.Op.BUILD:
			if hud:
				hud.open_tab(&"economy")
		SimCmd.Op.PACK:
			_pack_key(false)
		SimCmd.Op.PACK_ALL:
			_pack_key(true)
		SimCmd.Op.UNPACK:
			var w := _world(_mouse)
			var arbas := _filter(units, UnitStats.WAGON, true)
			if not arbas.is_empty() and w != Vector2.INF:
				issue_cmd(SimCmd.unpack(arbas, w))
		SimCmd.Op.DEMOLISH:
			if own.size() == 1 and Ids.kind(own[0]) == Ids.Kind.BUILDING:
				issue_cmd(SimCmd.demolish(own[0]))
		SimCmd.Op.UNGARRISON:
			if own.size() == 1 and Ids.kind(own[0]) == Ids.Kind.BUILDING:
				issue_cmd(SimCmd.ungarrison(own[0]))
		SimCmd.Op.HERD_MOVE:
			if own.size() == 1 and Ids.kind(own[0]) == Ids.Kind.HERD:
				arm(SimCmd.Op.MOVE)          # перегон — ЛКМ по карте
		SimCmd.Op.TRADE:
			# обмен — кнопками «Продать / Купить» в панели Бозора
			if hud:
				hud.notes.push(tr("Обмен — кнопками в панели базара"), CityNotes.Seal.GOLD)
		SimCmd.Op.SET_DAM:
			if own.size() == 1 and Ids.kind(own[0]) == Ids.Kind.BUILDING:
				dam_button(own[0])
		SimCmd.Op.SET_RECIPE:
			if own.size() == 1 and Ids.kind(own[0]) == Ids.Kind.BUILDING:
				var rc := _next_recipe(own[0])
				if rc >= 0:
					issue_cmd(SimCmd.set_recipe(own[0], rc))
		_:
			if op in ARMABLE and not own.is_empty():
				arm(op)        # ждёт ЛКМ по карте


## Кнопка «Запруда» тўғона: если панель знает, открыт ли он (dam_open), — переключить (SET_DAM);
## иначе (Сб. 1: тўғон всегда открыт, шлюзы — позже) — записка
func dam_button(b_h: int) -> void:
	var panel := query.building_panel(b_h)
	if panel.has("dam_open"):
		issue_cmd(SimCmd.set_dam(b_h, not bool(panel["dam_open"])))
	elif hud:
		hud.notes.push(tr("Тўғон всегда открыт: шлюзы — позже"), CityNotes.Seal.GOLD)


## Наложение на карту: постройка воды / загона (ставится) → выбранное своё здание → Tab (вид стороны) → нет.
## Сообщает overlay_toggled, только если показ или вид сменились.
func update_overlay() -> void:
	var kind := &""
	if placement and placement.active() and query:
		kind = overlay_kind_of(query.defs(), placement.btype)
	if kind == &"":
		kind = _overlay_sel
	if kind == &"" and overlay:
		kind = _overlay_side
	var on := kind != &""
	if on == overlay_on and (not on or kind == overlay_kind):
		return
	overlay_on = on
	if on:
		overlay_kind = kind
	overlay_toggled.emit(on, overlay_kind)


## Вид наложения у постройки: вода (сеть тўғона, место у воды) / трава (загон со стадом, кроме ставки) / нет
static func overlay_kind_of(defs: Defs, btype: int) -> StringName:
	if defs == null or btype < 0 or btype >= defs.b_ids.size():
		return &""
	if String(defs.b_network[btype].get("kind", "")) == "water" or defs.b_water_place[btype] > 0:
		return OVERLAY_WATER
	if defs.b_herd[btype] >= 0 and defs.b_herd_cap[btype] > 0 and defs.b_flags[btype] & Defs.BF_HQ == 0:
		return OVERLAY_GRASS
	return &""


## Вид наложения стороны игрока p для Tab: вода, если у стороны есть постройки воды (Коканд), иначе трава
static func side_overlay(q: GameQuery, p: int) -> StringName:
	var defs := q.defs()
	var fid := defs.f_ids[q.players().faction[p]]
	for b in defs.b_ids.size():
		if defs.b_enabled[b] != 0 and defs.b_faction[b] == fid and overlay_kind_of(defs, b) == OVERLAY_WATER:
			return OVERLAY_WATER
	return OVERLAY_GRASS


## Своё выбранное здание воды / загон (одно) → вид наложения; иначе пусто
func _selected_overlay() -> StringName:
	if selection == null or selection.selected.size() != 1 or Ids.kind(selection.selected[0]) != Ids.Kind.BUILDING:
		return &""
	var h := selection.selected[0]
	var bt := query.buildings()
	if not bt.valid(h) or bt.owner[bt.slot(h)] != player:
		return &""
	return overlay_kind_of(query.defs(), bt.btype[bt.slot(h)])


func begin_place(btype: int) -> void:
	sync_driver()
	disarm()
	placement.begin(btype)
	var w := _world(_mouse)
	if w != Vector2.INF:
		placement.move(w)
	update_overlay()


## «.» — следующий свободный работник: выделить и показать
func next_idle_worker() -> int:
	var idle := query.idle_workers(player)
	if idle.is_empty():
		return 0
	_idle_i = (_idle_i + 1) % idle.size()
	var h := idle[_idle_i]
	selection.set_selection(PackedInt32Array([h]))
	center_on(selection.selected)
	return h


func _squad_key() -> void:
	var units := _units_of(_own_selection())
	var bs := query.battle()
	if units.is_empty() or bs == null:
		return
	# массивы ядра — в локальные один раз (CONTRACT §10.2 п. 9)
	var usq := bs.u_squad
	var types := bs.u_type
	var tf := bs.t_flags
	var single := bs.sq_single
	var members := bs.sq_members
	var gen := bs.sq_gen
	var squads := {}
	var singles := PackedInt32Array()
	var officer := 0
	for h in units:
		var u := query.unit_index(h)
		if u < 0:
			continue
		var s := usq[u]
		if single[s] == 0 and members[s].size() > 1:
			squads[s] = true
		elif tf[types[u]] & UnitStats.OFFICER and officer == 0:
			officer = h
		else:
			singles.append(h)
	if not squads.is_empty():
		for s: int in squads:
			issue_cmd(SimCmd.disband(Ids.make(Ids.Kind.SQUAD, s, gen[s])))
	elif officer != 0 and not singles.is_empty():
		issue_cmd(SimCmd.form_squad(officer, singles))


func _pack_key(all: bool) -> void:
	var own := _own_selection()
	var units := _units_of(own)
	var arbas := _filter(units, UnitStats.WAGON, true)
	if not all and not arbas.is_empty():
		var w := _world(_mouse)
		if w != Vector2.INF:
			issue_cmd(SimCmd.unpack(arbas, w))
		return
	var defs := query.defs()
	var bt := query.buildings()
	if all:
		var hq := 0
		if own.size() == 1 and Ids.kind(own[0]) == Ids.Kind.BUILDING and defs.b_flags[bt.btype[bt.slot(own[0])]] & Defs.BF_HQ:
			hq = own[0]
		else:
			hq = query.players().hq_b[player]
		if hq != 0:
			issue_cmd(SimCmd.pack_all(hq))
		return
	for h in own:
		if Ids.kind(h) == Ids.Kind.BUILDING and bt.valid(h) and defs.b_flags[bt.btype[bt.slot(h)]] & Defs.BF_PACKABLE:
			issue_cmd(SimCmd.pack(h))


## N: тревога стороны (Ноғора / Чакырык, ECONOMY §1.7) — у своей ставки; повторное N — отбой
func alarm() -> void:
	var hq := query.players().hq_b[player]
	var cmd := future_cmd("alarm", [hq]) if hq != 0 else PackedInt32Array()
	if not cmd.is_empty():
		issue_cmd(cmd)
	elif hud:
		var name := query.defs().f_alarm[query.players().faction[player]]
		hud.notes.push(tr("«%s» — ещё не готово") % (name if name != "" else tr("Тревога")), CityNotes.Seal.GOLD)


## Кнопка постройки (Ҳашар у Урды; V при выбранной Урде)
func use_ability(b_h: int) -> void:
	var cmd := future_cmd("ability", [b_h])
	if not cmd.is_empty():
		issue_cmd(cmd)
	elif hud:
		var bt := query.buildings()
		var ab: Dictionary = query.defs().b_ability[bt.btype[bt.slot(b_h)]]
		hud.notes.push(tr("«%s» — ещё не готово") % ability_name(ab), CityNotes.Seal.GOLD)


## Имя умения по-русски (в Defs у умения только id)
static func ability_name(ab: Dictionary) -> String:
	var id := String(ab.get("id", ""))
	return TranslationServer.translate(String(ab.get("name", ABILITY_NAMES.get(id, id))))


## Выделено одно своё здание с кнопкой-умением (Defs.b_ability) — его описатель, иначе 0
func _ability_building() -> int:
	var own := _own_selection()
	if own.size() != 1 or Ids.kind(own[0]) != Ids.Kind.BUILDING:
		return 0
	var bt := query.buildings()
	if not bt.valid(own[0]) or bt.state[bt.slot(own[0])] != BuildingTable.State.ACTIVE:
		return 0
	return own[0] if not query.defs().b_ability[bt.btype[bt.slot(own[0])]].is_empty() else 0


## Следующая стойка по кругу (наступать → оборона → стоять → не отвечать) от стойки первого отряда
func _next_stance(units: PackedInt32Array) -> int:
	var bs := query.battle()
	if bs == null:
		return BattleSim.Stance.HOLD
	for h in units:
		var u := query.unit_index(h)
		if u >= 0:
			var s := bs.u_squad[u]
			return (bs.sq_stance[s] + 1) % 4          # одно чтение: выход на первом
	return BattleSim.Stance.HOLD


## Следующий доступный рецепт здания по кругу (Defs.b_recipes); −1 — рецептов нет
func _next_recipe(b_h: int) -> int:
	var bt := query.buildings()
	if not bt.valid(b_h):
		return -1
	var defs := query.defs()
	var b := bt.slot(b_h)
	var list := PackedInt32Array()
	for rc in defs.b_recipes[bt.btype[b]]:
		if defs.rc_enabled[rc] != 0:
			list.append(rc)
	if list.is_empty():
		return -1
	return list[(list.find(bt.recipe[b]) + 1) % list.size()]


## Пешие (без коней, пушек и арб) — для гарнизона
func _foot(units: PackedInt32Array) -> PackedInt32Array:
	return _filter(units, UnitStats.MOUNTED | UnitStats.CANNON | UnitStats.WAGON, false)


func _next_formation(units: PackedInt32Array) -> int:
	var bs := query.battle()
	if bs == null:
		return BattleSim.Formation.LINE
	var usq := bs.u_squad
	var single := bs.sq_single
	for h in units:
		var u := query.unit_index(h)
		if u >= 0 and single[usq[u]] == 0:
			return (bs.sq_form[usq[u]] + 1) % 4          # одно чтение: выход на первом
	return BattleSim.Formation.LINE


func _general() -> int:
	var bs := query.battle()
	if bs == null:
		return 0
	var types := bs.u_type
	var tf := bs.t_flags
	for h in _units_of(_own_selection()):
		var u := query.unit_index(h)
		if u >= 0 and tf[types[u]] & UnitStats.GENERAL:
			return h
	return 0


# ================================================================= выборки

func _on_selection_changed(_hs: PackedInt32Array) -> void:
	_own_dirty = true
	if query:
		_overlay_sel = _selected_overlay()
		update_overlay()


## Своё выделение (чужие юниты в выделении — только посмотреть, приказов нет)
func _own_selection() -> PackedInt32Array:
	if selection == null or selection.selected.is_empty():
		return PackedInt32Array()
	if _own_dirty:
		_own_dirty = false
		_own_cache = selection.selected if owns_all(query, player, selection.selected) else PackedInt32Array()
		_own_flags = 0
		var bs := query.battle()
		if bs:
			var types := bs.u_type
			var tf := bs.t_flags
			for h in _own_cache:
				var u := query.unit_index(h) if Ids.kind(h) == Ids.Kind.UNIT else -1
				if u >= 0:
					_own_flags |= tf[types[u]]
	return _own_cache


func _own_units() -> PackedInt32Array:
	return _units_of(_own_selection())


func _own_workers() -> PackedInt32Array:
	return _filter(_own_units(), UnitStats.WORKER, true)


func _units_of(hs: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for h in hs:
		if Ids.kind(h) == Ids.Kind.UNIT:
			out.append(h)
	return out


## Юниты, у рода которых есть (has = true) / нет флагов mask (UnitStats)
func _filter(units: PackedInt32Array, mask: int, has: bool) -> PackedInt32Array:
	var out := PackedInt32Array()
	var bs := query.battle()
	if bs == null:
		return out
	var life := bs.u_life
	var types := bs.u_type
	var tf := bs.t_flags
	for h in units:
		var u := query.unit_index(h)
		if u < 0 or life[u] != BattleSim.Life.ALIVE:
			continue
		if (tf[types[u]] & mask != 0) == has:
			out.append(h)
	return out


func _without(a: PackedInt32Array, b: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for h in a:
		if not b.has(h):
			out.append(h)
	return out


## Описатели для приказа: по одному живому бойцу на настоящий отряд (описатель юнита = его отряд) + все
## живые одиночки. Так приказ «всем 300» — несколько чисел, а не 300, и павший в выделении его не сорвёт.
func compact(units: PackedInt32Array) -> PackedInt32Array:
	return compact_of(query, units)


## То же для любого окна чтения (CityHud: сводка выделения и сетка приказов спрашиваются по сжатому
## выделению — ответ тот же, а GameQueryImpl считает отряд по бойцам каждого описателя)
static func compact_of(q: GameQuery, units: PackedInt32Array) -> PackedInt32Array:
	var bs := q.battle()
	if bs == null:
		return units
	# массивы ядра — в локальные один раз (CONTRACT §10.2 п. 9: 1000 описателей — не 1000 копий)
	var life := bs.u_life
	var usq := bs.u_squad
	var single := bs.sq_single
	var members := bs.sq_members
	var out := PackedInt32Array()
	var seen := {}
	for h in units:
		var u := q.unit_index(h)
		if u < 0 or life[u] != BattleSim.Life.ALIVE:
			continue
		var s := usq[u]
		if single[s] == 0 and members[s].size() > 1:
			if seen.has(s):
				continue
			seen[s] = true
		out.append(h)
	return out


static func owner_of(q: GameQuery, h: int) -> int:
	match Ids.kind(h):
		Ids.Kind.UNIT:
			var u := q.unit_index(h)
			var bs := q.battle()
			return bs.u_owner[u] if u >= 0 and bs else -1
		Ids.Kind.BUILDING:
			var bt := q.buildings()
			return bt.owner[bt.slot(h)] if bt.valid(h) else -1
		Ids.Kind.HERD:
			var ht := q.herds()
			return ht.owner[Ids.slot(h)] if ht.valid(h) else -1
	return -1


static func team_of(q: GameQuery, h: int) -> int:
	match Ids.kind(h):
		Ids.Kind.UNIT:
			var u := q.unit_index(h)
			var bs := q.battle()
			return bs.u_side[u] if u >= 0 and bs else -1
		Ids.Kind.BUILDING:
			var bt := q.buildings()
			return bt.team[bt.slot(h)] if bt.valid(h) else -1
	var o := owner_of(q, h)
	return q.players().team[o] if o >= 0 else -1


## Всё в hs — игрока p. Юниты — по u_owner, взятому в локальную один раз (CONTRACT §10.2 п. 9): выделение
## в 1000 бойцов — одна копия массива у BattleCore, а не тысяча
static func owns_all(q: GameQuery, p: int, hs: PackedInt32Array) -> bool:
	if hs.is_empty():
		return false
	var bs := q.battle()
	var owner := bs.u_owner if bs else PackedInt32Array()
	for h in hs:
		if Ids.kind(h) == Ids.Kind.UNIT:
			var u := q.unit_index(h)
			if u < 0 or u >= owner.size() or owner[u] != p:
				return false
		elif owner_of(q, h) != p:
			return false
	return true


# ================================================================= экран ↔ мир

func _world(screen: Vector2) -> Vector2:
	var w: Vector3 = to_world.call(screen)
	return Vector2.INF if w.x == INF else Vector2(w.x, w.z)


func _pick_r() -> float:
	if camera and camera.get("distance") != null:
		return clampf(float(camera.get("distance")) * 0.035, 1.6, 8.0)
	return 2.5


func _now() -> float:
	return now_s if now_s >= 0.0 else Time.get_ticks_msec() / 1000.0


## Камера к выделенному (среднее положение юнитов и зданий)
func center_on(hs: PackedInt32Array) -> void:
	if hs.is_empty() or camera == null or not camera.has_method("go_to"):
		return
	var bs := query.battle()
	var ux := bs.u_x if bs else PackedFloat32Array()
	var uz := bs.u_z if bs else PackedFloat32Array()
	var c := Vector2.ZERO
	var n := 0
	var bt := query.buildings()
	for h in hs:
		if Ids.kind(h) == Ids.Kind.BUILDING:
			if bt and bt.valid(h):
				c += Vector2(bt.x[bt.slot(h)], bt.z[bt.slot(h)])
				n += 1
			continue
		var u := query.unit_index(h)
		if u >= 0 and u < ux.size():
			c += Vector2(ux[u], uz[u])
			n += 1
	if n > 0 and hud:
		hud.look_at_world(c / n)


func _cam_to_world(screen: Vector2) -> Vector3:
	if camera == null or not camera.is_inside_tree():
		return Vector3(INF, INF, INF)
	return ground_hit(camera, screen)


func _cam_to_screen(p: Vector3) -> Vector2:
	if camera == null or not camera.is_inside_tree() or camera.is_position_behind(p):
		return Vector2(-1e6, -1e6)
	return camera.unproject_position(p)


func _view_rect() -> Rect2:
	var vp := get_viewport()
	return vp.get_visible_rect() if vp else Rect2(0, 0, 1920, 1080)


## Точка земли под точкой экрана (луч камеры, уточнение по рельефу); INF — луч не идёт к земле
static func ground_hit(cam: Camera3D, screen: Vector2) -> Vector3:
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if d.y > -0.01:
		return Vector3(INF, INF, INF)
	var y := 0.0
	var p := o
	for i in 5:
		var t := (y - o.y) / d.y
		p = o + d * t
		y = Terrain.height_at(p.x, p.z)
	return p


## Как ground_hit, но у горизонта — точка на расстоянии max_d по лучу (рамка камеры на миникарте)
static func ground_point(cam: Camera3D, screen: Vector2, max_d := 900.0) -> Vector2:
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	var t := max_d
	if d.y < -0.01:
		t = minf(max_d, (Terrain.height_at(o.x, o.z) - o.y) / d.y)
	var p := o + d * t
	return Vector2(p.x, p.z)


# ================================================================= курсор

## Курсор по смыслу: GameQuery.pick стоит O(юнитов) — заново, только если мышь сдвинулась на 4 px, сменились
## выделение, взведённый приказ или постройка, либо прошло 0,4 с (цель могла уйти из-под курсора)
func _update_cursor() -> void:
	var key := "%d|%d|%d|%d|%s" % [armed, selection.selected.size() if selection else 0, int(placement.active()),
		placement.why, str(Vector2i(_mouse / 4.0))]
	var now := _now()
	if key == _cur_key and now - _cur_t < 0.4:
		return
	_cur_key = key
	_cur_t = now
	sync_driver()
	CityCursor.apply(cursor_kind(_mouse))


## Вид курсора над точкой экрана (CityCursor.Kind): по смыслу ПКМ, взведённому приказу или призраку
func cursor_kind(screen: Vector2) -> int:
	if hud and hud.blocks(screen):
		return CityCursor.Kind.DEFAULT
	if placement.active():
		return CityCursor.Kind.BUILD if placement.why == NavApi.Why.OK else CityCursor.Kind.FORBID
	var own := _own_selection()
	if own.is_empty():
		return CityCursor.Kind.DEFAULT
	var w := _world(screen)
	if w == Vector2.INF:
		return CityCursor.Kind.FORBID if armed != SimCmd.Op.NONE else CityCursor.Kind.DEFAULT
	var t := query.pick(player, w, _pick_r())
	match armed:
		SimCmd.Op.ATTACK_MOVE:
			return CityCursor.Kind.ATTACK
		SimCmd.Op.GATHER:
			return CityCursor.Kind.GATHER if gatherable(t) else CityCursor.Kind.FORBID
		SimCmd.Op.ASSIST:
			return CityCursor.Kind.BUILD if needs_hands(t) else CityCursor.Kind.FORBID
		SimCmd.Op.GARRISON:
			return CityCursor.Kind.MOVE if can_garrison(t) else CityCursor.Kind.FORBID
		SimCmd.Op.MOVE, SimCmd.Op.RALLY:
			return CityCursor.Kind.MOVE
	if Ids.kind(own[0]) != Ids.Kind.UNIT or t == 0:
		return CityCursor.Kind.DEFAULT
	if is_enemy(t) or (has_builder("raid") and is_raid_target(t) and _own_flags & UnitStats.MOUNTED):
		return CityCursor.Kind.ATTACK
	if _own_flags & UnitStats.WORKER:
		if needs_hands(t):
			return CityCursor.Kind.BUILD
		if gatherable(t):
			return CityCursor.Kind.GATHER
	return CityCursor.Kind.DEFAULT
