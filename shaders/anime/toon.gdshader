shader_type spatial;
render_mode cull_back;

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_tex : source_color, filter_nearest;
uniform bool use_tex = false;
uniform bool use_vcol = false;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float shade_threshold = 0.12;
uniform float rim_strength = 0.35;
uniform vec3 shadow_tint = vec3(0.20, 0.16, 0.34);
uniform float spec_strength = 0.0;

varying vec3 vcolor;

void vertex() {
	vcolor = COLOR.rgb;
}

void fragment() {
	vec3 c = albedo_color.rgb;
	if (use_tex) {
		c *= texture(albedo_tex, UV).rgb;
	}
	if (use_vcol) {
		c *= vcolor;
	}
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
	if (spec_strength > 0.0) {
		vec3 h = normalize(LIGHT + VIEW);
		float sp = smoothstep(0.965, 0.975, dot(NORMAL, h));
		SPECULAR_LIGHT += LIGHT_COLOR * sp * spec_strength * lit;
	}
}
