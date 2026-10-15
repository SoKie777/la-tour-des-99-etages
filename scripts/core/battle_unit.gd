class_name BattleUnit
extends RefCounted
## Etat d'un personnage pendant un combat. Aucune logique de règles ici,
## seulement l'état et le calcul des stats effectives (base + effets + cumuls).

var id: String
var display_name: String
var data: Dictionary
var team: int
var slot: int
var constellation: String
var base: Dictionary
var hp: float
var ap: float = 0.0
## Tours de recharge restants par compétence (index 0..2).
var cooldowns: Array[int] = [0, 0, 0]
## Effets actifs : {id, turns, value, source (weakref, évite les cycles), caster_atk, skip_tick}
var effects: Array[Dictionary] = []
## Cumuls et marques (Étincelle, Fureur, Rage, Visage, Dette, clones…) : nom -> nombre
var stacks: Dictionary = {"spark": 0, "fury": 0}
var zero_loss_used := false
var actions_taken := 0
## Effets spéciaux de sets de reliques (ex: "lifesteal_20").
var set_specials: Array[String] = []
## Paramètres des passifs (« params » des compétences passives + « traits » du personnage).
var traits: Dictionary = {}
## PV max perdus définitivement pendant le combat (prix « non soignable »).
var max_hp_loss := 0.0
## Drapeaux du combat : une fois par combat, contre-attaque déjà faite ce tour, coup critique reçu…
var flags: Dictionary = {}
## Index des compétences utilisées, dans l'ordre (Aletheia de Prométhée lit les deux dernières).
var skill_history: Array[int] = []


func _init(char_data: Dictionary, team_idx: int, slot_idx: int, stats_override: Dictionary = {}) -> void:
	data = char_data
	id = char_data["id"]
	display_name = char_data["name"]
	team = team_idx
	slot = slot_idx
	constellation = GameData.constellation_of(char_data["nation"]) if char_data.has("nation") else str(char_data.get("constellation", "neutre"))
	base = (stats_override if not stats_override.is_empty() else char_data["stats"]).duplicate()
	hp = max_hp()
	traits = char_data.get("traits", {}).duplicate()
	for s: Dictionary in char_data["skills"]:
		traits.merge(s.get("params", {}))
	for i in 3:
		var sk: Dictionary = char_data["skills"][i]
		if sk.has("initial_cd"):
			cooldowns[i] = int(sk["initial_cd"])
		elif i == 2:
			cooldowns[i] = int(GameData.rules()["skill3_initial_cd"])


func is_alive() -> bool:
	return hp > 0.0


func max_hp() -> float:
	return maxf(1.0, float(base["hp"]) - max_hp_loss)


func hp_ratio() -> float:
	return hp / max_hp()


func skill(i: int) -> Dictionary:
	return data["skills"][i]


func is_passive(i: int) -> bool:
	return skill(i).has("passive")


func skill_cd(i: int) -> int:
	var rules := GameData.rules()
	var default_cd := 0
	if i == 1:
		default_cd = int(rules["skill2_cd_default"])
	elif i == 2:
		default_cd = int(rules["skill3_cd_default"])
	return int(skill(i).get("cd", default_cd))


func has_passive(passive_id: String) -> bool:
	for s: Dictionary in data["skills"]:
		if s.get("passive", "") == passive_id:
			return true
	return data.get("passive_always", "") == passive_id


func get_trait(key: String, default: Variant = null) -> Variant:
	return traits.get(key, default)


func stack(name: String) -> int:
	return int(stacks.get(name, 0))


func add_stack(name: String, n: int, max_n: int) -> void:
	stacks[name] = clampi(stack(name) + n, 0, max_n)


func has_effect(effect_id: String) -> bool:
	return not get_effect(effect_id).is_empty()


func get_effect(effect_id: String) -> Dictionary:
	for e in effects:
		if e["id"] == effect_id:
			return e
	return {}


func effect_kind(effect_id: String) -> String:
	return GameData.rules()["effects"][effect_id]["kind"]


func has_buff() -> bool:
	return count_kind("buff") > 0


func count_kind(kind: String) -> int:
	var n := 0
	for e in effects:
		if effect_kind(e["id"]) == kind:
			n += 1
	return n


func is_hard_cc() -> bool:
	for e in effects:
		if GameData.rules()["effects"][e["id"]].get("hard_cc", false):
			return true
	return false


## Passe son tour (contrôle, ou posture comme la Contre-attaque minimale de Selene).
func is_skipping() -> bool:
	for e in effects:
		if GameData.rules()["effects"][e["id"]].get("skip_turn", false):
			return true
	return false


func is_slowed() -> bool:
	return has_effect("slow") or has_effect("spd_down") or has_effect("room") or has_effect("gravite")


## Cumuls d'une marque, qu'elle soit un simple compteur ou un statut signature.
func marks(name: String) -> int:
	return maxi(stack(name), status_stacks(name))


func status_stacks(effect_id: String) -> int:
	return int(get_effect(effect_id).get("stacks", 0))


## Vrai si un effet actif porte ce drapeau dans sa définition (blocks_heal, blocks_buffs, debuff_immune…).
func effect_flag(flag: String) -> bool:
	for e in effects:
		if GameData.rules()["effects"][e["id"]].get(flag, false):
			return true
	return false


func shield_value() -> float:
	var s := get_effect("shield")
	return float(s.get("value", 0.0))


## Stat effective : base x (1 + somme des % / 100) + bonus plats.
func stat(stat_name: String) -> float:
	var defs: Dictionary = GameData.rules()["effects"]
	var value := float(base[stat_name])
	var pct := 0.0
	var flat := 0.0
	for e in effects:
		var d: Dictionary = defs[e["id"]]
		for sm: Dictionary in d.get("stack_mods", []):  # statuts signature : valeur x cumuls
			if sm["stat"] == stat_name:
				var n := int(e.get("stacks", 1))
				pct += float(sm.get("pct", 0.0)) * n
				flat += float(sm.get("flat", 0.0)) * n
		if d.get("stat", "") != stat_name:
			continue
		if d.has("pct"):
			pct += float(d["pct"])
		elif d.has("pct_from_value"):
			pct += float(d["pct_from_value"]) * float(e["value"])
		elif d.has("flat_from_value"):
			flat += float(d["flat_from_value"]) * float(e["value"])
	for sps: Dictionary in get_trait("stat_per_stack", []):
		if sps["stat"] == stat_name:
			pct += float(sps["pct"]) * stack(sps["stack"])
	if stat_name == "cr":
		flat += 5.0 * stack("spark")
	elif stat_name == "cd":
		flat += 10.0 * stack("spark")
	return maxf(0.0, value * (1.0 + pct / 100.0) + flat)
