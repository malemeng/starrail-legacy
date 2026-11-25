extends RefCounted

const Portrait = preload("res://portrait.gd")
const Society = preload("res://scripts/campaign/society.gd")
const WarPeace = preload("res://scripts/campaign/war_peace.gd")
const Hulls = preload("res://hull_catalog.gd")
const Economy = preload("res://economy.gd")

static func age(world, character: Dictionary) -> int:
	return floori((world.day - character.birth) / 360.0)

static func opinion(world, first: int, second: int) -> int:
	var actor: Dictionary = world.people[first]
	var target: Dictionary = world.people[second]
	var adjustment := 0
	if actor.noble and target.noble and (actor.house == target.house or target.id in actor.parents or target.id in actor.children):
		adjustment += 25
	if actor.faith == target.faith:
		adjustment += 2
	if actor.culture == target.culture:
		adjustment += 3
	if actor.flag == target.flag:
		adjustment += 10
	if actor.trait == target.trait:
		adjustment += 14
	if actor.trait == 1 and target.trait == 1:
		adjustment -= 15
	adjustment += Society.relation_bonus(actor, second)
	return clampi(adjustment + int(actor.opinions.get(second, 0)), -100, 100)

static func gift_wait(world, target: int) -> int:
	var history: Dictionary = world.people.get(target,{}).get("gifts_received",{})
	if not history.has(world.player):
		return 0
	return maxi(0,int(history[world.player])+int(Society.rules.personal_gift.interval_days)-world.day)

static func can_gift(world, target: int, remote: bool = false) -> bool:
	var actor: Dictionary = world.active()
	var receiver: Dictionary = world.people.get(target,{})
	return target != actor.id and receiver.get("alive",false) and (remote or (actor.loc > 0 and actor.loc == receiver.loc)) and actor.wallet >= int(Society.rules.personal_gift.cost) and gift_wait(world,target) == 0

static func influence(world, target: int, remote: bool = false) -> bool:
	if not can_gift(world,target,remote):
		return false
	var actor: Dictionary = world.active()
	var receiver: Dictionary = world.people[target]
	var gift: Dictionary = Society.rules.personal_gift
	receiver.get_or_add("gifts_received",{})[actor.id] = world.day
	world.credit(actor.id,-int(gift.cost))
	world.credit(target,int(gift.cost))
	Society.trait_stress(world, actor, "gift")
	receiver.opinions[actor.id] = mini(100, int(receiver.opinions.get(actor.id, 0)) + int(gift.opinion))
	receiver.loyalty = mini(100, receiver.loyalty + int(gift.loyalty))
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

static func marriage_terms(world, first: int, second: int, remote: bool = false) -> Dictionary:
	var terms := {"eligible":false,"accepted":false,"dynastic":false,"hook":false,"reason":"请选择另一位在世人物。"}
	if first == second or not world.people.has(first) or not world.people.has(second):
		return terms
	var actor: Dictionary = world.people[first]
	var partner: Dictionary = world.people[second]
	terms.dynastic = actor.noble and partner.noble
	if not actor.alive or not partner.alive:
		return terms
	if age(world,actor) < 18 or age(world,partner) < 18:
		terms.reason = "双方均须成年。"
		return terms
	if actor.spouse != 0 or partner.spouse != 0:
		terms.reason = "已有配偶，不能重复登记婚姻。"
		return terms
	if actor.gender == partner.gender or kin(world,first,second):
		terms.reason = "现行婚配规则要求双方异性且没有共同血亲。"
		return terms
	if not remote and (not terms.dynastic or first == world.player or second == world.player) and (actor.loc == 0 or partner.loc != actor.loc):
		terms.reason = "到同一港口见面后可以求婚。"
		return terms
	terms.eligible = true
	var proposed: Dictionary = partner if second != world.player else actor
	var proposer: Dictionary = actor if second != world.player else partner
	if opinion(world,proposed.id,proposer.id) < -5:
		var hook: Dictionary = proposer.hooks.get(proposed.id,{})
		if not terms.dynastic or hook.get("expires",-1) < world.day:
			terms.reason = "%s不愿意接受求婚。" % proposed.name
			return terms
		terms.hook = true
	terms.accepted = true
	terms.reason = "%s同意了这门婚事。" % proposed.name
	return terms

static func marry(world, first: int, second: int, remote: bool = false) -> bool:
	var terms := marriage_terms(world,first,second,remote)
	if not terms.accepted:
		return false
	var actor: Dictionary = world.people[first]
	var partner: Dictionary = world.people[second]
	if terms.hook:
		var proposer: Dictionary = actor if second != world.player else partner
		var target: Dictionary = partner if second != world.player else actor
		if proposer.hooks[target.id].get("strength",1) <= 1: proposer.hooks.erase(target.id)
		world.event("%s 动用把柄促成了与 %s 的联姻。" % [proposer.name,target.name])
	actor.spouse = second
	partner.spouse = first
	actor.last_child = world.day - 365
	partner.last_child = actor.last_child
	if terms.dynastic and actor.flag >= 0 and partner.flag >= 0 and actor.flag != partner.flag and world.factions[actor.flag].alive and world.factions[partner.flag].alive:
		var first_ruler: int = world.factions[actor.flag].leader
		var second_ruler: int = world.factions[partner.flag].leader
		if (first == first_ruler or kin(world, first, first_ruler)) and (second == second_ruler or kin(world, second, second_ruler)):
			world.set_treaty(actor.flag, partner.flag, 1)
			world.event("%s 和 %s 因联姻结盟。" % [world.flag_name(actor.flag), world.flag_name(partner.flag)])
	if first == world.player or second == world.player or world.day > 0:
		world.event("%s 与 %s 缔结婚姻。" % [actor.name, partner.name])
	return true

static func child(world, first: int, second: int) -> int:
	var parent: Dictionary = world.people.get(first,{})
	var partner: Dictionary = world.people.get(second,{})
	if parent.is_empty() or partner.is_empty() or not parent.alive or not partner.alive or parent.spouse != second or partner.spouse != first:
		return 0
	var basis: Dictionary = parent
	if parent.noble != partner.noble:
		basis = parent if parent.noble else partner
	elif second == world.player:
		basis = partner
	elif world.factions.get(partner.flag, {}).get("leader", 0) == second and first != world.player:
		basis = partner
	var baby_gender: int = world.rng.randi_range(0, 1)
	var given: String = world.random_given_name(basis.house, baby_gender)
	var baby: int = world.person(given, basis.house, world.day, basis.flag, basis.loc,
		basis.origin, world.rng.randi_range(0, 3), Portrait.inherit(parent.look, partner.look, world.rng), baby_gender)
	world.people[baby].parents = [first, second]
	world.people[baby].noble = parent.noble or partner.noble
	var baby_data: Dictionary = world.people[baby]
	for cong in Society.CK_CONGENITAL:
		var in_first: bool = cong in parent.get("ck_traits", [])
		var in_second: bool = cong in partner.get("ck_traits", [])
		var inherit_chance := 0.75 if (in_first and in_second) else (0.35 if (in_first or in_second) else 0.0)
		if inherit_chance > 0.0 and world.rng.randf() < inherit_chance:
			Society.apply_trait_mod(baby_data, cong)
	for person_id in [first, second]:
		world.people[person_id].children.append(baby)
		world.people[person_id].last_child = world.day
	if world.player in [first, second] or world.regency in [first, second]:
		world.event("家族新成员：%s · %s。" % [basis.house, given])
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
	var children := by_birth(world, actor.children.filter(func(other): return world.people[other].alive))
	if actor.get("designated_heir", 0) in children:
		children.erase(actor.designated_heir)
		children.push_front(actor.designated_heir)
	if not children.is_empty():
		return children
	if not actor.noble and world.people.get(actor.spouse,{}).get("alive",false):
		return [actor.spouse]
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
			Economy.clear_assignments(world,vessel)
	for station in world.ports.values():
		if station.manager == dead:
			station.manager = 0

