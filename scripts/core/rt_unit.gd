class_name RtUnit
extends RefCounted
## Un combattant du combat en temps réel (scripts/core/rt_battle.gd).
## Position 2D sur le terrain : x = axe du combat (ton équipe à gauche), y = profondeur.

var id: String
var data: Dictionary
var display_name: String
var team: int
var slot: int          # case de la grille : colonne × 3 + rangée (colonne 0 = devant)
var cls: String
var cls_info: Dictionary
var level: int
var star: int
var factions: Array[String] = []
var base: Dictionary   # stats fixes (niveau, étoiles, reliques, talents statiques)
var mods: Dictionary = {}  # bonus statiques en % ou points (talents, passifs, bonus de faction)

var pos := Vector2.ZERO
var home := Vector2.ZERO
var facing := 1.0
var hp := 0.0
var max_hp := 0.0
var shields: Array[Dictionary] = []    # {amount, t}
var statuses: Array[Dictionary] = []   # {id, t, value, src, acc}
var target: RtUnit = null

var attack_cd := 0.0
var skill_cd := 0.0
var ov_cd := 0.0
var lock := 0.0          # immobilisé par une animation (compétence, Overdrive)
var attack_count := 0
var rage := 0.0
var eveil := 0
var promesse := 0
var passive_on := true
var once_done := {}      # déclencheurs « une fois » déjà utilisés
var icd := {}            # intervalles minimums des passifs
var periodic := {}       # temps restant avant le prochain passif périodique
var low_allies := {}     # alliés déjà secourus par un passif ally_low
var hp_lost_acc := 0.0
var dead := false
var range_m := 1.3
var move_speed := 2.0
var interval := 1.2
var dmg_type := "phys"
var boss := false
var radius := 0.4

## Statistiques de fin de combat
var dealt := 0.0
var taken := 0.0
var healed := 0.0
var shielded := 0.0


func _init(spec: Dictionary, team_: int) -> void:
	id = spec["id"]
	data = HeroDb.hero(id)
	display_name = data.get("name", id)
	team = team_
	slot = int(spec.get("slot", 0))
	cls = data["class"]
	cls_info = HeroDb.class_info(cls)
	level = int(spec.get("level", 1))
	star = int(spec.get("star", HeroDb.start_star(int(data["rarity"]))))
	factions = HeroDb.active_factions(id, star)
	if data.get("boss", false):
		factions = []
		for f in data.get("factions", []):
			factions.append(str(f))
	base = HeroDb.stats(id, level, star, spec.get("gear", []), float(spec.get("power", 1.0)))
	max_hp = base["hp"] * float(HeroDb.rules().get("hp_mult", 1.0))
	hp = max_hp
	boss = data.get("boss", false)
	range_m = float(data.get("range", cls_info["range"]))
	move_speed = float(data.get("move", cls_info["move"]))
	interval = float(data.get("interval", cls_info["interval"]))
	dmg_type = str(data.get("dmg", cls_info["dmg"]))
	radius = 0.75 if boss else 0.4
	passive_on = boss or level >= int(HeroDb.levels()["passive_level"])


func is_alive() -> bool:
	return not dead


func hp_ratio() -> float:
	return hp / max_hp if max_hp > 0.0 else 0.0


func has_faction(f: String) -> bool:
	return factions.has(f)


func has_status(sid: String) -> bool:
	for s in statuses:
		if s["id"] == sid:
			return true
	return false


func get_status(sid: String) -> Dictionary:
	for s in statuses:
		if s["id"] == sid:
			return s
	return {}


func remove_status(sid: String) -> void:
	for i in range(statuses.size() - 1, -1, -1):
		if statuses[i]["id"] == sid:
			statuses.remove_at(i)


## Somme d'une stat en % ou en points : talents statiques + statuts + mécaniques de faction.
func mod(key: String) -> float:
	var v := float(mods.get(key, 0.0))
	for s in statuses:
		var info := HeroDb.status_info(s["id"])
		if info.has(key):
			v += float(s["value"]) if info.get("scaled", "") == key else float(info[key])
	return v


func flag(key: String) -> bool:
	for s in statuses:
		if HeroDb.status_info(s["id"]).get(key, false):
			return true
	return false


func can_act() -> bool:
	return not dead and not flag("no_act")


func can_move() -> bool:
	return not dead and not flag("no_move")


func can_skill() -> bool:
	return can_act() and not flag("no_skill")


func targetable() -> bool:
	return not dead and not flag("untargetable")


func shield_total() -> float:
	var t := 0.0
	for s in shields:
		t += float(s["amount"])
	return t


func atk() -> float:
	return base["atk"] * maxf(0.2, 1.0 + mod("atk_pct") / 100.0)


func def_of(kind: String) -> float:
	var d: float = base["pdef"] if kind == "phys" else base["mdef"]
	return d * maxf(0.0, 1.0 + mod("def_pct") / 100.0)


func aspd() -> float:
	return clampf(1.0 + mod("aspd_pct") / 100.0, 0.3, 3.0)


func haste() -> float:
	return 1.0 + maxf(-50.0, base["haste"] + mod("haste")) / 100.0


func crit_chance() -> float:
	return float(HeroDb.rules()["damage"]["crit_base"]) + base["crit"] + mod("crit")


func ov_skill() -> Dictionary:
	return data.get("overdrive", {})


func ov_cost() -> int:
	var sk := ov_skill()
	if sk.is_empty():
		return 99
	return maxi(0, int(sk.get("cost", 3)) + int(mod("ov_cost")))


func hero_rarity() -> int:
	return int(data.get("rarity", 0))
