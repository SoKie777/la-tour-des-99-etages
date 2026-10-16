class_name BattleScene
extends Node3D
## Scène de combat jouable, mise en scène façon Dislyte : ton équipe au premier plan (de dos), les ennemis
## dans le fond face à la caméra. Effets : tremblement de caméra, arrêt sur image sur les critiques, éclats
## de couleur et étincelles à l'impact, gros plan et bannière sur les ultimes, barre d'action en haut.
## Personnages : modèle MPFB res://assets/models/<id>.fbx s'il existe, sinon le mannequin Y Bot teinté.

signal finished(winner: int)

const COLORS := {"orion": Color("4d8fd6"), "grande_ourse": Color("c8553d"), "sirius": Color("9b6bd6")}
const UI_BG := UiKit.BG  # palette de la Bible D.A.
const UI_ACCENT := UiKit.ACCENT
const STACK_NAMES := {"spark": "Étincelle", "fury": "Fureur", "rage": "Rage", "visage": "Visage", "dette": "Dette",
	"clone": "Clones", "inertia": "Inertie"}
const CAM_FOV := 40.0  # focale serrée (Bible D.A.) : caméra reculée d'autant, les héros ressortent du décor
const CAM_POS := Vector3(0, 3.69, 10.37)
const CAM_LOOK := Vector3(0, 1.0, -0.9)
const RANGED := ["cast", "heal", "roar", "taunt", "block"]  # animations jouées sur place
const GAME_FONT := preload("res://assets/fonts/LilitaOne-Regular.ttf")  # police libre (OFL), chiffres et titres

var engine: BattleEngine
var pawns := {}        # BattleUnit -> Node3D
var models := {}       # BattleUnit -> CharacterModel
var bars := {}         # BattleUnit -> barre de vie 3D
var cards := {}        # BattleUnit -> {hp: ProgressBar, info: Label}
var status_rows := {}  # BattleUnit -> Node3D : icônes des effets au-dessus de la tête
var markers := {}      # BattleUnit -> marqueur de la barre d'action
var marker_status := {}  # BattleUnit -> petites icônes d'effets sous/sur le marqueur
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
var flash_rect: ColorRect  # frame d'impact noir et blanc des ultimes
## Mode tactique de la Tour : ultimes en attente (coupure de la ligne de temps), réserve de Sceaux.
var ult_queue: Array[BattleUnit] = []
var sp_row: HBoxContainer
var enemy_col_ref: Control  # fiches (cibles du tutoriel de la Tour)
var ally_col_ref: Control


func _ready() -> void:
	var teams := Session.battle_teams()
	engine = BattleEngine.new(teams[0], teams[1])
	engine.battle_event.connect(_on_battle_event)
	if Session.battle.get("mode", "") == "tower":  # mode tactique : seulement dans l'Ascension (et le prologue)
		engine.enable_tactics(Tower.tactics_rank(int(Session.battle["floor"])))
	var prologue_lv := int(Session.battle.get("level", 0)) if Session.battle.get("mode", "") == "prologue" else 0
	if prologue_lv > 0:
		engine.enable_tactics(Prologue.tactics_rank(prologue_lv))
		engine.unlosable = Prologue.level(prologue_lv).get("safe", false)
	_build_world()
	_build_ui()
	_refresh()
	var forced := -1  # captures : -- --tuto=<page>
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tuto="):
			forced = int(a.trim_prefix("--tuto="))
	if not engine.tactics.is_empty() and (not Session.smoke_test or forced >= 0):  # tutoriel : premier combat de la Tour, premier boss
		var prof := Session.profile
		var pages: Array[Dictionary] = []
		if forced >= 0:
			await _open_tutorial(TowerTutorial.pick(Prologue.level(prologue_lv)["tips"]) if prologue_lv > 0 else TowerTutorial.page_list(engine.ult_cut), forced)
		elif prologue_lv > 0:  # prologue : les pages du niveau, une seule fois
			if not prof.seen_tips.has("prologue_%d" % prologue_lv):
				pages = TowerTutorial.pick(Prologue.level(prologue_lv).get("tips", []))
				prof.seen_tips["prologue_%d" % prologue_lv] = true
				if engine.ult_cut:
					prof.seen_tips["tower_boss"] = true
		elif not prof.seen_tips.has("tower") and prof.seen_tips.has("prologue_1"):  # déjà vu au prologue
			pages = TowerTutorial.pick(["tower", "stars"])
			prof.seen_tips["tower"] = true
		elif not prof.seen_tips.has("tower"):
			pages = TowerTutorial.page_list(engine.ult_cut)
			prof.seen_tips["tower"] = true
			if engine.ult_cut:
				prof.seen_tips["tower_boss"] = true
		elif engine.ult_cut and not prof.seen_tips.has("tower_boss"):
			pages = TowerTutorial.page_list(true, true)
			prof.seen_tips["tower_boss"] = true
		if not pages.is_empty():
			Session.save()
			await _open_tutorial(pages)
	_advance()


## Explications du mode tactique (pages de TowerTutorial), avec un cadre sur la zone concernée.
func _open_tutorial(pages: Array[Dictionary], first := 0) -> void:
	var t := TowerTutorial.new()
	ui_root.add_child(t)
	t.start(pages, {"enemies": enemy_col_ref, "allies": ally_col_ref, "track": action_track,
		"sceaux": sp_row.get_parent() if sp_row != null else null}, first)
	await t.closed


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
		b["tough"].scale.x = clampf(u.toughness / u.max_toughness, 0.0, 1.0) if u.max_toughness > 0.0 else 0.0
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
			# boss en charge : son marqueur clignote en rouge sceau sur la ligne de temps
			m.modulate = Color(1.0, 0.45, 0.4) if u.charging > 0 and (Time.get_ticks_msec() / 250) % 2 == 0 else Color.WHITE
			m.position.x = lerpf(m.position.x, clampf(u.ap, 0.0, 1.0) * w - m.size.x / 2.0, minf(1.0, delta * 10.0))


# --- Déroulement ------------------------------------------------------------

func _advance() -> void:
	while true:
		if engine.winner != BattleEngine.ONGOING:
			_show_result()
			return
		await _run_ult_queue()
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


