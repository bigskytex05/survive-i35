class_name SpeedTrap
extends Node3D
## One speed trap: a state trooper parked off the right side of the road,
## partly hidden behind roadside cover, with the sun glinting off its
## windshield every couple of seconds (the tell to watch for). Cover is a
## billboard over a hedge, a big live oak, or (when the road happens to pass
## under one nearby) an overpass, with the cruiser tucked behind the piers.
##
## It's scenery until Police launches it into a chase: then the parked car
## disappears and a PoliceCar takes its place in traffic.

enum Cover { BILLBOARD, OAK, OVERPASS }

## Where the cruiser sits, meters right of the median, and how far its nose
## is turned toward the road.
const COP_D := 20.0
const COP_ANGLE := 0.5
## How far along the road an overpass may be for the trap to move under it.
const OVERPASS_REACH := 160.0
const GLINT_EVERY := 1.8
const GLINT_TIME := 0.32
const GLINT_SIZE := 2.2
const GLINT := preload("res://assets/ui/glint.svg")
const ADS: Array = [
	["INJURED?", "CALL 1-800-TEX-SUES"],
	["KOLACHES", "NEXT EXIT · OPEN 24 HRS"],
	["WORLD'S BIGGEST PECAN", "42 MILES · DON'T MISS IT"],
	["CLEAN RESTROOMS", "ONLY 89 MILES AHEAD"],
	["JERKY  JERKY  JERKY", "EXIT 261 · JERKY"],
	["FIREWORKS", "BIGGEST SELECTION IN TEXAS"],
]

## Road position of the cruiser.
var s := 0.0
var d := COP_D
var cover: Cover = Cover.BILLBOARD
var placed := false
var launched := false
## Sped through it with the Radar Detector on.
var dodged := false
## The cruiser's heading relative to the road (positive = nose toward the median).
var rel_yaw := COP_ANGLE

var _cop: Node3D
var _glint: Sprite3D
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(at_s: float, rng_seed: int) -> void:
	s = at_s
	_rng.seed = rng_seed
	cover = Cover.BILLBOARD if _rng.randf() < 0.5 else Cover.OAK
	_t = _rng.randf() * GLINT_EVERY


## The overpass chunk nearest to s among the built road, if one is close enough:
## the trap moves to just past its piers. Returns the bridge's s or NAN.
static func overpass_near(road: RoadManager, at_s: float) -> float:
	var best := NAN
	for chunk in road.active_chunks():
		if chunk.source_scene == null or not chunk.source_scene.resource_path.ends_with("overpass.tscn"):
			continue
		var bridge := chunk.start_s + chunk.length * 0.5
		if absf(bridge - at_s) < OVERPASS_REACH and (is_nan(best) or absf(bridge - at_s) < absf(best - at_s)):
			best = bridge
	return best


## Builds the scene once the road reaches past it. `police` is the trooper's
## TrafficCarData (for the cruiser's look).
func place(road: RoadManager, police: TrafficCarData) -> void:
	var bridge := overpass_near(road, s)
	if not is_nan(bridge):
		cover = Cover.OVERPASS
		s = bridge + 7.5
		d = 20.6
	transform = Transform3D(Basis(Vector3.UP, road.yaw_at(s)), road.sample(s, 0.0))
	var mk := MeshKit.new()
	match cover:
		Cover.BILLBOARD:
			_billboard(mk)
		Cover.OAK:
			_oak(mk)
	if cover != Cover.OVERPASS:
		add_child(Scenery.mesh_node("Cover", mk))
	_build_cop(police)
	# It just jumped here from the origin: don't let the renderer slide it over.
	reset_physics_interpolation()
	placed = true


## Where the parked cruiser is, in road coordinates (s, d) and heading.
func cop_footprint(police: TrafficCarData) -> Footprint:
	var fp := Footprint.new()
	fp.s = s
	fp.d = d
	fp.rel_yaw = rel_yaw
	fp.half_len = police.size.z * 0.5
	fp.half_wid = police.size.x * 0.5
	return fp


## The chase is on: the parked cruiser leaves (a PoliceCar replaces it).
func launch() -> void:
	launched = true
	if _cop:
		_cop.queue_free()
		_cop = null
	if _glint:
		_glint.visible = false


func _physics_process(delta: float) -> void:
	if _glint == null or launched:
		return
	# Sun on the windshield: a quick star, now and then.
	_t += delta
	var u := fmod(_t, GLINT_EVERY) / GLINT_TIME
	_glint.visible = u < 1.0
	if u < 1.0:
		var k := sin(u * PI)
		_glint.scale = Vector3.ONE * k
		_glint.rotation.z = u * 0.6


# --- Building -------------------------------------------------------------------------

