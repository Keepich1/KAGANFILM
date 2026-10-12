@tool
class_name CampArea
extends Marker3D
## Метка области лагеря для других областей: загон (SheepPen), конный двор (HorsePen).
## Центр — позиция метки, size — внутренний размер в метрах по локальным X и Z
## (повёрнут вместе с меткой). Вход — в сторону локального +Z.

@export var size := Vector2(12, 12)


## Случайная точка внутри области (в мировых координатах), u, v — 0..1.
func point_at(u: float, v: float) -> Vector3:
	var local := Vector3((u - 0.5) * size.x, 0.0, (v - 0.5) * size.y)
	return global_transform * local


## Лежит ли мировая точка внутри области (по плану, без учёта высоты).
func contains(world: Vector3) -> bool:
	var p := global_transform.affine_inverse() * world
	return absf(p.x) <= size.x * 0.5 and absf(p.z) <= size.y * 0.5
