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
	test_generic_effects()
	test_boss()
	test_loot()
	test_gacha()
	test_relics()
	test_profile()
	test_battle_stats()
	test_tactics()
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
	check(e.usable_skills(g) == [0, 1, 2], "Tour 1 : toutes les compétences sont prêtes (recharges à zéro)")
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


## Moteur v2 : mécaniques des kits (fiche, partie 1) et statuts signature (partie 6).
func test_kits_v2() -> void:
	print("Kits v2 et statuts signature")
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
	# Room : -25 % VIT, Montana vole 10 % de jauge au début du tour de la cible
	mou.effects.clear()
	e._try_apply(mon, mou, {"id": "room", "no_roll": true})
	approx(mou.stat("spd"), 94.0 * 0.75, "Room : -25 % VIT")
	mou.ap = 0.5
	mon.ap = 0.0
	e._start_turn(mou)
	check(is_equal_approx(mou.ap, 0.4) and is_equal_approx(mon.ap, 0.1), "Room : 10 % de jauge volée à Montana")
	e._apply_action(mon, mou, {"id": "cleanse"}, {})
	check(mou.has_effect("room"), "Room : non purgeable")
	# Vieillissement : -8 % ATK et DEF par cumul ; à 5, Étourdissement et cumuls retirés
	e = BattleEngine.new(["mikhaila"], ["mello"], 4)
	var mik := unit_of(e, "mikhaila")
	var mel := unit_of(e, "mello")
	e._try_apply(mik, mel, {"id": "vieillissement", "stacks": 2, "no_roll": true})
	approx(mel.stat("atk"), 1410.0 * 0.84, "Vieillissement x2 : -16 % ATK")
	e._try_apply(mik, mel, {"id": "vieillissement", "stacks": 3, "no_roll": true})
	check(mel.has_effect("stun") and not mel.has_effect("vieillissement"), "Vieillissement x5 : Étourdi, cumuls retirés")
	# Mikhaïla : résurrection une fois, purge, Vieillissement sur les ennemis
	e = BattleEngine.new(["mikhaila", "ghost"], ["moussa"], 4)
	mik = unit_of(e, "mikhaila")
	var gho := unit_of(e, "ghost")
	e._apply_damage(gho, 99999.0, unit_of(e, "moussa"), {})
	e._try_apply(unit_of(e, "moussa"), mik, {"id": "def_break", "turns": 2, "no_roll": true})
	e.execute(mik, mik.skill(2), null, 2)
	check(gho.is_alive() and is_equal_approx(gho.ap, 1.0), "Le temps ressenti : allié ressuscité à 100 % PA")
	check(not mik.has_effect("def_break") and mik.has_effect("immunity"), "Le temps ressenti : purge et Immunité")
	check(unit_of(e, "moussa").status_stacks("vieillissement") == 2, "Le temps ressenti : 2 Vieillissements sur l'ennemi")
	e._apply_damage(gho, 99999.0, unit_of(e, "moussa"), {})
	e.execute(mik, mik.skill(2), null, 2)
	check(not gho.is_alive(), "Résurrection : une seule fois par combat")
	# Givre : à 3 cumuls, Gel garanti
	e = BattleEngine.new(["ghost"], ["moussa"], 4)
	gho = unit_of(e, "ghost")
	mou = unit_of(e, "moussa")
	for i in 3:
		e._try_apply(gho, mou, {"id": "givre", "no_roll": true})
	check(mou.has_effect("freeze") and not mou.has_effect("givre"), "Givre x3 : Gel garanti")
	# Clone de Nyssa : un par tour (3 max), absorbe un coup en renvoyant 30 % ATK, copie ses attaques à 40 %
	e = BattleEngine.new(["nyssa", "noor_el"], ["moussa"], 4)
	var ny := unit_of(e, "nyssa")
	mou = unit_of(e, "moussa")
	for i in 4:
		e._start_turn(ny)
	check(ny.status_stacks("clone") == 3, "Clones temporels : 3 au maximum")
	var ny_hp := ny.hp
	var mou_hp := mou.hp
	e._deal_damage(mou, ny, 2000.0, {})
	check(ny.hp == ny_hp and ny.status_stacks("clone") == 2 and mou.hp < mou_hp, "Clone : coup absorbé, 30 % ATK renvoyés")
	evs.clear()
	e.battle_event.connect(func(ev: Dictionary) -> void: evs.append(ev))
	e.execute(ny, ny.skill(0), mou, 0)
	check(count.call("clone_copy") == 2, "Clones : chaque clone copie l'attaque")
	e.last_skill = {"unit": unit_of(e, "noor_el"), "index": 1}
	evs.clear()
	e.execute(ny, ny.skill(2), null, 2)
	check(count.call("copy") == 1 and ny.status_stacks("clone") == 0, "Copie de technique : S2 de Noor-El rejouée, clones consommés")
	# Selene : Inertie à chaque coup reçu, retirée à son tour ; à 6, bouclier sur sa compétence suivante
	e = BattleEngine.new(["selene"], ["mohamed", "issa"], 4)
	var sel := unit_of(e, "selene")
	var moh := unit_of(e, "mohamed")
	for i in 6:
		e._deal_damage(moh, sel, 100.0, {})
	check(sel.flags.has("shield_next_skill"), "Inertie x6 : bouclier promis")
	e._start_turn(sel)
	check(not sel.has_effect("inertie"), "Inertie : retirée au début de son tour")
	e.execute(sel, sel.skill(0), moh, 0)
	check(sel.shield_value() > 0.0, "Inertie : bouclier de 20 % PV sur la compétence suivante")
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
	# Adrian : Garde de fer (-12 % par cumul) ; à 4, contre-attaque à 120 % ; renvoi de 10 %
	e = BattleEngine.new(["adrian"], ["tarkhan"], 4)
	var adr := unit_of(e, "adrian")
	var tar := unit_of(e, "tarkhan")
	e._try_apply(adr, adr, {"id": "garde_de_fer", "stacks": 2})
	approx(e._taken_mult(adr), 0.76, "Garde de fer x2 : -12 % de dégâts par cumul (-24 %)")
	evs.clear()
	e.battle_event.connect(func(ev: Dictionary) -> void: evs.append(ev))
	e._try_apply(adr, adr, {"id": "garde_de_fer", "stacks": 2}, tar)
	check(count.call("counter") == 1 and not adr.has_effect("garde_de_fer"), "Garde de fer x4 : contre-attaque, cumuls consommés")
	var t_hp := tar.hp
	adr.effects.clear()
	e._apply_damage(adr, 1000.0, tar, {})
	approx(t_hp - tar.hp, 100.0, "Corps de feu : renvoie 10 % des dégâts")
	# Mello : Visage sur lui (+6 DC, +4 % ATK) ; à 6, ignore 30 % DEF et retombe à 2
	e = BattleEngine.new(["mello"], ["selene"], 4)
	mel = unit_of(e, "mello")
	sel = unit_of(e, "selene")
	e.execute(mel, mel.skill(0), sel, 0)
	check(mel.status_stacks("visage") == 2, "Flamme bleue : 2 Visages sur Mello")
	approx(mel.stat("cd"), 75.0 + 12.0, "Visage x2 : +12 DC")
	for i in 2:
		e.execute(mel, mel.skill(0), sel, 0)
	check(mel.status_stacks("visage") == 2 and mel.flags.has("ignore_def_next"), "Visage x6 : retombe à 2, ignore 30 % DEF ensuite")
	var max_before := mel.max_hp()
	e.execute(mel, mel.skill(2), sel, 2)
	check(mel.max_hp() < max_before and not mel.flags.has("ignore_def_next"), "Seimei : PV max perdus, bonus consommé")
	# Tarkhan : Rage (+5 % ATK, -3 % DEF) ; à 8, explosion de zone ; survit une fois
	e = BattleEngine.new(["tarkhan"], ["adrian", "flint"], 4)
	tar = unit_of(e, "tarkhan")
	e._try_apply(tar, tar, {"id": "rage", "stacks": 4})
	approx(tar.stat("atk"), 1155.0 * 1.2, "Rage x4 : +20 % ATK")
	var fl_hp := unit_of(e, "flint").hp
	e._try_apply(tar, tar, {"id": "rage", "stacks": 4})
	check(unit_of(e, "flint").hp < fl_hp and not tar.has_effect("rage"), "Rage x8 : explosion de zone")
	e._apply_damage(tar, 99999.0, unit_of(e, "adrian"), {})
	check(tar.hp == 1.0, "Immunité à la douleur : survit à 1 PV")
	e._apply_damage(tar, 99999.0, unit_of(e, "adrian"), {})
	check(not tar.is_alive(), "Immunité à la douleur : une seule fois")
	# Yass : Dette (2 % PV max par cumul en fin de tour), Malédiction certaine à 2 Dettes, Banqueroute
	e = BattleEngine.new(["yass"], ["adrian"], 4)
	var yas := unit_of(e, "yass")
	adr = unit_of(e, "adrian")
	e.execute(yas, yas.skill(0), adr, 0)
	check(adr.status_stacks("dette") == 2, "Chaînes : 2 Dettes")
	adr.base["res"] = 500
	e.execute(yas, yas.skill(1), adr, 1)
	check(adr.has_effect("curse"), "Dette d'Amour : Malédiction certaine malgré 500 RÉS")
	var a_hp := adr.hp
	adr.effects.erase(adr.get_effect("curse"))
	e.current = adr
	e._end_turn(adr)
	approx(a_hp - adr.hp, roundf(adr.max_hp() * 0.04), "Dette x2 : 4 % des PV max en fin de tour", 1.0)
	e._try_apply(adr, adr, {"id": "immunity", "turns": 2})
	e._try_apply(yas, adr, {"id": "dette", "no_roll": true})
	yas.cooldowns = [0, 0, 0]
	e.current = yas
	e.use_skill(yas, 2, adr)
	check(adr.marks("dette") == 0 and adr.has_effect("curse"), "Banqueroute : Dette explosée, Malédiction malgré l'Immunité")
	check(yas.cooldowns[1] >= 1, "Banqueroute : pas de S2 au tour suivant")
	# Saraya : Bénédiction (+10 % de soins reçus par cumul) ; sous 30 % PV, soin de 25 %
	e = BattleEngine.new(["saraya", "ghost"], ["mohamed"], 4)
	gho = unit_of(e, "ghost")
	e.execute(unit_of(e, "saraya"), unit_of(e, "saraya").skill(1), gho, 1)
	check(gho.status_stacks("benediction") == 2, "Guérison végétale : 2 Bénédictions")
	gho.effects.erase(gho.get_effect("shield"))
	gho.hp = gho.max_hp() * 0.35
	e._apply_damage(gho, gho.max_hp() * 0.1, unit_of(e, "mohamed"), {})
	check(gho.hp_ratio() > 0.45 and not gho.has_effect("benediction"), "Bénédiction : soin de 25 % sous 30 % PV")
	# Noor-El : Espéra par dégât de zone ; à 5, sa zone suivante frappe deux fois
	e = BattleEngine.new(["noor_el"], ["don_diego", "moussa"], 4)
	noor_check(e)
	# Jo : Gravité (bloque les bonus de VIT ; cible sans jauge entravée)
	e = BattleEngine.new(["jo_prince"], ["ghost"], 4)
	gho = unit_of(e, "ghost")
	gho.ap = 0.0
	e._try_apply(unit_of(e, "jo_prince"), gho, {"id": "gravite", "no_roll": true})
	check(gho.has_effect("entrave"), "Gravité : cible sans jauge entravée")
	check(not e._try_apply(gho, gho, {"id": "spd_up", "value": 30, "turns": 2}), "Gravité : bonus de VIT refusé")
	# Ezra : Vide (plus de buffs ni de soins, non purgeable) ; suppression des buffs avec bonus ; vol de buff
	e = BattleEngine.new(["ezra"], ["noor_el", "flint"], 4)
	var ez := unit_of(e, "ezra")
	var noor := unit_of(e, "noor_el")
	for b in ["atk_up", "def_up", "cr_up"]:
		e._try_apply(noor, noor, {"id": b, "value": 20, "turns": 3})
	e.execute(ez, ez.skill(1), noor, 1)
	check(not noor.has_buff() and noor.has_effect("vide"), "Null Void ciblé : buffs supprimés, Vide posé")
	var n_hp := noor.hp
	e._heal(noor, 500.0, unit_of(e, "flint"))
	e._apply_action(unit_of(e, "flint"), noor, {"id": "cleanse"}, {})
	check(noor.hp == n_hp and noor.has_effect("vide"), "Vide : pas de soin, non purgeable")
	var fl := unit_of(e, "flint")
	e._try_apply(fl, fl, {"id": "atk_up", "value": 20, "turns": 3})
	for i in 8:
		if ez.has_effect("atk_up"):
			break
		e.execute(ez, ez.skill(0), fl, 0)
	check(ez.has_effect("atk_up") and not fl.has_effect("atk_up"), "Muay Thai : buff volé")
	# Flint : Révélé (retire l'Immunité, +10 % de dégâts par cumul, +5 % de jauge aux alliés qui frappent)
	e = BattleEngine.new(["flint", "ghost"], ["moussa"], 4)
	mou = unit_of(e, "moussa")
	e._try_apply(mou, mou, {"id": "immunity", "turns": 2})
	e._try_apply(unit_of(e, "flint"), mou, {"id": "revele", "stacks": 2, "no_roll": true})
	check(not mou.has_effect("immunity") and not e._try_apply(mou, mou, {"id": "immunity", "turns": 2}), "Révélé : Immunité retirée et refusée")
	approx(e._taken_mult(mou), 1.2, "Révélé x2 : +20 % de dégâts subis")
	gho = unit_of(e, "ghost")
	gho.ap = 0.0
	e._on_targeted(gho, [mou])
	approx(gho.ap, 0.05, "Révélé : l'allié qui frappe gagne 5 % de jauge")
	# Don Selah : immunisé, 50 % de PA, Lien (partage 30 %, bouclier à sa mort), Scellement (contrecoup)
	e = BattleEngine.new(["don_selah", "flint"], ["ezra", "moussa"], 4)
	var ds := unit_of(e, "don_selah")
	check(is_equal_approx(ds.ap, 0.5), "Éveil : commence à 50 % PA")
	e._try_apply(unit_of(e, "ezra"), ds, {"id": "stun", "turns": 1, "no_roll": true, "ignores_immunity": true})
	check(not ds.has_effect("stun"), "Éveil : immunisé même contre « ignore l'immunité »")
	fl = unit_of(e, "flint")
	e._try_apply(ds, fl, {"id": "lien"})
	var ds_hp := ds.hp
	e._apply_damage(fl, 1000.0, unit_of(e, "ezra"), {})
	approx(fl.max_hp() - fl.hp, 700.0, "Lien : l'allié subit 70 %")
	approx(ds_hp - ds.hp, 300.0, "Lien : Don Selah absorbe 30 %")
	e._try_apply(ds, ds, {"id": "scellement"})
	var m_hp := unit_of(e, "moussa").hp
	e.current = ds
	e._end_turn(ds)
	approx(m_hp - unit_of(e, "moussa").hp, roundf(unit_of(e, "moussa").max_hp() * 0.15), "Scellement : contrecoup de 15 % à l'expiration", 1.0)
	e._apply_damage(ds, 99999.0, unit_of(e, "ezra"), {})
	check(not fl.has_effect("lien") and fl.shield_value() > 0.0, "Lien : Don tombe, bouclier de 20 % pour l'allié")


