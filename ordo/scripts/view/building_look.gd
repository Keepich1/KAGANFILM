class_name BuildingLook
extends RefCounted
## Как выглядит постройка (ARCHITECTURE §13, CONTRACT §10.8).
##
## Модели — арт сторон: assets/models/<faction>/<имя>.glb (+ <имя>_lod1.glb), стройка <имя>_site.glb,
## руина <имя>_ruin.glb, поле — стадии урожая <имя>_s0/_s1/_s2.glb. Имя — поле model в BuildingDefs,
## иначе id, иначе псевдоним ALIAS (имя в данных ↔ имя файла арта). Материалы — KokandModels /
## KipchakModels (как у обёрток KokandBuilding / KipchakBuilding): живописные, ткань колышется,
## пятна земли кыпчаков спрятаны (землю рисует мир), у Коканда — двор и вода видны (без тени).
## Обёртки арта scenes/kokand/<имя>.tscn и scenes/kipchak2/<имя>.tscn вид не ставит (готовые постройки
## рисует MultiMesh) — из них читаются только метки Markers: Smoke_N — дым (у дома — по варианту двора).
## Дом (uy): двор Var_1..3 выбирается по месту (как KokandBuilding._variant). Колесо мельницы
## (часть «Wheel») крутит BuildingView.
##
## Нет файла — заместитель: живописный «набор» (city_kit.gdshader): кокандские глинобитные дома с
## плоской кровлей, айваном и поясом изразцов, урда с порталом и куполом, стены с зубцами, бурж;
## кыпчакские войлочные шатры, срубы, частокол, вышка. Один меш и один материал на тип.
## Стройка: модель _site (нет её — готовая модель с лесами и крышкой среза) срезана по высоте
## прогресса — растёт снизу (site_rise.gdshader). Руина: _ruin; нет её — нижняя треть готовой,
## обгоревшая, с обломками.
##
##   BuildingLook.make(defs, btype, State.ACTIVE)         -> Node3D (основание в 0, фасад в +Z)
##   BuildingLook.set_progress(node, 0.4)                 стройка: срез на 40 % высоты
##   BuildingLook.parts_for(defs, btype, lod, stage)      части для MultiMesh: [{mesh, xform, material,
##                                                        var, spin, shadow}]
##   BuildingLook.smoke_points(defs, btype, variant)      дым готовой постройки (метки, тюндюк)

const KIT_SHADER := preload("res://shaders/view/city_kit.gdshader")
const RISE_SHADER := preload("res://shaders/view/site_rise.gdshader")
const SURFACE := preload("res://shaders/painterly_surface.gdshader")
const CUTOUT := preload("res://shaders/painterly_cutout.gdshader")
const ATLAS_PATH := "res://assets/textures/kipchak/atlas.png"
const SMOKE := preload("res://scenes/camp/smoke.tscn")
## Высота дымового отверстия над основанием модели, м (как у лагеря среза)
const TUNDUK_HEIGHT := {"boz": 4.55, "ordo": 8.1}
## Контровой свет: кыпчаки — как лагерь, Коканд — как KokandBuilding
const RIM_STRENGTH := 1.1
const RIM_KOKAND := 1.0
const LOD_DISTANCE := 140.0
## Имя в данных → имя файла арта (тўғон — tugon, ариқ — aryk)
const ALIAS := {"togon": "tugon", "ariq": "aryk"}
## Папка обёрток арта по стороне (метки Markers)
const WRAPPER_DIR := {"kokand": "res://scenes/kokand/", "kipchak": "res://scenes/kipchak2/"}
## Колесо мельницы, рад/с (как KokandBuilding.wheel_speed)
const WHEEL_SPEED := 0.9
const A := 2048.0

## Области атласа лагеря (tools/gen_camp_atlas.py LAYOUT): x, y, w, h в пикселях
const R := {
	"earth": Rect2(8, 1464, 512, 512), "stones": Rect2(808, 1464, 256, 256), "planks": Rect2(1352, 1464, 256, 256),
	"lattice": Rect2(1624, 1464, 256, 256), "wood": Rect2(696, 936, 256, 512), "walnut": Rect2(424, 936, 256, 512),
	"pole": Rect2(1912, 696, 128, 224), "bark": Rect2(1928, 1736, 112, 256), "logend": Rect2(1224, 1736, 128, 128),
	"felt": Rect2(1512, 1736, 256, 256), "felt_grey": Rect2(808, 1736, 256, 256), "wall_boz": Rect2(8, 8, 1008, 384),
	"dome": Rect2(8, 408, 1008, 512), "door": Rect2(8, 936, 256, 512), "hay": Rect2(536, 1464, 256, 256),
	"koshma": Rect2(1560, 696, 256, 224), "wattle": Rect2(1032, 696, 512, 224), "iron": Rect2(1080, 1464, 256, 256),
	"saddlecloth": Rect2(536, 1736, 256, 256), "eave": Rect2(1032, 408, 1008, 128), "rope": Rect2(1832, 696, 64, 224),
	"tile": Rect2(0, 0, 0, 0),
	"adobe": Rect2(1512, 1736, 256, 256), "rough": Rect2(808, 1464, 256, 256),
}
## Сколько метров на один повтор области
const M := {"earth": 3.0, "stones": 2.0, "planks": 2.0, "lattice": 1.6, "wood": 2.0, "walnut": 2.0, "pole": 1.0,
	"bark": 1.5, "logend": 0.6, "felt": 2.5, "felt_grey": 2.5, "wall_boz": 8.0, "dome": 8.0, "door": 2.0, "hay": 2.0,
	"koshma": 3.0, "wattle": 3.0, "iron": 1.0, "saddlecloth": 2.0, "eave": 8.0, "rope": 1.0, "tile": 1.0,
	"adobe": 2.8, "rough": 2.2}

## Тон глины, извести, дерева (Коканд), войлока (кыпчаки)
const ADOBE := Color(0.93, 0.77, 0.58)
const ADOBE_DARK := Color(0.76, 0.6, 0.45)
const PLASTER := Color(1.0, 0.94, 0.82)
const WOOD := Color(0.8, 0.68, 0.56)
const FELT := Color(1.0, 0.97, 0.92)
const SHADE := Color(0.55, 0.5, 0.48)

static var _mesh_cache := {}
static var _kit_mat: ShaderMaterial
static var _rise_cache := {}
static var _model_cache := {}
static var _name_cache := {}
static var _marker_cache := {}


# ================================================================= узел постройки

## Узел постройки: модель (если есть) или заместитель; state — BuildingTable.State,
## variant — двор дома (variant_of), stage — стадия поля 0..2
static func make(defs: Defs, btype: int, state: int, lod := LOD_DISTANCE, variant := 0, stage := 2) -> Node3D:
	var path := model_path(defs, btype, state, stage)
	var root := Node3D.new()
	root.name = defs.b_ids[btype]
	var body: Node3D
	var exact := path != "" and (state == BuildingTable.State.ACTIVE or _suffix_found(path, state))
	if path != "":
		body = instance_model(path, lod, false)
		pick_variant(body, variant)
	else:
		body = MeshInstance3D.new()
		(body as MeshInstance3D).mesh = mesh_for(defs, btype)
		(body as MeshInstance3D).material_override = kit_material()
	body.name = "Body"
	root.add_child(body)
	root.set_meta("height", _height_of(body, defs, btype))
	root.set_meta("exact", exact)
	root.set_meta("rise", false)
	if state == BuildingTable.State.ACTIVE and path != "":
		# дым из труб, тандыров, тюндюков (метки обёртки арта)
		for sp: Dictionary in smoke_points(defs, btype, variant):
			var s := smoke_node([sp.pos as Vector3], int(sp.amount), bool(sp.dark))
			s.name = "Smoke"
			root.add_child(s)
	if state == BuildingTable.State.SITE:
		_to_rise(body)
		root.set_meta("rise", true)
		if not exact:
			var sc := MeshInstance3D.new()
			sc.name = "Scaffold"
			sc.mesh = scaffold_mesh(defs, btype, float(root.get_meta("height")))
			sc.material_override = kit_material()
			sc.set_instance_shader_parameter("site", 1.0)
			root.add_child(sc)
			_add_cap(root, defs, btype, 0.0)
		set_progress(root, 0.0)
	elif state == BuildingTable.State.RUIN and not exact:
		_to_rise(body)
		root.set_meta("rise", true)
		_set_inst(body, "clip_h", float(root.get_meta("height")) * 0.34)
		_set_inst(body, "scorch", 0.85)
		var rb := MeshInstance3D.new()
		rb.name = "Rubble"
		rb.mesh = rubble_mesh(defs, btype)
		rb.material_override = kit_material()
		rb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rb.set_instance_shader_parameter("scorch", 0.55)
		root.add_child(rb)
		_add_cap(root, defs, btype, 0.85)
		var cap := root.get_node_or_null("Cap") as Node3D
		if cap:
			cap.position.y = float(root.get_meta("height")) * 0.34 - 0.04
	return root


