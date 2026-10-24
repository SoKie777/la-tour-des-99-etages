extends Control
## Héros (modèle Dragon Traveler) : fiche, niveaux (Encre et Pièces, paliers d'Essence, plafond selon
## les étoiles), étoiles par doublons (copies du héros, héros de la même classe, Pions d'encre et
## Poupées en remplacement), Résonance de classe après le niveau 100, compétences et reliques.

const SHOWN_STATS := [["hp", "hp"], ["atk", "atk"], ["pdef", "def"], ["mdef", "res"], ["crit", "cr"], ["haste", "spd"]]

var selected := ""
var slot_selected := 1
var recycle_armed := -1
var reset_armed := false
var fresh: Array[String] = []
var view_box: VBoxContainer
var tabs: TabContainer
var hero_box: VBoxContainer
var skill_box: VBoxContainer
var relic_box: VBoxContainer
var roster_grid: GridContainer
var filter_class := ""


func _ready() -> void:
	var p := Session.profile
	var owned := p.owned_ids()
	var team := p.formation_ids()
	selected = team[0] if not team.is_empty() else (owned[0] if not owned.is_empty() else "eirikr")
	var content := UiKit.screen(self, "Héros")
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	content.add_child(cols)
	fresh = p.unseen.duplicate()
	p.unseen.clear()
	Session.save()
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size.x = 372
	cols.add_child(left_col)
	var b := p.account_bonus()
	left_col.add_child(UiKit.rich("Codex : %d ★   ·   ATK et PV +%.1f %%" % [p.codex_stars(), float(b["atk_pct"])], 15, UiKit.ACCENT))
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 4)
	left_col.add_child(filters)
	filters.add_child(UiKit.button("Tous", _filter.bind(""), Vector2(56, 36)))
	for c in HeroDb.class_order():
		var fb := UiKit.icon_button(UiKit.class_icon(c), _filter.bind(c), 36)
		fb.tooltip_text = HeroDb.class_info(c)["name"]
		filters.add_child(fb)
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
	view_box.custom_minimum_size.x = 300
	cols.add_child(view_box)
	tabs = TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(tabs)
	hero_box = _tab("Progression")
	skill_box = _tab("Compétences")
	relic_box = _tab("Reliques")
	_select(selected)


func _tab(title: String) -> VBoxContainer:
	var s := ScrollContainer.new()
	s.name = title
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(s)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	s.add_child(v)
	return v


func _filter(cls: String) -> void:
	filter_class = cls
	_build_roster()


func _select(id: String) -> void:
	selected = id
	reset_armed = false
	_build_roster()
	for c in view_box.get_children():
		c.queue_free()
	view_box.add_child(UiKit.model_view([id], Vector2i(300, 360)))
	var h := HeroDb.hero(id)
	view_box.add_child(UiKit.label(h["name"], 24, UiKit.rarity_color(id)))
	var facs: Array[String] = []
	var star := Session.profile.best_star(id)
	for i in h["factions"].size():
		var f: String = h["factions"][i]
		var active: bool = i == 0 or star >= 6
		facs.append("%s %s%s" % [UiKit.bb("f_" + f, 18, UiKit.faction_color(f).lightened(0.2) if active else UiKit.DIM),
			UiKit.faction_name(f), "" if active else " (6★)"])
	view_box.add_child(UiKit.rich("%s  %s   %s\n%s" % [UiKit.RARITY_NAMES.get(int(h["rarity"]), ""), UiKit.bb(UiKit.class_icon(h["class"]), 18),
		UiKit.class_name_of(id), "   ".join(facs)], 15, UiKit.PAPER))
	_refresh_details()


func _refresh_details() -> void:
	_build_hero()
	_build_skills()
	_build_relics()


func _build_roster() -> void:
	var p := Session.profile
	for c in roster_grid.get_children():
		c.queue_free()
	var ids := HeroDb.playable_ids()
	ids.sort_custom(func(a: String, b: String) -> bool:
		if p.owns(a) != p.owns(b):
			return p.owns(a)
		return int(HeroDb.hero(a)["rarity"]) > int(HeroDb.hero(b)["rarity"]))
	for id in ids:
		var h := HeroDb.hero(id)
		if filter_class != "" and h["class"] != filter_class:
			continue
		var owns := p.owns(id)
		if not owns and h.get("substitute", false):
			continue
		var sub: String = "Niv. %d  ×%d" % [p.effective_level(id), p.copies(id)] if owns else UiKit.RARITY_NAMES.get(int(h["rarity"]), "")
		var card := UiKit.char_card(id, _select.bind(id), id == selected, not owns, p.best_star(id), sub)
		card.disabled = not owns
		roster_grid.add_child(card)
		if id in fresh:
			UiKit.badge(card, "+")


