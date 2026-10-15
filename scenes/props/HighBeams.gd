extends Prop
## High Beams (active): blinding high beams for `duration` seconds. Drivers
## ahead of you inside the beam are blinded: they slow to 60%, stop changing
## lanes and wander in theirs, until BLIND_AFTER seconds after the beam leaves
## them. The scene stays in daylight; see BeamLights for the look.
## High-beaming a trooper (parked or driving) starts a chase instead.

const LENGTH := 42.0
const HALF_ANGLE := 0.2   # radians, about 11.5 degrees each side
const BLIND_AFTER := 3.0
const FADE := 0.15        # seconds to switch on or off

## Seconds of beam left.
var on_left := 0.0

var _lights: BeamLights
var _intensity := 0.0
var _announced := false


func setup(race_node: Race, prop_data: PropData) -> void:
	super(race_node, prop_data)
	_lights = BeamLights.new()
	add_child(_lights)
	_lights.build(race.car.model, LENGTH, HALF_ANGLE)


func use() -> bool:
	on_left = data.duration
	_announced = false
	Sfx.play(self, &"whoomp", -2.0)
	return true


func active_fraction() -> float:
	return on_left / data.duration if data.duration > 0.0 else 0.0


func is_on() -> bool:
	return on_left > 0.0


func tick(delta: float) -> void:
	if on_left > 0.0:
		on_left = maxf(0.0, on_left - delta)
		_blind_drivers()
	_intensity = move_toward(_intensity, 1.0 if on_left > 0.0 else 0.0, delta / FADE)
	_lights.set_intensity(_intensity)


## Everyone ahead of us inside the beam's cone. A trooper in there takes it personally.
func _blind_drivers() -> void:
	for other in race.traffic.active_cars():
		if other.dir < 0 or not _in_beam(other.fp):
			continue
		if other is PoliceCar:
			race.police.provoke(other, &"high_beams")
		elif other.blind(BLIND_AFTER):
			race.on_driver_blinded(not _announced)
			_announced = true
	for trap in race.police.traps:
		if trap.placed and not trap.launched and _in_beam(trap.cop_footprint(Police.POLICE_DATA)):
			race.police.provoke(trap, &"high_beams")


## Whether a body is inside the beam, in road coordinates.
func _in_beam(fp: Footprint) -> bool:
	var car := race.car
	var rel_yaw := wrapf(car.yaw - car.road_yaw, -PI, PI)
	var fwd := Vector2(cos(rel_yaw), -sin(rel_yaw))  # (s, d), same convention as Footprint
	var across := Vector2(-fwd.y, fwd.x)
	var origin := Vector2(car.road_s, car.road_d) + fwd * car.car_data.size.z * 0.5
	var rel := Vector2(fp.s, fp.d) - origin
	var along := rel.dot(fwd)
	if along < -fp.half_len or along > LENGTH + fp.half_len:
		return false
	# The cone starts as wide as the car (two lamps) and spreads out.
	return absf(rel.dot(across)) <= maxf(along, 0.0) * tan(HALF_ANGLE) + car.car_data.size.x * 0.5 + fp.half_wid
