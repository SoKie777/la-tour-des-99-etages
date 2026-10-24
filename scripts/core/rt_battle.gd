class_name RtBattle
extends RefCounted
## Combat en temps réel (boucle de Dragon Traveler, docs/ANALYSE_DRAGON_TRAVELER.md §2) :
## - jusqu'à 6 héros par camp sur une grille 3 × 3 ; chacun avance vers sa cible, attaque à sa cadence,
##   lance sa compétence dès qu'elle est prête ;
## - jauge d'énergie commune à l'équipe ; chaque Overdrive coûte de l'énergie, a sa recharge et ne peut
##   suivre un autre Overdrive de l'équipe qu'après un court délai ; le joueur les déclenche (ou l'auto) ;
## - 6 mécaniques de faction (data/factions.json) et bonus de faction à 4/5/6 héros.
## Sans affichage : la scène lit les positions et vide la file 'events' à chaque image.

signal ended(winner: int)

var units: Array[RtUnit] = []
var time := 0.0
var energy: Array[float] = [0.0, 0.0]
var gcd: Array[float] = [0.0, 0.0]
var auto: Array[bool] = [true, true]
var queue: Array = [[], []]           # Overdrive demandés par le joueur (RtUnit)
var pending: Array[Dictionary] = []   # Overdrive annoncés (boss) : {t, unit, target}
var events: Array[Dictionary] = []
var winner := -1
var rng := RandomNumberGenerator.new()
var rules: Dictionary
var time_limit := 90.0
var record_events := true
var faction_bonus_pct: Array[int] = [0, 0]
var faction_bonus_id: Array[String] = ["", ""]
var berserk_done := 0
var opts: Dictionary


## team_a / team_b : listes de {id, level, star, gear, slot, power}.
func _init(team_a: Array, team_b: Array, seed_value := 0, options := {}) -> void:
	opts = options
	rules = HeroDb.rules()
	time_limit = float(options.get("time_limit", rules["time_limit"]))
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	for spec: Dictionary in team_a:
		units.append(RtUnit.new(spec, 0))
	for spec: Dictionary in team_b:
		units.append(RtUnit.new(spec, 1))
	var en: Dictionary = rules["energy"]
	for t in 2:
		energy[t] = float(options.get("energy_start", [en["start"], en["start"]])[t])
	_place()
	for t in 2:
		_apply_faction_bonus(t)
	for u in units:
		_init_unit(u)
	for u in units:
		_run_passive(u, "battle_start", {})


# --- Mise en place ---------------------------------------------------------

func _place() -> void:
	var g: Dictionary = rules["grid"]
	for t in 2:
		var side := -1.0 if t == 0 else 1.0
		var team_units := alive_of(t)
		for u in team_units:
			if u.boss and team_units.size() == 1:
				u.home = Vector2(side * float(g["boss_x"]), 0.0)
			else:
				var col := clampi(u.slot / 3, 0, 2)
				var row := clampi(u.slot % 3, 0, 2)
				u.home = Vector2(side * float(g["columns"][col]), float(g["rows"][row]))
			u.pos = u.home
			u.facing = -side


func _apply_faction_bonus(t: int) -> void:
	var counts := {}
	for u in alive_of(t):
		for f in u.factions:
			counts[f] = int(counts.get(f, 0)) + 1
	var best := 0
	var best_id := ""
	for f: String in counts:
		if counts[f] > best:
			best = counts[f]
			best_id = f
	var table := HeroDb.faction_bonus()
	var pct := 0
	for k: String in table:
		if best >= int(k):
			pct = maxi(pct, int(table[k]))
	faction_bonus_pct[t] = pct
	faction_bonus_id[t] = best_id if pct > 0 else ""
	if pct > 0:
		for u in alive_of(t):
			u.max_hp *= 1.0 + pct / 100.0
			u.hp = u.max_hp
			u.mods["atk_pct"] = float(u.mods.get("atk_pct", 0.0)) + pct


func _init_unit(u: RtUnit) -> void:
	var en: Dictionary = rules["energy"]
	for p in _passives(u):
		if p.get("trigger", "") == "static":
			for k: String in p.get("stats", {}):
				u.mods[k] = float(u.mods.get(k, 0.0)) + float(p["stats"][k])
		elif p.get("trigger", "") == "periodic":
			u.periodic[p["name"]] = float(p.get("interval", 10.0))
	var sk: Dictionary = u.data.get("skill", {})
	u.skill_cd = float(sk.get("open", 2.0))
	u.ov_cd = float(en["ov_open"])
	u.attack_cd = rng.randf_range(0.0, 0.4)
	if u.has_faction("fou"):
		u.eveil = int(HeroDb.faction("fou")["mechanic"].get("start", 0)) + int(u.mods.get("eveil_bonus", 0))
	if u.has_faction("pion"):
		u.promesse = int(u.mods.get("promesse_bonus", 0))
	u.mods["dr_pct"] = float(u.mods.get("dr_pct", 0.0))