## Срез стройки (руины) сверху: плоская крышка по следу на высоте среза — стройка выглядит сплошной
## растущей кладкой. Круглые постройки и башни — круг; поля, звенья и плотины — без крышки.
static func _add_cap(root: Node3D, defs: Defs, btype: int, scorch: float) -> void:
	var kind := defs.b_kind[btype]
	if kind == Defs.BKind.FIELD or kind == Defs.BKind.LINK or kind == Defs.BKind.WALL or kind == Defs.BKind.DAM:
		return
	var sz := defs.b_size[btype]
	var round := defs.b_flags[btype] & Defs.BF_ROUND != 0 or kind == Defs.BKind.TOWER
	var key := "cap:%s" % defs.b_ids[btype]
	var mesh: ArrayMesh = _mesh_cache.get(key)
	if mesh == null:
		var k := Kit.new()
		var reg := "adobe" if defs.b_faction[btype] == "kokand" else "felt_grey"
		var tint := Color(0.88, 0.7, 0.52) if defs.b_faction[btype] == "kokand" else Color(0.85, 0.8, 0.72)
		if round:
			k.cyl(Vector3(0, -0.06, 0), minf(sz.x, sz.y) * 0.4, minf(sz.x, sz.y) * 0.4, 0.06, 16, reg, tint)
		else:
			k.box(Vector3(0, -0.03, 0), Vector3(sz.x * 0.5 - 0.35, 0.03, sz.y * 0.5 - 0.35), reg, tint)
		mesh = k.commit()
		_mesh_cache[key] = mesh
	var cap := MeshInstance3D.new()
	cap.name = "Cap"
	cap.mesh = mesh
	cap.material_override = kit_material()
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cap.set_instance_shader_parameter("scorch", scorch)
	cap.set_meta("round", round)
	root.add_child(cap)


## Стройка: срез на доле высоты k (0..1). Модель _site растёт от цоколя до своей высоты; готовая
## модель вместо _site — до полной, с лесами и крышкой среза (пока k < 1)
static func set_progress(root: Node3D, k: float) -> void:
	var body := root.get_node_or_null("Body") as Node3D
	if body == null or not bool(root.get_meta("rise", false)):
		return
	var h := float(root.get_meta("height", 4.0))
	# фундамент виден сразу (0,35 м), дальше стены растут
	var clip := 0.35 + clampf(k, 0.0, 1.0) * (h - 0.35) * 1.02
	_set_inst(body, "clip_h", clip)
	set_base(root)
	var cap := root.get_node_or_null("Cap") as Node3D
	if cap:
		cap.position.y = clip - 0.02
		# у круглых кровля сужается — выше стен крышка торчала бы наружу
		cap.visible = k < 0.97 and (not bool(cap.get_meta("round", false)) or clip < h * 0.55)


## Основание среза (site_rise считает высоту от мировой y основания): звать, когда узел поставлен на место.
## Стройка зовёт сама из set_progress; руине — BuildingView после постановки (иначе срез от y = 0 мира).
static func set_base(root: Node3D) -> void:
	var body := root.get_node_or_null("Body") as Node3D
	if body == null or not bool(root.get_meta("rise", false)):
		return
	_set_inst(body, "base_y", root.global_position.y if root.is_inside_tree() else root.position.y)


## Плоская постройка (поле, арык и другое, по чему ходят): тени не нужны — меньше вызовов отрисовки
static func is_flat(defs: Defs, btype: int) -> bool:
	return defs.b_kind[btype] == Defs.BKind.FIELD or defs.b_flags[btype] & Defs.BF_WALKABLE != 0


## Выключить тени у всех мешей узла
static func no_shadow(root: Node) -> void:
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Копоть 0..1 (руина, сильно повреждённое здание). Готовой модели — материал среза без среза
## (у живописного материала копоти нет)
static func set_scorch(root: Node3D, k: float) -> void:
	var body := root.get_node_or_null("Body") as Node3D
	if body == null:
		return
	if k > 0.0 and not bool(root.get_meta("rise", false)):
		_to_rise(body)
		root.set_meta("rise", true)
	_set_inst(body, "scorch", k)


# ================================================================= модели арта

## Имя модели типа в assets/models/<faction>/ ("" — файла нет): поле model, id, псевдонимы ALIAS
static func model_name(defs: Defs, btype: int) -> String:
	var key := "%s/%s/%s" % [defs.b_faction[btype], defs.b_ids[btype], defs.b_model[btype]]
	if _name_cache.has(key):
		return _name_cache[key]
	var dir := _dir(defs, btype)
	var out := ""
	for c: String in [defs.b_model[btype], defs.b_ids[btype]]:
		for n: String in [c, String(ALIAS.get(c, ""))]:
			if out == "" and n != "" and (_exists(dir + n + ".glb") or _exists(dir + n + "_s2.glb")):
				out = n
	_name_cache[key] = out
	return out


static func _dir(defs: Defs, btype: int) -> String:
	return "res://assets/models/%s/" % defs.b_faction[btype]


## Путь модели ("" — нет файла): state — BuildingTable.State; stage — стадия поля 0..2
static func model_path(defs: Defs, btype: int, state: int, stage := 2) -> String:
	var n := model_name(defs, btype)
	if n == "":
		return ""
	var dir := _dir(defs, btype)
	if state == BuildingTable.State.SITE or state == BuildingTable.State.RUIN:
		var p := dir + n + ("_site" if state == BuildingTable.State.SITE else "_ruin") + ".glb"
		if _exists(p):
			return p
	if defs.b_kind[btype] == Defs.BKind.FIELD:
		var f := dir + n + "_s%d.glb" % clampi(stage, 0, 2)
		if _exists(f):
			return f
	var g := dir + n + ".glb"
	return g if _exists(g) else ""


static func _suffix_found(path: String, state: int) -> bool:
	return path.ends_with("_site.glb") if state == BuildingTable.State.SITE else path.ends_with("_ruin.glb")


static func _exists(p: String) -> bool:
	if not _model_cache.has(p):
		_model_cache[p] = ResourceLoader.exists(p)
	return _model_cache[p]


## Метки обёртки арта (scenes/kokand|kipchak2/<имя>.tscn, узел Markers): [{name, xform, meta}].
## Читаются из SceneState, сцена не создаётся.
static func markers(defs: Defs, btype: int) -> Array:
	var key := "%s/%s" % [defs.b_faction[btype], defs.b_ids[btype]]
	if _marker_cache.has(key):
		return _marker_cache[key]
	var out: Array = []
	var n := model_name(defs, btype)
	var path := String(WRAPPER_DIR.get(defs.b_faction[btype], "")) + n + ".tscn"
	if n != "" and _exists(path):
		var st := (load(path) as PackedScene).get_state()
		for i in st.get_node_count():
			if String(st.get_node_path(i, true)) != "./Markers":
				continue
			var m := {"name": String(st.get_node_name(i)), "xform": Transform3D(), "meta": {}}
			for k in st.get_node_property_count(i):
				var pn := String(st.get_node_property_name(i, k))
				if pn == "transform":
					m.xform = st.get_node_property_value(i, k)
				elif pn.begins_with("metadata/"):
					(m.meta as Dictionary)[pn.trim_prefix("metadata/")] = st.get_node_property_value(i, k)
			out.append(m)
	_marker_cache[key] = out
	return out


