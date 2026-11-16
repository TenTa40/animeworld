shader_type spatial;
render_mode cull_front, unshaded;

uniform float thickness = 0.02;
uniform vec4 line_color : source_color = vec4(0.10, 0.05, 0.16, 1.0);

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = line_color.rgb;
}
