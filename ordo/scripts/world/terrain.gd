class_name Terrain
extends RefCounted
## Высота земли для симуляции, расстановки и камеры.
## Заглушка: плоская земля. Владелец — мир (scripts/world/*); API не менять:
##   Terrain.height_at(x, z) -> float      высота земли, м
##   Terrain.normal_at(x, z) -> Vector3    нормаль земли
##   Terrain.is_water(x, z) -> bool        вода (брод, река)


static func height_at(_x: float, _z: float) -> float:
	return 0.0


static func normal_at(_x: float, _z: float) -> Vector3:
	return Vector3.UP


static func is_water(_x: float, _z: float) -> bool:
	return false
