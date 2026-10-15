class_name BattleEngine
extends RefCounted
## Moteur de combat à barre d'action (3 contre 3), sans aucune dépendance à l'affichage.
## La scène de combat et les simulations l'utilisent de la même façon :
##   var actor := engine.next_turn()
##   if not engine.can_act(actor): engine.skip_turn(actor)
##   else: engine.use_skill(actor, skill_index, target)
##
## Les compétences sont décrites dans data/characters.json (voir docs/KITS.md pour le vocabulaire) :
## coups (hits) multi-stats et répétés, effets par coup (on_hit), effets durables (rules.json) et
## actions immédiates (PA, purge, vol de buffs, soin, marques, résurrection…), bonus de dégâts,
## prix (self_cost), auras tant que la compétence est en recharge (while_cooldown).

signal battle_event(event: Dictionary)

const ONGOING := -1
const DRAW := 2
## Actions immédiates utilisables dans les listes d'effets (les autres ids sont des effets durables).
const ACTIONS := ["ap_down", "ap_up", "strip_buffs", "steal_buff", "cleanse", "heal", "stack", "cd_reduce"]

var rules: Dictionary
var units: Array[BattleUnit] = []
var rng := RandomNumberGenerator.new()
var winner := ONGOING
var current: BattleUnit = null
var total_actions := 0
var log_lines: Array[String] = []
var keep_log := false
## Dernière S2/S3 active utilisée (copiable par Nyssa) : {"unit", "index"}
var last_skill: Dictionary = {}
var _in_reaction := false  # contre-attaques et frappes de clones : pas de réaction en chaîne
## Bilan du combat par unité : {"dealt", "taken", "shielded" (boucliers donnés), "healed"}
var stats := {}


## team_a / team_b : listes d'ids de personnages, ou de BattleUnit déjà construits (reliques).
func _init(team_a: Array, team_b: Array, seed_value: int = 0) -> void:
	rules = GameData.rules()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	for t in [[team_a, 0], [team_b, 1]]:
		var members: Array = t[0]
		for i in members.size():
			var m: Variant = members[i]
			var u: BattleUnit = m if m is BattleUnit else BattleUnit.new(GameData.character(m), t[1], i)
			u.team = t[1]
			u.slot = i
			units.append(u)
	for u in units:
		stats[u] = {"dealt": 0.0, "taken": 0.0, "shielded": 0.0, "healed": 0.0}
	for u in units:
		if u.set_specials.has("start_immunity_1"):
			u.effects.append(_make_effect("immunity", 1, 0.0, u, true))
		if u.get_trait("start_ap") != null:
			u.ap = float(u.get_trait("start_ap")) / 100.0
		if u.get_trait("enemy_spd_aura") != null:
			for foe in enemies_of(u):
				foe.effects.append(_make_effect("aura_chill", 9999, float(u.get_trait("enemy_spd_aura")), u, false))


# --- Requêtes ---------------------------------------------------------------

func alive_units() -> Array[BattleUnit]:
	return units.filter(func(u: BattleUnit) -> bool: return u.is_alive())


func team_alive(team: int) -> Array[BattleUnit]:
	return units.filter(func(u: BattleUnit) -> bool: return u.is_alive() and u.team == team)


func allies_of(u: BattleUnit) -> Array[BattleUnit]:
	return team_alive(u.team)


func enemies_of(u: BattleUnit) -> Array[BattleUnit]:
	return team_alive(1 - u.team)


func can_act(u: BattleUnit) -> bool:
	return u.is_alive() and not u.is_skipping()


func usable_skills(u: BattleUnit) -> Array[int]:
	var out: Array[int] = []
	for i in 3:
		if u.is_passive(i) or u.cooldowns[i] > 0:
			continue
		if i == 2 and u.has_effect("silence"):
			continue
		out.append(i)
	return out


func valid_targets(u: BattleUnit, skill_idx: int) -> Array[BattleUnit]:
	var kind: String = u.skill(skill_idx).get("target", "enemy")
	match kind:
		"enemy":
			var foes := enemies_of(u)
			var taunters := foes.filter(func(f: BattleUnit) -> bool: return f.has_effect("taunt"))
			return taunters if not taunters.is_empty() else foes
		"ally":
			return allies_of(u)
		"other_ally":
			return allies_of(u).filter(func(a: BattleUnit) -> bool: return a != u)
	return []


func needs_target(u: BattleUnit, skill_idx: int) -> bool:
	return u.skill(skill_idx).get("target", "enemy") in ["enemy", "ally", "other_ally"]


func dominates(constellation_a: String, constellation_b: String) -> bool:
	return rules["triangle"]["beats"].get(constellation_a, "") == constellation_b


func crit_chance(att: BattleUnit, tgt: BattleUnit) -> float:
	var cr := att.stat("cr")
	if dominates(att.constellation, tgt.constellation):
		cr += float(rules["triangle"]["dominant_crit_bonus"])
	return minf(cr, float(rules["crit_cap"]))


func effect_chance(caster: BattleUnit, tgt: BattleUnit, base_chance: float) -> float:
	var acc := caster.stat("acc")
	if caster.has_passive("sage_reading") and tgt.has_buff():
		acc += 20.0
	var c := base_chance + acc - tgt.stat("res")
	return clampf(c, float(rules["effect_chance_min"]), float(rules["effect_chance_max"]))


## Dégâts d'un coup, avant application. crit et variance passés explicitement pour les tests.
func compute_damage(att: BattleUnit, tgt: BattleUnit, raw: float, opts: Dictionary, is_crit: bool, variance: float) -> float:
	var def_c := float(rules["def_constant"])
	var ignore := minf(1.0, float(opts.get("ignore_def", 0.0)) + float(att.get_trait("ignore_def", 0.0)) / 100.0)
	var def_eff := tgt.stat("def") * (1.0 - ignore)
	var dmg := raw * def_c / (def_c + def_eff)
	if is_crit:
		dmg *= 1.0 + att.stat("cd") / 100.0
	dmg *= variance
	if dominates(tgt.constellation, att.constellation):
		dmg *= float(rules["triangle"]["dominated_damage_mult"])
	if att.has_passive("fury"):
		dmg *= 1.0 + 0.08 * att.stack("fury")
	var punish: Variant = att.get_trait("punish")
	if punish != null and not dominates(tgt.constellation, att.constellation):
		dmg *= 1.0 + float(punish.get("dmg_taken", 0.0)) / 100.0
	if att.flags.has("dmg_bonus_pct"):  # phase de boss
		dmg *= 1.0 + float(att.flags["dmg_bonus_pct"]) / 100.0
	if opts.has("low_hp_bonus") and tgt.hp_ratio() < 0.5:
		dmg *= 1.0 + float(opts["low_hp_bonus"])
	return dmg * _taken_mult(tgt)


