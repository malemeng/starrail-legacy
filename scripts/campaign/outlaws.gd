extends RefCounted

const Registry = preload("res://data/campaign/outlaws.json")
const Geometry = preload("res://scripts/models/station_geometry.gd")
const PIRATES := "rift_pirates"
const CULT := "ember_cult"
static var groups: Dictionary = Registry.data

static func id_for(ship: Dictionary) -> String:
	var id: String = ship.get("organization", "")
	if not groups.has(id) or ship.get("owner", 0) != 0 or ship.flag != int(groups[id].flag):
		return ""
	return id

static func assign(ship: Dictionary, group: String, anchor: Vector2) -> void:
	ship.organization = group
	ship.job = {"kind": "守誓" if group == CULT else "劫掠", "anchor": anchor, "waypoint": ship.pos}

static func member(world, group: String, system: int, base: Dictionary, slot: int) -> int:
	var spec: Dictionary = groups[group]
	var kind: int = world.Hulls.kind_for_reference(spec.fleet[slot])
	var outward: Vector2 = Geometry.outpost(base).outward
	var spread := (-0.3 if slot % 2 == 0 else 0.3) * PI
	var position: Vector2 = base.pos + outward * float(Geometry.Defenses.geometry(kind).radius) + outward.rotated(spread) * float(spec.patrol_radius)
	var captain: int = world.random_person(int(spec.flag), 0)
	world.people[captain].faith = spec.faith
	var id: int = world.ship(kind, 0, captain, int(spec.flag), system, position)
	assign(world.ships[id], group, base.pos)
	return id

static func anchorage(world, region: Dictionary, group: String, distance: float, roll: int) -> Vector2:
	var bodies: Array = [region.sun] + region.planets
	if region.has("companion"):
		bodies.append(region.companion)
	var bearing := (Vector2(region.field) - Vector2(region.sun.pos)).angle() + deg_to_rad(roll % 151 - 75)
	var ports: Array = region.ports.map(func(id): return Geometry.layout(world.ports[id]))
	for i in range(32):
		var point := Vector2(region.field) + Vector2.from_angle(bearing + i * TAU / 16.0) * (distance + (i / 16) * Geometry.MAX_REACH)
		var hull := Geometry.outpost({"pos":point,"group":group})
		if not bodies.any(func(body): return Geometry.intersects_body(hull,body)) and not ports.any(func(port): return Geometry.overlaps(hull,port)):
			return point
	var safe := distance
	for body: Dictionary in bodies:
		safe = maxf(safe, Vector2(region.field).distance_to(body.pos) + float(body.radius) + Geometry.MAX_REACH)
	for port: Dictionary in ports:
		safe = maxf(safe, Vector2(region.field).distance_to(port.berth) + Geometry.MAX_REACH * 2.0)
	return Vector2(region.field) + Vector2.from_angle(bearing) * (safe + 1.0)

static func establish(world) -> void:
	if world.campaign.has("outlaw_bases"):
		return
	var sites := {}
	world.campaign.outlaw_bases = sites
	var candidates: Array = range(2, world.core_count)
	var pirate_systems := {}
	for ship: Dictionary in world.ships.values():
		if ship.flag == world.RAIDERS:
			if ship.has("crisis_unit"):
				ship.flag = world.ROGUE_MACHINES
			else:
				pirate_systems[ship.system] = true
				if not ship.has("organization"):
					assign(ship, PIRATES, ship.pos)
					ship.job.ambush_only = ship.system == 1
	var origin: Vector2 = world.systems[0].pos
	candidates.sort_custom(func(a, b): return origin.distance_squared_to(world.systems[a].pos) > origin.distance_squared_to(world.systems[b].pos))
	for group: String in groups:
		var spec: Dictionary = groups[group]
		var eligible: Array = candidates.filter(func(i): return not pirate_systems.has(i)) if group == CULT else candidates
		if eligible.is_empty():
			eligible = candidates
		var picks: Array = eligible.slice(0, maxi(1, ceili(eligible.size() * 0.6)))
		var roll := absi(hash([world.settings.seed, group]))
		var system: int = picks[roll % picks.size()]
		candidates.erase(system)
		var region: Dictionary = world.systems[system]
		var position := anchorage(world, region, group, float(spec.stand_off), roll)
		var base := {"group": group, "pos": position, "members": [], "next_muster": 0, "reserve": int(spec.reserve_hulls), "stock": world.quantities([])}
		region.outlaw_base = base
		sites[group] = system
		for slot in spec.fleet.size():
			base.members.append(member(world, group, system, base, slot))
		if not base.members.is_empty():
			var lead_ship: Dictionary = world.ships.get(base.members[0], {})
			if not lead_ship.is_empty():
				base.boss_id = int(lead_ship.get("captain", 0))

