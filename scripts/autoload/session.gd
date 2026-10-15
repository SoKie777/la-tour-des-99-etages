extends Node
## Etat partagé entre les écrans : profil du joueur (sauvegarde locale), bannière, combat en cours.
## Plus tard : synchronisation serveur.

var save_path := "user://profil.json"  # -- --save=user://autre.json pour un profil de test

var profile: Profile
var gacha: Gacha
var auto_battle := false
var battle_speed := 1.0
## Combat à lancer : {"mode": "tower", "floor": n} ou {"mode": "test", "player": [ids], "enemy": [ids]}
var battle: Dictionary = {}
var rng := RandomNumberGenerator.new()
## Résultats de la dernière invocation (cinématique puis écran d'invocation).
var last_pulls: Array[Dictionary] = []
## Test de fumée : godot --headless --path . res://scenes/battle.tscn -- --smoke
var smoke_test := false


func _ready() -> void:
	rng.randomize()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--save="):
			save_path = a.trim_prefix("--save=")
	if "--smoke" in OS.get_cmdline_user_args():
		smoke_test = true
		auto_battle = true
		battle_speed = 3.0
		profile = Profile.new_game()  # le test ne touche pas à la sauvegarde
		battle = {"mode": "tower", "floor": 1}
		if "--boss" in OS.get_cmdline_user_args():  # Prométhée (étage 12) : -- --smoke --boss
			for id in ["mikhaila", "ghost", "montana"]:
				profile.owned[id] = 1
			profile.set_team(["montana", "mikhaila", "ghost"])
			battle = {"mode": "tower", "floor": 12}
		if "--v2" in OS.get_cmdline_user_args():  # combat du roster v2 : -- --smoke --v2
			battle = {"mode": "test", "player": GameData.nation_team("A"), "enemy": GameData.nation_team("C")}
		get_tree().create_timer(120.0).timeout.connect(func() -> void:
			push_error("Test de fumée : le combat n'a pas fini en 120 s")
			get_tree().quit(1))
	else:
		load_profile()
	gacha = Gacha.new("featured_montana")
	gacha.set_state(profile.gacha_state)


func load_profile() -> void:
	profile = null
	if FileAccess.file_exists(save_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
		if parsed is Dictionary:
			profile = Profile.from_dict(parsed)
	if profile == null:
		profile = Profile.new_game()
		save()


func save() -> void:
	if smoke_test:
		return
	if gacha != null:
		profile.gacha_state = gacha.get_state()
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(profile.to_dict()))


func reset_profile() -> void:
	profile = Profile.new_game()
	gacha.set_state({})
	save()


## Invoque n fois si le joueur a assez d'Éclats de Vœu. Renvoie [] sinon.
func pull(n: int) -> Array[Dictionary]:
	var cost := n * int(GameData.progression()["pull_cost"])
	if not profile.spend("eclat_de_voeu", cost):
		return []
	var results := gacha.pull_many(n)
	for r in results:
		r.merge(profile.add_pull(r))
	save()
	last_pulls = results
	return results


func now() -> int:
	return int(Time.get_unix_time_from_system())


## Lance un étage si l'énergie suffit (elle est rendue en cas de défaite). Renvoie false sinon.
func start_tower_floor(number: int) -> bool:
	var cost := profile.floor_cost(number)
	if not profile.spend_energy(cost, now()):
		return false
	save()
	battle = {"mode": "tower", "floor": number, "energy": cost}
	get_tree().change_scene_to_file("res://scenes/battle.tscn")
	return true


## Equipes du combat en cours : [joueur, ennemis] (listes de BattleUnit).
func battle_teams() -> Array:
	var players: Array[BattleUnit] = []
	var enemies: Array[BattleUnit] = []
	if battle.get("mode", "") == "test":
		for id: String in battle["player"]:
			players.append(BattleUnit.new(GameData.character(id), 0, players.size()))
		for id: String in battle["enemy"]:
			enemies.append(BattleUnit.new(GameData.character(id), 1, enemies.size()))
	else:
		for id in profile.team:
			players.append(profile.make_unit(id))
		enemies = Tower.enemy_units(int(battle.get("floor", 1)))
	return [players, enemies]
