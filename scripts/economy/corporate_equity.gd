extends RefCounted

const Rules = preload("res://data/economy/industry.json")
static var CORPORATE_REGIMES := PackedInt32Array(Rules.data.equity.corporate_regimes)

static func corporate(regime: int) -> bool:
	return regime in CORPORATE_REGIMES

static func company(world, group: Dictionary) -> int:
	if not corporate(group.get("regime",-1)):
		return 0
	return int(group.get("firm",world.ports.get(group.get("capital",0),{}).get("firm",0)))

static func establish(world, flag: int) -> int:
	var group: Dictionary = world.factions[flag]
	if not corporate(group.regime) or not group.alive or not world.ports.has(group.capital):
		return 0
	if world.firms.has(group.get("firm",0)):
		return group.firm
	var seat: Dictionary = world.ports[group.capital]
	var id: int = world.incorporate(group.name+"控股",group.leader,seat.id,false)
	if id==0:
		return 0
	group.firm = id
	world.firms[id].flag = flag
	var holders := []
	for site: Dictionary in world.ports.values():
		if site.flag == flag:
			update_operator(world,site)
			if site.manager != 0 and site.manager != group.leader and site.manager not in holders:
				holders.append(site.manager)
	for i in mini(holders.size(),Rules.data.equity.founding_partners):
		var amount := int(world.firms[id].issued)*int(Rules.data.equity.partner_percent)/100
		world.people[group.leader].shares[id] -= amount
		world.people[holders[i]].shares[id] = amount
	return id

## Public facilities change operator with sovereignty. Independent operators retain their contracts.
static func update_operator(world, site: Dictionary) -> void:
	var current: Dictionary = world.firms.get(site.firm,{})
	if site.firm != 0 and current.get("flag",world.NEUTRAL) == world.NEUTRAL:
		return
	var group: Dictionary = world.factions.get(site.flag,{})
	var target: int = group.get("firm",0) if corporate(group.get("regime",-1)) and site.owner in [0,group.get("leader",0)] and not site.get("landing_only",false) else 0
	if site.firm != target:
		world.StationEquity.set_operator(world,site,target)

static func affiliate(world, station_id: int, firm_id: int) -> bool:
	var site: Dictionary = world.ports.get(station_id,{})
	var firm: Dictionary = world.firms.get(firm_id,{})
	if site.is_empty() or firm.is_empty() or site.firm != 0 or site.build > 0 or site.owner != world.player or firm.director != world.player:
		return false
	world.StationEquity.set_operator(world,site,firm_id)
	return true

static func adult(world, person: Dictionary) -> bool:
	return person.get("alive",false) and world.day-int(person.birth) >= 18*360

static func supporters(world, firm_id: int) -> Dictionary:
	var votes := {}
	var ballots: Dictionary = world.firms[firm_id].get("ballots",{})
	for person: Dictionary in world.people.values():
		var units: int = person.shares.get(firm_id,0)
		if units <= 0 or not adult(world,person):
			continue
		var candidate: Dictionary = world.people.get(ballots.get(person.id,person.id),{})
		if not adult(world,candidate) or candidate.shares.get(firm_id,0) <= 0:
			candidate = person
		votes[candidate.id] = int(votes.get(candidate.id,0))+units
	return votes

static func elected(world, firm_id: int) -> int:
	var votes := supporters(world,firm_id)
	if votes.is_empty():
		return 0
	var winner: int = world.firms[firm_id].director
	for id: int in votes:
		if votes[id] > int(votes.get(winner,0)):
			winner = id
	return winner

static func vote(world, firm_id: int, candidate_id: int) -> bool:
	var firm: Dictionary = world.firms.get(firm_id,{})
	var candidate: Dictionary = world.people.get(candidate_id,{})
	if firm.is_empty() or not adult(world,world.active()) or not adult(world,candidate) or world.active().shares.get(firm_id,0)<=0 or candidate.shares.get(firm_id,0)<=0:
		return false
	firm.ballots[world.player] = candidate_id
	world.Politics.board(world,firm_id)
	return true