## Talent (toujours actif) et passif (à partir du niveau 40).
func _passives(u: RtUnit) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if u.data.has("talent"):
		out.append(u.data["talent"])
	if u.passive_on and u.data.has("passive"):
		out.append(u.data["passive"])
	return out


func _run_passive(u: RtUnit, trigger: String, ctx: Dictionary) -> void:
	for p in _passives(u):
		if p.get("trigger", "") == trigger:
			var c := ctx.duplicate()
			if not c.has("primary"):
				c["primary"] = u
				c["hit"] = [u]
			_run_effects(u, p.get("effects", []), c)


# --- Accès ---------------------------------------------------------------

func alive_of(t: int) -> Array[RtUnit]:
	var out: Array[RtUnit] = []
	for u in units:
		if u.team == t and not u.dead:
			out.append(u)
	return out


func foes_of(u: RtUnit) -> Array[RtUnit]:
	var out: Array[RtUnit] = []
	for x in alive_of(1 - u.team):
		if x.targetable():
			out.append(x)
	return out


func is_over() -> bool:
	return winner >= 0


func _emit(ev: Dictionary) -> void:
	if record_events:
		events.append(ev)


func drain_events() -> Array[Dictionary]:
	var out := events
	events = []
	return out


# --- Boucle ---------------------------------------------------------------

func step(dt := -1.0) -> void:
	if winner >= 0:
		return
	if dt <= 0.0:
		dt = float(rules["tick"])
	time += dt
	var en: Dictionary = rules["energy"]
	for t in 2:
		energy[t] = minf(float(en["max"]), energy[t] + float(en["regen"]) * dt)
		gcd[t] = maxf(0.0, gcd[t] - dt)
	_tick_pending()
	for u in units:
		if not u.dead:
			_tick_statuses(u, dt)
	for u in units:
		if not u.dead:
			_tick_unit(u, dt)
	for t in 2:
		_tick_overdrives(t)
	_separate(dt)
	_check_berserk()
	_check_end()


func run(max_time := 0.0) -> int:
	var limit := max_time if max_time > 0.0 else time_limit + 1.0
	while winner < 0 and time < limit:
		step()
	return winner


func _check_end() -> void:
	if winner >= 0:
		return
	var a := alive_of(0).size()
	var b := alive_of(1).size()
	if a == 0 or b == 0:
		winner = 0 if b == 0 and a > 0 else 1
	elif time >= time_limit:
		winner = int(opts.get("timeout_winner", 1))
		if opts.get("timeout_by_hp", false):
			winner = 0 if _hp_share(0) > _hp_share(1) else 1
	if winner >= 0:
		_emit({"type": "end", "winner": winner})
		ended.emit(winner)


func _hp_share(t: int) -> float:
	var hp := 0.0
	var mx := 0.0
	for u in units:
		if u.team == t:
			hp += maxf(0.0, u.hp)
			mx += u.max_hp
	return hp / mx if mx > 0.0 else 0.0


func _check_berserk() -> void:
	if not opts.get("berserk", false):
		return
	var at: Array = rules["berserk"]["at"]
	if berserk_done < at.size() and time >= float(at[berserk_done]):
		berserk_done += 1
		for u in units:
			u.mods["atk_pct"] = float(u.mods.get("atk_pct", 0.0)) + float(rules["berserk"]["atk_pct"])
		_emit({"type": "berserk", "n": berserk_done})


# --- Unités ---------------------------------------------------------------

func _tick_unit(u: RtUnit, dt: float) -> void:
	var h := u.haste()
	u.attack_cd -= dt * u.aspd()
	u.skill_cd -= dt * h
	u.ov_cd -= dt * h
	for k: String in u.icd.keys():
		u.icd[k] = float(u.icd[k]) - dt
	for k: String in u.periodic.keys():
		u.periodic[k] = float(u.periodic[k]) - dt
		if float(u.periodic[k]) <= 0.0:
			for p in _passives(u):
				if p.get("name", "") == k:
					u.periodic[k] = float(p.get("interval", 10.0))
					_run_effects(u, p.get("effects", []), {"primary": u, "hit": [u]})
	if u.lock > 0.0:
		u.lock -= dt
		return
	if not u.can_act():
		return
	_choose_target(u)
	if u.target == null:
		return
	var d := u.pos.distance_to(u.target.pos) - u.radius - u.target.radius
	var engaged := d <= u.range_m
	var sk: Dictionary = u.data.get("skill", {})
	if not sk.is_empty() and u.skill_cd <= 0.0 and u.can_skill() and (engaged or _has_dash(sk) or _self_cast(sk)):
		if _cast(u, sk, false):
			u.skill_cd = float(sk.get("cd", 10.0))
			u.lock = float(rules["cast_lock"]["skill"])
			return
	if engaged:
		if u.attack_cd <= 0.0:
			_basic_attack(u, u.target)
			u.attack_cd = u.interval
			u.lock = float(rules["cast_lock"]["attack"]) / u.aspd()
	elif u.can_move():
		var dir := (u.target.pos - u.pos).normalized()
		var speed := u.move_speed * maxf(0.2, 1.0 + u.mod("move_pct") / 100.0)
		u.pos += dir * speed * dt
		u.facing = signf(dir.x) if absf(dir.x) > 0.01 else u.facing
		_clamp_field(u)


