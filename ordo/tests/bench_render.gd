extends SceneTree
## Замер отрисовки среза (видеокарта): вызовы отрисовки, треугольники и объекты — отдельно основной
## проход и проходы теней (RenderingServer.viewport_get_render_info), по уровням качества и камерам,
## с нагрузкой F9 (+3000 солдат) и эффектами боя. Счёт движка — только с настоящим рендером:
##   tools/godot.sh --path ordo --resolution 1920x1080 --audio-driver Dummy --fixed-fps 30 \
##       --script res://tests/bench_render.gd -- --quality=high [ключи]
## Только толпа по юнитам (что остаётся после шейдера) — быстро, без видеокарты:
##   godot --headless --path ordo --script res://tests/bench_render.gd -- --stress=2 --freeze
## Ключи (после «--»):
##   --presets=high,medium,low   уровни по очереди (смена как по F2: Ordo.set_quality)
##   --cams=CamRTS,CamBattleRTS  камеры (CamBattleRTS — та, что после F9 по умолчанию)
##   --stress=2                  нагрузка F9: 1 — +1000, 2 — +3000 солдат (ключ среза)
##   --warm=9                    секунд боя до замера (шаги без отрисовки)
##   --frames=1                  кадров замера на камеру (среднее)
##   --settle=8                  кадров перед замером после смены уровня, камеры или части: толпа
##                               раскладывает блоки по LOD за 8 кадров, трава и LOD догоняют камеру
##   --breakdown                 на первом уровне и первой камере — вклад частей (прячем по одной)
##   --freeze                    после разогрева бои на паузе: каждый кадр замера тот же (толпа, дым),
##                               числа не скачут от кадра к кадру и вклад частей не шумит
##   --full                      рисовать всё (иначе объёмный туман, SSAO, свечение, MSAA и живописный
##                               фильтр выключены — на счёт вызовов и треугольников они не влияют,
##                               а программный Vulkan с ними считает кадр в разы дольше)
##   --out=/abs/file.json        итог в JSON
##   --gpu_ab=3                  вместо счёта: время кадра видеокарты (viewport_get_measured_render_time_gpu)
##                               «Высокого» на первой камере, полный кадр — прежние настройки, новые и новые
##                               с возвратом одной меры (фильтр, сглаживание, тени, туман); столько кругов,
##                               варианты чередуются, итог — медиана. На программном Vulkan это время
##                               процессора за работу видеокарты (шумно при занятой машине), но доли мер видны
## Числа вызовов и треугольников честны и на программном Vulkan (lavapipe): это счёт отправленного
## на видеокарту. Время видеокарты здесь не меряется — его смотреть на F9 у автора.
## Толпа отправляет больше, чем рисует: шейдер сжимает в точку юнитов не своей полосы LOD, вне кадра
## прохода и вне каскадов, куда падает их тень. Строка «толпа по юнитам» — оценка того, что остаётся
## (по каждому юниту, как в шейдере: полоса LOD, кадр камеры, каскады тени; кадр каскада не учтён —
## оценка сверху). С --headless счёта движка нет (нули), а толпа по юнитам — есть: быстро, без видеокарты
## (кадр 1920 × 1080 для каскадов задаётся сам).
## До замера (загрузка, разогрев боя) 3D не рисуется (Viewport.disable_3d).
## Процессор: «толпа» и «эффекты» — PerfMeter view / fx (мс за последний кадр замера).

const SLICE := "res://scenes/slice.tscn"

var _presets: Array[String] = ["high", "medium", "low"]
var _cams: Array[String] = ["CamRTS", "CamBattleRTS"]
var _warm := 9.0
var _frames := 1
var _settle := 8
var _breakdown := false
var _freeze := false
var _full := false
var _out := ""
var _results: Array = []
var _started := false
var _gpu_rounds := 0
var _headless := DisplayServer.get_name() == "headless"

