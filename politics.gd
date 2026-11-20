extends RefCounted

const Portrait = preload("res://portrait.gd")
const Economy = preload("res://economy.gd")

static func age(world, character: Dictionary) -> int:
	return floori((world.day - character.birth) / 360.0)

static func opinion(world, first: int, second: int) -> int:
	var actor: Dictionary = world.people[first]
	var target: Dictionary = world.people[second]
	var adjustment := 0
	if actor.noble and target.noble and (actor.house == target.house or target.id in actor.parents or target.id in actor.children):
		adjustment += 25
	if actor.flag == target.flag:
		adjustment += 10
	if actor.trait == target.trait:
		adjustment += 14
	if actor.trait == 1 and target.trait == 1:
		adjustment -= 15
	return clampi(adjustment + int(actor.opinions.get(second, 0)), -100, 100)

static func influence(world, target: int) -> bool:
	var actor: Dictionary = world.active()
	if target == world.player or not world.people.has(target) or not world.people[target].alive or actor.wallet < 35:
		return false
	var receiver: Dictionary = world.people[target]
	if actor.loc == 0 or receiver.loc != actor.loc:
		return false
	world.credit(actor.id, -35)
	world.credit(target, 35)
	receiver.opinions[actor.id] = mini(100, int(receiver.opinions.get(actor.id, 0)) + 18)
	receiver.loyalty = mini(100, receiver.loyalty + 8)
	world.event("%s 收到了 %s 的馈赠。" % [receiver.name, actor.name])
	return true

static func kin(world, first: int, second: int) -> bool:
	var first_line := ancestors(world, first)
	for candidate in ancestors(world, second):
		if candidate in first_line:
			return true
	return false

static func ancestors(world, person_id: int) -> Array:
	var family := [person_id]
	var cursor := 0
	while cursor < family.size():
		for parent in world.people[family[cursor]].parents:
			if parent not in family:
				family.append(parent)
		cursor += 1
	return family

static func marry(world, first: int, second: int) -> bool:
	if first == second or not world.people.has(first) or not world.people.has(second):
		return false
	var actor: Dictionary = world.people[first]
	var partner: Dictionary = world.people[second]
	if not actor.noble or not partner.noble or not actor.alive or not partner.alive or actor.spouse != 0 or partner.spouse != 0 or age(world, actor) < 18 or age(world, partner) < 18 or kin(world, first, second):
		return false
	if (first == world.player or second == world.player) and (actor.loc == 0 or partner.loc != actor.loc or opinion(world, second, first) < -5):
		return false
	actor.spouse = second
	partner.spouse = first
	actor.last_child = world.day - 365
	partner.last_child = actor.last_child
	if actor.flag >= 0 and partner.flag >= 0 and actor.flag != partner.flag and world.factions[actor.flag].alive and world.factions[partner.flag].alive:
		var first_ruler: int = world.factions[actor.flag].leader
		var second_ruler: int = world.factions[partner.flag].leader
		if (first == first_ruler or kin(world, first, first_ruler)) and (second == second_ruler or kin(world, second, second_ruler)):
			world.set_treaty(actor.flag, partner.flag, 1)
			world.event("%s 和 %s 因联姻结盟。" % [world.flag_name(actor.flag), world.flag_name(partner.flag)])
	if first == world.player or second == world.player or world.day > 0:
		world.event("%s 与 %s 缔结婚姻。" % [actor.name, partner.name])
	return true

static func child(world, first: int, second: int) -> int:
	var parent: Dictionary = world.people[first]
	var partner: Dictionary = world.people[second]
	if not parent.noble or not partner.noble or not parent.alive or not partner.alive or parent.spouse != second:
		return 0
	var given: String = world.START_NAMES[world.rng.randi_range(0, world.START_NAMES.size() - 1)]
	var basis: Dictionary = parent
	if second == world.player:
		basis = partner
	elif world.factions.get(partner.flag, {}).get("leader", 0) == second and first != world.player:
		basis = partner
	var baby: int = world.person(given, basis.house, world.day, basis.flag, basis.loc,
		basis.origin, world.rng.randi_range(0, 3), Portrait.inherit(parent.look, partner.look, world.rng))
	world.people[baby].parents = [first, second]
	world.people[baby].noble = true
	for person_id in [first, second]:
		world.people[person_id].children.append(baby)
		world.people[person_id].last_child = world.day
	if world.player in [first, second] or world.regency in [first, second]:
		world.event("家族新成员：%s · %s。" % [basis.house, given])
		world.attention = true
	return baby

