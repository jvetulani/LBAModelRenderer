shader_type spatial;
render_mode cull_back, specular_disabled, shadows_disabled;

uniform sampler2D palette_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D texture_atlas : filter_nearest, repeat_disable;
uniform sampler2D shade_table : filter_nearest, repeat_disable;
uniform bool has_texture_atlas = false;
uniform bool has_shade_table = false;
uniform float normal_light_level = 12.0;
uniform int palette_index_override = -1;
uniform bool use_mesh_lighting = false;
uniform float mesh_light_span = 7.0;
// 0 = palette bands, 1 = source MAT_DITHER faces (diagnostic),
// 2 = strong screen dither, 3 = smooth, 4 = soft model-anchored dither.
uniform int dither_mode = 4;
uniform float dither_pixel_scale = 1.0;
uniform bool platform_style = false;
// Approximate integer vector from LBA1 SetLightVector(896, 950, 0): a
// 59-unit light rotated by the game's angle convention. Scene light changes
// and the original trigonometric lookup table are future work.
uniform vec3 source_light_vector = vec3(-25.8, 37.6, 37.6);

varying float source_palette_index;
varying flat float source_render_type;
varying flat float source_base_index;
varying vec3 pixel_source_normal;
varying float pixel_light_scale;
varying float platform_height;
varying flat vec4 texture_region;
varying vec3 dither_anchor;

float dither_hash(vec2 coordinate) {
	return fract(sin(dot(coordinate, vec2(127.1, 311.7))) * 43758.5453);
}

float aperiodic_threshold(vec2 screen_pixel) {
	return dither_hash(floor(screen_pixel / max(dither_pixel_scale, 1.0)));
}

vec2 anchored_dither_coord() {
	vec3 face_axis = abs(cross(dFdx(dither_anchor), dFdy(dither_anchor)));
	if (face_axis.x > face_axis.y && face_axis.x > face_axis.z) {
		return dither_anchor.yz * 256.0;
	}
	if (face_axis.y > face_axis.z) {
		return dither_anchor.xz * 256.0;
	}
	return dither_anchor.xy * 256.0;
}

float anchored_dither_threshold(vec2 coord) {
	vec2 cell = floor(coord);
	return fract(52.9829189 * fract(dot(cell, vec2(0.06711056, 0.00583715))));
}

float anchored_dither_weight(vec2 coord) {
	float footprint = max(length(dFdx(coord)), length(dFdy(coord)));
	return 1.0 - smoothstep(0.75, 1.5, footprint);
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
	texture_region = CUSTOM1;
	dither_anchor = CUSTOM2.xyz;
	platform_height = clamp((VERTEX.y + 0.06) / 0.12, 0.0, 1.0);
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
		float vertex_shade = palette_index_override >= 0
			? 0.0
			: max(dot(CUSTOM0.xyz, source_light_vector), 0.0) / max(CUSTOM0.w, 1.0);
		// Soft dither needs the continuous vertex light level. Rounding here
		// exposes every triangle before the fragment can blend palette steps.
		// A small ambient lift also reduces the severe dark facets that become
		// conspicuous when the original low-resolution body fills a HD viewport.
		float soft_vertex_shade = 3.0 + vertex_shade * 0.65;
		float shade = dither_mode == 4 && palette_index_override < 0 ? soft_vertex_shade : floor(vertex_shade);
		source_palette_index = mod(base_index + shade, 256.0);
		source_render_type = palette_index_override >= 0 ? -1.0 : UV2.y;
	}
}

