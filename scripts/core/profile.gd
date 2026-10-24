class_name Profile
extends RefCounted
## Profil du joueur (refonte Dragon Traveler) : exemplaires de héros et leurs étoiles, niveaux partagés
## par héros, Résonance de classe, monnaies, reliques, formation sur la grille 3 × 3, campagne,
## Patrouille (revenu hors ligne), Tour, Expédition, compteurs du gacha.
## Pur état + règles de méta-jeu : aucune dépendance à l'affichage. Sérialisé par to_dict / from_dict.

const SAVE_VERSION := 2

var heroes: Array[Dictionary] = []   # exemplaires : {uid, id, star, consumed: [{id, star, at, kind}]}
var next_uid := 1
var levels: Dictionary = {}          # id -> niveau (partagé par tous les exemplaires, comme dans DT)
var class_levels: Dictionary = {}    # classe -> niveau de Résonance (100 et plus)
var currencies: Dictionary = {}
var relics: Array[Dictionary] = []
var next_relic_uid := 1
var equipped: Dictionary = {}        # id du héros -> {"1".."6": uid de relique}
var formation: Dictionary = {}       # case "0".."8" -> id du héros
var presets: Array = []              # formations enregistrées
var campaign_cleared := 0
var patrol_time := 0
var quick_day := 0
var quick_used := 0
var tower_cleared := 0
var tower_stars: Dictionary = {}
var loot: Dictionary = {}
var energy := 0
var energy_time := 0
var gacha_state: Dictionary = {}
var seen_tips: Dictionary = {}
var unseen: Array[String] = []
var grants_received: Array[String] = []
var reset_week := 0
var resets_used := 0
var codex: Dictionary = {}           # id -> meilleure étoile jamais atteinte (Codex des héros)
var challenges: Dictionary = {}      # Défis : id -> {best, kills, day, used}
var dispatch: Dictionary = {}        # Missions : {day, missions: [{..., heroes, start, claimed}]}


static func cfg() -> Dictionary:
	return GameData.progression()


static func new_game(now: int = 0) -> Profile:
	var p := Profile.new()
	var c := cfg()
	var t := now if now > 0 else int(Time.get_unix_time_from_system())
	p.energy = int(c["energy"]["max"])
	p.energy_time = t
	p.patrol_time = t
	for h: Dictionary in c["starter_heroes"]:
		p.add_hero(str(h["id"]), int(h["star"]))
		p.levels[str(h["id"])] = int(c.get("starter_levels", 1))
	for k: String in c["starter_currencies"]:
		p.currencies[k] = int(c["starter_currencies"][k])
	p.unseen.clear()
	p.auto_formation()
	return p


# --- Monnaies ---------------------------------------------------------------

func amount(currency: String) -> int:
	return int(currencies.get(currency, 0))


func add(currency: String, n: int) -> void:
	currencies[currency] = amount(currency) + n


func add_all(d: Dictionary) -> void:
	for k: String in d:
		add(k, int(d[k]))


func spend(currency: String, n: int) -> bool:
	if amount(currency) < n:
		return false
	currencies[currency] = amount(currency) - n
	return true


func can_pay(cost: Dictionary) -> bool:
	for k: String in cost:
		if amount(k) < int(cost[k]):
			return false
	return true


func pay(cost: Dictionary) -> bool:
	if not can_pay(cost):
		return false
	for k: String in cost:
		spend(k, int(cost[k]))
	return true


func apply_grants() -> Array[String]:
	var notes: Array[String] = []
	for g: Dictionary in cfg().get("grants", []):
		if g["id"] in grants_received:
			continue
		add_all(g["currencies"])
		grants_received.append(g["id"])
		notes.append(str(g.get("note", "")))
	return notes


# --- Exemplaires de héros ------------------------------------------------------

func add_hero(id: String, star: int = -1) -> int:
	var h := HeroDb.hero(id)
	if star < 1:
		star = HeroDb.start_star(int(h["rarity"]))
	var inst := {"uid": next_uid, "id": id, "star": star, "consumed": []}
	next_uid += 1
	heroes.append(inst)
	if not levels.has(id):
		levels[id] = 1
	codex_update(id)
	return int(inst["uid"])


func instance(uid: int) -> Dictionary:
	for h in heroes:
		if int(h["uid"]) == uid:
			return h
	return {}


