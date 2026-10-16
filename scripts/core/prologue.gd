class_name Prologue
extends RefCounted
## Prologue (data/prologue.json) : 8 niveaux joués dès le début avec Eiríkr seul, deux invocations x10
## gratuites sur la bannière de départ, puis la Tour s'ouvre. L'avancée est dans le profil
## (prologue_cleared, prologue_pulls).


static func cfg() -> Dictionary:
	return GameData.prologue()


static func level_count() -> int:
	return cfg()["levels"].size()


## Niveau n (à partir de 1) : {number, name, enemies | boss_unit, power, safe, elite, decor, tips, brief, team}.
static func level(n: int) -> Dictionary:
	var f: Dictionary = cfg()["levels"][n - 1].duplicate()
	f["number"] = n
	if not f.has("enemies"):
		f["enemies"] = []
	return f


static func enemy_units(n: int) -> Array[BattleUnit]:
	return Tower.make_enemies(level(n))


static func tactics_rank(n: int) -> String:
	return "elite" if level(n).get("elite", false) else "normal"


## Faiblesses des ennemis du niveau (constellations qui entament leur Ténacité).
static func weaknesses(n: int) -> Array[String]:
	return Tower.weaknesses_of(level(n))


## Nombre d'invocations gratuites débloquées après n niveaux gagnés.
static func free_multis_unlocked(cleared: int) -> int:
	var k := 0
	for after: Variant in cfg()["free_multis_after"]:
		if cleared >= int(after):
			k += 1
	return k