void fragment() {
	float palette_index = floor(source_palette_index);
	if (has_texture_atlas && (source_render_type == 12.0 || source_render_type == 13.0 || source_render_type == 14.0 || source_render_type == 16.0 || source_render_type == 20.0 || source_render_type == 24.0)) {
		// LBA2-96 stores texture coordinates and a repeat region on its
		// compact LBA1-style polygons. The page remains indexed and unfiltered.
		vec2 atlas_pixel = mod(texture_region.xy + mod(floor(UV), texture_region.zw + vec2(1.0)), vec2(256.0));
		float texel = floor(texture(texture_atlas, (atlas_pixel + vec2(0.5)) / 256.0).r * 255.0 + 0.5);
		float original_texel = texel;
		vec3 shaded_color = vec3(0.0);
		bool soft_shade = has_shade_table && dither_mode == 4;
		if (has_shade_table) {
			float lighting = length(pixel_source_normal) > 0.0
				? clamp(source_palette_index - source_base_index, 0.0, 15.0)
				: normal_light_level;
			float row = soft_shade || dither_mode == 3 ? floor(lighting) : floor(lighting + 0.5);
			if (dither_mode == 2) {
				row = floor(lighting) + (fract(lighting) > aperiodic_threshold(FRAGCOORD.xy) ? 1.0 : 0.0);
			}
			texel = floor(texture(shade_table, vec2((texel + 0.5) / 256.0, (row + 0.5) / 256.0)).r * 255.0 + 0.5);
			if (soft_shade || dither_mode == 3) {
				float next_index = floor(texture(shade_table, vec2((original_texel + 0.5) / 256.0, (min(row + 1.0, 15.0) + 0.5) / 256.0)).r * 255.0 + 0.5);
				vec3 lower_color = texture(palette_texture, vec2((texel + 0.5) / 256.0, 0.5)).rgb;
				vec3 upper_color = texture(palette_texture, vec2((next_index + 0.5) / 256.0, 0.5)).rgb;
				float fraction = fract(lighting);
				shaded_color = mix(lower_color, upper_color, fraction);
				if (soft_shade) {
					vec2 coord = anchored_dither_coord();
					vec3 stepped_color = fraction > anchored_dither_threshold(coord) ? upper_color : lower_color;
					shaded_color = mix(shaded_color, stepped_color, anchored_dither_weight(coord));
				}
			}
		}
		ALBEDO = has_shade_table && (dither_mode == 3 || dither_mode == 4) ? shaded_color : texture(palette_texture, vec2((texel + 0.5) / 256.0, 0.5)).rgb;
		ROUGHNESS = 1.0;
	} else if (platform_style) {
		float lit = max(dot(normalize(pixel_source_normal), normalize(source_light_vector)), 0.0);
		float level = clamp(0.18 + platform_height * 0.56 + lit * 0.16, 0.0, 1.0);
		if (pixel_source_normal.y > 0.7) {
			level = 0.96;
		}
		if (dither_mode != 3 && dither_mode != 4) {
			float steps = level * 8.0;
			float threshold = 0.5;
			if (dither_mode == 2) {
				threshold = aperiodic_threshold(FRAGCOORD.xy);
			}
			level = (floor(steps) + (fract(steps) > threshold ? 1.0 : 0.0)) / 8.0;
		}
		ALBEDO = mix(vec3(0.42, 0.15, 0.015), vec3(0.98, 0.68, 0.075), level);
		ROUGHNESS = 1.0;
	} else if ((dither_mode == 3 || dither_mode == 4) && source_render_type >= 7.0) {
		float pixel_shade = max(dot(normalize(pixel_source_normal), source_light_vector), 0.0) * pixel_light_scale;
		float smooth_index = dither_mode == 3 ? mod(source_base_index + pixel_shade, 256.0) : mod(source_palette_index, 256.0);
		float lower_index = floor(smooth_index);
		float upper_index = mod(lower_index + 1.0, 256.0);
		vec3 lower_color = texture(palette_texture, vec2((lower_index + 0.5) / 256.0, 0.5)).rgb;
		vec3 upper_color = texture(palette_texture, vec2((upper_index + 0.5) / 256.0, 0.5)).rgb;
		float fraction = fract(smooth_index);
		ALBEDO = mix(lower_color, upper_color, fraction);
		if (dither_mode == 4) {
			vec2 coord = anchored_dither_coord();
			vec3 stepped_color = fraction > anchored_dither_threshold(coord) ? upper_color : lower_color;
			ALBEDO = mix(ALBEDO, stepped_color, anchored_dither_weight(coord));
		}
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
			float cell = dither_mode == 1 ? 1.0 : max(dither_pixel_scale, 1.0);
			float cell_x = floor(FRAGCOORD.x / cell);
			float local_x = mod(cell_x, 64.0);
			float row = floor(FRAGCOORD.y / cell);
			float block = floor(cell_x / 64.0);
			float phase = fract(row * 0.61803398875 + block * 0.41421356237);
			if (dither_mode == 2) {
				float lower = floor(source_palette_index);
				palette_index = lower + (fract(source_palette_index) > aperiodic_threshold(FRAGCOORD.xy) ? 1.0 : 0.0);
			} else {
			float shade = floor(source_palette_index * 256.0) / 256.0;
			float gradient = dFdx(source_palette_index) * cell;
			float first = shade - gradient * local_x;
			float prefix = (local_x + 1.0) * first + gradient * local_x * (local_x + 1.0) * 0.5;
			float previous = local_x * first + gradient * (local_x - 1.0) * local_x * 0.5;
			palette_index = floor(prefix + phase) - floor(previous + phase);
			}
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