## Multiplicateur de dégâts subis (réductions passives, postures, auras, Vulnérabilité, statuts).
func _taken_mult(tgt: BattleUnit) -> float:
	var m := 1.0 - float(tgt.get_trait("damage_reduction", 0.0)) / 100.0
	for e in tgt.effects:
		var d: Dictionary = rules["effects"][e["id"]]
		if d.has("dmg_taken_from_value"):
			m *= 1.0 + float(d["dmg_taken_from_value"]) * float(e["value"]) / 100.0
		if d.has("dmg_taken_per_stack"):
			m *= 1.0 + float(d["dmg_taken_per_stack"]) * int(e.get("stacks", 1)) / 100.0
		if d.has("dmg_taken_pct"):
			m *= 1.0 + float(d["dmg_taken_pct"]) / 100.0
	return maxf(0.0, m)


# --- Déroulement ------------------------------------------------------------

## Avance la jauge jusqu'à ce qu'une unité joue, résout le début de son tour
## et la renvoie. Renvoie null si le combat est terminé.
func next_turn() -> BattleUnit:
	_check_end()
	if winner != ONGOING:
		return null
	var ap_c := float(rules["ap_constant"])
	var continuous: bool = rules.get("tick_mode", "continuous") == "continuous"
	var guard := 0
	while true:
		var ready := alive_units().filter(func(u: BattleUnit) -> bool: return u.ap >= 1.0 - 1e-9)
		if not ready.is_empty():
			ready.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool:
				if not is_equal_approx(a.stat("spd"), b.stat("spd")):
					return a.stat("spd") > b.stat("spd")
				if not is_equal_approx(a.ap, b.ap):
					return a.ap > b.ap
				if a.slot != b.slot:  # à VIT égale : la position dans l'équipe (fiche, partie 4)
					return a.slot < b.slot
				return a.team < b.team)
			current = ready[0]
			break
		var step := 1.0
		if continuous:
			step = INF
			for u in alive_units():
				var rate := u.stat("spd") / ap_c
				if rate > 0.0:
					step = minf(step, (1.0 - u.ap) / rate)
		for u in alive_units():
			u.ap += u.stat("spd") / ap_c * step
		guard += 1
		if guard > 100000:
			winner = DRAW
			return null
	current.ap = 0.0
	total_actions += 1
	current.actions_taken += 1
	_emit({"type": "turn_start", "actor": current})
	for x in alive_units():  # Chronophage : chaque tour d'un héros le nourrit
		if x.team != current.team and x.get_trait("gain_ap_on_enemy_turn") != null:
			x.ap = minf(1.0, x.ap + float(x.get_trait("gain_ap_on_enemy_turn")) / 100.0)
	_start_turn(current)
	if not current.is_alive():
		_end_turn(current)
	return current


func skip_turn(u: BattleUnit) -> void:
	_emit({"type": "skip", "actor": u})
	if u.has_effect("stun"):
		_remove_effect(u, "stun")
	_end_turn(u)


func use_skill(u: BattleUnit, idx: int, target: BattleUnit = null) -> void:
	assert(idx in usable_skills(u), "Compétence indisponible")
	var sk := u.skill(idx)
	u.skill_history.append(idx)
	execute(u, sk, target, idx)
	u.cooldowns[idx] = u.skill_cd(idx)
	if sk.has("lock_skill"):  # « ne peut pas utiliser S2 au tour suivant »
		var li := int(sk["lock_skill"])
		u.cooldowns[li] = maxi(u.cooldowns[li], 2)
	if idx > 0 and not sk.get("copy_last_skill", false):
		last_skill = {"unit": u, "index": idx}
	_end_turn(u)


## Résout une compétence (sans finir le tour) : utilisée par use_skill, la copie de Nyssa,
## les relances gratuites et les contre-attaques.
func execute(u: BattleUnit, sk: Dictionary, target: BattleUnit, idx: int, power := 1.0) -> void:
	var targets := _resolve_targets(u, sk, target, idx)
	_emit({"type": "skill", "actor": u, "skill": sk["name"], "index": idx, "targets": targets})
	if u.flags.has("shield_next_skill"):  # Inertie au maximum (Selene)
		_try_apply(u, u, {"id": "shield", "value": float(u.flags["shield_next_skill"]), "of": "target_max_hp", "turns": 2})
		u.flags.erase("shield_next_skill")
	if sk.has("revive"):
		_revive(u, sk["revive"])
	var ctx := {"removed": 0, "dealt": 0.0, "success": [], "power": power, "missed": []}
	if u.flags.has("ignore_def_next") and sk.has("hits"):  # Visage au maximum (Mello)
		ctx["ignore_def"] = float(u.flags["ignore_def_next"])
		u.flags.erase("ignore_def_next")
	var passes := 1
	if sk.get("target", "") == "all_enemies" and u.flags.has("double_aoe") and sk.has("hits"):  # Espéra au maximum
		passes = 2
		u.flags.erase("double_aoe")
	for t in targets:
		if t.team != u.team and sk.has("hits") and _rolls_miss(u, t, sk):
			ctx["missed"].append(t)
			_emit({"type": "miss", "actor": u, "target": t})
		for ef: Dictionary in sk.get("pre_effects", []):
			ctx["removed"] += _apply_action(u, t, ef, ctx)
	if sk.has("detonate") and not targets.is_empty():
		_detonate(u, targets[0], sk["detonate"])
	for t in targets:
		if not t.is_alive():
			continue
		for p in passes:
			_hit_target(u, t, sk, ctx)
		if t.is_alive() and not t in ctx["missed"]:
			for ef: Dictionary in sk.get("effects", []):
				_apply_action(u, t, ef, ctx)
		_consume_bonus_stacks(u, t, sk)
	for a in allies_of(u):
		for ef: Dictionary in sk.get("to_allies", []):
			_apply_action(u, a, ef, ctx)
	for f in enemies_of(u):
		for ef: Dictionary in sk.get("to_enemies", []):
			_apply_action(u, f, ef, ctx)
	for ef: Dictionary in sk.get("self_effects", []):
		var e2 := ef.duplicate()
		e2["no_roll"] = true
		e2["self_cost"] = true
		_apply_action(u, u, e2, ctx)
	if sk.get("consume_fury", false):
		u.stacks["fury"] = 0
	if sk.has("gain_fury"):
		u.add_stack("fury", int(sk["gain_fury"]), 5)
	if sk.get("strip_all_buffs", false):
		for x in alive_units():
			_apply_action(u, x, {"id": "strip_buffs"}, ctx)
	if sk.has("heal_lowest_ally_pct_dmg") and float(ctx["dealt"]) > 0.0:
		_heal(_lowest_hp(allies_of(u)), float(ctx["dealt"]) * float(sk["heal_lowest_ally_pct_dmg"]) / 100.0, u)
	if sk.has("lifesteal") and u.is_alive():
		_heal(u, float(ctx["dealt"]) * float(sk["lifesteal"]) / 100.0, u)
	if sk.has("self_cost"):
		_pay(u, sk["self_cost"])
	if sk.has("while_cooldown"):
		var turns := int(sk.get("cd", u.skill_cd(idx)))
		for a in allies_of(u):
			for ef: Dictionary in sk["while_cooldown"]:
				var e3 := ef.duplicate()
				e3["turns"] = turns
				_apply_action(u, a, e3, ctx)
	if sk.has("on_effect_success") and sk["on_effect_success"]["effect"] in ctx["success"] and not targets.is_empty():
		var t0: BattleUnit = targets[0]
		if t0.is_alive() and u.is_alive():
			_emit({"type": "bonus_action", "actor": u})
			execute(u, u.skill(int(sk["on_effect_success"]["cast"])), t0, int(sk["on_effect_success"]["cast"]))
	if sk.get("copy_last_skill", false):
		_copy_last_skill(u)
	if sk.has("clones_strike"):
		_clones_strike(u, float(sk["clones_strike"]))
	elif not _in_reaction and power >= 1.0 and sk.has("hits") and u.status_stacks("clone") > 0 and not targets.is_empty() 			and targets[0].team != u.team:
		_clone_copies(u, sk, targets)
	if not targets.is_empty() and u.team != targets[0].team and not _in_reaction:
		_on_targeted(u, targets)


