class_name BattleFx
extends RefCounted
## Effets visuels du combat, direction artistique d'estampe ukiyo-e : arène au crépuscule (soleil rouge,
## nuages kumo, piliers laqués, lanternes), taches d'encre à l'impact, pétales de sakura, ondes à écume.
## Formes simples et particules CPU : légères pour le mobile.

const INK := Color("1c1618")
const SAKURA := Color("f29ab4")

const SLASH_SHADER := preload("res://assets/materials/shaders/ink_slash.gdshader")
const SEAL_SHADER := preload("res://assets/materials/shaders/unit_seal.gdshader")
const TRAIL_SHADER := preload("res://assets/materials/shaders/vfx_scrolling.gdshader")
const TORNADO_SHADER := preload("res://assets/materials/shaders/vfx_tornado.gdshader")
const AURA_SHADER := preload("res://assets/materials/shaders/vfx_aura.gdshader")
## Couleur signature des pouvoirs de chaque héros et boss (sinon la couleur de la constellation).
const SIGNATURE := {
	"montana": Color("ffc94a"), "mikhaila": Color("ffe08a"), "ghost": Color("5ab4ff"),
	"nyssa": Color("9b6bff"), "selene": Color("8fa8c8"), "adrian": Color("ff6230"),
	"mello": Color("38b6ff"), "tarkhan": Color("ff3d2e"), "yass": Color("b06aff"),
	"saraya": Color("58e08a"), "noor_el": Color("ffd85a"), "jo_prince": Color("6a5aff"),
	"ezra": Color("c84aff"), "flint": Color("ff7aa8"), "don_selah": Color("e8e0d0"),
	"eirikr": Color("5ac8ff"), "ymir": Color("4aa0ff"), "nidhogg": Color("ffd46a"),
	"don_diego": Color("f0c45a"), "general_metal": Color("c0cad8"), "espion_lumiere": Color("80f0b0"),
	"moussa": Color("e09048"), "issa": Color("7fe8c8"), "mohamed": Color("9a58ff"),
	"promethee": Color("ff6a2a"), "geode": Color("d07aff"), "chronophage": Color("f0c860"),
	"wyrm": Color("7fd8ff"), "serpent": Color("ffb040"),
}

static var _disc_tex: GradientTexture2D
static var _crescent: ArrayMesh


## Croissant (UV.x le long du trait, UV.y en travers) : plus épais au milieu, effilé aux pointes.
static func crescent_mesh() -> ArrayMesh:
	if _crescent == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := 24
		var outer: Array[Vector3] = []
		var inner: Array[Vector3] = []
		for i in n + 1:
			var t := float(i) / n
			var a := lerpf(-1.25, 1.25, t)
			var w := 0.42 * sin(t * PI) + 0.02
			outer.append(Vector3(cos(a), sin(a), 0) * (0.95 + w * 0.5))
			inner.append(Vector3(cos(a), sin(a), 0) * (0.95 - w * 0.5))
		for i in n:
			var t0 := float(i) / n
			var t1 := float(i + 1) / n
			for v: Array in [[outer[i], t0, 0.0], [inner[i], t0, 1.0], [outer[i + 1], t1, 0.0],
					[outer[i + 1], t1, 0.0], [inner[i], t0, 1.0], [inner[i + 1], t1, 1.0]]:
				st.set_uv(Vector2(v[1], v[2]))
				st.add_vertex(v[0])
		_crescent = st.commit()
	return _crescent


## Disque doux (dégradé radial) : tache d'encre, pétale, soleil, nuage.
static func disc_texture() -> GradientTexture2D:
	if _disc_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color.WHITE)
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.72, Color.WHITE)
		_disc_tex = GradientTexture2D.new()
		_disc_tex.gradient = g
		_disc_tex.fill = GradientTexture2D.FILL_RADIAL
		_disc_tex.fill_from = Vector2(0.5, 0.5)
		_disc_tex.fill_to = Vector2(1.0, 0.5)
		_disc_tex.width = 64
		_disc_tex.height = 64
	return _disc_tex


