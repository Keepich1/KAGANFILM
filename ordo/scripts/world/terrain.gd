class_name Terrain
extends RefCounted
## Высота земли для симуляции, расстановки и камеры. Владелец — мир (scripts/world/*).
## API (не менять):
##   Terrain.height_at(x, z) -> float      высота земли, м (билинейно по сетке 2 м)
##   Terrain.normal_at(x, z) -> Vector3    нормаль земли
##   Terrain.is_water(x, z) -> bool        вода (река, брод)
## Дополнительно:
##   Terrain.water_depth(x, z) -> float    глубина воды, м (0 на суше; у брода ≈0,3)
##   Terrain.water_level() -> float        уровень воды в реке, м
##   Terrain.marker(имя) -> Vector3        метки карты: camp, koroo, jylky, meadow, ford
##   Terrain.info() -> Dictionary          заголовок assets/world/height.json (река, тропы, размеры)
##   Terrain.position_on_ground(x, z) -> Vector3
##
## Данные: assets/world/height.bin (float32, строки по z с севера на юг) + height.json.
## Делает tools/gen_world.py. Читаются один раз через FileAccess (работает без монитора
## и в экспорте; в пресете экспорта нужен фильтр «*.bin, *.json»).

const DATA_DIR := "res://assets/world/"

static var _loaded := false
static var _h := PackedFloat32Array()
static var _n := 0
static var _spacing := 2.0
static var _ox := -512.0
static var _oz := -512.0
static var _water := -4.0
static var _info: Dictionary = {}
static var _tex: ImageTexture


static func height_at(x: float, z: float) -> float:
	_ensure()
	if _n == 0:
		return 0.0
	var fx := clampf((x - _ox) / _spacing, 0.0, _n - 1.001)
	var fz := clampf((z - _oz) / _spacing, 0.0, _n - 1.001)
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	var k := j * _n + i
	var a := lerpf(_h[k], _h[k + 1], u)
	var b := lerpf(_h[k + _n], _h[k + _n + 1], u)
	return lerpf(a, b, v)


static func normal_at(x: float, z: float) -> Vector3:
	var e := _spacing
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hn := height_at(x, z - e)
	var hs := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hn - hs).normalized()


static func is_water(x: float, z: float) -> bool:
	return water_depth(x, z) > 0.05


static func water_depth(x: float, z: float) -> float:
	_ensure()
	return maxf(_water - height_at(x, z), 0.0)


static func water_level() -> float:
	_ensure()
	return _water


static func position_on_ground(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


static func marker(name: String) -> Vector3:
	_ensure()
	var m: Array = _info.get("markers", {}).get(name, [0.0, 0.0, 0.0])
	return Vector3(m[0], m[1], m[2])


static func info() -> Dictionary:
	_ensure()
	return _info


## Сырые высоты (для построения сетки земли): size × size, шаг spacing().
static func heights() -> PackedFloat32Array:
	_ensure()
	return _h


static func size() -> int:
	_ensure()
	return _n


static func spacing() -> float:
	_ensure()
	return _spacing


static func origin() -> Vector2:
	_ensure()
	return Vector2(_ox, _oz)


## Высоты как текстура (FORMAT_RF) — для травы и шейдеров на видеокарте.
## UV = (x − origin.x) / (size − 1) / spacing … то есть узлы сетки в центрах текселей.
static func height_texture() -> ImageTexture:
	_ensure()
	if _tex == null and _n > 0:
		var img := Image.create_from_data(_n, _n, false, Image.FORMAT_RF, _h.to_byte_array())
		_tex = ImageTexture.create_from_image(img)
	return _tex


## Читает дополнительный двоичный файл float32 рядом с height.bin (например, far.bin).
static func read_floats(file_name: String) -> PackedFloat32Array:
	var f := FileAccess.open(DATA_DIR + file_name, FileAccess.READ)
	if f == null:
		push_warning("Terrain: нет файла %s%s" % [DATA_DIR, file_name])
		return PackedFloat32Array()
	return f.get_buffer(f.get_length()).to_float32_array()


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(DATA_DIR + "height.json", FileAccess.READ)
	if f == null:
		push_warning("Terrain: нет assets/world/height.json — земля плоская (запустите tools/gen_world.py)")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		push_warning("Terrain: height.json не читается")
		return
	_info = parsed
	_n = int(_info.get("size", 0))
	_spacing = float(_info.get("spacing", 2.0))
	var o: Array = _info.get("origin", [-512.0, -512.0])
	_ox = float(o[0])
	_oz = float(o[1])
	_water = float(_info.get("water_level", -4.0))
	_h = read_floats(String(_info.get("files", {}).get("height", "height.bin")))
	if _h.size() != _n * _n:
		push_warning("Terrain: размер height.bin не совпадает с заголовком")
		_n = 0
