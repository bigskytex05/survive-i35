extends TestSuite
## The three cars: honest trade-offs in their data, and they drive and crash
## differently (the truck's "Bully" trait in particular).

const TRUCK := preload("res://data/cars/truck.tres")
const SUV := preload("res://data/cars/suv.tres")
const EV := preload("res://data/cars/ev.tres")
const SEDAN := preload("res://data/traffic/sedan.tres")
const WORK_TRUCK := preload("res://data/traffic/construction_truck.tres")
const STAY_IN_LANE := preload("res://tests/StayInLaneBehavior.gd")


func _keeper() -> TrafficCarData:
	var data: TrafficCarData = SEDAN.duplicate()
	data.behavior = STAY_IN_LANE
	return data


func test_trade_offs_in_the_data() -> void:
	check(TRUCK.mass > SUV.mass and SUV.mass > EV.mass, "the truck is heaviest, the EV lightest")
	check(EV.acceleration > SUV.acceleration and SUV.acceleration > TRUCK.acceleration,
		"the EV is quickest off the line, the truck slowest")
	check(EV.steer_rate > SUV.steer_rate and SUV.steer_rate > TRUCK.steer_rate, "the EV turns tightest, the truck widest")
	check(SUV.offroad_drag < TRUCK.offroad_drag and SUV.offroad_drag < EV.offroad_drag, "the SUV is best off-road")
	check(EV.police_detection_scale < 1.0 and SUV.police_detection_scale == 1.0, "only the EV runs silent")
	for car: CarData in [TRUCK, SUV, EV]:
		check(car.has_trait(car.trait_id) and car.trait_name != "" and car.description != "", "%s has a trait and a blurb" % car.id)
		check(car.default_paint in Palette.PLAYER_PAINTS, "%s's default paint is one of the garage paints" % car.id)


func test_zero_to_sixty_order() -> void:
	var times := {}
	for car: CarData in [TRUCK, SUV, EV]:
		var race := await start_race(make_level(), false, 0.0, 99, car)
		var player: PlayerCar = race.get_node("PlayerCar")
		check(player.car_data == car, "the race uses the %s" % car.id)
		var frames := 0
		while player.speed_mph() < 60.0 and frames < 1200:
			await hold([&"accelerate"], 1)
			frames += 1
		times[car.id] = frames / 60.0
		await end_race(race)
	check(times[&"ev"] < times[&"suv"] and times[&"suv"] < times[&"truck"],
		"0-60: EV %.1f s < SUV %.1f s < truck %.1f s" % [times[&"ev"], times[&"suv"], times[&"truck"]])


## Rear-ends a sedan at 8 m/s closing speed and reports what happened.
func _rear_end_sedan(car: CarData) -> Dictionary:
	var race := await start_race(make_level(), true, 0.0, 99, car)
	var player: PlayerCar = race.get_node("PlayerCar")
	var traffic: TrafficSpawner = race.get_node("TrafficSpawner")
	place_player(player, race.get_node("RoadManager"), 0.0, RoadSpec.lane_center(1), 30.0)
	var sedan := traffic.spawn_car(_keeper(), car.size.z * 0.5 + 2.4 + 3.0, 1, 22.0)
	var lowest := 30.0
	var touched := false
	for i in 90:
		await hold([], 1)
		lowest = minf(lowest, player.speed)
		touched = touched or sedan.touched_cooldown > 0.0
	var result := {
		"lowest": lowest,
		"shoved": absf(sedan.fp.d - RoadSpec.lane_center(1)),
		"spun": race.stats.spin_outs,
		"touched": touched,
	}
	await end_race(race)
	return result


func test_truck_bullies_lighter_cars() -> void:
	var truck := await _rear_end_sedan(TRUCK)
	var suv := await _rear_end_sedan(SUV)
	check(truck.touched and suv.touched, "both cars hit the sedan")
	check(truck.lowest > suv.lowest + 2.0, "the truck keeps its speed (%.1f m/s vs the SUV's %.1f)" % [truck.lowest, suv.lowest])
	check(truck.lowest > 25.0, "it barely notices (%.1f m/s left of 30)" % truck.lowest)
	check(truck.shoved > 1.0, "the sedan is shoved out of its lane (%.2f m)" % truck.shoved)
	check(truck.spun == 0, "and the truck doesn't spin out")


func test_heavier_things_still_win_against_the_truck() -> void:
	var race := await start_race(make_level(), true, 0.0, 99, TRUCK)
	var player: PlayerCar = race.get_node("PlayerCar")
	var traffic: TrafficSpawner = race.get_node("TrafficSpawner")
	place_player(player, race.get_node("RoadManager"), 0.0, RoadSpec.lane_center(2), 32.0)
	traffic.spawn_car(WORK_TRUCK, 30.0, 2, 18.0)
	var spun := false
	for i in 120:
		await hold([], 1)
		spun = spun or player.is_spinning()
	check(spun, "rear-ending a work truck at 14 m/s still spins the truck out")
	await end_race(race)