func _cost_bb(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for k: String in cost:
		var have := Session.profile.amount(k)
		var col := "f5f0e6" if have >= int(cost[k]) else "ff8a7a"
		parts.append("%s [color=#%s]%s[/color]" % [UiKit.bb(k, 14), col, UiKit.thousands(int(cost[k]))])
	return "  ".join(parts)


func _build_hero() -> void:
	var p := Session.profile
	for c in hero_box.get_children():
		c.queue_free()
	var id := selected
	var s := p.hero_stats(id)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	hero_box.add_child(grid)
	for pair: Array in SHOWN_STATS:
		grid.add_child(UiKit.icon(pair[1], 18, UiKit.DIM))
		grid.add_child(UiKit.label(UiKit.thousands(int(round(float(s[pair[0]])))), 15))
	hero_box.add_child(UiKit.rich("%s Puissance %s" % [UiKit.bb("atk", 16, UiKit.HIGHLIGHT), UiKit.thousands(HeroDb.power_of(s))], 15, UiKit.HIGHLIGHT))
	hero_box.add_child(HSeparator.new())
	# Niveau
	var lvl := p.level(id)
	var cap := p.level_cap(id)
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 8)
	hero_box.add_child(lrow)
	var ll := UiKit.label("Niveau %d / %d" % [lvl, cap], 18, UiKit.ACCENT)
	ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lrow.add_child(ll)
	if lvl < 100:
		var cost := p.level_cost(id)
		lrow.add_child(UiKit.rich(_cost_bb(cost), 14))
		var up := UiKit.button("+1", func() -> void:
			if p.level_up(id):
				UiJuicer.play_sfx("buff")
				_changed(), Vector2(60, 40))
		up.disabled = not p.can_level(id)
		lrow.add_child(up)
		var up10 := UiKit.button("+10", func() -> void:
			if p.level_up_many(id, 10) > 0:
				UiJuicer.play_sfx("buff")
				_changed(), Vector2(64, 40))
		up10.disabled = not p.can_level(id)
		lrow.add_child(up10)
		if lvl >= cap:
			hero_box.add_child(UiKit.label("Plafond atteint : monte les étoiles pour aller plus haut.", 13, UiKit.DIM))
	else:
		var cls := str(HeroDb.hero(id)["class"])
		var crow := HBoxContainer.new()
		crow.add_theme_constant_override("separation", 8)
		hero_box.add_child(crow)
		var cl := UiKit.label("Résonance %s : niveau %d / %d" % [HeroDb.class_info(cls)["name"], p.class_level(cls), p.class_cap(cls)], 15, UiKit.CYAN)
		cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crow.add_child(cl)
		crow.add_child(UiKit.rich(_cost_bb(p.class_level_cost(cls)), 14))
		var cu := UiKit.button("+1", func() -> void:
			if p.class_level_up(cls):
				UiJuicer.play_sfx("buff")
				_changed(), Vector2(60, 40))
		cu.disabled = not p.can_class_level(cls)
		crow.add_child(cu)
		hero_box.add_child(UiKit.label("Tous les héros %s de niveau 100 partagent ce niveau de classe." % HeroDb.class_info(cls)["name"], 12, UiKit.DIM))
	hero_box.add_child(HSeparator.new())
	# Étoiles
	var uid := p.best_uid(id)
	var star := p.best_star(id)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	hero_box.add_child(srow)
	var sl := UiKit.rich("Étoiles  %s   (exemplaires : %d)" % [UiKit.stars_bb(star, 20), p.copies(id)], 18, UiKit.ACCENT)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(sl)
	var req := p.star_req(uid)
	if req.is_empty():
		hero_box.add_child(UiKit.label("Étoiles au maximum pour cette rareté.", 14, UiKit.DIM))
	else:
		var cand := p.fodder_candidates(uid)
		var cls := str(HeroDb.hero(id)["class"])
		var lines: Array[String] = []
		if int(req["main"]) > 0:
			lines.append("%d × %s %s  (dispo : %d)" % [int(req["main"]), UiKit.char_name(id), UiKit.stars_bb(int(req["main_star"]), 12), cand["main"].size()])
		if int(req["class"]) > 0:
			lines.append("%d × %s %s de classe %s  (dispo : %d + %d Poupée(s))" % [int(req["class"]), UiKit.bb(UiKit.class_icon(cls), 14),
				UiKit.stars_bb(int(req["class_star"]), 12), HeroDb.class_info(cls)["name"], cand["class"].size(), p.amount("poupee_" + cls)])
		hero_box.add_child(UiKit.rich("Pour %s :\n%s" % [UiKit.stars_bb(star + 1, 16), "\n".join(lines)], 14, UiKit.PAPER, true))
		var auto := p.auto_fodder(uid)
		var up := UiKit.cta(UiKit.button("Monter d'étoile", func() -> void:
			if p.star_up(uid):
				UiJuicer.play_sfx("victory")
				_select(selected), Vector2(220, 46)))
		up.disabled = auto.is_empty()
		hero_box.add_child(up)
		if not auto.is_empty():
			var used: Array[String] = []
			for u: int in auto["main"] + auto["class"]:
				var inst := p.instance(u)
				used.append("%s %s" % [UiKit.char_name(inst["id"]), UiKit.stars_bb(int(inst["star"]), 10)])
			if int(auto["dolls"]) > 0:
				used.append("%d Poupée(s)" % int(auto["dolls"]))
			hero_box.add_child(UiKit.rich("Consommera : " + ", ".join(used), 12, UiKit.DIM, true))
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	hero_box.add_child(tools)
	tools.add_child(UiKit.button("Montée rapide (≤ 6★)", func() -> void:
		if p.quick_star_up() > 0:
			UiJuicer.play_sfx("victory")
		_select(selected), Vector2(220, 40)))
	if star >= int(HeroDb.stars()["reset"]["min_star"]):
		var rb := UiKit.button("Réinitialiser (%d/sem.)" % p.resets_left(Session.now()), func() -> void: pass, Vector2(220, 40))
		rb.pressed.connect(func() -> void:
			if not reset_armed:
				reset_armed = true
				rb.text = "Confirmer : retour à 6★ ?"
				return
			if p.star_reset(uid, Session.now()):
				_select(selected))
		tools.add_child(rb)
	# Pions d'encre (substituts de copie principale)
	var cls2 := str(HeroDb.hero(id)["class"])
	var pc: Dictionary = GameData.progression()["pion_craft"]
	var pion_id := HeroDb.substitute_for(cls2)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	hero_box.add_child(prow)
	var pl := UiKit.rich("%s %s : %d   ·   %s %d" % [UiKit.bb("gelee", 16), UiKit.char_name(pion_id), p.copies(pion_id), UiKit.bb("gelee", 14),
		p.amount("gelee")], 13, UiKit.DIM, true)
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(pl)
	var cb := UiKit.rich_button("Fabriquer  %s %d" % [UiKit.bb("gelee", 14), int(pc["gelee"])], func() -> void:
		if p.craft_pion(cls2) > 0:
			_changed(), Vector2(170, 40), 13)
	cb.disabled = p.amount("gelee") < int(pc["gelee"])
	prow.add_child(cb)


