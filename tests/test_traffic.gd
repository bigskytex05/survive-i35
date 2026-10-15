extends TestSuite
## Traffic AI, crashes and near misses, using the real race scene. Most tests
## start with an empty road (density 0) and place the cars they need.

const SEDAN := preload("res://data/traffic/sedan.tres")
const WORK_TRUCK := preload("res://data/traffic/construction_truck.tres")
const CAMPER := preload("res://scenes/traffic/behaviors/LeftLaneCamper.gd")
const STAY_IN_LANE := preload("res://tests/StayInLaneBehavior.gd")
## Parks the player on the grass so AI-only tests run undisturbed.
const OUT_OF_THE_WAY := 25.0


func _parts(race: Node3D) -> Array:
	return [race.get_node("PlayerCar"), race.get_node("RoadManager"), race.get_node("TrafficSpawner")]


func _sedan_like(behavior: Script) -> TrafficCarData:
	var data: TrafficCarData = SEDAN.duplicate()
	data.behavior = behavior
	data.signal_chance = 1.0
	return data


func test_traffic_flows_around_a_stopped_player() -> void:
	var race := await start_race(make_level(100000.0, 600.0, 9.0))
	var car: PlayerCar = race.get_node("PlayerCar")
	var traffic: TrafficSpawner = race.get_node("TrafficSpawner")
	var start_s := car.road_s
	var start_d := car.road_d
	var overlaps := 0
	var passed := 0
	for second in 40:
		await hold([], 60)
		var cars := traffic.active_cars()
		for i in cars.size():
			if cars[i].dir > 0 and cars[i].fp.s > car.road_s + 10.0:
				passed += 1
			for j in range(i + 1, cars.size()):
				if cars[i].dir == cars[j].dir and Footprint.overlap(cars[i].fp, cars[j].fp).z > 0.1:
					overlaps += 1
	check(overlaps == 0, "traffic never piles into itself (%d overlaps)" % overlaps)
	check(absf(car.road_s - start_s) < 0.5 and absf(car.road_d - start_d) < 0.5,
		"nobody rear-ends the parked player (moved to s=%.2f d=%.2f)" % [car.road_s, car.road_d])
	check(passed > 0, "traffic gets around the player")
	check(traffic.active_cars().size() <= TrafficSpawner.MAX_SAME + TrafficSpawner.MAX_ONCOMING, "car count capped")
	check(traffic.instanced_count < 80, "cars are pooled (%d instanced)" % traffic.instanced_count)
	await end_race(race)


## Regression: on these seeds, drivers used to change lanes in behind the parked
## player with no room left to brake.
func test_nobody_merges_into_a_parked_player() -> void:
	var kickoff: LevelData = load("res://data/levels/01_kickoff.tres")
	for seed_value in [17, 19, 22, 23, 24]:
		var race := await start_race(kickoff, true, 0.0, seed_value)
		var car: PlayerCar = race.get_node("PlayerCar")
		var start_s := car.road_s
		await hold([], 25 * 60)
		check(absf(car.road_s - start_s) < 0.05 and car.speed < 0.2,
			"seed %d: the parked player wasn't hit (moved %.2f m)" % [seed_value, car.road_s - start_s])
		await end_race(race)


func test_follows_a_slow_car_without_hitting_it() -> void:
	var race := await start_race(make_level())
	var p := _parts(race)
	var car: PlayerCar = p[0]
	var traffic: TrafficSpawner = p[2]
	place_player(car, p[1], 0.0, OUT_OF_THE_WAY, 0.0)
	var keeper := _sedan_like(STAY_IN_LANE)
	var slow := traffic.spawn_car(keeper, 160.0, 1, 12.0)
	var fast := traffic.spawn_car(keeper, 60.0, 1, 32.0)
	var min_gap := INF
	for i in 900:
		await hold([], 1)
		min_gap = minf(min_gap, fast.gap_to(slow.fp))
	check(min_gap > 1.0, "the follower never touches the slow car (closest %.2f m)" % min_gap)
	check_near(fast.speed, slow.speed, 1.0, "it settles at the slow car's speed")
	check(fast.gap_to(slow.fp) < 40.0, "and follows at a sensible distance (%.1f m)" % fast.gap_to(slow.fp))
	await end_race(race)


func test_passes_a_slow_car_with_a_signal() -> void:
	var race := await start_race(make_level())
	var p := _parts(race)
	var car: PlayerCar = p[0]
	var traffic: TrafficSpawner = p[2]
	place_player(car, p[1], 0.0, OUT_OF_THE_WAY, 0.0)
	# The work truck would happily keep right too; pin it to the middle lane.
	var pinned: TrafficCarData = WORK_TRUCK.duplicate()
	pinned.behavior = STAY_IN_LANE
	var slow := traffic.spawn_car(pinned, 200.0, 1, 12.0)
	var fast := traffic.spawn_car(_sedan_like(null), 100.0, 1, 32.0)
	var signaled := false
	for i in 600:
		await hold([], 1)
		signaled = signaled or (fast.blinker() != 0 and fast.mode == TrafficCar.Mode.SIGNAL)
	check(fast.lane != 1, "the fast car changed lanes (lane %d)" % fast.lane)
	check(fast.fp.s > slow.fp.s, "and got past the work truck")
	check(signaled, "after signaling first")
	await end_race(race)