func _has_dash(sk: Dictionary) -> bool:
	for e: Dictionary in sk.get("effects", []):
		if e.get("t", "") == "dash":
			return true
	return false


func _self_cast(sk: Dictionary) -> bool:
	return str(sk.get("target", "")) in ["self", "lowest_ally", "all_allies", "all_enemies", "highest_atk_ally"]


func _clamp_field(u: RtUnit) -> void:
	var f: Dictionary = rules["field"]
	u.pos.x = clampf(u.pos.x, -float(f["x_max"]), float(f["x_max"]))
	u.pos.y = clampf(u.pos.y, -float(f["z_max"]), float(f["z_max"]))


## Les unités d'une même équipe s'écartent un peu pour ne pas se superposer.
func _separate(dt: float) -> void:
	var sep := float(rules["field"]["separation"])
	for i in units.size():
		var a := units[i]
		if a.dead:
			continue
		for j in range(i + 1, units.size()):
			var b := units[j]
			if b.dead or b.team != a.team:
				continue
			var delta := a.pos - b.pos
			var dist := delta.length()
			var want := sep + (a.radius + b.radius - 0.8) * 0.5
			if dist < want and dist > 0.0001:
				var push := delta / dist * (want - dist) * 0.5 * minf(1.0, dt * 8.0)
				if a.can_move():
					a.pos += push
				if b.can_move():
					b.pos -= push
			elif dist <= 0.0001:
				a.pos.y += 0.05


func _choose_target(u: RtUnit) -> void:
	var taunt := u.get_status("taunt")
	if not taunt.is_empty() and taunt["src"] is RtUnit and (taunt["src"] as RtUnit).targetable():
		u.target = taunt["src"]
		return
	if u.target != null and u.target.targetable():
		return
	var foes := foes_of(u)
	if foes.is_empty():
		u.target = null
		return
	if str(u.cls_info.get("ai", "nearest")) == "backline":
		u.target = _pick(u, foes, "backline")
	else:
		u.target = _pick(u, foes, "nearest")


func _pick(u: RtUnit, pool: Array[RtUnit], how: String) -> RtUnit:
	if pool.is_empty():
		return null
	var best: RtUnit = pool[0]
	match how:
		"nearest":
			for x in pool:
				if u.pos.distance_squared_to(x.pos) < u.pos.distance_squared_to(best.pos):
					best = x
		"backline":
			var side := 1.0 if u.team == 0 else -1.0
			for x in pool:
				if x.pos.x * side > best.pos.x * side:
					best = x
		"lowest_hp":
			for x in pool:
				if x.hp_ratio() < best.hp_ratio():
					best = x
		"highest_atk":
			for x in pool:
				if x.atk() > best.atk():
					best = x
		"random":
			best = pool[rng.randi() % pool.size()]
	return best


# --- Attaques, compétences, Overdrive --------------------------------------

func _basic_attack(u: RtUnit, t: RtUnit) -> void:
	u.attack_count += 1
	_emit({"type": "attack", "src": u, "dst": t})
	_deal(u, t, 1.0, "atk", u.dmg_type, {"basic": true})
	if u.has_faction("cavalier"):
		_gain_rage(u, float(HeroDb.faction("cavalier")["mechanic"]["rage_per_hit"]))
	for p in _passives(u):
		if p.get("trigger", "") == "every_attack" and u.attack_count % maxi(1, int(p.get("every", 1))) == 0:
			if t.dead:
				continue
			_run_effects(u, p.get("effects", []), {"primary": t, "hit": [t]})


## Résout la cible et la zone d'une compétence puis applique ses effets. Renvoie false sans cible.
func _cast(u: RtUnit, sk: Dictionary, is_ov: bool) -> bool:
	var ctx := _resolve(u, sk)
	if ctx.is_empty():
		return false
	_emit({"type": "overdrive" if is_ov else "skill", "src": u, "name": sk.get("name", ""),
		"primary": ctx["primary"], "hit": ctx["hit"], "area": sk.get("area", {})})
	_run_effects(u, sk.get("effects", []), ctx)
	return true


