class_name HUD
extends CanvasLayer
## Race HUD: one slim top bar with the clock (big; red and pulsing in the last
## 30 s) and the trip progress strip, the speedometer with the posted limit, banners
## (countdown, GO!, FINISH!), the level intro card, floating popups, a control
## hint, an FPS readout for performance testing, and a "rotate your phone" notice.
## Props add a dial with a cooldown ring (keyboard/gamepad; on touch screens the
## PROP button shows it), the radar detector, and the censored gesture. During a
## police chase a pursuit meter sits under the top bar. The mute
## button and music slider live top-left (under the speedometer on touch screens).
##
## The top bar is deliberately short: the chase camera puts the road 60-160 m
## ahead at the top-center of the screen, and that's what the player must read.

const HINT_SECONDS := 9.0
const LOW_TIME := 30.0
const KEYBOARD_HINT := "W A S D or arrows: drive  ·  Space: prop  ·  M: mute  ·  Esc: pause"
const TOUCH_HINT := "Hold GAS, steer with the arrows. Let go to straighten up."
const DIAL_SIZE := 92.0

var car: PlayerCar
var clock: RaceClock
var camera: Camera3D
var props: PropController

var _hint_time := 0.0
var _touch := false
var _banner_tween: Tween
var _bonus_tween: Tween
var _dial: PropDial
var _radar: RadarWidget
var _gesture: CensorBubble
var _gesture_side := -1.0
var _audio: AudioControls
var _pursuit: PursuitMeter

@onready var _root: Control = $Root
@onready var _speedo: Control = %Speedo
@onready var _speed_value: Label = %SpeedValue
@onready var _limit_value: Label = %LimitValue
@onready var _fps: Label = %Fps
@onready var _hint_panel: Control = %HintPanel
@onready var _hint: Label = %Hint
@onready var _rotate_notice: Control = %RotateNotice
@onready var _top_bar: PanelContainer = %TopBar
@onready var _strip: ProgressStrip = %Strip
@onready var _time_value: Label = %TimeValue
@onready var _bonus: Label = %Bonus
@onready var _intro: Control = %Intro
@onready var _banner: Label = %Banner
@onready var _popups: PopupLayer = %Popups


func _ready() -> void:
	_root.theme = UiTheme.get_theme()
	for label: Label in [_speed_value, _limit_value, _time_value, _banner, _bonus, %IntroTitle]:
		label.add_theme_font_override("font", UiTheme.font(900))
	_banner.add_theme_color_override("font_outline_color", Palette.UI_PANEL)
	_bonus.add_theme_color_override("font_color", Palette.UI_BONUS)
	_bonus.add_theme_color_override("font_outline_color", Palette.UI_PANEL)
	var bar := (_root.theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).duplicate() as StyleBoxFlat
	bar.content_margin_top = 8.0
	bar.content_margin_bottom = 8.0
	bar.content_margin_left = 12.0
	bar.content_margin_right = 18.0
	_top_bar.add_theme_stylebox_override("panel", bar)
	_hint.text = KEYBOARD_HINT
	_build_prop_widgets()


func _build_prop_widgets() -> void:
	# Prop dial with room for its key cap below.
	_dial = PropDial.new()
	_dial.caption = "SPACE"
	_dial.visible = false
	_root.add_child(_dial)
	_dial.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_layout_dial()
	# Radar detector, top-right.
	_radar = RadarWidget.new()
	_radar.visible = false
	_root.add_child(_radar)
	_radar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_layout_radar()
	_gesture = CensorBubble.new()
	_root.add_child(_gesture)
	_audio = AudioControls.new()
	_audio.slider_width = 96.0
	_root.add_child(_audio)
	_pursuit = PursuitMeter.new()
	_pursuit.visible = false
	_root.add_child(_pursuit)


## Stacked above the speedometer, right-aligned with it, clear of the hint bar.
func _layout_dial() -> void:
	_dial.offset_right = _speedo.offset_right
	_dial.offset_left = _speedo.offset_right - DIAL_SIZE
	_dial.offset_bottom = _speedo.offset_top - 14.0
	_dial.offset_top = _dial.offset_bottom - DIAL_SIZE - 32.0


func _layout_radar() -> void:
	# On touch screens the pause button owns the top-right corner.
	var right := -100.0 if _touch else -24.0
	_radar.offset_right = right
	_radar.offset_left = right - 172.0
	_radar.offset_top = 22.0
	_radar.offset_bottom = 72.0


## Shows the dial for active props (the radar detector is passive and shows itself).
func setup_prop(controller: PropController) -> void:
	props = controller
	_dial.icon = controller.data.icon if controller.data else null
	_update_dial_visibility()


func _update_dial_visibility() -> void:
	_dial.visible = props != null and props.is_active_kind() and not _touch


func show_radar(on: bool) -> void:
	_radar.visible = on


func set_radar_threat(threat: float) -> void:
	_radar.threat = threat


## The censored gesture out of the window on `side` (-1 left, +1 right).
func show_gesture(side: float) -> void:
	_gesture_side = side
	_gesture.play()
	_place_gesture()


func is_gesture_showing() -> bool:
	return _gesture.is_playing()


func _place_gesture() -> void:
	if camera == null or car == null:
		return
	var body := car.car_data.size
	var window := car.get_global_transform_interpolated() * Vector3(_gesture_side * (body.x * 0.5 + 0.4), body.y * 0.8, -body.z * 0.05)
	if camera.is_position_behind(window):
		return
	var at := camera.unproject_position(window)
	_gesture.position = at - _gesture.size * 0.5 + Vector2(_gesture_side * 16.0, -36.0)


