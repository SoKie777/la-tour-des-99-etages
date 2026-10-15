extends SceneTree
## Aide au réglage de data/tower.json (mode tactique) : taux de victoire par étage, sans reliques.
## godot --headless --path . --script res://tools/tune_tower.gd -- [premier] [dernier] [combats]


const TEAMS := {
	"depart": ["nidhogg", "espion_lumiere", "issa"],
	"mixte": ["eirikr", "issa", "don_diego"],
	"triade5": ["montana", "adrian", "noor_el"],
	"epiques": ["ghost", "tarkhan", "jo_prince"],
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var first := int(args[0]) if args.size() > 0 else 1
	var last := int(args[1]) if args.size() > 1 else Tower.floor_count()
	var n := int(args[2]) if args.size() > 2 else 20
	print("Étage | " + " | ".join(TEAMS.keys()))
	for f in range(first, last + 1):
		var line := "%5d" % f
		for t: String in TEAMS:
			var wins := 0
			for k in n:
				var players: Array[BattleUnit] = []
				for id: String in TEAMS[t]:
					players.append(BattleUnit.new(GameData.character(id), 0, players.size()))
				var e := BattleEngine.new(players, Tower.enemy_units(f), 9000 + k)
				e.enable_tactics(Tower.tactics_rank(f))
				if e.run_auto() == 0:
					wins += 1
			line += " | %3d %%" % roundi(100.0 * wins / n)
		print(line)
	quit()
