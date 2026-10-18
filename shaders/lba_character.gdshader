shader_type spatial;
render_mode cull_back, specular_disabled, shadows_disabled;

uniform sampler2D palette_texture : source_color, filter_nearest, repeat_disable;
uniform int palette_index_override = -1;
uniform bool use_mesh_lighting = false;
uniform float mesh_light_span = 7.0;
// 0 = palette bands, 1 = source MAT_DITHER faces (diagnostic),
// 2 = LBA-style dithered shading, 3 = smooth palette interpolation.
uniform int dither_mode = 2;
uniform float dither_pixel_scale = 1.0;
// Approximate integer vector from LBA1 SetLightVector(896, 950, 0): a
// 59-unit light rotated by the game's angle convention. Scene light changes
// and the original trigonometric lookup table are future work.
uniform vec3 source_light_vector = vec3(-25.8, 37.6, 37.6);

varying float source_palette_index;
varying flat float source_render_type;
varying flat float source_base_index;
varying vec3 pixel_source_normal;
varying float pixel_light_scale;

void vertex() {
	float base_index = palette_index_override >= 0
		? float(palette_index_override)
		: floor(UV2.x + 0.5);
	source_base_index = base_index;
	if (use_mesh_lighting) {
		vec3 normal_world = normalize(MODEL_NORMAL_MATRIX * NORMAL);
		pixel_source_normal = normal_world;
		pixel_light_scale = mesh_light_span / max(length(source_light_vector), 0.001);
		source_palette_index = base_index + max(dot(normal_world, normalize(source_light_vector)), 0.0) * mesh_light_span;
		source_render_type = 9.0;
	} else {
		float normal_length = length(CUSTOM0.xyz);
		pixel_source_normal = normal_length > 0.0 ? CUSTOM0.xyz / normal_length : vec3(0.0);
		pixel_light_scale = normal_length / max(CUSTOM0.w, 1.0);
		float shade = palette_index_override >= 0
			? 0.0
			: floor(max(dot(CUSTOM0.xyz, source_light_vector), 0.0) / max(CUSTOM0.w, 1.0));
		source_palette_index = mod(base_index + shade, 256.0);
		source_render_type = palette_index_override >= 0 ? -1.0 : UV2.y;
	}
}

void fragment() {
	float palette_index = floor(source_palette_index);
	if (dither_mode == 3 && source_render_type >= 7.0) {
		float pixel_shade = max(dot(normalize(pixel_source_normal), source_light_vector), 0.0) * pixel_light_scale;
		float smooth_index = mod(source_base_index + pixel_shade, 256.0);
		float lower_index = floor(smooth_index);
		float upper_index = mod(lower_index + 1.0, 256.0);
		vec3 lower_color = texture(palette_texture, vec2((lower_index + 0.5) / 256.0, 0.5)).rgb;
		vec3 upper_color = texture(palette_texture, vec2((upper_index + 0.5) / 256.0, 0.5)).rgb;
		ALBEDO = mix(lower_color, upper_color, fract(smooth_index));
		ROUGHNESS = 1.0;
	} else {
		bool dither_face = (dither_mode == 1 && source_render_type >= 10.0)
			|| (dither_mode == 2 && source_render_type >= 9.0);
		if (dither_face) {
			// LBA1 type 10 uses the dedicated SVGAPolyDith scanline path.
			// Diffuse the 8.8 palette-index fraction along each screen row. The
			// prefix sum is evaluated analytically in short blocks, so each fragment
			// runs in constant time even at 4K. Original polygon-edge scan conversion
			// and low-byte rotation still need a matched-game reference.
			float cell = dither_mode == 1 ? 1.0
				: max(1.0, floor(VIEWPORT_SIZE.y / 720.0 + 0.5)) * max(dither_pixel_scale, 1.0);
			float cell_x = floor(FRAGCOORD.x / cell);
			float local_x = mod(cell_x, 64.0);
			float row = floor(FRAGCOORD.y / cell);
			float phase = fract(row * 0.61803398875 + floor(cell_x / 64.0) * 0.41421356237);
			float shade = floor(source_palette_index * 256.0) / 256.0;
			float gradient = dFdx(source_palette_index) * cell;
			float first = shade - gradient * local_x;
			float prefix = (local_x + 1.0) * first + gradient * local_x * (local_x + 1.0) * 0.5;
			float previous = local_x * first + gradient * (local_x - 1.0) * local_x * 0.5;
			palette_index = floor(prefix + phase) - floor(previous + phase);
		}
		palette_index = mod(palette_index, 256.0);
		ALBEDO = texture(palette_texture, vec2((palette_index + 0.5) / 256.0, 0.5)).rgb;
		ROUGHNESS = 1.0;
	}
}

void light() {
	// The palette step is computed per vertex. One white directional light passes
	// that colour through; original light coefficients remain to be verified.
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION / PI;
}
