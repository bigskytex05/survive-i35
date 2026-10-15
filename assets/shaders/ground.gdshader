shader_type spatial;
// Endless pasture under the highway. Patches of greener and drier grass come
// from cheap world-space value noise, posterized into flat zones to match the
// low-poly look. Patterns are anchored to the world, so the plane can follow
// the car without the grass sliding.
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform vec4 grass : source_color = vec4(0.74, 0.7, 0.47, 1.0);
uniform vec4 grass_dry : source_color = vec4(0.82, 0.76, 0.54, 1.0);
uniform vec4 grass_dark : source_color = vec4(0.64, 0.63, 0.4, 1.0);
uniform float patch_scale = 0.014;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz * patch_scale;
	float n = value_noise(p) * 0.65 + value_noise(p * 3.7 + 17.0) * 0.35;
	vec3 c = mix(grass_dark.rgb, grass.rgb, smoothstep(0.34, 0.4, n));
	c = mix(c, grass_dry.rgb, smoothstep(0.62, 0.68, n));
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
