extends Node
## Balance check: an autopilot drives a level on several traffic seeds and
## reports how much time it had left. Run tools/run_balance.sh.
##
## - Default: a cautious, decent driver (keeps to lanes, changes lanes when
##   blocked, checks its mirrors, rarely crashes). Its times are a floor that
##   real players should beat.
## - SKILL=1: a confident driver who weaves early, brakes late and uses the
##   shoulder in cars that don't mind it (SUV, truck). Closer to a good player.
## Both take the stadium exit (or any site's lot) near the end, and brake to
## the limit for a speed trap once the cruiser's in sight (SPOT_TRAP meters),
## unless they have the Radar Detector.
##
## Env: LEVEL (res:// path, default Kickoff), SEEDS (comma list), CAR (res://
## path to a CarData, default the scene's SUV), SKILL (1 = confident driver),
## TRAPS (override the level's speed-trap count), TRAFFIC (0 = empty road, to
## measure what the road itself, exits and traps cost).

const RACE_SCENE := preload("res://scenes/race/Race.tscn")
## Where on the stadium ramp the bot aims (meters right of the median).
const EXIT_D := 19.5
## How far ahead the bot notices a parked cruiser.
const SPOT_TRAP := 220.0

var _skilled := false
var _look_ahead := 150.0
var _caution := 1.0        # seconds of closing speed treated as "already blocked"
var _switch_gain := 10.0   # meters of extra free road worth a lane change
var _target_d := 0.0
var _traffic := true


func _ready() -> void:
	_skilled = OS.get_environment("SKILL") == "1"
	if _skilled:
		_look_ahead = 220.0
		_caution = 0.35
		_switch_gain = 4.0
	var level_path := OS.get_environment("LEVEL")
	var level: LevelData = load(level_path if level_path != "" else "res://data/levels/01_kickoff.tres")
	if OS.get_environment("TRAPS") != "":
		level = level.duplicate()
		level.speed_traps = int(OS.get_environment("TRAPS"))
	_traffic = OS.get_environment("TRAFFIC") != "0"
	var seeds := OS.get_environment("SEEDS")
	var car_path := OS.get_environment("CAR")
	var car: CarData = load(car_path) if car_path != "" else null
	print("%s: %.0f m in %s%s%s, %d speed traps%s" % [level.title, level.distance_m, RaceClock.format(level.time_limit),
		", %s" % car.display_name if car else "", ", confident driver" if _skilled else ", careful driver",
		level.speed_traps, "" if _traffic else ", no traffic"])
	for seed_text in (seeds if seeds != "" else "7,11,23,42,99").split(","):
		await _run(level, int(seed_text), car)
	get_tree().quit()


func _run(level: LevelData, seed_value: int, car: CarData) -> void:
	var race: Race = RACE_SCENE.instantiate()
	race.level = level
	race.countdown_seconds = 0.0
	race.traffic_enabled = _traffic
	race.police_seed = seed_value
	if car:
		race.car_data = car
	(race.get_node("TrafficSpawner") as TrafficSpawner).rng_seed = seed_value
	add_child(race)
	await get_tree().physics_frame
	_target_d = RoadSpec.lane_center(race.start_lane)
	while race.state == Race.State.RACING:
		_drive(race)
		await get_tree().physics_frame
	var outcome := "made it, %s left" % RaceClock.format_precise(race.clock.time_left) if race.state == Race.State.FINISHED \
		else "out of time, %.1f mi short" % race.route.miles_left(race.car.road_s)
	print("  seed %3d: %-26s near misses %d, spin-outs %d, tickets %d, top %d mph" % [seed_value, outcome,
		race.stats.near_misses, race.stats.spin_outs, race.stats.tickets, roundi(race.stats.top_speed_mph)])
	for action in [&"accelerate", &"brake", &"steer_left", &"steer_right"]:
		Input.action_release(action)
	race.queue_free()
	await get_tree().process_frame


