class_name TrafficSpawner
extends Node3D
## Keeps the highway full of traffic around the player and runs it.
##
## - Spawning: cars appear out in the haze ahead (and behind, when the player
##   is slow enough to be caught), at the density TrafficProfile asks for, and
##   are recycled into per-type pools once they're far away.
## - Every tick: sort everyone into lanes, let each driver think, then resolve
##   bumps (player included), award near misses and update the visuals.
## - Phantom slowdowns: now and then a slow patch appears ahead and drifts
##   back through traffic, the way real I-35 jams do for no visible reason.
## - Props: the censored gesture enrages a driver (enrage). When a raging driver
##   crashes out, 1-3 cars around it go down with it (a pileup). The truck's
##   "Bully" trait and a raging driver's lunge rewrite contacts with the player.
##
## Runs after the player car each physics tick (process_physics_priority), so it
## always sees where the player ended up.

signal near_miss(car: TrafficCar)
signal slowdown_ahead
## A raging driver crashed out and took `count - 1` others with it.
signal road_rage_ko(count: int)
## A raging driver's lunge connected with the player.
signal rage_hit
## A car crashed out (a rager or a pileup victim): crunch.
signal wrecked(car: TrafficCar)
## A driver leans on the horn (the player bumped them).
signal honked(car: TrafficCar)
## The player touched a car (Police listens for anyone hitting a cruiser).
signal player_contact(car: TrafficCar, closing: float)

const CAR_SCENE := preload("res://scenes/traffic/TrafficCar.tscn")

## Traffic exists from BEHIND meters behind the player to AHEAD meters ahead.
const AHEAD := 450.0
const BEHIND := 110.0
const MAX_SAME := 34
const MAX_ONCOMING := 16
## Oncoming traffic is lighter than ours.
const ONCOMING_SHARE := 0.55
## Free road needed around a new car, meters (plus the cars' half lengths).
const SPAWN_CLEARANCE := 22.0
## Starting grid: no traffic this close to the player at the start.
const START_CLEAR := 35.0
const START_CLEAR_BEHIND := 90.0
## Near miss: at most this much daylight (meters) between you and the car you
## pass, at this speed or more (m/s, about 50 mph), passing at least 4 m/s faster.
const NEAR_MISS_GAP := 1.1
const NEAR_MISS_MIN_SPEED := 22.0
const NEAR_MISS_MIN_CLOSING := 4.0
## Phantom slowdowns.
const WAVE_HALF_WIDTH := 70.0
const WAVE_UPSTREAM := 4.5   # m/s the slow patch drifts back toward the player
const WAVE_LIFE := 24.0
const WAVE_SPEED := 0.25     # how slow traffic gets at its heart
const WAVE_INTERVAL := Vector2(20.0, 38.0)
## Pileups: cars this close (meters) to a crashed-out rager can go down with it,
## one after another, this many seconds apart.
const PILEUP_RADIUS := 30.0
const PILEUP_STAGGER := 0.22
## Bump a driver at least this hard (closing m/s) and they lean on the horn.
const HONK_SPEED := 1.5

class Wave:
	var s := 0.0
	var age := 0.0

class PileupHit:
	var car: TrafficCar
	var delay := 0.0

## Vehicle types. Each one's spawn_weight sets how often it shows up.
##
## TODO: meme car roster. Add each meme car as data/traffic/<id>.tres (a
## TrafficCarData with its own personality) and append it to this list in
## TrafficSpawner.tscn. For custom antics, set its `behavior` to a script that
## extends TrafficBehavior. behaviors/LeftLaneCamper.gd is a worked example
## ("always camps in the left lane at 5 under").
@export var roster: Array[TrafficCarData] = []
@export var oncoming := true
## 0 = different traffic every run.
@export var rng_seed := 0

var road: RoadManager
var player: PlayerCar
var profile := TrafficProfile.uniform(7.0)
var speed_limit_mph := 75.0
var feature_paint := Color(0, 0, 0, 0)
var feature_paint_chance := 0.0
## Whether phantom slowdowns may start (off until GO and after the finish).
var waves_enabled := false
## How many TrafficCar nodes were ever created (pooling keeps this small).
var instanced_count := 0
## Stretches (from s, to s) where everyone eases off to `slow_speed` (m/s):
## drivers who've spotted a speed trap.
var slow_zones: Array[Vector2] = []
var slow_speed := 30.0