func test_behavior_hook_left_lane_camper() -> void:
	var race := await start_race(make_level())
	var p := _parts(race)
	var car: PlayerCar = p[0]
	var traffic: TrafficSpawner = p[2]
	place_player(car, p[1], 0.0, OUT_OF_THE_WAY, 0.0)
	var camper := traffic.spawn_car(_sedan_like(CAMPER), 50.0, 2, 33.0)
	camper.cruise = 36.0
	await hold([], 720)
	check(camper.lane == 0, "it heads for the fast lane (lane %d)" % camper.lane)
	var limit := 75.0 / PlayerCar.MPS_TO_MPH
	check_near(camper.speed * PlayerCar.MPS_TO_MPH, 70.0, 1.0, "and sits at 5 under the limit (%.1f m/s vs limit %.1f)" % [camper.speed, limit])
	await end_race(race)


func test_hard_rear_end_spins_out_and_recovers_in_a_lane() -> void:
	var race := await start_race(make_level())
	var p := _parts(race)
	var car: PlayerCar = p[0]
	var road: RoadManager = p[1]
	var traffic: TrafficSpawner = p[2]
	place_player(car, road, 0.0, RoadSpec.lane_center(2), 40.0)
	var truck := traffic.spawn_car(WORK_TRUCK, 30.0, 2, 20.0)
	var spun := false
	for i in 120:
		await hold([], 1)
		spun = spun or car.is_spinning()
	check(spun, "a 20 m/s rear-end spins the player out")
	check(race.stats.spin_outs == 1, "and counts one spin-out (got %d)" % race.stats.spin_outs)
	check(truck.mode == TrafficCar.Mode.KNOCKED or truck.speed > 20.5, "the truck felt it (mode %d, speed %.1f)" % [truck.mode, truck.speed])
	for i in 120:
		if not car.is_spinning():
			break
		await hold([], 1)
	check(not car.is_spinning(), "the spin ends within ~1.5 s")
	var lane_d := RoadSpec.lane_center(TrafficLanes.nearest_lane(car.road_d))
	check(absf(car.road_d - lane_d) < 0.35, "dropped back into a lane (d=%.2f)" % car.road_d)
	check(absf(wrapf(car.yaw - car.road_yaw, -PI, PI)) < 0.2, "facing down the road")
	check(car.speed >= PlayerCar.RECOVER_SPEED.x - 0.5, "rolling again (%.1f m/s)" % car.speed)
	await end_race(race)


func test_gentle_bump_slows_without_spinning() -> void:
	var race := await start_race(make_level())
	var p := _parts(race)
	var car: PlayerCar = p[0]
	var traffic: TrafficSpawner = p[2]
	place_player(car, p[1], 0.0, RoadSpec.lane_center(2), 24.0)
	var truck := traffic.spawn_car(WORK_TRUCK, 13.0, 2, 19.0)
	var touched := false
	for i in 150:
		await hold([], 1)
		touched = touched or truck.touched_cooldown > 0.0
	check(touched, "the player bumped the truck")
	check(car.speed < 21.0, "and lost speed (%.1f m/s)" % car.speed)
	check(race.stats.spin_outs == 0 and not car.is_spinning(), "but no spin-out")
	await end_race(race)


func test_near_miss_gives_time() -> void:
	var race := await start_race(make_level())
	var p := _parts(race)
	var car: PlayerCar = p[0]
	var traffic: TrafficSpawner = p[2]
	var clock: RaceClock = race.get_node("RaceClock")
	# Hug the right edge of the middle lane while passing a car in the right lane.
	place_player(car, p[1], 0.0, RoadSpec.lane_center(1) + 0.8, 40.0)
	traffic.spawn_car(WORK_TRUCK, 40.0, 2, 18.0)
	var before := clock.time_left
	await hold([&"accelerate"], 180)
	check(race.stats.near_misses == 1, "one near miss (got %d)" % race.stats.near_misses)
	check_near(clock.time_left, before - 3.0 + Race.NEAR_MISS_BONUS, 0.05, "+0.5 s on the clock")
	await end_race(race)


func test_wide_pass_is_not_a_near_miss() -> void:
	var race := await start_race(make_level())
	var p := _parts(race)
	var car: PlayerCar = p[0]
	var traffic: TrafficSpawner = p[2]
	place_player(car, p[1], 0.0, RoadSpec.lane_center(0), 40.0)
	traffic.spawn_car(WORK_TRUCK, 40.0, 2, 18.0)
	await hold([&"accelerate"], 180)
	check(race.stats.near_misses == 0, "two lanes over doesn't count (got %d)" % race.stats.near_misses)
	await end_race(race)

