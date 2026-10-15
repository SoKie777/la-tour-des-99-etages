extends Control
## Menu MVP : lancer un combat de test et essayer l'invocation.

const MATCHUPS := [
	["Nation A (Orion) vs Nation B (Grande Ourse)", "A", "B"],
	["Nation B (Grande Ourse) vs Nation C (Sirius)", "B", "C"],
	["Nation C (Sirius) vs Nation A (Orion)", "C", "A"],
]
const RARITY_COLORS := {3: Color("8fa3c0"), 4: Color("b07de0"), 5: Color("e8b84a")}

var pity_label: Label
var results_grid: GridContainer


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("14121f")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 48)
	margin.add_child(cols)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	cols.add_child(left)
	var title := Label.new()
	title.text = "LA TOUR DES 99 ÉTAGES"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color("c9a24a"))
	left.add_child(title)
	var sub := Label.new()
	sub.text = "MVP · combat 3 contre 3 à barre d'action"
	left.add_child(sub)
	left.add_child(HSeparator.new())
	for m in MATCHUPS:
		var b := Button.new()
		b.text = m[0]
		b.custom_minimum_size.y = 48
		b.pressed.connect(_start_battle.bind(m[1], m[2]))
		left.add_child(b)
	var auto := CheckButton.new()
	auto.text = "Combat automatique"
	auto.button_pressed = Session.auto_battle
	auto.toggled.connect(func(on: bool) -> void: Session.auto_battle = on)
	left.add_child(auto)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	cols.add_child(right)
	var gtitle := Label.new()
	gtitle.text = Session.gacha.banner["name"]
	gtitle.add_theme_font_size_override("font_size", 28)
	right.add_child(gtitle)
	var row := HBoxContainer.new()
	right.add_child(row)
	for n in [1, 10]:
		var b := Button.new()
		b.text = "Invoquer x%d" % n
		b.custom_minimum_size = Vector2(160, 48)
		b.pressed.connect(_pull.bind(n))
		row.add_child(b)
	pity_label = Label.new()
	right.add_child(pity_label)
	results_grid = GridContainer.new()
	results_grid.columns = 5
	results_grid.add_theme_constant_override("h_separation", 8)
	results_grid.add_theme_constant_override("v_separation", 8)
	right.add_child(results_grid)
	_update_pity()


func _start_battle(a: String, b: String) -> void:
	Session.player_team.assign(GameData.character_ids_by_nation(a))
	Session.enemy_team.assign(GameData.character_ids_by_nation(b))
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


func _pull(n: int) -> void:
	var results := Session.gacha.pull_many(n)
	Session.record_pulls(results)
	for c in results_grid.get_children():
		c.queue_free()
	for r in results:
		var p := PanelContainer.new()
		var s := StyleBoxFlat.new()
		s.bg_color = Color(RARITY_COLORS[r["rarity"]], 0.25)
		s.border_color = RARITY_COLORS[r["rarity"]]
		s.set_border_width_all(2)
		s.set_corner_radius_all(6)
		s.set_content_margin_all(8)
		p.add_theme_stylebox_override("panel", s)
		p.custom_minimum_size = Vector2(120, 70)
		var l := Label.new()
		var id: String = r["id"]
		var label_name: String = GameData.character(id)["name"] if GameData.characters().has(id) else id.capitalize()
		l.text = "%s\n%s" % ["★".repeat(r["rarity"]), label_name]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.add_child(l)
		results_grid.add_child(p)
	_update_pity()


func _update_pity() -> void:
	var g := Session.gacha
	pity_label.text = "Invocations : %d · Légendaire garanti dans %d · Épique garanti dans %d" % [
		g.total_pulls, int(g.banner["hard_pity_5"]) - g.pity_5, int(g.banner["guarantee_4_every"]) - g.pity_4]
