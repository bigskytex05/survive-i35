shader_type canvas_item;
// Soft warm vignette laid over the 3D view (under the HUD).

uniform float strength : hint_range(0.0, 1.0) = 0.3;
uniform vec4 tint : source_color = vec4(0.16, 0.11, 0.07, 1.0);

void fragment() {
	vec2 uv = UV - vec2(0.5);
	// Slightly wider than tall so the effect hugs a landscape screen.
	float dist = length(uv * vec2(1.0, 0.8)) * 1.6;
	COLOR = vec4(tint.rgb, smoothstep(0.45, 1.15, dist) * strength);
}
