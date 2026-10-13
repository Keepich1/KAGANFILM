class_name UnitView
extends BattleView
## Юниты «Города» (ARCHITECTURE §13): слои толпы с ДИНАМИЧЕСКИМИ местами.
##
## В городе юниты рождаются (найм, набеги) и освобождаются (FREE, смена поколения u_gen), поэтому
## места в слоях выдаются на ходу: slot_of[u] и unit_of_slot[layer][slot], удаление — перестановкой
## последнего на место ушедшего (видимые места всегда 0..count−1). Событий о рождении не нужно:
## вид сам видит новый индекс, FREE и смену поколения. Слой начинается с 512 мест и при заполнении
## пересоздаётся вдвое больше.
##
## Роль знаменосца ядро меняет без нового поколения (CORE R3: собрать отряд из одиночек — последний
## боец становится BANNER, распустить — снова TROOPER), поэтому вид помнит и флаг знамени: сменился —
## юнит переезжает в слой с флагом (или без). Знаменосец без своего «_banner»-вида рисуется знаменосцем
## своей стороны (BANNER_STANDIN: пеший — kok_sarboz_banner, конный — kip_sayisker_banner, атлас стороны).
##
## Анимация — как у BattleView (_human_c/_rider_c), плюс работа: Act.WORK → AnimSpec.Human.WORK
## с видом работы u_work (рубит/копает/строит — цикл по времени; несёт — ноги по пройденному пути,
## ARCHITECTURE §1 ряд 22). Тела перед уборкой (corpse_steps) за последние 3 с уходят в землю.
## Гарнизон — на высоте площадки st_top. Арбы — отдельные модели kipchak/arba.glb (пока у толпы нет
## скелета «wagon»). Юниты без своей модели рисуются заместителем (STANDIN) — модель ближайшего вида,
## атлас своей стороны (цвет стороны узнаётся сразу).
##
## Несущий груз (WORK_CARRY): у работников с ношей в реестре толпы (item «sack»: kok_dehqon, kip_malchy)
## мешок и бревно рисует шейдер толпы; у прочих людских видов — мешок за спиной (свой MultiMesh «Sacks»,
## один вызов отрисовки).
##
## Каждый кадр обновляются только юниты в прямоугольнике камеры + 40 м, остальные — раз в 4 кадра.
## Время кадра — PerfMeter «view_units».
##
## Шаги симуляции ведёт сам драйвер (SimDriver._process, узел раньше вида в дереве), а не SimStepper:
## FakeCity/GameSim пишут не только ядро, и фоновый шаг читал бы таблицы на ходу.

const START_CAP := 512
const CULL_PAD := 40.0
## Тела уходят в землю за последние SINK_S секунд перед уборкой, на SINK_DEPTH м
const SINK_S := 3.0
const SINK_DEPTH := 0.9
## Цикл работы, с: рубит, копает, строит (молот — два удара за цикл)
const WORK_CHOP_S := 1.5
const WORK_DIG_S := 1.7
const WORK_BUILD_S := 1.3
const FREE := BattleSim.Life.FREE
const ACT_WORK := BattleSim.Act.WORK
const BANNER := BattleSim.Role.BANNER

## Заместители: тип ядра → [вид толпы, атлас стороны ("" — атлас самого вида)].
## Работник Коканда — свой вид kok_dehqon (инструменты по WORK), в UnitStats (срез) его поля visual нет.
const STANDIN := {
	"dehqon": ["kok_dehqon", ""],
	"kilichboz": ["kip_jooker", "kokand"],
	"nayzachi": ["kok_sarboz", ""],
	"kamonchi": ["kok_sarboz", ""],
	"zarbzan": ["kok_sarboz", ""],
	"navkar": ["kok_yuzboshi", ""],
	"xos_navkar": ["kok_yuzboshi", ""],
	"lashkarboshi": ["kok_yuzboshi", ""],
	"atchan": ["kip_sayisker", ""],
	"chabuulchu": ["kip_sayisker", ""],
	"batyr": ["kip_kolbashchy", ""],
	"mergen": ["kip_jooker", ""],
}
## Знаменосец, у вида которого нет «_banner»: базовый вид → знаменный вид толпы и его родная сторона
const BANNER_STANDIN := {
	"kok_sarboz": ["kok_sarboz_banner", "kokand"],
	"kip_jooker": ["kok_sarboz_banner", "kokand"],
	"kip_malchy": ["kok_sarboz_banner", "kokand"],
	"kok_yuzboshi": ["kip_sayisker_banner", "kipchak"],
	"kip_sayisker": ["kip_sayisker_banner", "kipchak"],
	"kip_kolbashchy": ["kip_sayisker_banner", "kipchak"],
}
const ATLAS := {
	"kokand": "res://assets/textures/units/kokand_units.png",
	"kipchak": "res://assets/textures/units/kipchak_units.png",
}
const ARBA_MODEL := "res://assets/models/kipchak/arba.glb"
## Мешок несущего: центр на доле высоты вида и за спиной, м
const SACK_UP := 0.6
const SACK_BACK := 0.26

