class_name GorodShots
extends RefCounted
## Серия кадров проверки вида «Города» (VIEW, ARCHITECTURE §19.5): стройки на разных стадиях, стена,
## призрак зелёный и красный, работники (рубят, копают, строят, несут), выделение, стада, лагерь.
##   tools/shot.sh res://scenes/gorod/gorod.tscn out.png -- --skip=6 --series=/abs/dir [--only=sites,ghost_bad]
##   tools/shot.sh res://scenes/test/gorod_look.tscn out.png -- --series=/abs/dir   (ряды образцов, LOOK_SHOTS)
## Камера — RtsCamera.go_to(x, z, расстояние, азимут) или «на юнита за работой» (work = AnimSpec.WORK_*);
## с pitch (градусы) — своя камера CamShot с этим наклоном (крупные планы ниже, чем у стратегии).
## Юнит за работой берётся у своей цели (рубит — у живого дерева, копает — у жилы, строит — у стройки,
## несёт — на ходу) и не из нагрузки --stress; нет такого сейчас — город шагает дальше (до 40 с).

## [имя, {view: Vector4 | work: aux, near: Vector2, dist, yaw, ghost: ..., select: ...}]
const SHOTS := [
	["town", {"view": Vector4(186, 52, 165, -58)}],
	["sites", {"view": Vector4(222, 62, 88, -76), "pitch": 34.0}],
	["walls", {"view": Vector4(140, 30, 58, -96), "pitch": 26.0}],
	["ghost_ok", {"view": Vector4(166, 70, 48, -70), "ghost": ["uy", Vector2(163, 72), 0]}],
	["ghost_bad", {"view": Vector4(172, 22, 56, -70), "ghost": ["kazarma", Vector2(172, 26), 1],
		"wall": ["devor", [Vector2(150, -14), Vector2(204, -14)]]}],
	["chop", {"work": 0.0, "near": Vector2(166, 30), "dist": 15.0, "yaw": -55.0, "pitch": 20.0}],
	["dig", {"work": 0.25, "near": Vector2(266, -66), "dist": 15.0, "yaw": -60.0, "pitch": 22.0}],
	["build", {"work": 0.5, "near": Vector2(214, 8), "dist": 15.0, "yaw": -50.0, "pitch": 22.0}],
	["carry", {"work": 0.75, "near": Vector2(180, 20), "dist": 9.0, "yaw": -60.0, "pitch": 16.0}],
	["select", {"view": Vector4(150, 52, 78, -72), "select": ["drill", "urda"]}],
	["fields", {"view": Vector4(168, -36, 72, -62), "pitch": 36.0}],
	["herd_sheep", {"view": Vector4(-112, 68, 40, -64), "pitch": 28.0}],
	["herd_horses", {"view": Vector4(-26, 90, 34, -70), "pitch": 26.0}],
	["camp", {"view": Vector4(-72, 34, 150, -62)}],
	["gold", {"work": 0.25, "near": Vector2(-56, 168), "dist": 18.0, "yaw": -70.0, "pitch": 24.0}],
	["raid", {"view": Vector4(112, 132, 40, -60), "pitch": 28.0}],
	["overview", {"view": Vector4(170, 170, 260, -25)}],
	["overview_world", {"view": Vector4(170, 170, 260, -25), "hide_views": true}],
]

## Ряды образцов (scenes/test/gorod_look.tscn): все постройки обеих сторон готовыми, стройки на трёх
## стадиях и руины — к югу от долины; кадр на ряд (look_row<N>, row — номер ряда, по place_lineup),
## потом призрак и общий вид
const LOOK_SHOTS := [
	["look_ghost", {"view": Vector4(10, -6, 40, -30), "pitch": 34.0, "ghost": ["uy", Vector2(4, -8), 0],
		"wall": ["devor", [Vector2(-16, -4), Vector2(30, -30)]]}],
	["look_all", {"view": Vector4(46, -76, 150, -16), "pitch": 46.0}],
]
## Где ряды: колонки шириной LOOK_W от x = LOOK_COLS[i], ряды — от z = LOOK_Z0 на юг (−z) до LOOK_ZMIN
## (дальше — река); не влез ряд — следующая колонка. Фасады (+Z) — к камере. Узкие ряды — крупнее в кадре.
const LOOK_COLS := [-40.0, 50.0]
const LOOK_W := 82.0
const LOOK_Z0 := -24.0
const LOOK_ZMIN := -126.0
const LOOK_KOKAND := ["urda", "uy", "dala", "tegirmon", "ombor", "togon", "aryk", "xumdon", "bozor", "kazarma",
	"otxona", "topxona", "temirchixona", "devor", "tosh", "darvoza", "burj"]
