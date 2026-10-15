extends Node3D
## Scène de combat jouable, mise en scène façon Dislyte : ton équipe au premier plan (de dos), les ennemis
## dans le fond face à la caméra. Effets : tremblement de caméra, arrêt sur image sur les critiques, éclats
## de couleur et étincelles à l'impact, gros plan et bannière sur les ultimes, barre d'action en haut.
## Personnages : modèle MPFB res://assets/models/<id>.fbx s'il existe, sinon le mannequin Y Bot teinté.

signal finished(winner: int)

const COLORS := {"orion": Color("4d8fd6"), "grande_ourse": Color("c8553d"), "sirius": Color("9b6bd6")}
const UI_BG := Color("14121f")
const UI_ACCENT := Color("c9a24a")
const STACK_NAMES := {"spark": "Étincelle", "fury": "Fureur", "rage": "Rage", "visage": "Visage", "dette": "Dette",
	"clone": "Clones", "inertia": "Inertie"}
const CAM_POS := Vector3(0, 3.1, 7.9)
const CAM_LOOK := Vector3(0, 1.0, -0.9)
const RANGED := ["cast", "heal", "roar", "taunt", "block"]  # animations jouées sur place
const GAME_FONT := preload("res://assets/fonts/LilitaOne-Regular.ttf")  # police libre (OFL), chiffres et titres

var engine: BattleEngine
var pawns := {}        # BattleUnit -> Node3D
var models := {}       # BattleUnit -> CharacterModel
var bars := {}         # BattleUnit -> barre de vie 3D
var cards := {}        # BattleUnit -> {hp: ProgressBar, info: Label}
var markers := {}      # BattleUnit -> marqueur de la barre d'action
var float_stack := {}  # BattleUnit -> [instant ms, rang] des textes flottants
var log_label: RichTextLabel
var log_panel: PanelContainer
var turn_label: Label
var action_box: HBoxContainer
var action_track: Control
var result_panel: PanelContainer
var dim: ColorRect
var banner: Label
var banner_sub: Label
var waiting_input := false
var done := false
var cam: Camera3D
var cam_pos := CAM_POS
var cam_look := CAM_LOOK
var trauma := 0.0
var active_ring: MeshInstance3D
var hitstop_used := false
var info_panel: PanelContainer
var ui_root: Control
var stars := {}       # BattleUnit -> étoiles qui tournent au-dessus de la tête (Étourdissement)
var zz_timer := {}    # BattleUnit -> temps avant le prochain « Z » (Sommeil)


func _ready() -> void:
	var teams := Session.battle_teams()
	engine = BattleEngine.new(teams[0], teams[1])
	engine.battle_event.connect(_on_battle_event)
	_build_world()
	_build_ui()
	_refresh()
	_advance()


func _process(delta: float) -> void:
	trauma = maxf(0.0, trauma - delta * 1.8)
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-0.5, 0.5)) * trauma * trauma * 0.35
	cam.position = cam_pos + shake
	cam.look_at(cam_look + shake * 0.4)
	for u: BattleUnit in bars:
		var b: Dictionary = bars[u]
		b["root"].global_basis = cam.global_basis
		b["fill"].scale.x = lerpf(b["fill"].scale.x, clampf(u.hp_ratio(), 0.0, 1.0), minf(1.0, delta * 8.0))
		b["shield"].scale.x = clampf(u.shield_value() / u.max_hp(), 0.0, 1.0)
		b["root"].visible = u.is_alive()
	for u: BattleUnit in stars:
		stars[u].rotation.y += delta * 4.0
	for u: BattleUnit in zz_timer.keys():
		zz_timer[u] -= delta
		if zz_timer[u] <= 0.0:
			zz_timer[u] = 0.75
			_spawn_z(u)
	if active_ring != null:
		var k := 1.0 + 0.06 * sin(Time.get_ticks_msec() / 160.0)
		active_ring.scale = Vector3(k, 0.05, k)
	if action_track != null:
		var w := action_track.size.x
		for u: BattleUnit in markers:
			var m: Control = markers[u]
			m.visible = u.is_alive()
			m.position.x = lerpf(m.position.x, clampf(u.ap, 0.0, 1.0) * w - m.size.x / 2.0, minf(1.0, delta * 10.0))


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
		_move_ring(actor)
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
	hitstop_used = false
	var sk := actor.skill(skill_idx)
	var action: String = ["attack", "skill", "ultimate"][skill_idx]
	if skill_idx == 2:
		await _ultimate_intro(actor, sk["name"])
		_reset_camera()  # retour en vue générale pendant l'élan : on voit l'impact
	var pawn: Node3D = pawns[actor]
	var home := _home(actor)
	var focus: BattleUnit = target
	if focus == null:
		focus = engine.enemies_of(actor)[0] if sk.get("target", "") == "all_enemies" and not engine.enemies_of(actor).is_empty() else actor
	var anim := _anim_name(actor, action)
	_play_anim(actor, action)
	var melee := focus.team != actor.team and not RANGED.any(func(r: String) -> bool: return anim.begins_with(r))
	if melee:
		var dest := home.lerp(_home(focus), 0.62)
		var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(pawn, "position", dest, 0.2 / Session.battle_speed)
		await tw.finished
	else:
		await _pause(0.12)
		await _skill_vfx(actor, sk, focus)
	if melee and sk.get("target", "") == "all_enemies":
		BattleFx.shockwave(self, _home(focus) * Vector3(0, 0, 1), _col(actor), 4.5, 0.5 / Session.battle_speed)
	engine.use_skill(actor, skill_idx, target)
	_refresh()
	if melee:
		var back := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		back.tween_property(pawn, "position", home, 0.25 / Session.battle_speed)
		await back.finished
	await _pause(0.3)


