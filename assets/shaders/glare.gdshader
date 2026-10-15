shader_type spatial;
// Lens glare on a headlight: a hot spot plus a horizontal streak. Always faces
// the camera and draws over the car body, like a flare on a lens would.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.96, 0.85, 1.0);
uniform float energy = 1.0;

void vertex() {
	// Billboard: keep the node's position, take the camera's orientation.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float core = pow(max(0.0, 1.0 - length(p)), 3.0);
	float streak = exp(-abs(p.y) * 18.0) * max(0.0, 1.0 - abs(p.x));
	ALBEDO = tint.rgb * energy * (core * 1.5 + streak * 0.9);
}