## Обновлять дальние юниты реже (выключают тесты, чтобы видеть каждый кадр)
@export var cull := true

var frame := 0
## Слои: вид (ключ «вид|атлас»), узел, юниты по местам, число занятых мест
var l_key := PackedStringArray()
var l_node: Array[Node3D] = []
var l_units: Array[PackedInt32Array] = []
var l_count := PackedInt32Array()
## Юнит ядра → слой (−1 нет, −2 арба) и место
var slot_of := PackedInt32Array()
var layer_of := PackedInt32Array()

var _l_fast: Array[bool] = []
var _l_index := {}
var _seen_gen := PackedInt32Array()
var _seen_banner := PackedByteArray()  # 1 — юнит нарисован знаменосцем (роль меняется без поколения)
var _fresh := PackedByteArray()        # новое место: записать в этом кадре, даже если вне камеры
var _arbas: Array[Node3D] = []         # по местам арб
var _arba_units := PackedInt32Array()
var _arba_root: Node3D
var _rect := Rect2()
var _standin_mats := {}
var _l_sack := PackedFloat32Array()    # по слоям: высота центра мешка (0 — без мешка)
var _sacks: MultiMeshInstance3D
var _sack_buf := PackedFloat32Array()
## Сколько мешков нарисовано в последнем кадре (тесты)
var sacks_drawn := 0


func _ready() -> void:
	scenario = get_node_or_null(scenario_path) as SimDriver
	if not force_debug and ResourceLoader.exists(CROWD_LAYER_PATH):
		_crowd_script = load(CROWD_LAYER_PATH) as Script
		using_real_crowd = _crowd_script != null
	if ResourceLoader.exists(REGISTRY_PATH):
		var reg := load(REGISTRY_PATH) as Script
		if reg:
			_registry = reg.get_script_constant_map().get("UNITS", {})
	_arba_root = Node3D.new()
	_arba_root.name = "Arbas"
	add_child(_arba_root)
	if scenario:
		scenario.started.connect(_on_started)
		if scenario.sim:
			_on_started(scenario.current_seed)


## Подключить ядро без дерева сцены (тесты): bind(sim)
func bind(sim: BattleSim) -> void:
	if _arba_root == null:
		_arba_root = Node3D.new()
		_arba_root.name = "Arbas"
		add_child(_arba_root)
	_sim = sim
	_reset()


func _on_started(_seed: int) -> void:
	_sim = scenario.sim
	_reset()


func _rebuild() -> void:
	_reset()


func _reset() -> void:
	for li in l_node.size():
		l_count[li] = 0
		l_node[li].call("set_visible_count", 0)
	slot_of.resize(0)
	layer_of.resize(0)
	_seen_gen.resize(0)
	_seen_banner.resize(0)
	_fresh.resize(0)
	_u_layer.resize(0)
	_u_slot.resize(0)
	for a in _arbas:
		a.queue_free()
	_arbas.clear()
	_arba_units.resize(0)
	_hgt = Terrain.heights()
	_hn = Terrain.size()
	_hsp = Terrain.spacing()
	var o := Terrain.origin()
	_hox = o.x
	_hoz = o.y
	_b_owner = null


func _process(_delta: float) -> void:
	update_view()


