class_name BattleFx
extends RefCounted
## Effets visuels du combat, direction artistique d'estampe ukiyo-e : arène au crépuscule (soleil rouge,
## nuages kumo, piliers laqués, lanternes), taches d'encre à l'impact, pétales de sakura, ondes à écume.
## Formes simples et particules CPU : légères pour le mobile.

const INK := Color("1c1618")
const SAKURA := Color("f29ab4")

static var _disc_tex: GradientTexture2D


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


## Ciel, brume, lumières et arène (plateforme de marbre, anneau de runes, piliers aux cristaux).
static func build_arena(parent: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("142342")  # bleu de Prusse
	sm.sky_horizon_color = Color("b8644a")  # crépuscule vermillon, comme chez Hiroshige
	sm.ground_bottom_color = Color("07060a")
	sm.ground_horizon_color = Color("3a2430")
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("a89ab0")
	e.ambient_light_energy = 0.55
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.03
	e.fog_enabled = true
	e.fog_light_color = Color("3b2a3a")
	e.fog_density = 0.018
	env.environment = e
	parent.add_child(env)
	var key := DirectionalLight3D.new()  # lumière principale de face : on voit le visage des ennemis
	key.rotation_degrees = Vector3(-42, 160, 0)
	key.light_energy = 1.15
	key.light_color = Color("fff1dc")
	key.shadow_enabled = true
	parent.add_child(key)
	var rim := DirectionalLight3D.new()  # contre-jour froid : détache les silhouettes
	rim.rotation_degrees = Vector3(-20, -20, 0)
	rim.light_energy = 0.6
	rim.light_color = Color("8fa6e8")
	parent.add_child(rim)
	var plat := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 7.0
	cyl.bottom_radius = 7.4
	cyl.height = 0.4
	cyl.radial_segments = 64
	plat.mesh = cyl
	plat.position.y = -0.2
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("2e211c")  # bois sombre
	pm.roughness = 0.6
	pm.metallic_specular = 0.3
	plat.material_override = pm
	parent.add_child(plat)
	for r in [5.6, 6.6]:
		var ring := flat_ring(Color("c9a24a"), r, 0.05 if r < 6 else 0.03, 1.2)
		ring.position.y = 0.01
		parent.add_child(ring)
	# grand soleil rouge et bandes de nuages kumo à l'horizon
	parent.add_child(_disc(Color("c4281f"), Vector2(9, 9), Vector3(7, 8, -60)))
	for k in 2:
		for j in 3:
			parent.add_child(_disc(Color("ece0c6", 0.75 - k * 0.2), Vector2(8.0 - j * 1.5, 0.7),
				Vector3(-12 + j * 11.0 + k * 5.0, 5.5 + k * 2.6 + (j % 2) * 0.4, -58)))
	var colors := [Color("ffb35c"), Color("ff7a4a"), Color("ffe0a0")]  # lanternes de papier
	for i in 8:
		var a := i * TAU / 8.0 + PI / 8.0
		var p := Vector3(cos(a) * 10.5, 0, sin(a) * 10.5)
		if p.z > 4.0:
			continue  # pas de pilier entre la caméra et l'arène
		var pillar := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.45
		pc.bottom_radius = 0.6
		pc.height = 7.0
		pillar.mesh = pc
		pillar.position = p + Vector3(0, 3.5, 0)
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color("4a1612")  # laque vermillon sombre (torii)
		pillar.material_override = stone
		parent.add_child(pillar)
		var crystal := MeshInstance3D.new()
		var pr := SphereMesh.new()  # lanterne de papier
		pr.radius = 0.4
		pr.height = 1.0
		crystal.mesh = pr
		crystal.position = p + Vector3(0, 7.6, 0)
		crystal.material_override = glow_material(colors[i % 3], 1.6)
		parent.add_child(crystal)
		var l := OmniLight3D.new()
		l.light_color = colors[i % 3]
		l.light_energy = 1.2
		l.omni_range = 6.0
		l.position = crystal.position
		parent.add_child(l)
	var dust := CPUParticles3D.new()  # pétales de sakura qui dérivent
	dust.amount = 50
	dust.lifetime = 8.0
	dust.preprocess = 8.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(9, 3, 3.5)
	dust.position = Vector3(0, 3, -4.5)  # loin de la caméra : pas de gros carrés au premier plan
	dust.direction = Vector3(1, -0.3, 0)
	dust.spread = 40.0
	dust.initial_velocity_min = 0.2
	dust.initial_velocity_max = 0.5
	dust.gravity = Vector3(0, -0.08, 0)
	dust.angle_max = 360.0
	dust.angular_velocity_min = -60.0
	dust.angular_velocity_max = 60.0
	var petal := QuadMesh.new()
	petal.size = Vector2(0.09, 0.055)
	dust.mesh = petal
	dust.color = SAKURA
	dust.material_override = flat_material(Color.WHITE, true)
	parent.add_child(dust)


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
	return {"root": root, "fill": fill_root, "shield": shield_root}


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
