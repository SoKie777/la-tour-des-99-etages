class_name BattleScene
extends Node3D
## Combat en temps réel (boucle de Dragon Traveler) : RtBattle simule, cette scène affiche.
## Vue de côté : ton équipe à gauche, l'adversaire à droite. En bas, la jauge d'énergie commune et une
## carte d'Overdrive par héros (toucher = lancer) ; en haut, temps, auto, vitesse et pause.
## Test de fumée : godot --headless --path . res://scenes/battle.tscn -- --smoke

signal finished(winner: int)

const GAME_FONT := preload("res://assets/fonts/LilitaOne-Regular.ttf")
const CAM_FOV := 36.0
const CAM_POS := Vector3(0.0, 5.6, 10.2)
const CAM_LOOK := Vector3(0.0, 0.9, 0.0)
const DEPTH := 0.95           # profondeur 3D d'une unité de terrain
const RANGED := ["pretre", "archer", "mage"]

var engine: RtBattle
var pawns := {}        # RtUnit -> Node3D
var models := {}       # RtUnit -> CharacterModel
var bars := {}         # RtUnit -> barre de vie 3D
var anim_state := {}   # RtUnit -> "idle" | "walk" | "action"
var action_until := {} # RtUnit -> instant (ms) de fin de l'animation d'action
var float_count := {}  # RtUnit -> [instant ms, nombre] (limite des textes flottants)
var cards := {}        # RtUnit -> {root, cd, cost, hp, glow, button}
var acc := 0.0
var paused := false
var done := false
var cam: Camera3D
var trauma := 0.0
var ui_root: Control
var energy_cells: Array[Panel] = []
var energy_label: Label
var timer_label: Label
var speed_btn: Button
var auto_btn: Button
var boss_bar: ProgressBar
var boss_unit: RtUnit
var banner_box: Control
var result_panel: PanelContainer
var stats_panel: PanelContainer
var telegraphs := {}   # RtUnit -> MeshInstance3D


func _ready() -> void:
	var specs := Session.battle_specs()
	engine = RtBattle.new(specs[0], specs[1])
	engine.auto[0] = Session.auto_battle
	_build_world()
	_build_ui()
	if not Session.smoke_test and not Session.profile.seen_tips.has("rt_basics"):
		Session.profile.seen_tips["rt_basics"] = true
		Session.save()
		_show_tips()
	if Session.smoke_test:
		print("Test de fumée : %d contre %d" % [specs[0].size(), specs[1].size()])


func _process(delta: float) -> void:
	trauma = maxf(0.0, trauma - delta * 1.8)
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * trauma * trauma * 0.3
	cam.position = CAM_POS + shake
	cam.look_at(CAM_LOOK + shake * 0.3)
	if not paused and not done:
		acc += delta * Session.battle_speed
		var tick := float(engine.rules["tick"])
		var guard := 0
		while acc >= tick and guard < 12 and not engine.is_over():
			acc -= tick
			engine.step()
			guard += 1
		for ev in engine.drain_events():
			_on_event(ev)
		if engine.is_over() and not done:
			_show_result()
	_update_pawns(delta)
	_update_ui()


# --- Monde 3D -------------------------------------------------------------------

func _to3(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y * DEPTH)


func _build_world() -> void:
	BattleDecor.build(self, _decor_id())
	cam = Camera3D.new()
	cam.fov = CAM_FOV
	cam.attributes = BattleDecor.camera_blur()
	add_child(cam)
	cam.position = CAM_POS
	cam.look_at(CAM_LOOK)
	var rim := BattleDecor.rim_color(_decor_id())
	for u in engine.units:
		var p := _make_pawn(u)
		p.position = _to3(u.pos)
		p.rotation_degrees.y = 90.0 if u.team == 0 else -90.0
		add_child(p)
		pawns[u] = p
		anim_state[u] = "idle"
		action_until[u] = 0
		if u.boss and u.team == 1:
			boss_unit = u
	for m: CharacterModel in models.values():
		m.set_rim(rim)


func _decor_id() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--decor="):
			return a.trim_prefix("--decor=")
	return Session.battle_decor()


func _height(u: RtUnit) -> float:
	return float(u.data.get("height_m", 1.75))


