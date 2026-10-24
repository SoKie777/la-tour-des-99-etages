class_name HeroDb
extends RefCounted
## Données de la refonte temps réel : héros, classes, factions, étoiles, niveaux.
## Calcul des stats d'un héros (modèle Dragon Traveler, docs/ANALYSE_DRAGON_TRAVELER.md §2.6) :
## stat = base de classe au niveau 100 / 5,023 × courbe du niveau × aptitude de rareté × aptitude du héros
##        × multiplicateur d'étoiles, puis reliques (plates et %) et sets.

const L1_DIVISOR := 5.023

static var _cache: Dictionary = {}


static func _json(name: String) -> Dictionary:
	if not _cache.has(name):
		_cache[name] = GameData.load_json("res://data/%s.json" % name)
	return _cache[name]


static func rules() -> Dictionary:
	return _json("rt_rules")


static func statuses() -> Dictionary:
	return _json("rt_statuses")["statuses"]


static func classes() -> Dictionary:
	return _json("classes")["classes"]


static func class_order() -> Array:
	return _json("classes")["order"]


static func class_info(cls: String) -> Dictionary:
	return classes().get(cls, {})


static func factions() -> Dictionary:
	return _json("factions")["factions"]


static func faction_order() -> Array:
	return _json("factions")["order"]


static func faction(id: String) -> Dictionary:
	return factions().get(id, {})


static func faction_bonus() -> Dictionary:
	return _json("factions")["bonus"]


static func stars() -> Dictionary:
	return _json("stars")


static func levels() -> Dictionary:
	return _json("levels")


## Tous les héros et boss : id -> fiche.
static func all() -> Dictionary:
	if not _cache.has("_heroes"):
		var d := _json("heroes")
		var out := {}
		for h: Dictionary in d["heroes"]:
			out[h["id"]] = h
		for h: Dictionary in d["bosses"]:
			out[h["id"]] = h
		_cache["_heroes"] = out
	return _cache["_heroes"]


static func hero(id: String) -> Dictionary:
	return all().get(id, {})


static func exists(id: String) -> bool:
	return all().has(id)


## Héros jouables (sans les boss), dans l'ordre du fichier.
static func playable_ids(include_substitutes := true) -> Array[String]:
	var out: Array[String] = []
	for h: Dictionary in _json("heroes")["heroes"]:
		if include_substitutes or not h.get("substitute", false):
			out.append(h["id"])
	return out


static func ids_of_rarity(rarity: int) -> Array[String]:
	var out: Array[String] = []
	for id in playable_ids():
		if int(hero(id)["rarity"]) == rarity:
			out.append(id)
	return out


static func substitute_for(cls: String) -> String:
	for id in playable_ids():
		var h := hero(id)
		if h.get("substitute", false) and h["class"] == cls:
			return id
	return ""


static func start_star(rarity: int) -> int:
	return int(stars()["start_star"].get(str(rarity), 1))


static func max_star(rarity: int) -> int:
	return int(stars()["max_star_by_rarity"].get(str(rarity), 19))


static func star_tier(star: int) -> Dictionary:
	var tiers: Array = stars()["tiers"]
	return tiers[clampi(star, 1, tiers.size()) - 1]


static func max_level_for_star(star: int) -> int:
	return int(star_tier(star)["max_level"])


## Multiplicateur de niveau ; au-delà de 100, la Résonance de classe prolonge la courbe.
static func level_rate(level: int) -> float:
	var lv := levels()
	var rate: Array = lv["rate"]
	if level <= rate.size():
		return float(rate[clampi(level, 1, rate.size()) - 1])
	return float(rate[-1]) + float(lv["resonance"]["rate_per_level"]) * (level - rate.size())


## Factions actives : la 2e s'éveille à 6 étoiles.
static func active_factions(id: String, star: int) -> Array[String]:
	var f: Array = hero(id).get("factions", [])
	var out: Array[String] = []
	for i in f.size():
		if i == 0 or star >= 6:
			out.append(str(f[i]))
	return out