func _pause(seconds: float) -> void:
	await get_tree().create_timer(seconds / Session.battle_speed).timeout


func _anim_name(u: BattleUnit, action: String) -> String:
	var m: CharacterModel = models.get(u)
	return str(m.anims.get(action, action)) if m != null else action


## Gros plan sur le lanceur, écran assombri, nom de l'ultime en grand.
func _ultimate_intro(actor: BattleUnit, skill_name: String) -> void:
	var p := _home(actor)
	var facing := -1.0 if actor.team == 0 else 1.0  # ton équipe regarde vers le fond : on la filme de face
	_cam_to(p + Vector3(1.2, 1.55, 3.7 * facing), p + Vector3(0, 1.15, 0), 0.35)
	banner.text = skill_name.to_upper()
	banner_sub.text = actor.display_name
	banner.modulate = Color(_col(actor).lightened(0.35), 0.0)
	banner_sub.modulate.a = 0.0
	banner.position.x = -400
	var tw := create_tween().set_parallel()
	tw.tween_property(dim, "color:a", 0.45, 0.25)
	tw.tween_property(banner, "modulate:a", 1.0, 0.2)
	tw.tween_property(banner_sub, "modulate:a", 1.0, 0.3)
	tw.tween_property(banner, "position:x", 40.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if models.has(actor):
		models[actor].flash(Color(_col(actor).lightened(0.3), 0.45), 0.6)
	await _pause(0.85)
	var out := create_tween().set_parallel()
	out.tween_property(dim, "color:a", 0.0, 0.3)
	out.tween_property(banner, "modulate:a", 0.0, 0.3)
	out.tween_property(banner_sub, "modulate:a", 0.0, 0.3)


## Effet visuel d'une compétence lancée à distance : projectile, onde de zone ou cercle de soutien.
func _skill_vfx(actor: BattleUnit, sk: Dictionary, focus: BattleUnit) -> void:
	var col := _col(actor)
	var from := _home(actor) + Vector3(0, 1.3, 0)
	var kind: String = sk.get("target", "enemy")
	var dur := 0.28 / Session.battle_speed
	if kind == "enemy" and focus != null and focus.team != actor.team:
		BattleFx.projectile(self, from, _home(focus) + Vector3(0, 1.1, 0), col, dur)
		await get_tree().create_timer(dur).timeout
	elif kind == "all_enemies":
		var line_z := -3.0 if actor.team == 0 else 2.3
		for t in engine.enemies_of(actor):
			BattleFx.projectile(self, from, _home(t) + Vector3(0, 1.1, 0), col, dur)
		await get_tree().create_timer(dur).timeout
		BattleFx.shockwave(self, Vector3(0, 0, line_z), col, 4.5, 0.5 / Session.battle_speed)
		_shake(0.2)
	elif kind in ["all_allies", "ally", "other_ally", "self"]:
		var line_z := 2.3 if actor.team == 0 else -3.0
		BattleFx.shockwave(self, Vector3(0, 0, line_z), col.lightened(0.4), 4.0, 0.6 / Session.battle_speed)
		await _pause(0.2)


func _cam_to(pos: Vector3, look: Vector3, t: float) -> void:
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "cam_pos", pos, t / Session.battle_speed)
	tw.tween_property(self, "cam_look", look, t / Session.battle_speed)


