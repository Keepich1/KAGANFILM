extends Node
## Портреты родов войск для карточек и кнопок найма (ARCHITECTURE §19.6: «портреты из моделей»):
## каждый вид толпы (UnitRegistry) в своём SubViewport — плечи и голова (всадник — с конём) на прозрачном
## фоне, тёплый ключевой свет заката, холодное заполнение, контровой. Результат — assets/ui/portraits/<вид>.png.
##   tools/godot.sh --path ordo --audio-driver Dummy --fixed-fps 30 res://scenes/test/ui_portraits.tscn
## Нет вида у рода (UnitStats.visual "") — интерфейс берёт рисованную эмблему (UiTheme.unit_icon).
## Постройки — так же из моделей сторон (scenes/kokand/<id>.tscn, scenes/kipchak2/<id>.tscn, assets/models/kipchak;
## есть в главной ветке после слияния арта): готовое здание в три четверти сверху → assets/ui/portraits/bld_<id постройки>.png
## (медальон панели здания). Сцены нет — портрета нет, медальон берёт гравированный значок.

const OUT := "res://assets/ui/portraits/"
const SIZE := 192
const IDS := ["kok_sarboz", "kok_yuzboshi", "kip_sayisker", "kip_kolbashchy", "kip_jooker", "kip_malchy"]
## id постройки (Defs) → сцена модели
const BUILDINGS := {
	"urda": "res://scenes/kokand/urda.tscn", "uy": "res://scenes/kokand/uy.tscn",
	"tegirmon": "res://scenes/kokand/tegirmon.tscn", "ombor": "res://scenes/kokand/ombor.tscn",
	"togon": "res://scenes/kokand/tugon.tscn", "xumdon": "res://scenes/kokand/xumdon.tscn",
	"bozor": "res://scenes/kokand/bozor.tscn", "kazarma": "res://scenes/kokand/kazarma.tscn",
	"otxona": "res://scenes/kokand/otxona.tscn", "topxona": "res://scenes/kokand/topxona.tscn",
	"darvoza": "res://scenes/kokand/darvoza.tscn", "burj": "res://scenes/kokand/burj.tscn",
	"jooker": "res://scenes/kipchak2/jooker.tscn", "ken": "res://scenes/kipchak2/ken.tscn",
	"kurultai": "res://scenes/kipchak2/kurultai.tscn", "munara": "res://scenes/kipchak2/munara.tscn",
	"darbaza": "res://scenes/kipchak2/darbaza.tscn", "chep": "res://scenes/kipchak2/chep.tscn",
	"devor": "res://scenes/kokand/devor.tscn", "tosh": "res://scenes/kokand/tosh.tscn",
	# у ставки и юрты кыпчаков сцен-обёрток нет — сами модели
	"ordo": "res://assets/models/kipchak/ordo.glb", "boz": "res://assets/models/kipchak/boz.glb"}
## Плоское (поле, арык, загоны короо и жылкы) в медальоне не читается — у них остаётся гравированный значок

var _vps: Array[SubViewport] = []
var _frames := 0


func _ready() -> void:
	print("[портрет] начало, видов: ", IDS.size())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for id in IDS:
		_vps.append(_stage(id))
	for id: String in BUILDINGS:
		if ResourceLoader.exists(BUILDINGS[id]):
			_vps.append(_stage_building(id, BUILDINGS[id]))


## Свет и окружение портрета (одни на юниты и постройки)
func _lights(vp: SubViewport) -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#4a7fa0")
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#ffc890")
	key.light_energy = 1.6
	key.rotation_degrees = Vector3(-28, -40, 0)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("#ffcf8a")
	rim.light_energy = 0.9
	rim.rotation_degrees = Vector3(-15, 160, 0)
	vp.add_child(rim)


## Постройка: готовая модель без дыма и пятна земли, камера в три четверти сверху по её габаритам
func _stage_building(id: String, path: String) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = "bld_" + id
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	_lights(vp)
	var b := (load(path) as PackedScene).instantiate() as Node3D
	for prop in ["smoke", "ground_decal", "snap"]:
		if prop in b:
			b.set(prop, false)
	if "lod_distance" in b:
		b.set("lod_distance", 1.0e6)
	vp.add_child(b)
	var box := _bounds(b)
	var c := box.get_center()
	var rad := maxf(box.size.length() * 0.5, 1.0)
	var cam := Camera3D.new()
	cam.fov = 26.0
	var yaw := deg_to_rad(32.0)
	var pitch := deg_to_rad(30.0)
	var dist := rad / sin(deg_to_rad(cam.fov * 0.5)) * 0.92
	cam.position = c + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	vp.add_child(cam)
	cam.look_at(c, Vector3.UP)
	cam.current = true
	return vp


## Габариты всех сеток узла (в мировых осях)
func _bounds(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for vi in n.find_children("*", "VisualInstance3D", true, false):
		var v := vi as VisualInstance3D
		if not v.visible or v is Decal or v is GPUParticles3D:
			continue
		var a := v.global_transform * v.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


func _stage(id: String) -> SubViewport:
	var info := UnitRegistry.info(id)
	var vp := SubViewport.new()
	vp.name = id
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#4a7fa0")
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#ffc890")
	key.light_energy = 1.6
	key.rotation_degrees = Vector3(-28, -40, 0)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("#ffcf8a")
	rim.light_energy = 0.9
	rim.rotation_degrees = Vector3(-15, 160, 0)
	vp.add_child(rim)
	var layer := CrowdLayer.new()
	vp.add_child(layer)
	layer.setup(id, 1)
	var skel := String(info.get("skeleton", "human"))
	var state: int = AnimSpec.Horse.IDLE if skel == "rider" else AnimSpec.Human.IDLE
	layer.set_instance(0, Transform3D(Basis(Vector3.UP, deg_to_rad(-20.0)), Vector3.ZERO), AnimSpec.custom(state, 0.3, 0.0, 0.0))
	layer.set_visible_count(1)
	var h := float(info.get("height", 2.0))
	var cam := Camera3D.new()
	cam.fov = 30.0
	var target := Vector3(0, h * (0.8 if skel == "human" else 0.7), 0)
	var dist := h * (1.15 if skel == "human" else 1.75)
	cam.position = target + Vector3(sin(deg_to_rad(18.0)), 0.18, cos(deg_to_rad(18.0))) * dist
	vp.add_child(cam)
	cam.look_at(target, Vector3.UP)
	cam.current = true
	return vp


func _process(_delta: float) -> void:
	_frames += 1
	print("[портрет] кадр ", _frames)
	if _frames < 8:
		return
	set_process(false)
	await RenderingServer.frame_post_draw
	for vp in _vps:
		var img := vp.get_texture().get_image()
		var path := ProjectSettings.globalize_path(OUT + vp.name + ".png")
		print("[портрет] ", vp.name, " ", img.get_size(), " err=", img.save_png(path))
	# все картинки уже на диске; на программном Vulkan (lavapipe) выход после голых .glb кыпчаков
	# иногда виснет — запускать с timeout, результат от этого не страдает
	print("[портрет] готово: ", _vps.size())
	get_tree().quit()