func _resolve(u: RtUnit, sk: Dictionary) -> Dictionary:
	var how := str(sk.get("target", "enemy"))
	var allies := alive_of(u.team)
	var foes := foes_of(u)
	var primary: RtUnit = null
	var hit: Array[RtUnit] = []
	var ally_side := false
	match how:
		"self":
			primary = u
			ally_side = true
		"lowest_ally":
			primary = _pick(u, allies, "lowest_hp")
			ally_side = true
		"highest_atk_ally":
			primary = _pick(u, allies, "highest_atk")
			ally_side = true
		"all_allies":
			primary = u
			hit = allies.duplicate()
			ally_side = true
		"all_enemies":
			if foes.is_empty():
				return {}
			primary = _pick(u, foes, "nearest")
			hit = foes.duplicate()
		"enemy":
			primary = u.target if u.target != null and u.target.targetable() else _pick(u, foes, "nearest")
		_:
			primary = _pick(u, foes, how)
	if primary == null:
		return {}
	var area: Dictionary = sk.get("area", {})
	if hit.is_empty():
		if area.is_empty():
			hit = [primary]
		else:
			var center := u.pos if area.get("center", "") == "self" else primary.pos
			var pool: Array[RtUnit] = allies if ally_side else foes
			var shape := str(area.get("shape", "circle"))
			for x in pool:
				if shape == "line":
					if _in_line(u.pos, primary.pos, x.pos, float(area.get("width", 1.2))):
						hit.append(x)
				elif center.distance_to(x.pos) <= float(area.get("radius", 2.0)) + x.radius:
					hit.append(x)
			if hit.is_empty():
				hit = [primary]
	return {"primary": primary, "hit": hit}


func _in_line(from: Vector2, to: Vector2, p: Vector2, width: float) -> bool:
	var dir := (to - from)
	if dir.length() < 0.01:
		return p.distance_to(to) <= width
	dir = dir.normalized()
	var rel := p - from
	var along := rel.dot(dir)
	var across := absf(rel.cross(dir))
	return along >= -0.3 and along <= 10.0 and across <= width * 0.5 + 0.4


func can_overdrive(u: RtUnit) -> bool:
	if u.dead or u.ov_skill().is_empty() or not u.can_skill():
		return false
	return u.ov_cd <= 0.0 and gcd[u.team] <= 0.0 and energy[u.team] >= u.ov_cost() and u.lock <= 0.0


## Demande du joueur : l'Overdrive part dès que possible (énergie, recharge, délai d'équipe).
func request_overdrive(u: RtUnit) -> bool:
	if u.dead or u.ov_skill().is_empty() or u.ov_cd > 0.0 or energy[u.team] < u.ov_cost():
		return false
	if not queue[u.team].has(u):
		queue[u.team].append(u)
	return true


func _tick_overdrives(t: int) -> void:
	var q: Array = queue[t]
	if not q.is_empty():
		var u: RtUnit = q[0]
		if u.dead or u.ov_cd > 0.0:
			q.pop_front()
		elif can_overdrive(u):
			q.pop_front()
			_launch_ov(u)
		return
	if not auto[t] or gcd[t] > 0.0:
		return
	for u in alive_of(t):
		if can_overdrive(u) and _ov_worth(u):
			_launch_ov(u)
			return


## IA des Overdrive : soins quand un allié souffre, sinon dès qu'un ennemi est à portée.
func _ov_worth(u: RtUnit) -> bool:
	var sk := u.ov_skill()
	var how := str(sk.get("target", "enemy"))
	var heals := false
	for e: Dictionary in sk.get("effects", []):
		if e.get("t", "") in ["heal", "cleanse"]:
			heals = true
	if heals:
		for a in alive_of(u.team):
			if a.hp_ratio() < 0.7:
				return true
		return time > 30.0
	if how in ["self", "all_allies"]:
		return u.target != null and u.pos.distance_to(u.target.pos) < u.range_m + 3.0
	return u.target != null


func _launch_ov(u: RtUnit) -> void:
	var sk := u.ov_skill()
	energy[u.team] -= u.ov_cost()
	gcd[u.team] = float(rules["energy"]["team_gcd"])
	u.ov_cd = float(sk.get("cd", 20.0))
	u.remove_status("ov_tax")
	u.lock = float(rules["cast_lock"]["overdrive"])
	var tele := float(sk.get("telegraph", 0.0))
	if tele > 0.0:
		pending.append({"t": time + tele, "unit": u})
		_emit({"type": "telegraph", "src": u, "name": sk.get("name", ""), "dur": tele})
		u.lock = tele + 0.3
	else:
		_cast(u, sk, true)
	for a in alive_of(u.team):
		if a.has_faction("fou"):
			var mx := int(HeroDb.faction("fou")["mechanic"]["max_stacks"])
			if a.eveil < mx:
				a.eveil += 1
				_emit({"type": "stack", "dst": a, "id": "eveil", "n": a.eveil})


