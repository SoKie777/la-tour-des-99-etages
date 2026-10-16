extends Control
## Accueil : l'équipe, de dos au pied de la Tour des 99 Étages, lève les yeux vers elle (HomeTower).
## Les modes sont écrits en grand sur la tour, en police de jeu, comme les enseignes de Dislyte ;
## Équipe, Collection et réglages dans la barre du bas.

const GAME_FONT := preload("res://assets/fonts/LilitaOne-Regular.ttf")
const TEST_MATCHUPS := [["A – B", "A", "B"], ["B – C", "B", "C"], ["C – A", "C", "A"]]  # combats libres de test

var cam: Camera3D
var pinned: Array = []  # [Control, Vector3 du point d'accroche sur la tour, décalage écran]
var settings: PanelContainer
var reset_armed := false


func _ready() -> void:
	if Session.profile.in_prologue():  # nouvelle partie : le prologue d'abord, la Tour ensuite
		get_tree().change_scene_to_file.call_deferred("res://scenes/prologue.tscn")
		return
	theme = UiKit.theme()
	var world := Node3D.new()
	add_child(world)
	cam = HomeTower.build(world, Session.profile.team)
	var p := Session.profile
	p.refresh_energy(Session.now())

	var shade := TextureRect.new()  # bas d'écran assombri : lisibilité de la barre du bas
	var grad := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0.04, 0.02, 0.08, 0.85))
	grad.gradient = g
	grad.fill_from = Vector2(0, 0.6)
	grad.fill_to = Vector2(0, 1)
	shade.texture = grad
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var top := HBoxContainer.new()  # titre et monnaies
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 20
	top.offset_right = -20
	top.offset_top = 12
	add_child(top)
	var title := _neon("T99", 40, UiKit.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UiKit.currency_bar())

	# enseignes des modes, accrochées à la tour
	var next_floor := mini(p.tower_cleared + 1, Tower.floor_count())
	var asc := _sign("ASCENSION", 66, UiKit.ACCENT, _go.bind("tower"), -3.0)
	var sub := UiKit.rich("[center]%s %d   ·   %s  %d / %d[/center]" % [UiKit.bb("floor", 22, Color("fff1c4")), next_floor,
		Tower.floor_info(next_floor)["universe"], p.tower_cleared, Tower.floor_count()], 18, Color("fff1c4"))
	sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sub.offset_left = -200
	sub.offset_right = 200
	sub.offset_top = 2
	asc.add_child(sub)
	if p.energy >= int(GameData.progression()["energy"]["max"]) and p.tower_cleared < Tower.floor_count():
		UiKit.badge(asc, "MAX", "energie")
	_pin(asc, HomeTower.anchor(6.0), Vector2(0, 0))
	var summ := _sign("INVOCATION", 46, Color("c9a0ff"), _go.bind("summon"), 5.0)
	if p.amount("eclat_de_voeu") >= 10 * int(GameData.progression()["pull_cost"]):
		UiKit.badge(summ, "x10")
	_pin(summ, HomeTower.anchor(3.2, -1.0), Vector2(-190, 0))
	var loot := _sign("BOSS DE BUTIN", 42, Color("ff8a6a"), _go.bind("loot"), -5.0)
	_pin(loot, HomeTower.anchor(1.6, 1.0), Vector2(210, 0))

	var steps := Objectives.next_steps(p, Session.now())  # prochaine étape conseillée, en un geste
	if not steps.is_empty():
		var first: Dictionary = steps[0]
		var cont := UiKit.rich_button("CONTINUER  ›   " + UiKit.iconize(str(first["text"]), 20, Color("fff1c4")), _do_step.bind(first), Vector2(330, 56), 20, Color("fff1c4"))
		cont.add_theme_stylebox_override("normal", UiKit.panel_style(Color("4a3a12", 0.92), UiKit.ACCENT, 2, 28))
		cont.add_theme_stylebox_override("hover", UiKit.panel_style(Color("5c4818"), Color("ffe08a"), 3, 28))
		cont.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		cont.position = Vector2(24, -170)
		add_child(cont)
		cont.position.y = get_viewport_rect().size.y - 160

	var nav := HBoxContainer.new()  # barre du bas, façon Dislyte
	nav.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	nav.offset_left = 24
	nav.offset_right = -24
	nav.offset_top = -78
	nav.offset_bottom = -10
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 60)
	add_child(nav)
	nav.add_child(_sign("ÉQUIPE", 38, UiKit.PAPER, _go.bind("team"), 0.0))
	var coll := _sign("COLLECTION", 38, UiKit.PAPER, _go.bind("collection"), 0.0)
	if not p.unseen.is_empty():
		UiKit.badge(coll, "+%d" % p.unseen.size())
	nav.add_child(coll)
	var gear := UiKit.icon_button("info", _toggle_settings, 48)
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nav.add_child(gear)

	if not Session.grant_notes.is_empty():  # cadeau reçu : message affiché une fois
		var gift := UiKit.rich("+  %s 3 000   %s 300 000" % [UiKit.bb("eclat_de_voeu", 20, UiKit.ACCENT), UiKit.bb("pieces", 20, UiKit.ACCENT)], 17, UiKit.ACCENT)
		gift.position = Vector2(24, 70)
		add_child(gift)
		Session.grant_notes.clear()
	if Time.get_ticks_msec() > 60 * 60 * 1000:  # respect du temps : rappel discret après une heure
		var rest := UiKit.label("Tu joues depuis plus d'une heure : pense à faire une pause.", 13, Color("8fd8a0"))
		rest.position = Vector2(24, 100)
		add_child(rest)


