class_name UiKit
extends RefCounted
## Briques d'interface partagées par les écrans (couleurs, icônes, textes, boutons, vue 3D des personnages).
## Règle UI T99 : zéro texte superflu. Ressources, stats et effets s'affichent en icônes vectorielles
## (assets/icons, assets/status_icons : tools/ui_icons.py) ; le texte ne sert qu'aux nombres, aux noms des
## personnages et aux titres de menus.

# Palette officielle (Bible D.A.) : indigo nocturne, or ancien, ivoire papier, rouge sceau, bleu minéral, encre.
const BG := Color("21172f")
const PANEL := Color("2a2040")
const ACCENT := Color("d1ad62")
const DIM := Color("a89cb8")  # texte secondaire (lavande)
const PAPER := Color("f5f0e6")  # texte primaire (ivoire)
const HIGHLIGHT := Color("ffd700")  # valeurs mises en avant
const CYAN := Color("00e5ff")
const CARD_BG := Color(0.098, 0.063, 0.149, 0.9)  # #191026 à 90 %
const CARD_BORDER := Color("4a3763")
const CTA_TOP := Color("e6b84b")
const CTA_BOTTOM := Color("c28e28")
const CTA_EDGE := Color("fff0b3")
const VERMILION := Color("b83a35")
const MINERAL := Color("263c4a")
const INK := Color("332c29")
## Texte du jeu : Fredoka arrondie et grasse (titres : LilitaOne), tailles agrandies de 25 %.
const BODY_FONT := preload("res://assets/fonts/Fredoka-Variable.ttf")
const TITLE_FONT := preload("res://assets/fonts/LilitaOne-Regular.ttf")
const FONT_SCALE := 1.25
const ICON_DIR := "res://assets/icons/"
const CONST_COLORS := {"orion": Color("4a7ab8"), "grande_ourse": Color("c94f35"), "sirius": Color("8e6bb8")}
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


## Stat en BBCode (pour rich()) : icône puis valeur.
static func stat_text(stat: String, value: float) -> String:
	return "%s +%d%s" % [bb(stat.trim_suffix("_pct")), int(value), " %" if stat in PCT_STATS else ""]


static func roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI"][n]


## Relique en BBCode : icône d'ensemble, emplacement, stat principale, niveau.
static func relic_title(r: Dictionary) -> String:
	return "%s %s   %s   [color=#%s]+%d[/color]" % [bb("set_" + str(r["set"]), 18, ACCENT), roman(int(r["slot"])),
		stat_text(r["main"]["stat"], float(r["main"]["value"])), ACCENT.to_html(false), int(r["level"])]


static func relic_subs(r: Dictionary) -> String:
	var parts: Array[String] = []
	for s: String in r["subs"]:
		parts.append(stat_text(s, float(r["subs"][s])))
	return "   ".join(parts)


## Symbole d'une compétence (règle UI : pas de nom écrit en combat). Clé « icon » des données si
## présente, sinon déduit de ce que fait la compétence : effet posé, soin, zone ou frappe simple.
static func skill_icon_id(sk: Dictionary) -> String:
	if sk.has("icon"):
		return str(sk["icon"])
	if sk.has("passive"):
		return "passive"
	var ids: Array[String] = []
	for key in ["effects", "self_effects", "pre_effects", "while_cooldown"]:
		for ef: Dictionary in sk.get(key, []):
			ids.append(str(ef["id"]))
	for h: Dictionary in sk.get("hits", []):
		for ef: Dictionary in h.get("on_hit", []):
			ids.append(str(ef["id"]))
	for id in ids:
		if not id in BattleEngine.ACTIONS and ResourceLoader.exists(ICON_DIR + "fx_" + id + ".svg"):
			return "fx_" + id
	if "heal" in ids or "cleanse" in ids or sk.has("revive") or sk.has("heal_lowest_ally_pct_dmg") or sk.get("target", "") == "all_allies":
		return "support"
	if "ap_down" in ids:
		return "fx_spd_down"
	if "ap_up" in ids:
		return "fx_spd_up"
	return "dps_aoe" if sk.get("target", "") == "all_enemies" else "atk"


