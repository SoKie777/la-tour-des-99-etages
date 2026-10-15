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
	test_gacha()
	test_relics()
	test_profile()
	simulate_balance(sims)
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
	check(max_gap <= 120, "Pity : Légendaire garanti en 120 invocations max (pire cas %d)" % max_gap)
	check(max_gap4 <= 20, "Épique ou mieux toutes les 20 invocations (pire cas %d)" % max_gap4)
	print("  Taux observés sur 100 000 : 3★ %.2f %% | 4★ %.2f %% | 5★ %.2f %%" % [counts[3] / 1000.0, counts[4] / 1000.0, counts[5] / 1000.0])
	var f := Gacha.new("featured_eirikr", 9)
	var hits := 0
	var fives := 0
	for i in 50000:
		var r := f.pull()
		if r["rarity"] == 5:
			fives += 1
			if r["id"] == "eirikr":
				hits += 1
	print("  Bannière vedette : Eiríkr = %.1f %% des 5★" % (100.0 * hits / fives))
	check(hits > fives / 5, "Vedette pondérée x2")


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
	var teams := {
		"A (Orion)": GameData.character_ids_by_nation("A"),
		"B (Grande Ourse)": GameData.character_ids_by_nation("B"),
		"C (Sirius)": GameData.character_ids_by_nation("C"),
	}
	print("\nSimulation d'équilibrage (%d combats par duel, IA des deux côtés)" % n)
	duel_table(teams, n)
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
		var e := BattleEngine.new(mixed, teams["B (Grande Ourse)"], 5000 + k)
		var w := e.run_auto()
		if w in [0, 1]:
			w2[w] += 1
	print("  Mixte (Eiríkr, Issa, Don Diego) vs B : %.1f %% de victoires" % (100.0 * w2[0] / n))


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
