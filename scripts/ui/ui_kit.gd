class_name UiKit
extends RefCounted
## Briques d'interface partagées par les écrans (couleurs, textes, boutons, vue 3D des personnages).

const BG := Color("14121f")
const PANEL := Color("201c30")
const ACCENT := Color("c9a24a")
const DIM := Color("8f8aa8")
const CONST_COLORS := {"orion": Color("4d8fd6"), "grande_ourse": Color("c8553d"), "sirius": Color("9b6bd6")}
const CONST_NAMES := {"orion": "Orion", "grande_ourse": "Grande Ourse", "sirius": "Sirius"}
const RARITY_COLORS := {3: Color("8fa3c0"), 4: Color("b07de0"), 5: Color("e8b84a")}
const CLASS_NAMES := {
	"dps_single": "DPS mono-cible", "dps_aoe": "DPS zone", "tank_def": "Tank défensif",
	"tank_off": "Tank offensif", "neutralizer": "Neutralisateur", "support": "Support", "titan": "Titan",
}
const STAT_NAMES := {
	"hp": "PV", "atk": "ATK", "def": "DEF", "spd": "VIT", "cr": "TC", "cd": "DC", "acc": "PRÉ", "res": "RÉS",
	"hp_pct": "PV", "atk_pct": "ATK", "def_pct": "DEF", "spd_pct": "VIT",
}
const PCT_STATS := ["hp_pct", "atk_pct", "def_pct", "spd_pct", "cr", "cd", "acc", "res"]
const SET_NAMES := {
	"attaque": "Attaque", "vitesse": "Vitesse", "taux_critique": "Taux critique", "defense": "Défense",
	"immunite": "Immunité", "vampirisme": "Vampirisme", "vie": "Vie", "precision": "Précision", "gel": "Gel",
}
const CURRENCY_NAMES := {"eclat_de_voeu": "Éclats de Vœu", "pieces": "Pièces", "fragments_etage": "Fragments d'étage"}
const RECRUIT_NAMES := {"recrue_orion": "Recrue d'Orion", "recrue_ourse": "Recrue de la Grande Ourse", "recrue_sirius": "Recrue de Sirius"}
const TARGET_NAMES := {"enemy": "un ennemi", "all_enemies": "tous les ennemis", "ally": "un allié", "all_allies": "toute l'équipe", "self": "soi-même"}


# --- Textes -------------------------------------------------------------------

static func char_name(id: String) -> String:
	if GameData.characters().has(id):
		return GameData.character(id)["name"]
	return RECRUIT_NAMES.get(id, id.capitalize())


static func char_color(id: String) -> Color:
	if not GameData.characters().has(id):
		return DIM
	return CONST_COLORS[GameData.constellation_of(GameData.character(id)["nation"])]


static func stat_text(stat: String, value: float) -> String:
	return "%s +%d%s" % [STAT_NAMES.get(stat, stat), int(value), " %" if stat in PCT_STATS else ""]


static func roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI"][n]


static func relic_title(r: Dictionary) -> String:
	return "%s %s · %s · +%d" % [SET_NAMES.get(r["set"], r["set"]), roman(int(r["slot"])),
		stat_text(r["main"]["stat"], float(r["main"]["value"])), int(r["level"])]


static func relic_subs(r: Dictionary) -> String:
	var parts: Array[String] = []
	for s: String in r["subs"]:
		parts.append(stat_text(s, float(r["subs"][s])))
	return "  ".join(parts)


## Description courte d'une compétence, tirée de ses données.
static func skill_text(sk: Dictionary) -> String:
	if sk.has("passive"):
		return "Passif. " + str(sk.get("desc", ""))
	var parts: Array[String] = []
	var hits: Array = sk.get("hits", [])
	if not hits.is_empty():
		var strikes: Array[String] = []
		for h: Dictionary in hits:
			var sc: Variant = h.get("scale", "atk")
			var terms: Array[String] = []
			if sc is Dictionary:
				for s: String in sc:
					terms.append("%d %% %s" % [roundi(float(sc[s]) * 100.0), "PV max" if s == "hp" else STAT_NAMES.get(s, s)])
			else:
				terms.append("%d %% %s" % [roundi(float(h.get("mult", 1.0)) * 100.0), "PV max" if sc == "hp" else STAT_NAMES.get(sc, sc)])
			var txt := " + ".join(terms)
			if int(h.get("repeat", 1)) > 1:
				txt = "%d x (%s)" % [int(h["repeat"]), txt]
			strikes.append(txt)
		parts.append("Frappe %s : %s" % [TARGET_NAMES.get(sk.get("target", ""), "la cible"), ", puis ".join(strikes)])
	elif sk.has("target"):
		parts.append("Cible : " + TARGET_NAMES.get(sk["target"], sk["target"]))
	if not sk.has("desc"):  # la description de la fiche détaille déjà les effets
		for ef: Dictionary in sk.get("effects", []):
			if ef["id"] in BattleEngine.ACTIONS:
				continue
			var chance := int(ef.get("chance", 100))
			parts.append("%s %d tour(s)%s" % [BattleLog.effect_name(ef["id"]), int(ef.get("turns", 1)),
				" (%d %%)" % chance if chance < 100 else ""])
	if sk.has("cd"):
		parts.append("recharge %d" % int(sk["cd"]))
	if sk.has("desc"):
		parts.append(str(sk["desc"]).trim_suffix("."))
	return ". ".join(parts) + "."


