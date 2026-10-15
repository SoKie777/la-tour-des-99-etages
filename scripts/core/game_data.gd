class_name GameData
extends RefCounted
## Chargement et cache des fichiers de données JSON (res://data).
## Tout l'équilibrage vit dans ces fichiers : on règle sans toucher au code.

static var _cache: Dictionary = {}
static var _characters_by_id: Dictionary = {}


static func load_json(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	assert(parsed is Dictionary, "JSON invalide ou introuvable : " + path)
	_cache[path] = parsed
	return parsed


## Règles de combat ; les statuts signature (data/statuses.json) rejoignent les effets.
static func rules() -> Dictionary:
	var r := load_json("res://data/rules.json")
	if not r.has("_statuses_merged"):
		r["_statuses_merged"] = true
		for id: String in load_json("res://data/statuses.json"):
			if not id.begins_with("_"):
				r["effects"][id] = load_json("res://data/statuses.json")[id]
	return r


static func gacha() -> Dictionary:
	return load_json("res://data/gacha.json")


static func relics() -> Dictionary:
	return load_json("res://data/relics.json")


static func tower() -> Dictionary:
	return load_json("res://data/tower.json")


static func progression() -> Dictionary:
	return load_json("res://data/progression.json")


static func bosses() -> Dictionary:
	return load_json("res://data/bosses.json")


static func boss(id: String) -> Dictionary:
	return bosses()["bosses"][id]


static func characters() -> Dictionary:
	if _characters_by_id.is_empty():
		for c: Dictionary in load_json("res://data/characters.json")["characters"]:
			_characters_by_id[c["id"]] = c
	return _characters_by_id


static func character(id: String) -> Dictionary:
	var all := characters()
	assert(all.has(id), "Personnage inconnu : " + id)
	return all[id]


static func character_ids_by_nation(nation: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in characters():
		if characters()[id]["nation"] == nation:
			out.append(id)
	return out


## Equipe de 3 d'une nation (combats de test et simulations) : d'une rareté donnée,
## ou les meilleures raretés si rarity = 0 (hors Titan).
static func nation_team(nation: String, rarity: int = 0) -> Array[String]:
	var ids := character_ids_by_nation(nation).filter(func(id: String) -> bool:
		return characters()[id]["class"] != "titan" and (rarity == 0 or int(characters()[id]["rarity"]) == rarity))
	ids.sort_custom(func(a: String, b: String) -> bool: return int(characters()[a]["rarity"]) > int(characters()[b]["rarity"]))
	var out: Array[String] = []
	out.assign(ids.slice(0, 3))
	return out


static func constellation_of(nation: String) -> String:
	return rules()["triangle"]["nation_constellation"][nation]