func noor_check(e: BattleEngine) -> void:
	var noor := unit_of(e, "noor_el")
	var dd := unit_of(e, "don_diego")
	e.execute(noor, noor.skill(1), null, 1)
	check(dd.status_stacks("espera") == 1, "Souffle glacial : Espéra sur chaque ennemi touché")
	approx(e._taken_mult(dd), 1.05, "Espéra x1 : +5 % de dégâts subis")
	for i in 4:
		e._try_apply(noor, dd, {"id": "espera", "no_roll": true})
	check(noor.flags.has("double_aoe"), "Espéra x5 : la zone suivante frappera deux fois")


## Effets génériques (fiche, parties 4 et 5) : Invincibilité, Bloc, Anti-soin, Régénération, Sommeil,
## raté du triangle, « ne peut pas être résisté », égalité de vitesse.
func test_generic_effects() -> void:
	print("Effets génériques (Dislyte, Etheria)")
	var e := BattleEngine.new(["mohamed"], ["issa", "moussa"], 6)
	var moh := unit_of(e, "mohamed")
	var issa := unit_of(e, "issa")
	e._try_apply(issa, issa, {"id": "invincible", "turns": 1})
	var hp := issa.hp
	e._deal_damage(moh, issa, 5000.0, {})
	check(issa.hp == hp, "Invincibilité : aucun dégât")
	issa.effects.clear()
	e._try_apply(moh, issa, {"id": "block", "turns": 2, "no_roll": true})
	check(not e._try_apply(issa, issa, {"id": "atk_up", "value": 20, "turns": 2}), "Bloc : buffs refusés")
	e._try_apply(moh, issa, {"id": "no_heal", "turns": 2, "no_roll": true})
	issa.hp = 1000.0
	e._heal(issa, 500.0, issa)
	check(issa.hp == 1000.0, "Anti-soin : pas de soin")
	moh.hp = 1000.0
	e._try_apply(moh, moh, {"id": "regen", "turns": 2})
	e._start_turn(moh)
	approx(moh.hp, 1000.0 + roundf(moh.max_hp() * 0.15), "Régénération : 15 % des PV max au début du tour")
	# Sommeil : le premier coup frappe 25 % plus fort
	var e2 := BattleEngine.new(["mohamed"], ["moussa"], 6)
	var mou := unit_of(e2, "moussa")
	var normal := e2.compute_damage(unit_of(e2, "mohamed"), mou, 1000.0, {}, false, 1.0)
	e2._try_apply(unit_of(e2, "mohamed"), mou, {"id": "sleep", "turns": 2, "no_roll": true})
	var before := mou.hp
	e2.rng.seed = 1
	e2._deal_damage(unit_of(e2, "mohamed"), mou, 1000.0, {"missed": false})
	check(before - mou.hp >= normal * 0.95 * 1.25 - 1.0 or before - mou.hp >= normal * 0.95 * 1.25 * 1.69 - 1.0, "Sommeil : +25 % sur le premier coup")
	# « Ne peut pas être résisté »
	mou.base["res"] = 900
	check(e2._try_apply(unit_of(e2, "mohamed"), mou, {"id": "def_break", "turns": 1, "cannot_resist": true}), "cannot_resist : passe malgré 900 RÉS")
	# Raté du triangle : le dominé rate, 25 % des dégâts, pas d'effet
	var tri: Dictionary = GameData.rules()["triangle"]
	var saved: float = tri["dominated_miss_chance"]
	tri["dominated_miss_chance"] = 100.0
	var e3 := BattleEngine.new(["eirikr"], ["mohamed"], 6)  # Orion contre Sirius : Orion est dominé
	var evs: Array[Dictionary] = []
	e3.battle_event.connect(func(ev: Dictionary) -> void: evs.append(ev))
	e3.execute(unit_of(e3, "eirikr"), unit_of(e3, "eirikr").skill(0), unit_of(e3, "mohamed"), 0)
	check(evs.any(func(ev: Dictionary) -> bool: return ev["type"] == "miss"), "Raté : le dominé rate")
	tri["dominated_miss_chance"] = saved
	# Égalité de vitesse : la position dans l'équipe départage
	var e4 := BattleEngine.new(["issa", "issa"], ["mohamed"], 6)
	var first := e4.next_turn()
	check(first.slot == 0 and first.team == 0, "Égalité de VIT : la première position joue d'abord")


