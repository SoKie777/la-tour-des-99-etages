extends Control
## Prologue : chemin des 8 niveaux (consigne, faiblesses, récompense), invocations x10 offertes sur la
## bannière de départ après les niveaux 2 et 3, puis l'entrée dans la Tour.

const GAME_FONT := preload("res://assets/fonts/LilitaOne-Regular.ttf")


func _ready() -> void:
	var p := Session.profile
	if not p.in_prologue():
		_finale()
	elif p.free_multi_due():
		_offer()
	else:
		_path()
	if Session.in_trial():  # essai du prologue : retour à la vraie partie à tout moment
		var back := UiKit.button("Revenir à ma partie", func() -> void:
			Session.end_trial()
			get_tree().change_scene_to_file("res://scenes/main.tscn"), Vector2(220, 40))
		back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		back.position = Vector2(-560, 14)
		add_child(back)


func _big(text: String, size: int, color := UiKit.PAPER) -> Label:
	var l := UiKit.label(text, size, color)
	l.add_theme_font_override("font", GAME_FONT)
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_outline_color", UiKit.INK)
	return l


## Chemin des niveaux et équipe.
func _path() -> void:
	var p := Session.profile
	var content := UiKit.screen(self, "Prologue", "")
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 20)
	content.add_child(cols)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var focus: Control = null
	var multis: Array[int] = []  # niveaux suivis d'une invocation offerte
	for m: Variant in Prologue.cfg()["free_multis_after"]:
		multis.append(int(m))
	for n in range(1, Prologue.level_count() + 1):
		var row := _level_row(n)
		list.add_child(row)
		if n == p.prologue_cleared + 1:
			focus = row
		if n in multis:  # invocation offerte après ce niveau
			var done := p.prologue_pulls > multis.find(n)
			list.add_child(UiKit.rich("        %s  ×10  %s" % [UiKit.bb("summon", 20, UiKit.ACCENT if not done else UiKit.DIM),
				"✓" if done else "[s]%s 10[/s]" % UiKit.bb("eclat_de_voeu", 16, UiKit.DIM)], 16, UiKit.ACCENT if not done else UiKit.DIM))
	list.add_child(UiKit.rich("        %s  %s" % [UiKit.bb("floor", 22, UiKit.ACCENT), "La Tour des 99 Étages"], 18, UiKit.ACCENT))
	if focus != null:
		_scroll_to.call_deferred(scroll, focus)

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 380
	side.add_theme_constant_override("separation", 8)
	cols.add_child(side)
	side.add_child(UiKit.model_view(p.team, Vector2i(380, 330)))
	side.add_child(UiKit.amount("eclat_de_voeu", str(p.amount("eclat_de_voeu")), 20, UiKit.ACCENT))
	if p.owned_ids().size() > 1:
		side.add_child(UiKit.button("Équipe", func() -> void: get_tree().change_scene_to_file("res://scenes/team.tscn"), Vector2(380, 48)))
		var coll := UiKit.button("Collection", func() -> void: get_tree().change_scene_to_file("res://scenes/collection.tscn"), Vector2(380, 44))
		if not p.unseen.is_empty():
			UiKit.badge(coll, "+%d" % p.unseen.size())
		side.add_child(coll)


func _scroll_to(scroll: ScrollContainer, target: Control) -> void:
	await get_tree().process_frame  # attendre la mise en page
	scroll.ensure_control_visible(target)


## Taille d'équipe demandée par le niveau (jamais plus que le nombre de héros possédés).
func _team_needed(f: Dictionary) -> int:
	return mini(int(f.get("team", 1)), Session.profile.owned_ids().size())


