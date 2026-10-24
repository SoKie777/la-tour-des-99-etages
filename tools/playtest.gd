extends SceneTree
## Parcours automatique sur un profil de test (campagne 1-1 et 1-2, invocation x10, montée rapide, Patrouille) avec captures :
## godot --path . --script res://tools/playtest.gd -- --save=user://profil_test.json <dossier_captures>


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[-1]
	await process_frame
	var S: Node = root.get_node("/root/Session")  # autoload : pas accessible par son nom dans un --script
	root.size = Vector2i(1280, 720)
	S.reset_profile()
	S.profile.seen_tips["rt_basics"] = true  # l'explication du premier combat met le combat en pause
	S.auto_battle = true
	S.battle_speed = 3.0
	for stage in [1, 2]:
		S.start_stage(stage)
		await create_timer(1.5).timeout
		_shot(out + "/pt_%d_combat.png" % stage)
		var t := 0.0
		while not current_scene.get("done") and t < 120.0:
			await create_timer(0.5).timeout
			t += 0.5
		await create_timer(1.0).timeout
		_shot(out + "/pt_%d_resultat.png" % stage)
		print("Étape %d : vainqueur %d · étapes gagnées %d" % [stage, current_scene.engine.winner, S.profile.campaign_cleared])

	change_scene_to_file("res://scenes/summon.tscn")
	await create_timer(0.5).timeout
	current_scene._pull(10)
	await create_timer(1.0).timeout
	_shot(out + "/pt_3_invocation.png")

	var p: Profile = S.profile
	print("Montée rapide : ", p.quick_star_up(), " · héros ", p.owned_ids().size())
	p.auto_formation()
	change_scene_to_file("res://scenes/collection.tscn")
	await create_timer(1.0).timeout
	_shot(out + "/pt_4_heros.png")
	var tabs: TabContainer = current_scene.find_children("*", "TabContainer", true, false)[0]
	tabs.current_tab = 1
	await create_timer(0.4).timeout
	_shot(out + "/pt_5_competences.png")
	change_scene_to_file("res://scenes/team.tscn")
	await create_timer(1.0).timeout
	_shot(out + "/pt_6_equipe.png")
	change_scene_to_file("res://scenes/main.tscn")
	await create_timer(1.5).timeout
	_shot(out + "/pt_7_accueil.png")
	quit()


func _shot(path: String) -> void:
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)
