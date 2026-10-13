class_name CityBar
extends Control
## Полоска (здоровье, мораль, выносливость, ход стройки): тёмный жёлоб с латунной кромкой,
## заливка цветом с бликом сверху. value 0..1.

var color := Color("#b8382a")
var value := 1.0:
	set(v):
		v = clampf(v, 0.0, 1.0)
		if not is_equal_approx(v, value):
			value = v
			queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.13, 0.08, 0.04, 0.85))
	if value > 0.0:
		var f := Rect2(Vector2(1, 1), Vector2((size.x - 2) * value, size.y - 2))
		draw_rect(f, color)
		draw_rect(Rect2(f.position, Vector2(f.size.x, maxf(1.0, f.size.y * 0.35))), color.lightened(0.35))
	draw_rect(r, Color(0.72, 0.54, 0.24, 0.9), false, 1.0)
