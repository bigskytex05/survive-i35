class_name ProgressStrip
extends Control
## The trip at a glance, in the HUD's top bar: the start town on the left,
## the destination (and miles to go) on the right, mile markers and towns in
## between, and a dot for you. The bar around it draws the panel.

const PAD := 10.0
const MAX_TICKS := 8

var route: RouteMap:
	set(value):
		route = value
		_ticks.clear()
		if route:
			for step: float in [1.0, 2.0, 5.0, 10.0, 25.0, 50.0, 100.0]:
				_ticks = route.marks(step)
				if _ticks.size() <= MAX_TICKS:
					break
		queue_redraw()

## The player's s along the route.
var progress_s := 0.0:
	set(value):
		if absf(value - progress_s) > 0.5:
			progress_s = value
			queue_redraw()

var _ticks: Array[float] = []
var _name_font := UiTheme.font(850)
var _small_font := UiTheme.font(750)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if route == null:
		return
	var mid := size.y * 0.5 + 1.0
	var left_w := _name_font.get_string_size(route.start_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var miles := "%d mi" % ceili(route.miles_left(progress_s))
	var right_w := maxf(_name_font.get_string_size(route.end_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x,
		_small_font.get_string_size(miles, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
	draw_string(_name_font, Vector2(PAD, mid + 6.0), route.start_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Palette.UI_TEXT)
	draw_string(_name_font, Vector2(size.x - PAD - right_w, mid), route.end_name, HORIZONTAL_ALIGNMENT_RIGHT, right_w, 17, Palette.UI_TEXT)
	draw_string(_small_font, Vector2(size.x - PAD - right_w, mid + 17.0), miles, HORIZONTAL_ALIGNMENT_RIGHT, right_w, 13, Palette.UI_MUTED)

	var x0 := PAD + left_w + 18.0
	var x1 := size.x - PAD - right_w - 18.0
	var track := Color(Palette.UI_MUTED, 0.35)
	draw_line(Vector2(x0, mid), Vector2(x1, mid), track, 4.0, true)
	for mile in _ticks:
		var x := lerpf(x0, x1, route.fraction(route.s_at_mile(mile)))
		draw_line(Vector2(x, mid - 5.0), Vector2(x, mid + 5.0), Palette.UI_MUTED, 2.0, true)
		draw_string(_small_font, Vector2(x - 20.0, mid + 20.0), str(int(mile)), HORIZONTAL_ALIGNMENT_CENTER, 40.0, 11, Palette.UI_MUTED)
	for town in route.towns:
		var x := lerpf(x0, x1, route.fraction(town["s"]))
		draw_circle(Vector2(x, mid), 5.0, Palette.UI_TEXT)
		draw_string(_small_font, Vector2(x - 50.0, mid - 10.0), town["name"], HORIZONTAL_ALIGNMENT_CENTER, 100.0, 12, Palette.UI_TEXT)
	draw_circle(Vector2(x0, mid), 5.0, Palette.UI_TEXT)
	draw_circle(Vector2(x1, mid), 5.0, Palette.UI_TEXT)
	var you := lerpf(x0, x1, route.fraction(progress_s))
	draw_line(Vector2(x0, mid), Vector2(you, mid), Palette.UI_ACCENT, 4.0, true)
	draw_circle(Vector2(you, mid), 10.0, Palette.UI_PANEL)
	draw_circle(Vector2(you, mid), 7.0, Palette.UI_ACCENT)
