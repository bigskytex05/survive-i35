extends Node3D
## A cross-street bridge spanning the highway on concrete piers, with grassy
## embankments. Local X runs across the highway (+X = player's side), Z runs
## along it. The mesh is generated once and shared by every overpass chunk.
## Piers on the player's side have collision (they stand in the grass you can
## drive on, and later make good speed-trap hiding spots).

const DECK_BOTTOM := 7.0
const DECK_THICK := 1.1
const HALF_WIDTH := 5.5   # half the deck width, measured along the highway
const SPAN := 36.0        # center to abutment, measured across the highway
const RAMP := 75.0        # embankment length down to ground level
const PIER_X: Array[float] = [-19.5, 0.0, 19.5]
const COLUMN_Z := 2.8
const COLUMN_RADIUS := 0.55

static var _mesh: ArrayMesh


func _ready() -> void:
	if _mesh == null:
		_mesh = _build_mesh()
	var mi := MeshInstance3D.new()
	mi.name = "Bridge"
	mi.mesh = _mesh
	add_child(mi)
	_add_pier_collision()


func _add_pier_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "PierCollision"
	body.collision_layer = 1 << 2  # "obstacles"
	body.collision_mask = 0
	add_child(body)
	var shape := CylinderShape3D.new()
	shape.radius = COLUMN_RADIUS
	shape.height = DECK_BOTTOM
	for z: float in [-COLUMN_Z, COLUMN_Z]:
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = Vector3(PIER_X[2], DECK_BOTTOM * 0.5, z)
		body.add_child(col)


static func _build_mesh() -> ArrayMesh:
	var mk := MeshKit.new()
	var top := DECK_BOTTOM + DECK_THICK
	var road_half := HALF_WIDTH - 0.6
	# Deck, road surface and parapets.
	mk.box(Vector3(0, DECK_BOTTOM + DECK_THICK * 0.5, 0), Vector3(SPAN * 2.0, DECK_THICK, HALF_WIDTH * 2.0),
		Palette.CONCRETE_SHADE, Palette.CONCRETE)
	mk.box(Vector3(0, top + 0.03, 0), Vector3(SPAN * 2.0, 0.06, road_half * 2.0), Palette.ASPHALT)
	for z: float in [-(HALF_WIDTH - 0.16), HALF_WIDTH - 0.16]:
		mk.box(Vector3(0, top + 0.4, z), Vector3(SPAN * 2.0, 0.8, 0.32), Palette.CONCRETE)
	# Piers: a cap beam on two round columns.
	for x in PIER_X:
		mk.box(Vector3(x, DECK_BOTTOM - 0.45, 0), Vector3(1.6, 0.9, HALF_WIDTH * 2.0 - 0.6), Palette.CONCRETE)
		for z: float in [-COLUMN_Z, COLUMN_Z]:
			mk.prism(Vector3(x, 0, z), COLUMN_RADIUS, COLUMN_RADIUS, DECK_BOTTOM - 0.9, 8, Palette.CONCRETE)
	# Embankments: the cross street ramps down to ground level on both sides.
	for side: float in [1.0, -1.0]:
		var x0: float = SPAN * side
		var x1: float = (SPAN + RAMP) * side
		var foot := HALF_WIDTH + 14.0
		var normal_up := Vector3(side * DECK_BOTTOM / RAMP, 1.0, 0.0).normalized()
		mk.quad(Vector3(x0, top, -road_half), Vector3(x0, top, road_half),
			Vector3(x1, 0.05, road_half), Vector3(x1, 0.05, -road_half), normal_up, Palette.ASPHALT)
		for z_side: float in [1.0, -1.0]:
			var edge := Vector3(x0, top, HALF_WIDTH * z_side)
			var shoulder := Vector3(x0, top, road_half * z_side)
			var far_edge := Vector3(x1, 0.02, HALF_WIDTH * z_side)
			var far_shoulder := Vector3(x1, 0.05, road_half * z_side)
			mk.quad(shoulder, edge, far_edge, far_shoulder, normal_up, Palette.GRAVEL)
			mk.tri(edge, Vector3(x0, 0, foot * z_side), far_edge,
				Vector3(0.2 * side, 0.6, z_side).normalized(), Palette.GRASS_DARK)
		mk.quad(Vector3(x0, 0, -foot), Vector3(x0, top, -HALF_WIDTH),
			Vector3(x0, top, HALF_WIDTH), Vector3(x0, 0, foot), Vector3(-side, 0, 0), Palette.CONCRETE_SHADE)
		# The cross street carries on at ground level into the haze.
		mk.quad(Vector3(x1, 0.04, -road_half), Vector3(x1, 0.04, road_half),
			Vector3(x1 + 320.0 * side, 0.04, road_half), Vector3(x1 + 320.0 * side, 0.04, -road_half),
			Vector3.UP, Palette.ASPHALT)
	return mk.commit()
