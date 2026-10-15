shader_type spatial;
// Shared "toy" material: matte, flat-shaded facets.
// Face normals are rebuilt from screen-space derivatives, so every mesh
// (code-built or imported) gets crisp low-poly facets without needing
// duplicated vertices or special normals.
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
// Code-built meshes bake their colors into vertices (one material, one draw call).
uniform bool use_vertex_color = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.95;
uniform float specular : hint_range(0.0, 1.0) = 0.2;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;

void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	// Derivative sign conventions differ between GL backends; a visible face
	// always points toward the camera (VERTEX is the view-space position).
	NORMAL = dot(n, VERTEX) > 0.0 ? -n : n;
	vec3 base = albedo.rgb;
	if (use_vertex_color) {
		base *= COLOR.rgb;
	}
	ALBEDO = base;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	EMISSION = emission.rgb * emission_energy;
}
