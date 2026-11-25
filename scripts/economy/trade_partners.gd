extends RefCounted

const Industry = preload("res://scripts/economy/industry.gd")
const Rules = preload("res://data/campaign/sector.json")

static func location(world) -> int:
	var ship: Dictionary = world.ride()
	return int(world.active().get("loc",0)) if ship.is_empty() else int(ship.dock)

## Cargo belongs to the operator, and has to be present at the same physical berth.
static func cargo_ship(world, actor: Dictionary, port: int, company_market: bool = false) -> int:
	var ship: Dictionary = world.ships.get(actor.get("ship",0),{})
	if port<=0 or ship.is_empty() or ship.dock!=port or ship.captain!=actor.id:
		return 0
	if ship.job.get("kind","") in ["站属贸易","站属采矿","施工配送"] or ship.has("construction_contract"):
		return 0
	if ship.has("firm"):
		return ship.id if company_market and actor.id == world.player else 0
	return ship.id if world.Hulls.operator_id(ship) == actor.id else 0

static func market_firm(world, kind: String, port: int) -> int:
	if kind != "station":
		return 0
	var ship := cargo_ship(world,world.active(),port,true)
	return world.ships.get(ship,{}).get("firm",0)

static func available_cargo(ship: Dictionary, ware: int) -> int:
	var quantity: int = ship.cargo[ware]
	var freight: Dictionary = ship.get("reservation",{})
	if freight.get("loaded",false) and freight.get("ware",-1)==ware:
		quantity -= int(freight.qty)
	return maxi(0,quantity)

static func reachable_person(world, actor: Dictionary, port: int) -> bool:
	if actor.loc==port or not actor.shares.is_empty():
		return true
	for group: Dictionary in world.factions.values():
		if group.alive and group.leader==actor.id:
			return true
	for firm: Dictionary in world.firms.values():
		if firm.director==actor.id:
			return true
	for site: Dictionary in world.ports.values():
		if world.StationEquity.listed(world,site) and (site.manager==actor.id or world.StationEquity.cap_table(world,site).people.has(actor.id)):
			return true
	return false

static func black_broker(world, site: Dictionary) -> int:
	for resident: Dictionary in world.people.values():
		if resident.loc==site.id and resident.ship==0 and resident.id not in [site.manager,site.owner] and not world.oversees(resident.id) and world.Equity.adult(world,resident):
			return resident.id
	return world.StationEquity.trustee(world,site)

static func participant(world, kind: String, id: int, black: bool = false) -> Dictionary:
	var dock := location(world)
	var here: Dictionary = world.ports.get(dock,{})
	if here.is_empty() or not world.Equity.adult(world,world.active()):
		return {}
	if black and (kind not in ["player","station"] or not world.is_regular(here)):
		return {}
	if not black and not world.Equity.at_market(world):
		return {}
	var signer := 0
	var ship := 0
	var name := ""
	var ordinary_only := false
	match kind:
		"person","player":
			var actor: Dictionary = world.people.get(id,{})
			if not world.Equity.adult(world,actor) or (kind=="player") != (id==world.player):
				return {}
			if kind=="person" and (world.oversees(id) or not reachable_person(world,actor,dock)):
				return {}
			signer = id
			name = actor.name
			ship = cargo_ship(world,actor,dock)
		"company":
			var firm: Dictionary = world.firms.get(id,{})
			if firm.is_empty() or int(world.active().shares.get(id,0))*2 > int(firm.issued)-int(firm.treasury_shares):
				return {}
			signer = firm.director
			name = firm.name
		"station":
			var site: Dictionary = world.ports.get(id,{})
			if site.is_empty() or site.get("landing_only",false) or site.build>0 or (black and id!=dock):
				return {}
			var table: Dictionary = world.StationEquity.cap_table(world,site)
			if id!=dock and (table.treasury_units<=0 or not world.StationEquity.listed(world,site)):
				return {}
			ordinary_only = not black and (world.oversees(site.owner) or world.oversees(world.firms.get(site.firm,{}).get("director",0)) or int(table.people.get(world.player,0))*2>int(table.total))
			if ordinary_only and id!=dock:
				return {}
			signer = black_broker(world,site) if black else world.StationEquity.trustee(world,site)
			if ordinary_only and world.oversees(signer):
				for office: int in [site.manager,world.ports[world.systems[site.system].ports[0]].manager,world.ports[world.systems[0].ports[0]].manager]:
					if world.Equity.adult(world,world.people.get(office,{})) and not world.oversees(office):
						signer = office
						break
			name = site.name+(" · 黑市" if black else "")
		"faction":
			var group: Dictionary = world.factions.get(id,{})
			if not group.get("alive",false):
				return {}
			signer = group.leader
			name = group.name
		_:
			return {}
	if not world.Equity.adult(world,world.people.get(signer,{})) or (kind!="player" and not ordinary_only and world.oversees(signer)):
		return {}
	return {"kind":kind,"id":id,"name":name,"representative":signer,"black":black,"ship":ship,"ordinary_only":ordinary_only,
		"port":id if kind=="station" else dock,"local":kind!="station" or id==dock}

