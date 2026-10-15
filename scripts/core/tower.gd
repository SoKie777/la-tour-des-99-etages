class_name Tower
extends RefCounted
## Ascension de la Tour : étages numérotés à partir de 1, ennemis renforcés selon « power »,
## récompenses de victoire (data/tower.json).


static func floor_count() -> int:
	var n := 0
	for u: Dictionary in GameData.tower()["universes"]:
		n += u["floors"].size()
	return n


## {number, universe, decor, enemies, power, elite, boss}
static func floor_info(number: int) -> Dictionary:
	for u: Dictionary in GameData.tower()["universes"]:
		var idx := number - int(u["first_floor"])
		if idx >= 0 and idx < u["floors"].size():
			var f: Dictionary = u["floors"][idx].duplicate()
			f["number"] = number
			f["universe"] = u["name"]
			f["decor"] = u.get("boss_decor" if f.has("boss") else "decor", "dojo")
			return f
	return {}


## Ennemis d'un étage. Étage de boss : le boss (data/bosses.json), renforcé selon le palier de difficulté.
static func enemy_units(number: int, difficulty := "facile") -> Array[BattleUnit]:
	var f := floor_info(number)
	var power := float(f["power"])
	var out: Array[BattleUnit] = []
	if f.has("boss_unit"):
		var data := GameData.boss(f["boss_unit"])
		var stats: Dictionary = data["stats"].duplicate()
		var dp := float(GameData.bosses()["difficulties"][difficulty]["power"]) * power
		for k in ["hp", "atk", "def"]:
			stats[k] = roundf(float(stats[k]) * dp)
		out.append(BattleUnit.new(data, 1, 0, stats))
		return out
	for id: String in f["enemies"]:
		var data := GameData.character(id)
		var stats: Dictionary = data["stats"].duplicate()
		for k in ["hp", "atk", "def"]:
			stats[k] = roundf(float(stats[k]) * power)
		out.append(BattleUnit.new(data, 1, out.size(), stats))
	return out


## {currencies: {id: n}, relics: [relique...]}
static func rewards(number: int, first_clear: bool, rng: RandomNumberGenerator) -> Dictionary:
	var cfg: Dictionary = GameData.tower()["rewards"]
	var f := floor_info(number)
	var cur := {"pieces": int(cfg["each"]["pieces_base"]) + int(cfg["each"]["pieces_per_floor"]) * number}
	if first_clear:
		var key := "eclat_de_voeu_boss" if f.has("boss") else ("eclat_de_voeu_elite" if f.get("elite", false) else "eclat_de_voeu")
		cur["eclat_de_voeu"] = int(cfg["first"][key])
	var sets: Array = GameData.progression()["relic_drop_sets"]
	var relics: Array[Dictionary] = []
	for i in int(cfg["each"]["relics"]):
		relics.append(Relics.generate(rng, sets[rng.randi() % sets.size()], rng.randi_range(1, 6)))
	return {"currencies": cur, "relics": relics}