## Дым готовой постройки: [{pos, amount, dark}] в осях постройки — метки Smoke_N обёртки (у дома —
## только своего варианта двора) и тюндюк юрты
static func smoke_points(defs: Defs, btype: int, variant := 0) -> Array:
	var out: Array = []
	for m: Dictionary in markers(defs, btype):
		if not String(m.name).begins_with("Smoke_"):
			continue
		var meta: Dictionary = m.meta
		if meta.has("variant") and int(meta.variant) != variant:
			continue
		out.append({"pos": (m.xform as Transform3D).origin, "amount": int(meta.get("amount", 16)),
			"dark": bool(meta.get("dark", false))})
	var n := model_name(defs, btype)
	if TUNDUK_HEIGHT.has(n):
		out.append({"pos": Vector3(0, TUNDUK_HEIGHT[n], 0), "amount": 14 if n == "boz" else 22, "dark": false})
	return out


## Вариант двора дома 1..3 по месту центра (как KokandBuilding._variant); 0 — у модели вариантов нет
static func variant_of(defs: Defs, btype: int, p: Vector2) -> int:
	if model_name(defs, btype) != "uy":
		return 0
	return int(absf(p.x * 7.0 + p.y * 13.0)) % 3 + 1


## Оставить видимым двор Var_<variant> (у LOD1 тоже); 0 — первый
static func pick_variant(body: Node, variant: int) -> void:
	for n in body.find_children("Var_*", "Node3D", true, false):
		var k := int(String(n.name).trim_prefix("Var_"))
		(n as Node3D).visible = k == maxi(variant, 1)


## Дым (GPUParticles3D дыма лагеря) из точек pts (в осях родителя); узел — в середине точек.
## dark — дым печи и горна (темнее). Видимость — весь столб над каждой точкой.
static func smoke_node(pts: PackedVector3Array, amount_each: int, dark := false, amount_max := 1400) -> GPUParticles3D:
	var s := SMOKE.instantiate() as GPUParticles3D
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var mid := (lo + hi) * 0.5
	var pm := (s.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
	if pts.size() > 1:
		var img := Image.create(pts.size(), 1, false, Image.FORMAT_RGBF)
		for i in pts.size():
			var p := pts[i] - mid
			img.set_pixel(i, 0, Color(p.x, p.y, p.z))
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
		pm.emission_point_texture = ImageTexture.create_from_image(img)
		pm.emission_point_count = pts.size()
	if dark:
		# дым печи и горна: темнее и гуще белёсого дыма тюндюка (как KokandBuilding._darken)
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.1, 0.5, 1.0])
		g.colors = PackedColorArray([Color(0.35, 0.28, 0.24, 0.0), Color(0.3, 0.27, 0.26, 0.32),
			Color(0.36, 0.36, 0.4, 0.2), Color(0.4, 0.42, 0.48, 0.0)])
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt
	s.process_material = pm
	s.position = mid
	s.amount = clampi(amount_each * pts.size(), 4, amount_max)
	s.lifetime = 9.0
	s.preprocess = 9.0
	# весь столб над каждой точкой (как у одиночного дыма: −6..8 в стороны, −1..15 вверх)
	s.visibility_aabb = AABB(lo - mid + Vector3(-6, -1, -6), hi - lo + Vector3(14, 16, 14))
	return s


## Модель из glb/tscn: живописные материалы стороны (Коканд — KokandModels, иначе KipchakModels),
## LOD1 дальше lod, пятна земли кыпчаков спрятаны, дым тюндюка у юрт (smoke)
static func instance_model(path: String, lod := LOD_DISTANCE, smoke := true) -> Node3D:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	if path.ends_with(".glb"):
		_apply(n, path)
	var lod1_path := path.get_basename() + "_lod1.glb"
	if lod > 0.0 and path.ends_with(".glb") and _exists(lod1_path):
		_set_range(n, 0.0, lod)
		var l1 := (load(lod1_path) as PackedScene).instantiate() as Node3D
		l1.name = "LOD1"
		n.add_child(l1)
		_apply(l1, lod1_path)
		_set_range(l1, lod, 0.0)
	var kind := path.get_file().get_basename()
	if smoke and TUNDUK_HEIGHT.has(kind):
		var s := SMOKE.instantiate() as GPUParticles3D
		s.name = "TundukSmoke"
		s.position = Vector3(0, TUNDUK_HEIGHT[kind], 0)
		s.amount = 14 if kind == "boz" else 22
		s.lifetime = 9.0
		s.preprocess = 9.0
		n.add_child(s)
	return n


## Материалы модели арта по стороне (папка файла)
static func _apply(n: Node, path: String) -> void:
	if path.contains("/models/kokand/"):
		KokandModels.apply(n, {"rim_strength": RIM_KOKAND})
	else:
		KipchakModels.apply(n, {"rim_strength": RIM_STRENGTH})
		_hide_ground(n)


static func _hide_ground(root: Node) -> void:
	for c in root.get_children():
		if c is MeshInstance3D and String(c.name).begins_with("Ground"):
			(c as MeshInstance3D).visible = false


static func _set_range(root: Node, begin: float, end: float) -> void:
	if root is GeometryInstance3D:
		var g := root as GeometryInstance3D
		g.visibility_range_begin = begin
		g.visibility_range_end = end
		g.visibility_range_begin_margin = 4.0 if begin > 0.0 else 0.0
		g.visibility_range_end_margin = 4.0 if end > 0.0 else 0.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for c in root.get_children():
		if not c is GPUParticles3D:
			_set_range(c, begin, end)


static func _height_of(body: Node3D, defs: Defs, btype: int) -> float:
	var hi := 0.0
	for mi in _mesh_instances(body):
		if mi.mesh and mi.visible and String(mi.name) != "LOD1" and String(mi.get_parent().name) != "LOD1":
			var box := mi.mesh.get_aabb()
			hi = maxf(hi, (_rel_xform(body, mi) * box).end.y)
	return hi if hi > 0.5 else 4.0


## Материалы модели → срез по высоте (site_rise), по одному на исходный материал
static func _to_rise(body: Node3D) -> void:
	for mi in _mesh_instances(body):
		if mi.material_override == kit_material():
			continue
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			mi.set_surface_override_material(s, _rise_material(src))


static func _rise_material(src: Material) -> Material:
	if _rise_cache.has(src):
		return _rise_cache[src]
	var m := ShaderMaterial.new()
	m.shader = RISE_SHADER
	if src is ShaderMaterial:
		var sm := src as ShaderMaterial
		for k: String in ["albedo_tex", "albedo_tint", "use_vertex_color", "rim_strength", "roughness"]:
			var v: Variant = sm.get_shader_parameter(k)
			if v != null:
				m.set_shader_parameter(k, v)
		if sm.shader == CUTOUT or (sm.shader != SURFACE and sm.get_shader_parameter("albedo_tex") == null):
			m.set_shader_parameter("alpha_cut", true)
		if sm.get_shader_parameter("albedo_tex") == null:
			# ткань и угли: свой атлас не найден — тёплый войлок
			m.set_shader_parameter("albedo_tint", Color(0.8, 0.7, 0.6))
	elif src is BaseMaterial3D:
		m.set_shader_parameter("albedo_tex", (src as BaseMaterial3D).albedo_texture)
		m.set_shader_parameter("albedo_tint", (src as BaseMaterial3D).albedo_color)
	_rise_cache[src] = m
	return m


static func _set_inst(root: Node, param: String, v: float) -> void:
	for mi in _mesh_instances(root):
		mi.set_instance_shader_parameter(param, v)


static func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_mesh_instances(c))
	return out


# ================================================================= MultiMesh

