class_name Gacha
extends RefCounted
## Invocation façon Dragon Traveler : taux N/R/SR/SSR, SR ou mieux garanti toutes les 10, SSR garanti
## (40 sur la bannière standard, 50 sur la limitée, compteurs séparés et sauvegardés), vedette garantie
## sur la limitée, liste de souhaits sur la standard.

var banner_id: String
var banner: Dictionary
var pity := {}          # clé de compteur -> invocations depuis le dernier SSR
var pity_4 := {}        # clé -> invocations depuis le dernier SR ou mieux
var total_pulls := 0
var wishlist: Array[String] = []
var rng := RandomNumberGenerator.new()


func _init(id: String, seed_value: int = 0) -> void:
	set_banner(id)
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


static func banners() -> Dictionary:
	return GameData.gacha()["banners"]


func set_banner(id: String) -> void:
	banner_id = id
	banner = banners()[id]


func get_state() -> Dictionary:
	return {"pity": pity.duplicate(), "pity_4": pity_4.duplicate(), "total_pulls": total_pulls, "wishlist": wishlist.duplicate()}


func set_state(s: Dictionary) -> void:
	pity = {}
	pity_4 = {}
	for k: String in s.get("pity", {}):
		pity[k] = int(s["pity"][k])
	for k: String in s.get("pity_4", {}):
		pity_4[k] = int(s["pity_4"][k])
	total_pulls = int(s.get("total_pulls", 0))
	wishlist.assign(s.get("wishlist", []))


func key() -> String:
	return str(banner.get("pity_key", banner_id))


func pity_count() -> int:
	return int(pity.get(key(), 0))


func wishlist_open() -> bool:
	return banner.has("wishlist_unlock") and total_pulls >= int(banner["wishlist_unlock"])


func pull() -> Dictionary:
	var k := key()
	pity[k] = int(pity.get(k, 0)) + 1
	pity_4[k] = int(pity_4.get(k, 0)) + 1
	total_pulls += 1
	var rates: Dictionary = banner["rates"]
	var roll := rng.randf() * 100.0
	var rarity := 2
	var acc := 0.0
	for r in [5, 4, 3, 2]:
		acc += float(rates.get(str(r), 0.0))
		if roll < acc:
			rarity = r
			break
	if int(pity[k]) >= int(banner["pity_5"]):
		rarity = 5
	elif rarity < 4 and int(pity_4[k]) >= int(banner["guarantee_4_every"]):
		rarity = 4
	if rarity == 5:
		pity[k] = 0
		pity_4[k] = 0
	elif rarity == 4:
		pity_4[k] = 0
	var id := _pick(rarity)
	return {"rarity": rarity, "id": id, "pity": int(pity[k])}


func pull_many(n: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in n:
		out.append(pull())
	return out


func _pick(rarity: int) -> String:
	var featured: Array = banner.get("featured", [])
	if rarity == 5 and not featured.is_empty() and rng.randf() * 100.0 < float(banner.get("featured_share", 0.0)):
		return str(featured[rng.randi() % featured.size()])
	var f4: Array = banner.get("featured_4", [])
	if rarity == 4 and not f4.is_empty() and rng.randf() * 100.0 < float(banner.get("featured_4_share", 0.0)):
		return str(f4[rng.randi() % f4.size()])
	if rarity == 5 and wishlist_open() and not wishlist.is_empty():
		for w in wishlist:
			if rng.randf() * 100.0 < float(banner.get("wishlist_chance", 20.0)):
				return w
	var ids := HeroDb.ids_of_rarity(rarity)
	return ids[rng.randi() % ids.size()]


## Taux affichés : [{rarity, pct}] et rappel des garanties.
func rates_text() -> Array[String]:
	var out: Array[String] = []
	var names := {5: "SSR", 4: "SR", 3: "R", 2: "N"}
	for r in [5, 4, 3, 2]:
		out.append("%s : %s %%" % [names[r], str(banner["rates"].get(str(r), 0))])
	out.append("SR ou mieux garanti toutes les %d invocations" % int(banner["guarantee_4_every"]))
	out.append("SSR garanti en %d invocations au plus" % int(banner["pity_5"]))
	if not banner.get("featured", []).is_empty():
		out.append("Chaque SSR obtenu est la vedette")
	if banner.has("wishlist_unlock"):
		out.append("Liste de souhaits après %d invocations : %d %% par héros souhaité quand un SSR sort" % [int(banner["wishlist_unlock"]), int(banner["wishlist_chance"])])
	return out
