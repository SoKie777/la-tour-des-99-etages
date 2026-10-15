extends SceneTree
## Photos de buste de chaque personnage (fond transparent), à styliser ensuite en estampe :
## godot --path . --script res://tools/portraits.gd -- <dossier_sortie> [id1,id2,...]
## puis : python tools/ukiyoe_portraits.py <dossier_sortie> (écrit assets/portraits/<id>.png)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	await process_frame
	var ids: Array = []
	if args.size() > 1:
		ids.assign(args[1].split(","))
	else:
		ids.assign(GameData.characters().keys())
		ids.append_array(["promethee", "chronophage", "wyrm", "serpent"])
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 512)
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
	env.environment.ambient_light_color = Color(0.75, 0.72, 0.7)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-25, 35, 0)
	sun.light_energy = 1.1
	world.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 26
	world.add_child(cam)
	for id: String in ids:
		var m := CharacterModel.new()
		world.add_child(m)
		m.setup(id, Color.GRAY, 1.75)
		m.rotation_degrees.y = 22.0  # trois quarts, comme un portrait d'estampe
		m.play("idle_caster")  # pose neutre : pas de garde de boxe devant le visage
		await create_timer(0.35).timeout
		m.ap.pause()  # pose figée
		var head := _head_height(m)
		cam.position = Vector3(0.12, head + 0.02, 1.3)
		cam.look_at(Vector3(0.02, head - 0.07, 0))
		await process_frame
		await process_frame
		vp.get_texture().get_image().save_png("%s/%s.png" % [out, id])
		print("PORTRAIT ", id)
		m.queue_free()
		await process_frame
	quit()


func _head_height(m: CharacterModel) -> float:
	var hi := 0.0
	for mi in m.meshes:
		var bb: AABB = mi.global_transform * mi.get_aabb()
		hi = maxf(hi, bb.end.y)
	return hi - 0.12