## Raté (Dislyte) : seul le dominé peut rater, une fois par cible et par compétence.
func _rolls_miss(u: BattleUnit, t: BattleUnit, sk: Dictionary) -> bool:
	if sk.get("cannot_miss", false):
		return false
	var chance := 0.0
	if dominates(t.constellation, u.constellation):
		chance += float(rules["triangle"].get("dominated_miss_chance", 0.0))
	var punish: Variant = t.get_trait("punish")  # boss de butin : seule la constellation dominante est épargnée
	if punish != null and not dominates(u.constellation, t.constellation):
		chance += float(punish.get("miss", 0.0))
	return chance > 0.0 and rng.randf() * 100.0 < chance


func _resolve_targets(u: BattleUnit, sk: Dictionary, target: BattleUnit, idx: int) -> Array[BattleUnit]:
	var kind: String = sk.get("target", "enemy")
	var out: Array[BattleUnit] = []
	match kind:
		"enemy", "ally", "other_ally":
			var valid := _valid_for(u, kind)
			if target == null or not valid.has(target):
				target = _ai_target_for(u, sk, valid)
			if target != null:
				out.append(target)
		"all_enemies":
			out = enemies_of(u)
		"all_allies":
			out = allies_of(u)
		"self":
			out = [u]
	return out


func _valid_for(u: BattleUnit, kind: String) -> Array[BattleUnit]:
	match kind:
		"enemy":
			var foes := enemies_of(u)
			var taunters := foes.filter(func(f: BattleUnit) -> bool: return f.has_effect("taunt"))
			return taunters if not taunters.is_empty() else foes
		"ally":
			return allies_of(u)
		"other_ally":
			return allies_of(u).filter(func(a: BattleUnit) -> bool: return a != u)
	return []


func _hit_target(u: BattleUnit, t: BattleUnit, sk: Dictionary, ctx: Dictionary) -> void:
	var missed: bool = t in ctx.get("missed", [])
	for h: Dictionary in sk.get("hits", []):
		if h.has("if") and not _condition(h["if"], u, t):
			continue
		for r in int(h.get("repeat", 1)):
			var tt := t
			if h.get("random_other", false):
				var others := enemies_of(u).filter(func(x: BattleUnit) -> bool: return x != t)
				if others.is_empty():
					continue
				tt = others[rng.randi() % others.size()]
			if not tt.is_alive() or not u.is_alive():
				return
			var raw := _raw(u, h) + tt.max_hp() * float(h.get("target_max_hp_pct", 0.0)) / 100.0
			raw *= _damage_bonus(u, tt, sk, ctx) * float(ctx.get("power", 1.0))
			if h.get("pursuit", false) and tt.has_effect("room"):
				raw *= 1.0 + float(rules["effects"]["room"]["pursuit_taken_pct"]) / 100.0
			var opts := h
			if ctx.has("ignore_def") or (missed and tt == t):
				opts = h.duplicate()
				opts["ignore_def"] = float(h.get("ignore_def", 0.0)) + float(ctx.get("ignore_def", 0.0))
				if missed and tt == t:
					opts["missed"] = true
			ctx["dealt"] += _deal_damage(u, tt, raw, opts)
			if missed and tt == t:
				continue  # un raté n'applique pas d'effet
			for ef: Dictionary in h.get("on_hit", []):
				if tt.is_alive():
					_apply_action(u, tt, ef, ctx)
			if sk.get("target", "") == "all_enemies" and u.get_trait("aoe_mark") != null and tt.is_alive():
				_try_apply(u, tt, {"id": u.get_trait("aoe_mark"), "chance": 100})  # Espéra : chaque dégât de zone


## Puissance brute d'un coup : une stat x multiplicateur, ou plusieurs stats {"atk": 0.35, "def": 0.3}.
func _raw(u: BattleUnit, h: Dictionary) -> float:
	var sc: Variant = h.get("scale", "atk")
	var raw := 0.0
	if sc is Dictionary:
		for s: String in sc:
			raw += (u.max_hp() if s == "hp" else u.stat(s)) * float(sc[s])
	else:
		var mult: float = float(h.get("mult", 1.0)) + float(h.get("per_fury", 0.0)) * u.stack("fury")
		raw = (u.max_hp() if sc == "hp" else u.stat(sc)) * mult
	return raw


func _damage_bonus(u: BattleUnit, t: BattleUnit, sk: Dictionary, ctx: Dictionary) -> float:
	var m := 1.0
	for b: Dictionary in sk.get("bonus", []):
		if b.has("per_stack"):
			m *= 1.0 + float(b["pct"]) / 100.0 * t.marks(b["per_stack"])
		elif b.has("per_self_stack"):
			m *= 1.0 + float(b["pct"]) / 100.0 * u.marks(b["per_self_stack"])
		elif b.has("per_ally_alive"):
			m *= 1.0 + float(b["per_ally_alive"]) / 100.0 * allies_of(u).size()
		elif b.has("per_removed"):
			m *= 1.0 + float(b["per_removed"]) / 100.0 * int(ctx["removed"])
		elif b.has("per_spd"):
			m *= 1.0 + float(b["per_spd"]) / 100.0 * u.stat("spd")
	if u.get_trait("dmg_per_spd") != null:
		m *= 1.0 + float(u.get_trait("dmg_per_spd")) / 100.0 * u.stat("spd")
	if u.get_trait("dmg_if_ally_low") != null and allies_of(u).any(func(a: BattleUnit) -> bool: return a.hp_ratio() < 0.5):
		m *= 1.0 + float(u.get_trait("dmg_if_ally_low")) / 100.0
	return m


func _consume_bonus_stacks(u: BattleUnit, t: BattleUnit, sk: Dictionary) -> void:
	for b: Dictionary in sk.get("bonus", []):
		if not b.get("consume", false):
			continue
		var who := t if b.has("per_stack") else u
		var name: String = b.get("per_stack", b.get("per_self_stack", ""))
		if name != "":
			who.stacks[name] = 0
			if who.has_effect(name):
				_remove_effect(who, name)


