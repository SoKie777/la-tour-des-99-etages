extends SceneTree
## Parcours automatique sur un profil de test (étage 1, invocation x10, relique équipée) avec captures :
## godot --path . --script res://tools/playtest.gd -- --save=user://profil_test.json <dossier_captures>


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[-1]
	await process_frame
	var S: Node = root.get_node("/root/Session")  # autoload : pas accessible par son nom dans un --script
	root.size = Vector2i(1280, 720)
	S.reset_profile()
	S.auto_battle = true
	S.battle_speed = 3.0
	S.start_tower_floor(1)
	await create_timer(1.0).timeout
	_shot(out + "/pt_1_combat.png")
	var t := 0.0
	while not current_scene.get("done") and t < 90.0:
		await create_timer(0.5).timeout
		t += 0.5
	await create_timer(1.0).timeout
	_shot(out + "/pt_2_resultat.png")
	print("Étage 1 : vainqueur ", current_scene.engine.winner, " · reliques ", S.profile.relics.size())

	change_scene_to_file("res://scenes/summon.tscn")
	await create_timer(0.5).timeout
	current_scene._pull(10)
	await create_timer(1.0).timeout
	_shot(out + "/pt_3_invocation.png")

	var p: Profile = S.profile
	if not p.relics.is_empty():
		p.equip(p.team[0], int(p.relics[0]["uid"]))
		p.level_relic(int(p.relics[0]["uid"]), S.rng)
	change_scene_to_file("res://scenes/collection.tscn")
	await create_timer(0.5).timeout
	var tabs: TabContainer = current_scene.find_children("*", "TabContainer", true, false)[0]
	tabs.current_tab = 1
	if not p.relics.is_empty():
		current_scene._pick_slot(int(p.relics[0]["slot"]))
	await create_timer(1.0).timeout
	_shot(out + "/pt_4_reliques.png")
	tabs.current_tab = 0
	await create_timer(0.3).timeout
	_shot(out + "/pt_5_fiche.png")
	change_scene_to_file("res://scenes/tower.tscn")
	await create_timer(1.0).timeout
	_shot(out + "/pt_6_tour.png")
	quit()


func _shot(path: String) -> void:
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)
