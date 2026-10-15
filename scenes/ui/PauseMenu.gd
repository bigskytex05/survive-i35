extends CanvasLayer
## Pause overlay. Runs while the tree is paused and listens for the `pause`
## action from any device (Esc / P, gamepad Start, the on-screen pause button).
## It also has the mute button and the music and effects volume sliders.
## The game also pauses itself when the app or browser tab loses focus.

signal restart_pressed
signal loadout_pressed

## Off once the race is over (the results screen takes over).
var allowed := true

@onready var _root: Control = $Root
@onready var _resume: Button = %Resume


func _ready() -> void:
	_root.theme = UiTheme.get_theme()
	%Title.add_theme_font_override("font", UiTheme.font(900))
	_resume.pressed.connect(set_paused.bind(false))
	%Restart.pressed.connect(restart_pressed.emit)
	%Loadout.pressed.connect(loadout_pressed.emit)
	var audio := AudioControls.new()
	audio.caption = "Music"
	audio.slider_width = 240.0
	audio.keyboard_focus = true
	audio.effects_slider = true
	audio.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	$Root/Center/Panel/VBox.add_child(audio)
	_root.visible = false


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		set_paused(not get_tree().paused)


func set_paused(on: bool) -> void:
	if on and not allowed:
		return
	get_tree().paused = on
	_root.visible = on
	if on:
		_resume.grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree() and not get_tree().paused:
		set_paused(true)