func _condition(cond: String, u: BattleUnit, t: BattleUnit) -> bool:
	match cond:
		"target_cc":
			return t.is_hard_cc()
		"target_slowed":
			return t.is_slowed()
		"target_repeated_skill":  # Aletheia : même compétence deux tours de suite
			var h := t.skill_history
			return h.size() >= 2 and h[-1] == h[-2]
	return true


## Choix automatique (ennemis et mode Auto).
func ai_choose(u: BattleUnit) -> Dictionary:
	var skills := usable_skills(u)
	skills.reverse()
	skills = skills.filter(func(i: int) -> bool:
		return u.skill(i).get("target_pref", "") != "repeated_skill" 			or valid_targets(u, i).any(func(t: BattleUnit) -> bool: return _condition("target_repeated_skill", u, t)))
	var idx: int = skills[0]
	var target: BattleUnit = _ai_target(u, idx) if needs_target(u, idx) else null
	return {"skill": idx, "target": target}


## Joue le combat jusqu'au bout avec l'IA des deux côtés. Renvoie l'équipe gagnante.
func run_auto() -> int:
	while winner == ONGOING:
		var a := next_turn()
		if a == null:
			break
		if not a.is_alive():
			continue
		if not can_act(a):
			skip_turn(a)
		else:
			var c := ai_choose(a)
			use_skill(a, c["skill"], c["target"])
	return winner


# --- Interne ----------------------------------------------------------------

func _ai_target(u: BattleUnit, idx: int) -> BattleUnit:
	return _ai_target_for(u, u.skill(idx), valid_targets(u, idx))


func _ai_target_for(u: BattleUnit, sk: Dictionary, valid: Array[BattleUnit]) -> BattleUnit:
	valid = valid.duplicate()
	valid.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool: return a.hp_ratio() < b.hp_ratio())
	if sk.get("target_pref", "") == "repeated_skill":
		var pred := valid.filter(func(t: BattleUnit) -> bool: return _condition("target_repeated_skill", u, t))
		if not pred.is_empty():
			return pred[0]
	# Ne pas réveiller un ennemi endormi s'il y a une autre cible (réglage « ai_avoid_sleeping »).
	if rules.get("ai_avoid_sleeping", false) and sk.has("hits"):
		var awake := valid.filter(func(t: BattleUnit) -> bool: return t.team == u.team or not t.has_effect("sleep"))
		if not awake.is_empty():
			valid = awake
	return valid[0] if not valid.is_empty() else null


func _lowest_hp(group: Array[BattleUnit]) -> BattleUnit:
	var best: BattleUnit = null
	for x in group:
		if best == null or x.hp_ratio() < best.hp_ratio():
			best = x
	return best


func _start_turn(u: BattleUnit) -> void:
	u.flags.erase("countered")
	if u.has_passive("breeze"):
		_heal(_lowest_hp(allies_of(u)), _lowest_hp(allies_of(u)).max_hp() * 0.10, u)
	if u.get_trait("ramp_dmg_per_turn") != null:  # montée en puissance (Etheria)
		u.flags["dmg_bonus_pct"] = float(u.flags.get("dmg_bonus_pct", 0.0)) + float(u.get_trait("ramp_dmg_per_turn"))
	if u.flags.has("bar_shield"):  # bouclier de barre resté intact : le boss punit
		u.flags.erase("bar_shield")
		if u.has_effect("shield"):
			_shield_punish(u)
	if u.flags.has("self_burn_pct"):  # phase 2 de Prométhée : la surcharge brûle ses circuits
		_apply_damage(u, u.max_hp() * float(u.flags["self_burn_pct"]) / 100.0, u, {"dot": "surcharge"})
		if not u.is_alive():
			return
	if u.get_trait("clone_per_turn", false):  # Clones temporels (Nyssa)
		_try_apply(u, u, {"id": "clone"})
	for e in u.effects.duplicate():
		var d: Dictionary = rules["effects"][e["id"]]
		if not u.is_alive():
			return
		if d.get("dot_on", "") == "turn_start":
			_apply_damage(u, _dot_amount(u, e, d), e["source"].get_ref(), {"dot": e["id"]})
		if d.has("regen_pct_max_hp"):
			_heal(u, u.max_hp() * float(d["regen_pct_max_hp"]) / 100.0, e["source"].get_ref())
		_run_hooks(u, e, "on_turn_start", null)


func _dot_amount(u: BattleUnit, e: Dictionary, d: Dictionary) -> float:
	if d.has("dot_pct_target_max_hp_from_value"):
		return u.max_hp() * float(e["value"]) / 100.0
	return float(e["caster_atk"]) * float(d["dot_pct_caster_atk"]) / 100.0


func _end_turn(u: BattleUnit) -> void:
	if u.is_alive():
		for e in u.effects.duplicate():
			var d: Dictionary = rules["effects"][e["id"]]
			if d.get("dot_on", "") == "after_action" and u.is_alive():
				_apply_damage(u, _dot_amount(u, e, d), e["source"].get_ref(), {"dot": e["id"]})
			if u.is_alive():
				_run_hooks(u, e, "on_turn_end", null)
	for e in u.effects.duplicate():
		if not e in u.effects:
			continue
		if e["skip_tick"]:
			e["skip_tick"] = false
			continue
		e["turns"] -= 1
		if e["turns"] <= 0:
			_remove_effect(u, e["id"], true)
	for i in 3:
		u.cooldowns[i] = maxi(0, u.cooldowns[i] - 1)
	_emit({"type": "turn_end", "actor": u})
	_check_end()


## Réactions d'une cible attaquée : contre-attaques, perte de PA de l'attaquant, statuts, sets de reliques.
func _on_targeted(attacker: BattleUnit, targets: Array[BattleUnit]) -> void:
	for t in targets:
		if not attacker.is_alive():
			return
		var was_crit: bool = t.flags.get("hit_crit", false)
		t.flags.erase("hit_crit")
		if not t.is_alive():
			continue
		for e in t.effects.duplicate():
			_run_hooks(t, e, "on_attacked", attacker)
		if t.is_hard_cc():
			continue
		if t.get_trait("attacker_ap_down") != null:
			attacker.ap = maxf(0.0, attacker.ap - float(t.get_trait("attacker_ap_down")) / 100.0)
		var counter: Variant = t.get_trait("counter")
		if counter != null and not t.flags.has("countered"):
			var chance := float(counter.get("crit_chance", counter["chance"])) if was_crit else float(counter["chance"])
			if rng.randf() * 100.0 < chance:
				if counter.get("once_per_turn", false):
					t.flags["countered"] = true
				_counter(t, attacker, counter)
		elif t.has_passive("counter") and rng.randf() < 0.30:
			_counter(t, attacker, {"hits": [{"scale": "atk", "mult": 0.8}]})
		if t.set_specials.has("freeze_on_hit_10") and attacker.is_alive() and rng.randf() < 0.10:
			_try_apply(t, attacker, {"id": "freeze", "turns": 1, "chance": 100, "no_roll": true})


