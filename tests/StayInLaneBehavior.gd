extends TrafficBehavior
## Test helper: a driver that never leaves the lane it starts in.

var _home := -1


func lane_preference(car: TrafficCar, lane: int) -> float:
	if _home < 0:
		_home = car.lane
	return 0.0 if lane == _home else -100.0
