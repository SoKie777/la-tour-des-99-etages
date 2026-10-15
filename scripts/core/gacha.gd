class_name Gacha
extends RefCounted
## Invocation façon Dislyte : taux par rareté, garantie Légendaire (pity dur),
## Épique garanti toutes les N invocations, personnage vedette pondéré.

var banner_id: String
var banner: Dictionary
var pity_5 := 0
var pity_4 := 0
var total_pulls := 0
var rng := RandomNumberGenerator.new()


func _init(id: String, seed_value: int = 0) -> void:
	banner_id = id
	banner = GameData.gacha()["banners"][id]
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


func pull() -> Dictionary:
	pity_5 += 1
	pity_4 += 1
	total_pulls += 1
	var rates: Dictionary = banner["rates"]
	var rarity := 3
	var roll := rng.randf() * 100.0
	if pity_5 >= int(banner["hard_pity_5"]):
		rarity = 5
	elif roll < float(rates["5"]):
		rarity = 5
	elif pity_4 >= int(banner["guarantee_4_every"]) or roll < float(rates["5"]) + float(rates["4"]):
		rarity = 4
	if rarity == 5:
		pity_5 = 0
		pity_4 = 0
	elif rarity == 4:
		pity_4 = 0
	return {"rarity": rarity, "id": _pick(rarity), "pulls_since_5": pity_5}


func pull_many(n: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in n:
		out.append(pull())
	return out


func _pick(rarity: int) -> String:
	if rarity == 3:
		var pool: Array = GameData.gacha()["three_star_pool"]
		return pool[rng.randi() % pool.size()]
	var ids: Array[String] = []
	var weights: Array[float] = []
	var featured: Array = banner["featured"]
	for id: String in GameData.characters():
		if int(GameData.character(id)["rarity"]) == rarity:
			ids.append(id)
			weights.append(float(banner["featured_multiplier"]) if featured.has(id) else 1.0)
	return ids[rng.rand_weighted(PackedFloat32Array(weights))]
