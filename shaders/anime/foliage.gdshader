shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool use_alpha = false;
uniform float alpha_cut = 0.5;
uniform float sway = 0.0;
uniform float shade_threshold = 0.10;
uniform vec3 shadow_tint = vec3(0.18, 0.18, 0.34);

// per-instance data (MultiMesh custom data): rgb = tint, a = amount of luma-mapped recolour (0 = plain multiply)
varying vec4 itint;

void vertex() {
	itint = INSTANCE_CUSTOM;
	if (sway > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float k = sway * max(VERTEX.y, 0.0);
		VERTEX.x += sin(TIME * 1.6 + wp.x * 0.35 + wp.z * 0.25) * 0.045 * k;
		VERTEX.z += cos(TIME * 1.3 + wp.z * 0.30 + wp.x * 0.20) * 0.035 * k;
	}
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	if (use_alpha && t.a < alpha_cut) {
		discard;
	}
	vec3 base = t.rgb * tint.rgb;
	vec3 col = base;
	if (itint.a > 0.01) {
		float lum = dot(t.rgb, vec3(0.30, 0.59, 0.11));
		col = mix(base, itint.rgb * lum * 2.3, itint.a);
	} else if (dot(itint.rgb, vec3(1.0)) > 0.01) {
		col = base * itint.rgb;
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
}

void light() {
	float nl = dot(NORMAL, LIGHT);
	float band = smoothstep(shade_threshold - 0.05, shade_threshold + 0.05, nl);
	float lit = band * ATTENUATION;
	DIFFUSE_LIGHT += LIGHT_COLOR * (lit + shadow_tint * (1.0 - lit) * 0.35);
}
