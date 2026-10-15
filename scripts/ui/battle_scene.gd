extends Node3D
## Scène de combat jouable. Personnages : modèle MPFB res://assets/models/<id>.fbx s'il existe,
## sinon le mannequin Y Bot teinté à la couleur de la constellation (voir CharacterModel).

signal finished(winner: int)

const COLORS := {"orion": Color("4d8fd6"), "grande_ourse": Color("c8553d"), "sirius": Color("9b6bd6")}
const UI_BG := Color("14121f")
const UI_ACCENT := Color("c9a24a")
const STACK_NAMES := {"spark": "Étincelle", "fury": "Fureur", "rage": "Rage", "visage": "Visage", "dette": "Dette",
	"clone": "Clones", "inertia": "Inertie"}

var engine: BattleEngine
var pawns := {}        # BattleUnit -> Node3D
var models := {}       # BattleUnit -> CharacterModel
var cards := {}        # BattleUnit -> {hp: ProgressBar, info: Label}
var float_stack := {}  # BattleUnit -> [instant ms, rang] des textes flottants
var log_label: RichTextLabel
var turn_label: Label
var action_box: HBoxContainer
var result_panel: PanelContainer
var waiting_input := false
var done := false


func _ready() -> void:
	var teams := Session.battle_teams()
	engine = BattleEngine.new(teams[0], teams[1])
	engine.battle_event.connect(_on_battle_event)
	_build_world()
	_build_ui()
	_refresh()
	_advance()


# --- Déroulement ------------------------------------------------------------

func _advance() -> void:
	while true:
		if engine.winner != BattleEngine.ONGOING:
			_show_result()
			return
		var actor := engine.next_turn()
		_refresh()
		if actor == null:
			_show_result()
			return
		if not actor.is_alive():
			await _pause(0.3)
			continue
		if not engine.can_act(actor):
			engine.skip_turn(actor)
			_refresh()
			await _pause(0.5)
			continue
		if actor.team == 1 or Session.auto_battle:
			await _pause(0.35)
			var choice := engine.ai_choose(actor)
			await _perform(actor, choice["skill"], choice["target"])
			continue
		_show_actions(actor)
		return


func _perform(actor: BattleUnit, skill_idx: int, target: BattleUnit) -> void:
	_clear_actions()
	var pawn: Node3D = pawns[actor]
	var home := pawn.position
	var focus: BattleUnit = target if target != null else (engine.enemies_of(actor)[0] if actor.skill(skill_idx).get("target", "") == "all_enemies" else actor)
	_play_anim(actor, ["attack", "skill", "ultimate"][skill_idx])
	if focus.team != actor.team:
		var dest := home.lerp(pawns[focus].position, 0.55)
		var tw := create_tween()
		tw.tween_property(pawn, "position", dest, 0.18 / Session.battle_speed)
		await tw.finished
	engine.use_skill(actor, skill_idx, target)
	_refresh()
	var back := create_tween()
	back.tween_property(pawn, "position", home, 0.2 / Session.battle_speed)
	await back.finished
	await _pause(0.25)


func _pause(seconds: float) -> void:
	await get_tree().create_timer(seconds / Session.battle_speed).timeout


func _on_battle_event(ev: Dictionary) -> void:
	var line := BattleLog.describe(ev)
	if line != "" and log_label != null:
		var color := "#c9a24a" if ev["type"] in ["turn_start", "battle_end"] else "#d8d4e8"
		log_label.append_text("[color=%s]%s[/color]\n" % [color, line])
	match ev["type"]:
		"damage":
			_float_text(ev["target"], str(int(ev["amount"])) + ("!" if ev.get("crit", false) else ""), Color("ff6b5b") if ev.get("crit", false) else Color.WHITE)
			_play_anim(ev["target"], "crit_hit" if ev.get("crit", false) else "hit")
		"heal":
			_float_text(ev["target"], "+" + str(int(ev["amount"])), Color("6bdc8a"))
		"resist", "immune":
			_float_text(ev["target"], "Résiste", Color("a0a0b8"))
		"miss":
			_float_text(ev["target"], "Raté", Color("a0a0b8"))
		"phase":
			_float_text(ev["target"], ev["name"].to_upper(), Color("ff8a3d"))
		"bar_break":
			_float_text(ev["target"], "BOUCLIER !", Color("7fc8ff"))
		"shield_punish":
			_float_text(ev["target"], "ÉCRASEMENT", Color("ff5050"))
		"boss_revive":
			_float_text(ev["target"], "RÉSURRECTION", Color("ff8a3d"))
		"clone_absorb":
			_float_text(ev["target"], "Clone !", Color("b07de0"))
		"effect":
			_float_text(ev["target"], BattleLog.effect_name(ev["effect"]), Color("e0c060"))
		"death":
			_play_anim(ev["target"], "death")
			if not models.has(ev["target"]):
				var tw := create_tween()
				tw.tween_property(pawns[ev["target"]], "scale", Vector3(1, 0.15, 1), 0.3)