func instances(id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h in heroes:
		if h["id"] == id:
			out.append(h)
	return out


func owns(id: String) -> bool:
	for h in heroes:
		if h["id"] == id:
			return true
	return false


func copies(id: String) -> int:
	return instances(id).size()


## Héros possédés (un par nom), du plus rare au plus commun.
func owned_ids(include_substitutes := false) -> Array[String]:
	var out: Array[String] = []
	for id in HeroDb.playable_ids():
		if owns(id) and (include_substitutes or not HeroDb.hero(id).get("substitute", false)):
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool:
		var ra := int(HeroDb.hero(a)["rarity"])
		var rb := int(HeroDb.hero(b)["rarity"])
		if ra != rb:
			return ra > rb
		return best_star(a) > best_star(b))
	return out


## L'exemplaire le mieux étoilé (celui qui combat, comme dans DT).
func best_uid(id: String) -> int:
	var best := -1
	var star := -1
	for h in instances(id):
		if int(h["star"]) > star:
			star = int(h["star"])
			best = int(h["uid"])
	return best


func best_star(id: String) -> int:
	var b := best_uid(id)
	return int(instance(b)["star"]) if b >= 0 else 0


## Résultat d'une invocation : un exemplaire de plus ; un N déjà possédé devient de la Gelée.
func add_pull(result: Dictionary) -> Dictionary:
	var id: String = result["id"]
	var rarity := int(result.get("rarity", HeroDb.hero(id)["rarity"]))
	if rarity <= 2 and owns(id):
		var g := int(cfg()["n_duplicate_gelee"])
		add("gelee", g)
		return {"new": false, "gelee": g, "uid": -1}
	var is_new := not owns(id)
	var uid := add_hero(id)
	if is_new and not id in unseen:
		unseen.append(id)
	return {"new": is_new, "gelee": 0, "uid": uid}


## Fabrique un Pion d'encre (substitut d'une classe) avec de la Gelée.
func craft_pion(cls: String) -> int:
	var pc: Dictionary = cfg()["pion_craft"]
	var id := HeroDb.substitute_for(cls)
	if id == "" or not spend("gelee", int(pc["gelee"])):
		return -1
	return add_hero(id, int(pc["star"]))


# --- Niveaux ---------------------------------------------------------------

func level(id: String) -> int:
	return int(levels.get(id, 1))


func level_cap(id: String) -> int:
	return HeroDb.max_level_for_star(best_star(id))


## Coût pour passer au niveau suivant : {encre, pieces[, essence]}.
func level_cost(id: String) -> Dictionary:
	var lv := HeroDb.levels()
	var l := level(id)
	if l >= int(lv["max_level"]):
		return {}
	var cost := {"encre": int(lv["xp"][l - 1]), "pieces": int(lv["gold"][l - 1])}
	if lv["essence"].has(str(l)):
		cost["essence"] = int(lv["essence"][str(l)])
	return cost


func can_level(id: String) -> bool:
	return owns(id) and level(id) < level_cap(id) and can_pay(level_cost(id))


func level_up(id: String) -> bool:
	if not can_level(id):
		return false
	pay(level_cost(id))
	levels[id] = level(id) + 1
	if level(id) >= 100 and not class_levels.has(HeroDb.hero(id)["class"]):
		class_levels[HeroDb.hero(id)["class"]] = 100
	return true


## Monte jusqu'à n niveaux (s'arrête au plafond ou faute de ressources). Renvoie le nombre de niveaux gagnés.
func level_up_many(id: String, n: int) -> int:
	var done := 0
	while done < n and level_up(id):
		done += 1
	return done


# --- Résonance de classe (après le niveau 100) --------------------------------------

func class_level(cls: String) -> int:
	return int(class_levels.get(cls, 0))


## Niveau de combat : un héros niveau 100 prend le niveau de sa classe.
func effective_level(id: String) -> int:
	var l := level(id)
	if l >= 100:
		return maxi(100, class_level(HeroDb.hero(id)["class"]))
	return l


func class_cap(cls: String) -> int:
	var res: Dictionary = HeroDb.levels()["resonance"]
	var best := 0
	for id in owned_ids():
		if HeroDb.hero(id)["class"] == cls and level(id) >= 100:
			best = maxi(best, best_star(id))
	var cap := 100
	for k: String in res["cap_by_star"]:
		if best >= int(k):
			cap = maxi(cap, int(res["cap_by_star"][k]))
	var lowest := 100000
	for c: String in class_levels:
		lowest = mini(lowest, int(class_levels[c]))
	if class_levels.size() > 1:
		cap = mini(cap, lowest + int(res["lead"]))
	return mini(cap, int(res["max"]))


