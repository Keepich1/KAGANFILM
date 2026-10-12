class_name BattleDebugLayer
extends Node3D
## Запасной слой толпы боя: те же методы, что у CrowdLayer (scripts/units/crowd_layer.gd).
## Пока настоящей толпы нет в проекте, бой рисуется простыми фигурами из жёстких частей:
## силуэт, цвет стороны (20–30 % фигуры), анимация в вершинном шейдере (shaders/fx/crowd_debug.gdshader).
##
##   var layer := BattleDebugLayer.new()
##   add_child(layer)
##   layer.setup("kok_sarboz", 120)
##   layer.set_instance(i, Transform3D(Basis(Vector3.UP, h), pos), AnimSpec.custom(state, phase, aux, w))
##   layer.set_visible_count(n)
##
## Модель смотрит в +Z, начало координат — ступни на земле.

const SHADER := preload("res://shaders/fx/crowd_debug.gdshader")
const STRIDE := 16

## Запасной реестр (если нет UnitRegistry): скелет, оружие, высота, радиус, сторона
const INFO := {
	"kok_sarboz": {"skeleton": "human", "weapon": "musket", "height": 2.1, "radius": 0.4, "side": "kokand"},
	"kok_sarboz_banner": {"skeleton": "human", "weapon": "banner", "height": 2.1, "radius": 0.4, "side": "kokand"},
	"kok_yuzboshi": {"skeleton": "rider", "weapon": "saber", "height": 2.75, "radius": 0.9, "side": "kokand"},
	"kip_sayisker": {"skeleton": "rider", "weapon": "lance", "height": 2.75, "radius": 0.9, "side": "kipchak"},
	"kip_sayisker_banner": {"skeleton": "rider", "weapon": "banner", "height": 2.75, "radius": 0.9, "side": "kipchak"},
	"kip_kolbashchy": {"skeleton": "rider", "weapon": "mace", "height": 3.0, "radius": 1.05, "side": "kipchak", "scale": 1.1},
	"kip_jooker": {"skeleton": "human", "weapon": "sword", "height": 2.05, "radius": 0.4, "side": "kipchak"},
	"kip_malchy": {"skeleton": "human", "weapon": "staff", "height": 2.0, "radius": 0.35, "side": "kipchak"},
	"sheep": {"skeleton": "sheep", "weapon": "none", "height": 0.84, "radius": 0.45, "side": "neutral"},
	"horse": {"skeleton": "horse", "weapon": "none", "height": 2.0, "radius": 0.9, "side": "neutral"},
}
const SKELETON_ID := {"human": 0, "rider": 1, "sheep": 2, "horse": 3}

## Цвета сторон (ТЗ 2.1, 2.2): основной и отделка
const SIDE_MAIN := {"kokand": Color("#2f8f74"), "kipchak": Color("#b0392f"), "neutral": Color("#8a7a62")}
const SIDE_TRIM := {"kokand": Color("#c9a24a"), "kipchak": Color("#e6dcc4"), "neutral": Color("#d8ccb0")}

# классы цвета вершины (альфа)
const C_OWN := 1.0
const C_SIDE := 0.75
const C_TRIM := 0.5
const C_COAT := 0.25
const C_SKIN := 0.0

var unit_id := ""
var capacity := 0
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _buf := PackedFloat32Array()
var _visible := 0
var _dirty := false

static var _mesh_cache := {}
static var _mat_cache := {}


func setup(p_unit_id: String, p_capacity: int) -> void:
	if _mmi:
		_mmi.queue_free()
	unit_id = p_unit_id
	capacity = maxi(p_capacity, 0)
	var info: Dictionary = INFO.get(unit_id, INFO["kok_sarboz"])
	_buf.resize(capacity * STRIDE)
	_buf.fill(0.0)
	for i in capacity:
		_buf[i * STRIDE] = 1.0
		_buf[i * STRIDE + 5] = 1.0
		_buf[i * STRIDE + 10] = 1.0
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = _mesh_for(unit_id, info)
	_mm.instance_count = capacity
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Debug_" + unit_id
	_mmi.multimesh = _mm
	_mmi.material_override = _material_for(unit_id, info)
	_mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_mmi)
	_dirty = true


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
	_buf[o + 12] = custom.r
	_buf[o + 13] = custom.g
	_buf[o + 14] = custom.b
	_buf[o + 15] = custom.a
	_dirty = true