## Части модели для MultiMesh: [{mesh, xform, material, var, spin, shadow}]; lod 0 или 1 ([] — нет LOD1);
## stage — стадия поля. var — двор Var_<k> (0 — общая часть), spin — колесо (крутит BuildingView),
## shadow — отбрасывает ли тень (вода, двор, колосья — нет). Части с одним материалом (и тем же двором
## и тенью) слиты в один меш: на часть — свой MultiMesh, значит, вызов отрисовки. Заместитель — один меш.
static func parts_for(defs: Defs, btype: int, lod := 0, stage := 2) -> Array:
	var path := model_path(defs, btype, BuildingTable.State.ACTIVE, stage)
	if path.ends_with(".glb"):
		var p := path if lod == 0 else path.get_basename() + "_lod1.glb"
		if lod > 0 and not _exists(p):
			return []
		var key := "parts:" + p
		if _mesh_cache.has(key):
			return _mesh_cache[key]
		var n := instance_model(p, 0.0, false)
		var out: Array = []
		for mi in _mesh_instances(n):
			if mi.mesh == null or not mi.visible or String(mi.name) == "LOD1":
				continue
			# двор/пятно земли Коканда — только вблизи (вдали — земля мира): на группу вызовом меньше
			if lod > 0 and String(mi.name).begins_with("Ground"):
				continue
			# материалы — в копию меша (у MultiMesh нет своих материалов на поверхность)
			var m := mi.mesh.duplicate() as Mesh
			for s in m.get_surface_count():
				var mat := mi.get_active_material(s)
				if m is ArrayMesh:
					(m as ArrayMesh).surface_set_material(s, mat)
			out.append({"mesh": m, "xform": _rel_xform(n, mi), "material": null, "var": _var_of(n, mi),
				"spin": String(mi.name).begins_with("Wheel"),
				"shadow": mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF})
		n.free()
		out = merge_parts(out)
		if lod > 0:
			# вдали тень — только у самой большой части (флаги, навесы, колёса — без тени)
			var main := -1
			var best := -1.0
			for i in out.size():
				var v := ((out[i].mesh as Mesh).get_aabb().size as Vector3)
				if bool(out[i].shadow) and v.x * v.y * v.z > best:
					best = v.x * v.y * v.z
					main = i
			for i in out.size():
				if i != main and int(out[i]["var"]) == 0:
					out[i].shadow = false
		_mesh_cache[key] = out
		return out
	if lod > 0:
		return []
	return [{"mesh": mesh_for(defs, btype), "xform": Transform3D(), "material": kit_material(), "var": 0,
		"spin": false, "shadow": not is_flat(defs, btype)}]


## Слить части с одним материалом, двором и тенью в один меш (SurfaceTool.append_from с переносом в
## оси постройки). Колёса и многоповерхностные части — как есть.
static func merge_parts(parts: Array) -> Array:
	# двор Var_1..3 и общая часть с тем же материалом — в меш на каждый вариант (дом — один вызов,
	# а не общий + свой двор); варианты есть все три — общая часть есть у каждого дома
	var vars := {}
	for p: Dictionary in parts:
		if int(p["var"]) > 0 and (p.mesh as Mesh).get_surface_count() == 1:
			var vk: Variant = [(p.mesh as Mesh).surface_get_material(0), bool(p.shadow)]
			if not vars.has(vk):
				vars[vk] = {}
			(vars[vk] as Dictionary)[int(p["var"])] = true
	var spread: Array = []
	for p: Dictionary in parts:
		var m: Mesh = p.mesh
		var vk: Variant = [m.surface_get_material(0), bool(p.shadow)] if m.get_surface_count() == 1 else null
		if int(p["var"]) == 0 and not bool(p.spin) and vk != null and vars.has(vk) and \
				(vars[vk] as Dictionary).has_all([1, 2, 3]):
			for k in [1, 2, 3]:
				var c := p.duplicate()
				c["var"] = k
				spread.append(c)
		else:
			spread.append(p)
	parts = spread
	var groups := {}
	var order: Array = []
	for p: Dictionary in parts:
		var m: Mesh = p.mesh
		var key: Variant = p
		if not bool(p.spin) and m.get_surface_count() == 1:
			key = [m.surface_get_material(0), int(p["var"]), bool(p.shadow)]
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		(groups[key] as Array).append(p)
	var out: Array = []
	for key: Variant in order:
		var g: Array = groups[key]
		if g.size() == 1:
			out.append(g[0])
			continue
		var st := SurfaceTool.new()
		for p: Dictionary in g:
			st.append_from(p.mesh, 0, p.xform)
		var am := st.commit()
		var first: Dictionary = g[0]
		am.surface_set_material(0, (first.mesh as Mesh).surface_get_material(0))
		out.append({"mesh": am, "xform": Transform3D(), "material": null, "var": first["var"], "spin": false,
			"shadow": first.shadow})
	return out


## Двор Var_<k>, к которому относится меш (0 — общая часть)
static func _var_of(root: Node, n: Node) -> int:
	var c := n
	while c != null and c != root:
		if String(c.name).begins_with("Var_"):
			return int(String(c.name).trim_prefix("Var_"))
		c = c.get_parent()
	return 0


