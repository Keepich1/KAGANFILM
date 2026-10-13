class_name RtsInput
extends Node
## Управление «Города» на ПК (ТЗ §10, ARCHITECTURE §14): мышь и клавиши → SimCmd (единственный вход симуляции).
##   ЛКМ / рамка / двойной щелчок — выбрать / свои в рамке / всех такого рода на экране;
##   ПКМ — по смыслу (GameQuery.pick): враг → ATTACK; узел, своё поле, своё стадо + работники → GATHER;
##     своя стройка или повреждённое здание + работники → ASSIST; своя башня/ворота + пехота → GARRISON;
##     земля → MOVE (Shift — в очередь); выбрано своё здание с наймом → RALLY;
##   протянуть ПКМ — MOVE_LINE; двойной ПКМ — бегом/галопом;
##   H стоп, F строй по кругу, G качып, R стрельба/рукопашная, V клич, U собрать/распустить отряд,
##   K свернуть / Shift+K свернуть лагерь / K с арбами — развернуть у курсора, «.» свободный работник,
##   Ctrl+1…9 / 1…9 / Shift+1…9 группы (двойное — камера), P пауза, + / − скорость, M звук,
##   B — вкладка «Хозяйство», буквы на открытой вкладке — постройки, Del — снести, Esc — отмена,
##   F5–F8 — виды камеры (1–4 в городе — группы).
## Постройка — PlacementMode (призрак, поворот колесом или R, стены ЛКМ-ЛКМ-…-ПКМ).
##
## Узел ставится в сцене ПОСЛЕ RtsCamera (свой _unhandled_input получает раньше камеры: колесо в режиме
## постройки поворачивает, а не приближает). Тесты подают события в handle() и задают to_world / to_screen.

signal issued(cmd: PackedInt32Array)

const DRAG_PX := 8.0
const LINE_PX := 16.0
const DOUBLE_S := 0.35

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
var _muted := false


func setup(q: GameQuery, sel_model: SelectionModel, p: int, issue_fn: Callable, cam: Camera3D = null,
		drv: SimDriver = null) -> void:
	query = q
	selection = sel_model
	player = p
	issue = issue_fn
	camera = cam
	driver = drv
	sel = SelectionImpl.new(q, sel_model, p)
	groups = ControlGroups.new(sel_model)
	placement = PlacementMode.new(q, p)
	placement.ghost = ghost
	if not to_world.is_valid():
		to_world = _cam_to_world
	if not to_screen.is_valid():
		to_screen = _cam_to_screen
	if not view_rect.is_valid():
		view_rect = _view_rect


func set_ghost(g: Object) -> void:
	ghost = g
	if placement:
		placement.ghost = g


func _unhandled_input(event: InputEvent) -> void:
	if enabled and query and handle(event):
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_hover_t += delta
	if _hover_t >= 0.08 and query and enabled:
		_hover_t = 0.0
		_update_cursor()


# ================================================================= события

## Разобрать событие ввода; true — съедено
func handle(e: InputEvent) -> bool:
	if e is InputEventMouseButton:
		return _mouse_button(e as InputEventMouseButton)
	if e is InputEventMouseMotion:
		return _mouse_motion(e as InputEventMouseMotion)
	if e is InputEventKey:
		var k := e as InputEventKey
		if k.pressed and not k.echo:
			return _key(k)
	return false


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
				sel.box(Rect2(_lmb_from, mb.position - _lmb_from), mb.shift_pressed, to_screen)
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
				_rmb = true
				_rmb_from = mb.position
				_lining = false
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
				order_at(w, mb.shift_pressed, run)
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
	if _rmb and not _lining and mm.position.distance_to(_rmb_from) > LINE_PX and not _own_units().is_empty():
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
		else:
			selection.set_selection(PackedInt32Array())
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
				_center_on(selection.selected)
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
		var g := _general()
		if g != 0:
			issue_cmd(SimCmd.war_cry(g))
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
		_muted = not _muted
		AudioServer.set_bus_mute(0, _muted)
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


