shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

// vertex COLOR.r encodes water depth: depth = r * 8 - 2 (metres)
uniform vec4 shallow_color : source_color = vec4(0.38, 0.92, 0.88, 0.62);
uniform vec4 deep_color : source_color = vec4(0.10, 0.42, 0.80, 0.92);
uniform vec3 light_tint = vec3(1.0, 1.0, 1.0);

varying vec3 wp;
varying float dep;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	dep = COLOR.r * 8.0 - 2.0;
}

void fragment() {
	float depth = clamp(dep, 0.0, 6.0);
	float t = smoothstep(0.0, 3.2, depth);
	vec4 col = mix(shallow_color, deep_color, t);
	float wave = sin(wp.x * 0.7 + TIME * 0.8) * sin(wp.z * 0.6 + TIME * 0.6);
	col.rgb += vec3(0.05) * wave;
	float pulse = 0.5 + 0.5 * sin(TIME * 1.2 + (wp.x + wp.z) * 0.15);
	float foam1 = 1.0 - step(0.30 + 0.30 * pulse, depth);
	float foam2 = step(abs(depth - (1.05 + 0.25 * pulse)), 0.07);
	float foam = clamp(foam1 + foam2 * 0.7, 0.0, 1.0);
	float g = sin(wp.x * 1.7 + TIME * 1.3) * sin(wp.z * 1.5 - TIME * 1.1);
	float glint = step(0.93, g) * 0.5;
	vec3 rgb = mix(col.rgb, vec3(1.0), foam * 0.9) + vec3(glint);
	ALBEDO = rgb * light_tint;
	ALPHA = clamp(mix(col.a, 1.0, foam), 0.0, 1.0);
}
