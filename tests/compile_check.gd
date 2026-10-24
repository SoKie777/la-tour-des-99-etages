extends Node
## Scène de contrôle : charge tous les scripts du jeu (autoloads disponibles) pour détecter les erreurs
## de compilation. godot --headless --path . res://tests/compile_check.tscn


func _ready() -> void:
	var bad := 0
	for dir in ["res://scripts/core/", "res://scripts/ui/", "res://scripts/autoload/", "res://tools/"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				var s: Script = load(dir + f)
				if s == null or not s.can_instantiate():
					print("ÉCHEC : ", dir + f)
					bad += 1
	for f in DirAccess.get_files_at("res://scenes/"):
		if f.ends_with(".tscn"):
			var ps: PackedScene = load("res://scenes/" + f)
			if ps == null:
				print("ÉCHEC : scène ", f)
				bad += 1
	print("compilation : %d échec(s)" % bad)
	get_tree().quit(1 if bad > 0 else 0)
