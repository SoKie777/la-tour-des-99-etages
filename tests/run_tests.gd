extends SceneTree
## Tests des règles de la refonte temps réel + simulations d'équilibrage, sans écran.
## godot --headless --path . --script res://tests/run_tests.gd [-- --sims=100] [-- --quick]

var failures := 0
var checks := 0


func _init() -> void:
	var sims := 100
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sims="):
			sims = int(a.split("=")[1])
	test_data()
	test_placement()
	test_stats()
	test_battle_basics()
	test_energy_and_overdrive()
	test_factions()
	test_statuses()
	test_profile_levels()
	test_profile_stars()
	test_profile_misc()
	test_gacha()
	test_campaign_and_tower()
	test_codex_and_challenges()
	test_dispatch_and_trial()
	if not "--quick" in OS.get_cmdline_user_args():
		simulate_factions(maxi(10, sims / 5))
		simulate_campaign(maxi(6, sims / 10))
	print("\n%d vérifications, %d échec(s)." % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("  ÉCHEC : ", label)


func approx(a: float, b: float, label: String, eps := 0.01) -> void:
	check(absf(a - b) <= eps, "%s (obtenu %.4f, attendu %.4f)" % [label, a, b])


func spec(id: String, slot: int, level := 60, star := 6) -> Dictionary:
	return {"id": id, "level": level, "star": star, "slot": slot}


func unit_of(e: RtBattle, id: String, team := -1) -> RtUnit:
	for u in e.units:
		if u.id == id and (team < 0 or u.team == team):
			return u
	return null


# --- Données -----------------------------------------------------------------

func test_data() -> void:
	print("Données du roster")
	var per_faction := {}
	var per_class := {}
	var main := HeroDb.playable_ids(false)
	check(main.size() == 24, "24 héros jouables (hors Pions)")
	for id in HeroDb.all():
		var h := HeroDb.hero(id)
		check(HeroDb.classes().has(h["class"]), "%s : classe connue" % id)
		for f in h.get("factions", []):
			check(HeroDb.factions().has(f), "%s : faction %s connue" % [id, f])
		for key in ["skill", "overdrive", "passive", "talent"]:
			if h.has(key):
				for e: Dictionary in h[key].get("effects", []):
					if e.get("t", "") == "status":
						check(not HeroDb.status_info(e["id"]).is_empty(), "%s : statut %s connu" % [id, e["id"]])
		check(h.has("skill") and h.has("overdrive"), "%s : compétence et Overdrive" % id)
	for id in main:
		var h := HeroDb.hero(id)
		per_faction[h["factions"][0]] = int(per_faction.get(h["factions"][0], 0)) + 1
		per_class[h["class"]] = int(per_class.get(h["class"], 0)) + 1
		check(h["factions"].size() == 2 and h["factions"][0] != h["factions"][1], "%s : 2 factions distinctes" % id)
	for f in HeroDb.faction_order():
		check(int(per_faction.get(f, 0)) == 4, "faction %s : 4 héros (obtenu %d)" % [f, int(per_faction.get(f, 0))])
	for c in HeroDb.class_order():
		check(int(per_class.get(c, 0)) == 4, "classe %s : 4 héros (obtenu %d)" % [c, int(per_class.get(c, 0))])
		check(HeroDb.substitute_for(c) != "", "classe %s : un Pion d'encre" % c)
	check(HeroDb.stars()["tiers"].size() == 19, "19 paliers d'étoiles")
	check(HeroDb.levels()["rate"].size() == 100 and HeroDb.levels()["xp"].size() == 99, "courbes de niveau 1 à 100")


func test_placement() -> void:
	print("Grille 3 × 3 et classes")
	check(HeroDb.can_place("adrian", 1) and not HeroDb.can_place("adrian", 4), "Gardien : devant seulement")
	check(HeroDb.can_place("eirikr", 4) and not HeroDb.can_place("eirikr", 7), "Guerrier : devant ou milieu")
	check(not HeroDb.can_place("issa", 0) and HeroDb.can_place("issa", 7), "Prêtre : milieu ou fond")
	check(HeroDb.can_place("mello", 0) and HeroDb.can_place("mello", 8), "Assassin : partout")
	var placed := HeroDb.auto_place(["issa", "adrian", "noor_el", "mello", "eirikr", "montana"])
	check(placed.size() == 6, "placement automatique de 6")
	for s: int in placed:
		check(HeroDb.can_place(placed[s], s), "placement auto valide : %s en %d" % [placed[s], s])


func test_stats() -> void:
	print("Stats (classe × niveau × aptitude × étoiles)")
	var s := HeroDb.stats("adrian", 100, 5)
	approx(s["hp"], 13186 * 1.08, "Adrian 5★ niv. 100 : PV de classe × aptitude", 2.0)
	var s1 := HeroDb.stats("adrian", 1, 5)
	approx(s1["hp"], 13186 / 5.023 * 1.08, "niveau 1 = niveau 100 / 5,023", 1.0)
	var s19 := HeroDb.stats("adrian", 100, 19)
	approx(s19["atk"] / s["atk"], 2.12, "arc-en-ciel : ×2,12")
	var r := HeroDb.stats("eirikr", 100, 5)
	approx(r["atk"] / (1256.0 * 1.04), 0.86, "aptitude R 0,86")
	check(HeroDb.active_factions("mello", 5).size() == 1 and HeroDb.active_factions("mello", 6).size() == 2, "2e faction à 6★")
	check(HeroDb.max_level_for_star(3) == 60 and HeroDb.max_level_for_star(5) == 100, "plafond de niveau par étoiles")


# --- Combat ------------------------------------------------------------------

func test_battle_basics() -> void:
	print("Combat temps réel : bases")
	var a := [spec("adrian", 1), spec("mello", 4), spec("noor_el", 7)]
	var b := [spec("selene", 1), spec("ghost", 4), spec("nyssa", 7)]
	var e1 := RtBattle.new(a, b, 42)
	var w1 := e1.run()
	var e2 := RtBattle.new(a, b, 42)
	var w2 := e2.run()
	check(w1 >= 0, "le combat se termine")
	check(w1 == w2 and absf(e1.time - e2.time) < 0.001, "même graine, même combat")
	check(e1.time > 5.0 and e1.time <= 91.0, "durée plausible (%.1f s)" % e1.time)
	var ad := unit_of(e1, "adrian", 0)
	check(ad.home.x < 0 and absf(ad.home.x + 1.7) < 0.01, "ton équipe à gauche, Gardien devant")
	check(unit_of(e1, "selene", 1).home.x > 0, "l'adversaire à droite")
	# Les mêlées avancent : après 2 s, Adrian a quitté sa case
	var e3 := RtBattle.new(a, b, 7)
	for i in 40:
		e3.step()
	check(unit_of(e3, "adrian", 0).pos.x > -1.7, "les combattants avancent vers l'ennemi")
	# Limite de temps : défaite par défaut
	var e4 := RtBattle.new([spec("issa", 7, 1, 1)], [spec("don_diego", 1, 1, 1)], 3, {"time_limit": 2.0})
	check(e4.run() == 1 and e4.time <= 2.1, "temps écoulé : l'attaquant perd")


func test_energy_and_overdrive() -> void:
	print("Énergie d'équipe et Overdrive")
	var en: Dictionary = HeroDb.rules()["energy"]
	var e := RtBattle.new([spec("mello", 4, 100, 19)], [spec("pion_gardien", 1, 1, 1)], 5, {"time_limit": 60.0})
	e.auto[0] = false
	e.auto[1] = false
	approx(e.energy[0], float(en["start"]), "énergie de départ")
	var m_unit := unit_of(e, "pion_gardien", 1)
	m_unit.hp = 1e12
	m_unit.max_hp = 1e12
	for i in 20:
		e.step()
	approx(e.energy[0], float(en["start"]) + float(en["regen"]) * 1.0, "régénération par seconde", 0.05)
	var m := unit_of(e, "mello", 0)
	check(not e.can_overdrive(m), "Overdrive fermé avant %.1f s" % float(en["ov_open"]))
	e.energy[0] = 10.0
	while e.time < float(en["ov_open"]) + 0.2 and not e.is_over():
		e.step()
	e.energy[0] = 10.0
	m.lock = 0.0
	check(e.can_overdrive(m), "Overdrive prêt après l'ouverture")
	check(e.request_overdrive(m), "demande acceptée")
	e.step()
	approx(e.energy[0], 10.0 - m.ov_cost() + float(en["regen"]) * 0.05, "coût prélevé sur la jauge", 0.06)
	check(m.ov_cd > 15.0, "recharge propre de l'Overdrive")
	check(e.gcd[0] > 0.0, "délai d'équipe entre deux Overdrive")
	# Coût alourdi
	var s := m_unit
	var before := s.ov_cost()
	e.apply_status(m, s, "ov_tax", 5.0, 1.0)
	check(s.ov_cost() == before + 1, "Overdrive alourdi de 1")


func test_factions() -> void:
	print("Mécaniques de faction")
	# Bonus de faction : 4 héros de la même faction -> +10 % ATK et PV
	var four := [spec("montana", 4, 60, 5), spec("noor_el", 7, 60, 5), spec("tarkhan", 5, 60, 5), spec("ymir", 8, 60, 5)]
	var e := RtBattle.new(four, [spec("selene", 1)], 1)
	check(e.faction_bonus_pct[0] == 10 and e.faction_bonus_id[0] == "roi", "4 Roi : bonus de faction 10 %")
	var mon := unit_of(e, "montana", 0)
	approx(mon.max_hp / HeroDb.stats("montana", 60, 5)["hp"] / float(HeroDb.rules()["hp_mult"]), 1.10, "PV +10 %")
	# Réaction élémentaire : Brûlure puis Choc par un héros du Roi
	var t := unit_of(e, "selene", 1)
	e.record_events = true
	e.apply_status(mon, t, "burn", 5.0, 10.0)
	var hp0 := t.hp
	e.apply_status(mon, t, "shock", 5.0, null)
	var reacted := e.events.any(func(ev: Dictionary) -> bool: return ev["type"] == "reaction")
	check(reacted and t.hp < hp0 and not t.has_status("burn"), "Réaction élémentaire (Surcharge) : dégâts et élément consommé")
	# Grâce : Moral + Ferveur
	var e2 := RtBattle.new([spec("mikhaila", 7)], [spec("selene", 1)], 2)
	var mk := unit_of(e2, "mikhaila", 0)
	e2.apply_status(mk, mk, "moral", 6.0, null)
	e2.apply_status(mk, mk, "ferveur", 6.0, null)
	check(mk.has_status("grace") and not mk.has_status("moral"), "Moral + Ferveur : Grâce")
	# Cavalier : la Rage pleine donne le Galop
	var e3 := RtBattle.new([spec("mello", 4)], [spec("selene", 1)], 3)
	var me := unit_of(e3, "mello", 0)
	e3._gain_rage(me, 200.0)
	check(me.has_status("galop") and me.aspd() > 1.3, "Rage pleine : Galop (+35 % de vitesse d'attaque)")
	# Pion : un allié tombe -> Promesse
	var e4 := RtBattle.new([spec("don_selah", 1), spec("issa", 7, 1, 3)], [spec("selene", 1)], 4)
	var ds := unit_of(e4, "don_selah", 0)
	var p0 := ds.promesse
	e4._take(null, unit_of(e4, "issa", 0), 1e9)
	check(ds.promesse == p0 + 1, "allié tombé : +1 Promesse")
	# Fou : un Overdrive allié donne de l'Éveil
	var e5 := RtBattle.new([spec("ezra", 7), spec("mello", 4)], [spec("selene", 1)], 5)
	var ez := unit_of(e5, "ezra", 0)
	var ev0 := ez.eveil
	e5._launch_ov(unit_of(e5, "mello", 0))
	check(ez.eveil == ev0 + 1, "Overdrive allié : +1 Éveil")
	# Tour : Châtiment contre un Overdrive coûteux (coût >= 4)
	var e6 := RtBattle.new([spec("yass", 7)], [spec("montana", 7)], 6)
	e6.record_events = true
	var ya := unit_of(e6, "yass", 0)
	var mo := unit_of(e6, "montana", 1)
	check(mo.ov_cost() >= 3, "Montana : Overdrive coûteux")
	e6._deal(ya, mo, 1.0, "atk", "phys", {"chatiment": true})
	var chat := e6.events.any(func(ev: Dictionary) -> bool: return ev["type"] == "damage" and ev["chatiment"])
	check(chat and mo.has_status("ov_tax"), "Châtiment : bonus et Overdrive alourdi")


func test_statuses() -> void:
	print("Statuts")
	var e := RtBattle.new([spec("don_diego", 1)], [spec("mohamed", 1), spec("ghost", 4)], 8)
	var dd := unit_of(e, "don_diego", 0)
	var mh := unit_of(e, "mohamed", 1)
	e.apply_status(dd, mh, "taunt", 3.0, null)
	e._choose_target(mh)
	mh.target = null
	e._choose_target(mh)
	check(mh.target == dd, "Provocation : force la cible")
	e.apply_status(dd, mh, "stun", 1.0, null)
	check(not mh.can_act(), "Étourdi : ne peut pas agir")
	for i in 25:
		e.step()
	check(mh.dead or mh.can_act(), "l'Étourdissement prend fin")
	var gh := unit_of(e, "ghost", 1)
	var hp0 := gh.hp
	e.apply_status(dd, gh, "poison", 3.0, 20.0)
	for i in 21:
		e._tick_statuses(gh, 0.05)
	check(gh.hp < hp0, "Poison : dégâts chaque seconde")
	gh.shields.append({"amount": 1e7, "t": 5.0})
	var hp1 := gh.hp
	e._take(dd, gh, 500.0)
	check(gh.hp == hp1, "le bouclier absorbe d'abord")


# --- Profil ---------------------------------------------------------------

func test_profile_levels() -> void:
	print("Niveaux et Résonance de classe")
	var p := Profile.new_game(1000)
	check(p.formation_ids().size() == 3, "nouvelle partie : 3 héros en formation")
	check(p.level("eirikr") == int(GameData.progression()["starter_levels"]), "niveau de départ")
	p.add("encre", 10_000_000)
	p.add("pieces", 10_000_000)
	p.add("essence", 100000)
	var n := p.level_up_many("eirikr", 200)
	check(p.level("eirikr") == 60, "Eiríkr 3★ plafonné au niveau 60 (obtenu %d, +%d)" % [p.level("eirikr"), n])
	var uid := p.add_hero("adrian", 5)
	p.level_up_many("adrian", 200)
	check(p.level("adrian") == 100, "Adrian 5★ jusqu'au niveau 100")
	check(p.class_level("gardien") == 100, "niveau 100 : Résonance de la classe")
	check(p.class_level_up("gardien") and p.effective_level("adrian") == 101, "niveau de classe partagé")
	check(p.class_cap("gardien") == 120, "plafond de classe selon les étoiles (5★ : 120)")
	check(uid > 0, "exemplaire créé")


func test_profile_stars() -> void:
	print("Étoiles et doublons")
	var p := Profile.new_game(1000)
	var main := p.best_uid("eirikr")
	check(p.star_req(main)["main"] == 2, "3★ -> 4★ : 2 copies")
	check(not p.can_star_up(main), "sans copie : impossible")
	p.add_hero("eirikr", 3)
	p.add_hero("eirikr", 3)
	check(p.star_up(main), "2 copies 3★ : 4★")
	check(int(p.instance(main)["star"]) == 4 and p.copies("eirikr") == 1, "copies consommées")
	# Pion d'encre comme copie principale
	p.add("gelee", 1000)
	var pion := p.craft_pion("guerrier")
	check(pion > 0 and int(p.instance(pion)["star"]) == 5, "Pion d'encre fabriqué (5★)")
	p.instance(pion)["star"] = 4
	check(p.star_up(main), "un Pion de la même classe remplace une copie (4★ -> 5★)")
	# 6★ -> violet : 1 héros de la même classe à 6★, ou une Poupée
	var a := p.add_hero("adrian", 6)
	check(p.star_req(a)["class"] == 1, "6★ -> violet 1 : 1 héros de classe")
	p.add("poupee_gardien", 1)
	check(p.star_up(a) and int(p.instance(a)["star"]) == 7, "Poupée de classe utilisée")
	p.add_hero("adrian", 6)
	p.add_hero("moussa", 6)
	check(p.star_up(a) and int(p.instance(a)["star"]) == 8, "violet 1 -> 2 : copie 6★ + Gardien 6★")
	# Réinitialisation : retour à 6★, copies rendues
	var before := p.copies("adrian")
	check(p.star_reset(a, 1000) and int(p.instance(a)["star"]) == 6, "réinitialisation : 6★")
	check(p.copies("adrian") == before + 1 and p.amount("poupee_gardien") == 2, "copie rendue, héros de classe rendus en Poupées")
	# Doublon N : Gelée
	var n0 := p.amount("gelee")
	p.add_pull({"id": "pion_mage", "rarity": 2})
	p.add_pull({"id": "pion_mage", "rarity": 2})
	check(p.amount("gelee") == n0 + int(GameData.progression()["n_duplicate_gelee"]), "doublon N : Gelée")
	# Montée rapide
	var q := Profile.new_game(1000)
	for i in 3:
		q.add_hero("issa", 3)
	check(q.quick_star_up() >= 1 and q.best_star("issa") >= 4, "montée rapide")


func test_profile_misc() -> void:
	print("Formation, Patrouille, campagne, sauvegarde")
	var p := Profile.new_game(1000)
	check(p.deploy_max() == 3, "3 cases au départ")
	p.add_hero("adrian", 5)
	check(not p.set_slot(4, "adrian"), "Gardien au milieu : refusé")
	check(not p.set_slot(0, "adrian") or p.formation.size() <= 3, "limite de cases")
	p.campaign_cleared = 12
	check(p.deploy_max() == 6, "6 cases débloquées par la campagne")
	check(p.set_slot(0, "adrian"), "Gardien devant : accepté")
	# Patrouille
	p.patrol_time = 1000
	var got := p.patrol_pending(1000 + 3600)
	check(int(got.get("pieces", 0)) > 0 and int(got.get("encre", 0)) > 0, "Patrouille : or et encre accumulés")
	var cap := p.patrol_pending(1000 + 3600 * 100)
	var cap_m := float(Campaign.cfg()["patrol"]["cap_hours"]) * 60.0
	check(int(cap["pieces"]) == int(floor(Campaign.patrol_rate(12)["pieces"] * cap_m)), "Patrouille plafonnée")
	check(p.quick_price(86400 * 3) == 0, "1re Patrouille rapide gratuite")
	p.quick_patrol(86400 * 3)
	check(p.quick_price(86400 * 3) > 0, "les suivantes coûtent des Éclats")
	# Campagne
	var q := Profile.new_game(1000)
	var e0 := q.amount("eclat_de_voeu")
	var w := q.win_stage(1, 2000)
	check(w["first"] and q.campaign_cleared == 1 and q.amount("eclat_de_voeu") > e0, "étape 1 gagnée : récompenses")
	check(not q.win_stage(5, 2000)["first"], "on ne saute pas d'étape")
	# Sauvegarde
	var d: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict()))
	var p2 := Profile.from_dict(d)
	check(p2 != null and p2.copies("adrian") == p.copies("adrian") and p2.formation == p.formation, "sauvegarde relue")
	check(Profile.from_dict({"version": 1, "owned": {"montana": 1}}) == null, "sauvegarde d'avant la refonte : nouvelle partie")


