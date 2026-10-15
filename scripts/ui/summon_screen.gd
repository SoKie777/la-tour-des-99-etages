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
	info.add_child(UiKit.label("★ %s" % ", ".join(featured), 15))
	# transparence : taux et garanties visibles (docs/CAPTOLOGIE.md)
	var rates: Dictionary = g.banner["rates"]
	var rate_txt: Array[String] = []
	for r in [3, 4, 5]:
		rate_txt.append("[color=#%s]%s[/color] %s %%" % [UiKit.RARITY_COLORS[r].to_html(false), "★".repeat(r), str(rates[str(r)]).trim_suffix(".0")])
	info.add_child(UiKit.rich("    ".join(rate_txt), 14, UiKit.DIM))
	info.add_child(UiKit.progress("[color=#%s]★★★★★[/color]" % UiKit.RARITY_COLORS[5].to_html(false), g.pity_5, int(g.banner["hard_pity_5"]), UiKit.RARITY_COLORS[5], 300))
	info.add_child(UiKit.progress("[color=#%s]★★★★+[/color]" % UiKit.RARITY_COLORS[4].to_html(false), g.pity_4, int(g.banner["guarantee_4_every"]), UiKit.RARITY_COLORS[4], 300))
	var cost := int(GameData.progression()["pull_cost"])
	var buttons := HBoxContainer.new()  # boutons sous les infos : la ligne tient sur un écran de téléphone
	buttons.add_theme_constant_override("separation", 12)
	info.add_child(buttons)
	for n in [1, 10]:
		var b := UiKit.rich_button("Invoquer ×%d   %s %d" % [n, UiKit.bb("eclat_de_voeu", 18, UiKit.ACCENT), n * cost], _pull.bind(n), Vector2(200, 60))
		b.disabled = Session.profile.amount("eclat_de_voeu") < n * cost
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		buttons.add_child(b)
	if g.banner.has("art") and ResourceLoader.exists(g.banner["art"]):
		var art := TextureRect.new()  # image de bannière façon estampe (tools/make_banner.py)
		art.texture = load(g.banner["art"])
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size = Vector2(480, 270)
		head.add_child(art)
		head.move_child(art, 0)  # l'image à gauche, les infos et les boutons à droite
	elif not g.banner["featured"].is_empty():
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
	var tail := "NOUVEAU !" if r.get("new", false) else "%s +%d" % [UiKit.bb("fragments_etage", 15, col), int(r.get("fragments", 0))]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	h.add_child(UiKit.portrait(r["id"], 72))
	var l := UiKit.rich("[center]%s\n%s\n%s[/center]" % ["★".repeat(rarity), UiKit.char_name(r["id"]), tail], 15, col)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return p
