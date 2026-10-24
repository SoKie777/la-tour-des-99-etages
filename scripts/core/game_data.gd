class_name GameData
extends RefCounted
## Chargement et cache des fichiers de données JSON (res://data).
## Tout l'équilibrage vit dans ces fichiers : on règle sans toucher au code.
## Héros, classes, factions, étoiles, niveaux et combat : HeroDb.

static var _cache: Dictionary = {}


static func load_json(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	assert(parsed is Dictionary, "JSON invalide ou introuvable : " + path)
	_cache[path] = parsed
	return parsed


static func gacha() -> Dictionary:
	return load_json("res://data/gacha.json")


static func relics() -> Dictionary:
	return load_json("res://data/relics.json")


static func tower() -> Dictionary:
	return load_json("res://data/tower.json")


static func progression() -> Dictionary:
	return load_json("res://data/progression.json")


## Fiche d'un héros ou d'un boss (data/heroes.json).
static func character(id: String) -> Dictionary:
	return HeroDb.hero(id)


static func characters() -> Dictionary:
	return HeroDb.all()
