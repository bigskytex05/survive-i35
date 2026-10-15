class_name CensorBubble
extends Control
## The censored gesture, the way broadcast TV would show it: a jittering pixel
## mosaic out of the car window with a big black CENSORED bar over it. Nothing
## underneath is ever drawn: it's mosaic tiles all the way down.

const CELL := 13.0
const GRID := Vector2i(6, 7)
const LIFE := 1.4
const SKIN: Array[Color] = [
	Color(0.89, 0.71, 0.55), Color(0.79, 0.59, 0.44), Color(0.93, 0.76, 0.61),
	Color(0.85, 0.65, 0.49), Color(0.73, 0.52, 0.37),
]

var _t := -1.0
var _shuffle := 0
var _shuffle_in := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(CELL * GRID.x, CELL * GRID.y)
	pivot_offset = size * 0.5
	visible = false
	_font = UiTheme.font(900)


func play() -> void:
	_t = 0.0
	visible = true


func is_playing() -> bool:
	return _t >= 0.0


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	_shuffle_in -= delta
	if _shuffle_in <= 0.0:
		_shuffle_in = 0.07
		_shuffle += 1
		queue_redraw()
	var pop := minf(_t / 0.12, 1.0)
	scale = Vector2.ONE * (0.4 + 0.6 * pop) * (1.0 + 0.05 * sin(_t * 40.0))
	rotation = sin(_t * 18.0) * 0.08
	modulate.a = clampf((LIFE - _t) / 0.25, 0.0, 1.0)
	if _t >= LIFE:
		_t = -1.0
		visible = false


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _shuffle
	for y in GRID.y:
		for x in GRID.x:
			var corner := (x == 0 or x == GRID.x - 1) and (y == 0 or y == GRID.y - 1)
			if corner or rng.randf() < 0.12:
				continue
			draw_rect(Rect2(Vector2(x, y) * CELL, Vector2(CELL, CELL)), SKIN[rng.randi() % SKIN.size()])
	# The bar is wider than the mosaic and tilted, like it was slapped on in a hurry.
	var c := size * 0.5
	draw_set_transform(c, -0.12, Vector2.ONE)
	var bar := Rect2(Vector2(-size.x * 0.5 - CELL * 1.6, -15.0), Vector2(size.x + CELL * 3.2, 30.0))
	draw_rect(bar.grow(2.0), Palette.UI_PANEL)
	draw_rect(bar, Color(0.08, 0.08, 0.08))
	draw_string(_font, Vector2(bar.position.x, 7.0), "CENSORED", HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 19,
		Palette.UI_TEXT_LIGHT)
	draw_set_transform(Vector2.ZERO)