func _counter(t: BattleUnit, attacker: BattleUnit, counter: Dictionary) -> void:
	if not attacker.is_alive():
		return
	_emit({"type": "counter", "actor": t, "target": attacker})
	var was := _in_reaction
	_in_reaction = true
	if counter.has("skill"):
		execute(t, t.skill(int(counter["skill"])), attacker, int(counter["skill"]))
	else:
		_hit_target(t, attacker, {"hits": counter["hits"]}, {"removed": 0, "dealt": 0.0, "success": []})
	_in_reaction = was


## S3 de Nyssa : chaque clone frappe un ennemi au hasard, puis les clones disparaissent.
func _clones_strike(u: BattleUnit, pct: float) -> void:
	for c in u.status_stacks("clone"):
		var foes := enemies_of(u)
		if foes.is_empty():
			break
		_deal_damage(u, foes[rng.randi() % foes.size()], u.stat("atk") * pct / 100.0, {})
	if u.has_effect("clone"):
		_remove_effect(u, "clone")


## Clones de Nyssa : chaque clone copie son attaque à 40 % de puissance (sans effets).
func _clone_copies(u: BattleUnit, sk: Dictionary, targets: Array[BattleUnit]) -> void:
	var pct := float(rules["effects"]["clone"]["clone"]["copy_pct"]) / 100.0
	var was := _in_reaction
	_in_reaction = true
	for c in u.status_stacks("clone"):
		var t: BattleUnit = targets[0] if targets[0].is_alive() else (enemies_of(u)[0] if not enemies_of(u).is_empty() else null)
		if t == null:
			break
		_emit({"type": "clone_copy", "actor": u})
		_hit_target(u, t, {"hits": sk["hits"]}, {"removed": 0, "dealt": 0.0, "success": [], "power": pct})
	_in_reaction = was


func _copy_last_skill(u: BattleUnit) -> void:
	if last_skill.is_empty():
		return
	var src: BattleUnit = last_skill["unit"]
	var sk: Dictionary = src.skill(int(last_skill["index"]))
	if sk.get("copy_last_skill", false):
		return
	_emit({"type": "copy", "actor": u, "skill": sk["name"], "from": src})
	execute(u, sk, null, int(last_skill["index"]))


func _deal_damage(att: BattleUnit, tgt: BattleUnit, raw: float, opts: Dictionary) -> float:
	var missed: bool = opts.get("missed", false)
	var is_crit := not missed and rng.randf() * 100.0 < crit_chance(att, tgt)
	var variance := rng.randf_range(float(rules["variance_min"]), float(rules["variance_max"]))
	var dmg := compute_damage(att, tgt, raw, opts, is_crit, variance)
	if missed:
		dmg *= float(rules["triangle"].get("miss_damage_mult", 0.25))
	if tgt.has_effect("sleep"):  # le premier coup sur un dormeur frappe plus fort (Etheria)
		dmg *= 1.0 + float(rules.get("sleep_first_hit_bonus", 0.0)) / 100.0
	if is_crit:
		tgt.flags["hit_crit"] = true
	var dealt := _apply_damage(tgt, dmg, att, {"crit": is_crit, "missed": missed} if missed else {"crit": is_crit})
	if att.set_specials.has("lifesteal_20") and att.is_alive():
		_heal(att, dealt * 0.20, att)
	return dealt


## Applique des dégâts (invincibilité, clones, partages, bouclier). Renvoie les dégâts réellement encaissés.
func _apply_damage(tgt: BattleUnit, dmg: float, source: BattleUnit, info: Dictionary) -> float:
	if not tgt.is_alive():
		return 0.0
	dmg = roundf(dmg)
	var direct := not info.has("dot") and not info.has("reflect")
	if tgt.effect_flag("invincible"):
		_emit({"type": "invincible", "target": tgt})
		return 0.0
	if direct and source != null and source != tgt and tgt.status_stacks("clone") > 0:
		# un clone absorbe le coup et renvoie 30 % de l'ATK de Nyssa à l'attaquant
		_set_stacks(tgt, "clone", tgt.status_stacks("clone") - 1)
		_emit({"type": "clone_absorb", "target": tgt})
		var pct := float(rules["effects"]["clone"]["clone"]["absorb_reflect_pct_atk"])
		if source.is_alive():
			_apply_damage(source, tgt.stat("atk") * pct / 100.0, tgt, {"reflect": true})
		return 0.0
	if direct:
		for sid in ["guarded", "lien"]:  # partage des dégâts avec le Titan
			var share := tgt.get_effect(sid)
			if share.is_empty():
				continue
			var guardian: BattleUnit = share["source"].get_ref()
			if guardian != null and guardian.is_alive() and guardian != tgt:
				var pct := float(share["value"]) if sid == "guarded" else float(rules["effects"]["lien"]["share_with_source_pct"])
				var part := roundf(dmg * pct / 100.0)
				dmg -= part
				_apply_damage(guardian, part, source, {"guard": true})
	var shield := tgt.get_effect("shield")
	if not shield.is_empty():
		var absorbed := minf(dmg, float(shield["value"]))
		shield["value"] -= absorbed
		dmg -= absorbed
		if shield["value"] <= 0.0:
			_remove_effect(tgt, "shield")
	var bastion := tgt.get_effect("bastion")
	if not bastion.is_empty():
		bastion["stored"] = float(bastion.get("stored", 0.0)) + dmg
	tgt.hp -= dmg
	if tgt.hp <= 0.0:
		var saver := _zero_loss_saver(tgt)
		if saver != null:
			saver.zero_loss_used = true
			tgt.hp = 1.0
			_emit({"type": "zero_loss", "actor": saver, "target": tgt})
		elif tgt.get_trait("survive_lethal_once", false) and not tgt.flags.has("survived"):
			tgt.flags["survived"] = true
			tgt.hp = 1.0
			_emit({"type": "survive", "target": tgt})
		elif tgt.get_trait("revive_self_once") != null and not tgt.flags.has("self_revived"):
			tgt.flags["self_revived"] = true  # Laboratoire infini : le réseau de Clefs le relève
			tgt.hp = roundf(tgt.max_hp() * float(tgt.get_trait("revive_self_once")) / 100.0)
			_emit({"type": "boss_revive", "target": tgt})
	_count(source, "dealt", dmg)
	_count(tgt, "taken", dmg)
	var ev := {"type": "damage", "target": tgt, "source": source, "amount": dmg}
	ev.merge(info)
	_emit(ev)
	if tgt.is_alive():
		_check_phases(tgt)
		_check_bars(tgt)
		if direct:
			if tgt.has_effect("sleep"):
				_remove_effect(tgt, "sleep")
			if tgt.has_passive("spark"):
				tgt.add_stack("spark", 1, 5)
			var soh: Variant = tgt.get_trait("stack_on_hit_taken")
			if soh != null:
				tgt.add_stack(soh["stack"], 1, int(soh["max"]))
			for sid: String in tgt.get_trait("status_on_hit_taken", []):  # Inertie, Rage, Garde de fer
				_try_apply(tgt, tgt, {"id": sid}, source)
			if tgt.get_trait("reflect_pct") != null and source != null and source.is_alive() and source != tgt:
				_apply_damage(source, dmg * float(tgt.get_trait("reflect_pct")) / 100.0, tgt, {"reflect": true})
		for e in tgt.effects.duplicate():
			var below: Variant = rules["effects"][e["id"]].get("hooks", {}).get("below_hp")
			if below != null and tgt.is_alive() and tgt.hp_ratio() * 100.0 < float(below["pct"]):
				_run_actions(tgt, e, below["do"], source)
	else:
		tgt.hp = 0.0
		tgt.effects.clear()
		tgt.ap = 0.0
		tgt.stacks.clear()
		_emit({"type": "death", "target": tgt})
		_on_death(tgt)
	return dmg


