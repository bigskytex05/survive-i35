class_name AudioControls
extends PanelContainer
## The mute button and music volume slider, wired to AudioManager. It sits on
## the HUD and in the garage (mouse and touch only, so arrow keys keep steering
## and browsing) and in the pause menu (`keyboard_focus` on, for gamepads),
## where a second slider sets the sound effects volume.

const SPEAKER_ON := preload("res://assets/ui/speaker_on.svg")
const SPEAKER_OFF := preload("res://assets/ui/speaker_off.svg")

@export var slider_width := 110.0
## Whether the slider and button take keyboard / gamepad focus.
@export var keyboard_focus := false
## Optional caption before the slider ("Music").
@export var caption := ""
## Adds an "Effects" slider under the music one.
@export var effects_slider := false

var _mute: Button
var _slider: HSlider
var _sfx_slider: HSlider


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiTheme.panel_box(Color(Palette.UI_PANEL, 0.92), 24, 6.0))
	var row := GridContainer.new()
	row.columns = 3 if not caption.is_empty() else 2
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 4)
	add_child(row)
	_mute = Button.new()
	_mute.flat = true
	# No padding: the theme's roomy button margins would squeeze the icon to nothing.
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		_mute.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_mute.custom_minimum_size = Vector2(40, 38)
	_mute.expand_icon = true
	_mute.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mute.add_theme_constant_override("icon_max_width", 32)
	_mute.tooltip_text = "Mute everything (M)"
	_mute.pressed.connect(AudioManager.toggle_mute)
	row.add_child(_mute)
	if not caption.is_empty():
		var label := Label.new()
		label.text = caption
		label.add_theme_font_size_override("font_size", 18)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
	_slider = _make_slider("Music volume", AudioManager.set_music_volume)
	row.add_child(_slider)
	if effects_slider:
		row.add_child(Control.new())  # under the mute button
		var label := Label.new()
		label.text = "Effects"
		label.add_theme_font_size_override("font_size", 18)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
		_sfx_slider = _make_slider("Sound effects volume", AudioManager.set_sfx_volume)
		row.add_child(_sfx_slider)
	if not keyboard_focus:
		_mute.focus_mode = Control.FOCUS_NONE
		_slider.focus_mode = Control.FOCUS_NONE
	AudioManager.changed.connect(_sync)
	_sync()


func _make_slider(tip: String, setter: Callable) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(slider_width, 32)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.tooltip_text = tip
	slider.value_changed.connect(setter)
	return slider


func slider() -> HSlider:
	return _slider


func effects() -> HSlider:
	return _sfx_slider


func mute_button() -> Button:
	return _mute


func _sync() -> void:
	_mute.icon = SPEAKER_OFF if AudioManager.muted else SPEAKER_ON
	_slider.set_value_no_signal(AudioManager.music_volume)
	_slider.modulate.a = 0.45 if AudioManager.muted else 1.0
	if _sfx_slider:
		_sfx_slider.set_value_no_signal(AudioManager.sfx_volume)
		_sfx_slider.modulate.a = _slider.modulate.a
