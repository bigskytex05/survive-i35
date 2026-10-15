extends TestSuite
## Police: where speed traps go, who gets clocked, chases, pull-overs and
## getaways. Tests use an empty road and place their own traps and cruisers
## (make_level has no traps).

const RADAR := preload("res://data/props/radar_detector.tres")
const BEAMS := preload("res://data/props/high_beams.tres")
const GESTURE := preload("res://data/props/censored_gesture.tres")
const EV := preload("res://data/cars/ev.tres")
const SUV := preload("res://data/cars/suv.tres")
const POLICE := preload("res://data/traffic/police.tres")
const SEDAN := preload("res://data/traffic/sedan.tres")
const TRAP_S := 900.0


## A race with one trap (cruiser at TRAP_S) and the player in the middle lane
## at road position `s`, doing `speed` m/s.
func _race_with_trap(speed: float, s := 700.0, prop: PropData = null, car: CarData = null) -> Race:
	var race: Race = await start_race(make_level(), true, 0.0, 99, car, prop)
	race.police.add_trap(TRAP_S)
	race.road.update_stream(s)
	place_player(race.car, race.road, s, RoadSpec.lane_center(1), speed)
	await hold([], 2)
	return race


## Holds the player's speed steady (cruise control) for some frames.
func _cruise(race: Race, speed: float, frames: int) -> void:
	await hold([], 0)
	for i in frames:
		race.car.velocity = RoadGeo.forward(race.car.yaw) * speed
		race.car.speed = speed
		await get_tree().physics_frame


## A trooper in traffic at (s, d) doing `speed`, not chasing anybody (yet).
func _cruiser(race: Race, s: float, d: float, speed: float) -> PoliceCar:
	var cop := race.traffic.spawn_police(POLICE, s, d, 0.0)
	cop.speed = speed
	cop.fp.v_s = speed
	return cop


func test_traps_are_spread_over_open_road() -> void:
	var race: Race = await start_race(make_level(5600.0, 180.0, 0.0, true, 3), false)
	var traps := race.police.traps
	check(traps.size() == 3, "Kickoff-sized trip: three traps (got %d)" % traps.size())
	var last := -INF
	var jam_from := race.traffic.profile.jams[0].x if not race.traffic.profile.jams.is_empty() else INF
	for trap in traps:
		check(trap.s >= Police.START_CLEAR, "none right at the start (%.0f)" % trap.s)
		check(trap.s <= 5600.0 - Police.END_CLEAR - race.finish_site.straight_before, "none at the stadium (%.0f)" % trap.s)
		check(trap.s < jam_from - Police.JAM_CLEAR, "none in the Austin jam (%.0f)" % trap.s)
		check(trap.s - last > 300.0, "spread out (%.0f after %.0f)" % [trap.s, last])
		last = trap.s
	var spans := Police._open_road(0.0, 1000.0, ([Vector2(300.0, 400.0)] as Array[Vector2]))
	check(spans == ([Vector2(0.0, 150.0), Vector2(550.0, 1000.0)] as Array[Vector2]), "jams are cut out of the open road")
	await end_race(race)


func test_speeding_through_a_trap_starts_a_chase() -> void:
	var race := await _race_with_trap(40.0)
	var trap := race.police.traps[0]
	check(trap.placed, "the trap is built once the road reaches it")
	check(trap.get_node_or_null("ParkedCruiser") != null, "with a cruiser parked behind cover")
	var reasons: Array[StringName] = []
	race.police.chase_started.connect(func(_cop: PoliceCar, reason: StringName) -> void: reasons.append(reason))
	await hold([&"accelerate"], 90)
	check(reasons.is_empty(), "not clocked yet, 100+ m out: there's time to spot it and brake")
	await hold([&"accelerate"], 150)
	check(reasons == ([&"speeding"] as Array[StringName]), "clocked speeding (got %s)" % [reasons])
	check(race.police.cop != null and race.police.cop.is_pursuing(), "a cruiser is after you")
	check(trap.launched and trap.get_node_or_null("ParkedCruiser") == null, "it left its hiding spot")
	check(race.police.clocked_mph > race.speed_limit_mph + Police.GRACE_MPH, "clocked over the limit")
	check(race.hud.pursuit_meter().visible, "the pursuit meter shows")
	check(Sfx.is_looping(race.audio.siren()), "siren on")
	await end_race(race)


