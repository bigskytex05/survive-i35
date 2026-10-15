class_name TestSuite
extends Node
## Base class for headless test suites. Methods named test_* are run by
## tests/run_tests.gd; they may await frames. Run with --fixed-fps 60 so every
## physics frame is exactly 1/60 s.

const RACE_SCENE := preload("res://scenes/race/Race.tscn")
const DRIVE_ACTIONS: Array[StringName] = [&"accelerate", &"brake", &"steer_left", &"steer_right"]

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s (expected %.4f, got %.4f)" % [message, expected, actual])


func check_vec_near(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
	if actual.distance_to(expected) > tolerance:
		failures.append("%s (expected %s, got %s)" % [message, expected, actual])


## A level for tests: Kickoff's route with the given length, clock and traffic.
## Plain ends (no start or finish set pieces) unless `sites` is true, and no
## speed traps unless asked for.
static func make_level(distance := 100000.0, time_limit := 600.0, density := 0.0, sites := false,
		traps := 0) -> LevelData:
	var level: LevelData = load("res://data/levels/01_kickoff.tres").duplicate()
	level.distance_m = distance
	level.time_limit = time_limit
	level.traffic_density = density
	level.speed_traps = traps
	if not sites:
		level.start_site = null
		level.finish_site = null
	return level


## Starts a race with no countdown. Road and traffic seeds are fixed so runs
## repeat exactly. With density 0 the road stays empty until a test places cars.
## `car` and `prop` override the scene's defaults (the SUV, no prop).
func start_race(level: LevelData, traffic := true, countdown := 0.0, traffic_seed := 99,
		car: CarData = null, prop: PropData = null) -> Node3D:
	var race: Node3D = RACE_SCENE.instantiate()
	race.level = level
	race.traffic_enabled = traffic
	race.countdown_seconds = countdown
	if car:
		race.car_data = car
	if prop:
		race.prop_data = prop
	(race.get_node("RoadManager") as RoadManager).rng_seed = 1234
	(race.get_node("TrafficSpawner") as TrafficSpawner).rng_seed = traffic_seed
	add_child(race)
	# Phantom slowdowns are random; tests that want one start it themselves.
	(race.get_node("TrafficSpawner") as TrafficSpawner).waves_enabled = false
	await get_tree().physics_frame
	return race


## Holds exactly these driving inputs (releasing the rest) for some frames.
func hold(actions: Array[StringName], frames: int) -> void:
	for action in DRIVE_ACTIONS:
		if action in actions:
			Input.action_press(action)
		else:
			Input.action_release(action)
	for i in frames:
		await get_tree().physics_frame


func end_race(race: Node3D) -> void:
	await hold([], 1)
	get_tree().paused = false
	race.queue_free()
	await get_tree().process_frame


## Puts the player at road coordinate (s, d), facing down the road at `speed`.
static func place_player(car: PlayerCar, road: RoadManager, s: float, d: float, speed: float) -> void:
	car.place_at(road.sample(s, d), road.yaw_at(s))
	car.velocity = RoadGeo.forward(road.yaw_at(s)) * speed
	car.speed = speed