## Prométhée (étage 12) : phases, résurrection, Aletheia prédictive, résistance aux contrôles.
func test_boss() -> void:
	print("Boss : Prométhée")
	var e := BattleEngine.new(["mello", "mikhaila"], Tower.enemy_units(12), 8)
	var pro: BattleUnit = e.units[2]
	var mel := unit_of(e, "mello")
	check(pro.id == "promethee" and pro.constellation == "neutre", "Étage 12 : Prométhée, neutre")
	check(Tower.floor_info(1)["decor"] == "acier" and Tower.floor_info(12)["decor"] == "forge", "Décors : Cité d'Acier, forge du boss")
	check(not e._try_apply(mel, pro, {"id": "freeze", "turns": 1, "no_roll": true}), "Boss final : immunisé au Gel")
	var stuns := 0
	for i in 200:
		pro.effects.clear()
		if e._try_apply(mel, pro, {"id": "stun", "turns": 1, "no_roll": true}):
			stuns += 1
	check(stuns > 70 and stuns < 130, "Boss : Étourdissement deux fois moins probable (%d / 200)" % stuns)
	pro.effects.clear()
	e._apply_damage(pro, pro.max_hp() * 0.55, mel, {})
	check(pro.flags.has("dmg_bonus_pct") and pro.flags.has("self_burn_pct"), "Phase 2 sous 50 % PV")
	var hp := pro.hp
	e._start_turn(pro)
	approx(hp - pro.hp, roundf(pro.max_hp() * 0.02), "Phase 2 : perd 2 % de ses PV max par tour", 1.0)
	e._apply_damage(pro, 999999.0, mel, {})
	check(pro.is_alive() and is_equal_approx(pro.hp_ratio(), 0.2), "Laboratoire infini : ressuscite à 20 % PV")
	e._apply_damage(pro, 999999.0, mel, {})
	check(not pro.is_alive(), "Laboratoire infini : une seule fois")
	# Aletheia : seulement contre un héros qui répète la même compétence
	var e2 := BattleEngine.new(["mello", "mikhaila"], Tower.enemy_units(12), 8)
	var p2: BattleUnit = e2.units[2]
	var m2 := unit_of(e2, "mello")
	var k2 := unit_of(e2, "mikhaila")
	m2.skill_history.assign([0, 2])
	k2.skill_history.assign([0, 2])
	check(not e2.ai_choose(p2)["skill"] == 1 or p2.cooldowns[1] > 0, "Aletheia : pas lancée sans héros prévisible")
	e2.execute(p2, p2.skill(1), m2, 1)
	check(not m2.has_effect("freeze"), "Aletheia : échoue si le héros a varié ses compétences")
	k2.skill_history.assign([0, 0])
	p2.cooldowns = [0, 0, 0]
	var c := e2.ai_choose(p2)
	check(c["skill"] == 2 or (c["skill"] == 1 and c["target"] == k2), "Aletheia : vise le héros prévisible")
	e2.execute(p2, p2.skill(1), k2, 1)
	check(k2.has_effect("freeze"), "Aletheia : désactive un héros qui répète sa compétence")
	e2.execute(p2, p2.skill(0), m2, 0)
	check(m2.status_stacks("clef") == 2, "Ignis Divinus : une Clef par coup")


