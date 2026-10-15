extends TestSuite
## The garage: picking a car, paint and prop, and handing that loadout to the race.

const GARAGE := preload("res://scenes/main/Garage.tscn")
const TRUCK := preload("res://data/cars/truck.tres")


func _open_garage() -> Garage:
	var garage: Garage = GARAGE.instantiate()
	garage.change_scene_on_go = false
	add_child(garage)
	await get_tree().process_frame
	return garage


func _close(garage: Garage) -> void:
	garage.queue_free()
	await get_tree().process_frame


func _send(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func test_picks_flow_into_the_race() -> void:
	GameState.clear()
	var garage := await _open_garage()
	check(garage.step == Garage.Step.CAR and garage.selected_car().id == &"suv", "starts on the car step with the SUV")
	garage.select_car(0)
	check(garage.selected_car().id == &"truck", "picks the truck")
	check(garage.selected_paint() == TRUCK.default_paint, "showing its own paint")
	garage.select_paint(4)
	garage.select_car(2)
	check(garage.selected_paint() == Palette.PLAYER_PAINTS[4], "a paint you chose sticks when you switch cars")
	garage.go_next()
	check(garage.step == Garage.Step.PROP, "Next goes to the props")
	garage.select_prop(2)
	var asked := [false]
	garage.drive_requested.connect(func() -> void: asked[0] = true)
	garage.go_next()
	check(asked[0], "Hit the Road asks for the race")
	check(GameState.has_loadout and GameState.car.id == &"ev" and GameState.prop.id == &"high_beams" \
		and GameState.paint == Palette.PLAYER_PAINTS[4], "and hands over the loadout")
	await _close(garage)

	var race: Race = await start_race(make_level(), false)
	check(race.car_data.id == &"ev" and race.car.car_data.id == &"ev", "the race drives the EV")
	check(race.paint == Palette.PLAYER_PAINTS[4], "in the chosen paint")
	check(race.props.data.id == &"high_beams", "with the high beams")
	await end_race(race)
	GameState.clear()


func test_keyboard_and_gamepad_navigation() -> void:
	GameState.clear()
	var garage := await _open_garage()
	garage._cards[2].grab_focus()
	await get_tree().process_frame
	check(garage.selected_car().id == &"ev", "moving onto a card picks it")
	await _send(&"ui_accept")
	check(garage.step == Garage.Step.PROP, "Enter / A on the picked card moves on")
	await _send(&"ui_cancel")
	check(garage.step == Garage.Step.CAR, "Esc / B goes back")
	check(garage.selected_car().id == &"ev", "keeping the pick")
	await _close(garage)


func test_coming_back_from_a_race_keeps_the_loadout() -> void:
	GameState.set_loadout(TRUCK, Palette.PLAYER_PAINTS[5], load("res://data/props/radar_detector.tres"))
	var garage := await _open_garage()
	check(garage.selected_car().id == &"truck" and garage.selected_paint() == Palette.PLAYER_PAINTS[5]
		and garage.selected_prop().id == &"radar_detector", "the garage opens on the last loadout")
	await _close(garage)
	GameState.clear()
