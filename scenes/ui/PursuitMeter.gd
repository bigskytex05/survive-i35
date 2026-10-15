class_name PursuitMeter
extends Control
## The chase readout under the top bar: a flashing light bar, what the trooper
## is up to and how far back it is, and a bar that fills red while it's
## alongside (full = pulled over) or green while you're pulling away (full =
## lost it). The cruiser is usually behind you, out of the chase camera's view,
## so this (and the siren) is how you keep track of it.

const SIZE := Vector2(420, 66)

## Meters the cruiser is behind you (negative = ahead).
var gap := 0.0
## 0..1 toward being pulled over, and toward getting away.
var caught := 0.0
var losing := 0.0

var _t := 0.0
var _box := StyleBoxFlat.new()
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	size = SIZE
	_box.bg_color = Color(Palette.UI_PANEL_DARK, 0.94)
	_box.set_corner_radius_all(14)
	_box.anti_aliasing = true
	_font = UiTheme.font(900)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func status() -> String:
	if caught > 0.05:
		return "PULL OVER!"
	if losing > 0.05:
		return "LOSING HIM..."
	if gap < -3.0:
		return "TROOPER PULLING OUT"
	if gap < 25.0:
		return "TROOPER ON YOUR BUMPER"
	return "TROOPER ON YOUR TAIL"


func _draw() -> void:
	draw_style_box(_box, Rect2(Vector2.ZERO, size))
	# Light bar: red, then blue, strobing.
	var cycle := fmod(_t * 2.4, 1.0)
	var strobe := fmod(_t * 14.0, 1.0) < 0.6
	draw_rect(Rect2(14, 14, 20, 12), Color(Palette.POLICE_RED, 1.0 if cycle < 0.5 and strobe else 0.25))
	draw_rect(Rect2(36, 14, 20, 12), Color(Palette.POLICE_BLUE, 1.0 if cycle >= 0.5 and strobe else 0.25))
	var text_color := Palette.UI_TEXT_LIGHT
	if caught > 0.05:
		text_color = Palette.POLICE_RED.lightened(0.25)
	elif losing > 0.05:
		text_color = Palette.UI_BONUS.lightened(0.3)
	draw_string(_font, Vector2(66, 27), status(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 66 - 84, 18, text_color)
	var distance := "%d m" % maxi(roundi(gap), 0) if gap >= -3.0 else ""
	draw_string(_font, Vector2(size.x - 82, 27), distance, HORIZONTAL_ALIGNMENT_RIGHT, 68, 18,
		Color(Palette.UI_TEXT_LIGHT, 0.8))
	# The bar: red while it's alongside, green while you pull away, otherwise
	# a dim gauge of how close it is.
	var bar := Rect2(14, 40, size.x - 28, 12)
	draw_rect(bar, Color(1, 1, 1, 0.12))
	var fill := 0.0
	var color := Palette.CONE_ORANGE
	if caught > 0.0:
		fill = caught
		color = Palette.POLICE_RED
	elif losing > 0.0:
		fill = losing
		color = Palette.UI_BONUS
	else:
		fill = clampf(1.0 - gap / Police.ESCAPE_GAP, 0.0, 1.0) * 0.5
		color = Color(Palette.CONE_ORANGE, 0.7)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(fill, 0.0, 1.0), bar.size.y)), color)
