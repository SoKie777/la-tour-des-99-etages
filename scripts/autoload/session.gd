extends Node
## État partagé entre les écrans : profil du joueur (sauvegarde locale), bannière, combat en cours.

const MAIN_SAVE := "user://profil.json"
var save_path := MAIN_SAVE  # -- --save=user://autre.json pour un profil de test

var profile: Profile
var gacha: Gacha
var auto_battle := true
var battle_speed := 1.0
## Combat à lancer : {"mode": "campaign", "stage": n}, {"mode": "tower", "floor": n},
## {"mode": "loot", "boss": id, "diff": i} ou {"mode": "test", "player": [specs], "enemy": [specs]}
var battle: Dictionary = {}
var rng := RandomNumberGenerator.new()
## Résultats de la dernière invocation (cinématique puis écran d'invocation).
var last_pulls: Array[Dictionary] = []
## Cadeaux versés au chargement (affichés une fois sur le menu).
var grant_notes: Array[String] = []
## Test de fumée : godot --headless --path . res://scenes/battle.tscn -- --smoke
var smoke_test := false


func _ready() -> void:
	rng.randomize()
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--save="):
			save_path = a.trim_prefix("--save=")
	if "--smoke" in args:
		smoke_test = true
		auto_battle = true
		battle_speed = 3.0
		profile = Profile.new_game()
		battle = {"mode": "campaign", "stage": 1}
		if "--boss" in args:  # Prométhée avec une équipe 5★ : -- --smoke --boss
			_smoke_team(["adrian", "mello", "noor_el", "montana", "mikhaila", "don_selah"], 30)
			battle = {"mode": "campaign", "stage": 12}
		if "--loot" in args:  # Expédition (Wyrm, palier 1) : -- --smoke --loot
			_smoke_team(["adrian", "mello", "noor_el", "montana", "mikhaila", "don_selah"], 40)
			battle = {"mode": "loot", "boss": "wyrm", "diff": 0}
		if "--six" in args:  # 6 contre 6 : -- --smoke --six
			_smoke_team(["adrian", "mello", "noor_el", "montana", "mikhaila", "don_selah"], 60)
			battle = {"mode": "campaign", "stage": 60}
		get_tree().create_timer(240.0).timeout.connect(func() -> void:
			push_error("Test de fumée : le combat n'a pas fini en 240 s")
			get_tree().quit(1))
	else:
		load_profile()
		for a in args:  # captures : -- --save=user://essai.json --demo=<étape>
			if a.begins_with("--demo="):
				_smoke_team(["adrian", "mello", "noor_el", "montana", "mikhaila", "don_selah"], 60)
				battle = {"mode": "campaign", "stage": int(a.trim_prefix("--demo="))}
	gacha = Gacha.new("standard")
	gacha.set_state(profile.gacha_state)


func _smoke_team(ids: Array, lvl: int) -> void:
	profile.campaign_cleared = 30
	for id: String in ids:
		profile.add_hero(id, 6)
		profile.levels[id] = lvl
	profile.formation = {}
	var placed := HeroDb.auto_place(ids)
	for s: int in placed:
		profile.formation[str(s)] = placed[s]


func load_profile() -> void:
	profile = null
	if FileAccess.file_exists(save_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
		if parsed is Dictionary:
			profile = Profile.from_dict(parsed)
	if profile == null:
		profile = Profile.new_game()
	grant_notes = profile.apply_grants()
	if gacha != null:
		gacha.set_state(profile.gacha_state)
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
	profile.apply_grants()
	gacha.set_state({})
	save()


func now() -> int:
	return int(Time.get_unix_time_from_system())


## Change de bannière (chaque bannière garde ses propres compteurs dans l'état du gacha).
func set_banner(id: String) -> void:
	var st := gacha.get_state()
	gacha = Gacha.new(id)
	gacha.set_state(st)


## Coût d'invocations : tickets de la bannière d'abord, puis Éclats de Vœu. Renvoie {} si impossible.
func pull_cost(n: int) -> Dictionary:
	var ticket := str(gacha.banner.get("ticket", "sceau"))
	var have := profile.amount(ticket)
	var use := mini(have, n)
	var cost := {}
	if use > 0:
		cost[ticket] = use
	if n - use > 0:
		cost["eclat_de_voeu"] = (n - use) * int(GameData.gacha()["cost_eclats"])
	return cost


func pull(n: int) -> Array[Dictionary]:
	var cost := pull_cost(n)
	if not profile.pay(cost):
		return []
	var results := gacha.pull_many(n)
	for r in results:
		r.merge(profile.add_pull(r))
	save()
	last_pulls = results
	return results


func _go_battle(b: Dictionary) -> void:
	battle = b
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


func start_stage(n: int) -> void:
	_go_battle({"mode": "campaign", "stage": n})


func start_tower_floor(number: int) -> void:
	_go_battle({"mode": "tower", "floor": number})


func start_loot(id: String, diff: int) -> bool:
	var cost := int(GameData.progression()["energy"]["loot_cost"])
	if not profile.spend_energy(cost, now()):
		return false
	save()
	_go_battle({"mode": "loot", "boss": id, "diff": diff, "energy": cost})
	return true


## Équipes du combat en cours : [joueur, ennemis] au format de RtBattle.
func battle_specs() -> Array:
	var enemies := []
	var mine := profile.battle_specs()
	match str(battle.get("mode", "")):
		"campaign":
			enemies = Campaign.enemy_specs(int(battle.get("stage", 1)))
		"tower":
			enemies = Tower.enemy_specs(int(battle.get("floor", 1)))
		"loot":
			enemies = LootBoss.enemy_specs(str(battle["boss"]), int(battle["diff"]))
		"test":
			mine = battle["player"]
			enemies = battle["enemy"]
	return [mine, enemies]


## Décor du combat en cours.
func battle_decor() -> String:
	match str(battle.get("mode", "")):
		"campaign":
			return str(Campaign.stage_info(int(battle.get("stage", 1))).get("decor", "dojo"))
		"tower":
			return str(Tower.floor_info(int(battle.get("floor", 1))).get("decor", "dojo"))
		"loot":
			return str(LootBoss.boss(str(battle["boss"])).get("decor", "dojo"))
	return "dojo"


func battle_title() -> String:
	match str(battle.get("mode", "")):
		"campaign":
			var info := Campaign.stage_info(int(battle.get("stage", 1)))
			return "%s  ·  %s" % [info.get("number", ""), info.get("name", "")]
		"tower":
			return "Tour  ·  Étage %d" % int(battle.get("floor", 1))
		"loot":
			return "%s  ·  %s" % [LootBoss.boss(str(battle["boss"]))["name"], LootBoss.difficulty(int(battle["diff"]))["name"]]
	return "Combat"
