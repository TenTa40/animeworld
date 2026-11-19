shader_type spatial;
render_mode cull_front, unshaded;

// outline pass for the skinned iko (inverted hull)
uniform float thickness = 0.008;
uniform vec4 line_color : source_color = vec4(0.07, 0.04, 0.12, 1.0);

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = line_color.rgb;
}
