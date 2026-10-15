class_name PlayerCar
extends CharacterBody3D
## Arcade car controller, tuned for touchscreens rather than realism.
##
## - Speed and heading are integrated directly; steering is gentler at speed.
## - Sideways slip decays by `grip`, so the car drifts a little in hard turns.
## - Letting go of steering makes the car follow the road's bend and ease back
##   in line with it (`steer_assist`), so tap-to-steer on a phone is comfortable.
##   Changing lanes is always the player's job; the assist never pulls sideways.
## - The median barrier and the outer fence are enforced analytically in road
##   coordinates (exact on curves, no tunneling); other solid things like
##   overpass piers use regular physics collisions.
## - The body rides on springs for toy-like roll, pitch and bounce.
## - Traffic contacts arrive from TrafficSpawner via apply_contact(). A hard hit
##   spins the car out for SPIN_TIME seconds and then sets it down in a safe
##   lane, lined up with the road. No game over: the clock is the real enemy.

signal bumped(strength: float)
signal spun_out
## Rubbing along the median barrier or the fence at `speed` m/s (every tick it touches).
signal scraped(speed: float)

const MPS_TO_MPH := 2.236936
const STEER_IN_RATE := 4.5       # digital steering ramps to full lock in ~0.2 s
const STEER_OUT_RATE := 7.0      # ...and recenters a bit faster
const FULL_STEER_SPEED := 6.0    # m/s before full steering authority (no pivoting in place)
const REVERSE_MAX := 9.0         # m/s
const REVERSE_ACCEL := 6.0
const COAST_DRAG := 1.4          # m/s^2 of engine braking off the gas
const AERO_DRAG := 0.0004        # extra coasting drag, times speed squared
const SHOULDER_DRAG := 0.12      # per second (scaled by CarData.offroad_drag)
const GRASS_DRAG := 0.5
const WALL_BOUNCE := 0.3
const SPRING_K := 140.0          # body spring stiffness
const SPRING_DAMP := 13.0        # under-damped on purpose: toys bounce
const SPIN_TIME := 1.5
const SPIN_FRICTION := 7.0       # m/s^2 of tire scrub while spinning
const SPIN_IMMUNITY := 1.2       # seconds after a spin-out before another can start
const RECOVER_SPEED := Vector2(6.0, 16.0)  # m/s range when the car is set back down

@export var car_data: CarData
## Leave transparent to use the car's default paint.
@export var paint := Color(0, 0, 0, 0)
## How strongly the car lines back up with the road when steering is released
## (0 turns the assist off entirely, including following curves).
@export_range(0.0, 4.0) var steer_assist := 1.4
@export var input_enabled := true
## Closing speed (m/s) at which a hit spins the car out (~20 mph by default).
@export var hard_crash_speed := 9.0

## Brake applied while input is disabled (rolling to a stop after the finish).
var auto_brake := 0.0
## Optional: Callable(s: float, d: float) -> int picking the lane to recover
## into after a spin-out. Defaults to the nearest lane.
var safe_lane_picker: Callable

## Injected by the race scene.
var road: RoadManager

var yaw := 0.0
## Signed speed along the car's heading, m/s (negative when reversing).
var speed := 0.0
var road_s := 0.0
var road_d := 0.0
var road_yaw := 0.0
var road_curvature := 0.0
var surface: RoadSpec.Surface = RoadSpec.Surface.LANE
## Smoothed steering, -1 (left) .. 1 (right).
var steer := 0.0
var throttle := 0.0
var brake := 0.0

var _built := false
var _yaw_rate := 0.0
var _long_accel := 0.0
var _wobble := 0.0
var _time := 0.0
var _roll := 0.0
var _roll_v := 0.0
var _pitch := 0.0
var _pitch_v := 0.0
var _heave := 0.0
var _heave_v := 0.0
var _spin_t := -1.0              # >= 0 while spinning out
var _spin_from := 0.0
var _spin_total := 0.0
var _spin_lane := -1
var _spin_immunity := 0.0

@onready var model: CarModel = $Model
@onready var _shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	if car_data and not _built:
		setup(car_data, paint)