static func flat_material(c: Color, billboard := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.albedo_texture = disc_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true  # aplats d'estampe : la brume ne les ternit pas
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
	return m


static func _disc(c: Color, size: Vector2, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.material_override = flat_material(c)
	mi.position = pos
	return mi


static func glow_material(c: Color, energy := 1.0, billboard := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
	return m


static func _quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	return q


static func flat_ring(c: Color, radius: float, thickness: float, energy := 1.5) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = radius - thickness
	t.outer_radius = radius
	t.rings = 64
	t.ring_segments = 6
	mi.mesh = t
	mi.scale = Vector3(1, 0.05, 1)
	mi.material_override = glow_material(c, energy)
	return mi


## Gerbe de particules qui s'éteint toute seule (impact, soin, mort).
static func burst(parent: Node3D, pos: Vector3, c: Color, amount := 24, speed := 4.5, size := 0.08, life := 0.5, rising := false) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = life
	p.position = pos
	var orb := SphereMesh.new()  # petites billes lumineuses (plus douces que des carrés)
	orb.radius = size * 0.5
	orb.height = size
	orb.radial_segments = 6
	orb.rings = 3
	p.mesh = orb
	var pm := glow_material(c, 3.0)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.vertex_color_use_as_albedo = true
	p.material_override = pm
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0 if rising else 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, 2.0, 0) if rising else Vector3(0, -7.0, 0)
	var g := Gradient.new()
	g.set_color(0, Color(c, 1.0))
	g.set_color(1, Color(c, 0.0))
	p.color_ramp = g
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = curve
	parent.add_child(p)
	parent.get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


## Tranchant d'encre (vibe Ufotable) : un croissant de pinceau balaie la cible puis s'efface. Un seul
## maillage et un shader à défilement d'UV, pas de particules lourdes.
static func ink_slash(parent: Node3D, pos: Vector3, c: Color, crit := false, duration := 0.28) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = crescent_mesh()
	var m := ShaderMaterial.new()
	m.shader = SLASH_SHADER
	m.set_shader_parameter("edge_color", c)
	m.set_shader_parameter("angle", randf_range(-0.9, 0.9) + (PI if randf() < 0.5 else 0.0))
	m.set_shader_parameter("seed", randf() * 50.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.scale = Vector3.ONE * (1.8 if crit else 1.4)
	parent.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("progress", v), 0.0, 1.0, duration)
	tw.tween_callback(mi.queue_free)


## Sceau doré sous les pieds d'une unité (anneaux, graduations, échiquier inscrit).
static func unit_seal(c: Color, radius := 0.62) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = SEAL_SHADER
	m.set_shader_parameter("color", c)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.03
	return mi


## Impact : tache d'encre qui s'étale puis s'efface, gouttelettes d'encre et éclats de la couleur de l'attaquant.
static func ink_splash(parent: Node3D, pos: Vector3, c: Color, crit := false) -> void:
	var blot := _disc(INK, Vector2(1, 1), pos)
	var mat: StandardMaterial3D = blot.material_override
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	blot.scale = Vector3.ONE * 0.2
	parent.add_child(blot)
	var tw := blot.create_tween().set_parallel()
	tw.tween_property(blot, "scale", Vector3.ONE * (1.6 if crit else 1.0), 0.12).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35).set_delay(0.12)
	tw.chain().tween_callback(blot.queue_free)
	var p := CPUParticles3D.new()  # gouttelettes d'encre, lourdes
	p.one_shot = true
	p.emitting = true
	p.explosiveness = 1.0
	p.amount = 22 if crit else 12
	p.lifetime = 0.55
	p.position = pos
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.11)
	p.mesh = q
	p.material_override = flat_material(Color.WHITE, true)
	p.direction = Vector3(0, 0.4, 1)
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0 if crit else 3.5
	p.gravity = Vector3(0, -12.0, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.3
	var g := Gradient.new()
	g.set_color(0, INK)
	g.set_color(1, Color(INK, 0.0))
	p.color_ramp = g
	parent.add_child(p)
	parent.get_tree().create_timer(0.9).timeout.connect(p.queue_free)
	burst(parent, pos, c, 10 if crit else 6, 4.0, 0.07, 0.4)


## Soin : pétales de sakura qui montent en tourbillonnant puis retombent.
static func petals(parent: Node3D, pos: Vector3, amount := 14) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.explosiveness = 0.8
	p.amount = amount
	p.lifetime = 1.3
	p.position = pos
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.085)
	p.mesh = q
	p.material_override = flat_material(Color.WHITE, true)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.direction = Vector3(0, 1, 0)
	p.spread = 45.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, -1.2, 0)
	p.angle_max = 360.0
	p.angular_velocity_min = -220.0
	p.angular_velocity_max = 220.0
	p.tangential_accel_min = 1.0
	p.tangential_accel_max = 2.5
	var g := Gradient.new()
	g.set_color(0, Color("ffd6e0"))
	g.add_point(0.6, SAKURA)
	g.set_color(1, Color(SAKURA, 0.0))
	p.color_ramp = g
	parent.add_child(p)
	parent.get_tree().create_timer(1.6).timeout.connect(p.queue_free)