func _reset_camera() -> void:
	_cam_to(CAM_POS, CAM_LOOK, 0.45)


func _shake(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)


## Arrêt sur image d'un instant (une fois par action) : le coup « pèse ».
func _hitstop(duration: float) -> void:
	if hitstop_used or Session.smoke_test:
		return
	hitstop_used = true
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


func _on_battle_event(ev: Dictionary) -> void:
	if ev["type"] in ["effect", "effect_end", "death", "revive"] and ev.has("target"):
		_status_look.call_deferred(ev["target"])
	var line := BattleLog.describe(ev)
	if line != "" and log_label != null:
		var color := "#c9a24a" if ev["type"] in ["turn_start", "battle_end"] else "#d8d4e8"
		log_label.append_text("[color=%s]%s[/color]\n" % [color, line])
	match ev["type"]:
		"damage":
			var t: BattleUnit = ev["target"]
			var crit: bool = ev.get("crit", false)
			var dot := ev.has("dot")
			var src: BattleUnit = ev.get("source")
			var col := Color("ff9a3d") if crit else (Color("c9b8ff") if dot else Color.WHITE)
			_float_text(t, str(int(ev["amount"])) + (" !" if crit else ""), col, 1.3 if crit else 1.0)
			if not dot:
				_play_anim(t, "crit_hit" if crit else "hit")
				if models.has(t):
					models[t].flash(Color(1, 1, 1, 0.7) if not crit else Color(1, 0.7, 0.45, 0.9), 0.18)
				if pawns.has(t):
					BattleFx.ink_splash(self, pawns[t].position + Vector3(0, 1.2, 0.3), _col(src) if src != null else Color.WHITE, crit)
				_shake(0.45 if crit else 0.22)
				if crit:
					_hitstop(0.07)
			elif models.has(t):
				models[t].flash(Color(0.55, 0.25, 0.8, 0.6), 0.25)
		"heal":
			var t: BattleUnit = ev["target"]
			_float_text(t, "+" + str(int(ev["amount"])), Color("6bdc8a"))
			if models.has(t):
				models[t].flash(Color(0.36, 1.0, 0.6, 0.6), 0.35)
			if pawns.has(t):
				BattleFx.petals(self, pawns[t].position + Vector3(0, 0.5, 0))
		"resist", "immune":
			_float_text(ev["target"], "Résiste", Color("a0a0b8"), 0.6)
		"miss":
			_float_text(ev["target"], "Raté", Color("a0a0b8"), 0.9)
		"phase":
			_float_text(ev["target"], ev["name"].to_upper(), Color("ff8a3d"), 1.4)
			_shake(0.6)
		"bar_break":
			_float_text(ev["target"], "BOUCLIER !", Color("7fc8ff"), 1.3)
			_shake(0.4)
		"shield_punish":
			_float_text(ev["target"], "ÉCRASEMENT", Color("ff5050"), 1.4)
			_shake(0.8)
		"boss_revive":
			_float_text(ev["target"], "RÉSURRECTION", Color("ff8a3d"), 1.4)
			if pawns.has(ev["target"]):
				BattleFx.burst(self, pawns[ev["target"]].position + Vector3(0, 1.0, 0), Color("ff8a3d"), 40, 3.0, 0.1, 1.2, true)
		"clone_absorb":
			_float_text(ev["target"], "Clone !", Color("b07de0"))
		"counter":
			_float_text(ev["actor"], "Riposte", Color("ffd27f"), 0.9)
			_play_anim(ev["actor"], "attack")
		"effect":
			_float_text(ev["target"], BattleLog.effect_name(ev["effect"]), Color("e0c060"), 0.6)
		"revive":
			if pawns.has(ev["target"]):
				_play_anim(ev["target"], "idle")
				BattleFx.burst(self, pawns[ev["target"]].position + Vector3(0, 0.5, 0), Color("fff0a0"), 30, 2.5, 0.09, 1.0, true)
		"death":
			var t: BattleUnit = ev["target"]
			_play_anim(t, "death")
			if pawns.has(t):
				BattleFx.burst(self, pawns[t].position + Vector3(0, 0.8, 0), Color("b07de0"), 36, 2.2, 0.09, 1.1, true)
			_shake(0.3)
			if not models.has(t):
				var tw := create_tween()
				tw.tween_property(pawns[t], "scale", Vector3(1, 0.15, 1), 0.3)