func set_custom(i: int, custom: Color) -> void:
	if i < 0 or i >= capacity:
		return
	var o := i * STRIDE + 12
	_buf[o] = custom.r
	_buf[o + 1] = custom.g
	_buf[o + 2] = custom.b
	_buf[o + 3] = custom.a
	_dirty = true


func set_visible_count(n: int) -> void:
	_visible = clampi(n, 0, capacity)
	if _mm:
		_mm.visible_instance_count = _visible
	_dirty = true


func get_visible_count() -> int:
	return _visible


func _enter_tree() -> void:
	if not RenderingServer.frame_pre_draw.is_connected(_flush):
		RenderingServer.frame_pre_draw.connect(_flush)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_flush):
		RenderingServer.frame_pre_draw.disconnect(_flush)


func _flush() -> void:
	if not _dirty or _mm == null:
		return
	_dirty = false
	RenderingServer.multimesh_set_buffer(_mm.get_rid(), _buf)
	# границы: по видимым экземплярам с запасом на копья и лежащих
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in _visible:
		var o := i * STRIDE
		var p := Vector3(_buf[o + 3], _buf[o + 7], _buf[o + 11])
		lo = lo.min(p)
		hi = hi.max(p)
	if _visible > 0:
		_mm.custom_aabb = AABB(lo - Vector3(4, 1, 4), hi - lo + Vector3(8, 7, 8))


# ================================================================= материал и меш

static func _material_for(id: String, info: Dictionary) -> ShaderMaterial:
	if _mat_cache.has(id):
		return _mat_cache[id]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var side: String = info.get("side", "neutral")
	m.set_shader_parameter("skeleton", SKELETON_ID.get(info.get("skeleton", "human"), 0))
	m.set_shader_parameter("side_main", SIDE_MAIN[side])
	m.set_shader_parameter("side_light", SIDE_TRIM[side])
	m.set_shader_parameter("model_height", float(info.get("height", 2.0)))
	_mat_cache[id] = m
	return m


static func _mesh_for(id: String, info: Dictionary) -> ArrayMesh:
	if _mesh_cache.has(id):
		return _mesh_cache[id]
	var b := _Builder.new()
	var side: String = info.get("side", "neutral")
	match String(info.get("skeleton", "human")):
		"human":
			_build_human(b, side, String(info.get("weapon", "none")))
		"rider":
			_build_horse(b, side, true)
			_build_rider(b, side, String(info.get("weapon", "lance")), id)
		"horse":
			_build_horse(b, "neutral", false)
		"sheep":
			_build_sheep(b)
	var mesh := b.commit()
	var sc := float(info.get("scale", 1.0))
	if sc != 1.0:
		mesh = b.commit(sc)
	_mesh_cache[id] = mesh
	return mesh


