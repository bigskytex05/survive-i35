class_name PropDial
extends Control
## A prop's icon with its cooldown ring. While recharging, a dark pie covers
## the part still to go and an accent ring grows back around it; a bright outer
## ring drains while the prop is switched on. The HUD shows one (with a key
## caption) for keyboard and gamepad; the touch PROP button has one inside.

var icon: Texture2D:
	set(value):
		icon = value
		queue_redraw()
## Draws its own round backing (the HUD). The touch button has its own.
var backing := true
## Text under the dial, e.g. "SPACE".
var caption := ""

## 1 = just used .. 0 = ready.
var cooldown := 0.0:
	set(value):
		if not is_equal_approx(value, cooldown):
			cooldown = value
			queue_redraw()
## 1 = just switched on .. 0 = off.
var active := 0.0:
	set(value):
		if not is_equal_approx(value, active):
			active = value
			queue_redraw()

var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiTheme.font(900)


func _draw() -> void:
	var r := size.x * 0.5
	var c := Vector2(r, r)
	if backing:
		draw_circle(c, r, Color(Palette.UI_PANEL, 0.92))
	var ring_r := r - 5.0
	if icon:
		var s := r * 1.1
		var tint := Color(1, 1, 1, 0.4 if cooldown > 0.0 else 1.0)
		draw_texture_rect(icon, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, tint)
	if cooldown > 0.0:
		_pie(c, ring_r, -PI * 0.5, -PI * 0.5 + TAU * cooldown, Color(0.1, 0.08, 0.06, 0.4))
		draw_arc(c, ring_r, -PI * 0.5 + TAU * cooldown, PI * 1.5, 48, Palette.UI_ACCENT, 5.0, true)
	else:
		draw_arc(c, ring_r, 0.0, TAU, 48, Palette.UI_ACCENT, 5.0, true)
	if active > 0.0:
		draw_arc(c, r + 3.0, -PI * 0.5, -PI * 0.5 + TAU * active, 48, Palette.HEADLIGHT, 6.0, true)
	if not caption.is_empty():
		# A small key cap under the dial.
		var w := _font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 18.0
		var cap := Rect2(c.x - w * 0.5, size.x + 6.0, w, 24.0)
		draw_rect(cap, Color(Palette.UI_PANEL, 0.92))
		draw_string(_font, Vector2(cap.position.x, cap.position.y + 17.0), caption, HORIZONTAL_ALIGNMENT_CENTER, w, 14,
			Palette.UI_TEXT)


func _pie(c: Vector2, radius: float, from: float, to: float, color: Color) -> void:
	var points := PackedVector2Array([c])
	var steps := maxi(3, int((to - from) / TAU * 48.0))
	for i in steps + 1:
		var a := lerpf(from, to, float(i) / steps)
		points.append(c + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(points, color)