static func _rel_xform(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D()
	var c: Node = n
	while c != null and c != root:
		xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf


# ================================================================= заместители

static func kit_material() -> ShaderMaterial:
	if _kit_mat == null:
		_kit_mat = ShaderMaterial.new()
		_kit_mat.shader = KIT_SHADER
		_kit_mat.set_shader_parameter("albedo_tex", load(ATLAS_PATH))
		_kit_mat.set_shader_parameter("rim_strength", RIM_STRENGTH)
	return _kit_mat


## Простой ящик (запас для арбы и т. п.)
static func box(size: Vector3, tint: Color) -> Node3D:
	var k := Kit.new()
	k.box(Vector3(0, size.y * 0.5, 0), size * 0.5, "planks", tint)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	mi.material_override = kit_material()
	return mi


## Меш заместителя типа btype (кэш); основание — y = 0, фасад — +Z, размер — size из defs
static func mesh_for(defs: Defs, btype: int) -> ArrayMesh:
	var id := defs.b_ids[btype]
	var key := "kit:" + id
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var k := Kit.new()
	var sz := defs.b_size[btype]
	var kind := defs.b_kind[btype]
	var kokand := defs.b_faction[btype] == "kokand"
	var round := defs.b_flags[btype] & Defs.BF_ROUND != 0
	match id:
		"urda": _urda(k, sz)
		"dala": _field(k, sz)
		"aryk": _aryk(k, sz)
		"togon": _dam(k, sz)
		"tegirmon":
			_house(k, sz, 5.0, true, false)
			_mill_wheel(k, sz)
		"xumdon": _kiln(k, sz)
		"bozor": _bazaar(k, sz)
		"uy": _house(k, sz, 3.4, false, false)
		"ken": _mine(k, sz)
		"kurultai": _yurt(k, sz.x * 0.5, 4.2, 3.6, "felt", true)
		"jooker": _tent(k, sz)
		"kiyiz":
			_yurt(k, minf(sz.x, sz.y) * 0.32, 2.6, 2.0, "felt_grey", false)
			_felt_rolls(k, sz)
		_:
			if kind == Defs.BKind.WALL:
				_wall_link(k, sz, kokand, id == "tosh")
			elif kind == Defs.BKind.GATE:
				_gate(k, sz, kokand)
			elif kind == Defs.BKind.TOWER:
				_tower(k, sz, kokand)
			elif kind == Defs.BKind.FIELD:
				_field(k, sz)
			elif round:
				_yurt(k, minf(sz.x, sz.y) * 0.45, 2.6, 2.4, "felt", true)
			elif kokand:
				_house(k, sz, 4.6 if sz.x * sz.y > 120.0 else 3.8, sz.x * sz.y > 100.0, true)
			else:
				_tent(k, sz)
	var m := k.commit()
	_mesh_cache[key] = m
	return m


## Леса и разметка стройки (COLOR.a = 0: видны только у стройки)
static func scaffold_mesh(defs: Defs, btype: int, height: float) -> ArrayMesh:
	var id := defs.b_ids[btype]
	var key := "scaffold:%s:%d" % [id, int(height * 10.0)]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var k := Kit.new()
	k.scaffold = true
	var wood := Color(0.62, 0.52, 0.44)
	var sz := defs.b_size[btype]
	var hx := sz.x * 0.5 + 0.6
	var hz := sz.y * 0.5 + 0.6
	var h := clampf(height * 0.95, 2.0, 12.0)
	var kind := defs.b_kind[btype]
	if kind == Defs.BKind.FIELD:
		# поле: колышки и шнур по краю
		for i in 4:
			var c := Vector3(hx if i % 2 == 0 else -hx, 0.4, hz if i < 2 else -hz)
			k.box(c, Vector3(0.06, 0.4, 0.06), "pole", wood)
		k.box(Vector3(0, 0.6, hz), Vector3(hx, 0.015, 0.015), "rope", Color(1.0, 0.95, 0.8))
		k.box(Vector3(0, 0.6, -hz), Vector3(hx, 0.015, 0.015), "rope", Color(1.0, 0.95, 0.8))
	else:
		# стойки по периметру, ярусы настила, раскосы
		var nx := maxi(2, int(sz.x / 3.0) + 1)
		var nz := maxi(2, int(sz.y / 3.0) + 1)
		for i in nx:
			var x := lerpf(-hx, hx, float(i) / (nx - 1))
			for zz: float in [-hz, hz]:
				k.box(Vector3(x, h * 0.5, zz), Vector3(0.08, h * 0.5, 0.08), "pole", wood)
		for j in nz:
			var z := lerpf(-hz, hz, float(j) / (nz - 1))
			for xx: float in [-hx, hx]:
				k.box(Vector3(xx, h * 0.5, z), Vector3(0.08, h * 0.5, 0.08), "pole", wood)
		var levels := maxi(1, int(h / 2.2))
		for lv in levels:
			var y := (lv + 1) * h / (levels + 0.4)
			k.box(Vector3(0, y, hz), Vector3(hx, 0.05, 0.35), "planks", wood)
			k.box(Vector3(0, y, -hz), Vector3(hx, 0.05, 0.35), "planks", wood)
			k.box(Vector3(hx, y, 0), Vector3(0.35, 0.05, hz), "planks", wood)
			k.box(Vector3(-hx, y, 0), Vector3(0.35, 0.05, hz), "planks", wood)
		# кучи кирпича/брёвен у стройки
		k.box(Vector3(hx + 1.2, 0.35, hz * 0.4), Vector3(0.7, 0.35, 0.5), "rough", ADOBE_DARK)
		k.box(Vector3(-hx - 1.0, 0.2, -hz * 0.3), Vector3(0.25, 0.2, 1.1), "bark", wood)
	var m := k.commit()
	_mesh_cache[key] = m
	return m


## Обломки руины: кучи глины и балки
static func rubble_mesh(defs: Defs, btype: int) -> ArrayMesh:
	var id := defs.b_ids[btype]
	var key := "rubble:" + id
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var k := Kit.new()
	var sz := defs.b_size[btype]
	var rng := BattleRng.new(id.hash() & 0xFFFF)
	var n := clampi(int(sz.x * sz.y / 12.0), 3, 14)
	for i in n:
		var c := Vector3(rng.range_f(-0.45, 0.45) * sz.x, 0.0, rng.range_f(-0.45, 0.45) * sz.y)
		var s := Vector3(rng.range_f(0.5, 1.4), rng.range_f(0.2, 0.6), rng.range_f(0.5, 1.2))
		c.y = s.y
		k.box(c, s, "rough" if defs.b_faction[btype] == "kokand" else "felt_grey", ADOBE_DARK)
	for i in 3:
		var c := Vector3(rng.range_f(-0.4, 0.4) * sz.x, 0.25, rng.range_f(-0.4, 0.4) * sz.y)
		k.box(c, Vector3(rng.range_f(1.0, 2.2), 0.09, 0.09), "bark", Color(0.4, 0.33, 0.28), rng.range_f(-1.5, 1.5))
	var m := k.commit()
	_mesh_cache[key] = m
	return m


# ---------------------------------------------------------------- Коканд

## Глинобитный дом: стены, плоская кровля на балках (торцы наружу), дверь, пояс изразцов, айван
static func _house(k: Kit, sz: Vector2, h: float, aivan: bool, tiles: bool) -> void:
	var hx := sz.x * 0.5 - 0.2
	var hz := sz.y * 0.5 - 0.2
	var porch := 1.8 if aivan else 0.0
	var body_hz := hz - porch * 0.5
	var cz := -porch * 0.5
	k.box(Vector3(0, 0.2, 0), Vector3(hx + 0.25, 0.2, hz + 0.25), "rough", ADOBE_DARK)          # цоколь
	k.box(Vector3(0, h * 0.5, cz), Vector3(hx, h * 0.5, body_hz), "adobe", ADOBE)               # стены
	k.box(Vector3(0, h + 0.12, cz), Vector3(hx + 0.35, 0.14, body_hz + 0.35), "rough", ADOBE_DARK)  # кровля
	k.box(Vector3(0, h + 0.38, cz), Vector3(hx + 0.2, 0.12, body_hz + 0.2), "rough", Color(0.85, 0.7, 0.52))
	# торцы балок под кровлей
	var nb := maxi(2, int(sz.x / 1.2))
	for i in nb:
		var x := lerpf(-hx + 0.3, hx - 0.3, float(i) / (nb - 1))
		k.box(Vector3(x, h - 0.1, cz + body_hz + 0.3), Vector3(0.09, 0.09, 0.3), "logend", WOOD)
	# дверь и окна-решётки (панджара) на фасаде
	var fz := cz + body_hz + 0.02
	k.box(Vector3(0, 1.05, fz), Vector3(0.6, 1.05, 0.04), "walnut", Color(0.85, 0.75, 0.65))
	if sz.x > 7.0:
		for sx: float in [-1.0, 1.0]:
			k.box(Vector3(sx * hx * 0.55, h * 0.55, fz), Vector3(0.45, 0.45, 0.04), "lattice", WOOD)
	if tiles:
		k.box(Vector3(0, h - 0.55, fz + 0.01), Vector3(hx - 0.2, 0.22, 0.03), "tile", Color(1, 1, 1))
	if aivan:
		# айван: резные колонны и навес над крыльцом
		var pz := cz + body_hz + porch * 0.5
		var nc := maxi(2, int(sz.x / 3.0) + 1)
		for i in nc:
			var x := lerpf(-hx + 0.3, hx - 0.3, float(i) / (nc - 1))
			k.cyl(Vector3(x, 0, pz + porch * 0.4), 0.13, 0.11, h - 0.2, 8, "walnut", WOOD)
		k.box(Vector3(0, h - 0.05, pz), Vector3(hx + 0.2, 0.12, porch * 0.55), "planks", WOOD)
		k.box(Vector3(0, h - 0.3, pz + porch * 0.5), Vector3(hx + 0.1, 0.12, 0.08), "tile", Color(1, 1, 1))


## Урда: ограда с угловыми башнями, портал-пештак с изразцами, внутренний дом с бирюзовым куполом
static func _urda(k: Kit, sz: Vector2) -> void:
	var hx := sz.x * 0.5
	var hz := sz.y * 0.5
	var wh := 4.2
	k.box(Vector3(0, 0.15, 0), Vector3(hx + 0.3, 0.15, hz + 0.3), "rough", ADOBE_DARK)
	# ограда (передняя стена — с проёмом под портал)
	k.box(Vector3(0, wh * 0.5, -hz + 0.4), Vector3(hx, wh * 0.5, 0.4), "adobe", ADOBE)
	k.box(Vector3(-hx + 0.4, wh * 0.5, 0), Vector3(0.4, wh * 0.5, hz), "adobe", ADOBE)
	k.box(Vector3(hx - 0.4, wh * 0.5, 0), Vector3(0.4, wh * 0.5, hz), "adobe", ADOBE)
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * (hx * 0.5 + 1.6), wh * 0.5, hz - 0.4), Vector3(hx * 0.5 - 1.6, wh * 0.5, 0.4), "adobe", ADOBE)
	# зубцы
	var nm := int(sz.x / 1.4)
	for i in nm:
		var x := lerpf(-hx + 0.6, hx - 0.6, float(i) / (nm - 1))
		k.box(Vector3(x, wh + 0.3, -hz + 0.4), Vector3(0.32, 0.3, 0.42), "adobe", ADOBE)
		k.box(Vector3(x * 0.98, wh + 0.3, hz - 0.4), Vector3(0.32, 0.3, 0.42), "adobe", ADOBE)
	# угловые башни-гульдаста
	for sx: float in [-1.0, 1.0]:
		for sz2: float in [-1.0, 1.0]:
			k.cyl(Vector3(sx * (hx - 0.6), 0, sz2 * (hz - 0.6)), 1.25, 1.0, wh + 1.6, 12, "adobe", ADOBE)
			k.cone(Vector3(sx * (hx - 0.6), wh + 1.6, sz2 * (hz - 0.6)), 1.15, 0.9, 12, "rough", ADOBE_DARK)
	# портал-пештак: высокий, рама из изразцов, тёмная ниша, дверь
	var pz := hz - 0.6
	k.box(Vector3(0, 4.6, pz), Vector3(3.2, 4.6, 0.9), "adobe", PLASTER)
	k.box(Vector3(0, 4.9, pz + 0.92), Vector3(2.9, 4.0, 0.03), "tile", Color(1, 1, 1))
	k.box(Vector3(0, 3.4, pz + 0.96), Vector3(1.7, 3.2, 0.03), "rough", SHADE)
	k.box(Vector3(0, 1.35, pz + 0.99), Vector3(0.95, 1.35, 0.03), "walnut", Color(0.9, 0.78, 0.62))
	for sx: float in [-1.0, 1.0]:
		k.cyl(Vector3(sx * 3.3, 0, pz + 0.7), 0.42, 0.36, 10.2, 10, "tile", Color(1, 1, 1))
	# внутренний дом и купол
	k.box(Vector3(0, 3.2, -1.8), Vector3(4.2, 3.2, 3.6), "adobe", ADOBE)
	k.cyl(Vector3(0, 6.4, -1.8), 3.0, 3.0, 1.2, 16, "tile", Color(1, 1, 1))
	k.dome(Vector3(0, 7.6, -1.8), 3.0, 2.6, 16, "tile", Color(0.95, 1.05, 1.05))
	# айван во дворе и дерево-шест флага
	k.box(Vector3(-hx + 3.5, 1.6, 2.5), Vector3(2.4, 1.6, 2.2), "adobe", ADOBE)
	k.box(Vector3(-hx + 3.5, 3.3, 2.5), Vector3(2.7, 0.12, 2.5), "planks", WOOD)
	k.cyl(Vector3(hx - 3.0, 0, 3.0), 0.08, 0.06, 9.5, 6, "pole", WOOD)
	k.box(Vector3(hx - 2.2, 8.6, 3.0), Vector3(0.8, 0.5, 0.03), "tile", Color(1, 1, 1))


