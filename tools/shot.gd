extends SceneTree
## Capture d'écran d'une scène du jeu (contrôle visuel de l'interface) :
## godot --path . --script res://tools/shot.gd -- res://scenes/tower.tscn sortie.png [secondes]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	await process_frame
	root.size = Vector2i(1280, 720)
	change_scene_to_file(args[0])
	await create_timer(float(args[2]) if args.size() > 2 else 1.5).timeout
	root.get_texture().get_image().save_png(args[1])
	print("SHOT ", args[1])
	quit()
