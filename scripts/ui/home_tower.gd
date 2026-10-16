class_name HomeTower
## Écran d'accueil en 3D : l'équipe, de dos au pied de la Tour des 99 Étages, lève les yeux vers une tour
## qui se perd dans les nuages. La caméra, basse, regarde vers le haut. anchor(n) donne un point de la
## façade à l'étage n (pour y accrocher les libellés des modes).

const FLOORS := 44
const FLOOR_H := 3.4
const BASE_R := 8.0
const TOWER_Z := -34.0
const STONE := Color("2b2140")
const ROOF := Color("4a1f2c")
const GOLD := Color("d1ad62")

static var _rng := RandomNumberGenerator.new()


## Construit la scène sous parent ; renvoie la caméra.
static func build(parent: Node3D, team: Array) -> Camera3D:
	_rng.seed = 99
	_environment(parent)
	_ground(parent)
	_tower(parent)
	_sky_props(parent)
	_team(parent, team)
	var cam := Camera3D.new()
	cam.fov = 58.0
	parent.add_child(cam)
	cam.look_at_from_position(Vector3(0.3, 0.7, 7.6), Vector3(0, 12.0, TOWER_Z))
	cam.current = true
	return cam


## Point de la façade (vers la caméra) à l'étage n, décalé de side (−1 gauche, +1 droite).
static func anchor(n: float, side := 0.0) -> Vector3:
	var y := n * FLOOR_H + 1.5
	var r := _radius(n)
	return Vector3(side * r * 1.05, y, TOWER_Z + r * (1.0 - absf(side) * 0.4))


static func _radius(n: float) -> float:
	return BASE_R * (1.0 - n / (FLOORS * 1.45))


static func _environment(parent: Node3D) -> void:
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("0d0818")
	sm.sky_horizon_color = Color("6b2846")
	sm.sky_curve = 0.12
	sm.ground_horizon_color = Color("3a1a30")
	sm.ground_bottom_color = Color("0d0818")
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("6a5a8a")
	e.ambient_light_energy = 0.55
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_strength = 1.1
	e.glow_bloom = 0.05
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.15
	e.adjustment_saturation = 1.2
	e.fog_enabled = true  # le haut de la tour se perd dans la brume
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = Color("4a2346")
	e.fog_density = 1.0
	e.fog_depth_begin = 45.0
	e.fog_depth_end = 160.0
	e.fog_depth_curve = 1.3
	e.fog_sky_affect = 0.0
	var env := WorldEnvironment.new()
	env.environment = e
	parent.add_child(env)
	var key := DirectionalLight3D.new()  # lumière de la lune, derrière la tour : contre-jour sur l'équipe
	key.rotation_degrees = Vector3(-28, 200, 0)
	key.light_energy = 1.1
	key.light_color = Color("ffb08a")
	key.shadow_enabled = true
	key.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	parent.add_child(key)
	var fill := DirectionalLight3D.new()  # lumière douce de face
	fill.rotation_degrees = Vector3(-35, 10, 0)
	fill.light_energy = 0.55
	fill.light_color = Color("b9a8ff")
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	parent.add_child(fill)


static func _ground(parent: Node3D) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	BattleDecor._mesh(parent, plane, BattleDecor._toon(Color("1a1226"), 0.0, 0.0), Vector3(0, 0, -60))
	# parvis : grandes dalles et marches jusqu'à la porte de la tour
	BattleDecor._mesh(parent, BattleDecor._cyl(BASE_R * 2.2, BASE_R * 2.3, 0.4, 48), BattleDecor._toon(Color("2a2038")), Vector3(0, 0.2, TOWER_Z))
	for k in 6:
		var w := 7.0 - k * 0.6
		BattleDecor._mesh(parent, BattleDecor._box(Vector3(w, 0.35, 1.4)), BattleDecor._toon(Color("33284a")),
			Vector3(0, 0.18 + k * 0.35, TOWER_Z + BASE_R * 1.9 - k * 1.3))
	var path := PlaneMesh.new()  # chemin d'or vers la tour
	path.size = Vector2(2.4, 30)
	BattleDecor._mesh(parent, path, BattleDecor._toon(Color(GOLD, 0.35), 0.6, 0.0), Vector3(0, 0.02, -10))
	for k in 8:  # lanternes de pierre le long du chemin
		var side := -1.0 if k % 2 == 0 else 1.0
		var z := -4.0 - (k / 2) * 7.0
		var base := Vector3(side * 3.2, 0, z)
		BattleDecor._mesh(parent, BattleDecor._cyl(0.18, 0.25, 1.4, 8), BattleDecor._toon(Color("3a3050")), base + Vector3(0, 0.7, 0))
		BattleDecor._mesh(parent, BattleDecor._box(Vector3(0.6, 0.5, 0.6)), BattleDecor._toon(Color("ffcf7a"), 2.5, 0.0), base + Vector3(0, 1.65, 0))
		BattleDecor._mesh(parent, BattleDecor._cyl(0.05, 0.55, 0.35, 4), BattleDecor._toon(Color("2a2038")), base + Vector3(0, 2.05, 0), Vector3(0, 45, 0))
		var l := OmniLight3D.new()
		l.position = base + Vector3(0, 1.7, 0)
		l.light_color = Color("ffbf6a")
		l.light_energy = 1.4
		l.omni_range = 5.0
		parent.add_child(l)