## cut : ultime hors tour du mode tactique (coupure de la ligne de temps, le tour n'est pas consommé).
func _perform(actor: BattleUnit, skill_idx: int, target: BattleUnit, cut := false) -> void:
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
	if cut:
		engine.cast_ultimate(actor, target)
	else:
		engine.use_skill(actor, skill_idx, target)
	if skill_idx == 2:
		_impact_flash()
	_refresh()
	if melee:
		var back := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		back.tween_property(pawn, "position", home, 0.25 / Session.battle_speed)
		await back.finished
	await _pause(0.3)


## Frame d'impact d'un ultime : un éclair noir et blanc à l'encre (Bible D.A., étape 4).
func _impact_flash() -> void:
	if flash_rect == null or Session.smoke_test:
		return
	flash_rect.visible = true
	var m: ShaderMaterial = flash_rect.material
	m.set_shader_parameter("amount", 1.0)
	var tw := create_tween()
	tw.tween_interval(0.07)
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("amount", v), 1.0, 0.0, 0.18)
	tw.tween_callback(func() -> void: flash_rect.visible = false)


## Ultimes en attente (mode tactique) : joués avant le tour suivant, quel que soit le joueur actif.
## En mode Auto, chaque héros lance son ultime dès que son énergie est pleine.
func _run_ult_queue() -> void:
	if not engine.ult_cut:
		return
	if Session.auto_battle:
		for u in engine.ready_ultimates():
			if not u in ult_queue:
				ult_queue.append(u)
	while not ult_queue.is_empty() and engine.winner == BattleEngine.ONGOING:
		var u: BattleUnit = ult_queue.pop_front()
		if engine.ult_ready(u):
			var t: BattleUnit = engine.ai_target(u, 2) if engine.needs_target(u, 2) else null
			await _perform(u, 2, t, true)
	_refresh()


## Bouton d'ultime d'un héros (fiche ou barre d'actions). Pendant ton tour : il coupe immédiatement la
## ligne de temps (choix de la cible), puis ton héros actif joue normalement ; sinon il passe en file.
func _on_ult_pressed(u: BattleUnit) -> void:
	if done or not engine.ult_ready(u) or u in ult_queue:
		return
	if not waiting_input:
		ult_queue.append(u)
		_float_text(u, "!", UI_ACCENT, 1.2)
		return
	var actor: BattleUnit = engine.current
	_clear_actions()
	var go := func(t: BattleUnit) -> void:
		waiting_input = false
		await _perform(u, 2, t, true)
		if engine.winner != BattleEngine.ONGOING:
			_show_result()
		else:
			_refresh()
			_show_actions(actor)
	var targets := engine.valid_targets(u, 2) if engine.needs_target(u, 2) else [] as Array[BattleUnit]
	if targets.size() <= 1:
		go.call(targets[0] if not targets.is_empty() else null)
		return
	for t in targets:
		var b := _skill_button(t.display_name, _col(t), go.bind(t))
		b.custom_minimum_size = Vector2(170, 64)
		_corner(b, UiKit.amount("hp", "%d %%" % int(t.hp_ratio() * 100), 12))
		action_box.add_child(b)
	action_box.add_child(UiKit.icon_button("back", _show_actions.bind(actor), 64))


func _pause(seconds: float) -> void:
	await get_tree().create_timer(seconds / Session.battle_speed).timeout


func _anim_name(u: BattleUnit, action: String) -> String:
	var m: CharacterModel = models.get(u)
	return str(m.anims.get(action, action)) if m != null else action


## Gros plan sur le lanceur, écran assombri, nom de l'ultime en grand.
func _ultimate_intro(actor: BattleUnit, skill_name: String) -> void:
	var p := _home(actor)
	var facing := -1.0 if actor.team == 0 else 1.0  # ton équipe regarde vers le fond : on la filme de face
	_cam_to(p + Vector3(1.5, 1.7, 4.7 * facing), p + Vector3(0, 1.15, 0), 0.35)
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
					BattleFx.ink_slash(self, pawns[t].position + Vector3(0, 1.1, 0.45), _col(src).lightened(0.3) if src != null else UI_ACCENT,
						crit, 0.28 / Session.battle_speed)
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
			_float_icon(ev["target"], UiKit.icon_texture("res"))
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
			_float_icon(ev["target"], UiKit.status_texture(ev["effect"]))
		"break":  # Rupture : gros éclat d'encre, la cible recule sur la ligne de temps
			var bt: BattleUnit = ev["target"]
			_float_text(bt, "RUPTURE", UiKit.PAPER, 1.5)
			if pawns.has(bt):
				BattleFx.ink_splash(self, pawns[bt].position + Vector3(0, 1.2, 0.3), UiKit.PAPER, true)
				BattleFx.shockwave(self, pawns[bt].position, UiKit.PAPER, 2.5, 0.4 / Session.battle_speed)
			_shake(0.6)
			_hitstop(0.09)
		"pursuit":  # Montana : poursuite en chaîne
			var pa: BattleUnit = ev["actor"]
			var pt: BattleUnit = ev["target"]
			_float_text(pa, "»%d" % int(ev["n"]), UI_ACCENT, 1.0 + 0.15 * int(ev["n"]))
			_play_anim(pa, "attack")
			if pawns.has(pt):
				BattleFx.ink_slash(self, pawns[pt].position + Vector3(0, 1.1, 0.45), _col(pa).lightened(0.3), false, 0.22 / Session.battle_speed)
		"follow_up":  # assaut coordonné après une Rupture
			_play_anim(ev["actor"], "attack")
		"charge":  # boss : charge télégraphiée (Oblitération à son prochain tour)
			_float_icon(ev["actor"], UiKit.icon_texture("charge"))
			if models.has(ev["actor"]):
				models[ev["actor"]].flash(Color(UiKit.VERMILION, 0.7), 0.6)
			_shake(0.3)
		"obliterate":
			_float_text(ev["actor"], "!!!", UiKit.VERMILION.lightened(0.3), 1.6)
			BattleFx.shockwave(self, Vector3(0, 0, 2.3), UiKit.VERMILION, 6.0, 0.6 / Session.battle_speed)
			_shake(1.0)
			_impact_flash()
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
	BattleDecor.build(self, _decor_id())
	cam = Camera3D.new()
	cam.fov = CAM_FOV
	cam.attributes = BattleDecor.camera_blur()  # léger flou du lointain : l'arène se détache du décor
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


