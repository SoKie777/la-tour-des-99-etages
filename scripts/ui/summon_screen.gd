extends Control
## Invocation, mise en scène façon Dislyte : illustration plein pied de la vedette, nom en très grand,
## filigrane du titre de la bannière, compteur de garantie, boutons ×1 / ×10 inclinés et sélecteur de
## bannières en bas. Règle UI : coûts, taux et garanties en icônes et nombres.

const GAME_FONT := preload("res://assets/fonts/LilitaOne-Regular.ttf")

var rates_panel: PanelContainer


func _ready() -> void:
	_build()


func _build() -> void:
	var g := Session.gacha
	var b := g.banner
	var featured: Array = b.get("featured", [])
	var star_id: String = featured[0] if not featured.is_empty() else ""
	var col := UiKit.char_color(star_id) if star_id != "" else UiKit.ACCENT
	var content := UiKit.screen(self, "Invocation")
	_stage(b, col)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 540
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	if star_id != "":
		var d := HeroDb.hero(star_id)
		var f0 := str(d["factions"][0])
		left.add_child(UiKit.rich("%s %s   %s  [b]%s[/b]" % [UiKit.bb(UiKit.class_icon(d["class"]), 20, col.lightened(0.4)), UiKit.class_name_of(star_id),
			UiKit.bb("f_" + f0, 20, col.lightened(0.4)), UiKit.faction_name(f0).to_upper()], 18, col.lightened(0.4)))
		left.add_child(_big_name(str(d["name"]).to_upper()))
		left.add_child(UiKit.label("SSR", 30, UiKit.RARITY_COLORS[5]))
	else:
		left.add_child(_big_name(str(b["name"]).to_upper()))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	# garantie Épique (petite jauge) puis encart de la vedette et garantie Légendaire
	left.add_child(UiKit.progress("[color=#%s]SR+[/color]" % UiKit.RARITY_COLORS[4].to_html(false), int(g.pity_4.get(g.key(), 0)),
		int(b["guarantee_4_every"]), UiKit.RARITY_COLORS[4], 260))
	var box := PanelContainer.new()
	var st := UiKit.panel_style(Color(UiKit.BG, 0.82), Color(col, 0.7), 1, 10)
	st.set_content_margin_all(12)
	box.add_theme_stylebox_override("panel", st)
	left.add_child(box)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	box.add_child(bv)
	if star_id != "":
		var fh := HBoxContainer.new()
		fh.add_theme_constant_override("separation", 10)
		bv.add_child(fh)
		fh.add_child(UiKit.portrait(star_id, 44))
		fh.add_child(UiKit.rich("[color=#%s]SSR[/color] = 100 %%   [b]%s[/b]" % [UiKit.RARITY_COLORS[5].to_html(false),
			UiKit.char_name(star_id)], 20, Color("8fe6d6")))
	var left_5 := int(b["pity_5"]) - g.pity_count()
	bv.add_child(UiKit.rich("[center][color=#%s]SSR[/color] garanti dans   %s   [font_size=34][color=#%s]%d[/color][/font_size][/center]" % [
		UiKit.RARITY_COLORS[5].to_html(false), UiKit.bb("turn", 18), UiKit.ACCENT.to_html(false), left_5], 18))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	left.add_child(buttons)
	for n in [1, 10]:
		buttons.add_child(_pull_button(n))
	var tick := str(b.get("ticket", "sceau"))
	left.add_child(UiKit.rich("%s %d   %s %s" % [UiKit.bb(tick, 20), Session.profile.amount(tick), UiKit.bb("eclat_de_voeu", 20),
		UiKit.thousands(Session.profile.amount("eclat_de_voeu"))], 16))
	if not Session.last_pulls.is_empty():  # derniers tirages, en vignettes
		var last := HBoxContainer.new()
		last.add_theme_constant_override("separation", 4)
		left.add_child(last)
		for r in Session.last_pulls:
			last.add_child(_result_chip(r))
	left.add_child(_banner_bar())

	var side := VBoxContainer.new()  # bouton rond à droite, comme les raccourcis de Dislyte
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(side)
	var info := UiKit.icon_button("info", _toggle_rates, 52)
	info.size_flags_horizontal = Control.SIZE_SHRINK_END
	side.add_child(info)


