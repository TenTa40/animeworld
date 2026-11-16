shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.40, 1.0);
uniform float height = 60.0;

varying float ly;

void vertex() {
	ly = VERTEX.y;
}

void fragment() {
	float t = clamp((ly + 0.5 * height) / height, 0.0, 1.0);
	float f = pow(abs(dot(NORMAL, VIEW)), 1.4);
	float stripes = 0.65 + 0.35 * sin(TIME * 2.5 - ly * 0.5);
	ALBEDO = color.rgb;
	ALPHA = (1.0 - t) * f * stripes * 0.9;
}
