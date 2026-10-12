class_name KokandWallLine
extends RefCounted
## Линия стены Коканда из звеньев (ТЗ 6, 11.6): tosh (кирпич) или devor (пахса).
##
##   KokandWallLine.place(town, Vector3(-40, 0, 30), Vector3(40, 0, 30), "tosh")
##
## Звено 3,6 м, шаг 3,2 м (перекрытие 0,4). Длина линии L делится на n = ceil(L / 3,2) звеньев,
## шаг s = L / n, звенья растягиваются по своей оси X на s / 3,2 — рисунок кирпича и зубцы
## в линии идут ровно, без швов. На концах — круглые столбы <kind>_end (ends = true).
## Наружная сторона (зубцы, +Z звена) — справа по ходу a→b, если смотреть сверху (север вверху):
## для замкнутого обвода наружу обходите его против часовой стрелки (на виде сверху).

const STEP := 3.2
const SCENES := "res://scenes/kokand/"


## Ставит звенья в parent; возвращает созданные узлы (звенья, затем столбы).
## snap — каждое звено встаёт на землю мира (Terrain.height_at) при добавлении в дерево.
static func place(parent: Node3D, a: Vector3, b: Vector3, kind := "tosh", state := "built", ends := true,
		name_prefix := "", snap := false) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := d.length()
	if length < 0.5:
		return out
	var n := maxi(1, ceili(length / STEP - 0.001))
	var s := length / float(n)
	var dir := d / length
	var yaw := atan2(-dir.z, dir.x)
	var seg_scene := load(SCENES + kind + ".tscn") as PackedScene
	var prefix := name_prefix if name_prefix != "" else kind.capitalize().replace(" ", "")
	for i in n:
		var w := seg_scene.instantiate() as Node3D
		w.name = "%s_%d" % [prefix, i + 1]
		w.set("state", state)
		w.set("snap", snap)
		var p := a + dir * (s * (float(i) + 0.5))
		w.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(s / STEP, 1.0, 1.0)), p)
		parent.add_child(w)
		out.append(w)
	if ends:
		var end_scene := load(SCENES + kind + "_end.tscn") as PackedScene
		for k in 2:
			var e := end_scene.instantiate() as Node3D
			e.name = "%sEnd_%d" % [prefix, k + 1]
			e.set("state", state)
			e.set("snap", snap)
			e.transform = Transform3D(Basis(Vector3.UP, yaw), a if k == 0 else b)
			parent.add_child(e)
			out.append(e)
	return out


## Сколько звеньев нужно на линию длиной length (для цены: 3 дерева / 8 камня за звено, ТЗ 6).
static func segment_count(length: float) -> int:
	return maxi(1, ceili(length / STEP - 0.001))