## Мельничное колесо сбоку
static func _mill_wheel(k: Kit, sz: Vector2) -> void:
	var x := sz.x * 0.5 + 0.35
	k.disc_x(Vector3(x, 2.1, -0.6), 1.9, 0.35, 14, "planks", WOOD)
	k.box(Vector3(x + 0.6, 0.15, -0.6), Vector3(0.6, 0.15, 2.4), "stones", Color(0.8, 0.85, 0.95))


## Хумдон: печь-купол с трубой и навесом
static func _kiln(k: Kit, sz: Vector2) -> void:
	var hx := sz.x * 0.5 - 0.3
	var hz := sz.y * 0.5 - 0.3
	k.box(Vector3(0, 0.2, 0), Vector3(hx + 0.2, 0.2, hz + 0.2), "rough", ADOBE_DARK)
	k.cyl(Vector3(-hx * 0.35, 0, -hz * 0.2), hz * 0.75, hz * 0.7, 2.4, 14, "adobe", Color(0.95, 0.66, 0.5))
	k.dome(Vector3(-hx * 0.35, 2.4, -hz * 0.2), hz * 0.7, 1.9, 14, "adobe", Color(0.92, 0.64, 0.5))
	k.cyl(Vector3(-hx * 0.35, 3.6, -hz * 0.2), 0.55, 0.45, 3.4, 8, "rough", Color(0.9, 0.66, 0.52))
	k.box(Vector3(-hx * 0.35, 0.8, -hz * 0.2 + hz * 0.72), Vector3(0.5, 0.6, 0.05), "rough", SHADE)
	# навес и штабели кирпича
	for i in 4:
		k.cyl(Vector3(hx * 0.4 + (i % 2) * hx * 0.5, 0, (i / 2) * hz * 1.2 - hz * 0.6), 0.1, 0.09, 2.8, 6, "pole", WOOD)
	k.box(Vector3(hx * 0.65, 2.85, 0), Vector3(hx * 0.42, 0.08, hz * 0.85), "planks", WOOD)
	for i in 3:
		k.box(Vector3(hx * 0.65, 0.3 + i * 0.32, -hz * 0.3 + i * 0.4), Vector3(0.7, 0.16, 0.45), "rough", Color(0.95, 0.6, 0.45))


## Бозор: ряды лавок с навесами
static func _bazaar(k: Kit, sz: Vector2) -> void:
	var hx := sz.x * 0.5
	var hz := sz.y * 0.5
	k.box(Vector3(0, 0.1, 0), Vector3(hx, 0.1, hz), "rough", ADOBE_DARK)
	for row: float in [-1.0, 1.0]:
		for i in 4:
			var x := lerpf(-hx + 2.0, hx - 2.0, i / 3.0)
			var z := row * hz * 0.55
			k.box(Vector3(x, 1.1, z - row * 0.9), Vector3(1.6, 1.1, 0.5), "adobe", ADOBE)
			k.box(Vector3(x, 2.35, z), Vector3(1.8, 0.06, 1.3), "koshma" if i % 2 == 0 else "saddlecloth", Color(1, 0.95, 0.9))
			k.box(Vector3(x, 0.45, z + row * 0.3), Vector3(1.2, 0.45, 0.45), "planks", WOOD)
	k.box(Vector3(0, 3.0, 0), Vector3(1.3, 3.0, 1.3), "adobe", PLASTER)
	k.dome(Vector3(0, 6.0, 0), 1.3, 1.4, 12, "tile", Color(1, 1, 1))


## Поле (дала): вспаханная земля, грядки, межа
static func _field(k: Kit, sz: Vector2) -> void:
	var hx := sz.x * 0.5
	var hz := sz.y * 0.5
	k.box(Vector3(0, 0.04, 0), Vector3(hx, 0.04, hz), "rough", Color(0.62, 0.48, 0.36))
	var rows := int(sz.y / 1.1)
	for i in rows:
		var z := lerpf(-hz + 0.5, hz - 0.5, float(i) / (rows - 1))
		k.box(Vector3(0, 0.14, z), Vector3(hx - 0.5, 0.1, 0.36), "hay", Color(0.5, 0.8, 0.36))
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * hx, 0.18, 0), Vector3(0.25, 0.18, hz), "rough", ADOBE_DARK)
		k.box(Vector3(0, 0.18, sx * hz), Vector3(hx, 0.18, 0.25), "rough", ADOBE_DARK)


## Звено арыка: два вала и вода
static func _aryk(k: Kit, sz: Vector2) -> void:
	var hx := sz.x * 0.5 + 0.1
	k.box(Vector3(0, 0.02, 0), Vector3(hx, 0.03, 0.42), "stones", Color(0.42, 0.62, 0.72))
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(0, 0.12, s * 0.62), Vector3(hx, 0.12, 0.22), "rough", ADOBE_DARK)


## Тўғон: каменная плотина с затвором
static func _dam(k: Kit, sz: Vector2) -> void:
	var hx := sz.x * 0.5
	var hz := sz.y * 0.5
	k.box(Vector3(0, 0.9, 0), Vector3(hx, 0.9, hz * 0.6), "stones", Color(0.95, 0.92, 0.88))
	k.box(Vector3(0, 1.4, 0), Vector3(1.1, 1.4, hz * 0.7), "planks", WOOD)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * 1.4, 1.9, 0), Vector3(0.2, 1.9, 0.2), "pole", WOOD)
	k.box(Vector3(0, 3.7, 0), Vector3(1.6, 0.12, 0.2), "bark", WOOD)


## Звено стены: пахса (глина) или камень, зубцы поверху
static func _wall_link(k: Kit, sz: Vector2, kokand: bool, stone: bool) -> void:
	var hx := sz.x * 0.5
	var hz := sz.y * 0.5
	if kokand:
		var h := 4.2
		var reg := "stones" if stone else "adobe"
		var tint := Color(0.95, 0.92, 0.88) if stone else ADOBE
		k.box(Vector3(0, h * 0.5, 0), Vector3(hx, h * 0.5, hz), reg, tint)
		k.box(Vector3(0, h + 0.08, 0), Vector3(hx, 0.08, hz + 0.08), reg, tint * 0.9)
		for s: float in [-1.0, 1.0]:
			k.box(Vector3(s * hx * 0.5, h + 0.55, hz * 0.55), Vector3(hx * 0.3, 0.45, hz * 0.4), reg, tint)
	else:
		# частокол: заострённые брёвна
		var n := int(sz.x / 0.42)
		for i in n:
			var x := lerpf(-hx + 0.2, hx - 0.2, float(i) / maxf(n - 1, 1))
			var hh := 3.4 + 0.3 * sin(i * 2.7)
			k.cyl(Vector3(x, 0, 0), 0.21, 0.19, hh, 6, "bark", WOOD)
			k.cone(Vector3(x, hh, 0), 0.19, 0.45, 6, "logend", WOOD)
		k.box(Vector3(0, 2.4, -0.25), Vector3(hx, 0.08, 0.06), "bark", WOOD)


