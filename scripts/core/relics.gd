class_name Relics
extends RefCounted
## Reliques (équipement) : génération, montée de niveau, bonus de sets
## et calcul des stats finales d'un personnage équipé.
## Une relique : {set, slot, level, main: {stat, value}, subs: {stat: value}}


static func generate(rng: RandomNumberGenerator, set_id: String, slot: int) -> Dictionary:
	var cfg := GameData.relics()
	var mains: Array = cfg["slots"][str(slot)]
	var main_stat: String = mains[rng.randi() % mains.size()]
	var relic := {"set": set_id, "slot": slot, "level": 0, "main": {"stat": main_stat, "value": 0.0}, "subs": {}}
	_update_main(relic)
	for i in 3:
		_add_or_boost_sub(rng, relic)
	return relic


## Monte une relique d'un niveau. Aux paliers (+3, +6...), une stat secondaire est ajoutée ou renforcée.
static func level_up(rng: RandomNumberGenerator, relic: Dictionary) -> void:
	var cfg := GameData.relics()
	if relic["level"] >= int(cfg["max_level"]):
		return
	relic["level"] += 1
	_update_main(relic)
	if cfg["substat_milestones"].any(func(m: float) -> bool: return int(m) == int(relic["level"])):
		_add_or_boost_sub(rng, relic)


## Nombre d'activations de chaque set (un set de 2 porté en 4 pièces s'active 2 fois).
static func active_sets(equipped: Array) -> Dictionary:
	var sets: Dictionary = GameData.relics()["sets"]
	var counts := {}
	for r: Dictionary in equipped:
		counts[r["set"]] = counts.get(r["set"], 0) + 1
	var active := {}
	for s: String in counts:
		var n: int = counts[s] / int(sets[s]["size"])
		if n > 0:
			active[s] = n
	return active


## Stats finales = base du personnage + reliques + sets. Renvoie {stats, specials}.
static func apply(base_stats: Dictionary, equipped: Array) -> Dictionary:
	var flat := {}
	var pct := {}
	var add := func(stat_name: String, v: float) -> void:
		if stat_name.ends_with("_pct"):
			var key := stat_name.trim_suffix("_pct")
			pct[key] = pct.get(key, 0.0) + v
		else:
			flat[stat_name] = flat.get(stat_name, 0.0) + v
	for r: Dictionary in equipped:
		add.call(r["main"]["stat"], float(r["main"]["value"]))
		for s: String in r["subs"]:
			add.call(s, float(r["subs"][s]))
	var specials: Array[String] = []
	var sets: Dictionary = GameData.relics()["sets"]
	var active := active_sets(equipped)
	for s: String in active:
		for stat_name: String in sets[s]["bonus"]:
			add.call(stat_name, float(sets[s]["bonus"][stat_name]) * active[s])
		if sets[s].has("special"):
			specials.append(sets[s]["special"])
	var out := {}
	for k: String in base_stats:
		var v := float(base_stats[k])
		if k in ["hp", "atk", "def", "spd"]:
			v = v * (1.0 + pct.get(k, 0.0) / 100.0)
		out[k] = v + flat.get(k, 0.0)
	return {"stats": out, "specials": specials}


## Construit un BattleUnit équipé, prêt pour BattleEngine.new([...], [...]).
static func make_unit(char_id: String, equipped: Array) -> BattleUnit:
	var data := GameData.character(char_id)
	var result := apply(data["stats"], equipped)
	var u := BattleUnit.new(data, 0, 0, result["stats"])
	u.set_specials = result["specials"]
	return u


static func _update_main(relic: Dictionary) -> void:
	var cfg := GameData.relics()
	var maxv := float(cfg["main_stat_max"][relic["main"]["stat"]])
	# 20 % de la valeur max au niveau 0, 100 % au niveau max.
	relic["main"]["value"] = roundf(maxv * (0.2 + 0.8 * float(relic["level"]) / float(cfg["max_level"])))


static func _add_or_boost_sub(rng: RandomNumberGenerator, relic: Dictionary) -> void:
	var cfg := GameData.relics()
	var subs: Dictionary = relic["subs"]
	var stat_name: String
	if subs.size() < 4:
		var pool: Array = cfg["substat_pool"].filter(func(s: String) -> bool:
			return s != relic["main"]["stat"] and not subs.has(s))
		stat_name = pool[rng.randi() % pool.size()]
	else:
		stat_name = subs.keys()[rng.randi() % subs.size()]
	var roll_range: Array = cfg["substat_roll"][stat_name]
	subs[stat_name] = subs.get(stat_name, 0.0) + float(rng.randi_range(int(roll_range[0]), int(roll_range[1])))