## Builds the body and collision for a car. Safe to call again (garage swaps).
func setup(data: CarData, new_paint := Color(0, 0, 0, 0)) -> void:
	car_data = data
	paint = new_paint
	var shape := BoxShape3D.new()
	shape.size = Vector3(data.size.x * 0.95, data.size.y * 0.8, data.size.z * 0.95)
	_shape.shape = shape
	_shape.position = Vector3(0.0, data.size.y * 0.5, 0.0)
	model.build(data, data.default_paint if paint.a == 0.0 else paint)
	_built = true


func place_at(pos: Vector3, heading: float) -> void:
	global_position = Vector3(pos.x, 0.0, pos.z)
	yaw = heading
	rotation = Vector3(0.0, yaw, 0.0)
	velocity = Vector3.ZERO
	speed = 0.0
	steer = 0.0
	_spin_t = -1.0
	if road:
		_sample_road()
	reset_physics_interpolation()


func top_speed() -> float:
	return car_data.top_speed_mph / MPS_TO_MPH


func speed_mph() -> float:
	return absf(speed) * MPS_TO_MPH


func is_spinning() -> bool:
	return _spin_t >= 0.0


## False while spinning or just after (the short immunity after a spin-out).
func can_spin_out() -> bool:
	return not is_spinning() and _spin_immunity <= 0.0


func _physics_process(delta: float) -> void:
	if car_data == null:
		return
	_time += delta
	_spin_immunity = maxf(0.0, _spin_immunity - delta)
	if road:
		_sample_road()
	if is_spinning():
		_spin(delta)
	else:
		_read_input(delta)
		_drive(delta)
	if road:
		_keep_on_road()
	_animate_body(delta)


func _read_input(delta: float) -> void:
	var target := 0.0
	throttle = 0.0
	brake = 0.0
	if input_enabled:
		target = Input.get_axis("steer_left", "steer_right")
		throttle = Input.get_action_strength("accelerate")
		brake = Input.get_action_strength("brake")
	else:
		brake = auto_brake
	# Keys and touch buttons are all-or-nothing; easing toward the target turns
	# a quick tap into a small correction instead of a full-lock swerve.
	var rate := STEER_IN_RATE
	if absf(target) < absf(steer) or (steer != 0.0 and signf(target) != signf(steer)):
		rate = STEER_OUT_RATE
	steer = move_toward(steer, target, rate * delta)


func _sample_road() -> void:
	var sd := road.project(global_position)
	road_s = sd.x
	road_d = sd.y
	road_yaw = road.yaw_at(road_s)
	road_curvature = road.curvature_at(road_s)
	surface = road.surface_at(road_s, road_d)


func _drive(delta: float) -> void:
	var top := top_speed()
	var speed_ratio := clampf(absf(speed) / top, 0.0, 1.0)

	# --- Steering ---------------------------------------------------------------
	var authority := clampf(absf(speed) / FULL_STEER_SPEED, 0.0, 1.0) * (1.0 - 0.5 * speed_ratio)
	var direction := -1.0 if speed < -0.1 else 1.0  # reversing flips steering, like a real car
	_yaw_rate = -steer * car_data.steer_rate * authority * direction
	if steer_assist > 0.0 and absf(steer) < 0.05 and speed > 3.0 and road:
		# In a bend the velocity lags the nose by the slip angle (turn rate / grip),
		# so aim the nose that much into the bend to make the car track the road.
		var slip_lead := road_curvature * speed / maxf(car_data.grip, 0.1)
		var misalign := wrapf(road_yaw + slip_lead - yaw, -PI, PI)
		if absf(misalign) < deg_to_rad(40.0):
			# Follow the bend (feed-forward) and bleed off any heading error.
			_yaw_rate += road_curvature * speed + misalign * steer_assist
	yaw = wrapf(yaw + _yaw_rate * delta, -PI, PI)

	# --- Speed along the (new) heading ------------------------------------------
	var fwd := RoadGeo.forward(yaw)
	var side := RoadGeo.right(yaw)
	var v_fwd := velocity.dot(fwd)
	var v_side := velocity.dot(side)
	var accel := 0.0
	if throttle > 0.01:
		if v_fwd > -0.5:
			var t := clampf(v_fwd / top, 0.0, 1.0)
			accel += car_data.acceleration * throttle * (1.0 - t * t)  # power fades near top speed
		else:
			accel += car_data.brake_power * throttle  # gas while rolling backward brakes first
	if brake > 0.01:
		if v_fwd > 0.5:
			accel -= car_data.brake_power * brake
		else:
			accel -= REVERSE_ACCEL * brake
	if throttle <= 0.01 and brake <= 0.01:
		var drag := COAST_DRAG + AERO_DRAG * v_fwd * v_fwd
		accel -= signf(v_fwd) * minf(drag, absf(v_fwd) / delta)  # never coast past zero
	var new_fwd := v_fwd + accel * delta
	var surface_drag := 0.0
	match surface:
		RoadSpec.Surface.SHOULDER:
			surface_drag = SHOULDER_DRAG
		RoadSpec.Surface.GRASS:
			surface_drag = GRASS_DRAG
	new_fwd -= new_fwd * surface_drag * car_data.offroad_drag * delta
	new_fwd = clampf(new_fwd, -REVERSE_MAX, top)
	_long_accel = (new_fwd - v_fwd) / delta

	# --- Grip -------------------------------------------------------------------
	# Turning leaves some velocity pointing sideways; grip bleeds it off. Hard
	# steering at speed loosens grip so the tail steps out a little.
	var grip := car_data.grip * (1.0 - 0.55 * absf(steer) * speed_ratio)
	if surface == RoadSpec.Surface.GRASS:
		grip *= 0.7
	v_side *= exp(-grip * delta)

	velocity = fwd * new_fwd + side * v_side
	speed = new_fwd
	rotation = Vector3(0.0, yaw, 0.0)

	var before := velocity
	move_and_slide()
	_react_to_collisions(before)
	global_position.y = 0.0
	velocity.y = 0.0


