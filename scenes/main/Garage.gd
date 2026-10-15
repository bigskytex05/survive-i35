class_name Garage
extends Node3D
## The garage: pick a car (and its paint), then a prop, then hit the road. The
## car you're looking at spins on a turntable.
##
## Touch and mouse: tap a card to pick it, then Next. Keyboard and gamepad:
## arrows / d-pad move between cards (moving onto a card picks it), Enter / A
## moves on, Esc / B goes back. M mutes; the music slider sits on the bottom row.
## Add a car or prop by appending its .tres to the `cars` / `props` lists in
## Garage.tscn.

signal drive_requested

enum Step { CAR, PROP }

const RACE_SCENE := "res://scenes/race/Race.tscn"
const TURN_SPEED := 0.35        # turntable, rad/s
const PANEL_WIDTH := 500.0
const MARGIN := 24.0
const CAM_DISTANCE := 12.5
const CAM_ELEVATION := 0.22     # radians above the horizon (low enough to show some sky)
const CAM_AZIMUTH := 0.6        # radians around from straight behind the car
const CAM_FOV := 32.0
const TABLE_RADIUS := 3.7
const TABLE_TOP := 0.22
const REV_TIME := 1.4         # seconds of engine blip when a car is picked

@export var cars: Array[CarData] = []
@export var props: Array[PropData] = []
## Off in tests: Hit the Road only emits drive_requested.
@export var change_scene_on_go := true

var step := Step.CAR
var car_index := 1
var prop_index := 1
var paint_index := 0

var _paint_chosen := false
var _cards: Array[Button] = []
var _swatches: Array[Button] = []
var _stat_bars: Array[StatBar] = []

@onready var _camera: Camera3D = $Camera3D
@onready var _turntable: Node3D = $Turntable
@onready var _model: CarModel = $Turntable/Car
@onready var _root: Control = $UI/Root

# Built in code by _build_ui().
var _step_label: Label
var _title: Label
var _name: Label
var _blurb: Label
var _car_info: Control
var _trait_name: Label
var _trait_text: Label
var _paint_name: Label
var _prop_info: Control
var _prop_icon: TextureRect
var _prop_kind: Label
var _prop_timing: Label
var _prop_how: Label
var _card_row: HBoxContainer
var _back: Button
var _next: Button
var _rev_player: AudioStreamPlayer
var _rev_tween: Tween


func _ready() -> void:
	_root.theme = UiTheme.get_theme()
	if GameState.has_loadout:
		# Back from a race: start from what was picked last time.
		car_index = maxi(cars.find(GameState.car), 0)
		prop_index = maxi(props.find(GameState.prop), 0)
		var paint := Palette.PLAYER_PAINTS.find(GameState.paint)
		_paint_chosen = paint >= 0
		paint_index = paint if paint >= 0 else 0
	if not _paint_chosen:
		paint_index = _default_paint(cars[car_index])
	_build_stage()
	_build_ui()
	_show_step(Step.CAR)
	_frame_camera()


func _process(delta: float) -> void:
	_turntable.rotation.y = wrapf(_turntable.rotation.y + TURN_SPEED * delta, -PI, PI)
	_frame_camera()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if step == Step.PROP:
			_show_step(Step.CAR)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and get_viewport().gui_get_focus_owner() in _cards:
		# Enter / A on a card confirms it (a click or tap only picks it).
		go_next()
		get_viewport().set_input_as_handled()


# --- Picking ---------------------------------------------------------------------

func selected_car() -> CarData:
	return cars[car_index]


func selected_prop() -> PropData:
	return props[prop_index]


func selected_paint() -> Color:
	return Palette.PLAYER_PAINTS[paint_index]


func select_car(index: int) -> void:
	var changed := clampi(index, 0, cars.size() - 1) != car_index
	car_index = clampi(index, 0, cars.size() - 1)
	if changed:
		Sfx.play(self, &"click", -10.0)
		_rev()
	if not _paint_chosen:
		paint_index = _default_paint(selected_car())
	_refresh()
	_rebuild_model(true)