## Description courte d'une compétence, tirée de ses données (BBCode : stats et effets en icônes).
static func skill_text(sk: Dictionary) -> String:
	if sk.has("passive"):
		return bb("passive") + " " + str(sk.get("desc", ""))
	var parts: Array[String] = []
	var hits: Array = sk.get("hits", [])
	if not hits.is_empty():
		var strikes: Array[String] = []
		for h: Dictionary in hits:
			var sc: Variant = h.get("scale", "atk")
			var terms: Array[String] = []
			if sc is Dictionary:
				for s: String in sc:
					terms.append("%d %% %s" % [roundi(float(sc[s]) * 100.0), bb(s)])
			else:
				terms.append("%d %% %s" % [roundi(float(h.get("mult", 1.0)) * 100.0), bb(str(sc))])
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
			parts.append("%s %d%s" % [bb_status(ef["id"]), int(ef.get("turns", 1)),
				" (%d %%)" % chance if chance < 100 else ""])
	if sk.has("cd"):
		parts.append("%s %d" % [bb("cooldown"), int(sk["cd"])])
	if sk.has("desc"):
		parts.append(str(sk["desc"]).trim_suffix("."))
	return ". ".join(parts) + "."


# --- Icônes ------------------------------------------------------------------

static func icon_texture(id: String) -> Texture2D:
	var path := ICON_DIR + id + ".svg"
	return load(path) if ResourceLoader.exists(path) else null


static func status_texture(effect_id: String) -> Texture2D:
	var path := "res://assets/status_icons/%s.svg" % effect_id
	return load(path) if ResourceLoader.exists(path) else null


static func icon(id: String, side := 20.0, tint := PAPER) -> TextureRect:
	var t := TextureRect.new()
	t.texture = icon_texture(id)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(side, side)
	t.self_modulate = _icon_tint(tint)  # glyphes dessinés en ivoire
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Icône suivie d'un nombre (ressource, stat…) : seul le chiffre est écrit.
static func amount(id: String, text: String, size := 16, color := PAPER) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.add_child(icon(id, size * 1.25, color))
	var l := label(text, size, color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


## Icône dans un texte BBCode (rich()).
static func bb(id: String, size := 16, tint := PAPER) -> String:
	var path := ICON_DIR + id + ".svg"
	if not ResourceLoader.exists(path):
		return STAT_NAMES.get(id, id)
	return "[img width=%d height=%d color=#%s]%s[/img]" % [size, size, _icon_tint(tint).to_html(), path]


static func bb_status(effect_id: String, size := 16) -> String:
	var path := "res://assets/status_icons/%s.svg" % effect_id
	if not ResourceLoader.exists(path):
		return BattleLog.effect_name(effect_id)
	return "[img width=%d height=%d]%s[/img]" % [size, size, path]


static func _icon_tint(tint: Color) -> Color:
	return Color(minf(tint.r / PAPER.r, 1.0), minf(tint.g / PAPER.g, 1.0), minf(tint.b / PAPER.b, 1.0), tint.a)


## Texte avec icônes (BBCode). wrap : retour à la ligne dans la largeur disponible.
static func rich(text: String, size := 16, color := PAPER, wrap := false) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	if wrap:
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", fs(size))
	r.add_theme_font_size_override("bold_font_size", fs(size))
	r.add_theme_color_override("default_color", color)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.text = _scale_bbcode(text)
	return r


## Les tailles écrites dans le BBCode ([font_size=N]) suivent aussi FONT_SCALE.
static func _scale_bbcode(text: String) -> String:
	if not "[font_size=" in text:
		return text
	var re := RegEx.create_from_string("\\[font_size=(\\d+)\\]")
	var out := ""
	var at := 0
	for m in re.search_all(text):
		out += text.substr(at, m.get_start() - at) + "[font_size=%d]" % fs(int(m.get_string(1)))
		at = m.get_end()
	return out + text.substr(at)


## Remplace les jetons {id} d'un texte par les icônes correspondantes (textes venus du cœur du jeu).
static func iconize(text: String, size := 16, tint := PAPER) -> String:
	var re := RegEx.create_from_string("\\{([a-z_]+)\\}")
	var out := text
	for m in re.search_all(text):
		out = out.replace(m.get_string(), bb(m.get_string(1), size, tint))
	return out


## Bouton dont le libellé contient des icônes (BBCode centré).
static func rich_button(text: String, cb: Callable, min_size := Vector2(150, 52), size := 16, color := PAPER) -> Button:
	var b := button("", cb, min_size)
	var r := rich("[center]%s[/center]" % text, size, color)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.fit_content = false
	r.offset_top = (min_size.y - fs(size) * 1.5) / 2.0
	b.add_child(r)
	return b


## Bouton-icône (Retour, Infos, Journal…), sans texte.
static func icon_button(id: String, cb: Callable, side := 44.0) -> Button:
	var b := Button.new()
	b.icon = icon_texture(id)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(side, side)
	b.add_theme_constant_override("icon_max_width", int(side * 0.55))
	b.pressed.connect(cb)
	juice(b)
	return b


# --- Widgets -----------------------------------------------------------------

## Panneau / carte : violet sombre translucide, liseré indigo, coins de 16 px.
static func card_style() -> StyleBoxFlat:
	return panel_style(CARD_BG, CARD_BORDER, 1, 16)


static func panel_style(bg: Color, border := Color.TRANSPARENT, width := 2, radius := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(10)
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(width)
	return s


## Bouton principal (valider, invoquer...) : or chaud en dégradé, liseré or brillant, ombre portée.
static func cta_style(state := "normal") -> StyleBox:
	var top := CTA_TOP.lightened(0.12 if state == "hover" else 0.0)
	var bottom := CTA_BOTTOM.darkened(0.12 if state == "pressed" else 0.0)
	if state == "disabled":
		return panel_style(Color(PANEL, 0.9), Color(CTA_EDGE, 0.25), 2, 12)
	var s := panel_style(top.lerp(bottom, 0.5), CTA_EDGE, 2, 12)
	s.shadow_color = Color(0, 0, 0, 0.3)  # le dégradé est un reflet posé par cta()
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	return s


## Applique le style « bouton principal » (fond or en dégradé, texte encre 22 px).
static func cta(b: Button) -> Button:
	for st in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, cta_style(st))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_font_size_override("font_size", 22)
	var grad := GradientTexture2D.new()  # reflet en dégradé par-dessus le fond plat
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.97, 0.85, 0.35))
	g.set_color(1, Color(0.45, 0.3, 0.05, 0.25))
	grad.gradient = g
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(0, 1)
	var sheen := TextureRect.new()
	sheen.texture = grad
	sheen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sheen.stretch_mode = TextureRect.STRETCH_SCALE
	sheen.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		sheen.set("offset_" + side, 3.0 if side in ["left", "top"] else -3.0)
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(sheen)
	b.move_child(sheen, 0)
	return b


