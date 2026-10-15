class_name Footprint
extends RefCounted
## A vehicle's rectangle on the road, in road coordinates: s (meters along the
## road) and d (meters right of the median). Over a car's length the road is
## nearly straight (curve radius ~1 km), so (s, d) is treated as a flat plane;
## the error is about 1%. Traffic AI and collisions work entirely in this space.

var s := 0.0
var d := 0.0
## Heading relative to the road's forward direction. Positive turns left
## (toward the median). Oncoming cars sit near PI.
var rel_yaw := 0.0
var half_len := 2.3
var half_wid := 0.95
## Velocity along the road (+s) and across it (+d = toward the outer shoulder).
var v_s := 0.0
var v_d := 0.0
var mass := 1.0
## The traffic car this belongs to; null for the player.
var car: TrafficCar


func forward() -> Vector2:
	return Vector2(cos(rel_yaw), -sin(rel_yaw))


func side() -> Vector2:
	return Vector2(sin(rel_yaw), cos(rel_yaw))


## Half extent of the (possibly rotated) rectangle along the road.
func reach_s() -> float:
	return half_len * absf(cos(rel_yaw)) + half_wid * absf(sin(rel_yaw))


## Half extent across the road.
func reach_d() -> float:
	return half_len * absf(sin(rel_yaw)) + half_wid * absf(cos(rel_yaw))


func is_player() -> bool:
	return car == null


## Separating-axis test between two rectangles. Returns the contact normal
## (pointing from a to b) in x/y and the overlap depth in z; z <= 0 means apart.
static func overlap(a: Footprint, b: Footprint) -> Vector3:
	var ds := b.s - a.s
	var dd := b.d - a.d
	if absf(ds) >= a.reach_s() + b.reach_s() or absf(dd) >= a.reach_d() + b.reach_d():
		return Vector3(0.0, 0.0, -1.0)
	var delta := Vector2(ds, dd)
	var a_fwd := a.forward()
	var a_side := a.side()
	var b_fwd := b.forward()
	var b_side := b.side()
	var best_depth := INF
	var best_axis := Vector2.ZERO
	for axis: Vector2 in [a_fwd, a_side, b_fwd, b_side]:
		var ra := a.half_len * absf(a_fwd.dot(axis)) + a.half_wid * absf(a_side.dot(axis))
		var rb := b.half_len * absf(b_fwd.dot(axis)) + b.half_wid * absf(b_side.dot(axis))
		var dist := delta.dot(axis)
		var depth := ra + rb - absf(dist)
		if depth <= 0.0:
			return Vector3(0.0, 0.0, -1.0)
		if depth < best_depth:
			best_depth = depth
			best_axis = axis if dist >= 0.0 else -axis
	return Vector3(best_axis.x, best_axis.y, best_depth)
