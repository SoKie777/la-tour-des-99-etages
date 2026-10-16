class_name CharacterModel
extends Node3D
## Personnage 3D animé (méthode de Coup d'État) :
## - modèle MPFB res://assets/models/<id>.fbx s'il existe, sinon le mannequin Y Bot teinté ;
## - animations Mixamo de res://assets/mixamo/anims/, reciblées à l'import (BoneMap humanoïde).

const BASE_SCENE := "res://assets/mixamo/ybot_idle.fbx"
const ANIM_DIR := "res://assets/mixamo/anims/"
const LOOPS := ["idle", "idle_caster"]
## Action du combat -> animation Mixamo (par défaut)
const MAP := {
	"idle": "idle", "attack": "cross", "skill": "punch_combo", "ultimate": "hurricane_kick",
	"hit": "hit", "crit_hit": "hit_big", "death": "ko", "victory": "victory",
}
## Jeu d'animations de chaque personnage, selon son kit (remplace MAP action par action)
const CHAR_MAP := {
	"eirikr": {"attack": "hook", "ultimate": "flying_kick"},
	"ymir": {"idle": "idle_caster", "attack": "cast_attack", "ultimate": "cast_area"},
	"nidhogg": {"idle": "idle_caster", "attack": "cast_attack", "ultimate": "heal"},
	"don_diego": {"attack": "cross", "skill": "taunt", "ultimate": "roar"},
	"general_metal": {"attack": "punch_combo", "skill": "spin_back_kick", "ultimate": "hurricane_kick"},
	"espion_lumiere": {"attack": "kick_high", "ultimate": "cast_area"},
	"moussa": {"attack": "uppercut", "ultimate": "jump_attack"},
	"issa": {"idle": "idle_caster", "attack": "cast_attack", "ultimate": "cast_buff"},
	"mohamed": {"attack": "cast_attack", "ultimate": "flip_kick"},
	# roster v2
	"montana": {"idle": "idle_caster", "attack": "hook", "skill": "cast_area", "ultimate": "cast_attack"},
	"mikhaila": {"idle": "idle_caster", "attack": "cast_attack", "skill": "cast_buff", "ultimate": "heal"},
	"ghost": {"attack": "punch_combo", "ultimate": "hurricane_kick"},
	"nyssa": {"attack": "hook", "ultimate": "flip_kick"},
	"selene": {"attack": "elbow", "ultimate": "block"},
	"adrian": {"attack": "punch_combo", "ultimate": "jump_attack"},
	"mello": {"attack": "cross", "ultimate": "flying_kick"},
	"tarkhan": {"attack": "punch_combo", "ultimate": "spin_back_kick"},
	"yass": {"idle": "idle_caster", "attack": "cast_attack", "skill": "cast_attack", "ultimate": "cast_area"},
	"saraya": {"idle": "idle_caster", "attack": "cast_attack", "skill": "heal", "ultimate": "cast_area"},
	"noor_el": {"idle": "idle_caster", "attack": "cast_attack", "skill": "cast_area", "ultimate": "cast_buff"},
	"jo_prince": {"attack": "kick_high", "skill": "elbow", "ultimate": "flip_kick"},
	"ezra": {"attack": "elbow", "skill": "kick_high", "ultimate": "flying_kick"},
	"flint": {"idle": "idle_caster", "attack": "cast_attack", "skill": "heal", "ultimate": "cast_buff"},
	"don_selah": {"attack": "punch_combo", "skill": "roar", "ultimate": "jump_attack"},
	# boss
	"promethee": {"attack": "punch_combo", "skill": "cast_attack", "ultimate": "cast_area"},
	"chronophage": {"idle": "idle_caster", "attack": "cast_attack", "skill": "cast_area", "ultimate": "cast_buff"},
	"wyrm": {"attack": "punch_combo", "skill": "hurricane_kick", "ultimate": "roar"},
	"serpent": {"idle": "idle_caster", "attack": "kick_high", "skill": "heal", "ultimate": "cast_area"},
	"geode": {"idle": "idle_caster", "attack": "cast_attack", "skill": "cast_area", "ultimate": "cast_buff"},
}
const HOLD_AT_END := ["ko"]
## Vêtements MPFB (peints en couleurs de sommets, sans texture) : mots-clés des noms d'objets.
const TOON_SHADER := preload("res://assets/materials/shaders/toon_ukiyoe.gdshader")
const HAIR_SHADER := preload("res://assets/materials/shaders/toon_ukiyoe_hair.gdshader")  # cartes double face
const HAIR_WORDS := ["hair", "short", "afro", "bob", "braid", "long", "ponytail", "locs", "strand"]
const INK := Color("332c29")  # contours (Bible D.A.)
const CLOTH_WORDS := ["suit", "shoes", "robe", "ninja", "tunic", "jacket", "pants", "boots", "dress", "uniform", "coveralls"]

static var _lib: AnimationLibrary