## Barre de vie 3D tournée vers la caméra : {root, fill, shield}.
static func hp_bar(c: Color) -> Dictionary:
	var root := Node3D.new()
	var bg := MeshInstance3D.new()
	bg.mesh = _box(Vector3(1.0, 0.09, 0.01))
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.05, 0.04, 0.08)
	bg.material_override = bm
	root.add_child(bg)
	var fill_root := Node3D.new()  # ancré à gauche pour réduire la barre par la droite
	fill_root.position = Vector3(-0.48, 0, 0.006)
	root.add_child(fill_root)
	var fill := MeshInstance3D.new()
	fill.mesh = _box(Vector3(0.96, 0.06, 0.01))
	fill.position = Vector3(0.48, 0, 0)
	fill.material_override = glow_material(c, 0.6)
	fill_root.add_child(fill)
	var shield_root := Node3D.new()
	shield_root.position = Vector3(-0.48, 0.065, 0.006)
	root.add_child(shield_root)
	var sh := MeshInstance3D.new()
	sh.mesh = _box(Vector3(0.96, 0.025, 0.01))
	sh.position = Vector3(0.48, 0, 0)
	sh.material_override = glow_material(Color("d8f2ff"), 1.2)
	shield_root.add_child(sh)
	shield_root.scale.x = 0.0
	var tough_root := Node3D.new()  # Ténacité (mode tactique de la Tour), sous la barre de vie
	tough_root.position = Vector3(-0.48, -0.075, 0.006)
	root.add_child(tough_root)
	var tg := MeshInstance3D.new()
	tg.mesh = _box(Vector3(0.96, 0.03, 0.01))
	tg.position = Vector3(0.48, 0, 0)
	tg.material_override = glow_material(Color("e8dec5"), 0.9)
	tough_root.add_child(tg)
	tough_root.scale.x = 0.0
	return {"root": root, "fill": fill_root, "shield": shield_root, "tough": tough_root}


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


