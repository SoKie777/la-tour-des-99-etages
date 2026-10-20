class_name BattleDecor
extends RefCounted
## Décors de combat imaginés, façon estampe : couches de silhouettes en papier découpé (dégradé « bokashi »),
## ciel, brume, plateforme et ambiance propres à chaque lieu. Tout est procédural, sans texture : léger pour
## le mobile. Le décor se choisit dans les données : « decor » et « boss_decor » (data/tower.json),
## « decor » (data/loot_bosses.json).
##   dojo   : cour de temple au crépuscule, torii, cerisiers (combats d'essai)
##   acier  : Cité d'Acier, pagodes d'acier, cheminées, engrenage géant dans le ciel (étages 1 à 11)
##   forge  : sommet de Prométhée, éclipse, volcan, chaînes géantes, braseros (étage 12)
##   orion  : sanctuaire du Chronophage, nuit étoilée, horloges flottantes, sabliers
##   givre  : lac gelé du Wyrm, monts enneigés, côtes de dragon pris dans la glace, Grande Ourse
##   sirius : désert du Serpent solaire, dunes, pyramides, serpent géant, obélisques
##   gemmes : Forêt des Gemmes, arbres géants aux cristaux luminescents, lucioles (étages 13 à 24)
##   geode  : cœur de la Géode, parois d'améthyste, cristaux géants (étage 25, l'Impératrice Géode)

## Liseré des personnages (rim light) selon l'arène : magma orange, givre cyan, torii or chaud,
## acier indigo néon… (spécification visuelle v0.10).
const RIM := {"dojo": "d1ad62", "acier": "8a2be2", "forge": "ff5500", "givre": "00e5ff", "orion": "6fa8ff",
	"sirius": "b48aff", "gemmes": "d07aff", "geode": "ff6ad5"}


static func rim_color(id: String) -> Color:
	return Color(RIM.get(id, "d1ad62"))


const THEMES := {
	"dojo": {"sky": ["142342", "b8644a"], "ground": "2a1c22", "mist": "6a4450",
		"ambient": "a89ab0", "key": "fff1dc", "key_energy": 1.15, "rim": "8fa6e8"},
	"acier": {"sky": ["1d2b45", "d9824f"], "ground": "201c22", "mist": "7a5a5c",
		"ambient": "9aa0b4", "key": "ffe2c0", "key_energy": 1.15, "rim": "7fa0d8"},
	"forge": {"sky": ["1a0a0e", "c2381c"], "ground": "170d0c", "mist": "6a2016",
		"ambient": "b08070", "key": "ffc89a", "key_energy": 1.1, "rim": "ff6a3a"},
	"orion": {"sky": ["070b22", "3a3a78"], "ground": "0d1024", "mist": "2a2c5c",
		"ambient": "8a90c8", "key": "e8e4ff", "key_energy": 1.05, "rim": "e0b860"},
	"givre": {"sky": ["3a5f8f", "f0c6c0"], "ground": "a8bcd4", "mist": "c8d4e6",
		"ambient": "c0d0ec", "key": "fff4ea", "key_energy": 1.1, "rim": "9fd0ff"},
	"gemmes": {"sky": ["0e2a2e", "3fa38a"], "ground": "10221f", "mist": "2f6e62",
		"ambient": "9fd8c8", "key": "e8fff4", "key_energy": 1.05, "rim": "b07de0"},
	"geode": {"sky": ["160a26", "6a2a8a"], "ground": "1a0f26", "mist": "4a2a6a",
		"ambient": "b8a0e0", "key": "f4e8ff", "key_energy": 1.05, "rim": "e07de0"},
	"sirius": {"sky": ["2f5a96", "f2b24a"], "ground": "a8743e", "mist": "e8b070",
		"ambient": "f0d0a0", "key": "fff0c8", "key_energy": 1.2, "rim": "ffb060"},
}
const GOLD := Color("e0b860")
const SHADOW_BLUE := Color("263c4a")  # bleu minéral de la Bible D.A.
const CHECKER := preload("res://assets/materials/shaders/arena_checker.gdshader")

static var _paper_mats := {}
static var _dot_mat: StandardMaterial3D


static func ids() -> Array:
	return THEMES.keys()


static func build(parent: Node3D, id: String) -> void:
	if not THEMES.has(id):
		id = "dojo"
	var t: Dictionary = THEMES[id]
	_environment(parent, t)
	_ground(parent, Color(t["ground"]), Color(t["mist"]))
	match id:
		"acier":
			_acier(parent)
			_acier_rich(parent)
		"forge":
			_forge(parent)
			_forge_rich(parent)
		"orion":
			_orion(parent)
			_orion_rich(parent)
		"givre":
			_givre(parent)
			_givre_rich(parent)
		"sirius":
			_sirius(parent)
			_sirius_rich(parent)
		"gemmes":
			_gemmes(parent)
			_gemmes_rich(parent)
		"geode":
			_geode(parent)
			_geode_rich(parent)
		_:
			_dojo(parent)
			_dojo_rich(parent)


# --- Ciel, lumières, sol -------------------------------------------------------