var model: Node3D
var skel: Skeleton3D
var ap: AnimationPlayer
var meshes: Array[MeshInstance3D] = []
var dead := false
var anims: Dictionary = MAP


static func _build_library() -> void:
	_lib = AnimationLibrary.new()
	# list_directory voit aussi les ressources importées d'un APK (où les .fbx n'existent plus)
	for f in ResourceLoader.list_directory(ANIM_DIR):
		if not f.ends_with(".fbx"):
			continue
		var n := f.get_basename()
		var inst := (load(ANIM_DIR + f) as PackedScene).instantiate()
		var src_ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
		if src_ap != null and src_ap.has_animation("mixamo_com"):
			var a: Animation = src_ap.get_animation("mixamo_com").duplicate(true)
			_strip_root_motion(a)
			a.loop_mode = Animation.LOOP_LINEAR if n in LOOPS else Animation.LOOP_NONE
			_lib.add_animation(n, a)
		inst.free()
	if _lib.get_animation_list().is_empty():
		push_error("CharacterModel : aucune animation dans " + ANIM_DIR)


## Le personnage reste à sa place : on fige les hanches en X/Z.
static func _strip_root_motion(a: Animation) -> void:
	for i in a.get_track_count():
		if a.track_get_type(i) != Animation.TYPE_POSITION_3D or not str(a.track_get_path(i)).ends_with(":Hips"):
			continue
		if a.track_get_key_count(i) == 0:
			continue
		var first: Vector3 = a.track_get_key_value(i, 0)
		for k in a.track_get_key_count(i):
			var v: Vector3 = a.track_get_key_value(i, k)
			v.x = first.x
			v.z = first.z
			a.track_set_key_value(i, k, v)


static func available() -> bool:
	return ResourceLoader.exists(BASE_SCENE)


## Modèle 3D d'un personnage ou d'un boss : clé « model » de ses données (modèle provisoire), sinon son id.
static func model_id(char_id: String) -> String:
	if GameData.characters().has(char_id):
		return str(GameData.character(char_id).get("model", char_id))
	if GameData.bosses()["bosses"].has(char_id):
		return str(GameData.boss(char_id).get("model", char_id))
	return char_id


func setup(char_id: String, tint: Color, height_m: float = 1.75) -> void:
	anims = MAP.merged(CHAR_MAP.get(char_id, {}), true)
	var custom := "res://assets/models/%s.fbx" % model_id(char_id)
	var is_custom := ResourceLoader.exists(custom)
	model = (load(custom if is_custom else BASE_SCENE) as PackedScene).instantiate()
	add_child(model)
	skel = model.find_child("Skeleton3D", true, false)
	ap = model.find_child("AnimationPlayer", true, false)
	if ap == null:
		# les pistes visent "Skeleton3D:os" : le lecteur doit être à côté du squelette
		ap = AnimationPlayer.new()
		skel.get_parent().add_child(ap)
	if _lib == null:
		_build_library()
	ap.add_animation_library("fx", _lib)
	ap.playback_default_blend_time = 0.12
	ap.animation_finished.connect(_on_finished)
	for mi in skel.get_children():
		if mi is MeshInstance3D:
			meshes.append(mi)
			if is_custom:
				_toonify(mi)
			else:
				var surface := str(mi.name).ends_with("Surface")
				mi.material_override = _toon(tint if surface else tint.darkened(0.6))
	_fit_height(height_m)
	play("idle")


func play(action: String) -> void:
	var anim: String = anims.get(action, action)
	if dead or _lib == null or not _lib.has_animation(anim):
		return
	if frozen and not anim in HOLD_AT_END:
		return
	if anim in HOLD_AT_END:
		dead = true
		frozen = false
		ap.speed_scale = 1.0
	ap.play("fx/" + anim)


var status_mat: StandardMaterial3D = null  # teinte durable d'un état (Gel, Poison…)
var frozen := false  # statue de glace : seules la mort et la sortie du Gel changent la pose


## État visible : teinte durable (alpha 0 = aucune) et vitesse d'animation
## (0 = figé comme une statue de glace, < 1 = ralenti par le Sommeil).
func set_status_look(tint: Color, anim_speed: float) -> void:
	frozen = anim_speed == 0.0
	if ap != null:
		ap.speed_scale = anim_speed
	if tint.a <= 0.0:
		status_mat = null
	else:
		if status_mat == null:
			status_mat = StandardMaterial3D.new()
			status_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			status_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			status_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		status_mat.albedo_color = tint
	for mi in meshes:
		mi.material_overlay = status_mat


## Éclat de couleur sur tout le personnage (coup reçu, soin) : un voile additif qui s'efface.
func flash(color: Color, duration := 0.22) -> void:
	if meshes.is_empty():
		return
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color, color.a * 0.6)  # l'alpha de la couleur règle l'intensité
	for mi in meshes:
		mi.material_overlay = m
	var tw := create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, duration)
	tw.tween_callback(func() -> void:
		for mi in meshes:
			if mi.material_overlay == m:
				mi.material_overlay = status_mat)  # retour à la teinte d'état (ou rien)


