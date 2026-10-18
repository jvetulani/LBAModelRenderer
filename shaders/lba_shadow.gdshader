shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque;

uniform sampler2D shadow_texture : source_color, filter_nearest, repeat_disable;

void fragment() {
	vec4 source = texture(shadow_texture, UV);
	if (source.a < 0.5) {
		discard;
	}
	ALBEDO = source.rgb;
}
