class_name CrowdLayer
extends Node3D
## Слой толпы: один вид юнита, анимация целиком на видеокарте (CONTRACT §7, ТЗ 11.5).
##
## LOD — по каждому юниту, а не по всему слою: ближе lod_distance — подробная модель (LOD0),
## дальше — облегчённая (LOD1). Тени отбрасывают только юниты ближе дальности теней толпы
## (WorldQuality «crowd_shadow»: на «Высоком» — первые два каскада солнца, 126 м) и только в тех
## каскадах, что эту дальность покрывают: в дальних каскадах (они охватывают и ближнее поле)
## юниты не рисуются — порог полуширины прохода (shadow_pass_limit) уходит в шейдер, crowd_lod.w.
## Тень подробной моделью — только в первом каскаде солнца (near_shadow_distance, на «Высоком» ≈ 52 м):
## дальше точка карты теней (≈ 13 см во втором каскаде) крупнее разницы моделей, и тень юнита
## рисует облегчённая модель — в проходах теней треугольников вдвое меньше.
## Ключи сравнения: --crowd_cascades=all — юниты во всех каскадах и тень LOD0 у всех подробных, как было
## (none — без теней юнитов, проверка); --crowd_shadow=700 — дальность теней юнитов, м (уровень — 126 / 90 / 60).
## Четыре MultiMeshInstance3D (Part): LOD0 с тенью (ближе первого каскада), LOD0 без тени, LOD1 без тени
## и «Тень» — облегчённая модель только в проходах теней. Буфер экземпляров делится на
## блоки по BLOCK мест; каждый кадр блок по своим границам и камере уходит в те MultiMesh,
## чьей полосе дальности он может принадлежать (на границе — в оба). Точный выбор по юниту —
## в шейдере (shaders/crowd.gdshader, crowd_lod): лишние там сжимаются в точку до расчёта позы,
## так же — юниты вне кадра (и вне каскада тени) и дальние в проходе теней.
## Данные экземпляров копятся в одном буфере и уходят на видеокарту раз за кадр.
##
##   var layer := CrowdLayer.new()
##   add_child(layer)
##   layer.setup("kok_sarboz", 200)
##   var dir := Vector3(0, 0, 1)                     # куда смотрит юнит
##   var xf := Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), Vector3(x, Terrain.height_at(x, z), z))
##   layer.set_instance(i, xf, AnimSpec.custom(AnimSpec.Human.WALK, fposmod(dist / 1.5, 1.0), 1.0, w))
##   layer.set_visible_count(n)                       # видны экземпляры 0..n-1
##
## Модель смотрит в +Z, начало координат — ступни на земле.
## Слой должен быть в дереве сцены: буфер уходит на видеокарту перед отрисовкой кадра
## (RenderingServer.frame_pre_draw). Фазы и события анимаций — CrowdAnim, данные — AnimSpec.
## Невидимые хвосты (i ≥ видимого числа) не рисуются; границы для отсечения и LOD считаются сами.

const SHADER := preload("res://shaders/crowd.gdshader")
const STRIDE := 16  # 12 чисел трансформа + 4 числа INSTANCE_CUSTOM
## Мест в блоке (места одного отряда идут подряд — блок компактен на поле)
const BLOCK := 32
## Границы всех блоков пересчитываются точно за столько отправок (каждый кадр — своя доля)
const SCAN_FRAMES := 8
## Запас границ блока на движение юнитов с его пересчёта, м/с (галоп с натиском — до 12)
const DRIFT_SPEED := 15.0
const FAR := 1.0e9
## Группа солнца мира (World кладёт в неё свой DirectionalLight3D): по нему — каскады теней
const SUN_GROUP := &"ordo_sun"
## Тень подробной моделью — до конца первого каскада солнца и ещё столько, м (юниты у края кадра,
## тени к камере)
const NEAR_SHADOW_PAD := 10.0
## Части слоя: подробная модель с тенью (ближе near_shadow_distance), подробная без тени,
## облегчённая без тени, тень облегчённой моделью (только проходы теней)
enum Part { LOD0_NEAR, LOD0, LOD1, SHADOW }
const PARTS := 4

## Дальность смены LOD0 → LOD1, м
var lod_distance: float = 90.0:
	set(value):
		lod_distance = value
		_apply_lod()

var unit_id := ""
var capacity := 0

