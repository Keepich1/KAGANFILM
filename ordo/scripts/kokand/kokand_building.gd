class_name KokandBuilding
extends Node3D
## Здание или укрепление Коканда — обёртка над моделями assets/models/kokand/<kind>*.glb.
## Сцены-обёртки scenes/kokand/<kind>.tscn собирает tools/gen_kokand.py scenes.
##
## Состояния (state): "built" — готовое (<kind>.glb), "site" — стройка (<kind>_site.glb),
## "ruin" — руины (<kind>_ruin.glb). У каждого — облегчённая модель _lod1 (дальше lod_distance).
## Поле (kind = "dala"): готовое — стадия урожая growth 0..2 (dala_s0/s1/s2.glb).
##
## Метаданные (для экономики, поиска пути, выделения): footprint — Vector2 размер в плане, м
## (x — вдоль X, y — вдоль Z), kind, side = "kokand".
##
## Метки (узел Markers, Marker3D, в осях здания):
##   Door — вход (куда идут работники), WorkSpot_N — места работы, Smoke_N — дым (печь, тандыр,
##   труба), Fire_N — огонь и дым над руинами, Slot_1..10 — места гарнизона на башне (burj),
##   Banner — верх древка.
## Ворота (darvoza): set_gate_open(0..1) поворачивает створки Door/Door_L (+90°) и Door/Door_R (−90°)
##   внутрь (к −Z). Мельница (tegirmon): узел «Wheel» вращается вокруг своей оси X.
## Дом (uy): variant 1..3 — свой набор вещей во дворе (узлы Var_1..Var_3), 0 — по месту.

const MODELS := "res://assets/models/kokand/"
const SMOKE_SCENE := "res://scenes/camp/smoke.tscn"
const GROUND_DECAL := "res://assets/textures/kokand/ground_decal.png"

@export var kind := "uy"
@export var footprint := Vector2(8, 8)
@export_enum("built", "site", "ruin") var state := "built":
	set = set_state
## Дом: набор вещей во дворе 1..3 (0 — выбрать по месту)
@export_range(0, 3) var variant := 0
## Поле: стадия урожая 0 — всходы, 1 — зелёное, 2 — спелое
@export_range(0, 2) var growth := 2:
	set = set_growth
## С какого расстояния камеры модель сменяется облегчённой (LOD1), м
@export var lod_distance := 140.0
## Оттенок (глина домов немного разная)
@export var tint := Color(1, 1, 1, 1)
## Дым из труб/тандыров и над руинами
@export var smoke := true
## Ставить на землю мира (Terrain.height_at) при запуске
@export var snap := false
## Скорость колеса мельницы, рад/с
@export var wheel_speed := 0.9
## Утоптанная земля под зданием (Decal по земле мира): у зданий да, у звеньев стен и полей — нет
@export var ground_decal := true

const RIM_STRENGTH := 1.0

var gate_open := 0.0
var _model: Node3D
var _lod1: Node3D
var _wheels: Array[Node3D] = []
var _ready_done := false


func _ready() -> void:
	set_meta("footprint", footprint)
	set_meta("kind", kind)
	set_meta("side", "kokand")
	if _is_low():
		lod_distance = minf(lod_distance, 80.0)
	if snap:
		snap_to_terrain()
	_ready_done = true
	_rebuild()
	if ground_decal:
		_add_ground_decal()


func _process(delta: float) -> void:
	for w in _wheels:
		if is_instance_valid(w):
			w.rotate_object_local(Vector3.RIGHT, -wheel_speed * delta)


## Состояние: "built" | "site" | "ruin".
func set_state(s: String) -> void:
	state = s
	if _ready_done:
		_rebuild()


func set_growth(g: int) -> void:
	growth = clampi(g, 0, 2)
	if _ready_done and kind == "dala" and state == "built":
		_rebuild()