static func panel(border := Color.TRANSPARENT) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(PANEL, border))
	return p


static func label(text: String, size := 16, color := PAPER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs(size))
	l.add_theme_color_override("font_color", color)
	return l


## Taille de police à l'écran (tailles du code × FONT_SCALE).
static func fs(size: int) -> int:
	return roundi(size * FONT_SCALE)


## Police du jeu à une graisse donnée (400 normal, 600 demi-gras, 700 gras).
static func body_font(weight := 600) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = BODY_FONT
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return f


static func button(text: String, cb: Callable, min_size := Vector2(150, 52)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.pressed.connect(cb)
	juice(b)
	return b


## Bouton qui s'enfonce quand on appuie et rebondit quand on relâche.
static func juice(b: Control) -> void:
	if b is BaseButton:  # les boutons sont animés par l'autoload UiJuicer
		return
	b.resized.connect(func() -> void: b.pivot_offset = b.size / 2.0)
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton or ev is InputEventScreenTouch):
			return
		if b is BaseButton and (b as BaseButton).disabled:
			return
		var tw := b.create_tween()
		if ev.is_pressed():
			tw.tween_property(b, "scale", Vector2(0.94, 0.94), 0.06)
		else:
			tw.tween_property(b, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


## Barre de progression légendée (auto-suivi : le joueur voit où il en est). text : BBCode (icônes).
static func progress(text: String, value: float, maxv: float, col := ACCENT, width := 0.0) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.add_child(rich("%s  %d / %d" % [text, int(value), int(maxv)], 13, PAPER))
	var bar := ProgressBar.new()
	bar.max_value = maxv
	bar.value = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, 10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(BG.darkened(0.4), 0.9)
	bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	v.add_child(bar)
	bar.create_tween().tween_property(bar, "value", value, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return v


## Pastille discrète en haut à droite d'un bouton (suggestion au bon moment).
static func badge(target: Control, text := "!", icon_id := "") -> void:
	var b := PanelContainer.new()
	var st := panel_style(VERMILION, Color.TRANSPARENT, 0, 10)
	st.set_content_margin_all(3)
	st.content_margin_left = 7
	st.content_margin_right = 7
	b.add_theme_stylebox_override("panel", st)
	b.add_child(amount(icon_id, text, 12) if icon_id != "" else label(text, 12, Color.WHITE))
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_right = -6.0  # collée au coin, à l'intérieur du bouton
	b.offset_top = -9.0
	b.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_child(b)
	b.pivot_offset = Vector2(12, 10)
	var tw := b.create_tween().set_loops()
	tw.tween_property(b, "scale", Vector2(1.12, 1.12), 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(b, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)


static func currency_bar() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var labels := {}
	for k in ["eclat_de_voeu", "pieces", "fragments_etage", "energie"]:
		var box := amount(k, "", 15, HIGHLIGHT if k == "eclat_de_voeu" else (Color("9fd8b0") if k == "energie" else PAPER))
		labels[k] = box.get_child(1)
		var pill := PanelContainer.new()  # chaque ressource dans une pastille arrondie
		var ps := panel_style(Color(0.04, 0.02, 0.07, 0.72), Color(ACCENT, 0.3), 1, 20)
		ps.content_margin_left = 12
		ps.content_margin_right = 14
		ps.content_margin_top = 4
		ps.content_margin_bottom = 4
		pill.add_theme_stylebox_override("panel", ps)
		pill.add_child(box)
		h.add_child(pill)
	var refresh := func() -> void:
		for k: String in labels:
			if k != "energie":
				labels[k].text = thousands(Session.profile.amount(k))
		var p: Profile = Session.profile
		p.refresh_energy(Session.now())
		var nxt := p.energy_next_in(Session.now())
		labels["energie"].text = "%d/%d%s" % [p.energy, int(GameData.progression()["energy"]["max"]),
			"  %d:%02d" % [nxt / 60, nxt % 60] if nxt > 0 else ""]
	refresh.call()
	var timer := Timer.new()  # suit les dépenses faites sur l'écran
	timer.wait_time = 0.25
	timer.autostart = true
	timer.timeout.connect(refresh)
	h.add_child(timer)
	return h


## 300000 → « 300 000 » (espace fine des milliers).
static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "\u202f" + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static var _theme: Theme


## Thème commun (Bible D.A.) : fonds indigo, fins liserés d'or ancien, texte ivoire.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = body_font(600)
	t.default_font_size = fs(16)
	t.set_font("normal_font", "RichTextLabel", body_font(600))
	t.set_font("bold_font", "RichTextLabel", body_font(700))
	var normal := panel_style(PANEL, Color(ACCENT, 0.55), 1, 8)
	var hover := panel_style(PANEL.lightened(0.08), ACCENT, 2, 8)
	var pressed := panel_style(PANEL.lightened(0.16), ACCENT.lightened(0.2), 2, 8)
	var disabled := panel_style(BG.darkened(0.2), Color(ACCENT, 0.15), 1, 8)
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, PAPER)
		t.set_color("font_hover_color", cls, Color("fff6e0"))
		t.set_color("font_disabled_color", cls, Color(PAPER, 0.35))
		t.set_color("icon_normal_color", cls, PAPER)
		t.set_color("icon_hover_color", cls, Color("fff6e0"))
		t.set_color("icon_disabled_color", cls, Color(PAPER, 0.35))
	t.set_color("font_color", "Label", PAPER)
	t.set_font_size("font_size", "Button", 22)
	t.set_stylebox("panel", "PanelContainer", card_style())
	t.set_stylebox("panel", "Panel", card_style())
	t.set_stylebox("panel", "TabContainer", panel_style(Color(BG, 0.9), Color.TRANSPARENT, 0, 8))
	t.set_stylebox("tab_selected", "TabContainer", panel_style(PANEL.lightened(0.06), ACCENT, 1, 6))
	t.set_stylebox("tab_unselected", "TabContainer", panel_style(BG.darkened(0.2), Color.TRANSPARENT, 0, 6))
	_theme = t
	return t


## Fond + marges + en-tête (Retour, titre, monnaies). Renvoie le conteneur du contenu.
static func screen(owner: Control, title: String, back_scene := "res://scenes/main.tscn") -> VBoxContainer:
	for c in owner.get_children():
		c.queue_free()
	owner.theme = theme()
	var bg := TextureRect.new()  # fond en dégradé (indigo nocturne vers encre)
	var grad := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, BG.lightened(0.08))
	g.set_color(1, Color("0d0914"))
	grad.gradient = g
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.3, 0.35)
	grad.fill_to = Vector2(1.1, 1.1)
	bg.texture = grad
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
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
		head.add_child(icon_button("back", func() -> void: owner.get_tree().change_scene_to_file(back_scene)))
	var t := label(title, 32, ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(currency_bar())
	var content := VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	v.add_child(content)
	return content


## Carte d'un personnage : nom, étoiles, classe, liseré de constellation.
## Icône estampe du personnage (assets/portraits, générées par tools/ukiyoe_portraits.py), ou null.
static func portrait_texture(id: String) -> Texture2D:
	var path := "res://assets/portraits/%s.png" % id
	if not ResourceLoader.exists(path):  # boss au modèle provisoire : portrait de ce modèle
		path = "res://assets/portraits/%s.png" % CharacterModel.model_id(id)
	if not ResourceLoader.exists(path):
		path = "res://assets/portraits/%s.png" % id.trim_suffix("_" + id.get_slice("_", id.get_slice_count("_") - 1))
	return load(path) if ResourceLoader.exists(path) else null


static func portrait(id: String, side: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = portrait_texture(id)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(side, side)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func char_card(id: String, cb: Callable, selected := false, locked := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(170, 86)
	var col := char_color(id)
	var normal := panel_style(Color(col, 0.18) if not locked else Color(PANEL, 0.6), col if selected else Color(col, 0.5), 3 if selected else 1)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", panel_style(Color(col, 0.3), col, 2))
	b.add_theme_stylebox_override("pressed", panel_style(Color(col, 0.4), col, 3))
	var rarity := int(GameData.character(id)["rarity"]) if GameData.characters().has(id) else 3
	b.text = "%s\n%s" % [char_name(id) if not locked else "???", "★".repeat(rarity)]
	if GameData.characters().has(id) and not locked:  # classe en icône, en haut à droite
		var ci := icon(str(GameData.character(id)["class"]), 18, Color(PAPER, 0.8))
		ci.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		ci.offset_left = -24
		ci.offset_top = 6
		ci.offset_right = -6
		ci.offset_bottom = 24
		b.add_child(ci)
	b.add_theme_color_override("font_color", RARITY_COLORS[rarity] if not locked else DIM)
	if not locked:
		b.icon = portrait_texture(id)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 64)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true  # un nom long ne doit pas écraser l'icône
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.add_theme_font_size_override("font_size", fs(13))
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
	var stage := Node3D.new()  # léger balancement : les personnages vivent à l'écran
	world.add_child(stage)
	stage.rotation_degrees.y = -6.0
	var sway := stage.create_tween().set_loops()
	sway.tween_property(stage, "rotation_degrees:y", 6.0, 3.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sway.tween_property(stage, "rotation_degrees:y", -6.0, 3.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for i in ids.size():
		var m := CharacterModel.new()
		stage.add_child(m)
		m.position = Vector3((i - (ids.size() - 1) / 2.0) * spacing, 0, 0)
		m.rotation_degrees.y = 18.0 * ((ids.size() - 1) / 2.0 - i) if ids.size() > 1 else 0.0
		m.setup(ids[i], char_color(ids[i]))
		m.play(action)
	var pedestal := BattleFx.flat_ring(ACCENT, 0.4 + ids.size() * 0.45, 0.04, 1.0)  # socle lumineux
	world.add_child(pedestal)
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 4.5, 1.5)
	spot.rotation_degrees = Vector3(-72, 0, 0)
	spot.light_energy = 2.0
	spot.spot_angle = 30.0
	spot.light_color = Color("fff0dc")
	world.add_child(spot)
	var cam := Camera3D.new()
	var width := maxf(1.6, ids.size() * spacing)
	cam.fov = 35
	cam.position = Vector3(0, 1.0, 1.9 + width * 1.15)
	world.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 0.92, 0))
	return svc