## Кадр вида (замеры и тесты зовут его сами)
func update_view() -> void:
	var t0 := CityView.now_usec()
	if _sim and (scenario == null or scenario.sim == _sim):
		frame += 1
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		_rect = CityView.camera_ground_rect(cam, CULL_PAD) if cull and cam else Rect2(-1.0e6, -1.0e6, 2.0e6, 2.0e6)
		sync_slots()
		_bind_sim(_sim)
		_update_units()
		_update_arbas()
		_unbind()
	CityView.mark(&"view_units", t0)


## Отпустить массивы ядра до следующего кадра (ARCHITECTURE §5.2, правило 9: массивы ядра — только в
## локальных на время кадра, в полях между кадрами не держать)
func _unbind() -> void:
	_b_owner = null
	_b_x = PackedFloat32Array()
	_b_z = PackedFloat32Array()
	_b_h = PackedFloat32Array()
	_b_px = PackedFloat32Array()
	_b_pz = PackedFloat32Array()
	_b_ph = PackedFloat32Array()
	_b_vx = PackedFloat32Array()
	_b_vz = PackedFloat32Array()
	_b_life = PackedInt32Array()
	_b_death_t = PackedFloat32Array()
	_b_act = PackedInt32Array()
	_b_act_t = PackedFloat32Array()
	_b_reload_t = PackedFloat32Array()
	_b_couched = PackedInt32Array()
	_b_fall = PackedInt32Array()
	_b_sq_status = PackedInt32Array()
	_b_var = PackedFloat32Array()
	_b_role = PackedInt32Array()
	_b_squad = PackedInt32Array()


# ---------------------------------------------------------------- места

## Сверка мест с ядром: новые юниты получают место, FREE и сменившие поколение — отдают;
## сменившие роль знаменосца (собрали или распустили отряд) — переезжают в другой слой
func sync_slots() -> void:
	var sim := _sim
	var n := sim.n
	if slot_of.size() < n:
		_grow_units(n)
	var life := sim.u_life
	var gen := sim.u_gen
	var role := sim.u_role
	var seen := _seen_gen
	var seen_b := _seen_banner
	var lay := layer_of
	for u in n:
		if life[u] == FREE:
			if lay[u] != -1:
				_release(u)
			seen[u] = 0
			continue
		var bf := 1 if role[u] == BANNER else 0
		if seen[u] != gen[u] or seen_b[u] != bf:
			if lay[u] != -1:
				_release(u)
			seen[u] = gen[u]
			seen_b[u] = bf
			_map(u)


func _grow_units(n: int) -> void:
	var old := slot_of.size()
	for arr: Variant in [slot_of, layer_of]:
		arr.resize(n)
	_seen_gen.resize(n)
	_seen_banner.resize(n)
	_fresh.resize(n)
	for a: Variant in [_u_skel, _u_slot]:
		a.resize(n)
	for a: Variant in [_u_stride_k, _u_fallrot, _phase, _lx, _lz]:
		a.resize(n)
	_u_done.resize(n)
	for u in range(old, n):
		slot_of[u] = -1
		layer_of[u] = -1
		_seen_gen[u] = 0
		_seen_banner[u] = 0


## Юнит получает вид, слой и место
func _map(u: int) -> void:
	var sim := _sim
	var t := sim.type_of(u)
	_u_done[u] = 0
	_u_fallrot[u] = (BattleRng.hash01(u * 7 + 3 + _seen_gen[u] * 131) - 0.5) * 1.5
	_phase[u] = BattleRng.hash01(u * 3 + 1 + _seen_gen[u] * 17)
	_lx[u] = sim.u_x[u]
	_lz[u] = sim.u_z[u]
	if sim.t_flags[sim.u_type[u]] & UnitStats.WAGON:
		_add_arba(u)
		return
	var key := layer_key(t, sim.u_role[u] == BANNER)
	if key == "":
		return
	var vid := key.get_slice("|", 0)
	var info := unit_info(vid)
	_u_skel[u] = 0 if String(info.get("skeleton", "human")) == "human" else 1
	_u_stride_k[u] = float(info.get("scale", 1.0))
	var li := _layer_for(key)
	_acquire(u, li)