func setup_route(route: RouteMap) -> void:
	_strip.route = route


func _process(delta: float) -> void:
	if car:
		_speed_value.text = str(roundi(car.speed_mph()))
		_strip.progress_s = car.road_s
	if clock:
		_update_clock()
	if props and _dial.visible:
		_dial.cooldown = props.cooldown_fraction()
		_dial.active = props.active_fraction()
	if _gesture.is_playing():
		_place_gesture()
	_fps.text = "%d fps" % Engine.get_frames_per_second()
	var view := get_viewport().get_visible_rect().size
	_rotate_notice.visible = view.x < view.y
	_layout_top_bar(view)
	if _hint_panel.visible:
		_hint_time += delta
		_hint_panel.modulate.a = clampf(HINT_SECONDS - _hint_time, 0.0, 1.0)
		_hint_panel.visible = _hint_time < HINT_SECONDS


## Keeps the top bar clear of the corner controls (speedometer and pause
## button on touch screens) and parks the bonus flash under the clock.
func _layout_top_bar(view: Vector2) -> void:
	var side := 285.0 if _touch else 24.0
	var width := clampf(view.x - side * 2.0, 560.0, 900.0)
	_top_bar.offset_left = -width * 0.5
	_top_bar.offset_right = width * 0.5
	var clock_center := _time_value.global_position + _time_value.size * 0.5
	_bonus.position = Vector2(clock_center.x - _bonus.size.x * 0.5, _top_bar.position.y + _top_bar.size.y + 2.0)
	# The chase readout sits below the bonus flash, centered.
	_pursuit.position = Vector2((view.x - _pursuit.size.x) * 0.5, _top_bar.position.y + _top_bar.size.y + 40.0)
	_layout_audio()


## Top-left on desktop (dropping below the top bar on narrow screens), under the
## speedometer on touch screens, where the top-left corner is the speedometer's.
func _layout_audio() -> void:
	var size := _audio.get_combined_minimum_size()
	var pos := Vector2(16.0, 40.0)
	if _touch:
		pos = Vector2(20.0, _speedo.offset_top + _speedo.get_combined_minimum_size().y + 46.0)
	elif _top_bar.position.x < pos.x + size.x + 8.0:
		pos.y = _top_bar.position.y + _top_bar.size.y + 10.0
	_audio.position = pos
	_audio.size = size


func _update_clock() -> void:
	_time_value.text = RaceClock.format(clock.time_left)
	var low := clock.time_left <= LOW_TIME
	_time_value.add_theme_color_override("font_color", Palette.UI_WARN if low else Palette.UI_TEXT)
	var pulse := 1.0
	if low and clock.running:
		pulse = 1.0 + 0.09 * maxf(0.0, sin(clock.time_left * TAU))  # one beat per second
	_time_value.pivot_offset = _time_value.size * 0.5
	_time_value.scale = Vector2(pulse, pulse)


## The chase readout (see PursuitMeter).
func show_pursuit(on: bool) -> void:
	_pursuit.visible = on
	if not on:
		_pursuit.caught = 0.0
		_pursuit.losing = 0.0


func update_pursuit(gap: float, caught: float, losing: float) -> void:
	_pursuit.gap = gap
	_pursuit.caught = caught
	_pursuit.losing = losing


func pursuit_meter() -> PursuitMeter:
	return _pursuit


func set_speed_limit(mph: int) -> void:
	_limit_value.text = str(mph)


## On touch screens the bottom corners belong to the thumbs and the car sits
## bottom-center, so the speedometer moves up to the free top-left corner.
func set_touch_mode(touch: bool) -> void:
	_touch = touch
	var preset := Control.PRESET_TOP_LEFT if touch else Control.PRESET_BOTTOM_RIGHT
	_speedo.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 20)
	_fps.position = Vector2(24, _speedo.get_combined_minimum_size().y + 28.0) if touch else Vector2(16, 10)
	_hint.text = TOUCH_HINT if touch else KEYBOARD_HINT
	if _dial:
		_update_dial_visibility()
		_layout_dial()
		_layout_radar()


## The level card shown during the countdown.
func show_intro(title: String, route_text: String, scenario: String) -> void:
	%IntroTitle.text = title
	%IntroRoute.text = route_text
	%IntroScenario.text = scenario
	_intro.visible = true


func hide_intro() -> void:
	_intro.visible = false


## Big centered text that pops in and fades out (countdown digits, GO!, FINISH!).
func banner(text: String, color := Palette.UI_TEXT, hold := 0.6) -> void:
	if _banner_tween:
		_banner_tween.kill()
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.visible = true
	_banner.modulate.a = 1.0
	_banner.scale = Vector2(1.5, 1.5)
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if hold >= 0.0:
		_banner_tween.tween_interval(hold)
		_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.25)
		_banner_tween.tween_callback(_banner.hide)


func hide_banner() -> void:
	if _banner_tween:
		_banner_tween.kill()
	_banner.hide()


func popup(text: String, color := Palette.UI_TEXT, font_size := 28) -> void:
	_popups.show_text(text, color, font_size)


## A little "+0.5" (or a red "-15.0") that flashes next to the clock.
func flash_bonus(seconds: float) -> void:
	if _bonus_tween:
		_bonus_tween.kill()
	_bonus.add_theme_color_override("font_color", Palette.UI_BONUS if seconds >= 0.0 else Palette.UI_WARN)
	_bonus.text = "%+.1f" % seconds
	_bonus.modulate.a = 1.0
	_bonus_tween = create_tween()
	_bonus_tween.tween_interval(0.6)
	_bonus_tween.tween_property(_bonus, "modulate:a", 0.0, 0.4)
