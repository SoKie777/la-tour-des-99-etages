class_name BattleLog
extends RefCounted
## Transforme les événements du moteur en texte lisible (journal de combat).

const EFFECT_NAMES := {
	"burn": "Brûlure", "poison": "Poison", "curse": "Malédiction", "slow": "Ralentissement",
	"def_break": "Défense brisée", "disorient": "Désorientation", "atk_down": "ATK réduite",
	"silence": "Silence", "sleep": "Sommeil", "stun": "Étourdissement", "freeze": "Gel",
	"taunt": "Provocation", "immunity": "Immunité", "atk_up": "ATK +", "def_up": "DEF +",
	"spd_up": "VIT +", "cr_up": "TC +", "cd_up": "DC +", "shield": "Bouclier",
	"spd_down": "VIT −", "def_down": "DEF −", "res_down": "Révélé", "acc_up": "PRÉ +",
	"vulnerable": "Expulsé", "aging": "Vieillissement", "dmg_reduce": "Protection",
	"aura_spd": "Élan", "aura_dmg_reduce": "Garde", "aura_chill": "Sol gelé", "guarded": "Sous la garde du Titan",
	"bastion": "Contre-poids",
}


static func effect_name(eid: String) -> String:
	return EFFECT_NAMES.get(eid, eid)


static func describe(ev: Dictionary) -> String:
	match ev["type"]:
		"turn_start":
			return "— Tour de %s" % ev["actor"].display_name
		"skip":
			return "%s ne peut pas agir." % ev["actor"].display_name
		"skill":
			return "%s utilise %s." % [ev["actor"].display_name, ev["skill"]]
		"damage":
			var tag := " (CRITIQUE)" if ev.get("crit", false) else ""
			if ev.has("dot"):
				tag = " (%s)" % effect_name(ev["dot"])
			return "%s subit %d dégâts%s." % [ev["target"].display_name, int(ev["amount"]), tag]
		"heal":
			return "%s récupère %d PV." % [ev["target"].display_name, int(ev["amount"])]
		"effect":
			return "%s : %s (%d t)." % [ev["target"].display_name, effect_name(ev["effect"]), ev["turns"]]
		"effect_end":
			return "%s : fin de %s." % [ev["target"].display_name, effect_name(ev["effect"])]
		"resist":
			return "%s résiste à %s." % [ev["target"].display_name, effect_name(ev["effect"])]
		"immune":
			return "%s est immunisé (%s)." % [ev["target"].display_name, effect_name(ev["effect"])]
		"counter":
			return "%s contre-attaque !" % ev["actor"].display_name
		"zero_loss":
			return "Zéro perte ! %s reste à 1 PV." % ev["target"].display_name
		"death":
			return "%s est hors combat." % ev["target"].display_name
		"ap":
			return "%s : %+d %% de PA." % [ev["target"].display_name, int(ev["amount"])]
		"steal":
			return "%s vole %s à %s." % [ev["actor"].display_name, effect_name(ev["effect"]), ev["target"].display_name]
		"cost":
			return "%s paie le prix : -%d PV." % [ev["target"].display_name, int(ev["amount"])]
		"revive":
			return "%s ramène %s au combat !" % [ev["actor"].display_name, ev["target"].display_name]
		"survive":
			return "%s refuse de tomber (1 PV) !" % ev["target"].display_name
		"release":
			return "%s renvoie %d dégâts à tous les ennemis !" % [ev["actor"].display_name, int(ev["amount"])]
		"copy":
			return "%s copie %s (%s) !" % [ev["actor"].display_name, ev["skill"], ev["from"].display_name]
		"bonus_action":
			return "%s enchaîne !" % ev["actor"].display_name
		"battle_end":
			return {0: "VICTOIRE", 1: "DÉFAITE", 2: "ÉGALITÉ"}.get(ev["winner"], "")
	return ""
