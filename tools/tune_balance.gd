extends SceneTree
## Compare des variantes d'équilibrage (modifiées en mémoire, sans toucher aux JSON) :
## godot --headless --path . --script res://tools/tune_balance.gd


func _init() -> void:
	var rules := GameData.rules()
	var tri: Dictionary = rules["triangle"]
	var nid: Dictionary = GameData.character("nidhogg")["skills"][2]
	var variants := [
		["Actuel (+20 TC / -15 %)", func() -> void: pass],
		["Triangle adouci (+15 TC / -10 %)", func() -> void:
			tri["dominant_crit_bonus"] = 15
			tri["dominated_damage_mult"] = 0.9],
		["+ IA qui épargne les endormis", func() -> void:
			rules["ai_avoid_sleeping"] = true],
		["+ Couronne de Nidhogg : bouclier 15 % PV", func() -> void:
			nid["effects"].append({"id": "shield", "value": 15, "of": "caster_max_hp", "turns": 2})],
	]
	var teams := {"A": GameData.character_ids_by_nation("A"), "B": GameData.character_ids_by_nation("B"), "C": GameData.character_ids_by_nation("C")}
	var n := 200
	for v in variants:
		v[1].call()  # les variantes se cumulent
		var line := "%-42s" % v[0]
		for pair in [["A", "B"], ["B", "C"], ["C", "A"]]:
			var w := 0
			for k in n:
				var swap := k % 2 == 1
				var e := BattleEngine.new(teams[pair[1]] if swap else teams[pair[0]], teams[pair[0]] if swap else teams[pair[1]], 1000 + k)
				var r := e.run_auto()
				if r != BattleEngine.DRAW and ((r == 0) != swap):
					w += 1
			line += " | %s>%s %3d %%" % [pair[0], pair[1], roundi(100.0 * w / n)]
		print(line)
	quit()
