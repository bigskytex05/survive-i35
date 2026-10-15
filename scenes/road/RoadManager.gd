class_name RoadManager
extends Node3D
## Streams road chunks ahead of the player and recycles the ones left behind.
##
## It is also the authority on road coordinates: s = meters along the road,
## d = meters right of the median centerline (see RoadSpec). Traffic, cones and
## speed traps can live entirely in (s, d) and ask the road for world positions.
##
## Chunk choice is a weighted mix for now. Levels (Phase 6) will feed their own
## sequence/weights so stretches feel authored rather than random.
##
## Set pieces (a level's FinishSite) can shape the road around them with zones
## in road coordinates, set before reset():
## - straight_zone: chunks overlapping it are straight;
## - open_zone: chunks overlapping it are the plain straight chunk (the first in
##   chunk_scenes) with no fence, trees or poles on the player's side;
## - paved zones: drivable at full speed (surface_at says LANE);
## - limit zones: move the hard outer boundary (outer_limit_at), e.g. out to the
##   far edge of a parking lot.

@export var chunk_scenes: Array[PackedScene] = []
## Relative pick weights, same order as chunk_scenes (missing entries = 1).
@export var chunk_weights: PackedFloat32Array = PackedFloat32Array()
@export var view_ahead := 540.0
@export var keep_behind := 100.0
## The road starts this far behind s = 0, which sits at the world origin.
@export var road_start_s := -120.0
## Chunks starting before this s are kept straight (a calm spawn area).
@export var straight_until_s := 240.0
## Past this heading drift (either way), curves that would add to it are skipped.
@export var max_heading_drift_deg := 20.0
## 0 = different road every run.
@export var rng_seed := 0

## How many chunk nodes were ever instanced (pooling keeps this small).
var instanced_count := 0
## Road s ranges (x = from, y = to); see the class notes.
var straight_zone := Vector2(INF, -INF)
var open_zone := Vector2(INF, -INF)

var _paved: Array[Rect2] = []        # position = (s, d) corner, size = (along, across)
var _limits: Array[Vector3] = []     # (from s, to s, outer limit d); later zones win

var _active: Array[RoadChunk] = []
var _pools: Dictionary = {}        # PackedScene -> Array of idle RoadChunks
var _probe_cache: Dictionary = {}  # PackedScene -> {turn, allow_repeat}
var _end_s := 0.0
var _end_pos := Vector3.ZERO
var _end_yaw := 0.0
var _last_scene: PackedScene
var _rng := RandomNumberGenerator.new()


func reset(seed_value := rng_seed) -> void:
	while not _active.is_empty():
		_release(_active.pop_back())
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_end_s = road_start_s
	_end_pos = Vector3(0.0, 0.0, -road_start_s)  # puts s = 0 at the origin
	_end_yaw = 0.0
	_last_scene = null


## Call every physics tick with the player's s.
func update_stream(focus_s: float) -> void:
	while _end_s < focus_s + view_ahead:
		_spawn_next()
	while _active.size() > 1 and _active[0].end_s() < focus_s - keep_behind:
		_release(_active.pop_front())


## How far the road has been built (the s of its far end).
func streamed_to() -> float:
	return _end_s


func active_count() -> int:
	return _active.size()


func active_chunks() -> Array[RoadChunk]:
	return _active


func chunk_at(s: float) -> RoadChunk:
	for chunk in _active:
		if s < chunk.end_s():
			return chunk
	return _active.back()


## World position of road coordinate (s, d).
func sample(s: float, d := 0.0) -> Vector3:
	return chunk_at(s).world_point(s, d)


## Road heading (yaw) at s.
func yaw_at(s: float) -> float:
	return chunk_at(s).yaw_at(s)


## Road curvature (1 / radius, positive = bending left) at s.
func curvature_at(s: float) -> float:
	return chunk_at(s).kappa


## Paves a rectangle of road coordinates: from s0 to s1, from d0 to d1.
func add_paved_zone(s0: float, s1: float, d0: float, d1: float) -> void:
	_paved.append(Rect2(s0, d0, s1 - s0, d1 - d0))


## Moves the player's outer boundary (normally the ranch fence) to `limit_d`
## between s0 and s1.
func add_limit_zone(s0: float, s1: float, limit_d: float) -> void:
	_limits.append(Vector3(s0, s1, limit_d))


