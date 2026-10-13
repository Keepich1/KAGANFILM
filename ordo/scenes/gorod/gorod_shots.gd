class_name GorodShots
extends RefCounted
## Серия кадров проверки вида «Города» (VIEW, ARCHITECTURE §19.5): стройки на разных стадиях, стена,
## призрак зелёный и красный, работники (рубят, копают, строят, несут), выделение, стада, лагерь.
##   tools/shot.sh res://scenes/gorod/gorod.tscn out.png -- --skip=6 --series=/abs/dir [--only=sites,ghost_bad]
## Камера — RtsCamera.go_to(x, z, расстояние, азимут) или «на юнита за работой» (work = AnimSpec.WORK_*);
## с pitch (градусы) — своя камера CamShot с этим наклоном (крупные планы ниже, чем у стратегии).

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
	["carry", {"work": 0.75, "near": Vector2(180, 20), "dist": 15.0, "yaw": -60.0, "pitch": 20.0}],
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
	if cfg.has("view"):
		view = cfg["view"]
	elif cfg.has("work"):
		var u := _worker(q, float(cfg["work"]), cfg.get("near", Vector2.ZERO))
		var sim := q.battle()
		var at: Vector2 = Vector2(sim.u_x[u], sim.u_z[u]) if u >= 0 else cfg.get("near", Vector2.ZERO)
		view = Vector4(at.x, at.y, float(cfg.get("dist", 18.0)), _clear_yaw(q, at, float(cfg.get("yaw", -60.0))))
	if cfg.has("pitch"):
		var shot := scene.get_node("Cameras/CamShot") as Camera3D
		var f := Vector3(view.x, Terrain.height_at(view.x, view.y), view.y)
		var p := deg_to_rad(float(cfg["pitch"]))
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
		# звенья на чужих постройках — красные (заглушка навигации проверяет только край карты)
		var why: PackedByteArray = plan["why"]
		var centers: PackedVector2Array = plan["centers"]
		for i in centers.size():
			var h := q.pick(0, centers[i], 0.1)
			if Ids.kind(h) == Ids.Kind.BUILDING:
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


## Юнит за работой aux, ближайший к near (−1 — нет)
static func _worker(q: GameQuery, aux: float, near: Vector2) -> int:
	var sim := q.battle()
	var best := -1
	var bd := INF
	for u in sim.n:
		if sim.u_life[u] != BattleSim.Life.ALIVE or sim.u_act[u] != BattleSim.Act.WORK:
			continue
		if absf(sim.u_work[u] - aux) > 0.01:
			continue
		var d := Vector2(sim.u_x[u], sim.u_z[u]).distance_squared_to(near)
		if d < bd:
			bd = d
			best = u
	return best
