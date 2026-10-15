class_name RoadChunk
extends Node3D
## One reusable piece of highway (straight or gentle curve). Chunk scenes use
## this as their root script and add decoration children (overpasses, later
## town exits and construction). RoadManager places, pools and recycles them.
##
## Children that implement `on_chunk_spawned(chunk: RoadChunk, rng)` get a
## call every time the chunk is (re)used, so they can re-randomize themselves.

const MAX_TREES := 40

## Length in meters. Keep it a multiple of RoadSpec.DASH_PERIOD (12 m).
@export var length := 120.0
## Total heading change across the chunk. Positive bends left.
@export_range(-15.0, 15.0, 0.5) var turn_degrees := 0.0
## False for set pieces (overpasses) that shouldn't appear twice in a row.
@export var allow_repeat := true
@export_range(0, 40) var tree_count := 24
## Local s ranges (x = from, y = to) that stay clear of trees, e.g. embankments.
@export var tree_free_ranges: Array[Vector2] = []

## Curvature (1 / radius). Positive bends left.
var kappa: float:
	get:
		return deg_to_rad(turn_degrees) / length

## No fence, poles, delineators or trees on the player's side (a set piece,
## like a parking lot, is there instead). Set by RoadManager before each use.
var open_right := false:
	set(value):
		if value != open_right:
			open_right = value
			if _structures:
				_structures.mesh = RoadMeshBuilder.structures_mesh(length, kappa, open_right)

## Road position of this chunk, assigned by RoadManager in place().
var start_s := 0.0
var start_pos := Vector3.ZERO
var start_yaw := 0.0
## The scene this chunk was instanced from (its pool).
var source_scene: PackedScene

var _oaks: MultiMeshInstance3D
var _cedars: MultiMeshInstance3D
var _structures: MeshInstance3D


func _ready() -> void:
	var surface := MeshInstance3D.new()
	surface.name = "Surface"
	surface.mesh = RoadMeshBuilder.surface_mesh(length, kappa)
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)

	_structures = MeshInstance3D.new()
	_structures.name = "Structures"
	_structures.mesh = RoadMeshBuilder.structures_mesh(length, kappa, open_right)
	add_child(_structures)

	_oaks = _make_trees("Oaks", Foliage.oak_mesh())
	_cedars = _make_trees("Cedars", Foliage.cedar_mesh())


func place(s: float, pos: Vector3, yaw: float) -> void:
	start_s = s
	start_pos = pos
	start_yaw = yaw
	transform = Transform3D(Basis(Vector3.UP, yaw), pos)


func end_s() -> float:
	return start_s + length


func world_point(s: float, d: float) -> Vector3:
	return start_pos + Basis(Vector3.UP, start_yaw) * RoadGeo.point(kappa, s - start_s, d)


func yaw_at(s: float) -> float:
	return start_yaw + RoadGeo.heading(kappa, s - start_s)


## World position -> road (s, d), using this chunk's geometry (extrapolates
## past the ends, so callers check whether s actually falls inside).
func project(world: Vector3) -> Vector2:
	var local := Basis(Vector3.UP, -start_yaw) * (world - start_pos)
	var sd := RoadGeo.project(kappa, local)
	return Vector2(sd.x + start_s, sd.y)


func on_spawned(rng: RandomNumberGenerator) -> void:
	_scatter_trees(rng)
	for child in get_children():
		if child.has_method("on_chunk_spawned"):
			child.on_chunk_spawned(self, rng)


func _make_trees(node_name: String, mesh: Mesh) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = MAX_TREES
	mm.visible_instance_count = 0
	var inst := MultiMeshInstance3D.new()
	inst.name = node_name
	inst.multimesh = mm
	# Trees never move while visible. Godot 4.4's MultiMesh physics
	# interpolation keeps freshly placed instances hidden, so opt out.
	inst.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Trees move on every reuse; a fixed box covering the whole chunk keeps
	# culling simple and correct.
	inst.custom_aabb = AABB(Vector3(-200.0, -1.0, -length - 40.0), Vector3(400.0, 16.0, length + 80.0))
	add_child(inst)
	return inst


## Trees grow in small clumps (mottes) beyond the fence on both sides.
func _scatter_trees(rng: RandomNumberGenerator) -> void:
	var oak_count := 0
	var cedar_count := 0
	var placed := 0
	var guard := 0
	while placed < tree_count and guard < tree_count * 4:
		guard += 1
		var side := 1.0 if rng.randf() < 0.5 and not open_right else -1.0
		var clump_s := rng.randf_range(0.0, length)
		var clump_d := side * (RoadSpec.FENCE_D + 5.0 + pow(rng.randf(), 1.7) * 120.0)
		for i in rng.randi_range(1, 5):
			var s := clampf(clump_s + rng.randf_range(-10.0, 10.0), 0.0, length)
			var d := clump_d + rng.randf_range(-9.0, 9.0)
			if absf(d) < RoadSpec.FENCE_D + 3.0 or _tree_blocked(s) or placed >= tree_count:
				continue
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.75, 1.35))
			var xf := Transform3D(basis, RoadGeo.point(kappa, s, d))
			if rng.randf() < 0.7:
				_oaks.multimesh.set_instance_transform(oak_count, xf)
				oak_count += 1
			else:
				_cedars.multimesh.set_instance_transform(cedar_count, xf)
				cedar_count += 1
			placed += 1
	_oaks.multimesh.visible_instance_count = oak_count
	_cedars.multimesh.visible_instance_count = cedar_count


func _tree_blocked(s: float) -> bool:
	for r in tree_free_ranges:
		if s >= r.x and s <= r.y:
			return true
	return false
