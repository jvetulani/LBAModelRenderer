shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform float opacity = 0.58;
uniform vec2 height_range = vec2(0.0, 1.0);

varying float flame_height;

void vertex() {
	flame_height = clamp((VERTEX.y - height_range.x) / max(height_range.y - height_range.x, 0.001), 0.0, 1.0);
}

void fragment() {
	vec3 ember = vec3(1.0, 0.25, 0.035);
	vec3 flame = vec3(1.0, 0.73, 0.12);
	ALBEDO = mix(ember, flame, flame_height);
	ALPHA = opacity * (1.0 - 0.28 * flame_height);
}