static func overview(world, firm_id: int) -> Dictionary:
	var firm: Dictionary = world.firms.get(firm_id,{})
	if firm.is_empty():
		return {}
	var holdings := []
	var sites := []
	var reserved: int = world.EquityOrders.escrow_for(world,-firm_id)
	var value: int = firm.get("treasury",0) + reserved + int(firm.get("deal_receivable",0))
	var market_value: int = value
	var fleet := []
	for ship: Dictionary in world.ships.values():
		if ship.get("firm",0) == firm_id:
			fleet.append(ship.id)
			value += int(world.Hulls.MODELS[ship.kind].price)
			market_value += int(world.Hulls.MODELS[ship.kind].price)
	for site: Dictionary in world.ports.values():
		if site.firm == firm_id:
			sites.append(site.id)
		var table: Dictionary = world.StationEquity.cap_table(world,site)
		if table.company == firm_id and table.company_units > 0:
			holdings.append({"port":site.id,"units":table.company_units})
			var outstanding: int = table.total-int(table.get("treasury_units",0))
			value += int(table.company_units)*int(world.StationEquity.net_assets(site))/maxi(1,outstanding)
			market_value += int(table.company_units)*int(world.StationEquity.valuation(site))/maxi(1,outstanding)
	var pe := int(Rules.data.equity.get("pe_multiple",15))
	var floor_pct := int(Rules.data.equity.get("min_pb_percent",50))
	market_value = maxi(value * floor_pct / 100, market_value + int(firm.get("operating_profit",0)) * pe)
	var holders := []
	var votes := supporters(world,firm_id)
	for person: Dictionary in world.people.values():
		var units: int = person.shares.get(firm_id,0)
		if person.alive and units>0:
			holders.append({"person":person.id,"shares":units,"votes":votes.get(person.id,0),"supports":firm.ballots.get(person.id,person.id)})
	var issued: int = firm.issued
	return {"id":firm_id,"name":firm.name,"flag":firm.flag,"hq":firm.hq,"director":firm.director,"ports":sites,"ships":fleet,"holdings":holdings,
		"holders":holders,"issued":issued,"net_assets":value,"owned":world.active().shares.get(firm_id,0),"unit_price":maxi(1,ceili(float(market_value)/maxi(1,issued-int(firm.treasury_shares) if issued>firm.treasury_shares else issued))),
		"treasury":firm.get("treasury",0),"reserved_cash":reserved,"operating_profit":firm.get("operating_profit",0),"treasury_shares":firm.treasury_shares}

static func at_market(world) -> bool:
	var visitor: Dictionary = world.active()
	if not adult(world,visitor):
		return false
	var ship: Dictionary = world.ride()
	var port: Dictionary = world.ports.get(visitor.loc if ship.is_empty() else ship.dock,{})
	if port.is_empty() or port.build > 0:
		return false
	if ship.is_empty():
		return world.Economy.market_open(world,visitor,port) and not world.enemy(visitor,port)
	return world.Economy.allowed(world,ship,port)

static func participants(world, firm_id: int) -> Dictionary:
	var firm: Dictionary = world.firms.get(firm_id,{})
	if firm.is_empty():
		return {}
	var result := {}
	for person: Dictionary in world.people.values():
		var units: int = person.shares.get(firm_id,0)
		if units > 0 and adult(world,person):
			result[person.id] = {"units":units,"controller":units*2>int(firm.issued)-int(firm.treasury_shares),
				"interest":true,"representative":person.id}
	for site: Dictionary in world.ports.values():
		if site.firm==firm_id and site.manager>0 and adult(world,world.people[site.manager]):
			result.get_or_add(site.manager,{"units":0,"controller":false,"interest":true,"representative":site.manager})
	if firm.treasury_shares>0:
		result[0] = {"units":firm.treasury_shares,"controller":false,"interest":false,"representative":firm.director,"name":"%s库存股" % firm.name}
	return result