func _make_pawn(u: RtUnit) -> Node3D:
	var root := Node3D.new()
	var h := _height(u)
	var tint := Color(str(u.data.get("tint", ""))) if u.data.has("tint") else UiKit.char_color(u.id)
	if CharacterModel.available():
		var model := CharacterModel.new()
		root.add_child(model)
		model.setup(u.id, tint, h)
		models[u] = model
	else:
		var mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.3
		capsule.height = h
		mesh.mesh = capsule
		mesh.position.y = h / 2.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint
		mesh.material_override = mat
		root.add_child(mesh)
	var shadow := BattleFx.flat_ring(Color(0, 0, 0), 0.45 * (1.8 if u.boss else 1.0), 0.45, 0.0)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0, 0, 0, 0.45)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow.material_override = sm
	shadow.position.y = 0.02
	root.add_child(shadow)
	root.add_child(BattleFx.unit_seal(UiKit.ACCENT if u.team == 0 else UiKit.VERMILION.lightened(0.15), 0.5 * (1.8 if u.boss else 1.0)))
	var bar := BattleFx.hp_bar(Color("6fd36f") if u.team == 0 else Color("e05050"))
	bar["root"].position.y = h + 0.35
	bar["root"].scale = Vector3(0.8, 1.0, 1.0) if not u.boss else Vector3(1.8, 1.5, 1.0)
	root.add_child(bar["root"])
	bars[u] = bar
	return root


func _update_pawns(delta: float) -> void:
	var now := Time.get_ticks_msec()
	for u: RtUnit in pawns:
		var p: Node3D = pawns[u]
		var target := _to3(u.pos)
		var moved := p.position.distance_to(target)
		p.position = p.position.lerp(target, minf(1.0, delta * 14.0))
		var b: Dictionary = bars[u]
		b["root"].global_basis = cam.global_basis
		b["fill"].scale.x = lerpf(b["fill"].scale.x, clampf(u.hp_ratio(), 0.0, 1.0), minf(1.0, delta * 8.0))
		b["shield"].scale.x = clampf(u.shield_total() / u.max_hp, 0.0, 1.0)
		b["tough"].scale.x = clampf(u.rage / 100.0, 0.0, 1.0) if u.has_faction("cavalier") else 0.0
		b["root"].visible = not u.dead
		if u.dead:
			continue
		var face := 90.0 * u.facing
		if u.target != null:
			var d := _to3(u.target.pos) - p.position
			if d.length() > 0.05:
				face = rad_to_deg(atan2(d.x, d.z))
		p.rotation_degrees.y = lerp_angle_deg(p.rotation_degrees.y, face, minf(1.0, delta * 10.0))
		var m: CharacterModel = models.get(u)
		if m == null:
			continue
		m.set_status_look(_status_tint(u), 0.0 if u.has_status("freeze") else (0.35 if u.has_status("sleep") else 1.0))
		if now < int(action_until[u]):
			continue
		var walking := moved > 0.02 and not paused
		var want := "walk" if walking else "idle"
		if anim_state[u] != want:
			anim_state[u] = want
			m.play(want)


static func lerp_angle_deg(a: float, b: float, t: float) -> float:
	return rad_to_deg(lerp_angle(deg_to_rad(a), deg_to_rad(b), t))


func _status_tint(u: RtUnit) -> Color:
	if u.has_status("freeze"):
		return Color(0.55, 0.8, 1.0, 0.65)
	if u.has_status("poison"):
		return Color(0.25, 0.95, 0.35, 0.18)
	if u.has_status("burn"):
		return Color(1.0, 0.45, 0.2, 0.15)
	if u.has_status("grace"):
		return Color(1.0, 0.85, 0.5, 0.18)
	if u.has_status("galop"):
		return Color(1.0, 0.3, 0.25, 0.18)
	return Color(0, 0, 0, 0)


func _act(u: RtUnit, action: String, dur_ms := 520) -> void:
	var m: CharacterModel = models.get(u)
	if m == null or u.dead:
		return
	m.play(action)
	anim_state[u] = "action"
	action_until[u] = Time.get_ticks_msec() + int(dur_ms / Session.battle_speed)


func _sig(u: RtUnit) -> Color:
	return BattleFx.SIGNATURE.get(u.id, UiKit.char_color(u.id).lightened(0.3))


func _chest(u: RtUnit) -> Vector3:
	return pawns[u].position + Vector3(0, _height(u) * 0.6, 0)


# --- Événements du moteur ----------------------------------------------------------

