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


static func rules() -> Dictionary:
	return load_json("res://data/rules.json")


static func gacha() -> Dictionary:
	return load_json("res://data/gacha.json")


static func relics() -> Dictionary:
	return load_json("res://data/relics.json")


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


static func constellation_of(nation: String) -> String:
	return rules()["triangle"]["nation_constellation"][nation]