func _tick_pending() -> void:
	for i in range(pending.size() - 1, -1, -1):
		var p := pending[i]
		if time >= float(p["t"]):
			pending.remove_at(i)
			var u: RtUnit = p["unit"]
			if not u.dead and u.can_act():
				_cast(u, u.ov_skill(), true)


# --- Effets ---------------------------------------------------------------

func _run_effects(u: RtUnit, effects: Array, ctx: Dictionary) -> void:
	var primary: RtUnit = ctx.get("primary")
	var hit: Array = ctx.get("hit", [])
	for e: Dictionary in effects:
		if u.dead and e.get("t", "") != "heal":
			return
		var to := str(e.get("to", "hit"))
		var targets: Array[RtUnit] = _targets_for(u, to, hit, primary, ctx)
		match str(e.get("t", "")):
			"dmg":
				for n in int(e.get("hits", 1)):
					for x in targets:
						if not x.dead:
							_deal(u, x, float(e.get("mult", 1.0)), str(e.get("scale", "atk")), str(e.get("type", u.dmg_type)),
								{"chatiment": e.get("chatiment", false)})
			"heal":
				for x in targets:
					var amount := _scaled(u, x, str(e.get("scale", "atk"))) * float(e.get("mult", 1.0))
					_heal(u, x, amount)
			"shield":
				for x in targets:
					var amount := _scaled(u, x, str(e.get("scale", "atk"))) * float(e.get("mult", 1.0))
					_shield(u, x, amount, float(e.get("dur", 6.0)))
			"status":
				for x in targets:
					apply_status(u, x, str(e["id"]), float(e.get("dur", 4.0)), e.get("value", null), float(e.get("chance", 100.0)), e.get("stack", false))
			"energy":
				var team := u.team if to != "foe" else 1 - u.team
				energy[team] = clampf(energy[team] + float(e.get("value", 1.0)), 0.0, float(rules["energy"]["max"]))
				_emit({"type": "energy", "team": team, "delta": float(e.get("value", 1.0))})
			"ov_cost":
				for x in targets:
					apply_status(u, x, "ov_tax", float(e.get("dur", 10.0)), float(e.get("value", 1.0)), 100.0, true)
			"dash":
				if primary != null and primary.team != u.team:
					var side := 1.0 if u.team == 0 else -1.0
					u.pos = primary.pos + Vector2(side * (primary.radius + 0.7), rng.randf_range(-0.3, 0.3))
					_clamp_field(u)
					u.target = primary
					_emit({"type": "dash", "src": u, "dst": primary})
			"knock":
				for x in targets:
					if x.boss or x.flag("cc_immune"):
						continue
					var side := 1.0 if x.team == 1 else -1.0
					x.pos.x += side * float(e.get("dist", 1.0))
					_clamp_field(x)
			"cleanse":
				for x in targets:
					for i in range(x.statuses.size() - 1, -1, -1):
						var k := str(HeroDb.status_info(x.statuses[i]["id"]).get("kind", ""))
						if k in ["debuff", "cc"]:
							x.statuses.remove_at(i)
					_emit({"type": "cleanse", "dst": x})
			"stack":
				for x in targets:
					_add_stack(x, str(e.get("id", "")), int(e.get("value", 1)))


func _targets_for(u: RtUnit, to: String, hit: Array, primary: RtUnit, ctx: Dictionary) -> Array[RtUnit]:
	var out: Array[RtUnit] = []
	match to:
		"self":
			out.append(u)
		"allies":
			out = alive_of(u.team)
		"lowest_ally":
			var a := _pick(u, alive_of(u.team), "lowest_hp")
			if a != null:
				out.append(a)
		"attacker":
			var att: RtUnit = ctx.get("attacker")
			if att != null and not att.dead:
				out.append(att)
		"foe":
			pass
		_:
			for x in hit:
				out.append(x)
	return out


func _scaled(u: RtUnit, x: RtUnit, scale: String) -> float:
	match scale:
		"max_hp":
			return u.max_hp
		"target_max_hp":
			return x.max_hp
		"lost_hp":
			return u.max_hp - u.hp
		"def":
			return u.def_of("phys")
	return u.atk()


