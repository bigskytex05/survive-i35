class_name BeamLights
extends Node3D
## How the high beams look in broad daylight: an additive light cone from each
## headlight, a pool of light on the road ahead and lens glare on the lamps.
## The cones and glare ride on the bouncing body; the pool stays on the road.

const BEAM_SHADER := preload("res://assets/shaders/beam.gdshader")
const GLARE_SHADER := preload("res://assets/shaders/glare.gdshader")
const CONE_SIDES := 12
const GLARE_SIZE := 2.8

var _beam_mat: ShaderMaterial
var _pool_mat: ShaderMaterial
var _glare_mat: ShaderMaterial
var _parts: Array[Node3D] = []
var _intensity := 0.0
var _t := 0.0


## `model` is the player's CarModel. Length in meters, half_angle in radians.
func build(model: CarModel, length: float, half_angle: float) -> void:
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = BEAM_SHADER
	_pool_mat = ShaderMaterial.new()
	_pool_mat.shader = BEAM_SHADER
	_pool_mat.set_shader_parameter("ground", true)
	_pool_mat.set_shader_parameter("strength", 0.3)
	_glare_mat = ShaderMaterial.new()
	_glare_mat.shader = GLARE_SHADER
	var cone := _cone_mesh(length, half_angle)
	var glare := QuadMesh.new()
	glare.size = Vector2(GLARE_SIZE * 1.6, GLARE_SIZE)
	var body: Node3D = model.body_pivot if model.body_pivot else model
	var nose := 0.0
	for lamp in model.headlights:
		var beam := _mesh_part(cone, _beam_mat)
		beam.position = lamp
		beam.rotation.x = -0.035  # aimed a touch down the road
		body.add_child(beam)
		var flare := _mesh_part(glare, _glare_mat)
		flare.position = lamp + Vector3(0.0, 0.0, -0.1)
		body.add_child(flare)
		nose = lamp.z
	var pool := _mesh_part(_pool_mesh(length * 0.85, half_angle), _pool_mat)
	pool.position = Vector3(0.0, 0.06, nose)
	model.add_child(pool)
	set_intensity(0.0)


func set_intensity(k: float) -> void:
	_intensity = k
	for part in _parts:
		part.visible = k > 0.001
	if k <= 0.001:
		return
	_beam_mat.set_shader_parameter("energy", k)
	_pool_mat.set_shader_parameter("energy", k)


func _process(delta: float) -> void:
	if _intensity <= 0.001:
		return
	_t += delta
	# A little shimmer on the glare.
	_glare_mat.set_shader_parameter("energy", _intensity * (0.9 + 0.1 * sin(_t * 31.0)))


func _mesh_part(mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_parts.append(mi)
	return mi


## Open cone with its tip at the origin, opening toward -Z. UV.y = distance
## along the beam (0..1); normals point away from the axis.
static func _cone_mesh(length: float, half_angle: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius := length * tan(half_angle)
	for i in CONE_SIDES:
		var a0 := TAU * i / CONE_SIDES
		var a1 := TAU * (i + 1) / CONE_SIDES
		var n0 := Vector3(cos(a0), sin(a0), tan(half_angle)).normalized()
		var n1 := Vector3(cos(a1), sin(a1), tan(half_angle)).normalized()
		for v: Array in [[Vector3.ZERO, (n0 + n1).normalized(), 0.0],
				[Vector3(cos(a0) * radius, sin(a0) * radius, -length), n0, 1.0],
				[Vector3(cos(a1) * radius, sin(a1) * radius, -length), n1, 1.0]]:
			st.set_normal(v[1])
			st.set_uv(Vector2(0.5, v[2]))
			st.add_vertex(v[0])
	return st.commit()


## Flat fan of light on the road from the nose forward, in strips so the
## fades interpolate smoothly. UV.x runs across (0..1), UV.y along (0..1).
static func _pool_mesh(length: float, half_angle: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 8
	for i in steps:
		var v0 := float(i) / steps
		var v1 := float(i + 1) / steps
		var w0 := 1.1 + length * v0 * tan(half_angle)
		var w1 := 1.1 + length * v1 * tan(half_angle)
		var quad: Array = [
			[Vector3(-w0, 0.0, -length * v0), Vector2(0.0, v0)], [Vector3(w0, 0.0, -length * v0), Vector2(1.0, v0)],
			[Vector3(w1, 0.0, -length * v1), Vector2(1.0, v1)], [Vector3(-w1, 0.0, -length * v1), Vector2(0.0, v1)]]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(quad[k][1])
			st.add_vertex(quad[k][0])
	return st.commit()
