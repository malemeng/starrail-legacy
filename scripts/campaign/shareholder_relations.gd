extends RefCounted

const Rules = preload("res://data/campaign/sector.json")

## A contact may speak for their private portfolio and an institution in the same market.
static func profile(world, person_id: int) -> Dictionary:
	var person: Dictionary = world.people.get(person_id,{})
	if person.is_empty():
		return {}
	var roles := PackedStringArray()
	var interests := []
	for group: Dictionary in world.factions.values():
		if group.alive and group.leader == person_id:
			roles.append(group.name + "领袖")
	for key: int in world.firms:
		var firm: Dictionary = world.firms[key]
		if firm.director == person_id:
			roles.append(firm.name + "董事长")
		append_contacts(world,interests,person_id,"company",key,firm.name)
	for station: Dictionary in world.ports.values():
		if not world.StationEquity.listed(world,station):
			continue
		if station.manager == person_id:
			roles.append(station.name + "站长")
		append_contacts(world,interests,person_id,"station",station.id,station.name)
	for ship: Dictionary in world.ships.values():
		if ship.captain == person_id and (person_id == world.player or world.oversees(world.ship_principal(ship)) or person.loc == world.active().loc and person.loc > 0):
			roles.append("#%d %s船长" % [ship.id,world.HULLS[ship.kind]])
	return {"id":person_id,"name":person.name,"house":person.house if person.noble else "",
		"alive":person.alive,"trait":world.TRAITS[person.trait],"faction":world.flag_name(person.flag),
		"opinion":world.Politics.opinion(world,person_id,world.player),"roles":roles,"interests":interests}

static func append_contacts(world, rows: Array, person_id: int, kind: String, id: int, name: String) -> void:
	var parties: Dictionary = world.EquityOrders.participants(world,kind,id)
	for party: int in parties:
		var entry: Dictionary = parties[party]
		if entry.representative != person_id:
			continue
		var authorized: bool = not world.EquityOrders.controlled(world,entry,kind,id,party)
		if entry.units <= 0 and (not authorized or not entry.interest):
			continue
		var account: Dictionary = world.EquityOrders.account(world,kind,id,party)
		rows.append({"kind":kind,"id":id,"name":name,"counterparty":party,"account":entry.get("name",account.name),
			"units":entry.units,"can_negotiate":authorized})

## The shareholder keeps the shares, their dividends, and the right to cast a later ballot.
static func request_support(world, firm_id: int, voter_id: int) -> Dictionary:
	var voter: Dictionary = world.people.get(voter_id,{})
	var firm: Dictionary = world.firms.get(firm_id,{})
	var actor: Dictionary = world.active()
	var response := {"accepted":false,"decider":voter_id,"votes":0,"reason":""}
	if firm.is_empty() or not world.Equity.at_market(world):
		response.reason = "请在营业港联络董事会。"
	elif not world.Equity.adult(world,actor) or actor.shares.get(firm_id,0) <= 0:
		response.reason = "你需要先成为这家公司的成年股东，才能竞选董事长。"
	elif not world.Equity.adult(world,voter) or voter.shares.get(firm_id,0) <= 0 or world.oversees(voter_id):
		response.reason = "请选择一位可以独立投票的成年股东。"
	else:
		return weigh_support(world,firm_id,voter)
	return response

static func weigh_support(world, firm_id: int, voter: Dictionary) -> Dictionary:
	var firm: Dictionary = world.firms[firm_id]
	var actor: Dictionary = world.active()
	var incumbent: int = firm.ballots.get(voter.id,voter.id)
	var prior: Dictionary = world.people.get(incumbent,{})
	if not world.Equity.adult(world,prior) or prior.shares.get(firm_id,0) <= 0:
		incumbent = voter.id
	var answer := {"accepted":false,"decider":voter.id,"votes":int(voter.shares[firm_id]),"reason":""}
	if incumbent == actor.id:
		answer.accepted = true
		answer.reason = "我的 %d 票已经投给你了。" % answer.votes
		return answer
	var rules: Dictionary = Rules.data.board_canvass
	var trust: int = world.Politics.opinion(world,voter.id,actor.id)
	var threshold := int(rules.minimum_trust)
	var reason := "我对你还不够信任。"
	if incumbent == voter.id:
		threshold += roundi(voter.personality.boldness * float(rules.ambition_weight))
		if firm.director == voter.id:
			threshold += int(rules.incumbent_premium)
			reason = "我打算继续担任董事长，会把票留给自己。"
	else:
		threshold = maxi(threshold,world.Politics.opinion(world,voter.id,incumbent) + int(rules.switch_margin))
		reason = "我仍然支持%s。" % world.name_of(incumbent)
	var persuasion := roundi((actor.stats.diplomacy - voter.stats.diplomacy) * float(rules.diplomacy_weight))
	if trust + persuasion < threshold:
		answer.reason = reason
		return answer
	firm.ballots[voter.id] = actor.id
	world.Politics.board(world,firm_id)
	answer.accepted = true
	answer.reason = "我愿意把这次的 %d 票投给你，股份和股息仍归我。" % answer.votes
	return answer