static func offers(world, firm_id: int, buying: bool) -> Array:
	var result := []
	if not at_market(world) or not world.firms.has(firm_id):
		return result
	world.EquityOrders.publish(world,"company",firm_id,overview(world,firm_id).unit_price,participants(world,firm_id))
	var actor: Dictionary = world.active()
	for row: Dictionary in world.EquityOrders.quotes(world,"company",firm_id,buying):
		var available: int = int(actor.wallet)/int(row.unit_price) if buying else int(actor.shares.get(firm_id,0))-world.DiplomaticTrade.reserved_shares(world,"company",firm_id,actor.id)
		row.quantity = mini(row.quantity,available)
		if row.quantity > 0:
			result.append(row)
	return result

static func trade(world, firm_id: int, counterparty: int, quantity: int, buying: bool, expected_unit_price: int, order_id: int = 0, listing_id: int = 0) -> bool:
	var firm: Dictionary = world.firms.get(firm_id,{})
	var actor: Dictionary = world.active()
	if firm.is_empty() or quantity<=0 or (counterparty==0 and not buying):
		return false
	var seller_units: int = firm.treasury_shares if counterparty==0 else world.people.get(counterparty,{}).get("shares",{}).get(firm_id,0)
	if quantity>(seller_units if buying else int(actor.shares.get(firm_id,0))):
		return false
	if not world.EquityOrders.fill(world,"company",firm_id,counterparty,quantity,buying,expected_unit_price,order_id,listing_id):
		return false
	var delta := quantity if buying else -quantity
	world.StationEquity.add_units(actor.shares,firm_id,delta)
	world.StockPrices.record(world,"company",firm_id,quantity,quantity*expected_unit_price)
	if counterparty==0:
		firm.treasury_shares-=delta
	else:
		world.StationEquity.add_units(world.people[counterparty].shares,firm_id,-delta)
	if listing_id!=0:
		world.ShareExchange.settled(world,listing_id,counterparty,quantity,expected_unit_price)
	world.Politics.board(world,firm_id)
	world.EquityOrders.audit(world,"company",firm_id)
	return true

static func valid(data: Dictionary) -> bool:
	var totals := {}
	for id in data.firms:
		var firm: Variant = data.firms[id]
		if not firm is Dictionary or not firm.get("issued") is int or firm.issued<=0 or firm.issued>2147483647 or not firm.get("treasury_shares") is int or firm.treasury_shares < 0:
			return false
		if not firm.get("treasury") is int or firm.treasury < 0 or not firm.get("operating_profit") is int:
			return false
		if not firm.get("flag") is int or (firm.flag >= 0 and not data.factions.has(firm.flag)):
			return false
		if firm.has("last_dividend_day") and (not firm.last_dividend_day is int or firm.last_dividend_day < 0 or firm.last_dividend_day > data.day):
			return false
		if firm.has("dividend_policy"):
			var policy: Variant = firm.dividend_policy
			if not policy is Dictionary or not policy.get("percent") is int or policy.percent < 0 or policy.percent > 100 or not policy.get("reserve") is int or policy.reserve < 0:
				return false
		if not firm.get("ballots") is Dictionary or not data.ports.has(firm.get("hq",0)) or not data.people.has(firm.get("director",0)):
			return false
		for holder in firm.ballots:
			if not data.people.has(holder) or not data.people.has(firm.ballots[holder]):
				return false
		totals[id] = firm.treasury_shares
	for person in data.people.values():
		if not person is Dictionary or not person.get("shares") is Dictionary:
			return false
		for id in person.shares:
			var units: Variant = person.shares[id]
			if not totals.has(id) or not units is int or units < 0 or (units > 0 and not person.alive):
				return false
			totals[id] += units
	for flag in data.factions:
		var f_shares: Variant = data.factions[flag].get("shares",{})
		if not f_shares is Dictionary:
			return false
		for id in f_shares:
			var units: Variant = f_shares[id]
			if not totals.has(id) or not units is int or units < 0:
				return false
			totals[id] += units
	for id in totals:
		if totals[id] != data.firms[id].issued:
			return false
	for flag in data.factions:
		var group: Dictionary = data.factions[flag]
		if group.has("firm") and data.firms.get(group.firm,{}).get("flag",-1) != flag:
			return false
	return true
