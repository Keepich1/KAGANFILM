class_name CityPost
extends Control
## Резной ореховый столб между частями нижней панели: фаска, желобок, латунные шапки с заклёпкой.

const WOOD := Color("#4a2f1c")
const DARK := Color("#24140b")
const LIGHT := Color("#8a6040")
const BRASS := Color("#c49a48")
const BRASS_HI := Color("#f2d68a")
const BRASS_LO := Color("#7a5422")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(2, 0, w + 2, h), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(0, 0, w, h), WOOD)
	draw_rect(Rect2(0, 0, 2, h), LIGHT)
	draw_rect(Rect2(w - 2, 0, 2, h), DARK)
	draw_line(Vector2(w * 0.5, 14), Vector2(w * 0.5, h - 14), DARK, 2.0)
	draw_line(Vector2(w * 0.5 + 1.5, 14), Vector2(w * 0.5 + 1.5, h - 14), Color(LIGHT, 0.6), 1.0)
	for y in [0.0, h - 10.0]:
		draw_rect(Rect2(-2, y, w + 4, 10), BRASS_LO)
		draw_rect(Rect2(-1, y + 1, w + 2, 4), BRASS)
		draw_rect(Rect2(-1, y + 1, w + 2, 1), BRASS_HI)
	for y in [h * 0.33, h * 0.66]:
		draw_circle(Vector2(w * 0.5, y), 3.4, BRASS_LO)
		draw_circle(Vector2(w * 0.5 - 0.6, y - 0.6), 2.4, BRASS)
		draw_circle(Vector2(w * 0.5 - 1.0, y - 1.2), 1.0, BRASS_HI)