# --- Monde 3D ---------------------------------------------------------------

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("1b1830")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("8a86b0")
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.2
	add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 5.5, 9.5)
	cam.fov = 45
	add_child(cam)
	cam.look_at(Vector3(0, 0.6, 0))
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16, 10)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("2a2540")
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	for u in engine.units:
		var p := _make_pawn(u)
		var side := -1.0 if u.team == 0 else 1.0
		var alone := engine.units.filter(func(x: BattleUnit) -> bool: return x.team == u.team).size() == 1
		p.position = Vector3(side * 3.2, 0, 0.0 if alone else (u.slot - 1) * 2.0)  # un boss seul se tient au centre
		p.rotation_degrees.y = 90.0 if u.team == 0 else -90.0
		add_child(p)
		pawns[u] = p


func _make_pawn(u: BattleUnit) -> Node3D:
	var root := Node3D.new()
	if CharacterModel.available():
		var model := CharacterModel.new()
		root.add_child(model)
		model.setup(u.id, _col(u), float(u.data.get("height_m", 1.75)))
		models[u] = model
	else:
		var mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.35
		capsule.height = 1.7
		mesh.mesh = capsule
		mesh.position.y = 0.85
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _col(u)
		mesh.material_override = mat
		root.add_child(mesh)
	var label := Label3D.new()
	label.text = u.display_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.15
	label.font_size = 40
	label.outline_size = 8
	label.modulate = _col(u).lightened(0.4)
	root.add_child(label)
	return root


func _col(u: BattleUnit) -> Color:
	return COLORS.get(u.constellation, Color("b8a890"))  # boss neutre


func _play_anim(u: BattleUnit, action: String) -> void:
	var model: CharacterModel = models.get(u)
	if model != null:
		model.play(action)


func _float_text(u: BattleUnit, text: String, color: Color) -> void:
	if not pawns.has(u):
		return
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 56
	l.outline_size = 10
	# textes simultanés sur la même cible : empilés au lieu de se superposer
	var now := Time.get_ticks_msec()
	var last: Array = float_stack.get(u, [0, -1])
	var row: int = last[1] + 1 if now - int(last[0]) < 450 else 0
	float_stack[u] = [now, row]
	l.position = pawns[u].position + Vector3(randf_range(-0.2, 0.2), 2.5 + row * 0.38, 0)
	add_child(l)
	var tw := create_tween()
	tw.set_parallel()
	tw.tween_property(l, "position:y", l.position.y + 1.0, 0.8 / Session.battle_speed)
	tw.tween_property(l, "modulate:a", 0.0, 0.8 / Session.battle_speed)
	tw.chain().tween_callback(l.queue_free)


# --- Interface --------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 10
	root.add_child(top)
	turn_label = Label.new()
	turn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(turn_label)
	var auto := CheckButton.new()
	auto.text = "Auto"
	auto.button_pressed = Session.auto_battle
	auto.toggled.connect(func(on: bool) -> void:
		Session.auto_battle = on
		if on and waiting_input:
			waiting_input = false
			_advance())
	top.add_child(auto)
	var speed := Button.new()
	speed.text = "x%d" % int(Session.battle_speed)
	speed.pressed.connect(func() -> void:
		Session.battle_speed = 1.0 if Session.battle_speed >= 3.0 else Session.battle_speed + 1.0
		speed.text = "x%d" % int(Session.battle_speed))
	top.add_child(speed)
	var back := Button.new()
	back.text = "Quitter"
	back.pressed.connect(_back_to_menu)
	top.add_child(back)

	for team in 2:
		var col := VBoxContainer.new()
		col.position = Vector2(16, 60) if team == 0 else Vector2(1280 - 246, 60)
		col.custom_minimum_size.x = 230
		col.add_theme_constant_override("separation", 8)
		if team == 1:
			col.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			col.offset_left = -246
			col.offset_right = -16
			col.offset_top = 60
			col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		root.add_child(col)
		for u in engine.units:
			if u.team == team:
				col.add_child(_make_card(u))

	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.offset_left = -330
	bottom.offset_right = 330
	bottom.offset_top = -230
	bottom.offset_bottom = -12
	root.add_child(bottom)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.custom_minimum_size.y = 130
	log_label.add_theme_font_size_override("normal_font_size", 13)
	var log_panel := PanelContainer.new()
	log_panel.add_theme_stylebox_override("panel", _panel_style(Color(UI_BG, 0.85)))
	log_panel.add_child(log_label)
	bottom.add_child(log_panel)
	action_box = HBoxContainer.new()
	action_box.alignment = BoxContainer.ALIGNMENT_CENTER
	action_box.custom_minimum_size.y = 64
	action_box.add_theme_constant_override("separation", 10)
	bottom.add_child(action_box)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	result_panel = PanelContainer.new()
	result_panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(UI_BG, 0.95), UI_ACCENT, 2, 10))
	result_panel.custom_minimum_size.x = 460
	result_panel.visible = false
	center.add_child(result_panel)