## Décor de la bannière : dégradé, filigrane du titre, soleil, illustration de la vedette.
func _stage(b: Dictionary, col: Color) -> void:
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.clip_contents = true
	add_child(stage)
	move_child(stage, 1)  # juste au-dessus du fond de l'écran
	var grad := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, col.darkened(0.35))
	gr.set_color(1, UiKit.BG.darkened(0.3))
	gr.add_point(0.55, UiKit.VERMILION.darkened(0.55))
	grad.gradient = gr
	grad.fill_from = Vector2(1, 0)
	grad.fill_to = Vector2(0, 1)
	var bg := TextureRect.new()
	bg.texture = grad
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.modulate.a = 0.9
	stage.add_child(bg)
	var mark := Label.new()  # filigrane : titre de la bannière en contour, très grand
	var title := str(b["name"]).to_upper()
	mark.text = "%s  ·  %s  ·  %s" % [title, title, title]
	mark.add_theme_font_override("font", GAME_FONT)
	mark.add_theme_font_size_override("font_size", 120)
	mark.add_theme_color_override("font_color", Color(1, 1, 1, 0.0))
	mark.add_theme_color_override("font_outline_color", Color(UiKit.PAPER, 0.13))
	mark.add_theme_constant_override("outline_size", 5)
	mark.position = Vector2(-120, 60)
	mark.rotation_degrees = -4.0
	stage.add_child(mark)
	var sun := Panel.new()  # grand soleil rouge derrière la vedette
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(UiKit.VERMILION, 0.85)
	ss.set_corner_radius_all(400)
	sun.add_theme_stylebox_override("panel", ss)
	sun.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	sun.offset_left = -640
	sun.offset_right = -180
	sun.offset_top = -260
	sun.offset_bottom = 200
	stage.add_child(sun)
	var path: String = b.get("splash", b.get("art", ""))
	if path != "" and ResourceLoader.exists(path):
		var art := TextureRect.new()
		art.texture = load(path)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		art.offset_left = -760
		art.offset_right = -60
		art.offset_top = 40
		stage.add_child(art)
		art.modulate.a = 0.0  # entrée en fondu
		art.create_tween().tween_property(art, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _big_name(text: String) -> Label:
	var l := UiKit.label(text, 76, UiKit.PAPER)
	l.add_theme_font_override("font", GAME_FONT)
	l.add_theme_constant_override("outline_size", 12)
	l.add_theme_color_override("font_outline_color", UiKit.INK)
	return l


## Bouton d'invocation (×1 / ×10) : Sceaux de la bannière d'abord, puis Éclats de Vœu.
func _pull_button(n: int) -> Button:
	var cost := Session.pull_cost(n)
	var enough := Session.profile.can_pay(cost)
	var parts: Array[String] = []
	for k: String in cost:
		parts.append("%s %s" % [UiKit.bb(k, 20, UiKit.INK), UiKit.thousands(int(cost[k]))])
	var bt := UiKit.rich_button("[font_size=22][b]×%d[/b][/font_size]    %s" % [n, "  ".join(parts)],
		_pull.bind(n), Vector2(280, 64), 20, UiKit.INK if enough else UiKit.DIM)
	UiKit.cta(bt)  # même style or que les boutons principaux
	bt.disabled = not enough
	return bt


func _result_chip(r: Dictionary) -> Control:
	var rarity: int = r["rarity"]
	var p := PanelContainer.new()
	var st := UiKit.panel_style(Color(UiKit.RARITY_COLORS[rarity], 0.25), UiKit.RARITY_COLORS[rarity], 2 if r.get("new", false) else 1, 4)
	st.set_content_margin_all(2)
	p.add_theme_stylebox_override("panel", st)
	p.add_child(UiKit.portrait(r["id"], 38))
	return p


## Sélecteur de bannières (barre arrondie en bas, comme Dislyte).
func _banner_bar() -> Control:
	var bar := PanelContainer.new()
	var st := UiKit.panel_style(Color(UiKit.BG, 0.85), Color(UiKit.ACCENT, 0.5), 1, 30)
	st.content_margin_left = 16
	st.content_margin_right = 16
	bar.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	bar.add_child(h)
	for id: String in GameData.gacha()["banners"]:
		var bd: Dictionary = GameData.gacha()["banners"][id]
		if bd.get("hidden", false):
			continue  # bannière de départ (prologue)
		var selected := id == Session.gacha.banner_id
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		var fe: Array = bd.get("featured", [])
		var tab := Button.new()
		tab.custom_minimum_size = Vector2(64, 52)
		tab.flat = true
		tab.icon = UiKit.portrait_texture(fe[0]) if not fe.is_empty() else UiKit.icon_texture("summon")
		tab.expand_icon = true
		tab.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tab.modulate = Color.WHITE if selected else Color(1, 1, 1, 0.5)
		tab.pressed.connect(func() -> void:
			Session.set_banner(id)
			_build())
		v.add_child(tab)
		var l := UiKit.label(str(bd["name"]), 11, UiKit.ACCENT if selected else UiKit.DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		h.add_child(v)
	return bar


## Taux et garanties (bouton « i »).
func _toggle_rates() -> void:
	if rates_panel != null:
		rates_panel.queue_free()
		rates_panel = null
		return
	var b := Session.gacha.banner
	rates_panel = PanelContainer.new()
	rates_panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(UiKit.BG, 0.96), UiKit.ACCENT, 2, 8))
	rates_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	rates_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	rates_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	rates_panel.custom_minimum_size.x = 460
	add_child(rates_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	rates_panel.add_child(v)
	for line in Session.gacha.rates_text():
		v.add_child(UiKit.label(line, 15))
	if b.has("wishlist_unlock"):
		var g := Session.gacha
		var open := g.wishlist_open()
		v.add_child(UiKit.label("Liste de souhaits (%d / %d)%s" % [g.wishlist.size(), int(b["wishlist_size"]),
			"" if open else "  —  %d / %d invocations" % [g.total_pulls, int(b["wishlist_unlock"])]], 15, UiKit.ACCENT if open else UiKit.DIM))
		var wl := HFlowContainer.new()
		wl.add_theme_constant_override("h_separation", 4)
		v.add_child(wl)
		for id in HeroDb.ids_of_rarity(5):
			var on := g.wishlist.has(id)
			var chip := Button.new()
			chip.custom_minimum_size = Vector2(52, 52)
			chip.icon = UiKit.portrait_texture(id)
			chip.expand_icon = true
			chip.modulate = Color.WHITE if on else Color(1, 1, 1, 0.45)
			chip.disabled = not open
			chip.pressed.connect(func() -> void:
				if g.wishlist.has(id):
					g.wishlist.erase(id)
				elif g.wishlist.size() < int(b["wishlist_size"]):
					g.wishlist.append(id)
				Session.save()
				_toggle_rates()
				_toggle_rates())
			wl.add_child(chip)
	v.add_child(UiKit.icon_button("close", _toggle_rates, 40))


func _pull(n: int) -> void:
	if not Session.pull(n).is_empty():
		get_tree().change_scene_to_file("res://scenes/summon_cinematic.tscn")