func _process(_delta: float) -> void:
	if cam == null:
		return
	for e in pinned:  # les enseignes suivent leur point d'accroche sur la tour
		var c: Control = e[0]
		var at: Vector2 = cam.unproject_position(e[1]) + e[2]
		c.position = at - c.size / 2.0


func _pin(c: Control, at: Vector3, offset: Vector2) -> void:
	add_child(c)
	pinned.append([c, at, offset])


## Texte en police de jeu, contour d'encre et halo de couleur (néon).
func _neon(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", GAME_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", UiKit.INK.darkened(0.4))
	l.add_theme_constant_override("outline_size", maxi(8, size / 5))
	l.add_theme_color_override("font_shadow_color", Color(color, 0.55))
	l.add_theme_constant_override("shadow_outline_size", size / 2)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Enseigne cliquable : grand texte néon légèrement incliné, qui s'enfonce à l'appui.
func _sign(text: String, size: int, color: Color, cb: Callable, tilt: float) -> Button:
	var b := Button.new()
	b.flat = true
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	var l := _neon(text, size, color)
	b.add_child(l)
	l.resized.connect(func() -> void: b.custom_minimum_size = l.size)  # taille du texte une fois mis en page
	b.rotation_degrees = tilt
	b.pressed.connect(cb)
	UiKit.juice(b)
	b.resized.connect(func() -> void: b.pivot_offset = b.size / 2.0)
	return b


func _toggle_settings() -> void:
	if settings != null:
		settings.queue_free()
		settings = null
		return
	settings = PanelContainer.new()
	settings.add_theme_stylebox_override("panel", UiKit.panel_style(Color(UiKit.BG, 0.96), UiKit.ACCENT, 2, 10))
	settings.set_anchors_preset(Control.PRESET_CENTER)
	settings.offset_left = -220
	settings.offset_right = 220
	settings.offset_top = -150
	settings.offset_bottom = 150
	add_child(settings)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	settings.add_child(v)
	var row := HBoxContainer.new()
	v.add_child(row)
	for m in TEST_MATCHUPS:
		row.add_child(UiKit.button(m[0], _test_battle.bind(m[1], m[2]), Vector2(132, 40)))
	v.add_child(UiKit.button("Essayer le prologue (sans toucher à ta partie)", func() -> void:
		Session.start_trial()
		get_tree().change_scene_to_file("res://scenes/prologue.tscn"), Vector2(400, 40)))
	var reset := UiKit.button("Recommencer le profil", func() -> void: pass, Vector2(400, 40))
	reset.pressed.connect(func() -> void:
		if not reset_armed:
			reset_armed = true
			reset.text = "Confirmer : tout effacer ?"
			return
		Session.reset_profile()
		get_tree().reload_current_scene())
	v.add_child(reset)
	v.add_child(UiKit.icon_button("close", _toggle_settings, 40))


func _do_step(step: Dictionary) -> void:
	if step.has("floor"):
		if Session.start_tower_floor(int(step["floor"])):
			return
	_go(step["scene"])


func _go(screen: String) -> void:
	get_tree().change_scene_to_file("res://scenes/%s.tscn" % screen)


func _test_battle(a: String, b: String) -> void:
	Session.battle = {"mode": "test", "player": GameData.nation_team(a), "enemy": GameData.nation_team(b)}
	get_tree().change_scene_to_file("res://scenes/battle.tscn")