## ПКМ в точке мира (и с миникарты): приказ по смыслу цели под точкой
func order_at(world: Vector2, shift := false, run := false) -> void:
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
	var units := _units_of(own)
	if units.is_empty():
		return
	var my_team := query.players().team[player]
	var workers := _filter(units, UnitStats.WORKER, true)
	var rest := _without(units, workers)
	if target != 0:
		var tk := Ids.kind(target)
		var tteam := team_of(query, target)
		if (tk == Ids.Kind.UNIT or tk == Ids.Kind.BUILDING) and tteam >= 0 and tteam != my_team:
			issue_cmd(SimCmd.attack(compact(units), target, true))
			return
		var towner := owner_of(query, target)
		if not workers.is_empty():
			var job := PackedInt32Array()
			if tk == Ids.Kind.NODE or (tk == Ids.Kind.HERD and towner == player):
				job = SimCmd.gather(workers, target)
			elif tk == Ids.Kind.BUILDING and towner == player:
				var bt := query.buildings()
				var b := bt.slot(target)
				var kind := query.defs().b_kind[bt.btype[b]]
				if bt.state[b] == BuildingTable.State.SITE or bt.hp_c[b] < bt.hp_max_c[b]:
					job = SimCmd.assist(workers, target)
				elif kind == Defs.BKind.FIELD:
					job = SimCmd.gather(workers, target)
			if not job.is_empty():
				issue_cmd(job)
				if not rest.is_empty():
					issue_cmd(SimCmd.move(compact(rest), world, run, NAN, shift))
				return
		if tk == Ids.Kind.BUILDING and towner == player:
			var bt := query.buildings()
			var b := bt.slot(target)
			var defs := query.defs()
			var kind := defs.b_kind[bt.btype[b]]
			var foot := _filter(rest, UnitStats.MOUNTED | UnitStats.CANNON | UnitStats.WAGON, false)
			if (kind == Defs.BKind.TOWER or kind == Defs.BKind.GATE) and defs.b_gar_cap[bt.btype[b]] > 0 and not foot.is_empty():
				issue_cmd(SimCmd.garrison(foot, target))
				return
	issue_cmd(SimCmd.move(compact(units), world, run, NAN, shift))


## Кнопка сетки приказов
func order_button(op: int) -> void:
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
				issue_cmd(SimCmd.stance(compact(units), BattleSim.Stance.HOLD))
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
		_:
			pass        # ПКМ-приказы (идти, атаковать, добывать, место сбора) — мышью по карте


func begin_place(btype: int) -> void:
	placement.begin(btype)
	var w := _world(_mouse)
	if w != Vector2.INF:
		placement.move(w)


## «.» — следующий свободный работник: выделить и показать
func next_idle_worker() -> int:
	var idle := query.idle_workers(player)
	if idle.is_empty():
		return 0
	_idle_i = (_idle_i + 1) % idle.size()
	var h := idle[_idle_i]
	selection.set_selection(PackedInt32Array([h]))
	_center_on(selection.selected)
	return h


func _squad_key() -> void:
	var units := _units_of(_own_selection())
	var bs := query.battle()
	if units.is_empty() or bs == null:
		return
	var squads := {}
	var singles := PackedInt32Array()
	var officer := 0
	for h in units:
		var u := query.unit_index(h)
		if u < 0:
			continue
		var s := bs.u_squad[u]
		if bs.sq_single[s] == 0 and bs.sq_members[s].size() > 1:
			squads[s] = true
		elif bs.t_flags[bs.u_type[u]] & UnitStats.OFFICER and officer == 0:
			officer = h
		else:
			singles.append(h)
	if not squads.is_empty():
		for s: int in squads:
			issue_cmd(SimCmd.disband(Ids.make(Ids.Kind.SQUAD, s, bs.sq_gen[s])))
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