## Projectile lumineux (sorts) : une sphère qui file vers la cible avec sa lumière.
static func projectile(parent: Node3D, from: Vector3, to: Vector3, c: Color, duration: float) -> void:
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	orb.mesh = sm
	orb.material_override = glow_material(c.lightened(0.3), 4.0)
	orb.position = from
	parent.add_child(orb)
	var light := OmniLight3D.new()
	light.light_color = c
	light.light_energy = 2.0
	light.omni_range = 2.5
	orb.add_child(light)
	var tw := orb.create_tween()
	tw.tween_property(orb, "position", to, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(orb.queue_free)


## Onde au sol qui s'élargit et s'efface (attaques de zone, soins de groupe).
static func shockwave(parent: Node3D, center: Vector3, c: Color, radius: float, duration: float) -> void:
	var ring := flat_ring(c, 1.0, 0.12, 3.0)
	ring.position = center + Vector3(0, 0.05, 0)
	ring.scale = Vector3(0.2, 0.05, 0.2)
	var mat: StandardMaterial3D = ring.material_override
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	parent.add_child(ring)
	var tw := ring.create_tween().set_parallel()
	tw.tween_property(ring, "scale", Vector3(radius, 0.05, radius), duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(ring.queue_free)
	# écume blanche qui suit la vague, comme la crête d'une vague de Hokusai
	var foam := flat_ring(Color("f4ecd8"), 1.0, 0.05, 1.5)
	foam.position = ring.position + Vector3(0, 0.01, 0)
	foam.scale = Vector3(0.15, 0.05, 0.15)
	var fm: StandardMaterial3D = foam.material_override
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	parent.add_child(foam)
	var tf := foam.create_tween().set_parallel()
	tf.tween_property(foam, "scale", Vector3(radius * 0.88, 0.05, radius * 0.88), duration * 1.1).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tf.tween_property(fm, "albedo_color:a", 0.0, duration * 1.1)
	tf.chain().tween_callback(foam.queue_free)


# --- Pipeline VFX : traînées, tornades, impacts, rupture, auras ------------------------

static var _arc_mesh: ArrayMesh
static var _shard_mesh: Mesh


## Arc de cercle plat (UV.x le long de l'arc, UV.y en travers), base des traînées de lame.
static func arc_mesh() -> ArrayMesh:
	if _arc_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := 28
		for i in n:
			var a0 := lerpf(-1.25, 1.25, float(i) / n)
			var a1 := lerpf(-1.25, 1.25, float(i + 1) / n)
			var w0 := 0.22 * sin(PI * float(i) / n) + 0.03
			var w1 := 0.22 * sin(PI * float(i + 1) / n) + 0.03
			var pts := [Vector3(sin(a0) * (1.0 - w0), cos(a0) * (1.0 - w0), 0), Vector3(sin(a0) * (1.0 + w0), cos(a0) * (1.0 + w0), 0),
				Vector3(sin(a1) * (1.0 + w1), cos(a1) * (1.0 + w1), 0), Vector3(sin(a1) * (1.0 - w1), cos(a1) * (1.0 - w1), 0)]
			var uvs := [Vector2(float(i) / n, 0), Vector2(float(i) / n, 1), Vector2(float(i + 1) / n, 1), Vector2(float(i + 1) / n, 0)]
			for idx: int in [0, 1, 2, 0, 2, 3]:
				st.set_uv(uvs[idx])
				st.add_vertex(pts[idx])
		_arc_mesh = st.commit()
	return _arc_mesh


## Coup de lame : un arc d'énergie colorée qui balaie la cible (shader à défilement d'UV).
static func arc_slash(parent: Node3D, pos: Vector3, c: Color, crit := false, duration := 0.3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = arc_mesh()
	var m := ShaderMaterial.new()
	m.shader = TRAIL_SHADER
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("energy", 3.0 if crit else 2.2)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation = Vector3(randf_range(-0.3, 0.3), randf_range(-0.4, 0.4), randf_range(-1.1, 1.1) + (PI if randf() < 0.5 else 0.0))
	mi.scale = Vector3.ONE * (1.25 if crit else 0.95)
	parent.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("progress", v), 0.0, 1.6, duration)
	tw.tween_callback(mi.queue_free)


## Tornade (sorts de zone de Yass Ming, souffles) : entonnoir en spirale qui monte puis s'efface.
static func tornado(parent: Node3D, pos: Vector3, c: Color, duration := 1.1, height := 3.2, radius := 1.1) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 24
	cyl.rings = 10
	cyl.cap_top = false
	cyl.cap_bottom = false
	mi.mesh = cyl
	var m := ShaderMaterial.new()
	m.shader = TORNADO_SHADER
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("intensity", 0.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3(0, height * 0.5, 0)
	parent.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("intensity", v), 0.0, 1.0, duration * 0.25)
	tw.tween_interval(duration * 0.45)
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("intensity", v), 1.0, 0.0, duration * 0.3)
	tw.tween_callback(mi.queue_free)
	burst(parent, pos + Vector3(0, 0.3, 0), c, 18, 3.0, 0.07, 0.9, true)


## Orbe de pouvoir (sorts de zone) : sphère lumineuse qui gonfle puis éclate.
static func orb(parent: Node3D, pos: Vector3, c: Color, duration := 0.6, radius := 0.9) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	mi.mesh = sm
	var mat := glow_material(c.lightened(0.2), 3.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.55
	mi.material_override = mat
	mi.position = pos
	mi.scale = Vector3.ONE * 0.1
	parent.add_child(mi)
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * radius, duration * 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration * 0.4).set_delay(duration * 0.6)
	tw.chain().tween_callback(mi.queue_free)
	parent.get_tree().create_timer(duration * 0.6).timeout.connect(func() -> void:
		if is_instance_valid(parent):
			burst(parent, pos, c, 26, 5.0, 0.08, 0.5))


## Impact d'un coup : gerbe d'étincelles à la couleur du lanceur et éclair d'impact très court.
static func impact(parent: Node3D, pos: Vector3, c: Color, crit := false) -> void:
	burst(parent, pos, c.lightened(0.25), 30 if crit else 16, 6.5 if crit else 4.5, 0.06, 0.35)
	var star := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	star.mesh = q
	var mat := flat_material(Color(1, 1, 1, 0.95), true)
	mat.albedo_texture = disc_texture()
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	star.material_override = mat
	star.position = pos
	star.scale = Vector3.ONE * 0.2
	parent.add_child(star)
	var size := 2.2 if crit else 1.4
	var tw := star.create_tween().set_parallel()
	tw.tween_property(star, "scale", Vector3.ONE * size, 0.07)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.12).set_delay(0.05)
	tw.chain().tween_callback(star.queue_free)


