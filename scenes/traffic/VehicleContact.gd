class_name VehicleContact
extends RefCounted
## What happens when two vehicles touch: they're pushed apart (the lighter one
## moves more) and trade momentum with a little bounce and some scraping
## friction. Pure math on Footprints; the caller applies the result.

const RESTITUTION := 0.25
const FRICTION := 0.3

## Unit normal in (s, d), pointing from a to b.
var normal := Vector2.ZERO
var depth := 0.0
## How fast they were closing along the normal, m/s (0 if already separating).
var closing := 0.0
var push_a := Vector2.ZERO
var push_b := Vector2.ZERO
var dv_a := Vector2.ZERO
var dv_b := Vector2.ZERO


## Returns null when the two don't touch.
static func between(a: Footprint, b: Footprint) -> VehicleContact:
	var hit := Footprint.overlap(a, b)
	if hit.z <= 0.0:
		return null
	var c := VehicleContact.new()
	c.normal = Vector2(hit.x, hit.y)
	c.depth = hit.z
	var wa := 1.0 / maxf(a.mass, 0.01)
	var wb := 1.0 / maxf(b.mass, 0.01)
	var w := wa + wb
	c.push_a = -c.normal * (c.depth * wa / w)
	c.push_b = c.normal * (c.depth * wb / w)
	var rel := Vector2(b.v_s - a.v_s, b.v_d - a.v_d)
	var vn := rel.dot(c.normal)
	if vn < 0.0:
		c.closing = -vn
		var j := -(1.0 + RESTITUTION) * vn / w
		# Friction along the contact surface, capped by the normal impulse.
		var tangent := Vector2(-c.normal.y, c.normal.x)
		var jt := clampf(-rel.dot(tangent) / w, -FRICTION * j, FRICTION * j)
		var impulse := c.normal * j + tangent * jt
		c.dv_a = -impulse * wa
		c.dv_b = impulse * wb
	return c
