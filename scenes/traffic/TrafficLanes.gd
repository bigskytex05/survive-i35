class_name TrafficLanes
extends RefCounted
## Vehicles sorted into bands across the road (inner shoulder, each lane, then
## the outer shoulder and grass), each band ordered along the direction of
## travel. Rebuilt every tick, it answers "who's ahead of me?" and "is there a
## gap in that lane?" without comparing every car with every other.
## A car straddling two lanes is listed in both.

const BANDS := RoadSpec.LANES + 2
## A body has to reach this far into a band to count as being in it.
const MARGIN := 0.15

var _same: Array = []      # per band: Footprints driving with the player, by s ascending
var _oncoming: Array = []  # per band: oncoming Footprints, by s descending
var _ascending := func(a: Footprint, b: Footprint) -> bool: return a.s < b.s
var _descending := func(a: Footprint, b: Footprint) -> bool: return a.s > b.s


func _init() -> void:
	for i in BANDS:
		_same.append([])
		_oncoming.append([])


## Band index of a lane (band 0 is the inner shoulder).
static func lane_band(lane: int) -> int:
	return lane + 1


## The lane whose center is nearest to offset d (either carriageway).
static func nearest_lane(d: float) -> int:
	return clampi(floori((absf(d) - RoadSpec.LANE0_EDGE) / RoadSpec.LANE_WIDTH), 0, RoadSpec.LANES - 1)


## First and last band a body overlaps on its own side of the median.
static func bands_of(fp: Footprint) -> Vector2i:
	var d := absf(fp.d)
	var r := maxf(fp.reach_d() - MARGIN, 0.0)
	return Vector2i(_band_at(d - r), _band_at(d + r))


static func _band_at(d: float) -> int:
	if d < RoadSpec.LANE0_EDGE:
		return 0
	return mini(floori((d - RoadSpec.LANE0_EDGE) / RoadSpec.LANE_WIDTH) + 1, BANDS - 1)


func rebuild(same: Array[Footprint], oncoming: Array[Footprint]) -> void:
	_fill(_same, same, _ascending)
	_fill(_oncoming, oncoming, _descending)


func _fill(bands: Array, bodies: Array[Footprint], order: Callable) -> void:
	for list: Array in bands:
		list.clear()
	for fp in bodies:
		var span := bands_of(fp)
		for b in range(span.x, span.y + 1):
			bands[b].append(fp)
	for list: Array in bands:
		if list.size() > 1:
			list.sort_custom(order)


## Bodies driving with the player in band i, ordered along the road.
func band(i: int) -> Array:
	return _same[i]


## The nearest body ahead of fp (in its direction of travel) in any band it
## overlaps, or only in `only_band` when given. Null when the road is clear.
func leader(fp: Footprint, dir: int, only_band := -1) -> Footprint:
	var bands := _same if dir > 0 else _oncoming
	var span := bands_of(fp) if only_band < 0 else Vector2i(only_band, only_band)
	var p := fp.s * dir
	var best: Footprint = null
	var best_q := INF
	for b in range(span.x, span.y + 1):
		for other: Footprint in bands[b]:
			var q := other.s * dir
			if other == fp or q <= p:
				continue
			if q < best_q:
				best_q = q
				best = other
			break  # sorted: the first one ahead is the nearest in this band
	return best


## The nearest bodies ahead of and behind fp in one band (driving with the
## player), for gap checks before a lane change: [leader, follower], either may be null.
func around(band_index: int, fp: Footprint) -> Array[Footprint]:
	var lead: Footprint = null
	var follow: Footprint = null
	for other: Footprint in _same[band_index]:
		if other == fp:
			continue
		if other.s > fp.s:
			lead = other
			break
		follow = other
	return [lead, follow]