static func _build_human(b: _Builder, side: String, weapon: String) -> void:
	var kok := side == "kokand"
	var boot := Color("#3a2a20")
	var trousers := Color("#2b3530") if kok else Color("#4a3426")
	# ноги (части 1, 2), опора — под полами халата
	for k in 2:
		var sx := 0.11 if k == 0 else -0.11
		b.cyl(Vector3(sx, 0.0, 0.0), Vector3(sx, 0.64, 0.0), 0.075, 0.085, trousers, C_OWN, 1 + k, Vector2(0.62, 0.0))
		b.cyl(Vector3(sx, 0.0, 0.02), Vector3(sx, 0.3, 0.0), 0.085, 0.09, boot, C_OWN, 1 + k, Vector2(0.62, 0.0))
	# халат (чапан): расширяется книзу — цвет стороны
	b.cyl(Vector3(0, 0.48, 0), Vector3(0, 1.42, 0), 0.29, 0.19, Color(1, 1, 1), C_SIDE, 0, Vector2.ZERO, 9)
	# пояс
	b.cyl(Vector3(0, 0.96, 0), Vector3(0, 1.04, 0), 0.215, 0.205, Color("#c9a24a") if kok else Color("#6e4428"), C_OWN, 0)
	# отделка по полам и вороту
	b.cyl(Vector3(0, 0.47, 0), Vector3(0, 0.55, 0), 0.295, 0.28, Color(1, 1, 1), C_TRIM, 0, Vector2.ZERO, 9)
	# широкие плечи (ТЗ 11.1: силуэт чуть утрирован)
	b.box(Vector3(0, 1.36, 0), Vector3(0.6, 0.15, 0.27), Color(0.92, 0.92, 0.92), C_SIDE, 0)
	b.box(Vector3(0, 1.43, 0.02), Vector3(0.22, 0.06, 0.22), Color(1, 1, 1), C_TRIM, 0)
	# левая рука вдоль тела
	b.cyl(Vector3(-0.29, 1.36, 0), Vector3(-0.27, 0.9, 0.05), 0.065, 0.055, Color(0.85, 0.85, 0.85), C_SIDE, 0)
	# голова и борода
	b.sphere(Vector3(0, 1.58, 0.01), Vector3(0.115, 0.13, 0.12), Color(1, 1, 1), C_SKIN, 0)
	b.box(Vector3(0, 1.49, 0.08), Vector3(0.12, 0.08, 0.06), Color("#2a1e18"), C_OWN, 0)
	# высокая шапка — силуэт стороны
	if kok:
		b.cyl(Vector3(0, 1.64, 0), Vector3(0, 1.76, 0), 0.15, 0.15, Color("#e6dcc4"), C_OWN, 0, Vector2.ZERO, 10)
		b.cyl(Vector3(0, 1.74, 0), Vector3(0, 2.0, 0), 0.11, 0.05, Color(0.8, 0.8, 0.8), C_SIDE, 0, Vector2.ZERO, 8)
		b.sphere(Vector3(0, 2.02, 0), Vector3(0.035, 0.035, 0.035), Color(1, 1, 1), C_TRIM, 0)
	else:
		b.cyl(Vector3(0, 1.65, 0), Vector3(0, 1.69, 0), 0.17, 0.165, Color("#2a1e18"), C_OWN, 0, Vector2.ZERO, 10)
		b.cyl(Vector3(0, 1.68, 0), Vector3(0, 2.02, 0), 0.14, 0.06, Color("#ece4d0"), C_OWN, 0, Vector2.ZERO, 8)
	# правая рука + оружие (часть 3, опора в плече)
	var piv := Vector2(1.36, 0.0)
	b.cyl(Vector3(0.29, 1.36, 0), Vector3(0.27, 1.02, 0.08), 0.065, 0.055, Color(0.85, 0.85, 0.85), C_SIDE, 3, piv)
	match weapon:
		"musket":
			b.box(Vector3(0.27, 1.5, 0.08), Vector3(0.05, 1.5, 0.06), Color("#5a3b24"), C_OWN, 3, piv)
			b.box(Vector3(0.27, 2.05, 0.08), Vector3(0.03, 0.42, 0.03), Color("#5d6066"), C_OWN, 3, piv)
			b.box(Vector3(0.27, 1.02, 0.1), Vector3(0.07, 0.3, 0.1), Color("#4a3020"), C_OWN, 3, piv)
		"banner":
			# древко и полотнище (часть 4 — волнуется)
			b.cyl(Vector3(0.27, 0.5, 0.08), Vector3(0.27, 3.75, 0.08), 0.028, 0.025, Color("#5a3b24"), C_OWN, 3, piv)
			b.cone(Vector3(0.27, 3.75, 0.08), 0.06, 0.25, Color("#c9a24a"), C_OWN, 3, piv)
			b.box(Vector3(0.27, 3.25, -0.48), Vector3(0.03, 0.78, 0.95), Color(1, 1, 1), C_SIDE, 4, piv)
			b.box(Vector3(0.27, 3.25, -0.98), Vector3(0.035, 0.78, 0.08), Color(1, 1, 1), C_TRIM, 4, piv)
			b.box(Vector3(0.27, 3.66, -0.48), Vector3(0.035, 0.06, 0.95), Color(1, 1, 1), C_TRIM, 4, piv)
		"sword":
			b.box(Vector3(0.27, 1.4, 0.12), Vector3(0.05, 0.85, 0.02), Color("#b8bec4"), C_OWN, 3, piv)
			b.box(Vector3(0.27, 1.0, 0.12), Vector3(0.12, 0.04, 0.05), Color("#c9a24a"), C_OWN, 3, piv)
			# щит на левой руке — цвет стороны с белым кантом
			b.cyl(Vector3(-0.36, 1.12, 0.05), Vector3(-0.42, 1.12, 0.05), 0.31, 0.31, Color(1, 1, 1), C_TRIM, 0, Vector2.ZERO, 12, Vector3.RIGHT)
			b.cyl(Vector3(-0.42, 1.12, 0.05), Vector3(-0.44, 1.12, 0.05), 0.25, 0.25, Color(1, 1, 1), C_SIDE, 0, Vector2.ZERO, 12, Vector3.RIGHT)
		"staff":
			b.cyl(Vector3(0.27, 0.2, 0.1), Vector3(0.27, 1.9, 0.1), 0.025, 0.022, Color("#7a5a3a"), C_OWN, 3, piv)