func _on_event(ev: Dictionary) -> void:
	var t := str(ev["type"])
	var spd := Session.battle_speed
	match t:
		"attack":
			var src: RtUnit = ev["src"]
			var dst: RtUnit = ev["dst"]
			_act(src, "attack", 420)
			if src.cls in RANGED and pawns.has(dst):
				BattleFx.projectile(self, _chest(src), _chest(dst), _sig(src), 0.18 / spd)
		"skill":
			var src: RtUnit = ev["src"]
			_act(src, "skill", 650)
			_skill_fx(src, ev, false)
		"overdrive":
			var src: RtUnit = ev["src"]
			_act(src, "ultimate", 900)
			_skill_fx(src, ev, true)
			_banner(src, str(ev["name"]))
			trauma = minf(1.0, trauma + 0.5)
			UiJuicer.play_sfx("ultimate")
		"telegraph":
			_telegraph(ev["src"], float(ev["dur"]), str(ev["name"]))
		"dash":
			var src: RtUnit = ev["src"]
			if pawns.has(src):
				var from: Vector3 = pawns[src].position
				pawns[src].position = _to3(src.pos)
				BattleFx.dash_trail(self, from + Vector3.UP, pawns[src].position + Vector3.UP, _sig(src), 0.22 / spd)
		"damage":
			var dst: RtUnit = ev["dst"]
			if not pawns.has(dst):
				return
			var amount := int(round(float(ev["amount"])))
			var crit: bool = ev["crit"]
			var src: RtUnit = ev.get("src")
			if ev.get("dot", false):
				_float(dst, str(amount), Color("c48cff"), 0.75)
			else:
				_float(dst, ("%d!" % amount) if crit else str(amount), Color("ffd84a") if crit else (Color("ffffff") if dst.team == 1 else Color("ff8a7a")), 1.3 if crit else 0.95)
				if src != null and not (src.cls in RANGED) and ev.get("basic", false):
					BattleFx.ink_slash(self, _chest(dst), _sig(src), crit, 0.22 / spd)
				elif crit:
					BattleFx.impact(self, _chest(dst), _sig(src) if src != null else Color.WHITE, true)
				if ev.get("chatiment", false):
					_float(dst, "Châtiment", UiKit.faction_color("tour").lightened(0.3), 0.8)
				var m: CharacterModel = models.get(dst)
				if m != null:
					m.flash(Color(1, 1, 1), 0.12)
				if crit and anim_state.get(dst, "") != "action":
					_act(dst, "crit_hit", 380)
				if crit:
					trauma = minf(1.0, trauma + 0.12)
		"heal":
			var dst: RtUnit = ev["dst"]
			if float(ev["amount"]) >= 1.0:
				_float(dst, "+%d" % int(ev["amount"]), Color("7ff09a"), 0.85)
		"shield":
			var dst: RtUnit = ev["dst"]
			_float_icon(dst, UiKit.status_texture("dr_up"))
		"status":
			var dst: RtUnit = ev["dst"]
			if str(ev["id"]) in ["moral", "ferveur", "ov_tax"] or ev.get("src") == null:
				return
			_float_icon(dst, UiKit.status_texture(str(ev["id"])))
		"reaction":
			var dst: RtUnit = ev["dst"]
			_float(dst, str(ev["name"]), UiKit.faction_color("roi").lightened(0.2), 1.25)
			if pawns.has(dst):
				BattleFx.shockwave(self, pawns[dst].position, UiKit.faction_color("roi"), 2.2, 0.4 / spd)
				BattleFx.burst(self, _chest(dst), Color("ffd27a"), 26, 5.0, 0.09, 0.5)
		"grace":
			_float(ev["dst"], "Grâce", UiKit.faction_color("dame").lightened(0.3), 1.1)
		"galop":
			_float(ev["dst"], "Galop !", UiKit.faction_color("cavalier").lightened(0.3), 1.1)
		"stack":
			var name: String = {"eveil": "Éveil", "promesse": "Promesse"}.get(str(ev["id"]), "")
			if name != "":
				_float(ev["dst"], "%s %d" % [name, int(ev["n"])], UiKit.faction_color("fou" if ev["id"] == "eveil" else "pion").lightened(0.3), 0.8)
		"resist":
			_float(ev["dst"], "Résiste", UiKit.DIM, 0.8)
		"death":
			var dst: RtUnit = ev["dst"]
			var m: CharacterModel = models.get(dst)
			if m != null:
				m.play("death")
			anim_state[dst] = "dead"
			action_until[dst] = 1 << 40
			if telegraphs.has(dst):
				telegraphs[dst].queue_free()
				telegraphs.erase(dst)
			if pawns.has(dst):
				var tw := create_tween()
				tw.tween_interval(1.4 / spd)
				tw.tween_property(pawns[dst], "scale", Vector3(1, 0.01, 1), 0.35)
				tw.tween_callback(pawns[dst].hide)
		"energy":
			if int(ev["team"]) == 0 and float(ev["delta"]) > 0.0:
				_flash_energy()