static func _gate(k: Kit, sz: Vector2, kokand: bool) -> void:
	var hx := sz.x * 0.5
	var hz := sz.y * 0.5
	if kokand:
		for s: float in [-1.0, 1.0]:
			k.box(Vector3(s * (hx - 0.9), 3.0, 0), Vector3(0.9, 3.0, hz + 0.3), "adobe", ADOBE)
			k.cyl(Vector3(s * (hx - 0.9), 6.0, 0), 0.9, 0.8, 0.9, 10, "rough", ADOBE_DARK)
		k.box(Vector3(0, 5.2, 0), Vector3(hx - 1.6, 0.9, hz), "adobe", ADOBE)
		k.box(Vector3(0, 5.3, hz + 0.02), Vector3(hx - 1.8, 0.45, 0.03), "tile", Color(1, 1, 1))
		k.box(Vector3(0, 2.15, 0), Vector3(hx - 1.85, 2.15, 0.12), "planks", Color(0.8, 0.62, 0.45))
	else:
		for s: float in [-1.0, 1.0]:
			for j in 2:
				k.cyl(Vector3(s * (hx - 0.5), 0, (j - 0.5) * hz), 0.25, 0.22, 5.2, 6, "bark", WOOD)
		k.box(Vector3(0, 4.6, 0), Vector3(hx, 0.2, hz * 0.7), "bark", WOOD)
		k.box(Vector3(0, 1.8, 0), Vector3(hx - 0.8, 1.8, 0.1), "planks", WOOD)


static func _tower(k: Kit, sz: Vector2, kokand: bool) -> void:
	var r := minf(sz.x, sz.y) * 0.5
	if kokand:
		k.cyl(Vector3(0, 0, 0), r, r * 0.82, 8.4, 16, "adobe", ADOBE)
		k.cyl(Vector3(0, 8.4, 0), r * 0.9, r * 0.9, 0.3, 16, "rough", ADOBE_DARK)
		var n := 10
		for i in n:
			var a := TAU * i / n
			k.box(Vector3(sin(a) * r * 0.78, 9.15, cos(a) * r * 0.78), Vector3(0.38, 0.45, 0.3), "adobe", ADOBE, a)
		k.box(Vector3(0, 7.0, r * 0.84), Vector3(0.5, 0.22, 0.05), "tile", Color(1, 1, 1))
		k.box(Vector3(0, 1.2, r * 0.97), Vector3(0.6, 1.2, 0.05), "walnut", Color(0.85, 0.72, 0.6))
	else:
		var h := 7.0
		for i in 4:
			var c := Vector3((i % 2 - 0.5) * r * 1.3, 0, (i / 2 - 0.5) * r * 1.3)
			k.cyl(c, 0.22, 0.18, h + 1.6, 6, "bark", WOOD)
		k.box(Vector3(0, h, 0), Vector3(r * 0.85, 0.12, r * 0.85), "planks", WOOD)
		for s: float in [-1.0, 1.0]:
			k.box(Vector3(0, h + 0.55, s * r * 0.8), Vector3(r * 0.8, 0.45, 0.05), "wattle", WOOD)
			k.box(Vector3(s * r * 0.8, h + 0.55, 0), Vector3(0.05, 0.45, r * 0.8), "wattle", WOOD)
		k.cone(Vector3(0, h + 1.6, 0), r * 0.9, 1.4, 8, "felt_grey", FELT)
		k.box(Vector3(0, h * 0.5, r * 0.65), Vector3(0.12, h * 0.5, 0.05), "pole", WOOD)


# ---------------------------------------------------------------- кыпчаки

## Юрта-заместитель: кереге (стена), купол-уук, красный пояс
static func _yurt(k: Kit, r: float, wall_h: float, roof_h: float, reg: String, band: bool) -> void:
	k.cyl(Vector3.ZERO, r, r, wall_h, 18, reg, FELT)
	k.dome(Vector3(0, wall_h, 0), r * 1.02, roof_h, 18, "dome", FELT)
	if band:
		k.cyl(Vector3(0, wall_h - 0.55, 0), r * 1.01, r * 1.01, 0.4, 18, "eave", Color(1, 1, 1))
	k.box(Vector3(0, 0.85, r - 0.02), Vector3(0.45, 0.85, 0.05), "door", Color(1, 1, 1))


## Шатёр/срубный дом (жоокер үйү и прочие кыпчакские)
static func _tent(k: Kit, sz: Vector2) -> void:
	var hx := sz.x * 0.5 - 0.3
	var hz := sz.y * 0.5 - 0.3
	k.box(Vector3(0, 1.1, 0), Vector3(hx, 1.1, hz), "wattle", WOOD)
	k.gable(Vector3(0, 2.2, 0), Vector3(hx + 0.4, 2.0, hz + 0.3), "felt_grey", FELT)
	k.box(Vector3(0, 0.9, hz + 0.02), Vector3(0.6, 0.9, 0.04), "door", Color(1, 1, 1))
	# стойка с оружием
	k.box(Vector3(hx * 0.6, 0.9, hz + 0.9), Vector3(1.2, 0.05, 0.05), "pole", WOOD)
	for i in 5:
		k.cyl(Vector3(hx * 0.6 - 1.0 + i * 0.5, 0, hz + 0.95), 0.03, 0.02, 2.3, 4, "pole", WOOD)


## Кен: ворот над шахтой, кучи руды, войлочный навес
static func _mine(k: Kit, sz: Vector2) -> void:
	var hx := sz.x * 0.5
	var hz := sz.y * 0.5
	k.box(Vector3(0, 0.12, 0), Vector3(hx, 0.12, hz), "stones", Color(0.85, 0.8, 0.75))
	for s: float in [-1.0, 1.0]:
		k.cyl(Vector3(s * 1.2, 0, -0.5), 0.14, 0.12, 3.2, 6, "bark", WOOD)
	k.disc_x(Vector3(0, 3.0, -0.5), 0.45, 2.2, 8, "bark", WOOD)
	k.cone(Vector3(hx * 0.5, 0.0, hz * 0.4), 1.6, 1.2, 9, "stones", Color(0.9, 0.85, 0.8))
	k.cone(Vector3(-hx * 0.45, 0.0, hz * 0.5), 1.2, 0.9, 9, "stones", Color(1.05, 0.95, 0.7))
	for i in 4:
		k.cyl(Vector3((i % 2 - 0.5) * 3.0 - hx * 0.4, 0, (i / 2 - 0.5) * 2.4 - hz * 0.35), 0.08, 0.07, 2.2, 5, "pole", WOOD)
	k.box(Vector3(-hx * 0.4, 2.25, -hz * 0.35), Vector3(1.8, 0.05, 1.5), "koshma", FELT)


static func _felt_rolls(k: Kit, sz: Vector2) -> void:
	for i in 4:
		k.disc_x(Vector3(sz.x * 0.25, 0.3, -sz.y * 0.3 + i * 0.7), 0.3, 1.6, 8, "felt_grey", FELT)
	k.box(Vector3(-sz.x * 0.28, 0.8, sz.y * 0.2), Vector3(1.4, 0.8, 0.05), "lattice", WOOD)


# ================================================================= набор частей

