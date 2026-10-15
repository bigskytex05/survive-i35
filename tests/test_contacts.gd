extends TestSuite
## Collision math in road coordinates: rectangle overlap (including rotated
## cars) and the push/impulse response.


func _fp(s: float, d: float, yaw := 0.0, half_len := 2.3, half_wid := 0.95, v_s := 0.0, mass := 1.0) -> Footprint:
	var fp := Footprint.new()
	fp.s = s
	fp.d = d
	fp.rel_yaw = yaw
	fp.half_len = half_len
	fp.half_wid = half_wid
	fp.v_s = v_s
	fp.mass = mass
	return fp


func test_overlap_straight_cars() -> void:
	var a := _fp(0.0, 5.0)
	check(Footprint.overlap(a, _fp(5.0, 5.0)).z <= 0.0, "5 m apart nose to tail: no contact")
	var hit := Footprint.overlap(a, _fp(4.0, 5.0))
	check_near(hit.z, 0.6, 1e-4, "overlap depth along the road")
	check_near(hit.x, 1.0, 1e-4, "normal points from a to b along +s")
	check(Footprint.overlap(a, _fp(0.0, 7.0)).z <= 0.0, "side by side in adjacent lanes: no contact")
	var side := Footprint.overlap(a, _fp(1.0, 6.5))
	check_near(side.y, 1.0, 1e-4, "side swipe normal points across the road")
	check_near(side.z, 0.4, 1e-4, "side swipe depth")


func test_overlap_rotated_car() -> void:
	# A car turned 90 degrees is 4.6 m wide across the road.
	var sideways := _fp(0.0, 5.0, PI * 0.5)
	check(Footprint.overlap(sideways, _fp(0.0, 8.0)).z > 0.0, "a sideways car blocks the next lane")
	check(Footprint.overlap(_fp(0.0, 5.0), _fp(0.0, 8.0)).z <= 0.0, "a straight one doesn't")
	# Corner case: rotated rectangles whose bounding boxes touch but shapes don't.
	var a := _fp(0.0, 0.0, deg_to_rad(45.0), 1.0, 1.0)
	var b := _fp(2.6, 0.0, deg_to_rad(45.0), 1.0, 1.0)
	check(Footprint.overlap(a, b).z > 0.0, "diamonds 2.6 m apart overlap (reach 1.41 each)")
	b.s = 2.9
	check(Footprint.overlap(a, b).z <= 0.0, "diamonds 2.9 m apart don't")


func test_rear_end_impulse() -> void:
	var player := _fp(0.0, 7.55, 0.0, 2.25, 1.0, 40.0, 1.0)
	var truck := _fp(4.5, 7.55, 0.0, 4.1, 1.25, 20.0, 3.5)
	var c := VehicleContact.between(player, truck)
	check(c != null, "they touch")
	if c == null:
		return
	check_near(c.closing, 20.0, 1e-3, "closing speed")
	check(c.dv_a.x < -10.0, "the player loses a lot of speed (dv %.1f)" % c.dv_a.x)
	check(c.dv_b.x > 0.0 and c.dv_b.x < -c.dv_a.x, "the heavy truck is shoved forward, but less (dv %.1f)" % c.dv_b.x)
	check_near(c.dv_a.x * player.mass + c.dv_b.x * truck.mass, 0.0, 1e-3, "momentum is conserved")
	check(c.push_a.x < 0.0 and c.push_b.x > 0.0, "pushed apart")
	check(absf(c.push_a.x) > absf(c.push_b.x), "the lighter car moves more")


func test_separating_cars_get_no_impulse() -> void:
	var a := _fp(0.0, 5.0, 0.0, 2.3, 0.95, 30.0)
	var b := _fp(4.0, 5.0, 0.0, 2.3, 0.95, 35.0)
	var c := VehicleContact.between(a, b)
	check(c != null and c.closing == 0.0 and c.dv_a == Vector2.ZERO, "already pulling apart: only pushed out of the overlap")