static func _build_horse(b: _Builder, side: String, saddled: bool) -> void:
	var dark := Color(0.35, 0.3, 0.28)
	var coat := Color(1, 1, 1)
	# туловище
	b.capsule_z(Vector3(0, 1.2, -0.05), 0.37, 2.05, coat, C_COAT, 0)
	# шея и голова
	b.cyl(Vector3(0, 1.32, 0.7), Vector3(0, 1.95, 1.08), 0.22, 0.14, coat, C_COAT, 0, Vector2.ZERO, 8)
	b.box_rot(Vector3(0, 1.78, 1.3), Vector3(0.19, 0.22, 0.56), 1.0, coat, C_COAT, 0)
	b.box_rot(Vector3(0, 1.98, 1.06), Vector3(0.05, 0.12, 0.08), 0.2, dark * 0.5, C_OWN, 0)
	b.box_rot(Vector3(0, 1.72, 0.86), Vector3(0.06, 0.3, 0.62), -0.8, dark * 0.5, C_OWN, 0)
	# хвост
	b.cyl(Vector3(0, 1.38, -1.02), Vector3(0, 0.62, -1.28), 0.08, 0.04, dark * 0.45, C_OWN, 0, Vector2.ZERO, 6)
	# ноги (части 1–4): передние левая/правая, задние левая/правая
	var legs := [Vector2(0.18, 0.66), Vector2(-0.18, 0.66), Vector2(0.18, -0.72), Vector2(-0.18, -0.72)]
	for k in 4:
		var l: Vector2 = legs[k]
		var piv := Vector2(1.05, l.y)
		b.cyl(Vector3(l.x, 0.62, l.y), Vector3(l.x, 1.1, l.y), 0.085, 0.12, coat, C_COAT, 1 + k, piv)
		b.cyl(Vector3(l.x, 0.08, l.y), Vector3(l.x, 0.64, l.y), 0.055, 0.07, coat * 0.85, C_COAT, 1 + k, piv)
		b.cyl(Vector3(l.x, 0.0, l.y + 0.02), Vector3(l.x, 0.1, l.y + 0.02), 0.075, 0.065, Color("#2a2420"), C_OWN, 1 + k, piv)
	if saddled:
		# попона цвета стороны (20–30 % силуэта) с каймой
		b.box(Vector3(0, 1.12, -0.12), Vector3(0.84, 0.62, 1.32), Color(1, 1, 1), C_SIDE, 0)
		b.box(Vector3(0, 0.83, -0.12), Vector3(0.86, 0.08, 1.34), Color(1, 1, 1), C_TRIM, 0)
		b.box(Vector3(0, 1.52, -0.1), Vector3(0.6, 0.12, 0.62), Color("#4a3020"), C_OWN, 0)


