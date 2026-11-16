shader_type spatial;
render_mode cull_back;

uniform sampler2D grass_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D stone_tex : source_color, repeat_enable, filter_linear_mipmap;
// R = road, G = rock (altitude), B = sand, A = forest darkness
uniform sampler2D splat_tex : filter_linear, repeat_disable;
uniform float half_size = 96.0;
uniform float grass_scale = 0.16;
uniform float stone_scale = 0.2;
uniform vec3 grass_tint = vec3(1.0, 1.0, 1.0);
uniform vec4 sand_color : source_color = vec4(0.93, 0.84, 0.58, 1.0);
uniform float shade_threshold = 0.12;
uniform vec3 shadow_tint = vec3(0.16, 0.14, 0.30);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 grass_at(vec2 p) {
	vec3 a = texture(grass_tex, p * grass_scale).rgb;
	vec3 b = texture(grass_tex, p * grass_scale * 0.37 + vec2(0.37, 0.11)).rgb;
	return mix(a, b, 0.4);
}

void fragment() {
	vec4 sp = texture(splat_tex, (wpos.xz + vec2(half_size)) / (2.0 * half_size));
	vec3 g = grass_at(wpos.xz) * grass_tint;
	vec3 s = texture(stone_tex, wpos.xz * stone_scale).rgb;
	float slope = 1.0 - smoothstep(0.62, 0.80, wnrm.y);
	float rock = clamp(max(slope, sp.g), 0.0, 1.0);
	vec3 col = mix(g, g * vec3(0.55, 0.78, 0.5), sp.a);
	col = mix(col, s * vec3(1.05, 0.97, 0.88), sp.r);
	col = mix(col, s * vec3(0.72, 0.76, 0.85), rock);
	col = mix(col, sand_color.rgb, sp.b);
	ALBEDO = col;
	ROUGHNESS = 1.0;
}

void light() {
	float nl = dot(NORMAL, LIGHT);
	float band = smoothstep(shade_threshold - 0.03, shade_threshold + 0.03, nl);
	float lit = band * ATTENUATION;
	DIFFUSE_LIGHT += LIGHT_COLOR * (lit + shadow_tint * (1.0 - lit) * 0.35);
}