func _skill_fx(src: RtUnit, ev: Dictionary, big: bool) -> void:
	var spd := Session.battle_speed
	var col := _sig(src)
	var area: Dictionary = ev.get("area", {})
	var primary: RtUnit = ev.get("primary")
	var hit: Array = ev.get("hit", [])
	if primary == null or not pawns.has(primary):
		return
	var at: Vector3 = pawns[src].position if area.get("center", "") == "self" else pawns[primary].position
	if primary.team == src.team:  # soutien
		for x: RtUnit in hit:
			if pawns.has(x):
				BattleFx.orb(self, _chest(x), col, 0.5 / spd, 0.6)
				if big:
					BattleFx.petals(self, pawns[x].position + Vector3.UP * 1.5, 8)
		return
	if area.get("shape", "") == "line":
		BattleFx.dash_trail(self, _chest(src), _chest(primary) + (_chest(primary) - _chest(src)).normalized() * 3.0, col, 0.3 / spd)
	elif not area.is_empty():
		BattleFx.shockwave(self, at, col, float(area.get("radius", 2.0)), 0.45 / spd)
	for x: RtUnit in hit:
		if pawns.has(x):
			BattleFx.impact(self, _chest(x), col, big)
	if big:
		match src.cls:
			"mage":
				BattleFx.void_vortex(self, at, col, 0.8 / spd)
			"archer":
				BattleFx.solar_pillar(self, at, col, 0.8 / spd)
			"assassin", "guerrier":
				BattleFx.tornado(self, at, col, 0.9 / spd, 2.6, 0.9)
			_:
				BattleFx.crystal_eruption(self, at, col, 0.8 / spd)


func _telegraph(u: RtUnit, dur: float, name: String) -> void:
	if not pawns.has(u):
		return
	var ring := BattleFx.flat_ring(UiKit.VERMILION, 3.4, 0.12, 2.0)
	ring.position = pawns[u].position + Vector3(0, 0.05, 0)
	ring.scale = Vector3(0.2, 1, 0.2)
	add_child(ring)
	telegraphs[u] = ring
	var tw := create_tween()
	tw.tween_property(ring, "scale", Vector3(1, 1, 1), dur / Session.battle_speed)
	tw.tween_callback(func() -> void:
		if is_instance_valid(ring):
			ring.queue_free()
		telegraphs.erase(u))
	_float(u, "! %s !" % name, UiKit.VERMILION.lightened(0.35), 1.3)


func _float(u: RtUnit, text: String, color: Color, size := 1.0) -> void:
	if not pawns.has(u) or Session.smoke_test:
		return
	var now := Time.get_ticks_msec()
	var fc: Array = float_count.get(u, [0, 0])
	var row := int(fc[1]) + 1 if now - int(fc[0]) < 300 else 0
	if row > 4:
		return
	float_count[u] = [now, row]
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font = GAME_FONT
	l.font_size = int(34 * size)
	l.outline_size = 8
	l.outline_modulate = Color(0.05, 0.02, 0.08)
	_float_node(u, l, row)


func _float_icon(u: RtUnit, tex: Texture2D) -> void:
	if not pawns.has(u) or tex == null or Session.smoke_test:
		return
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.pixel_size = 0.0045
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.no_depth_test = true
	sp.render_priority = 4
	_float_node(u, sp, 0)


func _float_node(u: RtUnit, l: Node3D, row: int) -> void:
	l.position = pawns[u].position + Vector3(randf_range(-0.3, 0.3), _height(u) + 0.6 + row * 0.3, 0.3)
	l.scale = Vector3.ONE * 1.4
	add_child(l)
	var spd := Session.battle_speed
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "position:y", l.position.y + 0.8, 0.8 / spd)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.4 / spd).set_delay(0.45 / spd)
	tw.tween_callback(l.queue_free)