static func _build_rider(b: _Builder, side: String, weapon: String, id: String) -> void:
	var kok := side == "kokand"
	var general := id == "kip_kolbashchy"
	# ноги всадника по бокам коня
	for k in 2:
		var sx := 0.36 if k == 0 else -0.36
		b.box_rot(Vector3(sx, 1.38, 0.08), Vector3(0.13, 0.5, 0.16), 0.35, Color("#3a2a20"), C_OWN, 5)
	# торс в халате/доспехе
	b.cyl(Vector3(0, 1.52, -0.05), Vector3(0, 2.2, 0.0), 0.24, 0.2, Color(1, 1, 1), C_SIDE, 5, Vector2.ZERO, 9)
	b.box(Vector3(0, 2.14, 0.0), Vector3(0.62, 0.15, 0.28), Color(0.92, 0.92, 0.92), C_SIDE, 5)
	if not kok:
		# пластинчатый доспех сайыскера — сталь поверх халата
		b.cyl(Vector3(0, 1.72, 0.0), Vector3(0, 2.08, 0.0), 0.245, 0.215, Color("#8a9098"), C_OWN, 5, Vector2.ZERO, 9)
	b.cyl(Vector3(0, 1.62, 0), Vector3(0, 1.68, 0), 0.25, 0.25, Color(1, 1, 1), C_TRIM, 5, Vector2.ZERO, 9)
	# голова
	b.sphere(Vector3(0, 2.38, 0.02), Vector3(0.115, 0.13, 0.12), Color(1, 1, 1), C_SKIN, 5)
	if kok:
		b.cyl(Vector3(0, 2.42, 0), Vector3(0, 2.56, 0), 0.16, 0.16, Color("#e6dcc4"), C_OWN, 5, Vector2.ZERO, 10)
		b.cyl(Vector3(0, 2.54, 0), Vector3(0, 2.76, 0), 0.11, 0.05, Color(0.8, 0.8, 0.8), C_SIDE, 5, Vector2.ZERO, 8)
	elif general:
		# шлем полководца: позолота и высокий султан
		b.cyl(Vector3(0, 2.42, 0), Vector3(0, 2.78, 0), 0.15, 0.03, Color("#d89a3a"), C_OWN, 5, Vector2.ZERO, 10)
		b.cyl(Vector3(0, 2.75, 0), Vector3(0, 3.2, -0.08), 0.05, 0.015, Color(1, 1, 1), C_TRIM, 5, Vector2.ZERO, 6)
		# плащ полководца
		b.box_rot(Vector3(0, 1.85, -0.3), Vector3(0.56, 0.75, 0.06), 0.25, Color(1, 1, 1), C_SIDE, 5)
	else:
		# остроконечный шлем
		b.cyl(Vector3(0, 2.42, 0), Vector3(0, 2.74, 0), 0.14, 0.02, Color("#9aa1a8"), C_OWN, 5, Vector2.ZERO, 10)
		b.cyl(Vector3(0, 2.3, -0.03), Vector3(0, 2.44, -0.03), 0.15, 0.145, Color("#5d6066"), C_OWN, 5, Vector2.ZERO, 10)
	# правая рука + оружие (часть 6, опора в кисти), знамя — часть 7
	var piv := Vector2(1.95, 0.12)
	b.cyl(Vector3(0.3, 2.14, 0.0), Vector3(0.32, 1.95, 0.12), 0.065, 0.055, Color(0.85, 0.85, 0.85), C_SIDE, 6, piv)
	match weapon:
		"lance":
			b.cyl(Vector3(0.33, 0.9, 0.12), Vector3(0.33, 5.0, 0.12), 0.03, 0.022, Color("#6e4c2c"), C_OWN, 6, piv, 6)
			b.cone(Vector3(0.33, 5.0, 0.12), 0.045, 0.32, Color("#c8ced4"), C_OWN, 6, piv)
			# вымпел у острия
			b.box(Vector3(0.33, 4.62, -0.12), Vector3(0.02, 0.22, 0.42), Color(1, 1, 1), C_SIDE, 6, piv)
			# щит за спиной
			b.cyl(Vector3(-0.3, 1.95, -0.05), Vector3(-0.36, 1.95, -0.05), 0.3, 0.3, Color(1, 1, 1), C_SIDE, 5, Vector2.ZERO, 12, Vector3.RIGHT)
		"banner":
			b.cyl(Vector3(0.33, 1.0, 0.12), Vector3(0.33, 5.3, 0.12), 0.034, 0.028, Color("#5a3b24"), C_OWN, 7, piv, 6)
			# трезубец навершия
			for k in 3:
				var dz := (k - 1) * 0.1
				b.cyl(Vector3(0.33, 5.25, 0.12 + dz), Vector3(0.33, 5.55 - absf(dz) * 1.2, 0.12 + dz * 1.4), 0.018, 0.008, Color("#c9a24a"), C_OWN, 7, piv, 4)
			# полотнище с каймой (ТЗ 11.3: вымпел)
			b.box(Vector3(0.33, 4.55, -0.55), Vector3(0.03, 1.1, 1.3), Color(1, 1, 1), C_SIDE, 7, piv)
			b.box(Vector3(0.33, 4.0, -0.55), Vector3(0.035, 0.08, 1.3), Color(1, 1, 1), C_TRIM, 7, piv)
			b.box(Vector3(0.33, 4.55, -1.22), Vector3(0.035, 1.1, 0.08), Color(1, 1, 1), C_TRIM, 7, piv)
		"saber":
			b.box(Vector3(0.33, 2.4, 0.12), Vector3(0.04, 0.9, 0.02), Color("#c8ced4"), C_OWN, 6, piv)
		"mace":
			b.cyl(Vector3(0.33, 1.85, 0.12), Vector3(0.33, 2.6, 0.12), 0.025, 0.025, Color("#5a3b24"), C_OWN, 6, piv, 6)
			b.sphere(Vector3(0.33, 2.66, 0.12), Vector3(0.09, 0.1, 0.09), Color("#c9a24a"), C_OWN, 6, piv)


