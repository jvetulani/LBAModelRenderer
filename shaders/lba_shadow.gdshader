shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled, depth_draw_never;

uniform sampler2D shadow_texture : source_color, filter_nearest, repeat_disable;
uniform float shadow_opacity : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	vec4 source = texture(shadow_texture, UV);
	if (source.a < 0.5) {
		discard;
	}
	ALBEDO = source.rgb;
	ALPHA = source.a * shadow_opacity;
}
