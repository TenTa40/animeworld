shader_type spatial;
render_mode cull_front, unshaded;

// outline pass for the skinned iko (inverted hull)
uniform float thickness = 0.005;
uniform vec4 line_color : source_color = vec4(0.07, 0.04, 0.12, 1.0);

uniform vec3 drag = vec3(0.0);
uniform float flutter = 0.6;

void vertex() {
	float fl = COLOR.a;
	float w = sin(TIME * 6.0 + VERTEX.y * 9.0 + VERTEX.x * 7.0);
	float w2 = cos(TIME * 4.3 + VERTEX.y * 6.0 - VERTEX.x * 5.0);
	VERTEX += drag * fl;
	VERTEX.z -= fl * flutter * 0.022 * (0.5 + 0.5 * w);
	VERTEX.x += fl * flutter * 0.016 * w2;
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = line_color.rgb;
}
