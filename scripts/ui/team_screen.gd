extends Control
## Composition de l'équipe : 3 personnages parmi ceux que l'on possède.

var picked: Array[String] = []


func _ready() -> void:
	picked = Session.profile.team.duplicate()
	_build()


func _build() -> void:
	var content := UiKit.screen(self, "Équipe")
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 20)
	content.add_child(cols)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(UiKit.label("Touche un personnage pour l'ajouter ou le retirer (3 au maximum).", 15, UiKit.DIM))
	var scroll := ScrollContainer.new()  # 24 personnages : la grille défile
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for id in Session.profile.owned_ids():
		grid.add_child(UiKit.char_card(id, _toggle.bind(id), id in picked))
	left.add_child(UiKit.label(_triangle_hint(), 14, UiKit.DIM))

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 420
	cols.add_child(right)
	right.add_child(UiKit.label("Équipe (%d / 3)" % picked.size(), 18, UiKit.ACCENT))
	right.add_child(UiKit.model_view(picked, Vector2i(420, 300)))
	var names: Array[String] = []
	for id in picked:
		names.append("%s (%s)" % [UiKit.char_name(id), UiKit.CLASS_NAMES[GameData.character(id)["class"]]])
	var l := UiKit.label("\n".join(names), 15)
	right.add_child(l)
	# formations (fiche, partie 4) : équipe + reliques, appliquées en un clic
	right.add_child(UiKit.label("Formations (équipe et reliques)", 15, UiKit.ACCENT))
	var p := Session.profile
	for i in int(GameData.progression()["formation_slots"]):
		var f: Dictionary = p.formations[i] if i < p.formations.size() else {}
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		right.add_child(row)
		var fnames: Array[String] = []
		for id: String in f.get("team", []):
			fnames.append(UiKit.char_name(id))
		var fl := UiKit.label("%d. %s" % [i + 1, ", ".join(fnames) if not fnames.is_empty() else "vide"], 13, UiKit.DIM)
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fl.clip_text = true
		row.add_child(fl)
		row.add_child(UiKit.button("Enregistrer", func() -> void:
			p.save_formation(i)
			Session.save()
			_build(), Vector2(104, 36)))
		var ap := UiKit.button("Appliquer", func() -> void:
			if p.apply_formation(i):
				picked = p.team.duplicate()
				Session.save()
				_build(), Vector2(96, 36))
		ap.disabled = f.is_empty()
		row.add_child(ap)


func _toggle(id: String) -> void:
	if id in picked:
		if picked.size() == 1:
			return  # il faut au moins un personnage
		picked.erase(id)
	elif picked.size() < 3:
		picked.append(id)
	else:
		return
	Session.profile.set_team(picked)
	Session.save()
	_build()


func _triangle_hint() -> String:
	var tri: Dictionary = GameData.rules()["triangle"]
	return "Triangle des constellations : Orion > Grande Ourse > Sirius > Orion.\n" + \
		"Le dominant gagne +%d de TC ; le dominé inflige %d %% de dégâts en moins." % [
			int(tri["dominant_crit_bonus"]), roundi((1.0 - float(tri["dominated_damage_mult"])) * 100.0)]