func _on_finished(anim_name: StringName) -> void:
	if not dead and not str(anim_name).trim_prefix("fx/") in LOOPS:
		ap.play("fx/" + anims["idle"])


## Matériau toon de la Bible D.A. (assets/materials/shaders/toon_ukiyoe.gdshader) : ombre bleu minéral,
## liseré d'or ; contour couleur encre en seconde passe.
static func ukiyoe_material(c: Color, tex: Texture2D = null, vertex_color := false, scissor := 0.0,
		outline := true, hair := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HAIR_SHADER if hair else TOON_SHADER
	if hair:
		m.set_shader_parameter("band_strength", 0.9)  # reflet net des cheveux
	m.set_shader_parameter("albedo_color", c)
	m.set_shader_parameter("use_texture", tex != null)
	if tex != null:
		m.set_shader_parameter("albedo_texture", tex)
	m.set_shader_parameter("use_vertex_color", vertex_color)
	m.set_shader_parameter("alpha_scissor", scissor)
	if outline:
		var o := StandardMaterial3D.new()
		o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		o.albedo_color = INK
		o.cull_mode = BaseMaterial3D.CULL_FRONT
		o.grow = true
		o.grow_amount = 0.008
		m.next_pass = o
	return m


func _toon(c: Color) -> ShaderMaterial:
	return ukiyoe_material(c, null, false, 0.0, false)


## Garde les textures MPFB avec le rendu toon de la Bible ; vêtements en aplats (couleurs de sommets).
## Yeux et surfaces double face (mèches) gardent un matériau standard en cel-shading.
func _toonify(mi: MeshInstance3D) -> void:
	for i in mi.mesh.get_surface_count():
		var src := mi.get_active_material(i)
		var std: StandardMaterial3D = src if src is StandardMaterial3D else null
		var name_l := str(mi.name).to_lower()
		var arrays := mi.mesh.surface_get_arrays(i)
		var has_col: bool = arrays[Mesh.ARRAY_COLOR] != null and (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0
		var is_cloth: bool = CLOTH_WORDS.any(func(w: String) -> bool: return w in name_l)
		var scissor := 0.4 if ("brow" in name_l or (has_col and not is_cloth)) else 0.0
		# pas de contour sur les yeux, les sourcils et les mèches générées (trop fines : le contour les noircirait)
		var outline := not ("eye" in name_l or "brow" in name_l or "locs" in name_l)
		var is_hair: bool = HAIR_WORDS.any(func(w: String) -> bool: return w in name_l) and not "eye" in name_l
		var keep_std := "eye" in name_l or (not is_hair and std != null and (std.cull_mode == BaseMaterial3D.CULL_DISABLED
			or std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA))
		if is_hair:  # cheveux : shader toon double face, découpe nette et reflet en bande
			var htex: Texture2D = std.albedo_texture if std != null and not has_col else null
			var hcol := Color.WHITE if (has_col or std == null) else std.albedo_color
			mi.set_surface_override_material(i, ukiyoe_material(hcol, htex, has_col, maxf(scissor, 0.35), false, true))
			continue
		if not keep_std:
			var tex: Texture2D = null if (std == null or (has_col and is_cloth)) else std.albedo_texture
			var col := Color.WHITE if (has_col or std == null) else std.albedo_color
			mi.set_surface_override_material(i, ukiyoe_material(col, tex, has_col, scissor, outline))
			continue
		var m: StandardMaterial3D = std.duplicate() if std != null else StandardMaterial3D.new()
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_TOON
		m.roughness = 0.7
		m.rim_enabled = true
		m.rim = 0.3
		if has_col:
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			m.albedo_color = Color.WHITE
			if is_cloth:
				m.albedo_texture = null
		if scissor > 0.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = scissor
		mi.set_surface_override_material(i, m)


## Met le modèle à la taille voulue (mètres), d'après la boîte englobante de ses maillages.
func _fit_height(target_m: float) -> void:
	var lo := INF
	var hi := -INF
	for mi in meshes:
		var bb: AABB = mi.transform * mi.get_aabb()
		lo = minf(lo, bb.position.y)
		hi = maxf(hi, bb.end.y)
	if hi > lo:
		model.scale = Vector3.ONE * (target_m / (hi - lo)) * model.scale.x
	_set_param("figure_height", target_m)


## Règle un paramètre de tous les matériaux toon du modèle.
func _set_param(param: String, value: Variant) -> void:
	for mi in meshes:
		if mi.material_override is ShaderMaterial:  # mannequin teinté
			(mi.material_override as ShaderMaterial).set_shader_parameter(param, value)
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i)
			if m is ShaderMaterial:
				(m as ShaderMaterial).set_shader_parameter(param, value)


## Liseré (rim light) à la couleur de l'arène.
func set_rim(c: Color) -> void:
	_set_param("arena_rim_color", c)
