extends Control
## Défis (« Conquête des mythes » de Dragon Traveler) : Défense de la forêt (distance seule), Casse du
## trésor (mêlée seule), Ralliement sauvage (un héros par classe, au score). Tenter un nouveau palier
## est gratuit ; le balayage du meilleur palier consomme un des essais du jour.

var msg := ""


func _ready() -> void:
	_build()


func _build() -> void:
	var content := UiKit.screen(self, "Défis")
	if msg != "":
		content.add_child(UiKit.rich(msg, 15, UiKit.ACCENT, true))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	scroll.add_child(cols)
	for id: String in Challenges.ids():
		cols.add_child(_card(id))


func _card(id: String) -> Control:
	var p := Session.profile
	var c := Challenges.info(id)
	var st := p.challenge_state(id)
	var now := Session.now()
	var open := p.campaign_cleared >= int(c["unlock"])
	var panel := UiKit.panel(UiKit.ACCENT if open else UiKit.CARD_BORDER)
	panel.custom_minimum_size.x = 400
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(UiKit.label(c["name"], 22, UiKit.ACCENT))
	var classes: Array[String] = []
	if c.get("one_per_class", false):
		classes.append("Un héros par classe")
	else:
		for cl: String in Challenges.classes_for(id, now):
			classes.append("%s %s" % [UiKit.bb(UiKit.class_icon(cl), 18), HeroDb.class_info(cl)["name"]])
	v.add_child(UiKit.rich("   ".join(classes), 15))
	v.add_child(UiKit.rich(str(c["desc"]), 13, UiKit.DIM, true))
	if not open:
		v.add_child(UiKit.rich("%s  Étape %d de la campagne" % [UiKit.bb("lock", 18, UiKit.DIM), int(c["unlock"])], 15, UiKit.DIM))
		panel.modulate = Color(1, 1, 1, 0.6)
		return panel
	var team := HBoxContainer.new()  # l'équipe que l'on enverra (les plus puissants des héros autorisés)
	team.add_theme_constant_override("separation", 2)
	v.add_child(team)
	var specs := Challenges.team_specs(id, p, now)
	for s: Dictionary in specs:
		team.add_child(UiKit.portrait(s["id"], 46))
	if specs.is_empty():
		v.add_child(UiKit.label("Aucun héros autorisé.", 14, UiKit.VERMILION.lightened(0.3)))
	var scored := c.has("reward_per_kill")
	var left := p.challenge_attempts(id, now)
	if scored:
		v.add_child(UiKit.label("Record : %d ennemis" % int(st["kills"]), 16, UiKit.PAPER))
	else:
		v.add_child(UiKit.label("Palier franchi : %d / %d" % [int(st["best"]), int(c["tiers"])], 16, UiKit.PAPER))
	v.add_child(UiKit.label("Essais du jour : %d / %d" % [left, int(Challenges.cfg()["daily"])], 14, UiKit.DIM))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	if scored:
		var go := UiKit.cta(UiKit.button("Lancer (1 essai)", func() -> void: Session.start_challenge(id, 1), Vector2(240, 50)))
		go.disabled = left <= 0 or specs.is_empty()
		v.add_child(go)
	else:
		var nxt := int(st["best"]) + 1
		if nxt <= int(c["tiers"]):
			v.add_child(UiKit.rich("Palier %d  ·  %s" % [nxt, _reward_bb(Challenges.reward(id, nxt, 0, now))], 14, UiKit.ACCENT, true))
			var go := UiKit.cta(UiKit.button("Défier le palier %d" % nxt, func() -> void: Session.start_challenge(id, nxt), Vector2(240, 50)))
			go.disabled = specs.is_empty()
			v.add_child(go)
	if int(st["best"]) > 0:
		var rw := Challenges.reward(id, int(st["best"]), int(st["kills"]), now)
		var sw := UiKit.rich_button("Balayer  %s" % _reward_bb(rw), func() -> void:
			var got := p.sweep_challenge(id, Session.now())
			if not got.is_empty():
				Session.save()
				UiJuicer.play_sfx("victory")
				msg = "Balayage : " + _reward_bb(got)
			_build(), Vector2(240, 50), 14)
		sw.disabled = left <= 0
		v.add_child(sw)
	return panel


func _reward_bb(rw: Dictionary) -> String:
	var parts: Array[String] = []
	for k: String in rw:
		parts.append("%s %s" % [UiKit.bb(k, 16), UiKit.thousands(int(rw[k]))])
	return "  ".join(parts)