## Wyrm : le bouclier n'a pas été brisé à temps ; il gèle le héros le plus fort et l'écrase.
func _shield_punish(u: BattleUnit) -> void:
	var foes := enemies_of(u)
	if foes.is_empty():
		return
	foes.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool: return a.stat("atk") > b.stat("atk"))
	var t: BattleUnit = foes[0]
	_emit({"type": "shield_punish", "actor": u, "target": t})
	_try_apply(u, t, {"id": "freeze", "turns": 1, "cannot_resist": true})
	_deal_damage(u, t, u.stat("atk") * float(u.get_trait("shield_punish", {}).get("mult", 2.5)), {})


## Barres de PV (fiche, partie 4) : à chaque barre perdue, un bouclier à briser avant le tour du boss.
func _check_bars(u: BattleUnit) -> void:
	var n := int(u.get_trait("hp_bars", 1))
	if n <= 1:
		return
	for k in range(n - 1, 0, -1):
		if u.flags.has("bar_%d" % k) or u.hp_ratio() > float(k) / n:
			continue
		u.flags["bar_%d" % k] = true
		u.flags["bar_shield"] = true
		_emit({"type": "bar_break", "target": u, "bars_left": k})
		_try_apply(u, u, {"id": "shield", "value": float(u.get_trait("bar_shield_pct", 15.0)), "of": "target_max_hp", "turns": 99})


## Phases de boss : au passage d'un seuil de PV, une seule fois chacune.
func _check_phases(u: BattleUnit) -> void:
	var phases: Array = u.get_trait("phases", [])
	for i in phases.size():
		var ph: Dictionary = phases[i]
		if u.flags.has("phase_%d" % i) or u.hp_ratio() * 100.0 > float(ph["at_hp_pct"]):
			continue
		u.flags["phase_%d" % i] = true
		for k in ["self_burn_pct", "dmg_bonus_pct"]:
			if ph.has(k):
				u.flags[k] = float(ph[k])
		_emit({"type": "phase", "target": u, "name": ph.get("name", "Phase %d" % (i + 2))})


## Mort d'un personnage : ses auras disparaissent, ses statuts posés sur les autres réagissent (Lien).
func _on_death(dead: BattleUnit) -> void:
	for u in units:
		for e in u.effects.duplicate():
			if e["source"].get_ref() != dead:
				continue
			if rules["effects"][e["id"]]["kind"] == "aura":
				_remove_effect(u, e["id"])
			else:
				_run_hooks(u, e, "on_source_death", null)


func _zero_loss_saver(tgt: BattleUnit) -> BattleUnit:
	for u in units:
		if u.team == tgt.team and u.has_passive("zero_loss") and not u.zero_loss_used and (u.is_alive() or u == tgt):
			return u
	return null


func _count(u: BattleUnit, key: String, amount: float) -> void:
	if u != null and stats.has(u):
		stats[u][key] += amount


func _heal(tgt: BattleUnit, amount: float, source: BattleUnit) -> void:
	if tgt == null or not tgt.is_alive():
		return
	if tgt.effect_flag("blocks_heal"):  # Anti-soin, Vide
		_emit({"type": "no_heal", "target": tgt})
		return
	for e in tgt.effects:
		var d: Dictionary = rules["effects"][e["id"]]
		if d.has("heal_received_per_stack"):
			amount *= 1.0 + float(d["heal_received_per_stack"]) * int(e.get("stacks", 1)) / 100.0
	var healed := minf(roundf(amount), tgt.max_hp() - tgt.hp)
	tgt.hp += healed
	if healed > 0.0:
		_count(source if source != null else tgt, "healed", healed)
		_emit({"type": "heal", "target": tgt, "source": source, "amount": healed})


## Prix d'une compétence : PV perdus (en % des PV max), éventuellement non soignables.
func _pay(u: BattleUnit, cost: Dictionary) -> void:
	if not u.is_alive():
		return
	var amount := roundf(u.max_hp() * float(cost.get("hp_pct", 0.0)) / 100.0)
	if cost.get("unhealable", false):
		u.max_hp_loss += amount
	u.hp = maxf(1.0, u.hp - amount)  # un prix ne tue jamais
	_emit({"type": "cost", "target": u, "amount": amount})


func _revive(u: BattleUnit, cfg: Dictionary) -> void:
	if cfg.get("once", true) and u.flags.has("revive_used"):
		return
	for x in units:
		if x.team == u.team and not x.is_alive():
			u.flags["revive_used"] = true
			x.hp = roundf(x.max_hp() * float(cfg.get("hp_pct", 20.0)) / 100.0)
			x.ap = float(cfg.get("ap", 0.0)) / 100.0
			_emit({"type": "revive", "actor": u, "target": x})
			return


## Fait exploser les marques de la cible (Dette de Yass) et, au besoin, les dégâts restants de sa Malédiction.
func _detonate(u: BattleUnit, t: BattleUnit, cfg: Dictionary) -> void:
	if not t.is_alive():
		return
	var n := t.marks(cfg["stack"])
	t.stacks[cfg["stack"]] = 0
	if t.has_effect(cfg["stack"]):
		_remove_effect(t, cfg["stack"])
	if n > 0:
		_deal_damage(u, t, u.stat("atk") * float(cfg["pct_atk"]) / 100.0 * n, {})
	if cfg.get("consume_curse", false) and t.is_alive() and t.has_effect("curse"):
		var e := t.get_effect("curse")
		var d: Dictionary = rules["effects"]["curse"]
		_apply_damage(t, _dot_amount(t, e, d) * int(e["turns"]), u, {"dot": "curse"})
		if t.is_alive():
			_remove_effect(t, "curse")


