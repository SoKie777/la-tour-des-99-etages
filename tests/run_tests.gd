extends SceneTree
## Tests des règles + simulation d'équilibrage, sans écran.
## godot --headless --path . --script res://tests/run_tests.gd [-- --sims=500]

var failures := 0
var checks := 0


func _init() -> void:
	var sims := 300
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sims="):
			sims = int(a.split("=")[1])
	test_formulas()
	test_cooldowns()
	test_effects()
	test_passives()
	test_kits_v2()
	test_gacha()
	test_relics()
	test_profile()
	simulate_balance(sims)
	simulate_rarity(maxi(40, sims / 2))
	simulate_tower(maxi(20, sims / 4))
	print("\n%d vérifications, %d échec(s)." % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("  ÉCHEC : ", label)


func approx(a: float, b: float, label: String, eps := 0.01) -> void:
	check(absf(a - b) <= eps, "%s (obtenu %.4f, attendu %.4f)" % [label, a, b])


func unit_of(e: BattleEngine, id: String) -> BattleUnit:
	for u in e.units:
		if u.id == id:
			return u
	return null


func test_formulas() -> void:
	print("Formules du document MVP")
	# Mohamed (Sirius) contre Eiríkr (Orion) : Sirius domine Orion.
	var e := BattleEngine.new(["mohamed"], ["eirikr"], 1)
	var moh := unit_of(e, "mohamed")
	var eir := unit_of(e, "eirikr")
	approx(e.crit_chance(moh, eir), 40.0, "Sirius vs Orion : TC 20 % + 20 points")
	approx(e.crit_chance(eir, moh), 15.0, "Orion vs Sirius : pas de bonus de TC")
	# 1 000 dégâts d'Orion contre Sirius tombent à 850 (DEF neutralisée pour l'exemple).
	moh.base["def"] = 0
	approx(e.compute_damage(eir, moh, 1000.0, {}, false, 1.0), 850.0, "Orion -> Sirius : -15 %")
	# Avec 500 de DEF, on subit 67 % des dégâts.
	moh.base["def"] = 500
	var e2 := BattleEngine.new(["moussa"], ["mohamed"], 1)
	unit_of(e2, "mohamed").base["def"] = 500
	approx(e2.compute_damage(unit_of(e2, "moussa"), unit_of(e2, "mohamed"), 1000.0, {}, false, 1.0), 666.67, "DEF 500 -> 67 %", 0.5)
	# Critique : DC 70 % -> x1,7
	unit_of(e2, "mohamed").base["def"] = 0
	var m2 := unit_of(e2, "mohamed")
	approx(e2.compute_damage(m2, unit_of(e2, "moussa"), 1000.0, {}, true, 1.0) / e2.compute_damage(m2, unit_of(e2, "moussa"), 1000.0, {}, false, 1.0), 1.7, "Critique DC 70 %")
	# TC plafonné à 100 %
	m2.base["cr"] = 95
	var e3 := BattleEngine.new(["issa"], ["eirikr"], 1)
	unit_of(e3, "issa").base["cr"] = 95
	approx(e3.crit_chance(unit_of(e3, "issa"), unit_of(e3, "eirikr")), 100.0, "TC plafonné à 100 %")
	# Chance d'effet bornée 15..100
	var e4 := BattleEngine.new(["ymir"], ["nidhogg"], 1)
	var y := unit_of(e4, "ymir")
	var n := unit_of(e4, "nidhogg")
	approx(e4.effect_chance(y, n, 50.0), 65.0, "Chance = 50 + 45 PRÉ - 30 RÉS")
	n.base["res"] = 200
	approx(e4.effect_chance(y, n, 50.0), 15.0, "Chance plancher 15 %")


func test_cooldowns() -> void:
	print("Recharges")
	var e := BattleEngine.new(["general_metal"], ["moussa"], 7)
	var g := unit_of(e, "general_metal")
	check(e.usable_skills(g) == [0, 1], "Tour 1 : compétences 1 et 2, pas l'ultime")
	g.cooldowns = [0, 0, 2]
	var turns_until_ult := 0
	for t in 5:
		if 2 in e.usable_skills(g):
			break
		turns_until_ult += 1
		e.current = g
		e._end_turn(g)
	check(turns_until_ult == 2, "L'ultime est prête au 3e tour (attendu 2 tours d'attente, obtenu %d)" % turns_until_ult)
	g.cooldowns[2] = g.skill_cd(2)
	var wait := 0
	while not 2 in e.usable_skills(g):
		e._end_turn(g)
		wait += 1
	check(wait == 5, "Recharge 5 : utilisable 5 tours plus tard (obtenu %d)" % wait)


func test_effects() -> void:
	print("Effets")
	var e := BattleEngine.new(["espion_lumiere"], ["moussa"], 3)
	var spy := unit_of(e, "espion_lumiere")
	var mou := unit_of(e, "moussa")
	e._try_apply(spy, mou, {"id": "poison", "chance": 100, "turns": 2})
	check(mou.get_effect("poison").get("turns", 0) == 3, "Venin tenace : Poison 2 -> 3 tours")
	var hp_before := mou.hp
	e.current = mou
	e._end_turn(mou)
	approx(hp_before - mou.hp, roundf(850 * 0.40), "Poison : 40 % de l'ATK du lanceur après l'action")
	# Sommeil : réveil quand touché
	var e2 := BattleEngine.new(["ymir"], ["mohamed"], 3)
	var moh := unit_of(e2, "mohamed")
	e2._try_apply(unit_of(e2, "ymir"), moh, {"id": "sleep", "chance": 100, "turns": 2, "no_roll": true})
	check(not e2.can_act(moh), "Endormi : ne joue pas")
	e2._deal_damage(unit_of(e2, "ymir"), moh, 10.0, {})
	check(e2.can_act(moh), "Sommeil levé quand la cible est touchée")
	# Nidhogg immunisé aux contrôles
	var e3 := BattleEngine.new(["ymir"], ["nidhogg"], 3)
	e3._try_apply(unit_of(e3, "ymir"), unit_of(e3, "nidhogg"), {"id": "sleep", "chance": 100, "turns": 2, "no_roll": true})
	check(not unit_of(e3, "nidhogg").has_effect("sleep"), "Un roi ne pleure pas : pas de Sommeil")
	# Provocation : ciblage forcé
	var e4 := BattleEngine.new(["mohamed"], ["don_diego", "issa"], 3)
	var dd := unit_of(e4, "don_diego")
	e4._try_apply(dd, dd, {"id": "taunt", "turns": 2})
	var vt := e4.valid_targets(unit_of(e4, "mohamed"), 0)
	check(vt.size() == 1 and vt[0] == dd, "Provocation : seule cible possible")
	# Bouclier
	e4._try_apply(dd, unit_of(e4, "issa"), {"id": "shield", "value": 15, "of": "caster_max_hp", "turns": 2})
	approx(unit_of(e4, "issa").shield_value(), 975.0, "Citadelle : bouclier 15 % des PV max de Don Diego")


func test_passives() -> void:
	print("Passifs")
	var e := BattleEngine.new(["mohamed"], ["eirikr"], 5)
	var eir := unit_of(e, "eirikr")
	for i in 7:
		eir.hp = eir.max_hp()
		e._deal_damage(unit_of(e, "mohamed"), eir, 10.0, {})
	check(eir.stacks["spark"] == 5, "Étincelle : 5 cumuls max")
	approx(eir.stat("cr"), 40.0, "Étincelle : TC 15 + 25")
	var e2 := BattleEngine.new(["mohamed"], ["issa", "moussa"], 5)
	var issa := unit_of(e2, "issa")
	e2._apply_damage(issa, 99999.0, unit_of(e2, "mohamed"), {})
	check(issa.hp == 1.0, "Zéro perte : l'allié reste à 1 PV")
	e2._apply_damage(issa, 99999.0, unit_of(e2, "mohamed"), {})
	check(not issa.is_alive(), "Zéro perte : une seule fois par combat")


## Moteur v2 : chaque mécanique des kits de la fiche « Personnages jouables et boss ».
func test_kits_v2() -> void:
	print("Kits v2")
	var evs: Array[Dictionary] = []
	var count := func(type: String) -> int: return evs.filter(func(ev: Dictionary) -> bool: return ev["type"] == type).size()
	# Coups multiples
	var e := BattleEngine.new(["ghost"], ["moussa"], 4)
	e.battle_event.connect(func(ev: Dictionary) -> void: evs.append(ev))
	e.execute(unit_of(e, "ghost"), unit_of(e, "ghost").skill(0), unit_of(e, "moussa"), 0)
	check(count.call("damage") == 2, "Pics de glace : 2 coups")
	# Poursuite de Montana : 2 frappes, 3 sur une cible sous contrôle ; Selah + Gel réussi -> S1 gratuit
	e = BattleEngine.new(["montana"], ["moussa"], 4)
	var mon := unit_of(e, "montana")
	var mou := unit_of(e, "moussa")
	evs.clear()
	e.battle_event.connect(func(ev: Dictionary) -> void: evs.append(ev))
	e.execute(mon, mon.skill(0), mou, 0)
	check(count.call("damage") == 2, "Contact accéléré : 2 frappes")
	evs.clear()
	e._try_apply(mon, mou, {"id": "freeze", "turns": 1, "no_roll": true})
	e.execute(mon, mon.skill(0), mou, 0)
	check(count.call("damage") == 3, "Contact accéléré : 3 frappes sur une cible gelée")
	mou.effects.clear()
	mou.base["res"] = -200  # Gel certain
	evs.clear()
	e.execute(mon, mon.skill(2), mou, 2)
	check(count.call("bonus_action") == 1 and count.call("skill") == 2, "Selah : Gel réussi -> S1 gratuit")
	check(mon.hp < mon.max_hp(), "Selah : prix de 10 % des PV")
	# Visages de Mello : cumulés puis consommés, PV max perdus
	e = BattleEngine.new(["mello"], ["selene"], 4)
	var mel := unit_of(e, "mello")
	var sel := unit_of(e, "selene")
	e.execute(mel, mel.skill(0), sel, 0)
	check(sel.stack("visage") == 2, "Flamme bleue : 2 Visages")
	var max_before := mel.max_hp()
	e.execute(mel, mel.skill(2), sel, 2)
	check(sel.stack("visage") == 0 and mel.max_hp() < max_before, "Seimei : Visages consommés, PV max perdus")
	# Dette de Yass : Malédiction certaine à 2 Dettes, explosion, S2 bloquée
	e = BattleEngine.new(["yass"], ["adrian"], 4)
	var yas := unit_of(e, "yass")
	var adr := unit_of(e, "adrian")
	adr.base["res"] = 500
	e.execute(yas, yas.skill(0), adr, 0)
	check(adr.stack("dette") == 2, "Chaînes : 2 Dettes")
	e.execute(yas, yas.skill(1), adr, 1)
	check(adr.has_effect("curse"), "Dette d'Amour : Malédiction certaine malgré 500 RÉS")
	e._try_apply(adr, adr, {"id": "immunity", "turns": 2})
	yas.cooldowns = [0, 0, 0]
	e.current = yas
	e.use_skill(yas, 2, adr)
	check(adr.stack("dette") == 0 and adr.has_effect("curse"), "Banqueroute : Dette explosée, Malédiction malgré l'Immunité")
	check(yas.cooldowns[1] >= 1, "Banqueroute : pas de S2 au tour suivant")
	# Ezra : suppression des buffs avec bonus, vol de buff
	e = BattleEngine.new(["ezra"], ["noor_el", "flint"], 4)
	var ez := unit_of(e, "ezra")
	var noor := unit_of(e, "noor_el")
	for b in ["atk_up", "def_up", "cr_up"]:
		e._try_apply(noor, noor, {"id": b, "value": 20, "turns": 3})
	e.execute(ez, ez.skill(1), noor, 1)
	check(not noor.has_buff(), "Null Void ciblé : buffs supprimés")
	e._try_apply(noor, noor, {"id": "atk_up", "value": 20, "turns": 3})
	for i in 6:
		if ez.has_effect("atk_up"):
			break
		e.execute(ez, ez.skill(0), noor, 0)
	check(ez.has_effect("atk_up") and not noor.has_effect("atk_up"), "Muay Thai : buff volé")
	# Mikhaïla : résurrection une fois, purge, Vieillissement
	e = BattleEngine.new(["mikhaila", "ghost"], ["moussa"], 4)
	var mik := unit_of(e, "mikhaila")
	var gho := unit_of(e, "ghost")
	e._apply_damage(gho, 99999.0, unit_of(e, "moussa"), {})
	e._try_apply(unit_of(e, "moussa"), mik, {"id": "def_break", "turns": 2, "no_roll": true})
	e.execute(mik, mik.skill(2), null, 2)
	check(gho.is_alive() and is_equal_approx(gho.ap, 1.0), "Le temps ressenti : allié ressuscité à 100 % PA")
	check(not mik.has_effect("def_break") and mik.has_effect("immunity"), "Le temps ressenti : purge et Immunité")
	check(unit_of(e, "moussa").has_effect("aging"), "Le temps ressenti : Vieillissement sur l'ennemi")
	e._apply_damage(gho, 99999.0, unit_of(e, "moussa"), {})
	e.execute(mik, mik.skill(2), null, 2)
	check(not gho.is_alive(), "Résurrection : une seule fois par combat")
	# Selene : posture, accumulation puis renvoi à tous les ennemis
	e = BattleEngine.new(["selene"], ["mohamed", "issa"], 4)
	sel = unit_of(e, "selene")
	e.current = sel
	e.execute(sel, sel.skill(2), null, 2)
	check(not e.can_act(sel), "Contre-attaque minimale : Selene immobile")
	e._deal_damage(unit_of(e, "mohamed"), sel, 3000.0, {})
	var issa_hp := unit_of(e, "issa").hp
	for i in 3:
		e.current = sel
		e._end_turn(sel)
	check(not sel.has_effect("bastion") and unit_of(e, "issa").hp < issa_hp, "Fin de la posture : dégâts renvoyés aux ennemis")
	# Don Selah : immunisé aux débuffs, 50 % de PA au départ, garde des alliés
	e = BattleEngine.new(["don_selah", "flint"], ["ezra"], 4)
	var ds := unit_of(e, "don_selah")
	check(is_equal_approx(ds.ap, 0.5), "Éveil : commence à 50 % PA")
	e._try_apply(unit_of(e, "ezra"), ds, {"id": "stun", "turns": 1, "no_roll": true, "ignore_immunity": true})
	check(not ds.has_effect("stun"), "Éveil : immunisé même contre « passe l'Immunité »")
	var fl := unit_of(e, "flint")
	e._try_apply(ds, fl, {"id": "guarded", "value": 30, "turns": 2})
	var ds_hp := ds.hp
	e._apply_damage(fl, 1000.0, unit_of(e, "ezra"), {})
	approx(fl.max_hp() - fl.hp, 700.0, "Garde du Titan : l'allié subit 70 %")
	approx(ds_hp - ds.hp, 300.0, "Garde du Titan : Don Selah absorbe 30 %")
	# Tarkhan survit une fois ; Adrian renvoie 10 %
	e = BattleEngine.new(["tarkhan"], ["adrian"], 4)
	var tar := unit_of(e, "tarkhan")
	adr = unit_of(e, "adrian")
	e._apply_damage(tar, 99999.0, adr, {})
	check(tar.hp == 1.0 and tar.stack("rage") == 1, "Immunité à la douleur : survit à 1 PV, +1 Rage")
	e._apply_damage(tar, 99999.0, adr, {})
	check(not tar.is_alive(), "Immunité à la douleur : une seule fois")
	var t_hp := 0.0
	e = BattleEngine.new(["tarkhan"], ["adrian"], 4)
	tar = unit_of(e, "tarkhan")
	adr = unit_of(e, "adrian")
	t_hp = tar.hp
	e._apply_damage(adr, 1000.0, tar, {})
	approx(t_hp - tar.hp, 100.0, "Corps de feu : renvoie 10 % des dégâts")
	# Nyssa : clones à chaque tour, copie de la dernière S2/S3
	e = BattleEngine.new(["nyssa", "noor_el"], ["moussa"], 4)
	var ny := unit_of(e, "nyssa")
	for i in 4:
		e._start_turn(ny)
	check(ny.stack("clone") == 3, "Clones temporels : 3 au maximum")
	e.last_skill = {"unit": unit_of(e, "noor_el"), "index": 1}
	evs.clear()
	e.battle_event.connect(func(ev: Dictionary) -> void: evs.append(ev))
	e.execute(ny, ny.skill(2), null, 2)
	check(count.call("copy") == 1 and ny.stack("clone") == 0, "Copie de technique : S2 de Noor-El rejouée, clones consommés")
	# Ghost : sol gelé sur les ennemis, levé à sa mort
	e = BattleEngine.new(["ghost"], ["moussa"], 4)
	mou = unit_of(e, "moussa")
	approx(mou.stat("spd"), 94.0 * 0.9, "Givre glissant : ennemis -10 % VIT")
	e._apply_damage(unit_of(e, "ghost"), 99999.0, mou, {})
	approx(mou.stat("spd"), 94.0, "Givre glissant : levé à la mort de Ghost")


func test_gacha() -> void:
	print("Gacha")
	var g := Gacha.new("standard", 42)
	var counts := {3: 0, 4: 0, 5: 0}
	var max_gap := 0
	var gap := 0
	var gap4 := 0
	var max_gap4 := 0
	for i in 100000:
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
	var hard := int(g.banner["hard_pity_5"])
	var every := int(g.banner["guarantee_4_every"])
	check(max_gap <= hard, "Pity : Légendaire garanti en %d invocations max (pire cas %d)" % [hard, max_gap])
	check(max_gap4 <= every, "Épique ou mieux toutes les %d invocations (pire cas %d)" % [every, max_gap4])
	print("  Taux observés sur 100 000 : 3★ %.2f %% | 4★ %.2f %% | 5★ %.2f %%" % [counts[3] / 1000.0, counts[4] / 1000.0, counts[5] / 1000.0])
	var f := Gacha.new("featured_montana", 9)
	var hits := 0
	var fives := 0
	for i in 50000:
		var r := f.pull()
		if r["rarity"] == 5:
			fives += 1
			if r["id"] == "montana":
				hits += 1
	var n5 := GameData.characters().values().filter(func(c: Dictionary) -> bool: return int(c["rarity"]) == 5).size()
	print("  Bannière vedette : Montana = %.1f %% des 5★ (%d Légendaires)" % [100.0 * hits / fives, n5])
	approx(float(hits) / fives, 2.0 / (n5 + 1), "Vedette pondérée x2", 0.03)


func test_relics() -> void:
	print("Reliques")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var gear: Array = []
	for slot in range(1, 5):
		gear.append(Relics.generate(rng, "vampirisme", slot))
	gear.append(Relics.generate(rng, "vitesse", 5))
	gear.append(Relics.generate(rng, "vitesse", 6))
	for r: Dictionary in gear:
		for i in 15:
			Relics.level_up(rng, r)
	check(gear[0]["subs"].size() == 4, "Relique +15 : 4 stats secondaires")
	var active := Relics.active_sets(gear)
	check(active.get("vampirisme", 0) == 1 and active.get("vitesse", 0) == 1, "Set 4 + set 2 actifs")
	var u := Relics.make_unit("mohamed", gear)
	check(u.set_specials.has("lifesteal_20"), "Vampirisme transmis au combat")
	check(u.base["spd"] > 108 * 1.12 - 0.01, "Set Vitesse : +12 % VIT")


func test_profile() -> void:
	print("Profil, Tour et sauvegarde")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var p := Profile.new_game()
	check(p.owned_ids().size() == 3 and p.team.size() == 3, "Nouveau joueur : 3 personnages dans l'équipe")
	check(p.amount("eclat_de_voeu") == 20, "Nouveau joueur : 20 Éclats de Vœu")
	check(p.add_pull({"id": "eirikr", "rarity": 5})["new"], "Nouveau 5★ ajouté à la collection")
	check(p.add_pull({"id": "eirikr", "rarity": 5})["fragments"] == 40 and p.amount("fragments_etage") == 40, "Doublon 5★ → 40 Fragments")
	p.add_pull({"id": "recrue_orion", "rarity": 3})
	check(p.amount("fragments_etage") == 41 and not "recrue_orion" in p.owned_ids(), "Recrue 3★ → 1 Fragment")
	check(not p.set_team(["eirikr", "ymir"]), "Équipe refusée avec un personnage non possédé")
	check(p.set_team(["eirikr", "issa"]), "Équipe de 2 acceptée")
	check(p.can_enter_floor(1) and not p.can_enter_floor(2), "Seul l'étage 1 est ouvert au départ")
	var rw := p.win_floor(1, rng)
	check(rw["first_clear"] and p.tower_cleared == 1 and p.can_enter_floor(2), "Victoire à l'étage 1 : étage 2 ouvert")
	check(p.amount("eclat_de_voeu") == 23 and p.relics.size() == 1, "Récompenses : 3 Éclats + 1 relique")
	check(not p.win_floor(1, rng)["first_clear"] and p.amount("eclat_de_voeu") == 23, "Rejouer : pas de nouveaux Éclats")
	var r: Dictionary = p.relics[0]
	var uid := int(r["uid"])
	check(p.equip("eirikr", uid) and p.owner_of(uid) == "eirikr", "Relique équipée")
	check(p.equip("issa", uid) and p.owner_of(uid) == "issa" and p.equipped_relics("eirikr").is_empty(), "Relique passée à un autre porteur")
	var pieces := p.amount("pieces")
	check(p.level_relic(uid, rng) and int(r["level"]) == 1 and p.amount("pieces") == pieces - 100, "Montée +1 : coût 100 Pièces")
	var u := p.make_unit("issa")
	check(u.base["hp"] != GameData.character("issa")["stats"]["hp"] or u.base["atk"] != GameData.character("issa")["stats"]["atk"] \
		or u.base["def"] != GameData.character("issa")["stats"]["def"] or r["main"]["stat"] in ["cr", "cd", "acc", "res", "spd"], "La relique change les stats")
	var back := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	check(back.owner_of(uid) == "issa" and back.tower_cleared == 2 - 1 and back.amount("fragments_etage") == 41, "Sauvegarde relue à l'identique")
	check(back.team == p.team and int(back.relic(uid)["level"]) == 1, "Équipe et niveau de relique conservés")


## Une équipe de Légendaires doit battre largement une équipe de Rares (et les Épiques aussi).
func simulate_rarity(n: int) -> void:
	var by := {3: [], 4: [], 5: []}
	for id: String in GameData.characters():
		if id != "don_selah":
			by[int(GameData.character(id)["rarity"])].append(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	print("
Raretés (équipes tirées au hasard, %d combats) :" % n)
	for pair in [[5, 3], [4, 3], [5, 4]]:
		var wins := 0
		for k in n:
			var a: Array = []
			var b: Array = []
			var pa: Array = by[pair[0]].duplicate()
			var pb: Array = by[pair[1]].duplicate()
			for i in 3:
				a.append(pa.pop_at(rng.randi() % pa.size()))
				b.append(pb.pop_at(rng.randi() % pb.size()))
			var swap := k % 2 == 1
			var e := BattleEngine.new(b if swap else a, a if swap else b, 3000 + k)
			var w := e.run_auto()
			if w != BattleEngine.DRAW and ((w == 0) != swap):
				wins += 1
		var pct := 100.0 * wins / n
		print("  %d★ contre %d★ : %.0f %% de victoires" % [pair[0], pair[1], pct])
		check(pct >= (85.0 if pair == [5, 3] else 60.0), "%d★ nettement plus fort que %d★" % [pair[0], pair[1]])


## Taux de victoire étage par étage (IA des deux côtés), sans reliques.
func simulate_tower(n: int) -> void:
	var teams := {"Départ (Nidhogg, Espion, Issa)": ["nidhogg", "espion_lumiere", "issa"],
		"Mixte (Eiríkr, Issa, Don Diego)": ["eirikr", "issa", "don_diego"]}
	print("\nTour, sans reliques (%d combats par étage) :" % n)
	for name: String in teams:
		var line: Array[String] = []
		for f in range(1, Tower.floor_count() + 1):
			var wins := 0
			for k in n:
				var players: Array[BattleUnit] = []
				for id: String in teams[name]:
					players.append(BattleUnit.new(GameData.character(id), 0, players.size()))
				var e := BattleEngine.new(players, Tower.enemy_units(f), 7000 + k)
				if e.run_auto() == 0:
					wins += 1
			line.append("%d:%d%%" % [f, roundi(100.0 * wins / n)])
		print("  %-32s %s" % [name, " ".join(line)])


func simulate_balance(n: int) -> void:
	var rares := {"A (Orion)": GameData.nation_team("A", 3), "B (Grande Ourse)": GameData.nation_team("B", 3), "C (Sirius)": GameData.nation_team("C", 3)}
	var teams := {"A (Orion)": GameData.nation_team("A"), "B (Grande Ourse)": GameData.nation_team("B"), "C (Sirius)": GameData.nation_team("C")}
	print("\nSimulation d'équilibrage, roster v2 (%d combats par duel, IA des deux côtés)" % n)
	for k: String in teams:
		print("  %s : %s" % [k, ", ".join(teams[k].map(func(id: String) -> String: return GameData.character(id)["name"]))])
	duel_table(teams, n)
	print("Rares (personnages du MVP) :")
	duel_table(rares, n)
	# Même duels sans le triangle : sépare l'effet du triangle de celui de la composition.
	var tri: Dictionary = GameData.rules()["triangle"]
	var saved := [tri["dominant_crit_bonus"], tri["dominated_damage_mult"]]
	tri["dominant_crit_bonus"] = 0
	tri["dominated_damage_mult"] = 1.0
	print("Sans le triangle des constellations :")
	duel_table(teams, n)
	tri["dominant_crit_bonus"] = saved[0]
	tri["dominated_damage_mult"] = saved[1]
	# Equipe mixte : un DPS, un soutien, un tank de nations différentes
	var mixed := ["eirikr", "issa", "don_diego"]
	var w2 := [0, 0]
	for k in n:
		var e := BattleEngine.new(mixed, rares["B (Grande Ourse)"], 5000 + k)
		var w := e.run_auto()
		if w in [0, 1]:
			w2[w] += 1
	print("  Mixte (Eiríkr, Issa, Don Diego) vs B (Rares) : %.1f %% de victoires" % (100.0 * w2[0] / n))


func duel_table(teams: Dictionary, n: int) -> void:
	var names := teams.keys()
	for i in names.size():
		for j in names.size():
			if i >= j:
				continue
			var wins := [0, 0, 0]
			var actions_per_side := 0.0
			for k in n:
				# On alterne les côtés pour neutraliser l'avantage éventuel du slot.
				var swap := k % 2 == 1
				var left: Array = teams[names[j]] if swap else teams[names[i]]
				var right: Array = teams[names[i]] if swap else teams[names[j]]
				var e := BattleEngine.new(left, right, 1000 + k)
				var w := e.run_auto()
				if w == BattleEngine.DRAW:
					wins[2] += 1
				else:
					var i_won := (w == 0) != swap
					wins[0 if i_won else 1] += 1
				var acts := 0
				for u in e.units:
					acts += u.actions_taken
				actions_per_side += acts / 6.0
			print("  %-18s vs %-18s : %5.1f %% / %5.1f %% (nuls %d) | ~%.1f tours par personnage" % [
				names[i], names[j], 100.0 * wins[0] / n, 100.0 * wins[1] / n, wins[2], actions_per_side / n])