func class_level_cost(cls: String) -> Dictionary:
	var res: Dictionary = HeroDb.levels()["resonance"]
	var over := class_level(cls) - 100
	var cost := {"encre": int(res["xp_base"]) + int(res["xp_step"]) * over, "pieces": int(res["gold_base"]) + int(res["gold_step"]) * over}
	if (over + 1) % int(res["essence_every"]) == 0:
		cost["essence"] = int(res["essence"])
	return cost


func can_class_level(cls: String) -> bool:
	return class_levels.has(cls) and class_level(cls) < class_cap(cls) and can_pay(class_level_cost(cls))


func class_level_up(cls: String) -> bool:
	if not can_class_level(cls):
		return false
	pay(class_level_cost(cls))
	class_levels[cls] = class_level(cls) + 1
	return true


# --- Étoiles ---------------------------------------------------------------------

## Exigences pour passer l'exemplaire à l'étoile suivante : {main, main_star, class, class_star} ou {}.
func star_req(uid: int) -> Dictionary:
	var inst := instance(uid)
	if inst.is_empty():
		return {}
	var h := HeroDb.hero(inst["id"])
	var star := int(inst["star"])
	if h.get("substitute", false) and star >= int(HeroDb.stars()["substitute_max_star"]):
		return {}
	if star >= HeroDb.max_star(int(h["rarity"])) or star >= 19:
		return {}
	var tier := HeroDb.star_tier(star)
	var ms := int(tier.get("main_star", -1))
	return {"main": int(tier.get("main", 0)), "main_star": star if ms < 0 else ms,
		"class": int(tier.get("class", 0)), "class_star": int(tier.get("class_star", 6))}


func _is_main_copy(main: Dictionary, other: Dictionary, need_star: int) -> bool:
	if int(other["uid"]) == int(main["uid"]) or int(other["star"]) < need_star:
		return false
	if other["id"] == main["id"]:
		return true
	var oh := HeroDb.hero(other["id"])
	return oh.get("substitute", false) and oh["class"] == HeroDb.hero(main["id"])["class"] \
		and need_star <= int(HeroDb.stars()["substitute_max_star"])


func _is_class_fodder(main: Dictionary, other: Dictionary, need_star: int) -> bool:
	return int(other["uid"]) != int(main["uid"]) and int(other["star"]) >= need_star \
		and HeroDb.hero(other["id"])["class"] == HeroDb.hero(main["id"])["class"]


## Exemplaires utilisables : {main: [uids], class: [uids]} (les moins précieux d'abord).
func fodder_candidates(uid: int) -> Dictionary:
	var req := star_req(uid)
	var main := instance(uid)
	var out := {"main": [], "class": []}
	if req.is_empty():
		return out
	var pool := heroes.duplicate()
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _fodder_value(a) < _fodder_value(b))
	for o: Dictionary in pool:
		if int(req["main"]) > 0 and _is_main_copy(main, o, int(req["main_star"])):
			out["main"].append(int(o["uid"]))
		if int(req["class"]) > 0 and _is_class_fodder(main, o, int(req["class_star"])) and o["id"] != main["id"]:
			out["class"].append(int(o["uid"]))
	return out


## Valeur d'un exemplaire comme fourrage : on sacrifie d'abord les Pions, les doublons, les moins rares.
func _fodder_value(o: Dictionary) -> int:
	var h := HeroDb.hero(o["id"])
	var v := int(h["rarity"]) * 100 + int(o["star"])
	if h.get("substitute", false):
		v -= 1000
	if best_uid(o["id"]) == int(o["uid"]):
		v += 500
		if formation.values().has(o["id"]):
			v += 2000
	return v


## Choix automatique du fourrage (doublons d'abord, Poupées pour les héros de classe). {} si impossible.
func auto_fodder(uid: int) -> Dictionary:
	var req := star_req(uid)
	if req.is_empty():
		return {}
	var cand := fodder_candidates(uid)
	var main_list: Array = cand["main"].slice(0, int(req["main"]))
	if main_list.size() < int(req["main"]):
		return {}
	var cls := str(HeroDb.hero(instance(uid)["id"])["class"])
	var need_class := int(req["class"])
	var dolls := mini(need_class, amount("poupee_" + cls))
	var class_list: Array = []
	for c: int in cand["class"]:
		if class_list.size() >= need_class - dolls:
			break
		if not main_list.has(c) and _fodder_value(instance(c)) < 2000:
			class_list.append(c)
	if class_list.size() + dolls < need_class:
		return {}
	return {"main": main_list, "class": class_list, "dolls": dolls}