var _mm: Array[MultiMesh] = []
var _mmi: Array[MultiMeshInstance3D] = []
var _buf := PackedFloat32Array()
var _visible := 0
var _dirty := false
var _lod_d := 90.0          # дальность LOD с учётом уровня качества
var _shadow_d := 126.0      # дальше юниты теней не отбрасывают
var _far_shadow := true     # облегчённые юниты отбрасывают тень («Низкое» — нет)
var _casc_limit := 0.0      # порог полуширины прохода теней (0 — во всех каскадах), см. shadow_pass_limit
var _near_d := 90.0         # ближе — тень подробной моделью (первый каскад), дальше — облегчённой
var _casc_mode := ""        # ключ --crowd_cascades: "" — по каскадам, all — во всех, none — ни в одном
# границы блоков (ступни юнитов), сколько «пути» набежало к их пересчёту
var _blo := PackedVector3Array()
var _bhi := PackedVector3Array()
var _bdrift := PackedFloat32Array()
var _drift := 0.0
var _drift_t := -1.0
var _scan := 0
var _full_scan := true
var _cam := Vector3(INF, INF, INF)  # камера последнего деления
var _counts := PackedInt32Array([0, 0, 0, 0])

## Запас границ: копья, знамёна, лежащие тела выходят за ступни
const AABB_PAD_LO := Vector3(3.0, 1.0, 3.0)
const AABB_PAD_HI := Vector3(3.0, 5.0, 3.0)

static var _mesh_cache := {}
static var _material_cache := {}


## Создаёт MultiMeshInstance3D слоя с материалом толпы. Можно звать повторно (пересоздаёт).
func setup(p_unit_id: String, p_capacity: int) -> void:
	_clear()
	unit_id = p_unit_id
	capacity = maxi(p_capacity, 0)
	var u := UnitRegistry.info(unit_id)
	if u.is_empty():
		return
	_buf.resize(capacity * STRIDE)
	_buf.fill(0.0)
	for i in capacity:
		# единичный базис, чтобы невидимые экземпляры не были вырожденными
		_buf[i * STRIDE] = 1.0
		_buf[i * STRIDE + 5] = 1.0
		_buf[i * STRIDE + 10] = 1.0
	var names := ["LOD0", "LOD0_NoShadow", "LOD1", "Shadow"]
	for part in PARTS:
		var data := _load(UnitRegistry.mesh_path(unit_id, 0 if part <= Part.LOD0 else 1))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = data["mesh"]
		mm.instance_count = capacity
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = names[part]
		mmi.multimesh = mm
		mmi.material_override = _material(unit_id, data["texture"])
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mmi)
		_mm.append(mm)
		_mmi.append(mmi)
	_counts = PackedInt32Array([0, 0, 0, 0])
	_full_scan = true
	_apply_lod()
	_dirty = true


## Трансформ экземпляра в мире (базис — поворот по ходу юнита, начало — ступни на земле)
## и данные анимации (AnimSpec.custom).
func set_instance(i: int, xform: Transform3D, custom: Color) -> void:
	if i < 0 or i >= capacity:
		return
	var o := i * STRIDE
	var b := xform.basis
	_buf[o] = b.x.x
	_buf[o + 1] = b.y.x
	_buf[o + 2] = b.z.x
	_buf[o + 3] = xform.origin.x
	_buf[o + 4] = b.x.y
	_buf[o + 5] = b.y.y
	_buf[o + 6] = b.z.y
	_buf[o + 7] = xform.origin.y
	_buf[o + 8] = b.x.z
	_buf[o + 9] = b.y.z
	_buf[o + 10] = b.z.z
	_buf[o + 11] = xform.origin.z
	var k := i / BLOCK
	if i < _visible and k < _blo.size():
		_blo[k] = _blo[k].min(xform.origin)
		_bhi[k] = _bhi[k].max(xform.origin)
	_buf[o + 12] = custom.r
	_buf[o + 13] = custom.g
	_buf[o + 14] = custom.b
	_buf[o + 15] = custom.a
	_dirty = true


## Только данные анимации (трансформ не меняется)
func set_custom(i: int, custom: Color) -> void:
	if i < 0 or i >= capacity:
		return
	var o := i * STRIDE + 12
	_buf[o] = custom.r
	_buf[o + 1] = custom.g
	_buf[o + 2] = custom.b
	_buf[o + 3] = custom.a
	_dirty = true


## Сколько экземпляров видно (0..n-1)
func set_visible_count(n: int) -> void:
	_visible = clampi(n, 0, capacity)
	_full_scan = true  # границы блоков пересчитать целиком при следующей отправке
	_dirty = true


