class_name LootBoss
extends RefCounted
## Boss de butin (data/loot_bosses.json) : un par constellation, chacun donne les reliques de sa
## constellation. Paliers Facile à Enfer ; aux paliers élevés, les équipes qui ne dominent pas le boss
## ratent plus et subissent plus de dégâts. Pitié : une relique du set choisi toutes les N victoires.


static func cfg() -> Dictionary:
	return GameData.load_json("res://data/loot_bosses.json")


static func ids() -> Array:
	return cfg()["bosses"].keys()


static func boss(id: String) -> Dictionary:
	return cfg()["bosses"][id]


static func difficulty(i: int) -> Dictionary:
	return cfg()["difficulties"][i]


static func difficulty_count() -> int:
	return cfg()["difficulties"].size()


## Constellation qui domine le boss (celle qu'il faut emmener).
static func countered_by(id: String) -> String:
	var beats: Dictionary = GameData.rules()["triangle"]["beats"]
	for c: String in beats:
		if beats[c] == boss(id)["constellation"]:
			return c
	return ""


static func enemy_units(id: String, diff: int) -> Array[BattleUnit]:
	var data := boss(id)
	var d := difficulty(diff)
	var stats: Dictionary = data["stats"].duplicate()
	for k in ["hp", "atk", "def"]:
		stats[k] = roundf(float(stats[k]) * float(d["power"]))
	var u := BattleUnit.new(data, 1, 0, stats)
	if d.has("punish"):
		u.traits["punish"] = d["punish"]
	var out: Array[BattleUnit] = [u]
	return out


## {currencies: {pieces}, relics: [...]} ; forced_set : set imposé pour une relique (pitié).
static func rewards(id: String, diff: int, rng: RandomNumberGenerator, forced_set := "") -> Dictionary:
	var d := difficulty(diff)
	var sets: Array = boss(id)["sets"]
	var relics: Array[Dictionary] = []
	for i in int(d["relics"]):
		var set_id: String = forced_set if (i == 0 and forced_set != "") else sets[rng.randi() % sets.size()]
		var r := Relics.generate(rng, set_id, rng.randi_range(1, 6))
		for l in int(d["relic_level"]):
			Relics.level_up(rng, r)
		relics.append(r)
	return {"currencies": {"pieces": int(d["pieces"])}, "relics": relics}