## Ключ слоя «вид|атлас» для типа ядра ("" — не рисуется); banner — знаменосец отряда
func layer_key(type_id: String, banner: bool) -> String:
	var vid := UnitStats.visual_for(type_id, banner)
	var atlas := ""
	if vid == "" and STANDIN.has(type_id):
		var s: Array = STANDIN[type_id]
		vid = s[0]
		atlas = s[1]
	if vid == "":
		return ""
	if banner and not vid.ends_with("_banner") and BANNER_STANDIN.has(vid):
		# знамя в руке — знаменосец своей стороны: родной вид или атлас стороны поверх
		var bs: Array = BANNER_STANDIN[vid]
		var side := String(UnitStats.get_stats(type_id).get("faction", bs[1]))
		vid = bs[0]
		atlas = "" if side == bs[1] or not ATLAS.has(side) else side
	return vid + "|" + atlas


func _layer_for(key: String) -> int:
	if _l_index.has(key):
		return _l_index[key]
	var li := l_key.size()
	_l_index[key] = li
	l_key.append(key)
	var l := _make_layer()
	l.name = "Layer_" + key.replace("|", "_")
	add_child(l)
	l_node.append(l)
	l_units.append(PackedInt32Array())
	l_count.append(0)
	_l_fast.append(false)
	# ноша вида — по реестру толпы (и у отладочного слоя: тесты рисуют без толпы)
	var vid := key.get_slice("|", 0)
	var info := UnitRegistry.info(vid) if UnitRegistry.has(vid) else unit_info(vid)
	var human := String(info.get("skeleton", "human")) == "human"
	var own_sack := String(info.get("item", "")) == "sack" or String(info.get("weapon", "")) == "tool"
	_l_sack.append(float(info.get("height", 2.0)) * SACK_UP if human and not own_sack else 0.0)
	_setup_layer(li, START_CAP)
	return li


func _setup_layer(li: int, cap: int) -> void:
	var l := l_node[li]
	var vid := l_key[li].get_slice("|", 0)
	var atlas := l_key[li].get_slice("|", 1)
	l.call("setup", vid, cap)
	_l_fast[li] = l.has_method("buffer") and l.has_method("expand_bounds")
	var units := l_units[li]
	units.resize(cap)
	l_units[li] = units
	if atlas != "" and using_real_crowd:
		var m := _standin_material(vid, atlas, l)
		if m:
			for c in l.get_children():
				if c is MultiMeshInstance3D:
					(c as MultiMeshInstance3D).material_override = m
	l.call("set_visible_count", l_count[li])


## Материал заместителя: материал вида толпы с атласом другой стороны
func _standin_material(vid: String, atlas: String, l: Node3D) -> Material:
	var key := vid + "|" + atlas
	if _standin_mats.has(key):
		return _standin_mats[key]
	var base: Material = null
	for c in l.get_children():
		if c is MultiMeshInstance3D:
			base = (c as MultiMeshInstance3D).material_override
			break
	if not base is ShaderMaterial or not ATLAS.has(atlas):
		return null
	var m := (base as ShaderMaterial).duplicate() as ShaderMaterial
	m.set_shader_parameter("atlas", load(ATLAS[atlas]))
	_standin_mats[key] = m
	return m


func _acquire(u: int, li: int) -> void:
	var l := l_node[li]
	var cap := int(l.get("capacity"))
	if l_count[li] >= cap:
		_grow_layer(li, maxi(cap * 2, START_CAP))
	var s := l_count[li]
	l_units[li][s] = u
	l_count[li] = s + 1
	slot_of[u] = s
	layer_of[u] = li
	_fresh[u] = 1
	l.call("set_visible_count", s + 1)


## Слой полон: пересоздать вдвое больше и записать все места заново в этом кадре
func _grow_layer(li: int, cap: int) -> void:
	_setup_layer(li, cap)
	var units := l_units[li]
	for s in l_count[li]:
		_fresh[units[s]] = 1
		_u_done[units[s]] = 0


## Освободить место: последний юнит слоя переезжает на место ушедшего (с данными экземпляра)
func _release(u: int) -> void:
	var li := layer_of[u]
	if li == -2:
		_remove_arba(u)
		layer_of[u] = -1
		return
	var s := slot_of[u]
	var l := l_node[li]
	var last := l_count[li] - 1
	var units := l_units[li]
	if s != last:
		var moved := units[last]
		units[s] = moved
		slot_of[moved] = s
		if _l_fast[li]:
			var buf: PackedFloat32Array = l.call("buffer")
			var a := s * 16
			var b := last * 16
			for k in 16:
				buf[a + k] = buf[b + k]
			l.call("expand_bounds", Vector3(buf[a + 3], buf[a + 7], buf[a + 11]), Vector3(buf[a + 3], buf[a + 7], buf[a + 11]))
		else:
			_fresh[moved] = 1
			_u_done[moved] = 0
	units[last] = -1
	l_count[li] = last
	l.call("set_visible_count", last)
	slot_of[u] = -1
	layer_of[u] = -1


