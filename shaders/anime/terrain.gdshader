shader_type spatial;
render_mode cull_disabled;

uniform sampler2D grass_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D stone_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform float grass_scale = 0.16;
uniform float stone_scale = 0.2;
uniform float shade_threshold = 0.12;
uniform vec3 shadow_tint = vec3(0.16, 0.14, 0.30);

varying vec4 vc;
varying vec3 wpos;

void vertex() {
	vc = COLOR;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 g1 = texture(grass_tex, wpos.xz * grass_scale).rgb;
	vec3 g2 = texture(grass_tex, wpos.xz * grass_scale * 0.37 + vec2(0.37, 0.11)).rgb;
	float g = dot(mix(g1, g2, 0.4), vec3(0.3333));
	float s = dot(texture(stone_tex, wpos.xz * stone_scale).rgb, vec3(0.3333));
	float d = mix(s, g, vc.a);
	ALBEDO = vc.rgb * (0.45 + d * 1.1);
	ROUGHNESS = 1.0;
}

void light() {
	float nl = dot(NORMAL, LIGHT);
	float band = smoothstep(shade_threshold - 0.03, shade_threshold + 0.03, nl);
	float lit = band * ATTENUATION;
	DIFFUSE_LIGHT += LIGHT_COLOR * (lit + shadow_tint * (1.0 - lit) * 0.35);
}
