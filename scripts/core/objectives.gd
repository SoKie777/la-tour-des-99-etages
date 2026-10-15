class_name Objectives
extends RefCounted
## Prochaines étapes conseillées (captologie : tunnel et suggestion, docs/CAPTOLOGIE.md).
## Purement informatif : propose ce qui fait progresser, sans pression ni fausse urgence.
## Chaque objectif : {"id", "text", "scene", "floor" (facultatif)}.


static func next_steps(p: Profile, now: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	p.refresh_energy(now)
	var nxt := p.tower_cleared + 1
	if nxt <= Tower.floor_count():
		var cost := p.floor_cost(nxt)
		var f := Tower.floor_info(nxt)
		if p.energy >= cost:
			var tag := " (boss)" if f.has("boss") else (" (élite)" if f.get("elite", false) else "")
			out.append({"id": "tower", "text": "Gravir l'étage %d%s" % [nxt, tag], "scene": "tower", "floor": nxt})
	var cost10 := 10 * int(GameData.progression()["pull_cost"])
	if p.amount("eclat_de_voeu") >= cost10:
		out.append({"id": "summon", "text": "Invocation x10 disponible (%d Éclats)" % p.amount("eclat_de_voeu"), "scene": "summon"})
	var empty := empty_relic_slots(p)
	if empty > 0:
		out.append({"id": "relics", "text": "Équiper des reliques (%d emplacements libres dans l'équipe)" % empty, "scene": "collection"})
	if not p.unseen.is_empty():
		out.append({"id": "unseen", "text": "%d nouveau(x) personnage(s) à découvrir" % p.unseen.size(), "scene": "collection"})
	for id: String in LootBoss.ids():
		var st := p.loot_state(id)
		var left := int(LootBoss.cfg()["pity_wins"]) - int(st["pity"])
		if int(st["wins"]) > 0 and left <= 2:
			out.append({"id": "loot_" + id, "text": "Relique garantie dans %d victoire(s) : %s" % [left, LootBoss.boss(id)["name"]],
				"scene": "loot"})
	if p.tower_cleared >= 3 and LootBoss.ids().all(func(id: String) -> bool: return int(p.loot_state(id)["wins"]) == 0):
		out.append({"id": "loot_discover", "text": "Affronter un boss de butin pour des reliques ciblées", "scene": "loot"})
	return out


## Emplacements de relique vides dans l'équipe, pour lesquels une relique libre existe.
static func empty_relic_slots(p: Profile) -> int:
	var n := 0
	for id in p.team:
		var worn: Dictionary = p.equipped.get(id, {})
		for slot in range(1, 7):
			if worn.has(str(slot)):
				continue
			if p.relics.any(func(r: Dictionary) -> bool: return int(r["slot"]) == slot and p.owner_of(int(r["uid"])) == ""):
				n += 1
	return n
