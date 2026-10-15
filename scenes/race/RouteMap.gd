class_name RouteMap
extends RefCounted
## Maps game meters along a level (s = 0 at the start line, s = distance at the
## finish) onto the corridor: mile markers and where each town sits.

var distance := 1.0
var start_mile := 0.0
var end_mile := 0.0
var start_name := ""
var end_name := ""
## Towns passed on the way (not the two ends): {id, name, s}, in driving order.
var towns: Array[Dictionary] = []


static func from_level(level: LevelData) -> RouteMap:
	var route := RouteMap.new()
	route.distance = maxf(level.distance_m, 1.0)
	route.start_mile = Corridor.town_mile(level.start_town)
	route.end_mile = Corridor.town_mile(level.destination)
	route.start_name = Corridor.town_name(level.start_town)
	route.end_name = Corridor.town_name(level.destination)
	for id in Corridor.towns_between(level.start_town, level.destination):
		route.towns.append({"id": id, "name": Corridor.town_name(id), "s": route.s_at_mile(Corridor.town_mile(id))})
	return route


## 0 at the start, 1 at the finish.
func fraction(s: float) -> float:
	return clampf(s / distance, 0.0, 1.0)


func mile_at(s: float) -> float:
	return lerpf(start_mile, end_mile, s / distance)


func s_at_mile(mile: float) -> float:
	return (mile - start_mile) / (end_mile - start_mile) * distance


func miles_left(s: float) -> float:
	return absf(end_mile - mile_at(clampf(s, 0.0, distance)))


## Real miles per game kilometer (how hard the corridor is squeezed).
func miles_per_km() -> float:
	return absf(end_mile - start_mile) / (distance / 1000.0)


## The smallest "nice" mile interval whose marks land at least `min_gap`
## game meters apart. Used for the roadside posts and the HUD strip.
func mile_step(min_gap: float) -> float:
	for step: float in [1.0, 2.0, 5.0, 10.0, 25.0, 50.0]:
		if step / miles_per_km() * 1000.0 >= min_gap:
			return step
	return 100.0


## Mile values that are multiples of `step`, strictly inside the route.
func marks(step: float) -> Array[float]:
	var lo := minf(start_mile, end_mile)
	var hi := maxf(start_mile, end_mile)
	var found: Array[float] = []
	var m := floorf(lo / step) * step + step
	while m < hi - 0.001:
		if m > lo + 0.001:
			found.append(m)
		m += step
	return found