## Сборщик меша заместителя: части — ящики, цилиндры, купола; UV — повторы области атласа
class Kit:
	var st := SurfaceTool.new()
	var scaffold := false
	var _n := 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)

	func commit() -> ArrayMesh:
		if _n == 0:
			box(Vector3(0, 0.05, 0), Vector3(0.05, 0.05, 0.05), "rough", Color(1, 1, 1))
		st.index()
		return st.commit()

	func _region(reg: String) -> Color:
		var r: Rect2 = BuildingLook.R.get(reg, BuildingLook.R["adobe"])
		var inset := 2.0
		return Color((r.position.x + inset) / BuildingLook.A, (r.position.y + inset) / BuildingLook.A,
			maxf(r.size.x - inset * 2.0, 0.0) / BuildingLook.A, maxf(r.size.y - inset * 2.0, 0.0) / BuildingLook.A)

	func _v(p: Vector3, n: Vector3, uv: Vector2, region: Color, tint: Color) -> void:
		st.set_normal(n)
		st.set_uv(uv)
		st.set_custom(0, region)
		st.set_color(Color(tint.r, tint.g, tint.b, 0.0 if scaffold else 1.0))
		st.add_vertex(p)

	## Четырёхугольник bl, tl, tr, br (смотрим снаружи); outward — подсказка, куда наружу
	func quad(bl: Vector3, tl: Vector3, tr: Vector3, br: Vector3, reg: String, tint: Color, outward := Vector3.ZERO,
			normals: Array = []) -> void:
		var n := (br - bl).cross(tl - bl).normalized()
		if outward != Vector3.ZERO and n.dot(outward) < 0.0:
			var t1 := bl
			bl = br
			br = t1
			var t2 := tl
			tl = tr
			tr = t2
			n = -n
			if normals.size() == 4:
				normals = [normals[3], normals[2], normals[1], normals[0]]
		var m: float = BuildingLook.M.get(reg, 2.0)
		var w := bl.distance_to(br) / m
		var h := bl.distance_to(tl) / m
		var region := _region(reg)
		var ns: Array = normals if normals.size() == 4 else [n, n, n, n]
		_v(bl, ns[0], Vector2(0, h), region, tint)
		_v(tl, ns[1], Vector2(0, 0), region, tint)
		_v(tr, ns[2], Vector2(w, 0), region, tint)
		_v(bl, ns[0], Vector2(0, h), region, tint)
		_v(tr, ns[2], Vector2(w, 0), region, tint)
		_v(br, ns[3], Vector2(w, h), region, tint)
		_n += 1

	## Ящик: центр c, полуразмеры e, поворот вокруг Y
	func box(c: Vector3, e: Vector3, reg: String, tint: Color, yaw := 0.0) -> void:
		var b := Basis(Vector3.UP, yaw)
		var p := func(x: float, y: float, z: float) -> Vector3: return c + b * Vector3(x * e.x, y * e.y, z * e.z)
		var faces := [
			[Vector3(0, 0, 1), [-1, -1, 1], [-1, 1, 1], [1, 1, 1], [1, -1, 1]],
			[Vector3(0, 0, -1), [1, -1, -1], [1, 1, -1], [-1, 1, -1], [-1, -1, -1]],
			[Vector3(1, 0, 0), [1, -1, 1], [1, 1, 1], [1, 1, -1], [1, -1, -1]],
			[Vector3(-1, 0, 0), [-1, -1, -1], [-1, 1, -1], [-1, 1, 1], [-1, -1, 1]],
			[Vector3(0, 1, 0), [-1, 1, 1], [-1, 1, -1], [1, 1, -1], [1, 1, 1]],
		]
		for f: Array in faces:
			var pts: Array[Vector3] = []
			for i in range(1, 5):
				var q: Array = f[i]
				pts.append(p.call(q[0], q[1], q[2]))
			# верх чуть темнее и теплее — нарисованный свет сверху у глины не «горит»
			var t := tint * (0.92 if f[0].y > 0.5 else 1.0)
			t.a = tint.a
			quad(pts[0], pts[1], pts[2], pts[3], reg, t, b * f[0])

	## Цилиндр (усечённый конус) от основания c вверх на h
	func cyl(c: Vector3, r0: float, r1: float, h: float, sides: int, reg: String, tint: Color) -> void:
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var d0 := Vector3(sin(a0), 0, cos(a0))
			var d1 := Vector3(sin(a1), 0, cos(a1))
			var slope := (r0 - r1) / maxf(h, 0.01)
			var n0 := (d0 + Vector3(0, slope, 0)).normalized()
			var n1 := (d1 + Vector3(0, slope, 0)).normalized()
			quad(c + d0 * r0, c + d0 * r1 + Vector3(0, h, 0), c + d1 * r1 + Vector3(0, h, 0), c + d1 * r0, reg, tint,
				(d0 + d1) * 0.5, [n0, n0, n1, n1])
		# крышка
		var top := c + Vector3(0, h, 0)
		var region := _region(reg)
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			tri(top, top + Vector3(sin(a0), 0, cos(a0)) * r1, top + Vector3(sin(a1), 0, cos(a1)) * r1, Vector3.UP,
				[Vector2(0.5, 0.5), Vector2(0.5 + sin(a0) * 0.5, 0.5 + cos(a0) * 0.5), Vector2(0.5 + sin(a1) * 0.5, 0.5 + cos(a1) * 0.5)],
				region, tint * 0.9)
		_n += 1

	## Треугольник наружу по n (порядок вершин подбирается сам)
	func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, uvs: Array, region: Color, tint: Color) -> void:
		if (c - a).cross(b - a).dot(n) < 0.0:
			var t := b
			b = c
			c = t
			uvs = [uvs[0], uvs[2], uvs[1]]
		_v(a, n, uvs[0], region, tint)
		_v(b, n, uvs[1], region, tint)
		_v(c, n, uvs[2], region, tint)

	## Конус от основания c радиуса r, высота h
	func cone(c: Vector3, r: float, h: float, sides: int, reg: String, tint: Color) -> void:
		cyl(c, r, 0.02, h, sides, reg, tint)

	## Купол (полусфера, сжатая по высоте h)
	func dome(c: Vector3, r: float, h: float, sides: int, reg: String, tint: Color) -> void:
		var rings := 5
		for j in rings:
			var t0 := float(j) / rings * PI * 0.5
			var t1 := float(j + 1) / rings * PI * 0.5
			var ra := cos(t0) * r
			var rb := cos(t1) * r
			var ya := sin(t0) * h
			var yb := sin(t1) * h
			for i in sides:
				var a0 := TAU * i / sides
				var a1 := TAU * (i + 1) / sides
				var d0 := Vector3(sin(a0), 0, cos(a0))
				var d1 := Vector3(sin(a1), 0, cos(a1))
				var na := func(d: Vector3, t: float) -> Vector3: return (d * cos(t) / r + Vector3(0, sin(t) / h, 0)).normalized()
				quad(c + d0 * ra + Vector3(0, ya, 0), c + d0 * rb + Vector3(0, yb, 0), c + d1 * rb + Vector3(0, yb, 0),
					c + d1 * ra + Vector3(0, ya, 0), reg, tint, (d0 + d1) * 0.5 + Vector3(0, 0.3, 0),
					[na.call(d0, t0), na.call(d0, t1), na.call(d1, t1), na.call(d1, t0)])

	## Двускатная кровля над c (полуразмеры e: x — вдоль конька, y — высота, z — полуширина)
	func gable(c: Vector3, e: Vector3, reg: String, tint: Color) -> void:
		var ridge0 := c + Vector3(-e.x, e.y, 0)
		var ridge1 := c + Vector3(e.x, e.y, 0)
		for s: float in [-1.0, 1.0]:
			var eave0 := c + Vector3(-e.x, 0, s * e.z)
			var eave1 := c + Vector3(e.x, 0, s * e.z)
			quad(eave0, ridge0, ridge1, eave1, reg, tint, Vector3(0, 0.5, s))
		var region := _region(reg)
		for s: float in [-1.0, 1.0]:
			var a := c + Vector3(s * e.x, 0, -e.z)
			var b := c + Vector3(s * e.x, 0, e.z)
			var t := c + Vector3(s * e.x, e.y, 0)
			tri(a, t, b, Vector3(s, 0, 0), [Vector2(0, 1), Vector2(0.5, 0), Vector2(1, 1)], region, tint)
		_n += 1

	## Диск-колесо с осью X (центр c, радиус r, толщина w)
	func disc_x(c: Vector3, r: float, w: float, sides: int, reg: String, tint: Color) -> void:
		var region := _region(reg)
		var hx := Vector3(w * 0.5, 0, 0)
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var d0 := Vector3(0, sin(a0), cos(a0))
			var d1 := Vector3(0, sin(a1), cos(a1))
			quad(c + d0 * r - hx, c + d0 * r + hx, c + d1 * r + hx, c + d1 * r - hx, reg, tint, (d0 + d1) * 0.5)
			for s: float in [-1.0, 1.0]:
				var o := c + hx * s
				tri(o, o + d0 * r, o + d1 * r, Vector3(s, 0, 0),
					[Vector2(0.5, 0.5), Vector2(0.5 + d0.y * 0.5, 0.5 + d0.z * 0.5), Vector2(0.5 + d1.y * 0.5, 0.5 + d1.z * 0.5)],
					region, tint * 0.9)
