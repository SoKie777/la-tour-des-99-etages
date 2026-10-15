extends Control
## Invocation : bannière vedette, coût en Éclats de Vœu, garanties, résultats.



func _ready() -> void:
	_build()


func _build() -> void:
	var g := Session.gacha
	var content := UiKit.screen(self, "Invocation")
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	content.add_child(head)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	info.add_child(UiKit.label(g.banner["name"], 26, UiKit.ACCENT))
	var featured: Array[String] = []
	for id: String in g.banner["featured"]:
		featured.append(UiKit.char_name(id))
	info.add_child(UiKit.label("Vedette : %s (chances doublées parmi les 5★)" % ", ".join(featured), 15))
	# transparence : taux et garanties visibles (docs/CAPTOLOGIE.md)
	var rates: Dictionary = g.banner["rates"]
	info.add_child(UiKit.label("Taux : Rare %s %% · Épique %s %% · Légendaire %s %%" % [str(rates["3"]).trim_suffix(".0"), str(rates["4"]).trim_suffix(".0"), str(rates["5"]).trim_suffix(".0")], 14, UiKit.DIM))
	info.add_child(UiKit.progress("Légendaire garanti (compteur)", g.pity_5, int(g.banner["hard_pity_5"]), UiKit.RARITY_COLORS[5], 380))
	info.add_child(UiKit.progress("Épique ou mieux garanti (compteur)", g.pity_4, int(g.banner["guarantee_4_every"]), UiKit.RARITY_COLORS[4], 380))
	info.add_child(UiKit.label("Doublons → Fragments d'étage (promotion, bientôt).", 13, UiKit.DIM))
	var cost := int(GameData.progression()["pull_cost"])
	for n in [1, 10]:
		var b := UiKit.button("Invoquer x%d\n%d Éclats" % [n, n * cost], _pull.bind(n), Vector2(170, 72))
		b.disabled = Session.profile.amount("eclat_de_voeu") < n * cost
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(b)
	if not g.banner["featured"].is_empty():
		head.add_child(UiKit.model_view(g.banner["featured"], Vector2i(220, 260), "victory"))

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)
	for r in Session.last_pulls:
		grid.add_child(_result_card(r))


func _pull(n: int) -> void:
	if not Session.pull(n).is_empty():
		get_tree().change_scene_to_file("res://scenes/summon_cinematic.tscn")


func _result_card(r: Dictionary) -> Control:
	var rarity: int = r["rarity"]
	var col: Color = UiKit.RARITY_COLORS[rarity]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.panel_style(Color(col, 0.22), col, 3 if r.get("new", false) else 1))
	p.custom_minimum_size = Vector2(220, 80)
	var tail := "NOUVEAU !" if r.get("new", false) else "+%d Fragments" % int(r.get("fragments", 0))
	var l := UiKit.label("%s\n%s\n%s" % ["★".repeat(rarity), UiKit.char_name(r["id"]), tail], 15, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p
