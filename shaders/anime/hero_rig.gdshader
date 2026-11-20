shader_type spatial;
render_mode cull_disabled;

// iko, skinned version: colours come from the vertex colours baked by tools/herogen.py (sRGB-encoded).
uniform float bright = 1.35;
uniform float lift = 0.045;
uniform float col_gamma = 2.2;
uniform float rim_strength = 0.30;
uniform float shade_threshold = 0.12;
uniform vec3 shadow_tint = vec3(0.46, 0.42, 0.56);
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;

uniform vec3 drag = vec3(0.0);       // model-space offset of loose cloth (set by hero_rig.gd, spring driven)
uniform float flutter = 0.6;

varying vec3 vcol;

void vertex() {
	vcol = COLOR.rgb;
	float fl = COLOR.a;
	float w = sin(TIME * 6.0 + VERTEX.y * 9.0 + VERTEX.x * 7.0);
	float w2 = cos(TIME * 4.3 + VERTEX.y * 6.0 - VERTEX.x * 5.0);
	VERTEX += drag * fl;
	VERTEX.z -= fl * flutter * 0.022 * (0.5 + 0.5 * w);
	VERTEX.x += fl * flutter * 0.016 * w2;
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