func select_paint(index: int) -> void:
	paint_index = clampi(index, 0, Palette.PLAYER_PAINTS.size() - 1)
	_paint_chosen = true
	_refresh()
	_rebuild_model(false)


func select_prop(index: int) -> void:
	if clampi(index, 0, props.size() - 1) != prop_index:
		Sfx.play(self, &"click", -10.0)
	prop_index = clampi(index, 0, props.size() - 1)
	_refresh()


## Next from the car step; Hit the Road from the prop step.
func go_next() -> void:
	# On AudioManager, so it isn't cut off when the race scene takes over.
	Sfx.play(AudioManager, &"confirm", -6.0)
	if step == Step.CAR:
		_show_step(Step.PROP)
	else:
		hit_the_road()


func hit_the_road() -> void:
	GameState.set_loadout(selected_car(), selected_paint(), selected_prop())
	drive_requested.emit()
	if change_scene_on_go:
		# Deferred: we're inside a button's input handling right now.
		get_tree().change_scene_to_file.call_deferred(RACE_SCENE)


## Blips the picked car's engine (the EV whirs instead).
func _rev() -> void:
	if is_instance_valid(_rev_player):
		_rev_player.queue_free()
	if _rev_tween:
		_rev_tween.kill()
	var car := selected_car()
	var player := Sfx.loop_player(car.engine_sound)
	_rev_player = player
	add_child(player)
	_rev_tween = create_tween()
	_rev_tween.tween_method(_set_rev.bind(player, car), 0.0, 1.0, REV_TIME)
	_rev_tween.tween_callback(player.queue_free)


func _set_rev(u: float, player: AudioStreamPlayer, car: CarData) -> void:
	var ratio := 0.55 * pow(sin(PI * minf(u / 0.7, 1.0)), 0.8)
	var level := minf(u / 0.05, 1.0) * (1.0 - smoothstep(0.7, 1.0, u))
	Sfx.set_loop(player, level, -11.0, RaceAudio.engine_pitch(car, ratio))


func _default_paint(car: CarData) -> int:
	return maxi(Palette.PLAYER_PAINTS.find(car.default_paint), 0)


func _show_step(new_step: Step) -> void:
	step = new_step
	var on_car := step == Step.CAR
	_step_label.text = "STEP 1 OF 2" if on_car else "STEP 2 OF 2"
	_title.text = "Pick your ride" if on_car else "Pick your prop"
	_car_info.visible = on_car
	_prop_info.visible = not on_car
	_back.visible = not on_car
	_next.text = "Next: Pick a Prop" if on_car else "Hit the Road!"
	for card in _cards:
		card.queue_free()
	_cards.clear()
	var count := cars.size() if on_car else props.size()
	for i in count:
		var card := _make_card(i)
		_card_row.add_child(card)
		_cards.append(card)
	_refresh()
	_cards[car_index if on_car else prop_index].grab_focus()


## Updates every label, bar and highlight from the current picks.
func _refresh() -> void:
	var picked := car_index if step == Step.CAR else prop_index
	for i in _cards.size():
		_style_card(_cards[i], i == picked)
	if step == Step.CAR:
		var car := selected_car()
		_name.text = car.display_name
		_blurb.text = car.description
		var values := _car_stats(car)
		for i in _stat_bars.size():
			_stat_bars[i].value = values[i]
		_trait_name.text = car.trait_name
		_trait_text.text = car.trait_description
		_paint_name.text = Palette.PLAYER_PAINT_NAMES[paint_index]
		for i in _swatches.size():
			_style_swatch(_swatches[i], i)
	else:
		var prop := selected_prop()
		_name.text = prop.display_name
		_blurb.text = prop.description
		_prop_icon.texture = prop.icon
		if prop.kind == PropData.Kind.PASSIVE:
			_prop_kind.text = "Passive: always on"
			_prop_timing.text = "Works the whole trip"
		else:
			_prop_kind.text = "Active: Space, gamepad A or PROP"
			_prop_timing.text = ("Lasts %d s  ·  " % roundi(prop.duration) if prop.duration > 0.0 else "") \
				+ "%d s cooldown" % roundi(prop.cooldown)
		_prop_how.text = prop.how_it_works