func can_star_up(uid: int) -> bool:
	return not auto_fodder(uid).is_empty()


## Monte l'exemplaire d'une étoile en consommant les exemplaires indiqués (et des Poupées).
func star_up(uid: int, main_uids: Array = [], class_uids: Array = [], dolls := -1) -> bool:
	var req := star_req(uid)
	if req.is_empty():
		return false
	if main_uids.is_empty() and class_uids.is_empty() and dolls < 0:
		var auto := auto_fodder(uid)
		if auto.is_empty():
			return false
		main_uids = auto["main"]
		class_uids = auto["class"]
		dolls = int(auto["dolls"])
	dolls = maxi(0, dolls)
	var main := instance(uid)
	var cls := str(HeroDb.hero(main["id"])["class"])
	if main_uids.size() != int(req["main"]) or class_uids.size() + dolls != int(req["class"]) or amount("poupee_" + cls) < dolls:
		return false
	var seen := {}
	for m: int in main_uids:
		if seen.has(m) or not _is_main_copy(main, instance(m), int(req["main_star"])):
			return false
		seen[m] = true
	for c: int in class_uids:
		if seen.has(c) or not _is_class_fodder(main, instance(c), int(req["class_star"])):
			return false
		seen[c] = true
	var at := int(main["star"])
	for m: int in main_uids:
		var o := instance(m)
		main["consumed"].append({"id": o["id"], "star": int(o["star"]), "at": at, "kind": "main"})
		_remove_instance(m)
	for c: int in class_uids:
		var o := instance(c)
		main["consumed"].append({"id": o["id"], "star": int(o["star"]), "at": at, "kind": "class"})
		_remove_instance(c)
	for i in dolls:
		main["consumed"].append({"id": "", "star": int(req["class_star"]), "at": at, "kind": "doll"})
	spend("poupee_" + cls, dolls)
	main["star"] = at + 1
	codex_update(str(main["id"]))
	return true


func _remove_instance(uid: int) -> void:
	var inst := instance(uid)
	if inst.is_empty():
		return
	heroes.erase(inst)
	var id: String = inst["id"]
	if not owns(id):
		for s: String in formation.keys():
			if formation[s] == id:
				formation.erase(s)
		equipped.erase(id)


## Montée rapide (DT) : monte tout ce qui peut l'être jusqu'à 6★, les plus rares d'abord.
func quick_star_up() -> int:
	var n := 0
	var progress := true
	while progress:
		progress = false
		var order := heroes.duplicate()
		order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _fodder_value(a) > _fodder_value(b))
		for h: Dictionary in order:
			if instance(int(h["uid"])).is_empty() or int(h["star"]) >= 6 or HeroDb.hero(h["id"]).get("substitute", false):
				continue
			if int(h["uid"]) != best_uid(h["id"]):
				continue
			if star_up(int(h["uid"])):
				n += 1
				progress = true
				break
	return n


func resets_left(now: int) -> int:
	var week := now / 604800
	if week != reset_week:
		reset_week = week
		resets_used = 0
	return maxi(0, int(HeroDb.stars()["reset"]["free_per_week"]) - resets_used)


## Réinitialisation d'étoiles (DT) : retour à 6★, copies principales rendues à leur étoile, héros de
## classe rendus en Poupées. 5 gratuites par semaine.
func star_reset(uid: int, now: int) -> bool:
	var inst := instance(uid)
	var rs: Dictionary = HeroDb.stars()["reset"]
	if inst.is_empty() or int(inst["star"]) < int(rs["min_star"]) or resets_left(now) <= 0:
		return false
	var cls := str(HeroDb.hero(inst["id"])["class"])
	var keep: Array = []
	for c: Dictionary in inst["consumed"]:
		if int(c["at"]) < 6:
			keep.append(c)
			continue
		if c["kind"] == "main" and str(c["id"]) != "":
			add_hero(str(c["id"]), int(c["star"]))
		else:
			add("poupee_" + cls, 1)
	inst["consumed"] = keep
	inst["star"] = 6
	resets_used += 1
	return true


# --- Codex des héros -------------------------------------------------------------

## Enregistre la meilleure étoile d'un héros ; chaque nouvelle étoile rapporte des Éclats. Renvoie
## le nombre d'étoiles nouvelles.
func codex_update(id: String) -> int:
	if HeroDb.hero(id).get("substitute", false):
		return 0
	var before := int(codex.get(id, 0))
	var now_star := best_star(id)
	if now_star <= before:
		return 0
	codex[id] = now_star
	add("eclat_de_voeu", (now_star - before) * int(cfg()["codex"]["eclats_per_star"]))
	return now_star - before


