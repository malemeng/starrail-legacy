extends RefCounted

const Industry = preload("res://scripts/economy/industry.gd")

static func can_manage(world, station: Dictionary, actor_id: int = 0) -> bool:
	return world.oversees(station.get("manager",0), actor_id) or world.oversees(station.owner, actor_id) or world.oversees(world.firms.get(station.firm,{}).get("director",0), actor_id)

static func terms(world, account: Dictionary, available: int, eligible: bool) -> Dictionary:
	var config: Dictionary = Industry.RULES.dividends
	var policy: Dictionary = account.get("dividend_policy",{})
	var percent := int(policy.get("percent",config.default_percent))
	var reserve := int(policy.get("reserve",config.cash_reserve))
	var retained := int(account.get("operating_profit",0))
	var next_day := int(account.get("last_dividend_day",-int(config.period_days))) + int(config.period_days)
	var payout := 0
	if eligible and world.day >= next_day:
		payout = mini(maxi(0,available-reserve),maxi(0,retained)*percent/100)
	return {"balance":int(account.get("treasury",0)),"available":available,"retained_profit":retained,"reserve":reserve,"percent":percent,
		"period_days":int(config.period_days),"next_eligible_day":maxi(0,next_day),"payable":payout}

static func statement(world, station: Dictionary) -> Dictionary:
	var table: Dictionary = world.StationEquity.cap_table(world,station)
	var outstanding := int(table.total) - int(table.get("treasury_units",0))
	var eligible: bool = (outstanding > 0 or (table.total == 0 and world.factions.has(station.flag))) and station.build == 0 and not station.get("landing_only",false)
	return terms(world,station,world.Treasury.available(station),eligible)

static func company_statement(world, id: int) -> Dictionary:
	var firm: Dictionary = world.firms[id]
	var outstanding: int = firm.issued - firm.treasury_shares
	return terms(world,firm,int(firm.treasury),outstanding > 0)

static func set_terms(account: Dictionary, percent: int, reserve: int) -> bool:
	if percent < 0 or percent > 100 or reserve < 0:
		return false
	account.dividend_policy = {"percent":percent,"reserve":reserve}
	return true

static func configure(world, station: Dictionary, percent: int, reserve: int) -> bool:
	return not station.is_empty() and can_manage(world,station) and set_terms(station,percent,reserve)

static func configure_company(world, id: int, percent: int, reserve: int) -> bool:
	var firm: Dictionary = world.firms.get(id,{})
	return not firm.is_empty() and world.oversees(firm.director) and set_terms(firm,percent,reserve)

## Allocate whole credits by largest remainder, using stable holder IDs for ties.
static func allocate(weights: Dictionary, dividend: int) -> Array:
	var total := 0
	for shares: int in weights.values():
		total += shares
	var allocations := []
	var remainder := dividend
	for holder: int in weights:
		var weighted := dividend * int(weights[holder])
		var amount := weighted / total
		remainder -= amount
		allocations.append({"person":holder,"amount":amount,"fraction":weighted % total})
	allocations.sort_custom(func(a,b): return a.fraction > b.fraction if a.fraction != b.fraction else a.person < b.person)
	for i in remainder:
		allocations[i].amount += 1
	return allocations

static func company_asset(id: int, firm: Dictionary) -> Dictionary:
	return {"id":id,"name":firm.name,"ledger_type":"company"}

static func settle(world, station: Dictionary) -> int:
	var dividend: int = statement(world,station).payable
	if dividend <= 0 or not world.Treasury.post(world,station,-dividend,"分红",false):
		return 0
	station.operating_profit -= dividend
	station.last_dividend_day = world.day
	var table: Dictionary = world.StationEquity.cap_table(world,station)
	var weights: Dictionary = table.people.duplicate()
	if table.company_units > 0:
		weights[-int(table.company)] = table.company_units
	for flag in table.get("factions",{}):
		var units := int(table.factions[flag])
		if units > 0 and world.factions.has(flag):
			weights[-1000000 - int(flag)] = units
	if weights.is_empty():
		world.factions[station.flag].treasury += dividend
		return dividend
	for allocation in allocate(weights,dividend):
		var id := int(allocation.person)
		if id <= -1000000:
			var flag := -id - 1000000
			if world.factions.has(flag):
				world.factions[flag].treasury += allocation.amount
		elif id < 0:
			var firm: Dictionary = world.firms[-id]
			firm.treasury += allocation.amount
			firm.operating_profit += allocation.amount
			world.Finances.record(world,firm.director,company_asset(-id,firm),"公司收到站点股息",allocation.amount,false,true)
		else:
			world.credit(id,allocation.amount)
			world.Finances.record(world,id,station,"股息到账",allocation.amount,false,true)
	return dividend

static func settle_company(world, id: int) -> int:
	var firm: Dictionary = world.firms[id]
	var dividend: int = company_statement(world,id).payable
	if dividend <= 0:
		return 0
	var weights := {}
	for person: Dictionary in world.people.values():
		var stake: int = person.shares.get(id,0)
		if person.alive and stake > 0:
			weights[person.id] = stake
	for flag in world.factions:
		var f_stake := int(world.factions[flag].get("shares",{}).get(id,0))
		if f_stake > 0:
			weights[-1000000 - int(flag)] = f_stake
	if weights.is_empty():
		return 0
	firm.treasury -= dividend
	firm.operating_profit -= dividend
	firm.last_dividend_day = world.day
	var asset := company_asset(id,firm)
	world.Finances.record(world,firm.director,asset,"公司派息",-dividend,false,true)
	for row in allocate(weights,dividend):
		var holder := int(row.person)
		if holder <= -1000000:
			var flag := -holder - 1000000
			if world.factions.has(flag):
				world.factions[flag].treasury += row.amount
		else:
			world.credit(holder,row.amount)
			world.Finances.record(world,holder,asset,"股息到账",row.amount,false,true)
	return dividend

static func monthly(world) -> void:
	if world.day % int(Industry.RULES.dividends.period_days) != 0:
		return
	for station: Dictionary in world.ports.values():
		if station.get("operating_profit",0) > 0:
			settle(world,station)
	for id: int in world.firms:
		if world.firms[id].get("operating_profit",0) > 0:
			settle_company(world,id)
