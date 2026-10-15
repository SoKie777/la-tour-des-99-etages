// Socle des unités (Bible D.A., étape 4) : sceau doré discret sous les pieds, anneaux, graduations
// et échiquier inscrit dans le cercle. Plaqué au sol, tourne lentement.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform vec4 color : source_color = vec4(0.82, 0.68, 0.38, 1.0);
uniform float strength = 0.55;
uniform float spin = 0.15;  // vitesse de rotation (radians par seconde)

void fragment() {
	vec2 p = UV - 0.5;
	float a = TIME * spin;
	p = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * p;
	float r = length(p);
	float aa = 0.006;
	float outer = smoothstep(0.47 + aa, 0.47, r) * smoothstep(0.445 - aa, 0.445, r);
	float inner = smoothstep(0.405 + aa, 0.405, r) * smoothstep(0.392 - aa, 0.392, r);
	// 16 graduations entre les deux anneaux
	float ang = atan(p.y, p.x) / 6.2831853 * 16.0;
	float ticks = step(abs(fract(ang) - 0.5), 0.08) * step(0.41, r) * step(r, 0.44);
	// échiquier inscrit (4 × 4 cases dans un carré posé en losange)
	vec2 q = mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071)) * p;
	vec2 cell = floor((q + 0.27) / 0.135);
	float inside = step(abs(q.x), 0.27) * step(abs(q.y), 0.27);
	float chk = mod(cell.x + cell.y, 2.0) * inside * 0.45;
	vec2 e = abs(q);
	float frame = inside * (1.0 - step(max(e.x, e.y), 0.255));
	float m = max(max(outer, inner), max(ticks, max(chk, frame)));
	ALBEDO = color.rgb * 1.3;
	ALPHA = m * strength * color.a;
}
