extends Node3D
## Проверочная сцена мира (scenes/test/world_look.tscn): камеры для кадров и заглушки —
## юрты лагеря (цилиндр + конус) и два отряда на поле, чтобы судить о читаемости (ТЗ 11.2).
##
## tools/shot.sh res://scenes/test/world_look.tscn out.png --cam=CamSunward --at=3

const SURFACE := preload("res://shaders/painterly_surface.gdshader")

## Ставить заглушки лагеря и отрядов
@export var stand_ins := true


func _ready() -> void:
	_place_cameras()
	if stand_ins:
		_build_camp()
		_build_squads()


func _cam(name: String, from: Vector3, to: Vector3, fov: float) -> void:
	var cam := get_node_or_null(name) as Camera3D
	if cam == null:
		return
	cam.position = from
	cam.look_at(to, Vector3.UP)
	cam.fov = fov
	cam.far = 6000.0
	cam.near = 0.3


func _place_cameras() -> void:
	var g := func(x: float, z: float, up: float) -> Vector3:
		return Vector3(x, Terrain.height_at(x, z) + up, z)
	# Вид стратегии: ~50° вниз, ~80 м над лугом, смотрит на север
	var m: Vector3 = g.call(90.0, 0.0, 0.0)
	_cam("CamMeadow", m + Vector3(0, 80, 67), m, 42.0)
	# Против солнца через лагерь: подсвеченная трава, дымка, лучи
	_cam("CamSunward", g.call(24.0, -24.0, 3.2), g.call(-80.0, 22.0, 6.5), 46.0)
	# Брод: вода, деревья, отражение заката
	_cam("CamFord", g.call(78.0, -146.0, 4.5), g.call(-40.0, -172.0, 1.0), 50.0)
	# Общий план с горами
	_cam("CamPanorama", g.call(330.0, 230.0, 70.0), g.call(-120.0, -170.0, 10.0), 52.0)


func _mat(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SURFACE
	m.set_shader_parameter("albedo_tint", color)
	return m


func _build_camp() -> void:
	var root := Node3D.new()
	root.name = "CampStandIns"
	add_child(root)
	var felt := _mat(Color(0.9, 0.86, 0.77))
	var red := _mat(Color(0.69, 0.22, 0.18))
	var wood := _mat(Color(0.35, 0.23, 0.14))
	var c := Terrain.marker("camp")
	# ханская юрта в центре и 9 юрт кольцом
	var spots: Array[Vector3] = [Vector3(c.x, 0, c.z)]
	for k in 9:
		var a := TAU * k / 9.0 + 0.3
		spots.append(Vector3(c.x + cos(a) * 38.0, 0, c.z + sin(a) * 38.0))
	for i in spots.size():
		var p := spots[i]
		var big := i == 0
		var r := 7.0 if big else 3.5
		var y := Terrain.height_at(p.x, p.z)
		var wall := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = r
		cy.bottom_radius = r
		cy.height = r * 0.5
		cy.radial_segments = 24
		wall.mesh = cy
		wall.material_override = felt
		wall.position = Vector3(p.x, y + r * 0.25, p.z)
		root.add_child(wall)
		var roof := MeshInstance3D.new()
		var cn := CylinderMesh.new()
		cn.top_radius = r * 0.12
		cn.bottom_radius = r * 1.02
		cn.height = r * 0.45
		cn.radial_segments = 24
		roof.mesh = cn
		roof.material_override = felt
		roof.position = Vector3(p.x, y + r * 0.5 + r * 0.225, p.z)
		root.add_child(roof)
	# древко с вымпелом у входа в ставку
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.06
	pm.bottom_radius = 0.08
	pm.height = 9.0
	pole.mesh = pm
	pole.material_override = wood
	var pp := Vector3(c.x + 4.0, 0, c.z + 11.0)
	pole.position = Vector3(pp.x, Terrain.height_at(pp.x, pp.z) + 4.5, pp.z)
	root.add_child(pole)
	var flag := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(2.6, 1.0, 0.05)
	flag.mesh = fb
	flag.material_override = red
	flag.position = pole.position + Vector3(1.35, 3.6, 0)
	root.add_child(flag)


func _build_squads() -> void:
	var root := Node3D.new()
	root.name = "SquadStandIns"
	add_child(root)
	# кыпчакская тяжёлая конница: киноварь, белый войлок
	var kip := _mat(Color(0.69, 0.22, 0.18))
	var kip_felt := _mat(Color(0.9, 0.86, 0.77))
	var horse := _mat(Color(0.42, 0.25, 0.15))
	for row in 2:
		for i in 10:
			var x := 45.0 + row * 4.0
			var z := -18.0 + i * 3.6
			var y := Terrain.height_at(x, z)
			var body := MeshInstance3D.new()
			var bm := CapsuleMesh.new()
			bm.radius = 0.55
			bm.height = 2.4
			body.mesh = bm
			body.material_override = horse
			body.rotation_degrees = Vector3(90, 0, 90)
			body.position = Vector3(x, y + 1.3, z)
			root.add_child(body)
			var rider := MeshInstance3D.new()
			var rm := CapsuleMesh.new()
			rm.radius = 0.32
			rm.height = 1.3
			rider.mesh = rm
			rider.material_override = kip if (i + row) % 3 != 0 else kip_felt
			rider.position = Vector3(x, y + 2.3, z)
			root.add_child(rider)
	# кокандские стрелки: бирюза с золотом, линия
	var kok := _mat(Color(0.18, 0.56, 0.45))
	for i in 24:
		var x := 128.0 + (i % 2) * 1.6
		var z := -20.0 + i * 1.7
		var y := Terrain.height_at(x, z)
		var man := MeshInstance3D.new()
		var mm := CapsuleMesh.new()
		mm.radius = 0.3
		mm.height = 1.75
		man.mesh = mm
		man.material_override = kok
		man.position = Vector3(x, y + 0.875, z)
		root.add_child(man)