func test_gacha() -> void:
	print("Invocation")
	var g := Gacha.new("standard", 99)
	var counts := {2: 0, 3: 0, 4: 0, 5: 0}
	var max_gap := 0
	var gap := 0
	var gap4 := 0
	var max_gap4 := 0
	for i in 4000:
		var r := g.pull()
		counts[r["rarity"]] += 1
		gap += 1
		gap4 += 1
		if r["rarity"] == 5:
			max_gap = maxi(max_gap, gap)
			gap = 0
		if r["rarity"] >= 4:
			max_gap4 = maxi(max_gap4, gap4)
			gap4 = 0
		check(HeroDb.exists(r["id"]) and int(HeroDb.hero(r["id"])["rarity"]) == int(r["rarity"]), "tirage cohérent")
	check(max_gap <= 40, "SSR garanti en 40 (écart max %d)" % max_gap)
	check(max_gap4 <= 10, "SR ou mieux toutes les 10 (écart max %d)" % max_gap4)
	var ssr := float(counts[5]) / 4000.0 * 100.0
	check(ssr > 2.5 and ssr < 6.0, "taux SSR effectif plausible (%.2f %%)" % ssr)
	var lim := Gacha.new("featured_montana", 5)
	var all_feat := true
	for i in 400:
		var r := lim.pull()
		if r["rarity"] == 5 and r["id"] != "montana":
			all_feat = false
	check(all_feat, "bannière limitée : chaque SSR est la vedette")
	var w := Gacha.new("standard", 6)
	w.total_pulls = 500
	w.wishlist.assign(["adrian"])
	var hits := 0
	var ssrs := 0
	for i in 3000:
		var r := w.pull()
		if r["rarity"] == 5:
			ssrs += 1
			if r["id"] == "adrian":
				hits += 1
	check(float(hits) / ssrs > 0.2, "liste de souhaits : le héros souhaité sort plus souvent")
	var st := g.get_state()
	var g2 := Gacha.new("standard", 1)
	g2.set_state(st)
	check(g2.pity_count() == g.pity_count() and g2.total_pulls == g.total_pulls, "compteurs sauvegardés")


