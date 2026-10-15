extends SceneTree
## Réglage d'un boss : taux de victoire de plusieurs équipes (sans reliques) selon ses PV et son ATK.
## godot --headless --path . --script res://tools/tune_boss.gd -- <boss> <combats> <pv,...> <atk,...> [palier]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var boss_id: String = args[0] if args.size() > 0 else "promethee"
	var n := int(args[1]) if args.size() > 1 else 60
	var hps := Array(args[2].split(",")).map(func(x: String) -> float: return float(x)) if args.size() > 2 else [1.0]
	var atks := Array(args[3].split(",")).map(func(x: String) -> float: return float(x)) if args.size() > 3 else [1.0]
	var diff: String = args[4] if args.size() > 4 else "facile"
	var teams := {
		"Rares (départ)": ["nidhogg", "espion_lumiere", "issa"],
		"Rares (mixte)": ["eirikr", "issa", "don_diego"],
		"Épiques": ["ghost", "saraya", "selene"],
		"2 Lég. + 1 Ép.": ["montana", "mikhaila", "ghost"],
		"Légendaires": ["mello", "mikhaila", "adrian"],
	}
	var base: Dictionary = GameData.boss(boss_id)["stats"].duplicate()
	print("PV x | ATK x || " + " | ".join(teams.keys()) + " || tours du boss")
	for hm: float in hps:
		for am: float in atks:
			GameData.boss(boss_id)["stats"]["hp"] = roundf(float(base["hp"]) * hm)
			GameData.boss(boss_id)["stats"]["atk"] = roundf(float(base["atk"]) * am)
			var line := "%4.2f | %5.2f ||" % [hm, am]
			var boss_turns := 0.0
			for t: String in teams:
				var w := 0
				for k in n:
					var players: Array[BattleUnit] = []
					for id: String in teams[t]:
						players.append(BattleUnit.new(GameData.character(id), 0, players.size()))
					var e := BattleEngine.new(players, Tower.enemy_units(12, diff), 800 + k)
					if e.run_auto() == 0:
						w += 1
					boss_turns += e.units[3].actions_taken
				line += " %3d%%" % roundi(100.0 * w / n)
			print(line + " || %.1f" % (boss_turns / (n * teams.size())))
	quit()