func get_visible_count() -> int:
	return _visible


## Сколько юнитов слоя в последнем кадре ушло в подробную модель, в облегчённую и в тень
## (по блокам: юнит на границе полос может быть в двух частях — шейдер оставит одну)
func lod_counts() -> PackedInt32Array:
	return PackedInt32Array([_counts[Part.LOD0_NEAR] + _counts[Part.LOD0], _counts[Part.LOD1],
		_counts[Part.LOD0_NEAR] + _counts[Part.SHADOW]])


## Дальность тени подробной моделью (первый каскад солнца), м
func near_shadow_distance() -> float:
	return _near_d


## Самый быстрый путь (бой на тысячи юнитов): сам буфер слоя, по 16 чисел на экземпляр —
## 12 чисел трансформа (строки 3×4: базис и начало) и 4 числа INSTANCE_CUSTOM. Пишите в него
## напрямую (это тот же массив, не копия), затем expand_bounds() по записанным точкам —
## слой отметит буфер к отправке. Брать заново каждый кадр: setup() буфер пересоздаёт.
func buffer() -> PackedFloat32Array:
	return _buf


## Границы записанных напрямую экземпляров (ступни): буфер уйдёт на видеокарту перед кадром.
## Границы блоков слой пересчитывает сам (по частям, с запасом на движение юнитов).
func expand_bounds(_lo: Vector3, _hi: Vector3) -> void:
	_dirty = true


## Быстрый путь: весь буфер сразу (по 16 чисел на экземпляр, как в MultiMesh.buffer
## с TRANSFORM_3D и custom data). Длина — capacity * 16.
func set_raw_buffer(data: PackedFloat32Array) -> void:
	if data.size() != _buf.size():
		push_error("CrowdLayer.set_raw_buffer: нужно %d чисел" % _buf.size())
		return
	_buf = data
	_full_scan = true
	_dirty = true


func _enter_tree() -> void:
	if not RenderingServer.frame_pre_draw.is_connected(_flush):
		RenderingServer.frame_pre_draw.connect(_flush)
	# качество можно переключить во время игры (ТЗ 11.7, F2 в срезе)
	var ordo := get_tree().root.get_node_or_null("Ordo")
	if ordo and ordo.has_signal("quality_changed") and not ordo.is_connected("quality_changed", _on_quality):
		ordo.connect("quality_changed", _on_quality)
	_apply_lod()


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_flush):
		RenderingServer.frame_pre_draw.disconnect(_flush)
	var ordo := get_tree().root.get_node_or_null("Ordo")
	if ordo and ordo.is_connected("quality_changed", _on_quality):
		ordo.disconnect("quality_changed", _on_quality)


func _on_quality(_level: String) -> void:
	_apply_lod()


## Буфер уходит на видеокарту один раз перед отрисовкой кадра (и при сдвиге камеры —
## деление на LOD зависит от неё)
func _flush() -> void:
	if _mm.is_empty():
		return
	# каскады зависят от угла камеры, кадра и солнца — пересчёт дёшев, меняется редко
	var sc := _shadow_cfg(_camera())
	if absf(sc.x - _casc_limit) > 0.01 * maxf(sc.x, _casc_limit) or absf(sc.y - _near_d) > 0.05:
		_casc_limit = sc.x
		_near_d = sc.y
		_set_bands()
		_cam = Vector3(INF, INF, INF)  # полосы частей сдвинулись — поделить заново
	var cam := _camera_pos()
	if not _dirty and cam.distance_squared_to(_cam) < 0.25:
		return
	if _dirty:
		# сколько юниты могли пройти с прошлой отправки (для запаса границ блоков)
		var now := Time.get_ticks_usec() * 1.0e-6
		if _drift_t >= 0.0:
			_drift += minf(now - _drift_t, 0.25) * DRIFT_SPEED
		_drift_t = now
		_scan_blocks()
	_dirty = false
	_cam = cam
	_partition(cam)