func codex_stars() -> int:
	var n := 0
	for id: String in codex:
		n += int(codex[id])
	return n


## Bonus de compte appliqué à tous les héros en combat (Codex).
func account_bonus() -> Dictionary:
	var pct := codex_stars() * float(cfg()["codex"]["pct_per_star"])
	return {"atk_pct": pct, "hp_pct": pct}


# --- Défis (Conquête des mythes) ---------------------------------------------------

func challenge_state(id: String) -> Dictionary:
	if not challenges.has(id):
		challenges[id] = {"best": 0, "kills": 0, "day": 0, "used": 0}
	return challenges[id]


func challenge_attempts(id: String, now: int) -> int:
	var st := challenge_state(id)
	var day := now / 86400
	if int(st["day"]) != day:
		st["day"] = day
		st["used"] = 0
	return maxi(0, int(Challenges.cfg()["daily"]) - int(st["used"]))


## Victoire à un palier : la première victoire d'un palier donne sa récompense (sans essai consommé,
## comme dans DT). Ralliement : récompense selon le score, record gardé, un essai consommé.
func win_challenge(id: String, tier: int, kills: int, now: int) -> Dictionary:
	var st := challenge_state(id)
	var c := Challenges.info(id)
	if c.has("reward_per_kill"):
		if challenge_attempts(id, now) <= 0:
			return {}
		st["used"] = int(st["used"]) + 1
		st["kills"] = maxi(int(st["kills"]), kills)
		st["best"] = 1
		var rw := Challenges.reward(id, 1, kills)
		add_all(rw)
		return rw
	if tier != int(st["best"]) + 1:
		return {}
	st["best"] = tier
	var out := Challenges.reward(id, tier, 0, now)
	add_all(out)
	return out


## Balayage : récompense du meilleur palier (ou du meilleur score), un essai consommé.
func sweep_challenge(id: String, now: int) -> Dictionary:
	var st := challenge_state(id)
	if int(st["best"]) <= 0 or challenge_attempts(id, now) <= 0:
		return {}
	st["used"] = int(st["used"]) + 1
	var rw := Challenges.reward(id, int(st["best"]), int(st["kills"]), now)
	add_all(rw)
	return rw


# --- Missions (Dispatch) --------------------------------------------------------------

## Missions du jour ; les missions en cours d'un jour passé restent jusqu'à leur récolte.
func dispatch_missions(now: int) -> Array:
	var day := now / 86400
	if int(dispatch.get("day", -1)) != day:
		var keep := []
		for m: Dictionary in dispatch.get("missions", []):
			if int(m.get("start", 0)) > 0 and not m.get("claimed", false):
				keep.append(m)
		for m: Dictionary in Dispatch.missions_of_day(day):
			m["heroes"] = []
			m["start"] = 0
			m["claimed"] = false
			keep.append(m)
		dispatch = {"day": day, "missions": keep}
	return dispatch["missions"]


func dispatch_busy() -> Dictionary:
	var busy := {}
	for m: Dictionary in dispatch.get("missions", []):
		if int(m.get("start", 0)) > 0 and not m.get("claimed", false):
			for h: String in m["heroes"]:
				busy[h] = true
	return busy


## Héros proposés pour une mission : les moins puissants qui remplissent la condition (les meilleurs
## restent libres), [] s'il n'y en a pas assez.
func dispatch_pick(m: Dictionary) -> Array[String]:
	var busy := dispatch_busy()
	var pool: Array[String] = []
	for id in owned_ids():
		if not busy.has(id) and Dispatch.fits(m, id, best_star(id)):
			pool.append(id)
	pool.sort_custom(func(a: String, b: String) -> bool: return hero_power(a) < hero_power(b))
	if pool.size() < int(m["count"]):
		return []
	return pool.slice(0, int(m["count"]))


func dispatch_start(i: int, now: int) -> bool:
	var ms := dispatch_missions(now)
	if i >= ms.size() or int(ms[i]["start"]) > 0:
		return false
	var team := dispatch_pick(ms[i])
	if team.is_empty():
		return false
	ms[i]["heroes"] = team
	ms[i]["start"] = now
	return true


## Secondes avant la fin d'une mission (-1 si elle n'est pas lancée).
func dispatch_left(m: Dictionary, now: int) -> int:
	if int(m.get("start", 0)) <= 0:
		return -1
	return maxi(0, int(m["start"]) + int(float(m["hours"]) * 3600.0) - now)


