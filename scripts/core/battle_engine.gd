class_name BattleEngine
extends RefCounted
## Moteur de combat à barre d'action (3 contre 3), sans aucune dépendance à l'affichage.
## La scène de combat et les simulations l'utilisent de la même façon :
##   var actor := engine.next_turn()
##   if not engine.can_act(actor): engine.skip_turn(actor)
##   else: engine.use_skill(actor, skill_index, target)

signal battle_event(event: Dictionary)

const ONGOING := -1
const DRAW := 2

var rules: Dictionary
var units: Array[BattleUnit] = []
var rng := RandomNumberGenerator.new()
var winner := ONGOING
var current: BattleUnit = null
var total_actions := 0
var log_lines: Array[String] = []
var keep_log := false


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
		if u.set_specials.has("start_immunity_1"):
			u.effects.append(_make_effect("immunity", 1, 0.0, u, true))


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
	return u.is_alive() and not u.is_hard_cc()


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
	return []


func needs_target(u: BattleUnit, skill_idx: int) -> bool:
	return u.skill(skill_idx).get("target", "enemy") in ["enemy", "ally"]


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
	var def_eff := tgt.stat("def") * (1.0 - float(opts.get("ignore_def", 0.0)))
	var dmg := raw * def_c / (def_c + def_eff)
	if is_crit:
		dmg *= 1.0 + att.stat("cd") / 100.0
	dmg *= variance
	if dominates(tgt.constellation, att.constellation):
		dmg *= float(rules["triangle"]["dominated_damage_mult"])
	if att.has_passive("fury"):
		dmg *= 1.0 + 0.08 * att.stacks["fury"]
	if opts.has("low_hp_bonus") and tgt.hp_ratio() < 0.5:
		dmg *= 1.0 + float(opts["low_hp_bonus"])
	return dmg


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
				return a.ap > b.ap)
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
	var kind: String = sk.get("target", "enemy")
	var targets: Array[BattleUnit] = []
	match kind:
		"enemy", "ally":
			var valid := valid_targets(u, idx)
			if target == null or not valid.has(target):
				target = _ai_target(u, idx)
			targets = [target]
		"all_enemies":
			targets = enemies_of(u)
		"all_allies":
			targets = allies_of(u)
		"self":
			targets = [u]
	_emit({"type": "skill", "actor": u, "skill": sk["name"], "index": idx, "targets": targets})

	for t in targets:
		if not t.is_alive():
			continue
		for h: Dictionary in sk.get("hits", []):
			var mult: float = float(h["mult"]) + float(h.get("per_fury", 0.0)) * int(u.stacks["fury"])
			var scale: float = u.max_hp() if h["scale"] == "hp" else u.stat(h["scale"])
			_deal_damage(u, t, scale * mult, h)
		if t.is_alive():
			for ef: Dictionary in sk.get("effects", []):
				_try_apply(u, t, ef)
	for ef: Dictionary in sk.get("self_effects", []):
		_try_apply(u, u, ef)

	if sk.get("consume_fury", false):
		u.stacks["fury"] = 0
	if sk.has("gain_fury"):
		u.stacks["fury"] = mini(5, u.stacks["fury"] + int(sk["gain_fury"]))

	if not targets.is_empty() and u.team != targets[0].team:
		_on_targeted(u, targets)
	u.cooldowns[idx] = u.skill_cd(idx)
	_end_turn(u)


## Choix automatique (ennemis et mode Auto).
func ai_choose(u: BattleUnit) -> Dictionary:
	var skills := usable_skills(u)
	skills.reverse()
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
	var valid := valid_targets(u, idx)
	valid.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool: return a.hp_ratio() < b.hp_ratio())
	return valid[0] if not valid.is_empty() else null


func _start_turn(u: BattleUnit) -> void:
	if u.has_passive("breeze"):
		var allies := allies_of(u)
		allies.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool: return a.hp_ratio() < b.hp_ratio())
		_heal(allies[0], allies[0].max_hp() * 0.10, u)
	for e in u.effects.duplicate():
		var d: Dictionary = rules["effects"][e["id"]]
		if d.get("dot_on", "") == "turn_start" and u.is_alive():
			_apply_damage(u, float(e["caster_atk"]) * float(d["dot_pct_caster_atk"]) / 100.0, e["source"].get_ref(), {"dot": e["id"]})


func _end_turn(u: BattleUnit) -> void:
	if u.is_alive():
		for e in u.effects.duplicate():
			var d: Dictionary = rules["effects"][e["id"]]
			if d.get("dot_on", "") == "after_action" and u.is_alive():
				_apply_damage(u, float(e["caster_atk"]) * float(d["dot_pct_caster_atk"]) / 100.0, e["source"].get_ref(), {"dot": e["id"]})
	for e in u.effects.duplicate():
		if e["skip_tick"]:
			e["skip_tick"] = false
			continue
		e["turns"] -= 1
		if e["turns"] <= 0:
			_remove_effect(u, e["id"])
	for i in 3:
		u.cooldowns[i] = maxi(0, u.cooldowns[i] - 1)
	_emit({"type": "turn_end", "actor": u})
	_check_end()


