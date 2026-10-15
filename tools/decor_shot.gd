extends SceneTree
## Capture d'un décor de combat seul, vu de la caméra de combat :
## godot --path . --script res://tools/decor_shot.gd -- <decor> sortie.png [largeur hauteur]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	await process_frame
	root.size = Vector2i(int(args[2]), int(args[3])) if args.size() > 3 else Vector2i(1280, 720)
	var world := Node3D.new()
	root.add_child(world)
	BattleDecor.build(world, args[0])
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 40.0  # = BattleScene.CAM_FOV (la scène de combat dépend des autoloads)
	cam.position = Vector3(0, 3.69, 10.37)
	cam.look_at(Vector3(0, 1.0, -0.9))
	cam.attributes = BattleDecor.camera_blur()
	await create_timer(1.0).timeout
	root.get_texture().get_image().save_png(args[1])
	print("SHOT ", args[1])
	quit()
