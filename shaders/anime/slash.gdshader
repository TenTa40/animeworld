shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform float progress = 0.0;
uniform vec4 color : source_color = vec4(1.0, 0.95, 0.80, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float head = mix(-2.3, 2.3, progress);
	float d = head - ang;
	float m = 0.0;
	if (d > 0.0 && d < 2.2) {
		m = 1.0 - d / 2.2;
	}
	float r_in = 0.55 + 0.30 * (1.0 - m);
	float ring = smoothstep(r_in, r_in + 0.12, r) * (1.0 - smoothstep(0.86, 0.98, r));
	float fade = 1.0 - smoothstep(0.65, 1.0, progress);
	ALBEDO = color.rgb * (0.6 + m);
	ALPHA = clamp(ring * m * fade * 1.4, 0.0, 1.0);
}
