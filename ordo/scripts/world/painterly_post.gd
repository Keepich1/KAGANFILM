@tool
class_name PainterlyPost
extends CompositorEffect
## Живописный фильтр поверх кадра (ТЗ 11.7 [Свободно]): анизотропная Кувахара —
## мелкий шум кадра собирается в мазки вдоль контуров; затем цветные тени,
## тёплый свет, фактура холста, виньетка. Работает после прозрачных объектов,
## до тональной кривой и свечения (shaders/post/*.glsl, вычислительные шейдеры).
##
## Включается/выключается свойством enabled (качество «Низкое» выключает).
## Без RenderingDevice (рендер Compatibility) молча ничего не делает.

const CTX := &"ordo_painterly_post"

## Радиус мазка в пикселях при высоте кадра 1080 (масштабируется с разрешением)
@export_range(0.0, 8.0, 0.1) var radius_1080 := 2.6
## Резкость выбора сектора (больше — чётче границы мазков)
@export_range(1.0, 20.0, 0.1) var hardness := 3.5
@export_range(1.0, 16.0, 0.1) var sharpness_q := 3.0
## Вытянутость мазка вдоль контура (меньше — сильнее вытянут)
@export_range(0.2, 4.0, 0.05) var anisotropy_alpha := 0.45
## Доля живописного фильтра (0 — только тон и холст)
@export_range(0.0, 1.0, 0.01) var amount := 0.75
## Подъём теней холодным цветом (rgb, сила в a)
@export var shadow_lift := Color(0.012, 0.026, 0.04, 1.0)
## Ниже какой яркости (линейной) тень поднимается
@export_range(0.01, 0.5, 0.005) var shadow_range := 0.06
## Тёплый множитель светов (rgb, сила в a)
@export var highlight_warm := Color(1.05, 0.98, 0.88, 0.6)
@export_range(0.0, 0.2, 0.002) var canvas_grain := 0.03
@export_range(0.0, 1.0, 0.01) var vignette := 0.32

var _rd: RenderingDevice
var _shaders := {}
var _size := Vector2i.ZERO


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	RenderingServer.call_on_render_thread(_init_compute)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd:
		for k in _shaders:
			if _shaders[k].shader.is_valid():
				_rd.free_rid(_shaders[k].shader)


func _init_compute() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	for n in ["tensor", "blur", "kuwahara"]:
		var file := load("res://shaders/post/painterly_%s.glsl" % n) as RDShaderFile
		if file == null:
			push_warning("PainterlyPost: нет шейдера %s" % n)
			continue
		var spirv := file.get_spirv()
		if spirv.compile_error_compute != "":
			push_error("PainterlyPost: %s: %s" % [n, spirv.compile_error_compute])
			continue
		var sh := _rd.shader_create_from_spirv(spirv)
		if not sh.is_valid():
			continue
		_shaders[n] = {"shader": sh, "pipeline": _rd.compute_pipeline_create(sh)}


func _render_callback(_type: int, render_data: RenderData) -> void:
	if _rd == null or _shaders.size() < 3:
		return
	var sb := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if sb == null:
		return
	var size := sb.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	if size != _size or not sb.has_texture(CTX, &"src"):
		_size = size
		if sb.has_texture(CTX, &"src"):
			sb.clear_context(CTX)
		var usage := RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		var fmt := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
		for name in [&"src", &"tensor", &"tmp"]:
			sb.create_texture(CTX, name, fmt, usage, RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, true, false)
	var gx := (size.x + 7) / 8
	var gy := (size.y + 7) / 8
	var scale := float(size.y) / 1080.0
	for view in sb.get_view_count():
		var color := sb.get_color_layer(view)
		var src := sb.get_texture_slice(CTX, &"src", view, 0, 1, 1)
		var tensor := sb.get_texture_slice(CTX, &"tensor", view, 0, 1, 1)
		var tmp := sb.get_texture_slice(CTX, &"tmp", view, 0, 1, 1)
		var cl := _rd.compute_list_begin()
		# 1. копия + тензор
		_bind(cl, "tensor", [color, src, tensor])
		_push(cl, PackedFloat32Array([size.x, size.y, 0.0, 0.0]))
		_rd.compute_list_dispatch(cl, gx, gy, 1)
		_rd.compute_list_add_barrier(cl)
		# 2. размытие тензора: по x в tmp, по y обратно
		var sigma := maxf(2.0 * scale, 1.0)
		_bind(cl, "blur", [tensor, tmp])
		_push(cl, PackedFloat32Array([size.x, size.y, 1.0, 0.0, sigma, 0.0, 0.0, 0.0]))
		_rd.compute_list_dispatch(cl, gx, gy, 1)
		_rd.compute_list_add_barrier(cl)
		_bind(cl, "blur", [tmp, tensor])
		_push(cl, PackedFloat32Array([size.x, size.y, 0.0, 1.0, sigma, 0.0, 0.0, 0.0]))
		_rd.compute_list_dispatch(cl, gx, gy, 1)
		_rd.compute_list_add_barrier(cl)
		# 3. Кувахара + тон
		_bind(cl, "kuwahara", [src, tensor, color])
		_push(cl, PackedFloat32Array([
			size.x, size.y, radius_1080 * scale, hardness, sharpness_q, 2.0 / maxf(radius_1080, 1.0) * 0.5, 0.58, anisotropy_alpha,
			shadow_lift.r, shadow_lift.g, shadow_lift.b, shadow_lift.a,
			highlight_warm.r, highlight_warm.g, highlight_warm.b, highlight_warm.a,
			canvas_grain, vignette, amount, shadow_range]))
		_rd.compute_list_dispatch(cl, gx, gy, 1)
		_rd.compute_list_end()


func _bind(cl: int, name: String, images: Array) -> void:
	var sh: RID = _shaders[name].shader
	_rd.compute_list_bind_compute_pipeline(cl, _shaders[name].pipeline)
	var uniforms := []
	for i in images.size():
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u.binding = i
		u.add_id(images[i])
		uniforms.append(u)
	_rd.compute_list_bind_uniform_set(cl, UniformSetCacheRD.get_cache(sh, 0, uniforms), 0)


func _push(cl: int, data: PackedFloat32Array) -> void:
	var bytes := data.to_byte_array()
	_rd.compute_list_set_push_constant(cl, bytes, bytes.size())