var _cars: Array[TrafficCar] = []
var _pools: Dictionary = {}  # TrafficCarData -> Array of idle TrafficCars
var _lanes := TrafficLanes.new()
var _player_fp := Footprint.new()
var _same_fps: Array[Footprint] = []
var _oncoming_fps: Array[Footprint] = []
var _waves: Array[Wave] = []
var _pileup: Array[PileupHit] = []
var _wave_in := 0.0
var _rng := RandomNumberGenerator.new()
var _time := 0.0


func setup(road_manager: RoadManager, player_car: PlayerCar, traffic_profile: TrafficProfile, limit_mph: float) -> void:
	road = road_manager
	player = player_car
	profile = traffic_profile
	speed_limit_mph = limit_mph


## Clears the road and fills it for a fresh start around the player.
func reset() -> void:
	while not _cars.is_empty():
		_release(_cars.size() - 1)
	_waves.clear()
	_pileup.clear()
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	_wave_in = _rng.randf_range(10.0, 16.0)
	_sync_player()
	_fill(1, profile.density_at(player.road_s + 150.0) * (AHEAD + BEHIND) / 1000.0 * RoadSpec.LANES)
	if oncoming:
		_fill(-1, profile.density_at(player.road_s + 150.0) * ONCOMING_SHARE * (AHEAD + BEHIND) / 1000.0 * RoadSpec.LANES)
	for car in _cars:
		car.reset_physics_interpolation()


func active_cars() -> Array[TrafficCar]:
	return _cars


## The player's rectangle in road coordinates, as traffic sees it.
func player_footprint() -> Footprint:
	return _player_fp


## Puts a trooper on the road (from a speed trap): standing still at (s, d),
## nose turned `rel_yaw` toward the road. Police tells it what to do next.
func spawn_police(type: TrafficCarData, s: float, d: float, rel_yaw: float) -> PoliceCar:
	var car := _acquire(type) as PoliceCar
	car.activate(s, TrafficLanes.nearest_lane(d), 1, 0.0, speed_limit_mph / PlayerCar.MPS_TO_MPH,
		type.paints[0] if not type.paints.is_empty() else Palette.POLICE_BLACK, _rng)
	car.speed_limit = speed_limit_mph / PlayerCar.MPS_TO_MPH
	car.fp.d = d
	car.fp.rel_yaw = rel_yaw
	car.pass_rel = s - player.road_s
	car.near_miss_ready = false
	_cars.append(car)
	car.sync_to_road(road, _time)
	car.reset_physics_interpolation()
	return car


## Places a specific car (tests, scripted moments). Returns null if blocked.
func spawn_car(type: TrafficCarData, s: float, lane: int, speed: float, direction := 1) -> TrafficCar:
	var car := _acquire(type)
	car.activate(s, lane, direction, speed, speed, _pick_paint(type), _rng)
	car.speed_limit = speed_limit_mph / PlayerCar.MPS_TO_MPH
	car.pass_rel = s - player.road_s
	_cars.append(car)
	car.sync_to_road(road, _time)
	car.reset_physics_interpolation()
	return car


## The lane to drop the player into after a spin-out: close by, and with no
## traffic bearing down on it.
func safest_lane(s: float, d: float) -> int:
	var best := TrafficLanes.nearest_lane(d)
	var best_score := -INF
	for lane in RoadSpec.LANES:
		var center := RoadSpec.lane_center(lane)
		var score := -absf(center - d) * 2.0
		for car in _cars:
			if car.dir < 0 or absf(car.fp.d - center) > RoadSpec.LANE_WIDTH * 0.75:
				continue
			var rel := car.fp.s - s
			if rel > -45.0 and rel < 0.0:
				score -= 30.0  # something coming up from behind
			elif rel >= 0.0 and rel < 20.0:
				score -= 15.0
		if score > best_score:
			best_score = score
			best = lane
	return best


