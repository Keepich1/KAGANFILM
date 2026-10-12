class_name CrowdLayer
extends Node3D
## Слой толпы: один вид юнита, анимация целиком на видеокарте (CONTRACT §7, ТЗ 11.5).
##
## Два MultiMeshInstance3D — LOD0 вблизи и LOD1 вдали (visibility range по lod_distance).
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

const SHADER := preload("res://shaders/crowd.gdshader")
const STRIDE := 16  # 12 чисел трансформа + 4 числа INSTANCE_CUSTOM

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
var _lo := Vector3(INF, INF, INF)   # границы видимых экземпляров (для отсечения и выбора LOD)
var _hi := Vector3(-INF, -INF, -INF)
var _flushes := 0

## Запас границ: копья, знамёна, лежащие тела выходят за ступни
const AABB_PAD_LO := Vector3(3.0, 1.0, 3.0)
const AABB_PAD_HI := Vector3(3.0, 5.0, 3.0)

static var _mesh_cache := {}
static var _material_cache := {}


## Создаёт оба MultiMeshInstance3D с материалом толпы. Можно звать повторно (пересоздаёт).
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
	for lod in 2:
		var data := _load(UnitRegistry.mesh_path(unit_id, lod))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = data["mesh"]
		mm.instance_count = capacity
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "LOD%d" % lod
		mmi.multimesh = mm
		mmi.material_override = _material(unit_id, data["texture"])
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mmi)
		_mm.append(mm)
		_mmi.append(mmi)
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
	if i < _visible:
		_lo = _lo.min(xform.origin)
		_hi = _hi.max(xform.origin)
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
	for mm in _mm:
		mm.visible_instance_count = _visible
	_flushes = 0  # границы пересчитать при следующей отправке
	_dirty = true


func get_visible_count() -> int:
	return _visible


## Быстрый путь: весь буфер сразу (по 16 чисел на экземпляр, как в MultiMesh.buffer
## с TRANSFORM_3D и custom data). Длина — capacity * 16.
func set_raw_buffer(data: PackedFloat32Array) -> void:
	if data.size() != _buf.size():
		push_error("CrowdLayer.set_raw_buffer: нужно %d чисел" % _buf.size())
		return
	_buf = data
	_flushes = 0
	_dirty = true


func _enter_tree() -> void:
	if not RenderingServer.frame_pre_draw.is_connected(_flush):
		RenderingServer.frame_pre_draw.connect(_flush)
	_apply_lod()


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_flush):
		RenderingServer.frame_pre_draw.disconnect(_flush)


## Буфер уходит на видеокарту один раз перед отрисовкой кадра
func _flush() -> void:
	if not _dirty or _mm.is_empty():
		return
	_dirty = false
	# границы: точный пересчёт по видимым экземплярам раз в 15 отправок, между ними — расширение
	if _flushes % 15 == 0:
		_recompute_bounds()
	_flushes += 1
	var box := AABB()
	if _visible > 0 and _lo.x <= _hi.x:
		box = AABB(_lo - AABB_PAD_LO, (_hi - _lo) + AABB_PAD_LO + AABB_PAD_HI)
	for mm in _mm:
		RenderingServer.multimesh_set_buffer(mm.get_rid(), _buf)
		mm.custom_aabb = box


func _recompute_bounds() -> void:
	_lo = Vector3(INF, INF, INF)
	_hi = Vector3(-INF, -INF, -INF)
	for i in _visible:
		var o := i * STRIDE
		var p := Vector3(_buf[o + 3], _buf[o + 7], _buf[o + 11])
		_lo = _lo.min(p)
		_hi = _hi.max(p)


func _apply_lod() -> void:
	if _mmi.size() < 2:
		return
	var low := _is_low()
	var d := lod_distance * (0.5 if low else 1.0)
	_mmi[0].visibility_range_end = d
	_mmi[0].visibility_range_end_margin = 3.0
	_mmi[1].visibility_range_begin = d
	_mmi[1].visibility_range_begin_margin = 3.0
	_mmi[1].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if low else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _is_low() -> bool:
	if not is_inside_tree():
		return false
	var ordo := get_tree().root.get_node_or_null("Ordo")
	return ordo != null and ordo.has_method("is_low") and ordo.is_low()


func _clear() -> void:
	for mmi in _mmi:
		mmi.queue_free()
	_mmi.clear()
	_mm.clear()


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


## Общий материал вида юнита (один на LOD0 и LOD1 и на все слои этого вида)
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
