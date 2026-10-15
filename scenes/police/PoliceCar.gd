class_name PoliceCar
extends TrafficCar
## A state trooper on the move. Parked at a speed trap it's just scenery
## (SpeedTrap draws it); when a chase starts, one of these takes its place in
## traffic:
## - PURSUIT: lights on, flat out (TOP_SPEED) until it's close, then it paces
##   you and pulls alongside in the lane next to yours (whichever side has
##   room). It brakes for traffic like anybody (that's how you lose it in a
##   jam) but weaves hard, and bumps don't rattle it.
## - PARKED: on the shoulder behind you after a ticket, lights still going.
## - OFF_DUTY: lights off, cruising like regular traffic (once you've lost it)
##   until it's recycled.
## A cruiser launched before you've reached it waits for you to go by first.

enum Duty { PURSUIT, PARKED, OFF_DUTY }

## 125 mph: faster than any of the player's cars.
const TOP_SPEED := 55.9
## Sideways speed while weaving (m/s); slower when barely moving.
const LATERAL := 4.2
## Within this many meters behind you it stops charging and paces you.
const PACE_FROM := 40.0
## Extra speed (m/s) per meter it's still behind, while pacing.
const PACE_GAIN := 0.9
## Free road (meters) a lane must offer over its current one before it switches.
const LANE_HOLD := 12.0
const LOOK_AHEAD := 300.0

var duty := Duty.OFF_DUTY
## The player's footprint (kept up to date by TrafficSpawner).
var target: Footprint

var _bars: Array[MeshInstance3D] = []
var _chase_lane := 1


func build(type: TrafficCarData) -> void:
	super(type)
	for side: float in [-1.0, 1.0]:
		var bar := _add_mesh("LightBar%d" % side, TrafficModel.police_bar_mesh(type, side))
		bar.material_override = TrafficModel.police_material(side, false)
		_bars.append(bar)


func activate(s: float, lane_index: int, direction: int, start_speed: float, cruise_speed: float,
		paint: Color, rng: RandomNumberGenerator) -> void:
	super(s, lane_index, direction, start_speed, cruise_speed, paint, rng)
	duty = Duty.OFF_DUTY
	target = null


## Lights on: chase the player.
func pursue(player: Footprint) -> void:
	duty = Duty.PURSUIT
	target = player
	mode = Mode.CRUISE
	_blink = 0
	_chase_lane = TrafficLanes.nearest_lane(fp.d)


## Lights off: back to being traffic.
func go_off_duty() -> void:
	duty = Duty.OFF_DUTY
	target = null
	lane = TrafficLanes.nearest_lane(fp.d)
	_target_lane = lane
	cruise = speed_limit
	mode = Mode.CRUISE
	_steer_yaw = 0.0


## Stopped on the shoulder at (s, d), lights on (the ticket's being written).
func park(at_s: float, at_d: float) -> void:
	duty = Duty.PARKED
	target = null
	fp.s = at_s
	fp.d = at_d
	fp.rel_yaw = 0.0
	fp.v_s = 0.0
	fp.v_d = 0.0
	speed = 0.0
	accel = 0.0
	_steer_yaw = 0.0


func is_pursuing() -> bool:
	return duty == Duty.PURSUIT


func drive(delta: float, desired: float, lanes: TrafficLanes, rng: RandomNumberGenerator) -> void:
	if duty == Duty.PARKED:
		speed = 0.0
		accel = 0.0
		fp.v_s = 0.0
		return
	if duty != Duty.PURSUIT:
		super(delta, desired, lanes, rng)
		return
	_age += delta
	touched_cooldown = maxf(0.0, touched_cooldown - delta)
	var behind := target.s - fp.s
	if behind < -fp.half_len and speed < 1.0:
		# Still parked, and you haven't come by yet: wait, then pull out behind you.
		accel = 0.0
		return
	# Across the road: toward the chosen spot, unless someone's right there.
	var want_d := _pick_d(lanes, behind)
	var lateral := minf(LATERAL, 1.0 + speed * 0.35)
	var v_d := clampf((want_d - fp.d) * 3.0, -lateral, lateral)
	if absf(v_d) > 0.05 and not _side_clear(lanes, signf(v_d)):
		v_d = 0.0
	fp.v_d = v_d
	fp.d += v_d * delta
	_clamp_to_road()
	# Along the road: charge, then pace the player to sit alongside.
	var want_v := TOP_SPEED
	if behind < PACE_FROM:
		want_v = clampf(target.v_s + behind * PACE_GAIN, 0.0, TOP_SPEED)
	accel = _idm(want_v, lanes.leader(fp, 1))
	speed = maxf(0.0, speed + accel * delta)
	fp.s += speed * delta
	fp.v_s = speed
	_steer_yaw = -atan2(fp.v_d, maxf(speed, 4.0))
	fp.rel_yaw = lerp_angle(fp.rel_yaw, _steer_yaw, 1.0 - exp(-8.0 * delta))