static func boss_for(world, group: String) -> Dictionary:
	var sites: Dictionary = world.campaign.get("outlaw_bases", {})
	if not sites.has(group):
		return {}
	var system: int = sites[group]
	var base: Dictionary = world.systems[system].get("outlaw_base", {})
	if base.is_empty():
		return {}
	var bid := int(base.get("boss_id", 0))
	if bid != 0 and world.people.has(bid) and world.people[bid].get("alive", false):
		return world.people[bid]
	for sid in base.get("members", []):
		var sh: Dictionary = world.ships.get(int(sid), {})
		var cap := int(sh.get("captain", 0))
		if cap != 0 and world.people.has(cap) and world.people[cap].get("alive", false):
			base.boss_id = cap
			return world.people[cap]
	return {}

static func on_roster(world, id: int, group: String) -> bool:
	var ship: Dictionary = world.ships.get(id, {})
	return not ship.is_empty() and id_for(ship) == group and ship.hp > 0

static func summary(world) -> Array:
	var result := []
	for group: String in world.campaign.get("outlaw_bases", {}):
		var spec: Dictionary = groups[group]
		var system: int = world.campaign.outlaw_bases[group]
		var base: Dictionary = world.systems[system].outlaw_base
		var active := 0
		for ship_id: int in base.members:
			if on_roster(world, ship_id, group):
				active += 1
		result.append({"id": group, "name": spec.name, "flag": int(spec.flag), "color": spec.color,
			"description": spec.description, "base_name": spec.base_name, "system": system, "pos": base.pos,
			"active": active, "capacity": spec.fleet.size(), "reserve": base.reserve})
	return result

static func permits_target(ship: Dictionary, target: Dictionary) -> bool:
	if id_for(ship) != CULT:
		return true
	var radius := float(groups[CULT].guard_radius)
	return Vector2(target.pos).distance_squared_to(ship.job.anchor) <= radius * radius

static func cargo_priority(world, ship: Dictionary) -> float:
	var spec: Dictionary = groups[PIRATES]
	var capacity: int = world.HULL_CARGO[ship.kind]
	if capacity <= 0:
		return 1.0
	var fill := 1.0 - float(world.cargo_free(ship)) / capacity
	return lerpf(1.0, float(spec.cargo_priority), clampf(fill / float(spec.priority_load), 0.0, 1.0))

static func loot(world, ship: Dictionary, base: Dictionary) -> bool:
	var spec: Dictionary = groups[PIRATES]
	var available: int = world.cargo_free(ship)
	var hold: Array = ship.cargo
	if available < world.HULL_CARGO[ship.kind] and ship.pos.distance_squared_to(base.pos) <= float(spec.loot_range) ** 2:
		for i in hold.size():
			base.stock[i] += hold[i]
			hold[i] = 0
		available = world.HULL_CARGO[ship.kind]
	if available == 0:
		ship.job.waypoint = base.pos
		return true
	var nearest: Dictionary = {}
	var distance := INF
	for wreck: Dictionary in world.wrecks.values():
		if wreck.system != ship.system or Vector2(wreck.pos).distance_squared_to(base.pos) > float(spec.loot_search) ** 2:
			continue
		var gap: float = ship.pos.distance_squared_to(wreck.pos)
		if gap < distance and wreck.stock.any(func(q): return q > 0):
			nearest = wreck
			distance = gap
	if nearest.is_empty():
		if available < world.HULL_CARGO[ship.kind]:
			ship.job.waypoint = base.pos
			return true
		return false
	ship.job.waypoint = nearest.pos
	if distance <= float(spec.loot_range) ** 2:
		var limit := mini(int(spec.loot_units), available)
		for i in hold.size():
			var moved := mini(nearest.stock[i], limit)
			nearest.stock[i] -= moved
			hold[i] += moved
			limit -= moved
			if limit == 0:
				break
	return true

