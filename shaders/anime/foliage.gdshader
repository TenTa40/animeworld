shader_type spatial;
render_mode cull_disabled;

// Trees, bushes, flowers, ferns, rocks. Toon-lit, wind sway, cheap fake AO, distance dissolve.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool use_alpha = false;
uniform float alpha_cut = 0.5;
uniform float sway = 0.0;
uniform float ao_h = 0.0;          // height (model units) over which the base darkening fades out (0 = off)
uniform float ao_min = 0.70;
uniform float sat = 1.18;
uniform float shade_threshold = 0.10;
uniform vec3 shadow_tint = vec3(0.20, 0.20, 0.38);
// near/far model cross-fade: mode 1 = fades OUT between a and b, mode 2 = fades IN between a and b
uniform int lod_mode = 0;
uniform float lod_a = 30.0;
uniform float lod_b = 40.0;

// per-instance data (MultiMesh custom data):
//   rgb = tint (multiply) or recolour target, a = +fade_end (plain) or -fade_end (recolour)
varying vec4 itint;
varying float vy;

void vertex() {
	itint = INSTANCE_CUSTOM;
	vy = VERTEX.y;
	if (sway > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float k = sway * max(VERTEX.y, 0.0);
		float g = sin(TIME * 1.5 + wp.x * 0.31 + wp.z * 0.22) + 0.45 * sin(TIME * 2.9 + wp.x * 0.83 - wp.z * 0.61);
		float g2 = cos(TIME * 1.25 + wp.z * 0.29 + wp.x * 0.19);
		VERTEX.x += g * 0.036 * k;
		VERTEX.z += g2 * 0.028 * k;
	}
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	if (use_alpha && t.a < alpha_cut) {
		discard;
	}
	float dist = length(VERTEX);
	float f = 1.0;
	float fe = abs(itint.a);
	if (fe > 1.0) {
		f *= 1.0 - smoothstep(fe * 0.78, fe, dist);
	}
	if (lod_mode == 1) {
		f *= 1.0 - smoothstep(lod_a, lod_b, dist);
	} else if (lod_mode == 2) {
		f *= smoothstep(lod_a, lod_b, dist);
	}
	if (f < 0.999) {
		float n = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (f < n) {
			discard;
		}
	}
	vec3 base = t.rgb * tint.rgb;
	vec3 col = base;
	if (itint.a < 0.0) {
		float lum = dot(t.rgb, vec3(0.30, 0.59, 0.11));
		col = mix(base, itint.rgb * lum * 2.3, 0.85);
	} else if (dot(itint.rgb, vec3(1.0)) > 0.01) {
		col = base * itint.rgb;
	}
	float l = dot(col, vec3(0.30, 0.59, 0.11));
	col = mix(vec3(l), col, sat);
	if (ao_h > 0.0) {
		col *= mix(ao_min, 1.0, clamp(vy / ao_h, 0.0, 1.0));
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
