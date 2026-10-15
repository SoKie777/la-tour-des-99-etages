extends SceneTree
## Aperçu des contrôles visibles en combat (Gel, Étourdissement, Sommeil, Poison, Malédiction) :
## godot --path . --script res://tools/status_preview.gd -- sortie.png


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	await process_frame
	var S: Node = root.get_node("/root/Session")
	root.size = Vector2i(1280, 720)
	S.auto_battle = false
	S.battle = {"mode": "test", "player": ["montana", "mikhaila", "ghost"], "enemy": ["noor_el", "ezra", "jo_prince"]}
	change_scene_to_file("res://scenes/battle.tscn")
	await create_timer(0.6).timeout
	var sc: Node = current_scene
	var e: BattleEngine = sc.engine
	var looks := [["montana", "freeze"], ["mikhaila", "stun"], ["ghost", "poison"], ["noor_el", "sleep"], ["ezra", "stun"], ["jo_prince", "curse"]]
	for pair in looks:
		for u in e.units:
			if u.id == pair[0]:
				e._try_apply(u, u, {"id": pair[1], "turns": 3, "no_roll": true, "self_cost": true})
				sc._status_look(u)
	await create_timer(1.6).timeout
	root.get_texture().get_image().save_png(out)
	print("SHOT ", out)
	quit()