## Варианты --gpu_ab: имя → ключи сравнения WorldQuality (пусто — уровень как есть)
const GPU_VARIANTS := {
	"прежнее «Высокое»": {"post_cap": "0", "aa": "msaa", "shadow_atlas": "8192", "fog_grid": "128", "fog_depth": "128"},
	"новое «Высокое»": {},
	"новое, фильтр в полном кадре": {"post_cap": "0"},
	"новое, MSAA 4×": {"aa": "msaa"},
	"новое, тени 8192": {"shadow_atlas": "8192"},
	"новое, туман 128³": {"fog_grid": "128", "fog_depth": "128"},
}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		var v := kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"presets":
				_presets.clear()
				for s in v.split(",", false):
					_presets.append(s)
			"cams":
				_cams.clear()
				for s in v.split(",", false):
					_cams.append(s)
			"warm":
				_warm = float(v)
			"frames":
				_frames = maxi(1, int(v))
			"settle":
				_settle = maxi(0, int(v))
			"breakdown":
				_breakdown = true
			"freeze":
				_freeze = true
			"full":
				_full = true
			"out":
				_out = v
			"gpu_ab":
				_gpu_rounds = maxi(1, int(v)) if v != "" else 3
				_full = true
	if _headless:
		# без окна кадр 64 × 64 — каскады теней толпы считались бы для другого кадра
		root.size = Vector2i(1920, 1080)
		print("[замер] без видеокарты (--headless): счёта движка нет, только толпа по юнитам")
	change_scene_to_file(SLICE)


func _process(_delta: float) -> bool:
	if not _started and current_scene != null and current_scene.is_node_ready():
		_started = true
		root.disable_3d = true
		_run()
	return false


## Только счёт: выключить то, что не меняет вызовов и треугольников, но долго считается на процессоре
func _count_only(slice: Node) -> void:
	if _full:
		return
	var we := slice.get_node_or_null("World/Environment") as WorldEnvironment
	if we:
		we.environment.volumetric_fog_enabled = false
		we.environment.ssao_enabled = false
		we.environment.glow_enabled = false
		if we.compositor:
			for e in we.compositor.compositor_effects:
				e.enabled = false
	root.msaa_3d = Viewport.MSAA_DISABLED


func _run() -> void:
	# два кадра: качество применяется отложенно, слои толпы собираются
	await process_frame
	await process_frame
	var slice := current_scene
	var ordo := root.get_node_or_null("Ordo")
	print("[замер] видеокарта: %s, кадр %s" % [RenderingServer.get_video_adapter_name(), root.size])
	_warm_up(slice)
	if _freeze:
		# бои на паузе (как P в срезе): толпа стоит, частицы эффектов замирают, но рисуются
		for v: BattleView in _views(slice):
			var sc := v.get("scenario") as SimDriver
			if sc:
				sc.paused = true
		print("[замер] бои на паузе (--freeze)")
	if _gpu_rounds > 0:
		await _gpu_ab(slice, ordo)
		quit()
		return
	for level in _presets:
		ordo.call("set_quality", level, false)
		var sun := slice.get_node_or_null("World/Sun") as DirectionalLight3D
		if sun:
			sun.shadow_enabled = true
		_count_only(slice)
		root.disable_3d = false
		for cam_name in _cams:
			var cam := slice.find_child(cam_name, true, false) as Camera3D
			if cam == null:
				print("[замер] нет камеры ", cam_name)
				continue
			# смена уровня и камеры действует в следующем кадре, но толпа раскладывает блоки по LOD
			# за 8 кадров, а трава и деревья догоняют камеру — меряем после --settle кадров
			cam.make_current()
			var r := await _measure(level, cam_name)
			_results.append(r)
			_print_row(r)
			if _breakdown and level == _presets[0] and cam_name == _cams[0]:
				await _parts(slice, level, cam_name, r)
	_print_table()
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(_results, "  "))
	quit()


## Бой до замера без отрисовки кадров: шаги симуляции основного и нагрузочного боя
## (их сигналы идут в эффекты, как в игре)
func _warm_up(slice: Node) -> void:
	var t0 := Time.get_ticks_msec()
	var drivers: Array = []
	for v: BattleView in _views(slice):
		if v.stepper():
			v.sync_sim()
			drivers.append(v.stepper())
	var steps := int(_warm / BattleSim.DT)
	for i in steps:
		for st: SimStepper in drivers:
			st.advance(BattleSim.DT)
	for st: SimStepper in drivers:
		st.sync()
	var units := 0
	for st: SimStepper in drivers:
		units += st.scenario.sim.n
	print("[замер] разогрев: %.1f с боя, %d юнитов, %d мс" % [_warm, units, Time.get_ticks_msec() - t0])


## Виды боя: основной и нагрузочный (F9)
func _views(slice: Node) -> Array[BattleView]:
	var out: Array[BattleView] = []
	var main := slice.get_node_or_null("Battle/View") as BattleView
	if main:
		out.append(main)
	var stress := slice.get("_stress") as Node
	if stress and stress.get_node_or_null("View") is BattleView:
		out.append(stress.get_node("View") as BattleView)
	return out


