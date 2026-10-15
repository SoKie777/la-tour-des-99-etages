extends SceneTree
## Réglage du roster v2 : durée des combats, force des nations (équipes tirées au hasard), poids du triangle.
## godot --headless --path . --script res://tools/tune_v2.gd -- [combats] [hp_mult,...] [miss,...] [tc,...] [dmg,...]
## Les réglages sont appliqués en mémoire (les JSON ne changent pas).


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 120
	var hp_mults := _floats(args, 1, [1.0])
	var misses := _floats(args, 2, [0.0])
	var tcs := _floats(args, 3, [20.0])
	var dmgs := _floats(args, 4, [0.85])
	var pools := {}
	for nat in ["A", "B", "C"]:
		pools[nat] = GameData.character_ids_by_nation(nat).filter(func(id: String) -> bool:
			var c := GameData.character(id)
			return int(c["rarity"]) >= 4 and c["class"] != "titan")
	var rares := {}
	for nat in ["A", "B", "C"]:
		rares[nat] = GameData.nation_team(nat, 3)
	var base_hp := {}
	for id: String in GameData.characters():
		base_hp[id] = float(GameData.character(id)["stats"]["hp"])
	var tri: Dictionary = GameData.rules()["triangle"]
	print("PV v2 | raté | TC dom. | dégâts dominé || A>B  B>C  C>A | tours/perso v2 | tours Rares | 5★ vs 3★")
	for hm: float in hp_mults:
		for id: String in base_hp:
			if int(GameData.character(id)["rarity"]) >= 4:
				GameData.character(id)["stats"]["hp"] = roundf(base_hp[id] * hm)
		for mi: float in misses:
			for tc: float in tcs:
				for dm: float in dmgs:
					tri["dominated_miss_chance"] = mi
					tri["dominant_crit_bonus"] = tc
					tri["dominated_damage_mult"] = dm
					var rng := RandomNumberGenerator.new()
					rng.seed = 5
					var line := "%5.2f | %4d | %7d | %13.2f ||" % [hm, int(mi), int(tc), dm]
					var turns := 0.0
					for pair in [["A", "B"], ["B", "C"], ["C", "A"]]:
						var w := 0
						for k in n:
							var a := _pick(pools[pair[0]], rng)
							var b := _pick(pools[pair[1]], rng)
							var swap := k % 2 == 1
							var e := BattleEngine.new(b if swap else a, a if swap else b, 100 + k)
							var r := e.run_auto()
							if r != BattleEngine.DRAW and ((r == 0) != swap):
								w += 1
							turns += _turns(e)
						line += " %3d%%" % roundi(100.0 * w / n)
					var rt := 0.0
					for pair in [["A", "B"], ["B", "C"], ["C", "A"]]:
						for k in 20:
							var e := BattleEngine.new(rares[pair[0]], rares[pair[1]], 300 + k)
							e.run_auto()
							rt += _turns(e)
					var lw := 0
					for k in 40:
						var e := BattleEngine.new(_pick(pools["A"] + pools["B"] + pools["C"], rng).filter(func(id: String) -> bool:
							return true), _pick(rares["A"] + rares["B"] + rares["C"], rng), 500 + k)
						if e.run_auto() == 0:
							lw += 1
					line += " | %14.1f | %11.1f | %3d%%" % [turns / (3 * n), rt / 60.0, roundi(100.0 * lw / 40)]
					print(line)
	quit()


func _floats(args: PackedStringArray, i: int, default: Array) -> Array:
	if args.size() <= i:
		return default
	return Array(args[i].split(",")).map(func(x: String) -> float: return float(x))


func _pick(pool: Array, rng: RandomNumberGenerator) -> Array:
	var p := pool.duplicate()
	var out: Array = []
	for i in 3:
		out.append(p.pop_at(rng.randi() % p.size()))
	return out


func _turns(e: BattleEngine) -> float:
	var acts := 0
	for u in e.units:
		acts += u.actions_taken
	return acts / 6.0
