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
var promos: Array[Node3D] = []      # pièces de promotion préparées à l'avance
var flash_lights: Array[OmniLight3D] = []
var reveal_model: CharacterModel = null
var white: ColorRect                # flash plein écran
var cam_pos := Vector3.ZERO
var cam_look := Vector3.ZERO
var trauma := 0.0

const GAME_FONT := preload("res://assets/fonts/LilitaOne-Regular.ttf")


func _ready() -> void:
	results = Session.last_pulls.duplicate()
	if results.is_empty():  # aperçu hors invocation (outils de capture) ; -- --demo10 pour une x10
		results = [{"id": "montana", "rarity": 5, "new": true}]
		if "--demo10" in OS.get_cmdline_user_args():
			results.assign(Gacha.new("featured_montana", 3).pull_many(10))
	_build_world()
	_build_ui()
	_prepare()
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
	cam_pos = pos
	cam_look = look
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
	root.set_meta("mat", mat)
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
	var from_pos := cam_pos
	var from_look := cam_look
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(k: float) -> void:
		cam_pos = from_pos.lerp(pos, k)
		cam_look = from_look.lerp(look, k), 0.0, 1.0, t)
	await tw.finished


func _process(delta: float) -> void:
	trauma = maxf(0.0, trauma - delta * 2.0)
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * trauma * trauma * 0.3
	cam.position = cam_pos + shake
	cam.look_at(cam_look + shake * 0.3)


func _lane_of(r: Dictionary) -> String:
	var id: String = r["id"]
	return GameData.constellation_of(GameData.character(id)["nation"]) if GameData.characters().has(id) else "orion"


## Tout ce qui est lourd est préparé pendant le fondu d'entrée (pièces de promotion, lumières, personnage,
## matériaux) : le moment de la promotion ne fait plus que révéler des objets prêts. Pas de saccade.
func _prepare() -> void:
	var per_lane := {"orion": 0, "grande_ourse": 0, "sirius": 0}
	var single := results.size() == 1
	for i in results.size():
		var r: Dictionary = results[i]
		var rar: int = r["rarity"]
		var lane := _lane_of(r)
		var n: int = per_lane[lane]
		per_lane[lane] = n + 1
		var file := LANES.find(lane) * 3 + (1 if single else n % 3)
		var rank := 6 - (n / 3)  # au-delà de 3 pions dans un couloir : une rangée plus bas
		var pawn := _piece("pawn", Color(0, 0, 0, 0))
		pawn.position = _square(file, rank)
		pawn.visible = false
		add_child(pawn)
		pawns.append(pawn)
		var kind: String = PIECE_FOR.get(rar, "knight" if randf() < 0.5 else "bishop")
		var piece := _piece(kind, RARITY_GLOW[rar])
		piece.position = pawn.position + Vector3(0, 0, -1.0)
		piece.scale = Vector3.ONE * 0.001  # dessinée une fois, minuscule : ses matériaux sont prêts
		add_child(piece)
		promos.append(piece)
		var o := OmniLight3D.new()
		o.light_color = RARITY_GLOW[rar]
		o.omni_range = 3.0 + rar
		o.light_energy = 0.0
		o.position = piece.position + Vector3(0, 1.2, 0)
		add_child(o)
		flash_lights.append(o)
	if single and GameData.characters().has(results[0]["id"]):
		reveal_model = CharacterModel.new()
		add_child(reveal_model)
		reveal_model.setup(results[0]["id"], UiKit.char_color(results[0]["id"]), 1.75)
		reveal_model.position = promos[0].position + Vector3(0, -3.0, 0)  # sous le plateau, invisible
	# un éclat et une onde jetables pour compiler leurs matériaux maintenant plutôt qu'à la promotion
	BattleFx.burst(self, Vector3(0, -4, 0), Color.WHITE, 4, 1.0, 0.05, 0.2)
	BattleFx.shockwave(self, Vector3(0, -4, 0), Color.WHITE, 1.0, 0.2)


