extends SceneTree
## Capture d'un effet de combat figé à mi-course (réglage visuel) :
## godot --path . --script res://tools/fx_shot.gd -- sortie.png [décor]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	await process_frame
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	root.add_child(world)
	BattleDecor.build(world, args[1] if args.size() > 1 else "dojo")
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 40.0
	cam.position = Vector3(0, 3.69, 10.37)
	cam.look_at(Vector3(0, 1.0, -0.9))
	for i in 3:
		world.add_child(BattleFx.unit_seal(Color("d1ad62") if i < 2 else Color("c45048")))
		world.get_child(world.get_child_count() - 1).position = Vector3((i - 1) * 2.4, 0.03, 2.3 if i < 2 else -3.0)
		BattleFx.ink_slash(world, Vector3((i - 1) * 2.6, 1.1, -2.5), [Color("ff9a3d"), Color("7fb0ff"), Color("c07de0")][i], i == 2, 2.0)
	await create_timer(0.75).timeout
	root.get_texture().get_image().save_png(args[0])
	quit()