const LOOK_KIPCHAK := ["ordo", "boz", "koroo", "ken", "jooker", "jylky", "kurultai", "kiyiz", "temirchi", "chep",
	"darbaza", "munara"]
## Стройки на трёх стадиях (‰) и руина: модели _site/_ruin (uy, kazarma), без них — срез готовой (boz, ordo)
const LOOK_SITES := ["uy", "kazarma", "boz", "ordo"]
const LOOK_STAGES := [250, 550, 850]
const LOOK_GAP := 4.0
const LOOK_ROW_GAP := 6.0

## Прямоугольники рядов образцов (x, z) после place_lineup
static var rows: Array[Rect2] = []


## Набор кадров сцены: «look» — по кадру на ряд образцов и LOOK_SHOTS, иначе — город
static func shots(set_name: StringName) -> Array:
	if set_name != &"look":
		return SHOTS
	var out: Array = []
	for i in rows.size():
		# ряд из одной небольшой постройки виден в кадре соседнего ряда
		if rows[i].size.x >= 20.0:
			out.append(["look_row%d" % i, {"row": i}])
	out.append_array(LOOK_SHOTS)
	return out


## Поставить ряды образцов в поддельный город (сцена gorod_look; FakeCity — подделка, не правила игры)
static func place_lineup(city: FakeCity) -> void:
	rows.clear()
	if city == null:
		return
	var d := city.defs()
	var items: Array = []           # [ряд-группа, id, состояние, прогресс]
	for id: String in LOOK_KOKAND:
		items.append([0, id, BuildingTable.State.ACTIVE, 0])
	for id: String in LOOK_KIPCHAK:
		items.append([1, id, BuildingTable.State.ACTIVE, 0])
	for id: String in LOOK_SITES:
		for k: int in LOOK_STAGES:
			items.append([2, id, BuildingTable.State.SITE, k])
		items.append([2, id, BuildingTable.State.RUIN, 0])
	# раскладка: ряды по колонкам — [[id, состояние, прогресс, центр]]
	var col := 0
	var x0: float = LOOK_COLS[0]
	var x := x0
	var z := LOOK_Z0
	var depth := 0.0
	var group := -1
	var row_items: Array = []
	var placed: Array = []
	for it: Array in items + [[-1, "", 0, 0]]:
		var ty := d.building(StringName(it[1])) if it[0] >= 0 else -1
		if it[0] >= 0 and ty < 0:
			continue
		var sz := d.b_size[ty] if ty >= 0 else Vector2.ZERO
		if not row_items.is_empty() and (int(it[0]) != group or x + sz.x > x0 + LOOK_W):
			# ряд закрыт: не влез по глубине — в следующую колонку
			var w := x - LOOK_GAP - x0
			if z - depth < LOOK_ZMIN and col + 1 < LOOK_COLS.size():
				col += 1
				var dx: float = float(LOOK_COLS[col]) - x0
				x0 = LOOK_COLS[col]
				z = LOOK_Z0
				for r: Array in row_items:
					r[3] = (r[3] as Vector2) + Vector2(dx, LOOK_Z0 - (r[4] as float))
			rows.append(Rect2(x0, z - depth, w, depth))
			placed.append_array(row_items)
			row_items = []
			z -= depth + LOOK_ROW_GAP
			x = x0
			depth = 0.0
		if it[0] < 0:
			break
		group = int(it[0])
		row_items.append([it[1], it[2], it[3], Vector2(x + sz.x * 0.5, z - sz.y * 0.5), z])
		x += sz.x + LOOK_GAP
		depth = maxf(depth, sz.y)
	for r: Array in placed:
		var ty := d.building(StringName(r[0]))
		var owner := FakeCity.KOK if d.b_faction[ty] == "kokand" else FakeCity.KIP
		var b: int = city.call("_add", owner, StringName(r[0]), r[3], 0, r[1])
		if int(r[1]) == BuildingTable.State.SITE:
			city.buildings().progress[b] = int(r[2])