## Проверка инвариантов мест (тесты): "" — всё верно, иначе описание первой ошибки
func check_slots() -> String:
	for li in l_node.size():
		var cnt := l_count[li]
		if int(l_node[li].call("get_visible_count")) != cnt:
			return "слой %s: видимых %d ≠ занятых %d" % [l_key[li], int(l_node[li].call("get_visible_count")), cnt]
		for s in cnt:
			var u := l_units[li][s]
			if u < 0 or u >= slot_of.size():
				return "слой %s место %d: юнит %d" % [l_key[li], s, u]
			if slot_of[u] != s or layer_of[u] != li:
				return "слой %s место %d: юнит %d думает, что он в %d/%d" % [l_key[li], s, u, layer_of[u], slot_of[u]]
	var n := _sim.n if _sim else 0
	for u in mini(n, slot_of.size()):
		var li := layer_of[u]
		var free := _sim.u_life[u] == FREE
		if free and li != -1:
			return "юнит %d свободен, но занимает место" % u
		if li >= 0 and (slot_of[u] >= l_count[li] or l_units[li][slot_of[u]] != u):
			return "юнит %d: место %d вне слоя %s" % [u, slot_of[u], l_key[li]]
	return ""


## Сколько мест занято во всех слоях (тесты)
func used_slots() -> int:
	var s := 0
	for c in l_count:
		s += c
	return s + _arba_units.size()


# ---------------------------------------------------------------- кадр

