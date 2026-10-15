// Personnages (Bible D.A., étape 2) : cel-shading à deux tons, ombres teintées de bleu minéral,
// liseré d'or (rim light) côté lumière. Version corrigée du shader de la Bible : l'albédo n'est pas
// appliqué deux fois, l'ombre ne s'additionne qu'une fois par lumière directionnelle et les ombres portées
// sont respectées.
shader_type spatial;
render_mode depth_draw_opaque, cull_back;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_texture = true;
uniform bool use_vertex_color = false;  // vêtements MPFB peints en couleurs de sommets (sRGB)
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.0;  // sourcils, mèches : découpe nette
uniform vec4 shadow_color : source_color = vec4(0.149, 0.235, 0.290, 1.0);  // bleu minéral #263C4A
uniform float shadow_brightness : hint_range(0.0, 1.0) = 0.62;  // clarté de l'aplat d'ombre (teinte bleu minéral)
uniform vec4 rim_color : source_color = vec4(0.819, 0.678, 0.384, 1.0);  // or ancien #D1AD62
uniform float rim_thickness : hint_range(0.0, 1.0) = 0.32;
uniform float rim_smoothness : hint_range(0.0, 1.0) = 0.05;
uniform float rim_strength : hint_range(0.0, 4.0) = 1.4;
uniform sampler2D emission_texture : source_color, hint_default_black;
uniform float emission_energy : hint_range(0.0, 10.0) = 0.0;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec4 a = albedo_color;
	if (use_texture) {
		a *= texture(albedo_texture, UV);
	}
	if (use_vertex_color) {
		a.rgb *= srgb_to_linear(COLOR.rgb);
	}
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
	SPECULAR_LIGHT += rim * max(ndl, 0.0) * rim_color.rgb * LIGHT_COLOR / PI * ATTENUATION * rim_strength;
}
