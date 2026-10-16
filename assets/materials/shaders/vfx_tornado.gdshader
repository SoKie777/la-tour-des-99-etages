// Tornade / aura de zone : cylindre ouvert déformé en entonnoir, bandes en spirale qui montent en tournant.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.7, 0.45, 1.0, 1.0);
uniform float intensity = 1.0;  // 0 -> 1 -> 0 : apparition et disparition
uniform float spin = 3.0;
uniform float energy = 2.2;
uniform float funnel = 1.6;  // évasement du haut

void vertex() {
	float h = clamp(UV.y, 0.0, 1.0);
	float widen = mix(0.45, funnel, pow(1.0 - h, 1.4));  // UV.y = 0 en haut sur un CylinderMesh
	float twist = (1.0 - h) * 2.5 + TIME * spin;
	vec2 xz = VERTEX.xz * widen;
	float c = cos(twist * 0.15);
	float s = sin(twist * 0.15);
	VERTEX.xz = vec2(xz.x * c - xz.y * s, xz.x * s + xz.y * c);
}

void fragment() {
	float band = sin((UV.x * 3.0 + UV.y * 2.2 - TIME * spin * 0.5) * 6.2831);
	float a = smoothstep(0.1, 0.9, band * 0.5 + 0.5);
	a *= smoothstep(0.0, 0.15, UV.y) * smoothstep(1.0, 0.75, UV.y);  // bords haut et bas adoucis
	ALBEDO = mix(color.rgb, vec3(1.0), 0.2 * a) * energy;
	ALPHA = clamp(a * intensity * 0.85, 0.0, 1.0);
}