## Dégâts : puissance × K / (K + DEF effective), critique, blocage, bonus et réductions.
func _deal(u: RtUnit, x: RtUnit, mult: float, scale: String, kind: String, flags: Dictionary) -> void:
	if x.dead or not x.targetable():
		return
	var dmg_rules: Dictionary = rules["damage"]
	var power := _scaled(u, x, scale) * mult
	var bonus := u.mod("dmg_pct")
	if u.has_status("grace"):
		var g: Dictionary = HeroDb.faction("dame")["mechanic"]["grace"]
		bonus += float(g["dmg_pct"]) + float(u.mods.get("grace_dmg_bonus", 0.0))
	if u.has_status("galop"):
		bonus += float(HeroDb.faction("cavalier")["mechanic"]["galop"]["dmg_pct"])
	if u.has_faction("fou"):
		var per: Dictionary = HeroDb.faction("fou")["mechanic"]["per_stack"]
		bonus += u.eveil * (float(per["dmg_pct"]) + float(u.mods.get("eveil_dmg_pct", 0.0)))
	var tour: Dictionary = HeroDb.faction("tour")["mechanic"]
	var heavy := x.ov_cost() >= int(tour["threshold"]) and not x.ov_skill().is_empty()
	var chatiment := false
	if heavy and u.has_faction("tour"):
		bonus += float(tour["passive_dmg_pct"])
	if flags.get("chatiment", false) and heavy:
		bonus += float(tour["chatiment_dmg_pct"]) + float(u.mods.get("chatiment_bonus", 0.0))
		chatiment = true
	var val := power * maxf(0.1, 1.0 + bonus / 100.0)
	val *= maxf(0.1, 1.0 + x.mod("dmg_taken_pct") / 100.0)
	var crit := false
	if kind != "true":
		var pen := clampf(float(u.mods.get("pen_pct", 0.0)) / 100.0, 0.0, 0.9)
		var k := float(dmg_rules["def_k_base"]) + float(dmg_rules["def_k_per_level"]) * u.level
		val *= k / (k + x.def_of(kind) * (1.0 - pen))
		var cc := u.crit_chance() - float(x.mods.get("crit_res", 0.0))
		if rng.randf() * 100.0 < cc:
			crit = true
			val *= 1.0 + (float(dmg_rules["crit_dmg"]) + u.base["crit_dmg"]) / 100.0
		if rng.randf() * 100.0 < float(x.mods.get("block", 0.0)):
			val *= 1.0 - float(dmg_rules["block_pct"]) / 100.0
	var dr := x.mod("dr_pct")
	if x.has_status("grace"):
		dr += float(HeroDb.faction("dame")["mechanic"]["grace"]["dr_pct"])
	if x.has_status("galop"):
		dr += float(HeroDb.faction("cavalier")["mechanic"]["galop"]["dr_pct"])
	if x.has_faction("pion"):
		dr += x.promesse * float(HeroDb.faction("pion")["mechanic"]["per_stack"]["dr_pct"])
	val *= 1.0 - clampf(dr, -100.0, 70.0) / 100.0
	var v := float(dmg_rules["variance"])
	val *= rng.randf_range(1.0 - v, 1.0 + v)
	val = maxf(1.0, val)
	_take(u, x, val, crit, flags.get("basic", false), chatiment)
	var ls := float(u.mods.get("lifesteal_pct", 0.0))
	if u.has_faction("tour"):
		ls += float(tour.get("lifesteal_pct", 0.0))
	if ls > 0.0 and not u.dead:
		_heal(u, u, val * ls / 100.0, true)
	if chatiment:
		apply_status(u, x, "ov_tax", 10.0, 1.0, 100.0, true)


## Applique des dégâts (boucliers d'abord). src peut être null (dégâts sur la durée).
func _take(src: RtUnit, x: RtUnit, val: float, crit := false, basic := false, chatiment := false, dot := false) -> void:
	var absorbed := 0.0
	var left := val
	for i in range(x.shields.size() - 1, -1, -1):
		var s := x.shields[i]
		var a := minf(left, float(s["amount"]))
		s["amount"] = float(s["amount"]) - a
		left -= a
		absorbed += a
		if float(s["amount"]) <= 0.01:
			x.shields.remove_at(i)
		if left <= 0.0:
			break
	var before := x.hp
	x.hp -= left
	x.taken += val
	if src != null:
		src.dealt += val
	_emit({"type": "damage", "src": src, "dst": x, "amount": val, "crit": crit, "absorbed": absorbed,
		"basic": basic, "chatiment": chatiment, "dot": dot})
	if x.has_status("sleep") and not dot:
		x.remove_status("sleep")
	if x.has_faction("cavalier") and before > x.hp:
		var pct_lost := (before - x.hp) / x.max_hp * 100.0
		_gain_rage(x, pct_lost * float(HeroDb.faction("cavalier")["mechanic"]["rage_per_hp_pct"]))
	if x.hp <= 0.0:
		_kill(src, x)
		return
	if src != null and not dot:
		for p in _passives(x):
			if p.get("trigger", "") == "on_hit_taken" and float(x.icd.get(p["name"], 0.0)) <= 0.0:
				if rng.randf() * 100.0 < float(p.get("chance", 100.0)):
					x.icd[p["name"]] = float(p.get("icd", 1.0))
					_run_effects(x, p.get("effects", []), {"primary": src, "hit": [src], "attacker": src})
	_check_hp_triggers(x)
	for a in alive_of(x.team):
		for p in _passives(a):
			if p.get("trigger", "") == "ally_low" and x.hp_ratio() * 100.0 < float(p.get("pct", 30.0)) and not a.low_allies.has(x):
				a.low_allies[x] = true
				_run_effects(a, p.get("effects", []), {"primary": x, "hit": [x]})


