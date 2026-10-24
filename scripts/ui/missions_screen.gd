extends Control
## Missions (« Dispatch » de Dragon Traveler) : missions du jour, héros envoyés automatiquement (les
## moins puissants qui remplissent la condition), compte à rebours, récolte.

var msg := ""


func _ready() -> void:
	_build()
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(_build)
	add_child(t)


func _build() -> void:
	var timer: Timer = null
	for c in get_children():
		if c is Timer:
			timer = c
	if timer != null:
		remove_child(timer)
	var p := Session.profile
	var now := Session.now()
	var content := UiKit.screen(self, "Missions")
	if timer != null:
		add_child(timer)
	if p.campaign_cleared < int(Dispatch.cfg()["unlock"]):
		content.add_child(UiKit.label("Les missions s'ouvrent à l'étape %d de la campagne." % int(Dispatch.cfg()["unlock"]), 18, UiKit.DIM))
		return
	if msg != "":
		content.add_child(UiKit.rich(msg, 15, UiKit.ACCENT, true))
	content.add_child(UiKit.label("Envoie des héros en mission : ils reviennent avec des ressources. Ils peuvent combattre pendant ce temps.", 14, UiKit.DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	content.add_child(grid)
	var ms := p.dispatch_missions(now)
	for i in ms.size():
		grid.add_child(_card(i, ms[i], now))


func _card(i: int, m: Dictionary, now: int) -> Control:
	var p := Session.profile
	var panel := UiKit.panel(UiKit.ACCENT if not m.get("claimed", false) else UiKit.CARD_BORDER)
	panel.custom_minimum_size = Vector2(600, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := UiKit.label(str(m["name"]), 18, UiKit.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UiKit.label("%d h" % int(m["hours"]), 16, UiKit.PAPER))
	var key := str(m["key"])
	var req := "%s %s" % [UiKit.bb(UiKit.class_icon(key), 18), HeroDb.class_info(key)["name"]] if m["kind"] == "class" \
		else "%s %s" % [UiKit.bb("f_" + key, 18, UiKit.faction_color(key)), UiKit.faction_name(key)]
	v.add_child(UiKit.rich("%d × %s   %s" % [int(m["count"]), req, UiKit.stars_bb(int(m["min_star"]), 13)], 15))
	var parts: Array[String] = []
	for k: String in m["reward"]:
		parts.append("%s %s" % [UiKit.bb(k, 16), UiKit.thousands(int(m["reward"][k]))])
	v.add_child(UiKit.rich("   ".join(parts), 15, UiKit.PAPER))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var left := p.dispatch_left(m, now)
	if m.get("claimed", false):
		row.add_child(UiKit.label("Récoltée ✓", 15, Color("7fe08a")))
	elif left < 0:
		var team := p.dispatch_pick(m)
		for h in team:
			row.add_child(UiKit.portrait(h, 36))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		var go := UiKit.cta(UiKit.button("Envoyer", func() -> void:
			if p.dispatch_start(i, Session.now()):
				Session.save()
			_build(), Vector2(150, 44)))
		go.disabled = team.is_empty()
		if team.is_empty():
			row.add_child(UiKit.label("Pas assez de héros libres", 13, UiKit.DIM))
		row.add_child(go)
	else:
		for h: String in m["heroes"]:
			row.add_child(UiKit.portrait(h, 36))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		if left > 0:
			row.add_child(UiKit.label("%d:%02d:%02d" % [left / 3600, (left / 60) % 60, left % 60], 18, UiKit.CYAN))
		else:
			row.add_child(UiKit.cta(UiKit.button("Récolter", func() -> void:
				var rw := p.dispatch_claim(i, Session.now())
				if not rw.is_empty():
					Session.save()
					UiJuicer.play_sfx("victory")
				_build(), Vector2(150, 44))))
	return panel
