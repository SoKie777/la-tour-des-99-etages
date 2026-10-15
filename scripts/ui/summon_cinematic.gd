extends Node3D
## Cinématique d'invocation (fiche, partie 3) : un plateau d'échecs en marbre, trois couloirs aux couleurs
## des constellations. Chaque tirage est un pion blanc posé sur l'avant-dernière case du couloir de sa
## constellation ; il avance jusqu'à la promotion et devient cavalier ou fou (Rare), tour (Épique) ou dame
## (Légendaire), puis le personnage sort de la pièce. Résultats : Session.last_pulls. « Passer » saute tout.

const FILES := 9   # 3 colonnes par couloir
const RANKS := 8
const LANES := ["orion", "grande_ourse", "sirius"]
const LANE_COLORS := {"orion": Color("7fc8ff"), "grande_ourse": Color("d0242c"), "sirius": Color("f2dc9a")}
const RARITY_GLOW := {3: Color("9fb6d8"), 4: Color("b07de0"), 5: Color("ffcf4a")}
const PIECE_FOR := {4: "rook", 5: "queen"}

var results: Array = []
var cam: Camera3D
var lane_lights := {}
var pawns: Array[Node3D] = []
var ui: CanvasLayer
var done := false
var skip_requested := false
var marble_white: StandardMaterial3D
var marble_black: StandardMaterial3D


func _ready() -> void:
	results = Session.last_pulls.duplicate()
	if results.is_empty():  # aperçu hors invocation (outils de capture) ; -- --demo10 pour une x10
		results = [{"id": "montana", "rarity": 5, "new": true}]
		if "--demo10" in OS.get_cmdline_user_args():
			results.assign(Gacha.new("featured_montana", 3).pull_many(10))
	_build_world()
	_build_ui()
	_play()


# --- Monde -------------------------------------------------------------------

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("07060c")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.24, 0.3)
	e.ambient_light_energy = 0.5
	e.glow_enabled = true
	e.glow_intensity = 1.1
	e.glow_bloom = 0.15
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()  # lumière dramatique rasante
	key.rotation_degrees = Vector3(-28, 35, 0)
	key.light_energy = 0.55
	key.shadow_enabled = true
	add_child(key)
	marble_white = _marble(Color(0.9, 0.88, 0.84))
	marble_black = _marble(Color(0.07, 0.07, 0.09))
	for f in FILES:
		for r in RANKS:
			var tile := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.98, 0.2, 0.98)
			tile.mesh = box
			tile.material_override = marble_white if (f + r) % 2 == 0 else marble_black
			tile.position = _square(f, r) - Vector3(0, 0.1, 0)
			add_child(tile)
	var frame := MeshInstance3D.new()  # cadre du plateau
	var fb := BoxMesh.new()
	fb.size = Vector3(FILES + 0.6, 0.3, RANKS + 0.6)
	frame.mesh = fb
	frame.material_override = _marble(Color(0.16, 0.13, 0.1))
	frame.position = Vector3(0, -0.2, 0)
	add_child(frame)
	for i in LANES.size():
		var lane: String = LANES[i]
		var col: Color = LANE_COLORS[lane]
		var strip := MeshInstance3D.new()  # liseré lumineux du couloir
		var sb := BoxMesh.new()
		sb.size = Vector3(3.0, 0.02, RANKS)
		strip.mesh = sb
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(col, 0.08)
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.emission_enabled = true
		sm.emission = col
		sm.emission_energy_multiplier = 0.15
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		strip.material_override = sm
		strip.position = Vector3((i - 1) * 3.0, 0.012, 0)
		add_child(strip)
		var spot := SpotLight3D.new()
		spot.light_color = col
		spot.light_energy = 0.6
		spot.spot_range = 14.0
		spot.spot_angle = 22.0
		spot.position = Vector3((i - 1) * 3.0, 9.0, -1.0)
		spot.rotation_degrees = Vector3(-90, 0, 0)
		add_child(spot)
		lane_lights[lane] = {"spot": spot, "strip": sm}
	cam = Camera3D.new()
	cam.fov = 48
	add_child(cam)
	_cam_at(Vector3(0, 12, 13), Vector3(0, 0, 0))