func test_campaign_and_tower() -> void:
	print("Campagne et Tour")
	check(Campaign.stage_count() == 240, "240 étapes")
	var last_lvl := 0
	for n in range(1, Campaign.stage_count() + 1):
		var info := Campaign.stage_info(n)
		var specs := Campaign.enemy_specs(n)
		check(not specs.is_empty(), "étape %d : des ennemis" % n)
		check(int(info["level"]) >= last_lvl, "niveaux croissants")
		last_lvl = int(info["level"])
		for s: Dictionary in specs:
			check(HeroDb.exists(s["id"]), "étape %d : %s existe" % [n, s["id"]])
	check(Campaign.stage_info(12)["boss"], "étape 1-12 : boss")
	check(Tower.floor_count() == 99, "99 étages")
	check(Tower.floor_info(12)["boss"] == "promethee" and Tower.floor_info(6)["elite"], "boss à 12, Élite à 6")
	check(Tower.enemy_specs(30).size() == 6, "6 ennemis par étage")


# --- Simulations -----------------------------------------------------------------

func team_of_faction(f: String, level := 80, star := 6) -> Array:
	var ids := []
	for id in HeroDb.playable_ids(false):
		if HeroDb.hero(id)["factions"][0] == f:
			ids.append(id)
	for id in HeroDb.playable_ids(false):
		if ids.size() >= 6:
			break
		if not ids.has(id) and HeroDb.hero(id)["factions"][1] == f:
			ids.append(id)
	var placed := HeroDb.auto_place(ids)
	var out := []
	for s: int in placed:
		out.append({"id": placed[s], "level": level, "star": star, "slot": s})
	return out


