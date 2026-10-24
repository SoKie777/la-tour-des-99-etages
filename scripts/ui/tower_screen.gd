extends Control
## La Tour des 99 Étages (mode à étages, comme les Ruines d'os de Wyrm de Dragon Traveler) :
## un étage après l'autre, Élites régulières, un boss à la fin de chaque univers.


func _ready() -> void:
	_build()


func _build() -> void:
	var p := Session.profile
	var content := UiKit.screen(self, "La Tour des 99 Étages")
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
	var top := mini(Tower.floor_count(), p.tower_cleared + 6)
	for n in range(top, 0, -1):  # du sommet vers la base, comme une tour
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
	side.add_theme_constant_override("separation", 8)
	cols.add_child(side)
	side.add_child(UiKit.model_view(p.formation_ids().slice(0, 4), Vector2i(380, 300)))
	side.add_child(UiKit.label("Étage atteint : %d / %d" % [p.tower_cleared, Tower.floor_count()], 18, UiKit.ACCENT))
	side.add_child(UiKit.rich("%s %s" % [UiKit.bb("atk", 18, UiKit.HIGHLIGHT), UiKit.thousands(p.team_power())], 18, UiKit.HIGHLIGHT))
	side.add_child(UiKit.button("Modifier l'équipe", func() -> void: get_tree().change_scene_to_file("res://scenes/team.tscn"), Vector2(380, 52)))


func _scroll_to(scroll: ScrollContainer, target: Control) -> void:
	await get_tree().process_frame
	scroll.ensure_control_visible(target)


func _floor_row(f: Dictionary) -> Control:
	var p := Session.profile
	var n: int = f["number"]
	var cleared := n <= p.tower_cleared
	var open := n <= p.tower_cleared + 1
	var border := UiKit.ACCENT if open and not cleared else (Color("4a8a5a") if cleared else Color.TRANSPARENT)
	var panel := UiKit.panel(border)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	panel.add_child(h)
	var title := "%s %d" % [UiKit.bb("floor", 20), n]
	if f["boss"] != "":
		title += "  " + UiKit.bb("boss", 20, UiKit.VERMILION.lightened(0.3))
	elif f["elite"]:
		title += "  Élite"
	var t := UiKit.rich("%s\nNiv. %d" % [title, int(f["level"])], 17, UiKit.ACCENT if f["boss"] != "" else UiKit.PAPER)
	t.custom_minimum_size.x = 150
	h.add_child(t)
	var foes := HBoxContainer.new()
	foes.add_theme_constant_override("separation", 2)
	foes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(foes)
	for s: Dictionary in Tower.enemy_specs(n):
		foes.add_child(UiKit.portrait(s["id"], 44))
	if open and not cleared:
		var rw: Dictionary = Tower.cfg()["rewards"]["first"]
		var key := "eclat_de_voeu_boss" if f["boss"] != "" else ("eclat_de_voeu_elite" if f["elite"] else "eclat_de_voeu")
		h.add_child(UiKit.rich("★ %s +%d" % [UiKit.bb("eclat_de_voeu", 16, UiKit.ACCENT), int(rw[key])], 15, UiKit.ACCENT))
	if open:
		var fight := UiKit.button("Rejouer" if cleared else "Combattre", func() -> void: Session.start_tower_floor(n), Vector2(140, 50))
		if not cleared:
			UiKit.cta(fight)
		fight.disabled = p.formation.is_empty()
		h.add_child(fight)
	else:
		h.add_child(UiKit.icon("lock", 22, UiKit.DIM))
		panel.modulate = Color(1, 1, 1, 0.55)
	return panel
