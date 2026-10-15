class_name BattleFx
extends RefCounted
## Effets visuels du combat : arène, étincelles d'impact, anneaux lumineux, barres de vie 3D.
## Formes simples et particules CPU : légères pour le mobile.


## Ciel, brume, lumières et arène (plateforme de marbre, anneau de runes, piliers aux cristaux).
static func build_arena(parent: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("0d0a1c")
	sm.sky_horizon_color = Color("3a2a5c")
	sm.ground_bottom_color = Color("05040a")
	sm.ground_horizon_color = Color("2a1f45")
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("8a86b0")
	e.ambient_light_energy = 0.55
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.03
	e.fog_enabled = true
	e.fog_light_color = Color("2c2148")
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
	rim.light_color = Color("7f8cff")
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
	pm.albedo_color = Color("2a2638")
	pm.roughness = 0.6
	pm.metallic_specular = 0.3
	plat.material_override = pm
	parent.add_child(plat)
	for r in [5.6, 6.6]:
		var ring := flat_ring(Color("c9a24a"), r, 0.05 if r < 6 else 0.03, 1.2)
		ring.position.y = 0.01
		parent.add_child(ring)
	var colors := [Color("7fc8ff"), Color("d0242c"), Color("f2dc9a")]
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
		stone.albedo_color = Color("1c1828")
		pillar.material_override = stone
		parent.add_child(pillar)
		var crystal := MeshInstance3D.new()
		var pr := PrismMesh.new()
		pr.size = Vector3(0.5, 0.9, 0.5)
		crystal.mesh = pr
		crystal.position = p + Vector3(0, 7.6, 0)
		crystal.material_override = glow_material(colors[i % 3], 2.5)
		parent.add_child(crystal)
		var l := OmniLight3D.new()
		l.light_color = colors[i % 3]
		l.light_energy = 1.2
		l.omni_range = 6.0
		l.position = crystal.position
		parent.add_child(l)
	var dust := CPUParticles3D.new()  # poussière lumineuse en suspension
	dust.amount = 60
	dust.lifetime = 8.0
	dust.preprocess = 8.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(9, 3, 3.5)
	dust.position = Vector3(0, 3, -4.5)  # loin de la caméra : pas de gros carrés au premier plan
	dust.direction = Vector3(0, 1, 0)
	dust.spread = 180.0
	dust.initial_velocity_min = 0.05
	dust.initial_velocity_max = 0.2
	dust.gravity = Vector3.ZERO
	dust.mesh = _quad(0.04)
	dust.material_override = glow_material(Color("e6d3ff"), 1.5, true)
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
