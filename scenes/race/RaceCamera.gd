class_name RaceCamera
extends Camera3D
## Elevated chase camera in the spirit of art-of-rally-style games: looks down
## at the car from roughly 40-48 degrees, trails it with a little lag, and pulls
## back and widens as speed rises so traffic and lane closures ahead stay readable.
##
## Runs in _process using the car's interpolated transform (physics
## interpolation is on), so motion stays smooth on 90/120 Hz screens.
##
## Two extras for destinations: `lift` (0..1) tilts the view up toward the
## horizon on the final approach, showcase() swings the camera round after the
## finish to frame a point of interest (the stadium) with the car in shot, and
## intro() starts in that kind of view (the start town) and eases back.

## x = at a standstill, y = at top speed.
@export var height := Vector2(15.0, 19.5)
@export var distance := Vector2(13.5, 18.5)
@export var look_ahead := Vector2(8.0, 18.0)
@export var fov_range := Vector2(48.0, 55.0)
## Higher = tighter follow. Position lag is what sells the speed.
@export var position_sharpness := 9.0
@export var yaw_sharpness := 3.5
@export var zoom_sharpness := 1.5

var target: PlayerCar
## 0..1: aim higher, toward the horizon (set by the race near a destination).
var lift := 0.0

const LIFT_LOOK := 9.0           # meters the look point rises at full lift
const SHOWCASE_BLEND := 2.2      # seconds to swing into the showcase view
const SHOWCASE_BACK := 24.0
const SHOWCASE_UP := 9.0

var _focus := Vector3.ZERO
var _yaw := 0.0
var _zoom := 0.0
var _shake := 0.0
var _showcase_point := Vector3.ZERO
var _showcase := -1.0            # < 0: off; 0..1: blend into the showcase view
var _intro_rate := 0.0           # > 0 while easing out of an intro view


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Jump straight to the resting position (race start, respawn).
func snap() -> void:
	if target == null:
		return
	_focus = target.global_position
	_yaw = target.yaw
	_zoom = 0.0
	_apply()


## Swings round to look at `point` (world space), keeping the car in shot.
func showcase(point: Vector3) -> void:
	_showcase_point = point
	_showcase = 0.0


## Starts looking at `point` with the car in shot, holds a moment, and eases
## back to the chase view so it's there after `seconds` (the countdown).
func intro(point: Vector3, seconds: float) -> void:
	_showcase_point = point
	_showcase = 1.5
	_intro_rate = 1.5 / maxf(seconds, 0.1)


func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.0)


func _process(delta: float) -> void:
	if target == null:
		return
	var xf := target.get_global_transform_interpolated()
	# While spinning out, follow the road instead so the view doesn't whirl.
	var car_yaw := target.road_yaw if target.is_spinning() else atan2(xf.basis.z.x, xf.basis.z.z)
	var zoom_target := clampf(absf(target.speed) / target.top_speed(), 0.0, 1.0)
	_zoom = lerpf(_zoom, zoom_target, 1.0 - exp(-zoom_sharpness * delta))
	_focus = _focus.lerp(xf.origin, 1.0 - exp(-position_sharpness * delta))
	_yaw = lerp_angle(_yaw, car_yaw, 1.0 - exp(-yaw_sharpness * delta))
	if _intro_rate > 0.0:
		_showcase -= _intro_rate * delta
		if _showcase <= 0.0:
			_showcase = -1.0
			_intro_rate = 0.0
	elif _showcase >= 0.0:
		_showcase = minf(_showcase + delta / SHOWCASE_BLEND, 1.0)
	_apply()
	if _shake > 0.0:
		h_offset = randf_range(-1.0, 1.0) * _shake * 0.4
		v_offset = randf_range(-1.0, 1.0) * _shake * 0.4
		_shake = move_toward(_shake, 0.0, delta * 2.5)
	else:
		h_offset = 0.0
		v_offset = 0.0


func _apply() -> void:
	var fwd := RoadGeo.forward(_yaw)
	var back := lerpf(distance.x, distance.y, _zoom)
	var up := lerpf(height.x, height.y, _zoom)
	var eye := _focus - fwd * back + Vector3.UP * up
	var look := _focus + fwd * lerpf(look_ahead.x, look_ahead.y, _zoom) + Vector3.UP * LIFT_LOOK * lift
	var view_fov := lerpf(fov_range.x, fov_range.y, _zoom)
	if _showcase > 0.0:
		# Behind the car on the line toward the point, a little up, looking past
		# the car at it.
		var toward := _showcase_point - _focus
		toward.y = 0.0
		toward = toward.normalized()
		var k := smoothstep(0.0, 1.0, minf(_showcase, 1.0))
		eye = eye.lerp(_focus - toward * SHOWCASE_BACK + Vector3.UP * SHOWCASE_UP, k)
		look = look.lerp(_focus.lerp(_showcase_point, 0.6), k)
		view_fov = lerpf(view_fov, 58.0, k)
	global_position = eye
	look_at(look, Vector3.UP)
	fov = view_fov