static func by_birth(world, list: Array) -> Array:
	list.sort_custom(func(first, second): return world.people[first].birth < world.people[second].birth or (world.people[first].birth == world.people[second].birth and first < second))
	return list

static func blood(world, person_id: int) -> Array:
	var result: Array = []
	var seen := {person_id: true}
	var wave := [person_id]
	while not wave.is_empty():
		var following: Array = []
		for current in wave:
			var actor: Dictionary = world.people[current]
			for relative in by_birth(world, actor.children.duplicate()) + by_birth(world, actor.parents.duplicate()):
				if not seen.has(relative):
					following.append(relative)
					seen[relative] = true
					if kin(world, person_id, relative):
						result.append(relative)
		wave = following
	return result

static func heirs(world, person_id: int) -> Array:
	var actor: Dictionary = world.people[person_id]
	if not actor.noble:
		return []
	var children := by_birth(world, actor.children.filter(func(other): return world.people[other].alive))
	if not children.is_empty():
		return children
	var relatives := blood(world, person_id).filter(func(other): return world.people[other].alive)
	return relatives.slice(0, 1)

static func change_law(world) -> bool:
	var actor: Dictionary = world.active()
	if actor.is_empty() or not actor.noble or world.regency != 0:
		return false
	actor.law = 1 - actor.law
	if actor.law == 1:
		for child_id in heirs(world, actor.id).slice(1):
			var relative: Dictionary = world.people[child_id]
			relative.opinions[actor.id] = int(relative.opinions.get(actor.id, 0)) - 25
			relative.loyalty = maxi(0, relative.loyalty - 12)
	world.event("家族继承制度变更为%s。" % ("集中继承" if actor.law == 1 else "分产"))
	return true

static func clean_jobs(world, dead: int) -> void:
	for character in world.people.values():
		if character.employer == dead:
			character.employer = 0
	for vessel in world.ships.values():
		if vessel.captain == dead:
			vessel.captain = 0
			vessel.job = {}
			vessel.travel = {}
	for station in world.ports.values():
		if station.manager == dead:
			station.manager = 0

static func estate(world, dead: int, recipients: Array) -> void:
	var actor: Dictionary = world.people[dead]
	var main: int = recipients[0] if not recipients.is_empty() else 0
	var stations: Array = []
	for port_id in world.ports:
		if world.ports[port_id].owner == dead:
			stations.append(port_id)
	var capital: int = world.factions.get(actor.flag, {}).get("capital", 0)
	if capital in stations:
		stations.erase(capital)
		stations.push_front(capital)
	var compensated: Array = []
	for index in range(stations.size()):
		var recipient: int = main if actor.law == 1 or main == 0 else recipients[index % recipients.size()]
		world.ports[stations[index]].owner = recipient
		if world.ports[stations[index]].manager != 0 and recipient != 0:
			world.people[world.ports[stations[index]].manager].employer = recipient
		compensated.append(recipient)
	for vessel in world.ships.values():
		if vessel.owner == dead:
			vessel.owner = main
			vessel.job = {}
			vessel.travel = {}
			if vessel.captain != 0:
				world.people[vessel.captain].employer = main
	if main != 0:
		var empty_handed := recipients.filter(func(other): return other not in compensated)
		if actor.law == 0 and recipients.size() > 1 and not empty_handed.is_empty():
			var portion := floori(float(actor.wallet) / empty_handed.size())
			for receiver in empty_handed:
				world.credit(receiver, portion)
				actor.wallet -= portion
		world.credit(main, actor.wallet)
		world.people[main].law = actor.law
		for firm_id in actor.shares:
			world.people[main].shares[firm_id] = world.people[main].shares.get(firm_id, 0) + actor.shares[firm_id]
		for sibling in recipients.slice(1):
			var claimant: Dictionary = world.people[sibling]
			var resentment := 30 if actor.law == 0 and sibling in compensated else 20
			claimant.opinions[main] = int(claimant.opinions.get(main, 0)) - resentment
	actor.shares.clear()
	actor.wallet = 0

