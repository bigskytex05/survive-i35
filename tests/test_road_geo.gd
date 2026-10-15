extends TestSuite
## Road math: points and projections must be exact inverses on straights and
## on both left and right arcs, and headings must match the arc's direction.

const KAPPAS: Array[float] = [0.0, 0.001, -0.001, 0.0035, -0.0035]


func test_straight_axes() -> void:
	check_vec_near(RoadGeo.point(0.0, 10.0, 0.0), Vector3(0, 0, -10), 1e-5, "forward is -Z")
	check_vec_near(RoadGeo.point(0.0, 0.0, 3.0), Vector3(3, 0, 0), 1e-5, "right is +X")
	check_vec_near(RoadGeo.forward(0.0), Vector3(0, 0, -1), 1e-6, "yaw 0 faces -Z")
	check_vec_near(RoadGeo.forward(PI * 0.5), Vector3(-1, 0, 0), 1e-6, "positive yaw turns left")


func test_point_project_round_trip() -> void:
	for kappa in KAPPAS:
		for s in [0.0, 17.5, 60.0, 120.0]:
			for d in [-30.0, -7.4, 0.0, 5.55, 30.0]:
				var sd := RoadGeo.project(kappa, RoadGeo.point(kappa, s, d))
				check_near(sd.x, s, 1e-3, "s round trip k=%f s=%f d=%f" % [kappa, s, d])
				check_near(sd.y, d, 1e-3, "d round trip k=%f s=%f d=%f" % [kappa, s, d])


func test_heading_matches_arc_direction() -> void:
	for kappa in KAPPAS:
		for s in [0.0, 50.0, 110.0]:
			var ahead := RoadGeo.point(kappa, s + 0.01, 0.0)
			var here := RoadGeo.point(kappa, s - 0.01, 0.0)
			var tangent := (ahead - here).normalized()
			check_vec_near(tangent, RoadGeo.forward(RoadGeo.heading(kappa, s)), 1e-3,
				"tangent k=%f s=%f" % [kappa, s])
			var side := RoadGeo.point(kappa, s, 1.0) - RoadGeo.point(kappa, s, 0.0)
			check_vec_near(side, RoadGeo.right(RoadGeo.heading(kappa, s)), 1e-3,
				"right vector k=%f s=%f" % [kappa, s])


func test_left_curve_bends_left() -> void:
	var end := RoadGeo.point(deg_to_rad(7.0) / 120.0, 120.0, 0.0)
	check(end.x < -1.0, "a left curve should end left of where it started (x=%f)" % end.x)


func test_lane_layout() -> void:
	check_near(RoadSpec.lane_center(0), 3.85, 1e-4, "lane 0 center")
	check(RoadSpec.surface_at(RoadSpec.lane_center(1)) == RoadSpec.Surface.LANE, "lane is LANE")
	check(RoadSpec.surface_at(RoadSpec.lanes_outer_edge() + 1.0) == RoadSpec.Surface.SHOULDER, "outer shoulder")
	check(RoadSpec.surface_at(RoadSpec.FENCE_D - 2.0) == RoadSpec.Surface.GRASS, "grass")
	check(RoadSpec.surface_at(1.0) == RoadSpec.Surface.SHOULDER, "inner shoulder")
