shader_type spatial;
render_mode cull_disabled;

// Grass tufts (MultiMesh). No alpha-test: blades are real geometry, so the GPU keeps early-Z.
// Wind sway, player push, blades shrink into the ground at the edge of their range instead of popping.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float blade_h = 1.0;        // blade height in model units, used for the sway/AO ramp
uniform float sway = 1.0;
uniform float wind_dir_x = 0.8;
uniform float wind_dir_z = 0.6;
uniform float ao_min = 0.55;
uniform float sat = 1.06;
uniform vec3 tip_tint : source_color = vec3(0.95, 1.0, 0.70);
uniform float tip_amount = 0.10;
uniform vec3 player_pos = vec3(0.0, -1000.0, 0.0);
uniform float push_size = 1.25;
uniform float push_amount = 0.55;
// size envelope: mode 1 = shrinks away between a and b (near mesh), mode 2 = grows in between a and b (far mesh)
uniform int lod_mode = 0;
uniform float lod_a = 12.0;
uniform float lod_b = 18.0;
uniform float shade_threshold = 0.05;
uniform vec3 shadow_tint = vec3(0.24, 0.26, 0.42);

varying vec4 itint;
varying float h01;

void vertex() {
	itint = INSTANCE_CUSTOM;
	h01 = clamp(VERTEX.y / blade_h, 0.0, 1.0);
	vec3 centre_vs = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = length(centre_vs);
	float fe = abs(itint.a);
	float f = 1.0;
	if (fe > 1.0) {
		f *= 1.0 - smoothstep(fe * 0.70, fe, dist);
	}
	if (lod_mode == 1) {
		f *= 1.0 - smoothstep(lod_a, lod_b, dist);
	} else if (lod_mode == 2) {
		f *= smoothstep(lod_a, lod_b, dist);
	}
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float bend = h01 * h01;
	float t = TIME;
	float g = sin(t * 1.7 + wp.x * 0.42 * wind_dir_x + wp.z * 0.42 * wind_dir_z) * 0.6
		+ sin(t * 3.1 + wp.x * 1.3 + wp.z * 0.9) * 0.25 + 0.35;
	vec3 wind_ws = vec3(wind_dir_x, 0.0, wind_dir_z) * g * 0.16 * sway * bend;
	// player push (world space)
	vec2 dpl = wp.xz - player_pos.xz;
	float dl = length(dpl);
	float pf = (1.0 - smoothstep(0.0, push_size, dl)) * (1.0 - smoothstep(0.6, 2.2, abs(wp.y - player_pos.y)));
	vec3 push_ws = vec3(dpl.x, -0.45, dpl.y) / max(dl, 0.05) * pf * push_amount * bend;
	vec3 total_ws = wind_ws + push_ws;
	float s2 = max(dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz), 0.0001);
	VERTEX += (vec4(total_ws, 0.0) * MODEL_MATRIX).xyz / s2;
	VERTEX.y *= f;
	VERTEX.xz *= mix(0.35, 1.0, f);
	NORMAL = normalize(vec3(0.0, 1.0, 0.0) + NORMAL * 0.25);
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * tint.rgb;
	if (dot(itint.rgb, vec3(1.0)) > 0.01) {
		if (itint.a < 0.0) {
			float lum = dot(c, vec3(0.30, 0.59, 0.11));
			c = mix(c, itint.rgb * lum * 2.2, 0.8);
		} else {
			c *= itint.rgb;
		}
	}
	c = mix(c, c * tip_tint * 1.25, h01 * tip_amount);
	float l = dot(c, vec3(0.30, 0.59, 0.11));
	c = mix(vec3(l), c, sat);
	c *= mix(ao_min, 1.0, smoothstep(0.0, 0.7, h01));
	ALBEDO = c;
	ROUGHNESS = 1.0;
}

void light() {
	float nl = dot(NORMAL, LIGHT);
	float band = smoothstep(shade_threshold - 0.20, shade_threshold + 0.30, nl);
	float lit = band * ATTENUATION;
	DIFFUSE_LIGHT += LIGHT_COLOR * (lit * 0.9 + 0.1 + shadow_tint * (1.0 - lit) * 0.30);
}