## Applique une entrée d'une liste d'effets : action immédiate ou effet durable. Renvoie 1 si réussi.
func _apply_action(caster: BattleUnit, tgt: BattleUnit, ef: Dictionary, ctx: Dictionary) -> int:
	if not tgt.is_alive():
		return 0
	if ef.has("if") and not _condition(ef["if"], caster, tgt):
		return 0
	var eid: String = ef["id"]
	var value := float(ef.get("value", 0.0))
	match eid:
		"ap_down":
			if not (ef.get("no_roll", false) or ef.get("cannot_resist", false)) and caster.team != tgt.team:
				if rng.randf() * 100.0 >= effect_chance(caster, tgt, float(ef.get("chance", 100.0))):
					return 0
			tgt.ap = maxf(0.0, tgt.ap - value / 100.0)
			_emit({"type": "ap", "target": tgt, "amount": -value})
			return 1
		"ap_up":
			if ef.has("lowest_value") and tgt == _lowest_ap(allies_of(caster)):
				value = float(ef["lowest_value"])
			tgt.ap = minf(1.0, tgt.ap + value / 100.0)
			_emit({"type": "ap", "target": tgt, "amount": value})
			return 1
		"strip_buffs":
			if ef.has("chance") and rng.randf() * 100.0 >= float(ef["chance"]):
				return 0
			var removed := 0
			for e in tgt.effects.duplicate():
				if _dispellable(e, "buff") and (int(ef.get("count", 0)) == 0 or removed < int(ef["count"])):
					_remove_effect(tgt, e["id"])
					removed += 1
			return removed
		"steal_buff":
			if rng.randf() * 100.0 >= float(ef.get("chance", 100.0)):
				return 0
			for e in tgt.effects.duplicate():
				if _dispellable(e, "buff") and e["id"] != "shield":
					_remove_effect(tgt, e["id"])
					_try_apply(caster, caster, {"id": e["id"], "turns": int(e["turns"]), "value": float(e["value"]), "stacks": int(e.get("stacks", 1))})
					_emit({"type": "steal", "actor": caster, "target": tgt, "effect": e["id"]})
					return 1
			return 0
		"cleanse":
			var n := 0
			for e in tgt.effects.duplicate():
				if _dispellable(e, "debuff") or _dispellable(e, "cc") or _dispellable(e, "mark"):
					_remove_effect(tgt, e["id"])
					n += 1
			return n
		"heal":
			var base_hp := caster.max_hp() if ef.get("of", "") == "caster_max_hp" else tgt.max_hp()
			_heal(tgt, base_hp * value / 100.0, caster)
			return 1
		"stack":
			var who := caster if ef.get("on", "target") == "self" else tgt
			if rules["effects"].has(ef["stack"]):  # marque devenue statut signature
				return 1 if _try_apply(caster, who, {"id": ef["stack"], "stacks": int(ef.get("value", 1)), "chance": ef.get("chance", 100),
					"no_roll": ef.get("no_roll", who.team == caster.team)}) else 0
			who.add_stack(ef["stack"], int(ef.get("value", 1)), int(ef.get("max", 99)))
			return 1
		"cd_reduce":
			var i := int(ef.get("skill", 1))
			tgt.cooldowns[i] = maxi(0, tgt.cooldowns[i] - int(value))
			return 1
	var ok := _try_apply(caster, tgt, ef)
	if ok:
		ctx["success"].append(eid)
	return 1 if ok else 0


func _dispellable(e: Dictionary, kind: String) -> bool:
	var d: Dictionary = rules["effects"][e["id"]]
	return d["kind"] == kind and d.get("dispellable", true)


func _lowest_ap(group: Array[BattleUnit]) -> BattleUnit:
	var best: BattleUnit = null
	for x in group:
		if best == null or x.ap < best.ap:
			best = x
	return best


## Pose un effet ou un statut. Drapeaux de la fiche : cannot_resist (pas de jet), ignores_immunity.
## Les statuts à cumuls s'empilent jusqu'à max_stacks ; atteindre le maximum déclenche on_max.
func _try_apply(caster: BattleUnit, tgt: BattleUnit, ef: Dictionary, attacker: BattleUnit = null) -> bool:
	var eid: String = ef["id"]
	var d: Dictionary = rules["effects"][eid]
	var turns := int(ef.get("turns", d.get("duration", 1)))
	var value := float(ef.get("value", 0.0))
	var hostile: bool = d["kind"] in ["debuff", "cc", "mark"]
	var ignore_imm: bool = ef.get("ignore_immunity", false) or ef.get("ignores_immunity", false) or d.get("ignores_immunity", false)
	if d["kind"] == "buff" and tgt.effect_flag("blocks_buffs"):  # Bloc, Vide
		_emit({"type": "immune", "target": tgt, "effect": eid})
		return false
	for e in tgt.effects:
		if eid in rules["effects"][e["id"]].get("blocks", []):  # Gravité (VIT), Révélé (Immunité)
			return false
	if hostile and not ef.get("self_cost", false):
		if tgt.get_trait("debuff_immune", false) or tgt.effect_flag("debuff_immune") \
				or (d["kind"] == "cc" and tgt.get_trait("cc_immune", false)):
			_emit({"type": "immune", "target": tgt, "effect": eid})
			return false
		if tgt.has_effect("immunity") and not ignore_imm:
			_emit({"type": "immune", "target": tgt, "effect": eid})
			return false
		if d.get("hard_cc", false) and tgt.has_passive("cc_immune"):
			_emit({"type": "immune", "target": tgt, "effect": eid})
			return false
		var certain: bool = ef.get("no_roll", false) or ef.get("cannot_resist", false) or not d.get("resistable", true)
		var cis: Variant = ef.get("certain_if_stack")
		if cis != null and tgt.marks(cis["stack"]) >= int(cis["min"]):
			certain = true
		var boss: String = str(tgt.get_trait("boss", ""))
		if boss != "" and eid in ["freeze", "stun", "sleep"]:
			if eid == "freeze" and boss == "final":
				_emit({"type": "immune", "target": tgt, "effect": eid})
				return false
			if rng.randf() >= 0.5:  # deux fois moins de chances sur un boss, même pour un effet certain
				_emit({"type": "resist", "target": tgt, "effect": eid})
				return false
		if not certain:
			var chance := float(ef.get("chance", 100.0))
			if eid == "freeze" and tgt.has_effect("givre"):
				chance += float(rules["effects"]["givre"]["freeze_chance_per_stack"]) * tgt.status_stacks("givre")
			if rng.randf() * 100.0 >= effect_chance(caster, tgt, chance):
				_emit({"type": "resist", "target": tgt, "effect": eid})
				return false
		if eid == "poison" and caster.has_passive("lasting_poison"):
			turns += 1
	if eid in ["shield", "guarded"] or ef.has("of"):
		match ef.get("of", ""):
			"caster_max_hp":
				value = caster.max_hp() * value / 100.0
			"target_max_hp":
				value = tgt.max_hp() * value / 100.0
	var own_turn := tgt == current
	var max_stacks := int(d.get("max_stacks", 1))
	var add := int(ef.get("stacks", 1))
	var existing := tgt.get_effect(eid)
	if eid == "shield":  # bilan : protection donnée = valeur de bouclier ajoutée
		_count(caster, "shielded", maxf(0.0, value - (float(existing["value"]) if not existing.is_empty() else 0.0)))
	var e: Dictionary
	var before := 0
	if not existing.is_empty():
		e = existing
		before = int(e.get("stacks", 1))
		e["turns"] = maxi(int(e["turns"]), turns)
		e["value"] = maxf(float(e["value"]), value)
		e["source"] = weakref(caster)
		e["caster_atk"] = caster.stat("atk")
		e["skip_tick"] = own_turn
		e["stacks"] = mini(max_stacks, before + add)
	else:
		e = _make_effect(eid, turns, value, caster, own_turn)
		e["stacks"] = mini(max_stacks, add)
		tgt.effects.append(e)
	_emit({"type": "effect", "target": tgt, "source": caster, "effect": eid, "turns": turns, "stacks": int(e["stacks"])})
	_run_hooks(tgt, e, "on_apply", attacker)
	if max_stacks > 1 and before < max_stacks and int(e["stacks"]) >= max_stacks and e in tgt.effects:
		_run_hooks(tgt, e, "on_max", attacker)
	return true


