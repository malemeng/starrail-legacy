extends RefCounted

const Industry = preload("res://scripts/economy/industry.gd")
const Hulls = preload("res://hull_catalog.gd")
const TREASURY_PARTY := -2147483648

static func cap_table(world, station: Dictionary) -> Dictionary:
	if station.has("equity"):
		var copy: Dictionary = station.equity.duplicate(true)
		if not copy.has("factions"):
			copy.factions = {}
		return copy
	var company: int = station.get("firm",0)
	var owner: int = station.get("owner",0)
	var units: int = station.get("charter_units",0)
	var table := {"people":{},"company":0,"company_units":0,"factions":{},"treasury_units":0,"total":0}
	if company > 0 and world.firms.has(company):
		table.company = company
		table.company_units = units
		table.total = units
	elif world.people.has(owner):
		table.people[owner] = units
		table.total = units
	return table

static func freeze(world, station: Dictionary) -> void:
	if not station.has("equity"):
		var table := cap_table(world,station)
		if table.total>0:
			station.equity=table

## Transfer the former proprietor's stake in this site only. Other investors retain their units.
static func settle_capture(world, site: Dictionary, previous_flag: int, flag: int, person: int, former_company: int) -> void:
	var table := cap_table(world,site)
	var former_owner := int(site.owner)
	var units := int(table.people.get(former_owner,0)) + int(table.factions.get(previous_flag,0))
	table.people.erase(former_owner)
	table.factions.erase(previous_flag)
	if int(table.company) == former_company:
		units += int(table.company_units)
		table.company_units = 0
		table.company = 0
	if table.total == 0:
		units = int(site.get("charter_units",0))
		table.total = units
	if units > 0:
		if person > 0:
			add_units(table.people,person,units)
		elif flag >= 0:
			add_units(table.factions,flag,units)
		else:
			table.treasury_units += units
	# Release share reservations and return any escrow before switching operators.
	var deal: Dictionary = world.campaign.get("diplomatic_deal",{})
	for item in deal.get("give",[]) + deal.get("want",[]):
		if item.kind == "station_share" and item.id == site.id:
			world.DiplomaticTrade.unlock(world,deal)
			break
	for order in world.campaign.get("equity_orders",{}).get("orders",{}).values():
		if order.scope == "station" and order.asset == site.id:
			world.EquityOrders.close(world,order)
	for listing in world.campaign.get("share_listings",{}).values():
		if listing.scope == "station" and listing.asset == site.id and listing.status == "open":
			listing.status = "void"
	site.erase("primary_offer")
	site.equity = table
	site.firm = 0
	if units > 0:
		world.event("%s 完成产权交割：%d 股本站股份转入%s名下。" % [site.name,units,world.name_of(person) if person else world.flag_name(flag)])

## New incorporations can contribute the founder's own station. Replacing a manager cannot transfer another party's shares.
static func set_operator(world, station: Dictionary, company: int) -> void:
	if station.firm == company:
		return
	var table := cap_table(world,station)
	if not station.has("equity") and table.total > 0:
		var founder: int = world.firms.get(company,{}).get("director",0)
		if table.company_units > 0 or not table.people.has(founder):
			station.equity = table
	station.firm = company
	if station.has("equity") and station.equity.company_units == 0:
		station.equity.company = company

## Marketable assets and installed infrastructure use the same ware and hull values as the local industry.
static func net_assets(station: Dictionary) -> int:
	var assets: int = station.treasury+int(station.get("deal_receivable",0))
	var foundation: Dictionary = Industry.CONSTRUCTION.foundation
	var structure: int = foundation.credits
	for ware in Industry.FOUNDATION:
		structure += int(Industry.FOUNDATION[ware])*int(Industry.BASE[ware])
	assets += structure * station.modules.size()
	for ware in station.stock.size():
		assets += (int(station.stock[ware])+int(station.build_storage[ware])) * int(Industry.BASE[ware])
	for kind in station.hulls.size():
		if station.hulls[kind] > 0:
			assets += int(station.hulls[kind])*int(Industry.ship_quote(station,Hulls.MODELS[kind]).price)
	return assets

static func valuation(station: Dictionary) -> int:
	var assets := net_assets(station)
	var profit := int(station.get("operating_profit",0))
	var pe := int(Industry.RULES.equity.get("pe_multiple",15))
	var floor_pct := int(Industry.RULES.equity.get("min_pb_percent",50))
	return maxi(assets * floor_pct / 100, assets + profit * pe)

static func unit_price(station: Dictionary) -> int:
	var table: Dictionary = station.get("equity",{})
	var issued: int=table.get("total",station.get("charter_units",1))
	var units: int=issued-int(table.get("treasury_units",0))
	return maxi(1,ceili(float(valuation(station))/maxi(1,units if units>0 else issued)))

static func listed(world, station: Dictionary) -> bool:
	if station.is_empty() or station.get("landing_only",false) or station.build > 0:
		return false
	var table := cap_table(world,station)
	if table.total == 0:
		return false
	return station.scan or world.oversees(station.owner) or table.people.has(world.player) or world.firms.has(station.firm) or (table.company_units > 0 and world.firms.has(table.company))