func _physics_process(delta: float) -> void:
	if road == null or player == null:
		return
	_time += delta
	_sync_player()
	_update_waves(delta)
	_recycle()
	_spawn()
	_rebuild_lanes()
	for car in _cars:
		car.drive(delta, _desired_speed(car), _lanes, _rng)
	_rebuild_lanes()
	_resolve_contacts()
	_update_pileups(delta)
	_check_near_misses()
	for car in _cars:
		car.sync_to_road(road, _time, delta)


func _process(_delta: float) -> void:
	# Work-truck beacons flash together; they share one material.
	var flash := pow(maxf(0.0, sin(Time.get_ticks_msec() * 0.009)), 4.0)
	TrafficModel.beacon_material().set_shader_parameter("emission_energy", 0.6 + 3.0 * flash)


func _sync_player() -> void:
	var fp := _player_fp
	var size := player.car_data.size
	fp.s = player.road_s
	fp.d = player.road_d
	fp.rel_yaw = wrapf(player.yaw - player.road_yaw, -PI, PI)
	fp.half_len = size.z * 0.48
	fp.half_wid = size.x * 0.48
	fp.mass = player.car_data.mass
	fp.v_s = player.velocity.dot(RoadGeo.forward(player.road_yaw))
	fp.v_d = player.velocity.dot(RoadGeo.right(player.road_yaw))


func _desired_speed(car: TrafficCar) -> float:
	var v := car.cruise * profile.speed_factor_at(car.fp.s)
	if car.dir > 0:
		v *= _wave_factor(car.fp.s)
		for zone in slow_zones:
			if car.fp.s > zone.x and car.fp.s < zone.y:
				v = minf(v, slow_speed)
	return v


func _rebuild_lanes() -> void:
	_same_fps.clear()
	_oncoming_fps.clear()
	for car in _cars:
		if car.dir > 0:
			_same_fps.append(car.fp)
		else:
			_oncoming_fps.append(car.fp)
	_same_fps.append(_player_fp)
	_lanes.rebuild(_same_fps, _oncoming_fps)


# --- Spawning and recycling ---------------------------------------------------

func _recycle() -> void:
	var focus := player.road_s
	for i in range(_cars.size() - 1, -1, -1):
		var car := _cars[i]
		var rel := car.fp.s - focus
		if car is PoliceCar and (car as PoliceCar).is_pursuing():
			continue  # Police decides when a chase is over
		if car.expired or rel < -BEHIND - 15.0 or rel > AHEAD + (60.0 if car.dir > 0 else 100.0):
			_release(i)


func _spawn() -> void:
	var focus := player.road_s
	var ahead := 0
	var behind := 0
	var opposite := 0
	for car in _cars:
		if car.dir < 0:
			opposite += 1
		elif car.fp.s >= focus:
			ahead += 1
		else:
			behind += 1
	var lanes := float(RoadSpec.LANES)
	# Top up out in the haze ahead, where cars can't be seen popping in.
	var want_ahead := profile.density_at(focus + AHEAD * 0.7) * AHEAD / 1000.0 * lanes
	if ahead < want_ahead and ahead + behind < MAX_SAME:
		_try_spawn(focus + _rng.randf_range(AHEAD - 80.0, AHEAD), 1)
	# From behind only when the player is slow enough to be caught.
	var want_behind := profile.density_at(focus - BEHIND * 0.5) * BEHIND / 1000.0 * lanes
	if behind < want_behind and ahead + behind < MAX_SAME and player.speed < 24.0:
		_try_spawn(focus - BEHIND + _rng.randf_range(0.0, 20.0), 1)
	if oncoming:
		var want_opposite := profile.density_at(focus + AHEAD * 0.5) * ONCOMING_SHARE * (AHEAD + BEHIND) / 1000.0 * lanes
		if opposite < want_opposite and opposite < MAX_ONCOMING:
			_try_spawn(focus + AHEAD + _rng.randf_range(20.0, 80.0), -1)


## Scatters `count` cars over the whole window (race start).
func _fill(direction: int, count: float) -> void:
	var placed := 0
	var tries := 0
	while placed < int(count) and tries < int(count) * 4 + 8:
		tries += 1
		var s := player.road_s + _rng.randf_range(-BEHIND, AHEAD)
		if _try_spawn(s, direction, true):
			placed += 1