func _build_cop(police: TrafficCarData) -> void:
	_cop = Node3D.new()
	_cop.name = "ParkedCruiser"
	# The cruiser is at d, s = 0 in this node's frame; rel_yaw turns its nose
	# toward the road (left).
	_cop.transform = Scenery.at(0.0, d, rel_yaw)
	add_child(_cop)
	var body := MeshInstance3D.new()
	body.mesh = TrafficModel.body_mesh(police, Palette.POLICE_BLACK)
	_cop.add_child(body)
	for side: float in [-1.0, 1.0]:
		var bar := MeshInstance3D.new()
		bar.mesh = TrafficModel.police_bar_mesh(police, side)
		bar.material_override = TrafficModel.police_material(side, false)
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cop.add_child(bar)
	# Solid, like the overpass piers: drive into it and you'll know.
	var solid := StaticBody3D.new()
	solid.collision_layer = 1 << 2
	solid.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = police.size
	shape.shape = box
	shape.position = Vector3(0.0, police.size.y * 0.5, 0.0)
	solid.add_child(shape)
	_cop.add_child(solid)
	_glint = Sprite3D.new()
	_glint.texture = GLINT
	_glint.pixel_size = GLINT_SIZE / float(GLINT.get_width())
	_glint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_glint.shaded = false
	_glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glint.visible = false
	# The windshield, toward the front of the cabin.
	_glint.position = Vector3(0.0, police.size.y * 0.78, -police.size.z * 0.18)
	_cop.add_child(_glint)


## A billboard on stilts with a hedge along its foot; the cruiser idles in the
## gap just past the hedge.
func _billboard(mk: MeshKit) -> void:
	var at := Scenery.at(-5.0, d + 3.5, -0.35)
	var width := 13.0
	var height := 5.2
	var bottom := 4.4
	for x: float in [-width * 0.33, width * 0.33]:
		mk.xf = at * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
		mk.box(Vector3(0, (bottom + height) * 0.5, 0.15), Vector3(0.35, bottom + height, 0.35), Palette.TRUNK)
	mk.xf = at
	mk.box(Vector3(0, bottom + height * 0.5, 0), Vector3(width + 0.3, height + 0.3, 0.2), Palette.TRIM)
	var ad: Array = ADS[_rng.randi() % ADS.size()]
	var colors := [Color(0.95, 0.83, 0.3), Color(0.86, 0.3, 0.24), Color(0.25, 0.47, 0.72), Color(0.96, 0.95, 0.9)]
	var face: Color = colors[_rng.randi() % colors.size()]
	mk.box(Vector3(0, bottom + height * 0.5, 0.06), Vector3(width, height, 0.2), face)
	mk.xf = Transform3D.IDENTITY
	var ink := Palette.UI_TEXT if face.get_luminance() > 0.6 else Palette.SIGN_WHITE
	# As big as fits across the board.
	var sizes := [mini(150, int(12.0 / (String(ad[0]).length() * 0.6 * 0.012))),
		mini(70, int(12.0 / (String(ad[1]).length() * 0.6 * 0.012)))]
	add_child(Scenery.sign_text(at * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.1)), bottom + height * 0.5,
		[ad[0], ad[1]], sizes, ink, 0.012))
	_hedge(mk, -9.0, -2.2)


## A big spreading live oak with brush around its trunk.
func _oak(mk: MeshKit) -> void:
	mk.xf = Scenery.at(-2.0, d + 2.5)
	mk.prism(Vector3.ZERO, 0.7, 0.5, 3.4, 7, Palette.TRUNK)
	mk.blob(Vector3(0.0, 5.0, 0.0), Vector3(7.5, 2.6, 6.5), Palette.LEAF, 21)
	mk.blob(Vector3(3.2, 4.4, 2.0), Vector3(4.2, 1.8, 3.6), Palette.LEAF_DARK, 22)
	mk.blob(Vector3(-3.4, 4.6, -1.6), Vector3(4.0, 1.9, 3.8), Palette.LEAF_LIGHT, 23)
	mk.xf = Transform3D.IDENTITY
	_hedge(mk, -7.5, -2.8)


## A row of bushes (s0..s1 in this node's frame, before the cruiser) that hides
## the cruiser's tail from drivers coming up the road.
func _hedge(mk: MeshKit, s0: float, s1: float) -> void:
	var n := 4
	for i in n:
		var u := float(i) / (n - 1)
		var center := Scenery.at(lerpf(s0, s1, u), d - 0.2 + _rng.randf_range(-0.6, 0.6))
		mk.xf = center
		var size := Vector3(_rng.randf_range(1.6, 2.2), _rng.randf_range(1.1, 1.5), _rng.randf_range(1.6, 2.2))
		mk.blob(Vector3(0, size.y * 0.8, 0), size, Palette.LEAF_DARK if i % 2 == 0 else Palette.LEAF, 30 + i)
	mk.xf = Transform3D.IDENTITY
