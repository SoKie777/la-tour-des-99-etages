extends SceneTree
## Photo de groupe des légendaires pour l'image de bannière (fond transparent) :
## godot --path . --script res://tools/banner_shot.gd -- <sortie.png> [vedette]
## puis : python tools/make_banner.py <sortie.png>  →  assets/ui/banner_legendaires.png


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var star: String = args[1] if args.size() > 1 else "montana"
	await process_frame
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 900)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.72, 0.68, 0.66)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 25, 0)
	sun.light_energy = 1.15
	world.add_child(sun)
	var others: Array[String] = []
	for c in GameData.characters().values():
		if int(c["rarity"]) == 5 and c["id"] != star:
			others.append(c["id"])
	# arc derrière la vedette : les plus proches du centre un peu plus en avant
	var n := others.size()
	for i in n:
		var side := -1.0 if i % 2 == 0 else 1.0
		var rank := i / 2 + 1
		var m := CharacterModel.new()
		world.add_child(m)
		m.setup(others[i], Color.GRAY)
		m.position = Vector3(side * (0.85 + (rank - 1) * 0.85), 0, -0.6 - rank * 0.3)
		m.rotation_degrees.y = -side * 14.0
		m.play("idle" if rank % 2 == 1 else "idle_caster")
	var hero := CharacterModel.new()
	world.add_child(hero)
	hero.setup(star, Color.GRAY, 1.9)
	hero.position = Vector3(0, 0, 0.6)
	hero.play("victory")
	var cam := Camera3D.new()
	cam.fov = 34
	world.add_child(cam)
	cam.position = Vector3(0, 1.2, 6.0)
	cam.look_at(Vector3(0, 1.12, 0))
	await create_timer(1.1).timeout
	vp.get_texture().get_image().save_png(args[0])
	print("BANNIERE ", args[0])
	quit()
