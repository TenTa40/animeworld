shader_type spatial;
render_mode cull_disabled;

uniform sampler2D grass_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D stone_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform float grass_scale = 0.16;
uniform float stone_scale = 0.2;
uniform float relief = 2.4;
uniform float shade_threshold = 0.12;
uniform vec3 shadow_tint = vec3(0.16, 0.14, 0.30);

varying vec4 vc;
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	vc = COLOR;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 g1 = texture(grass_tex, wpos.xz * grass_scale).rgb;
	vec3 g2 = texture(grass_tex, wpos.xz * grass_scale * 0.37 + vec2(0.37, 0.11)).rgb;
	float g = dot(mix(g1, g2, 0.4), vec3(0.3333));
	float s = dot(texture(stone_tex, wpos.xz * stone_scale).rgb, vec3(0.3333));
	float d = mix(s, g, vc.a);

	// low-frequency relief: bends the normal so far hills and cliffs get light and shade
	vec2 pm = wpos.xz * 0.012;
	float h0 = dot(texture(stone_tex, pm).rgb, vec3(0.3333));
	float hx = dot(texture(stone_tex, pm + vec2(0.07, 0.0)).rgb, vec3(0.3333));
	float hz = dot(texture(stone_tex, pm + vec2(0.0, 0.07)).rgb, vec3(0.3333));
	vec3 nw = normalize(wnrm + vec3(h0 - hx, 0.0, h0 - hz) * relief);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// rock strata on cliffs and mountain sides
	float steep = 1.0 - clamp(nw.y, 0.0, 1.0);
	float strata = 0.88 + 0.12 * sin(wpos.y * 1.3 + h0 * 6.0);
	float rocky = (1.0 - vc.a) * smoothstep(0.12, 0.45, steep);

	ALBEDO = vc.rgb * (0.45 + d * 1.1) * mix(1.0, strata, rocky);
	ROUGHNESS = 1.0;
}

void light() {
	float nl = dot(NORMAL, LIGHT);
	float band = smoothstep(shade_threshold - 0.03, shade_threshold + 0.03, nl);
	float hi = smoothstep(0.52, 0.58, nl) * 0.16;
	float lit = band * ATTENUATION;
	DIFFUSE_LIGHT += LIGHT_COLOR * (lit + hi * ATTENUATION + shadow_tint * (1.0 - lit) * 0.35);
}
