class_name TrafficProfile
extends RefCounted
## How busy and how fast traffic is along a level. Towns are busier, and metro
## approaches (Austin, Dallas) are a parking lot that suddenly opens up a few
## hundred meters before the finish.

const TOWN_RADIUS := 350.0
const TOWN_BUSY := 1.6
const JAM_LENGTH := 420.0
## Clear road between the metro jam and the finish line: the "opens up" moment.
const JAM_OPEN_RUN := 380.0
const JAM_DENSITY := 2.1
const JAM_SPEED := 0.42
## Meters over which a busy stretch or a jam fades in and out.
const EDGE := 90.0

var base_density := 7.0
## Busy stretches around towns, as (center s, radius).
var busy: Array[Vector2] = []
## Metro jams, as (from s, to s).
var jams: Array[Vector2] = []


## Even traffic everywhere (sandbox, tests).
static func uniform(density: float) -> TrafficProfile:
	var profile := TrafficProfile.new()
	profile.base_density = density
	return profile


static func for_level(level: LevelData, route: RouteMap) -> TrafficProfile:
	var profile := TrafficProfile.new()
	profile.base_density = level.traffic_density
	if Corridor.is_metro(level.start_town):
		profile.jams.append(Vector2(-300.0, JAM_LENGTH))
	else:
		profile.busy.append(Vector2(0.0, TOWN_RADIUS))
	for town in route.towns:
		profile.busy.append(Vector2(town["s"], TOWN_RADIUS))
	var end := route.distance
	if Corridor.is_metro(level.destination):
		profile.jams.append(Vector2(end - JAM_OPEN_RUN - JAM_LENGTH, end - JAM_OPEN_RUN))
	else:
		profile.busy.append(Vector2(end, TOWN_RADIUS))
	return profile


## Cars per kilometer per lane at s.
func density_at(s: float) -> float:
	var town := 0.0
	for b in busy:
		town = maxf(town, _window(s, b.x - b.y, b.x + b.y))
	return base_density * lerpf(1.0, TOWN_BUSY, town) * lerpf(1.0, JAM_DENSITY, jam_weight(s))


## Multiplier on how fast traffic wants to go at s.
func speed_factor_at(s: float) -> float:
	return lerpf(1.0, JAM_SPEED, jam_weight(s))


## 0 outside jams, 1 inside, smooth in between.
func jam_weight(s: float) -> float:
	var w := 0.0
	for j in jams:
		w = maxf(w, _window(s, j.x, j.y))
	return w


static func _window(s: float, from: float, to: float) -> float:
	return smoothstep(from - EDGE, from, s) * (1.0 - smoothstep(to, to + EDGE, s))
