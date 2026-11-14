shader_type spatial;
render_mode blend_mix, cull_back;

uniform vec4 water_color : source_color = vec4(0.16, 0.62, 0.88, 0.78);
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float s = sin(wp.x * 0.7 + TIME * 0.8) * sin(wp.z * 0.6 + TIME * 0.6);
	ALBEDO = water_color.rgb + vec3(0.07) * s;
	ALPHA = water_color.a;
	ROUGHNESS = 0.2;
}