## Точные границы части блоков (за SCAN_FRAMES отправок — всех); после set_visible_count — всех сразу
func _scan_blocks() -> void:
	var nb := (_visible + BLOCK - 1) / BLOCK
	if _blo.size() != nb:
		_blo.resize(nb)
		_bhi.resize(nb)
		_bdrift.resize(nb)
		_full_scan = true
	if nb == 0:
		return
	var count := nb if _full_scan else mini(nb, (nb + SCAN_FRAMES - 1) / SCAN_FRAMES)
	var start := 0 if _full_scan else _scan
	_full_scan = false
	var buf := _buf
	for k in count:
		var b := (start + k) % nb
		var i0 := b * BLOCK
		var i1 := mini(i0 + BLOCK, _visible)
		var x0 := INF
		var y0 := INF
		var z0 := INF
		var x1 := -INF
		var y1 := -INF
		var z1 := -INF
		for i in range(i0, i1):
			var o := i * STRIDE
			var x := buf[o + 3]
			var y := buf[o + 7]
			var z := buf[o + 11]
			x0 = minf(x0, x)
			x1 = maxf(x1, x)
			y0 = minf(y0, y)
			y1 = maxf(y1, y)
			z0 = minf(z0, z)
			z1 = maxf(z1, z)
		_blo[b] = Vector3(x0, y0, z0)
		_bhi[b] = Vector3(x1, y1, z1)
		_bdrift[b] = _drift
	_scan = (start + count) % nb


## Деление блоков по LOD: блок идёт в каждую часть, в полосу дальности которой может попасть
## хоть один его юнит; подряд идущие блоки одной части копируются одним куском
func _partition(cam: Vector3) -> void:
	var nb := mini((_visible + BLOCK - 1) / BLOCK, _blo.size())
	# дальность до блока: ближайшая и самая дальняя точка его границ (с запасом на движение)
	var dmin := PackedFloat32Array()
	var dmax := PackedFloat32Array()
	var blo := PackedVector3Array()
	var bhi := PackedVector3Array()
	dmin.resize(nb)
	dmax.resize(nb)
	blo.resize(nb)
	bhi.resize(nb)
	for b in nb:
		var pad := 0.5 + (_drift - _bdrift[b])
		var lo := _blo[b] - Vector3(pad, pad, pad)
		var hi := _bhi[b] + Vector3(pad, pad, pad)
		blo[b] = lo
		bhi[b] = hi
		dmin[b] = cam.distance_to(cam.clamp(lo, hi))
		dmax[b] = cam.distance_to(Vector3(lo.x if cam.x > (lo.x + hi.x) * 0.5 else hi.x,
			lo.y if cam.y > (lo.y + hi.y) * 0.5 else hi.y, lo.z if cam.z > (lo.z + hi.z) * 0.5 else hi.z))
	var send := _shadow_end()
	for part in PARTS:
		var out := PackedFloat32Array()
		var run0 := -1
		var run1 := -1
		var runs := 0
		var n := 0
		var lo3 := Vector3(INF, INF, INF)
		var hi3 := -Vector3(INF, INF, INF)
		for b in nb:
			# блок в части, если его полоса дальности [dmin, dmax] задевает полосу части
			var take := false
			match part:
				Part.LOD0_NEAR:
					take = dmin[b] < _near_d
				Part.LOD0:
					take = dmax[b] >= _near_d and dmin[b] < _lod_d
				Part.LOD1:
					take = dmax[b] >= _lod_d
				_:
					take = dmax[b] >= _near_d and dmin[b] < send
			if not take:
				continue
			var i0 := b * BLOCK
			var i1 := mini(i0 + BLOCK, _visible)
			n += i1 - i0
			lo3 = lo3.min(blo[b])
			hi3 = hi3.max(bhi[b])
			if run1 == i0:
				run1 = i1
				continue
			if run0 >= 0:
				out.append_array(_buf.slice(run0 * STRIDE, run1 * STRIDE))
			run0 = i0
			run1 = i1
			runs += 1
		# на видеокарту: весь слой в одной части — сам буфер без копии, иначе собранные куски
		var mm := _mm[part]
		if n == 0:
			if _counts[part] != 0:
				mm.visible_instance_count = 0
			_counts[part] = 0
			continue
		if runs == 1 and run0 == 0 and run1 == _visible:
			RenderingServer.multimesh_set_buffer(mm.get_rid(), _buf)
		else:
			out.append_array(_buf.slice(run0 * STRIDE, run1 * STRIDE))
			out.resize(capacity * STRIDE)
			RenderingServer.multimesh_set_buffer(mm.get_rid(), out)
		if _counts[part] != n:
			mm.visible_instance_count = n
		_counts[part] = n
		var a := lo3 - AABB_PAD_LO
		mm.custom_aabb = AABB(a, (hi3 + AABB_PAD_HI) - a)