func _marble(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.18
	m.metallic_specular = 0.8
	return m


## Centre d'une case : colonnes 0..8 (gauche à droite), rangées 0..7 (du joueur vers le fond).
func _square(file: int, rank: int) -> Vector3:
	return Vector3(file - (FILES - 1) / 2.0, 0.0, (RANKS - 1) / 2.0 - rank)


func _cam_at(pos: Vector3, look: Vector3) -> void:
	cam.position = pos
	cam.look_at(look)


# --- Pièces (formes simples en marbre) ---------------------------------------

func _piece(kind: String, glow: Color) -> Node3D:
	var root := Node3D.new()
	var mat := marble_white.duplicate()
	if glow.a > 0.0:
		mat.emission_enabled = true
		mat.emission = glow
		mat.emission_energy_multiplier = 0.35 if glow == RARITY_GLOW[5] else 0.12
	var add := func(mesh: Mesh, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = pos
		mi.rotation_degrees = rot
		mi.scale = scl
		root.add_child(mi)
	add.call(_cyl(0.32, 0.34, 0.12), Vector3(0, 0.06, 0))
	match kind:
		"pawn":
			add.call(_cyl(0.12, 0.22, 0.45), Vector3(0, 0.34, 0))
			add.call(_cyl(0.2, 0.2, 0.05), Vector3(0, 0.56, 0))
			add.call(_sph(0.17), Vector3(0, 0.74, 0))
		"knight":
			add.call(_cyl(0.16, 0.26, 0.5), Vector3(0, 0.37, 0))
			add.call(_box(Vector3(0.24, 0.5, 0.36)), Vector3(0, 0.82, 0.02), Vector3(-18, 0, 0))
			add.call(_box(Vector3(0.2, 0.2, 0.34)), Vector3(0, 0.88, 0.22), Vector3(15, 0, 0))
			add.call(_box(Vector3(0.06, 0.16, 0.08)), Vector3(0, 1.1, -0.05))
		"bishop":
			add.call(_cyl(0.12, 0.25, 0.6), Vector3(0, 0.42, 0))
			add.call(_cyl(0.21, 0.21, 0.05), Vector3(0, 0.74, 0))
			add.call(_sph(0.17), Vector3(0, 0.95, 0), Vector3.ZERO, Vector3(1, 1.45, 1))
			add.call(_sph(0.055), Vector3(0, 1.22, 0))
		"rook":
			add.call(_cyl(0.24, 0.29, 0.75), Vector3(0, 0.49, 0))
			add.call(_cyl(0.32, 0.3, 0.16), Vector3(0, 0.94, 0))
			for k in 4:
				var a := k * PI / 2.0
				add.call(_box(Vector3(0.14, 0.14, 0.14)), Vector3(cos(a) * 0.22, 1.09, sin(a) * 0.22))
		"queen":
			add.call(_cyl(0.13, 0.28, 0.9), Vector3(0, 0.57, 0))
			add.call(_cyl(0.24, 0.24, 0.06), Vector3(0, 1.04, 0))
			add.call(_cyl(0.26, 0.15, 0.22), Vector3(0, 1.18, 0))
			for k in 8:
				var a := k * TAU / 8.0
				add.call(_sph(0.05), Vector3(cos(a) * 0.24, 1.3, sin(a) * 0.24))
			add.call(_sph(0.09), Vector3(0, 1.38, 0))
			add.call(_sph(0.045), Vector3(0, 1.5, 0))
	return root


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 24
	return m


func _sph(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return m


func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


# --- Déroulement -------------------------------------------------------------

func _wait(t: float) -> void:
	if skip_requested:
		return
	await get_tree().create_timer(t).timeout


func _tween_cam(pos: Vector3, look: Vector3, t: float) -> void:
	if skip_requested:
		return
	var from_pos := cam.position
	var from_look := cam.position + (-cam.global_transform.basis.z) * 10.0
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(k: float) -> void:
		_cam_at(from_pos.lerp(pos, k), from_look.lerp(look, k)), 0.0, 1.0, t)
	await tw.finished


func _lane_of(r: Dictionary) -> String:
	var id: String = r["id"]
	return GameData.constellation_of(GameData.character(id)["nation"]) if GameData.characters().has(id) else "orion"


func _play() -> void:
	var single := results.size() == 1
	# 1. le plateau se révèle
	_cam_at(Vector3(0, 13, 12), Vector3(0, 0, -0.5))
	await _tween_cam(Vector3(0, 7.5, 7.5), Vector3(0, 0, -2.0), 1.3)
	# 2. les pions sur l'avant-dernière case de leur couloir
	var per_lane := {"orion": 0, "grande_ourse": 0, "sirius": 0}
	for i in results.size():
		var r: Dictionary = results[i]
		var lane := _lane_of(r)
		var li := LANES.find(lane)
		var n: int = per_lane[lane]
		per_lane[lane] = n + 1
		var file := li * 3 + (1 if single else n % 3)
		var rank := 6 - (n / 3)  # au-delà de 3 pions dans un couloir : une rangée plus bas
		var pawn := _piece("pawn", Color(0, 0, 0, 0))
		pawn.position = _square(file, rank)
		pawn.scale = Vector3.ONE * 0.01
		add_child(pawn)
		pawns.append(pawn)
		var tw := create_tween()
		tw.tween_property(pawn, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_light_lane(lane)
		await _wait(0.12 if not single else 0.4)
	await _wait(0.4)
	# 3. l'avancée vers la promotion (dernière rangée)
	var focus := _square(4, 7)
	if single:
		focus = Vector3(pawns[0].position.x, 0, _square(0, 7).z)
	var adv := create_tween().set_parallel()
	for i in pawns.size():
		var target := pawns[i].position
		target.z -= 1.0  # une case en avant : la rangée de devant atteint la promotion
		adv.tween_property(pawns[i], "position", target, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_tween_cam(focus + Vector3(0, 3.0 if single else 5.0, 4.2 if single else 6.5), focus + Vector3(0, 0.6, 0), 1.2)
	if not skip_requested:
		await adv.finished
	await _wait(0.25)
	# 4. la promotion : la pièce dit la rareté
	var best := 0
	for i in results.size():
		var r: Dictionary = results[i]
		var rar: int = r["rarity"]
		best = maxi(best, rar)
		var kind: String = PIECE_FOR.get(rar, "knight" if randf() < 0.5 else "bishop")
		var piece := _piece(kind, RARITY_GLOW[rar])
		piece.position = pawns[i].position
		add_child(piece)
		pawns[i].queue_free()
		pawns[i] = piece
		_flash(piece.position, RARITY_GLOW[rar], rar, 1.0 if single else 0.3)
		piece.scale = Vector3.ONE * 0.6
		var tw := create_tween()
		tw.tween_property(piece, "scale", Vector3.ONE * (1.25 if rar == 5 else 1.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if rar == 5:  # la dame tourne sur elle-même
			tw.parallel().tween_property(piece, "rotation_degrees:y", 360.0, 1.2)
		await _wait(0.12 if not single else (1.3 if rar == 5 else 0.6))
	# 5. l'apparition
	if single:
		await _reveal(results[0], pawns[0])
	else:
		await _wait(0.9 if best == 5 else 0.5)
	_finish()


func _light_lane(lane: String) -> void:
	var l: Dictionary = lane_lights[lane]
	var tw := create_tween().set_parallel()
	tw.tween_property(l["spot"], "light_energy", 6.0, 0.4)
	tw.tween_property(l["strip"], "emission_energy_multiplier", 1.4, 0.4)


func _flash(pos: Vector3, col: Color, rarity: int, power: float) -> void:
	var o := OmniLight3D.new()
	o.light_color = col
	o.omni_range = 3.0 + rarity
	o.position = pos + Vector3(0, 1.2, 0)
	o.light_energy = 0.0
	add_child(o)
	var tw := create_tween()
	tw.tween_property(o, "light_energy", (4.0 + rarity * 3.0) * power, 0.12)
	tw.tween_property(o, "light_energy", (1.0 if rarity == 5 else 0.0) * power, 0.8 + rarity * 0.2)


func _reveal(r: Dictionary, piece: Node3D) -> void:
	var id: String = r["id"]
	if not GameData.characters().has(id):
		return
	var m := CharacterModel.new()
	add_child(m)
	m.setup(id, UiKit.char_color(id), 1.75)
	m.position = piece.position + Vector3(0, -1.8, 0)
	m.rotation_degrees.y = 0.0
	m.play("victory")
	var tw := create_tween().set_parallel()
	tw.tween_property(piece, "scale", Vector3.ONE * 0.01, 0.5)
	tw.tween_property(m, "position", piece.position + Vector3(0, 0.05, 0), 0.9 if r["rarity"] == 5 else 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween_cam(piece.position + Vector3(0, 1.5, 3.6), piece.position + Vector3(0, 1.0, 0), 0.9)
	await _wait(1.6 if r["rarity"] == 5 else 1.1)


# --- Interface ---------------------------------------------------------------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var skip := UiKit.button("Passer", func() -> void:
		skip_requested = true
		_finish(), Vector2(120, 44))
	skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip.position = Vector2(-140, 16)
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	ui.add_child(skip)


func _finish() -> void:
	if done:
		return
	done = true
	var center := CenterContainer.new()
	if results.size() == 1:  # le personnage reste visible : la carte se place en bas
		center.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		center.offset_top = -200
		center.offset_bottom = -12
	else:
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(UiKit.BG, 0.88), UiKit.ACCENT, 2, 10))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var grid := GridContainer.new()
	grid.columns = mini(5, results.size())
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for r: Dictionary in results:
		var rar: int = r["rarity"]
		var col: Color = UiKit.RARITY_COLORS[rar]
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UiKit.panel_style(Color(col, 0.22), col, 3 if r.get("new", false) else 1))
		p.custom_minimum_size = Vector2(200, 76)
		var tail := "NOUVEAU !" if r.get("new", false) else "+%d Fragments" % int(r.get("fragments", 0))
		var l := UiKit.label("%s\n%s\n%s" % [["", "", "", "Rare", "Épique", "Légendaire"][rar], UiKit.char_name(r["id"]), tail], 15, col)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.add_child(l)
		grid.add_child(p)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	row.add_child(UiKit.button("Continuer", func() -> void: get_tree().change_scene_to_file("res://scenes/summon.tscn"), Vector2(200, 50)))
