extends Control
## Accueil : l'équipe, de dos au pied de la Tour des 99 Étages, lève les yeux vers elle (HomeTower).
## Modes en enseignes (Campagne, Invocation, Tour, Expédition), coffre de Patrouille (revenu hors ligne,
## comme dans Dragon Traveler), Équipe et Héros dans la barre du bas.

const GAME_FONT := preload("res://assets/fonts/LilitaOne-Regular.ttf")

var cam: Camera3D
var pinned: Array = []  # [Control, Vector3 du point d'accroche sur la tour, décalage écran]
var settings: PanelContainer
var reset_armed := false
var patrol_label: RichTextLabel


func _ready() -> void:
	theme = UiKit.theme()
	var p := Session.profile
	var world := Node3D.new()
	add_child(world)
	var team := p.formation_ids()
	cam = HomeTower.build(world, team.slice(0, 5))

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

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 20
	top.offset_right = -20
	top.offset_top = 12
	top.add_theme_constant_override("separation", 14)
	add_child(top)
	var title := _neon("T99", 40, UiKit.ACCENT)
	top.add_child(title)
	var power := UiKit.rich("%s %s" % [UiKit.bb("atk", 18, UiKit.HIGHLIGHT), UiKit.thousands(p.team_power())], 18, UiKit.HIGHLIGHT)
	power.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	power.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(power)
	top.add_child(UiKit.currency_bar())

	# Campagne : enseigne principale, étape suivante
	var cleared := p.campaign_cleared
	var nxt := p.next_stage()
	var info := Campaign.stage_info(nxt)
	var camp := _sign("CAMPAGNE", 66, UiKit.ACCENT, _go.bind("campaign"), -3.0)
	var sub := UiKit.rich("[center]%s %s   ·   %s[/center]" % [UiKit.bb("campagne", 22, Color("fff1c4")), info.get("number", ""), info.get("name", "")], 18, Color("fff1c4"))
	sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sub.offset_left = -220
	sub.offset_right = 220
	sub.offset_top = 2
	camp.add_child(sub)
	_pin(camp, HomeTower.anchor(6.0), Vector2(0, 0))
	var summ := _sign("INVOCATION", 46, Color("c9a0ff"), _go.bind("summon"), 5.0)
	if p.amount("sceau") >= 10:
		UiKit.badge(summ, "x10")
	_pin(summ, HomeTower.anchor(3.2, -1.0), Vector2(-190, 0))
	if Campaign.unlocked("tower", cleared):
		var tw := _sign("TOUR", 44, Color("7fd8ff"), _go.bind("tower"), -4.0)
		_pin(tw, HomeTower.anchor(4.6, 1.0), Vector2(200, 0))
	if Campaign.unlocked("expedition", cleared):
		var loot := _sign("EXPÉDITION", 40, Color("ff8a6a"), _go.bind("loot"), -5.0)
		_pin(loot, HomeTower.anchor(2.2, -1.0), Vector2(-220, 40))

	# Patrouille (idle) : revenu accumulé pendant l'absence
	var patrol := PanelContainer.new()
	patrol.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.04, 0.02, 0.07, 0.82), UiKit.ACCENT, 2, 14))
	add_child(patrol)
	patrol.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	patrol.grow_vertical = Control.GROW_DIRECTION_BEGIN
	patrol.offset_left = 20
	patrol.offset_bottom = -96
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 6)
	patrol.add_child(pv)
	pv.add_child(UiKit.rich("%s  Patrouille" % UiKit.bb("patrouille", 20, UiKit.ACCENT), 17, UiKit.ACCENT))
	patrol_label = UiKit.rich("", 15)
	pv.add_child(patrol_label)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 6)
	pv.add_child(prow)
	prow.add_child(UiKit.cta(UiKit.button("Récolter", _claim_patrol, Vector2(130, 42))))
	var quick := UiKit.button("Rapide", _quick_patrol, Vector2(110, 42))
	prow.add_child(quick)
	_refresh_patrol()
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(_refresh_patrol)
	add_child(t)

	# Combat direct de l'étape suivante
	var go := UiKit.cta(UiKit.rich_button("COMBATTRE  ›   %s" % info.get("number", ""), func() -> void: Session.start_stage(nxt), Vector2(300, 60), 22, Color("3a2a08")))
	add_child(go)
	go.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	go.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	go.grow_vertical = Control.GROW_DIRECTION_BEGIN
	go.offset_right = -24
	go.offset_bottom = -100

	var nav := HBoxContainer.new()
	nav.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	nav.offset_left = 24
	nav.offset_right = -24
	nav.offset_top = -78
	nav.offset_bottom = -10
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 60)
	add_child(nav)
	nav.add_child(_sign("ÉQUIPE", 38, UiKit.PAPER, _go.bind("team"), 0.0))
	var coll := _sign("HÉROS", 38, UiKit.PAPER, _go.bind("collection"), 0.0)
	if not p.unseen.is_empty():
		UiKit.badge(coll, "+%d" % p.unseen.size())
	nav.add_child(coll)
	var gear := UiKit.icon_button("info", _toggle_settings, 48)
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nav.add_child(gear)

	if not Session.grant_notes.is_empty():
		var gift := UiKit.label("Cadeau reçu : " + " ".join(Session.grant_notes), 15, UiKit.ACCENT)
		gift.position = Vector2(24, 70)
		add_child(gift)
		Session.grant_notes.clear()