func _build_skills() -> void:
	for c in skill_box.get_children():
		c.queue_free()
	var h := HeroDb.hero(selected)
	var lvl := Session.profile.level(selected)
	var entries := [["overdrive", "Overdrive", UiKit.CYAN], ["skill", "Compétence", UiKit.ACCENT], ["passive", "Passif (niv. %d)" % int(HeroDb.levels()["passive_level"]), UiKit.PAPER], ["talent", "Talent de faction", UiKit.faction_color(str(h["factions"][0])).lightened(0.3)]]
	for e: Array in entries:
		if not h.has(e[0]):
			continue
		var sk: Dictionary = h[e[0]]
		var locked: bool = e[0] == "passive" and lvl < int(HeroDb.levels()["passive_level"])
		skill_box.add_child(UiKit.rich("%s  [b]%s[/b]   [color=#a89cb8]%s%s[/color]" % [UiKit.bb(UiKit.skill_icon_id(sk), 18, e[2]), sk.get("name", ""), e[1],
			"  🔒" if locked else ""], 16, e[2] if not locked else UiKit.DIM))
		skill_box.add_child(UiKit.rich(UiKit.iconize(UiKit.skill_text(sk, e[0])), 14, UiKit.DIM, true))
	skill_box.add_child(HSeparator.new())
	var f: Dictionary = HeroDb.faction(str(h["factions"][0]))
	skill_box.add_child(UiKit.rich("%s  %s : %s" % [UiKit.bb("f_" + str(h["factions"][0]), 18, UiKit.faction_color(str(h["factions"][0]))), f["name"], f["desc"]], 13, UiKit.DIM, true))


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
	if candidates.is_empty():
		relic_box.add_child(UiKit.label("Aucune relique : la Tour et l'Expédition en donnent.", 13, UiKit.DIM))
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
	_build_roster()