static func select_leader(world, flag: int, location: int, excluded: int = 0) -> int:
	var regime: int = world.factions[flag].regime
	var top := -INF
	var elected := 0
	for candidate in world.people.values():
		if not candidate.alive or candidate.id == excluded or candidate.flag != flag or age(world, candidate) < 18:
			continue
		var score := float(candidate.wallet)
		match regime:
			0:
				if not candidate.noble:
					continue
				score += 300 if candidate.loc == location else 0
			1:
				score = candidate.endorsement * 30 + candidate.loyalty
				for official in world.people.values():
					if official.alive and official.flag == flag and official.id != candidate.id:
						score += opinion(world, official.id, candidate.id) * 0.1
			2:
				score += 160 if candidate.origin == 1 else 0
			3:
				score = 900 if world.ships.get(candidate.ship, {}).get("kind", -1) == 2 else 0
				score += candidate.loyalty + (100 if candidate.origin == 0 else 0)
			4:
				score = candidate.wallet * 0.2
				for firm_id in candidate.shares:
					if world.ports[world.firms[firm_id].hq].flag == flag:
						score += 10 * candidate.shares[firm_id]
		if score > top:
			top = score
			elected = candidate.id
	if elected == 0:
		elected = world.random_person(flag, location)
		world.people[elected].noble = regime == 0
	return elected

static func board(world, firm_id: int) -> void:
	var enterprise: Dictionary = world.firms[firm_id]
	var best := -1
	var chosen := 0
	for candidate in world.people.values():
		if not candidate.alive or age(world, candidate) < 18:
			continue
		var stake: int = candidate.shares.get(firm_id, 0)
		if stake > best and (stake > 0 or candidate.loc == enterprise.hq):
			best = stake
			chosen = candidate.id
	if chosen == 0 and not world.people.get(enterprise.director, {}).get("alive", false):
		chosen = world.random_person(world.ports[enterprise.hq].flag, enterprise.hq)
		world.people[chosen].shares[firm_id] = 100
	if chosen != 0 and enterprise.director != chosen:
		enterprise.director = chosen
		world.event("%s 董事会任命 %s。" % [enterprise.name, world.name_of(chosen)])

static func landing(world, actor: Dictionary) -> int:
	if actor.loc != 0 and world.ports.has(actor.loc):
		return actor.loc
	if world.ships.has(actor.ship):
		return world.systems[world.ships[actor.ship].system].ports[0]
	return world.systems[0].ports[0]

static func find_regent(world, child_id: int) -> int:
	var child_data: Dictionary = world.people[child_id]
	for candidate in child_data.parents + blood(world, child_id):
		if world.people[candidate].alive and age(world, world.people[candidate]) >= 18:
			return candidate
	return world.random_person(child_data.flag, landing(world, child_data), child_data.house)

static func die(world, person_id: int, save_first: bool = true) -> void:
	var actor: Dictionary = world.people[person_id]
	if not actor.alive:
		return
	var was_player: bool = person_id == world.player
	var fallback := landing(world, actor)
	if was_player and save_first and world.before_death.is_valid():
		world.before_death.call()
	actor.alive = false
	actor.ship = 0
	if actor.spouse != 0:
		world.people[actor.spouse].spouse = 0
		actor.spouse = 0
	var recipients := heirs(world, person_id)
	var main: int = recipients[0] if not recipients.is_empty() else 0
	clean_jobs(world, person_id)
	estate(world, person_id, recipients)
	world.contracts.erase(person_id)
	for flag in world.factions:
		var group: Dictionary = world.factions[flag]
		if not group.alive or group.leader != person_id:
			continue
		if main != 0 and group.regime == 0:
			group.leader = main
			world.people[main].flag = flag
		else:
			var candidates: Array = world.systems_owned(flag)
			group.leader = select_leader(world, flag, candidates[0] if not candidates.is_empty() else fallback, person_id)
		group.npc = group.leader != main or not was_player
		world.event("%s 易主：%s 上任。" % [group.name, world.name_of(group.leader)])
	for firm_id in world.firms:
		if world.firms[firm_id].director == person_id:
			board(world, firm_id)
	if not was_player:
		if person_id == world.regency:
			world.regency = 0
			world.regent = 0
		return
	world.last_player = person_id
	world.attention = true
	world.event("%s 去世，遗产已结算。" % actor.name)
	if world.regency != 0 and person_id == world.regent:
		main = world.regency
		world.regent = 0
	if main == 0:
		world.player = 0
		world.succession = true
		return
	if age(world, world.people[main]) < 18:
		world.regency = main
		world.regent = find_regent(world, main)
		world.player = world.regent
		world.event("%s 尚未成年，由 %s 担任摄政。" % [world.name_of(main), world.name_of(world.regent)])
	else:
		world.regency = 0
		world.regent = 0
		world.player = main
		world.event("现在扮演继承人 " + world.name_of(main))
	var successor: Dictionary = world.active()
	if successor.loc == 0 and successor.ship == 0:
		successor.loc = fallback
	var vessel: Dictionary = world.ride()
	if not vessel.is_empty():
		vessel.travel = {}
		vessel.job = {}

