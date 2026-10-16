extends SceneTree
## Aide au réglage de data/prologue.json : taux de victoire par niveau (mode tactique, sans reliques).
## Les niveaux « safe » sont joués sans la protection, pour voir leur vraie difficulté.
## godot --headless --path . --script res://tools/tune_prologue.gd -- [combats]


const TEAMS := {
	"eirikr": ["eirikr"],
	"eir+yass+rare": ["eirikr", "yass", "issa"],
	"mello+yass+eir": ["mello", "yass", "eirikr"],
	"mello+yass+epique": ["mello", "yass", "ghost"],
	"mello+rares": ["mello", "eirikr", "issa"],
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 40
	print("Niveau | " + " | ".join(TEAMS.keys()))
	for lv in range(1, Prologue.level_count() + 1):
		var line := "%6d" % lv
		for t: String in TEAMS:
			var wins := 0
			for k in n:
				var e := BattleEngine.new(TEAMS[t], Prologue.enemy_units(lv), 9000 + k)
				e.enable_tactics(Prologue.tactics_rank(lv))
				if e.run_auto() == 0:
					wins += 1
			line += " | %3d%%" % roundi(100.0 * wins / n)
		print(line)
	quit()