func _make_card(u: BattleUnit) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(UI_BG, 0.85), _col(u)))
	var v := VBoxContainer.new()
	panel.add_child(v)
	var name_label := Label.new()
	var voie: String = u.data.get("voie", "")
	name_label.text = u.display_name if voie in ["", "À définir"] else "%s  ·  %s" % [u.display_name, voie]
	v.add_child(name_label)
	var hp := ProgressBar.new()
	hp.max_value = u.max_hp()
	hp.show_percentage = false
	hp.custom_minimum_size.y = 12
	v.add_child(hp)
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 12)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(info)
	cards[u] = {"hp": hp, "info": info}
	return panel


func _panel_style(bg: Color, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.set_content_margin_all(8)
	if border.a > 0.0:
		s.border_color = border
		s.border_width_left = 4
	return s


func _refresh() -> void:
	for u: BattleUnit in cards:
		var c: Dictionary = cards[u]
		c["hp"].value = u.hp
		var parts: Array[String] = ["PV %d/%d" % [int(u.hp), int(u.max_hp())], "PA %d %%" % int(u.ap * 100.0)]
		if u.shield_value() > 0.0:
			parts.append("Bouclier %d" % int(u.shield_value()))
		for e in u.effects:
			var turns := int(e["turns"])
			var label := BattleLog.effect_name(e["id"]) + (" x%d" % int(e["stacks"]) if int(e.get("stacks", 1)) > 1 else "")
			parts.append(label if turns > 99 else "%s(%d)" % [label, turns])
		for s: String in u.stacks:
			if u.stack(s) > 0:
				parts.append("%s %d" % [STACK_NAMES.get(s, s.capitalize()), u.stack(s)])
		c["info"].text = "  ".join(parts) if u.is_alive() else "Hors combat"
		c["hp"].modulate = Color(1, 1, 1, 1.0 if u.is_alive() else 0.3)
	if engine.current != null:
		turn_label.text = "Au tour de : %s" % engine.current.display_name


func _clear_actions() -> void:
	for c in action_box.get_children():
		c.queue_free()


func _show_actions(actor: BattleUnit) -> void:
	waiting_input = true
	_clear_actions()
	for i in 3:
		var sk := actor.skill(i)
		var b := Button.new()
		b.custom_minimum_size = Vector2(190, 56)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		if actor.is_passive(i):
			b.text = "%s\n(passif)" % sk["name"]
			b.disabled = true
			b.tooltip_text = sk.get("desc", "")
		else:
			var cd := actor.cooldowns[i]
			b.text = sk["name"] + ("\n(recharge %d)" % cd if cd > 0 else "")
			b.disabled = not i in engine.usable_skills(actor)
			b.pressed.connect(_on_skill_chosen.bind(actor, i))
		action_box.add_child(b)


func _on_skill_chosen(actor: BattleUnit, idx: int) -> void:
	if not engine.needs_target(actor, idx):
		waiting_input = false
		await _perform(actor, idx, null)
		_advance()
		return
	_clear_actions()
	for t in engine.valid_targets(actor, idx):
		var b := Button.new()
		b.text = "%s (%d %%)" % [t.display_name, int(t.hp_ratio() * 100)]
		b.custom_minimum_size = Vector2(170, 56)
		b.pressed.connect(func() -> void:
			waiting_input = false
			await _perform(actor, idx, t)
			_advance())
		action_box.add_child(b)
	var cancel := Button.new()
	cancel.text = "Retour"
	cancel.pressed.connect(_show_actions.bind(actor))
	action_box.add_child(cancel)


func _show_result() -> void:
	if done:
		return
	done = true
	_clear_actions()
	var v := VBoxContainer.new()
	var title := Label.new()
	title.text = {0: "VICTOIRE", 1: "DÉFAITE"}.get(engine.winner, "ÉGALITÉ")
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", UI_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var floor_n := int(Session.battle.get("floor", 0))
	var in_tower: bool = Session.battle.get("mode", "") == "tower"
	var in_loot: bool = Session.battle.get("mode", "") == "loot"
	if in_loot and engine.winner != 0 and not Session.smoke_test:
		Session.profile.refund_energy(int(Session.battle.get("energy", 0)))
		Session.save()
		var ll := Label.new()
		ll.text = "Énergie rendue (+%d)" % int(Session.battle.get("energy", 0))
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(ll)
	if in_loot and engine.winner == 0 and not Session.smoke_test:
		var lrw := Session.profile.win_loot(Session.battle["boss"], int(Session.battle["diff"]), Session.rng)
		Session.save()
		var ls: Array[String] = ["+%d Pièces" % lrw["currencies"]["pieces"]]
		for r: Dictionary in lrw["relics"]:
			ls.append("Relique : " + UiKit.relic_title(r))
		if lrw["pity_used"] != "":
			ls.append("Relique garantie : set " + UiKit.SET_NAMES.get(lrw["pity_used"], lrw["pity_used"]))
		if lrw.has("unlocked"):
			ls.append("Palier débloqué : " + LootBoss.difficulty(int(lrw["unlocked"]))["name"])
		var lab := Label.new()
		lab.text = "\n".join(ls)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(lab)
	if in_tower and engine.winner != 0 and not Session.smoke_test and GameData.progression()["energy"]["refund_on_defeat"]:
		Session.profile.refund_energy(int(Session.battle.get("energy", 0)))
		Session.save()
		if int(Session.battle.get("energy", 0)) > 0:
			var lr := Label.new()
			lr.text = "Énergie rendue (+%d)" % int(Session.battle["energy"])
			lr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(lr)
	if in_tower and engine.winner == 0 and not Session.smoke_test:
		var rw := Session.profile.win_floor(floor_n, Session.rng)
		Session.save()
		var lines: Array[String] = ["Étage %d franchi !" % floor_n if rw["first_clear"] else "Étage %d" % floor_n]
		lines.append("+%d Pièces" % rw["currencies"]["pieces"])
		if rw["currencies"].has("eclat_de_voeu"):
			lines.append("+%d Éclats de Vœu (première victoire)" % rw["currencies"]["eclat_de_voeu"])
		for r: Dictionary in rw["relics"]:
			lines.append("Relique : " + UiKit.relic_title(r))
		var l := Label.new()
		l.text = "\n".join(lines)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	if in_tower and engine.winner == 0 and Session.profile.can_enter_floor(floor_n + 1) and floor_n < Tower.floor_count():
		var nb := UiKit.button("Étage suivant", func() -> void: Session.start_tower_floor(floor_n + 1))
		nb.disabled = Session.profile.energy < Session.profile.floor_cost(floor_n + 1)
		row.add_child(nb)
	if in_loot:
		var lb := UiKit.button("Rejouer", func() -> void: Session.start_loot(Session.battle["boss"], int(Session.battle["diff"])))
		lb.disabled = Session.profile.energy < int(LootBoss.cfg()["energy_cost"])
		row.add_child(lb)
	if in_tower:
		var rb := UiKit.button("Rejouer", func() -> void: Session.start_tower_floor(floor_n))
		rb.disabled = Session.profile.energy < Session.profile.floor_cost(floor_n)
		row.add_child(rb)
	row.add_child(UiKit.button("Retour", _back_to_menu))
	result_panel.add_child(v)
	result_panel.visible = true
	for u in engine.units:
		if u.is_alive() and u.team == engine.winner:
			_play_anim(u, "victory")
	finished.emit(engine.winner)
	if Session.smoke_test:
		print("Test de fumée OK : combat terminé (vainqueur %d, %d actions)" % [engine.winner, engine.total_actions])
		get_tree().quit(0)


func _back_to_menu() -> void:
	var back := {"tower": "res://scenes/tower.tscn", "loot": "res://scenes/loot.tscn"}
	get_tree().change_scene_to_file(back.get(Session.battle.get("mode", ""), "res://scenes/main.tscn"))