static func estate(world, dead: int, recipients: Array) -> void:
	var actor: Dictionary = world.people[dead]
	var main: int = recipients[0] if not recipients.is_empty() else 0
	world.StationEquity.inherit(world,dead,main)
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
			Economy.clear_assignments(world,vessel)
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
	else:
		for firm_id in actor.shares:
			world.firms[firm_id].treasury_shares += int(actor.shares[firm_id])
	actor.shares.clear()
	actor.wallet = 0

static func select_leader(world, flag: int, location: int, excluded: int = 0) -> int:
	var regime: int = world.factions[flag].regime
	var company: int = world.Equity.company(world,world.factions[flag])
	if company != 0:
		var elected_director: int = world.Equity.elected(world,company)
		if elected_director != 0 and elected_director != excluded:
			return elected_director
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
				score = Hulls.MODELS[world.ships[candidate.ship].kind].power * 3 if world.ships.has(candidate.ship) else 0
				score += candidate.loyalty + (100 if candidate.origin == 0 else 0)
			5, 7:
				score = candidate.merit * 10 + candidate.stats.stewardship + candidate.stats.learning
			6:
				score = candidate.prestige * 6 + candidate.stats.prowess + candidate.loyalty
			8:
				score = candidate.stats.martial * 5 + candidate.prestige + candidate.endorsement * 12
			9:
				score = candidate.legitimacy * 20 + candidate.stats.diplomacy + candidate.prestige
		if score > top:
			top = score
			elected = candidate.id
	if elected == 0:
		elected = world.random_person(flag, location)
		world.people[elected].noble = regime == 0
	return elected

static func board(world, firm_id: int) -> void:
	var enterprise: Dictionary = world.firms[firm_id]
	var chosen: int = world.Equity.elected(world,firm_id)
	if chosen == 0 and not world.people.get(enterprise.director, {}).get("alive", false):
		chosen = world.random_person(world.ports[enterprise.hq].flag, enterprise.hq)
	if chosen == 0:
		return
	if enterprise.director != chosen:
		enterprise.director = chosen
		world.EquityOrders.audit(world)
		world.event("%s 董事会任命 %s。" % [enterprise.name, world.name_of(chosen)])
	var flag: int = enterprise.flag
	var group: Dictionary = world.factions.get(flag,{})
	if group.get("alive",false) and group.get("firm",0) == firm_id and group.leader != chosen:
		Society.install_ruler(world,flag,chosen,true)

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
	world.DiplomaticTrade.release_for(world,person_id)
	world.ShareExchange.release_for(world,person_id)
	var actor: Dictionary = world.people[person_id]
	if not actor.alive:
		return
	var was_player: bool = person_id == world.player
	var fallback := landing(world, actor)
	if was_player and save_first and world.before_death.is_valid():
		world.before_death.call()
	world.EquityOrders.revoke_signer(world,person_id)
	actor.alive = false
	actor.death_day = world.day
	actor.ship = 0
	var recipients := heirs(world, person_id)
	if actor.spouse != 0:
		world.people[actor.spouse].spouse = 0
		actor.spouse = 0
	var main: int = recipients[0] if not recipients.is_empty() else 0
	clean_jobs(world, person_id)
	estate(world, person_id, recipients)
	world.contracts.erase(person_id)
	for flag in world.factions:
		var group: Dictionary = world.factions[flag]
		if not group.alive or group.leader != person_id:
			continue
		if main != 0 and group.regime == 0 and kin(world,person_id,main):
			group.leader = main
			world.people[main].flag = flag
		else:
			var candidates: Array = world.systems_owned(flag)
			group.leader = select_leader(world, flag, candidates[0] if not candidates.is_empty() else fallback, person_id)
		group.npc = group.leader != main or not was_player
		var incoming: Dictionary = world.people[group.leader]
		for subordinate in world.people.values():
			if subordinate.alive and subordinate.flag == flag and subordinate.id != incoming.id:
				subordinate.opinions[incoming.id] = int(subordinate.opinions.get(incoming.id, 0)) - (10 if incoming.legitimacy >= 4 else 20)
		world.event("%s 易主：%s 上任。" % [group.name, world.name_of(group.leader)])
	for firm_id in world.firms:
		if world.firms[firm_id].director == person_id:
			board(world, firm_id)
	if not world.campaign.get("equity_orders",{}).get("orders",{}).is_empty():
		world.EquityOrders.audit(world)
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
		world.event("%s 尚未成年，由 %s %s。" % [world.name_of(main),world.name_of(world.regent),"担任摄政" if world.people[main].noble else "担任监护人"])
	else:
		world.regency = 0
		world.regent = 0
		world.player = main
		world.event("现在扮演继承人 " + world.name_of(main))
	var successor: Dictionary = world.active()
	Society.offer(world, "on_succession")
	if successor.loc == 0 and successor.ship == 0:
		successor.loc = fallback
	var vessel: Dictionary = world.ride()
	if not vessel.is_empty():
		Economy.clear_assignments(world,vessel)

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
		Economy.clear_assignments(world,current)
		current.locked = false
	Society.offer(world, "on_succession")
	world.event("%s 的人生现在由你继续。" % actor.name)
	return true

## Switch player control to any living non-raider character at any time.
static func switch_character(world, person_id: int) -> bool:
	if not world.people.has(person_id) or person_id == world.player:
		return false
	var actor: Dictionary = world.people[person_id]
	if not actor.alive or int(actor.get("flag", world.NEUTRAL)) == world.RAIDERS:
		return false
	var prev_id: int = world.player
	if world.people.has(prev_id):
		world.last_player = prev_id
		var prev_actor: Dictionary = world.people[prev_id]
		var prev_faction: Dictionary = world.factions.get(int(prev_actor.get("flag", world.NEUTRAL)), {})
		if prev_faction.get("leader", 0) == prev_id:
			prev_faction.npc = true
		var prev_ship_id := int(prev_actor.get("ship", 0))
		if prev_ship_id > 0 and world.ships.has(prev_ship_id):
			var prev_ship: Dictionary = world.ships[prev_ship_id]
			prev_ship.locked = false
			if prev_ship.job.is_empty():
				var role := "采矿" if Economy.Hulls.MODELS[prev_ship.kind].mine >= 20 else "贸易"
				prev_ship.job = {"kind": role, "automatic": true, "label": "自动" + role, "phase": 0}
				prev_ship.default_behavior = prev_ship.job.duplicate(true)
	world.player = person_id
	world.regency = 0
	world.regent = 0
	world.succession = false
	world.attention = false
	var next_faction: Dictionary = world.factions.get(int(actor.get("flag", world.NEUTRAL)), {})
	if next_faction.get("alive", false) and next_faction.get("leader", 0) == person_id:
		next_faction.npc = false
	if int(actor.get("loc", 0)) == 0 and int(actor.get("ship", 0)) == 0:
		var cap := int(next_faction.get("capital", 0))
		actor.loc = cap if world.ports.has(cap) else int(world.systems[0].ports[0])
	var current: Dictionary = world.ride()
	if not current.is_empty():
		Economy.clear_assignments(world, current)
		current.locked = false
	world.event("你已切换为 %s 视角继续星海人生。" % actor.name)
	return true

