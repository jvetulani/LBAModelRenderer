shader_type spatial;
render_mode cull_back, specular_disabled, shadows_disabled;

// LBA2 has an 8-bit VGA palette and a 256x256 indexed texture page.
// Both samplers are nearest-filtered; the atlas has no mipmaps.
uniform sampler2D palette_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D texture_atlas : filter_nearest, repeat_disable;
uniform sampler2D shade_table : filter_nearest, repeat_disable;
uniform bool has_texture_atlas = false;
uniform float normal_light_level = 12.0;
uniform int palette_index_override = -1;
uniform bool use_mesh_lighting = false;
uniform float mesh_light_span = 10.0;
uniform float preview_ambient_level = 2.0;
uniform float reverse_shade_strength = 0.0;
uniform int dither_mode = 2;
uniform float dither_pixel_scale = 1.0;
uniform vec3 source_light_vector = vec3(-4.4, 6.41, 6.41);

varying flat float face_palette_index;
varying flat float face_render_type;
varying flat vec4 texture_region;
varying float vertex_shade;
varying vec3 pixel_normal;
varying vec2 affine_uv_times_w;
varying float affine_w;

float dither_hash(vec2 coordinate) {
	return fract(sin(dot(coordinate, vec2(127.1, 311.7))) * 43758.5453);
}

float aperiodic_threshold(vec2 screen_pixel) {
	return dither_hash(floor(screen_pixel / max(dither_pixel_scale, 1.0)));
}

float varied_bayer_threshold(vec2 screen_pixel, float cell) {
	vec2 grid_pixel = floor(screen_pixel / cell);
	vec2 tile = floor(grid_pixel / 4.0);
	ivec2 pixel = ivec2(mod(grid_pixel, vec2(4.0)));
	int rotation = int(floor(dither_hash(tile) * 4.0));
	if (rotation == 1) {
		pixel = ivec2(3 - pixel.y, pixel.x);
	} else if (rotation == 2) {
		pixel = ivec2(3 - pixel.x, 3 - pixel.y);
	} else if (rotation == 3) {
		pixel = ivec2(pixel.y, 3 - pixel.x);
	}
	int bayer[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(bayer[pixel.y * 4 + pixel.x]) + 0.5) / 16.0;
}

void vertex() {
	face_palette_index = palette_index_override >= 0 ? float(palette_index_override) : floor(UV2.x + 0.5);
	face_render_type = palette_index_override >= 0 ? -1.0 : UV2.y;
	texture_region = CUSTOM1;
	float clip_w = (PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).w;
	affine_uv_times_w = UV * clip_w;
	affine_w = clip_w;
	pixel_normal = use_mesh_lighting ? normalize(MODEL_NORMAL_MATRIX * NORMAL) : CUSTOM0.xyz;
	float light_span = use_mesh_lighting ? mesh_light_span : length(source_light_vector);
	float source_strength = use_mesh_lighting ? 1.0 : min(length(pixel_normal) / 16384.0, 1.0);
	vertex_shade = length(pixel_normal) > 0.0
		? preview_ambient_level + max(dot(normalize(pixel_normal), normalize(source_light_vector)), 0.0) * (light_span - preview_ambient_level) * source_strength
		: 0.0;
}

