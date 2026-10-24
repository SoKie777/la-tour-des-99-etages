class_name Campaign
extends RefCounted
## Campagne principale (data/campaign.json) : 8 chapitres, étapes numérotées de 1 à stage_count().
## Génère les équipes ennemies (déterministe pour une étape donnée), les récompenses de première
## victoire et le revenu de Patrouille (idle) selon la progression.


static func cfg() -> Dictionary:
	return HeroDb._json("campaign")


static func chapters() -> Array:
	return cfg()["chapters"]


static func stage_count() -> int:
	var n := 0
	for c: Dictionary in chapters():
		n += int(c["stages"])
	return n


## {chapter: Dictionary, chapter_index, index (1..stages), number "1-3", level, boss: bool, decor}
static func stage_info(n: int) -> Dictionary:
	var start := 1
	var chs := chapters()
	for ci in chs.size():
		var c: Dictionary = chs[ci]
		var count := int(c["stages"])
		if n < start + count:
			var idx := n - start + 1
			var t := float(idx - 1) / maxf(1.0, float(count - 1))
			var lvl := int(round(lerpf(float(c["level_from"]), float(c["level_to"]), t)))
			var boss := idx == count and c.has("boss")
			return {"chapter": c, "chapter_index": ci, "index": idx, "number": "%d-%d" % [ci + 1, idx], "level": lvl,
				"boss": boss, "decor": str(c.get("boss_decor", c["decor"])) if boss else str(c["decor"]), "progress": t,
				"name": c["name"]}
		start += count
	return {}


static func enemy_specs(n: int) -> Array:
	var info := stage_info(n)
	if info.is_empty():
		return []
	var c: Dictionary = info["chapter"]
	var lvl := int(info["level"])
	var t := float(info["progress"])
	var p: Dictionary = cfg()["power"]
	var power := lerpf(float(p["from"]), float(p["to"]), t)
	if info["boss"]:
		var bid := str(c["boss"])
		var boss_star := 5 + int(info["chapter_index"])
		return [{"id": bid, "level": lvl, "star": mini(19, boss_star), "slot": 4, "power": float(cfg()["boss_power"]) * (0.8 + 0.05 * int(info["chapter_index"]))}]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * n + 13
	var size_range: Array = c["team_size"]
	var size := int(round(lerpf(float(size_range[0]), float(size_range[1]), t)))
	var pool: Array = c["pool"].duplicate()
	var ids: Array[String] = []
	while ids.size() < size and not pool.is_empty():
		ids.append(str(pool.pop_at(rng.randi() % pool.size())))
	var extra := int(info["chapter_index"]) / 2 + (int(cfg()["star_bonus_end"]) if t > 0.7 else 0)
	var placed := HeroDb.auto_place(ids)
	var out := []
	for slot: int in placed:
		var id: String = placed[slot]
		var r := int(HeroDb.hero(id)["rarity"])
		var star := mini(HeroDb.max_star(r), HeroDb.start_star(r) + extra)
		out.append({"id": id, "level": lvl, "star": star, "slot": slot, "power": power})
	return out


static func first_rewards(n: int) -> Dictionary:
	var info := stage_info(n)
	var f: Dictionary = cfg()["first"]
	var lvl := int(info.get("level", 1))
	var out := {
		"eclat_de_voeu": int(f["eclat_de_voeu"]),
		"pieces": int(f["pieces_per_level"]) * lvl + 200,
		"encre": int(f["encre_per_level"]) * lvl + 100,
	}
	if info.get("boss", false):
		out["eclat_de_voeu"] += int(f["boss_eclats"])
		out["essence"] = 40 + lvl * 2
	if n % int(f["ticket_every"]) == 0:
		out["sceau"] = 1
	return out


## Revenu de Patrouille par minute selon le nombre d'étapes gagnées.
static func patrol_rate(cleared: int) -> Dictionary:
	var pt: Dictionary = cfg()["patrol"]
	var s := maxi(int(pt["min_stage"]), cleared)
	return {
		"pieces": float(pt["gold"]) + float(pt["gold_per_stage"]) * s,
		"encre": float(pt["encre"]) + float(pt["encre_per_stage"]) * s,
		"essence": float(pt["essence_per_stage"]) * s / float(pt["essence_every"]) * 10.0,
	}


static func unlocked(key: String, cleared: int) -> bool:
	return cleared >= int(cfg()["unlocks"].get(key, 0))


## Nombre de héros déployables selon la progression (3 au départ, puis 4, 5 et 6).
static func deploy_slots(cleared: int) -> int:
	var n := 3
	for k in ["slot_4", "slot_5", "slot_6"]:
		if unlocked(k, cleared):
			n += 1
	return n