## Spawn a brand-new captain with a starter ship in the existing universe after death.
static func new_adventurer(world) -> bool:
	if not world.succession:
		return false
	var spawn_port := 0
	if not world.systems.is_empty() and not world.systems[0].ports.is_empty():
		var first_pid := int(world.systems[0].ports[0])
		if world.ports.get(first_pid, {}).get("build", 1) == 0:
			spawn_port = first_pid
	if spawn_port == 0:
		for pid in world.ports:
			if world.ports[pid].build == 0:
				spawn_port = int(pid)
				break
	if spawn_port == 0:
		return false
	var station: Dictionary = world.ports[spawn_port]
	var starter_ref: String = Society.rules.deployment.starter
	var gender: int = world.rng.randi_range(0, 1)
	var names := ["林溯", "沈岚", "周澈", "顾屿", "陆离", "许衡", "叶青", "程远"]
	var new_name: String = names[world.rng.randi_range(0, names.size() - 1)]
	var new_id: int = world.person(new_name, "远岚", -26 * 360, world.NEUTRAL, spawn_port, 0, world.rng.randi_range(0, 3), Portrait.random_look_for_gender(world.rng, gender), gender)
	world.people[new_id].wallet = int(Economy.Industry.RULES.ship_market.starting_working_capital)
	var starter_kind: int = Hulls.kind_for_reference(starter_ref)
	var ship_id: int = world.ship(starter_kind, new_id, new_id, world.NEUTRAL, station.system, station.pos, spawn_port)
	world.people[new_id].ship = ship_id
	world.player = new_id
	world.regency = 0
	world.regent = 0
	world.succession = false
	world.attention = false
	Society.offer(world, "on_succession")
	world.event("新的开拓者「%s」在 %s 登舰启航，继续在这片星区航行。" % [new_name, station.name])
	return true

static func conquer(world, port_id: int, attacker: int, owner: int = 0) -> void:
	if Society.civil_capture(world, port_id, attacker):
		return
	var station: Dictionary = world.ports[port_id]
	var previous: int = station.get("occupied_from", station.flag)
	station.erase("occupied_from")
	world.StationEquity.freeze(world,station)
	var old_manager: int = station.manager
	if old_manager != 0:
		world.people[old_manager].employer = 0
	station.flag = attacker
	world.refresh_tariffs(station.system)
	station.owner = owner
	if owner != 0:
		world.people[owner].noble = true
	elif attacker >= 0 and world.factions[attacker].regime == 0:
		station.owner = world.factions[attacker].leader
	station.manager = 0
	world.Equity.update_operator(world,station)
	station.defense = 22
	station.since = world.day
	world.event("%s 被 %s 从 %s 手中夺取。" % [station.name, world.flag_name(attacker), world.flag_name(previous)])
	reconcile_capital(world, previous)

static func reconcile_capital(world, flag: int) -> void:
	var faction: Dictionary = world.factions.get(flag, {})
	if not faction.get("alive", false):
		return
	var capital: Dictionary = world.ports.get(faction.capital, {})
	if capital.get("occupied_from", capital.get("flag", -1)) == flag and capital.build == 0:
		return
	var replacement := 0
	for site in world.ports.values():
		if site.build == 0 and site.get("occupied_from", site.flag) == flag:
			replacement = site.id
			if site.flag == flag:
				break
	faction.capital = replacement
	if replacement != 0:
		if faction.get("firm", 0) != 0:
			world.firms[faction.firm].hq = replacement
		return
	faction.alive = false
	world.refresh_all_tariffs()
	for vessel in world.ships.values():
		if vessel.flag == flag:
			vessel.flag = world.NEUTRAL
			Economy.clear_assignments(world,vessel)
	world.event(world.flag_name(flag) + " 失去了最后一座空间站。")

static func found(world, name_text: String, port_id: int, regime: int = 0, founder_id: int = -1) -> bool:
	var fid: int = world.player if founder_id <= 0 else founder_id
	var actor: Dictionary = world.people.get(fid, {})
	if actor.is_empty() or not actor.alive:
		return false
	var own_nation: bool = world.factions.has(actor.flag) and world.factions[actor.flag].leader == actor.id
	if regime not in range(world.REGIMES.size()) or name_text.strip_edges().is_empty() or not world.ports.has(port_id) or world.ports[port_id].owner != fid or world.ports[port_id].build > 0 or own_nation:
		return false
	var flag: int = world.uid() + 10
	world.factions[flag] = {"name": name_text.strip_edges().left(18), "style": 0, "regime": regime, "color": "8ad9ad", "leader": fid,
		"npc": fid != world.player, "alive": true, "treasury": 0, "last_war": world.day, "capital": port_id}
	actor.flag = flag
	actor.noble = actor.noble or regime == 0
	for vessel in world.ships.values():
		if vessel.owner == fid:
			vessel.flag = flag
	for station in world.ports.values():
		if station.owner == fid:
			station.flag = flag
	world.refresh_all_tariffs()
	world.Equity.establish(world,flag)
	for station in world.ports.values():
		if station.flag == flag:
			world.Equity.update_operator(world,station)
	world.event("%s 建立了新势力：%s。" % [actor.name, world.flag_name(flag)])
	return true

static func rival(world, faction_id: int, station: Dictionary) -> Dictionary:
	var civil_enemy: int = world.factions[faction_id].get("civil_enemy", world.NEUTRAL)
	if world.factions.get(civil_enemy,{}).get("alive",false) and world.hostile(faction_id,civil_enemy):
		var enemy_capital: Dictionary = world.ports.get(world.factions[civil_enemy].capital,{})
		if enemy_capital.get("flag",world.NEUTRAL) == civil_enemy:
			return enemy_capital
	var best := INF
	var target := {}
	var at_war := false
	for other in world.factions:
		if world.factions[other].alive and world.hostile(faction_id,other):
			at_war = true
			break
	for port_data in world.ports.values():
		var flag: int = port_data.flag
		if flag < 0 or flag == faction_id or port_data.build != 0 or not world.factions[flag].alive:
			continue
		var treaty: Dictionary = world.treaty(faction_id,flag)
		if treaty.state == 1 or treaty.get("truce_until",0) > world.day:
			continue
		if at_war and treaty.state != -1:
			continue
		var score: float = world.distance(station.system, port_data.system) + port_data.defense * 2.0
		if port_data.get("occupied_from",-1) == faction_id:
			score *= 0.25
		if score < best:
			best = score
			target = port_data
	return target