static func choose(world, person_id: int) -> bool:
	if not world.succession or not world.people.has(person_id):
		return false
	var actor: Dictionary = world.people[person_id]
	if not actor.alive or age(world, actor) < 18:
		return false
	world.player = person_id
	var faction: Dictionary = world.factions.get(actor.flag, {})
	if faction.get("leader", 0) == person_id:
		faction.npc = false
	world.succession = false
	world.attention = false
	if actor.loc == 0 and actor.ship == 0:
		actor.loc = world.systems[0].ports[0]
	var current: Dictionary = world.ride()
	if not current.is_empty():
		current.travel = {}
		current.job = {}
		current.locked = false
	world.event("%s 的人生现在由你继续。" % actor.name)
	return true

static func conquer(world, port_id: int, attacker: int, owner: int = 0) -> void:
	var station: Dictionary = world.ports[port_id]
	var previous: int = station.flag
	var old_manager: int = station.manager
	if old_manager != 0:
		world.people[old_manager].employer = 0
	station.flag = attacker
	station.owner = owner
	if owner != 0:
		world.people[owner].noble = true
	elif attacker >= 0 and world.factions[attacker].regime == 0:
		station.owner = world.factions[attacker].leader
	station.manager = 0
	station.defense = 22
	station.since = world.day
	world.event("%s 被 %s 从 %s 手中夺取。" % [station.name, world.flag_name(attacker), world.flag_name(previous)])
	if world.factions.has(previous):
		var left: Array = world.systems_owned(previous)
		if left.is_empty():
			world.factions[previous].alive = false
			world.factions[previous].capital = 0
			for vessel in world.ships.values():
				if vessel.flag == previous:
					vessel.flag = world.NEUTRAL
					vessel.job = {}
			world.event(world.flag_name(previous) + " 失去了最后一座空间站。")
		elif world.factions[previous].capital == port_id:
			world.factions[previous].capital = left[0]
	if old_manager == world.player or previous >= 0 and world.factions[previous].leader == world.player:
		world.attention = true

static func found(world, name_text: String, port_id: int, regime: int = 0) -> bool:
	var actor: Dictionary = world.active()
	var own_nation: bool = world.factions.has(actor.flag) and world.factions[actor.flag].leader == actor.id
	if regime not in range(world.REGIMES.size()) or name_text.strip_edges().is_empty() or not world.ports.has(port_id) or world.ports[port_id].owner != world.player or world.ports[port_id].build > 0 or own_nation:
		return false
	var flag: int = world.uid() + 10
	world.factions[flag] = {"name": name_text.strip_edges().left(18), "style": 0, "regime": regime, "color": "8ad9ad", "leader": world.player,
		"npc": false, "alive": true, "treasury": 0, "last_war": world.day, "capital": port_id}
	actor.flag = flag
	actor.noble = actor.noble or regime == 0
	for vessel in world.ships.values():
		if vessel.owner == world.player:
			vessel.flag = flag
	for station in world.ports.values():
		if station.owner == world.player:
			station.flag = flag
	if regime == 4 and world.ports[port_id].firm == 0:
		world.incorporate(world.flag_name(flag) + "控股", world.player, port_id)
	world.event("%s 建立了新势力：%s。" % [actor.name, world.flag_name(flag)])
	return true

