extends Node3D
## Scène de combat jouable. Les personnages sont des capsules de couleur tant que
## leur modèle n'existe pas ; dès qu'un fichier
## res://assets/characters/<id>/<id>.glb est présent, il est utilisé automatiquement
## (animations attendues : idle, attack, skill, ultimate, hit, death).

signal finished(winner: int)

const COLORS := {"orion": Color("4d8fd6"), "grande_ourse": Color("c8553d"), "sirius": Color("9b6bd6")}
const UI_BG := Color("14121f")
const UI_ACCENT := Color("c9a24a")

var engine: BattleEngine
var pawns := {}        # BattleUnit -> Node3D
var anim_players := {} # BattleUnit -> AnimationPlayer
var cards := {}        # BattleUnit -> {hp: ProgressBar, info: Label}
var log_label: RichTextLabel
var turn_label: Label
var action_box: HBoxContainer
var result_panel: PanelContainer
var waiting_input := false
var done := false


func _ready() -> void:
	engine = BattleEngine.new(Session.player_team, Session.enemy_team)
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
			_play_anim(ev["target"], "hit")
		"heal":
			_float_text(ev["target"], "+" + str(int(ev["amount"])), Color("6bdc8a"))
		"resist", "immune":
			_float_text(ev["target"], "Résiste", Color("a0a0b8"))
		"effect":
			_float_text(ev["target"], BattleLog.effect_name(ev["effect"]), Color("e0c060"))
		"death":
			_play_anim(ev["target"], "death")
			if not anim_players.has(ev["target"]):
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
		p.position = Vector3(side * 3.2, 0, (u.slot - 1) * 2.0)
		p.rotation_degrees.y = 90.0 if u.team == 0 else -90.0
		add_child(p)
		pawns[u] = p


func _make_pawn(u: BattleUnit) -> Node3D:
	var root := Node3D.new()
	var model_path := "res://assets/characters/%s/%s.glb" % [u.id, u.id]
	if ResourceLoader.exists(model_path):
		var model: Node3D = load(model_path).instantiate()
		root.add_child(model)
		var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap != null:
			anim_players[u] = ap
			if ap.has_animation("idle"):
				ap.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
				ap.play("idle")
	else:
		var mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.35
		capsule.height = 1.7
		mesh.mesh = capsule
		mesh.position.y = 0.85
		var mat := StandardMaterial3D.new()
		mat.albedo_color = COLORS[u.constellation]
		mesh.material_override = mat
		root.add_child(mesh)
	var label := Label3D.new()
	label.text = u.display_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.1
	label.font_size = 40
	label.outline_size = 8
	root.add_child(label)
	return root


func _play_anim(u: BattleUnit, anim_name: String) -> void:
	var ap: AnimationPlayer = anim_players.get(u)
	if ap == null:
		return
	if anim_name == "ultimate" and not ap.has_animation("ultimate"):
		anim_name = "skill"
	if not ap.has_animation(anim_name):
		return
	ap.play(anim_name)
	if anim_name in ["attack", "skill", "ultimate", "hit"] and ap.has_animation("idle"):
		ap.queue("idle")


func _float_text(u: BattleUnit, text: String, color: Color) -> void:
	if not pawns.has(u):
		return
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 56
	l.outline_size = 10
	l.position = pawns[u].position + Vector3(randf_range(-0.3, 0.3), 2.5, 0)
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
			col.offset_top = 60
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

	result_panel = PanelContainer.new()
	result_panel.set_anchors_preset(Control.PRESET_CENTER)
	result_panel.add_theme_stylebox_override("panel", _panel_style(UI_BG))
	result_panel.visible = false
	root.add_child(result_panel)


func _make_card(u: BattleUnit) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(UI_BG, 0.85), COLORS[u.constellation]))
	var v := VBoxContainer.new()
	panel.add_child(v)
	var name_label := Label.new()
	name_label.text = "%s  ·  %s" % [u.display_name, u.data["voie"]]
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
			parts.append("%s(%d)" % [BattleLog.effect_name(e["id"]), e["turns"]])
		if u.stacks["fury"] > 0:
			parts.append("Fureur %d" % u.stacks["fury"])
		if u.stacks["spark"] > 0:
			parts.append("Étincelle %d" % u.stacks["spark"])
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
	var b := Button.new()
	b.text = "Retour au menu"
	b.pressed.connect(_back_to_menu)
	v.add_child(b)
	result_panel.add_child(v)
	result_panel.visible = true
	finished.emit(engine.winner)
	if Session.smoke_test:
		print("Test de fumée OK : combat terminé (vainqueur %d, %d actions)" % [engine.winner, engine.total_actions])
		get_tree().quit(0)


func _back_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