## Камера, что рисует кадр слоя (или null)
func _camera() -> Camera3D:
	var vp := get_viewport() if is_inside_tree() else null
	return vp.get_camera_3d() if vp else null


## Камера, для которой делим на LOD (та же, что рисует кадр); без камеры — точка над серединой карты
func _camera_pos() -> Vector3:
	var cam := _camera()
	return cam.global_position if cam else Vector3(0.0, 60.0, 0.0)


func _apply_lod() -> void:
	if _mmi.size() < PARTS:
		return
	# уровень качества (WorldQuality): «Высокое» — LOD 90 м, тени юнитов до 126 м; «Среднее» —
	# ×0,75 и тени до 90 м; «Низкое» — ×0,5, тени до 60 м и облегчённые юниты без теней
	var p := WorldQuality.preset(_quality())
	_lod_d = lod_distance * float(p.get("crowd_lod", 1.0))
	_shadow_d = float(p.get("crowd_shadow", 126.0))
	_far_shadow = bool(p.get("crowd_lod1_shadow", true))
	var ordo := get_tree().root.get_node_or_null("Ordo") if is_inside_tree() else null
	if ordo and ordo.has_method("arg"):
		_casc_mode = String(ordo.call("arg", "crowd_cascades", ""))
		# --crowd_shadow=700 — дальность теней юнитов, м (сравнение: все юниты с тенью, как было)
		_shadow_d = float(ordo.call("arg", "crowd_shadow", str(_shadow_d)))
	var sc := _shadow_cfg(_camera())
	_casc_limit = sc.x
	_near_d = sc.y
	_set_bands()
	_cam = Vector3(INF, INF, INF)  # поделить заново
	_dirty = true


## Конец теней юнитов, м: дальность теней толпы («Низкое» — облегчённые без тени: не дальше LOD0)
func _shadow_end() -> float:
	return _shadow_d if _far_shadow else minf(_shadow_d, _lod_d)


## Полосы частей в шейдер (crowd_lod: от, до, дальность теней, порог каскадов) и тени частей:
## LOD0 ближе _near_d — с тенью подробной моделью; LOD0 дальше и LOD1 — без тени;
## «Тень» — облегчённая модель от _near_d до конца теней, только в проходах теней
func _set_bands() -> void:
	if _mmi.size() < PARTS:
		return
	var send := _shadow_end()
	var bands := [Vector4(0.0, _near_d, _near_d, _casc_limit), Vector4(_near_d, _lod_d, 0.0, 0.0),
		Vector4(_lod_d, FAR, 0.0, 0.0), Vector4(_near_d, send, send, _casc_limit)]
	var modes := [GeometryInstance3D.SHADOW_CASTING_SETTING_ON, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY]
	for part in PARTS:
		var mmi := _mmi[part]
		mmi.visibility_range_begin = 0.0
		mmi.visibility_range_end = 0.0
		mmi.set_instance_shader_parameter("crowd_lod", bands[part])
		mmi.cast_shadow = modes[part]


## Каскады для камеры cam и солнца мира (группа SUN_GROUP, World): x — порог полуширины прохода
## теней (0 — без порога), y — дальность тени подробной моделью (_near_d: конец первого каскада
## + NEAR_SHADOW_PAD, не дальше LOD0 и конца теней). Нет солнца с тенью или камера не перспективная —
## без порога, тень подробной моделью у всех LOD0 (как без деления по каскадам).
func _shadow_cfg(cam: Camera3D) -> Vector2:
	var whole := minf(_lod_d, _shadow_end())
	if _casc_mode == "none":
		return Vector2(0.001, whole)
	if _casc_mode == "all" or cam == null or cam.projection != Camera3D.PROJECTION_PERSPECTIVE or not is_inside_tree():
		return Vector2(0.0, whole)
	var sun := get_tree().get_first_node_in_group(SUN_GROUP) as DirectionalLight3D
	if sun == null or not sun.shadow_enabled:
		return Vector2(0.0, whole)
	var count := 1
	match sun.directional_shadow_mode:
		DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS:
			count = 2
		DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS:
			count = 4
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var t := tan(deg_to_rad(cam.fov) * 0.5)
	var by_height := cam.keep_aspect == Camera3D.KEEP_HEIGHT
	var dist := cascade_distances(cam.near, cam.far, sun.directional_shadow_max_distance, count,
		[sun.directional_shadow_split_1, sun.directional_shadow_split_2, sun.directional_shadow_split_3])
	var radii := cascade_radii(t * aspect if by_height else t, t if by_height else t / aspect, dist,
		sun.directional_shadow_blend_splits)
	var near := minf(dist[1] + NEAR_SHADOW_PAD, whole) if count > 1 else whole
	return Vector2(shadow_pass_limit(radii, dist, _shadow_d), near)


