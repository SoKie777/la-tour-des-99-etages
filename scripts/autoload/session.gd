extends Node
## Etat partagé entre les écrans (choix d'équipes, bannière, collection).
## Plus tard : sauvegarde locale puis serveur.

var player_team: Array[String] = ["eirikr", "ymir", "nidhogg"]
var enemy_team: Array[String] = ["don_diego", "general_metal", "espion_lumiere"]
var auto_battle := false
var battle_speed := 1.0
var gacha: Gacha
var collection: Dictionary = {}  # id -> nombre d'exemplaires
## Test de fumée : godot --headless --path . res://scenes/battle.tscn -- --smoke
var smoke_test := false


func _ready() -> void:
	gacha = Gacha.new("featured_eirikr")
	if "--smoke" in OS.get_cmdline_user_args():
		smoke_test = true
		auto_battle = true
		battle_speed = 3.0
		get_tree().create_timer(120.0).timeout.connect(func() -> void:
			push_error("Test de fumée : le combat n'a pas fini en 120 s")
			get_tree().quit(1))


func record_pulls(results: Array[Dictionary]) -> void:
	for r in results:
		collection[r["id"]] = collection.get(r["id"], 0) + 1
