extends SceneTree
## Aide au réglage de data/tower.json : taux de victoire par étage selon la puissance des ennemis.
## godot --headless --path . --script res://tools/tune_tower.gd


func _init() -> void:
	var teams := {"depart": ["nidhogg", "espion_lumiere", "issa"], "mixte": ["eirikr", "issa", "don_diego"]}
	var powers := [0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.3]
	var n := 30
	for f in range(1, Tower.floor_count() + 1):
		var info := Tower.floor_info(f)
		var line := "Étage %2d %-45s" % [f, str(info["enemies"])]
		for t: String in teams:
			line += " | " + t
			for pw: float in powers:
				info["power"] = pw
				var wins := 0
				for k in n:
					var players: Array[BattleUnit] = []
					for id: String in teams[t]:
						players.append(BattleUnit.new(GameData.character(id), 0, players.size()))
					var enemies: Array[BattleUnit] = []
					for id: String in info["enemies"]:
						var d := GameData.character(id)
						var st: Dictionary = d["stats"].duplicate()
						for s in ["hp", "atk", "def"]:
							st[s] = float(st[s]) * pw
						enemies.append(BattleUnit.new(d, 1, enemies.size(), st))
					if BattleEngine.new(players, enemies, 9000 + k).run_auto() == 0:
						wins += 1
				line += " %3d" % roundi(100.0 * wins / n)
		print(line)
	print("Puissances testées : ", powers)
	quit()