func test_at_the_limit_nothing_happens() -> void:
	var race := await _race_with_trap(33.0, 780.0)  # 74 mph
	await _cruise(race, 33.0, 300)
	check(race.car.road_s > TRAP_S + Police.DETECT_AFTER, "drove right past the trap")
	check(race.police.cop == null, "no chase at the limit")
	check(not race.police.traps[0].launched, "the cruiser stays put")
	await end_race(race)


func test_traffic_eases_off_near_a_trap() -> void:
	var race := await _race_with_trap(20.0)
	var near := race.traffic.spawn_car(SEDAN, TRAP_S - 60.0, 0, 34.0)
	near.cruise = 36.0
	var away := race.traffic.spawn_car(SEDAN, TRAP_S + 200.0, 0, 34.0)
	away.cruise = 36.0
	check(race.traffic._desired_speed(near) <= race.traffic.slow_speed + 0.01, "drivers who've spotted the cop slow down")
	check(race.traffic._desired_speed(away) > race.traffic.slow_speed + 1.0, "everyone else doesn't")
	await end_race(race)


func test_the_ev_is_harder_to_clock() -> void:
	var race := await _race_with_trap(42.0, TRAP_S - 50.0, null, EV)
	check(race.police.detection_radius(EV) < race.police.detection_radius(SUV), "Silent Running shrinks the radar's reach")
	check(race.police.detection_radius(SUV) > 50.0, "(an SUV would be clocked from here)")
	await _cruise(race, 42.0, 1)
	check(race.police.cop == null, "50 m out at 94 mph: the EV slips under the radar...")
	await _cruise(race, 42.0, 40)
	check(race.police.cop != null, "...until it gets close")
	await end_race(race)


func test_radar_detector_beats_traps() -> void:
	var race := await _race_with_trap(42.0, 600.0, RADAR)
	var dodged: Array[SpeedTrap] = []
	race.police.trap_dodged.connect(func(trap: SpeedTrap) -> void: dodged.append(trap))
	check(race.props.prop.threat > 0.2, "the detector lights up as a trap gets near")
	await _cruise(race, 42.0, 560)
	check(race.car.road_s > TRAP_S + 50.0, "blew right past it")
	check(race.police.cop == null, "and nobody came after you")
	check(dodged.size() == 1, "the HUD gets a 'trap dodged'")
	check_near(race.police.threat_at(race.car.road_s), 0.0, 0.001, "all quiet once it's behind you")
	await end_race(race)


func test_hitting_a_parked_cruiser_starts_a_chase_even_with_radar() -> void:
	var race := await _race_with_trap(10.0, 860.0, RADAR)
	var trap := race.police.traps[0]
	place_player(race.car, race.road, trap.s - 7.0, trap.d, 8.0)
	await hold([&"accelerate"], 60)
	check(race.police.cop != null and race.police.chase_reason == &"rammed", "rammed a trooper: chase")
	await end_race(race)


func test_high_beaming_a_trooper() -> void:
	var race: Race = await start_race(make_level(), true, 0.0, 99, null, BEAMS)
	place_player(race.car, race.road, 0.0, RoadSpec.lane_center(1), 28.0)
	var cop := _cruiser(race, 22.0, RoadSpec.lane_center(1), 28.0)
	await hold([], 1)
	Input.action_press(&"use_prop")
	await get_tree().physics_frame
	Input.action_release(&"use_prop")
	await get_tree().physics_frame
	await get_tree().physics_frame  # the beam reaches out on the next tick
	check(race.police.cop == cop and race.police.chase_reason == &"high_beams", "high-beamed a trooper: chase")
	check(not cop.is_blinded(), "troopers don't get blinded")
	await end_race(race)


func test_flipping_off_a_trooper() -> void:
	var race: Race = await start_race(make_level(), true, 0.0, 99, null, GESTURE)
	place_player(race.car, race.road, 0.0, RoadSpec.lane_center(1), 25.0)
	var cop := _cruiser(race, 6.0, RoadSpec.lane_center(2), 25.0)
	await hold([], 1)
	Input.action_press(&"use_prop")
	await get_tree().physics_frame
	Input.action_release(&"use_prop")
	await get_tree().physics_frame
	check(race.police.cop == cop and race.police.chase_reason == &"gesture", "flipped off a trooper: chase")
	check(race.hud.is_gesture_showing(), "(censored, of course)")
	check(cop.mode != TrafficCar.Mode.RAGE, "troopers don't road-rage; they write tickets")
	await end_race(race)


