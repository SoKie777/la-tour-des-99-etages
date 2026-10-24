class_name Dispatch
extends RefCounted
## Missions (« Dispatch » de Dragon Traveler, data/dispatch.json) : missions du jour tirées au sort,
## conditions de classe ou de faction et d'étoiles, durée réelle, récompense à la récolte.


static func cfg() -> Dictionary:
	return HeroDb._json("dispatch")


## Missions du jour (déterministes pour un jour donné) : [{tid, name, hours, count, min_star, kind, key, reward}].
static func missions_of_day(day: int) -> Array:
	var c := cfg()
	var rng := RandomNumberGenerator.new()
	rng.seed = 92821 * day + 3
	var tpl: Array = c["templates"].duplicate()
	var out := []
	for i in mini(int(c["per_day"]), tpl.size()):
		var t: Dictionary = tpl.pop_at(rng.randi() % tpl.size())
		var keys: Array = HeroDb.class_order() if t["kind"] == "class" else HeroDb.faction_order()
		var key := str(keys[rng.randi() % keys.size()])
		var reward: Dictionary = {}
		for k: String in t["reward"]:
			reward[k] = int(t["reward"][k])
		if reward.has("poupee"):
			var cls := key if t["kind"] == "class" else str(HeroDb.class_order()[rng.randi() % HeroDb.class_order().size()])
			reward["poupee_" + cls] = reward["poupee"]
			reward.erase("poupee")
		out.append({"tid": t["name"], "name": t["name"], "hours": float(t["hours"]), "count": int(t["count"]), "min_star": int(t["min_star"]),
			"kind": t["kind"], "key": key, "reward": reward})
	return out


static func fits(m: Dictionary, hero_id: String, star: int) -> bool:
	if star < int(m["min_star"]):
		return false
	var h := HeroDb.hero(hero_id)
	if m["kind"] == "class":
		return h["class"] == m["key"]
	return h["factions"].has(m["key"])
