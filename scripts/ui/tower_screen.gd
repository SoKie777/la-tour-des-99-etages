extends Control
## Ascension de la Tour : liste des étages, adversaires, récompenses, combat, balayage des étages gagnés.

var sweep_msg := ""


func _ready() -> void:
	_build()


func _build() -> void:
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
	var view := UiKit.model_view(p.team, Vector2i(380, 330))
	side.add_child(view)
	side.add_child(UiKit.button("Modifier l'équipe", func() -> void: get_tree().change_scene_to_file("res://scenes/team.tscn"), Vector2(380, 52)))
	if sweep_msg != "":
		side.add_child(UiKit.rich(sweep_msg, 14, UiKit.ACCENT, true))


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
	var title := "%s %d" % [UiKit.bb("floor", 20), n]
	if f.has("boss"):
		title += "  " + UiKit.bb("boss", 20, UiKit.VERMILION.lightened(0.3))
	elif f.get("elite", false):
		title += "  ★"
	var stars := p.floor_stars(n)  # étoiles obtenues (victoire, aucun K.O., victoire rapide)
	var srow: Array[String] = []
	for k in 3:
		srow.append("[color=#%s]★[/color]" % (UiKit.ACCENT if (stars >> k) & 1 == 1 else Color(UiKit.DIM, 0.4)).to_html())
	var weak: Array[String] = []  # faiblesses : constellations qui brisent la Ténacité
	for c in Tower.floor_weaknesses(n):
		weak.append(UiKit.bb(c, 24, UiKit.CONST_COLORS[c].lightened(0.3)))
	var t := UiKit.rich("%s
%s   %s" % [title, "".join(srow), " ".join(weak)], 18, UiKit.ACCENT if f.has("boss") else UiKit.PAPER)
	t.custom_minimum_size.x = 170
	h.add_child(t)
	var names: Array[String] = []
	for id: String in f["enemies"]:
		names.append(UiKit.char_name(id))
	var txt := "%s\n%s %d %%" % [", ".join(names), UiKit.bb("atk", 14), roundi(float(f["power"]) * 100.0)]
	if f.has("boss_unit"):
		var b := GameData.boss(f["boss_unit"])
		txt = "%s · %s\n%s" % [b["name"], b.get("voie", ""), b["skills"][1]["desc"]]
	if open and not cleared:  # anticipation : la récompense de première victoire est annoncée
		var rk := "eclat_de_voeu_boss" if f.has("boss") else ("eclat_de_voeu_elite" if f.get("elite", false) else "eclat_de_voeu")
		txt += "\n★ %s +%d" % [UiKit.bb("eclat_de_voeu", 16, UiKit.ACCENT), int(GameData.tower()["rewards"]["first"][rk])]
	var info := UiKit.rich(txt, 14, UiKit.ACCENT if open and not cleared else UiKit.DIM, true)
	h.add_child(info)
	if open:
		var cost := p.floor_cost(n)
		var fight := UiKit.rich_button(("%s" % UiKit.bb("auto", 18) if cleared else "Combattre") + ("  %s %d" % [UiKit.bb("energie", 16), cost] if cost > 0 else ""),
			func() -> void: Session.start_tower_floor(n), Vector2(150, 50), 15)
		fight.disabled = p.energy < cost
		h.add_child(fight)
		if cleared:
			for times in [1, 5]:
				var sw := UiKit.rich_button("%s ×%d" % [UiKit.bb("speed", 16), times], _sweep.bind(n, times), Vector2(76, 50), 15)
				sw.disabled = cost > 0 and p.energy < cost
				h.add_child(sw)
	else:
		h.add_child(UiKit.icon("lock", 22, UiKit.DIM))
	if not open:
		panel.modulate = Color(1, 1, 1, 0.55)
	return panel


func _sweep(n: int, times: int) -> void:
	var rw := Session.profile.sweep_floor(n, times, Session.rng, Session.now())
	Session.save()
	if int(rw["times"]) == 0:
		sweep_msg = "%s 0" % UiKit.bb("energie", 16, UiKit.VERMILION.lightened(0.3))
	else:
		var sets: Array[String] = []
		for r: Dictionary in rw["relics"]:
			sets.append(UiKit.relic_title(r))
		sweep_msg = "%s %d ×%d   %s +%s\n%s" % [UiKit.bb("floor", 16), n, int(rw["times"]), UiKit.bb("pieces", 16),
			UiKit.thousands(int(rw["currencies"].get("pieces", 0))), "\n".join(sets)]
	_build()