func dispatch_claim(i: int, now: int) -> Dictionary:
	var ms := dispatch_missions(now)
	if i >= ms.size() or ms[i].get("claimed", false) or dispatch_left(ms[i], now) != 0:
		return {}
	ms[i]["claimed"] = true
	var rw: Dictionary = ms[i]["reward"]
	add_all(rw)
	return rw


# --- Formation (grille 3 × 3) ------------------------------------------------------

func deploy_max() -> int:
	return Campaign.deploy_slots(campaign_cleared)


func formation_ids() -> Array[String]:
	var out: Array[String] = []
	for s in 9:
		if formation.has(str(s)):
			out.append(str(formation[str(s)]))
	return out


func slot_of(id: String) -> int:
	for s: String in formation:
		if formation[s] == id:
			return int(s)
	return -1


## Place un héros (ou "" pour vider la case). Refuse les placements interdits par la classe,
## les doublons et le dépassement du nombre de cases débloquées.
func set_slot(slot: int, id: String) -> bool:
	var key := str(slot)
	if id == "":
		formation.erase(key)
		return true
	if not owns(id) or not HeroDb.can_place(id, slot):
		return false
	var prev := slot_of(id)
	if prev >= 0:
		formation.erase(str(prev))
	elif not formation.has(key) and formation.size() >= deploy_max():
		return false
	formation[key] = id
	return true


## Formation automatique : les héros les plus puissants, placés selon leur classe.
func auto_formation() -> void:
	var ids := owned_ids()
	ids.sort_custom(func(a: String, b: String) -> bool: return hero_power(a) > hero_power(b))
	ids = ids.slice(0, deploy_max())
	formation = {}
	var placed := HeroDb.auto_place(ids)
	for s: int in placed:
		formation[str(s)] = placed[s]


func hero_stats(id: String) -> Dictionary:
	var s := HeroDb.stats(id, effective_level(id), best_star(id), equipped_relics(id))
	var b := account_bonus()
	s["atk"] *= 1.0 + float(b["atk_pct"]) / 100.0
	s["hp"] *= 1.0 + float(b["hp_pct"]) / 100.0
	return s


func hero_power(id: String) -> int:
	return HeroDb.power_of(hero_stats(id))


func team_power() -> int:
	var p := 0
	for id in formation_ids():
		p += hero_power(id)
	return p


## Équipe du joueur prête pour RtBattle.
func battle_specs() -> Array:
	var out := []
	for s in 9:
		var key := str(s)
		if formation.has(key):
			var id: String = formation[key]
			out.append({"id": id, "level": effective_level(id), "star": best_star(id), "gear": equipped_relics(id), "slot": s,
				"bonus": account_bonus()})
	return out


# --- Campagne et Patrouille -------------------------------------------------------

func next_stage() -> int:
	return mini(campaign_cleared + 1, Campaign.stage_count())


func win_stage(n: int, now: int) -> Dictionary:
	var out := {"first": false, "currencies": {}}
	if n != campaign_cleared + 1:
		return out
	claim_patrol(now)  # le revenu accumulé est compté au taux d'avant la victoire
	campaign_cleared = n
	var rw := Campaign.first_rewards(n)
	add_all(rw)
	out["first"] = true
	out["currencies"] = rw
	return out


func patrol_minutes(now: int) -> float:
	var cap := float(Campaign.cfg()["patrol"]["cap_hours"]) * 60.0
	return clampf(float(now - patrol_time) / 60.0, 0.0, cap)


func patrol_pending(now: int) -> Dictionary:
	var rate := Campaign.patrol_rate(campaign_cleared)
	var m := patrol_minutes(now)
	var out := {}
	for k: String in rate:
		var v := int(floor(float(rate[k]) * m))
		if v > 0:
			out[k] = v
	return out


func claim_patrol(now: int) -> Dictionary:
	var got := patrol_pending(now)
	add_all(got)
	patrol_time = now
	return got


func quick_price(now: int) -> int:
	var day := now / 86400
	if day != quick_day:
		quick_day = day
		quick_used = 0
	var prices: Array = Campaign.cfg()["patrol"]["quick_prices"]
	return int(prices[mini(quick_used, prices.size() - 1)]) if quick_used < prices.size() else -1


func quick_patrol(now: int) -> Dictionary:
	var price := quick_price(now)
	if price < 0 or not spend("eclat_de_voeu", price):
		return {}
	quick_used += 1
	var rate := Campaign.patrol_rate(campaign_cleared)
	var m := float(Campaign.cfg()["patrol"]["quick_hours"]) * 60.0
	var out := {}
	for k: String in rate:
		out[k] = int(floor(float(rate[k]) * m))
	add_all(out)
	return out


