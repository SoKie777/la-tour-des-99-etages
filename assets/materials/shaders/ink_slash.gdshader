// Tranchant à l'encre (Bible D.A., étape 4) : croissant face caméra, traînée de pinceau sec qui balaie
// puis s'efface (défilement d'UV), cœur d'encre et bord de la couleur de l'attaquant. Sans texture.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform vec4 edge_color : source_color = vec4(1.0, 0.6, 0.3, 1.0);
uniform vec4 ink_color : source_color = vec4(0.2, 0.173, 0.161, 1.0);  // encre #332C29
uniform float progress = 0.0;  // 0 → 1 : le trait se pose puis s'efface
uniform float angle = 0.0;     // rotation du trait autour de l'axe de la caméra
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	float c = cos(angle);
	float s = sin(angle);
	VERTEX.xy = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xy;
	// face caméra (billboard)
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float head = progress * 1.7;
	float tail = (progress - 0.35) * 1.7;
	float sweep = smoothstep(head, head - 0.12, UV.x) * smoothstep(tail - 0.1, tail + 0.12, UV.x);
	// poils du pinceau : stries le long du trait qui défilent avec le geste
	float streak = noise(vec2(UV.x * 4.0 - progress * 6.0 + seed, UV.y * 26.0));
	streak = smoothstep(0.25, 0.65, streak + 0.25 * (1.0 - abs(UV.y - 0.5) * 2.0));
	float across = 1.0 - pow(abs(UV.y - 0.5) * 2.0, 2.0);
	float a = sweep * streak * across;
	float core = smoothstep(0.35, 0.8, across * streak);
	ALBEDO = mix(edge_color.rgb * 1.4, ink_color.rgb, core);
	ALPHA = clamp(a * 1.3, 0.0, 1.0);
}
