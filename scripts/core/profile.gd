class_name Profile
extends RefCounted
## Profil du joueur : collection, monnaies, reliques et équipement, équipe, progression dans la Tour,
## compteurs du gacha. Pur état + règles de méta-jeu : aucune dépendance à l'affichage.
## Sérialisé en Dictionary (to_dict / from_dict) pour la sauvegarde locale, plus tard le serveur.

const SAVE_VERSION := 1

var owned: Dictionary = {}          # id -> nombre d'exemplaires obtenus
var currencies: Dictionary = {}     # eclat_de_voeu, pieces, fragments_etage
var relics: Array[Dictionary] = []  # reliques avec un "uid"
var next_relic_uid := 1
var equipped: Dictionary = {}       # id du perso -> {"1".."6": uid}
var team: Array[String] = []
var tower_cleared := 0              # plus haut étage gagné
var gacha_state: Dictionary = {}
var energy := 0
var energy_time := 0                # instant (secondes Unix) du dernier point d'énergie compté
var formations: Array = []          # {"team": [ids], "relics": {id: {"1".."6": uid}}} ou {} si vide


static func new_game(now: int = 0) -> Profile:
	var p := Profile.new()
	var cfg := GameData.progression()
	p.energy = int(cfg["energy"]["max"])
	p.energy_time = now if now > 0 else int(Time.get_unix_time_from_system())
	for id: String in cfg["starter_characters"]:
		p.owned[id] = 1
		if p.team.size() < 3:
			p.team.append(id)
	for k: String in cfg["starter_currencies"]:
		p.currencies[k] = int(cfg["starter_currencies"][k])
	return p


# --- Monnaies ---------------------------------------------------------------

func amount(currency: String) -> int:
	return int(currencies.get(currency, 0))


func add(currency: String, n: int) -> void:
	currencies[currency] = amount(currency) + n


func spend(currency: String, n: int) -> bool:
	if amount(currency) < n:
		return false
	currencies[currency] = amount(currency) - n
	return true


# --- Énergie -----------------------------------------------------------------

## Recharge l'énergie écoulée depuis la dernière mise à jour (aussi pendant l'absence du joueur).
func refresh_energy(now: int) -> void:
	var cfg: Dictionary = GameData.progression()["energy"]
	var maxe := int(cfg["max"])
	var period := int(cfg["regen_seconds"])
	if energy >= maxe:
		energy_time = now
		return
	var gained := (now - energy_time) / period
	if gained > 0:
		energy = mini(maxe, energy + gained)
		energy_time = now if energy >= maxe else energy_time + gained * period


## Secondes avant le prochain point d'énergie (0 si plein).
func energy_next_in(now: int) -> int:
	var cfg: Dictionary = GameData.progression()["energy"]
	if energy >= int(cfg["max"]):
		return 0
	return int(cfg["regen_seconds"]) - (now - energy_time)


func floor_cost(number: int) -> int:
	var cfg: Dictionary = GameData.progression()["energy"]
	return 0 if number <= int(cfg["free_floors"]) else int(cfg["floor_cost"])


func spend_energy(n: int, now: int) -> bool:
	refresh_energy(now)
	if energy < n:
		return false
	var cfg: Dictionary = GameData.progression()["energy"]
	if energy >= int(cfg["max"]):
		energy_time = now  # la recharge repart du moment où l'on passe sous le maximum
	energy -= n
	return true


func refund_energy(n: int) -> void:
	energy += n  # peut dépasser le maximum, comme une récompense


# --- Collection et invocation -----------------------------------------------

func owns(id: String) -> bool:
	return int(owned.get(id, 0)) > 0


func owned_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in GameData.characters():
		if owns(id):
			out.append(id)
	return out


## Ajoute le résultat d'une invocation. Les 3★ (recrues) et les doublons deviennent des Fragments d'étage.
## Renvoie {"new": bool, "fragments": int}.
func add_pull(result: Dictionary) -> Dictionary:
	var id: String = result["id"]
	var frag := int(GameData.progression()["duplicate_fragments"][str(result["rarity"])])
	if not GameData.characters().has(id) or owns(id):
		owned[id] = int(owned.get(id, 0)) + 1
		add("fragments_etage", frag)
		return {"new": false, "fragments": frag}
	owned[id] = 1
	return {"new": true, "fragments": 0}