# --- Énergie (Expédition) ------------------------------------------------------------

func refresh_energy(now: int) -> void:
	var c: Dictionary = cfg()["energy"]
	var maxe := int(c["max"])
	var period := int(c["regen_seconds"])
	if energy >= maxe:
		energy_time = now
		return
	var gained := (now - energy_time) / period
	if gained > 0:
		energy = mini(maxe, energy + gained)
		energy_time = now if energy >= maxe else energy_time + gained * period


func energy_next_in(now: int) -> int:
	var c: Dictionary = cfg()["energy"]
	if energy >= int(c["max"]):
		return 0
	return int(c["regen_seconds"]) - (now - energy_time)


func spend_energy(n: int, now: int) -> bool:
	refresh_energy(now)
	if energy < n:
		return false
	if energy >= int(cfg()["energy"]["max"]):
		energy_time = now
	energy -= n
	return true


func refund_energy(n: int) -> void:
	energy += n


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


func owner_of(uid: int) -> String:
	for id: String in equipped:
		for slot: String in equipped[id]:
			if int(equipped[id][slot]) == uid:
				return id
	return ""


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
	var c: Dictionary = cfg()["relic_level_cost"]
	return int(c["base"]) + int(c["per_level"]) * int(r["level"])


func level_relic(uid: int, rng: RandomNumberGenerator) -> bool:
	var r := relic(uid)
	if r.is_empty() or int(r["level"]) >= int(GameData.relics()["max_level"]):
		return false
	if not spend("pieces", relic_level_cost(r)):
		return false
	Relics.level_up(rng, r)
	return true


func relic_invested(r: Dictionary) -> int:
	var c: Dictionary = cfg()["relic_level_cost"]
	var total := 0
	for lvl in int(r["level"]):
		total += int(c["base"]) + int(c["per_level"]) * lvl
	return total


func recycle_relic(uid: int) -> int:
	var r := relic(uid)
	if r.is_empty():
		return -1
	var owner := owner_of(uid)
	if owner != "":
		unequip(owner, int(r["slot"]))
	var gain := int(cfg()["relic_recycle_base"]) + relic_invested(r)
	relics.erase(r)
	add("pieces", gain)
	return gain


# --- Formations enregistrées --------------------------------------------------------

func save_preset(i: int) -> void:
	while presets.size() < int(cfg()["formation_slots"]):
		presets.append({})
	presets[i] = {"formation": formation.duplicate()}


func apply_preset(i: int) -> bool:
	if i >= presets.size() or presets[i].is_empty():
		return false
	var f: Dictionary = presets[i]["formation"]
	formation = {}
	for s: String in f:
		set_slot(int(s), str(f[s]))
	return true


# --- Tour et Expédition ---------------------------------------------------------------

func win_floor(number: int, rng: RandomNumberGenerator) -> Dictionary:
	var first := number > tower_cleared
	var rw := Tower.rewards(number, first, rng)
	add_all(rw["currencies"])
	for r: Dictionary in rw["relics"]:
		add_relic(r)
	if first:
		tower_cleared = number
	rw["first_clear"] = first
	return rw


func loot_state(id: String) -> Dictionary:
	if not loot.has(id):
		loot[id] = {"unlocked": 0, "wins": 0, "pity": 0, "pity_set": LootBoss.boss(id)["sets"][0]}
	return loot[id]


func win_loot(id: String, diff: int, rng: RandomNumberGenerator) -> Dictionary:
	var st := loot_state(id)
	st["wins"] = int(st["wins"]) + 1
	st["pity"] = int(st["pity"]) + 1
	var forced := ""
	if int(st["pity"]) >= int(LootBoss.cfg()["pity_wins"]):
		forced = st["pity_set"]
		st["pity"] = 0
	var rw := LootBoss.rewards(id, diff, rng, forced)
	add_all(rw["currencies"])
	for r: Dictionary in rw["relics"]:
		add_relic(r)
	if diff == int(st["unlocked"]) and diff + 1 < LootBoss.difficulty_count():
		st["unlocked"] = diff + 1
		rw["unlocked"] = diff + 1
	rw["pity_used"] = forced
	return rw


