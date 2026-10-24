class_name Tower
extends RefCounted
## La Tour des 99 Étages (data/tower.json) : étages générés, Élites régulières, un boss à la fin de
## chaque univers. Ennemis au format de RtBattle.


static func cfg() -> Dictionary:
	return GameData.tower()


static func floor_count() -> int:
	return int(cfg()["universes"][-1]["last"])


static func universe_of(number: int) -> Dictionary:
	for u: Dictionary in cfg()["universes"]:
		if number <= int(u["last"]):
			return u
	return cfg()["universes"][-1]


## {number, universe, decor, level, power, elite, boss: id ou ""}
static func floor_info(number: int) -> Dictionary:
	var c := cfg()
	var u := universe_of(number)
	var is_boss := number == int(u["last"])
	var raw_level := int(c["level_base"]) + int(float(c["level_per_floor"]) * number)
	var power := float(c["power_base"]) + float(c["power_per_floor"]) * number
	if raw_level > 100:
		power += float(c["power_over_100"]) * (raw_level - 100)
	var elite := not is_boss and number % int(c["elite_every"]) == 0
	if elite:
		power *= float(c["elite_power"])
	return {"number": number, "universe": u["name"], "decor": str(u.get("boss_decor", u["decor"])) if is_boss else str(u["decor"]),
		"level": mini(100, raw_level), "power": power, "elite": elite, "boss": str(u["boss"]) if is_boss else ""}


static func enemy_specs(number: int) -> Array:
	var f := floor_info(number)
	var lvl := int(f["level"])
	var tier := clampi(number / 12, 0, 8)
	if f["boss"] != "":
		return [{"id": f["boss"], "level": lvl, "star": mini(19, 5 + tier * 2), "slot": 4, "power": float(f["power"])}]
	var rng := RandomNumberGenerator.new()
	rng.seed = 104729 * number + 7
	var pool: Array = universe_of(number)["pool"].duplicate()
	var ids: Array[String] = []
	while ids.size() < 6 and not pool.is_empty():
		ids.append(str(pool.pop_at(rng.randi() % pool.size())))
	var placed := HeroDb.auto_place(ids)
	var out := []
	for slot: int in placed:
		var id: String = placed[slot]
		var r := int(HeroDb.hero(id)["rarity"])
		out.append({"id": id, "level": lvl, "star": mini(HeroDb.max_star(r), HeroDb.start_star(r) + tier + (1 if f["elite"] else 0)),
			"slot": slot, "power": float(f["power"])})
	return out


## {currencies: {id: n}, relics: [relique...]}
static func rewards(number: int, first_clear: bool, rng: RandomNumberGenerator) -> Dictionary:
	var rw: Dictionary = cfg()["rewards"]
	var f := floor_info(number)
	var each: Dictionary = rw["each"]
	var cur := {"pieces": int(each["pieces_base"]) + int(each["pieces_per_floor"]) * number,
		"encre": int(each["encre_base"]) + int(each["encre_per_floor"]) * number}
	if first_clear:
		var first: Dictionary = rw["first"]
		if f["boss"] != "":
			cur["eclat_de_voeu"] = int(first["eclat_de_voeu_boss"])
			cur["essence"] = int(first["essence_boss"])
			cur["sceau_destin"] = int(first["sceau_destin_boss"])
		else:
			cur["eclat_de_voeu"] = int(first["eclat_de_voeu_elite" if f["elite"] else "eclat_de_voeu"])
	var sets: Array = GameData.progression()["relic_drop_sets"]
	var relics: Array[Dictionary] = []
	for i in int(each["relics"]):
		relics.append(Relics.generate(rng, sets[rng.randi() % sets.size()], rng.randi_range(1, 6)))
	return {"currencies": cur, "relics": relics}