static func partners(world) -> Array:
	var result := []
	var dock := location(world)
	if dock<=0:
		return result
	for kind: String in ["station","person","company","faction"]:
		var accounts: Dictionary
		match kind:
			"station": accounts = world.ports
			"person": accounts = world.people
			"company": accounts = world.firms
			"faction": accounts = world.factions
		for id: int in accounts:
			var entry := participant(world,kind,id)
			if not entry.is_empty():
				result.append(entry)
			if kind=="station" and id==dock:
				entry = participant(world,kind,id,true)
				if not entry.is_empty():
					result.append(entry)
	return result

static func asset(rows: Array, kind: String, id: int, units: int, name: String, price: int) -> void:
	if units>0:
		rows.append({"kind":kind,"id":id,"quantity":units,"name":name,"unit_price":price})

static func assets(world, kind: String, id: int, black: bool = false, market_company: int = 0) -> Array:
	var side := participant(world,kind,id,black)
	var result := []
	if side.is_empty():
		return result
	var cash := 0
	match kind:
		"player","person": cash = world.people[id].wallet
		"company": cash = world.firms[id].treasury
		"station": cash = world.ports[id].get("black_treasury",0) if black else world.Treasury.available(world.ports[id])
		"faction": cash = world.factions[id].treasury
	if market_company != 0 and kind == "player":
		side.ship = world.active().ship
		var company_cash: int = world.firms[market_company].treasury
		asset(result,"cash",0,maxi(cash,company_cash),"信用点（货物用公司账户 ¢%d，私人账户 ¢%d）" % [company_cash,cash],1)
	else:
		asset(result,"cash",0,cash,"信用点",1)
	var local: Dictionary = world.ports[location(world)]
	if side.ship != 0 or (kind=="station" and side.local):
		for ware in world.WARES.size():
			if not black and ware==Industry.Ware.LUXURY:
				continue
			var qty: int
			if side.ship!=0:
				qty = available_cargo(world.ships[side.ship],ware)
			else:
				qty = local.black[ware] if black else Industry.available(local,ware)
			asset(result,"ware",ware,qty,world.WARES[ware],world.Economy.price(local,ware,kind!="player",world.active().origin,black))
	if black or side.ordinary_only:
		return result
	if kind in ["player","person","company"]:
		var holdings: Dictionary = {id:world.firms[id].treasury_shares} if kind=="company" else world.people[id].shares
		for company: int in holdings:
			var free: int = int(holdings[company])-world.ShareExchange.reserved(world,"company",company,id) if kind=="player" else int(holdings[company])
			asset(result,"company_share",company,free,world.firms[company].name+" · 公司股",world.Equity.overview(world,company).unit_price)
	for site: Dictionary in world.ports.values():
		if not world.StationEquity.listed(world,site):
			continue
		var cap: Dictionary = world.StationEquity.cap_table(world,site)
		var units := 0
		match kind:
			"player","person": units = cap.people.get(id,0)
			"company": units = cap.company_units if cap.company==id else 0
			"station": units = cap.treasury_units if site.id==id else 0
		if units>0:
			if kind=="player":
				units-=world.ShareExchange.reserved(world,"station",site.id,id)
			asset(result,"station_share",site.id,units,site.name+" · 站股",world.StationEquity.unit_price(site))
	if kind=="faction":
		var terms := treaty(world,id)
		if terms.ok:
			asset(result,"treaty",id,1,"停战协定（%d 日）" % int(Rules.data.negotiated_truce.days),terms.unit_price)
	return result

## Settlement calls this after locking the agreed consideration. The two political principals must still have a mandate.
static func treaty(world, flag: int, execute: bool = false) -> Dictionary:
	var group: Dictionary = world.factions.get(flag,{})
	var own: int = world.active().get("flag",world.NEUTRAL)
	for governed: int in world.factions:
		if world.Society.player_governs(world,governed):
			own = governed
			break
	var who: int = group.get("leader",0)
	var terms: Dictionary = Rules.data.negotiated_truce
	var answer := {"ok":false,"reason":"","unit_price":0,"representative":who}
	if not world.Equity.at_market(world) or not group.get("alive",false) or not world.Equity.adult(world,world.people.get(who,{})) or world.oversees(who):
		answer.reason = "当前没有对方有权签字的外交代表。"
	elif own<0 or own==flag or not world.Society.player_governs(world,own):
		answer.reason = "签订势力间的停战协议需要代表己方政权。"
	elif group.get("civil_enemy",world.NEUTRAL)==own or world.factions[own].get("civil_enemy",world.NEUTRAL)==flag:
		answer.reason = "内战须通过本国的和解程序解决。"
	elif world.treaty(own,flag).state != -1:
		answer.reason = "双方当前没有交战。"
	elif world.Politics.opinion(world,who,world.player) < int(terms.minimum_opinion):
		answer.reason = "对方领袖拒绝与你签订停战协议。"
	else:
		answer.ok = true
		answer.unit_price = int(terms.base_reparations)+int(terms.per_held_port)*world.systems_owned(flag).size()
		answer.reason = "%s 接受 %d 日停战谈判。" % [world.name_of(who),int(terms.days)]
		if execute:
			world.set_treaty(own,flag,0)
			world.treaty(own,flag).truce_until = world.day+int(terms.days)
			world.event("%s 与 %s 签署停战协定。" % [world.flag_name(own),group.name])
	return answer
