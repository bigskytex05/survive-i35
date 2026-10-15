class_name StatBar
extends Control
## A garage stat as a row of chunky segments (0..1 fills 0..SEGMENTS).

const SEGMENTS := 10

var value := 0.5:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(200, 16)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var gap := 4.0
	var w := (size.x - gap * (SEGMENTS - 1)) / SEGMENTS
	var filled := maxi(1, roundi(value * SEGMENTS))
	for i in SEGMENTS:
		var color := Palette.UI_ACCENT if i < filled else Color(Palette.UI_MUTED, 0.22)
		draw_rect(Rect2(i * (w + gap), 0.0, w, size.y), color)