static func procurement_kind(site: Dictionary, faction: Dictionary) -> int:
	var selected := -1
	var best := -INF
	for kind in range(site.hulls.size()):
		if site.hulls[kind] <= 0 or not Hulls.model_limit(site, kind):
			continue
		var hull: Dictionary = Hulls.MODELS[kind]
		var price: int = Economy.ship_quote(site,kind).price
		if price > faction.treasury:
			continue
		var score := (float(hull.power) * (1.6 if faction.style == 0 else 1.0) + float(hull.hp) * 0.05) / price
		if score > best:
			selected = kind
			best = score
	return selected

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
				var origin_sys: int = vessel.job.get("origin_system", vessel.system)
				if origin_sys >= 0 and origin_sys < world.systems.size() and target.system != origin_sys:
					vessel.layer = true
					var total_days := maxi(1, int(vessel.job.eta) - int(vessel.job.get("started", world.day - 1)))
					var progress := clampf(float(world.day - int(vessel.job.get("started", world.day - 1))) / float(total_days), 0.0, 1.0)
					vessel.galpos = Vector2(world.systems[origin_sys].pos).lerp(Vector2(world.systems[target.system].pos), progress)
				continue
			vessel.layer = false
			vessel.system = target.system
			if vessel.job.get("arrived", false):
				if vessel.locked:
					continue
				var home_guard := false
				for defender in world.ships.values():
					if defender.flag == target.flag and defender.system == target.system and defender.job.get("kind", "") == "护航":
						home_guard = true
						break
				target.defense -= 14 if home_guard else 24
				vessel.hp -= 11 if home_guard else 4
				if vessel.hp <= 0:
					WarPeace.record_kill(world, vessel, target.flag)
					world.destruction(vessel.id)
				elif target.defense <= 0:
					WarPeace.occupy(world, target.id, flag)
					vessel.job = {"kind": "护航", "system": vessel.system}
			else:
				vessel.pos = target.pos + Vector2(-255, 130)
				vessel.job.arrived = true
		if deployed:
			continue
		var capital: Dictionary = world.ports.get(group.capital, world.ports[stations[0]])
		var leader: Dictionary = world.people[group.leader]
		var interval := [110, 180, 140][group.style] as int
		interval -= 20 if leader.trait == 1 else 0
		if world.day - group.last_war < interval:
			continue
		var target := rival(world, flag, capital)
		if target.is_empty():
			continue
		var new_war: bool = not world.hostile(flag,target.flag)
		if new_war:
			var reserve_days: int = [12,45,25][group.style]
			if world.day < interval / 2 + int(flag)*3 or capital.flag != flag or capital.get("blockaded",false):
				continue
			if group.treasury < reserve_days*8 or Economy.Industry.COLONY_NEEDS.any(func(ware): return Economy.Industry.available(capital,ware) < Economy.provisions_for(capital,reserve_days)):
				continue
		var task_force: Array[int] = []
		var guard_id := 0
		for existing in world.ships.values():
			if existing.flag != flag or existing.owner != 0 or existing.captain == world.player or existing.locked or existing.layer or existing.job.get("kind","") != "护航":
				continue
			if existing.system == capital.system and (guard_id == 0 or existing.hp > world.ships[guard_id].hp):
				guard_id = existing.id
			if existing.hp >= Hulls.MODELS[existing.kind].hp * 0.60:
				task_force.append(existing.id)
		task_force.erase(guard_id)
		task_force.sort_custom(func(a,b):
			var va: Dictionary = world.ships[a]
			var vb: Dictionary = world.ships[b]
			return world.distance(va.system,target.system) < world.distance(vb.system,target.system))
		if task_force.size() > 3:
			task_force.resize(3)
		if new_war and (guard_id == 0 or task_force.is_empty()):
			continue
		if task_force.is_empty() and capital.flag == flag:
			var procurement := procurement_kind(capital, group)
			var price := Economy.withdraw_priced_hull(capital,procurement,group.treasury) if procurement >= 0 else 0
			if price > 0:
				group.treasury -= price
				world.Treasury.post(world,capital,price,"船坞售舰")
				var officer: int = world.random_person(flag, capital.id)
				var bought: int = world.ship(procurement, 0, officer, flag, capital.system, capital.pos)
				if guard_id == 0:
					world.ships[bought].job = {"kind":"护航","system":capital.system}
				else:
					task_force.append(bought)
		if task_force.is_empty():
			continue
		if not world.hostile(flag, target.flag):
			world.set_treaty(flag, target.flag, -1)
			world.event("%s 向 %s 宣战，派遣 %d 艘战舰出征 %s。" % [group.name, world.flag_name(target.flag), task_force.size(), target.name])
			WarPeace.on_war_declared(world, flag, target.flag)
		group.last_war = world.day
		for vid in task_force:
			var v: Dictionary = world.ships[vid]
			var transit := clampi(int(world.distance(v.system, target.system) / 90.0), 6, 18)
			v.dock = 0
			v.job = {"kind": "攻城", "target": target.id, "origin_system": v.system, "started": world.day, "eta": world.day + transit}
	WarPeace.daily(world)
	if world.day % 6 == 0:
		for pid in world.people:
			var member: Dictionary = world.people[pid]
			if not member.alive or int(member.flag) < 0:
				continue
			var grp: Dictionary = world.factions.get(member.flag, {})
			if not grp.get("alive", false) or int(grp.leader) == pid:
				continue
			var stipend := 12 + int(member.get("merit", 0)) * 4
			if int(grp.get("treasury", 0)) >= stipend + 40:
				grp.treasury -= stipend
				member.wallet += stipend
				if pid == world.player:
					world.event("收到 %s 阵营俸禄 ¢%d。" % [world.flag_name(member.flag), stipend])

