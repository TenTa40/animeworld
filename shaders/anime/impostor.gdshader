shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec3 light_tint = vec3(1.0, 1.0, 1.0);
uniform float fade_in_start = 40.0;
uniform float fade_in_end = 60.0;

// custom data: x = atlas cell (0..3), y = pink recolour flag, z = brightness
varying vec4 cd;

void vertex() {
	cd = INSTANCE_CUSTOM;
	vec3 centre = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 fwd = vec3(cam.x - centre.x, 0.0, cam.z - centre.z);
	fwd = fwd / max(length(fwd), 0.001);
	vec3 right = vec3(fwd.z, 0.0, -fwd.x);
	vec3 wpos = centre + right * VERTEX.x * sx + vec3(0.0, 1.0, 0.0) * VERTEX.y * sy;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wpos, 1.0);
}

void fragment() {
	float c = floor(cd.x + 0.5);
	vec2 cell = vec2(mod(c, 2.0), floor(c / 2.0));
	vec4 t = texture(atlas, (UV + cell) * 0.5);
	if (t.a < 0.45) {
		discard;
	}
	float dist = length(VERTEX);
	float f = smoothstep(fade_in_start, fade_in_end, dist);
	float n = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (f < n) {
		discard;
	}
	vec3 col = t.rgb;
	if (cd.y > 0.5) {
		float lum = dot(col, vec3(0.30, 0.59, 0.11));
		col = mix(col, vec3(1.0, 0.70, 0.84) * lum * 2.3, 0.85);
	}
	ALBEDO = col * cd.z * light_tint;
}