# --- Monde 3D ---------------------------------------------------------------

func _build_world() -> void:
	BattleFx.build_arena(self)
	cam = Camera3D.new()
	cam.fov = 50
	add_child(cam)
	cam.position = CAM_POS
	cam.look_at(CAM_LOOK)
	active_ring = BattleFx.flat_ring(UI_ACCENT, 0.75, 0.06, 0.9)
	active_ring.visible = false
	add_child(active_ring)
	for u in engine.units:
		var p := _make_pawn(u)
		p.position = _home(u)
		p.rotation_degrees.y = 180.0 if u.team == 0 else 0.0  # ton équipe de dos, les ennemis face à toi
		add_child(p)
		pawns[u] = p


## Place d'un combattant : ton équipe au premier plan, l'adversaire au fond (un boss seul au centre).
func _home(u: BattleUnit) -> Vector3:
	var alone := engine.units.filter(func(x: BattleUnit) -> bool: return x.team == u.team).size() == 1
	var x := 0.0 if alone else (u.slot - 1) * (2.1 if u.team == 0 else 2.5)
	return Vector3(x, 0.0, 2.3 if u.team == 0 else -3.0)


func _make_pawn(u: BattleUnit) -> Node3D:
	var root := Node3D.new()
	var height := float(u.data.get("height_m", 1.75))
	if CharacterModel.available():
		var model := CharacterModel.new()
		root.add_child(model)
		model.setup(u.id, _col(u), height)
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
	var shadow := BattleFx.flat_ring(Color(0, 0, 0), 0.5, 0.5, 0.0)  # ombre de contact douce
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0, 0, 0, 0.45)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow.material_override = sm
	shadow.position.y = 0.02
	root.add_child(shadow)
	if u.team == 0:
		return root  # ton équipe est au premier plan : ses PV sont dans les fiches en bas à gauche
	var bar := BattleFx.hp_bar(Color("e05050"))
	bar["root"].position.y = height + 0.35
	if engine.units.filter(func(x: BattleUnit) -> bool: return x.team == u.team).size() == 1:
		bar["root"].scale = Vector3(2.2, 1.6, 1.0)  # boss : grande barre de vie
	root.add_child(bar["root"])
	bars[u] = bar
	var label := Label3D.new()
	label.text = u.display_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = height + 0.55
	label.font_size = 30
	label.outline_size = 8
	label.modulate = _col(u).lightened(0.45)
	root.add_child(label)
	return root


## Contrôles visibles : Gel = statue blanc-bleu figée, Étourdissement = étoiles, Sommeil = « Z » et
## gestes ralentis ; Poison et Malédiction teintent légèrement.
func _status_look(u: BattleUnit) -> void:
	var m: CharacterModel = models.get(u)
	var alive := u.is_alive()
	if m != null:
		var tint := Color(0, 0, 0, 0)
		var speed := 1.0
		if alive and u.has_effect("freeze"):
			tint = Color(0.55, 0.8, 1.0, 0.65)
			speed = 0.0
		elif alive and u.has_effect("poison"):
			tint = Color(0.25, 0.95, 0.35, 0.18)
		elif alive and u.has_effect("curse"):
			tint = Color(0.65, 0.2, 0.9, 0.22)
		if alive and u.has_effect("sleep"):
			speed = 0.3
		m.set_status_look(tint, speed)
	var head := float(u.data.get("height_m", 1.75)) + (0.15 if u.team == 0 else 0.6)
	if alive and u.has_effect("stun") and not stars.has(u) and pawns.has(u):
		var ring := Node3D.new()
		ring.position.y = head
		for i in 4:
			var st := Label3D.new()
			st.text = "★"
			st.font_size = 40 if u.team == 0 else 64
			st.outline_size = 6
			st.modulate = Color("ffe066")
			st.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			var a := i * TAU / 4.0
			st.position = Vector3(cos(a) * 0.32, 0.05 * sin(a * 2.0), sin(a) * 0.32)
			ring.add_child(st)
		pawns[u].add_child(ring)
		stars[u] = ring
	elif (not alive or not u.has_effect("stun")) and stars.has(u):
		stars[u].queue_free()
		stars.erase(u)
	if alive and u.has_effect("sleep"):
		if not zz_timer.has(u):
			zz_timer[u] = 0.0
	else:
		zz_timer.erase(u)