func _level_row(n: int) -> Control:
	var p := Session.profile
	var f := Prologue.level(n)
	var cleared := n <= p.prologue_cleared
	var current := n == p.prologue_next()
	var border := UiKit.ACCENT if current else (Color("4a8a5a") if cleared else Color.TRANSPARENT)
	var panel := UiKit.panel(border)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	panel.add_child(h)
	var title := "[b]%d[/b]  %s" % [n, f["name"]]
	if f.has("boss_unit"):
		title += "  " + UiKit.bb("boss", 20, UiKit.VERMILION.lightened(0.3))
	elif f.get("elite", false):
		title += "  ★"
	if cleared:
		title += "  [color=#8fd8a0]✓[/color]"
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	h.add_child(v)
	v.add_child(UiKit.rich(title, 19, UiKit.ACCENT if current else (UiKit.PAPER if cleared else UiKit.DIM)))
	if current:
		v.add_child(UiKit.rich(str(f["brief"]), 15, UiKit.PAPER, true))
		var weak: Array[String] = []  # faiblesses : constellations qui brisent la Ténacité
		for c in Prologue.weaknesses(n):
			weak.append(UiKit.bb(c, 26, UiKit.CONST_COLORS[c].lightened(0.3)))
		var foes: Array[String] = []
		if f.has("boss_unit"):
			foes.append(str(GameData.boss(f["boss_unit"])["name"]))
		for id: String in f["enemies"]:
			foes.append(UiKit.char_name(id))
		v.add_child(UiKit.rich("%s %s     %s" % [UiKit.bb("dmg_taken", 20, UiKit.VERMILION.lightened(0.3)), " ".join(weak), ", ".join(foes)], 15, UiKit.DIM, true))
		var rw: Dictionary = Prologue.cfg()["reward"]
		v.add_child(UiKit.rich("%s +%d     %s +%s" % [UiKit.bb("eclat_de_voeu", 18, UiKit.ACCENT), int(rw["eclat_de_voeu"]),
			UiKit.bb("pieces", 16), UiKit.thousands(int(rw["pieces"]))], 15, UiKit.ACCENT))
		var need := _team_needed(f)
		if p.team.size() < need:  # composer l'équipe avant le combat (team building)
			var tb := UiKit.button("Composer l'équipe (%d / %d)" % [p.team.size(), need],
				func() -> void: get_tree().change_scene_to_file("res://scenes/team.tscn"), Vector2(230, 56))
			_gold(tb)
			h.add_child(tb)
		else:
			var fight := UiKit.button("Combattre", func() -> void: Session.start_prologue(n), Vector2(170, 56))
			_gold(fight)
			h.add_child(fight)
	elif not cleared:
		h.add_child(UiKit.icon("lock", 22, UiKit.DIM))
		panel.modulate = Color(1, 1, 1, 0.55)
	return panel


func _gold(b: Button) -> void:
	b.add_theme_stylebox_override("normal", UiKit.panel_style(Color("4a3a12"), UiKit.ACCENT, 2, 10))
	b.add_theme_stylebox_override("hover", UiKit.panel_style(Color("5c4818"), Color("ffe08a"), 3, 10))
	b.add_theme_color_override("font_color", Color("fff1c4"))