## Where across the road to be. Far back: the lane with the most open road.
## Close: the lane beside the player's, on whichever side is nearer.
func _pick_d(lanes: TrafficLanes, behind: float) -> float:
	if behind > PACE_FROM:
		var best := _chase_lane
		var best_free := _free_ahead(lanes, _chase_lane) + LANE_HOLD
		for i in RoadSpec.LANES:
			var free := _free_ahead(lanes, i)
			if free > best_free:
				best = i
				best_free = free
		_chase_lane = best
		return RoadSpec.lane_center(_chase_lane)
	var sides: Array[float] = []
	var left := target.d - RoadSpec.LANE_WIDTH
	var right := target.d + RoadSpec.LANE_WIDTH
	if left >= RoadSpec.lane_center(0) - 0.3:
		sides.append(left)
	if right <= RoadSpec.shoulder_outer_edge() - fp.half_wid:
		sides.append(right)
	if sides.is_empty():
		return target.d
	sides.sort_custom(func(a: float, b: float) -> bool: return absf(fp.d - a) < absf(fp.d - b))
	# The nearer side with a way through; with traffic on both sides, sit on
	# the player's bumper, ready to dive into whichever lane opens first.
	for side in sides:
		if _room_beside(lanes, side):
			return side
	return target.d


## Whether the lane at `at_d` is clear from here up to beside the player, so
## there's a way to pull up there (a slowpoke in it would hold the cruiser back).
func _room_beside(lanes: TrafficLanes, at_d: float) -> bool:
	var from := minf(fp.s, target.s) - fp.reach_s()
	var to := target.s + target.reach_s() + fp.reach_s() + 6.0
	for other: Footprint in lanes.band(TrafficLanes._band_at(absf(at_d))):
		if other != fp and other != target and other.s + other.reach_s() > from and other.s - other.reach_s() < to:
			return false
	return true


## Meters of open road ahead in a lane (the player counts as traffic).
func _free_ahead(lanes: TrafficLanes, lane_index: int) -> float:
	for other: Footprint in lanes.band(TrafficLanes.lane_band(lane_index)):
		if other != fp and other.s > fp.s:
			return minf(other.s - other.reach_s() - fp.s - fp.reach_s(), LOOK_AHEAD)
	return LOOK_AHEAD


## Nothing alongside on that side (-1 = toward the median) to sideswipe.
func _side_clear(lanes: TrafficLanes, side: float) -> bool:
	var probe := absf(fp.d) + side * (fp.reach_d() + 0.5)
	var band := TrafficLanes._band_at(maxf(probe, 0.0))
	for other: Footprint in lanes.band(band):
		if other == fp:
			continue
		if absf(other.s - fp.s) < other.reach_s() + fp.reach_s() + 1.0 \
				and signf(other.d - fp.d) == side and absf(other.d - fp.d) < other.reach_d() + fp.reach_d() + 0.8:
			return false
	return true


## Bumps don't rattle a trooper on a chase; it just gets shoved.
func hit(push: Vector2, dv: Vector2, closing: float, rng: RandomNumberGenerator) -> void:
	if duty == Duty.OFF_DUTY:
		super(push, dv, closing, rng)
		return
	fp.s += push.x
	fp.d += push.y
	speed = maxf(0.0, speed + dv.x)
	fp.v_s = speed


## High beams don't blind a trooper (they start a chase; see Police).
func blind(_seconds: float) -> bool:
	return false


func sync_to_road(road: RoadManager, time: float, delta := 0.0) -> void:
	super(road, time, delta)
	# Red, then blue, each strobing.
	var lit := duty == Duty.PURSUIT or duty == Duty.PARKED
	var cycle := fmod(time * 2.4, 1.0)
	var strobe := fmod(time * 14.0, 1.0) < 0.6
	_bars[0].material_override = TrafficModel.police_material(-1.0, lit and cycle < 0.5 and strobe)
	_bars[1].material_override = TrafficModel.police_material(1.0, lit and cycle >= 0.5 and strobe)