static func setup(scene: GorodScene, s: Array) -> void:
	var cfg: Dictionary = s[1]
	var q := CityView.query_of(scene.driver)
	var cam := scene.camera
	scene.ghost.hide_ghost()
	# без видов «Города» — только мир (замер: сколько вызовов отрисовки добавляют виды)
	(scene.get_node("Views") as Node3D).visible = not bool(cfg.get("hide_views", false))
	(scene.get_node("HUD") as CanvasLayer).visible = not bool(cfg.get("hide_views", false))
	scene.selection.set_selection(PackedInt32Array())
	var view := Vector4.ZERO
	var pitch := float(cfg.get("pitch", -1.0))
	if cfg.has("view"):
		view = cfg["view"]
	elif cfg.has("row"):
		# ряд образцов: середина ряда, расстояние по ширине
		var r: Rect2 = rows[mini(int(cfg["row"]), rows.size() - 1)] if not rows.is_empty() else Rect2()
		var c := r.get_center()
		view = Vector4(c.x, c.y, r.size.x * 0.68 + 12.0, -14.0)
		pitch = 28.0
	elif cfg.has("work"):
		var aux := float(cfg["work"])
		var u := -1
		# нужного работника сейчас нет у цели — город шагает дальше (до 40 с)
		for i in 1200:
			u = _worker(q, aux, cfg.get("near", Vector2.ZERO))
			if u >= 0:
				break
			scene.driver.step()
		var sim := q.battle()
		var at: Vector2 = Vector2(sim.u_x[u], sim.u_z[u]) if u >= 0 else cfg.get("near", Vector2.ZERO)
		print("[город] кадр %s: работник %d в (%.1f, %.1f)" % [s[0], u, at.x, at.y])
		var yaw := _clear_yaw(q, at, float(cfg.get("yaw", -60.0)))
		var tgt := _work_target(q, aux, at)
		if tgt.is_finite():
			# камера со стороны работника, цель (дерево, жила) — за ним и чуть в стороне
			var away := at - tgt
			yaw = rad_to_deg(atan2(away.x, away.y)) + 35.0
		view = Vector4(at.x, at.y, float(cfg.get("dist", 18.0)), yaw)
	if pitch >= 0.0:
		var shot := scene.get_node("Cameras/CamShot") as Camera3D
		var f := Vector3(view.x, Terrain.height_at(view.x, view.y), view.y)
		var p := deg_to_rad(pitch)
		var y := deg_to_rad(view.w)
		var pos := f + Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * view.z
		pos.y = maxf(pos.y, Terrain.height_at(pos.x, pos.z) + 2.0)
		shot.global_position = pos
		shot.look_at(f + Vector3(0, 1.2, 0), Vector3.UP)
		shot.make_current()
	else:
		cam.go_to(view, true)
		cam.make_current()
	if cfg.has("ghost"):
		var g: Array = cfg["ghost"]
		var defs := q.defs()
		var bt := defs.building(StringName(g[0]))
		var c := q.snap(bt, g[1], g[2])
		scene.ghost.show_building(bt, c, g[2], q.place_cells(0, bt, c, g[2]))
	if cfg.has("wall"):
		var w: Array = cfg["wall"]
		var defs := q.defs()
		var wt := defs.building(StringName(w[0]))
		var pts := PackedVector2Array(w[1])
		var plan := q.plan_wall(0, wt, pts)
		# звенья на постройках — красные (заглушка навигации проверяет только край карты)
		var why: PackedByteArray = plan["why"]
		var centers: PackedVector2Array = plan["centers"]
		for i in centers.size():
			if _on_building(q, centers[i], 1.0):
				why[i] = NavApi.Why.OVERLAP
		plan["why"] = why
		# призрак постройки и цепочка стены в одном кадре (для проверки обоих видов сразу)
		scene.ghost.show_wall(plan, wt, cfg.has("ghost"))
	if cfg.has("select"):
		var hs := PackedInt32Array()
		var sim := q.battle()
		for what: String in cfg["select"]:
			if what == "drill":
				# отряд сарбозов: все его бойцы
				for u in sim.n:
					if sim.u_life[u] == BattleSim.Life.ALIVE and sim.type_of(u) in ["sarboz", "yuzboshi"] \
							and sim.sq_single[sim.u_squad[u]] == 0:
						hs.append(q.unit_handle(u))
			else:
				var bt := q.buildings()
				var ty := q.defs().building(StringName(what))
				for b in bt.hw:
					if bt.btype[b] == ty and bt.state[b] != BuildingTable.State.FREE:
						hs.append(bt.handle(b))
						break
		scene.selection.set_selection(hs)