func _update_units() -> void:
	var sim := _sim
	var t := _b_time
	var a := scenario.alpha if scenario else 0.0
	var n := mini(slot_of.size(), _b_x.size())
	var done := _u_done
	var fresh := _fresh
	var lx := _lx
	var lz := _lz
	var px := _b_px
	var pz := _b_pz
	var ph := _b_ph
	var ux := _b_x
	var uz := _b_z
	var uh := _b_h
	var vxs := _b_vx
	var vzs := _b_vz
	var lifes := _b_life
	var acts := _b_act
	var works := sim.u_work
	var death_t := _b_death_t
	var gar := sim.u_garrison
	var st_top := sim.st_top
	var fallrot := _u_fallrot
	var skel := _u_skel
	var hg := _hgt
	var hn := _hn
	var hsp := _hsp
	var hox := _hox
	var hoz := _hoz
	var hmax := hn - 1.001
	var rx0 := _rect.position.x
	var rz0 := _rect.position.y
	var rx1 := _rect.end.x
	var rz1 := _rect.end.y
	var sink := sim.corpse_steps > 0
	var life_s := sim.corpse_steps * BattleSim.DT
	var phase4 := frame & 3
	var sacks := _sack_buf
	var ns := 0
	for li in l_node.size():
		var cnt := l_count[li]
		if cnt == 0:
			continue
		var sack_h := _l_sack[li]
		var l: Node3D = l_node[li]
		var units: PackedInt32Array = l_units[li]
		var fast := _l_fast[li]
		var buf: PackedFloat32Array = l.call("buffer") if fast else PackedFloat32Array()
		var x0 := INF
		var y0 := INF
		var z0 := INF
		var x1 := -INF
		var y1 := -INF
		var z1 := -INF
		for s in cnt:
			var u := units[s]
			if u >= n:
				continue
			var fr := fresh[u]
			if done[u] == 1 and fr == 0:
				continue
			var cx := ux[u]
			var cz := uz[u]
			if fr == 0 and (s & 3) != phase4 and (cx < rx0 or cx > rx1 or cz < rz0 or cz > rz1):
				continue
			fresh[u] = 0
			var life := lifes[u]
			var x := lerpf(px[u], cx, a)
			var z := lerpf(pz[u], cz, a)
			var h := lerp_angle(ph[u], uh[u], a)
			if life != ALIVE:
				var k := 1.0 if life == DEAD else clampf((t - death_t[u]) / 0.8, 0.0, 1.0)
				h += fallrot[u] * k
			var mx := x - lx[u]
			var mz := z - lz[u]
			var moved := sqrt(mx * mx + mz * mz)
			lx[u] = x
			lz[u] = z
			var vx := vxs[u]
			var vz := vzs[u]
			var spd := sqrt(vx * vx + vz * vz)
			var c: Color
			if life == ALIVE and acts[u] == ACT_WORK and skel[u] == 0 and works[u] >= 0.0:
				c = _work_c(u, t, spd, moved, works[u])
			else:
				c = _human_c(u, t, spd, moved) if skel[u] == 0 else _rider_c(u, t, spd, moved)
			var y := 0.0
			if hn > 1:
				var fx := clampf((x - hox) / hsp, 0.0, hmax)
				var fz := clampf((z - hoz) / hsp, 0.0, hmax)
				var i := int(fx)
				var j := int(fz)
				var kk := j * hn + i
				var fu := fx - i
				y = lerpf(lerpf(hg[kk], hg[kk + 1], fu), lerpf(hg[kk + hn], hg[kk + hn + 1], fu), fz - j)
			if life == DEAD and sink:
				var left := life_s - (t - death_t[u])
				if left < SINK_S:
					y -= SINK_DEPTH * clampf(1.0 - left / SINK_S, 0.0, 1.0)
			elif life == ALIVE and gar[u] >= 0 and gar[u] < st_top.size():
				y += st_top[gar[u]]
			if sack_h > 0.0 and life == ALIVE and acts[u] == ACT_WORK and works[u] >= 0.625:
				# мешок за спиной (вперёд модели — +Z: (sin h, cos h))
				if sacks.size() < (ns + 1) * 12:
					sacks.resize(maxi(sacks.size() * 2, 64 * 12))
				var o2 := ns * 12
				var c2 := cos(h)
				var s2 := sin(h)
				sacks[o2] = c2
				sacks[o2 + 1] = 0.0
				sacks[o2 + 2] = s2
				sacks[o2 + 3] = x - s2 * SACK_BACK
				sacks[o2 + 4] = 0.0
				sacks[o2 + 5] = 1.0
				sacks[o2 + 6] = 0.0
				sacks[o2 + 7] = y + sack_h
				sacks[o2 + 8] = -s2
				sacks[o2 + 9] = 0.0
				sacks[o2 + 10] = c2
				sacks[o2 + 11] = z - c2 * SACK_BACK
				ns += 1
			if fast:
				var o := s * 16
				var cs := cos(h)
				var sn := sin(h)
				buf[o] = cs
				buf[o + 1] = 0.0
				buf[o + 2] = sn
				buf[o + 3] = x
				buf[o + 4] = 0.0
				buf[o + 5] = 1.0
				buf[o + 6] = 0.0
				buf[o + 7] = y
				buf[o + 8] = -sn
				buf[o + 9] = 0.0
				buf[o + 10] = cs
				buf[o + 11] = z
				buf[o + 12] = c.r
				buf[o + 13] = c.g
				buf[o + 14] = c.b
				buf[o + 15] = c.a
				x0 = minf(x0, x)
				x1 = maxf(x1, x)
				y0 = minf(y0, y)
				y1 = maxf(y1, y)
				z0 = minf(z0, z)
				z1 = maxf(z1, z)
			else:
				l.call("set_instance", s, Transform3D(Basis(Vector3.UP, h), Vector3(x, y, z)), c)
			if life == DEAD and not sink:
				done[u] = 1
		if fast and x0 <= x1:
			l.call("expand_bounds", Vector3(x0, y0, z0), Vector3(x1, y1, z1))
	_sack_buf = sacks
	_draw_sacks(ns)


## Мешки несущих: буфер MultiMesh на ns экземпляров (ёмкость растёт вдвое)
func _draw_sacks(ns: int) -> void:
	sacks_drawn = ns
	if _sacks == null:
		if ns == 0:
			return
		_sacks = MultiMeshInstance3D.new()
		_sacks.name = "Sacks"
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = sack_mesh()
		_sacks.multimesh = mm
		_sacks.material_override = BuildingLook.kit_material()
		# мешки разбросаны по всему городу: границы — вся карта
		_sacks.custom_aabb = AABB(Vector3(-1.0e4, -1.0e3, -1.0e4), Vector3(2.0e4, 2.0e3, 2.0e4))
		add_child(_sacks)
	var mm := _sacks.multimesh
	var cap := _sack_buf.size() / 12
	if mm.instance_count != cap:
		mm.instance_count = cap
	if cap > 0:
		mm.buffer = _sack_buf
	mm.visible_instance_count = ns


