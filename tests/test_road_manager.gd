extends TestSuite
## Streaming and recycling: chunks join seamlessly, cover the view distance,
## are pooled (not re-instanced), and road coordinates are consistent.

const ROAD_SCENE := preload("res://scenes/road/RoadManager.tscn")


func _make_road(seed_value: int) -> RoadManager:
	var road: RoadManager = ROAD_SCENE.instantiate()
	add_child(road)
	road.reset(seed_value)
	return road


func test_streams_ahead_and_joins_seamlessly() -> void:
	var road := _make_road(1234)
	road.update_stream(0.0)
	var chunks := road.active_chunks()
	check(chunks.back().end_s() >= road.view_ahead, "road should reach view_ahead")
	for i in range(1, chunks.size()):
		var prev := chunks[i - 1]
		var next := chunks[i]
		check_near(next.start_s, prev.end_s(), 1e-4, "s continuity at chunk %d" % i)
		check_vec_near(next.world_point(next.start_s, 0.0), prev.world_point(prev.end_s(), 0.0), 1e-3,
			"position continuity at chunk %d" % i)
		check_near(next.yaw_at(next.start_s), prev.yaw_at(prev.end_s()), 1e-5, "heading continuity at chunk %d" % i)
	road.queue_free()


func test_sample_and_project_agree_across_chunks() -> void:
	var road := _make_road(99)
	# Drive the stream far enough that curves and overpasses show up.
	for s in range(0, 3000, 40):
		road.update_stream(float(s))
	var focus := 2900.0
	for s in [focus - 60.0, focus, focus + 37.0, focus + 200.0, focus + 420.0]:
		for d in [RoadSpec.lane_center(0), RoadSpec.lane_center(2), -RoadSpec.lane_center(1), 25.0]:
			var sd := road.project(road.sample(s, d))
			check_near(sd.x, s, 0.01, "s at %.1f/%.1f" % [s, d])
			check_near(sd.y, d, 0.01, "d at %.1f/%.1f" % [s, d])
	road.queue_free()


func test_chunks_are_pooled() -> void:
	var road := _make_road(7)
	for s in range(0, 12000, 25):
		road.update_stream(float(s))
	check(road.active_count() <= 8, "active chunks bounded (got %d)" % road.active_count())
	check(road.instanced_count <= 24, "chunks reused from pools (instanced %d)" % road.instanced_count)
	road.queue_free()


func test_heading_stays_near_corridor() -> void:
	var road := _make_road(4242)
	var worst := 0.0
	for s in range(0, 15000, 60):
		road.update_stream(float(s))
		worst = maxf(worst, absf(rad_to_deg(road.yaw_at(float(s)))))
	check(worst < 35.0, "road heading should wander gently (max drift %.1f deg)" % worst)
	road.queue_free()
