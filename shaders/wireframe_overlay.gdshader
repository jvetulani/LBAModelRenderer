shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_test_disabled, depth_draw_never;

uniform float width_pixels = 2.5;

void vertex() {
	vec4 start_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 end_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(CUSTOM0.xyz, 1.0);
	vec2 delta = (end_clip.xy / end_clip.w - start_clip.xy / start_clip.w) * VIEWPORT_SIZE;
	vec2 side = normalize(vec2(-delta.y, delta.x));
	float corner = CUSTOM0.w;
	bool use_end = corner >= 2.0;
	float sign_side = mod(corner, 2.0) < 0.5 ? -1.0 : 1.0;
	POSITION = use_end ? end_clip : start_clip;
	POSITION.xy += side * sign_side * width_pixels / VIEWPORT_SIZE * POSITION.w;
}

void fragment() {
	ALBEDO = vec3(0.22, 0.94, 0.82);
	ALPHA = 0.58;
}