static func join_faction(world, person_id: int, flag: int) -> bool:
	var actor: Dictionary = world.people.get(person_id, {})
	var group: Dictionary = world.factions.get(flag, {})
	if actor.is_empty() or not actor.alive or group.is_empty() or not group.get("alive", false):
		return false
	if int(actor.flag) == flag:
		return true
	if world.faction_trust(flag,person_id) <= -40:
		return false
	if int(actor.flag) >= 0 and world.hostile(int(actor.flag), flag):
		return false
	for fid in world.factions:
		if world.factions[fid].alive and int(world.factions[fid].leader) == person_id:
			return false
	var old_flag := int(actor.flag)
	if int(actor.get("employer", 0)) != 0:
		actor.employer = 0
	for port_id in world.ports:
		if int(world.ports[port_id].manager) == person_id and int(world.ports[port_id].flag) != flag:
			world.ports[port_id].manager = 0
	actor.flag = flag
	for vessel in world.ships.values():
		if int(vessel.owner) == person_id:
			vessel.flag = flag
	# Benefits: immediate faction trust & leader opinion
	world.change_faction_trust(flag, person_id, 15, "宣誓加入 %s" % world.flag_name(flag))
	var new_leader := int(group.get("leader", 0))
	if new_leader != 0 and new_leader != person_id and world.people.has(new_leader):
		var leader_ref: Dictionary = world.people[new_leader]
		leader_ref.opinions[person_id] = mini(100, int(leader_ref.opinions.get(person_id, 0)) + 10)
	# Risks: penalty with previous faction and with all factions currently at war with the joined faction
	if old_flag >= 0 and old_flag != flag and world.factions.get(old_flag, {}).get("alive", false):
		world.change_faction_trust(old_flag, person_id, -15, "改投 %s" % world.flag_name(flag))
		var old_leader := int(world.factions[old_flag].get("leader", 0))
		if old_leader != 0 and old_leader != person_id and world.people.has(old_leader):
			var old_ref: Dictionary = world.people[old_leader]
			old_ref.opinions[person_id] = maxi(-100, int(old_ref.opinions.get(person_id, 0)) - 15)
	for other_flag in world.factions:
		var other := int(other_flag)
		if other != flag and world.factions[other].get("alive", false) and world.hostile(other, flag):
			world.change_faction_trust(other, person_id, -20, "加入敌对阵营 %s" % world.flag_name(flag))
	world.event("%s 加入了 %s（信任 +15，敌对势力信任 -20，可领阵营俸禄并受雇站长）。" % [actor.name, world.flag_name(flag)])
	return true

static func employ_as_manager(world, person_id: int, port_id: int) -> bool:
	var actor: Dictionary = world.people.get(person_id, {})
	var station: Dictionary = world.ports.get(port_id, {})
	if actor.is_empty() or not actor.alive or station.is_empty() or station.build != 0:
		return false
	var flag := int(station.flag)
	if flag < 0 or not world.factions.get(flag, {}).get("alive", false) or int(actor.flag) != flag:
		return false
	var leader := int(world.factions[flag].leader)
	if leader == person_id:
		return false
	if int(station.manager) == person_id:
		return true
	if world.faction_trust(flag,person_id) <= -20:
		return false
	if int(station.manager) == leader:
		return false
	if int(actor.ship) != 0 and not world.disembark(person_id):
		return false
	for other_id in world.ports:
		if int(world.ports[other_id].manager) == person_id:
			world.ports[other_id].manager = 0
	var old_mgr := int(station.manager)
	if old_mgr != 0 and world.people.has(old_mgr):
		world.people[old_mgr].employer = 0
	station.manager = person_id
	actor.employer = leader
	actor.loc = port_id
	actor.ship = 0
	world.event("%s 受雇出任 %s 站长。" % [actor.name, station.name])
	return true

static func appointments(world) -> void:
	var busy_managers := {}
	for st in world.ports.values():
		if int(st.manager) != 0:
			busy_managers[int(st.manager)] = true
	for station in world.ports.values():
		var group: Dictionary = world.factions.get(station.flag, {})
		if station.build > 0:
			continue
		if group.get("npc", false) and station.manager == 0:
			var best_candidate := 0
			var best_skill := -1
			for pid in world.people:
				var cand: Dictionary = world.people[pid]
				if not cand.alive or int(cand.flag) != int(station.flag) or int(cand.ship) != 0 or int(cand.employer) != 0:
					continue
				if int(group.leader) == pid or busy_managers.has(pid):
					continue
				if world.faction_trust(station.flag,pid) <= -20:
					continue
				var skill := int(cand.stats.stewardship)
				if pid == world.player:
					skill += 4
				if skill > best_skill:
					best_skill = skill
					best_candidate = pid
			if best_candidate != 0:
				station.manager = best_candidate
				world.people[best_candidate].employer = group.leader
				world.people[best_candidate].loc = station.id
				busy_managers[best_candidate] = true
				if best_candidate == world.player:
					world.event("%s 任命你为 %s 站长。" % [world.name_of(group.leader), station.name])
			else:
				station.manager = world.random_person(station.flag, station.id)
				world.people[station.manager].employer = group.leader
				busy_managers[int(station.manager)] = true

static func settle_captain_payroll(world) -> void:
	if world.day % 90 != 0 or world.campaign.get("captain_payroll_day",-1) == world.day:
		return
	world.campaign.captain_payroll_day = world.day
	for vessel in world.ships.values():
		var principal: int = world.ship_principal(vessel)
		if principal == 0 or vessel.captain == 0 or vessel.captain == principal or vessel.locked:
			continue
		var worker: Dictionary = world.people[vessel.captain]
		if world.reports_to(worker) != principal:
			continue
		var pay := int(Economy.Industry.RULES.ship_market.captain_quarterly_pay)
		if Economy.account_balance(world,vessel) >= pay:
			Economy.pay(world,vessel,-pay,"船长薪酬")
			world.credit(worker.id, pay)
			Economy.Diagnostics.transfer(world,vessel,"船长薪酬","%s #%d" % [worker.name,worker.id],-pay)
		else:
			worker.loyalty -= 8
		if worker.id != world.player and worker.loyalty + opinion(world, worker.id, principal) < 20 and world.rng.randf() < 0.30:
			if principal == world.player:
				world.event("%s 因忠诚过低，带走了受托舰船。" % worker.name)
			vessel.erase("firm")
			vessel.owner = worker.id
			vessel.flag = world.NEUTRAL
			worker.flag = world.NEUTRAL
			worker.employer = 0
			Economy.clear_assignments(world,vessel)

static func refresh_station_residents(world) -> void:
	var alive_count := 0
	var idle_by_port := {}
	for p in world.people.values():
		if not p.alive:
			continue
		alive_count += 1
		if p.id != world.player and p.loc != 0 and p.ship == 0 and p.employer == 0:
			idle_by_port[p.loc] = int(idle_by_port.get(p.loc, 0)) + 1
	if alive_count >= 240:
		return
	for station in world.ports.values():
		if alive_count >= 240:
			break
		if station.build > 0 or station.get("landing_only", false):
			continue
		if int(idle_by_port.get(station.id, 0)) >= 2 or world.rng.randf() > 0.45:
			continue
		var newcomer_id: int = world.random_person(station.flag, station.id)
		var newcomer: Dictionary = world.people[newcomer_id]
		var is_wild_noble: bool = world.rng.randf() < (0.35 if station.pop >= 45 else 0.18)
		newcomer.noble = is_wild_noble
		newcomer.wallet = world.rng.randi_range(180, 420) if is_wild_noble else world.rng.randi_range(90, 260)
		alive_count += 1

static func npc_archetype(actor: Dictionary) -> String:
	var traits: Array = actor.get("ck_traits", [])
	if "勇敢" in traits or "狂热" in traits or "强壮" in traits:
		return "mercenary"
	if "狡诈" in traits or "愤世" in traits:
		return "schemer"
	return "merchant"