func _try_spawn(s: float, direction: int, at_start := false) -> bool:
	if roster.is_empty():
		return false
	var type := _pick_type()
	var lane := _pick_lane(type)
	var lead_speed := INF
	var lane_d := RoadSpec.lane_center(lane) * direction
	var half := type.size.z * 0.5
	for car in _cars:
		if car.dir != direction or absf(car.fp.d - lane_d) > RoadSpec.LANE_WIDTH * 0.9:
			continue
		var rel := (car.fp.s - s) * direction
		if absf(rel) < SPAWN_CLEARANCE + half + car.fp.reach_s():
			return false
		if rel > 0.0 and rel < 90.0:
			lead_speed = minf(lead_speed, car.speed)
	if direction > 0:
		var rel_player := player.road_s - s
		var same_lane := absf(player.road_d - lane_d) < RoadSpec.LANE_WIDTH * 0.9
		if at_start and (absf(rel_player) < START_CLEAR or (same_lane and rel_player > 0.0 and rel_player < START_CLEAR_BEHIND)):
			return false
		if absf(rel_player) < SPAWN_CLEARANCE + half + 3.0 and same_lane:
			return false
	var cruise := (speed_limit_mph + _rng.randf_range(type.speed_vs_limit_mph.x, type.speed_vs_limit_mph.y)) / PlayerCar.MPS_TO_MPH
	var start := cruise * profile.speed_factor_at(s)
	if direction > 0:
		start *= _wave_factor(s)
		if s < player.road_s:
			start = minf(start, maxf(player.speed, 0.0) + 12.0)  # come up from behind gently
	start = minf(start, lead_speed)
	var car := _acquire(type)
	car.activate(s, lane, direction, start, cruise, _pick_paint(type), _rng)
	car.speed_limit = speed_limit_mph / PlayerCar.MPS_TO_MPH
	car.pass_rel = s - player.road_s
	_cars.append(car)
	car.sync_to_road(road, _time)
	car.reset_physics_interpolation()
	return true


func _pick_type() -> TrafficCarData:
	var total := 0.0
	for type in roster:
		total += type.spawn_weight
	var roll := _rng.randf() * total
	for type in roster:
		roll -= type.spawn_weight
		if roll <= 0.0:
			return type
	return roster.back()


## Slow vehicles mostly spawn in the right-hand lanes.
func _pick_lane(type: TrafficCarData) -> int:
	var weights: Array[float] = []
	var total := 0.0
	for lane in RoadSpec.LANES:
		var w := 1.0 + type.keep_right * lane * 2.0
		weights.append(w)
		total += w
	var roll := _rng.randf() * total
	for lane in RoadSpec.LANES:
		roll -= weights[lane]
		if roll <= 0.0:
			return lane
	return RoadSpec.LANES - 1


func _pick_paint(type: TrafficCarData) -> Color:
	if not type.paints.is_empty():
		return type.paints[_rng.randi() % type.paints.size()]
	if type.body_style == TrafficCarData.BodyStyle.WORK_TRUCK:
		return Palette.WORK_YELLOW
	if feature_paint.a > 0.0 and _rng.randf() < feature_paint_chance:
		return feature_paint
	return Palette.TRAFFIC_PAINTS[_rng.randi() % Palette.TRAFFIC_PAINTS.size()]


func _acquire(type: TrafficCarData) -> TrafficCar:
	if not _pools.has(type):
		_pools[type] = []
	var pool: Array = _pools[type]
	if not pool.is_empty():
		return pool.pop_back()
	var car: TrafficCar = type.car_script.new() if type.car_script else CAR_SCENE.instantiate()
	add_child(car)
	car.build(type)
	car.crashed.connect(wrecked.emit)
	instanced_count += 1
	return car


## Pooled cars stay in the tree, hidden (they have no processing of their own).
func _release(index: int) -> void:
	var car := _cars[index]
	car.visible = false
	_pools[car.data].append(car)
	_cars.remove_at(index)


# --- Phantom slowdowns --------------------------------------------------------

