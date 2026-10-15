shader_type spatial;
// High-beam light: additive, so it only brightens what's behind it and the
// daylight scene stays daylight. UV.y runs from the lamp (0) to the far end of
// the beam (1). Cones soften toward their silhouette; the pool on the road
// (ground = true) softens toward its sides with UV.x.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.95, 0.78, 1.0);
uniform float energy = 1.0;
uniform float strength = 0.45;
uniform bool ground = false;

void fragment() {
	float fade = pow(1.0 - UV.y, 1.4);
	float edge;
	if (ground) {
		edge = 1.0 - pow(abs(UV.x * 2.0 - 1.0), 2.0);
	} else {
		edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
	}
	ALBEDO = tint.rgb * energy * strength * fade * edge;
}
