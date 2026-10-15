class_name RoadGeo
extends RefCounted
## Pure math for one road piece: a straight or a constant-curvature arc.
##
## Local frame: the piece starts at the origin heading -Z (Godot's forward) with
## +X to the right. kappa = 1 / radius; positive kappa bends left.
## Road coordinates: s = meters along the centerline, d = signed meters to the
## right of it. Yaw follows Godot's convention: positive yaw turns left.

const EPS := 1e-7


static func forward(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func right(yaw: float) -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


static func heading(kappa: float, s: float) -> float:
	return kappa * s


## Local position of road coordinate (s, d).
static func point(kappa: float, s: float, d: float) -> Vector3:
	if absf(kappa) < EPS:
		return Vector3(d, 0.0, -s)
	# An arc is part of a circle centered at (-r, 0, 0): p = center + right(yaw) * (r + d).
	# Expanded with the half-angle identity (cos y - 1 = -2 sin^2(y/2)) and kept in
	# 64-bit scalars, so gentle curves (huge r) don't lose precision to cancellation.
	var r := 1.0 / kappa
	var yaw := kappa * s
	var half := sin(yaw * 0.5)
	var x := -2.0 * half * half * r + cos(yaw) * d
	var z := -sin(yaw) * (r + d)
	return Vector3(x, 0.0, z)


## Inverse of point(): local position -> (s, d). Valid while |d| < radius.
static func project(kappa: float, p: Vector3) -> Vector2:
	if absf(kappa) < EPS:
		return Vector2(-p.z, p.x)
	var r := 1.0 / kappa
	var sgn := signf(kappa)
	# Offset from the circle center, as 64-bit scalars (Vector2 is 32-bit).
	var fx := p.x + r
	var fz := p.z
	var dist := sqrt(fx * fx + fz * fz)
	# right(yaw) = (cos yaw, -sin yaw) is parallel to sgn * (fx, fz).
	var yaw := atan2(-fz * sgn, fx * sgn)
	return Vector2(yaw / kappa, sgn * dist - r)