# --- Interface ----------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = UiKit.theme()
	layer.add_child(ui_root)
	# Bandeau du haut : lieu, temps, auto, vitesse, pause
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 10
	top.add_theme_constant_override("separation", 10)
	ui_root.add_child(top)
	var title := UiKit.label(Session.battle_title(), 18, UiKit.ACCENT)
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.1))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	timer_label = UiKit.label("1:30", 24, UiKit.PAPER)
	timer_label.add_theme_font_override("font", GAME_FONT)
	timer_label.add_theme_constant_override("outline_size", 8)
	timer_label.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.1))
	timer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(timer_label)
	var right := HBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 8)
	top.add_child(right)
	auto_btn = UiKit.button("AUTO", _toggle_auto, Vector2(96, 44))
	right.add_child(auto_btn)
	speed_btn = UiKit.button("×1", _cycle_speed, Vector2(70, 44))
	right.add_child(speed_btn)
	right.add_child(UiKit.icon_button("pause", _toggle_pause, 44) if UiKit.icon_texture("pause") != null else UiKit.button("II", _toggle_pause, Vector2(48, 44)))
	_refresh_buttons()
	# Barre de vie du boss
	if boss_unit != null:
		var bb := VBoxContainer.new()
		bb.set_anchors_preset(Control.PRESET_CENTER_TOP)
		bb.offset_left = -260
		bb.offset_right = 260
		bb.offset_top = 58
		ui_root.add_child(bb)
		var bl := UiKit.label(boss_unit.display_name, 18, UiKit.VERMILION.lightened(0.4))
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bb.add_child(bl)
		boss_bar = ProgressBar.new()
		boss_bar.max_value = 1.0
		boss_bar.value = 1.0
		boss_bar.show_percentage = false
		boss_bar.custom_minimum_size = Vector2(520, 16)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color("d04040")
		fill.set_corner_radius_all(4)
		boss_bar.add_theme_stylebox_override("fill", fill)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.55)
		bg.set_corner_radius_all(4)
		boss_bar.add_theme_stylebox_override("background", bg)
		bb.add_child(boss_bar)
	# Bas : jauge d'énergie puis cartes d'Overdrive
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.offset_left = -420
	bottom.offset_right = 420
	bottom.offset_top = -176
	bottom.offset_bottom = -10
	bottom.add_theme_constant_override("separation", 6)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(bottom)
	var erow := HBoxContainer.new()
	erow.alignment = BoxContainer.ALIGNMENT_CENTER
	erow.add_theme_constant_override("separation", 4)
	bottom.add_child(erow)
	erow.add_child(UiKit.icon("overdrive", 22, UiKit.CYAN))
	var emax := int(engine.rules["energy"]["max"])
	for i in emax:
		var cell := Panel.new()
		cell.custom_minimum_size = Vector2(34, 14)
		cell.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0, 0, 0, 0.5), Color(UiKit.CYAN, 0.4), 1, 4))
		erow.add_child(cell)
		energy_cells.append(cell)
	energy_label = UiKit.label("0/%d" % emax, 18, UiKit.CYAN)
	energy_label.add_theme_font_override("font", GAME_FONT)
	energy_label.add_theme_constant_override("outline_size", 6)
	energy_label.add_theme_color_override("font_outline_color", Color(0.02, 0.06, 0.1))
	erow.add_child(energy_label)
	var crow := HBoxContainer.new()
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	crow.add_theme_constant_override("separation", 8)
	bottom.add_child(crow)
	for u in engine.units:
		if u.team == 0:
			crow.add_child(_make_card(u))
	banner_box = VBoxContainer.new()
	banner_box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	banner_box.offset_left = 0
	banner_box.offset_top = -120
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(banner_box)
	result_panel = PanelContainer.new()
	result_panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(UiKit.BG, 0.96), UiKit.ACCENT, 2, 10))
	result_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	result_panel.custom_minimum_size = Vector2(580, 0)
	result_panel.visible = false
	ui_root.add_child(result_panel)


func _make_card(u: RtUnit) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(104, 112)
	b.focus_mode = Control.FOCUS_NONE
	var col := UiKit.char_color(u.id)
	b.add_theme_stylebox_override("normal", UiKit.panel_style(Color(0.05, 0.03, 0.08, 0.85), Color(col, 0.7), 2, 10))
	b.add_theme_stylebox_override("hover", UiKit.panel_style(Color(0.1, 0.06, 0.14, 0.9), col, 2, 10))
	b.add_theme_stylebox_override("pressed", UiKit.panel_style(Color(col, 0.3), col, 3, 10))
	b.add_theme_stylebox_override("disabled", UiKit.panel_style(Color(0.05, 0.03, 0.08, 0.85), Color(col, 0.35), 2, 10))
	var por := UiKit.portrait(u.id, 78)
	por.set_anchors_preset(Control.PRESET_CENTER_TOP)
	por.offset_left = -39
	por.offset_right = 39
	por.offset_top = 4
	por.offset_bottom = 82
	b.add_child(por)
	var cd := ColorRect.new()  # voile de recharge, descend avec le temps
	cd.color = Color(0, 0, 0, 0.62)
	cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd.set_anchors_preset(Control.PRESET_TOP_WIDE)
	cd.offset_left = 3
	cd.offset_right = -3
	cd.offset_top = 3
	b.add_child(cd)
	var cd_l := UiKit.label("", 22, UiKit.PAPER)
	cd_l.add_theme_font_override("font", GAME_FONT)
	cd_l.set_anchors_preset(Control.PRESET_CENTER)
	cd_l.offset_left = -30
	cd_l.offset_right = 30
	cd_l.offset_top = -30
	cd_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(cd_l)
	var cost := PanelContainer.new()  # coût en énergie, en haut à gauche
	cost.add_theme_stylebox_override("panel", UiKit.panel_style(Color("0a3a4a"), UiKit.CYAN, 2, 14))
	cost.position = Vector2(-6, -8)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cost_l := UiKit.label(str(u.ov_cost()), 16, UiKit.CYAN)
	cost_l.add_theme_font_override("font", GAME_FONT)
	cost_l.custom_minimum_size = Vector2(20, 0)
	cost_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.add_child(cost_l)
	b.add_child(cost)
	var hp := ProgressBar.new()
	hp.max_value = 1.0
	hp.value = 1.0
	hp.show_percentage = false
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hp.offset_left = 8
	hp.offset_right = -8
	hp.offset_top = -24
	hp.offset_bottom = -16
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("6fd36f")
	hp.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	hp.add_theme_stylebox_override("background", bg)
	b.add_child(hp)
	var name_l := UiKit.label(u.display_name.get_slice(" ", 0), 11, Color(UiKit.PAPER, 0.85))
	name_l.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_l.offset_top = -16
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.clip_text = true
	b.add_child(name_l)
	b.pressed.connect(func() -> void: _on_card(u))
	cards[u] = {"button": b, "cd": cd, "cd_l": cd_l, "cost": cost_l, "hp": hp}
	return b


