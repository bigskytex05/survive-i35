extends TestSuite
## Props in a race: the button, cooldowns, and what each prop does to traffic.
## Traffic tests start on an empty road and place the drivers they need.

const RADAR := preload("res://data/props/radar_detector.tres")
const GESTURE := preload("res://data/props/censored_gesture.tres")
const BEAMS := preload("res://data/props/high_beams.tres")
const SEDAN := preload("res://data/traffic/sedan.tres")
const STAY_IN_LANE := preload("res://tests/StayInLaneBehavior.gd")


func _keeper() -> TrafficCarData:
	var data: TrafficCarData = SEDAN.duplicate()
	data.behavior = STAY_IN_LANE
	return data


func _press_prop() -> void:
	Input.action_press(&"use_prop")
	await get_tree().physics_frame
	Input.action_release(&"use_prop")
	await get_tree().physics_frame


## A race with the prop, the player cruising in the middle lane at `speed`.
func _race_with(prop: PropData, speed := 25.0) -> Race:
	var race: Race = await start_race(make_level(), true, 0.0, 99, null, prop)
	place_player(race.car, race.road, 0.0, RoadSpec.lane_center(1), speed)
	return race


func test_radar_detector_is_passive() -> void:
	var race := await _race_with(RADAR)
	check(race.props.blocks_speed_traps(), "speed traps can't clock you")
	check(race.hud._radar.visible, "the detector is on the HUD")
	check(not race.hud._dial.visible, "no prop dial: there's nothing to press")
	check(not (race.get_node("TouchControls/Root/Prop") as Control).visible, "and no PROP touch button")
	await _press_prop()
	check(race.props.cooldown_left == 0.0, "pressing the prop button does nothing")
	await end_race(race)


func test_gesture_with_nobody_around_costs_nothing() -> void:
	var race := await _race_with(GESTURE)
	check(race.hud._dial.visible and race.hud._dial.icon == GESTURE.icon, "the HUD dial shows the prop")
	check(not race.props.blocks_speed_traps(), "only the radar detector stops speed traps")
	await _press_prop()
	check(race.props.cooldown_left == 0.0, "no target, no cooldown")
	check(not race.hud.is_gesture_showing(), "and no gesture")
	await end_race(race)


func test_gesture_miss_wrecks_the_driver_and_starts_a_pileup() -> void:
	var race := await _race_with(GESTURE)
	race.props.prop.hit_chance = 0.0
	var traffic := race.traffic
	var rager := traffic.spawn_car(_keeper(), 2.0, 2, 25.0)
	var nearby := [traffic.spawn_car(_keeper(), 24.0, 2, 25.0), traffic.spawn_car(_keeper(), 14.0, 0, 25.0)]
	var far := traffic.spawn_car(_keeper(), 120.0, 0, 25.0)
	await _press_prop()
	check(rager.mode == TrafficCar.Mode.RAGE, "the driver alongside loses it")
	check(race.hud.is_gesture_showing(), "the (censored) gesture is on screen")
	check_near(race.props.cooldown_left, 8.0 - 1.0 / 60.0, 0.02, "8 s cooldown")
	await hold([], 4 * 60)
	check(rager.is_wrecked(), "it missed, overcorrected and crashed out")
	var downed := nearby.filter(func(c: TrafficCar) -> bool: return c.is_wrecked()).size()
	check(downed >= 1, "it took cars down with it (%d of 2)" % downed)
	check(race.stats.road_rage_kos == 1 + downed, "every one is a Road Rage KO (%d)" % race.stats.road_rage_kos)
	check(not far.is_wrecked(), "cars far away are fine")
	check(race.stats.spin_outs == 0, "the player wasn't hit")
	# Park and wait for the tow truck.
	await hold([&"brake"], 3 * 60)
	await hold([], int((TrafficCar.WRECK_HOLD + TrafficCar.TOW_TIME + 1.0) * 60.0))
	check(not rager in traffic.active_cars(), "the wreck gets towed away")
	await end_race(race)


func test_gesture_hit_spins_the_player_out() -> void:
	var race := await _race_with(GESTURE)
	race.props.prop.hit_chance = 1.0
	var rager := race.traffic.spawn_car(_keeper(), 2.0, 2, 25.0)
	await _press_prop()
	var spun := false
	for i in 150:
		await hold([], 1)
		spun = spun or race.car.is_spinning()
	check(spun, "the lunge connects and the player spins out")
	check(race.stats.spin_outs == 1, "one spin-out (%d)" % race.stats.spin_outs)
	check(not rager.is_wrecked() and race.stats.road_rage_kos == 0, "and the other driver gets away with it")
	await end_race(race)


func test_gesture_hit_can_be_dodged() -> void:
	var race := await _race_with(GESTURE)
	race.props.prop.hit_chance = 1.0
	var rager := race.traffic.spawn_car(_keeper(), 2.0, 2, 25.0)
	await _press_prop()
	await hold([&"brake"], 150)
	check(race.stats.spin_outs == 0, "braking hard makes it miss")
	check(rager.is_wrecked() and race.stats.road_rage_kos >= 1, "and it crashes out instead")
	await end_race(race)


func test_high_beams_blind_drivers_ahead() -> void:
	var race := await _race_with(BEAMS, 20.0)
	var traffic := race.traffic
	var ahead := traffic.spawn_car(_keeper(), 25.0, 1, 20.0)
	var beside := traffic.spawn_car(_keeper(), 20.0, 2, 20.0)
	var behind := traffic.spawn_car(_keeper(), -20.0, 1, 20.0)
	var far := traffic.spawn_car(_keeper(), 75.0, 0, 20.0)
	check(race.props.try_use(), "the beams switch on")
	await hold([], 12)
	check(ahead.is_blinded() and beside.is_blinded(), "drivers ahead in the beam are blinded")
	check(not behind.is_blinded() and not far.is_blinded(), "nobody behind or out of reach")
	check(race.stats.drivers_blinded == 2, "two blinded (%d)" % race.stats.drivers_blinded)
	check(race.props.active_fraction() > 0.9, "the HUD sees the beams on")
	check(not race.props.try_use(), "no second go while on cooldown")
	await hold([], 150)
	check(ahead.speed < 16.0, "blinded drivers slow down (%.1f m/s of 20)" % ahead.speed)
	# Beams last 4 s; blindness wears off 3 s after the beam leaves.
	await hold([], int((BEAMS.duration + 3.2) * 60.0) - 162)
	check(race.props.active_fraction() == 0.0, "the beams are off")
	check(not ahead.is_blinded(), "and the drivers can see again")
	await end_race(race)


func test_props_only_fire_while_racing() -> void:
	var race: Race = await start_race(make_level(), false, 3.0, 99, null, BEAMS)
	await _press_prop()
	check(race.props.cooldown_left == 0.0, "not during the countdown")
	await hold([], 3 * 60)
	await _press_prop()
	check(race.props.cooldown_left > 9.0, "the button works after GO")
	await end_race(race)
