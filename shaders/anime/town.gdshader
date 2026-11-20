shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float shade_threshold = 0.10;
uniform float rim_strength = 0.12;
uniform vec3 shadow_tint = vec3(0.26, 0.22, 0.40);

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * tint.rgb * 1.12;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	EMISSION = c * rim * rim_strength;
}

void light() {
	float nl = dot(NORMAL, LIGHT);
	float band = smoothstep(shade_threshold - 0.04, shade_threshold + 0.04, nl);
	float soft = clamp(nl * 0.5 + 0.5, 0.0, 1.0);
	float lit = mix(band, soft, 0.25) * ATTENUATION;
	DIFFUSE_LIGHT += LIGHT_COLOR * (lit + shadow_tint * (1.0 - lit) * 0.40);
}
