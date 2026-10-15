extends SceneTree
## Planche de contrôle des icônes SVG (assets/icons puis assets/status_icons) :
## godot --path . --script res://tools/icon_sheet.gd -- sortie.png


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	await process_frame
	root.size = Vector2i(1280, 900)
	var bg := ColorRect.new()
	bg.color = Color("21172f")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 14
	grid.position = Vector2(10, 10)
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	root.add_child(grid)
	for dir in ["res://assets/icons/", "res://assets/status_icons/"]:
		for f in ResourceLoader.list_directory(dir):
			if not f.ends_with(".svg"):
				continue
			var v := VBoxContainer.new()
			var t := TextureRect.new()
			t.texture = load(dir + f)
			t.custom_minimum_size = Vector2(48, 48)
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			v.add_child(t)
			var l := Label.new()
			l.text = f.get_basename().left(11)
			l.add_theme_font_size_override("font_size", 10)
			v.add_child(l)
			v.custom_minimum_size.x = 84
			grid.add_child(v)
	await create_timer(0.5).timeout
	root.get_texture().get_image().save_png(args[0])
	quit()
