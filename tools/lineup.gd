extends SceneTree
## Photo de groupe du roster (contrôle visuel des modèles MPFB) :
## godot --path . --script res://tools/lineup.gd -- [sortie.png] [animation]
## Sans argument : user://lineup.png, pose « idle ».


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://lineup.png"
	var anim: String = args[1] if args.size() > 1 else "idle"
	await process_frame
	root.size = Vector2i(1800, 700)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("2a2638")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	world.add_child(sun)
	var ids: Array = []
	for c in GameData.characters().values():
		ids.append(c["id"])
	for i in ids.size():
		var m := CharacterModel.new()
		world.add_child(m)
		m.position = Vector3((i - (ids.size() - 1) / 2.0) * 0.95, 0, 0)
		m.setup(ids[i], Color.GRAY)
		m.play(anim)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 6.2)
	cam.fov = 45
	world.add_child(cam)
	cam.look_at(Vector3(0, 0.9, 0))
	for _f in 40:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("LINEUP ", ProjectSettings.globalize_path(out))
	quit()
