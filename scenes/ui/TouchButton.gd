class_name TouchButton
extends Control
## One on-screen control. It only draws itself; TouchControls decides which
## finger is on it and presses the matching InputMap action.

enum Glyph { NONE, LEFT, RIGHT, PAUSE }

@export var action: StringName = &""
@export var text := ""
@export var glyph: Glyph = Glyph.NONE
@export var font_size := 22
## Accent buttons (the gas pedal) use the highlight color.
@export var accent := false
## Fully rounded (a circle for square buttons).
@export var round_shape := false
## A finger sliding onto this button from another slide button switches to it
## (thumb rolls from left to right steering without lifting).
@export var slide_switch := false
## Extra invisible touch area around the button, in UI pixels.
@export var hit_padding := 16.0

var pressed := false:
	set(value):
		if value != pressed:
			pressed = value
			queue_redraw()

var _box := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # TouchControls routes input itself
	_box.anti_aliasing = true
	_box.set_border_width_all(3)


func hit_rect() -> Rect2:
	return get_global_rect().grow(hit_padding)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var fill := Palette.UI_ACCENT if accent else Palette.UI_PANEL_DARK
	_box.bg_color = Color(fill, 0.62 if pressed else 0.34)
	_box.border_color = Color(Palette.UI_TEXT_LIGHT, 0.85 if pressed else 0.5)
	_box.set_corner_radius_all(int(minf(size.x, size.y) * (0.5 if round_shape else 0.24)))
	draw_style_box(_box, rect.grow(-3.0) if pressed else rect)  # pressed buttons sink a little

	var ink := Color(Palette.UI_TEXT_LIGHT, 0.95)
	var c := size * 0.5
	var k := minf(size.x, size.y)
	match glyph:
		Glyph.LEFT:
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(k * 0.16, -k * 0.2), c + Vector2(-k * 0.18, 0), c + Vector2(k * 0.16, k * 0.2)]), ink)
		Glyph.RIGHT:
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-k * 0.16, -k * 0.2), c + Vector2(k * 0.18, 0), c + Vector2(-k * 0.16, k * 0.2)]), ink)
		Glyph.PAUSE:
			draw_rect(Rect2(c + Vector2(-k * 0.17, -k * 0.2), Vector2(k * 0.12, k * 0.4)), ink)
			draw_rect(Rect2(c + Vector2(k * 0.05, -k * 0.2), Vector2(k * 0.12, k * 0.4)), ink)
	if not text.is_empty():
		var font := get_theme_default_font()
		var ascent := font.get_ascent(font_size)
		var descent := font.get_descent(font_size)
		var baseline := c.y + (ascent - descent) * 0.5
		draw_string(font, Vector2(0, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, ink)
