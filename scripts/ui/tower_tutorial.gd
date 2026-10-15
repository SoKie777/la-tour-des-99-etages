class_name TowerTutorial
extends Control
## Petit tutoriel du mode tactique de la Tour, page par page, avec un cadre doré autour de la partie de
## l'écran expliquée. Affiché au premier combat de la Tour (et la page « boss » au premier boss), puis à
## la demande avec le bouton « ? » du combat.

signal closed

var pages: Array[Dictionary] = []
var targets := {}
var index := 0
var frame: Panel
var box: PanelContainer
var title: Label
var body: RichTextLabel
var counter: Label
var next_btn: Button
var prev_btn: Button


## Pages du tutoriel. boss : ajoute la page des ultimes hors tour et de la charge.
static func page_list(boss: bool, only_boss := false) -> Array[Dictionary]:
	var b := func(id: String, tint := UiKit.PAPER) -> String: return UiKit.bb(id, 18, tint)
	var cc := UiKit.CONST_COLORS
	var all: Array[Dictionary] = [
		{"title": "La Tour : combat tactique", "target": "", "body":
			"Dans l'Ascension, les combats ont des règles en plus. Voici l'essentiel. Le bouton [b]?[/b] en haut de l'écran les réaffiche à tout moment."},
		{"title": "Le triangle des constellations", "target": "enemies", "body":
			"%s Orion  ›  %s Grande Ourse  ›  %s Sirius  ›  %s Orion\n\nL'emblème devant chaque nom donne sa constellation. Contre celle qu'il domine, un héros gagne +20 de taux critique ; la constellation dominée inflige 15 %% de dégâts en moins." % [
			b.call("orion", cc["orion"]), b.call("grande_ourse", cc["grande_ourse"]), b.call("sirius", cc["sirius"]), b.call("orion", cc["orion"])]},
		{"title": "Ténacité et faiblesses", "target": "enemies", "body":
			"La [b]barre blanche[/b] sous la vie d'un ennemi est sa Ténacité. Seules ses faiblesses l'entament : les emblèmes après %s sur sa fiche (et au-dessus d'un boss). S1 l'entame un peu, S2 davantage, l'ultime beaucoup." % b.call("dmg_taken", UiKit.VERMILION.lightened(0.3))},
		{"title": "La Rupture", "target": "track", "body":
			"Ténacité à zéro : [b]RUPTURE[/b]. L'ennemi recule de 30 % sur la ligne de temps, subit +50 % de dégâts jusqu'à son prochain tour, reçoit un effet de ta constellation (Orion : Lenteur, Grande Ourse : Brûlure, Sirius : DEF −30 %) et tes autres héros le frappent gratuitement. Sa Ténacité revient à son tour suivant."},
		{"title": "Les Sceaux d'équipe", "target": "sceaux", "body":
			"Les losanges en bas sont les Sceaux, communs à toute l'équipe (5 au plus). S1 en rapporte %s +1, S2 en coûte %s −1 (c'est indiqué sur chaque bouton). Alterne : les attaques simples paient les grosses compétences." % [b.call("sceau", UiKit.ACCENT), b.call("sceau", UiKit.VERMILION.lightened(0.35))]},
		{"title": "Composer son équipe", "target": "allies", "body":
			"Prends les constellations qui dominent l'étage : ses faiblesses sont affichées dans la liste des étages.\n[b]Résonance[/b] : 2 héros d'une même constellation donnent un bonus (Orion +10 % VIT, Grande Ourse +12 % ATK, Sirius +15 % PV). Les 3 constellations réunies (Triade) donnent un Sceau de plus."},
		{"title": "Contre un boss", "target": "allies", "boss": true, "body":
			"Chaque héros remplit une [b]jauge dorée[/b] sous sa vie (en jouant et en encaissant). Pleine, le bouton à droite de sa fiche lance son ultime [b]à tout moment[/b], même pendant le tour ennemi, sans perdre son tour.\nLe boss charge parfois une Oblitération (%s et marqueur rouge) : brise sa Ténacité avant son tour suivant, sinon toute l'équipe encaisse.\n★ Certains héros ont dans leur kit une arme contre un boss précis (leur portrait étoilé sur l'étage du boss)." % b.call("charge", UiKit.VERMILION.lightened(0.3))},
		{"title": "Les étoiles", "target": "", "body":
			"%s ★ victoire     %s ★ aucun héros K.O.     %s ★ victoire en 15 actions au plus\n\nChaque nouvelle étoile rapporte 2 %s." % [b.call("titan", UiKit.ACCENT), b.call("hp", UiKit.ACCENT), b.call("speed", UiKit.ACCENT), b.call("eclat_de_voeu", UiKit.ACCENT)]},
	]
	var out: Array[Dictionary] = []
	for p in all:
		var is_boss: bool = p.get("boss", false)
		if only_boss and not is_boss:
			continue
		if is_boss and not boss:
			continue
		out.append(p)
	return out


func start(p: Array[Dictionary], t: Dictionary, first := 0) -> void:
	pages = p
	targets = t
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	frame = Panel.new()  # cadre doré autour de la partie expliquée
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(UiKit.ACCENT, 0.08)
	fs.border_color = UiKit.ACCENT
	fs.set_border_width_all(3)
	fs.set_corner_radius_all(8)
	frame.add_theme_stylebox_override("panel", fs)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	box = PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiKit.panel_style(Color(UiKit.BG, 0.97), UiKit.ACCENT, 2, 10))
	box.custom_minimum_size = Vector2(620, 0)
	add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	box.add_child(v)
	title = UiKit.label("", 22, UiKit.ACCENT)
	v.add_child(title)
	body = UiKit.rich("", 16, UiKit.PAPER, true)
	body.custom_minimum_size.x = 590
	v.add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	prev_btn = UiKit.icon_button("back", func() -> void: _show(index - 1), 44)
	row.add_child(prev_btn)
	counter = UiKit.label("", 14, UiKit.DIM)
	counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(counter)
	next_btn = UiKit.button("", func() -> void: _show(index + 1), Vector2(150, 44))
	row.add_child(next_btn)
	_show.call_deferred(first)


func _show(i: int) -> void:
	if i >= pages.size():
		closed.emit()
		queue_free()
		return
	index = maxi(0, i)
	var p: Dictionary = pages[index]
	title.text = p["title"]
	body.text = p["body"]
	counter.text = "%d / %d" % [index + 1, pages.size()]
	next_btn.text = "Compris" if index == pages.size() - 1 else "Suivant  ›"
	prev_btn.disabled = index == 0
	await get_tree().process_frame  # attendre la mise en page avant de placer le cadre et la bulle
	var vp := get_viewport_rect().size
	var target: Control = targets.get(p["target"]) as Control
	if target != null and is_instance_valid(target) and target.is_visible_in_tree():
		var r := target.get_global_rect().grow(8)
		frame.visible = true
		frame.position = r.position
		frame.size = r.size
		# la bulle se place du côté opposé à la zone expliquée
		box.position = Vector2((vp.x - box.size.x) / 2.0, 70.0 if r.get_center().y > vp.y / 2.0 else vp.y - box.size.y - 40.0)
	else:
		frame.visible = false
		box.position = (vp - box.size) / 2.0
