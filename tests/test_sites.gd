extends TestSuite
## Start and finish set pieces: Kickoff starts in Round Rock and ends in the
## stadium's parking lot, which you reach by the exit ramp (or by cutting right
## into the lot if you miss it). A short test level puts the finish 900 m out.

const FINISH_S := 900.0


func _site_race() -> Race:
	var race: Race = await start_race(make_level(FINISH_S, 300.0, 0.0, true), false)
	return race


func test_the_road_bends_around_the_site() -> void:
	var race := await _site_race()
	var road := race.road
	check(race.finish_site != null and race.start_site != null, "Kickoff has a start and a finish set piece")
	place_player(race.car, road, FINISH_S - 400.0, RoadSpec.lane_center(1), 0.0)
	road.update_stream(race.car.road_s)
	var zone := road.straight_zone
	for chunk in road.active_chunks():
		if chunk.end_s() > zone.x and chunk.start_s < zone.y:
			check(chunk.turn_degrees == 0.0, "straight around the finish (chunk at s=%.0f)" % chunk.start_s)
		var open := chunk.end_s() > road.open_zone.x and chunk.start_s < road.open_zone.y
		check(chunk.open_right == open, "no fence on the lot side only where the lot is (chunk at s=%.0f)" % chunk.start_s)
	check(road.surface_at(FINISH_S - 100.0, 19.5) == RoadSpec.Surface.LANE, "the exit ramp is paved")
	check(road.surface_at(FINISH_S + 200.0, 60.0) == RoadSpec.Surface.LANE, "so is the lot")
	check(road.surface_at(100.0, 19.5) == RoadSpec.Surface.GRASS, "elsewhere that's grass")
	check(road.outer_limit_at(FINISH_S + 100.0) > 100.0, "you can drive deep into the lot")
	check(road.outer_limit_at(FINISH_S - 100.0) < RoadSpec.FENCE_D, "a guardrail lines the ramp")
	check_near(road.outer_limit_at(100.0), RoadSpec.FENCE_D, 0.01, "the fence everywhere else")
	await end_race(race)


func test_taking_the_exit_finishes_in_the_lot() -> void:
	var race := await _site_race()
	place_player(race.car, race.road, FINISH_S - 180.0, 19.5, 30.0)
	for i in 600:
		await hold([&"accelerate"], 1)
		if race.state != Race.State.RACING:
			break
	check(race.state == Race.State.FINISHED, "crossing the gate on the ramp finishes (s=%.0f)" % race.car.road_s)
	check(race.car.road_d > RoadSpec.lanes_outer_edge(), "in the lot")
	await end_race(race)


func test_missing_the_exit_means_cutting_into_the_lot() -> void:
	var race := await _site_race()
	place_player(race.car, race.road, FINISH_S - 60.0, RoadSpec.lane_center(1), 30.0)
	await hold([&"accelerate"], 150)
	check(race.car.road_s > FINISH_S + 15.0, "drove past the gate on the highway (s=%.0f)" % race.car.road_s)
	check(race.state == Race.State.RACING, "which doesn't count")
	check(race.finish_site._said.has(&"missed"), "and the game says so")
	for i in 600:
		await hold([&"accelerate", &"steer_right"], 1)
		if race.state != Race.State.RACING:
			break
	check(race.state == Race.State.FINISHED, "steering right into the lot finishes (d=%.1f)" % race.car.road_d)
	await end_race(race)


func test_scoreboard_counts_down_and_the_camera_shows_off_the_stadium() -> void:
	var race := await _site_race()
	var site := race.finish_site
	await hold([], 30)
	check(site._scoreboard_main.text == RaceClock.format(float(ceili(race.clock.time_left))),
		"the scoreboard shows the race clock (%s)" % site._scoreboard_main.text)
	place_player(race.car, race.road, FINISH_S - 30.0, 19.5, 30.0)
	await hold([&"accelerate"], 90)
	check(race.state == Race.State.FINISHED, "finished")
	check(site._scoreboard_main.text == "FAN!", "the scoreboard welcomes you")
	check(race.camera._showcase >= 0.0, "the camera swings round to the stadium")
	check(site._bursts_left > 0 or not site._bursts.is_empty(), "fireworks")
	await hold([], int(Race.RESULTS_DELAY * 60.0) + 10)
	check(not race.results.is_open(), "the results wait while you look")
	await hold([], int((Race.SHOWCASE_DELAY - Race.RESULTS_DELAY) * 60.0))
	check(race.results.is_open(), "then they open")
	await end_race(race)


func test_start_site_marks_the_start_town() -> void:
	var race := await _site_race()
	var site := race.start_site
	check(site.global_position.distance_to(race.road.sample(0.0, 0.0)) < 0.01, "it stands at the start line")
	var texts: Array[String] = []
	for label: Label3D in site.find_children("*", "Label3D", true, false):
		texts.append(label.text)
	check("ROUND ROCK" in texts, "the water tower says ROUND ROCK (%s)" % [texts])
	check("AUSTIN  18" in texts, "the distance sign counts the real miles to Austin")
	check(site.find_child("DoughnutHole", true, false) != null, "and Round Rock has its doughnut shop")
	await end_race(race)
