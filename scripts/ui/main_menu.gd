extends Control
## Hub : équipe en 3D, accès à la Tour, à l'équipe, à la collection et à l'invocation.

const TEST_MATCHUPS := [["A contre B", "A", "B"], ["B contre C", "B", "C"], ["C contre A", "C", "A"]]

var reset_armed := false


func _ready() -> void:
	var content := UiKit.screen(self, "LA TOUR DES 99 ÉTAGES", "")
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 24)
	content.add_child(cols)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(UiKit.label("Ton équipe", 18, UiKit.DIM))
	var view := UiKit.model_view(Session.profile.team, Vector2i(620, 470))
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(view)
	var names: Array[String] = []
	for id in Session.profile.team:
		names.append(UiKit.char_name(id))
	left.add_child(UiKit.label("  ·  ".join(names), 16))

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 420
	right.add_theme_constant_override("separation", 7)
	cols.add_child(right)
	var p := Session.profile
	var steps := Objectives.next_steps(p, Session.now())
	# réduction : la prochaine étape conseillée en un seul geste (docs/CAPTOLOGIE.md)
	if not steps.is_empty():
		var first: Dictionary = steps[0]
		var cont := UiKit.button("Continuer  ›  " + str(first["text"]), _do_step.bind(first), Vector2(400, 58))
		cont.add_theme_stylebox_override("normal", UiKit.panel_style(Color("4a3a12"), UiKit.ACCENT, 2, 12))
		cont.add_theme_stylebox_override("hover", UiKit.panel_style(Color("5c4818"), Color("ffe08a"), 3, 12))
		cont.add_theme_color_override("font_color", Color("fff1c4"))
		cont.add_theme_font_size_override("font_size", 17)
		right.add_child(cont)
		for k in range(1, mini(steps.size(), 3)):
			var sb := UiKit.button("›  " + str(steps[k]["text"]), _do_step.bind(steps[k]), Vector2(400, 30))
			sb.add_theme_font_size_override("font_size", 13)
			sb.alignment = HORIZONTAL_ALIGNMENT_LEFT
			right.add_child(sb)
	var next_floor := mini(p.tower_cleared + 1, Tower.floor_count())
	var tower := UiKit.button("Ascension de la Tour · étage %d" % next_floor, _go.bind("tower"), Vector2(400, 48))
	tower.add_theme_font_size_override("font_size", 19)
	right.add_child(tower)
	right.add_child(UiKit.progress("Cité d'Acier", p.tower_cleared, Tower.floor_count(), UiKit.ACCENT, 400))
	p.refresh_energy(Session.now())
	if p.energy >= int(GameData.progression()["energy"]["max"]) and p.tower_cleared < Tower.floor_count():
		UiKit.badge(tower, "Énergie pleine")
	right.add_child(UiKit.button("Boss de butin (reliques)", _go.bind("loot"), Vector2(400, 42)))
	right.add_child(UiKit.button("Équipe", _go.bind("team"), Vector2(400, 42)))
	var coll := UiKit.button("Collection et reliques", _go.bind("collection"), Vector2(400, 42))
	right.add_child(coll)
	if not p.unseen.is_empty():
		UiKit.badge(coll, "%d nouveau%s" % [p.unseen.size(), "x" if p.unseen.size() > 1 else ""])
	var summ := UiKit.button("Invocation", _go.bind("summon"), Vector2(400, 42))
	right.add_child(summ)
	if p.amount("eclat_de_voeu") >= 10 * int(GameData.progression()["pull_cost"]):
		UiKit.badge(summ, "x10")
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	if not Session.grant_notes.is_empty():  # cadeau reçu : message affiché une fois
		var gift := UiKit.label("Cadeau reçu : " + " ".join(Session.grant_notes) + " (3 000 Éclats, 300 000 Pièces)", 14, UiKit.ACCENT)
		gift.autowrap_mode = TextServer.AUTOWRAP_WORD
		right.add_child(gift)
		Session.grant_notes.clear()

	if Time.get_ticks_msec() > 60 * 60 * 1000:  # respect du temps : rappel discret après une heure
		right.add_child(UiKit.label("Tu joues depuis plus d'une heure : pense à faire une pause.", 13, Color("8fd8a0")))
	right.add_child(UiKit.label("Combat libre (test, équipes de nation)", 13, UiKit.DIM))
	var row := HBoxContainer.new()
	right.add_child(row)
	for m in TEST_MATCHUPS:
		row.add_child(UiKit.button(m[0], _test_battle.bind(m[1], m[2]), Vector2(128, 34)))
	var reset := UiKit.button("Recommencer le profil", func() -> void: pass, Vector2(400, 32))
	reset.pressed.connect(func() -> void:
		if not reset_armed:
			reset_armed = true
			reset.text = "Confirmer : tout effacer ?"
			return
		Session.reset_profile()
		get_tree().reload_current_scene())
	right.add_child(reset)


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