## Bumps against physics obstacles (piers now; traffic and barriers later).
func _react_to_collisions(before: Vector3) -> void:
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var normal := hit.get_normal()
		normal.y = 0.0
		if normal.length_squared() < 0.01:
			continue
		normal = normal.normalized()
		var closing := -before.dot(normal)
		if closing > 1.0:
			velocity *= 1.0 - clampf(0.05 + closing * 0.03, 0.0, 0.6)
			velocity += normal * closing * WALL_BOUNCE
			speed = velocity.dot(RoadGeo.forward(yaw))
			_impact(closing)


## Median barrier on the left, ranch fence (or a set piece's edge) on the right.
func _keep_on_road() -> void:
	_sample_road()
	var rel := wrapf(yaw - road_yaw, -PI, PI)
	var half_w := car_data.size.x * 0.5
	var half_l := car_data.size.z * 0.5
	# How far the angled car body reaches sideways across the road.
	var reach := absf(half_w * cos(rel)) + absf(half_l * sin(rel)) * 0.85
	var min_d := RoadSpec.MEDIAN_HALF_BASE + reach + 0.12
	var max_d := road.outer_limit_at(road_s) - reach
	if road_d < min_d:
		_hit_side_wall(min_d - road_d, 1.0, rel)
	elif road_d > max_d:
		_hit_side_wall(road_d - max_d, -1.0, rel)


## push_dir: +1 pushes the car right (away from the median), -1 pushes it left.
func _hit_side_wall(depth: float, push_dir: float, rel_yaw: float) -> void:
	var away := RoadGeo.right(road_yaw) * push_dir
	global_position += away * depth
	road_d += depth * push_dir
	var closing := -velocity.dot(away)
	if closing <= 0.0:
		return
	velocity += away * closing * (1.0 + WALL_BOUNCE)
	# A glancing scrape costs a little speed; a square hit costs a lot.
	velocity *= 1.0 - clampf(0.02 + closing * 0.04, 0.0, 0.5)
	# Nudge the nose away from the wall (a left-pointing nose has positive rel_yaw).
	if rel_yaw * push_dir > 0.0:
		yaw = wrapf(yaw - rel_yaw * 0.5, -PI, PI)
		rotation = Vector3(0.0, yaw, 0.0)
	speed = velocity.dot(RoadGeo.forward(yaw))
	scraped.emit(absf(speed))
	if closing > 1.5:
		_impact(closing)


## A traffic contact, in road coordinates: push moves the car out of the
## overlap, dv changes its velocity, closing is how hard it hit (m/s) and
## normal points from this car toward what it hit.
func apply_contact(push: Vector2, dv: Vector2, closing: float, normal: Vector2) -> void:
	var fwd := RoadGeo.forward(road_yaw)
	var right := RoadGeo.right(road_yaw)
	global_position += fwd * push.x + right * push.y
	velocity += fwd * dv.x + right * dv.y
	if road:
		_keep_on_road()
	speed = velocity.dot(RoadGeo.forward(yaw))
	if closing >= hard_crash_speed and not is_spinning() and _spin_immunity <= 0.0:
		# Spin away from the side that got hit; head-on taps pick a side at random.
		var direction := -signf(normal.y) if absf(normal.y) > 0.15 else (1.0 if randf() < 0.5 else -1.0)
		spin_out(direction)
	elif closing > 1.0:
		_impact(closing)


