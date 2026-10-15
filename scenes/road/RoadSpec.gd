class_name RoadSpec
extends RefCounted
## Cross-section of the highway, in meters measured sideways from the median
## centerline. d > 0 is the player's carriageway (right of the median),
## d < 0 is the oncoming side. Lane 0 is the fast lane next to the median.
##
##  oncoming | median |inner|  lane 0 | lane 1 | lane 2 | outer   | grass ... fence
##   lanes   |barrier |shldr|         |        |        | shoulder|

enum Surface { LANE, SHOULDER, GRASS }

const LANES := 3
const LANE_WIDTH := 3.7
const MEDIAN_HALF_BASE := 0.42   # Jersey barrier half-width at the ground
const MEDIAN_HEIGHT := 0.9
const LANE0_EDGE := 2.0          # median side of the fast lane
const OUTER_SHOULDER := 3.0
const GRAVEL_WIDTH := 0.9
const FENCE_D := 30.0            # ranch fence: the hard outer boundary
const LINE_WIDTH := 0.16
const DASH_LENGTH := 3.0         # US interstate lane dashes: 10 ft paint, 30 ft gap
const DASH_PERIOD := 12.0


static func lane_center(lane: int) -> float:
	return LANE0_EDGE + LANE_WIDTH * (lane + 0.5)


static func lanes_outer_edge() -> float:
	return LANE0_EDGE + LANE_WIDTH * LANES


static func shoulder_outer_edge() -> float:
	return lanes_outer_edge() + OUTER_SHOULDER


## Which surface the player's side of the road has at offset d.
static func surface_at(d: float) -> Surface:
	if d < LANE0_EDGE:
		return Surface.SHOULDER
	if d <= lanes_outer_edge():
		return Surface.LANE
	if d <= shoulder_outer_edge():
		return Surface.SHOULDER
	return Surface.GRASS
