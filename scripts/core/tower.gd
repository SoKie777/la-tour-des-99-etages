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


## Constellations qui entament la Ténacité des ennemis d'un étage (mode tactique), sans doublon.
static func floor_weaknesses(number: int) -> Array[String]:
	return weaknesses_of(floor_info(number))


## Faiblesses d'un groupe d'ennemis {enemies | boss_unit} (étage ou niveau du prologue).
static func weaknesses_of(f: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var beats: Dictionary = GameData.rules()["triangle"]["beats"]
	var cons: Array[String] = []
	if f.has("boss_unit"):
		for c: String in GameData.boss(f["boss_unit"]).get("weakness", []):
			if not c in out:
				out.append(c)
		return out
	for id: String in f["enemies"]:
		cons.append(GameData.constellation_of(GameData.character(id)["nation"]))
	for c: String in beats:
		if beats[c] in cons and not c in out:
			out.append(c)
	return out


## Personnages dont le kit contient une arme contre ce boss (clé « boss_bane »), le 5★ d'abord.
static func boss_banes(boss_id: String) -> Array[String]:
	var out: Array[String] = []
	for c: Dictionary in GameData.characters().values():
		if c.has("boss_bane") and c["boss_bane"]["boss"] == boss_id:
			out.append(c["id"])
	out.sort_custom(func(a: String, b: String) -> bool: return int(GameData.character(a)["rarity"]) > int(GameData.character(b)["rarity"]))
	return out


## Rang des ennemis pour la Ténacité du mode tactique (un boss a la sienne).
static func tactics_rank(number: int) -> String:
	return "elite" if floor_info(number).get("elite", false) else "normal"


## Ennemis d'un étage. Étage de boss : le boss (data/bosses.json), renforcé selon le palier de difficulté.
static func enemy_units(number: int, difficulty := "facile") -> Array[BattleUnit]:
	return make_enemies(floor_info(number), difficulty)


## Ennemis d'un groupe {enemies | boss_unit, power} (étage ou niveau du prologue).
static func make_enemies(f: Dictionary, difficulty := "facile") -> Array[BattleUnit]:
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
