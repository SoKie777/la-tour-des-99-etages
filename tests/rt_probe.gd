extends SceneTree
## Sonde : détail d'un duel de factions. godot --headless --path . --script res://tests/rt_probe.gd -- a b


func team(f: String) -> Array:
	var ids := []
	for id in HeroDb.playable_ids(false):
		if HeroDb.hero(id)["factions"][0] == f:
			ids.append(id)
	for id in HeroDb.playable_ids(false):
		if ids.size() >= 6:
			break
		if not ids.has(id) and HeroDb.hero(id)["factions"][1] == f:
			ids.append(id)
	var placed := HeroDb.auto_place(ids)
	var out := []
	for s: int in placed:
		out.append({"id": placed[s], "level": 80, "star": 6, "slot": s})
	return out


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var fa := args[0] if args.size() > 0 else "tour"
	var fb := args[1] if args.size() > 1 else "pion"
	var e := RtBattle.new(team(fa), team(fb), 77)
	var counts := {}
	var ov := []
	while not e.is_over():
		e.step()
		for ev in e.drain_events():
			var key := "%s/%s" % [ev["type"], (ev["src"] as RtUnit).id if ev.get("src") is RtUnit else "-"]
			counts[key] = int(counts.get(key, 0)) + 1
			if ev["type"] == "overdrive":
				ov.append("%.1f %s" % [e.time, (ev["src"] as RtUnit).id])
	print("vainqueur ", e.winner, " en %.1f s" % e.time)
	for u in e.units:
		print("  %d %-16s %s pv %6d/%6d inflige %7d subit %7d soins %6d  slot %d" % [u.team, u.id, "MORT" if u.dead else "vie ", u.hp, u.max_hp, u.dealt, u.taken, u.healed, u.slot])
	print("Overdrive : ", ov)
	var keys := counts.keys()
	keys.sort()
	for k in keys:
		if k.begins_with("skill") or k.begins_with("attack"):
			print("  ", k, " ", counts[k])
	quit()
