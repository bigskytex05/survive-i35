extends TestSuite
## Integration: load the real race scene (no traffic, no countdown), hold
## inputs for simulated seconds, and check the car behaves.


func _start_race() -> Node3D:
	# The fixed road seed puts curves early, so lane holding is tested on bends.
	return await start_race(make_level(), false)


func _hold(actions: Array[StringName], frames: int) -> void:
	await hold(actions, frames)


func _finish(race: Node3D) -> void:
	await end_race(race)


func test_accelerates_holds_lane_and_streams_road() -> void:
	var race := await _start_race()
	var car: PlayerCar = race.get_node("PlayerCar")
	var road: RoadManager = race.get_node("RoadManager")
	var lane_d := RoadSpec.lane_center(1)
	check_near(car.road_d, lane_d, 0.05, "starts centered in the middle lane")
	await _hold([&"accelerate"], 600)
	check(car.speed_mph() > 75.0, "10 s of full throttle should pass 75 mph (got %.1f)" % car.speed_mph())
	check(car.speed_mph() <= car.car_data.top_speed_mph + 0.5, "never exceeds top speed")
	check(car.road_s > 250.0, "travelled down the road (s=%.1f)" % car.road_s)
	check(absf(car.road_d - lane_d) < 0.6, "holds its lane through bends without steering (d=%.2f)" % car.road_d)
	var worst := 0.0
	for i in 40:
		await _hold([&"accelerate"], 60)
		worst = maxf(worst, absf(car.road_d - lane_d))
	check(worst < 0.6, "stays in its lane for 40 s of curves (worst drift %.2f m)" % worst)
	check(car.road_s > 2000.0, "keeps going (s=%.1f)" % car.road_s)
	check(road.active_count() <= 8, "chunks recycled behind (active %d)" % road.active_count())
	check(road.instanced_count <= 24, "chunks pooled (instanced %d)" % road.instanced_count)
	await _finish(race)


func test_fence_and_median_contain_the_car() -> void:
	var race := await _start_race()
	var car: PlayerCar = race.get_node("PlayerCar")
	var max_d := -INF
	var min_d := INF
	await _hold([&"accelerate"], 180)
	# Steer in short pulses like a player would (steer assist straightens in between).
	for i in 40:
		await _hold([&"accelerate", &"steer_right"], 8)
		max_d = maxf(max_d, car.road_d)
		await _hold([&"accelerate"], 12)
		max_d = maxf(max_d, car.road_d)
	for i in 60:
		await _hold([&"accelerate", &"steer_left"], 8)
		min_d = minf(min_d, car.road_d)
		await _hold([&"accelerate"], 12)
		min_d = minf(min_d, car.road_d)
	check(car.speed > 5.0, "still driving forward after scraping walls (speed=%.1f)" % car.speed)
	check(max_d > 20.0, "steering right reaches the grass (max d=%.1f)" % max_d)
	check(max_d <= RoadSpec.FENCE_D, "fence holds (max d=%.2f)" % max_d)
	check(min_d >= RoadSpec.MEDIAN_HALF_BASE, "median barrier holds (min d=%.2f)" % min_d)
	check(min_d < 3.0, "steering left reaches the median (min d=%.2f)" % min_d)
	await _finish(race)


func test_brake_stops_then_reverses() -> void:
	var race := await _start_race()
	var car: PlayerCar = race.get_node("PlayerCar")
	await _hold([&"accelerate"], 240)
	var cruising := car.speed
	await _hold([&"brake"], 150)
	check(car.speed < cruising, "braking slows the car")
	check(car.speed <= 0.0, "2.5 s of braking stops (and starts reversing) (speed=%.2f)" % car.speed)
	await _hold([&"brake"], 180)
	check(car.speed < -2.0, "holding brake at a stop reverses (speed=%.2f)" % car.speed)
	check(car.speed >= -PlayerCar.REVERSE_MAX - 0.01, "reverse speed is capped")
	await _finish(race)


func test_coasting_slows_down() -> void:
	var race := await _start_race()
	var car: PlayerCar = race.get_node("PlayerCar")
	await _hold([&"accelerate"], 300)
	var before := car.speed
	await _hold([], 180)
	check(car.speed < before - 2.0, "off the gas the car slows (%.1f -> %.1f)" % [before, car.speed])
	check(car.speed > 0.0, "but doesn't stop instantly")
	await _finish(race)