## La tour : étages octogonaux qui s'affinent, toits relevés liserés d'or, fenêtres allumées.
static func _tower(parent: Node3D) -> void:
	var stone := BattleDecor._toon(STONE, 0.0, 0.25)
	var roof := BattleDecor._toon(ROOF, 0.0, 0.3)
	var trim := BattleDecor._toon(GOLD, 0.8, 0.0)
	var win_x: Array[Transform3D] = []
	var win_c: Array[Color] = []
	for i in FLOORS:
		var r := _radius(i)
		var y := i * FLOOR_H
		BattleDecor._mesh(parent, BattleDecor._cyl(r * 0.97, r, FLOOR_H - 0.6, 8), stone, Vector3(0, y + (FLOOR_H - 0.6) / 2.0 + 0.4, TOWER_Z), Vector3(0, 22.5, 0))
		BattleDecor._mesh(parent, BattleDecor._cyl(r * 1.05, r * 1.42, 0.7, 8), roof, Vector3(0, y + FLOOR_H - 0.05, TOWER_Z), Vector3(0, 22.5, 0))
		var ring := TorusMesh.new()  # liseré d'or au bord du toit
		ring.inner_radius = r * 1.38
		ring.outer_radius = r * 1.46
		ring.rings = 8
		ring.ring_segments = 4
		BattleDecor._mesh(parent, ring, trim, Vector3(0, y + FLOOR_H - 0.4, TOWER_Z), Vector3(0, 22.5, 0))
		for f in 8:  # une fenêtre par face, pas toutes allumées
			if _rng.randf() < 0.35:
				continue
			var ang := TAU * f / 8.0
			var pos := Vector3(sin(ang) * r * 0.98, y + FLOOR_H * 0.5, TOWER_Z + cos(ang) * r * 0.98)
			var b := Basis(Vector3.UP, ang).scaled(Vector3(0.9, 1.4, 1))
			win_x.append(Transform3D(b, pos))
			win_c.append(Color("ffd27a") if _rng.randf() < 0.8 else Color("ff7a5a"))
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var wm := StandardMaterial3D.new()
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.vertex_color_use_as_albedo = true
	wm.emission_enabled = true
	wm.emission = Color("ffb84a")
	wm.emission_energy_multiplier = 1.4
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	BattleDecor._multi(parent, q, wm, win_x, win_c)
	# grande porte rouge au pied
	BattleDecor._mesh(parent, BattleDecor._box(Vector3(3.2, 4.2, 0.4)), BattleDecor._toon(Color("b83a35"), 0.5), Vector3(0, 2.5, TOWER_Z + BASE_R * 0.98))
	BattleDecor._mesh(parent, BattleDecor._box(Vector3(4.2, 0.4, 0.6)), trim, Vector3(0, 4.8, TOWER_Z + BASE_R * 1.0))


## Lune vermillon derrière la tour, étoiles, bancs de nuages autour des étages hauts.
static func _sky_props(parent: Node3D) -> void:
	BattleDecor._soft(parent, Color("ff5a3c"), 70.0, Vector3(26, 95, -140))
	var moon := BattleDecor._mesh(parent, BattleDecor._sphere(13.0), BattleDecor._toon(Color("e0483a"), 1.4, 0.0), Vector3(26, 95, -150))
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sx: Array[Transform3D] = []
	var sc: Array[Color] = []
	for k in 260:
		var p := Vector3(_rng.randf_range(-180, 180), _rng.randf_range(30, 220), _rng.randf_range(-230, -120))
		var s := _rng.randf_range(0.4, 1.3)
		sx.append(Transform3D(Basis.from_scale(Vector3(s, s, s)), p))
		sc.append(Color(1, 0.95, 0.85, _rng.randf_range(0.4, 1.0)))
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	BattleDecor._multi(parent, q, BattleDecor._dots(), sx, sc)
	var cloud := BattleDecor._toon(Color(0.42, 0.24, 0.42, 0.55), 0.15, 0.0)
	for band in [[52.0, 26.0], [78.0, 34.0], [110.0, 40.0]]:
		for k in 10:
			var ang := TAU * k / 10.0 + _rng.randf() * 0.4
			var d: float = band[1] * _rng.randf_range(0.7, 1.1)
			var c := BattleDecor._mesh(parent, BattleDecor._sphere(_rng.randf_range(6.0, 11.0)), cloud,
				Vector3(sin(ang) * d, float(band[0]) + _rng.randf_range(-3, 3), TOWER_Z + cos(ang) * d * 0.6))
			c.scale = Vector3(1.8, 0.45, 1.0)
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## L'équipe, de dos, regarde la tour.
static func _team(parent: Node3D, team: Array) -> void:
	for i in team.size():
		var m := CharacterModel.new()
		parent.add_child(m)
		var x := (i - (team.size() - 1) / 2.0) * 1.15
		m.position = Vector3(x, 0, 1.6 + absf(x) * 0.25)
		m.setup(team[i], UiKit.char_color(team[i]))
		m.rotation_degrees.y = 180.0 - x * 8.0  # de dos, tournés vers la tour
		m.play("idle")
	var ring := BattleFx.flat_ring(GOLD, 0.6 + team.size() * 0.55, 0.04, 1.2)
	ring.position = Vector3(0, 0.03, 1.8)
	parent.add_child(ring)
