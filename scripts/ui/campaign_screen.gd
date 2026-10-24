extends Control
## Campagne (Histoire de Dragon Traveler) : chapitres, étapes, aperçu des ennemis et des récompenses
## de première victoire, revenu de Patrouille au palier atteint.

var chapter := 0
var selected := 0


func _ready() -> void:
	var p := Session.profile
	selected = p.next_stage()
	chapter = int(Campaign.stage_info(selected)["chapter_index"])
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var p := Session.profile
	var content := UiKit.screen(self, "Campagne")
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	content.add_child(tabs)
	var chs := Campaign.chapters()
	var first := 1
	var firsts: Array[int] = []
	for i in chs.size():
		firsts.append(first)
		first += int(chs[i]["stages"])
	for i in chs.size():
		var open := firsts[i] <= p.campaign_cleared + 1
		var b := UiKit.button("%d" % (i + 1), _pick_chapter.bind(i), Vector2(52, 40))
		b.disabled = not open
		if i == chapter:
			b.add_theme_stylebox_override("normal", UiKit.panel_style(Color("4a3a12"), UiKit.ACCENT, 2, 8))
		tabs.add_child(b)
	var ch: Dictionary = chs[chapter]
	var head := UiKit.label("Chapitre %d  ·  %s" % [chapter + 1, ch["name"]], 22, UiKit.ACCENT)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(head)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 18)
	content.add_child(cols)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for k in int(ch["stages"]):
		var n := firsts[chapter] + k
		var info := Campaign.stage_info(n)
		var done := n <= p.campaign_cleared
		var nxt := n == p.campaign_cleared + 1
		var label := ("%d" % (k + 1)) + (" ✓" if done else "") + ("  ☠" if info["boss"] else "")
		var b := UiKit.button(label, _select.bind(n), Vector2(78, 52))
		b.disabled = n > p.campaign_cleared + 1
		var col := UiKit.ACCENT if nxt else (Color("6fd36f") if done else UiKit.CARD_BORDER)
		b.add_theme_stylebox_override("normal", UiKit.panel_style(Color(col, 0.2), col if (nxt or n == selected) else Color(col, 0.6), 3 if n == selected else 1, 8))
		grid.add_child(b)
	cols.add_child(_detail(selected))


func _detail(n: int) -> Control:
	var p := Session.profile
	var info := Campaign.stage_info(n)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 430
	panel.add_theme_stylebox_override("panel", UiKit.card_style())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(UiKit.label("Étape %s%s" % [info["number"], "  ·  Boss" if info["boss"] else ""], 22, UiKit.ACCENT))
	v.add_child(UiKit.label("Ennemis niveau %d" % int(info["level"]), 15, UiKit.DIM))
	var foes := HBoxContainer.new()
	foes.add_theme_constant_override("separation", 4)
	v.add_child(foes)
	var epow := 0
	for s: Dictionary in Campaign.enemy_specs(n):
		var box := VBoxContainer.new()
		box.add_child(UiKit.portrait(s["id"], 60))
		box.add_child(UiKit.rich("[center]%s[/center]" % UiKit.stars_bb(int(s["star"]), 10), 10))
		foes.add_child(box)
		epow += HeroDb.power_of(HeroDb.stats(s["id"], int(s["level"]), int(s["star"]), [], float(s.get("power", 1.0))))
	var mine := p.team_power()
	v.add_child(UiKit.rich("%s  Puissance ennemie %s   ·   la tienne [color=#%s]%s[/color]" % [UiKit.bb("atk", 16), UiKit.thousands(epow),
		("7fe08a" if mine >= epow else "ff8a7a"), UiKit.thousands(mine)], 15, UiKit.PAPER, true))
	if n > p.campaign_cleared:
		v.add_child(UiKit.label("Première victoire", 15, UiKit.ACCENT))
		var rw := Campaign.first_rewards(n)
		var parts: Array[String] = []
		for k: String in rw:
			parts.append("%s %s" % [UiKit.bb(k, 18), UiKit.thousands(int(rw[k]))])
		v.add_child(UiKit.rich("   ".join(parts), 15, UiKit.PAPER, true))
	var rate := Campaign.patrol_rate(maxi(n, p.campaign_cleared))
	v.add_child(UiKit.rich("%s  Patrouille : %s %d / min   %s %d / min" % [UiKit.bb("patrouille", 16, UiKit.ACCENT), UiKit.bb("pieces", 16),
		int(rate["pieces"]), UiKit.bb("encre", 16), int(rate["encre"])], 14, UiKit.DIM, true))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	row.add_child(UiKit.button("Équipe", func() -> void: get_tree().change_scene_to_file("res://scenes/team.tscn"), Vector2(120, 52)))
	var go := UiKit.cta(UiKit.button("Combattre  ›", func() -> void: Session.start_stage(n), Vector2(220, 52)))
	go.disabled = n > p.campaign_cleared + 1 or p.formation.is_empty()
	row.add_child(go)
	return panel


func _pick_chapter(i: int) -> void:
	chapter = i
	var first := 1
	for k in i:
		first += int(Campaign.chapters()[k]["stages"])
	selected = clampi(Session.profile.next_stage(), first, first + int(Campaign.chapters()[i]["stages"]) - 1)
	_build()


func _select(n: int) -> void:
	selected = n
	_build()