func simulate_factions(n: int) -> void:
	print("\nSimulation : équipes de faction (6 héros, niv. 80, 6★), %d combats par duel" % n)
	var fs := HeroDb.faction_order()
	var score := {}
	var dur := 0.0
	var fights := 0
	for i in fs.size():
		for j in range(i + 1, fs.size()):
			var w := 0
			for k in n:
				var a := team_of_faction(fs[i])
				var b := team_of_faction(fs[j])
				var e := RtBattle.new(a if k % 2 == 0 else b, b if k % 2 == 0 else a, 500 + k * 31 + i * 7 + j, {"timeout_by_hp": true})
				e.record_events = false
				var win := e.run()
				var a_won := (win == 0) == (k % 2 == 0)
				if a_won:
					w += 1
				dur += e.time
				fights += 1
			score[fs[i]] = int(score.get(fs[i], 0)) + w
			score[fs[j]] = int(score.get(fs[j], 0)) + (n - w)
			print("  %s contre %s : %d %%" % [fs[i], fs[j], int(100.0 * w / n)])
	print("  victoires totales : ", score)
	print("  durée moyenne : %.1f s" % (dur / fights))
	check(dur / fights > 15.0 and dur / fights < 80.0, "durée moyenne des combats dans la cible (15-80 s)")


