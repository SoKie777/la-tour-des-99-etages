// Frame d'impact (Bible D.A., étape 4, facultatif) : l'écran passe un instant en noir et blanc très
// contrasté, comme une estampe à l'encre, sur le coup d'un ultime.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float threshold = 0.42;

void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	float bw = smoothstep(threshold - 0.06, threshold + 0.06, l);
	vec3 ink = mix(vec3(0.2, 0.173, 0.161), vec3(0.91, 0.87, 0.77), bw);  // encre et ivoire papier
	COLOR = vec4(mix(c, ink, amount), 1.0);
}
