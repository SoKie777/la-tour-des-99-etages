extends SceneTree
## Réglage des boss de butin : taux de victoire par palier, équipe de chaque nation (sans reliques).
## godot --headless --path . --script res://tools/tune_loot.gd -- [combats] [pv_mult,...] [atk_mult,...] [paliers ex. 0,1,3]
## Les multiplicateurs s'appliquent en mémoire aux PV et à l'ATK de base des trois boss.


## Équipes équilibrées (2 attaquants + 1 soutien) de chaque nation.
const TEAMS := {"A": ["montana", "ghost", "mikhaila"], "B": ["mello", "adrian", "saraya"], "C": ["noor_el", "jo_prince", "flint"]}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 40
	var hps := _list(args, 1, [1.0])
	var atks := _list(args, 2, [1.0])
	var diffs := _list(args, 3, [0, 1, 3])
	var base := {}
	for id: String in LootBoss.ids():
		base[id] = LootBoss.boss(id)["stats"].duplicate()
	for hm: float in hps:
		for am: float in atks:
			for id: String in LootBoss.ids():
				var b := LootBoss.boss(id)
				b["stats"]["hp"] = roundf(float(base[id]["hp"]) * hm)
				b["stats"]["atk"] = roundf(float(base[id]["atk"]) * am)
				print(_line(id, n, diffs, "PV x%.2f ATK x%.2f " % [hm, am]))
	print("* = constellation qui domine le boss ; (t) = tours du boss")
	quit()


func _line(id: String, n: int, diffs: Array, prefix: String) -> String:
	var nation_of := {"orion": "A", "grande_ourse": "B", "sirius": "C"}
	var dom: String = nation_of[LootBoss.countered_by(id)]
	var line := prefix + "%-18s" % LootBoss.boss(id)["name"]
	for nat in ["A", "B", "C"]:
		for diff: float in diffs:
			var w := 0
			var turns := 0.0
			for k in n:
				var players: Array[BattleUnit] = []
				for cid in TEAMS[nat]:
					players.append(BattleUnit.new(GameData.character(cid), 0, players.size()))
				var e := BattleEngine.new(players, LootBoss.enemy_units(id, int(diff)), 900 + k)
				if e.run_auto() == 0:
					w += 1
				turns += e.units[3].actions_taken
			line += " | %s%s %s %3d%% (%2d t)" % [nat, "*" if nat == dom else " ", LootBoss.difficulty(int(diff))["name"].substr(0, 4),
				roundi(100.0 * w / n), roundi(turns / n)]
	return line


func _list(args: PackedStringArray, i: int, default: Array) -> Array:
	if args.size() <= i:
		return default
	return Array(args[i].split(",")).map(func(x: String) -> float: return float(x))
