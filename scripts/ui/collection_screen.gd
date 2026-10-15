extends Control
## Collection : fiche du personnage (modèle 3D, stats, compétences) et équipement des reliques.

const SHOWN_STATS := ["hp", "atk", "def", "spd", "cr", "cd", "acc", "res"]

var selected := ""
var slot_selected := 1
var view_box: VBoxContainer
var stats_box: VBoxContainer
var relic_box: VBoxContainer
var roster_grid: GridContainer


func _ready() -> void:
	var owned := Session.profile.owned_ids()
	selected = Session.profile.team[0] if not Session.profile.team.is_empty() else owned[0]
	var content := UiKit.screen(self, "Collection et reliques")
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	content.add_child(cols)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 360
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(scroll)
	roster_grid = GridContainer.new()
	roster_grid.columns = 2
	roster_grid.add_theme_constant_override("h_separation", 8)
	roster_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(roster_grid)

	view_box = VBoxContainer.new()
	view_box.custom_minimum_size.x = 330
	cols.add_child(view_box)

	var right := TabContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	stats_box = VBoxContainer.new()
	stats_box.name = "Fiche"
	right.add_child(stats_box)
	var relic_scroll := ScrollContainer.new()
	relic_scroll.name = "Reliques"
	relic_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(relic_scroll)
	relic_box = VBoxContainer.new()
	relic_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	relic_box.add_theme_constant_override("separation", 8)
	relic_scroll.add_child(relic_box)
	_select(selected)


func _select(id: String) -> void:
	selected = id
	_build_roster()
	for c in view_box.get_children():
		c.queue_free()
	view_box.add_child(UiKit.model_view([id], Vector2i(330, 420)))
	var d := GameData.character(id)
	var cons := GameData.constellation_of(d["nation"])
	view_box.add_child(UiKit.label(d["name"], 24, UiKit.RARITY_COLORS[int(d["rarity"])]))
	view_box.add_child(UiKit.label("%s · %s\n%s · Voie : %s" % ["★".repeat(int(d["rarity"])), UiKit.CLASS_NAMES[d["class"]],
		UiKit.CONST_NAMES[cons], d["voie"]], 14, UiKit.CONST_COLORS[cons]))
	_refresh_details()


func _refresh_details() -> void:
	_build_stats()
	_build_relics()


func _build_roster() -> void:
	for c in roster_grid.get_children():
		c.queue_free()
	for id: String in GameData.characters():
		var owns := Session.profile.owns(id)
		var card := UiKit.char_card(id, _select.bind(id), id == selected, not owns)
		card.custom_minimum_size = Vector2(170, 78)
		card.disabled = not owns
		roster_grid.add_child(card)


func _build_stats() -> void:
	for c in stats_box.get_children():
		c.queue_free()
	var d := GameData.character(selected)
	var unit := Session.profile.make_unit(selected)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	stats_box.add_child(UiKit.label("Stats (base → avec reliques)", 16, UiKit.ACCENT))
	stats_box.add_child(grid)
	for s: String in SHOWN_STATS:
		var base := float(d["stats"][s])
		var final := float(unit.base[s])
		var pct := s in ["cr", "cd", "acc", "res"]
		grid.add_child(UiKit.label(UiKit.STAT_NAMES[s], 15, UiKit.DIM))
		var txt := "%d%s" % [int(final), " %" if pct else ""]
		if int(final) != int(base):
			txt = "%d → %s" % [int(base), txt]
		grid.add_child(UiKit.label(txt, 15, UiKit.ACCENT if int(final) != int(base) else Color.WHITE))
	if not unit.set_specials.is_empty():
		stats_box.add_child(UiKit.label("Effets de sets : " + ", ".join(unit.set_specials), 13, UiKit.DIM))
	stats_box.add_child(HSeparator.new())
	stats_box.add_child(UiKit.label("Compétences", 16, UiKit.ACCENT))
	for i in 3:
		var sk: Dictionary = d["skills"][i]
		stats_box.add_child(UiKit.label(["S1", "S2", "Ultime"][i] + " · " + sk["name"], 15))
		var desc := UiKit.label(UiKit.skill_text(sk), 13, UiKit.DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD
		stats_box.add_child(desc)


func _build_relics() -> void:
	var p := Session.profile
	for c in relic_box.get_children():
		c.queue_free()
	var slots := GridContainer.new()
	slots.columns = 3
	slots.add_theme_constant_override("h_separation", 6)
	slots.add_theme_constant_override("v_separation", 6)
	relic_box.add_child(slots)
	var worn: Dictionary = p.equipped.get(selected, {})
	for slot in range(1, 7):
		var r := p.relic(int(worn[str(slot)])) if worn.has(str(slot)) else {}
		var txt := "%s · vide" % UiKit.roman(slot) if r.is_empty() else "%s %s\n%s +%d" % [UiKit.roman(slot),
			UiKit.SET_NAMES.get(r["set"], r["set"]), UiKit.stat_text(r["main"]["stat"], float(r["main"]["value"])), int(r["level"])]
		var b := UiKit.button(txt, _pick_slot.bind(slot), Vector2(150, 58))
		if slot == slot_selected:
			b.add_theme_stylebox_override("normal", UiKit.panel_style(Color(UiKit.ACCENT, 0.25), UiKit.ACCENT))
		slots.add_child(b)
	var active := Relics.active_sets(p.equipped_relics(selected))
	if not active.is_empty():
		var names: Array[String] = []
		for s: String in active:
			names.append("%s (%d pièces)" % [UiKit.SET_NAMES.get(s, s), active[s]])
		relic_box.add_child(UiKit.label("Sets actifs : " + ", ".join(names), 14, UiKit.ACCENT))

	relic_box.add_child(UiKit.label("Reliques de l'emplacement %s (gagnées dans la Tour)" % UiKit.roman(slot_selected), 15, UiKit.DIM))
	var candidates: Array[Dictionary] = []
	for r in p.relics:
		if int(r["slot"]) == slot_selected:
			candidates.append(r)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["level"]) > int(b["level"]))
	if candidates.is_empty():
		relic_box.add_child(UiKit.label("Aucune pour l'instant.", 14, UiKit.DIM))
	for r in candidates:
		relic_box.add_child(_relic_row(r))


func _relic_row(r: Dictionary) -> Control:
	var p := Session.profile
	var uid := int(r["uid"])
	var owner := p.owner_of(uid)
	var panel := UiKit.panel(UiKit.ACCENT if owner == selected else Color.TRANSPARENT)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	panel.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UiKit.label(UiKit.relic_title(r), 15))
	var sub := UiKit.label(UiKit.relic_subs(r) + ("" if owner == "" else "   · porté par " + UiKit.char_name(owner)), 12, UiKit.DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(sub)
	if owner == selected:
		h.add_child(UiKit.button("Retirer", func() -> void:
			p.unequip(selected, int(r["slot"]))
			_changed(), Vector2(96, 44)))
	else:
		h.add_child(UiKit.button("Équiper", func() -> void:
			p.equip(selected, uid)
			_changed(), Vector2(96, 44)))
	var maxed := int(r["level"]) >= int(GameData.relics()["max_level"])
	var cost := p.relic_level_cost(r)
	var up := UiKit.button("Max" if maxed else "+1\n%d P." % cost, func() -> void:
		p.level_relic(uid, Session.rng)
		_changed(), Vector2(84, 44))
	up.disabled = maxed or p.amount("pieces") < cost
	h.add_child(up)
	return panel


func _pick_slot(slot: int) -> void:
	slot_selected = slot
	_build_relics()


func _changed() -> void:
	Session.save()
	_refresh_details()