static func rival(world, faction_id: int, station: Dictionary) -> Dictionary:
	var best := INF
	var target := {}
	for port_data in world.ports.values():
		var flag: int = port_data.flag
		if flag < 0 or flag == faction_id or port_data.build != 0 or not world.factions[flag].alive or world.treaty(faction_id, flag).state == 1:
			continue
		var score: float = world.distance(station.system, port_data.system) + port_data.defense * 2.0
		if world.treaty(faction_id, flag).state == -1:
			score *= 0.45
		if score < best:
			best = score
			target = port_data
	return target

static func military(world) -> void:
	for flag in world.factions.keys():
		var group: Dictionary = world.factions[flag]
		if not group.alive or not group.npc:
			continue
		var stations: Array = world.systems_owned(flag)
		if stations.is_empty():
			continue
		var deployed := false
		for vessel in world.ships.values():
			if vessel.flag != flag or vessel.job.get("kind", "") != "攻城":
				continue
			deployed = true
			var target: Dictionary = world.ports[vessel.job.target]
			if not world.hostile(flag, target.flag):
				vessel.job = {"kind": "护航", "system": vessel.system}
				continue
			if world.day < vessel.job.eta:
				continue
			vessel.system = target.system
			if vessel.job.get("arrived", false):
				if vessel.locked:
					continue
				var home_guard := false
				for defender in world.ships.values():
					if defender.flag == target.flag and defender.system == target.system and defender.job.get("kind", "") == "护航":
						home_guard = true
						break
				target.defense -= 19 if home_guard else 31
				vessel.hp -= 11 if home_guard else 4
				if vessel.hp <= 0:
					world.destruction(vessel.id)
				elif target.defense <= 0:
					conquer(world, target.id, flag)
					vessel.job = {"kind": "护航", "system": vessel.system}
			else:
				vessel.pos = target.pos + Vector2(-255, 130)
				vessel.job.arrived = true
		if deployed:
			continue
		var capital: Dictionary = world.ports.get(group.capital, world.ports[stations[0]])
		var leader: Dictionary = world.people[group.leader]
		var interval := [60, 150, 120][group.style] as int
		interval -= 30 if leader.trait == 1 else 0
		if world.day - group.last_war < interval:
			continue
		var target := rival(world, flag, capital)
		if target.is_empty():
			continue
		var vessel_id := 0
		for existing in world.ships.values():
			if existing.flag == flag and existing.captain != world.player and not existing.locked and existing.job.get("kind", "") == "护航" and existing.hp >= 65:
				vessel_id = existing.id
				break
		if capital.hulls[2] > 0 and group.treasury >= 180:
			group.treasury -= 180
			capital.hulls[2] -= 1
			var officer: int = world.random_person(flag, capital.id)
			vessel_id = world.ship(2, 0, officer, flag, capital.system, capital.pos)
		if vessel_id == 0:
			continue
		if not world.hostile(flag, target.flag):
			world.set_treaty(flag, target.flag, -1)
			world.event("%s 向 %s 宣战。" % [group.name, world.flag_name(target.flag)])
		group.last_war = world.day
		world.ships[vessel_id].job = {"kind": "攻城", "target": target.id, "eta": world.day + 60}
	for relation in world.relations:
		var pact: Dictionary = world.relations[relation]
		if pact.state == -1 and world.day - pact.since > 390 and world.rng.randf() < 0.20:
			world.set_treaty(relation.x, relation.y, 0)
			world.event("%s 与 %s 停战。" % [world.flag_name(relation.x), world.flag_name(relation.y)])

