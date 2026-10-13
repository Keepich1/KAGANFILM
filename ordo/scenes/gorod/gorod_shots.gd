class_name GorodShots
extends RefCounted
## Серия кадров проверки вида «Города» (VIEW, ARCHITECTURE §19.5): стройки на разных стадиях, стена,
## призрак зелёный и красный, работники (рубят, копают, строят, несут), выделение, стада, лагерь.
##   tools/shot.sh res://scenes/gorod/gorod.tscn out.png -- --skip=6 --series=/abs/dir [--only=sites,ghost_bad]
## Камера — RtsCamera.go_to(x, z, расстояние, азимут) или «на юнита за работой» (work = AnimSpec.WORK_*).

## [имя, {view: Vector4 | work: aux, near: Vector2, dist, yaw, ghost: ..., select: ...}]
const SHOTS := [
	["town", {"view": Vector4(186, 52, 165, -58)}],
	["sites", {"view": Vector4(222, 60, 95, -78)}],
	["walls", {"view": Vector4(140, 30, 62, -96)}],
	["ghost_ok", {"view": Vector4(166, 70, 48, -70), "ghost": ["uy", Vector2(163, 72), 0]}],
	["ghost_bad", {"view": Vector4(170, 30, 50, -70), "ghost": ["kazarma", Vector2(172, 26), 1],
		"wall": ["devor", [Vector2(150, -8), Vector2(204, -8)]]}],
	["chop", {"work": 0.0, "near": Vector2(166, 30), "dist": 16.0, "yaw": -55.0}],
	["dig", {"work": 0.25, "near": Vector2(266, -66), "dist": 18.0, "yaw": -60.0}],
	["build", {"work": 0.5, "near": Vector2(214, 8), "dist": 17.0, "yaw": -50.0}],
	["carry", {"work": 0.75, "near": Vector2(180, 20), "dist": 16.0, "yaw": -60.0}],
	["select", {"view": Vector4(150, 52, 78, -72), "select": ["drill", "urda"]}],
	["fields", {"view": Vector4(168, -36, 72, -62)}],
	["herd_sheep", {"view": Vector4(-112, 68, 44, -64)}],
	["herd_horses", {"view": Vector4(-26, 90, 38, -70)}],
	["camp", {"view": Vector4(-72, 34, 150, -62)}],
	["gold", {"work": 0.25, "near": Vector2(-56, 168), "dist": 20.0, "yaw": -70.0}],
	["raid", {"view": Vector4(112, 132, 40, -60)}],
]


static func setup(scene: GorodScene, s: Array) -> void:
	var cfg: Dictionary = s[1]
	var q := CityView.query_of(scene.driver)
	var cam := scene.camera
	scene.ghost.hide_ghost()
	scene.selection.set_selection(PackedInt32Array())
	if cfg.has("view"):
		cam.go_to(cfg["view"], true)
	elif cfg.has("work"):
		var u := _worker(q, float(cfg["work"]), cfg.get("near", Vector2.ZERO))
		var sim := q.battle()
		var at: Vector2 = Vector2(sim.u_x[u], sim.u_z[u]) if u >= 0 else cfg.get("near", Vector2.ZERO)
		cam.go_to(Vector4(at.x, at.y, float(cfg.get("dist", 18.0)), float(cfg.get("yaw", -60.0))), true)
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
