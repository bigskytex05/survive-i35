class_name TouchControls
extends CanvasLayer
## On-screen driving controls for phones and tablets.
##
## Every finger is tracked on its own, and buttons press the same InputMap
## actions as the keyboard and gamepad (Input.action_press), so gameplay code
## never needs to know touch exists.
##
## Hidden on desktop until a touch arrives. Press T to toggle them for testing
## with a mouse.

signal shown_changed(is_shown: bool)

const MOUSE_FINGER := 1000

## Show even without a touchscreen (handy in the editor).
@export var force_show := false

var _buttons: Array[TouchButton] = []
var _finger_on: Dictionary = {}    # finger index -> TouchButton
var _press_count: Dictionary = {}  # TouchButton -> number of fingers holding it
var _shown := false
var _suppressed := false
var _props: PropController
var _prop_dial: PropDial

@onready var _prop_button: TouchButton = $Root/Prop


func _ready() -> void:
	$Root.theme = UiTheme.get_theme()
	for node in find_children("*", "TouchButton", true, false):
		_buttons.append(node as TouchButton)
	visible = false
	set_shown(force_show or DisplayServer.is_touchscreen_available())


## Puts the equipped prop's icon and cooldown ring on the PROP button. Passive
## props (and no prop) hide the button; there's nothing to press.
func set_prop(controller: PropController) -> void:
	_props = controller
	var active := controller != null and controller.is_active_kind()
	_prop_button.visible = active
	if not active:
		return
	if _prop_dial == null:
		_prop_dial = PropDial.new()
		_prop_dial.backing = false
		_prop_button.add_child(_prop_dial)
		_prop_dial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_prop_dial.icon = controller.data.icon
	_prop_button.text = ""


func _process(_delta: float) -> void:
	if _prop_dial and _props and visible:
		_prop_dial.cooldown = _props.cooldown_fraction()
		_prop_dial.active = _props.active_fraction()


func is_shown() -> bool:
	return _shown


func set_shown(on: bool) -> void:
	visible = on and not _suppressed
	if not on:
		release_all()
	if on != _shown:
		_shown = on
		shown_changed.emit(on)


## Hides the controls and ignores touches while a menu owns the screen.
func set_suppressed(on: bool) -> void:
	_suppressed = on
	release_all()
	visible = _shown and not on


func release_all() -> void:
	for finger in _finger_on.keys():
		_finger_up(finger)
	_finger_on.clear()


func _notification(what: int) -> void:
	# Lifting a finger outside the window, a phone call, a tab switch: never leave the gas stuck.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_all()


func _input(event: InputEvent) -> void:
	if _suppressed:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if not _shown:
			set_shown(true)
		if touch.pressed:
			_finger_down(touch.index, touch.position)
		else:
			_finger_up(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_finger_move(drag.index, drag.position)
	elif event is InputEventMouseButton:
		# Real mouse only: touches also arrive as emulated mouse events, which we skip.
		var mb := event as InputEventMouseButton
		if _shown and mb.button_index == MOUSE_BUTTON_LEFT and mb.device != InputEvent.DEVICE_ID_EMULATION:
			if mb.pressed:
				_finger_down(MOUSE_FINGER, mb.position)
			else:
				_finger_up(MOUSE_FINGER)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.device != InputEvent.DEVICE_ID_EMULATION and _finger_on.has(MOUSE_FINGER):
			_finger_move(MOUSE_FINGER, mm.position)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_T:
			set_shown(not _shown)


func _button_at(pos: Vector2) -> TouchButton:
	for button in _buttons:
		if button.is_visible_in_tree() and button.hit_rect().has_point(pos):
			return button
	return null


func _finger_down(finger: int, pos: Vector2) -> void:
	var button := _button_at(pos)
	if button == null:
		return
	if _finger_on.has(finger):
		_finger_up(finger)
	_finger_on[finger] = button
	_hold(button)
	get_viewport().set_input_as_handled()


func _finger_move(finger: int, pos: Vector2) -> void:
	if not _finger_on.has(finger):
		return
	var current: TouchButton = _finger_on[finger]
	var under := _button_at(pos)
	# Thumbs drift; only switch when sliding onto another slide-switch button.
	if under != null and under != current and under.slide_switch and current.slide_switch:
		_let_go(current)
		_finger_on[finger] = under
		_hold(under)


func _finger_up(finger: int) -> void:
	if _finger_on.has(finger):
		_let_go(_finger_on[finger])
		_finger_on.erase(finger)


func _hold(button: TouchButton) -> void:
	_press_count[button] = _press_count.get(button, 0) + 1
	if _press_count[button] == 1:
		button.pressed = true
		if button.action != &"":
			Input.action_press(button.action)


func _let_go(button: TouchButton) -> void:
	var count: int = _press_count.get(button, 0) - 1
	if count > 0:
		_press_count[button] = count
		return
	_press_count.erase(button)
	button.pressed = false
	if button.action != &"":
		Input.action_release(button.action)
