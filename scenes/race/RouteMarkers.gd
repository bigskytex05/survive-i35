class_name RouteMarkers
extends Node3D
## Roadside furniture tied to the level's route: green mile-marker posts whose
## numbers match the HUD strip, and an overhead city-limit sign with a
## checkered line across the road at the finish.

## Mile posts closer together than this (game meters) skip to a bigger interval.
const POST_MIN_GAP := 180.0
const POST_COUNT := 4
const SHOW_AHEAD := 470.0
const SHOW_BEHIND := 40.0
const GANTRY_TOP := 9.4

var road: RoadManager
var route: RouteMap
## No mile posts past this s (a finish site has the roadside there).
var posts_until_s := INF

var _marks: Array[float] = []
var _posts: Array[Node3D] = []
var _post_mile: Array[float] = []  # mile shown by each post (-1 = free)
var _finish: Node3D
var _finish_placed := false

static var _post_mesh: ArrayMesh
static var _gantry_mesh: ArrayMesh


## `with_finish` = false when a level's FinishSite stands at the finish instead.
func setup(road_manager: RoadManager, route_map: RouteMap, with_finish := true) -> void:
	road = road_manager
	route = route_map
	_marks = route.marks(route.mile_step(POST_MIN_GAP))
	for i in POST_COUNT:
		_posts.append(_make_post())
		_post_mile.append(-1.0)
	if with_finish:
		_finish = _make_finish(route.end_name)


## Call every physics tick with the player's s.
func update(focus_s: float) -> void:
	var built_to := road.streamed_to()
	if _finish and not _finish_placed and built_to > route.distance + 20.0:
		_place(_finish, route.distance, 0.0)
		_finish.visible = true
		_finish_placed = true
	for i in POST_COUNT:
		if _post_mile[i] >= 0.0 and route.s_at_mile(_post_mile[i]) < focus_s - SHOW_BEHIND:
			_post_mile[i] = -1.0
			_posts[i].visible = false
	for mile in _marks:
		var s := route.s_at_mile(mile)
		if s < focus_s - SHOW_BEHIND or s > minf(focus_s + SHOW_AHEAD, built_to) or s > posts_until_s or mile in _post_mile:
			continue
		var free := _post_mile.find(-1.0)
		if free < 0:
			break
		_post_mile[free] = mile
		var post := _posts[free]
		(post.get_node("Number") as Label3D).text = str(int(mile))
		_place(post, s, RoadSpec.shoulder_outer_edge() + 1.5)
		post.visible = true


func _place(node: Node3D, s: float, d: float) -> void:
	node.transform = Transform3D(Basis(Vector3.UP, road.yaw_at(s)), road.sample(s, d))
	node.reset_physics_interpolation()


func _make_post() -> Node3D:
	if _post_mesh == null:
		var mk := MeshKit.new()
		mk.box(Vector3(0, 0.75, 0), Vector3(0.1, 1.5, 0.1), Palette.HUB)
		mk.box(Vector3(0, 1.75, 0.07), Vector3(0.62, 0.92, 0.05), Palette.SIGN_WHITE)
		mk.box(Vector3(0, 1.75, 0.09), Vector3(0.54, 0.84, 0.05), Palette.SIGN_GREEN)
		_post_mesh = mk.commit()
	var post := Node3D.new()
	post.name = "MilePost"
	post.visible = false
	var mi := MeshInstance3D.new()
	mi.mesh = _post_mesh
	post.add_child(mi)
	post.add_child(_label("Caption", "MILE", 26, Vector3(0, 2.0, 0.125)))
	post.add_child(_label("Number", "0", 52, Vector3(0, 1.63, 0.125)))
	add_child(post)
	return post


## The finish: an overhead green city-limit sign on a steel truss from the
## median to the grass, and a checkered line across our lanes.
func _make_finish(town: String) -> Node3D:
	var finish := Node3D.new()
	finish.name = "Finish"
	finish.visible = false
	var outer_d := RoadSpec.shoulder_outer_edge() + 1.6
	var sign_d := (RoadSpec.LANE0_EDGE + RoadSpec.lanes_outer_edge()) * 0.5
	if _gantry_mesh == null:
		_gantry_mesh = _build_gantry(outer_d, sign_d)
	var mi := MeshInstance3D.new()
	mi.mesh = _gantry_mesh
	finish.add_child(mi)
	finish.add_child(_label("Town", town.to_upper(), 150, Vector3(sign_d, 8.2, 0.12), 0.009))
	finish.add_child(_label("Limit", "CITY LIMIT", 64, Vector3(sign_d, 6.85, 0.12), 0.009))
	# The outer post stands in the drivable grass, so it's solid.
	var body := StaticBody3D.new()
	body.collision_layer = 1 << 2  # "obstacles"
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, GANTRY_TOP, 0.6)
	shape.shape = box
	shape.position = Vector3(outer_d, GANTRY_TOP * 0.5, 0.0)
	body.add_child(shape)
	finish.add_child(body)
	add_child(finish)
	return finish


static func _build_gantry(outer_d: float, sign_d: float) -> ArrayMesh:
	var mk := MeshKit.new()
	var steel := Palette.HUB
	# Posts: one on the median barrier, one out in the grass.
	for d: float in [0.0, outer_d]:
		mk.box(Vector3(d, GANTRY_TOP * 0.5, -0.35), Vector3(0.5, GANTRY_TOP, 0.5), steel)
	# Truss: two chords with a few verticals.
	for y: float in [6.1, GANTRY_TOP - 0.2]:
		mk.box(Vector3(outer_d * 0.5, y, -0.35), Vector3(outer_d, 0.24, 0.24), steel)
	var x := 2.0
	while x < outer_d - 1.0:
		mk.box(Vector3(x, (6.1 + GANTRY_TOP - 0.2) * 0.5, -0.35), Vector3(0.12, GANTRY_TOP - 6.3, 0.12), steel)
		x += 2.5
	# The sign: white border, green face.
	mk.box(Vector3(sign_d, 7.6, 0.0), Vector3(10.4, 3.5, 0.12), Palette.SIGN_WHITE)
	mk.box(Vector3(sign_d, 7.6, 0.03), Vector3(10.0, 3.1, 0.12), Palette.SIGN_GREEN)
	# Checkered line: two rows of squares across our three lanes.
	var width := RoadSpec.lanes_outer_edge() - RoadSpec.LANE0_EDGE
	var count := 12
	var sq := width / count
	for row in 2:
		for i in count:
			var dark := (i + row) % 2 == 0
			var c := Vector3(RoadSpec.LANE0_EDGE + sq * (i + 0.5), 0.03, (row - 0.5) * sq)
			mk.quad(c + Vector3(-sq * 0.5, 0, -sq * 0.5), c + Vector3(sq * 0.5, 0, -sq * 0.5),
				c + Vector3(sq * 0.5, 0, sq * 0.5), c + Vector3(-sq * 0.5, 0, sq * 0.5),
				Vector3.UP, Palette.UI_TEXT if dark else Palette.LANE_WHITE)
	return mk.commit()


static func _label(node_name: String, text: String, size: int, pos: Vector3, pixel := 0.006) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.font = UiTheme.font(900)
	label.font_size = size
	label.pixel_size = pixel
	label.outline_size = 0
	label.modulate = Palette.SIGN_WHITE
	label.shaded = false
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.position = pos
	return label
