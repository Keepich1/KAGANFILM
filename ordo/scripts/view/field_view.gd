class_name FieldView
extends Node
## Поля карты (ARCHITECTURE §13): трава и полив «Города».
##
## Маска травы R8 на всю карту, 4 м на пиксель (= клетка навигации): 0 под постройками, звеньями
## и полями, иначе — значение травы GameQuery.grass() (16 м, вытоптанное пастбище реже и ниже).
## Отдаётся GrassField.set_mask (согласованная правка Мира) — вместо 48 полян среза.
## Обновление не чаще раза в секунду и только если что-то изменилось (постройки, трава).
## Поля (дала) с поливом — сочная зелень, «лалми» — сухие (instance uniform «wet» у BuildingView).

@export var driver_path: NodePath = ^"../../Driver"
@export var grass_path: NodePath = ^"../../World/Grass"
@export var buildings_path: NodePath = ^"../Buildings"
## Как часто сверять, с
@export var period := 1.0

var query: GameQuery
var mask: Image
var mask_tex: ImageTexture
var updates := 0

var _grass: GrassField
var _buildings: BuildingView
var _t := 0.0
var _sig := 0


func _ready() -> void:
	_grass = get_node_or_null(grass_path) as GrassField
	_buildings = get_node_or_null(buildings_path) as BuildingView
	var d := get_node_or_null(driver_path)
	if d and d.has_signal("started"):
		d.connect("started", func(_s: int) -> void: set_query(CityView.query_of(d)))
	if CityView.query_of(d):
		set_query(CityView.query_of(d))


func set_query(q: GameQuery) -> void:
	query = q
	_sig = 0
	_t = period


func _process(delta: float) -> void:
	if query == null:
		return
	_t += delta
	if _t < period:
		return
	_t = 0.0
	var t0 := CityView.now_usec()
	refresh()
	CityView.mark(&"view_fields", t0)


## Пересобрать маску, если изменились постройки или трава
func refresh(force := false) -> void:
	var bt := query.buildings()
	var g := query.grass()
	var sig := hash([bt.state, bt.gen, bt.hw, g])
	if sig != _sig or force:
		_sig = sig
		build_mask()
		updates += 1
	_update_fields()


func build_mask() -> void:
	var dims := query.field_dims()
	var size := Terrain.size()
	var span := (size - 1) * Terrain.spacing()          # 1024 м
	var n := int(span / NavApi.CELL)                    # 256 пикселей
	var g := query.grass()
	var img: Image
	if g.size() == dims.x * dims.y and dims.x > 0:
		img = Image.create_from_data(dims.x, dims.y, false, Image.FORMAT_L8, g)
		img.resize(n, n, Image.INTERPOLATE_BILINEAR)
	else:
		img = Image.create(n, n, false, Image.FORMAT_L8)
		img.fill(Color(1, 1, 1))
	img.convert(Image.FORMAT_R8)
	# под постройками и полями травы нет
	var bt := query.buildings()
	var bare := Color(0, 0, 0)
	for b in bt.hw:
		var st := bt.state[b]
		if st == BuildingTable.State.FREE or st == BuildingTable.State.PACKED:
			continue
		# клетки навигации — те же 4 м от того же начала карты
		var r := Rect2i(bt.c0[b], bt.r0[b], bt.cw[b], bt.ch[b]).intersection(Rect2i(0, 0, n, n))
		if r.size.x > 0 and r.size.y > 0:
			img.fill_rect(r, bare)
	mask = img
	if mask_tex == null:
		mask_tex = ImageTexture.create_from_image(img)
	else:
		mask_tex.update(img)
	if _grass:
		_grass.set_mask(mask_tex)


## Полив у полей: доля воды под центром поля
func _update_fields() -> void:
	if _buildings == null:
		return
	var bt := query.buildings()
	var defs := query.defs()
	var w := query.water()
	var dims := query.field_dims()
	for b in bt.hw:
		if bt.state[b] == BuildingTable.State.FREE or bt.btype[b] < 0:
			continue
		if defs.b_kind[bt.btype[b]] != Defs.BKind.FIELD:
			continue
		var node := _buildings.node_of(b)
		if node == null:
			continue
		var k := water_at(w, dims, Vector2(bt.x[b], bt.z[b]))
		for mi in node.find_children("*", "GeometryInstance3D", true, false):
			(mi as GeometryInstance3D).set_instance_shader_parameter("wet", k)


## Вода (GameQuery.water, 0..1) в точке p: сетка ww × wh на всю карту (Terrain.origin, размер)
static func water_at(w: PackedByteArray, dims: Vector4i, p: Vector2) -> float:
	if dims.z <= 0 or w.size() < dims.z * dims.w:
		return 1.0
	var o := Terrain.origin()
	var span := (Terrain.size() - 1) * Terrain.spacing()
	var i := clampi(int((p.x - o.x) / span * dims.z), 0, dims.z - 1)
	var j := clampi(int((p.y - o.y) / span * dims.w), 0, dims.w - 1)
	return w[j * dims.z + i] / 255.0