func _on_card(u: RtUnit) -> void:
	if done or u.dead:
		return
	if engine.request_overdrive(u):
		UiJuicer.play_sfx("click")
		var b: Button = cards[u]["button"]
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(1.08, 1.08), 0.08)
		tw.tween_property(b, "scale", Vector2.ONE, 0.12)


func _update_ui() -> void:
	if engine == null:
		return
	var left := maxf(0.0, engine.time_limit - engine.time)
	timer_label.text = "%d:%02d" % [int(left) / 60, int(left) % 60]
	timer_label.add_theme_color_override("font_color", UiKit.VERMILION.lightened(0.3) if left < 15.0 else UiKit.PAPER)
	var e := engine.energy[0]
	for i in energy_cells.size():
		var full := e >= i + 1
		var part := clampf(e - i, 0.0, 1.0)
		var st := UiKit.panel_style(Color(UiKit.CYAN, 0.85) if full else Color(UiKit.CYAN, 0.15 + 0.35 * part), Color(UiKit.CYAN, 0.6), 1, 4)
		energy_cells[i].add_theme_stylebox_override("panel", st)
	energy_label.text = "%d/%d" % [int(e), energy_cells.size()]
	for u: RtUnit in cards:
		var c: Dictionary = cards[u]
		var sk := u.ov_skill()
		var cd_frac := clampf(u.ov_cd / float(sk.get("cd", 20.0)), 0.0, 1.0) if u.ov_cd > 0.0 else 0.0
		var cd: ColorRect = c["cd"]
		cd.offset_bottom = 3 + (c["button"] as Button).size.y * cd_frac - 3
		c["cd_l"].text = "" if u.ov_cd <= 0.0 or u.dead else str(ceili(u.ov_cd))
		c["cost"].text = str(u.ov_cost())
		c["cost"].add_theme_color_override("font_color", UiKit.VERMILION.lightened(0.4) if u.mod("ov_cost") > 0 else UiKit.CYAN)
		c["hp"].value = u.hp_ratio()
		var ready := not u.dead and u.ov_cd <= 0.0 and engine.energy[0] >= u.ov_cost()
		var b: Button = c["button"]
		b.disabled = u.dead
		b.modulate = Color(0.45, 0.45, 0.45) if u.dead else (Color(1.15, 1.12, 1.0) if ready else Color(0.85, 0.85, 0.9))
	if boss_bar != null:
		boss_bar.value = lerpf(boss_bar.value, boss_unit.hp_ratio(), 0.2)


func _flash_energy() -> void:
	if energy_label != null:
		var tw := energy_label.create_tween()
		tw.tween_property(energy_label, "scale", Vector2(1.3, 1.3), 0.08)
		tw.tween_property(energy_label, "scale", Vector2.ONE, 0.15)


