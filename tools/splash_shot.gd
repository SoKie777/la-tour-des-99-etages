extends SceneTree
## Photo plein pied d'un personnage pour son illustration de bannière (fond transparent, contre-plongée) :
## godot --path . --script res://tools/splash_shot.gd -- <sortie.png> <id> [animation] [secondes]
## puis : python tools/make_splash.py <sortie.png> <id>  →  assets/ui/splash_<id>.png


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[1]
	await process_frame
	var vp := SubViewport.new()
	vp.size = Vector2i(1000, 1500)
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
	env.environment.ambient_light_color = Color(0.7, 0.66, 0.66)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-25, 30, 0)
	sun.light_energy = 1.2
	world.add_child(sun)
	var rim := DirectionalLight3D.new()  # contre-jour : liseré net sur la silhouette
	rim.rotation_degrees = Vector3(-15, 200, 0)
	rim.light_energy = 0.9
	world.add_child(rim)
	var hero := CharacterModel.new()
	world.add_child(hero)
	hero.setup(id, Color.GRAY, 1.9)
	hero.rotation_degrees.y = -10.0
	hero.play(args[2] if args.size() > 2 else "victory")
	var cam := Camera3D.new()
	cam.fov = 30
	world.add_child(cam)
	cam.position = Vector3(0.3, 0.7, 5.6)  # légère contre-plongée : la vedette domine
	cam.look_at(Vector3(0, 1.0, 0))
	await create_timer(float(args[3]) if args.size() > 3 else 1.2).timeout
	vp.get_texture().get_image().save_png(args[0])
	print("SPLASH ", args[0])
	quit()
