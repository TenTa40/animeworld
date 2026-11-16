shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, fog_disabled;

uniform float night = 0.0;

void fragment() {
	vec3 d = normalize(VERTEX);
	vec3 g = d * 60.0;
	vec3 id = floor(g);
	vec3 f = fract(g) - 0.5;
	float h = fract(sin(dot(id, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float s = step(0.982, h) * smoothstep(0.38, 0.0, length(f));
	float tw = 0.65 + 0.35 * sin(TIME * 2.0 + h * 60.0);
	ALBEDO = vec3(1.0, 0.95, 0.85) * s * tw * 2.0;
	ALPHA = s * night * step(0.04, d.y);
}