void fragment() {
	float base_index = face_palette_index;
	bool textured = has_texture_atlas && face_render_type >= 8.0;
	if (textured) {
		// Modes 8-15 use screen-linear UVs in the original filler; 16-23 use Z correction.
		vec2 map_uv = face_render_type < 16.0 ? affine_uv_times_w / affine_w : UV;
		vec2 atlas_pixel = mod(texture_region.xy + mod(floor(map_uv), texture_region.zw + vec2(1.0)), vec2(256.0));
		base_index = floor(texture(texture_atlas, (atlas_pixel + vec2(0.5)) / 256.0).r * 255.0 + 0.5);
		// Source modes 12-15 and 20-23 use chroma key before the CLUT lookup.
		// Atlas index zero leaves the destination pixel untouched.
		if ((int(face_render_type) & 4) != 0 && base_index < 0.5) {
			discard;
		}
		// XPL shade rows remap each source texel into the same palette.
		// Adding light to the texel index crosses unrelated color ramps.
		float texture_shade = vertex_shade;
		if (dither_mode == 3 && length(pixel_normal) > 0.0) {
			texture_shade = preview_ambient_level + max(dot(normalize(pixel_normal), normalize(source_light_vector)), 0.0) * (mesh_light_span - preview_ambient_level) * (use_mesh_lighting ? 1.0 : min(length(pixel_normal) / 16384.0, 1.0));
		}
		int texture_kind = int(face_render_type) % 4;
		float light_row = clamp(texture_kind == 0 ? normal_light_level : texture_shade, 0.0, 15.0);
		float row = floor(light_row + 0.5);
		if (dither_mode == 2) {
			row = floor(light_row) + (fract(light_row) > aperiodic_threshold(FRAGCOORD.xy) ? 1.0 : 0.0);
		}
		float mapped_index = floor(texture(shade_table, vec2((base_index + 0.5) / 256.0, (row + 0.5) / 256.0)).r * 255.0 + 0.5);
		vec3 texture_color = texture(palette_texture, vec2((mapped_index + 0.5) / 256.0, 0.5)).rgb;
		if (dither_mode == 3) {
			float next_index = floor(texture(shade_table, vec2((base_index + 0.5) / 256.0, (min(row + 1.0, 15.0) + 0.5) / 256.0)).r * 255.0 + 0.5);
			vec3 next_color = texture(palette_texture, vec2((next_index + 0.5) / 256.0, 0.5)).rgb;
			texture_color = mix(texture_color, next_color, fract(light_row));
		}
		ALBEDO = texture_color;
	} else {
	float shade = vertex_shade;
	if (dither_mode == 3 && length(pixel_normal) > 0.0) {
		shade = preview_ambient_level + max(dot(normalize(pixel_normal), normalize(source_light_vector)), 0.0) * ((use_mesh_lighting ? mesh_light_span : length(source_light_vector)) - preview_ambient_level) * (use_mesh_lighting ? 1.0 : min(length(pixel_normal) / 16384.0, 1.0));
	}
	// LBA2's solid colors live in 16-entry ramps. Crossing a ramp boundary
	// turns pale eye whites (218-223) into the near-black ramp at 224.
	float ramp_start = floor(base_index / 16.0) * 16.0;
	// Some source colors are authored near the bright end of a ramp. Keeping
	// only upward shade steps flattens their entire normal range at the cap.
	float smooth_index = reverse_shade_strength > 0.0 && fract(base_index / 16.0) >= 0.75 && length(pixel_normal) > 0.0
		? max(base_index - (15.0 - shade) * reverse_shade_strength, ramp_start)
		: min(base_index + shade, ramp_start + 15.0);
	float lower_index = floor(smooth_index);
	float upper_index = mod(lower_index + 1.0, 256.0);
	if (dither_mode == 3) {
		vec3 lower_color = texture(palette_texture, vec2((lower_index + 0.5) / 256.0, 0.5)).rgb;
		vec3 upper_color = texture(palette_texture, vec2((upper_index + 0.5) / 256.0, 0.5)).rgb;
		ALBEDO = mix(lower_color, upper_color, fract(smooth_index));
	} else {
		int kind = int(floor(face_render_type + 0.5));
		bool source_dither = kind == 3 || kind == 5 || kind == 7 || kind == 11 || kind == 15 || kind == 19 || kind == 23;
		bool dither = (dither_mode == 1 && source_dither) || (dither_mode == 2 && shade > 0.0);
		float index = lower_index;
		if (dither) {
			float threshold = aperiodic_threshold(FRAGCOORD.xy);
			index = fract(smooth_index) > threshold ? upper_index : lower_index;
		}
		ALBEDO = texture(palette_texture, vec2((index + 0.5) / 256.0, 0.5)).rgb;
	}
	}
	ROUGHNESS = 1.0;
}

void light() {
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION / PI;
}
