class_name TrafficBehavior
extends RefCounted
## Base for custom traffic personalities. Point TrafficCarData.behavior at a
## script that extends this and override only what you need; TrafficCar calls
## these hooks every tick. See LeftLaneCamper.gd for a worked example.


## The speed this driver wants right now, in m/s. `wanted` already includes the
## car's cruise speed and any slowdown or jam it's in.
func desired_speed(_car: TrafficCar, wanted: float) -> float:
	return wanted


## Extra liking for a lane (lane 0 is the fast lane by the median), in m/s^2 of
## lane-change incentive. Positive pulls the car toward that lane.
func lane_preference(_car: TrafficCar, _lane: int) -> float:
	return 0.0


## Anything else, every tick: brake-checks, weaving, honking...
func on_tick(_car: TrafficCar, _delta: float) -> void:
	pass