## Stats de combat d'un héros. gear : reliques équipées (format de Relics) ; power : multiplicateur
## des ennemis (PV, ATK, DEF).
static func stats(id: String, level: int, star: int, gear: Array = [], power := 1.0) -> Dictionary:
	var h := hero(id)
	var cls := class_info(h["class"])
	var base: Dictionary = cls["base_l100"]
	var r_apt := float(_json("heroes")["rarity_apt"].get(str(int(h["rarity"])), 1.0))
	var apt: Dictionary = h.get("apt", {})
	var k := level_rate(level) / L1_DIVISOR * r_apt * float(star_tier(star)["mult"])
	var out := {
		"hp": float(base["hp"]) * k * float(apt.get("hp", 1.0)) * power,
		"atk": float(base["atk"]) * k * float(apt.get("atk", 1.0)) * power,
		"pdef": float(base["pdef"]) * k * float(apt.get("def", 1.0)) * power,
		"mdef": float(base["mdef"]) * k * float(apt.get("def", 1.0)) * power,
		"crit": 0.0, "crit_dmg": 0.0, "haste": 0.0, "acc": 0.0, "res": 0.0,
	}
	if not gear.is_empty():
		_apply_gear(out, gear)
	return out


## Reliques : 'def' vaut pour les deux défenses, 'spd' devient de la Hâte, 'cr'/'cd' le critique.
static func _apply_gear(out: Dictionary, gear: Array) -> void:
	var flat := {}
	var pct := {}
	var add := func(stat: String, v: float) -> void:
		if stat.ends_with("_pct"):
			var key := stat.trim_suffix("_pct")
			pct[key] = float(pct.get(key, 0.0)) + v
		else:
			flat[stat] = float(flat.get(stat, 0.0)) + v
	for r: Dictionary in gear:
		add.call(str(r["main"]["stat"]), float(r["main"]["value"]))
		for s: String in r["subs"]:
			add.call(s, float(r["subs"][s]))
	var active := Relics.active_sets(gear)
	for s: String in active:
		var sb: Array = Relics.set_bonus(s, active[s])
		for stat: String in sb[0]:
			add.call(stat, float(sb[0][stat]))
	out["hp"] = out["hp"] * (1.0 + float(pct.get("hp", 0.0)) / 100.0) + float(flat.get("hp", 0.0))
	out["atk"] = out["atk"] * (1.0 + float(pct.get("atk", 0.0)) / 100.0) + float(flat.get("atk", 0.0))
	for d in ["pdef", "mdef"]:
		out[d] = out[d] * (1.0 + float(pct.get("def", 0.0)) / 100.0) + float(flat.get("def", 0.0))
	out["haste"] += float(flat.get("spd", 0.0))
	out["crit"] += float(flat.get("cr", 0.0))
	out["crit_dmg"] += float(flat.get("cd", 0.0))
	out["acc"] += float(flat.get("acc", 0.0))
	out["res"] += float(flat.get("res", 0.0))


## Puissance affichée (DT : « Power ») : somme pondérée simple.
static func power_of(s: Dictionary) -> int:
	return int(s["atk"] * 2.2 + s["hp"] * 0.18 + (s["pdef"] + s["mdef"]) * 0.9 + s["crit"] * 25 + s["haste"] * 20)


## Placement sur la grille 3 × 3 (case = colonne × 3 + rangée, colonne 0 = devant) selon la classe :
## Gardiens devant, Guerriers devant ou au milieu, Prêtres, Archers et Mages au milieu ou au fond,
## Assassins partout (DT §2.1).
static func can_place(id: String, slot: int) -> bool:
	if slot < 0 or slot > 8 or not exists(id):
		return false
	var col := slot / 3
	for c in class_info(hero(id)["class"]).get("columns", [0, 1, 2]):
		if int(c) == col:
			return true
	return false


## Place automatiquement une liste de héros : renvoie {case: id}.
static func auto_place(ids: Array) -> Dictionary:
	var order := ["gardien", "guerrier", "assassin", "archer", "mage", "pretre"]
	var sorted := ids.duplicate()
	sorted.sort_custom(func(a: String, b: String) -> bool:
		return order.find(hero(a)["class"]) < order.find(hero(b)["class"]))
	var out := {}
	for id: String in sorted:
		var cols: Array = class_info(hero(id)["class"]).get("columns", [0, 1, 2])
		if hero(id)["class"] == "assassin":
			cols = [2, 1, 0]
		var done := false
		for col: int in cols:
			for row in [1, 0, 2]:
				var s: int = col * 3 + row
				if not out.has(s):
					out[s] = id
					done = true
					break
			if done:
				break
		if not done:
			for s in 9:
				if not out.has(s):
					out[s] = id
					break
	return out


static func status_info(id: String) -> Dictionary:
	return statuses().get(id, {})