static func appointments(world) -> void:
	for station in world.ports.values():
		var group: Dictionary = world.factions.get(station.flag, {})
		if station.build > 0:
			continue
		if group.get("npc", false) and station.manager == 0:
			station.manager = world.random_person(station.flag, station.id)
			world.people[station.manager].employer = group.leader
		if station.owner != 0 and station.owner != group.get("leader", 0) and group.get("alive", false):
			var holder: Dictionary = world.people[station.owner]
			if holder.alive and age(world, holder) >= 18 and holder.trait == 1 and world.day - station.since >= 180:
				var head: int = group.leader
				if opinion(world, holder.id, head) < 15 and world.rng.randf() < 0.22:
					holder.flag = world.uid() + 10
					world.factions[holder.flag] = {"name": holder.house + " · 分支" + str(holder.flag), "color": "bc84af", "style": 0, "regime": 0, "leader": holder.id,
						"npc": true, "alive": true, "treasury": 600, "last_war": world.day, "capital": station.id}
					conquer(world, station.id, holder.flag, holder.id)
					world.set_treaty(holder.flag, world.people[head].flag, -1)
					if head == world.player:
						world.attention = true
	for vessel in world.ships.values():
		if vessel.owner == 0 or vessel.captain == 0 or vessel.captain == vessel.owner or vessel.captain == world.player or vessel.locked:
			continue
		var worker: Dictionary = world.people[vessel.captain]
		if worker.employer != vessel.owner:
			continue
		if world.people[vessel.owner].wallet >= 4:
			world.credit(vessel.owner, -4)
			world.credit(worker.id, 4)
		else:
			worker.loyalty -= 8
		if worker.loyalty + opinion(world, worker.id, vessel.owner) < 20 and world.rng.randf() < 0.30:
			if vessel.owner == world.player:
				world.event("%s 因忠诚过低，带走了受托舰船。" % worker.name)
				world.attention = true
			vessel.owner = worker.id
			vessel.flag = world.NEUTRAL
			worker.flag = world.NEUTRAL
			worker.employer = 0
			vessel.job = {}

static func advance(world) -> void:
	for person_id in world.people.keys():
		var actor: Dictionary = world.people[person_id]
		if not actor.alive:
			continue
		if world.day - actor.birth >= actor.lifespan and not world.ships.get(actor.ship, {}).get("locked", false):
			die(world, person_id)
			if world.succession or world.attention:
				return
		if actor.spouse > person_id and actor.children.size() < 4 and world.day - actor.last_child > 720 and age(world, actor) < 48:
			var partner: Dictionary = world.people[actor.spouse]
			if partner.alive and age(world, partner) < 48 and world.rng.randf() < 0.13:
				child(world, person_id, partner.id)
				if world.attention:
					return
		if world.day % 360 == 0 and actor.noble and person_id != world.player and actor.spouse == 0 and age(world, actor) >= 18 and age(world, actor) < 48 and world.rng.randf() < 0.48:
			for partner in world.people.values():
				if partner.id != world.player and partner.noble and partner.alive and partner.spouse == 0 and age(world, partner) < 48 and (actor.flag == partner.flag or world.rng.randf() < 0.15):
					if marry(world, actor.id, partner.id):
						break
	if world.regency != 0 and age(world, world.people[world.regency]) >= 18:
		var controlled: Dictionary = world.ride()
		if controlled.get("owner", 0) == world.regency and controlled.dock != 0:
			world.people[world.regency].loc = controlled.dock
			world.people[world.regency].ship = controlled.id
			controlled.captain = world.regency
			world.people[world.regent].ship = 0
		world.player = world.regency
		world.regency = 0
		world.regent = 0
		world.attention = true
		world.event(world.name_of(world.player) + " 已成年，摄政结束。")
		return
	military(world)
	if world.day % 90 == 0:
		appointments(world)
	if world.day % 360 == 0:
		for firm_id in world.firms:
			board(world, firm_id)
			var firm: Dictionary = world.firms[firm_id]
			var director: Dictionary = world.people[firm.director]
			var host: int = world.ports[firm.hq].flag
			if director.id != world.player and host >= 0:
				firm.embargo = world.NEUTRAL
				for flag in world.factions:
					if world.factions[flag].alive and world.hostile(host, flag):
						firm.embargo = flag
						break
		for flag in world.factions:
			var group: Dictionary = world.factions[flag]
			if group.alive and group.regime == 1 and world.day % 1440 == 0:
				var elected := select_leader(world, flag, group.capital)
				if group.leader != elected:
					group.leader = elected
					world.event("%s 议会选出了新执政官 %s。" % [group.name, world.name_of(elected)])
