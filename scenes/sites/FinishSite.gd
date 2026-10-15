class_name FinishSite
extends Node3D
## A level's destination: the set piece around the finish line. LevelData's
## finish_site points at a scene whose root extends this (Kickoff ends in a
## stadium parking lot). Without one, the race uses an overhead city-limit sign.
##
## A site:
## - shapes the road near the finish through RoadManager's zones (setup runs
##   before the road is built), and keeps it straight around itself;
## - decides what counts as finishing (is_finished: e.g. you must be in the lot);
## - shows itself once the straight approach exists, so it's there in the haze;
## - can talk to the player on the way in (hint_at), react to the clock
##   (on_clock) and to the finish (on_finished), and give the camera something
##   to look at after the finish (showcase_point).
##
## Local frame: origin at the finish line on the median, +X = d (meters right of
## the median), -Z = down the road (s beyond the finish). See Scenery.at().

## The road stays straight this far before and after the finish line.
@export var straight_before := 640.0
@export var straight_after := 720.0
## Meters before the finish from which roadside mile posts stay away.
@export var roadside_clear_before := 340.0
## Brake strength (0..1) the car uses to roll to a stop after the finish.
@export_range(0.0, 1.0) var finish_brake := 0.35
## To count as finished you have to cross the line at least this far right of
## the median (-INF = anywhere).
var finish_min_d := -INF

var road: RoadManager
var route: RouteMap

var _placed := false


func setup(road_manager: RoadManager, route_map: RouteMap) -> void:
	road = road_manager
	route = route_map
	visible = false
	road.straight_zone = Vector2(route.distance - straight_before, route.distance + straight_after)
	_shape_road()
	# Built while the race loads, not when it appears mid-race (no hitch).
	_build()


## Override: open up and pave the road around the site (RoadManager zones).
func _shape_road() -> void:
	pass


## Override: build the scenery (once, during setup).
func _build() -> void:
	pass


## Call every physics tick. Places the site as soon as the road's straight
## approach exists (everything past it is straight, so its position is exact).
func update(_focus_s: float) -> void:
	if _placed or road.streamed_to() < route.distance - straight_before + 1.0:
		return
	transform = Transform3D(Basis(Vector3.UP, road.yaw_at(route.distance)), road.sample(route.distance, 0.0))
	reset_physics_interpolation()
	visible = true
	_placed = true


func is_placed() -> bool:
	return _placed


func is_finished(s: float, d: float) -> bool:
	return s >= route.distance and d >= finish_min_d


## A popup for the player at (s, d), or "" for nothing. Called every tick while
## racing; the site keeps track of what it has already said.
func hint_at(_s: float, _d: float) -> String:
	return ""


## Seconds left on the race clock, every tick while racing.
func on_clock(_time_left: float) -> void:
	pass


func on_finished() -> void:
	pass


## Where the camera should look after the finish (world space), or null to
## keep the normal chase view.
func showcase_point() -> Variant:
	return null
