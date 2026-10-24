extends Control
## Expédition (« Expédition des champions » de Dragon Traveler) : boss qui donnent des reliques.
## Choix du palier (débloqué en battant le précédent) et du set garanti par la pitié.

var chosen_diff := {}  # id du boss -> palier choisi


func _ready() -> void:
	for id: String in LootBoss.ids():
		chosen_diff[id] = int(Session.profile.loot_state(id)["unlocked"])
	_build()


func _build() -> void:
	var content := UiKit.screen(self, "Expédition")
	content.get_parent().get_child(0).add_child(UiKit.currency_bar(["energie"]))
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	content.add_child(cols)
	for id: String in LootBoss.ids():
		cols.add_child(_boss_card(id))


func _boss_card(id: String) -> Control:
	var p := Session.profile
	var b := LootBoss.boss(id)
	var st := p.loot_state(id)
	var h := HeroDb.hero(id)
	var fac := str(h["factions"][0])
	var col := UiKit.faction_color(fac)
	var panel := UiKit.panel(col)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(UiKit.label(b["name"], 20, col.lightened(0.3)))
	v.add_child(UiKit.rich("%s %s   ·   %s" % [UiKit.bb("f_" + fac, 16, col), UiKit.faction_name(fac), UiKit.class_name_of(id)], 13, UiKit.DIM))
	var view := UiKit.model_view([id], Vector2i(380, 190))
	v.add_child(view)
	var mech := UiKit.label("%s : %s" % [h["overdrive"]["name"], h["overdrive"]["desc"]], 13)
	mech.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(mech)
	var sets: Array[String] = []
	for s: String in b["sets"]:
		var d: Dictionary = GameData.relics()["sets"][s]
		sets.append("%s ×%d" % [UiKit.bb("set_" + s, 18, UiKit.ACCENT), int(d["size"])])
	v.add_child(UiKit.rich(UiKit.bb("relique", 18, UiKit.ACCENT) + "    " + "   ".join(sets), 14, UiKit.ACCENT))
	# palier
	var diff_row := HBoxContainer.new()
	v.add_child(diff_row)
	var ob := OptionButton.new()
	for i in int(st["unlocked"]) + 1:
		var d := LootBoss.difficulty(i)
		ob.add_icon_item(UiKit.icon_texture("relique"), "%s  niv. %d   ×%d  +%d" % [d["name"], int(d["level"]), int(d["relics"]), int(d["relic_level"])], i)
	ob.selected = int(chosen_diff[id])
	ob.item_selected.connect(func(i: int) -> void: chosen_diff[id] = i)
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.add_theme_constant_override("icon_max_width", 20)
	ob.get_popup().add_theme_constant_override("icon_max_width", 20)
	diff_row.add_child(ob)
	# pitié
	var left := int(LootBoss.cfg()["pity_wins"]) - int(st["pity"])
	var pity_row := HBoxContainer.new()
	v.add_child(pity_row)
	pity_row.add_child(UiKit.rich("%s %d  ›" % [UiKit.bb("relique", 18, UiKit.ACCENT), left], 14, UiKit.DIM))
	var ps := OptionButton.new()
	for i in b["sets"].size():
		ps.add_icon_item(UiKit.icon_texture("set_" + str(b["sets"][i])), "", i)
		if b["sets"][i] == st["pity_set"]:
			ps.selected = i
	ps.item_selected.connect(func(i: int) -> void:
		st["pity_set"] = b["sets"][i]
		Session.save())
	ps.add_theme_constant_override("icon_max_width", 22)
	ps.get_popup().add_theme_constant_override("icon_max_width", 22)
	pity_row.add_child(ps)
	v.add_child(UiKit.amount("titan", str(int(st["wins"])), 13, UiKit.DIM))
	var cost := int(GameData.progression()["energy"]["loot_cost"])
	var fight := UiKit.rich_button("Combattre   %s %d" % [UiKit.bb("energie", 18), cost], func() -> void: Session.start_loot(id, int(chosen_diff[id])), Vector2(200, 50))
	fight.disabled = p.energy < cost
	v.add_child(fight)
	return panel