static func advance(world) -> void:
	var pilot: Dictionary = world.ride()
	for group: String in world.campaign.get("outlaw_bases", {}):
		var system: int = world.campaign.outlaw_bases[group]
		var region: Dictionary = world.systems[system]
		var base: Dictionary = region.outlaw_base
		var spec: Dictionary = groups[group]
		var outward: Vector2 = Geometry.outpost(base).outward
		var vacancy := -1
		for slot in base.members.size():
			var id: int = base.members[slot]
			if not on_roster(world, id, group):
				if vacancy < 0:
					vacancy = slot
				continue
			var ship: Dictionary = world.ships[id]
			if ship.locked or ship.layer or ship.dock != 0 or not ship.get("travel", {}).is_empty():
				continue
			if group == PIRATES and loot(world, ship, base):
				if ship.system != system:
					ship.travel = {"waypoints": [system], "stop": base.pos, "port": 0}
					continue
			else:
				var raid_phase: int = (int(world.day) / 18 + int(slot)) % 3
				if group == PIRATES and world.day >= 6 and int(slot) > 0 and raid_phase != 0:
					var local_merchants: Array = []
					for s: Dictionary in world.ships.values():
						if s.id != pilot.get("id", 0) and s.system == ship.system and s.hp > 0 and not s.layer and s.dock == 0 and s.flag != int(spec.flag):
							if s.job.get("kind", "") in ["贸易", "站属贸易", "采矿", "站属采矿"] or s.cargo.any(func(q): return q > 0):
								local_merchants.append(s)
					if not local_merchants.is_empty():
						var prey: Dictionary = local_merchants[0]
						ship.job.waypoint = prey.pos
						if pilot.get("system", -1) != ship.system or pilot.get("layer", false) or pilot.get("dock", 0) != 0:
							ship.pos = Vector2(ship.pos).move_toward(ship.job.waypoint, 160.0)
							if ship.pos.distance_to(prey.pos) <= 320.0:
								var defender_id := 0
								var defender_captain := 0
								for esc: Dictionary in world.ships.values():
									if esc.id != ship.id and esc.hp > 0 and not esc.layer and esc.dock == 0 and esc.system == prey.system and esc.flag == prey.flag and esc.job.get("kind", "") in ["护航", "巡逻"] and Vector2(esc.pos).distance_to(prey.pos) <= 420.0:
										defender_id = esc.id
										defender_captain = int(esc.get("captain", 0))
										break
								var stolen := 0
								var free_hold: int = world.cargo_free(ship)
								var loot_cap := mini(int(spec.loot_units), free_hold)
								if defender_id == 0 and loot_cap > 0:
									for wi in ship.cargo.size():
										var take := mini(int(prey.cargo[wi]), loot_cap)
										if take > 0:
											prey.cargo[wi] -= take
											ship.cargo[wi] += take
											stolen += take
											loot_cap -= take
											if loot_cap == 0:
												break
								if defender_id != 0:
									ship.hp -= 24
									prey.hp -= 12
									if ship.hp <= 0:
										world.destruction(ship.id, defender_captain)
										continue
								else:
									prey.hp -= 28
								if stolen > 0:
									world.event("裂缝海盗在 %s 截击商船 %s，掠夺 %d 单位货物。" % [world.systems[prey.system].name, world.HULLS[prey.kind], stolen])
								if prey.hp <= 0:
									world.destruction(prey.id, int(ship.get("captain", 0)))
						continue
					if ship.system == system:
						var raid_targets: Array = []
						for p: Dictionary in world.ports.values():
							if p.build == 0 and not p.get("landing_only", false) and p.system != system:
								raid_targets.append(p)
						if not raid_targets.is_empty():
							var boss := boss_for(world, group)
							var target_port: Dictionary = raid_targets[0]
							if not boss.is_empty():
								var best_score := -INF
								for cand: Dictionary in raid_targets:
									var score := float(int(cand.get("treasury", 0))) * 0.001
									var mgr := int(cand.get("manager", 0))
									if mgr != 0:
										score -= float(int(boss.get("opinions", {}).get(mgr, 0))) * 0.15
									if cand.flag >= 0:
										var fl := int(world.factions.get(cand.flag, {}).get("leader", 0))
										if fl != 0:
											score -= float(int(boss.get("opinions", {}).get(fl, 0))) * 0.10
									score += float(absi(hash([world.settings.seed, int(world.day) / 18, int(slot), int(cand.id)])) % 100) * 0.05
									if score > best_score:
										best_score = score
										target_port = cand
							else:
								var pick_idx: int = absi(hash([world.settings.seed, int(world.day) / 18, int(slot)])) % raid_targets.size()
								target_port = raid_targets[pick_idx]
							ship.fuel = maxf(ship.fuel, float(world.Hulls.MODELS[ship.kind].fuel_tank))
							ship.travel = {"waypoints": [target_port.system], "stop": target_port.pos, "port": 0}
							continue
					var sys_ports: Array = world.systems[ship.system].ports
					if not sys_ports.is_empty():
						var port_pos := Vector2(world.ports[sys_ports[0]].pos)
						var orbit_angle: float = float(world.day % 90) / 90.0 * TAU + float(slot)
						ship.job.waypoint = port_pos + Vector2.from_angle(orbit_angle) * 340.0
				else:
					if ship.system != system:
						ship.travel = {"waypoints": [system], "stop": base.pos, "port": 0}
						continue
					var angle: float = TAU * (float(world.day % 120) / 120.0 + float(slot) / base.members.size())
					ship.job.waypoint = base.pos + outward.rotated(sin(angle)*PI*0.45)*float(spec.patrol_radius)
					if group == PIRATES and (world.day / 30 + slot) % 2 == 0:
						ship.job.waypoint = region.field
			if pilot.get("system", -1) != ship.system or pilot.get("layer", false) or pilot.get("dock", 0) != 0:
				ship.pos = Vector2(ship.pos).move_toward(ship.job.waypoint, 95.0)
		if vacancy < 0 or base.reserve == 0:
			base.next_muster = 0
		elif base.next_muster == 0:
			base.next_muster = world.day + int(spec.rebuild_days)
		elif world.day >= base.next_muster:
			base.members[vacancy] = member(world, group, system, base, vacancy)
			base.reserve -= 1
			base.next_muster = world.day + int(spec.rebuild_days)
