extends Node
## Портреты родов войск для карточек и кнопок найма (ARCHITECTURE §19.6: «портреты из моделей»):
## каждый вид толпы (UnitRegistry) в своём SubViewport — плечи и голова (всадник — с конём) на прозрачном
## фоне, тёплый ключевой свет заката, холодное заполнение, контровой. Результат — assets/ui/portraits/<вид>.png.
##   tools/godot.sh --path ordo --audio-driver Dummy --fixed-fps 30 res://scenes/test/ui_portraits.tscn
## Нет вида у рода (UnitStats.visual "") — интерфейс берёт рисованную эмблему (UiTheme.unit_icon).

const OUT := "res://assets/ui/portraits/"
const SIZE := 192
const IDS := ["kok_sarboz", "kok_yuzboshi", "kip_sayisker", "kip_kolbashchy", "kip_jooker", "kip_malchy"]

var _vps: Array[SubViewport] = []
var _frames := 0


func _ready() -> void:
	print("[портрет] начало, видов: ", IDS.size())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for id in IDS:
		_vps.append(_stage(id))


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
	get_tree().quit()
