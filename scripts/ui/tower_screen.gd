extends Control
## Ascension de la Tour : liste des étages, adversaires, récompenses, accès au combat.


func _ready() -> void:
	var p := Session.profile
	var content := UiKit.screen(self, "Ascension de la Tour")
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
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var universe := ""
	var focus: Control = null
	for n in range(Tower.floor_count(), 0, -1):  # du sommet vers la base, comme une tour
		var f := Tower.floor_info(n)
		if f["universe"] != universe:
			universe = f["universe"]
			list.add_child(UiKit.label(universe, 20, UiKit.ACCENT))
		var row := _floor_row(f)
		list.add_child(row)
		if n == mini(p.tower_cleared + 1, Tower.floor_count()):
			focus = row
	if focus != null:
		_scroll_to.call_deferred(scroll, focus)

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 380
	cols.add_child(side)
	side.add_child(UiKit.label("Équipe engagée", 18, UiKit.DIM))
	var view := UiKit.model_view(p.team, Vector2i(380, 330))
	side.add_child(view)
	side.add_child(UiKit.button("Modifier l'équipe", func() -> void: get_tree().change_scene_to_file("res://scenes/team.tscn"), Vector2(380, 52)))
	side.add_child(UiKit.label("Chaque victoire : Pièces + 1 relique.\nPremière victoire : Éclats de Vœu.", 14, UiKit.DIM))


func _scroll_to(scroll: ScrollContainer, target: Control) -> void:
	await get_tree().process_frame  # attendre la mise en page
	scroll.ensure_control_visible(target)


func _floor_row(f: Dictionary) -> Control:
	var p := Session.profile
	var n: int = f["number"]
	var cleared := n <= p.tower_cleared
	var open := p.can_enter_floor(n)
	var border := UiKit.ACCENT if open and not cleared else (Color("4a8a5a") if cleared else Color.TRANSPARENT)
	var panel := UiKit.panel(border)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	panel.add_child(h)
	var title := "Étage %d" % n
	if f.has("boss"):
		title += " · BOSS"
	elif f.get("elite", false):
		title += " · Élite"
	var t := UiKit.label(title, 18, UiKit.ACCENT if f.has("boss") else Color.WHITE)
	t.custom_minimum_size.x = 170
	h.add_child(t)
	var names: Array[String] = []
	for id: String in f["enemies"]:
		names.append(UiKit.char_name(id))
	var info := UiKit.label("%s%s\nPuissance %d %%" % [str(f["boss"]) + " : " if f.has("boss") else "", ", ".join(names), roundi(float(f["power"]) * 100.0)], 14, UiKit.DIM)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	h.add_child(info)
	if open:
		h.add_child(UiKit.button("Rejouer" if cleared else "Combattre", Session.start_tower_floor.bind(n), Vector2(130, 48)))
	else:
		h.add_child(UiKit.label("Verrouillé", 14, UiKit.DIM))
	if not open:
		panel.modulate = Color(1, 1, 1, 0.55)
	return panel