func _play() -> void:
	var single := results.size() == 1
	# 1. le plateau se révèle
	_cam_at(Vector3(0, 13, 12), Vector3(0, 0, -0.5))
	await _tween_cam(Vector3(0, 7.5, 7.5), Vector3(0, 0, -2.0), 1.3)
	# 2. les pions apparaissent sur l'avant-dernière case de leur couloir
	for i in pawns.size():
		var pawn := pawns[i]
		pawn.visible = true
		pawn.scale = Vector3.ONE * 0.01
		var tw := create_tween()
		tw.tween_property(pawn, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		BattleFx.burst(self, pawn.position + Vector3(0, 0.2, 0), Color.WHITE, 8, 1.5, 0.05, 0.4, true)
		_light_lane(_lane_of(results[i]))
		await _wait(0.12 if not single else 0.4)
	await _wait(0.35)
	# 3. l'avancée : les pions brillent de plus en plus à la couleur de leur rareté (anticipation)
	var focus := _square(4, 7)
	if single:
		focus = Vector3(pawns[0].position.x, 0, _square(0, 7).z)
	var adv := create_tween().set_parallel()
	for i in pawns.size():
		var target := pawns[i].position
		target.z -= 1.0  # une case en avant : la rangée de devant atteint la promotion
		adv.tween_property(pawns[i], "position", target, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		var mat: StandardMaterial3D = pawns[i].get_meta("mat")
		var rar: int = results[i]["rarity"]
		mat.emission_enabled = true
		mat.emission = RARITY_GLOW[rar] if rar >= 4 else Color(0.8, 0.85, 1.0)
		mat.emission_energy_multiplier = 0.0
		adv.tween_property(mat, "emission_energy_multiplier", 0.25 + 0.35 * (rar - 3), 1.2)
	_tween_cam(focus + Vector3(0, 2.8 if single else 5.0, 4.0 if single else 6.5), focus + Vector3(0, 0.6, 0), 1.25)
	if not skip_requested:
		await adv.finished
	# 4. la tension : le pion du meilleur tirage tremble avant de se transformer
	var best := 0
	for r: Dictionary in results:
		best = maxi(best, int(r["rarity"]))
	if best >= 4 and not skip_requested:
		var shake_t := 0.7 if best == 5 else 0.35
		for i in pawns.size():
			if int(results[i]["rarity"]) == best:
				_tremble(pawns[i], shake_t)
		await _wait(shake_t)
	# 5. la promotion : flash, onde, gerbe, rebond — la pièce dit la rareté
	for i in results.size():
		var rar: int = results[i]["rarity"]
		await _promote(i, rar, single)
		await _wait(0.1 if not single else (0.0 if rar == 5 else 0.35))
	# 6. l'apparition
	if single:
		await _reveal(results[0], promos[0])
	else:
		await _wait(1.0 if best == 5 else 0.6)
	_finish()


func _tremble(n: Node3D, t: float) -> void:
	var base := n.position
	var tw := create_tween()
	var steps := int(t / 0.04)
	for k in steps:
		var amp := 0.02 + 0.05 * float(k) / steps  # de plus en plus fort
		tw.tween_property(n, "position", base + Vector3(randf_range(-amp, amp), 0, randf_range(-amp, amp)), 0.04)
	tw.tween_property(n, "position", base, 0.04)


func _promote(i: int, rar: int, single: bool) -> void:
	var pawn := pawns[i]
	var piece := promos[i]
	piece.position = pawn.position
	pawn.visible = false
	var power := 1.0 if single else 0.35
	var col: Color = RARITY_GLOW[rar]
	# flash plein écran (doré pour un Légendaire)
	white.color = Color(col.lightened(0.5) if rar == 5 else Color(1, 1, 1), 0.85 * power if single else 0.25)
	create_tween().tween_property(white, "color:a", 0.0, 0.35 if rar < 5 else 0.6)
	var o: OmniLight3D = flash_lights[i]
	o.position = piece.position + Vector3(0, 1.2, 0)
	var lt := create_tween()
	lt.tween_property(o, "light_energy", (4.0 + rar * 3.0) * power, 0.1)
	lt.tween_property(o, "light_energy", (1.2 if rar == 5 else 0.0) * power, 0.8 + rar * 0.2)
	BattleFx.shockwave(self, piece.position, col, 1.6 + rar * 0.5, 0.6)
	BattleFx.burst(self, piece.position + Vector3(0, 0.6, 0), col, 18 + rar * 8 if single else 10, 3.0 + rar * 0.4, 0.08, 0.7)
	trauma = minf(1.0, trauma + (0.25 + 0.15 * (rar - 3)) * (1.0 if single else 0.5))
	piece.scale = Vector3.ONE * 0.4
	var tw := create_tween()
	tw.tween_property(piece, "scale", Vector3.ONE * (1.3 if rar == 5 else 1.08), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(piece, "scale", Vector3.ONE * (1.2 if rar == 5 else 1.0), 0.15)
	if rar == 5:
		_legendary(piece, single)
		if single:
			await _wait(1.6)


## Légendaire : colonne de lumière dorée, étincelles qui montent, la caméra tourne autour de la dame.
func _legendary(piece: Node3D, single: bool) -> void:
	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.55
	cyl.height = 1.0
	pillar.mesh = cyl
	var pm := BattleFx.glow_material(RARITY_GLOW[5], 3.0)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.albedo_color = Color(RARITY_GLOW[5], 0.45)
	pillar.material_override = pm
	pillar.position = piece.position + Vector3(0, 0.5, 0)
	pillar.scale = Vector3(1, 0.01, 1)
	add_child(pillar)
	var tw := create_tween()
	tw.tween_property(pillar, "scale", Vector3(1, 14, 1), 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pillar, "position:y", piece.position.y + 7.0, 0.35)
	tw.tween_property(pm, "albedo_color:a", 0.0, 1.4)
	tw.parallel().tween_property(pillar, "scale:x", 0.2, 1.4)
	tw.parallel().tween_property(pillar, "scale:z", 0.2, 1.4)
	tw.tween_callback(pillar.queue_free)
	for k in 3:
		get_tree().create_timer(0.2 * k).timeout.connect(func() -> void:
			BattleFx.burst(self, piece.position + Vector3(0, 0.3, 0), Color("ffe08a"), 16, 2.5, 0.07, 1.4, true))
	var spin := create_tween()
	spin.tween_property(piece, "rotation_degrees:y", 360.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if single:  # la caméra tourne autour de la dame
		var c := piece.position
		var orbit := create_tween()
		orbit.tween_method(func(a: float) -> void:
			cam_pos = c + Vector3(sin(a) * 3.2, 1.8, cos(a) * 3.2)
			cam_look = c + Vector3(0, 0.9, 0), -0.6, 0.6, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _light_lane(lane: String) -> void:
	var l: Dictionary = lane_lights[lane]
	var tw := create_tween().set_parallel()
	tw.tween_property(l["spot"], "light_energy", 6.0, 0.4)
	tw.tween_property(l["strip"], "emission_energy_multiplier", 1.4, 0.4)


func _reveal(r: Dictionary, piece: Node3D) -> void:
	if reveal_model == null:
		return
	var m := reveal_model
	var rar: int = r["rarity"]
	m.position = piece.position + Vector3(0, -1.9, 0)
	m.rotation_degrees.y = -360.0
	m.play("victory")
	var tw := create_tween().set_parallel()
	tw.tween_property(piece, "scale", Vector3.ONE * 0.01, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(m, "position", piece.position + Vector3(0, 0.05, 0), 0.8 if rar == 5 else 0.55) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "rotation_degrees:y", 0.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	BattleFx.burst(self, piece.position + Vector3(0, 0.4, 0), RARITY_GLOW[rar], 30, 3.0, 0.08, 1.0, true)
	BattleFx.shockwave(self, piece.position, RARITY_GLOW[rar], 3.0, 0.8)
	m.flash(Color(RARITY_GLOW[rar], 0.8), 0.7)
	_tween_cam(piece.position + Vector3(0, 1.5, 3.6), piece.position + Vector3(0, 1.0, 0), 0.9)
	_name_card(r)
	await _wait(1.7 if rar == 5 else 1.2)


## Carte de présentation qui glisse : rareté, nom, étoiles.
func _name_card(r: Dictionary) -> void:
	var rar: int = r["rarity"]
	var col: Color = UiKit.RARITY_COLORS[rar]
	var box := VBoxContainer.new()
	box.position = Vector2(-520, 310)
	ui.add_child(box)
	box.add_child(UiKit.portrait(r["id"], 150))
	var rl := UiKit.label(["", "", "", "RARE", "ÉPIQUE", "LÉGENDAIRE"][rar], 22, col)
	rl.add_theme_font_override("font", GAME_FONT)
	box.add_child(rl)
	var nl := UiKit.label(UiKit.char_name(r["id"]), 46, Color.WHITE)
	nl.add_theme_font_override("font", GAME_FONT)
	nl.add_theme_constant_override("outline_size", 10)
	nl.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.08))
	box.add_child(nl)
	box.add_child(UiKit.label("★".repeat(rar) + ("   NOUVEAU !" if r.get("new", false) else ""), 24, col))
	var tw := create_tween()
	tw.tween_property(box, "position:x", 60.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- Interface ---------------------------------------------------------------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	white = ColorRect.new()
	white.set_anchors_preset(Control.PRESET_FULL_RECT)
	white.color = Color(1, 1, 1, 0)
	white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(white)
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
	var sorted := results.duplicate()  # les meilleurs tirages d'abord
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["rarity"]) > int(b["rarity"]))
	for k in sorted.size():
		var r: Dictionary = sorted[k]
		var rar: int = r["rarity"]
		var col: Color = UiKit.RARITY_COLORS[rar]
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UiKit.panel_style(Color(col, 0.22), col, 3 if r.get("new", false) else 1))
		p.custom_minimum_size = Vector2(200, 76)
		var tail := "NOUVEAU !" if r.get("new", false) else "%s +%d" % [UiKit.bb("fragments_etage", 15, col), int(r.get("fragments", 0))]
		var l := UiKit.rich("[center]%s\n%s\n%s[/center]" % ["★".repeat(rar), UiKit.char_name(r["id"]), tail], 15, col)
		l.custom_minimum_size.x = 190
		p.add_child(l)
		grid.add_child(p)
		# les cartes apparaissent une à une avec un rebond
		p.scale = Vector2.ZERO
		p.resized.connect(func() -> void: p.pivot_offset = p.size / 2.0)
		var tw := p.create_tween()
		tw.tween_interval(0.05 * k)
		tw.tween_property(p, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var back := "res://scenes/prologue.tscn" if Session.profile.in_prologue() else "res://scenes/summon.tscn"
	row.add_child(UiKit.button("Continuer", func() -> void: get_tree().change_scene_to_file(back), Vector2(200, 50)))
