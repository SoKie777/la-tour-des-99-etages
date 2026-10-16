// Aura au sol du personnage qui va jouer : disque lumineux qui pulse doucement, anneaux qui s'élargissent.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.35, 1.0);
uniform float energy = 1.6;
uniform float strength = 1.0;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float pulse = 0.65 + 0.35 * sin(TIME * 3.2);
	float disc = (1.0 - smoothstep(0.2, 1.0, r)) * 0.45 * pulse;
	float ring = 0.0;
	for (int i = 0; i < 2; i++) {  // deux ondes qui partent du centre
		float t = fract(TIME * 0.6 + float(i) * 0.5);
		ring += (1.0 - smoothstep(0.0, 0.06, abs(r - t))) * (1.0 - t);
	}
	float a = (disc + ring * 0.8) * (1.0 - smoothstep(0.92, 1.0, r)) * strength;
	ALBEDO = color.rgb * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