## Rupture : explosion de cristaux brisés or et orange qui jaillissent de la cible.
static func crystal_break(parent: Node3D, pos: Vector3) -> void:
	if _shard_mesh == null:
		var pm := PrismMesh.new()
		pm.size = Vector3(0.12, 0.32, 0.08)
		_shard_mesh = pm
	for c: Color in [Color("ffd060"), Color("ff8a2a")]:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.emitting = true
		p.explosiveness = 1.0
		p.amount = 22
		p.lifetime = 0.9
		p.position = pos
		p.mesh = _shard_mesh
		var mat := glow_material(c, 2.5)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		p.material_override = mat
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.4
		p.direction = Vector3(0, 1, 0)
		p.spread = 180.0
		p.initial_velocity_min = 4.0
		p.initial_velocity_max = 8.0
		p.gravity = Vector3(0, -9.0, 0)
		p.angular_velocity_min = -720.0
		p.angular_velocity_max = 720.0
		p.angle_max = 360.0
		var g := Gradient.new()
		g.set_color(0, Color(c, 1.0))
		g.set_color(1, Color(c, 0.0))
		p.color_ramp = g
		var curve := Curve.new()
		curve.max_value = 1.5
		curve.add_point(Vector2(0, 1.4))
		curve.add_point(Vector2(1, 0.4))
		p.scale_amount_curve = curve
		parent.add_child(p)
		parent.get_tree().create_timer(1.3).timeout.connect(p.queue_free)
	impact(parent, pos, Color("ffd060"), true)


## Aura au sol de l'unité qui s'apprête à jouer (dans son cercle).
static func aura(c: Color, radius := 0.6) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = AURA_SHADER
	m.set_shader_parameter("color", c)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.03
	return mi