## Gros plan de l'Overdrive : portrait et nom qui glissent depuis le bord (à droite pour l'adversaire).
func _banner(u: RtUnit, skill_name: String) -> void:
	if Session.smoke_test:
		return
	var p := PanelContainer.new()
	var col := UiKit.char_color(u.id)
	p.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.04, 0.02, 0.07, 0.86), col, 2, 12))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	h.add_child(UiKit.portrait(u.id, 64))
	var v := VBoxContainer.new()
	h.add_child(v)
	v.add_child(UiKit.label(skill_name, 22, UiKit.ACCENT if u.team == 0 else UiKit.VERMILION.lightened(0.4)))
	v.add_child(UiKit.label(u.display_name, 14, Color(UiKit.PAPER, 0.8)))
	ui_root.add_child(p)
	var y := 130.0 if u.team == 0 else 210.0
	var vw := get_viewport().get_visible_rect().size.x
	var start_x := -380.0 if u.team == 0 else vw + 20.0
	var end_x := 16.0 if u.team == 0 else vw - 380.0
	p.position = Vector2(start_x, y)
	var tw := p.create_tween()
	tw.tween_property(p, "position:x", end_x, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.0 / Session.battle_speed)
	tw.tween_property(p, "modulate:a", 0.0, 0.25)
	tw.tween_callback(p.queue_free)


func _toggle_auto() -> void:
	Session.auto_battle = not Session.auto_battle
	engine.auto[0] = Session.auto_battle
	_refresh_buttons()


func _cycle_speed() -> void:
	Session.battle_speed = {1.0: 2.0, 2.0: 3.0}.get(Session.battle_speed, 1.0)
	_refresh_buttons()


func _toggle_pause() -> void:
	paused = not paused


func _refresh_buttons() -> void:
	if auto_btn != null:
		auto_btn.text = "AUTO ✓" if Session.auto_battle else "AUTO"
		auto_btn.modulate = Color(1.2, 1.1, 0.8) if Session.auto_battle else Color.WHITE
	if speed_btn != null:
		speed_btn.text = "×%d" % int(Session.battle_speed)


## Premier combat : les bases du temps réel, combat en pause pendant la lecture.
func _show_tips() -> void:
	paused = true
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(UiKit.BG, 0.96), UiKit.ACCENT, 2, 12))
	ui_root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size.x = 620
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(UiKit.label("Le combat en temps réel", 24, UiKit.ACCENT))
	for line in [
		"Tes héros avancent, attaquent et lancent leur compétence tout seuls.",
		"%s La jauge d'énergie se remplit pour toute l'équipe." % UiKit.bb("overdrive", 18, UiKit.CYAN),
		"Touche la carte d'un héros pour lancer son Overdrive : il coûte l'énergie indiquée en haut à gauche, puis se recharge.",
		"AUTO lance les Overdrive à ta place. ×2 / ×3 accélèrent le combat.",
		"Placement : Gardiens devant, tireurs et soigneurs derrière (Équipe). 4 héros d'une même faction : +10 % ATK et PV.",
	]:
		v.add_child(UiKit.rich(line, 16, UiKit.PAPER, true))
	var ok := UiKit.cta(UiKit.button("C'est parti !", func() -> void:
		panel.queue_free()
		paused = false, Vector2(220, 50)))
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ok)


# --- Résultat ------------------------------------------------------------------

func _show_result() -> void:
	if done:
		return
	done = true
	var win := engine.winner == 0
	UiJuicer.play_sfx("victory" if win else "defeat")
	for u in engine.units:
		if not u.dead and u.team == engine.winner:
			_act(u, "victory", 999999)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "VICTOIRE" if win else "DÉFAITE"
	title.add_theme_font_override("font", GAME_FONT)
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", UiKit.ACCENT if win else UiKit.VERMILION.lightened(0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	v.add_child(UiKit.label("%s  ·  %.0f s" % [Session.battle_title(), engine.time], 14, UiKit.DIM))
	var mode := str(Session.battle.get("mode", ""))
	var lines: Array = []
	var next_cb := Callable()
	var next_text := ""
	var now := Session.now()
	if not Session.smoke_test:
		match mode:
			"campaign":
				var n := int(Session.battle["stage"])
				if win:
					var rw := Session.profile.win_stage(n, now)
					if rw["first"]:
						lines.append(["Première victoire !", true])
						_currency_lines(lines, rw["currencies"])
					if n < Campaign.stage_count():
						next_text = "Étape %s  ›" % Campaign.stage_info(n + 1)["number"]
						next_cb = func() -> void: Session.start_stage(n + 1)
				Session.save()
			"tower":
				var f := int(Session.battle["floor"])
				if win:
					var rw := Session.profile.win_floor(f, Session.rng)
					_currency_lines(lines, rw["currencies"])
					for r: Dictionary in rw["relics"]:
						lines.append([UiKit.relic_title(r), false])
					if f < Tower.floor_count():
						next_text = "Étage %d  ›" % (f + 1)
						next_cb = func() -> void: Session.start_tower_floor(f + 1)
				Session.save()
			"loot":
				if win:
					var rw := Session.profile.win_loot(str(Session.battle["boss"]), int(Session.battle["diff"]), Session.rng)
					_currency_lines(lines, rw["currencies"])
					for r: Dictionary in rw["relics"]:
						lines.append([UiKit.relic_title(r), false])
					if rw.has("unlocked"):
						lines.append(["▲ " + str(LootBoss.difficulty(int(rw["unlocked"]))["name"]), true])
				elif GameData.progression()["energy"]["refund_on_defeat"]:
					Session.profile.refund_energy(int(Session.battle.get("energy", 0)))
					lines.append(["%s +%d" % [UiKit.bb("energie", 20), int(Session.battle.get("energy", 0))], false])
				Session.save()
	if not win:
		lines.append(["Pour progresser : monter les niveaux, les étoiles (doublons) ou invoquer.", false])
	_reward_lines(v, lines)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	if next_text != "":
		var nb := UiKit.cta(UiKit.button(next_text, next_cb, Vector2(200, 52)))
		row.add_child(nb)
	if not win:
		row.add_child(UiKit.button("Héros", func() -> void: get_tree().change_scene_to_file("res://scenes/collection.tscn"), Vector2(120, 52)))
	row.add_child(UiKit.button("Rejouer", func() -> void: get_tree().reload_current_scene(), Vector2(120, 52)))
	row.add_child(UiKit.icon_button("stats", _toggle_battle_stats, 52))
	row.add_child(UiKit.icon_button("back", _back_to_menu, 52))
	result_panel.add_child(v)
	result_panel.visible = true
	UiJuicer.pop_in(result_panel, false)
	finished.emit(engine.winner)
	if Session.smoke_test:
		print("Test de fumée OK : combat terminé (vainqueur %d, %.1f s)" % [engine.winner, engine.time])
		get_tree().quit(0)


