// Corps commun des shaders toon des personnages (Bible D.A., étape 2, et spécification v0.10) :
// - cel-shading à deux tons, ombres teintées de bleu minéral, ombres portées respectées ;
// - liseré (rim light) à la couleur de l'arène (arena_rim_color, réglé par le combat) ;
// - dégradé vertical sculpté : plus sombre vers les pieds, plus clair vers le haut du corps ;
// - reflet net en bande (cheveux, tissus soyeux), sans lissage réaliste.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_texture = true;
uniform bool use_vertex_color = false;  // vêtements MPFB peints en couleurs de sommets (sRGB)
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.0;  // sourcils, mèches : découpe nette
uniform vec4 shadow_color : source_color = vec4(0.149, 0.235, 0.290, 1.0);  // bleu minéral #263C4A
uniform float shadow_brightness : hint_range(0.0, 1.0) = 0.62;  // clarté de l'aplat d'ombre
uniform vec4 arena_rim_color : source_color = vec4(0.819, 0.678, 0.384, 1.0);  // or ancien #D1AD62 par défaut
uniform float rim_thickness : hint_range(0.0, 1.0) = 0.32;
uniform float rim_smoothness : hint_range(0.0, 1.0) = 0.05;
uniform float rim_strength : hint_range(0.0, 4.0) = 1.4;
uniform float figure_height = 1.75;  // hauteur du personnage (m), pour le dégradé vertical
uniform float gradient_low : hint_range(0.0, 1.0) = 0.72;  // clarté au niveau des pieds
uniform float gradient_high : hint_range(0.5, 1.5) = 1.06;  // clarté au sommet de la tête
uniform float band_strength : hint_range(0.0, 2.0) = 0.0;  // reflet en bande (0 : aucun)
uniform vec4 band_color : source_color = vec4(1.0, 0.96, 0.88, 1.0);
uniform sampler2D emission_texture : source_color, hint_default_black;
uniform float emission_energy : hint_range(0.0, 10.0) = 0.0;

varying float body_h;  // hauteur du point au-dessus des pieds, de 0 à 1

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	float wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y - MODEL_MATRIX[3].y;
	body_h = clamp(wy / max(figure_height, 0.01), 0.0, 1.0);
}

void fragment() {
	vec4 a = albedo_color;
	if (use_texture) {
		a *= texture(albedo_texture, UV);
	}
	if (use_vertex_color) {
		a.rgb *= srgb_to_linear(COLOR.rgb);
	}
	// relief sculpté : dégradé vertical en paliers doux (occlusion des jambes, lumière sur le buste)
	a.rgb *= mix(gradient_low, gradient_high, smoothstep(0.0, 1.0, body_h));
	ALBEDO = a.rgb;
	ALPHA = alpha_scissor > 0.0 ? a.a : 1.0;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	EMISSION = texture(emission_texture, UV).rgb * emission_energy;
	ROUGHNESS = 0.8;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(0.0, 0.05, ndl);
	if (LIGHT_IS_DIRECTIONAL) {
		float lit = band * smoothstep(0.25, 0.6, ATTENUATION);  // ombres portées en aplat
		vec3 tone = shadow_color.rgb / max(shadow_color.b, max(shadow_color.r, shadow_color.g)) * shadow_brightness;
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(tone, vec3(1.0), lit);
	} else {
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * band * ATTENUATION;
	}
	float rim = smoothstep(1.0 - rim_thickness, 1.0 - rim_thickness + rim_smoothness, 1.0 - dot(NORMAL, VIEW));
	SPECULAR_LIGHT += rim * max(ndl, 0.0) * arena_rim_color.rgb * LIGHT_COLOR / PI * ATTENUATION * rim_strength;
	if (band_strength > 0.0 && LIGHT_IS_DIRECTIONAL) {
		// reflet découpé : un anneau net autour du point le plus brillant (style « anneau d'ange » des cheveux)
		float ndh = dot(NORMAL, normalize(LIGHT + VIEW));
		float ring = smoothstep(0.80, 0.82, ndh) * (1.0 - smoothstep(0.90, 0.92, ndh));
		SPECULAR_LIGHT += ring * band_color.rgb * LIGHT_COLOR / PI * ATTENUATION * band_strength * smoothstep(0.0, 0.1, ndl);
	}
}
