shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D face_tex : source_color, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 d = normalize(lp);
	vec2 uv = vec2(0.5 + d.x * 0.65, 0.5 - d.y * 1.3);
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	vec4 t = texture(face_tex, uv);
	float front = smoothstep(0.30, 0.50, d.z);
	ALBEDO = t.rgb * tint.rgb;
	ALPHA = t.a * inside * front;
}