# --- Équipe ------------------------------------------------------------------

func set_team(ids: Array) -> bool:
	if ids.is_empty() or ids.size() > 3:
		return false
	for id: String in ids:
		if not owns(id):
			return false
	team.assign(ids)
	return true


# --- Reliques ----------------------------------------------------------------

func add_relic(r: Dictionary) -> int:
	r["uid"] = next_relic_uid
	next_relic_uid += 1
	relics.append(r)
	return int(r["uid"])


func relic(uid: int) -> Dictionary:
	for r in relics:
		if int(r["uid"]) == uid:
			return r
	return {}


## Personnage qui porte la relique, ou "".
func owner_of(uid: int) -> String:
	for id: String in equipped:
		for slot: String in equipped[id]:
			if int(equipped[id][slot]) == uid:
				return id
	return ""


## Équipe la relique sur le personnage (remplace la pièce du même emplacement, la retire à son ancien porteur).
func equip(char_id: String, uid: int) -> bool:
	var r := relic(uid)
	if r.is_empty() or not owns(char_id):
		return false
	var prev := owner_of(uid)
	if prev != "":
		equipped[prev].erase(str(int(r["slot"])))
	if not equipped.has(char_id):
		equipped[char_id] = {}
	equipped[char_id][str(int(r["slot"]))] = uid
	return true


func unequip(char_id: String, slot: int) -> void:
	if equipped.has(char_id):
		equipped[char_id].erase(str(slot))


func equipped_relics(char_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var slots: Dictionary = equipped.get(char_id, {})
	for slot in range(1, 7):
		if slots.has(str(slot)):
			var r := relic(int(slots[str(slot)]))
			if not r.is_empty():
				out.append(r)
	return out


func relic_level_cost(r: Dictionary) -> int:
	var c: Dictionary = GameData.progression()["relic_level_cost"]
	return int(c["base"]) + int(c["per_level"]) * int(r["level"])


## Monte la relique d'un niveau en payant des Pièces. Renvoie false si impossible.
func level_relic(uid: int, rng: RandomNumberGenerator) -> bool:
	var r := relic(uid)
	if r.is_empty() or int(r["level"]) >= int(GameData.relics()["max_level"]):
		return false
	if not spend("pieces", relic_level_cost(r)):
		return false
	Relics.level_up(rng, r)
	return true


## Pièces investies dans une relique (montées de niveau), rendues au recyclage.
func relic_invested(r: Dictionary) -> int:
	var c: Dictionary = GameData.progression()["relic_level_cost"]
	var total := 0
	for lvl in int(r["level"]):
		total += int(c["base"]) + int(c["per_level"]) * lvl
	return total


## Recyclage intégral (fiche, partie 5) : la relique disparaît, toutes les Pièces investies sont rendues
## (plus une petite base). Renvoie les Pièces gagnées, -1 si la relique n'existe pas.
func recycle_relic(uid: int) -> int:
	var r := relic(uid)
	if r.is_empty():
		return -1
	var owner := owner_of(uid)
	if owner != "":
		unequip(owner, int(r["slot"]))
	for f: Dictionary in formations:
		for id: String in f.get("relics", {}):
			for slot: String in f["relics"][id].keys():
				if int(f["relics"][id][slot]) == uid:
					f["relics"][id].erase(slot)
	var gain := int(GameData.progression()["relic_recycle_base"]) + relic_invested(r)
	relics.erase(r)
	add("pieces", gain)
	return gain


# --- Formations (fiche, partie 4) --------------------------------------------

## Enregistre l'équipe actuelle et ses reliques dans l'emplacement i.
func save_formation(i: int) -> void:
	while formations.size() < int(GameData.progression()["formation_slots"]):
		formations.append({})
	var rel := {}
	for id in team:
		rel[id] = equipped.get(id, {}).duplicate()
	formations[i] = {"team": team.duplicate(), "relics": rel}


## Applique une formation : équipe et reliques (une relique portée ailleurs est déplacée).
func apply_formation(i: int) -> bool:
	if i >= formations.size() or formations[i].is_empty():
		return false
	var f: Dictionary = formations[i]
	if not set_team(f["team"]):
		return false
	for id: String in f["relics"]:
		for slot: String in f["relics"][id]:
			var uid := int(f["relics"][id][slot])
			if not relic(uid).is_empty():
				equip(id, uid)
	return true


## Personnage du joueur prêt pour le combat (reliques appliquées).
func make_unit(char_id: String) -> BattleUnit:
	return Relics.make_unit(char_id, equipped_relics(char_id))


# --- Tour --------------------------------------------------------------------

func can_enter_floor(number: int) -> bool:
	return number >= 1 and number <= mini(tower_cleared + 1, Tower.floor_count())


## Applique une victoire : monnaies et reliques gagnées. Renvoie les récompenses.
func win_floor(number: int, rng: RandomNumberGenerator) -> Dictionary:
	var first := number > tower_cleared
	var rw := Tower.rewards(number, first, rng)
	for k: String in rw["currencies"]:
		add(k, int(rw["currencies"][k]))
	for r: Dictionary in rw["relics"]:
		add_relic(r)
	if first:
		tower_cleared = number
	rw["first_clear"] = first
	return rw


## Balayage (fiche, partie 5) : rejoue un étage déjà gagné sans combat, autant de fois que l'énergie le
## permet (au plus « times »). Renvoie {currencies, relics, times} ; times = 0 si impossible.
func sweep_floor(number: int, times: int, rng: RandomNumberGenerator, now: int) -> Dictionary:
	var out := {"currencies": {}, "relics": [], "times": 0}
	if number > tower_cleared or times <= 0:
		return out
	refresh_energy(now)
	var cost := floor_cost(number)
	if cost > 0:
		times = mini(times, energy / cost)
	for k in times:
		spend_energy(cost, now)
		var rw := Tower.rewards(number, false, rng)
		for c: String in rw["currencies"]:
			add(c, int(rw["currencies"][c]))
			out["currencies"][c] = int(out["currencies"].get(c, 0)) + int(rw["currencies"][c])
		for r: Dictionary in rw["relics"]:
			add_relic(r)
			out["relics"].append(r)
	out["times"] = times
	return out


# --- Sauvegarde ----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION, "owned": owned, "currencies": currencies, "relics": relics,
		"next_relic_uid": next_relic_uid, "equipped": equipped, "team": team,
		"tower_cleared": tower_cleared, "gacha_state": gacha_state,
		"energy": energy, "energy_time": energy_time, "formations": formations,
	}


