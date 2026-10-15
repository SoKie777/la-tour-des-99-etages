extends Control
## Collection : fiche du personnage (modèle 3D, stats, compétences) et équipement des reliques.

const SHOWN_STATS := ["hp", "atk", "def", "spd", "cr", "cd", "acc", "res"]

var selected := ""
var slot_selected := 1
var recycle_armed := -1
var fresh: Array[String] = []  # personnages vus pour la première fois à cette visite  # relique en attente de confirmation de recyclage
var view_box: VBoxContainer
var stats_box: VBoxContainer
var relic_box: VBoxContainer
var roster_grid: GridContainer


func _ready() -> void:
	var owned := Session.profile.owned_ids()
	selected = Session.profile.team[0] if not Session.profile.team.is_empty() else owned[0]
	var content := UiKit.screen(self, "Collection")
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	content.add_child(cols)

	fresh = Session.profile.unseen.duplicate()
	Session.profile.unseen.clear()
	Session.save()
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size.x = 360
	cols.add_child(left_col)
	left_col.add_child(UiKit.progress("★", Session.profile.owned_ids().size(), GameData.characters().size(), UiKit.ACCENT, 350))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_col.add_child(scroll)
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
	view_box.add_child(UiKit.rich("%s   %s\n%s · %s" % ["★".repeat(int(d["rarity"])), UiKit.bb(str(d["class"]), 18, UiKit.CONST_COLORS[cons]),
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
		if id in fresh:
			UiKit.badge(card, "+")


func _build_stats() -> void:
	for c in stats_box.get_children():
		c.queue_free()
	var d := GameData.character(selected)
	var unit := Session.profile.make_unit(selected)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	stats_box.add_child(grid)
	for s: String in SHOWN_STATS:
		var base := float(d["stats"][s])
		var final := float(unit.base[s])
		var pct := s in ["cr", "cd", "acc", "res"]
		grid.add_child(UiKit.icon(s, 20, UiKit.DIM))
		var txt := "%d%s" % [int(final), " %" if pct else ""]
		if int(final) != int(base):
			txt = "%d → %s" % [int(base), txt]
		grid.add_child(UiKit.label(txt, 15, UiKit.ACCENT if int(final) != int(base) else UiKit.PAPER))
	if not unit.set_specials.is_empty():
		var sp := UiKit.rich("%s  %s" % [UiKit.bb("relique", 16, UiKit.ACCENT), ", ".join(unit.set_specials)], 13, UiKit.DIM, true)
		stats_box.add_child(sp)
	if d.has("boss_bane"):  # arme du kit contre un boss
		var bane: Dictionary = d["boss_bane"]
		stats_box.add_child(UiKit.rich("[color=#%s]★[/color] %s  [b]%s[/b]" % [UiKit.ACCENT.to_html(false),
			UiKit.bb("boss", 18, UiKit.VERMILION.lightened(0.3)), bane["name"]], 15, UiKit.ACCENT))
		stats_box.add_child(UiKit.rich(str(bane["desc"]), 13, UiKit.DIM, true))
	stats_box.add_child(HSeparator.new())
	stats_box.add_child(UiKit.label("Compétences", 16, UiKit.ACCENT))
	for i in 3:
		var sk: Dictionary = d["skills"][i]
		stats_box.add_child(UiKit.rich(("[color=#%s]◆[/color] " % UiKit.VERMILION.lightened(0.3).to_html(false) if i == 2 else "◇ ") + sk["name"], 15))
		stats_box.add_child(UiKit.rich(UiKit.skill_text(sk), 13, UiKit.DIM, true))


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
		var txt := UiKit.roman(slot) if r.is_empty() else "%s %s  %s" % [UiKit.roman(slot),
			UiKit.bb("set_" + str(r["set"]), 16, UiKit.ACCENT), UiKit.stat_text(r["main"]["stat"], float(r["main"]["value"]))]
		var b := UiKit.rich_button(txt, _pick_slot.bind(slot), Vector2(150, 58), 14)
		if slot == slot_selected:
			b.add_theme_stylebox_override("normal", UiKit.panel_style(Color(UiKit.ACCENT, 0.25), UiKit.ACCENT))
		slots.add_child(b)
	var active := Relics.active_sets(p.equipped_relics(selected))
	if not active.is_empty():
		var names: Array[String] = []
		for s: String in active:
			names.append("%s ×%d" % [UiKit.bb("set_" + s, 18, UiKit.ACCENT), active[s]])
		relic_box.add_child(UiKit.rich("   ".join(names), 15, UiKit.ACCENT))

	relic_box.add_child(UiKit.rich("%s %s" % [UiKit.bb("relique", 18), UiKit.roman(slot_selected)], 15, UiKit.DIM))
	var candidates: Array[Dictionary] = []
	for r in p.relics:
		if int(r["slot"]) == slot_selected:
			candidates.append(r)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["level"]) > int(b["level"]))
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
	v.add_child(UiKit.rich(UiKit.relic_title(r), 15))
	v.add_child(UiKit.rich(UiKit.relic_subs(r) + ("" if owner == "" else "   ‹ " + UiKit.char_name(owner)), 12, UiKit.DIM, true))
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
	var up := UiKit.rich_button("MAX" if maxed else "+1  %s %s" % [UiKit.bb("pieces", 14), UiKit.thousands(cost)], func() -> void:
		p.level_relic(uid, Session.rng)
		_changed(), Vector2(110, 44), 13)
	up.disabled = maxed or p.amount("pieces") < cost
	h.add_child(up)
	# recyclage intégral (fiche, partie 5) : deux appuis, car la relique disparaît
	var gain := int(GameData.progression()["relic_recycle_base"]) + p.relic_invested(r)
	var rec := UiKit.rich_button("%s %s +%s" % [UiKit.bb("close", 14) if recycle_armed != uid else "?", UiKit.bb("pieces", 14), UiKit.thousands(gain)], func() -> void:
		if recycle_armed != uid:
			recycle_armed = uid
			_build_relics()
			return
		recycle_armed = -1
		p.recycle_relic(uid)
		_changed(), Vector2(110, 44), 13)
	h.add_child(rec)
	return panel


func _pick_slot(slot: int) -> void:
	slot_selected = slot
	_build_relics()


func _changed() -> void:
	Session.save()
	_refresh_details()