func _process(_delta: float) -> void:
	if cam == null:
		return
	for e in pinned:
		var c: Control = e[0]
		var at: Vector2 = cam.unproject_position(e[1]) + e[2]
		c.position = at - c.size / 2.0


func _refresh_patrol() -> void:
	var p := Session.profile
	var now := Session.now()
	var got := p.patrol_pending(now)
	var parts: Array[String] = []
	for k in ["pieces", "encre", "essence"]:
		if got.has(k):
			parts.append("%s %s" % [UiKit.bb(k, 18), UiKit.thousands(int(got[k]))])
	var m := int(p.patrol_minutes(now))
	var cap := int(float(Campaign.cfg()["patrol"]["cap_hours"]) * 60.0)
	patrol_label.text = UiKit._scale_bbcode("%s\n[color=#a89cb8]%d h %02d / %d h%s[/color]" % ["   ".join(parts) if not parts.is_empty() else "…",
		m / 60, m % 60, cap / 60, "  (plein)" if m >= cap else ""])


func _claim_patrol() -> void:
	var got := Session.profile.claim_patrol(Session.now())
	Session.save()
	if not got.is_empty():
		UiJuicer.play_sfx("victory")
	_refresh_patrol()


func _quick_patrol() -> void:
	var p := Session.profile
	var price := p.quick_price(Session.now())
	if price < 0:
		return
	var got := p.quick_patrol(Session.now())
	if got.is_empty():
		return
	Session.save()
	UiJuicer.play_sfx("victory")
	_refresh_patrol()


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
	l.resized.connect(func() -> void: b.custom_minimum_size = l.size)
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
	settings.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	settings.grow_horizontal = Control.GROW_DIRECTION_BOTH
	settings.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(settings)
	UiJuicer.pop_in(settings)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	settings.add_child(v)
	v.add_child(UiKit.label("Combats de test (factions)", 15, UiKit.ACCENT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var fs := HeroDb.faction_order()
	for i in fs.size():
		var a: String = fs[i]
		var b: String = fs[(i + 1) % fs.size()]
		row.add_child(UiKit.button("%s – %s" % [UiKit.faction_name(a), UiKit.faction_name(b)], _test_battle.bind(a, b), Vector2(120, 40)))
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


func _go(screen: String) -> void:
	get_tree().change_scene_to_file("res://scenes/%s.tscn" % screen)


func _faction_team(f: String) -> Array:
	var ids := []
	for id in HeroDb.playable_ids(false):
		if HeroDb.hero(id)["factions"][0] == f:
			ids.append(id)
	var placed := HeroDb.auto_place(ids)
	var out := []
	for s: int in placed:
		out.append({"id": placed[s], "level": 60, "star": 6, "slot": s})
	return out


func _test_battle(a: String, b: String) -> void:
	Session.battle = {"mode": "test", "player": _faction_team(a), "enemy": _faction_team(b)}
	get_tree().change_scene_to_file("res://scenes/battle.tscn")