## The lane centers this driver will use: the three lanes, plus the outer
## shoulder for a confident driver in a car that barely slows on it.
func _centers(car: PlayerCar) -> Array[float]:
	var centers: Array[float] = []
	for lane in RoadSpec.LANES:
		centers.append(RoadSpec.lane_center(lane))
	if _skilled and car.car_data.offroad_drag <= 0.6:
		centers.append((RoadSpec.lanes_outer_edge() + RoadSpec.shoulder_outer_edge()) * 0.5)
	return centers


func _drive(race: Race) -> void:
	var car := race.car
	var centers := _centers(car)
	var n := centers.size()
	var free: Array[float] = []
	var can_enter: Array[bool] = []
	for i in n:
		free.append(INF)
		can_enter.append(true)
	var v := car.velocity.dot(RoadGeo.forward(car.road_yaw))
	for c in race.traffic.active_cars():
		var rel := c.fp.s - car.road_s
		if c.dir < 0 or rel < -40.0 or rel > _look_ahead:
			continue
		for i in n:
			if absf(c.fp.d - centers[i]) >= c.fp.reach_d() + 1.2:
				continue
			var mine := absf(car.road_d - centers[i]) < 1.0
			if not mine and rel < 6.0 and rel > -c.fp.reach_s() - 4.0:
				can_enter[i] = false  # alongside
			elif not mine and rel < 0.0 and rel > -25.0 and c.speed > v + 3.0:
				can_enter[i] = false  # closing fast from behind
			if rel > 0.0:
				# Free road: the gap, minus what closing speed will eat soon.
				free[i] = minf(free[i], rel - c.fp.reach_s() - 2.5 - maxf(0.0, v - c.speed) * _caution)
	var here := _nearest(centers, car.road_d)
	var target := _nearest(centers, _target_d)
	var to_finish := race.route.distance - car.road_s
	if race.finish_site and race.finish_site.finish_min_d > 0.0 and to_finish < 420.0:
		# Head for the exit: work over to the right, then onto the ramp.
		if to_finish < 250.0 and here >= n - 2:
			_target_d = EXIT_D
		elif here == target and target < n - 1 and can_enter[target + 1]:
			_target_d = centers[target + 1]
	elif absf(car.road_d - centers[target]) < 0.6 and free[target] < (90.0 if _skilled else 60.0):
		var best := target
		for i in [target - 1, target + 1]:
			if i >= 0 and i < n and can_enter[i] and free[i] > free[best] + _switch_gain:
				best = i
		_target_d = centers[best]
	# Steer toward where we'll be in a moment, so it doesn't overshoot the lane.
	var v_side := car.velocity.dot(RoadGeo.right(car.road_yaw))
	var err := _target_d - (car.road_d + v_side * 0.45)
	_press(&"steer_right", err > 0.25)
	_press(&"steer_left", err < -0.25)
	var on_exit := _target_d == EXIT_D
	var tight := INF if on_exit else minf(free[here], free[_nearest(centers, _target_d)])
	var mph := car.speed_mph()
	var cap := INF
	if _trap_ahead(race):
		cap = race.speed_limit_mph + 2.0
	if race.ticket.is_open():
		race.ticket.close()
	_press(&"brake", (tight < 0.0 and v > 8.0) or mph > cap + 2.0)
	_press(&"accelerate", tight >= (2.0 if _skilled else 4.0) and mph < cap)


## A parked cruiser within sight that would clock us (no Radar Detector).
func _trap_ahead(race: Race) -> bool:
	if race.props.blocks_speed_traps():
		return false
	for trap in race.police.traps:
		var rel := trap.s - race.car.road_s
		if trap.placed and not trap.launched and rel > -Police.DETECT_AFTER and rel < SPOT_TRAP:
			return true
	return false


static func _nearest(centers: Array[float], d: float) -> int:
	var best := 0
	for i in centers.size():
		if absf(centers[i] - d) < absf(centers[best] - d):
			best = i
	return best


func _press(action: StringName, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)