## Мешок: мешковина, перевязанная сверху (набор заместителей построек — тот же материал)
static func sack_mesh() -> ArrayMesh:
	var k := BuildingLook.Kit.new()
	var tint := Color(0.86, 0.74, 0.56)
	k.cyl(Vector3(0, -0.28, 0), 0.19, 0.22, 0.4, 8, "hay", tint)
	k.cyl(Vector3(0, 0.12, 0), 0.22, 0.08, 0.14, 8, "hay", Color(0.79, 0.68, 0.52))
	k.cyl(Vector3(0, 0.25, 0), 0.07, 0.1, 0.08, 6, "rope", Color(0.8, 0.7, 0.55))
	return k.commit()


## Работа (Act.WORK): рубит/копает/строит — цикл по времени; несёт — шаг по пройденному пути.
## Идёт к работе с инструментом (не CARRY) — обычный шаг.
func _work_c(u: int, t: float, spd: float, moved: float, aux: float) -> Color:
	var w := _b_var[u]
	if aux >= 0.625:
		if spd > 0.05:
			_phase[u] = fposmod(_phase[u] + moved / SH_WALK, 1.0)
		return Color(float(H.WORK), _phase[u], aux, w)
	if spd > 0.05:
		return _human_c(u, t, spd, moved)
	var period := WORK_CHOP_S if aux < 0.125 else (WORK_DIG_S if aux < 0.375 else WORK_BUILD_S)
	return Color(float(H.WORK), fposmod(t / period + w * 3.7, 1.0), aux, w)


## То же для проверок без кадра (tests/test_unit_view.gd): данные экземпляра юнита u
func custom_for(u: int, t: float, spd: float, moved: float) -> Color:
	if _b_owner != _sim:
		_bind_sim(_sim)
	if _b_life[u] == ALIVE and _b_act[u] == ACT_WORK and _u_skel[u] == 0 and _sim.u_work[u] >= 0.0:
		return _work_c(u, t, spd, moved, _sim.u_work[u])
	return _human_c(u, t, spd, moved) if _u_skel[u] == 0 else _rider_c(u, t, spd, moved)


# ---------------------------------------------------------------- арбы

func _add_arba(u: int) -> void:
	var node: Node3D = null
	if ResourceLoader.exists(ARBA_MODEL):
		node = BuildingLook.instance_model(ARBA_MODEL, 120.0)
	if node == null:
		node = BuildingLook.box(Vector3(2.2, 1.6, 3.6), Color(0.45, 0.33, 0.22))
	node.name = "Arba_%d" % u
	_arba_root.add_child(node)
	slot_of[u] = _arbas.size()
	layer_of[u] = -2
	_arbas.append(node)
	_arba_units.append(u)


func _remove_arba(u: int) -> void:
	var s := slot_of[u]
	var last := _arbas.size() - 1
	_arbas[s].queue_free()
	if s != last:
		_arbas[s] = _arbas[last]
		_arba_units[s] = _arba_units[last]
		slot_of[_arba_units[s]] = s
	_arbas.resize(last)
	_arba_units.resize(last)
	slot_of[u] = -1


func _update_arbas() -> void:
	if _arbas.is_empty():
		return
	var a := scenario.alpha if scenario else 0.0
	var px := _b_px
	var pz := _b_pz
	var ph := _b_ph
	var ux := _b_x
	var uz := _b_z
	var uh := _b_h
	for i in _arbas.size():
		var u := _arba_units[i]
		var x := lerpf(px[u], ux[u], a)
		var z := lerpf(pz[u], uz[u], a)
		_arbas[i].transform = Transform3D(Basis(Vector3.UP, lerp_angle(ph[u], uh[u], a)), Vector3(x, Terrain.height_at(x, z), z))
		_arbas[i].visible = _b_life[u] == ALIVE