## Top speed, acceleration, handling, weight and off-road, scaled 0..1 over
## the range a sensible car could have.
static func _car_stats(car: CarData) -> Array[float]:
	return [
		inverse_lerp(90.0, 115.0, car.top_speed_mph),
		car.acceleration / 13.0,
		car.steer_rate * car.grip / 18.0,
		car.mass / 2.4,
		1.0 - car.offroad_drag,
	]


func _rebuild_model(drop: bool) -> void:
	_model.build(selected_car(), selected_paint())
	_model.position.y = TABLE_TOP
	if drop:
		# A little drop onto the turntable, toy-style.
		_model.position.y = TABLE_TOP + 0.9
		var tween := create_tween()
		tween.tween_property(_model, "position:y", TABLE_TOP, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


# --- Camera and stage ---------------------------------------------------------------

## Orbits at a fixed angle and shifts the frame so the car sits in the middle of
## the space the panels leave free, on any screen shape.
func _frame_camera() -> void:
	var view := get_viewport().get_visible_rect().size
	var target := Vector3(0.0, 1.0, 0.0)
	var dir := Vector3(sin(CAM_AZIMUTH) * cos(CAM_ELEVATION), sin(CAM_ELEVATION), cos(CAM_AZIMUTH) * cos(CAM_ELEVATION))
	_camera.fov = CAM_FOV
	_camera.look_at_from_position(target + dir * CAM_DISTANCE, target, Vector3.UP)
	var free_center := (MARGIN + PANEL_WIDTH + view.x) * 0.5
	var meters_per_px := 2.0 * CAM_DISTANCE * tan(deg_to_rad(CAM_FOV) * 0.5) / view.y
	_camera.h_offset = -(free_center - view.x * 0.5) * meters_per_px
	_camera.v_offset = 0.25


func _build_stage() -> void:
	var mk := MeshKit.new()
	# Turntable: a concrete disc with a darker rim.
	mk.prism(Vector3.ZERO, TABLE_RADIUS + 0.25, TABLE_RADIUS + 0.25, TABLE_TOP * 0.6, 28, Palette.CONCRETE_SHADE)
	mk.prism(Vector3.ZERO, TABLE_RADIUS, TABLE_RADIUS, TABLE_TOP, 28, Palette.CONCRETE)
	var table := MeshInstance3D.new()
	table.mesh = mk.commit()
	_turntable.add_child(table)
	# A few cones, barrels and a highway sign: you're on an I-35 shoulder lot.
	# Spots are (meters back from the car, meters to its right) as the camera sees it.
	var away := Vector3(sin(CAM_AZIMUTH), 0.0, cos(CAM_AZIMUTH))
	var cam_left := away.cross(Vector3.UP)
	var spot := func(back: float, right: float) -> Vector3: return -away * back - cam_left * right
	var decor := MeshKit.new()
	for at: Vector3 in [spot.call(5.5, 4.2), spot.call(1.0, 4.6), spot.call(7.0, -3.2)]:
		decor.prism(at, 0.32, 0.04, 0.8, 8, Palette.CONE_ORANGE)
		decor.box(at + Vector3(0, 0.02, 0), Vector3(0.6, 0.04, 0.6), Palette.CONE_ORANGE.darkened(0.2))
		decor.prism(at + Vector3(0, 0.42, 0), 0.2, 0.15, 0.14, 8, Palette.SIGN_WHITE, false)
	for at: Vector3 in [spot.call(10.0, 5.4), spot.call(11.5, 6.6)]:
		for band in 4:
			var color := Palette.CONE_ORANGE if band % 2 == 0 else Palette.SIGN_WHITE
			decor.prism(at + Vector3(0, band * 0.26, 0), 0.42, 0.42, 0.26, 10, color, band == 3)
	# The sign stands far behind the car, up in the gap between the panels,
	# facing the camera.
	var sign_xf := Transform3D(Basis(Vector3.UP, CAM_AZIMUTH), spot.call(34.0, -2.5))
	decor.xf = sign_xf
	for x: float in [-3.4, 3.4]:
		decor.box(Vector3(x, 2.0, 0), Vector3(0.25, 4.0, 0.25), Palette.POLE)
	decor.box(Vector3(0, 3.4, 0), Vector3(8.4, 2.8, 0.2), Palette.SIGN_GREEN)
	decor.box(Vector3(0, 3.4, 0.11), Vector3(8.0, 2.4, 0.02), Palette.SIGN_WHITE)
	decor.box(Vector3(0, 3.4, 0.12), Vector3(7.8, 2.2, 0.02), Palette.SIGN_GREEN)
	var decor_mesh := MeshInstance3D.new()
	decor_mesh.mesh = decor.commit()
	add_child(decor_mesh)
	for line: Array in [["SURVIVE I-35", 118, 3.85], ["GARAGE  ·  NEXT EXIT", 62, 2.75]]:
		var label := Label3D.new()
		label.text = line[0]
		label.font = UiTheme.font(900)
		label.font_size = line[1]
		label.pixel_size = 0.01
		label.modulate = Palette.SIGN_WHITE
		label.outline_size = 0
		label.shaded = false
		label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		label.transform = sign_xf * Transform3D(Basis.IDENTITY, Vector3(0, line[2], 0.14))
		add_child(label)
	_rebuild_model(false)


# --- UI -----------------------------------------------------------------------------

func _build_ui() -> void:
	# Header, top-left.
	var header := VBoxContainer.new()
	header.position = Vector2(MARGIN + 4.0, 16.0)
	header.add_theme_constant_override("separation", -4)
	_root.add_child(header)
	_step_label = _label(header, 16, Palette.UI_ACCENT, 900)
	_title = _label(header, 40, Palette.UI_TEXT, 900)
	_title.add_theme_color_override("font_outline_color", Color(Palette.UI_PANEL, 0.85))
	_title.add_theme_constant_override("outline_size", 12)

	_build_trip_card()

	# Details panel, left column.
	var panel := PanelContainer.new()
	panel.position = Vector2(MARGIN, 96.0)
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_root.add_child(panel)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 10)
	panel.add_child(details)
	_name = _label(details, 34, Palette.UI_TEXT, 900)
	_blurb = _label(details, 18, Palette.UI_MUTED, 650, true)

	_car_info = VBoxContainer.new()
	_car_info.add_theme_constant_override("separation", 10)
	details.add_child(_car_info)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	_car_info.add_child(grid)
	for stat_name: String in ["Top speed", "Acceleration", "Handling", "Weight", "Off-road"]:
		var key := _label(grid, 17, Palette.UI_TEXT, 750)
		key.text = stat_name
		key.custom_minimum_size.x = 132
		var bar := StatBar.new()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(bar)
		_stat_bars.append(bar)
	_trait_name = _label(_car_info, 20, Palette.UI_ACCENT, 900)
	_trait_text = _label(_car_info, 17, Palette.UI_TEXT, 650, true)
	_trait_text.add_theme_constant_override("line_spacing", -2)
	var paint_row := HBoxContainer.new()
	paint_row.add_theme_constant_override("separation", 10)
	_car_info.add_child(paint_row)
	for i in Palette.PLAYER_PAINTS.size():
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(38, 38)
		swatch.tooltip_text = Palette.PLAYER_PAINT_NAMES[i]
		swatch.pressed.connect(select_paint.bind(i))
		swatch.focus_entered.connect(select_paint.bind(i))
		paint_row.add_child(swatch)
		_swatches.append(swatch)
	_paint_name = _label(paint_row, 17, Palette.UI_MUTED, 750)
	_paint_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_prop_info = VBoxContainer.new()
	_prop_info.add_theme_constant_override("separation", 12)
	details.add_child(_prop_info)
	var prop_row := HBoxContainer.new()
	prop_row.add_theme_constant_override("separation", 16)
	_prop_info.add_child(prop_row)
	_prop_icon = TextureRect.new()
	_prop_icon.custom_minimum_size = Vector2(84, 84)
	_prop_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_prop_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	prop_row.add_child(_prop_icon)
	var prop_text := VBoxContainer.new()
	prop_text.alignment = BoxContainer.ALIGNMENT_CENTER
	prop_row.add_child(prop_text)
	_prop_kind = _label(prop_text, 19, Palette.UI_ACCENT, 900)
	_prop_timing = _label(prop_text, 17, Palette.UI_MUTED, 750)
	_prop_how = _label(_prop_info, 18, Palette.UI_TEXT, 650, true)

	# Cards along the bottom-left, navigation bottom-right.
	_card_row = HBoxContainer.new()
	_card_row.add_theme_constant_override("separation", 10)
	_root.add_child(_card_row)
	_pin(_card_row, Control.PRESET_BOTTOM_LEFT, Vector2(MARGIN, -MARGIN))

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 12)
	_root.add_child(nav)
	_pin(nav, Control.PRESET_BOTTOM_RIGHT, Vector2(-MARGIN, -MARGIN))
	_back = Button.new()
	_back.text = "Back"
	_back.custom_minimum_size = Vector2(130, 64)
	_back.pressed.connect(_show_step.bind(Step.CAR))
	nav.add_child(_back)
	_next = Button.new()
	_next.custom_minimum_size = Vector2(250, 64)
	_next.add_theme_font_override("font", UiTheme.font(900))
	var go := UiTheme.panel_box(Palette.UI_ACCENT, 16, 14.0)
	go.content_margin_left = 28.0
	go.content_margin_right = 28.0
	var go_hover := go.duplicate() as StyleBoxFlat
	go_hover.bg_color = Palette.UI_ACCENT.lightened(0.08)
	var go_focus := go.duplicate() as StyleBoxFlat
	go_focus.set_border_width_all(4)
	go_focus.border_color = Palette.UI_TEXT
	_next.add_theme_stylebox_override("normal", go)
	_next.add_theme_stylebox_override("hover", go_hover)
	_next.add_theme_stylebox_override("pressed", go_hover)
	_next.add_theme_stylebox_override("focus", go_focus)
	for state: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		_next.add_theme_color_override(state, Palette.UI_TEXT_LIGHT)
	_next.pressed.connect(go_next)
	_next.set_meta(&"sfx", &"")  # go_next plays its own (Enter on a card skips the button)
	nav.add_child(_next)

	# Mute and music volume, bottom row between the cards and the buttons.
	var audio := AudioControls.new()
	_root.add_child(audio)
	_pin(audio, Control.PRESET_BOTTOM_LEFT, Vector2(MARGIN + PANEL_WIDTH + 18.0, -MARGIN - 22.0))


