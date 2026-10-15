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
	right.add_theme_constant_override("separation", 12)
	cols.add_child(right)
	var p := Session.profile
	var next_floor := mini(p.tower_cleared + 1, Tower.floor_count())
	var tower := UiKit.button("Ascension de la Tour\nÉtage %d / %d" % [next_floor, Tower.floor_count()], _go.bind("tower"), Vector2(400, 96))
	tower.add_theme_font_size_override("font_size", 22)
	right.add_child(tower)
	right.add_child(UiKit.button("Boss de butin (reliques)", _go.bind("loot"), Vector2(400, 60)))
	right.add_child(UiKit.button("Équipe", _go.bind("team"), Vector2(400, 60)))
	right.add_child(UiKit.button("Collection et reliques (%d)" % p.relics.size(), _go.bind("collection"), Vector2(400, 60)))
	right.add_child(UiKit.button("Invocation", _go.bind("summon"), Vector2(400, 60)))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)

	right.add_child(UiKit.label("Combat libre (test, équipes de nation)", 13, UiKit.DIM))
	var row := HBoxContainer.new()
	right.add_child(row)
	for m in TEST_MATCHUPS:
		row.add_child(UiKit.button(m[0], _test_battle.bind(m[1], m[2]), Vector2(128, 40)))
	var reset := UiKit.button("Recommencer le profil", func() -> void: pass, Vector2(400, 36))
	reset.pressed.connect(func() -> void:
		if not reset_armed:
			reset_armed = true
			reset.text = "Confirmer : tout effacer ?"
			return
		Session.reset_profile()
		get_tree().reload_current_scene())
	right.add_child(reset)


func _go(screen: String) -> void:
	get_tree().change_scene_to_file("res://scenes/%s.tscn" % screen)


func _test_battle(a: String, b: String) -> void:
	Session.battle = {"mode": "test", "player": GameData.nation_team(a), "enemy": GameData.nation_team(b)}
	get_tree().change_scene_to_file("res://scenes/battle.tscn")