## Décor du lieu (clé « decor » des données) ; argument « --decor=<id> » pour le forcer (captures, tests).
func _decor_id() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--decor="):
			return a.trim_prefix("--decor=")
	match Session.battle.get("mode", ""):
		"tower":
			return Tower.floor_info(int(Session.battle["floor"])).get("decor", "dojo")
		"loot":
			return LootBoss.boss(Session.battle["boss"]).get("decor", "dojo")
		"prologue":
			return Prologue.level(int(Session.battle["level"])).get("decor", "dojo")
	return "dojo"


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
	root.add_child(BattleFx.unit_seal(UI_ACCENT if u.team == 0 else UiKit.VERMILION.lightened(0.15)))  # socle-sceau
	var row := Node3D.new()  # icônes des buffs (bleus) et debuffs (rouges) au-dessus de la tête
	row.position.y = height + (0.3 if u.team == 0 else 0.85)
	root.add_child(row)
	status_rows[u] = row
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
	# faction bien visible : emblème de constellation au-dessus du nom ; pour un boss, ses faiblesses en grand
	var marks: Array[Dictionary] = []
	if u.get_trait("boss") != null:
		marks.append({"tex": UiKit.icon_texture("dmg_taken"), "col": UiKit.VERMILION.lightened(0.3)})
		for c in engine.weakness_of(u):
			marks.append({"tex": UiKit.icon_texture(c), "col": UiKit.CONST_COLORS[c].lightened(0.35)})
	elif UiKit.CONST_COLORS.has(u.constellation):
		marks.append({"tex": UiKit.icon_texture(u.constellation), "col": UiKit.CONST_COLORS[u.constellation].lightened(0.35)})
	var big := u.get_trait("boss") != null
	for i in marks.size():
		var sp := Sprite3D.new()
		sp.texture = marks[i]["tex"]
		sp.modulate = marks[i]["col"]
		sp.pixel_size = 0.0085 if big else 0.0055
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.no_depth_test = true
		sp.render_priority = 2
		sp.position = Vector3((i - (marks.size() - 1) / 2.0) * (0.62 if big else 0.4), height + (1.05 if big else 0.85), 0)
		root.add_child(sp)
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
	_float_node(u, l)


## Effet posé : son icône jaillit au-dessus de la cible (règle UI : pas de texte).
func _float_icon(u: BattleUnit, tex: Texture2D) -> void:
	if not pawns.has(u) or tex == null:
		return
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.pixel_size = 0.005
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.no_depth_test = true
	sp.render_priority = 4
	_float_node(u, sp)


func _float_node(u: BattleUnit, l: Node3D) -> void:
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
	root.theme = UiKit.theme()
	layer.add_child(root)

	dim = ColorRect.new()  # assombrissement des ultimes
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.0, 0.05, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://assets/materials/shaders/impact_flash.gdshader")
	flash_rect.material = fm
	flash_rect.visible = false
	root.add_child(flash_rect)
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
	top.add_child(UiKit.icon("turn", 16, UI_ACCENT))
	turn_label = UiKit.label("", 17, UI_ACCENT)
	turn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(turn_label)
	ui_root = root
	if not engine.tactics.is_empty():  # règles de la Tour, à revoir à tout moment
		var help := UiKit.button("?", func() -> void: _open_tutorial(TowerTutorial.page_list(engine.ult_cut)), Vector2(40, 40))
		help.add_theme_font_size_override("font_size", 22)
		top.add_child(help)
	top.add_child(UiKit.icon_button("info", _toggle_info, 40))
	top.add_child(UiKit.icon_button("journal", func() -> void: log_panel.visible = not log_panel.visible, 40))
	var auto := UiKit.icon_button("auto", func() -> void: pass, 40)  # combat automatique : bouton à bascule
	auto.toggle_mode = true
	auto.button_pressed = Session.auto_battle
	auto.toggled.connect(func(on: bool) -> void:
		Session.auto_battle = on
		if on and waiting_input:
			waiting_input = false
			_advance())
	top.add_child(auto)
	var speed := Button.new()
	speed.custom_minimum_size = Vector2(52, 40)
	speed.text = "x%d" % int(Session.battle_speed)
	speed.pressed.connect(func() -> void:
		Session.battle_speed = 1.0 if Session.battle_speed >= 3.0 else Session.battle_speed + 1.0
		speed.text = "x%d" % int(Session.battle_speed))
	top.add_child(speed)
	top.add_child(UiKit.icon_button("quit", _back_to_menu, 40))

	_build_action_bar(root)

	var enemy_col := VBoxContainer.new()  # fiches ennemies en haut à droite
	enemy_col.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	enemy_col.offset_left = -250
	enemy_col.offset_right = -14
	enemy_col.offset_top = 104
	enemy_col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	enemy_col.add_theme_constant_override("separation", 6)
	root.add_child(enemy_col)
	enemy_col_ref = enemy_col
	var ally_col := VBoxContainer.new()  # ta fiche d'équipe en bas à gauche
	ally_col.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ally_col.offset_left = 14
	ally_col.offset_right = 250
	ally_col.offset_bottom = -14
	ally_col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ally_col.add_theme_constant_override("separation", 6)
	root.add_child(ally_col)
	ally_col_ref = ally_col
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
	action_box.offset_left = -360
	action_box.offset_right = 360
	action_box.offset_top = -92
	action_box.offset_bottom = -14
	action_box.alignment = BoxContainer.ALIGNMENT_CENTER
	action_box.add_theme_constant_override("separation", 10)
	root.add_child(action_box)
	if not engine.tactics.is_empty():
		var sp_box := HBoxContainer.new()  # Sceaux de l'équipe (et Résonance des constellations)
		sp_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		sp_box.offset_left = -200
		sp_box.offset_right = 200
		sp_box.offset_top = -124
		sp_box.offset_bottom = -100
		sp_box.alignment = BoxContainer.ALIGNMENT_CENTER
		sp_box.add_theme_constant_override("separation", 14)
		sp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(sp_box)
		sp_row = HBoxContainer.new()
		sp_row.add_theme_constant_override("separation", 4)
		sp_box.add_child(sp_row)
		for i in engine.sp_max:
			sp_row.add_child(UiKit.icon("sceau", 20))
		var cons := {}
		for u in engine.units:
			if u.team == 0:
				cons[u.constellation] = int(cons.get(u.constellation, 0)) + 1
		for k: String in cons:
			if int(cons[k]) >= 2:
				sp_box.add_child(UiKit.amount(k, "×%d" % int(cons[k]), 12, UiKit.CONST_COLORS[k].lightened(0.3)))
		if cons.size() >= 3:
			var tri := HBoxContainer.new()
			for k: String in cons:
				tri.add_child(UiKit.icon(k, 16, UiKit.CONST_COLORS[k].lightened(0.3)))
			sp_box.add_child(tri)

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
	holder.offset_left = -300
	holder.offset_right = 300
	holder.offset_top = 52
	holder.offset_bottom = 110
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	var track := ColorRect.new()  # fil du temps, centré
	track.color = Color(UI_ACCENT, 0.7)
	track.position = Vector2(0, 28)
	track.size = Vector2(600, 2)
	holder.add_child(track)
	for x in [0.0, 600.0]:
		var tick := ColorRect.new()
		tick.color = UI_ACCENT
		tick.position = Vector2(x - 1, 22)
		tick.size = Vector2(2, 14)
		holder.add_child(tick)
	var goal := UiKit.icon("turn", 16, UI_ACCENT)
	goal.position = Vector2(606, 21)
	holder.add_child(goal)
	action_track = holder
	for u in engine.units:
		var m := VBoxContainer.new()
		m.add_theme_constant_override("separation", 1)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := PanelContainer.new()  # case carrée épurée
		var frame: Color = UiKit.CONST_COLORS.get(u.constellation, UiKit.VERMILION).lightened(0.25)  # couleur de faction
		var st := UiKit.panel_style(Color(UI_BG, 0.92), frame, 2, 2)
		st.set_content_margin_all(1)
		box.add_theme_stylebox_override("panel", st)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if UiKit.portrait_texture(u.id) != null:
			box.add_child(UiKit.portrait(u.id, 26))
		else:
			var l := UiKit.label(u.display_name.substr(0, 2), 11)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.custom_minimum_size = Vector2(26, 26)
			box.add_child(l)
		var fx := HBoxContainer.new()
		fx.add_theme_constant_override("separation", 1)
		fx.alignment = BoxContainer.ALIGNMENT_CENTER
		fx.custom_minimum_size = Vector2(28, 10)
		fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# alliés sous le fil (effets dessous), ennemis au-dessus (effets dessus)
		if u.team == 0:
			m.add_child(box)
			m.add_child(fx)
			m.position = Vector2(0, 31)
		else:
			m.add_child(fx)
			m.add_child(box)
			m.position = Vector2(0, -15)
		holder.add_child(m)
		markers[u] = m
		marker_status[u] = fx