func _check_hp_triggers(x: RtUnit) -> void:
	for p in _passives(x):
		if p.get("trigger", "") == "hp_below" and x.hp_ratio() * 100.0 < float(p.get("pct", 50.0)) and not x.once_done.has(p["name"]):
			x.once_done[p["name"]] = true
			_run_effects(x, p.get("effects", []), {"primary": x, "hit": [x]})


func _kill(src: RtUnit, x: RtUnit) -> void:
	if x.dead:
		return
	x.hp = 0.0
	x.dead = true
	x.statuses.clear()
	x.shields.clear()
	queue[x.team].erase(x)
	_emit({"type": "death", "dst": x, "src": src})
	energy[1 - x.team] = minf(float(rules["energy"]["max"]), energy[1 - x.team] + float(rules["kill_energy"]))
	for u in units:
		if not u.dead and u.target == x:
			u.target = null
	if src != null and not src.dead:
		for p in _passives(src):
			if p.get("trigger", "") == "on_kill":
				_run_effects(src, p.get("effects", []), {"primary": src, "hit": [src]})
	for a in alive_of(x.team):
		for p in _passives(a):
			if p.get("trigger", "") == "ally_death":
				_run_effects(a, p.get("effects", []), {"primary": a, "hit": [a]})
		if a.has_faction("pion"):
			var m: Dictionary = HeroDb.faction("pion")["mechanic"]
			if a.promesse < int(m["max_stacks"]):
				_add_stack(a, "promesse", 1)
			var heal_pct := float(m["heal_pct"]) + float(a.mods.get("promesse_heal_pct", 0.0))
			_heal(a, a, a.max_hp * heal_pct / 100.0)


func _add_stack(x: RtUnit, sid: String, n: int) -> void:
	match sid:
		"promesse":
			var m: Dictionary = HeroDb.faction("pion")["mechanic"]
			var before := x.promesse
			x.promesse = mini(int(m["max_stacks"]), x.promesse + n)
			var gained := x.promesse - before
			if gained > 0:
				x.mods["atk_pct"] = float(x.mods.get("atk_pct", 0.0)) + gained * float(m["per_stack"]["atk_pct"])
			_emit({"type": "stack", "dst": x, "id": "promesse", "n": x.promesse})
		"eveil":
			x.eveil = mini(int(HeroDb.faction("fou")["mechanic"]["max_stacks"]), x.eveil + n)
			_emit({"type": "stack", "dst": x, "id": "eveil", "n": x.eveil})


func _heal(u: RtUnit, x: RtUnit, amount: float, quiet := false) -> void:
	if x.dead:
		return
	var bonus := u.mod("heal_pct")
	if u.has_status("grace"):
		bonus += float(HeroDb.faction("dame")["mechanic"]["grace"]["heal_pct"])
	if u.has_faction("fou"):
		bonus += u.eveil * float(u.mods.get("eveil_heal_pct", 0.0))
	var v := amount * maxf(0.0, 1.0 + bonus / 100.0) * maxf(0.0, 1.0 + x.mod("healed_pct") / 100.0)
	var real := minf(v, x.max_hp - x.hp)
	x.hp += real
	u.healed += real
	if v > 0.0 and not quiet:
		_emit({"type": "heal", "src": u, "dst": x, "amount": v})


func _shield(u: RtUnit, x: RtUnit, amount: float, dur: float) -> void:
	if x.dead:
		return
	x.shields.append({"amount": amount, "t": dur})
	u.shielded += amount
	_emit({"type": "shield", "src": u, "dst": x, "amount": amount})


func _gain_rage(x: RtUnit, amount: float) -> void:
	if x.has_status("galop"):
		return
	var m: Dictionary = HeroDb.faction("cavalier")["mechanic"]
	x.rage += amount * (1.0 + float(x.mods.get("rage_gain_pct", 0.0)) / 100.0)
	if x.rage >= float(m["rage_max"]):
		x.rage = 0.0
		var g: Dictionary = m["galop"]
		apply_status(x, x, "galop", float(m["galop_dur"]), float(g["aspd_pct"]), 100.0)
		_emit({"type": "galop", "dst": x})


