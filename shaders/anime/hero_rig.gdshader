shader_type spatial;
render_mode cull_disabled;

// iko, skinned version: colours come from the vertex colours baked by tools/herogen.py (sRGB-encoded).
uniform float bright = 1.55;
uniform float lift = 0.045;
uniform float col_gamma = 2.2;
uniform float rim_strength = 0.30;
uniform float shade_threshold = 0.12;
uniform vec3 shadow_tint = vec3(0.34, 0.30, 0.50);
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;

varying vec3 vcol;

void vertex() {
	vcol = COLOR.rgb;
}

void fragment() {
	vec3 c = pow(max(vcol, vec3(0.0)), vec3(col_gamma)) * bright + vec3(lift);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	EMISSION = emission_color.rgb * emission_energy + c * rim * rim_strength;
}

void light() {
	float nl = dot(NORMAL, LIGHT);
	float band = smoothstep(shade_threshold - 0.03, shade_threshold + 0.03, nl);
	float lit = band * ATTENUATION;
	DIFFUSE_LIGHT += LIGHT_COLOR * (lit + shadow_tint * (1.0 - lit) * 0.35);
}