func _make_card(u: BattleUnit) -> Control:
	var tactical := not engine.tactics.is_empty()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(UI_BG, 0.78), _col(u)))
	panel.custom_minimum_size.x = 226
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	panel.add_child(h)
	if UiKit.portrait_texture(u.id) != null:
		h.add_child(UiKit.portrait(u.id, 34))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 3)
	v.add_child(head)
	if u.get_trait("boss") != null or not UiKit.CONST_COLORS.has(u.constellation):  # faction : emblème avant le nom
		head.add_child(UiKit.icon("boss", 15, UiKit.VERMILION.lightened(0.3)))
	else:
		head.add_child(UiKit.icon(u.constellation, 16, UiKit.CONST_COLORS[u.constellation].lightened(0.3)))
	head.add_child(UiKit.label(u.display_name, 13))
	if tactical and u.team == 1 and not u.weakness.is_empty():  # faiblesses : constellations qui entament la Ténacité
		head.add_child(UiKit.icon("dmg_taken", 12, UiKit.VERMILION.lightened(0.3)))
		for c in u.weakness:
			head.add_child(UiKit.icon(c, 14, UiKit.CONST_COLORS[c].lightened(0.3)))
	var hp := _bar(u.max_hp(), _col(u).lightened(0.25) if u.team == 0 else UiKit.VERMILION.lightened(0.15), 5)
	v.add_child(hp)
	var c := {"hp": hp, "panel": panel}
	if tactical and u.team == 1 and u.max_toughness > 0.0:
		c["tough"] = _bar(u.max_toughness, UiKit.PAPER, 3)
		v.add_child(c["tough"])
	if engine.ult_cut and u.team == 0 and not u.is_passive(2):  # énergie et ultime hors tour : contre un boss
		c["energy"] = _bar(float(engine.tactics["energy_max"]), UI_ACCENT, 3)
		v.add_child(c["energy"])
		var ult := Button.new()  # ultime : coupe la ligne de temps quand l'énergie est pleine
		ult.custom_minimum_size = Vector2(40, 40)
		ult.icon = UiKit.icon_texture(UiKit.skill_icon_id(u.skill(2)))
		ult.expand_icon = true
		ult.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ult.add_theme_constant_override("icon_max_width", 26)
		ult.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ult.pressed.connect(_on_ult_pressed.bind(u))
		h.add_child(ult)
		c["ult"] = ult
	var info := HFlowContainer.new()  # PV, bouclier, effets et cumuls : icônes + nombres
	info.add_theme_constant_override("h_separation", 6)
	info.add_theme_constant_override("v_separation", 1)
	v.add_child(info)
	c["info"] = info
	cards[u] = c
	return panel