func _spawn_z(u: BattleUnit) -> void:
	if not pawns.has(u):
		return
	var z := Label3D.new()
	z.text = "Z"
	z.font = GAME_FONT
	z.font_size = 34 if u.team == 0 else 64  # plus grand au fond de l'arène
	z.outline_size = 6
	z.modulate = Color("bfe3ff")
	z.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var head := float(u.data.get("height_m", 1.75)) + (0.0 if u.team == 0 else 0.4)
	z.position = pawns[u].position + Vector3(0.25, head, 0)
	z.scale = Vector3.ONE * 0.5
	add_child(z)
	var tw := create_tween().set_parallel()
	tw.tween_property(z, "position", z.position + Vector3(0.45, 0.7, 0), 1.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(z, "scale", Vector3.ONE * 1.1, 1.4)
	tw.tween_property(z, "modulate:a", 0.0, 0.6).set_delay(0.8)
	tw.chain().tween_callback(z.queue_free)


func _move_ring(actor: BattleUnit) -> void:
	if actor == null or not pawns.has(actor):
		return
	active_ring.visible = true
	var mat: StandardMaterial3D = active_ring.material_override
	mat.albedo_color = _col(actor).lightened(0.3)
	mat.emission = mat.albedo_color
	var tw := create_tween()
	tw.tween_property(active_ring, "position", _home(actor) + Vector3(0, 0.03, 0), 0.15)


func _col(u: BattleUnit) -> Color:
	if u == null:
		return Color.WHITE
	return COLORS.get(u.constellation, Color("b8a890"))  # boss neutre


func _play_anim(u: BattleUnit, action: String) -> void:
	var model: CharacterModel = models.get(u)
	if model != null:
		model.play(action)


func _float_text(u: BattleUnit, text: String, color: Color, size := 1.0) -> void:
	if not pawns.has(u):
		return
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font = GAME_FONT
	l.font_size = int(30 * size)
	l.outline_size = 7
	l.outline_modulate = Color(0.05, 0.02, 0.08)
	# textes simultanés sur la même cible : empilés au lieu de se superposer
	var now := Time.get_ticks_msec()
	var last: Array = float_stack.get(u, [0, -1])
	var row: int = last[1] + 1 if now - int(last[0]) < 450 else 0
	float_stack[u] = [now, row]
	var h := float(u.data.get("height_m", 1.75))
	var base_y := (h * 0.75) if u.team == 0 else (h + 0.3)
	l.position = pawns[u].position + Vector3(randf_range(-0.25, 0.25), base_y + row * 0.32, 0.3)
	l.scale = Vector3.ONE * 1.45
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "position:y", l.position.y + 0.9, 0.9 / Session.battle_speed)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.5 / Session.battle_speed).set_delay(0.45 / Session.battle_speed)
	tw.tween_callback(l.queue_free)


# --- Interface --------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	dim = ColorRect.new()  # assombrissement des ultimes
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.0, 0.05, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	banner = UiKit.label("", 54, Color.WHITE)
	banner.add_theme_font_override("font", GAME_FONT)
	banner.add_theme_constant_override("outline_size", 14)
	banner.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.08))
	banner.position = Vector2(-400, 250)
	root.add_child(banner)
	banner_sub = UiKit.label("", 22, Color("e8e0ff"))
	banner_sub.position = Vector2(46, 228)
	banner_sub.modulate.a = 0.0
	root.add_child(banner_sub)

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 8
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	turn_label = UiKit.label("", 17, UI_ACCENT)
	turn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(turn_label)
	ui_root = root
	var infos := Button.new()
	infos.text = "Infos"
	infos.pressed.connect(_toggle_info)
	top.add_child(infos)
	var journal := Button.new()
	journal.text = "Journal"
	journal.pressed.connect(func() -> void: log_panel.visible = not log_panel.visible)
	top.add_child(journal)
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

	_build_action_bar(root)

	var enemy_col := VBoxContainer.new()  # fiches ennemies en haut à droite
	enemy_col.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	enemy_col.offset_left = -250
	enemy_col.offset_right = -14
	enemy_col.offset_top = 104
	enemy_col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	enemy_col.add_theme_constant_override("separation", 6)
	root.add_child(enemy_col)
	var ally_col := VBoxContainer.new()  # ta fiche d'équipe en bas à gauche
	ally_col.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ally_col.offset_left = 14
	ally_col.offset_right = 250
	ally_col.offset_bottom = -14
	ally_col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ally_col.add_theme_constant_override("separation", 6)
	root.add_child(ally_col)
	for u in engine.units:
		(ally_col if u.team == 0 else enemy_col).add_child(_make_card(u))

	log_panel = PanelContainer.new()
	log_panel.add_theme_stylebox_override("panel", _panel_style(Color(UI_BG, 0.88)))
	log_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	log_panel.offset_left = 14
	log_panel.offset_right = 430
	log_panel.offset_top = 104
	log_panel.offset_bottom = -260
	log_panel.visible = false
	root.add_child(log_panel)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.add_theme_font_size_override("normal_font_size", 13)
	log_panel.add_child(log_label)

	action_box = HBoxContainer.new()
	action_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	action_box.offset_left = -330
	action_box.offset_right = 330
	action_box.offset_top = -92
	action_box.offset_bottom = -14
	action_box.alignment = BoxContainer.ALIGNMENT_CENTER
	action_box.add_theme_constant_override("separation", 10)
	root.add_child(action_box)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	result_panel = PanelContainer.new()
	result_panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(UI_BG, 0.95), UI_ACCENT, 2, 10))
	result_panel.custom_minimum_size.x = 460
	result_panel.visible = false
	center.add_child(result_panel)