## Bannière de départ : invocation x10 offerte (le prix barré, les Éclats restent au joueur).
func _offer() -> void:
	var p := Session.profile
	var b: Dictionary = GameData.gacha()["banners"][str(Prologue.cfg()["banner"])]
	var content := UiKit.screen(self, "Invocation", "")
	var splash: String = b.get("splash", "")
	if splash == "" or not ResourceLoader.exists(splash):  # pas d'illustration : la vedette en 3D
		var view := UiKit.model_view([b["featured"][0]], Vector2i(520, 600))
		view.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		view.offset_left = -620
		view.offset_top = -250
		add_child(view)
		move_child(view, 1)
	var stage := TextureRect.new()  # illustration de la vedette à droite
	if splash != "" and ResourceLoader.exists(splash):
		stage.texture = load(splash)
	stage.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stage.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stage.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	stage.offset_left = -700
	stage.offset_right = -40
	stage.offset_top = 40
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	move_child(stage, 1)
	var left := VBoxContainer.new()
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	content.add_child(left)
	left.add_child(_big(str(b["name"]).to_upper(), 70))
	var feat := HBoxContainer.new()
	feat.add_theme_constant_override("separation", 10)
	left.add_child(feat)
	for id: String in b["featured"]:
		var r := int(GameData.character(id)["rarity"])
		feat.add_child(UiKit.portrait(id, 52))
		feat.add_child(UiKit.rich("[color=#%s]%s[/color]\n%s" % [UiKit.RARITY_COLORS[r].to_html(false), "★".repeat(r), UiKit.char_name(id)], 16))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	var nth := int(Session.gacha.get_state()["banner_pulls"].get(str(Prologue.cfg()["banner"]), 0))
	left.add_child(UiKit.rich("[color=#%s]★★★★★[/color]   %s   [font_size=34][color=#%s]%d[/color][/font_size]" % [
		UiKit.RARITY_COLORS[5].to_html(false), UiKit.bb("turn", 18), UiKit.ACCENT.to_html(false), int(b["hard_pity_5"]) - nth], 18))
	# le prix, barré en grand : la ressource est là, mais l'invocation est offerte
	var price := HBoxContainer.new()
	price.add_theme_constant_override("separation", 8)
	left.add_child(price)
	price.add_child(UiKit.icon("eclat_de_voeu", 64, UiKit.DIM))
	var ten := _big("10", 110, UiKit.DIM)
	price.add_child(ten)
	var bar := ColorRect.new()  # grand trait vermillon en travers du prix
	bar.color = UiKit.VERMILION.lightened(0.15)
	bar.size = Vector2(150, 12)
	bar.position = Vector2(-12, 66)
	bar.rotation_degrees = -14.0
	bar.pivot_offset = Vector2(75, 6)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ten.add_child(bar)
	var have := UiKit.amount("eclat_de_voeu", str(p.amount("eclat_de_voeu")), 22, UiKit.ACCENT)  # la ressource est là
	have.size_flags_vertical = Control.SIZE_SHRINK_END
	price.add_child(have)
	var go := UiKit.button("×10   GRATUIT", func() -> void:
		if not Session.free_multi().is_empty():
			get_tree().change_scene_to_file("res://scenes/summon_cinematic.tscn"), Vector2(380, 76))
	go.add_theme_font_override("font", GAME_FONT)
	go.add_theme_font_size_override("font_size", 34)
	for state in ["normal", "hover", "pressed"]:
		var s := UiKit.panel_style(UiKit.ACCENT.lightened(0.15 if state == "hover" else 0.0), UiKit.PAPER if state == "pressed" else Color.TRANSPARENT, 2, 4)
		s.skew = Vector2(0.28, 0)  # bouton incliné, comme l'écran d'invocation
		go.add_theme_stylebox_override(state, s)
	go.add_theme_color_override("font_color", UiKit.INK)
	go.add_theme_color_override("font_hover_color", UiKit.INK)
	go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(go)
	var tw := go.create_tween().set_loops()  # le bouton respire
	tw.tween_property(go, "scale", Vector2(1.04, 1.04), 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(go, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)


## Fin du prologue : la Tour s'ouvre.
func _finale() -> void:
	var content := UiKit.screen(self, "Prologue", "")
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(center)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)
	var t := _big("LA TOUR S'OUVRE", 64, UiKit.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var won := Prologue.level_count() * int(Prologue.cfg()["reward"]["eclat_de_voeu"])  # gagnés pendant le prologue
	v.add_child(UiKit.rich("[center]%s %d   =   %s ×10 ×%d[/center]" % [UiKit.bb("eclat_de_voeu", 26, UiKit.ACCENT),
		won, UiKit.bb("summon", 26, UiKit.ACCENT), won / (10 * int(GameData.progression()["pull_cost"]))], 24, UiKit.ACCENT))
	var go := UiKit.button("Entrer dans la Tour  ›", func() -> void:
		if Session.in_trial():
			Session.end_trial()
		get_tree().change_scene_to_file("res://scenes/main.tscn"), Vector2(340, 64))
	_gold(go)
	var c2 := CenterContainer.new()
	c2.add_child(go)
	v.add_child(c2)