## Pose un statut. value = null : valeur par défaut du statut. Renvoie true si posé.
func apply_status(src: RtUnit, x: RtUnit, sid: String, dur: float, value: Variant, chance := 100.0, stack := false) -> bool:
	if x.dead:
		return false
	var info := HeroDb.status_info(sid)
	if info.is_empty():
		push_warning("Statut inconnu : " + sid)
		return false
	var kind := str(info.get("kind", "buff"))
	var hostile := kind in ["debuff", "cc"] and src != null and src.team != x.team
	if hostile:
		if kind == "cc" and (x.flag("cc_immune") or (x.boss and sid in ["freeze", "sleep", "taunt"])):
			_emit({"type": "resist", "dst": x, "id": sid})
			return false
		var c: float = chance + float(src.base["acc"]) - float(x.base["res"])
		c = maxf(float(rules["damage"]["min_chance"]), c) if chance < 100.0 else c
		if rng.randf() * 100.0 >= c:
			return false
		if x.boss and kind == "cc":
			dur *= 0.5
	var v: float = float(value) if value != null else float(info.get(str(info.get("scaled", "")), 0.0))
	if bool(info.get("dot", false)) or bool(info.get("hot", false)):
		var pct: float = float(value) if value != null else 10.0
		v = (src.atk() if src != null else 100.0) * pct / 100.0
	var el := str(info.get("element", ""))
	if el != "" and src != null and src.has_faction("roi") and hostile:
		if _react(src, x, el):
			return true
	var existing := x.get_status(sid)
	if not existing.is_empty():
		existing["t"] = maxf(float(existing["t"]), dur)
		if stack:
			existing["value"] = float(existing["value"]) + v
		else:
			existing["value"] = v if absf(v) > absf(float(existing["value"])) else existing["value"]
		existing["src"] = src
	else:
		x.statuses.append({"id": sid, "t": dur, "value": v, "src": src, "acc": 0.0})
	_emit({"type": "status", "dst": x, "id": sid, "src": src, "dur": dur})
	if sid in ["moral", "ferveur"] and x.has_status("moral") and x.has_status("ferveur"):
		x.remove_status("moral")
		x.remove_status("ferveur")
		var gdur := float(HeroDb.faction("dame")["mechanic"]["grace_dur"])
		if src != null:
			gdur += float(src.mods.get("grace_dur_bonus", 0.0))
		apply_status(src, x, "grace", gdur, null, 100.0)
		_emit({"type": "grace", "dst": x})
	return true


## Réaction élémentaire (Couronne du Roi) : un 2e élément différent sur la cible.
func _react(src: RtUnit, x: RtUnit, el: String) -> bool:
	var m: Dictionary = HeroDb.faction("roi")["mechanic"]
	for other in ["burn", "shock", "chill"]:
		if other == el or not x.has_status(other):
			continue
		var pair := [el, other]
		pair.sort()
		var key := "%s_%s" % pair
		var r: Dictionary = m["reactions"].get(key, {})
		if r.is_empty():
			continue
		x.remove_status(other)
		var mult := float(m["reaction_mult"]) + float(r.get("bonus_mult", 0.0))
		_emit({"type": "reaction", "src": src, "dst": x, "name": r.get("name", ""), "key": key})
		var victims: Array[RtUnit] = [x]
		if r.has("radius"):
			victims = []
			for f in foes_of(src):
				if f.pos.distance_to(x.pos) <= float(r["radius"]):
					victims.append(f)
		for v in victims:
			_deal(src, v, mult, "atk", "mag", {})
			if r.has("status") and not v.dead:
				apply_status(src, v, str(r["status"]), float(r.get("dur", 3.0)), r.get("value", null), 100.0)
		return true
	return false


func _tick_statuses(u: RtUnit, dt: float) -> void:
	for i in range(u.shields.size() - 1, -1, -1):
		u.shields[i]["t"] = float(u.shields[i]["t"]) - dt
		if float(u.shields[i]["t"]) <= 0.0:
			u.shields.remove_at(i)
	var i := u.statuses.size() - 1
	while i >= 0:
		if i >= u.statuses.size():
			i -= 1
			continue
		var s := u.statuses[i]
		var info := HeroDb.status_info(s["id"])
		if info.get("dot", false) or info.get("hot", false):
			s["acc"] = float(s["acc"]) + dt
			while float(s["acc"]) >= 1.0 and not u.dead:
				s["acc"] = float(s["acc"]) - 1.0
				if info.get("dot", false):
					_take(s["src"] if s["src"] is RtUnit else null, u, float(s["value"]), false, false, false, true)
				else:
					_heal(s["src"] if s["src"] is RtUnit and not (s["src"] as RtUnit).dead else u, u, float(s["value"]))
			if u.dead:
				return
		s["t"] = float(s["t"]) - dt
		if float(s["t"]) <= 0.0:
			u.statuses.remove_at(i)
		i -= 1


# --- Bilan ----------------------------------------------------------------

func summary() -> Dictionary:
	var out := {"winner": winner, "time": time, "units": []}
	for u in units:
		out["units"].append({"id": u.id, "team": u.team, "alive": not u.dead, "dealt": u.dealt, "taken": u.taken,
			"healed": u.healed, "shielded": u.shielded})
	return out
