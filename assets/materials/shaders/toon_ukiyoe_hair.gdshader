// Cheveux et mèches (cartes double face) : même rendu que toon_ukiyoe, sans élimination des faces
// arrière, avec le reflet en bande des cheveux.
shader_type spatial;
render_mode depth_draw_opaque, cull_disabled;

#include "res://assets/materials/shaders/toon_ukiyoe.gdshaderinc"
