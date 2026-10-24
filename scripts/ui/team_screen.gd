extends Control
## Formation sur la grille 3 × 3 (Dragon Traveler) : Gardiens devant, Guerriers devant ou au milieu,
## Prêtres, Archers et Mages au milieu ou au fond, Assassins partout. Jusqu'à 6 héros selon la campagne.
## Choisir un héros dans la liste puis une case ; toucher une case occupée sans héros choisi la vide.

var picked := ""


func _ready() -> void:
	_build()


func _build() -> void:
	var p := Session.profile
	var content := UiKit.screen(self, "Équipe")
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 22)
	content.add_child(cols)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	left.add_child(head)
	head.add_child(UiKit.label("%d / %d" % [p.formation.size(), p.deploy_max()], 20, UiKit.ACCENT))
	head.add_child(UiKit.rich("%s %s" % [UiKit.bb("atk", 18, UiKit.HIGHLIGHT), UiKit.thousands(p.team_power())], 18, UiKit.HIGHLIGHT))
	var hint := UiKit.label("   fond         milieu        devant  ›  ennemis", 13, UiKit.DIM)
	left.add_child(hint)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	left.add_child(grid)
	for row in 3:
		for c in [2, 1, 0]:
			grid.add_child(_cell(c * 3 + row))
	left.add_child(UiKit.rich(_faction_line(), 15, UiKit.PAPER, true))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	left.add_child(btns)
	btns.add_child(UiKit.button("Auto", func() -> void:
		p.auto_formation()
		Session.save()
		_build(), Vector2(110, 44)))
	for i in int(GameData.progression()["formation_slots"]):
		var has: bool = i < p.presets.size() and not (p.presets[i] as Dictionary).is_empty()
		var ib := UiKit.button("%d" % (i + 1), func() -> void:
			if p.apply_preset(i):
				Session.save()
				_build(), Vector2(48, 44))
		ib.disabled = not has
		btns.add_child(ib)
		btns.add_child(UiKit.button("✎", func() -> void:
			p.save_preset(i)
			Session.save()
			_build(), Vector2(40, 44)))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(UiKit.label("Choisis un héros, puis une case" if picked == "" else "%s : choisis une case" % UiKit.char_name(picked), 15, UiKit.DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var list := GridContainer.new()
	list.columns = 3
	list.add_theme_constant_override("h_separation", 8)
	list.add_theme_constant_override("v_separation", 8)
	scroll.add_child(list)
	for id in p.owned_ids():
		var in_team := p.slot_of(id) >= 0
		var card := UiKit.char_card(id, _pick.bind(id), id == picked, false, p.best_star(id),
			"Niv. %d%s" % [p.effective_level(id), "  ✓" if in_team else ""])
		list.add_child(card)


func _cell(slot: int) -> Control:
	var p := Session.profile
	var id: String = p.formation.get(str(slot), "")
	var b := Button.new()
	b.custom_minimum_size = Vector2(118, 118)
	b.focus_mode = Control.FOCUS_NONE
	var allowed := picked != "" and HeroDb.can_place(picked, slot)
	var border := UiKit.ACCENT if allowed else UiKit.CARD_BORDER
	b.add_theme_stylebox_override("normal", UiKit.panel_style(Color(0.08, 0.05, 0.12, 0.85), border, 2 if allowed else 1, 10))
	b.add_theme_stylebox_override("hover", UiKit.panel_style(Color(0.12, 0.08, 0.18, 0.9), UiKit.ACCENT, 2, 10))
	if id != "":
		var por := UiKit.portrait(id, 96)
		por.set_anchors_preset(Control.PRESET_CENTER)
		por.offset_left = -48
		por.offset_right = 48
		por.offset_top = -52
		por.offset_bottom = 44
		b.add_child(por)
		var st := UiKit.rich("[center]%s[/center]" % UiKit.stars_bb(p.best_star(id), 11), 11)
		st.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		st.offset_top = -20
		b.add_child(st)
		var ci := UiKit.icon(UiKit.class_icon(str(HeroDb.hero(id)["class"])), 18, Color(UiKit.PAPER, 0.9))
		ci.position = Vector2(6, 6)
		b.add_child(ci)
	elif picked != "" and not allowed:
		b.modulate = Color(0.6, 0.6, 0.6)
	b.pressed.connect(_on_cell.bind(slot))
	return b


func _pick(id: String) -> void:
	picked = "" if picked == id else id
	_build()


func _on_cell(slot: int) -> void:
	var p := Session.profile
	if picked == "":
		if p.formation.has(str(slot)):
			p.set_slot(slot, "")
			Session.save()
		_build()
		return
	var prev: String = p.formation.get(str(slot), "")
	if prev != "" and prev != picked:
		p.set_slot(slot, "")
	if p.set_slot(slot, picked):
		picked = ""
		Session.save()
	elif prev != "":
		p.set_slot(slot, prev)
	_build()


func _faction_line() -> String:
	var counts := {}
	for id in Session.profile.formation_ids():
		for f in HeroDb.active_factions(id, Session.profile.best_star(id)):
			counts[f] = int(counts.get(f, 0)) + 1
	var parts: Array[String] = []
	var best := 0
	for f: String in counts:
		parts.append("%s %d" % [UiKit.bb("f_" + f, 18, UiKit.faction_color(f).lightened(0.2)), int(counts[f])])
		best = maxi(best, int(counts[f]))
	var pct := 0
	var table := HeroDb.faction_bonus()
	for k: String in table:
		if best >= int(k):
			pct = maxi(pct, int(table[k]))
	return "   ".join(parts) + ("     Bonus de faction : ATK et PV +%d %%" % pct if pct > 0 else "     (4 héros d'une faction : +10 %)")
