class_name LootBoss
extends RefCounted
## Expédition (data/loot_bosses.json) : boss qui donnent des reliques de leurs sets, 4 paliers.
## Fiche de combat des boss : data/heroes.json (section bosses).


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


static func enemy_specs(id: String, diff: int) -> Array:
	var d := difficulty(diff)
	return [{"id": id, "level": int(d["level"]), "star": int(d["star"]), "slot": 4, "power": float(d["power"])}]


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