func _update_waves(delta: float) -> void:
	for i in range(_waves.size() - 1, -1, -1):
		var wave := _waves[i]
		wave.age += delta
		wave.s -= WAVE_UPSTREAM * delta
		if wave.age >= WAVE_LIFE:
			_waves.remove_at(i)
	if not waves_enabled:
		return
	_wave_in -= delta
	if _wave_in > 0.0:
		return
	_wave_in = _rng.randf_range(WAVE_INTERVAL.x, WAVE_INTERVAL.y)
	var s := player.road_s + _rng.randf_range(260.0, 340.0)
	if profile.jam_weight(s) > 0.1:
		return  # the jam is slow enough already
	var wave := Wave.new()
	wave.s = s
	_waves.append(wave)
	slowdown_ahead.emit()


## Speed multiplier from phantom slowdowns at s (1 = unaffected).
func _wave_factor(s: float) -> float:
	var f := 1.0
	for wave in _waves:
		var x := absf(s - wave.s) / WAVE_HALF_WIDTH
		if x >= 1.0:
			continue
		var strength := smoothstep(0.0, 2.0, wave.age) * (1.0 - smoothstep(WAVE_LIFE - 5.0, WAVE_LIFE, wave.age))
		f = minf(f, lerpf(1.0, WAVE_SPEED, strength * (1.0 - smoothstep(0.5, 1.0, x))))
	return f


# --- Road rage ------------------------------------------------------------------

## The closest driver the player could yell at: going our way, ahead or
## alongside, within `reach` meters bumper to bumper, and not already busy
## crashing. Null when nobody qualifies.
func rage_target_near(reach: float) -> TrafficCar:
	var p := _player_fp
	var best: TrafficCar = null
	var best_dist := INF
	for car in _cars:
		if car.dir < 0 or car.mode == TrafficCar.Mode.RAGE or car.mode == TrafficCar.Mode.WRECKED \
				or car.mode == TrafficCar.Mode.KNOCKED or car is PoliceCar:
			continue  # (troopers are Police's business)
		var ds := car.fp.s - p.s
		if ds < -(car.fp.reach_s() + p.reach_s()) * 0.5:
			continue  # mostly behind us
		var gap_s := maxf(0.0, absf(ds) - car.fp.reach_s() - p.reach_s())
		var gap_d := maxf(0.0, absf(car.fp.d - p.d) - car.fp.reach_d() - p.reach_d())
		var dist := Vector2(gap_s, gap_d).length()
		if dist <= reach and dist < best_dist:
			best = car
			best_dist = dist
	return best


## Sets a driver off. `will_hit` decides whether its lunge is aimed to connect;
## the player can still dodge it.
func enrage(car: TrafficCar, will_hit: bool) -> void:
	car.enrage(_player_fp, will_hit, _rng)


## A rager that crashed out takes 1-3 nearby cars down with it, one after
## another, each spinning away from the player.
func _update_pileups(delta: float) -> void:
	for car in _cars:
		if car.crashed_out:
			car.crashed_out = false
			_start_pileup(car)
	for i in range(_pileup.size() - 1, -1, -1):
		var hit := _pileup[i]
		hit.delay -= delta
		if hit.delay > 0.0:
			continue
		_pileup.remove_at(i)
		if hit.car in _cars and not hit.car.is_wrecked():
			var away := signf(hit.car.fp.d - _player_fp.d)
			hit.car.crash_out(away if away != 0.0 else 1.0, _rng)


func _start_pileup(source: TrafficCar) -> void:
	var nearby: Array[TrafficCar] = []
	for car in _cars:
		if car != source and car.dir > 0 and not car.is_wrecked() \
				and Vector2(car.fp.s - source.fp.s, car.fp.d - source.fp.d).length() < PILEUP_RADIUS:
			nearby.append(car)
	nearby.sort_custom(func(a: TrafficCar, b: TrafficCar) -> bool:
		return absf(a.fp.s - source.fp.s) + absf(a.fp.d - source.fp.d) < absf(b.fp.s - source.fp.s) + absf(b.fp.d - source.fp.d))
	var count := mini(_rng.randi_range(1, 3), nearby.size())
	for i in count:
		var hit := PileupHit.new()
		hit.car = nearby[i]
		hit.delay = PILEUP_STAGGER * (i + 1)
		_pileup.append(hit)
	road_rage_ko.emit(1 + count)


