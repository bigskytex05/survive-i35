class_name Materials
extends RefCounted
## Shared material cache. Reusing one material per look keeps state changes
## (and draw-call cost) low, which matters on low-end phones and WebGL.

const FLAT_SHADER := preload("res://assets/shaders/flat.gdshader")

static var _by_key: Dictionary = {}
static var _vertex_colored: ShaderMaterial


## The one material used by every code-built, vertex-colored mesh.
static func vertex_colored() -> ShaderMaterial:
	if _vertex_colored == null:
		_vertex_colored = ShaderMaterial.new()
		_vertex_colored.shader = FLAT_SHADER
		_vertex_colored.set_shader_parameter("use_vertex_color", true)
	return _vertex_colored


## Flat-shaded single-color material, cached per color.
static func flat(color: Color, roughness := 0.95) -> ShaderMaterial:
	var key := "%s/%.2f" % [color.to_html(), roughness]
	if not _by_key.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = FLAT_SHADER
		mat.set_shader_parameter("albedo", color)
		mat.set_shader_parameter("roughness", roughness)
		_by_key[key] = mat
	return _by_key[key]


## Glowing material whose brightness can be animated (brake lights, police bars).
## Not cached: each user owns its instance so it can change the energy.
static func glow(color: Color, energy := 1.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FLAT_SHADER
	mat.set_shader_parameter("albedo", color)
	mat.set_shader_parameter("emission", color)
	mat.set_shader_parameter("emission_energy", energy)
	return mat