func _next_formation(units: PackedInt32Array) -> int:
	var bs := query.battle()
	if bs == null:
		return BattleSim.Formation.LINE
	for h in units:
		var u := query.unit_index(h)
		if u >= 0 and bs.sq_single[bs.u_squad[u]] == 0:
			return (bs.sq_form[bs.u_squad[u]] + 1) % 4
	return BattleSim.Formation.LINE


func _general() -> int:
	var bs := query.battle()
	if bs == null:
		return 0
	for h in _units_of(_own_selection()):
		var u := query.unit_index(h)
		if u >= 0 and bs.t_flags[bs.u_type[u]] & UnitStats.GENERAL:
			return h
	return 0


# ================================================================= выборки

## Своё выделение (чужие юниты в выделении — только посмотреть, приказов нет)
func _own_selection() -> PackedInt32Array:
	if selection == null or selection.selected.is_empty():
		return PackedInt32Array()
	return selection.selected if owns_all(query, player, selection.selected) else PackedInt32Array()


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
	for h in units:
		var u := query.unit_index(h)
		if u < 0 or bs == null:
			continue
		if (bs.t_flags[bs.u_type[u]] & mask != 0) == has:
			out.append(h)
	return out


func _without(a: PackedInt32Array, b: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for h in a:
		if not b.has(h):
			out.append(h)
	return out


## Описатели для приказа: по одному бойцу на настоящий отряд (описатель юнита = его отряд) + все одиночки.
## Так приказ «всем 300» — несколько чисел, а не 300.
func compact(units: PackedInt32Array) -> PackedInt32Array:
	var bs := query.battle()
	if bs == null:
		return units
	var out := PackedInt32Array()
	var seen := {}
	for h in units:
		var u := query.unit_index(h)
		if u < 0:
			continue
		var s := bs.u_squad[u]
		if bs.sq_single[s] == 0 and bs.sq_members[s].size() > 1:
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


static func owns_all(q: GameQuery, p: int, hs: PackedInt32Array) -> bool:
	if hs.is_empty():
		return false
	for h in hs:
		if owner_of(q, h) != p:
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


func _center_on(hs: PackedInt32Array) -> void:
	if hs.is_empty() or camera == null or not camera.has_method("go_to"):
		return
	var bs := query.battle()
	var c := Vector2.ZERO
	var n := 0
	for h in hs:
		var u := query.unit_index(h)
		if u >= 0 and bs:
			c += Vector2(bs.u_x[u], bs.u_z[u])
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

func _update_cursor() -> void:
	var kind := CityCursor.Kind.DEFAULT
	if hud and hud.blocks(_mouse):
		CityCursor.apply(kind)
		return
	if placement.active():
		kind = CityCursor.Kind.BUILD if placement.why == NavApi.Why.OK else CityCursor.Kind.FORBID
	else:
		var own := _own_selection()
		if not own.is_empty() and Ids.kind(own[0]) == Ids.Kind.UNIT:
			var w := _world(_mouse)
			if w != Vector2.INF:
				var t := query.pick(player, w, _pick_r())
				var tk := Ids.kind(t)
				if t != 0 and (tk == Ids.Kind.UNIT or tk == Ids.Kind.BUILDING) \
						and team_of(query, t) != query.players().team[player] and team_of(query, t) >= 0:
					kind = CityCursor.Kind.ATTACK
				elif t != 0 and not _own_workers().is_empty():
					if tk == Ids.Kind.NODE or tk == Ids.Kind.HERD:
						kind = CityCursor.Kind.GATHER
					elif tk == Ids.Kind.BUILDING:
						var bt := query.buildings()
						var b := bt.slot(t)
						if bt.state[b] == BuildingTable.State.SITE or bt.hp_c[b] < bt.hp_max_c[b]:
							kind = CityCursor.Kind.BUILD
						elif query.defs().b_kind[bt.btype[b]] == Defs.BKind.FIELD:
							kind = CityCursor.Kind.GATHER
	CityCursor.apply(kind)