func _info(type: int, what: int) -> int:
	return RenderingServer.viewport_get_render_info(root.get_viewport_rid(), type, what)


func _sample() -> Dictionary:
	var V := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	var S := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW
	var DC := RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
	var PR := RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
	var OB := RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME
	return {
		"main_draws": _info(V, DC), "main_prims": _info(V, PR), "main_objs": _info(V, OB),
		"shadow_draws": _info(S, DC), "shadow_prims": _info(S, PR), "shadow_objs": _info(S, OB),
	}


func _measure(level: String, cam_name: String, settle := -1) -> Dictionary:
	for i in (_settle if settle < 0 else settle):
		await _next_frame()
	var acc := {}
	var view_ms := 0.0
	var fx_ms := 0.0
	for i in _frames:
		await _next_frame()
		var s := _sample()
		for k in s:
			acc[k] = int(acc.get(k, 0)) + int(s[k])
		# время этого кадра (PerfMeter копит сумму кадра, пока кадр не закрыт)
		view_ms += _frame_ms(&"view")
		fx_ms += _frame_ms(&"fx")
	var r := {"level": level, "cam": cam_name}
	for k in acc:
		r[k] = int(round(float(acc[k]) / _frames))
	r["draws"] = int(r.main_draws) + int(r.shadow_draws)
	r["prims"] = int(r.main_prims) + int(r.shadow_prims)
	r["view_ms"] = view_ms / _frames
	r["fx_ms"] = fx_ms / _frames
	r["particles"] = _particles()
	r.merge(_crowd_estimate())
	return r


## Толпа по юнитам — что остаётся после отбрасывания в шейдере (crowd.gdshader, crowd_keep), тем же
## правилом: основной проход — юниты, чья сфера (над ступнями, радиус 4 м) в кадре камеры, своей моделью
## (LOD0 ближе дальности LOD, дальше LOD1); проходы теней — юниты ближе конца теней (подробной моделью
## ближе near_shadow_distance, дальше облегчённой) в каждом каскаде, куда падает их тень
## (CrowdLayer.shadow_cascades) и в чей квадрат (полуширина каскада вокруг середины его куска кадра,
## в осях солнца) попадает сфера юнита; движок до того отбрасывает отбрасывающих тень вне куска кадра,
## протянутого к солнцу, — здесь: юнит дальше боковых плоскостей кадра, чем радиус и длина его тени.
## Кадр — 16:9 без окна (--headless), иначе окна. Оценка сверху (кадр каскада — шаром, как в шейдере).
func _crowd_estimate() -> Dictionary:
	var cam := root.get_camera_3d()
	var out := {"crowd_units": 0, "crowd_main_est": 0, "crowd_shadow_est": 0, "crowd_casc": 0.0}
	if cam == null or current_scene == null:
		return out
	var size := Vector2(root.size)
	var aspect := 16.0 / 9.0 if _headless or size.y < 1.0 else size.x / size.y
	var proj := Projection.create_perspective(cam.fov, aspect, cam.near, cam.far)
	var view := cam.global_transform.affine_inverse()
	var cp := cam.global_position
	var fwd := -cam.global_basis.z
	var sun := current_scene.get_tree().get_first_node_in_group(CrowdLayer.SUN_GROUP) as DirectionalLight3D
	var sx := sun.global_basis.x if sun else Vector3.RIGHT
	var sy := sun.global_basis.y if sun else Vector3.UP
	# боковые плоскости кадра (наружу) и длина тени юнита при этом солнце (как CrowdLayer.shadow_reach)
	var ty := tan(deg_to_rad(cam.fov) * 0.5)
	var tx := ty * aspect
	var sides: Array[Vector3] = [Vector3(1.0, 0.0, tx).normalized(), Vector3(-1.0, 0.0, tx).normalized(),
		Vector3(0.0, 1.0, ty).normalized(), Vector3(0.0, -1.0, ty).normalized()]
	var light := -sun.global_basis.z if sun else Vector3.DOWN
	var hl := Vector2(light.x, light.z).length()
	var shadow_len := minf(CrowdLayer.SHADOW_HEIGHT * hl / maxf(-light.y, 0.01), CrowdLayer.SHADOW_REACH_MAX)
	var casc_sum := 0
	var casters := 0
	for v: BattleView in _views(current_scene):
		for l in v.layers.values():
			var layer := l as CrowdLayer
			if layer == null or layer._mm.size() < CrowdLayer.PARTS:
				continue
			var t0 := _tris(layer._mm[CrowdLayer.Part.LOD0_NEAR].mesh)
			var t1 := _tris(layer._mm[CrowdLayer.Part.LOD1].mesh)
			var cfg: Dictionary = layer._shadow_cfg(cam, aspect)
			var send: float = 0.0 if layer._casc_mode == "none" else layer._shadow_end()
			var near: float = cfg.near
			var lod: float = layer._lod_d
			var r4: Vector4 = cfg.r
			var lo4: Vector4 = cfg.lo
			var hi4: Vector4 = cfg.hi
			var buf := layer.buffer()
			for i in layer.get_visible_count():
				var o := Vector3(buf[i * 16 + 3], buf[i * 16 + 7], buf[i * 16 + 11])
				var d := cp.distance_to(o)
				out.crowd_units += 1
				# кадр камеры — как crowd_keep: сфера над ступнями в пирамиде (без ближней и дальней плоскости)
				var c := proj * _v4(view * (o + Vector3(0.0, 1.5, 0.0)))
				var rw := absf(proj.z.w) * 4.0
				if absf(c.x) <= c.w + absf(proj.x.x) * 4.0 + rw and absf(c.y) <= c.w + absf(proj.y.y) * 4.0 + rw:
					out.crowd_main_est += t0 if d < lod else t1
				if d >= send:
					continue
				var beside := false
				var oc := view * o
				for n in sides:
					if n.dot(oc) > CrowdLayer.UNIT_RADIUS + shadow_len:
						beside = true
						break
				if beside:
					continue
				var mask := CrowdLayer.shadow_cascades(fwd.dot(o - cp), cfg)
				var k := 0
				for b in 4:
					if not (mask >> b) & 1:
						continue
					if r4[b] > 0.0:
						var cc := cp + fwd * (0.5 * (lo4[b] + minf(hi4[b], cam.far)))
						var e := o - cc
						if absf(e.dot(sx)) > r4[b] + 4.0 or absf(e.dot(sy)) > r4[b] + 4.0:
							continue
					k += 1
				out.crowd_shadow_est += (t0 if d < near else t1) * k
				casc_sum += k
				casters += 1
	out.crowd_casc = float(casc_sum) / maxf(casters, 1.0)
	return out