## Boss de butin : mécaniques, récompenses, pitié, paliers, pénalité des équipes non dominantes.
func test_loot() -> void:
	print("Boss de butin")
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	check(LootBoss.ids().all(func(id: String) -> bool: return LootBoss.boss(id).has("decor")), "Chaque boss de butin a son décor")
	check(LootBoss.countered_by("chronophage") == "sirius" and LootBoss.countered_by("wyrm") == "orion", "Constellation qui domine chaque boss")
	# Chronophage : jauge gagnée à chaque tour d'un héros, dégâts croissants
	var e := BattleEngine.new(["mello"], LootBoss.enemy_units("chronophage", 0), 4)
	var ch: BattleUnit = e.units[1]
	ch.ap = 0.0
	var mel := unit_of(e, "mello")
	mel.ap = 1.0
	e.next_turn()
	check(ch.ap >= 0.05, "Chronophage : +5 % de jauge quand un héros joue")
	e._start_turn(ch)
	e._start_turn(ch)
	approx(float(ch.flags["dmg_bonus_pct"]), 12.0, "Chronophage : +6 % de dégâts par tour")
	# Wyrm : barre perdue -> bouclier ; bouclier intact à son tour -> Gel et écrasement
	e = BattleEngine.new(["mello", "adrian"], LootBoss.enemy_units("wyrm", 0), 4)
	var wy: BattleUnit = e.units[2]
	e._apply_damage(wy, wy.max_hp() * 0.4, unit_of(e, "adrian"), {})
	check(wy.shield_value() > 0.0 and wy.flags.has("bar_shield"), "Wyrm : barre perdue, bouclier")
	var mel_hp := unit_of(e, "mello").hp
	e._start_turn(wy)
	check(unit_of(e, "mello").has_effect("freeze") and unit_of(e, "mello").hp < mel_hp, "Wyrm : bouclier intact -> le héros le plus fort est gelé et écrasé")
	# Serpent : le Venin solaire explose à la fin (20 % PV max)
	e = BattleEngine.new(["adrian"], LootBoss.enemy_units("serpent", 0), 4)
	var adr := unit_of(e, "adrian")
	e._try_apply(e.units[1], adr, {"id": "venin_solaire", "no_roll": true})
	var hp := adr.hp
	for i in 4:
		e.current = adr
		e._end_turn(adr)
	approx(hp - adr.hp, roundf(adr.max_hp() * 0.2), "Venin solaire : explose à la fin (20 % des PV max)", 1.0)
	# Pénalité aux paliers élevés : seule la constellation dominante est épargnée
	e = BattleEngine.new(["noor_el", "montana"], LootBoss.enemy_units("chronophage", 3), 4)
	var boss: BattleUnit = e.units[2]
	var noor := unit_of(e, "noor_el")
	var mon := unit_of(e, "montana")
	var misses := [0, 0]
	for i in 200:
		if e._rolls_miss(noor, boss, noor.skill(0)):
			misses[0] += 1
		if e._rolls_miss(mon, boss, mon.skill(0)):
			misses[1] += 1
	check(misses[0] == 0 and misses[1] > 50, "Enfer : Sirius ne rate jamais le Chronophage, Orion rate (%d / 200)" % misses[1])
	approx(e.compute_damage(boss, mon, 1000.0, {}, false, 1.0) / e.compute_damage(boss, noor, 1000.0, {}, false, 1.0) *
		(1000.0 + mon.stat("def")) / (1000.0 + noor.stat("def")), 1.35 / 0.85, "Enfer : +35 % de dégâts sur les non-dominants", 0.02)
	# Récompenses, paliers, pitié
	var p := Profile.new_game()
	var rw := p.win_loot("wyrm", 0, rng)
	check(rw["relics"].size() == 2 and rw["relics"].all(func(r: Dictionary) -> bool: return r["set"] in ["gel", "vie", "precision"]), "Wyrm : 2 reliques de la Grande Ourse")
	check(p.loot_state("wyrm")["unlocked"] == 1, "Victoire en Facile : Difficile débloqué")
	var rw3 := LootBoss.rewards("wyrm", 3, rng)
	check(rw3["relics"].size() == 3 and rw3["relics"].all(func(r: Dictionary) -> bool: return int(r["level"]) == 9), "Enfer : 3 reliques déjà à +9")
	p.loot_state("wyrm")["pity_set"] = "precision"
	var forced := ""
	for i in 7:
		forced = p.win_loot("wyrm", 0, rng)["pity_used"]
	check(forced == "precision" and p.loot_state("wyrm")["pity"] == 0, "Pitié : relique du set choisi à la 8e victoire")
	var back := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	check(back.loot_state("wyrm")["wins"] == 8 and back.loot_state("wyrm")["pity_set"] == "precision", "Progression des boss de butin sauvegardée")


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
	check(active.get("vampirisme", 0) == 4 and active.get("vitesse", 0) == 2, "Set 4 + set 2 actifs")
	var u := Relics.make_unit("mohamed", gear)
	check(u.set_specials.has("lifesteal_20"), "Vampirisme transmis au combat")
	check(u.base["spd"] > 108 * 1.12 - 0.01, "Set Vitesse (2 pièces) : +12 % VIT")
	var atk4: Array = []
	for slot in range(1, 5):
		atk4.append(Relics.generate(rng, "attaque", slot))
	var with4: Dictionary = Relics.apply(GameData.character("mohamed")["stats"], atk4)["stats"]
	var with2: Dictionary = Relics.apply(GameData.character("mohamed")["stats"], atk4.slice(0, 2))["stats"]
	check(with4["cd"] - with2["cd"] >= 30.0, "Set Attaque (4 pièces) : +30 DC en plus du bonus à 2 pièces")


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
	# Énergie : se recharge pendant l'absence, étages gratuits au début, balayage
	var t0 := 1_000_000
	var q := Profile.new_game(t0)
	check(q.energy == 120 and q.floor_cost(4) == 0 and q.floor_cost(5) == 6, "Énergie : 120 au départ, étages 1-4 gratuits")
	check(q.spend_energy(30, t0) and q.energy == 90, "Énergie : dépense")
	q.refresh_energy(t0 + 300 * 10 + 20)
	check(q.energy == 100 and q.energy_next_in(t0 + 300 * 10 + 20) == 280, "Énergie : +1 toutes les 5 min, même absent")
	q.refresh_energy(t0 + 300 * 999)
	check(q.energy == 120, "Énergie : plafonnée à 120")
	q.tower_cleared = 6
	var sw := q.sweep_floor(6, 5, rng, t0 + 300 * 999)
	check(int(sw["times"]) == 5 and q.energy == 90 and sw["relics"].size() == 5, "Balayage x5 : 30 d'énergie, 5 reliques")
	check(int(q.sweep_floor(7, 1, rng, t0)["times"]) == 0, "Balayage : seulement les étages gagnés")
	# Recyclage intégral : toutes les Pièces investies reviennent
	var r2: Dictionary = q.relics[0]
	var u2 := int(r2["uid"])
	q.add("pieces", 100000)
	q.owned["ghost"] = 1
	q.equip("ghost", u2)
	for i in 5:
		q.level_relic(u2, rng)
	var before := q.amount("pieces")
	var gain := q.recycle_relic(u2)
	check(gain == 50 + 100 + 200 + 300 + 400 + 500 and q.amount("pieces") == before + gain, "Recyclage : Pièces investies rendues (+50)")
	check(q.relic(u2).is_empty() and q.equipped_relics("ghost").is_empty(), "Recyclage : relique retirée et déséquipée")
	# Formations : équipe et reliques réappliquées, reliques déplacées si besoin
	q.owned["mello"] = 1
	var ra := int(q.relics[0]["uid"])
	q.set_team(["ghost", "issa"])
	q.equip("ghost", ra)
	q.save_formation(0)
	q.set_team(["mello"])
	q.equip("mello", ra)
	check(q.apply_formation(0) and q.team == ["ghost", "issa"] and q.owner_of(ra) == "ghost", "Formation : équipe et relique réappliquées")
	var eclats := q.amount("eclat_de_voeu")
	check(q.apply_grants().size() == 1 and q.amount("eclat_de_voeu") == eclats + 3000, "Cadeau de test : 3 000 Éclats versés")
	check(q.apply_grants().is_empty() and q.amount("eclat_de_voeu") == eclats + 3000, "Cadeau de test : une seule fois")
	var q2 := Profile.from_dict(JSON.parse_string(JSON.stringify(q.to_dict())))
	check(q2.apply_grants().is_empty(), "Cadeau de test : mémorisé dans la sauvegarde")
	check(q2.energy == q.energy and q2.formations.size() == q.formations.size() and q2.apply_formation(0), "Énergie et formations sauvegardées")


