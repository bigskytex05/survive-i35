extends TestSuite
## The race from countdown to results: input is locked during the countdown,
## crossing the finish line wins, the clock running out fails.


func _results_open(race: Node3D) -> bool:
	return (race.get_node("ResultsScreen") as ResultsScreen).is_open()


func test_countdown_holds_the_car_then_go() -> void:
	var race := await start_race(make_level(), false, 3.0)
	var car: PlayerCar = race.get_node("PlayerCar")
	var clock: RaceClock = race.get_node("RaceClock")
	await hold([&"accelerate"], 150)
	check(race.state == Race.State.COUNTDOWN, "still counting down after 2.5 s")
	check(car.speed < 0.01, "the gas does nothing before GO (%.2f m/s)" % car.speed)
	check(not clock.running and clock.time_left == 600.0, "the clock waits for GO")
	await hold([&"accelerate"], 60)
	check(race.state == Race.State.RACING, "GO after 3 s")
	check(car.speed > 1.0, "and the car pulls away")
	check(clock.running and clock.time_left < 600.0, "the clock is running")
	await end_race(race)


func test_finish_line_wins() -> void:
	var race := await start_race(make_level(320.0, 60.0), false)
	var car: PlayerCar = race.get_node("PlayerCar")
	var clock: RaceClock = race.get_node("RaceClock")
	var markers: RouteMarkers = race.get_node("RouteMarkers")
	for i in 900:
		await hold([&"accelerate"], 1)
		if race.state != Race.State.RACING:
			break
	check(race.state == Race.State.FINISHED, "crossing s = 320 finishes (state %d, s %.1f)" % [race.state, car.road_s])
	check(car.road_s >= 320.0, "at the line")
	var left := clock.time_left
	check(left > 40.0 and not clock.running, "the clock stops with time left (%.1f)" % left)
	check((markers.get_node("Finish") as Node3D).visible, "the finish gantry is up")
	check(not car.input_enabled, "the player is done driving")
	var crossing_speed := car.speed
	await hold([&"accelerate"], int(Race.RESULTS_DELAY * 60.0) + 5)
	check(_results_open(race), "the results screen opens")
	check(clock.time_left == left, "and the clock stays stopped")
	check(car.speed < crossing_speed - 8.0, "the car brakes itself (%.1f -> %.1f m/s)" % [crossing_speed, car.speed])
	await end_race(race)


func test_running_out_of_time_fails() -> void:
	var race := await start_race(make_level(5000.0, 2.0), false)
	var car: PlayerCar = race.get_node("PlayerCar")
	await hold([&"accelerate"], 130)
	check(race.state == Race.State.FAILED, "time's up after 2 s (state %d)" % race.state)
	check(not car.input_enabled, "controls locked")
	check(not race.get_node("PauseMenu").allowed, "no pausing over the results")
	await hold([], int(Race.RESULTS_DELAY * 60.0) + 5)
	check(_results_open(race), "the fail screen opens")
	await end_race(race)


func test_near_miss_after_finish_is_ignored() -> void:
	var race := await start_race(make_level(320.0, 60.0), false)
	for i in 900:
		await hold([&"accelerate"], 1)
		if race.state != Race.State.RACING:
			break
	var clock: RaceClock = race.get_node("RaceClock")
	var left := clock.time_left
	race._on_near_miss(null)
	check(clock.time_left == left and race.stats.near_misses == 0, "no bonus once the race is over")
	await end_race(race)
