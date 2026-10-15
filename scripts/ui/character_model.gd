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
}
const HOLD_AT_END := ["ko"]

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


func setup(char_id: String, tint: Color, height_m: float = 1.75) -> void:
	anims = MAP.merged(CHAR_MAP.get(char_id, {}), true)
	var custom := "res://assets/models/%s.fbx" % char_id
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
	if anim in HOLD_AT_END:
		dead = true
	ap.play("fx/" + anim)


func _on_finished(anim_name: StringName) -> void:
	if not dead and not str(anim_name).trim_prefix("fx/") in LOOPS:
		ap.play("fx/" + anims["idle"])


func _toon(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.roughness = 0.7
	m.rim_enabled = true
	m.rim = 0.3
	return m


## Garde les textures MPFB, rendu cel-shading + contour noir ; vêtements en aplats (couleurs de sommets).
func _toonify(mi: MeshInstance3D) -> void:
	for i in mi.mesh.get_surface_count():
		var src := mi.get_active_material(i)
		var m: StandardMaterial3D = src.duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_TOON
		m.roughness = 0.7
		m.rim_enabled = true
		m.rim = 0.3
		var name_l := str(mi.name).to_lower()
		var arrays := mi.mesh.surface_get_arrays(i)
		var has_col: bool = arrays[Mesh.ARRAY_COLOR] != null and (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0
		var is_cloth: bool = "suit" in name_l or "shoes" in name_l
		if has_col:
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			m.albedo_color = Color.WHITE
			if is_cloth:
				m.albedo_texture = null
		if "brow" in name_l or (has_col and not is_cloth):
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.4
		# pas de contour sur les yeux, les sourcils et les mèches générées (trop fines : le contour les noircirait)
		if not ("eye" in name_l or "brow" in name_l or "locs" in name_l):
			var o := StandardMaterial3D.new()
			o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			o.albedo_color = Color(0.02, 0.015, 0.015)
			o.cull_mode = BaseMaterial3D.CULL_FRONT
			o.grow = true
			o.grow_amount = 0.008
			m.next_pass = o
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