func _bar(maxv: float, col: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = maxv
	bar.show_percentage = false
	bar.custom_minimum_size.y = height
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	bar.add_theme_stylebox_override("fill", fill)
	var empty := StyleBoxFlat.new()
	empty.bg_color = Color(0, 0, 0, 0.45)
	bar.add_theme_stylebox_override("background", empty)
	return bar


func _panel_style(bg: Color, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(4)
	s.set_content_margin_all(6)
	s.border_color = Color(UI_ACCENT, 0.8)  # liseré d'or 1 px (Bible D.A.)
	s.set_border_width_all(1)
	if border.a > 0.0:
		s.border_width_left = 3  # couleur de constellation à gauche
	return s


## Petite icône d'effet avec ses tours restants (fiches, barre d'action).
func _chip(tex: Texture2D, num: int, side := 15.0) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 1)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(side, side)
	h.add_child(t)
	if num >= 0:
		h.add_child(UiKit.label(str(num), 11))
	return h


func _refresh() -> void:
	for u: BattleUnit in cards:
		var c: Dictionary = cards[u]
		c["hp"].max_value = u.max_hp()
		var tw := create_tween()
		tw.tween_property(c["hp"], "value", u.hp, 0.25)
		var info: HFlowContainer = c["info"]
		for ch in info.get_children():
			ch.queue_free()
		if not u.is_alive():
			info.add_child(UiKit.icon("boss", 15, UiKit.DIM))  # hors combat
		else:
			info.add_child(UiKit.amount("hp", "%d/%d" % [int(u.hp), int(u.max_hp())], 11))
			if u.shield_value() > 0.0:
				info.add_child(UiKit.amount("shield", str(int(u.shield_value())), 11, Color("9fc8e8")))
			for e in u.effects:
				if e["id"] != "shield":
					var turns := int(e["turns"])
					info.add_child(_chip(UiKit.status_texture(e["id"]), turns if turns <= 99 else -1))
			for st: String in u.stacks:
				if u.stack(st) > 0:
					info.add_child(UiKit.amount("stack_" + st, str(u.stack(st)), 11, UI_ACCENT))
		(c["panel"] as Control).modulate = Color(1, 1, 1, 1.0 if u.is_alive() else 0.4)
		if c.has("tough"):
			(c["tough"] as ProgressBar).value = u.toughness
			(c["tough"] as ProgressBar).modulate = Color(1, 0.55, 0.45) if u.broken else Color.WHITE
		if c.has("energy"):
			(c["energy"] as ProgressBar).value = u.energy
			var ult: Button = c["ult"]
			var ready := engine.ult_ready(u)
			ult.disabled = not ready
			ult.add_theme_stylebox_override("normal", UiKit.panel_style(Color(UiKit.VERMILION.darkened(0.3), 0.95) if ready else Color(UI_BG, 0.8),
				UI_ACCENT if ready else Color(UI_ACCENT, 0.25), 2 if ready else 1, 20))
		if u.charging > 0:
			info.add_child(UiKit.amount("charge", "1", 12, UiKit.VERMILION.lightened(0.3)))
	for u: BattleUnit in marker_status:
		var fx: HBoxContainer = marker_status[u]
		for ch in fx.get_children():
			ch.queue_free()
		var n := 0
		for e in u.effects:
			if e["id"] != "shield" and n < 3:
				fx.add_child(_chip(UiKit.status_texture(e["id"]), -1, 9))
				n += 1
	for u: BattleUnit in status_rows:
		_refresh_status_row(u)
	if engine.current != null:
		turn_label.text = engine.current.display_name
	if sp_row != null:  # réserve de Sceaux de l'équipe
		for i in sp_row.get_child_count():
			(sp_row.get_child(i) as CanvasItem).modulate = UI_ACCENT if i < engine.sp else Color(UiKit.PAPER, 0.18)


const GOOD_KINDS := ["buff", "aura", "stance"]


## Rangée d'icônes d'effets au-dessus de la tête : bonus d'abord, puis malus ; tours restants en petit.
func _refresh_status_row(u: BattleUnit) -> void:
	var row: Node3D = status_rows[u]
	for c in row.get_children():
		c.queue_free()
	if not u.is_alive():
		return
	var shown: Array[Dictionary] = []
	for e in u.effects:
		if e["id"] != "shield" and UiKit.status_texture(e["id"]) != null:
			shown.append(e)
	var effects_def: Dictionary = GameData.rules()["effects"]
	shown.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (str(effects_def.get(a["id"], {}).get("kind", "")) in GOOD_KINDS) and not (str(effects_def.get(b["id"], {}).get("kind", "")) in GOOD_KINDS))
	shown = shown.slice(0, 6)
	var step := 0.25
	for i in shown.size():
		var e: Dictionary = shown[i]
		var s := Sprite3D.new()
		s.texture = UiKit.status_texture(e["id"])
		s.pixel_size = 0.0034
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.no_depth_test = true
		s.render_priority = 2
		s.position.x = (i - (shown.size() - 1) / 2.0) * step
		row.add_child(s)
		var turns := int(e["turns"])
		if turns <= 99:
			var t := Label3D.new()
			t.text = str(turns)
			t.font_size = 26
			t.outline_size = 8
			t.pixel_size = 0.004
			t.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			t.no_depth_test = true
			t.render_priority = 3
			t.position = Vector3(0, -0.13, 0.01)
			s.add_child(t)


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
	head.add_child(UiKit.icon_button("close", _toggle_info, 40))
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
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	v.add_child(head)
	head.add_child(UiKit.icon(str(u.data.get("class", "boss")) if UiKit.CLASS_NAMES.has(u.data.get("class", "")) else "boss", 18, _col(u).lightened(0.4)))
	head.add_child(UiKit.label(u.display_name, 16, _col(u).lightened(0.4)))
	if not u.is_alive():
		head.add_child(UiKit.icon("boss", 16, UiKit.DIM))
	var stats := HFlowContainer.new()
	stats.add_theme_constant_override("h_separation", 12)
	v.add_child(stats)
	stats.add_child(UiKit.amount("hp", "%d/%d" % [int(u.hp), int(u.max_hp())], 12))
	for k in ["atk", "def", "spd", "cr", "cd", "acc", "res"]:
		stats.add_child(UiKit.amount(k, ("%d %%" if k in ["cr", "cd"] else "%d") % int(u.stat(k)), 12))
	for i in 3:
		var sk := u.skill(i)
		var state := UiKit.bb("passive") if u.is_passive(i) else ("" if u.cooldowns[i] == 0 else "%s %d" % [UiKit.bb("cooldown"), u.cooldowns[i]])
		var tag := "[color=#%s]%s[/color]" % [UiKit.VERMILION.lightened(0.3).to_html(false), "◆"] if i == 2 else "◇"
		v.add_child(UiKit.rich("%s %s  %s" % [tag, sk["name"], state], 13, UiKit.PAPER if not u.is_passive(i) else UiKit.DIM))
		v.add_child(UiKit.rich(UiKit.skill_text(sk), 11, UiKit.DIM, true))
	for e in u.effects:
		var def: Dictionary = GameData.rules()["effects"][e["id"]]
		var turns := int(e["turns"])
		var st := int(e.get("stacks", 1))
		v.add_child(UiKit.rich("%s %s%s  %s" % [UiKit.bb_status(e["id"], 18), "" if turns > 99 else str(turns),
			" ×%d" % st if st > 1 else "", def.get("desc", "")], 12, UiKit.PAPER, true))
	return p