func _v4(p: Vector3) -> Vector4:
	return Vector4(p.x, p.y, p.z, 1.0)


## Треугольников в меше (все поверхности)
func _tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var n := 0
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		n += idx.size() / 3 if idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


## Следующий кадр: после отрисовки; без видеокарты (--headless) кадров отрисовки нет — следующий кадр игры
func _next_frame() -> void:
	if _headless:
		await process_frame
	else:
		await RenderingServer.frame_post_draw


func _frame_ms(name: StringName) -> float:
	var e: Array = PerfMeter._m.get(name, [])
	return float(e[1]) if e.size() > 1 and int(e[0]) == Engine.get_process_frames() else 0.0


## Живых частиц не узнать — считаем, сколько заказано (amount) у видимых систем эффектов
func _particles() -> int:
	var n := 0
	for p in current_scene.find_children("*", "GPUParticles3D", true, false):
		if (p as GPUParticles3D).is_visible_in_tree():
			n += (p as GPUParticles3D).amount
	return n


## Вклад частей кадра: прячем по одной и смотрим, сколько ушло
func _parts(slice: Node, level: String, cam_name: String, _base: Dictionary) -> void:
	var parts := {
		"земля": ["World/Terrain"], "трава": ["World/Grass"], "деревья и камни": ["World/Scatter"],
		"вода": ["World/Water"], "туман-полосы": ["World/FogBanks"], "лагерь": ["Camp"],
		"толпа боя": ["Battle/View"], "толпа F9": ["Stress/View"], "эффекты": ["Battle/Fx"],
	}
	var stress := slice.get("_stress") as Node
	print("[замер] вклад частей (%s, %s): вызовов основн./тени · треугольников основн./тени" % [level, cam_name])
	for name in parts:
		var nodes: Array[Node3D] = []
		for path in parts[name]:
			var n := slice.get_node_or_null(path) as Node3D
			if String(path).begins_with("Stress/"):
				n = stress.get_node_or_null(String(path).trim_prefix("Stress/")) as Node3D if stress else null
			if n and n.visible:
				nodes.append(n)
		if nodes.is_empty():
			continue
		# парой кадров подряд «с частью» и «без»: бой идёт, толпа и дым меняются от кадра к кадру,
		# поэтому вычитаем из соседнего кадра, а не из общего замера
		var with := await _measure(level, cam_name, 1)
		for n in nodes:
			n.visible = false
		var r := await _measure(level, cam_name, 1)
		for n in nodes:
			n.visible = true
		r["part"] = name
		for k in ["main_draws", "shadow_draws", "main_prims", "shadow_prims"]:
			r["d_" + k] = int(with[k]) - int(r[k])
		_results.append(r)
		print("    %-16s %4d / %4d · %9s / %9s" % [name, r.d_main_draws, r.d_shadow_draws, _num(r.d_main_prims),
			_num(r.d_shadow_prims)])