## The trip you're packing for, top-right.
func _build_trip_card() -> void:
	var level := GameState.level
	var route := RouteMap.from_level(level)
	var card := PanelContainer.new()
	_root.add_child(card)
	_pin(card, Control.PRESET_TOP_RIGHT, Vector2(-MARGIN, 16.0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)
	var title := _label(box, 24, Palette.UI_TEXT, 900)
	title.text = level.title
	var trip := _label(box, 16, Palette.UI_ACCENT, 800)
	trip.text = "%s to %s  ·  %s" % [route.start_name, route.end_name, RaceClock.format(level.time_limit)]
	var scenario := _label(box, 15, Palette.UI_MUTED, 650, true)
	scenario.text = level.scenario
	scenario.custom_minimum_size.x = 300


## Pins a container's corner to a screen corner (offset in px); it grows from
## there to fit whatever is inside it.
func _pin(control: Control, corner: Control.LayoutPreset, offset: Vector2) -> void:
	control.set_anchors_preset(corner)
	control.offset_left = offset.x
	control.offset_right = offset.x
	control.offset_top = offset.y
	control.offset_bottom = offset.y
	var right := corner == Control.PRESET_TOP_RIGHT or corner == Control.PRESET_BOTTOM_RIGHT
	var bottom := corner == Control.PRESET_BOTTOM_LEFT or corner == Control.PRESET_BOTTOM_RIGHT
	control.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	control.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END


func _make_card(index: int) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2((PANEL_WIDTH - 20.0) / 3.0, 96.0)
	card.clip_contents = true
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	card.add_child(box)
	var name_text := ""
	var tag := ""
	if step == Step.CAR:
		name_text = cars[index].display_name
		tag = cars[index].trait_name
	else:
		var prop := props[index]
		name_text = prop.display_name
		tag = "Passive" if prop.kind == PropData.Kind.PASSIVE else "Active"
		var icon := TextureRect.new()
		icon.texture = prop.icon
		icon.custom_minimum_size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override("separation", 0)
	box.add_child(text)
	var name_label := _label(text, 22 if step == Step.CAR else 17, Palette.UI_TEXT, 900, step == Step.PROP)
	name_label.name = "Name"
	name_label.text = name_text
	var tag_label := _label(text, 14, Palette.UI_MUTED, 750, true)
	tag_label.name = "Tag"
	tag_label.text = tag
	var pick := select_car if step == Step.CAR else select_prop
	card.pressed.connect(pick.bind(index))
	card.focus_entered.connect(pick.bind(index))
	card.set_meta(&"sfx", &"")  # picking clicks (once, however it was picked)
	return card


func _style_card(card: Button, picked: bool) -> void:
	var box := UiTheme.panel_box(Palette.UI_ACCENT if picked else Color(Palette.UI_PANEL, 0.94), 16, 10.0)
	var hover := box.duplicate() as StyleBoxFlat
	hover.bg_color = Palette.UI_ACCENT.lightened(0.06) if picked else Palette.UI_PANEL.darkened(0.06)
	var focus := box.duplicate() as StyleBoxFlat
	focus.draw_center = false
	focus.set_border_width_all(4)
	focus.border_color = Palette.UI_TEXT if picked else Palette.UI_ACCENT
	card.add_theme_stylebox_override("normal", box)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", hover)
	card.add_theme_stylebox_override("focus", focus)
	var ink := Palette.UI_TEXT_LIGHT if picked else Palette.UI_TEXT
	for label: Label in card.find_children("*", "Label", true, false):
		var muted := label.name == "Tag"
		label.add_theme_color_override("font_color", Color(ink, 0.8) if muted else ink)


func _style_swatch(swatch: Button, index: int) -> void:
	var box := UiTheme.panel_box(Palette.PLAYER_PAINTS[index], 19, 0.0)
	if index == paint_index:
		box.set_border_width_all(4)
		box.border_color = Palette.UI_TEXT
	var focus := box.duplicate() as StyleBoxFlat
	focus.set_border_width_all(4)
	focus.border_color = Palette.UI_ACCENT
	focus.draw_center = false
	for state: String in ["normal", "hover", "pressed"]:
		swatch.add_theme_stylebox_override(state, box)
	swatch.add_theme_stylebox_override("focus", focus)


func _label(parent: Node, font_size: int, color: Color, weight: int, wrap := false) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_override("font", UiTheme.font(weight))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 60
	parent.add_child(label)
	return label