static func participants(world, station: Dictionary) -> Dictionary:
	var table := cap_table(world,station)
	var parties := {}
	var outstanding: int = table.total-int(table.get("treasury_units",0))
	for person: Dictionary in world.people.values():
		if not world.Equity.adult(world,person):
			continue
		var units: int = table.people.get(person.id,0)
		if person.loc != station.id and units == 0 and person.id != station.manager and person.id != station.owner:
			continue
		var runs_site: bool = person.id == station.owner or person.id == station.manager
		parties[person.id] = {"units":units,"controller":units*2>outstanding,"interest":runs_site or units > 0 or person.origin == 1,"representative":person.id}
	var firm_id: int = table.company if table.company > 0 else station.firm
	var firm: Dictionary = world.firms.get(firm_id,{})
	if not firm.is_empty() and world.Equity.adult(world,world.people.get(firm.director,{})):
		parties[-firm_id] = {"units":table.company_units,"controller":int(table.company_units)*2>outstanding,"interest":station.firm == firm_id,
			"representative":firm.director,"player_controlled":world.oversees(firm.director)}
	if int(table.get("treasury_units",0)) > 0:
		var signer := trustee(world,station)
		if signer != 0:
			parties[TREASURY_PARTY] = {"units":table.treasury_units,"controller":false,"interest":false,"representative":signer,
				"player_controlled":world.oversees(station.owner) or world.oversees(world.firms.get(station.firm,{}).get("director",0)),
				"name":"站点库存股"}
	return parties

## The manager or the system's existing registry handles an intestate facility's treasury stock.
static func trustee(world, station: Dictionary) -> int:
	var registry: Dictionary = world.ports[world.systems[station.system].ports[0]]
	var home: Dictionary = world.ports[world.systems[0].ports[0]]
	for id in [station.manager,station.owner,world.firms.get(station.firm,{}).get("director",0),
			world.factions.get(station.flag,{}).get("leader",0),registry.manager,home.manager]:
		if world.Equity.adult(world,world.people.get(id,{})):
			return id
	return 0

static func offers(world, station: Dictionary, buying: bool) -> Array:
	var result := []
	if not listed(world,station) or not world.Equity.at_market(world):
		return result
	world.EquityOrders.publish(world,"station",station.id,unit_price(station),participants(world,station))
	var table := cap_table(world,station)
	for original in world.EquityOrders.quotes(world,"station",station.id,buying):
		var row: Dictionary = original.duplicate()
		var limit: int = int(world.active().wallet)/int(row.unit_price) if buying else int(table.people.get(world.player,0))-world.DiplomaticTrade.reserved_shares(world,"station",station.id,world.player)
		row.quantity = mini(row.quantity,limit)
		if row.quantity > 0:
			if row.person == TREASURY_PARTY:
				row.name = "站点库存股"
			result.append(row)
	return result

static func trade(world, station: Dictionary, counterparty: int, qty: int, buying: bool, expected_price: int, order_id: int = 0, listing_id: int = 0) -> bool:
	if qty < 1 or expected_price < 1 or not listed(world,station) or (listing_id==0 and not world.Equity.at_market(world)):
		return false
	var table := cap_table(world,station)
	var owner_units: int = table.people.get(counterparty,0)
	if counterparty == TREASURY_PARTY:
		if not buying:
			return false
		owner_units = table.get("treasury_units",0)
	elif counterparty < 0:
		var company: int = table.company if table.company > 0 else station.firm
		if company != -counterparty:
			return false
		owner_units = table.company_units
	if qty > (owner_units if buying else int(table.people.get(world.player,0))):
		return false
	if not world.EquityOrders.fill(world,"station",station.id,counterparty,qty,buying,expected_price,order_id,listing_id):
		return false
	var delta := qty if buying else -qty
	if counterparty == TREASURY_PARTY:
		table.treasury_units -= qty
	elif counterparty < 0:
		table.company = -counterparty
		table.company_units -= delta
	else:
		add_units(table.people,counterparty,-delta)
	add_units(table.people,world.player,delta)
	world.StockPrices.record(world,"station",station.id,qty,qty*expected_price)
	station.equity = table
	if listing_id!=0:
		world.ShareExchange.settled(world,listing_id,counterparty,qty,expected_price)
	world.EquityOrders.audit(world,"station",station.id)
	return true

static func add_units(people: Dictionary, person: int, amount: int) -> void:
	var units := int(people.get(person,0)) + amount
	if units == 0:
		people.erase(person)
	else:
		people[person] = units

static func inherit(world, dead: int, heir: int) -> void:
	for station: Dictionary in world.ports.values():
		if not station.has("equity"):
			if heir != 0 or station.owner != dead or station.firm != 0:
				continue
			station.equity = cap_table(world,station)
		var people: Dictionary = station.equity.people
		var units: int = people.get(dead,0)
		if units == 0:
			continue
		if heir != 0:
			add_units(people,heir,units)
		else:
			station.equity.treasury_units = int(station.equity.get("treasury_units",0))+units
		people.erase(dead)