# --- Widgets -----------------------------------------------------------------

static func panel_style(bg: Color, border := Color.TRANSPARENT, width := 2, radius := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(10)
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(width)
	return s


static func panel(border := Color.TRANSPARENT) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(PANEL, border))
	return p


static func label(text: String, size := 16, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable, min_size := Vector2(150, 52)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.pressed.connect(cb)
	return b


static func currency_bar() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	var labels := {}
	for k in ["eclat_de_voeu", "pieces", "fragments_etage"]:
		labels[k] = label("", 15, ACCENT if k == "eclat_de_voeu" else Color.WHITE)
		h.add_child(labels[k])
	var en := label("", 15, Color("8fd8a0"))
	h.add_child(en)
	var refresh := func() -> void:
		for k: String in labels:
			labels[k].text = "%s : %d" % [CURRENCY_NAMES[k], Session.profile.amount(k)]
		var p: Profile = Session.profile
		p.refresh_energy(Session.now())
		var nxt := p.energy_next_in(Session.now())
		en.text = "Énergie : %d/%d%s" % [p.energy, int(GameData.progression()["energy"]["max"]),
			"  (+1 dans %d:%02d)" % [nxt / 60, nxt % 60] if nxt > 0 else ""]
	refresh.call()
	var timer := Timer.new()  # suit les dépenses faites sur l'écran
	timer.wait_time = 0.25
	timer.autostart = true
	timer.timeout.connect(refresh)
	h.add_child(timer)
	return h


## Fond + marges + en-tête (Retour, titre, monnaies). Renvoie le conteneur du contenu.
static func screen(owner: Control, title: String, back_scene := "res://scenes/main.tscn") -> VBoxContainer:
	for c in owner.get_children():
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	owner.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	owner.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	if back_scene != "":
		head.add_child(button("Retour", func() -> void: owner.get_tree().change_scene_to_file(back_scene), Vector2(110, 44)))
	var t := label(title, 28, ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(currency_bar())
	var content := VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	v.add_child(content)
	return content


## Carte d'un personnage : nom, étoiles, classe, liseré de constellation.
static func char_card(id: String, cb: Callable, selected := false, locked := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(170, 86)
	var col := char_color(id)
	var normal := panel_style(Color(col, 0.18) if not locked else Color(PANEL, 0.6), col if selected else Color(col, 0.5), 3 if selected else 1)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", panel_style(Color(col, 0.3), col, 2))
	b.add_theme_stylebox_override("pressed", panel_style(Color(col, 0.4), col, 3))
	var rarity := int(GameData.character(id)["rarity"]) if GameData.characters().has(id) else 3
	var cls: String = CLASS_NAMES.get(GameData.character(id)["class"], "") if GameData.characters().has(id) else ""
	b.text = "%s\n%s\n%s" % [char_name(id) if not locked else "???", "★".repeat(rarity), cls]
	b.add_theme_color_override("font_color", RARITY_COLORS[rarity] if not locked else DIM)
	b.pressed.connect(cb)
	return b


## Vue 3D animée d'un ou plusieurs personnages (CharacterModel dans un SubViewport).
static func model_view(ids: Array, view_size: Vector2i, action := "idle") -> SubViewportContainer:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = view_size
	var vp := SubViewport.new()
	vp.size = view_size
	vp.transparent_bg = true
	vp.own_world_3d = true
	svc.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.58, 0.68)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	world.add_child(sun)
	var spacing := 1.0
	for i in ids.size():
		var m := CharacterModel.new()
		world.add_child(m)
		m.position = Vector3((i - (ids.size() - 1) / 2.0) * spacing, 0, 0)
		m.rotation_degrees.y = 18.0 * ((ids.size() - 1) / 2.0 - i) if ids.size() > 1 else 0.0
		m.setup(ids[i], char_color(ids[i]))
		m.play(action)
	var cam := Camera3D.new()
	var width := maxf(1.6, ids.size() * spacing)
	cam.fov = 35
	cam.position = Vector3(0, 1.0, 1.9 + width * 1.15)
	world.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 0.92, 0))
	return svc