## Дальности каскадов тени солнца, м (как у движка, RendererSceneCull): d[0] — ближняя плоскость
## камеры, d[i] — доля splits[i − 1] дальности теней, последняя — сама дальность теней (не дальше камеры)
static func cascade_distances(near: float, far: float, max_dist: float, count: int, splits: Array) -> PackedFloat32Array:
	var max_d := minf(far, max_dist)
	var min_d := minf(near, max_d)
	var out := PackedFloat32Array([min_d])
	for i in count:
		out.append(min_d + float(splits[i]) * (max_d - min_d) if i < count - 1 else max_d)
	return out


## Полуширина каскадов, м: каскад i — шар вокруг куска пирамиды камеры от d[i] (со смешиванием
## каскадов — от d[i − 1]) до d[i + 1], как у движка; tan_x, tan_y — тангенсы половин углов камеры
static func cascade_radii(tan_x: float, tan_y: float, dist: PackedFloat32Array, blend: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var t2 := tan_x * tan_x + tan_y * tan_y
	for i in dist.size() - 1:
		var a := dist[i - 1 if i > 0 and blend else i]
		var b := dist[i + 1]
		out.append(sqrt(0.25 * (b - a) * (b - a) + b * b * t2))
	return out


## Порог полуширины прохода теней для толпы: юниты ближе shadow_d нужны только в каскадах до
## первого, чья дальность ≥ shadow_d. Порог — между его полушириной и полушириной следующего
## (среднее геометрическое: каскады растут в 2–3 раза, запас в обе стороны ×1,4 и больше).
## 0 — без порога (дальность теней толпы покрывает только последний каскад).
static func shadow_pass_limit(radii: PackedFloat32Array, dist: PackedFloat32Array, shadow_d: float) -> float:
	for k in range(1, dist.size() - 1):
		if dist[k] >= shadow_d - 1.0:
			return sqrt(radii[k - 1] * radii[k])
	return 0.0


func _quality() -> String:
	if not is_inside_tree():
		return "high"
	var ordo := get_tree().root.get_node_or_null("Ordo")
	return String(ordo.get("quality")) if ordo != null and ordo.get("quality") != null else "high"


func _clear() -> void:
	for mmi in _mmi:
		mmi.queue_free()
	_mmi.clear()
	_mm.clear()
	_blo.clear()
	_bhi.clear()
	_bdrift.clear()


## Меш и атлас из glb (кэш на все слои)
static func _load(path: String) -> Dictionary:
	if _mesh_cache.has(path):
		return _mesh_cache[path]
	var out := {"mesh": null, "texture": null}
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("CrowdLayer: нет модели %s" % path)
		return out
	var root := scene.instantiate()
	var mis := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		mis.insert(0, root)
	if not mis.is_empty():
		var mi := mis[0] as MeshInstance3D
		out["mesh"] = mi.mesh
		var mat := mi.get_active_material(0)
		if mat is BaseMaterial3D:
			out["texture"] = (mat as BaseMaterial3D).albedo_texture
	root.free()
	_mesh_cache[path] = out
	return out


## Общий материал вида юнита (один на все части и на все слои этого вида)
static func _material(id: String, tex: Texture2D) -> ShaderMaterial:
	if _material_cache.has(id):
		return _material_cache[id]
	var u := UnitRegistry.info(id)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("skeleton", UnitRegistry.SKELETON_ID.get(u.get("skeleton", "human"), 0))
	m.set_shader_parameter("weapon_kind", UnitRegistry.WEAPON_ID.get(u.get("weapon", "none"), 6))
	m.set_shader_parameter("item_kind", UnitRegistry.ITEM_ID.get(u.get("item", "none"), 0))
	m.set_shader_parameter("has_banner", u.get("banner", false))
	if tex:
		m.set_shader_parameter("atlas", tex)
	m.set_shader_parameter("unit_scale", u.get("scale", 1.0))
	if u.get("skeleton", "") in ["sheep", "horse"]:
		m.set_shader_parameter("jitter", 0.4)
	_material_cache[id] = m
	return m