func test_pulled_over_after_two_seconds_alongside() -> void:
	var race: Race = await start_race(make_level(), true, 0.0, 99)
	place_player(race.car, race.road, 0.0, RoadSpec.lane_center(1), 30.0)
	var cop := _cruiser(race, 0.0, RoadSpec.lane_center(2), 30.0)
	race.police.provoke(cop, &"rammed")
	var start_clock := race.clock.time_left
	await _cruise(race, 30.0, 60)
	check(race.stats.tickets == 0, "not after one second")
	check(race.hud.pursuit_meter().caught > 0.3, "the meter fills red while it's alongside")
	await _cruise(race, 30.0, 75)
	check(race.stats.tickets == 1, "pulled over after two seconds alongside")
	check(race.ticket.is_open() and get_tree().paused, "the ticket's up and the world waits")
	check_near(race.clock.time_left, start_clock - 2.0 - Police.TICKET_PENALTY, 0.3, "fifteen seconds off")
	check(race.car.road_d > RoadSpec.lanes_outer_edge(), "you're on the shoulder")
	check(cop.duty == PoliceCar.Duty.PARKED and cop.fp.s < race.car.road_s, "with the cruiser parked behind you")
	race.ticket.close()
	await hold([], 3)
	check(not get_tree().paused and race.state == Race.State.RACING, "then back to the race")
	check(race.police.cop == null and not race.hud.pursuit_meter().visible, "chase over")
	await end_race(race)


func test_getting_away() -> void:
	var race: Race = await start_race(make_level(), true, 0.0, 99)
	place_player(race.car, race.road, 0.0, RoadSpec.lane_center(1), 40.0)
	var cop := _cruiser(race, -60.0, RoadSpec.lane_center(1), 30.0)
	race.police.provoke(cop, &"rammed")
	var escapes: Array[PoliceCar] = []
	race.police.escaped.connect(func(gone: PoliceCar) -> void: escapes.append(gone))
	# Stuck in traffic way back there.
	for i in 300:
		cop.fp.s = race.car.road_s - Police.ESCAPE_GAP - 30.0
		cop.speed = 30.0
		race.car.velocity = RoadGeo.forward(race.car.yaw) * 40.0
		await get_tree().physics_frame
	check(escapes.is_empty() and race.police.cop == cop, "five seconds clear isn't enough")
	check(race.hud.pursuit_meter().losing > 0.5, "but the meter shows you're losing him")
	for i in 200:
		cop.fp.s = race.car.road_s - Police.ESCAPE_GAP - 30.0
		await get_tree().physics_frame
	check(escapes == ([cop] as Array[PoliceCar]), "eight seconds clear: lost him")
	check(not cop.is_pursuing() and race.police.cop == null, "the trooper gives up")
	check(race.stats.escapes == 1, "and it counts")
	# Way out of sight is instant.
	var second := _cruiser(race, race.car.road_s + 10.0, RoadSpec.lane_center(2), 30.0)
	race.police.provoke(second, &"rammed")
	second.fp.s = race.car.road_s - Police.LOST_GAP - 10.0
	await hold([], 2)
	check(race.police.cop == null, "out of sight: gone")
	await end_race(race)


## The real thing: no help, open road. A trooper launched from a trap catches a
## flat-out SUV and pulls it over.
func test_a_trooper_catches_a_speeder() -> void:
	var race := await _race_with_trap(44.0)
	var frames := 0
	while race.stats.tickets == 0 and frames < 2400:
		await hold([&"accelerate"], 30)
		frames += 30
	check(race.stats.tickets == 1, "caught within 40 s on an open road (took %.1f s)" % (frames / 60.0))
	if race.ticket.is_open():
		race.ticket.close()
	await end_race(race)


func test_results_list_tickets() -> void:
	var race: Race = await start_race(make_level(), false)
	race.stats.tickets = 1
	race.stats.ticket_time = 15.0
	race.results.show_win(race.level, race.stats, 20.0)
	var texts: Array[String] = []
	for label in race.results.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	check("Tickets" in texts and "1  (-15s)" in texts, "results show tickets (got %s)" % [texts])
	await end_race(race)
