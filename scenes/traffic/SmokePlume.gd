class_name SmokePlume
extends Node3D
## Chunky low-poly smoke rising off a wreck: a handful of gray puffs that swell,
## drift up and shrink away on a loop. Plain mesh nodes animated in code (not
## particles), so it costs almost nothing and behaves the same on web. It rides
## on a car that moves in the physics step, so it animates there too and gets
## the same physics interpolation.

const PUFFS := 5
const LIFE := 2.2
const RISE := 3.2
const SIZE := 1.5

static var _mesh: ArrayMesh

var _puffs: Array[MeshInstance3D] = []
var _age := 0.0
var _running := false


func _ready() -> void:
	if _mesh == null:
		var mk := MeshKit.new()
		mk.blob(Vector3.ZERO, Vector3.ONE * 0.5, Color(0.66, 0.64, 0.61), 7, 0.2)
		_mesh = mk.commit()
	for i in PUFFS:
		var puff := MeshInstance3D.new()
		puff.mesh = _mesh
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(puff)
		_puffs.append(puff)
	if not _running:
		visible = false
		set_physics_process(false)


func start() -> void:
	_running = true
	_age = 0.0
	visible = true
	set_physics_process(true)


func stop() -> void:
	_running = false
	visible = false
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	_age += delta
	for i in _puffs.size():
		# Puffs are evenly staggered through the cycle; each drifts a bit sideways.
		var t := fmod(_age + LIFE * i / PUFFS, LIFE) / LIFE
		var puff := _puffs[i]
		var swirl := float(i) * 2.4
		puff.position = Vector3(sin(swirl) * 0.4 + t * 0.6, t * RISE, cos(swirl) * 0.4 + t * 0.9)
		puff.scale = Vector3.ONE * SIZE * sin(t * PI) * (0.6 + 0.4 * t)
		puff.rotation = Vector3(t * 1.3, swirl + t, 0.0)