static func npc_buy_ship(world, actor: Dictionary, station: Dictionary, kind: int, role_override: String = "") -> int:
	var sid := Economy.purchase_ship(world,actor.get("id",0),station.get("id",0),kind,true)
	if sid == 0:
		return 0
	var vessel: Dictionary = world.ships[sid]
	var duty := role_override if not role_override.is_empty() else ("自动采矿" if Economy.Hulls.MODELS[kind].mine >= 20 else "自动贸易")
	if duty == "巡逻":
		vessel.job = {"kind": "巡逻", "source": station.id, "system": station.system}
	else:
		vessel.job = {"kind": duty.trim_prefix("自动"), "automatic": true, "label": duty, "phase": 0}
	vessel.default_behavior = vessel.job.duplicate(true)
	return sid

static func earning_capacity(model: Dictionary, role: String) -> float:
	match role:
		"巡逻": return float(model.power) * sqrt(float(model.hp))
		"采矿": return minf(model.mine*4,model.cargo) * float(model.speed)
	return float(model.cargo) * float(model.speed)

static func choose_work_ship(actor: Dictionary, port: Dictionary, current: Dictionary, role: String) -> int:
	var best := -1
	var best_value := 0.0
	var present := 0.0 if current.is_empty() else earning_capacity(Hulls.MODELS[current.kind],role)
	for kind in port.hulls.size():
		if port.hulls[kind] <= 0 or not Hulls.model_limit(port,kind):
			continue
		var model: Dictionary = Hulls.MODELS[kind]
		var duty := role if not role.is_empty() else ("采矿" if model.mine >= 20 else "贸易")
		var gain := earning_capacity(model,duty) - present
		var price: int = Economy.ship_quote(port,kind).price
		var reserve := 40 + (mini(24,model.cargo)*Economy.price(port,Economy.Industry.Ware.RATIONS,true) if duty == "贸易" else 0)
		if gain <= present*0.15 or price <= 0 or price+reserve > actor.wallet:
			continue
		var value := gain / price
		if value > best_value:
			best_value = value
			best = kind
	return best

static func npc_social_step(world, actor: Dictionary, arch: String) -> void:
	if int(actor.get("stress", 0)) >= 100:
		if actor.wallet >= 40 and world.rng.randf() < 0.65:
			world.credit(actor.id, -40)
			Society.stress(world, actor, -65)
			Society.apply_trait_mod(actor, "挥霍")
		else:
			Society.stress(world, actor, -45)
			Society.apply_trait_mod(actor, "隐士")
	if actor.loc == 0 or not world.ports.has(actor.loc):
		return
	var traits: Array = actor.get("ck_traits", [])
	if arch == "schemer" and world.rng.randf() < 0.18:
		for other in world.people.values():
			if other.id != actor.id and other.id != world.player and other.alive and other.loc == actor.loc and not other.get("secrets", []).is_empty():
				var secret: Dictionary = other.secrets.pop_front()
				if not actor.has("hooks"):
					actor.hooks = {}
				actor.hooks[other.id] = {"kind": secret.get("kind", "secret"), "strength": 1, "expires": world.day + 720}
				break
	elif ("慷慨" in traits or "仁慈" in traits) and actor.wallet >= 140 and world.rng.randf() < 0.15:
		var recipient := {}
		for other in world.people.values():
			if other.alive and other.loc == actor.loc and age(world,other) >= 18 and other.wallet+20 < actor.wallet and (recipient.is_empty() or other.wallet < recipient.wallet):
				recipient = other
		if not recipient.is_empty():
			world.credit(actor.id, -20)
			world.credit(recipient.id, 20)
			recipient.opinions[actor.id] = mini(100,int(recipient.opinions.get(actor.id,0))+15)
			if recipient.id != world.player and opinion(world,recipient.id,actor.id) >= 60 and not actor.get("relations",{}).has(recipient.id):
				Society.set_relation(actor,recipient.id,"friend")
				Society.set_relation(recipient,actor.id,"friend")

static func _npc_pioneer_station(world, actor: Dictionary) -> bool:
	var terms: Dictionary = Economy.Industry.CONSTRUCTION.foundation
	var total_cost: int = int(terms.credits) + 1500
	if int(actor.get("wallet", 0)) < total_cost:
		return false
	var owned_count := 0
	for st in world.ports.values():
		if int(st.get("owner", 0)) == int(actor.id):
			if int(st.get("build", 0)) > 0:
				return false
			owned_count += 1
	if owned_count >= 2:
		return false
	var ship: Dictionary = world.ships.get(int(actor.get("ship", 0)), {})
	var origin_sys: int = int(ship.get("system", 0)) if not ship.is_empty() else 0
	var sys_candidates: Array[int] = []
	for s_id in range(world.systems.size()):
		var reg: Dictionary = world.systems[s_id]
		if reg.planets.is_empty():
			continue
		var orbital_cnt: int = reg.ports.filter(func(pid): return not world.ports[pid].has("planet_index")).size()
		if orbital_cnt < int(Economy.Industry.CONSTRUCTION.max_sites):
			sys_candidates.append(s_id)
	if sys_candidates.is_empty():
		return false
	sys_candidates.sort_custom(func(a, b):
		var ap: int = world.systems[a].ports.size()
		var bp: int = world.systems[b].ports.size()
		if ap != bp:
			return ap < bp
		return world.distance(origin_sys, a) < world.distance(origin_sys, b))
	var mod_kind: int = world.rng.randi_range(0, world.MODULES.size() - 1)
	for s_id in sys_candidates.slice(0, mini(4, sys_candidates.size())):
		var reg: Dictionary = world.systems[s_id]
		for p_idx in range(reg.planets.size()):
			var planet: Dictionary = reg.planets[p_idx]
			var orbit_r: float = minf(float(Economy.Celestial.gravity_radius(reg, planet)) * 0.62, float(planet.get("radius", 30.0)) + float(Economy.Industry.CONSTRUCTION.minimum_altitude) + 70.0)
			for angle_step in range(6):
				var ang: float = float(angle_step) * TAU / 6.0 + world.rng.randf_range(0.0, 0.4)
				var pos: Vector2 = Vector2(planet.pos) + Vector2.from_angle(ang) * orbit_r
				if Economy.Celestial.orbit_at(reg, pos) != p_idx:
					continue
				var heading: float = pos.angle_to_point(planet.pos)
				var probe := {"pos": pos, "berth_heading": heading, "module": mod_kind, "build": int(terms.days), "modules": [], "system": s_id, "id": world.next_id}
				var planned: Array = Economy.StationDesign.cells(probe)
				if not Economy.design_issue(world, probe, planned).is_empty():
					continue
				var pid: int = world.port(s_id, "%s · %s站 %s" % [actor.house, world.MODULES[mod_kind], world.next_id], pos, int(actor.flag), int(actor.id), mod_kind, false)
				var site: Dictionary = world.ports[pid]
				site.orbit = p_idx
				site.berth_heading = heading
				site.design_cells = planned
				site.scan = true
				site.build = int(terms.days)
				var inv := Economy.Industry.station_data(site)
				for ware in Economy.Industry.FOUNDATION:
					inv.deliver_construction(ware, int(Economy.Industry.FOUNDATION[ware]), Economy.Industry.FOUNDATION)
				world.credit(int(actor.id), -total_cost, site, "自主拓荒建站")
				world.event("【自主拓荒】%s 出资在 %s 动工兴建 %s。" % [actor.name, reg.name, site.name])
				return true
	return false