## Ворота: 0 — закрыты, 1 — открыты (створки внутрь, к −Z).
func set_gate_open(t: float) -> void:
	gate_open = clampf(t, 0.0, 1.0)
	for root in [_model, _lod1]:
		if root == null:
			continue
		var l := root.find_child("Door_L", true, false) as Node3D
		var r := root.find_child("Door_R", true, false) as Node3D
		if l:
			l.rotation.y = deg_to_rad(90.0 * gate_open)
		if r:
			r.rotation.y = -deg_to_rad(90.0 * gate_open)


## Метка по имени: marker("Door"), marker("Slot_3").
func marker(marker_name: String) -> Marker3D:
	return get_node_or_null("Markers/" + marker_name) as Marker3D


## Все метки с началом имени: markers("Slot_"), markers("WorkSpot_").
func markers(prefix: String) -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	var root := get_node_or_null("Markers")
	if root == null:
		return out
	for n in root.get_children():
		if String(n.name).begins_with(prefix) and n is Marker3D:
			out.append(n)
	return out


## Ставит здание на землю мира: по самой низкой точке под углами основания.
func snap_to_terrain() -> void:
	var p := global_position
	var h := Terrain.height_at(p.x, p.z)
	var hx := footprint.x * 0.5
	var hz := footprint.y * 0.5
	for c: Vector3 in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(hx, 0, hz)]:
		var w := global_transform * c
		h = minf(h, Terrain.height_at(w.x, w.z))
	global_position = Vector3(p.x, h, p.z)


## Имя файла модели для текущего состояния (без .glb).
func model_name() -> String:
	if state == "site":
		return kind + "_site"
	if state == "ruin":
		return kind + "_ruin"
	if kind == "dala":
		return "dala_s%d" % growth
	return kind


# ---------------------------------------------------------------- внутреннее

func _rebuild() -> void:
	for n in [_model, _lod1]:
		if n and is_instance_valid(n):
			n.queue_free()
	_model = null
	_lod1 = null
	_wheels.clear()
	var prev := get_node_or_null("Model")
	if prev:
		# модель из сцены (для редактора) — оставляем, только если это нужное состояние
		if prev.scene_file_path == MODELS + model_name() + ".glb":
			_model = prev
		else:
			remove_child(prev)
			prev.queue_free()
	var opts := {"rim_strength": RIM_STRENGTH}
	if tint != Color(1, 1, 1, 1):
		opts["albedo_tint"] = tint
	if _model == null:
		_model = _load(model_name())
		if _model == null:
			push_warning("KokandBuilding: нет модели " + model_name())
			return
		_model.name = "Model"
		add_child(_model)
	KokandModels.apply(_model, opts)
	_lod1 = _load(model_name() + "_lod1")
	if _lod1:
		_lod1.name = "LOD1"
		add_child(_lod1)
		KokandModels.apply(_lod1, opts)
		_set_range(_model, 0.0, lod_distance)
		_set_range(_lod1, lod_distance, 0.0)
	_pick_variant()
	if state == "built":
		for root in [_model, _lod1]:
			if root:
				var w := root.find_child("Wheel", true, false) as Node3D
				if w:
					_wheels.append(w)
	set_gate_open(gate_open)
	_smoke()


func _add_ground_decal() -> void:
	if not ResourceLoader.exists(GROUND_DECAL):
		return
	var d := Decal.new()
	d.name = "GroundDecal"
	d.texture_albedo = load(GROUND_DECAL)
	d.size = Vector3(footprint.x * 1.3 + 2.0, 1.2, footprint.y * 1.3 + 2.0)
	d.albedo_mix = 0.8
	d.modulate = Color(0.82, 0.78, 0.74, 1) if state != "ruin" else Color(0.5, 0.45, 0.42, 1)
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.normal_fade = 0.5
	d.cull_mask = 1
	add_child(d)


func _load(file: String) -> Node3D:
	var path := MODELS + file + ".glb"
	if not ResourceLoader.exists(path):
		return null
	return (load(path) as PackedScene).instantiate() as Node3D


