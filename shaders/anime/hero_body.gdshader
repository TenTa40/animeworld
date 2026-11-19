shader_type spatial;
render_mode cull_disabled;

// iko: static mesh with baked vertex colours. The legs, arms and cloth are moved by weights computed
// from the vertex position (no skeleton in the source model). Keep hero_pose() identical in hero_outline.gdshader.
uniform float bright = 1.35;
uniform float leg_l = 0.0;      // rotation about X like Node3D.rotation.x (negative = forward)
uniform float leg_r = 0.0;
uniform float arm_l = 0.0;
uniform float arm_r = 0.0;
uniform float roll_l = 0.08;    // arms swing outward (radians)
uniform float roll_r = 0.08;
uniform float flutter = 0.2;
uniform float rim_strength = 0.30;
uniform float shade_threshold = 0.12;
uniform vec3 shadow_tint = vec3(0.30, 0.26, 0.46);
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;

varying vec3 vcol;

vec3 rot_x(vec3 p, vec3 pivot, float a) {
	vec3 q = p - pivot;
	float c = cos(a);
	float s = sin(a);
	return vec3(q.x, q.y * c - q.z * s, q.y * s + q.z * c) + pivot;
}

vec3 rot_z(vec3 p, vec3 pivot, float a) {
	vec3 q = p - pivot;
	float c = cos(a);
	float s = sin(a);
	return vec3(q.x * c - q.y * s, q.x * s + q.y * c, q.z) + pivot;
}

vec3 hero_pose(vec3 p, float t) {
	float ax = abs(p.x);
	float side = p.x >= 0.0 ? 1.0 : -1.0;
	// cloth tails and hem stream behind when moving
	float wc = (1.0 - smoothstep(0.20, 0.88, p.y)) * smoothstep(0.13, 0.22, ax);
	float wave = sin(t * 5.0 + p.y * 7.0 + p.x * 9.0);
	p.z -= flutter * wc * (0.45 + 0.55 * wave) * 0.16;
	p.x += side * flutter * wc * wave * 0.03;
	// legs
	float sg = clamp(p.x / 0.04, -1.0, 1.0);
	float la = leg_l * (0.5 + 0.5 * sg) + leg_r * (0.5 - 0.5 * sg);
	float wl = 1.0 - smoothstep(0.80, 0.98, p.y);
	p = rot_x(p, vec3(0.0, 0.85, 0.0), la * wl);
	// arms
	float wa = smoothstep(0.115, 0.15, ax) * smoothstep(0.66, 0.76, p.y) * (1.0 - smoothstep(1.28, 1.36, p.y));
	float aa = side > 0.0 ? arm_l : arm_r;
	float rr = side > 0.0 ? roll_l : roll_r;
	vec3 sh = vec3(side * 0.11, 1.30, 0.0);
	p = rot_x(p, sh, aa * wa);
	p = rot_z(p, sh, side * rr * wa);
	return p;
}

void vertex() {
	vcol = COLOR.rgb;
	VERTEX = hero_pose(VERTEX, TIME);
}

void fragment() {
	vec3 c = pow(vcol, vec3(2.2)) * bright;
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