# --- Sauvegarde ----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION, "heroes": heroes, "next_uid": next_uid, "levels": levels,
		"class_levels": class_levels, "currencies": currencies, "relics": relics, "next_relic_uid": next_relic_uid,
		"equipped": equipped, "formation": formation, "presets": presets, "campaign_cleared": campaign_cleared,
		"patrol_time": patrol_time, "quick_day": quick_day, "quick_used": quick_used, "tower_cleared": tower_cleared,
		"tower_stars": tower_stars, "loot": loot, "energy": energy, "energy_time": energy_time,
		"gacha_state": gacha_state, "seen_tips": seen_tips, "unseen": unseen, "grants_received": grants_received,
		"reset_week": reset_week, "resets_used": resets_used, "codex": codex, "challenges": challenges,
		"dispatch": dispatch,
	}


## Relit une sauvegarde v2 ; une sauvegarde plus ancienne (avant la refonte) donne null : nouvelle partie.
static func from_dict(d: Dictionary) -> Profile:
	if int(d.get("version", 1)) < SAVE_VERSION:
		return null
	var p := Profile.new()
	for h: Dictionary in d.get("heroes", []):
		if not HeroDb.exists(str(h["id"])):
			continue
		var cons: Array = []
		for c: Dictionary in h.get("consumed", []):
			cons.append({"id": str(c["id"]), "star": int(c["star"]), "at": int(c["at"]), "kind": str(c["kind"])})
		p.heroes.append({"uid": int(h["uid"]), "id": str(h["id"]), "star": int(h["star"]), "consumed": cons})
	p.next_uid = int(d.get("next_uid", p.heroes.size() + 1))
	for k: String in d.get("levels", {}):
		p.levels[k] = int(d["levels"][k])
	for k: String in d.get("class_levels", {}):
		p.class_levels[k] = int(d["class_levels"][k])
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
	for s: String in d.get("formation", {}):
		if HeroDb.exists(str(d["formation"][s])):
			p.formation[s] = str(d["formation"][s])
	p.presets = d.get("presets", [])
	p.campaign_cleared = int(d.get("campaign_cleared", 0))
	p.patrol_time = int(d.get("patrol_time", Time.get_unix_time_from_system()))
	p.quick_day = int(d.get("quick_day", 0))
	p.quick_used = int(d.get("quick_used", 0))
	p.tower_cleared = int(d.get("tower_cleared", 0))
	for k: String in d.get("tower_stars", {}):
		p.tower_stars[k] = int(d["tower_stars"][k])
	for id: String in d.get("loot", {}):
		var ls: Dictionary = d["loot"][id]
		p.loot[id] = {"unlocked": int(ls.get("unlocked", 0)), "wins": int(ls.get("wins", 0)), "pity": int(ls.get("pity", 0)),
			"pity_set": str(ls.get("pity_set", ""))}
	p.energy = int(d.get("energy", cfg()["energy"]["max"]))
	p.energy_time = int(d.get("energy_time", Time.get_unix_time_from_system()))
	p.gacha_state = d.get("gacha_state", {})
	for k: String in d.get("seen_tips", {}):
		p.seen_tips[k] = true
	p.unseen.assign(d.get("unseen", []))
	p.grants_received.assign(d.get("grants_received", []))
	p.reset_week = int(d.get("reset_week", 0))
	p.resets_used = int(d.get("resets_used", 0))
	for k: String in d.get("codex", {}):
		p.codex[k] = int(d["codex"][k])
	for k: String in d.get("challenges", {}):
		var c: Dictionary = d["challenges"][k]
		p.challenges[k] = {"best": int(c.get("best", 0)), "kills": int(c.get("kills", 0)), "day": int(c.get("day", 0)), "used": int(c.get("used", 0))}
	var dsp: Dictionary = d.get("dispatch", {})
	if not dsp.is_empty():
		var ms := []
		for m: Dictionary in dsp.get("missions", []):
			var heroes_out: Array = []
			for h in m.get("heroes", []):
				heroes_out.append(str(h))
			var rw := {}
			for k: String in m.get("reward", {}):
				rw[k] = int(m["reward"][k])
			ms.append({"tid": str(m["tid"]), "name": str(m["name"]), "hours": float(m["hours"]), "count": int(m["count"]),
				"min_star": int(m["min_star"]), "kind": str(m["kind"]), "key": str(m["key"]), "reward": rw, "heroes": heroes_out,
				"start": int(m.get("start", 0)), "claimed": bool(m.get("claimed", false))})
		p.dispatch = {"day": int(dsp.get("day", 0)), "missions": ms}
	for id in p.owned_ids():
		if not p.codex.has(id):
			p.codex[id] = p.best_star(id)
	return p