func _num(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out


func _print_row(r: Dictionary) -> void:
	print("[замер] %-6s %-13s вызовов %4d (основн. %d, тени %d) · треугольников %s (основн. %s, тени %s) · толпа %.1f мс · эффекты %.1f мс" % [
		r.level, r.cam, r.draws, r.main_draws, r.shadow_draws, _num(r.prims), _num(r.main_prims), _num(r.shadow_prims),
		r.view_ms, r.fx_ms])
	print("         толпа по юнитам (%d): шейдер оставляет треугольников основн. %s, тени %s · тень юнита в среднем в %.2f каскадах" % [
		r.crowd_units, _num(r.crowd_main_est), _num(r.crowd_shadow_est), r.crowd_casc])


func _print_table() -> void:
	print("")
	print("| уровень | камера | вызовов: всего / основн. / тени | треугольников: всего / основн. / тени | объектов осн./тени | толпа по юнитам: основн. / тени (каскадов на юнит) | толпа мс | эффекты мс |")
	print("|---|---|---|---|---|---|---|---|")
	for r: Dictionary in _results:
		if r.has("part"):
			continue
		print("| %s | %s | %d / %d / %d | %s / %s / %s | %d / %d | %s / %s (%.2f) | %.1f | %.1f |" % [r.level, r.cam, r.draws,
			r.main_draws, r.shadow_draws, _num(r.prims), _num(r.main_prims), _num(r.shadow_prims), r.main_objs, r.shadow_objs,
			_num(r.crowd_main_est), _num(r.crowd_shadow_est), r.crowd_casc, r.view_ms, r.fx_ms])


## Время видеокарты «Высокого»: варианты по кругу, на каждый — кадр на смену (карта теней и сетка
## тумана пересоздаются) и кадр замера; итог — медиана по кругам
func _gpu_ab(slice: Node, ordo: Node) -> void:
	var cam := slice.find_child(_cams[0], true, false) as Camera3D
	if cam:
		cam.make_current()
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var args: Dictionary = ordo.get("_args")
	var wq := slice.get_node_or_null("World/Quality") as WorldQuality
	ordo.call("set_quality", "high", false)
	root.disable_3d = false
	var times := {}
	for name in GPU_VARIANTS:
		times[name] = PackedFloat32Array()
	# первый круг — разогрев (шейдеры, толпа раскладывается по LOD), не считается
	for round in _gpu_rounds + 1:
		for name in GPU_VARIANTS:
			for k in ["post_cap", "aa", "shadow_atlas", "fog_grid", "fog_depth"]:
				args.erase(k)
			var over: Dictionary = GPU_VARIANTS[name]
			for k in over:
				args[k] = over[k]
			# только мир (WorldQuality): set_quality перезапустил бы частицы эффектов — дым пропал бы
			if wq:
				wq.apply("high")
			else:
				ordo.call("set_quality", "high", false)
			for i in 2:
				await RenderingServer.frame_post_draw
			var ms := RenderingServer.viewport_get_measured_render_time_gpu(rid)
			if round > 0:
				times[name].append(ms)
			print("[замер] круг %d · %-30s видеокарта %.1f мс" % [round, name, ms])
	print("")
	print("| вариант «Высокого» (%s, %s) | видеокарта, медиана мс | к прежнему |" % [_cams[0], root.size])
	print("|---|---|---|")
	var base := _median(times["прежнее «Высокое»"])
	for name in GPU_VARIANTS:
		var m := _median(times[name])
		print("| %s | %.1f | %+.0f %% |" % [name, m, (m / base - 1.0) * 100.0 if base > 0.0 else 0.0])
		_results.append({"variant": name, "gpu_ms": m, "runs": Array(times[name])})
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(_results, "  "))


func _median(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[b.size() / 2]