## Loses control for SPIN_TIME seconds: the car slides on, scrubbing speed,
## turns more than a full circle (direction: +1 = counterclockwise) and ends
## lined up with the road in a safe lane.
func spin_out(direction: float) -> void:
	_spin_t = 0.0
	_spin_from = yaw
	_spin_lane = -1
	var settle := wrapf(road_yaw - yaw, -PI, PI)
	# One full turn plus whatever it takes to end up facing down the road.
	_spin_total = signf(direction) * TAU + settle
	steer = 0.0
	_impact(hard_crash_speed)
	spun_out.emit()


func _spin(delta: float) -> void:
	_spin_t += delta
	var u := clampf(_spin_t / SPIN_TIME, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - u, 3.0)  # fast at first, settling at the end
	yaw = wrapf(_spin_from + _spin_total * eased, -PI, PI)
	rotation = Vector3(0.0, yaw, 0.0)
	_yaw_rate = 0.0
	throttle = 0.0
	brake = 0.0
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var slide := maxf(0.0, flat.length() - SPIN_FRICTION * delta)
	velocity = flat.normalized() * slide if slide > 0.01 else Vector3.ZERO
	var right := RoadGeo.right(road_yaw)
	if u > 0.55 and road:
		# Ease sideways into a safe lane and stop sliding across the road.
		if _spin_lane < 0:
			_spin_lane = safe_lane_picker.call(road_s, road_d) if safe_lane_picker.is_valid() \
				else TrafficLanes.nearest_lane(road_d)
		var k := 1.0 - exp(-7.0 * delta)
		global_position += right * (RoadSpec.lane_center(_spin_lane) - road_d) * k
		velocity -= right * velocity.dot(right) * k
	move_and_slide()
	global_position.y = 0.0
	velocity.y = 0.0
	speed = velocity.dot(RoadGeo.forward(yaw))
	_long_accel = -SPIN_FRICTION
	if u >= 1.0:
		_spin_t = -1.0
		_spin_immunity = SPIN_IMMUNITY
		var fwd := RoadGeo.forward(yaw)
		speed = clampf(velocity.dot(fwd), RECOVER_SPEED.x, RECOVER_SPEED.y)
		velocity = fwd * speed


func _impact(strength: float) -> void:
	_wobble = minf(_wobble + strength * 0.03, 0.35)
	_heave_v += strength * 0.12
	bumped.emit(strength)


func _animate_body(delta: float) -> void:
	# Lean out of turns, squat on the gas, dive under braking.
	var roll_target := clampf(-_yaw_rate * speed * 0.009, -0.1, 0.1)
	var pitch_target := clampf(_long_accel * 0.006, -0.07, 0.045)
	# Rumble on the shoulder, bounce on the grass.
	if absf(speed) > 3.0 and surface != RoadSpec.Surface.LANE:
		var bumpiness := 1.6 if surface == RoadSpec.Surface.GRASS else 0.7
		_heave_v += randf_range(-1.0, 1.0) * bumpiness * clampf(absf(speed) / 20.0, 0.2, 1.0) * delta * 20.0

	_roll_v += (SPRING_K * (roll_target - _roll) - SPRING_DAMP * _roll_v) * delta
	_roll += _roll_v * delta
	_pitch_v += (SPRING_K * (pitch_target - _pitch) - SPRING_DAMP * _pitch_v) * delta
	_pitch += _pitch_v * delta
	_heave_v += (SPRING_K * (0.0 - _heave) - SPRING_DAMP * _heave_v) * delta
	_heave += _heave_v * delta
	_heave = clampf(_heave, -0.12, 0.18)

	_wobble = move_toward(_wobble, 0.0, delta * 0.6)
	var wobble := sin(_time * 24.0) * _wobble

	model.set_body_pose(_roll + wobble, _pitch, _heave)
	model.update_wheels(speed, steer, delta)
	model.set_brake_lights((brake > 0.05 and speed > 0.5) or speed < -0.3)
