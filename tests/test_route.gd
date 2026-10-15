extends TestSuite
## Level data: corridor towns, mile mapping, the clock's formatting and the
## traffic profile (busy towns, metro jams).


func _level(start: StringName, destination: StringName, distance: float) -> LevelData:
	var level := LevelData.new()
	level.start_town = start
	level.destination = destination
	level.distance_m = distance
	return level


func test_towns_between_in_driving_order() -> void:
	var south: Array[StringName] = [&"temple", &"salado", &"georgetown", &"round_rock"]
	check(Corridor.towns_between(&"waco", &"austin") == south, "Waco to Austin passes Temple..Round Rock (got %s)" % [Corridor.towns_between(&"waco", &"austin")])
	var north := Corridor.towns_between(&"austin", &"dallas")
	check(north.size() == 7 and north[0] == &"round_rock" and north[6] == &"hillsboro", "Austin to Dallas, northbound (got %s)" % [north])


func test_route_maps_miles() -> void:
	var route := RouteMap.from_level(_level(&"round_rock", &"austin", 4000.0))
	check_near(route.mile_at(0.0), 252.0, 1e-6, "starts at Round Rock's mile")
	check_near(route.mile_at(4000.0), 234.0, 1e-6, "ends at Austin's mile")
	check_near(route.s_at_mile(243.0), 2000.0, 1e-6, "halfway in miles is halfway in meters")
	check_near(route.miles_left(1000.0), 13.5, 1e-6, "miles left")
	check(route.towns.is_empty(), "no towns between Round Rock and Austin")
	var marks := route.marks(5.0)
	check(marks == [235.0, 240.0, 245.0, 250.0], "5-mile marks inside the route (got %s)" % [marks])
	check(route.mile_step(180.0) == 1.0, "1-mile posts are far enough apart on a short trip")
	var long := RouteMap.from_level(_level(&"austin", &"dallas", 9000.0))
	check(long.mile_step(180.0) == 5.0, "a long trip spaces its posts out (got %s)" % long.mile_step(180.0))
	check(long.towns.size() == 7 and long.towns[0]["s"] < long.towns[1]["s"], "towns in order along the road")


func test_profile_jams_and_towns() -> void:
	var level := _level(&"round_rock", &"austin", 4000.0)
	level.traffic_density = 8.0
	var profile := TrafficProfile.for_level(level, RouteMap.from_level(level))
	check(profile.jams.size() == 1, "Austin has a jam on its approach")
	var jam := profile.jams[0]
	check_near(jam.y, 4000.0 - TrafficProfile.JAM_OPEN_RUN, 1e-6, "the jam clears before the finish")
	var mid := (jam.x + jam.y) * 0.5
	check_near(profile.jam_weight(mid), 1.0, 1e-6, "inside the jam")
	check_near(profile.speed_factor_at(mid), TrafficProfile.JAM_SPEED, 1e-6, "slow inside the jam")
	check_near(profile.speed_factor_at(3990.0), 1.0, 1e-6, "open road at the finish")
	check(profile.density_at(mid) > profile.density_at(2000.0) * 1.8, "the jam is packed")
	check(profile.density_at(0.0) > profile.density_at(2000.0) * 1.4, "busy near Round Rock")
	var from_dallas := _level(&"dallas", &"austin", 9000.0)
	var p2 := TrafficProfile.for_level(from_dallas, RouteMap.from_level(from_dallas))
	check(p2.jams.size() == 2 and p2.jam_weight(100.0) > 0.99, "leaving Dallas starts in a jam too")


func test_clock_format() -> void:
	check(RaceClock.format(180.0) == "3:00", "3:00 (got %s)" % RaceClock.format(180.0))
	check(RaceClock.format(179.4) == "2:59", "rounds down (got %s)" % RaceClock.format(179.4))
	check(RaceClock.format(9.46) == "9.5", "tenths in the last ten seconds (got %s)" % RaceClock.format(9.46))
	check(RaceClock.format_precise(42.25) == "0:42.2" or RaceClock.format_precise(42.25) == "0:42.3", "results format (got %s)" % RaceClock.format_precise(42.25))
	check(RaceClock.format_precise(65.0) == "1:05.0", "pads seconds (got %s)" % RaceClock.format_precise(65.0))