func _clear_actions() -> void:
	_hide_skill_tip()
	for c in action_box.get_children():
		c.queue_free()


func _skill_button(text: String, border: Color, cb: Callable, disabled := false, ultimate := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(210, 66)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD
	var bg := Color(UiKit.VERMILION.darkened(0.45), 0.92) if ultimate else Color(UI_BG, 0.9)
	b.add_theme_stylebox_override("normal", UiKit.panel_style(bg, border, 2 if ultimate else 1, 6))
	var glow := UiKit.panel_style(bg.lightened(0.15), border.lightened(0.3), 3, 6)  # surbrillance à la sélection
	glow.shadow_color = Color(border, 0.55)
	glow.shadow_size = 8
	b.add_theme_stylebox_override("hover", glow)
	b.add_theme_stylebox_override("pressed", glow)
	b.add_theme_stylebox_override("disabled", UiKit.panel_style(Color(UI_BG, 0.7), Color(border, 0.25), 1, 6))
	b.add_theme_color_override("font_color", UiKit.PAPER)
	b.disabled = disabled
	b.pressed.connect(cb)
	b.scale = Vector2(0.85, 0.85)
	b.pivot_offset = b.custom_minimum_size / 2.0
	var tw := b.create_tween()  # les boutons apparaissent avec un petit rebond
	tw.tween_property(b, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return b


## Pastille d'angle d'un bouton (recharge, passif, PV de la cible).
func _corner(b: Control, c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	c.offset_right = -6
	c.offset_top = 4
	b.add_child(c)


## Compétences en symboles (règle UI). Toucher = lancer ; appui long = bulle avec le nom et l'effet.
func _show_actions(actor: BattleUnit) -> void:
	waiting_input = true
	_clear_actions()
	for i in 3:
		var sk := actor.skill(i)
		var passive := actor.is_passive(i)
		var tactical_ult := engine.ult_cut and i == 2 and not passive
		var usable := (engine.ult_ready(actor) if tactical_ult else (not passive and i in engine.usable_skills(actor)))
		var b := _skill_button("", UI_ACCENT if not passive else Color(UI_ACCENT, 0.4), func() -> void: pass, false, i == 2)
		b.custom_minimum_size = Vector2(92, 92)
		b.pivot_offset = b.custom_minimum_size / 2.0
		if not usable:  # aspect grisé, mais l'appui long reste possible pour lire la compétence
			b.add_theme_stylebox_override("normal", UiKit.panel_style(Color(UI_BG, 0.7), Color(UI_ACCENT, 0.25), 1, 6))
		var ic := UiKit.icon(UiKit.skill_icon_id(sk), 50, UiKit.PAPER if usable else Color(UiKit.PAPER, 0.35))
		ic.set_anchors_preset(Control.PRESET_CENTER)
		ic.offset_left = -25
		ic.offset_top = -25
		ic.offset_right = 25
		ic.offset_bottom = 25
		b.add_child(ic)
		if passive:
			_corner(b, UiKit.icon("passive", 16, UiKit.DIM))
		elif tactical_ult:
			_corner(b, UiKit.amount("energie", "%d %%" % int(100.0 * actor.energy / float(engine.tactics["energy_max"])), 12))
		elif actor.cooldowns[i] > 0:
			_corner(b, UiKit.amount("cooldown", str(actor.cooldowns[i]), 12))
		if not engine.tactics.is_empty() and not passive and i < 2:  # économie de Sceaux
			var delta := int(engine.tactics["sp_gain"][i]) - int(engine.tactics["sp_cost"][i])
			if delta != 0:
				var sb := UiKit.amount("sceau", ("+%d" if delta > 0 else "−%d") % absi(delta), 12, UI_ACCENT if delta > 0 else UiKit.VERMILION.lightened(0.35))
				sb.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
				sb.grow_horizontal = Control.GROW_DIRECTION_BEGIN
				sb.grow_vertical = Control.GROW_DIRECTION_BEGIN
				sb.offset_right = -6
				sb.offset_bottom = -4
				b.add_child(sb)
		var held := [false]
		var timer := Timer.new()
		timer.one_shot = true
		timer.wait_time = 0.4
		b.add_child(timer)
		b.button_down.connect(func() -> void:
			held[0] = false
			timer.start())
		timer.timeout.connect(func() -> void:
			held[0] = true
			_show_skill_tip(actor, i))
		b.button_up.connect(func() -> void:
			timer.stop()
			_hide_skill_tip())
		b.pressed.connect(func() -> void:
			if usable and not held[0]:
				if tactical_ult:
					_on_ult_pressed(actor)
				else:
					_on_skill_chosen(actor, i))
		action_box.add_child(b)


var skill_tip: PanelContainer


## Bulle d'une compétence (appui long) : symbole, nom, recharge et description.
func _show_skill_tip(actor: BattleUnit, i: int) -> void:
	_hide_skill_tip()
	var sk := actor.skill(i)
	skill_tip = PanelContainer.new()
	skill_tip.add_theme_stylebox_override("panel", UiKit.panel_style(Color(UI_BG, 0.96),
		UiKit.VERMILION.lightened(0.2) if i == 2 else UI_ACCENT, 2, 6))
	skill_tip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	skill_tip.offset_left = -280
	skill_tip.offset_right = 280
	skill_tip.offset_bottom = -116
	skill_tip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	skill_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	skill_tip.add_child(v)
	var cd := ""
	if actor.is_passive(i):
		cd = UiKit.bb("passive", 18)
	elif sk.has("cd"):
		cd = "%s %d" % [UiKit.bb("cooldown", 18), int(sk["cd"])]
	v.add_child(UiKit.rich("%s  [b]%s[/b]   %s" % [UiKit.bb(UiKit.skill_icon_id(sk), 22, UI_ACCENT), sk["name"], cd], 18, UI_ACCENT))
	v.add_child(UiKit.rich(UiKit.skill_text(sk), 14, UiKit.PAPER, true))
	ui_root.add_child(skill_tip)


func _hide_skill_tip() -> void:
	if skill_tip != null:
		skill_tip.queue_free()
		skill_tip = null


func _on_skill_chosen(actor: BattleUnit, idx: int) -> void:
	if not engine.needs_target(actor, idx):
		waiting_input = false
		await _perform(actor, idx, null)
		_advance()
		return
	_clear_actions()
	for t in engine.valid_targets(actor, idx):
		var b := _skill_button(t.display_name, _col(t), func() -> void:
			waiting_input = false
			await _perform(actor, idx, t)
			_advance())
		b.custom_minimum_size = Vector2(170, 64)
		_corner(b, UiKit.amount("hp", "%d %%" % int(t.hp_ratio() * 100), 12))
		action_box.add_child(b)
	var back := UiKit.icon_button("back", _show_actions.bind(actor), 64)
	action_box.add_child(back)


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
	var in_prologue: bool = Session.battle.get("mode", "") == "prologue"
	if in_prologue and engine.winner == 0 and not Session.smoke_test:
		var lv := int(Session.battle["level"])
		var prw := Session.profile.win_prologue(lv)
		Session.grant_notes.append_array(prw["grants"])
		Session.save()
		var pl: Array = [["%s" % Prologue.level(lv)["name"], true]]
		for k: String in prw["currencies"]:
			pl.append(["%s +%s" % [UiKit.bb(k, 22 if k == "eclat_de_voeu" else 20, UI_ACCENT if k == "eclat_de_voeu" else UiKit.PAPER),
				UiKit.thousands(int(prw["currencies"][k]))], k == "eclat_de_voeu"])
		if prw["done"]:
			pl.append(["%s  La Tour s'ouvre !" % UiKit.bb("floor", 22, UI_ACCENT), true])
		_reward_lines(v, pl)
	if in_loot and engine.winner != 0 and not Session.smoke_test:
		Session.profile.refund_energy(int(Session.battle.get("energy", 0)))
		Session.save()
		_reward_lines(v, [["%s +%d" % [UiKit.bb("energie", 20), int(Session.battle.get("energy", 0))], false]])
	if in_loot and engine.winner == 0 and not Session.smoke_test:
		var lrw := Session.profile.win_loot(Session.battle["boss"], int(Session.battle["diff"]), Session.rng)
		Session.save()
		var ls: Array = [["%s +%s" % [UiKit.bb("pieces", 20), UiKit.thousands(lrw["currencies"]["pieces"])], false]]
		for r: Dictionary in lrw["relics"]:
			ls.append([UiKit.relic_title(r), false])
		if lrw["pity_used"] != "":
			ls.append(["%s %s ✓" % [UiKit.bb("relique", 20, UI_ACCENT), UiKit.bb("set_" + str(lrw["pity_used"]), 20, UI_ACCENT)], true])
		if lrw.has("unlocked"):
			ls.append(["▲ " + str(LootBoss.difficulty(int(lrw["unlocked"]))["name"]), true])
		_reward_lines(v, ls)
	if in_tower and engine.winner != 0 and not Session.smoke_test and GameData.progression()["energy"]["refund_on_defeat"]:
		Session.profile.refund_energy(int(Session.battle.get("energy", 0)))
		Session.save()
		if int(Session.battle.get("energy", 0)) > 0:
			_reward_lines(v, [["%s +%d" % [UiKit.bb("energie", 20), int(Session.battle["energy"])], false]])
	if in_tower and engine.winner == 0 and not Session.smoke_test:
		var rw := Session.profile.win_floor(floor_n, Session.rng)
		Session.save()
		var lines: Array = [["%s %d%s" % [UiKit.bb("floor", 22, UI_ACCENT), floor_n, "  ★" if rw["first_clear"] else ""], rw["first_clear"]]]
		lines.append(["%s +%s" % [UiKit.bb("pieces", 20), UiKit.thousands(rw["currencies"]["pieces"])], false])
		if rw["currencies"].has("eclat_de_voeu"):
			lines.append(["%s +%d" % [UiKit.bb("eclat_de_voeu", 22, UI_ACCENT), rw["currencies"]["eclat_de_voeu"]], true])
		for r: Dictionary in rw["relics"]:
			lines.append([UiKit.relic_title(r), false])
		if not engine.tactics.is_empty():  # étoiles : victoire, aucun K.O., victoire rapide
			var no_ko := engine.units.all(func(x: BattleUnit) -> bool: return x.team != 0 or x.is_alive())
			var mask := 1 | (2 if no_ko else 0) | (4 if engine.team_actions <= int(engine.tactics["star_actions"]) else 0)
			var st := Session.profile.record_stars(floor_n, mask)
			Session.save()
			var parts: Array[String] = []
			for k in 3:
				var got := (mask >> k) & 1 == 1
				parts.append("%s [color=#%s]★[/color]" % [UiKit.bb(["titan", "hp", "speed"][k], 18, UI_ACCENT if got else UiKit.DIM),
					(UI_ACCENT if got else UiKit.DIM).to_html(false)])
			lines.append(["   ".join(parts) + ("   %s +%d" % [UiKit.bb("eclat_de_voeu", 18, UI_ACCENT), int(st["currencies"].get("eclat_de_voeu", 0))] if int(st["new"]) > 0 else ""), int(st["new"]) > 0])
		_reward_lines(v, lines)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	if in_tower and engine.winner == 0 and Session.profile.can_enter_floor(floor_n + 1) and floor_n < Tower.floor_count():
		var nb := UiKit.button("%d  ›" % (floor_n + 1), func() -> void: Session.start_tower_floor(floor_n + 1), Vector2(150, 52))
		nb.icon = UiKit.icon_texture("floor")
		nb.add_theme_stylebox_override("normal", UiKit.panel_style(Color("4a3a12"), UI_ACCENT, 2, 10))  # action principale
		nb.add_theme_color_override("font_color", Color("fff1c4"))
		nb.disabled = Session.profile.energy < Session.profile.floor_cost(floor_n + 1)
		row.add_child(nb)
	if in_prologue:
		var cont := UiKit.button("Continuer  ›" if engine.winner == 0 else "Réessayer", func() -> void:
			if engine.winner == 0:
				_back_to_menu()
			else:
				Session.start_prologue(int(Session.battle["level"])), Vector2(170, 52))
		cont.add_theme_stylebox_override("normal", UiKit.panel_style(Color("4a3a12"), UI_ACCENT, 2, 10))  # action principale
		cont.add_theme_color_override("font_color", Color("fff1c4"))
		row.add_child(cont)
	if in_loot:
		var lb := UiKit.icon_button("auto", func() -> void: Session.start_loot(Session.battle["boss"], int(Session.battle["diff"])), 52)
		lb.disabled = Session.profile.energy < int(LootBoss.cfg()["energy_cost"])
		row.add_child(lb)
	if in_tower:
		var rb := UiKit.icon_button("auto", func() -> void: Session.start_tower_floor(floor_n), 52)
		rb.disabled = Session.profile.energy < Session.profile.floor_cost(floor_n)
		row.add_child(rb)
	row.add_child(UiKit.icon_button("stats", _toggle_battle_stats, 52))  # bilan du combat
	row.add_child(UiKit.icon_button("back", _back_to_menu, 52))
	result_panel.add_child(v)
	result_panel.visible = true
	result_panel.scale = Vector2(0.7, 0.7)
	result_panel.pivot_offset = result_panel.size / 2.0
	create_tween().tween_property(result_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for u in engine.units:
		if u.is_alive() and u.team == engine.winner:
			_play_anim(u, "victory")
	if engine.winner == 0:  # la caméra se rapproche des vainqueurs
		_cam_to(Vector3(0, 2.5, 7.2), Vector3(0, 1.2, 1.6), 1.2)
	finished.emit(engine.winner)
	if "--recap" in OS.get_cmdline_user_args():  # captures : ouvre le bilan au lieu de quitter
		_toggle_battle_stats()
		return
	if Session.smoke_test:
		print("Test de fumée OK : combat terminé (vainqueur %d, %d actions)" % [engine.winner, engine.total_actions])
		get_tree().quit(0)


## Récompenses révélées une à une (retour gratifiant) ; les plus importantes en doré. lines : [[bbcode, clé]].
func _reward_lines(v: VBoxContainer, lines: Array) -> void:
	for k in lines.size():
		var key: bool = lines[k][1]
		var l := UiKit.rich("[center]%s[/center]" % lines[k][0], 18 if key else 15, UI_ACCENT if key else UiKit.PAPER)
		l.custom_minimum_size.x = 420
		l.modulate.a = 0.0
		v.add_child(l)
		var tw := l.create_tween()
		tw.tween_interval(0.35 + 0.22 * k)
		tw.tween_property(l, "modulate:a", 1.0, 0.2)


var stats_panel: PanelContainer


## Bilan du combat : part des dégâts infligés dans l'équipe (%), dégâts subis, protection donnée
## (boucliers posés) et soins. Une grille par équipe, en icônes et nombres.
func _toggle_battle_stats() -> void:
	if stats_panel != null:
		stats_panel.queue_free()
		stats_panel = null
		return
	stats_panel = PanelContainer.new()
	stats_panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(UI_BG, 0.97), UI_ACCENT, 2, 8))
	stats_panel.set_anchors_preset(Control.PRESET_CENTER)
	stats_panel.offset_left = -400
	stats_panel.offset_right = 400
	stats_panel.offset_top = -200
	stats_panel.offset_bottom = 200
	ui_root.add_child(stats_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	stats_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(UiKit.icon("stats", 26, UI_ACCENT))
	var t := UiKit.label("Bilan", 22, UI_ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UiKit.icon_button("close", _toggle_battle_stats, 40))
	for team in 2:
		var members := engine.units.filter(func(x: BattleUnit) -> bool: return x.team == team)
		var total := 0.0
		for u: BattleUnit in members:
			total += float(engine.stats[u]["dealt"])
		var line := ColorRect.new()
		line.color = Color(UiKit.PAPER if team == 0 else UiKit.VERMILION, 0.6)
		line.custom_minimum_size.y = 2
		v.add_child(line)
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 6)
		v.add_child(grid)
		for id in ["", "", "atk", "dmg_taken", "shield", "support"]:  # en-têtes en icônes
			grid.add_child(Control.new() if id == "" else UiKit.icon(id, 20, UiKit.DIM))
		for u: BattleUnit in members:
			var st: Dictionary = engine.stats[u]
			grid.add_child(UiKit.portrait(u.id, 34) if UiKit.portrait_texture(u.id) != null else Control.new())
			var name_l := UiKit.label(u.display_name, 14, _col(u).lightened(0.35))
			name_l.custom_minimum_size.x = 170
			name_l.clip_text = true
			grid.add_child(name_l)
			var pct := 100.0 * float(st["dealt"]) / total if total > 0.0 else 0.0
			var dealt := HBoxContainer.new()
			dealt.add_theme_constant_override("separation", 6)
			var bar := ProgressBar.new()
			bar.max_value = 100.0
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(130, 10)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var fill := StyleBoxFlat.new()
			fill.bg_color = _col(u).lightened(0.2)
			bar.add_theme_stylebox_override("fill", fill)
			var empty := StyleBoxFlat.new()
			empty.bg_color = Color(0, 0, 0, 0.4)
			bar.add_theme_stylebox_override("background", empty)
			dealt.add_child(bar)
			dealt.add_child(UiKit.label("%d %%" % roundi(pct), 14))
			grid.add_child(dealt)
			bar.create_tween().tween_property(bar, "value", pct, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			for k in ["taken", "shielded", "healed"]:
				grid.add_child(UiKit.label(UiKit.thousands(roundi(float(st[k]))), 14))


func _back_to_menu() -> void:
	Engine.time_scale = 1.0
	var back := {"tower": "res://scenes/tower.tscn", "loot": "res://scenes/loot.tscn", "prologue": "res://scenes/prologue.tscn"}
	get_tree().change_scene_to_file(back.get(Session.battle.get("mode", ""), "res://scenes/main.tscn"))