## Colonne céleste / jugement solaire (Noor-El, Don Selah, Mikhaïla, Chronophage, Serpent) :
## faisceau vertical + anneaux runiques ascendants + gerbe dorée.
static func solar_pillar(parent: Node3D, pos: Vector3, c: Color, duration := 0.85, radius := 0.85) -> void:
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.75
	cyl.bottom_radius = radius
	cyl.height = 6.5
	cyl.radial_segments = 20
	cyl.cap_top = false
	cyl.cap_bottom = false
	beam.mesh = cyl
	var mat := glow_material(c.lightened(0.3), 3.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.65
	beam.material_override = mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = pos + Vector3(0, 3.25, 0)
	beam.scale = Vector3(0.1, 1.0, 0.1)
	parent.add_child(beam)
	var tw := beam.create_tween().set_parallel()
	tw.tween_property(beam, "scale", Vector3(1.15, 1.0, 1.15), duration * 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration * 0.55).set_delay(duration * 0.35)
	tw.chain().tween_callback(beam.queue_free)
	for i in 2:
		var ring := flat_ring(c.lightened(0.35), radius * (1.15 + i * 0.25), 0.08, 3.0)
		ring.position = pos + Vector3(0, 0.15 + i * 0.4, 0)
		var rm: StandardMaterial3D = ring.material_override
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		parent.add_child(ring)
		var rt := ring.create_tween().set_parallel()
		rt.tween_property(ring, "position:y", pos.y + 2.8 + i * 0.9, duration * 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		rt.tween_property(rm, "albedo_color:a", 0.0, duration * 0.8)
		rt.chain().tween_callback(ring.queue_free)
	burst(parent, pos + Vector3(0, 0.4, 0), c.lightened(0.25), 22, 4.2, 0.08, duration * 0.9, true)


## Éruption cristalline / glaciale / tellurique (Ghost, Selene, Moussa, Wyrm, Géode) :
## pointes prismatiques qui jaillissent du sol en couronne autour de la cible.
static func crystal_eruption(parent: Node3D, pos: Vector3, c: Color, duration := 0.8) -> void:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var mat := glow_material(c.lightened(0.2), 2.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in 6:
		var a := TAU * i / 6.0 + randf_range(-0.2, 0.2)
		var spike := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.0
		cyl.bottom_radius = 0.22
		cyl.height = 1.65
		cyl.radial_segments = 6
		spike.mesh = cyl
		spike.material_override = mat
		spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spike.position = Vector3(cos(a) * 0.55, -0.6, sin(a) * 0.55)
		spike.rotation = Vector3(sin(a) * 0.32, 0.0, -cos(a) * 0.32)
		root.add_child(spike)
		var st := spike.create_tween()
		st.tween_property(spike, "position:y", 0.65, duration * 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var fade := root.create_tween()
	fade.tween_property(mat, "albedo_color:a", 0.0, duration * 0.45).set_delay(duration * 0.45)
	fade.tween_callback(root.queue_free)
	burst(parent, pos + Vector3(0, 0.6, 0), c.lightened(0.3), 20, 4.5, 0.08, duration * 0.8)


## Vortex gravitationnel / temporel / néant (Montana, Ezra, Jo Prince, Nyssa, Mohamed) :
## noyau d'encre noire entouré d'un halo qui se contracte avant d'imploser.
static func void_vortex(parent: Node3D, pos: Vector3, c: Color, duration := 0.8) -> void:
	var center := pos + Vector3(0, 1.0, 0)
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.1
	core.mesh = sm
	var cm := flat_material(INK)
	core.material_override = cm
	core.position = center
	core.scale = Vector3.ONE * 0.1
	parent.add_child(core)
	var shell := MeshInstance3D.new()
	shell.mesh = sm
	var smat := glow_material(c, 3.2)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color.a = 0.45
	shell.material_override = smat
	shell.position = center
	shell.scale = Vector3.ONE * 1.9
	parent.add_child(shell)
	var tw := core.create_tween().set_parallel()
	tw.tween_property(core, "scale", Vector3.ONE * 1.1, duration * 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(shell, "scale", Vector3.ONE * 0.2, duration * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(cm, "albedo_color:a", 0.0, duration * 0.35).set_delay(duration * 0.55)
	tw.tween_property(smat, "albedo_color:a", 0.0, duration * 0.35).set_delay(duration * 0.55)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(core):
			core.queue_free()
		if is_instance_valid(shell):
			shell.queue_free())
	shockwave(parent, pos, c, 2.6, duration * 0.75)


## Sillage d'élan au corps-à-corps : souffle de vitesse au sol et étincelles dans le dos de l'attaquant.
static func dash_trail(parent: Node3D, from: Vector3, to: Vector3, c: Color, duration := 0.25) -> void:
	shockwave(parent, from, c.lightened(0.25), 1.35, duration * 1.2)
	var mid := from.lerp(to, 0.45) + Vector3(0, 0.85, 0)
	burst(parent, mid, c.lightened(0.3), 10, 3.2, 0.06, duration * 1.1)