## Joueur « type » : 2 SSR, 2 SR, 2 R au niveau de l'étape ; étoiles selon le chapitre (DT : on monte les
## étoiles par les doublons au fil de la campagne).
func expected_team(stage: int) -> Array:
	var info := Campaign.stage_info(stage)
	var ci := int(info["chapter_index"])
	var lvl := int(info["level"])
	var pool := [["adrian", 5], ["noor_el", 5], ["saraya", 4], ["jo_prince", 4], ["eirikr", 3], ["issa", 3]]
	var n := Campaign.deploy_slots(stage - 1)
	var ids := []
	var stars := {}
	for i in n:
		ids.append(pool[i][0])
		stars[pool[i][0]] = mini(HeroDb.max_star(int(pool[i][1])), int(pool[i][1]) + ci / 2 + (1 if ci >= 1 else 0))
	var placed := HeroDb.auto_place(ids)
	var out := []
	for s: int in placed:
		var id: String = placed[s]
		out.append({"id": id, "level": mini(lvl + 2, HeroDb.max_level_for_star(stars[id])), "star": stars[id], "slot": s})
	return out


func simulate_campaign(n: int) -> void:
	print("
Simulation : campagne avec une équipe type (2 SSR, 2 SR, 2 R, niveau de l'étape + 2)")
	for stage in [1, 6, 11, 12, 20, 32, 56, 70, 100, 140, 180, 220, 239, 240]:
		var info := Campaign.stage_info(stage)
		var wins := 0
		var dur := 0.0
		for k in n:
			var e := RtBattle.new(expected_team(stage), Campaign.enemy_specs(stage), 900 + k * 17 + stage)
			e.record_events = false
			if e.run() == 0:
				wins += 1
			dur += e.time
		print("  étape %s (niv. %d%s) : %d %%, %.0f s" % [info["number"], int(info["level"]), ", boss" if info["boss"] else "", int(100.0 * wins / n), dur / n])


func test_codex_and_challenges() -> void:
	print("Codex et Défis")
	var p := Profile.new_game(1000)
	var e0 := p.amount("eclat_de_voeu")
	var stars0 := p.codex_stars()
	p.add_hero("adrian", 5)
	check(p.codex_stars() == stars0 + 5 and p.amount("eclat_de_voeu") == e0 + 5 * int(GameData.progression()["codex"]["eclats_per_star"]), "Codex : 5 étoiles et des Éclats")
	check(float(p.account_bonus()["atk_pct"]) > 0.0, "Codex : bonus de compte")
	var sp := p.battle_specs()
	check(sp[0].has("bonus"), "le bonus de compte part au combat")
	# Défis : équipes à classes imposées
	for id in ["noor_el", "montana", "issa", "nyssa"]:
		p.add_hero(id)
	var ft := Challenges.team_specs("foret", p)
	check(ft.all(func(s: Dictionary) -> bool: return HeroDb.hero(s["id"])["class"] in ["archer", "mage", "pretre"]), "Forêt : distance seule")
	var ct := Challenges.team_specs("casse", p)
	check(ct.all(func(s: Dictionary) -> bool: return HeroDb.hero(s["id"])["class"] in ["gardien", "guerrier", "assassin"]), "Casse : mêlée seule")
	var rt := Challenges.team_specs("ralliement", p)
	var seen := {}
	for s: Dictionary in rt:
		check(not seen.has(HeroDb.hero(s["id"])["class"]), "Ralliement : un héros par classe")
		seen[HeroDb.hero(s["id"])["class"]] = true
	check(Challenges.waves("foret", 5).size() == 3, "Forêt : 3 vagues")
	# Vagues : le combat continue tant qu'il reste des vagues
	var w := Challenges.waves("foret", 1)
	var strong := [{"id": "noor_el", "level": 100, "star": 19, "slot": 4}, {"id": "montana", "level": 100, "star": 19, "slot": 7}]
	var e := RtBattle.new(strong, w[0], 11, {"waves": w.slice(1)})
	e.record_events = false
	var win := e.run()
	check(win == 0 and e.wave == 2, "3 vagues battues l'une après l'autre (vagues : %d)" % e.wave)
	check(e.kills[0] == w[0].size() + w[1].size() + w[2].size(), "score : ennemis achevés")
	# Ralliement : vagues sans fin jusqu'à la fin du temps
	var o := Challenges.battle_options("ralliement")
	var r := RtBattle.new(strong, Challenges.waves("ralliement", 1)[0], 12, o)
	r.record_events = false
	r.run()
	check(r.winner == 0 and r.kills[0] > 8 and r.time >= float(Challenges.info("ralliement")["duration"]) - 0.1, "Ralliement : %d ennemis en 60 s" % r.kills[0])
	# Récompenses et essais
	var cl := Profile.new_game(1000)
	check(not cl.win_challenge("foret", 2, 0, 5000).size() > 0, "on ne saute pas de palier")
	check(cl.win_challenge("foret", 1, 0, 5000).has("pieces"), "palier 1 : récompense")
	check(cl.challenge_attempts("foret", 5000) == 2, "tenter un palier ne consomme pas d'essai")
	check(cl.sweep_challenge("foret", 5000).has("pieces") and cl.challenge_attempts("foret", 5000) == 1, "balayage : un essai")
	cl.sweep_challenge("foret", 5000)
	check(cl.sweep_challenge("foret", 5000).is_empty(), "plus d'essai aujourd'hui")
	check(cl.challenge_attempts("foret", 5000 + 86400) == 2, "essais rendus le lendemain")


func test_dispatch_and_trial() -> void:
	print("Missions et Épreuve de la déesse")
	var p := Profile.new_game(1000)
	for id in ["adrian", "selene", "moussa", "don_selah", "mello", "ghost", "noor_el", "nyssa", "yass", "mikhaila", "issa", "flint", "montana", "ezra", "tarkhan", "ymir", "eirikr", "jo_prince", "general_metal", "mohamed", "espion_lumiere", "saraya", "nidhogg"]:
		p.add_hero(id, 6)
	var now := 86400 * 100 + 10
	var ms := p.dispatch_missions(now)
	check(ms.size() == int(Dispatch.cfg()["per_day"]), "missions du jour")
	check(p.dispatch_missions(now) == ms, "mêmes missions le même jour")
	var started := -1
	for i in ms.size():
		if p.dispatch_start(i, now):
			started = i
			break
	check(started >= 0, "une mission lancée")
	var m: Dictionary = ms[started]
	check(m["heroes"].size() == int(m["count"]), "nombre de héros envoyés")
	check(m["heroes"].all(func(h: String) -> bool: return Dispatch.fits(m, h, p.best_star(h))), "héros conformes à la condition")
	check(p.dispatch_claim(started, now + 10).is_empty(), "pas de récolte avant la fin")
	var pieces := p.amount("pieces")
	var rw := p.dispatch_claim(started, now + int(float(m["hours"]) * 3600.0))
	check(not rw.is_empty(), "récolte à la fin")
	check(p.dispatch_claim(started, now + 999999).is_empty(), "une seule récolte")
	var ms2 := p.dispatch_missions(now + 86400)
	check(ms2.size() == int(Dispatch.cfg()["per_day"]), "nouvelles missions le lendemain")
	# Épreuve de la déesse : classes du jour
	var sunday := 3 * 86400 + 12 * 3600  # 4 janvier 1970 : dimanche
	check(Challenges.classes_for("deesse", sunday) == ["gardien", "pretre"], "dimanche : Gardiens et Prêtres")
	var ts := Challenges.team_specs("deesse", p, sunday)
	check(not ts.is_empty() and ts.all(func(s: Dictionary) -> bool: return HeroDb.hero(s["id"])["class"] in ["gardien", "pretre"]), "équipe de l'Épreuve conforme")
	var trw := Challenges.reward("deesse", 1, 0, sunday)
	check(trw.has("poupee_gardien") and trw.has("essence"), "récompense : Poupée de la classe du jour")
