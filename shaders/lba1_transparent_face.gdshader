shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never;

uniform sampler2D palette_texture : source_color, filter_nearest, repeat_disable;

void fragment() {
	float palette_index = clamp(round(UV2.x), 0.0, 255.0);
	ALBEDO = texture(palette_texture, vec2((palette_index + 0.5) / 256.0, 0.5)).rgb;
	if (round(UV2.y) == 6.0) {
		// SVGAPolyTrame keeps alternating destination pixels; this is its
		// screen-door coverage in the native-resolution viewport.
		vec2 pixel = floor(FRAGCOORD.xy);
		if (mod(pixel.x + pixel.y, 2.0) < 1.0) {
			discard;
		}
		ALPHA = 1.0;
	} else {
		// SVGAPolyTrans replaces the high palette nibble and preserves the
		// destination's low nibble. Alpha is a portable RGB approximation.
		ALPHA = 0.5;
	}
}