## Азимут камеры, при котором ближайшая постройка не заслоняет юнита: камера по ту сторону юнита
## от постройки (постройка — фоном); если построек рядом нет — желаемый
static func _clear_yaw(q: GameQuery, at: Vector2, want: float) -> float:
	var bt := q.buildings()
	var best := -1
	var bd := 20.0 * 20.0
	for b in bt.hw:
		if bt.state[b] == BuildingTable.State.FREE:
			continue
		var d := Vector2(bt.x[b], bt.z[b]).distance_squared_to(at)
		if d < bd:
			bd = d
			best = b
	if best < 0:
		return want
	var away := at - Vector2(bt.x[best], bt.z[best])
	var yaw := rad_to_deg(atan2(away.x, away.y))
	# не прямо против солнца: к желаемому азимуту на треть
	return yaw + angle_difference(deg_to_rad(yaw), deg_to_rad(want)) * 0.35 * 180.0 / PI


## Точка p на следе постройки (кроме стен и звеньев) с запасом pad, м
static func _on_building(q: GameQuery, p: Vector2, pad: float) -> bool:
	var bt := q.buildings()
	var defs := q.defs()
	for b in bt.hw:
		if bt.state[b] == BuildingTable.State.FREE or bt.btype[b] < 0:
			continue
		var k := defs.b_kind[bt.btype[b]]
		if k == Defs.BKind.WALL or k == Defs.BKind.LINK:
			continue
		var l := (p - Vector2(bt.x[b], bt.z[b])).rotated(bt.rot[b])
		var e := defs.b_size[bt.btype[b]] * 0.5 + Vector2(pad, pad)
		if absf(l.x) <= e.x and absf(l.y) <= e.y:
			return true
	return false


## Юнит за работой aux у своей цели, ближайший к near (−1 — нет). Юнитов нагрузки (--stress) не берём.
static func _worker(q: GameQuery, aux: float, near: Vector2) -> int:
	var sim := q.battle()
	var last := sim.n if GorodStress.first_unit < 0 else mini(sim.n, GorodStress.first_unit)
	var best := -1
	var bd := INF
	for u in last:
		if sim.u_life[u] != BattleSim.Life.ALIVE or sim.u_act[u] != BattleSim.Act.WORK:
			continue
		if absf(sim.u_work[u] - aux) > 0.01:
			continue
		var p := Vector2(sim.u_x[u], sim.u_z[u])
		var d := p.distance_squared_to(near)
		if d >= bd or not _at_work(q, aux, p, Vector2(sim.u_vx[u], sim.u_vz[u]).length()):
			continue
		bd = d
		best = u
	return best


## Цель работы у точки p: дерево (рубит) или жила (копает); нет — Vector2.INF
static func _work_target(q: GameQuery, aux: float, p: Vector2) -> Vector2:
	if aux >= AnimSpec.WORK_BUILD - 0.01:
		return Vector2.INF
	var nt := q.nodes()
	var tree := aux < AnimSpec.WORK_DIG - 0.01
	var best := Vector2.INF
	var bd := 12.0 * 12.0
	for n in nt.hw:
		if nt.ntype[n] < 0 or (nt.scatter_ref[n] >= 0) != tree:
			continue
		var c := Vector2(nt.x[n], nt.z[n])
		if c.distance_squared_to(p) < bd:
			bd = c.distance_squared_to(p)
			best = c
	return best


## Работник в p со скоростью spd — у своей цели: рубит — у живого дерева, копает — у жилы (не поле),
## строит — у стройки; несёт — идёт
static func _at_work(q: GameQuery, aux: float, p: Vector2, spd: float) -> bool:
	if aux >= AnimSpec.WORK_CARRY - 0.01:
		return spd > 0.3
	if spd > 0.1:
		return false
	if aux >= AnimSpec.WORK_BUILD - 0.01:
		var bt := q.buildings()
		var defs := q.defs()
		for b in bt.hw:
			if bt.state[b] == BuildingTable.State.SITE and bt.btype[b] >= 0:
				var r := defs.b_size[bt.btype[b]].length() * 0.5 + 3.0
				if p.distance_squared_to(Vector2(bt.x[b], bt.z[b])) < r * r:
					return true
		return false
	var nt := q.nodes()
	var tree := aux < AnimSpec.WORK_DIG - 0.01
	for n in nt.hw:
		if nt.ntype[n] < 0 or nt.amount_milli[n] == 0:
			continue
		if (nt.scatter_ref[n] >= 0) != tree:
			continue
		var r := 3.0 if tree else 9.0
		if p.distance_squared_to(Vector2(nt.x[n], nt.z[n])) < r * r:
			return true
	return false
