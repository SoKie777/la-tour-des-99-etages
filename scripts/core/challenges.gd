class_name Challenges
extends RefCounted
## Défis (« Conquête des mythes » de Dragon Traveler, data/challenges.json) : équipes à classes
## imposées, paliers de difficulté en vagues, balayage quotidien ; Ralliement au score.


static func cfg() -> Dictionary:
	return HeroDb._json("challenges")


static func ids() -> Array:
	return cfg()["challenges"].keys()


static func info(id: String) -> Dictionary:
	return cfg()["challenges"][id]


## Classes autorisées (Épreuve de la déesse : selon le jour de la semaine, 0 = dimanche).
static func classes_for(id: String, now := -1) -> Array:
	var c := info(id)
	if c.has("by_weekday"):
		var t := now if now >= 0 else int(Time.get_unix_time_from_system())
		var wd := int(Time.get_datetime_dict_from_unix_time(t)["weekday"])
		return c["by_weekday"][str(wd)]
	return c.get("classes", [])


static func allowed(id: String, hero_id: String, now := -1) -> bool:
	var c := info(id)
	if c.get("one_per_class", false):
		return true
	return classes_for(id, now).has(HeroDb.hero(hero_id)["class"])


## Équipe imposée : les plus puissants des héros autorisés, placés selon leur classe.
static func team_specs(id: String, p: Profile, now := -1) -> Array:
	var c := info(id)
	var ids: Array[String] = []
	var by_power := p.owned_ids(true)
	by_power.sort_custom(func(a: String, b: String) -> bool: return p.hero_power(a) > p.hero_power(b))
	if c.get("one_per_class", false):
		var used := {}
		for h in by_power:
			var cls := str(HeroDb.hero(h)["class"])
			if not used.has(cls):
				used[cls] = true
				ids.append(h)
	else:
		for h in by_power:
			if allowed(id, h, now):
				ids.append(h)
	ids = ids.slice(0, p.deploy_max())
	var placed := HeroDb.auto_place(ids)
	var out := []
	for s: int in placed:
		var h: String = placed[s]
		out.append({"id": h, "level": p.effective_level(h), "star": p.best_star(h), "gear": p.equipped_relics(h), "slot": s,
			"bonus": p.account_bonus()})
	return out


## Vagues ennemies d'un palier (1..tiers).
static func waves(id: String, tier: int) -> Array:
	var c := info(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + tier * 7907
	var lvl := mini(100, int(c["level_base"]) + int(c["level_step"]) * (tier - 1))
	var power := float(c["power_base"]) + float(c["power_step"]) * (tier - 1)
	var size_range: Array = c["wave_size"]
	var out := []
	for w in int(c["waves"]):
		var t := float(w) / maxf(1.0, float(int(c["waves"]) - 1))
		var size := int(round(lerpf(float(size_range[0]), float(size_range[1]), t)))
		var pool: Array = c["pool"].duplicate()
		var ids: Array[String] = []
		while ids.size() < size and not pool.is_empty():
			ids.append(str(pool.pop_at(rng.randi() % pool.size())))
		var placed := HeroDb.auto_place(ids)
		var wave := []
		for s: int in placed:
			var h: String = placed[s]
			var r := int(HeroDb.hero(h)["rarity"])
			wave.append({"id": h, "level": lvl, "star": mini(HeroDb.max_star(r), HeroDb.start_star(r) + tier / 4), "slot": s, "power": power})
		out.append(wave)
	return out


## Options de combat d'un Défi (vagues, durée, score).
static func battle_options(id: String) -> Dictionary:
	var c := info(id)
	var w := waves(id, 1)
	var o := {"waves": w.slice(1)}
	if c.has("duration"):
		o = {"waves": w, "endless": {"growth": float(c.get("growth", 0.15))}, "time_limit": float(c["duration"]), "timeout_winner": 0}
	return o


static func reward(id: String, tier: int, kills := 0, now := -1) -> Dictionary:
	var c := info(id)
	var out := {}
	if c.has("reward_per_kill"):
		for k: String in c["reward_per_kill"]:
			out[k] = int(c["reward_per_kill"][k]) * kills
		return out
	var r: Dictionary = c["reward"]
	for k: String in r:
		if not k.ends_with("_per_tier"):
			var key := k
			if k == "poupee":  # Poupées de la 1re classe du jour
				key = "poupee_" + str(classes_for(id, now)[0])
			out[key] = int(float(r[k]) + float(r.get(k + "_per_tier", 0)) * (tier - 1))
	return out