func _on_targeted(attacker: BattleUnit, targets: Array[BattleUnit]) -> void:
	for t in targets:
		if not attacker.is_alive():
			return
		if not t.is_alive() or t.is_hard_cc():
			continue
		if t.has_passive("counter") and rng.randf() < 0.30:
			_emit({"type": "counter", "actor": t, "target": attacker})
			_deal_damage(t, attacker, t.stat("atk") * 0.8, {})
		if t.set_specials.has("freeze_on_hit_10") and attacker.is_alive() and rng.randf() < 0.10:
			_try_apply(t, attacker, {"id": "freeze", "turns": 1, "chance": 100, "no_roll": true})


func _deal_damage(att: BattleUnit, tgt: BattleUnit, raw: float, opts: Dictionary) -> void:
	var is_crit := rng.randf() * 100.0 < crit_chance(att, tgt)
	var variance := rng.randf_range(float(rules["variance_min"]), float(rules["variance_max"]))
	var dmg := compute_damage(att, tgt, raw, opts, is_crit, variance)
	var dealt := _apply_damage(tgt, dmg, att, {"crit": is_crit})
	if att.set_specials.has("lifesteal_20") and att.is_alive():
		_heal(att, dealt * 0.20, att)


## Applique des dégâts (bouclier d'abord). Renvoie les dégâts réellement encaissés.
func _apply_damage(tgt: BattleUnit, dmg: float, source: BattleUnit, info: Dictionary) -> float:
	dmg = roundf(dmg)
	var shield := tgt.get_effect("shield")
	if not shield.is_empty():
		var absorbed := minf(dmg, float(shield["value"]))
		shield["value"] -= absorbed
		dmg -= absorbed
		if shield["value"] <= 0.0:
			_remove_effect(tgt, "shield")
	tgt.hp -= dmg
	if tgt.hp <= 0.0:
		var saver := _zero_loss_saver(tgt)
		if saver != null:
			saver.zero_loss_used = true
			tgt.hp = 1.0
			_emit({"type": "zero_loss", "actor": saver, "target": tgt})
	var ev := {"type": "damage", "target": tgt, "source": source, "amount": dmg}
	ev.merge(info)
	_emit(ev)
	if tgt.is_alive():
		if not info.has("dot"):
			if tgt.has_effect("sleep"):
				_remove_effect(tgt, "sleep")
			if tgt.has_passive("spark"):
				tgt.stacks["spark"] = mini(5, tgt.stacks["spark"] + 1)
	else:
		tgt.hp = 0.0
		tgt.effects.clear()
		tgt.ap = 0.0
		_emit({"type": "death", "target": tgt})
	return dmg


func _zero_loss_saver(tgt: BattleUnit) -> BattleUnit:
	for u in units:
		if u.team == tgt.team and u.has_passive("zero_loss") and not u.zero_loss_used and (u.is_alive() or u == tgt):
			return u
	return null


func _heal(tgt: BattleUnit, amount: float, source: BattleUnit) -> void:
	if not tgt.is_alive():
		return
	var healed := minf(roundf(amount), tgt.max_hp() - tgt.hp)
	tgt.hp += healed
	if healed > 0.0:
		_emit({"type": "heal", "target": tgt, "source": source, "amount": healed})


func _try_apply(caster: BattleUnit, tgt: BattleUnit, ef: Dictionary) -> void:
	var eid: String = ef["id"]
	var d: Dictionary = rules["effects"][eid]
	var turns := int(ef.get("turns", 1))
	var value := float(ef.get("value", 0.0))
	if d["kind"] != "buff":
		if tgt.has_effect("immunity"):
			_emit({"type": "immune", "target": tgt, "effect": eid})
			return
		if d.get("hard_cc", false) and tgt.has_passive("cc_immune"):
			_emit({"type": "immune", "target": tgt, "effect": eid})
			return
		if not ef.get("no_roll", false):
			var chance := effect_chance(caster, tgt, float(ef.get("chance", 100.0)))
			if rng.randf() * 100.0 >= chance:
				_emit({"type": "resist", "target": tgt, "effect": eid})
				return
		if eid == "poison" and caster.has_passive("lasting_poison"):
			turns += 1
	if eid == "shield" and ef.get("of", "") == "caster_max_hp":
		value = caster.max_hp() * value / 100.0
	var own_turn := tgt == current
	var existing := tgt.get_effect(eid)
	if not existing.is_empty():
		existing["turns"] = maxi(int(existing["turns"]), turns)
		existing["value"] = maxf(float(existing["value"]), value)
		existing["source"] = weakref(caster)
		existing["caster_atk"] = caster.stat("atk")
		existing["skip_tick"] = own_turn
	else:
		tgt.effects.append(_make_effect(eid, turns, value, caster, own_turn))
	_emit({"type": "effect", "target": tgt, "source": caster, "effect": eid, "turns": turns})


func _make_effect(eid: String, turns: int, value: float, caster: BattleUnit, skip_tick: bool) -> Dictionary:
	return {"id": eid, "turns": turns, "value": value, "source": weakref(caster), "caster_atk": caster.stat("atk"), "skip_tick": skip_tick}


func _remove_effect(u: BattleUnit, eid: String) -> void:
	for i in u.effects.size():
		if u.effects[i]["id"] == eid:
			u.effects.remove_at(i)
			_emit({"type": "effect_end", "target": u, "effect": eid})
			return


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
