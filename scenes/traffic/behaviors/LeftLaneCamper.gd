extends TrafficBehavior
## Sample meme-car behavior: "always camps in the left lane at 5 under."
## It heads for the fast lane and stays there, 5 mph under the limit, no matter
## who is stuck behind it.
##
## To use it: duplicate data/traffic/sedan.tres, set personality to
## &"left_lane_camper" and behavior to this script, then add the new .tres to
## TrafficSpawner's roster (scenes/traffic/TrafficSpawner.tscn).

const MPH_UNDER := 5.0


func desired_speed(car: TrafficCar, wanted: float) -> float:
	return minf(wanted, car.speed_limit - MPH_UNDER / PlayerCar.MPS_TO_MPH)


## The further left the better; lane 0 is the fast lane by the median.
func lane_preference(_car: TrafficCar, lane: int) -> float:
	return (RoadSpec.LANES - 1 - lane) * 1.5