## Personality-weighted dice roll for autonomous NPC decisions.
static func _npc_roll(world, actor: Dictionary, base_prob: float, decision_kind: String) -> bool:
	var traits: Array = actor.get("ck_traits", [])
	var w := 1.0
	match decision_kind:
		"incorporate":
			if "贪婪" in traits: w *= 1.45
			if "勤勉" in traits: w *= 1.30
			if "狡诈" in traits: w *= 1.20
			if "懒惰" in traits: w *= 0.55
			if "隐士" in traits: w *= 0.50
			if "挥霍" in traits: w *= 0.75
			if actor.get("stats") != null and int(actor.stats.stewardship) >= 10: w *= 1.20
		"pioneer":
			if "勇敢" in traits: w *= 1.40
			if "勤勉" in traits: w *= 1.35
			if "贪婪" in traits: w *= 1.25
			if "狂热" in traits: w *= 1.20
			if "怯懦" in traits: w *= 0.45
			if "懒惰" in traits: w *= 0.50
			if "隐士" in traits: w *= 0.60
		"found_faction":
			if "勇敢" in traits: w *= 1.45
			if "狂热" in traits: w *= 1.35
			if "魅力非凡" in traits: w *= 1.30
			if "残忍" in traits: w *= 1.20
			if "怯懦" in traits: w *= 0.35
			if "隐士" in traits: w *= 0.40
			if "懒惰" in traits: w *= 0.55
			if "诚实" in traits: w *= 0.80
		"company_war":
			if "贪婪" in traits: w *= 1.40
			if "狡诈" in traits: w *= 1.45
			if "残忍" in traits: w *= 1.30
			if "勇敢" in traits: w *= 1.20
			if "仁慈" in traits: w *= 0.40
			if "诚实" in traits: w *= 0.50
			if "怯懦" in traits: w *= 0.45
			if "隐士" in traits: w *= 0.50
	var prob := clampf(base_prob * w, 0.03, 0.95)
	return world.rng.randf() < prob

static func _npc_enterprise_and_realm_step(world, actor: Dictionary) -> void:
	var aid := int(actor.id)
	var owned_ready: Array[Dictionary] = []
	for st in world.ports.values():
		if int(st.get("owner", 0)) == aid and int(st.get("build", 0)) == 0:
			owned_ready.append(st)
	var directed_firm := 0
	for fid in world.firms:
		if int(world.firms[fid].get("director", 0)) == aid:
			directed_firm = int(fid)
			break
	for st in owned_ready:
		if int(st.get("firm", 0)) == 0:
			if directed_firm == 0 and int(actor.get("wallet", 0)) >= 2200 and _npc_roll(world, actor, 0.45, "incorporate"):
				if Economy.incorporate(world, int(st.id), "%s工业" % actor.name, aid):
					for fid in world.firms:
						if int(world.firms[fid].get("director", 0)) == aid:
							directed_firm = int(fid)
							break
			elif directed_firm != 0:
				world.Equity.affiliate(world, int(st.id), directed_firm)
	if int(actor.get("flag", world.NEUTRAL)) == world.NEUTRAL and not owned_ready.is_empty() and int(actor.get("wallet", 0)) >= 10000 and _npc_roll(world, actor, 0.20, "found_faction"):
		found(world, "%s领" % actor.house, int(owned_ready[0].id), aid % world.REGIMES.size(), aid)
	if int(actor.get("ship", 0)) != 0 and int(actor.get("wallet", 0)) >= 8000 and _npc_roll(world, actor, 0.25, "pioneer"):
		_npc_pioneer_station(world, actor)

static func npc_autonomous_step(world) -> void:
	var slot: int = world.day % 30
	var leader_ids := {}
	for group in world.factions.values():
		if group.alive and group.leader != 0:
			leader_ids[group.leader] = true
	for person_id in world.people.keys():
		if person_id % 30 != slot or person_id == world.player or person_id == world.regency:
			continue
		var actor: Dictionary = world.people[person_id]
		if not actor.alive or age(world,actor) < 18:
			continue
		if actor.spouse == 0 and actor.loc > 0 and world.rng.randf() < 0.25:
			var married := false
			for other: Dictionary in world.people.values():
				if other.id != world.player and other.id != world.regency and other.id != person_id and other.loc == actor.loc and other.spouse == 0 and other.gender != actor.gender and marry(world,person_id,other.id):
					married = true
					break
			if married:
				continue
		if world.reports_to(actor) != 0 or leader_ids.has(person_id):
			continue
		var arch := npc_archetype(actor)
		npc_social_step(world, actor, arch)
		_npc_enterprise_and_realm_step(world, actor)
		if actor.ship == 0:
			if actor.loc == 0 or not world.ports.has(actor.loc):
				continue
			var station: Dictionary = world.ports[actor.loc]
			if station.build == 0 and actor.wallet > 40 and Economy.Industry.Module.YARD in station.modules:
				var role_pref := "巡逻" if arch == "mercenary" else ""
				var kind := choose_work_ship(actor,station,{},role_pref)
				if kind >= 0 and npc_buy_ship(world,actor,station,kind,role_pref) > 0:
					world.event("%s 在 %s 购入%s，启程谋生。" % [actor.name,station.name,world.HULLS[kind]])
					continue
			if world.rng.randf() < 0.14:
				var ports: Array = world.ports.values()
				var dest: Dictionary = ports[world.rng.randi_range(0, ports.size() - 1)]
				if dest.build == 0 and not world.hostile(actor.flag, dest.flag):
					actor.loc = dest.id
		else:
			var vessel: Dictionary = world.ships.get(actor.ship, {})
			if vessel.is_empty():
				actor.ship = 0
				continue
			if arch == "mercenary" and vessel.job.get("kind", "") == "巡逻" and vessel.dock == 0 and world.rng.randf() < 0.25:
				world.credit(actor.id, world.rng.randi_range(18, 42))
			if vessel.owner == actor.id and vessel.dock != 0 and world.ports.has(vessel.dock) and not vessel.has("reservation") and vessel.cargo.all(func(q): return q == 0):
				var dock_st: Dictionary = world.ports[vessel.dock]
				if Economy.Industry.Module.YARD in dock_st.modules:
					var role: String = vessel.job.get("kind","贸易")
					if role not in ["贸易","采矿","巡逻"]:
						continue
					var upgrade_kind := choose_work_ship(actor,dock_st,vessel,role)
					if upgrade_kind >= 0:
						var old_ship_id: int = vessel.id
						var new_ship_id := npc_buy_ship(world,actor,dock_st,upgrade_kind,role)
						if new_ship_id > 0:
							var hired_wing := 0
							if actor.wallet >= 95 + mini(24,Hulls.MODELS[upgrade_kind].cargo)*Economy.price(dock_st,Economy.Industry.Ware.RATIONS,true):
								for idle in world.people.values():
									if idle.id != actor.id and idle.id != world.player and idle.alive and idle.loc == dock_st.id and idle.ship == 0 and idle.employer == 0 and age(world, idle) >= 18:
										world.credit(actor.id, -55)
										world.credit(idle.id, 55)
										idle.employer = actor.id
										idle.ship = old_ship_id
										idle.loc = dock_st.id
										world.ships[old_ship_id].captain = idle.id
										world.ships[old_ship_id].job = {"kind": "贸易", "automatic": true, "label": "自动贸易", "phase": 0}
										world.ships[old_ship_id].default_behavior = world.ships[old_ship_id].job.duplicate(true)
										hired_wing = idle.id
										break
							if hired_wing == 0:
								world.ships[old_ship_id].captain = 0
								world.ships[old_ship_id].job = {"kind": "停泊待命", "source": dock_st.id, "system": dock_st.system}
							world.event("%s 换乘更适合%s的%s。" % [actor.name,role,world.HULLS[upgrade_kind]])