## Barre d'action (Dislyte) : la position de chaque combattant suit sa jauge ; à droite, il joue.
func _build_action_bar(root: Control) -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_CENTER_TOP)
	holder.offset_left = -320
	holder.offset_right = 320
	holder.offset_top = 44
	holder.offset_bottom = 96
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	var track := ColorRect.new()
	track.color = Color(UI_ACCENT, 0.55)
	track.position = Vector2(0, 25)
	track.size = Vector2(640, 3)
	holder.add_child(track)
	var goal := UiKit.label("▶", 18, UI_ACCENT)
	goal.position = Vector2(642, 12)
	holder.add_child(goal)
	action_track = holder
	for u in engine.units:
		var m := PanelContainer.new()
		var st := UiKit.panel_style(Color(_col(u), 0.85), Color.WHITE if u.team == 0 else Color("ff6060"), 1, 5)
		st.set_content_margin_all(2)
		m.add_theme_stylebox_override("panel", st)
		if UiKit.portrait_texture(u.id) != null:
			m.add_child(UiKit.portrait(u.id, 28))
		else:
			var l := UiKit.label(u.display_name.substr(0, 3), 11, Color.WHITE)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.custom_minimum_size = Vector2(30, 0)
			m.add_child(l)
		m.position = Vector2(0, 30 if u.team == 0 else 0)  # alliés sous la ligne, ennemis au-dessus
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(m)
		markers[u] = m


func _make_card(u: BattleUnit) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(UI_BG, 0.82), _col(u)))
	panel.custom_minimum_size.x = 236
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	v.add_child(head)
	if UiKit.portrait_texture(u.id) != null:
		head.add_child(UiKit.portrait(u.id, 30))
	var name_label := UiKit.label(u.display_name, 14)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(name_label)
	var hp := ProgressBar.new()
	hp.max_value = u.max_hp()
	hp.show_percentage = false
	hp.custom_minimum_size.y = 8
	var fill := StyleBoxFlat.new()
	fill.bg_color = _col(u).lightened(0.2) if u.team == 0 else Color("d04848")
	fill.set_corner_radius_all(3)
	hp.add_theme_stylebox_override("fill", fill)
	v.add_child(hp)
	var info := UiKit.label("", 11, Color("cfc8e8"))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(info)
	cards[u] = {"hp": hp, "info": info, "panel": panel}
	return panel