## Une équipe de Légendaires doit battre largement une équipe de Rares (et les Épiques aussi).
func test_battle_stats() -> void:
	print("Bilan de combat")
	var e := BattleEngine.new(GameData.nation_team("A"), GameData.nation_team("C"), 5)
	var guard := 0
	while e.winner == BattleEngine.ONGOING and guard < 400:
		var u := e.next_turn()
		guard += 1
		if u == null or not u.is_alive():
			continue
		if not e.can_act(u):
			e.skip_turn(u)
			continue
		var c := e.ai_choose(u)
		e.use_skill(u, c["skill"], c["target"])
	for team in 2:
		var dealt := 0.0
		var taken := 0.0
		for u in e.units:
			if u.team == team:
				dealt += float(e.stats[u]["dealt"])
			else:
				taken += float(e.stats[u]["taken"])
		approx(dealt, taken, "Équipe %d : dégâts infligés = dégâts subis en face" % team, 1.0)
	check(e.units.any(func(u: BattleUnit) -> bool: return float(e.stats[u]["dealt"]) > 0.0), "Bilan : des dégâts comptés")


func test_tactics() -> void:
	print("Mode tactique de la Tour")
	var tt: Dictionary = GameData.rules()["tower_tactics"]
	var e := BattleEngine.new(["montana", "mikhaila", "ghost"], ["adrian", "mello", "tarkhan"], 9)
	var mon := unit_of(e, "montana")
	var adr := unit_of(e, "adrian")
	check(e.tactics.is_empty() and (2 in e.usable_skills(mon)) == (mon.cooldowns[2] == 0), "Hors Tour : règles de base")
	e.enable_tactics()
	check(e.sp == int(tt["sp_start"]) and e.sp_max == int(tt["sp_max"]), "Sceaux de départ")
	check(adr.max_toughness == float(tt["toughness"]["normal"]) and adr.weakness == ["orion"], "Ténacité et faiblesse (constellation dominante)")
	check(not 2 in e.usable_skills(mon) and 1 in e.usable_skills(mon), "Ultime hors des compétences du tour, S2 payable")
	e.sp = 0
	check(not 1 in e.usable_skills(mon), "S2 impossible sans Sceau")
	e.current = mon
	var energy0 := mon.energy
	e.use_skill(mon, 0, adr)
	check(e.sp == 1 and mon.energy >= energy0 + float(tt["energy_gain"][0]), "S1 : +1 Sceau et de l'énergie")
	check(adr.toughness < adr.max_toughness, "La constellation dominante entame la Ténacité")
	adr.toughness = 1.0
	adr.ap = 0.5
	e.current = mon
	e.use_skill(mon, 0, adr)
	check(adr.broken and adr.ap <= 0.2 + 1e-6, "Rupture : recul sur la barre d'action")
	var m_broken := e._taken_mult(adr)
	adr.broken = false
	approx(m_broken / e._taken_mult(adr), 1.0 + float(tt["break_dmg_taken_pct"]) / 100.0, "Rupture : dégâts subis accrus")
	adr.broken = true
	e._start_turn(adr)
	check(not adr.broken and adr.toughness == adr.max_toughness, "Fin de Rupture : Ténacité reconstituée")
	mon.energy = float(tt["energy_max"])
	var acts := e.team_actions
	check(e.ult_ready(mon), "Énergie pleine : ultime prêt")
	e.cast_ultimate(mon)
	check(mon.energy < float(tt["energy_max"]) * 0.5 and e.team_actions == acts, "Ultime hors tour : énergie vidée, aucun tour consommé")
	var b := BattleEngine.new(["montana", "mikhaila", "ghost"], Tower.enemy_units(12), 4)
	b.enable_tactics()
	var boss: BattleUnit = b.units[3]
	check(boss.max_toughness == float(tt["toughness"]["boss"]) and not boss.weakness.is_empty(), "Boss : Ténacité et faiblesses propres")
	for k in int(tt["charge"]["every"]):
		boss.flags.erase("charge_turn")
		b._boss_charge(boss)
	check(boss.charging == 1 and boss.is_skipping(), "Boss : charge télégraphiée (il passe son tour)")
	var hp0 := 0.0
	for u in b.units:
		if u.team == 0:
			hp0 += u.hp
	b.skip_turn(boss)
	b._boss_charge(boss)
	var hp1 := 0.0
	for u in b.units:
		if u.team == 0:
			hp1 += u.hp
	check(hp1 < hp0 and boss.charging == 0, "Charge non brisée : Oblitération sur l'équipe")
	var w := BattleEngine.new(["montana", "adrian", "noor_el"], ["ghost"], 3)
	w.enable_tactics()
	check(w.sp_max == int(tt["sp_max"]) + int(tt["resonance"]["triad_sp_max"]), "Triade : un Sceau max de plus")
	var t := BattleEngine.new(["montana", "mikhaila", "ghost"], ["adrian", "mello", "tarkhan"], 11)
	t.enable_tactics()
	check(t.run_auto() != BattleEngine.ONGOING, "Combat tactique automatique jusqu'au bout")
	var pr := Profile.new_game()
	var ecl := pr.amount("eclat_de_voeu")
	var r1 := pr.record_stars(3, 1 | 2)
	var r2 := pr.record_stars(3, 1 | 4)
	check(int(r1["new"]) == 2 and int(r2["new"]) == 1 and pr.floor_stars(3) == 7, "Étoiles d'étage cumulées")
	check(pr.amount("eclat_de_voeu") == ecl + 3 * int(tt["star_reward"]["eclat_de_voeu"]), "Chaque nouvelle étoile rapporte des Éclats")
	var saved := Profile.from_dict(pr.to_dict())
	check(saved.floor_stars(3) == 7, "Étoiles sauvegardées")
	check(Tower.floor_count() == 25 and Tower.floor_info(25).get("boss_unit", "") == "geode" and Tower.floor_info(13)["decor"] == "gemmes",
		"Univers 02 : étages 13 à 25, boss Impératrice Géode")


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
## Tour en mode tactique (Sceaux, Ténacité, ultimes hors tour), sans reliques.
func simulate_tower(n: int) -> void:
	var teams := {"Départ (Nidhogg, Espion, Issa)": ["nidhogg", "espion_lumiere", "issa"],
		"Mixte (Eiríkr, Issa, Don Diego)": ["eirikr", "issa", "don_diego"],
		"Triade v2 (Montana, Adrian, Noor-El)": ["montana", "adrian", "noor_el"],
		"Épiques (Ghost, Tarkhan, Jo Prince)": ["ghost", "tarkhan", "jo_prince"]}
	print("
Tour tactique, sans reliques (%d combats par étage) :" % n)
	for name: String in teams:
		var line: Array[String] = []
		for f in range(1, Tower.floor_count() + 1):
			line.append("%d:%d%%" % [f, roundi(100.0 * tower_wins(teams[name], f, n) / n)])
		print("  %-38s %s" % [name, " ".join(line)])


func tower_wins(ids: Array, f: int, n: int) -> int:
	var wins := 0
	for k in n:
		var players: Array[BattleUnit] = []
		for id: String in ids:
			players.append(BattleUnit.new(GameData.character(id), 0, players.size()))
		var e := BattleEngine.new(players, Tower.enemy_units(f), 7000 + k)
		e.enable_tactics(Tower.tactics_rank(f))
		if e.run_auto() == 0:
			wins += 1
	return wins


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