## Allow wealthy, peaceful NPC factions to colonize nearby undeveloped planets or empty systems.
static func npc_colonize(world) -> void:
	var max_ports: int = world.systems.size() * 2 + 12
	var built_ports := 0
	for st in world.ports.values():
		if not st.get("landing_only", false):
			built_ports += 1
	if built_ports >= max_ports:
		return
	for flag in world.factions:
		var group: Dictionary = world.factions[flag]
		if not group.alive or not group.get("npc", false) or int(group.get("treasury", 0)) < 18000:
			continue
		if world.day - int(group.get("last_colonized", -240)) < 240:
			continue
		if not WarPeace.active_wars(world, int(flag)).is_empty():
			continue
		var cap: Dictionary = world.ports.get(int(group.get("capital", 0)), {})
		if cap.is_empty():
			continue
		var best_sys := -1
		var best_p_idx := -1
		var best_landing: Dictionary = {}
		var best_dist := 5000.0
		for s_idx in range(world.systems.size()):
			var region: Dictionary = world.systems[s_idx]
			var sys_owner: int = world.sovereign(s_idx)
			if sys_owner != world.NEUTRAL and sys_owner != int(flag):
				continue
			var d: float = world.distance(int(cap.system), s_idx)
			if d >= best_dist:
				continue
			var planets: Array = region.get("planets", [])
			for p_idx in range(planets.size()):
				var planet: Dictionary = planets[p_idx]
				var existing_pid := int(planet.get("port_id", 0))
				if existing_pid == 0:
					best_dist = d
					best_sys = s_idx
					best_p_idx = p_idx
					best_landing = {}
					break
				var st: Dictionary = world.ports.get(existing_pid, {})
				if st.get("landing_only", false):
					best_dist = d
					best_sys = s_idx
					best_p_idx = p_idx
					best_landing = st
					break
		var mod_kind: int = world.rng.randi_range(0, 2)
		if best_sys >= 0:
			var region: Dictionary = world.systems[best_sys]
			var planet: Dictionary = region.planets[best_p_idx]
			planet.surveyed = true
			var owner_id: int = int(group.leader) if int(group.regime) == 0 else 0
			var col_name := "%s · %s港" % [planet.name, Economy.Industry.MODULES[mod_kind]]
			if not best_landing.is_empty():
				best_landing.landing_only = false
				best_landing.surface_profile = "colony"
				best_landing.name = col_name
				best_landing.flag = int(flag)
				best_landing.owner = owner_id
				best_landing.module = mod_kind
				best_landing.build = 0
				best_landing.since = world.day
				best_landing.pop = 85
				best_landing.pop_cap = 220
				best_landing.defense = 22
				Economy.initialize_station(world, best_landing, true)
				world.PlanetPorts.configure_harvest(best_landing, planet)
				best_landing.treasury = 4800
				world.refresh_tariffs(best_sys)
				world.Equity.update_operator(world, best_landing)
			else:
				var pid: int = world.port(best_sys, col_name, world.PlanetPorts.point(planet), int(flag), owner_id, mod_kind, true)
				world.ports[pid].planet_index = best_p_idx
				world.ports[pid].surface_profile = "colony"
				world.ports[pid].landing_only = false
				world.ports[pid].treasury = 4800
				world.ports[pid].berth_heading = world.PlanetPorts.outward(planet).angle()
				planet.port_id = pid
				world.PlanetPorts.configure_harvest(world.ports[pid], planet)
				world.refresh_tariffs(best_sys)
			group.treasury -= 12000
			group.last_colonized = world.day
			world.event("【殖民扩张】%s 耗资 ¢12000 在 %s 建立了新殖民站：%s。" % [group.name, region.name, col_name])
			appointments(world)
			continue
		var empty_sys := -1
		best_dist = 1800.0
		for s_idx in range(world.systems.size()):
			var reg: Dictionary = world.systems[s_idx]
			if not reg.ports.is_empty() or reg.has("outlaw_base"):
				continue
			var d: float = world.distance(int(cap.system), s_idx)
			if d < best_dist:
				best_dist = d
				empty_sys = s_idx
		if empty_sys >= 0:
			var reg: Dictionary = world.systems[empty_sys]
			var owner_id: int = int(group.leader) if int(group.regime) == 0 else 0
			var pos := Vector2(reg.get("field", Vector2(180, -140))) * 0.65
			var pid: int = world.port(empty_sys, "%s 前哨站" % reg.name, pos, int(flag), owner_id, mod_kind, true)
			world.ports[pid].treasury = 4800
			world.refresh_tariffs(empty_sys)
			group.treasury -= 12000
			group.last_colonized = world.day
			world.event("【殖民扩张】%s 耗资 ¢12000 在 %s 建立了新前哨站：%s。" % [group.name, reg.name, world.ports[pid].name])
			appointments(world)
			continue

static func advance(world) -> void:
	for person_id in world.people.keys():
		var actor: Dictionary = world.people[person_id]
		if not actor.alive:
			continue
		if world.day - actor.birth >= actor.lifespan and not world.ships.get(actor.ship, {}).get("locked", false):
			die(world, person_id)
			if world.succession or world.attention:
				return
		if actor.spouse > person_id and actor.children.size() < 4 and world.day - actor.last_child > 720:
			var partner: Dictionary = world.people[actor.spouse]
			var actor_limit := 48 if int(actor.get("gender", 0)) == 1 else 65
			var partner_limit := 48 if int(partner.get("gender", 0)) == 1 else 65
			if partner.alive and age(world, actor) < actor_limit and age(world, partner) < partner_limit and world.rng.randf() < 0.13:
				child(world, person_id, partner.id)
				if world.attention:
					return
		if world.day % 360 == 0 and actor.noble and person_id != world.player and actor.spouse == 0 and age(world, actor) >= 18 and age(world, actor) < 48 and world.rng.randf() < 0.48:
			for partner in world.people.values():
				if partner.id != world.player and partner.noble and partner.alive and partner.spouse == 0 and int(partner.get("gender", 0)) != int(actor.get("gender", 0)) and age(world, partner) < 48 and (actor.flag == partner.flag or world.rng.randf() < 0.15):
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
		Society.offer(world, "on_succession")
		return
	if world.day % 45 == 0:
		npc_colonize(world)
	if world.day % 90 == 0:
		appointments(world)
		settle_captain_payroll(world)
		refresh_station_residents(world)
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