## Вариант двора дома: variant или (0) — по месту.
func _variant() -> int:
	if variant != 0:
		return variant
	var p := global_position if is_inside_tree() else position
	return int(absf(p.x * 7.0 + p.z * 13.0)) % 3 + 1


func _pick_variant() -> void:
	if kind != "uy":
		return
	var v := _variant()
	for root in [_model, _lod1]:
		if root == null:
			continue
		for k in range(1, 4):
			var n := root.find_child("Var_%d" % k, true, false) as Node3D
			if n:
				n.visible = k == v


func _smoke() -> void:
	for c in get_children():
		if c is GPUParticles3D and String(c.name).begins_with("Smoke"):
			c.queue_free()
	if not smoke or not ResourceLoader.exists(SMOKE_SCENE):
		return
	var prefix := "Smoke_" if state == "built" else ("Fire_" if state == "ruin" else "")
	if prefix == "":
		return
	var scene := load(SMOKE_SCENE) as PackedScene
	var low := _is_low()
	for m in markers(prefix):
		# дым только у своего варианта двора (тандыр у дома варианта 1)
		if m.has_meta("variant") and int(m.get_meta("variant")) != _variant():
			continue
		var s := scene.instantiate() as GPUParticles3D
		s.name = "Smoke" + String(m.name).trim_prefix(prefix.trim_suffix("_"))
		s.transform = m.transform
		var ruin := state == "ruin"
		var amount := float(m.get_meta("amount", 16 if not ruin else 22))
		s.amount = maxi(4, int(amount * (0.5 if low else 1.0)))
		s.lifetime = 9.0
		s.preprocess = 9.0
		if ruin or m.get_meta("dark", false):
			_darken(s)
		add_child(s)
	_wind_smoke()


func _darken(s: GPUParticles3D) -> void:
	# дым пожара и горна: темнее и гуще белёсого дыма тюндюка
	var pm := (s.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.1, 0.5, 1.0])
	g.colors = PackedColorArray([Color(0.35, 0.28, 0.24, 0.0), Color(0.3, 0.27, 0.26, 0.32),
		Color(0.36, 0.36, 0.4, 0.2), Color(0.4, 0.42, 0.48, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	s.process_material = pm


func _wind_smoke() -> void:
	var wind := Vector4(0.82, 0.35, 1.0, 0.55)
	var o := get_node_or_null("/root/Ordo")
	if o and o.get("wind") is Vector4:
		wind = o.get("wind")
	var dir := Vector2(wind.x, wind.y).normalized()
	var w3 := Vector3(dir.x, 0.0, dir.y)
	for c in get_children():
		var p := c as GPUParticles3D
		if p == null:
			continue
		var pm := p.process_material as ParticleProcessMaterial
		if pm:
			pm = pm.duplicate() as ParticleProcessMaterial
			pm.direction = Vector3(0.0, 1.0, 0.0) + w3 * 0.55 * wind.z
			pm.gravity = w3 * 0.1 * wind.z + Vector3(0.0, 0.03, 0.0)
			pm.scale_min = 1.6
			pm.scale_max = 2.5
			p.process_material = pm
		var lw := p.global_basis.orthonormalized().inverse() * w3 if p.is_inside_tree() else w3
		var box := AABB(Vector3(-4.0, -1.0, -4.0), Vector3(8.0, 18.0, 8.0))
		p.visibility_aabb = box.expand(lw * 24.0 + Vector3(0.0, 16.0, 0.0)).expand(lw * 24.0)


func _set_range(root: Node, begin: float, end: float) -> void:
	if root is GeometryInstance3D:
		var g := root as GeometryInstance3D
		g.visibility_range_begin = begin
		g.visibility_range_end = end
		g.visibility_range_begin_margin = 4.0 if begin > 0.0 else 0.0
		g.visibility_range_end_margin = 4.0 if end > 0.0 else 0.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for c in root.get_children():
		_set_range(c, begin, end)


func _is_low() -> bool:
	var o := get_node_or_null("/root/Ordo")
	return o != null and bool(o.call("is_low"))