func _panel_style(bg: Color, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.set_content_margin_all(7)
	if border.a > 0.0:
		s.border_color = border
		s.border_width_left = 4
	return s


func _refresh() -> void:
	for u: BattleUnit in cards:
		var c: Dictionary = cards[u]
		c["hp"].max_value = u.max_hp()
		var tw := create_tween()
		tw.tween_property(c["hp"], "value", u.hp, 0.25)
		var parts: Array[String] = ["PV %d/%d" % [int(u.hp), int(u.max_hp())]]
		if u.shield_value() > 0.0:
			parts.append("Bouclier %d" % int(u.shield_value()))
		for e in u.effects:
			var turns := int(e["turns"])
			if e["id"] == "shield":
				continue
			var label := BattleLog.effect_name(e["id"]) + (" x%d" % int(e["stacks"]) if int(e.get("stacks", 1)) > 1 else "")
			parts.append(label if turns > 99 else "%s(%d)" % [label, turns])
		for s: String in u.stacks:
			if u.stack(s) > 0:
				parts.append("%s %d" % [STACK_NAMES.get(s, s.capitalize()), u.stack(s)])
		c["info"].text = "  ".join(parts) if u.is_alive() else "Hors combat"
		c["panel"].modulate = Color(1, 1, 1, 1.0 if u.is_alive() else 0.4)
	if engine.current != null:
		turn_label.text = "Au tour de : %s" % engine.current.display_name


## Fiche des combattants : stats, compétences (recharges) et effets actifs avec leur explication.
func _toggle_info() -> void:
	if info_panel != null:
		info_panel.queue_free()
		info_panel = null
		return
	info_panel = PanelContainer.new()
	info_panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(UI_BG, 0.96), UI_ACCENT, 2, 12))
	info_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		info_panel.set("offset_" + side, 60 if side == "left" else -60)
	info_panel.offset_top = 52
	info_panel.offset_bottom = -20
	ui_root.add_child(info_panel)
	var v := VBoxContainer.new()
	info_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UiKit.label("Combattants", 22, UI_ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UiKit.button("Fermer", _toggle_info, Vector2(110, 40)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var cols := HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	scroll.add_child(cols)
	for team in 2:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 10)
		cols.add_child(col)
		col.add_child(UiKit.label("Ton équipe" if team == 0 else "Adversaires", 17, Color("cfc8e8")))
		for u in engine.units:
			if u.team == team:
				col.add_child(_unit_info(u))


func _unit_info(u: BattleUnit) -> Control:
	var p := UiKit.panel(_col(u))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	var cls: String = UiKit.CLASS_NAMES.get(u.data.get("class", ""), "Boss")
	v.add_child(UiKit.label("%s  ·  %s%s" % [u.display_name, cls, "" if u.is_alive() else "  (hors combat)"], 16, _col(u).lightened(0.4)))
	v.add_child(UiKit.label("PV %d/%d   ATK %d   DEF %d   VIT %d   TC %d %%   DC %d %%   PRÉ %d   RÉS %d" % [
		int(u.hp), int(u.max_hp()), int(u.stat("atk")), int(u.stat("def")), int(u.stat("spd")), int(u.stat("cr")),
		int(u.stat("cd")), int(u.stat("acc")), int(u.stat("res"))], 12, Color("cfc8e8")))
	for i in 3:
		var sk := u.skill(i)
		var state := "passif" if u.is_passive(i) else ("prête" if u.cooldowns[i] == 0 else "recharge %d" % u.cooldowns[i])
		var sl := UiKit.label("%s · %s  (%s)" % [["S1", "S2", "Ultime"][i], sk["name"], state], 13, Color.WHITE if state != "passif" else Color("b8b0d8"))
		v.add_child(sl)
		var d := UiKit.label(UiKit.skill_text(sk), 11, UiKit.DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD
		v.add_child(d)
	if u.effects.is_empty():
		v.add_child(UiKit.label("Aucun effet actif.", 12, UiKit.DIM))
	for e in u.effects:
		var def: Dictionary = GameData.rules()["effects"][e["id"]]
		var kind: String = def["kind"]
		var col := Color("7fd8a0") if kind == "buff" or kind == "aura" else (Color("ff8a7a") if kind in ["debuff", "cc", "mark"] else Color("e0c060"))
		var turns := int(e["turns"])
		var st := int(e.get("stacks", 1))
		var txt := "%s%s%s : %s" % [BattleLog.effect_name(e["id"]), " x%d" % st if st > 1 else "",
			"" if turns > 99 else " (%d t)" % turns, def.get("desc", "")]
		var el := UiKit.label(txt, 12, col)
		el.autowrap_mode = TextServer.AUTOWRAP_WORD
		v.add_child(el)
	return p


func _clear_actions() -> void:
	for c in action_box.get_children():
		c.queue_free()


func _skill_button(text: String, border: Color, cb: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 72)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD
	b.add_theme_stylebox_override("normal", UiKit.panel_style(Color(UI_BG, 0.9), border, 2, 12))
	b.add_theme_stylebox_override("hover", UiKit.panel_style(Color(border, 0.3), border, 3, 12))
	b.add_theme_stylebox_override("pressed", UiKit.panel_style(Color(border, 0.5), border, 3, 12))
	b.add_theme_stylebox_override("disabled", UiKit.panel_style(Color(UI_BG, 0.7), Color(border, 0.25), 1, 12))
	b.disabled = disabled
	b.pressed.connect(cb)
	b.scale = Vector2(0.85, 0.85)
	b.pivot_offset = b.custom_minimum_size / 2.0
	var tw := b.create_tween()  # les boutons apparaissent avec un petit rebond
	tw.tween_property(b, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return b


func _show_actions(actor: BattleUnit) -> void:
	waiting_input = true
	_clear_actions()
	for i in 3:
		var sk := actor.skill(i)
		var border := UI_ACCENT if i == 2 else _col(actor).lightened(0.2)
		if actor.is_passive(i):
			var pb := _skill_button("%s · %s\n(passif)" % [["S1", "S2", "S3"][i], sk["name"]], Color("6a6488"), func() -> void: pass, true)
			pb.tooltip_text = sk.get("desc", "")
			action_box.add_child(pb)
		else:
			var cd := actor.cooldowns[i]
			var txt := "%s · %s" % [["S1", "S2", "ULTIME"][i], sk["name"]] + ("\nrecharge %d" % cd if cd > 0 else "")
			var b := _skill_button(txt, border, _on_skill_chosen.bind(actor, i), not i in engine.usable_skills(actor))
			b.tooltip_text = UiKit.skill_text(sk)
			action_box.add_child(b)


func _on_skill_chosen(actor: BattleUnit, idx: int) -> void:
	if not engine.needs_target(actor, idx):
		waiting_input = false
		await _perform(actor, idx, null)
		_advance()
		return
	_clear_actions()
	for t in engine.valid_targets(actor, idx):
		var b := _skill_button("%s\n%d %% PV" % [t.display_name, int(t.hp_ratio() * 100)], _col(t), func() -> void:
			waiting_input = false
			await _perform(actor, idx, t)
			_advance())
		b.custom_minimum_size = Vector2(170, 64)
		action_box.add_child(b)
	action_box.add_child(_skill_button("Retour", Color("6a6488"), _show_actions.bind(actor)))


func _show_result() -> void:
	if done:
		return
	done = true
	_clear_actions()
	active_ring.visible = false
	var v := VBoxContainer.new()
	var title := Label.new()
	title.text = {0: "VICTOIRE", 1: "DÉFAITE"}.get(engine.winner, "ÉGALITÉ")
	title.add_theme_font_override("font", GAME_FONT)
	title.add_theme_font_size_override("font_size", 52)
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
		_reward_lines(v, ls)
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
		_reward_lines(v, lines)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	if in_tower and engine.winner == 0 and Session.profile.can_enter_floor(floor_n + 1) and floor_n < Tower.floor_count():
		var nb := UiKit.button("Étage suivant  ›", func() -> void: Session.start_tower_floor(floor_n + 1), Vector2(190, 52))
		nb.add_theme_stylebox_override("normal", UiKit.panel_style(Color("4a3a12"), UI_ACCENT, 2, 10))  # action principale
		nb.add_theme_color_override("font_color", Color("fff1c4"))
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
	result_panel.scale = Vector2(0.7, 0.7)
	result_panel.pivot_offset = result_panel.size / 2.0
	create_tween().tween_property(result_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for u in engine.units:
		if u.is_alive() and u.team == engine.winner:
			_play_anim(u, "victory")
	if engine.winner == 0:  # la caméra se rapproche des vainqueurs
		_cam_to(Vector3(0, 2.2, 6.0), Vector3(0, 1.2, 1.6), 1.2)
	finished.emit(engine.winner)
	if Session.smoke_test:
		print("Test de fumée OK : combat terminé (vainqueur %d, %d actions)" % [engine.winner, engine.total_actions])
		get_tree().quit(0)


## Récompenses révélées une à une (retour gratifiant) ; les plus importantes en doré.
func _reward_lines(v: VBoxContainer, lines: Array[String]) -> void:
	for k in lines.size():
		var key := lines[k].contains("Éclats") or lines[k].contains("franchi") or lines[k].contains("débloqué") or lines[k].contains("garantie")
		var l := UiKit.label(lines[k], 18 if key else 15, UI_ACCENT if key else Color("e8e2ff"))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.modulate.a = 0.0
		v.add_child(l)
		var tw := l.create_tween()
		tw.tween_interval(0.35 + 0.22 * k)
		tw.tween_property(l, "modulate:a", 1.0, 0.2)


func _back_to_menu() -> void:
	Engine.time_scale = 1.0
	var back := {"tower": "res://scenes/tower.tscn", "loot": "res://scenes/loot.tscn"}
	get_tree().change_scene_to_file(back.get(Session.battle.get("mode", ""), "res://scenes/main.tscn"))
