shader_type spatial;
render_mode blend_mix, depth_draw_never, depth_test_disabled, cull_back, unshaded;

uniform sampler2D texture_atlas : filter_nearest, repeat_disable;
uniform float opacity = 0.42;

varying flat float face_render_type;
varying flat vec4 texture_region;
varying vec2 affine_uv_times_w;
varying float affine_w;

void vertex() {
	face_render_type = UV2.y;
	texture_region = CUSTOM1;
	float clip_w = (PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).w;
	affine_uv_times_w = UV * clip_w;
	affine_w = clip_w;
}

void fragment() {
	int kind = int(face_render_type);
	if (kind < 8 || (kind & 4) == 0) {
		discard;
	}
	vec2 map_uv = kind < 16 ? affine_uv_times_w / affine_w : UV;
	vec2 atlas_pixel = mod(texture_region.xy + mod(floor(map_uv), texture_region.zw + vec2(1.0)), vec2(256.0));
	float index = floor(texture(texture_atlas, (atlas_pixel + vec2(0.5)) / 256.0).r * 255.0 + 0.5);
	if (index > 0.5) {
		discard;
	}
	ALBEDO = vec3(0.38, 0.47, 0.55);
	ALPHA = opacity;
}
