class_name CityRoundel
extends Control
## Круглый медальон: диск цвета стороны в латунном ободке, на нём золочёная эмблема (портрет рода
## войск или постройки до рендеров моделей).

var color := Color("#2f8f74")
var icon: Texture2D


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	draw_circle(c + Vector2(1.5, 2.5), r, Color(0.08, 0.04, 0.02, 0.45))
	draw_circle(c, r, Color("#7a5422"))
	draw_circle(c, r - 2.0, Color("#c49a48"))
	draw_circle(c, r - 4.5, Color("#3e2a12"))
	draw_circle(c, r - 5.5, color.darkened(0.25))
	draw_circle(c + Vector2(0, -r * 0.25), r * 0.55, Color(color.lightened(0.15), 0.35))
	if icon:
		var s := (r - 7.0) * 1.55
		draw_texture_rect(icon, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false)