# --- Collisions and near misses -----------------------------------------------

## Overlaps can only happen between neighbors in a band, so each body is
## checked against the next two along the road.
func _resolve_contacts() -> void:
	for b in TrafficLanes.BANDS:
		var list: Array = _lanes.band(b)
		for i in list.size():
			for j in range(i + 1, mini(i + 3, list.size())):
				_contact(list[i], list[j])


func _contact(a: Footprint, b: Footprint) -> void:
	var c := VehicleContact.between(a, b)
	if c == null:
		return
	if not a.is_player() and not b.is_player():
		_apply_contact(a, b, c.push_a, c.dv_a, c.closing, c.normal)
		_apply_contact(b, a, c.push_b, c.dv_b, c.closing, -c.normal)
		return
	# The player is in it: work from the player's side (n points player -> other).
	var flip := b.is_player()
	var other := a if flip else b
	var n := -c.normal if flip else c.normal
	var p_push := c.push_b if flip else c.push_a
	var p_dv := c.dv_b if flip else c.dv_a
	var o_push := c.push_a if flip else c.push_b
	var o_dv := c.dv_a if flip else c.dv_b
	var p_closing := c.closing
	if other.car.is_lunging() and other.car.rage_will_hit:
		_rage_landed(other.car, n)
	elif player.car_data.has_trait(&"bully") and other.mass < _player_fp.mass:
		# Bully: the lighter car takes the whole shove and gets pushed aside;
		# the truck barely notices.
		o_push -= p_push * 0.8
		p_push *= 0.2
		var away := signf(other.d - _player_fp.d)
		o_dv += Vector2(0.0, (away if away != 0.0 else 1.0) * (2.0 + c.closing * 0.35))
		p_dv *= 0.3
		p_closing *= 0.5
	_apply_contact(_player_fp, other, p_push, p_dv, p_closing, n)
	_apply_contact(other, _player_fp, o_push, o_dv, c.closing, -n)


## A raging driver's lunge connected: the player spins out (unless they just
## did) and the driver drives off, still fuming.
func _rage_landed(car: TrafficCar, n: Vector2) -> void:
	car.rage_landed()
	if player.can_spin_out():
		player.spin_out(-signf(n.y) if absf(n.y) > 0.15 else (1.0 if _rng.randf() < 0.5 else -1.0))
	rage_hit.emit()


## `normal` points from this body toward the one it touched.
func _apply_contact(fp: Footprint, other: Footprint, push: Vector2, dv: Vector2, closing: float, normal: Vector2) -> void:
	if fp.is_player():
		player.apply_contact(push, dv, closing, normal)
		_sync_player()
		if other.car:
			other.car.touched_cooldown = 1.5
			player_contact.emit(other.car, closing)
	else:
		fp.car.hit(push, dv, closing, _rng)
		if other.is_player() and closing > HONK_SPEED and fp.car.honk_cooldown <= 0.0 \
				and not fp.car.is_wrecked() and fp.car.mode != TrafficCar.Mode.RAGE:
			fp.car.honk_cooldown = 4.0
			honked.emit(fp.car)


func _check_near_misses() -> void:
	var p := _player_fp
	for car in _cars:
		if car.dir < 0:
			continue
		var rel := car.fp.s - p.s
		if rel > 12.0:
			car.near_miss_ready = true  # it got back in front; it can be passed again
		elif car.near_miss_ready and car.pass_rel > 0.0 and rel <= 0.0:
			car.near_miss_ready = false
			var gap := absf(car.fp.d - p.d) - car.fp.reach_d() - p.reach_d()
			if gap > -0.05 and gap < NEAR_MISS_GAP and p.v_s >= NEAR_MISS_MIN_SPEED \
					and p.v_s - car.fp.v_s >= NEAR_MISS_MIN_CLOSING and car.touched_cooldown <= 0.0 \
					and not player.is_spinning():
				near_miss.emit(car)
		car.pass_rel = rel
