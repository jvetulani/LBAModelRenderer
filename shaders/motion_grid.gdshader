shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec2 travel = vec2(0.0);
uniform float radius = 3.5;
uniform float cell_size = 0.5;

void fragment() {
	vec2 local = (UV - vec2(0.5)) * 8.0;
	vec2 grid_coordinate = (local + travel) / cell_size;
	vec2 line_distance = abs(fract(grid_coordinate + vec2(0.5)) - vec2(0.5));
	float line_width = max(fwidth(grid_coordinate.x), fwidth(grid_coordinate.y)) * 0.8;
	float line = 1.0 - smoothstep(0.0, line_width, min(line_distance.x, line_distance.y));
	float fade = 1.0 - smoothstep(radius * 0.5, radius, length(local));
	ALBEDO = vec3(1.0, 0.68, 0.075);
	ALPHA = line * fade * 0.38;
}