func clear_zones() -> void:
	straight_zone = Vector2(INF, -INF)
	open_zone = Vector2(INF, -INF)
	_paved.clear()
	_limits.clear()


## What's under the wheels at (s, d) on the player's side.
func surface_at(s: float, d: float) -> RoadSpec.Surface:
	for zone in _paved:
		if zone.has_point(Vector2(s, d)):
			return RoadSpec.Surface.LANE
	return RoadSpec.surface_at(d)


## The hard outer boundary on the player's side at s (meters right of the median).
func outer_limit_at(s: float) -> float:
	var limit := RoadSpec.FENCE_D
	for zone in _limits:
		if s >= zone.x and s <= zone.y:
			limit = zone.z
	return limit


## World position -> Vector2(s, d).
func project(world: Vector3) -> Vector2:
	var best := Vector2.ZERO
	var best_err := INF
	for chunk in _active:
		var sd := chunk.project(world)
		var local_s := sd.x - chunk.start_s
		var err := maxf(-local_s, local_s - chunk.length)
		if err <= 0.0:
			return sd
		if err < best_err:
			best_err = err
			best = sd
	return best


func _spawn_next() -> void:
	var scene := _pick_scene()
	var chunk := _acquire(scene)
	chunk.place(_end_s, _end_pos, _end_yaw)
	chunk.open_right = _overlaps(open_zone, _end_s, _end_s + chunk.length)
	add_child(chunk)
	chunk.reset_physics_interpolation()
	chunk.on_spawned(_rng)
	_active.append(chunk)
	_end_pos = chunk.world_point(chunk.end_s(), 0.0)
	_end_yaw = chunk.yaw_at(chunk.end_s())
	_end_s = chunk.end_s()
	_last_scene = scene


func _pick_scene() -> PackedScene:
	var length: float = _probe(chunk_scenes[0]).length
	if _overlaps(open_zone, _end_s, _end_s + length):
		return chunk_scenes[0]
	var force_straight := _overlaps(straight_zone, _end_s, _end_s + length)
	var drift := rad_to_deg(_end_yaw)
	var options: Array[PackedScene] = []
	var weights: Array[float] = []
	var total := 0.0
	for i in chunk_scenes.size():
		var scene := chunk_scenes[i]
		var info := _probe(scene)
		var turn: float = info.turn
		var w := chunk_weights[i] if i < chunk_weights.size() else 1.0
		if (_end_s < straight_until_s or force_straight) and turn != 0.0:
			continue
		if scene == _last_scene and not info.allow_repeat:
			continue
		if (turn > 0.0 and drift > max_heading_drift_deg) or (turn < 0.0 and drift < -max_heading_drift_deg):
			continue
		# Gently favor curves that steer the road back toward its original heading.
		if turn != 0.0 and absf(drift) > 5.0 and signf(turn) != signf(drift):
			w *= 2.0
		if w <= 0.0:
			continue
		options.append(scene)
		weights.append(w)
		total += w
	if options.is_empty():
		return chunk_scenes[0]
	var roll := _rng.randf() * total
	for i in options.size():
		roll -= weights[i]
		if roll <= 0.0:
			return options[i]
	return options.back()


## Reads a chunk scene's exported settings once (the probe goes into its pool).
func _probe(scene: PackedScene) -> Dictionary:
	if not _probe_cache.has(scene):
		var chunk := _acquire(scene)
		_probe_cache[scene] = {turn = chunk.turn_degrees, allow_repeat = chunk.allow_repeat, length = chunk.length}
		_pools[scene].append(chunk)
	return _probe_cache[scene]


static func _overlaps(zone: Vector2, from: float, to: float) -> bool:
	return to > zone.x and from < zone.y


func _acquire(scene: PackedScene) -> RoadChunk:
	if not _pools.has(scene):
		_pools[scene] = []
	var pool: Array = _pools[scene]
	if not pool.is_empty():
		return pool.pop_back()
	var chunk := scene.instantiate() as RoadChunk
	assert(chunk != null, "Road chunk scenes need RoadChunk.gd on their root")
	chunk.source_scene = scene
	instanced_count += 1
	return chunk


func _release(chunk: RoadChunk) -> void:
	remove_child(chunk)
	_pools[chunk.source_scene].append(chunk)


func _exit_tree() -> void:
	# Idle chunks are outside the tree, so free them explicitly.
	for pool in _pools.values():
		for chunk in pool:
			chunk.free()
	_pools.clear()
