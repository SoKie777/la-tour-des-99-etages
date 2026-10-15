// Dessus d'arène : échiquier discret (Bible D.A. : symbolique des échecs), ombrage toon à aplats.
shader_type spatial;
render_mode diffuse_toon, specular_toon;

uniform vec4 base_color : source_color = vec4(0.2, 0.15, 0.13, 1.0);
uniform vec4 line_color : source_color = vec4(0.82, 0.68, 0.38, 1.0);
uniform float cells = 9.0;      // cases sur le diamètre
uniform float contrast = 0.1;  // écart de teinte entre cases claires et sombres
uniform float radius = 0.5;     // en UV : disque inscrit dans le plan

void fragment() {
	vec2 c = UV - 0.5;
	if (length(c) > radius) {
		discard;
	}
	vec2 g = UV * cells;
	float chk = mod(floor(g.x) + floor(g.y), 2.0);
	vec3 col = base_color.rgb * (1.0 + contrast * (chk * 2.0 - 1.0));
	// fins liserés d'or entre les cases, effacés vers le centre pour ne pas gêner la lecture
	vec2 f = abs(fract(g) - 0.5);
	float line = smoothstep(0.47, 0.5, max(f.x, f.y)) * smoothstep(0.12, 0.42, length(c));
	ALBEDO = mix(col, line_color.rgb, line * 0.14);
	ROUGHNESS = 0.8;
}
