class_name RadarWidget
extends Control
## The little radar detector on the HUD (Radar Detector prop): a dark box with
## a row of LEDs that fill up and blink faster the closer a speed trap is. When
## all is quiet, a green power light pulses. Purely for fun; the protection
## lives in the prop itself.

const LEDS: Array[Color] = [
	Color(0.27, 0.64, 0.36), Color(0.27, 0.64, 0.36), Color(0.94, 0.62, 0.16),
	Color(0.94, 0.62, 0.16), Color(0.89, 0.27, 0.24),
]

## 0 = all clear .. 1 = a speed trap right here.
var threat := 0.0

var _t := 0.0
var _box := StyleBoxFlat.new()
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(172, 50)
	_box.bg_color = Color(Palette.UI_PANEL_DARK, 0.92)
	_box.set_corner_radius_all(14)
	_box.anti_aliasing = true
	_font = UiTheme.font(900)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	draw_style_box(_box, Rect2(Vector2.ZERO, size))
	var mid := size.y * 0.5
	# Power light: a slow pulse when quiet.
	var power := 0.35 + 0.65 * maxf(0.0, sin(_t * 3.0)) if threat < 0.05 else 1.0
	draw_circle(Vector2(16, mid), 4.5, Color(LEDS[0], power))
	draw_string(_font, Vector2(26, mid + 6), "RADAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
		Color(Palette.UI_TEXT_LIGHT, 0.85))
	# Bar graph, blinking faster as the threat grows.
	var lit := ceili(threat * LEDS.size())
	var blink := threat < 0.8 or fmod(_t * (4.0 + 10.0 * threat), 1.0) < 0.6
	for i in LEDS.size():
		var on := i < lit and blink
		var x := 92.0 + i * 15.0
		draw_rect(Rect2(x, mid - 7, 10, 14), Color(LEDS[i], 1.0 if on else 0.2))