func _make_effect(eid: String, turns: int, value: float, caster: BattleUnit, skip_tick: bool) -> Dictionary:
	return {"id": eid, "turns": turns, "value": value, "source": weakref(caster), "caster_atk": caster.stat("atk"),
		"skip_tick": skip_tick, "stacks": 1}


func _set_stacks(u: BattleUnit, eid: String, n: int) -> void:
	var e := u.get_effect(eid)
	if e.is_empty():
		return
	if n <= 0:
		_remove_effect(u, eid)
	else:
		e["stacks"] = n


## expired : l'effet arrive au bout de sa durée (déclenche on_expire), pas une purge ni un retrait.
func _remove_effect(u: BattleUnit, eid: String, expired := false) -> void:
	for i in u.effects.size():
		if u.effects[i]["id"] == eid:
			var e: Dictionary = u.effects[i]
			u.effects.remove_at(i)
			_emit({"type": "effect_end", "target": u, "effect": eid})
			if eid == "bastion" and u.is_alive():
				_release_bastion(u, e)
			if expired and u.is_alive():
				_run_hooks(u, e, "on_expire", null)
			return


# --- Déclencheurs des statuts signature (data/statuses.json) -----------------

func _run_hooks(holder: BattleUnit, e: Dictionary, hook: String, attacker: BattleUnit) -> void:
	var hooks: Dictionary = rules["effects"][e["id"]].get("hooks", {})
	if hooks.has(hook):
		_run_actions(holder, e, hooks[hook], attacker)


func _run_actions(holder: BattleUnit, e: Dictionary, actions: Array, attacker: BattleUnit) -> void:
	var source: BattleUnit = e["source"].get_ref()
	var n := int(e.get("stacks", 1))
	for a: Dictionary in actions:
		if not holder.is_alive():
			return
		if a.has("if_holder_has") and not holder.has_effect(a["if_holder_has"]):
			continue
		var v := float(a.get("value", 0.0))
		match a["do"]:
			"ap_steal":  # Room : la jauge volée passe à Montana
				var stolen := minf(holder.ap, v / 100.0)
				holder.ap -= stolen
				if source != null and source.is_alive():
					source.ap = minf(1.0, source.ap + stolen)
				_emit({"type": "ap", "target": holder, "amount": -stolen * 100.0})
			"apply":
				_try_apply(source if source != null else holder, holder, {"id": a["id"], "turns": int(a.get("turns", 1)), "no_roll": true})
			"apply_if_no_ap":
				if holder.ap <= 0.001:
					_try_apply(source if source != null else holder, holder, {"id": a["id"], "turns": int(a.get("turns", 1)), "no_roll": true})
			"clear", "remove":
				_remove_effect(holder, e["id"])
			"set_stacks":
				_set_stacks(holder, e["id"], int(v))
			"flag_holder":
				holder.flags[a["flag"]] = v
			"flag_source":
				if source != null:
					source.flags[a["flag"]] = v
			"counter":  # Garde de fer au maximum
				if attacker != null and attacker.is_alive() and attacker != holder:
					_emit({"type": "counter", "actor": holder, "target": attacker})
					_deal_damage(holder, attacker, holder.stat("atk") * float(a["pct_atk"]) / 100.0, {})
			"aoe":  # Rage au maximum
				_emit({"type": "release", "actor": holder, "amount": holder.stat("atk") * float(a["pct_atk"]) / 100.0})
				for f in enemies_of(holder):
					_deal_damage(holder, f, holder.stat("atk") * float(a["pct_atk"]) / 100.0, {})
			"self_cost":
				_pay(holder, {"hp_pct": float(a["hp_pct"])})
			"true_damage":  # Dette : dégâts réels en fin de tour
				var amount := holder.max_hp() * float(a.get("pct_max_hp", 0.0)) / 100.0
				if a.has("pct_source_atk"):
					amount = float(e["caster_atk"]) * float(a["pct_source_atk"]) / 100.0
				if a.get("per_stack", false):
					amount *= n
				_apply_damage(holder, amount, source, {"dot": e["id"]})
			"heal":
				_heal(holder, holder.max_hp() * float(a["pct_max_hp"]) / 100.0, source)
			"shield":
				_try_apply(holder, holder, {"id": "shield", "value": float(a["pct_max_hp"]), "of": "target_max_hp", "turns": 2})
			"extend_if_cc":  # Vide : un tour de plus sur une cible Étourdie
				if holder.is_hard_cc():
					e["turns"] = int(e["turns"]) + int(v)
			"remove_effect":
				if holder.has_effect(a["id"]):
					_remove_effect(holder, a["id"])
			"ap_up_attacker":  # Révélé : un allié du lanceur qui attaque la cible gagne de la jauge
				if attacker != null and source != null and attacker.team == source.team:
					attacker.ap = minf(1.0, attacker.ap + v / 100.0)
			"backlash":  # Scellement : contrecoup sur toute l'équipe ennemie
				for f in enemies_of(holder):
					_apply_damage(f, f.max_hp() * float(a["pct_max_hp"]) / 100.0, holder, {"dot": e["id"]})


## Fin de la Contre-attaque minimale de Selene : renvoie les dégâts accumulés à tous les ennemis.
func _release_bastion(u: BattleUnit, e: Dictionary) -> void:
	var stored := float(e.get("stored", 0.0)) * float(rules["effects"]["bastion"]["release_pct"]) / 100.0
	if stored <= 0.0:
		return
	_emit({"type": "release", "actor": u, "amount": stored})
	for f in enemies_of(u):
		_apply_damage(f, stored, u, {"reflect": true})


func _check_end() -> void:
	if winner != ONGOING:
		return
	if team_alive(0).is_empty():
		winner = 1
	elif team_alive(1).is_empty():
		winner = 0
	elif total_actions >= int(rules["max_actions"]):
		winner = DRAW
	if winner != ONGOING:
		_emit({"type": "battle_end", "winner": winner})


func _emit(ev: Dictionary) -> void:
	if keep_log:
		log_lines.append(BattleLog.describe(ev))
	battle_event.emit(ev)