static func _build_sheep(b: _Builder) -> void:
	var wool := Color("#ddd2b8")
	b.sphere(Vector3(0, 0.6, 0), Vector3(0.3, 0.27, 0.46), wool, C_OWN, 0)
	b.sphere(Vector3(0, 0.66, -0.12), Vector3(0.26, 0.24, 0.3), wool * 1.04, C_OWN, 0)
	var piv := Vector2(0.64, 0.38)
	b.box_rot(Vector3(0, 0.66, 0.55), Vector3(0.14, 0.15, 0.26), -0.4, Color("#3a2e26"), C_OWN, 5, piv)
	b.box(Vector3(0, 0.72, 0.44), Vector3(0.24, 0.05, 0.06), Color("#3a2e26"), C_OWN, 5, piv)
	var legs := [Vector2(0.12, 0.28), Vector2(-0.12, 0.28), Vector2(0.12, -0.3), Vector2(-0.12, -0.3)]
	for k in 4:
		var l: Vector2 = legs[k]
		b.cyl(Vector3(l.x, 0.0, l.y), Vector3(l.x, 0.42, l.y), 0.035, 0.04, Color("#3a2e26"), C_OWN, 1 + k, Vector2(0.42, l.y))


## Сборщик меша из примитивов: цвет вершины, номер части (UV2.x), опора (UV)
class _Builder:
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func _add(arrays: Array, xf: Transform3D, c: Color, cls: float, part: int, piv: Vector2) -> void:
		var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var pi: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var base := v.size()
		var lc := c.srgb_to_linear() if cls >= 0.99 else c
		lc.a = cls
		var nb := xf.basis.inverse().transposed()
		for k in pv.size():
			v.append(xf * pv[k])
			nr.append((nb * pn[k]).normalized())
			col.append(lc)
			uv.append(piv)
			uv2.append(Vector2(part, 0.0))
		for k in pi.size():
			idx.append(base + pi[k])

	## Цилиндр от a до b (радиусы ra у a, rb у b)
	func cyl(a: Vector3, b: Vector3, ra: float, rb: float, c: Color, cls: float, part: int,
			piv := Vector2.ZERO, seg := 8, _hint := Vector3.ZERO) -> void:
		var m := CylinderMesh.new()
		m.bottom_radius = ra
		m.top_radius = rb
		var d := b - a
		m.height = d.length()
		m.radial_segments = seg
		m.rings = 1
		var up := d.normalized()
		var basis := Basis()
		if absf(up.dot(Vector3.UP)) < 0.999:
			var x := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
			var z := x.cross(up).normalized()
			basis = Basis(x, up, z)
		elif up.y < 0.0:
			basis = Basis(Vector3.RIGHT, PI)
		_add(m.get_mesh_arrays(), Transform3D(basis, (a + b) * 0.5), c, cls, part, piv)

	func cone(base: Vector3, r: float, h: float, c: Color, cls: float, part: int, piv := Vector2.ZERO) -> void:
		cyl(base, base + Vector3(0, h, 0), r, 0.0, c, cls, part, piv, 6)

	func box(center: Vector3, size: Vector3, c: Color, cls: float, part: int, piv := Vector2.ZERO) -> void:
		var m := BoxMesh.new()
		m.size = size
		_add(m.get_mesh_arrays(), Transform3D(Basis(), center), c, cls, part, piv)

	## Коробка, наклонённая вокруг X (rx, радианы)
	func box_rot(center: Vector3, size: Vector3, rx: float, c: Color, cls: float, part: int, piv := Vector2.ZERO) -> void:
		var m := BoxMesh.new()
		m.size = size
		_add(m.get_mesh_arrays(), Transform3D(Basis(Vector3.RIGHT, rx), center), c, cls, part, piv)

	func sphere(center: Vector3, r: Vector3, c: Color, cls: float, part: int, piv := Vector2.ZERO) -> void:
		var m := SphereMesh.new()
		m.radius = 1.0
		m.height = 2.0
		m.radial_segments = 10
		m.rings = 6
		_add(m.get_mesh_arrays(), Transform3D(Basis.from_scale(r), center), c, cls, part, piv)

	## Капсула вдоль Z
	func capsule_z(center: Vector3, r: float, length: float, c: Color, cls: float, part: int) -> void:
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = length
		m.radial_segments = 10
		m.rings = 4
		_add(m.get_mesh_arrays(), Transform3D(Basis(Vector3.RIGHT, PI / 2), center), c, cls, part, Vector2.ZERO)

	func commit(scale := 1.0) -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		var vv := v
		if scale != 1.0:
			vv = PackedVector3Array()
			for p in v:
				vv.append(p * scale)
		arr[Mesh.ARRAY_VERTEX] = vv
		arr[Mesh.ARRAY_NORMAL] = nr
		arr[Mesh.ARRAY_COLOR] = col
		var uvs := uv
		if scale != 1.0:
			uvs = PackedVector2Array()
			for p in uv:
				uvs.append(p * scale)
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m
