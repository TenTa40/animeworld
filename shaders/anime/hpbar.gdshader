shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float ratio = 1.0;
uniform vec4 fill_color : source_color = vec4(1.0, 0.40, 0.55, 1.0);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float f = step(UV.x, ratio);
	float edge = step(0.12, UV.y) * step(UV.y, 0.88) * step(0.012, UV.x) * step(UV.x, 0.988);
	vec3 c = mix(vec3(0.10, 0.05, 0.18), fill_color.rgb, f);
	ALBEDO = mix(vec3(0.02, 0.0, 0.06), c, edge);
	ALPHA = 0.95;
}