func _currency_lines(lines: Array, cur: Dictionary) -> void:
	for k: String in cur:
		var key := k == "eclat_de_voeu" or k.begins_with("sceau")
		lines.append(["%s +%s" % [UiKit.bb(k, 22 if key else 20, UiKit.ACCENT if key else UiKit.PAPER), UiKit.thousands(int(cur[k]))], key])


func _reward_lines(v: VBoxContainer, lines: Array) -> void:
	for k in lines.size():
		var key: bool = lines[k][1]
		var l := UiKit.rich("[center]%s[/center]" % lines[k][0], 18 if key else 15, UiKit.ACCENT if key else UiKit.PAPER, true)
		l.custom_minimum_size.x = 520
		l.modulate.a = 0.0
		v.add_child(l)
		var tw := l.create_tween()
		tw.tween_interval(0.3 + 0.18 * k)
		tw.tween_property(l, "modulate:a", 1.0, 0.2)


## Bilan : dégâts infligés (part de l'équipe), subis, boucliers, soins.
func _toggle_battle_stats() -> void:
	if stats_panel != null:
		stats_panel.queue_free()
		stats_panel = null
		return
	stats_panel = PanelContainer.new()
	stats_panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(UiKit.BG, 0.97), UiKit.ACCENT, 2, 8))
	stats_panel.set_anchors_preset(Control.PRESET_CENTER)
	stats_panel.offset_left = -420
	stats_panel.offset_right = 420
	stats_panel.offset_top = -260
	stats_panel.offset_bottom = 260
	ui_root.add_child(stats_panel)
	var scroll := ScrollContainer.new()
	stats_panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UiKit.label("Bilan", 22, UiKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UiKit.icon_button("close", _toggle_battle_stats, 40))
	for team in 2:
		var total := 0.0
		for u in engine.units:
			if u.team == team:
				total += u.dealt
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 14)
		v.add_child(grid)
		for id in ["", "", "atk", "dmg_taken", "shield", "support"]:
			grid.add_child(Control.new() if id == "" else UiKit.icon(id, 20, UiKit.DIM))
		for u in engine.units:
			if u.team != team:
				continue
			grid.add_child(UiKit.portrait(u.id, 32))
			var nl := UiKit.label(u.display_name, 14, UiKit.char_color(u.id).lightened(0.35))
			nl.custom_minimum_size.x = 170
			nl.clip_text = true
			grid.add_child(nl)
			grid.add_child(UiKit.label("%d %%" % roundi(100.0 * u.dealt / total if total > 0.0 else 0.0), 14))
			for x in [u.taken, u.shielded, u.healed]:
				grid.add_child(UiKit.label(UiKit.thousands(roundi(x)), 14))


func _back_to_menu() -> void:
	var back := {"tower": "res://scenes/tower.tscn", "loot": "res://scenes/loot.tscn", "campaign": "res://scenes/campaign.tscn"}
	get_tree().change_scene_to_file(back.get(Session.battle.get("mode", ""), "res://scenes/main.tscn"))
