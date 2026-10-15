class_name StartSite
extends Node3D
## Scenery around a level's start line, so a trip visibly begins in its start
## town. LevelData.start_site points at a scene whose root uses this script (or
## extends it); children add town-specific landmarks.
##
## The generic part, built from the route: a water tower with the town's name,
## a "LEAVING <TOWN>" sign and a green distance sign to the destination.
##
## Local frame: origin at the start line on the median, +X = d (meters right of
## the median), -Z = down the road. The first stretch of road is always straight
## and the first overpass can't come before s = 240, so everything stays within
## s < 230. During the countdown the camera starts on showcase_point() and eases
## back behind the car by GO.

const TOWER := Vector2(140.0, 46.0)   # (s, d) of the water tower

var route: RouteMap


func setup(road: RoadManager, route_map: RouteMap) -> void:
	route = route_map
	transform = Transform3D(Basis(Vector3.UP, road.yaw_at(0.0)), road.sample(0.0, 0.0))
	reset_physics_interpolation()
	_build()


func _build() -> void:
	var town := route.start_name.to_upper()
	var mk := MeshKit.new()
	# Water tower beyond the fence: four legs, a tank and a little cap.
	var tower := Scenery.at(TOWER.x, TOWER.y)
	for x: float in [-3.2, 3.2]:
		for z: float in [-3.2, 3.2]:
			mk.xf = tower * Transform3D(Basis.IDENTITY, Vector3(x, 0, z))
			mk.prism(Vector3.ZERO, 0.35, 0.3, 22.0, 6, Palette.HUB)
	mk.xf = tower
	mk.box(Vector3(0, 12.0, 0), Vector3(6.6, 0.25, 0.25), Palette.HUB)
	mk.box(Vector3(0, 12.0, 0), Vector3(0.25, 0.25, 6.6), Palette.HUB)
	mk.prism(Vector3(0, 21.5, 0), 5.2, 5.2, 7.0, 16, Palette.SIGN_WHITE)
	mk.prism(Vector3(0, 28.5, 0), 5.2, 0.6, 2.4, 16, Palette.CONCRETE)
	mk.xf = Transform3D.IDENTITY
	Scenery.sign_board(mk, Scenery.at(40.0, 19.0), Vector2(5.2, 2.0), 2.6, Palette.SIGN_GREEN)
	Scenery.sign_board(mk, Scenery.at(200.0, 20.0), Vector2(6.0, 3.0), 3.0, Palette.SIGN_GREEN)
	add_child(Scenery.mesh_node("StartScenery", mk))
	# The tank's name faces the road and the approaching camera.
	var tank_label := Scenery.label(town, 220, 0.012, Palette.UI_TEXT)
	tank_label.transform = tower * Transform3D(Basis(Vector3.UP, -0.75), Vector3(-3.7, 25.0, 3.4))
	add_child(tank_label)
	add_child(Scenery.sign_text(Scenery.at(40.0, 19.0), 3.6, ["LEAVING", town], [44, 64]))
	var miles := roundi(absf(route.end_mile - route.start_mile))
	add_child(Scenery.sign_text(Scenery.at(200.0, 20.0), 4.5,
		["%s  %d" % [route.end_name.to_upper(), miles], "KEEP RIGHT FOR EXITS"], [80, 40]))


## What the countdown camera looks at: the town's landmarks.
func showcase_point() -> Vector3:
	# High up, so the tower's tank sits below the level card.
	return to_global(Vector3(TOWER.y - 4.0, 30.0, -(TOWER.x - 45.0)))
