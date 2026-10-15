class_name UiTheme
extends RefCounted
## Builds the shared UI theme from Palette: rounded Nunito type, flat cream
## panels and generous padding. The UI stays calm and tidy while the highway
## is chaos; that contrast is part of the joke.
##
## UI roots call `theme = UiTheme.get_theme()` in _ready().

const FONT_PATH := "res://assets/fonts/Nunito.ttf"

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


## Nunito is a variable font; this picks a weight (400 regular, 700 bold, 900 black).
static func font(weight := 750) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = load(FONT_PATH)
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	variation.variation_opentype = {wght: weight}
	return variation


static func panel_box(color: Color, radius := 20, margin := 18.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	box.anti_aliasing = true
	return box


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = font(750)
	t.default_font_size = 22

	t.set_color("font_color", "Label", Palette.UI_TEXT)

	var panel := panel_box(Color(Palette.UI_PANEL, 0.92))
	panel.shadow_color = Color(0.17, 0.11, 0.06, 0.16)
	panel.shadow_size = 10
	panel.shadow_offset = Vector2(0, 4)
	t.set_stylebox("panel", "PanelContainer", panel)

	var normal := panel_box(Palette.UI_PANEL.darkened(0.07), 16, 14.0)
	normal.content_margin_left = 28.0
	normal.content_margin_right = 28.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Palette.UI_PANEL.darkened(0.13)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Palette.UI_ACCENT
	var focus := normal.duplicate() as StyleBoxFlat
	focus.draw_center = false
	focus.set_border_width_all(4)
	focus.border_color = Palette.UI_ACCENT
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", Palette.UI_TEXT)
	t.set_color("font_hover_color", "Button", Palette.UI_TEXT)
	t.set_color("font_focus_color", "Button", Palette.UI_TEXT)
	t.set_color("font_pressed_color", "Button", Palette.UI_TEXT_LIGHT)
	t.set_font_size("font_size", "Button", 24)

	# Sliders: a soft track that fills with the accent color, a round grabber.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(Palette.UI_MUTED, 0.3)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4.0
	track.content_margin_bottom = 4.0
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Palette.UI_ACCENT
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var grabber: Texture2D = load("res://assets/ui/slider_grabber.svg")
	t.set_icon("grabber", "HSlider", grabber)
	t.set_icon("grabber_highlight", "HSlider", grabber)
	return t
