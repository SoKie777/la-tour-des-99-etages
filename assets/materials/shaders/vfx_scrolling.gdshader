// Traînée d'énergie à défilement d'UV (coups de lame, arcs de pouvoir) : UV.x suit l'arc, UV.y sa largeur.
// progress balaie l'arc de 0 à 1 + tail ; des stries défilent le long de la traînée.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.35, 1.0);
uniform float progress = 0.0;
uniform float tail = 0.55;
uniform float scroll = 3.0;
uniform float energy = 2.4;
uniform float streaks = 7.0;

float hash(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

void fragment() {
	float d = progress - UV.x;  // distance derrière la tête de la traînée
	float a = smoothstep(0.0, 0.05, d) * (1.0 - smoothstep(0.0, tail, d));
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	a *= smoothstep(0.0, 0.7, across);
	float row = floor(UV.y * streaks);
	float s = 0.55 + 0.45 * sin(UV.x * 22.0 - TIME * scroll * 8.0 + hash(row) * 6.2831);
	a *= mix(0.6, 1.0, s);
	vec3 core = mix(color.rgb, vec3(1.0), smoothstep(0.75, 1.0, across) * 0.6);  // cœur blanchi
	ALBEDO = core * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
