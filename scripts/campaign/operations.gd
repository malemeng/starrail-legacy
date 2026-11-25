extends RefCounted

const Society = preload("res://scripts/campaign/society.gd")
const Hulls = preload("res://hull_catalog.gd")
const Economy = preload("res://economy.gd")
const Industry = preload("res://scripts/economy/industry.gd")

static func rights(world, station: Dictionary, sponsor: int = 0) -> bool:
	if station.is_empty() or station.build > 0:
		return false
	if sponsor == 0:
		sponsor = world.player
	var faction: Dictionary = world.factions.get(station.flag, {})
	var offices := [station.owner, station.get("manager", 0)]
	return sponsor > 0 and (sponsor in offices or faction.get("leader", -1) == sponsor or (sponsor == world.regent and world.regency > 0 and world.regency in offices))

static func start_project(world, port_id: int, id: String) -> bool:
	var station: Dictionary = world.ports.get(port_id, {})
	var spec := Society.candidates(Society.rules.projects, id)
	if spec.is_empty() or not rights(world, station) or world.active().loc != port_id:
		return false
	if world.campaign.projects.has(port_id) or id in world.campaign.unlocks.get(port_id, []):
		return false
	if id != "lab" and "lab" not in world.campaign.unlocks.get(port_id, []):
		return false
	if id == "restore_gate" and not world.systems[station.system].get("sites", []).any(func(site): return site.kind == "古代星门遗迹"):
		return false
	var needed := {}
	for item in spec.materials:
		needed[int(item[0])] = int(item[1])
	if not Industry.consume(station, needed):
		return false
	world.campaign.projects[port_id] = {"id": id, "progress": 0, "sponsor": world.player}
	world.event("%s 启动%s，已交付初始材料。" % [station.name, spec.name])
	return true

static func teleport(world, ship_id: int) -> bool:
	var actor: Dictionary = world.active()
	var vessel: Dictionary = world.ships.get(ship_id, {})
	if actor.loc == 0 or vessel.is_empty() or vessel.dock == 0 or not world.can_operate(vessel):
		return false
	if not ("teleport" in world.campaign.unlocks.get(actor.loc, []) and "teleport" in world.campaign.unlocks.get(vessel.dock, [])):
		return false
	var previous: Dictionary = world.ride()
	if not previous.is_empty():
		previous.captain = 0
	actor.ship = 0
	actor.loc = vessel.dock
	return world.pilot(ship_id)

static func expedition(world, kind: String, target: int) -> bool:
	var actor: Dictionary = world.active()
	var origin: Dictionary = world.ports.get(actor.loc, {})
	var destination: Dictionary = world.ports.get(target, {})
	if origin.is_empty() or destination.is_empty() or actor.has("journey") or actor.wallet < 25:
		return false
	if kind not in ["tour", "festival", "wedding", "coronation", "funeral", "pilgrimage", "embassy", "quarantine"]:
		return false
	if kind == "wedding" and actor.spouse == 0:
		return false
	if kind == "embassy" and "embassy" not in world.campaign.unlocks.get(origin.id, []):
		return false
	if kind == "coronation" and not world.factions.values().any(func(group): return group.alive and group.leader == actor.id):
		return false
	world.credit(actor.id, -25)
	var vessel: Dictionary = world.ride()
	if not vessel.is_empty():
		vessel.captain = 0
	actor.ship = 0
	actor.loc = 0
	actor.journey = {"kind": kind, "origin": origin.id, "target": target,
		"arrives": world.day + 2 + ceili(world.distance(origin.system, destination.system) / 32.0),
		"ship": vessel.get("id", 0)}
	world.event("%s 从%s启程前往%s。" % [actor.name, origin.name, destination.name])
	return true

static func arrive(world, actor: Dictionary) -> void:
	var route: Dictionary = actor.journey
	var port: Dictionary = world.ports[route.target]
	actor.loc = port.id
	actor.erase("journey")
	actor.prestige += 2
	actor.experience += 4
	match route.kind:
		"tour": port.stability = minf(100, port.stability + 6)
		"pilgrimage": actor.legitimacy = mini(5, actor.legitimacy + 1)
		"coronation": actor.legitimacy = mini(5, actor.legitimacy + 2)
		"festival", "wedding", "funeral": Society.stress(world, actor, -20)
		"embassy":
			if actor.flag >= 0 and port.flag >= 0 and port.flag != actor.flag:
				world.set_treaty(actor.flag, port.flag, 1)
		"quarantine": port.quarantine_until = world.day + 60
	if route.ship != 0 and world.ships.get(route.ship, {}).get("dock", -1) == port.id:
		world.pilot(route.ship)
	world.event("%s 的行程结束，已抵达%s。" % [actor.name, port.name])