## Relit une sauvegarde (le JSON rend les entiers en flottants : on les reconvertit).
static func from_dict(d: Dictionary) -> Profile:
	var p := Profile.new()
	for id: String in d.get("owned", {}):
		p.owned[id] = int(d["owned"][id])
	for k: String in d.get("currencies", {}):
		p.currencies[k] = int(d["currencies"][k])
	for r: Dictionary in d.get("relics", []):
		r["uid"] = int(r["uid"])
		r["slot"] = int(r["slot"])
		r["level"] = int(r["level"])
		p.relics.append(r)
	p.next_relic_uid = int(d.get("next_relic_uid", p.relics.size() + 1))
	for id: String in d.get("equipped", {}):
		p.equipped[id] = {}
		for slot: String in d["equipped"][id]:
			p.equipped[id][slot] = int(d["equipped"][id][slot])
	p.team.assign(d.get("team", []))
	p.tower_cleared = int(d.get("tower_cleared", 0))
	p.gacha_state = d.get("gacha_state", {})
	p.energy = int(d.get("energy", GameData.progression()["energy"]["max"]))
	p.energy_time = int(d.get("energy_time", Time.get_unix_time_from_system()))
	for f: Variant in d.get("formations", []):
		var fd: Dictionary = f
		if fd.has("team"):
			var rel := {}
			for id: String in fd["relics"]:
				rel[id] = {}
				for slot: String in fd["relics"][id]:
					rel[id][slot] = int(fd["relics"][id][slot])
			p.formations.append({"team": Array(fd["team"]), "relics": rel})
		else:
			p.formations.append({})
	return p