static func _environment(parent: Node3D, t: Dictionary) -> void:
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	var horizon := Color(t["sky"][1])
	sm.sky_top_color = Color(t["sky"][0])
	sm.sky_horizon_color = horizon
	sm.sky_curve = 0.2
	sm.ground_horizon_color = Color(t["mist"])
	sm.ground_bottom_color = Color(t["ground"])
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(t["ambient"]).lerp(SHADOW_BLUE, 0.2)  # ombres teintées de bleu minéral
	e.ambient_light_energy = 0.4  # ombres plus marquées sous les pieds
	# réglages de la Bible D.A. : halo doux sur l'or et les runes, contraste et saturation relevés
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_strength = 1.0
	e.glow_bloom = 0.15
	e.glow_hdr_threshold = 1.0  # seuls les VFX et les néons brillent
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC  # noirs profonds, blancs non brûlés
	e.tonemap_exposure = 1.1
	e.tonemap_white = 1.0
	e.adjustment_enabled = true  # étalonnage : un peu plus sombre, noirs renforcés
	e.adjustment_brightness = 0.95
	e.adjustment_contrast = 1.25
	e.adjustment_saturation = 1.15
	# brume de profondeur : l'arène reste nette, le lointain se fond dans la brume (bokashi)
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = Color(t["mist"])
	e.fog_density = 1.0
	e.fog_depth_begin = 16.0
	e.fog_depth_end = 70.0
	e.fog_depth_curve = 1.4
	e.fog_sky_affect = 0.0
	var env := WorldEnvironment.new()
	env.environment = e
	parent.add_child(env)
	var key := DirectionalLight3D.new()  # lumière principale de face : on voit le visage des ennemis
	key.rotation_degrees = Vector3(-42, 160, 0)
	key.light_energy = float(t["key_energy"])
	key.light_color = Color(t["key"])
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS  # ombres fines près de l'arène
	key.directional_shadow_max_distance = 40.0
	key.shadow_blur = 0.6
	key.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY  # chaque décor peint son propre astre
	parent.add_child(key)
	var rim := DirectionalLight3D.new()  # contre-jour : détache les silhouettes
	rim.rotation_degrees = Vector3(-20, -20, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(t["rim"])
	rim.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	parent.add_child(rim)


## Flou léger du lointain (au-delà de l'arène).
static func camera_blur() -> CameraAttributesPractical:
	var a := CameraAttributesPractical.new()
	a.dof_blur_far_enabled = true
	a.dof_blur_far_distance = 25.0
	a.dof_blur_far_transition = 10.0
	a.dof_blur_amount = 0.05
	return a


## Sol : couleur du lieu au pied de l'arène, qui se fond dans la brume vers l'horizon (bokashi).
static func _ground(parent: Node3D, near: Color, mist: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zs := [40.0, -10.0, -18.0, -28.0, -40.0, -55.0, -75.0, -130.0]
	for i in zs.size() - 1:
		var za: float = zs[i]
		var zb: float = zs[i + 1]
		var ca := near.lerp(mist, smoothstep(-12.0, -62.0, za))
		var cb := near.lerp(mist, smoothstep(-12.0, -62.0, zb))
		for v: Array in [[-170.0, za, ca], [170.0, za, ca], [170.0, zb, cb], [-170.0, za, ca], [170.0, zb, cb], [-170.0, zb, cb]]:
			st.set_color(v[2])
			st.add_vertex(Vector3(v[0], -0.42, v[1]))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _paper(false)
	parent.add_child(mi)


static func _platform(parent: Node3D, c: Color, line := Color("d1ad62")) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 7.0
	cyl.bottom_radius = 7.4
	cyl.height = 0.4
	cyl.radial_segments = 64
	_mesh(parent, cyl, _toon(c, 0.0, 0.12), Vector3(0, -0.2, 0))
	var top := PlaneMesh.new()  # échiquier discret gravé dans l'arène (Bible D.A.)
	top.size = Vector2(13.6, 13.6)
	var m := ShaderMaterial.new()
	m.shader = CHECKER
	m.set_shader_parameter("base_color", c)
	m.set_shader_parameter("line_color", line)
	_mesh(parent, top, m, Vector3(0, 0.004, 0))


# --- Briques : papier découpé ---------------------------------------------------

static func _paper(alpha: bool) -> StandardMaterial3D:
	if not _paper_mats.has(alpha):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_fog = true  # couleurs posées à la main, comme des aplats d'estampe
		if alpha:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_paper_mats[alpha] = m
	return _paper_mats[alpha]


## Silhouettes plates (plan XY, profondeur z) réunies en un seul maillage, dégradé vertical de 'bottom'
## à 'top' entre les hauteurs y_range.x et y_range.y (par défaut : la hauteur des contours).
static func _layer(parent: Node3D, polys: Array, top: Color, bottom: Color, z: float,
		y_range := Vector2.ZERO) -> MeshInstance3D:
	if y_range == Vector2.ZERO:
		y_range = Vector2(INF, -INF)
		for pts: PackedVector2Array in polys:
			for q in pts:
				y_range = Vector2(minf(y_range.x, q.y), maxf(y_range.y, q.y))
	if y_range.y - y_range.x < 0.01:
		y_range.y = y_range.x + 1.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for pts: PackedVector2Array in polys:
		for i in Geometry2D.triangulate_polygon(pts):
			var q := pts[i]
			st.set_color(bottom.lerp(top, clampf(inverse_lerp(y_range.x, y_range.y, q.y), 0.0, 1.0)))
			st.add_vertex(Vector3(q.x, q.y, z))
			n += 1
	if n == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _paper(top.a < 1.0 or bottom.a < 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Ligne de crêtes de x0 à x1 (montagnes, dunes), fermée sous le sol : base + amp × bruit lissé.
static func _ridge(x0: float, x1: float, base: float, amp: float, seed_: int, step := 1.5, jag := 0.35) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var pts := PackedVector2Array()
	var x := x0
	while x < x1 + step * 0.5:
		var nz := 0.55 * sin(x * 0.07 + ph[0]) + 0.3 * sin(x * 0.16 + ph[1]) + 0.15 * sin(x * 0.41 + ph[2])
		pts.append(Vector2(minf(x, x1), base + amp * (0.5 + 0.5 * nz) + rng.randf_range(-jag, jag)))
		x += step
	pts.append(Vector2(x1, -2.0))
	pts.append(Vector2(x0, -2.0))
	return pts


## Mont isolé aux flancs concaves (à la Hokusai). cap > 0 : seulement la calotte de neige (part de la
## hauteur), au bord dentelé. flat > 0 : sommet tronqué (cratère).
static func _peak(cx: float, base: float, w: float, h: float, cap := 0.0, flat := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 32
	var top := h * (1.0 - flat)
	if cap <= 0.0:
		for i in n + 1:
			var u := -1.0 + 2.0 * i / n
			pts.append(Vector2(cx + u * w, base + minf(h * pow(1.0 - absf(u), 1.7), top)))
		pts.append(Vector2(cx + w, -2.0))
		pts.append(Vector2(cx - w, -2.0))
		return pts
	var uc := 1.0 - pow(1.0 - cap, 1.0 / 1.7)
	for i in n + 1:
		var u := -uc + 2.0 * uc * i / n
		pts.append(Vector2(cx + u * w, base + minf(h * pow(1.0 - absf(u), 1.7), top)))
	var yc := base + h * (1.0 - cap)
	for i in range(9, 0, -1):  # bord dentelé de la neige, de droite à gauche
		var u := -uc + 2.0 * uc * (i - 0.5) / 9.0
		pts.append(Vector2(cx + u * w, yc - (h * 0.06 if i % 2 == 0 else -h * 0.02)))
	return pts


static func _circle(c: Vector2, r: float, n := 32) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


## Étoile à n branches (rayons de soleil, scintillement, dents pointues).
static func _star(n: int, r_out: float, r_in: float, c := Vector2.ZERO) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n * 2:
		var a := PI * i / n + PI / 2.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r_out if i % 2 == 0 else r_in))
	return pts


static func _gear(teeth: int, r_out: float, r_in: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in teeth * 4:
		var a := TAU * i / (teeth * 4)
		pts.append(Vector2(cos(a), sin(a)) * (r_out if i % 4 in [1, 2] else r_in))
	return pts


static func _rect(c: Vector2, size: Vector2, angle := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		pts.append(c + (k * size * 0.5).rotated(angle))
	return pts


## Bande épaisse le long d'une ligne (câble, coulée de lave, corps de serpent) ; 'halves' : demi-épaisseurs.
static func _strip(line: PackedVector2Array, halves: PackedFloat32Array) -> PackedVector2Array:
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	for i in line.size():
		var d := line[mini(i + 1, line.size() - 1)] - line[maxi(i - 1, 0)]
		var nrm := Vector2(-d.y, d.x).normalized()
		a.append(line[i] + nrm * halves[i])
		b.append(line[i] - nrm * halves[i])
	b.reverse()
	a.append_array(b)
	return a


## Nuage kumo d'estampe : bande à fond plat, dessus festonné.
static func _cloud(cx: float, cy: float, w: float, h: float) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(cx - w * 0.5, cy), Vector2(cx + w * 0.5, cy)])
	var n := maxi(2, int(w / (h * 1.6)))
	var rb := w / (2.0 * n)
	for j in n:
		var xj := cx + w * 0.5 - rb * (2 * j + 1)
		for k in 9:
			var a := PI * k / 8.0
			if j > 0 and k == 0:
				continue
			pts.append(Vector2(xj + rb * cos(a), cy + h * 0.45 + h * 0.55 * sin(a)))
	return pts


## Tour à étages (pagode d'acier) : avant-toits relevés à chaque étage, flèche au sommet.
static func _pagoda(cx: float, y0: float, w: float, tiers: int, th: float) -> PackedVector2Array:
	var left := PackedVector2Array([Vector2(cx - w * 0.5, y0)])
	var y := y0
	var hw := w * 0.5
	for k in tiers:
		var top := y + th
		var ext := th * 0.5
		left.append(Vector2(cx - hw, top - th * 0.3))
		left.append(Vector2(cx - hw - ext, top - th * 0.42))  # pointe de l'avant-toit
		left.append(Vector2(cx - hw - ext * 1.2, top - th * 0.2))  # relevée
		hw *= 0.78
		left.append(Vector2(cx - hw, top))
		y = top
	left.append(Vector2(cx - 0.12, y + th * 0.25))
	return _mirror(left, Vector2(cx, y + th * 1.6), cx)


## Sapin en trois étages.
static func _pine(cx: float, y0: float, h: float, w: float) -> PackedVector2Array:
	var left := PackedVector2Array([
		Vector2(cx - 0.06 * w, y0), Vector2(cx - 0.06 * w, y0 + 0.12 * h), Vector2(cx - 0.5 * w, y0 + 0.12 * h),
		Vector2(cx - 0.16 * w, y0 + 0.45 * h), Vector2(cx - 0.38 * w, y0 + 0.42 * h),
		Vector2(cx - 0.11 * w, y0 + 0.72 * h), Vector2(cx - 0.25 * w, y0 + 0.7 * h)])
	return _mirror(left, Vector2(cx, y0 + h), cx)


## Contour symétrique : côté gauche (de bas en haut), sommet, puis côté droit en miroir.
static func _mirror(left: PackedVector2Array, apex: Vector2, cx: float) -> PackedVector2Array:
	var pts := left.duplicate()
	pts.append(apex)
	for i in range(left.size() - 1, -1, -1):
		pts.append(Vector2(2.0 * cx - left[i].x, left[i].y))
	return pts


## Île flottante : dessus presque plat, dessous en pointe rocheuse.
static func _island(w: float, depth: float, seed_: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var pts := PackedVector2Array()
	for i in 9:  # dessous, de gauche à droite
		var u := -1.0 + 2.0 * i / 8.0
		pts.append(Vector2(u * w, -depth * pow(1.0 - absf(u), 0.8) * rng.randf_range(0.75, 1.0)))
	for i in range(8, -1, -1):  # dessus
		var u := -1.0 + 2.0 * i / 8.0
		pts.append(Vector2(u * w * 1.02, rng.randf_range(0.0, 0.35)))
	return pts


# --- Briques : volumes et ambiance ---------------------------------------------------

static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


static func _toon(c: Color, emission := 0.0, rim := 0.35) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.roughness = 0.75
	m.rim_enabled = rim > 0.0
	m.rim = rim
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func _cyl(top: float, bottom: float, h: float, seg := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return s


## Petits points lumineux doux (étoiles, fenêtres) : couleur par instance.
static func _dots() -> StandardMaterial3D:
	if _dot_mat == null:
		_dot_mat = StandardMaterial3D.new()
		_dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dot_mat.albedo_texture = BattleFx.disc_texture()
		_dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dot_mat.vertex_color_use_as_albedo = true
		_dot_mat.vertex_color_is_srgb = true
		_dot_mat.disable_fog = true
	return _dot_mat


static func _multi(parent: Node3D, mesh: Mesh, mat: Material, xforms: Array[Transform3D],
		colors: Array[Color] = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


## Segment plat posé au sol (fissure, rayon gravé) de a à b, en coordonnées XZ.
static func _seg_xform(a: Vector2, b: Vector2, y: float, width: float) -> Transform3D:
	var d := b - a
	var basis := Basis(Vector3.UP, atan2(-d.y, d.x)) * Basis.from_scale(Vector3(d.length(), 1.0, width))
	return Transform3D(basis, Vector3((a.x + b.x) * 0.5, y, (a.y + b.y) * 0.5))


## Disque de lumière douce (halo d'astre, lueur de cratère).
static func _soft(parent: Node3D, c: Color, size: float, pos: Vector3) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	_mesh(parent, q, BattleFx.flat_material(c), pos)


static func _spin(n: Node3D, period: float, prop := "rotation:z") -> void:
	var tw := n.create_tween().set_loops()
	tw.tween_property(n, prop, TAU * signf(period), absf(period)).as_relative()


static func _bob(n: Node3D, amp: float, period: float) -> void:
	var tw := n.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(n, "position:y", amp, period * 0.5).as_relative()
	tw.tween_property(n, "position:y", -amp, period * 0.5).as_relative()


## Particules d'ambiance (braises, neige, sable, fumée...) qui apparaissent et s'effacent en douceur.
static func _ambient(parent: Node3D, c: Color, amount: int, life: float, pos: Vector3, extents: Vector3,
		vel: Vector3, size: float, grow := 1.0, spread := 25.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.position = pos
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = vel.normalized() if vel != Vector3.ZERO else Vector3.UP
	p.spread = spread
	p.initial_velocity_min = vel.length() * 0.6
	p.initial_velocity_max = vel.length()
	p.gravity = Vector3.ZERO
	p.angle_max = 360.0
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	p.mesh = q
	p.material_override = BattleFx.flat_material(Color.WHITE, true)
	p.color = c
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.2, Color.WHITE)
	g.add_point(0.7, Color.WHITE)
	p.color_ramp = g
	if grow != 1.0:
		var curve := Curve.new()
		curve.max_value = maxf(grow, 1.0)
		curve.add_point(Vector2(0, 1.0))
		curve.add_point(Vector2(1, grow))
		p.scale_amount_curve = curve
	parent.add_child(p)
	return p


static func _light(parent: Node3D, c: Color, pos: Vector3, energy := 1.2, reach := 6.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = reach
	l.position = pos
	parent.add_child(l)


## Constellation : étoiles brillantes reliées par de fins traits.
static func _constellation(parent: Node3D, stars: Array[Vector2], links: Array[Vector2i], c: Color, z: float) -> void:
	var lines: Array = []
	for l in links:
		lines.append(_strip(PackedVector2Array([stars[l.x], stars[l.y]]), PackedFloat32Array([0.07, 0.07])))
	_layer(parent, lines, Color(c, 0.4), Color(c, 0.4), z)
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	for s in stars:
		xf.append(Transform3D(Basis.from_scale(Vector3.ONE * 1.6), Vector3(s.x, s.y, z + 0.1)))
		cols.append(Color(c, 1.0).lightened(0.4))
	_multi(parent, QuadMesh.new(), _dots(), xf, cols)


static func _starfield(parent: Node3D, n: int, seed_: int, y_min: float, tint: Array[Color]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	for i in n:
		var s := rng.randf_range(0.15, 0.55)
		xf.append(Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(rng.randf_range(-120, 120), rng.randf_range(y_min, 34), -96)))
		cols.append(Color(tint[rng.randi() % tint.size()], rng.randf_range(0.4, 1.0)))
	_multi(parent, QuadMesh.new(), _dots(), xf, cols)


# --- Décors -----------------------------------------------------------------------

## Cour de temple au crépuscule : soleil rouge, mont enneigé, torii, cerisiers, lanternes de pierre.
static func _dojo(p: Node3D) -> void:
	_layer(p, [_circle(Vector2(9, 6.2), 3.4, 40)], Color("d0342a"), Color("c4281f"), -76)
	for k in 2:
		for j in 3:
			_layer(p, [_cloud(-34 + j * 30.0 + k * 14.0, 4.2 + k * 2.6 + (j % 2) * 0.6, 14.0 - j * 2.0, 0.9)],
				Color("f4ead6", 0.9 - k * 0.25), Color("e0cdb0", 0.8 - k * 0.25), -74 + k)
	_layer(p, [_peak(-24, -0.5, 26, 11)], Color("5a4a6a"), Color("9a6a70"), -70)
	_layer(p, [_peak(-24, -0.5, 26, 11, 0.3)], Color("fbf4f4"), Color("dccbd8"), -69.9)
	_layer(p, [_ridge(-120, 120, 0.0, 3.6, 3)], Color("3e2c40"), Color("6a4450"), -55)
	_layer(p, [_ridge(-120, 120, -0.5, 3.0, 7, 1.0, 0.15)], Color("21171f"), Color("33222c"), -32)
	_platform(p, Color("2e211c"))
	for r: float in [5.6, 6.6]:
		var ring := BattleFx.flat_ring(Color("c9a24a"), r, 0.05 if r < 6 else 0.03, 1.2)
		ring.position.y = 0.01
		p.add_child(ring)
	_torii(p, Vector3(0, 0, -15), 0.8)
	_sakura(p, Vector3(-13, 0, -11), 0.9)
	_sakura(p, Vector3(13.5, 0, -14), 1.0)
	for pos: Vector3 in [Vector3(-9.2, 0, -3.5), Vector3(9.2, 0, -3.5), Vector3(-5.5, 0, -9.5), Vector3(5.5, 0, -9.5)]:
		_toro(p, pos)
	_ambient(p, BattleFx.SAKURA, 50, 8.0, Vector3(0, 3, -4.5), Vector3(9, 3, 3.5), Vector3(0.45, -0.15, 0), 0.08)


static func _torii(p: Node3D, at: Vector3, s: float) -> void:
	var red := _toon(Color("b8322a"))
	var ink := _toon(Color("1c1618"))
	for x in [-3.4, 3.4]:
		_mesh(p, _cyl(0.26 * s, 0.32 * s, 7.0 * s), red, at + Vector3(x * s, 3.5 * s, 0))
		_mesh(p, _cyl(0.4 * s, 0.4 * s, 0.5 * s), ink, at + Vector3(x * s, 0.25 * s, 0))
	_mesh(p, _box(Vector3(8.4, 0.32, 0.3) * s), red, at + Vector3(0, 5.2 * s, 0))  # nuki
	_mesh(p, _box(Vector3(9.0, 0.36, 0.42) * s), red, at + Vector3(0, 6.35 * s, 0))  # shimaki
	_mesh(p, _box(Vector3(9.4, 0.4, 0.55) * s), ink, at + Vector3(0, 6.75 * s, 0))  # kasagi
	for side: float in [-1.0, 1.0]:  # extrémités relevées
		_mesh(p, _box(Vector3(1.6, 0.4, 0.55) * s), ink, at + Vector3(side * 5.2 * s, 6.95 * s, 0), Vector3(0, 0, side * 14.0))
	_mesh(p, _box(Vector3(0.3, 1.2, 0.25) * s), red, at + Vector3(0, 5.8 * s, 0))  # gakuzuka


static func _sakura(p: Node3D, at: Vector3, s: float) -> void:
	var bark := _toon(Color("2a1a1c"))
	_mesh(p, _cyl(0.2 * s, 0.38 * s, 4.2 * s, 8), bark, at + Vector3(0.3 * s, 2.0 * s, 0), Vector3(0, 0, -10))
	_mesh(p, _cyl(0.1 * s, 0.18 * s, 2.4 * s, 6), bark, at + Vector3(-0.6 * s, 3.6 * s, 0), Vector3(0, 0, 35))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(at.x * 10.0)
	var pinks := [Color("f6b8c8"), Color("f29ab4"), Color("fbd3dc")]
	for i in 9:
		var off := Vector3(rng.randf_range(-2.2, 2.2), rng.randf_range(3.8, 5.6), rng.randf_range(-1.2, 1.2)) * s
		_mesh(p, _sphere(rng.randf_range(0.9, 1.5) * s), _toon(pinks[i % 3], 0.15, 0.4), at + off)
	_ambient(p, BattleFx.SAKURA, 14, 6.0, at + Vector3(0, 4.5, 0) * s, Vector3(2.4, 0.8, 1.2) * s, Vector3(0.4, -0.6, 0), 0.09)


## Lanterne de pierre (tōrō) allumée.
static func _toro(p: Node3D, at: Vector3) -> void:
	var stone := _toon(Color("6a6470"))
	_mesh(p, _cyl(0.5, 0.6, 0.3, 6), stone, at + Vector3(0, 0.15, 0))
	_mesh(p, _cyl(0.17, 0.22, 1.2, 8), stone, at + Vector3(0, 0.9, 0))
	_mesh(p, _box(Vector3(0.75, 0.12, 0.75)), stone, at + Vector3(0, 1.55, 0))
	_mesh(p, _box(Vector3(0.5, 0.5, 0.5)), _toon(Color("ffcf80"), 2.2, 0.0), at + Vector3(0, 1.86, 0))
	_mesh(p, _cyl(0.08, 0.8, 0.45, 6), stone, at + Vector3(0, 2.32, 0))
	_mesh(p, _sphere(0.13), stone, at + Vector3(0, 2.62, 0))
	_light(p, Color("ffb35c"), at + Vector3(0, 1.9, 0.4), 1.0, 5.0)


## Cité d'Acier au crépuscule : pagodes d'acier, cheminées fumantes, câbles, engrenage géant dans le ciel.
static func _acier(p: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	_soft(p, Color("ff7a4a", 0.5), 22, Vector3(-16, 6.5, -88))
	_layer(p, [_circle(Vector2(-16, 6.5), 4.4, 40)], Color("d8402a"), Color("c4281f"), -86)
	var gear := _pivot(p, Vector3(22, 8.5, -84))
	_layer(gear, [_gear(20, 7.6, 6.8)], Color("6a4a5a"), Color("8a5a5e"), 0.0)
	var holes: Array = [_circle(Vector2.ZERO, 2.0, 24)]
	for i in 6:
		holes.append(_circle(Vector2.from_angle(TAU * i / 6.0) * 4.6, 1.05, 16))
	_layer(gear, holes, Color("46324a"), Color("553a50"), 0.05)
	_spin(gear, -140.0)
	# horizon : silhouettes de pagodes d'acier
	var far: Array = []
	var x := -120.0
	while x < 120.0:
		var w := rng.randf_range(2.4, 4.4)
		far.append(_pagoda(x, -0.5, w, rng.randi_range(2, 5), rng.randf_range(1.5, 2.1)))
		x += w + rng.randf_range(1.0, 5.0)
	_layer(p, far, Color("6e5868"), Color("a07a74"), -66, Vector2(0, 11))
	# plan moyen : tours, cheminées fumantes, fenêtres allumées, câbles
	var mid: Array = []
	var tops: Array[Vector2] = []
	var win_xf: Array[Transform3D] = []
	var win_col: Array[Color] = []
	x = -100.0
	while x < 100.0:
		var w := rng.randf_range(3.0, 5.0)
		var tiers := rng.randi_range(2, 4)
		var th := rng.randf_range(1.8, 2.5)
		mid.append(_pagoda(x, -0.5, w, tiers, th))
		tops.append(Vector2(x, tiers * th * 0.9))
		for k in rng.randi_range(4, 10):
			var lvl := rng.randi_range(0, tiers - 1)
			var hw := w * 0.5 * pow(0.78, lvl) * 0.7
			win_xf.append(Transform3D(Basis.from_scale(Vector3(0.3, 0.45, 1)),
				Vector3(x + rng.randf_range(-hw, hw), lvl * th + th * 0.4, -45.8)))
			win_col.append(Color("ffc46a") if rng.randf() < 0.7 else Color("ff8a4a"))
		if rng.randf() < 0.45:  # cheminée d'usine
			var cx := x + w * 0.5 + 1.2
			var ch := rng.randf_range(6.0, 8.5)
			mid.append(_rect(Vector2(cx, ch * 0.5 - 0.5), Vector2(1.1, ch)))
			mid.append(_rect(Vector2(cx, ch - 0.9), Vector2(1.5, 0.5)))
			if absf(cx) < 70.0:
				_ambient(p, Color("2c242c", 0.85), 9, 8.0, Vector3(cx, ch, -46.2), Vector3(0.4, 0.2, 0.1),
					Vector3(0.8, 1.0, 0), 1.7, 3.0, 8.0)
		x += w + rng.randf_range(2.5, 7.0)
	var cables: Array = []
	for i in tops.size() - 1:
		var a := tops[i]
		var b := tops[i + 1]
		var line := PackedVector2Array()
		var halves := PackedFloat32Array()
		for k in 11:
			var t := k / 10.0
			line.append(a.lerp(b, t) - Vector2(0, sin(t * PI) * 0.9))
			halves.append(0.07)
		cables.append(_strip(line, halves))
	_layer(p, cables, Color("3a2e38"), Color("3a2e38"), -46.1)
	_layer(p, mid, Color("3a2e38"), Color("6a4e54"), -46, Vector2(0, 9))
	_multi(p, QuadMesh.new(), _dots(), win_xf, win_col)
	# premier plan : toits bas de la ville
	var roof := PackedVector2Array()
	x = -110.0
	while x < 110.0:
		var w := rng.randf_range(4.0, 8.0)
		var h := rng.randf_range(0.6, 2.4)
		roof.append(Vector2(x, h))
		roof.append(Vector2(x + w * 0.5, h + rng.randf_range(0.8, 1.6)))
		roof.append(Vector2(x + w, h))
		x += w
	roof.append(Vector2(x, -2.0))
	roof.append(Vector2(-110.0, -2.0))
	_layer(p, [roof], Color("231c24"), Color("2e252e"), -30)
	# arène d'acier riveté, bordée de dents d'engrenage
	_platform(p, Color("3b3f48"))
	for r: float in [5.6, 6.95]:
		var ring := BattleFx.flat_ring(Color("c9783a") if r > 6.0 else Color("c9a24a"), r, 0.06 if r > 6.0 else 0.04, 1.3)
		ring.position.y = 0.01
		p.add_child(ring)
	var teeth: Array[Transform3D] = []
	var rivets: Array[Transform3D] = []
	for i in 40:
		var a := TAU * i / 40.0
		teeth.append(Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * 7.35, -0.12, sin(a) * 7.35)))
	for i in 48:
		var a := TAU * (i + 0.5) / 48.0
		rivets.append(Transform3D(Basis(), Vector3(cos(a) * 6.45, 0.0, sin(a) * 6.45)))
	_multi(p, _box(Vector3(0.6, 0.3, 0.45)), _toon(Color("2c3038")), teeth)
	_multi(p, _sphere(0.07), _toon(Color("8a8f99")), rivets)
	# réverbères de fer et bouches de vapeur
	for pos: Vector3 in [Vector3(-8.6, 0, -4.5), Vector3(8.6, 0, -4.5), Vector3(-6.5, 0, -10), Vector3(6.5, 0, -10)]:
		_mesh(p, _cyl(0.08, 0.12, 3.4, 8), _toon(Color("26282e")), pos + Vector3(0, 1.7, 0))
		_mesh(p, _box(Vector3(0.45, 0.6, 0.45)), _toon(Color("ffc46a"), 2.4, 0.0), pos + Vector3(0, 3.55, 0))
		_mesh(p, _cyl(0.05, 0.42, 0.3, 4), _toon(Color("26282e")), pos + Vector3(0, 4.0, 0), Vector3(0, 45, 0))
		_light(p, Color("ffb35c"), pos + Vector3(0, 3.5, 0.3), 1.1, 6.0)
	for xs: float in [-1.0, 1.0]:
		var vent := Vector3(xs * 8.0, 0.0, -7.5)
		_mesh(p, _cyl(0.5, 0.6, 0.35, 8), _toon(Color("2c3038")), vent + Vector3(0, -0.1, 0))
		_ambient(p, Color("e8e2ea", 0.7), 14, 2.6, vent + Vector3(0, 0.3, 0), Vector3(0.25, 0.05, 0.25),
			Vector3(0.2, 1.6, 0), 0.7, 3.5, 10.0)
	_ambient(p, Color("ffb35c"), 40, 4.0, Vector3(0, 4, -6), Vector3(11, 3, 3), Vector3(0.4, -0.5, 0), 0.06, 1.0, 40.0)


## Sommet de Prométhée : éclipse au halo de feu, volcan et coulées de lave, chaînes géantes, braseros.
const VW := 26.0  # volcan de Prométhée : demi-largeur et hauteur
const VH := 13.0


static func _forge(p: Node3D) -> void:
	_soft(p, Color("ff5a1a", 0.85), 20, Vector3(-18, 8, -88))
	_layer(p, [_circle(Vector2(-18, 8), 5.0, 48)], Color("ffc070"), Color("ff7a2a"), -86)
	_layer(p, [_circle(Vector2(-18.35, 8.2), 4.6, 48)], Color("140808"), Color("140808"), -85.9)
	_layer(p, [_ridge(-120, 120, 0.5, 6.0, 11, 1.2, 0.8)], Color("3e1416"), Color("a8361c"), -74)
	# volcan au cratère rougeoyant
	_layer(p, [_peak(16, -0.5, VW, VH, 0.0, 0.16)], Color("2a0e10"), Color("7a2216"), -62)
	var lava: Array = []
	for k in 3:
		var line := PackedVector2Array()
		var halves := PackedFloat32Array()
		var x0 := 16.0 + (k - 1) * 2.2
		for i in 12:
			var t := i / 11.0
			var dx := (k - 1) * 0.8 + (k - 1) * t * 10.0 + sin(t * 9.0 + k) * 0.8
			var xs := 16.0 + (x0 - 16.0) + dx
			var u := absf(xs - 16.0) / VW
			line.append(Vector2(xs, -0.5 + minf(VH * pow(1.0 - u, 1.7), VH * 0.84) - 0.2))
			halves.append(lerpf(0.4, 0.1, t))
		lava.append(_strip(line, halves))
	_layer(p, lava, Color("ffd070"), Color("ff4a1a"), -61.9)
	_soft(p, Color("ff8a2a", 0.9), 9, Vector3(16, 10.4, -61.5))
	_ambient(p, Color("2a1616", 0.8), 10, 9.0, Vector3(16, 10.6, -61.6), Vector3(1.5, 0.3, 0.1), Vector3(0.6, 1.0, 0), 2.0, 3.0, 12.0)
	_ambient(p, Color("ffa040"), 24, 3.0, Vector3(16, 10.6, -61.4), Vector3(1.5, 0.3, 0.1), Vector3(0, 3.0, 0), 0.3, 1.0, 35.0)
	_layer(p, [_ridge(-110, 110, 0.0, 5.0, 5, 2.6, 1.6)], Color("170a0c"), Color("4e1610"), -44)
	_layer(p, [_ridge(-100, 100, -0.5, 3.0, 13, 1.4, 0.6)], Color("120909"), Color("261010"), -26)
	# arène de basalte fissurée de lave
	_platform(p, Color("2a1d1c"))
	var ring := BattleFx.flat_ring(Color("ff5a1a"), 7.0, 0.08, 2.0)
	ring.position.y = 0.01
	p.add_child(ring)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var cracks: Array[Transform3D] = []
	for k in 9:
		var a := TAU * k / 9.0 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(1.6, 3.0)
		var prev := Vector2.from_angle(a) * r
		while r < 6.8:
			r += rng.randf_range(0.5, 0.9)
			a += rng.randf_range(-0.18, 0.18)
			var nxt := Vector2.from_angle(a) * minf(r, 6.9)
			cracks.append(_seg_xform(prev, nxt, 0.012, 0.05))
			prev = nxt
	_multi(p, _box(Vector3(1, 0.02, 1)), BattleFx.glow_material(Color("ff5a1a"), 2.2), cracks)
	# chaînes de Prométhée tendues entre le ciel et la roche
	_chain(p, Vector3(-12, 24, -18), Vector3(-6.4, 0.2, -6.2))
	_chain(p, Vector3(12, 24, -18), Vector3(6.4, 0.2, -6.2))
	_chain(p, Vector3(-22, 26, -34), Vector3(-11, 0.0, -15))
	_chain(p, Vector3(22, 26, -34), Vector3(11, 0.0, -15))
	for pos: Vector3 in [Vector3(-8.2, 0, -3.5), Vector3(8.2, 0, -3.5), Vector3(-4.5, 0, -9.5), Vector3(4.5, 0, -9.5)]:
		_brazier(p, pos)
	_ambient(p, Color("ff8a3a"), 60, 5.0, Vector3(0, 1.5, -4), Vector3(12, 2, 5), Vector3(0.3, 1.2, 0), 0.07, 0.4, 30.0)


static func _chain(p: Node3D, a: Vector3, b: Vector3, link := 0.6) -> void:
	var d := b - a
	var dir := d.normalized()
	var side := dir.cross(Vector3.FORWARD).normalized()
	var up := side.cross(dir)
	var base := Basis(dir, up, side) * Basis.from_scale(Vector3(1.5, 1.0, 1.0))
	var n := int(d.length() / (link * 0.85))
	var xf: Array[Transform3D] = []
	for i in n + 1:
		var bs := base if i % 2 == 0 else base * Basis(Vector3.RIGHT, PI / 2.0)
		xf.append(Transform3D(bs, a + d * (float(i) / n)))
	var tor := TorusMesh.new()
	tor.inner_radius = link * 0.28
	tor.outer_radius = link * 0.48
	tor.rings = 12
	tor.ring_segments = 6
	_multi(p, tor, _toon(Color("3a3236"), 0.0, 0.5), xf)
	_mesh(p, _cyl(0.7, 0.9, 0.5, 8), _toon(Color("1c1414")), b - Vector3(0, 0.1, 0))


static func _brazier(p: Node3D, at: Vector3) -> void:
	var iron := _toon(Color("241c1c"))
	_mesh(p, _cyl(0.14, 0.22, 1.3, 8), iron, at + Vector3(0, 0.65, 0))
	_mesh(p, _cyl(0.65, 0.28, 0.45, 10), iron, at + Vector3(0, 1.5, 0))
	_mesh(p, _sphere(0.35), BattleFx.glow_material(Color("ffb050"), 3.0), at + Vector3(0, 1.7, 0))
	_ambient(p, Color("ff8a2a"), 18, 0.9, at + Vector3(0, 1.85, 0), Vector3(0.25, 0.05, 0.25), Vector3(0, 2.2, 0), 0.4, 0.3, 12.0)
	_light(p, Color("ff8a3a"), at + Vector3(0, 2.0, 0.3), 1.5, 7.0)


## Sanctuaire du Chronophage : nuit étoilée, Orion, horloges flottantes, îles suspendues, sabliers.
static func _orion(p: Node3D) -> void:
	var stars_tint: Array[Color] = [Color("ffffff"), Color("cfd8ff"), Color("ffe6a8")]
	_starfield(p, 260, 7, 2.0, stars_tint)
	var o := Vector2(-28, 8.5)
	var orion: Array[Vector2] = []
	for s: Vector2 in [Vector2(-3, 4), Vector2(3, 3.5), Vector2(-1, 0), Vector2(0, 0.3), Vector2(1, 0.6), Vector2(-2.6, -4), Vector2(3, -3.6)]:
		orion.append(o + s * 1.4)
	_constellation(p, orion, [Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 4), Vector2i(2, 3), Vector2i(3, 4), Vector2i(2, 5), Vector2i(4, 6)], GOLD, -94)
	_ambient(p, Color("e6ecff"), 30, 3.0, Vector3(0, 18, -93), Vector3(100, 12, 0.5), Vector3.ZERO, 0.7)
	for k in 3:
		_layer(p, [_cloud(-60 + k * 52.0, 3.0 + k * 1.5, 34.0, 1.6)], Color("4a4a8a", 0.8), Color("2a2c5c", 0.8), -78 + k)
	_dial(p, Vector3(20, 7.5, -76), 5.2, 60.0)
	_dial(p, Vector3(-30, 5, -60), 2.8, -6.0)  # celle-ci tourne à l'envers, très vite : le temps dévoré
	_dial(p, Vector3(40, 4, -58), 2.2, 20.0)
	for isl: Array in [[Vector3(-14, 4.2, -50), 3.6, 3], [Vector3(9, 3.4, -44), 2.6, 5], [Vector3(30, 6, -66), 3.4, 8]]:
		var piv := _pivot(p, isl[0])
		_layer(piv, [_island(isl[1], isl[1] * 0.9, isl[2])], Color("2e3264"), Color("10122c"), 0.0)
		_layer(piv, [_rect(Vector2(isl[1] * 0.3, 1.0), Vector2(0.7, 2.0)), _rect(Vector2(-isl[1] * 0.2, 0.6), Vector2(0.6, 1.2))],
			Color("8a8ab8"), Color("4a4c80"), 0.05)
		_bob(piv, 0.6, 6.0 + isl[2])
	_layer(p, [_ridge(-120, 120, -0.5, 2.5, 4, 1.8, 0.4)], Color("161a3c"), Color("22264e"), -36)
	# arène-cadran : chiffres d'or et aiguilles qui tournent sous les combattants
	_platform(p, Color("1c2148"))
	var ring := BattleFx.flat_ring(GOLD, 6.95, 0.07, 1.6)
	ring.position.y = 0.01
	p.add_child(ring)
	var ticks: Array[Transform3D] = []
	for i in 60:
		var a := TAU * i / 60.0
		var big := i % 5 == 0
		var r0 := 5.9 if big else 6.3
		ticks.append(_seg_xform(Vector2.from_angle(a) * r0, Vector2.from_angle(a) * 6.65, 0.012, 0.16 if big else 0.05))
	_multi(p, _box(Vector3(1, 0.02, 1)), BattleFx.glow_material(GOLD, 1.4), ticks)
	var hands := _pivot(p, Vector3(0, 0.015, 0))
	_mesh(hands, _box(Vector3(0.14, 0.02, 3.6)), BattleFx.glow_material(GOLD, 1.2), Vector3(0, 0, -1.8))
	var minute := _pivot(p, Vector3(0, 0.02, 0))
	_mesh(minute, _box(Vector3(0.08, 0.02, 5.4)), BattleFx.glow_material(GOLD, 1.2), Vector3(0, 0, -2.7))
	_spin(hands, -240.0, "rotation:y")
	_spin(minute, -30.0, "rotation:y")
	for xs: float in [-1.0, 1.0]:
		_hourglass(p, Vector3(xs * 8.4, 0, -5.5))
	_ambient(p, Color("f0d080"), 40, 7.0, Vector3(0, 1.5, -3), Vector3(9, 1.5, 4), Vector3(0, 0.3, 0), 0.05, 1.0, 30.0)


static func _dial(p: Node3D, pos: Vector3, r: float, period: float) -> void:
	var piv := _pivot(p, pos)
	_soft(piv, Color("8a90ff", 0.25), r * 3.2, Vector3(0, 0, -0.1))
	_layer(piv, [_circle(Vector2.ZERO, r * 1.08, 48)], Color("f0d080"), Color("a07830"), 0.0)
	_layer(piv, [_circle(Vector2.ZERO, r, 48)], Color("2a3070"), Color("141a48"), 0.02)
	var ticks: Array = []
	for i in 12:
		var a := TAU * i / 12.0
		ticks.append(_rect(Vector2.from_angle(a) * r * 0.84, Vector2(r * (0.16 if i % 3 == 0 else 0.08), r * 0.035), a))
	ticks.append(_circle(Vector2.ZERO, r * 0.07, 12))
	_layer(piv, ticks, GOLD, GOLD, 0.04)
	var hour := _pivot(piv, Vector3(0, 0, 0.06))
	_layer(hour, [_rect(Vector2(r * 0.27, 0), Vector2(r * 0.55, r * 0.06))], GOLD, GOLD, 0.0)
	var minute := _pivot(piv, Vector3(0, 0, 0.07))
	_layer(minute, [_rect(Vector2(r * 0.4, 0), Vector2(r * 0.8, r * 0.035))], GOLD, GOLD, 0.0)
	hour.rotation.z = randf() * TAU
	_spin(hour, -period * 12.0)
	_spin(minute, -period)


static func _hourglass(p: Node3D, at: Vector3) -> void:
	var gold := _toon(GOLD, 0.3)
	_mesh(p, _cyl(0.95, 0.95, 0.18, 12), gold, at + Vector3(0, 0.09, 0))
	_mesh(p, _cyl(0.95, 0.95, 0.18, 12), gold, at + Vector3(0, 3.2, 0))
	for i in 3:
		var a := TAU * i / 3.0
		_mesh(p, _cyl(0.06, 0.06, 3.0, 6), gold, at + Vector3(cos(a) * 0.82, 1.65, sin(a) * 0.82))
	var glass := _toon(Color(0.75, 0.85, 1.0, 0.28), 0.0, 0.6)
	_mesh(p, _cyl(0.1, 0.78, 1.45, 16), glass, at + Vector3(0, 0.9, 0))
	_mesh(p, _cyl(0.78, 0.1, 1.45, 16), glass, at + Vector3(0, 2.35, 0))
	var sand := _toon(Color("e8c060"), 0.4)
	_mesh(p, _cyl(0.06, 0.62, 0.55, 12), sand, at + Vector3(0, 0.46, 0))
	_mesh(p, _cyl(0.55, 0.06, 0.45, 12), sand, at + Vector3(0, 2.1, 0))
	_mesh(p, _cyl(0.025, 0.025, 1.4, 6), BattleFx.glow_material(Color("f0d080"), 1.5), at + Vector3(0, 1.3, 0))
	_light(p, Color("f0d080"), at + Vector3(0, 1.6, 0.6), 0.8, 4.0)


## Lac gelé du Wyrm : aube rose, monts enneigés, forêt de sapins, côtes de dragon dans la glace, neige.
static func _givre(p: Node3D) -> void:
	_soft(p, Color("fff0e0", 0.7), 12, Vector3(-20, 8, -88))
	_layer(p, [_circle(Vector2(-20, 8), 2.6, 40)], Color("fffaf0"), Color("ffe8d8"), -86)
	var tint: Array[Color] = [Color("ffffff"), Color("dfe8ff")]
	var dip: Array[Vector2] = []
	for s: Vector2 in [Vector2(0, 0), Vector2(1.6, 0.5), Vector2(2.9, 0.7), Vector2(4.2, 0.6), Vector2(4.4, -0.7), Vector2(6.2, -0.5), Vector2(6.1, 0.9)]:
		dip.append(Vector2(12, 8) + s * 1.6)
	_constellation(p, dip, [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 4), Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 3)], Color("eaf2ff"), -94)
	_starfield(p, 50, 21, 7.0, tint)
	_layer(p, [_peak(-8, -0.5, 30, 12)], Color("6a82ac"), Color("b8c6de"), -76)
	_layer(p, [_peak(-8, -0.5, 30, 12, 0.32)], Color("ffffff"), Color("e2eaf6"), -75.9)
	_layer(p, [_ridge(-120, 120, 0.0, 6.0, 8, 1.4, 0.4)], Color("e4ecf8"), Color("7890b8"), -62)
	var pines: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var x := -110.0
	while x < 110.0:
		var h := rng.randf_range(1.8, 3.6)
		pines.append(_pine(x, -0.5, h, h * 0.55))
		x += rng.randf_range(0.7, 2.2)
	_layer(p, pines, Color("3a5070"), Color("6a84a8"), -40, Vector2(0, 3.5))
	_layer(p, [_ridge(-100, 100, -0.5, 1.6, 17, 2.0, 0.2)], Color("dce6f2"), Color("b8c8dc"), -24)
	# arène de glace gravée d'un flocon
	_platform(p, Color("6f90ae"))
	var ring := BattleFx.flat_ring(Color("e8f6ff"), 6.9, 0.06, 1.4)
	ring.position.y = 0.01
	p.add_child(ring)
	var flake: Array[Transform3D] = []
	for i in 6:
		var a := TAU * i / 6.0
		var dir := Vector2.from_angle(a)
		flake.append(_seg_xform(dir * 0.6, dir * 5.6, 0.012, 0.06))
		for f: float in [2.4, 3.8]:
			var root := dir * f
			for s: float in [-1.0, 1.0]:
				flake.append(_seg_xform(root, root + dir.rotated(s * 0.8) * 1.1, 0.012, 0.05))
	_multi(p, _box(Vector3(1, 0.02, 1)), BattleFx.glow_material(Color("cfe6f6"), 0.5), flake)
	# côtes et échine d'un dragon pris dans la glace
	var bone := _toon(Color("dfe9f2"), 0.12, 0.5)
	for i in 4:
		var z := -11.0 - i * 2.2
		var s := 0.62 - i * 0.07
		for side: float in [-1.0, 1.0]:
			var tilt := deg_to_rad(28.0) * side
			var base := Vector3(side * 5.2 * s, -0.2, z)
			_mesh(p, _cyl(0.02, 0.36 * s, 6.5 * s, 8), bone, base + Vector3(-sin(tilt), cos(tilt), 0) * 3.25 * s,
				Vector3(0, 0, rad_to_deg(tilt)))
		_mesh(p, _sphere(0.55 * s), bone, Vector3(0, -0.1, z))
	var ice := _toon(Color(0.62, 0.85, 0.95, 0.85), 0.35, 0.6)
	for i in 9:
		var a := deg_to_rad(rng.randf_range(200.0, 340.0))
		var r := rng.randf_range(9.5, 12.5)
		var h := rng.randf_range(1.0, 2.4)
		_mesh(p, _cyl(0.0, rng.randf_range(0.3, 0.6), h, 6), ice, Vector3(cos(a) * r, h * 0.5 - 0.2, sin(a) * r),
			Vector3(rng.randf_range(-14, 14), rng.randf_range(0, 60), rng.randf_range(-14, 14)))
	_ambient(p, Color("ffffff"), 70, 9.0, Vector3(0, 6, -3), Vector3(14, 5, 6), Vector3(0.25, -0.6, 0), 0.07, 1.0, 20.0)


## Désert du Serpent solaire : soleil rayonnant, Sirius, pyramides, serpent géant entre les dunes, obélisques.
static func _sirius(p: Node3D) -> void:
	var sun := _pivot(p, Vector3(16, 6, -88))
	_layer(sun, [_star(18, 9.0, 5.2)], Color("f8c060", 0.55), Color("f6a83a", 0.55), 0.0)
	_spin(sun, 160.0)
	_layer(p, [_circle(Vector2(16, 6), 4.4, 48)], Color("fff0b8"), Color("ffcc60"), -87.8)
	_soft(p, Color("e8f2ff", 0.8), 4.5, Vector3(-30, 9, -92))
	_layer(p, [_star(4, 1.8, 0.16, Vector2(-30, 9))], Color("ffffff"), Color("dfe8ff"), -91.9)
	_layer(p, [_ridge(-120, 120, 0.0, 3.8, 31, 2.0, 0.0)], Color("e0a868"), Color("f2cc90"), -72)
	for pyr: Array in [[-22.0, 7.0, 5.2], [-9.0, 4.6, 3.3], [30.0, 6.0, 4.2]]:
		var px: float = pyr[0]
		var w: float = pyr[1]
		var h: float = pyr[2]
		var y0 := 1.2
		_layer(p, [PackedVector2Array([Vector2(px - w, y0), Vector2(px, y0 + h), Vector2(px + w * 0.15, y0)])],
			Color("f0c080"), Color("d89a58"), -68)
		_layer(p, [PackedVector2Array([Vector2(px + w * 0.15, y0), Vector2(px, y0 + h), Vector2(px + w, y0)])],
			Color("b87a44"), Color("a06838"), -68)
	# le serpent solaire plonge et ressort des dunes
	var body := PackedVector2Array()
	var halves := PackedFloat32Array()
	var x := -80.0
	while x <= 6.0:
		body.append(Vector2(x, 1.6 + 2.2 * sin(x * 0.15 + 0.6)))
		halves.append(lerpf(0.1, 0.75, inverse_lerp(-80.0, 6.0, x)))
		x += 1.0
	var head := body[body.size() - 1]
	_layer(p, [_star(14, 2.4, 1.3, head + Vector2(0.5, 0))], Color("f0c050"), Color("e8a830"), -47.2)
	_layer(p, [_strip(body, halves), PackedVector2Array([head + Vector2(-0.4, -0.7), head + Vector2(1.7, -0.4),
		head + Vector2(2.2, 0.06), head + Vector2(1.6, 0.6), head + Vector2(-0.4, 0.8)])],
		Color("8a4a22"), Color("4a2410"), -47, Vector2(-1, 4.5))
	var stripe := PackedFloat32Array()
	for i in body.size():
		stripe.append(0.07)
	var spine := PackedVector2Array()
	for i in body.size():
		spine.append(body[i] + Vector2(0, halves[i] * 0.45))
	_layer(p, [_strip(spine, stripe)], Color("f0c050"), Color("f0c050"), -46.9)
	_layer(p, [_circle(head + Vector2(1.05, 0.22), 0.15, 10)], Color("fff4c0"), Color("fff4c0"), -46.8)
	_layer(p, [_ridge(-110, 110, 0.0, 2.4, 9, 2.0, 0.0)], Color("d89850"), Color("b87a40"), -44)
	_layer(p, [_ridge(-100, 100, -0.5, 1.8, 15, 2.5, 0.0)], Color("c0864a"), Color("a8743e"), -26)
	# arène de grès cerclée de lapis et d'or, rayons solaires gravés
	_platform(p, Color("7e5c3e"))
	var lapis := BattleFx.flat_ring(Color("2a5aa8"), 6.9, 0.22, 0.6)
	lapis.position.y = 0.01
	p.add_child(lapis)
	var gold := BattleFx.flat_ring(Color("f0c050"), 6.6, 0.05, 1.6)
	gold.position.y = 0.015
	p.add_child(gold)
	var rays: Array[Transform3D] = []
	for i in 24:
		var a := TAU * i / 24.0
		rays.append(_seg_xform(Vector2.from_angle(a) * 5.2, Vector2.from_angle(a) * (6.2 if i % 2 == 0 else 5.8), 0.012, 0.09))
	_multi(p, _box(Vector3(1, 0.02, 1)), BattleFx.glow_material(Color("f0c050"), 1.3), rays)
	var stone := _toon(Color("a8784a"))
	var tip := _toon(Color("f0c050"), 0.6)
	for pos: Vector3 in [Vector3(-10.5, 0, -7.0), Vector3(10.5, 0, -7.0), Vector3(-5.5, 0, -13.0), Vector3(5.5, 0, -13.0)]:
		_mesh(p, _box(Vector3(1.3, 0.4, 1.3)), stone, pos + Vector3(0, 0.0, 0))
		_mesh(p, _cyl(0.26, 0.42, 4.6, 4), stone, pos + Vector3(0, 2.4, 0), Vector3(0, 45, 0))
		_mesh(p, _cyl(0.0, 0.26, 0.5, 4), tip, pos + Vector3(0, 4.95, 0), Vector3(0, 45, 0))
	_light(p, Color("ffd080"), Vector3(0, 4.0, -9.0), 1.0, 9.0)
	_ambient(p, Color("f0c890"), 50, 5.0, Vector3(-2, 0.6, -2), Vector3(12, 0.6, 6), Vector3(2.0, 0.1, 0), 0.05, 1.0, 10.0)


## Cristal à facettes (prisme hexagonal à pointe) posé au sol, légèrement incliné.
static func _crystal(p: Node3D, at: Vector3, h: float, r: float, c: Color, tilt: Vector3, glow := 0.6) -> void:
	var mat := _toon(c, glow, 0.6)
	var piv := _pivot(p, at)  # corps et pointe tournent ensemble
	piv.rotation_degrees = tilt
	_mesh(piv, _cyl(r * 0.85, r, h * 0.7, 6), mat, Vector3(0, h * 0.35, 0))
	_mesh(piv, _cyl(0.0, r * 0.85, h * 0.3, 6), mat, Vector3(0, h * 0.85, 0))


## Arbre de la Forêt des Gemmes en silhouette : tronc tordu, houppier en nuages, fruits de cristal.
static func _gem_tree(cx: float, base: float, h: float, seed_: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var polys: Array = []
	var trunk := PackedVector2Array()
	var halves := PackedFloat32Array()
	for i in 9:
		var t := i / 8.0
		trunk.append(Vector2(cx + sin(t * 3.0 + seed_) * h * 0.06, base + t * h * 0.7))
		halves.append(lerpf(h * 0.06, h * 0.025, t))
	polys.append(_strip(trunk, halves))
	for k in 5:
		var c := Vector2(cx + rng.randf_range(-0.35, 0.35) * h, base + h * rng.randf_range(0.62, 0.95))
		polys.append(_circle(c, h * rng.randf_range(0.16, 0.26), 18))
	return polys


## Forêt des Gemmes (univers 02) : brume émeraude, arbres géants, cristaux qui luisent, lucioles.
static func _gemmes(p: Node3D) -> void:
	var tint: Array[Color] = [Color("dfffee"), Color("b8f0ff")]
	_starfield(p, 70, 13, 6.0, tint)
	_soft(p, Color("b8ffe8", 0.6), 14, Vector3(14, 7.5, -88))
	_layer(p, [_circle(Vector2(14, 7.5), 2.8, 40)], Color("f4fff8"), Color("c8ffe8"), -86)  # lune pâle
	_layer(p, [_ridge(-120, 120, 0.0, 6.5, 23, 1.6, 0.5)], Color("1f5a52"), Color("4f9e8a"), -72)
	var far: Array = []
	var x := -110.0
	var k := 0
	while x < 110.0:
		far.append_array(_gem_tree(x, -0.5, 7.0 + (k % 3) * 1.5, k))
		x += 9.0 + (k % 4)
		k += 1
	_layer(p, far, Color("17403e"), Color("2f6e62"), -58, Vector2(0, 10))
	var mid: Array = []
	x = -100.0
	while x < 100.0:
		mid.append_array(_gem_tree(x, -0.5, 5.5 + (k % 3), k))
		x += 11.0 + (k % 5)
		k += 1
	_layer(p, mid, Color("0d2826"), Color("1b4440"), -40, Vector2(0, 8))
	# fruits de cristal accrochés aux arbres du plan moyen : petits points lumineux
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	for i in 90:
		xf.append(Transform3D(Basis.from_scale(Vector3.ONE * rng.randf_range(0.25, 0.6)),
			Vector3(rng.randf_range(-90, 90), rng.randf_range(3.0, 8.5), -39.8)))
		cols.append([Color("7fffd4"), Color("c07de0"), Color("ffd27f")][rng.randi() % 3])
	_multi(p, QuadMesh.new(), _dots(), xf, cols)
	_layer(p, [_ridge(-100, 100, -0.5, 1.8, 29, 1.6, 0.4)], Color("0b1f1d"), Color("143330"), -24)
	# arène : dalle de jade, cristaux d'émeraude et d'améthyste autour
	_platform(p, Color("1f4a44"))
	var ring := BattleFx.flat_ring(Color("7fffd4"), 6.9, 0.06, 1.4)
	ring.position.y = 0.01
	p.add_child(ring)
	var gem_cols := [Color("3fe0b0"), Color("b07de0"), Color("7fd0ff")]
	for i in 12:
		var a := deg_to_rad(rng.randf_range(195.0, 345.0))
		var r := rng.randf_range(8.5, 12.0)
		var h := rng.randf_range(1.2, 3.4)
		_crystal(p, Vector3(cos(a) * r, -0.2, sin(a) * r), h, rng.randf_range(0.25, 0.5), gem_cols[i % 3],
			Vector3(rng.randf_range(-15, 15), rng.randf_range(0, 60), rng.randf_range(-15, 15)))
	for pos: Vector3 in [Vector3(-8.5, 0, -5), Vector3(8.5, 0, -5)]:
		_light(p, Color("7fffd4"), pos + Vector3(0, 1.5, 0.5), 1.2, 7.0)
	_ambient(p, Color("c8ffb0"), 45, 6.0, Vector3(0, 2.0, -3), Vector3(11, 2.0, 5), Vector3(0.2, 0.25, 0), 0.07, 1.0, 180.0)


## Cœur de la Géode (étage 25) : parois d'améthyste en éventail, cristaux géants, poussière violette.
static func _geode(p: Node3D) -> void:
	var walls: Array = []  # parois de la géode : grands éclats triangulaires en arc de cercle
	var rng := RandomNumberGenerator.new()
	rng.seed = 25
	for i in 40:
		var x := -100.0 + i * 5.2 + rng.randf_range(-1.5, 1.5)
		var h := 8.0 + 6.0 * pow(absf(x) / 100.0, 1.4) * 2.0 + rng.randf_range(-1.5, 2.5)
		var w := rng.randf_range(2.2, 4.0)
		walls.append(PackedVector2Array([Vector2(x - w, -0.5), Vector2(x + rng.randf_range(-1.0, 1.0), h), Vector2(x + w, -0.5)]))
	_layer(p, walls, Color("c07de0"), Color("3a1a5a"), -64, Vector2(0, 18))
	var front: Array = []
	for i in 26:
		var x := -95.0 + i * 7.6 + rng.randf_range(-2.0, 2.0)
		var h := 4.0 + rng.randf_range(0.0, 4.0)
		var w := rng.randf_range(1.5, 3.0)
		front.append(PackedVector2Array([Vector2(x - w, -0.5), Vector2(x, h), Vector2(x + w, -0.5)]))
	_layer(p, front, Color("7a3aa0"), Color("241038"), -44, Vector2(0, 8))
	_soft(p, Color("e0a0ff", 0.55), 34, Vector3(0, 9, -70))  # lueur au cœur de la géode
	_platform(p, Color("3a2050"))
	var ring := BattleFx.flat_ring(Color("e0a0ff"), 6.95, 0.07, 1.6)
	ring.position.y = 0.01
	p.add_child(ring)
	for i in 10:
		var side := -1.0 if i % 2 == 0 else 1.0
		var r := 9.0 + floori(i / 2.0) * 1.3
		var a := deg_to_rad(250.0 + side * (20.0 + floori(i / 2.0) * 9.0))
		_crystal(p, Vector3(cos(a) * r, -0.2, sin(a) * r - 2.0), 3.0 + floori(i / 2.0) * 0.9, 0.45 + floori(i / 2.0) * 0.08,
			Color("b07de0") if i % 3 else Color("e8c8ff"), Vector3(side * -12.0, i * 23.0, 0), 0.8)
	_light(p, Color("d08cff"), Vector3(0, 3.0, -9.0), 1.6, 10.0)
	_ambient(p, Color("e8c8ff"), 50, 7.0, Vector3(0, 3.0, -4), Vector3(12, 3.0, 5), Vector3(0, 0.15, 0), 0.06, 1.0, 180.0)


# --- Habillage anti-« espace lisse » : plans intermédiaires et climat ------------------------

const PULSE_GLOW := """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.35, 0.1, 1.0);
uniform float energy = 2.4;
uniform float speed = 1.6;
void fragment() {
	float p = 0.55 + 0.45 * sin(TIME * speed + NODE_POSITION_WORLD.x * 0.7 + UV.x * 6.0);
	ALBEDO = color.rgb * energy * p;
}
"""
const GROUND_MIST := """shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color = vec4(0.9, 0.95, 1.0, 0.5);
uniform float drift = 0.04;
float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(12.9898, 78.233))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1, 0), vec2(12.9898, 78.233))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0, 1), vec2(12.9898, 78.233))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1, 1), vec2(12.9898, 78.233))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
void fragment() {
	vec2 uv = UV * 4.0 + vec2(TIME * drift, TIME * drift * 0.4);
	float n = n2(uv) * 0.6 + n2(uv * 2.3) * 0.4;
	float edge = 1.0 - smoothstep(0.25, 0.5, length(UV - 0.5));
	ALBEDO = color.rgb;
	ALPHA = color.a * smoothstep(0.3, 0.8, n) * edge;
}
"""

static var _pulse_shader: Shader
static var _mist_shader: Shader


static func _pulse_mat(c: Color, energy := 2.4, speed := 1.6) -> ShaderMaterial:
	if _pulse_shader == null:
		_pulse_shader = Shader.new()
		_pulse_shader.code = PULSE_GLOW
	var m := ShaderMaterial.new()
	m.shader = _pulse_shader
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("speed", speed)
	return m


## Nappe de brouillard au ras du sol (le rendu mobile n'a pas de brouillard volumétrique) : plans de bruit qui dérivent.
static func _ground_mist(p: Node3D, c: Color, centers: Array[Vector3], size := 14.0) -> void:
	if _mist_shader == null:
		_mist_shader = Shader.new()
		_mist_shader.code = GROUND_MIST
	for i in centers.size():
		var pm := PlaneMesh.new()
		pm.size = Vector2(size, size * 0.6)
		var m := ShaderMaterial.new()
		m.shader = _mist_shader
		m.set_shader_parameter("color", c)
		m.set_shader_parameter("drift", 0.03 + 0.015 * (i % 3))
		var mi := _mesh(p, pm, m, centers[i])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Rocher stylisé (toon, facettes) posé au sol.
static func _rock(p: Node3D, at: Vector3, s: float, c: Color, rng: RandomNumberGenerator) -> void:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 6
	sm.rings = 3
	var mi := _mesh(p, sm, _toon(c, 0.0, 0.4), at + Vector3(0, 0.25 * s, 0), Vector3(0, rng.randf_range(0, 360), rng.randf_range(-8, 8)))
	mi.scale = Vector3(rng.randf_range(0.9, 1.4), rng.randf_range(0.5, 0.8), rng.randf_range(0.8, 1.2)) * s


## Touffes d'herbe : brins effilés regroupés (un seul MultiMesh pour tout le décor).
static func _grass(p: Node3D, spots: Array[Vector3], c: Color, rng: RandomNumberGenerator, blades := 9) -> void:
	var pm := PrismMesh.new()
	pm.size = Vector3(0.08, 0.6, 0.02)
	var xf: Array[Transform3D] = []
	for at in spots:
		for k in blades:
			var h := rng.randf_range(0.6, 1.3)
			var b := Basis(Vector3.UP, rng.randf_range(0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(-0.35, 0.35)) * Basis.from_scale(Vector3(1, h, 1))
			xf.append(Transform3D(b, at + Vector3(rng.randf_range(-0.35, 0.35), 0.3 * h - 0.05, rng.randf_range(-0.35, 0.35))))
	_multi(p, pm, _toon(c, 0.0, 0.3), xf)


## Jizō de pierre : petite statue au bonnet et bavoir rouges.
static func _jizo(p: Node3D, at: Vector3, s := 1.0) -> void:
	var stone := _toon(Color("7a7480"), 0.0, 0.3)
	_mesh(p, _cyl(0.32 * s, 0.4 * s, 0.25 * s, 8), stone, at + Vector3(0, 0.12 * s, 0))
	_mesh(p, _cyl(0.22 * s, 0.3 * s, 0.75 * s, 10), stone, at + Vector3(0, 0.62 * s, 0))
	_mesh(p, _sphere(0.2 * s), stone, at + Vector3(0, 1.15 * s, 0))
	_mesh(p, _cyl(0.05 * s, 0.31 * s, 0.25 * s, 10), _toon(Color("c0302a")), at + Vector3(0, 0.88 * s, 0.02))  # bavoir
	_mesh(p, _cyl(0.12 * s, 0.21 * s, 0.14 * s, 10), _toon(Color("c0302a")), at + Vector3(0, 1.3 * s, 0))  # bonnet


## Barrière traditionnelle en bois (poteaux et deux lisses) de a à b.
static func _fence(p: Node3D, a: Vector3, b: Vector3) -> void:
	var wood := _toon(Color("5a3a28"), 0.0, 0.3)
	var d := b - a
	var n := maxi(2, int(d.length() / 1.6))
	for i in n + 1:
		_mesh(p, _box(Vector3(0.14, 1.1, 0.14)), wood, a + d * (float(i) / n) + Vector3(0, 0.55, 0))
	var yaw := rad_to_deg(atan2(-d.z, d.x))
	for y: float in [0.45, 0.9]:
		_mesh(p, _box(Vector3(d.length(), 0.08, 0.08)), wood, (a + b) * 0.5 + Vector3(0, y, 0), Vector3(0, yaw, 0))


## Lucioles / flammèches qui s'élèvent autour d'une lanterne.
static func _fireflies(p: Node3D, at: Vector3, c := Color("ffd27a")) -> void:
	_ambient(p, c, 8, 3.5, at + Vector3(0, 1.4, 0), Vector3(0.9, 0.6, 0.9), Vector3(0, 0.45, 0), 0.07, 0.6, 60.0)


## Cour du torii : rochers, herbes, Jizō, barrières à mi-distance ; pétales plus denses, lucioles.
static func _dojo_rich(p: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var rock_c := Color("4a3a48")
	for at: Vector3 in [Vector3(-11, 0, -9), Vector3(-8.5, 0, -17), Vector3(10.5, 0, -10), Vector3(8, 0, -19),
			Vector3(-16, 0, -21), Vector3(17, 0, -22), Vector3(-3.5, 0, -22), Vector3(4, 0, -25)]:
		_rock(p, at, rng.randf_range(0.6, 1.3), rock_c, rng)
	var tufts: Array[Vector3] = []
	for i in 46:
		var a := deg_to_rad(rng.randf_range(190, 350))
		var r := rng.randf_range(7.8, 20.0)
		tufts.append(Vector3(cos(a) * r, -0.05, sin(a) * r * 1.2))
	_grass(p, tufts, Color("4a5a3a"), rng)
	for at: Vector3 in [Vector3(-6.8, 0, -12.5), Vector3(-5.6, 0, -12.9), Vector3(6.2, 0, -12.6)]:
		_jizo(p, at, 0.8)
	_fence(p, Vector3(-19, 0, -18), Vector3(-9, 0, -16))
	_fence(p, Vector3(9, 0, -16), Vector3(19, 0, -18))
	_fence(p, Vector3(-26, 0, -27), Vector3(-15, 0, -26))
	_fence(p, Vector3(15, 0, -26), Vector3(26, 0, -27))
	_ambient(p, BattleFx.SAKURA, 70, 8.0, Vector3(0, 4, -8), Vector3(16, 4, 7), Vector3(0.6, -0.25, 0.1), 0.09)
	for at: Vector3 in [Vector3(-9.2, 0, -3.5), Vector3(9.2, 0, -3.5), Vector3(-5.5, 0, -9.5), Vector3(5.5, 0, -9.5)]:
		_fireflies(p, at)


## Volcan éclipsé : pics rocheux, sanctuaire brisé, fumée sombre, braises, fissures de lave qui pulsent.
static func _forge_rich(p: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	var basalt := _toon(Color("1e1214"), 0.0, 0.45)
	for i in 14:
		var a := deg_to_rad(rng.randf_range(195, 345))
		var r := rng.randf_range(9.0, 22.0)
		var h := rng.randf_range(2.0, 6.5)
		_mesh(p, _cyl(0.0, rng.randf_range(0.5, 1.2), h, 5), basalt, Vector3(cos(a) * r, h * 0.5 - 0.3, sin(a) * r),
			Vector3(rng.randf_range(-12, 12), rng.randf_range(0, 70), rng.randf_range(-12, 12)))
	# sanctuaire brisé : piliers rompus, poutre tombée, toit effondré
	var lacquer := _toon(Color("5a1a18"), 0.0, 0.3)
	var dark := _toon(Color("1a1214"))
	for x: float in [-13.0, -9.0]:
		_mesh(p, _cyl(0.28, 0.32, 3.2 if x < -10 else 1.6, 8), lacquer, Vector3(x, (3.2 if x < -10 else 1.6) * 0.5, -17))
	_mesh(p, _box(Vector3(5.2, 0.35, 0.4)), lacquer, Vector3(-10.5, 0.4, -16.2), Vector3(0, 12, 8))
	_mesh(p, _cyl(0.4, 2.6, 0.9, 4), dark, Vector3(12, 0.3, -18), Vector3(18, 45, -10))
	_mesh(p, _cyl(0.22, 0.26, 2.3, 8), lacquer, Vector3(10.5, 1.15, -17.5), Vector3(0, 0, -14))
	# fumée sombre qui monte, braises plus nombreuses
	_ambient(p, Color("2a1414", 0.45), 14, 10.0, Vector3(0, 1.0, -26), Vector3(24, 0.5, 4), Vector3(0.2, 1.0, 0), 1.6, 2.5, 15.0)
	_ambient(p, Color("ffb050"), 50, 4.0, Vector3(0, 0.2, -6), Vector3(13, 0.3, 8), Vector3(0, 1.6, 0), 0.06, 0.4, 25.0)
	# micro-fissures de lave autour de l'arène, lueur qui pulse
	var cracks: Array[Transform3D] = []
	for i in 26:
		var a := deg_to_rad(rng.randf_range(0, 360))
		var r := rng.randf_range(7.6, 15.0)
		var p0 := Vector2(cos(a), sin(a)) * r
		var p1 := p0 + Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(0.8, 2.2)
		cracks.append(_seg_xform(p0, p1, -0.4, 0.07))
	_multi(p, _box(Vector3(1, 0.04, 1)), _pulse_mat(Color("ff5a1a"), 2.6, 1.4), cracks)


## Toundra : sapins enneigés, amas de glace, ruines gelées ; blizzard et brouillard de froid au sol.
static func _givre_rich(p: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 59
	var fir := _toon(Color("2e4a52"), 0.0, 0.35)
	var snow := _toon(Color("f4f8ff"), 0.1, 0.4)
	var trunk := _toon(Color("3a2a24"))
	for i in 18:
		var x := rng.randf_range(-28, 28)
		if absf(x) < 8.0:
			x += signf(x) * 8.0
		var z := rng.randf_range(-30, -15)
		var s := rng.randf_range(0.8, 1.6)
		_mesh(p, _cyl(0.12 * s, 0.16 * s, 0.8 * s, 6), trunk, Vector3(x, 0.4 * s - 0.3, z))
		for k in 3:
			var y := (0.9 + k * 0.75) * s
			var r := (1.15 - k * 0.3) * s
			_mesh(p, _cyl(0.0, r, 1.1 * s, 8), fir, Vector3(x, y, z))
			_mesh(p, _cyl(0.0, r * 0.75, 0.45 * s, 8), snow, Vector3(x, y + 0.3 * s, z))
	var ice := _toon(Color(0.7, 0.88, 0.98, 0.9), 0.3, 0.6)
	for c: Vector3 in [Vector3(-9.5, 0, -7), Vector3(9.8, 0, -6.5), Vector3(-13, 0, -13), Vector3(13, 0, -12.5)]:
		for k in 5:
			var h := rng.randf_range(0.5, 1.6)
			_mesh(p, _box(Vector3(rng.randf_range(0.4, 0.9), h, rng.randf_range(0.4, 0.8))), ice,
				c + Vector3(rng.randf_range(-1.2, 1.2), h * 0.4 - 0.2, rng.randf_range(-1.0, 1.0)),
				Vector3(rng.randf_range(-25, 25), rng.randf_range(0, 90), rng.randf_range(-25, 25)))
	# ruines de glace : piliers brisés et arche
	var ruin := _toon(Color(0.78, 0.9, 1.0, 0.85), 0.25, 0.6)
	for x: float in [-4.0, 4.0]:
		_mesh(p, _box(Vector3(0.9, 4.2 if x < 0 else 2.6, 0.9)), ruin, Vector3(x, (4.2 if x < 0 else 2.6) * 0.5 - 0.2, -20))
	_mesh(p, _box(Vector3(5.5, 0.7, 0.9)), ruin, Vector3(-1.6, 4.3, -20), Vector3(0, 0, -6))
	_mesh(p, _box(Vector3(2.2, 0.6, 0.8)), ruin, Vector3(5.6, 0.1, -18.5), Vector3(10, 30, 70))
	# blizzard léger et brouillard de froid au ras du sol
	_ambient(p, Color("ffffff"), 140, 4.0, Vector3(-4, 4, -2), Vector3(18, 4, 8), Vector3(2.6, -1.1, 0.4), 0.06, 1.0, 12.0)
	var fog: Array[Vector3] = [Vector3(-9, 0.15, 2), Vector3(9, 0.18, 1), Vector3(-12, 0.2, -9), Vector3(12, 0.22, -10),
		Vector3(0, 0.25, -14), Vector3(-6, 0.2, -18), Vector3(7, 0.2, -19)]
	_ground_mist(p, Color(0.92, 0.96, 1.0, 0.55), fog)


## Cité d'Acier enrichie : pylônes industriels, conduites luminescentes au sol et nappes de vapeur.
static func _acier_rich(p: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var steel := _toon(Color("282c36"), 0.0, 0.45)
	for at: Vector3 in [Vector3(-11.5, 0, -12), Vector3(11.5, 0, -12), Vector3(-15, 0, -20), Vector3(15, 0, -20)]:
		_mesh(p, _box(Vector3(0.9, 3.8, 0.9)), steel, at + Vector3(0, 1.9, 0))
		_mesh(p, _box(Vector3(1.1, 0.25, 1.1)), _pulse_mat(Color("ff9a3d"), 2.2, 1.8), at + Vector3(0, 2.8, 0))
	var pipes: Array[Transform3D] = []
	for i in 18:
		var a := deg_to_rad(rng.randf_range(190, 350))
		var r := rng.randf_range(8.0, 16.0)
		var p0 := Vector2(cos(a), sin(a)) * r
		var p1 := p0 + Vector2.from_angle(a + PI * 0.5) * rng.randf_range(1.2, 2.6)
		pipes.append(_seg_xform(p0, p1, -0.38, 0.08))
	_multi(p, _box(Vector3(1, 0.04, 1)), _pulse_mat(Color("ff8a3a"), 2.0, 1.5), pipes)
	var smog: Array[Vector3] = [Vector3(-8, 0.15, -8), Vector3(8, 0.15, -8), Vector3(0, 0.2, -15), Vector3(-11, 0.2, -18), Vector3(11, 0.2, -18)]
	_ground_mist(p, Color(0.75, 0.65, 0.72, 0.42), smog)


## Sanctuaire d'Orion enrichi : anneaux d'astrolabe en lévitation, monolithes stellaires et brume astrale.
static func _orion_rich(p: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	var astro := _pivot(p, Vector3(0, 0.2, 0))
	var ring := BattleFx.flat_ring(GOLD, 8.2, 0.05, 1.8)
	astro.add_child(ring)
	_spin(astro, 90.0, "rotation:y")
	var stone := _toon(Color("1c224a"), 0.1, 0.5)
	for at: Vector3 in [Vector3(-11, 0, -11), Vector3(11, 0, -11), Vector3(-7, 0, -18), Vector3(7, 0, -18)]:
		var piv := _pivot(p, at)
		_mesh(piv, _box(Vector3(0.65, 2.8, 0.35)), stone, Vector3(0, 1.4, 0))
		_mesh(piv, _sphere(0.18), BattleFx.glow_material(GOLD, 2.5), Vector3(0, 3.1, 0))
		_bob(piv, 0.35, rng.randf_range(4.5, 6.5))
	var mist: Array[Vector3] = [Vector3(-8, 0.15, -6), Vector3(8, 0.15, -6), Vector3(0, 0.2, -13), Vector3(-9, 0.2, -17), Vector3(9, 0.2, -17)]
	_ground_mist(p, Color(0.45, 0.52, 0.95, 0.42), mist)


## Désert de Sirius enrichi : vestiges ensablés, braseros solaires et brume de sable doré.
static func _sirius_rich(p: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 83
	var sandstone := _toon(Color("b8844e"), 0.0, 0.35)
	for at: Vector3 in [Vector3(-12, 0, -10), Vector3(12, 0, -10), Vector3(-15, 0, -19), Vector3(15, 0, -19)]:
		_rock(p, at, rng.randf_range(0.9, 1.5), Color("9e6e3e"), rng)
		_mesh(p, _box(Vector3(1.1, 1.8, 1.1)), sandstone, at + Vector3(0, 0.6, -1.2), Vector3(8, rng.randf_range(-25, 25), -12))
	for at: Vector3 in [Vector3(-7.8, 0, -4.2), Vector3(7.8, 0, -4.2)]:
		_brazier(p, at)
	var sand_mist: Array[Vector3] = [Vector3(-9, 0.15, -5), Vector3(9, 0.15, -5), Vector3(0, 0.2, -12), Vector3(-10, 0.2, -17), Vector3(10, 0.2, -17)]
	_ground_mist(p, Color(0.96, 0.78, 0.48, 0.45), sand_mist)


## Forêt des Gemmes enrichie : herbes bioluminescentes, rochers moussus et brume d'émeraude.
static func _gemmes_rich(p: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 89
	var tufts: Array[Vector3] = []
	for i in 42:
		var a := deg_to_rad(rng.randf_range(190, 350))
		var r := rng.randf_range(7.8, 19.0)
		tufts.append(Vector3(cos(a) * r, -0.05, sin(a) * r * 1.15))
	_grass(p, tufts, Color("2e8a78"), rng)
	for at: Vector3 in [Vector3(-10, 0, -9), Vector3(10, 0, -9), Vector3(-14, 0, -17), Vector3(14, 0, -17)]:
		_rock(p, at, rng.randf_range(0.8, 1.3), Color("183834"), rng)
		_fireflies(p, at, Color("7fffd4"))
	var mist: Array[Vector3] = [Vector3(-8, 0.15, -6), Vector3(8, 0.15, -6), Vector3(0, 0.2, -13), Vector3(-10, 0.2, -18), Vector3(10, 0.2, -18)]
	_ground_mist(p, Color(0.35, 0.88, 0.75, 0.42), mist)


## Cœur de la Géode enrichi : veines d'améthyste pulsantes, éclats en lévitation et brume cristalline.
static func _geode_rich(p: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 97
	var veins: Array[Transform3D] = []
	for i in 24:
		var a := deg_to_rad(rng.randf_range(0, 360))
		var r := rng.randf_range(7.4, 15.0)
		var p0 := Vector2(cos(a), sin(a)) * r
		var p1 := p0 + Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(0.9, 2.3)
		veins.append(_seg_xform(p0, p1, -0.38, 0.07))
	_multi(p, _box(Vector3(1, 0.04, 1)), _pulse_mat(Color("d07aff"), 2.5, 1.6), veins)
	for at: Vector3 in [Vector3(-8.5, 2.2, -8), Vector3(8.5, 2.4, -8), Vector3(-11, 3.0, -15), Vector3(11, 3.2, -15)]:
		var piv := _pivot(p, at)
		_crystal(piv, Vector3.ZERO, 1.2, 0.24, Color("e0a0ff"), Vector3(15, 0, -12), 1.2)
		_bob(piv, 0.45, rng.randf_range(3.8, 5.5))
	var mist: Array[Vector3] = [Vector3(-8, 0.15, -6), Vector3(8, 0.15, -6), Vector3(0, 0.2, -12), Vector3(-9, 0.2, -17), Vector3(9, 0.2, -17)]
	_ground_mist(p, Color(0.78, 0.48, 0.98, 0.45), mist)