static func civic(world, action: String, target: int) -> bool:
	var actor: Dictionary = world.active()
	var site: Dictionary = world.ports.get(actor.loc, {})
	if site.is_empty() or world.day - int(actor.last_decision) < 30:
		return false
	var official: Dictionary = world.people.get(target, {})
	match action:
		"examination":
			if actor.wallet < 10:
				return false
			world.credit(actor.id, -10)
			actor.merit += 1 + int(actor.stats.learning / 4)
		"designate":
			if not actor.noble or target not in actor.children or not official.get("alive", false):
				return false
			actor.designated_heir = target
			actor.law = 1
		"appoint":
			if not rights(world, site) or official.is_empty() or not official.alive or official.loc != site.id:
				return false
			site.manager = target
			official.employer = actor.id
			official.merit += 2
		"charter":
			if not rights(world, site):
				return false
			site.tax_rate = clampf(site.tax_rate + (0.02 if target > 0 else -0.02), 0.0, 0.25)
			world.refresh_tariffs(site.system)
			if world.people.has(site.manager):
				var manager: Dictionary = world.people[site.manager]
				manager.opinions[actor.id] = clampi(int(manager.opinions.get(actor.id, 0)) + (8 if target <= 0 else -12), -100, 100)
		"reform":
			if not rights(world, site) or actor.prestige < 4:
				return false
			actor.prestige -= 4
			site.faith = "星港公约" if actor.faith == "星灯" else "星灯"
			actor.faith = site.faith
			site.stability = maxf(0, site.stability - 4)
		"integrate":
			if not rights(world, site) or actor.wallet < 40:
				return false
			world.credit(actor.id, -40)
			site.culture = actor.culture
			site.stability = minf(100, site.stability + 8)
			actor.merit += 2
		"claim":
			var claimed: Dictionary = world.ports.get(target, {})
			if not rights(world, site) or claimed.is_empty() or claimed.flag == actor.flag or actor.flag < 0:
				return false
			world.campaign.claims[target] = {"flag": actor.flag, "holder": actor.id, "day": world.day}
		"press_claim":
			var claim: Dictionary = world.campaign.claims.get(target, {})
			if claim.get("holder", -1) != actor.id or not rights(world, site) or not world.ports.has(target):
				return false
			var defender: int = world.ports[target].flag
			if defender < 0 or actor.flag < 0 or defender == actor.flag:
				return false
			world.set_treaty(actor.flag, defender, -1)
		"tribute":
			var court: Dictionary = world.ports.get(target, {})
			if not rights(world, site) or court.is_empty() or court.flag < 0 or court.flag == site.flag or actor.wallet < 50:
				return false
			world.credit(actor.id, -50)
			world.factions[court.flag].treasury += 50
			site.tributary_to = court.flag
			world.set_treaty(site.flag, court.flag, 1)
		_: return false
	actor.last_decision = world.day
	return true

static func begin_boarding(world, target_id: int) -> bool:
	var own: Dictionary = world.ride()
	var foe: Dictionary = world.ships.get(target_id, {})
	if own.is_empty() or foe.is_empty() or own.dock != 0 or own.layer or foe.dock != 0 or foe.layer:
		return false
	if own.system != foe.system or not world.enemy(own, foe) or own.pos.distance_to(foe.pos) > 95:
		return false
	if foe.hp > 0.4 * world.HULL_HP[foe.kind] or foe.battle.shield or own.has("boarding"):
		return false
	var marines := mini(10, int(own.crew) - Hulls.crew_limits(own.kind).x)
	if marines <= 0:
		return false
	own.crew -= marines
	own.boarding = {"target": target_id, "marines": marines, "stage": 0}
	return true

static func advance_boarding(world, vessel: Dictionary) -> void:
	var op: Dictionary = vessel.boarding
	var enemy: Dictionary = world.ships.get(op.target, {})
	if enemy.is_empty() or enemy.layer or enemy.system != vessel.system or vessel.pos.distance_to(enemy.pos) > 160:
		vessel.erase("boarding")
		return
	op.stage += 1
	if op.stage < 3:
		return
	var survivors := maxi(0, op.marines - ceili(enemy.crew * 0.25))
	var previous: Dictionary = world.people.get(enemy.captain, {})
	if survivors > 0:
		if not previous.is_empty():
			previous.ship = 0
			previous.loc = world.systems[enemy.system].ports.front() if not world.systems[enemy.system].ports.is_empty() else 0
		world.DiplomaticTrade.release_for(world,0,enemy.id)
		enemy.captain = 0
		Economy.clear_assignments(world,enemy)
		for key in ["charter", "lease", "station_owner", "firm", "engaged_by", "privateer_firm", "blockade_owner", "crisis_unit", "organization"]:
			enemy.erase(key)
		for other in world.ships.values():
			if other.has("engaged_by"):
				other.engaged_by.erase(enemy.id)
		enemy.owner = Hulls.operator_id(vessel)
		if vessel.has("firm"):
			enemy.firm = vessel.firm
		enemy.flag = vessel.flag
		enemy.raid = world.NEUTRAL
		enemy.crew = survivors
		enemy.locked = false
		world.event("登舰组接管了%s。" % world.HULLS[enemy.kind])
		if vessel.captain == world.player:
			Society.offer(world, "on_ship_captured", {"prize": enemy.id, "ship_name": world.HULLS[enemy.kind]})
	else:
		enemy.crew = maxi(1, enemy.crew - op.marines)
		world.event("登舰组未能夺取舰桥。")
	vessel.erase("boarding")

static func daily(world) -> void:
	var actor: Dictionary = world.active()
	if actor.has("journey") and world.day >= actor.journey.arrives:
		arrive(world, actor)
	var own: Dictionary = world.ride()
	if own.has("boarding"):
		advance_boarding(world, own)
	for site in world.campaign.projects.keys():
		var project: Dictionary = world.campaign.projects[site]
		var station: Dictionary = world.ports[site]
		if not rights(world, station, project.sponsor):
			continue
		if project.progress % 6 == 0 and not Industry.consume(station, {Industry.Ware.ENERGY: 1}):
			continue
		project.progress += 1
		var spec := Society.candidates(Society.rules.projects, project.id)
		if project.progress < int(spec.days):
			continue
		if not world.campaign.unlocks.has(site):
			world.campaign.unlocks[site] = []
		world.campaign.unlocks[site].append(project.id)
		match project.id:
			"terraform":
				station.pop_cap += 150
				station.stability = minf(100, station.stability + 12)
			"restore_gate":
				world.systems[station.system].gate_online = true
		world.campaign.projects.erase(site)
		world.event("%s 完成%s。" % [station.name, spec.name])
