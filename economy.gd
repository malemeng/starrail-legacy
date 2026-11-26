extends RefCounted

const Industry = preload("res://scripts/economy/industry.gd")
const Diagnostics = preload("res://scripts/services/ship_diagnostics.gd")
const ArmsMarket = preload("res://data/economy/arms_market.json")
const StationData = preload("res://scripts/models/station_data.gd")
static var BASE: Array = Industry.BASE
const Hulls = preload("res://hull_catalog.gd")
const Celestial = preload("res://celestial.gd")
const Hyperspace = preload("res://scripts/campaign/hyperspace.gd")
const MerchantSecurity = preload("res://scripts/economy/merchant_security.gd")
const OperatingArea = preload("res://scripts/economy/operating_area.gd")
const Defenses = preload("res://scripts/battle/defenses.gd")
const FleetOrder = preload("res://scripts/models/fleet_order.gd")
const StationGeometry = preload("res://scripts/models/station_geometry.gd")
const StationDesign = preload("res://scripts/models/station_design.gd")
const LOCAL_DISTANCE_PER_DAY := 120.0

static func colony_defaults(wild: bool, ready: bool = true) -> Dictionary:
	var pop := (85 if wild else 680) if ready else 10
	return {"pop":pop,"pop_cap":320 if wild else 1250,"stability":(66.0 if wild else 81.0) if ready else 60.0,
		"tax_rate":0.10,"black":Industry.initial_black_market() if ready else [],"tax_remainder":0.0,"shortage":0}

static func market_size(station: Dictionary) -> int:
	var pop := int(station.get("pop", 0))
	if pop <= 0:
		return 0
	if pop >= 2000:
		return 6
	if pop >= 1000:
		return 5
	if pop >= 500:
		return 4
	if pop >= 200:
		return 3
	if pop >= 50:
		return 2
	return 1

static func market_size_label(station: Dictionary) -> String:
	const NAMES := ["无人", "前哨", "聚落", "殖民站", "枢纽", "星港", "都会"]
	var sz := market_size(station)
	return "%d级·%s" % [sz, NAMES[clampi(sz, 0, NAMES.size() - 1)]]

static func provisions_for(station: Dictionary, days: int) -> int:
	return ceili(float(station.pop * days) / int(Industry.RULES.colony.person_days_per_unit))

static func demand(station: Dictionary) -> int:
	return (int(station.get("provision_person_days",0)) + int(station.pop)) / int(Industry.RULES.colony.person_days_per_unit)

static func initialize_station(world, station: Dictionary, ready: bool) -> void:
	Industry.setup(world, station, ready)
	world.Treasury.open(world,station,ready)
	if ready and Industry.Module.YARD in station.modules:
		var cheapest := -1
		for kind in Hulls.MODELS.size():
			var model: Dictionary = Hulls.MODELS[kind]
			if model.get("initial_shipyard_stock",0) > 0 and Hulls.model_limit(station,kind):
				station.hulls[kind] = maxi(station.hulls[kind],int(model.initial_shipyard_stock))
			if model.fighter_bays > model.builtin_wings.size() and Hulls.model_limit(station,kind) and (cheapest < 0 or model.price < Hulls.MODELS[cheapest].price):
				cheapest = kind
		if cheapest >= 0:
			station.hulls[cheapest] = maxi(station.hulls[cheapest],1)

static func station_overview(world, port_id: int) -> Dictionary:
	var station: Dictionary = world.ports.get(port_id,{})
	if station.is_empty():
		return {}
	var result := Industry.station_data(station).overview()
	result.trade_rules = station.get("trade_rules",{}).duplicate(true)
	result.available_methods = Industry.RULES.shipbuilding.keys()
	result.yard_work = station.get("yard_work",{}).duplicate()
	return result

static func set_method(world, port_id: int, method: String) -> bool:
	var station: Dictionary = world.ports.get(port_id,{})
	if station.is_empty() or not world.oversees(station.owner) or Industry.Module.YARD not in station.modules or not Industry.RULES.shipbuilding.has(method):
		return false
	if station.has("yard_work") and station.method != method:
		return false
	if not station.get("yard_works", {}).is_empty() and station.method != method:
		return false
	var industry := Industry.station_data(station)
	for i in range(industry.order_count()):
		if not supports_method(industry.order_at(i),method):
			return false
	station.method = method
	Industry.update_market(station)
	return true

static func supports_method(kind: int, method: String) -> bool:
	return Industry.supports_method(Hulls.MODELS[kind],method)

static func population_day(world, moved: Dictionary = {}) -> void:
	transit_day(world,moved)
	daily_leases(world)
	for station in world.ports.values():
		if station.build > 0 or station.get("landing_only",false):
			continue
		var person_days := int(station.get("provision_person_days",0)) + int(station.pop)
		var unit_days := int(Industry.RULES.colony.person_days_per_unit)
		var need := demand(station)
		station.provision_person_days = person_days % unit_days
		var blockaded := false
		if world.day % 6 == 0 or not station.has("blockaded"):
			for ship in world.ships.values():
				if ship.job.get("kind","") in ["攻城", "私掠"] and ship.job.get("target",0) == station.id and ship.job.get("arrived",false):
					blockaded = true
					break
			station.blockaded = blockaded
		var shortage := 0
		var inventory := Industry.station_data(station)
		for ware in Industry.COLONY_NEEDS:
			if need > 0:
				shortage += need - inventory.withdraw(ware,need)
			elif station.pop > 0 and inventory.available(ware) == 0:
				shortage += 1
		var supplied: bool = shortage == 0 and not station.blockaded and not station.get("coalition_blockade",false)
		station.shortage = 0 if supplied else station.shortage + 1
		station.stability = clampf(station.stability + (0.55 if supplied else -(0.45 + minf(float(shortage) * 0.08, 0.75))), 0.0, 100.0)
		if supplied and station.stability >= 50.0 and world.day % 30 == 0:
			var growth_reserve := provisions_for(station,90)
			if Industry.COLONY_NEEDS.all(func(ware): return inventory.available(ware) >= growth_reserve):
				station.pop = mini(station.pop_cap, station.pop + maxi(1, floori(station.pop * 0.024)))
		elif not supplied and station.shortage > 21 and station.stability < 45.0 and world.day % 6 == 0:
			var wild_sys: bool = world.systems[station.system].get("wild", false)
			var pop_floor := mini(station.pop, 25 if wild_sys else 120) if station.pop < 25 else (25 if wild_sys else 120)
			var refugees := mini(maxi(0, station.pop - pop_floor), maxi(1, floori(station.pop * 0.03)))
			if refugees > 0:
				station.pop -= refugees
				var refuge: Dictionary = {}
				var nearest := INF
				for other in world.ports.values():
					if other.id == station.id or other.build > 0 or other.stability < 65.0 or other.pop >= other.pop_cap or world.hostile(station.flag, other.flag):
						continue
					var gap: float = world.distance(station.system,other.system)
					if gap < nearest:
						nearest = gap
						refuge = other
				if not refuge.is_empty():
					refuge.pop = mini(refuge.pop_cap, refuge.pop + refugees)
				if station.shortage <= 27:
					world.event("%s 断供，%s 位居民撤离。" % [station.name, refugees])
		if station.stability <= 16.0 and station.shortage == 30:
			world.event("%s 爆发补给骚乱，站务委员会要求自治。" % station.name)
		station.tax_remainder += station.pop * station.tax_rate * station.stability / 8500.0
		var taxes := floori(station.tax_remainder)
		station.tax_remainder -= taxes
		if taxes > 0:
			var faction_cut := floori(taxes * 0.25) if int(station.flag) >= 0 and world.factions.get(station.flag, {}).get("alive", false) else 0
			if faction_cut > 0:
				world.factions[station.flag].treasury += faction_cut
			if taxes - faction_cut > 0:
				world.Treasury.post(world,station,taxes - faction_cut,"居民税收")
		if world.day % 6 == 0 and int(station.manager) != 0 and int(station.manager) != int(station.owner):
			var mgr: Dictionary = world.people.get(station.manager, {})
			if mgr.get("alive", false):
				var want := maxi(8, roundi(float(station.pop) * 0.04 + float(mgr.stats.stewardship) * 1.5))
				var salary := mini(world.Treasury.available(station), want)
				if salary > 0 and world.Treasury.post(world, station, -salary, "站长俸禄"):
					world.credit(int(station.manager), salary)
				if supplied and int(station.flag) >= 0 and not world.WarPeace.active_wars(world, int(station.flag)).is_empty():
					mgr.merit = int(mgr.get("merit", 0)) + 1
					mgr.prestige = int(mgr.get("prestige", 0)) + 1
					var leader_id := int(world.factions.get(station.flag, {}).get("leader", 0))
					if leader_id != 0 and leader_id != int(station.manager) and world.people.has(leader_id):
						var l_op: Dictionary = world.people[leader_id].get("opinions", {})
						l_op[int(station.manager)] = clampi(int(l_op.get(int(station.manager), 0)) + 1, -100, 100)
						world.people[leader_id].opinions = l_op

static func crew(world, amount: int) -> int:
	var vessel: Dictionary = world.ride()
	if vessel.is_empty() or vessel.dock == 0 or amount == 0:
		return 0
	var station: Dictionary = world.ports[vessel.dock]
	if not allowed(world,vessel,station) or station.build > 0:
		return 0
	var fee := int(Industry.RULES.colony.wage_per_crew)
	var count := mini(amount, mini(Hulls.crew_limits(vessel.kind).y - vessel.crew,mini(maxi(0,station.pop-10),player_funds(world,vessel) / fee))) if amount > 0 else -mini(-amount,mini(vessel.crew, station.pop_cap - station.pop))
	vessel.crew += count
	station.pop -= count
	if count > 0:
		player_pay(world,vessel,-fee*count,"船员招募")
	return count

static func market_open(world, visitor: Dictionary, station: Dictionary) -> bool:
	if station.get("coalition_blockade",false) or station.get("landing_only",false):
		return false
	if visitor.flag < 0 or station.firm == 0:
		return true
	return world.firms.get(station.firm, {}).get("embargo", -1) != visitor.flag and not world.CompanyWars.at_war(world,station.firm,visitor.flag)

static func allowed(world, vessel: Dictionary, station: Dictionary) -> bool:
	return market_open(world,vessel,station) and world.can_dock(vessel,station)

static func incorporate(world, port_id: int, label: String, founder_id: int = -1) -> bool:
	var fid: int = world.player if founder_id <= 0 else founder_id
	var founder: Dictionary = world.people.get(fid, {})
	var station: Dictionary = world.ports.get(port_id, {})
	if founder.is_empty() or not founder.alive or station.is_empty() or station.owner != fid or station.build != 0 or station.firm != 0 or int(founder.get("wallet", 0)) < 1800 or label.strip_edges().is_empty():
		return false
	if world.incorporate(label,fid,port_id,true,1800)==0:
		return false
	world.credit(fid, -1800,station,"企业注册")
	world.event("%s 注册成立了 %s。" % [founder.name, label])
	return true

static func price(station: Dictionary, ware: int, buying: bool, origin: int = -1, black: bool = false) -> int:
	return lot_quote(station,ware,1,buying,origin,black).y

static func contributable(vessel: Dictionary) -> bool:
	return not vessel.is_empty() and vessel.owner != 0 and not vessel.has("lease") and not vessel.has("station_owner") and not vessel.has("charter") and not vessel.has("firm") and vessel.get("deal_space",0) == 0 and not vessel.locked and vessel.get("reservation",{}).is_empty()

static func incorporate_ship(world, ship_id: int, label: String) -> int:
	var vessel: Dictionary = world.ships.get(ship_id,{})
	if not contributable(vessel) or vessel.owner != world.player or world.active().wallet < 1800 or label.strip_edges().is_empty():
		return 0
	var anchor: int = vessel.dock if vessel.dock else world.active().loc
	if not world.ports.has(anchor):
		var local: Array = world.systems[vessel.system].ports
		anchor = local.front() if not local.is_empty() else world.ports.keys().front()
	var id: int = world.incorporate(label,world.player,anchor,false,1800,vessel)
	if id:
		world.credit(world.player,-1800,vessel,"企业注册")
		world.event("%s 以 #%d %s 出资成立 %s。" % [world.active().name,ship_id,world.HULLS[vessel.kind],world.firms[id].name])
	return id

static func contribute_ship(world, ship_id: int, firm_id: int) -> bool:
	var vessel: Dictionary = world.ships.get(ship_id,{})
	var company: Dictionary = world.firms.get(firm_id,{})
	if not contributable(vessel) or vessel.owner != world.player or company.get("director",0) != world.player:
		return false
	if vessel.captain != world.player and world.people.has(vessel.captain) and world.people[vessel.captain].employer == world.player:
		world.people[vessel.captain].employer = 0
	vessel.owner = 0
	vessel.firm = firm_id
	world.event("#%d %s 已由 %s 接收。" % [ship_id,world.HULLS[vessel.kind],company.name])
	return true

## x = executable units, y = total credits. Each unit crosses the same stock level in either direction.
static func lot_quote(station: Dictionary, ware: int, units: int, buying: bool, origin: int = -1, black: bool = false, budget: int = 2147483647) -> Vector2i:
	return Industry.lot_quote(station,ware,units,buying,origin,black,budget)

static func trade_quote(world, station: Dictionary, ware: int, amount: int, black: bool = false) -> Vector2i:
	var quote := trade_invoice(world,station,ware,amount,black)
	return Vector2i(quote.units,quote.total)

static func trade_invoice(world, station: Dictionary, ware: int, amount: int, black: bool = false) -> Dictionary:
	var vessel: Dictionary = world.ride()
	var character: Dictionary = world.active()
	if vessel.is_empty() or station.get("landing_only",false) or ware not in range(world.WARES.size()) or (not black and ware == Industry.Ware.LUXURY):
		return {"units":0,"total":0,"base":0,"tax":0}
	var buying := amount > 0
	var remaining := absi(amount)
	var available := StationData.market_quantity(station,ware,true) if black else Industry.available(station,ware)
	if buying:
		return Industry.lot_invoice(station,ware,mini(remaining,mini(available,world.cargo_free(vessel))),true,character.origin,black,player_funds(world,vessel))
	var capacity: int = vessel.cargo[ware] if black else Industry.space(station,ware)
	var buyer_budget := int(station.get("black_treasury",0)) if black else Industry.Treasury.available(station)
	return Industry.lot_invoice(station,ware,mini(remaining,mini(vessel.cargo[ware],capacity)),false,character.origin,black,buyer_budget)

static func remit_goods_tax(world, flag: int, amount: int) -> bool:
	if amount==0:
		return true
	var group: Dictionary = world.factions.get(flag,{})
	if amount<0 or flag<0 or not group.get("alive",false):
		return false
	group.treasury += amount
	group.goods_tax_collected = int(group.get("goods_tax_collected",0))+amount
	return true

static func trade(world, port_id: int, ware: int, amount: int, black: bool = false) -> int:
	var vessel: Dictionary = world.ride()
	var character: Dictionary = world.active()
	var station: Dictionary = world.ports.get(port_id, {})
	if station.is_empty() or vessel.is_empty() or vessel.dock != port_id or ware not in range(world.WARES.size()) or amount == 0:
		return 0
	if station.build > 0 or (black and not world.is_regular(station)) or (not black and not allowed(world, vessel, station)):
		return 0
	var buying := amount > 0
	var quote := trade_invoice(world,station,ware,amount,black)
	var quantity: int = quote.units
	if quantity <= 0:
		return 0
	var moved := Industry.station_data(station).sell_to_ship(ware,quantity if buying else -quantity,black)
	vessel.cargo[ware] += moved
	player_pay(world,vessel,-quote.total if buying else quote.total,"货物采购" if buying else "货物销售")
	if not black:
		world.Treasury.market(world,station,quote.base if buying else -quote.base)
		remit_goods_tax(world,station.tariff_flag,quote.tax)
	if black:
		station.black_treasury += quote.total if buying else -quote.total
		character.suspicion = mini(100, int(character.get("suspicion",0)) + quantity * (3 if ware == 6 else 1))
	if not black:
		world.chart(port_id)
	Diagnostics.transfer(world,vessel,("采购 " if buying else "销售 ") + world.WARES[ware],station.name + (" 黑市" if black else ""),-quote.total if buying else quote.total,quantity,quote.tax,station.tariff_flag,world.player if personal_operator(vessel) else 0)
	world.combat_event("trade", station.pos, station.system)
	world.trade_event(black,character.id)
	world.market_updated.emit(port_id,ware,black)
	return moved

static func inspect_departure(world, vessel: Dictionary) -> int:
	var actor: Dictionary = world.active()
	var suspicion: int = actor.get("suspicion",0)
	if suspicion == 0 or vessel.dock == 0 or not world.is_regular(world.ports[vessel.dock]):
		return 0
	actor.suspicion = maxi(0,suspicion - 11)
	if world.rng.randi_range(1,100) > suspicion:
		return 0
	var fine := mini(actor.wallet,25 + suspicion * 2 + vessel.cargo[6] * 3)
	world.credit(actor.id,-fine,vessel,"查缉罚款")
	vessel.cargo[6] = 0
	world.event("巡逻队盘查：违禁品被扣，罚款 %d。" % fine)
	return fine

static func ship_quote(station: Dictionary, kind: int) -> Dictionary:
	return Industry.ship_quote(station,Hulls.MODELS[kind])

## Private buyers and fleets both take a completed hull from stock at its current replacement price.
static func withdraw_priced_hull(station: Dictionary, kind: int, budget: int, expected_price: int = -1) -> int:
	if kind not in range(Hulls.MODELS.size()) or station.build > 0 or not Hulls.model_limit(station,kind):
		return 0
	var quote: int = ship_quote(station,kind).price
	if budget < quote or (expected_price >= 0 and expected_price != quote):
		return 0
	return quote if Industry.station_data(station).withdraw_hull(kind) else 0

static func buy_ship(world, port_id: int, kind: int, expected_price: int = -1) -> int:
	return purchase_ship(world,world.player,port_id,kind,false,expected_price)

## A private purchase debits the named buyer and credits the yard delivering the hull.
static func purchase_ship(world, buyer_id: int, port_id: int, kind: int, take_command: bool, expected_price: int = -1) -> int:
	var station: Dictionary = world.ports.get(port_id, {})
	var buyer: Dictionary = world.people.get(buyer_id,{})
	if station.is_empty() or not buyer.get("alive",false) or buyer.loc != port_id or not allowed(world,buyer,station):
		return 0
	var current_ship: Dictionary = world.ships.get(buyer.ship,{})
	if buyer.ship != 0 and (current_ship.get("dock",0) != port_id or current_ship.system != station.system or current_ship.layer or not allowed(world,current_ship,station)):
		return 0
	var price_tag := withdraw_priced_hull(station,kind,buyer.wallet,expected_price)
	if price_tag <= 0:
		return 0
	if take_command and current_ship.get("captain",0) == buyer_id:
		current_ship.captain = 0
	var ship_id: int = world.ship(kind,buyer_id,buyer_id if take_command else 0,buyer.flag,station.system,station.pos,port_id)
	world.credit(buyer_id,-price_tag,world.ships[ship_id],"购舰")
	world.Treasury.post(world,station,price_tag,"船坞售舰")
	return ship_id

static func charter_quote(world, ship_id: int) -> Dictionary:
	var vessel: Dictionary = world.ships.get(ship_id,{})
	var charter: Dictionary = vessel.get("charter",{})
	var quote := {"ok":false,"price":0,"port":0,"reason":""}
	if charter.is_empty() or vessel.owner != 0 or charter.operator != world.player:
		quote.reason = "没有这艘船的承租权"
		return quote
	quote.port = charter.port
	var port: Dictionary = world.ports.get(charter.port,{})
	if port.is_empty():
		quote.reason = "登记港已不存在"
		return quote
	quote.replacement_price = ship_quote(port,vessel.kind).price
	quote.price = ceili(quote.replacement_price * Industry.RULES.ship_market.charter_buyout_share)
	quote.depreciation = quote.replacement_price - quote.price
	if port.build > 0 or vessel.dock != charter.port or world.active().loc != charter.port:
		quote.reason = "人和船都须在登记港"
	elif not allowed(world,vessel,port):
		quote.reason = "登记港目前禁止交易"
	elif world.active().wallet < quote.price:
		quote.reason = "还需 ¢%d" % (quote.price - world.active().wallet)
	else:
		quote.ok = true
	return quote

static func buyout_charter(world, ship_id: int, expected_price: int = -1) -> bool:
	var quote := charter_quote(world,ship_id)
	if not quote.ok or (expected_price >= 0 and expected_price != quote.price):
		return false
	var vessel: Dictionary = world.ships[ship_id]
	world.credit(world.player,-int(quote.price),vessel,"购舰")
	world.Treasury.post(world,world.ports[quote.port],quote.price,"船坞售舰")
	vessel.erase("charter")
	vessel.owner = world.player
	world.event("%s 付清 ¢%d，%s #%d 已转为私产。" % [world.active().name,quote.price,world.HULLS[vessel.kind],ship_id])
	return true

static func supply(world, repair: bool) -> bool:
	var vessel: Dictionary = world.ride()
	if vessel.is_empty() or vessel.dock == 0:
		return false
	var station: Dictionary = world.ports[vessel.dock]
	if station.build > 0 or station.get("landing_only",false) or not world.can_dock(vessel, station):
		return false
	var wallet: int = player_funds(world,vessel)
	if repair:
		var max_hp: int = world.HULL_HP[vessel.kind]
		var max_armor: float = Hulls.COMBAT[vessel.kind].armor
		var repair_scale := Hulls.crew_efficiency(vessel)
		var budget := mini(wallet, 6 * Industry.available(station,Industry.Ware.HULL_PARTS))
		var hull_cost := mini(budget, ceili(maxf(0,max_hp - vessel.hp) / 3.0 / repair_scale))
		var armor_cost := mini(budget - hull_cost, ceili(maxf(0,max_armor - vessel.battle.armor) / 4.0 / repair_scale))
		var cost := hull_cost + armor_cost
		Industry.station_data(station).withdraw(Industry.Ware.HULL_PARTS,ceili(cost / 6.0))
		vessel.hp = minf(max_hp, vessel.hp + 3.0 * hull_cost * repair_scale)
		Defenses.repair_armor(vessel,4.0 * armor_cost * repair_scale)
		player_pay(world,vessel,-cost,"维修")
		world.Treasury.post(world,station,cost,"维修")
		return cost > 0
	var from_cargo := mini(vessel.cargo[2], ceili(100.0 - vessel.fuel))
	vessel.cargo[2] -= from_cargo
	vessel.fuel = minf(100, vessel.fuel + from_cargo)
	var units := pump_fuel(vessel,station,wallet)
	player_pay(world,vessel,-units,"燃料")
	world.Treasury.post(world,station,units,"燃料")
	return units + from_cargo > 0

static func pump_fuel(vessel: Dictionary, station: Dictionary, budget: int) -> int:
	var tank_space := maxi(0,floori(100.0-vessel.fuel))
	var units := Industry.station_data(station).withdraw(Industry.Ware.FUEL,mini(tank_space,budget))
	vessel.fuel += units
	return units

static func supply_fleet_quote(world, port_id: int) -> Dictionary:
	var station: Dictionary = world.ports.get(port_id, {})
	if station.is_empty() or station.build > 0 or station.get("landing_only", false):
		return {"ships": 0, "cost": 0, "needs_service": false}
	var total_cost := 0
	var ships_need := 0
	for vessel in world.ships.values():
		if not world.can_operate(vessel) or vessel.dock != port_id or not world.can_dock(vessel, station):
			continue
		var max_hp: int = world.HULL_HP[vessel.kind]
		var max_armor: float = Hulls.COMBAT[vessel.kind].armor
		var repair_scale := Hulls.crew_efficiency(vessel)
		var hull_cost := ceili(maxf(0.0, max_hp - float(vessel.hp)) / 3.0 / repair_scale)
		var armor_cost := ceili(maxf(0.0, max_armor - float(vessel.battle.armor)) / 4.0 / repair_scale)
		var fuel_need := maxi(0, floori(100.0 - float(vessel.fuel)))
		var from_cargo := mini(int(vessel.cargo[2]), fuel_need)
		var fuel_cost := maxi(0, fuel_need - from_cargo)
		if hull_cost + armor_cost + fuel_need > 0:
			ships_need += 1
			total_cost += hull_cost + armor_cost + fuel_cost
	return {"ships": ships_need, "cost": total_cost, "needs_service": ships_need > 0}

static func supply_fleet(world, port_id: int) -> int:
	var station: Dictionary = world.ports.get(port_id, {})
	if station.is_empty() or station.build > 0 or station.get("landing_only",false):
		return 0
	var actor: Dictionary = world.active()
	var serviced := 0
	for vessel in world.ships.values():
		if not world.can_operate(vessel) or vessel.dock != port_id or not world.can_dock(vessel, station):
			continue
		var touched := false
		var max_hp: int = world.HULL_HP[vessel.kind]
		var max_armor: float = Hulls.COMBAT[vessel.kind].armor
		var repair_scale := Hulls.crew_efficiency(vessel)
		var budget := mini(player_funds(world,vessel), 6 * Industry.available(station, Industry.Ware.HULL_PARTS))
		var hull_cost := mini(budget, ceili(maxf(0, max_hp - vessel.hp) / 3.0 / repair_scale))
		var armor_cost := mini(budget - hull_cost, ceili(maxf(0, max_armor - vessel.battle.armor) / 4.0 / repair_scale))
		var cost := hull_cost + armor_cost
		if cost > 0:
			Industry.station_data(station).withdraw(Industry.Ware.HULL_PARTS, ceili(cost / 6.0))
			vessel.hp = minf(max_hp, vessel.hp + 3.0 * hull_cost * repair_scale)
			Defenses.repair_armor(vessel, 4.0 * armor_cost * repair_scale)
			player_pay(world,vessel,-cost,"维修")
			world.Treasury.post(world,station,cost,"维修")
			touched = true
		var from_cargo := mini(vessel.cargo[2], ceili(100.0 - vessel.fuel))
		if from_cargo > 0:
			vessel.cargo[2] -= from_cargo
			vessel.fuel = minf(100.0, vessel.fuel + from_cargo)
			touched = true
		var fuel_units := Industry.station_data(station).withdraw(Industry.Ware.FUEL, mini(floori(100.0 - vessel.fuel), player_funds(world,vessel)))
		if fuel_units > 0:
			vessel.fuel += fuel_units
			player_pay(world,vessel,-fuel_units,"燃料")
			world.Treasury.post(world,station,fuel_units,"燃料")
			touched = true
		if touched:
			serviced += 1
	return serviced

static func design_issue(world, station: Dictionary, cells: Array) -> String:
	if station.has("planet_index"):
		return "地表港没有轨道装配格。"
	var kinds := StationDesign.kinds(station)
	if cells.size() != kinds.size():
		return "每个已安装或在建模块都须占用一格。"
	var conflict := StationDesign.issue(cells)
	if not conflict.is_empty():
		return conflict
	var geometry := StationGeometry.layout(station,cells)
	var region: Dictionary = world.systems[station.system]
	if StationGeometry.intersects_body(geometry,region.sun) or (region.has("companion") and StationGeometry.intersects_body(geometry,region.companion)):
		return "站体会与恒星重叠。"
	for planet: Dictionary in region.planets:
		if StationGeometry.intersects_body(geometry,planet):
			return "站体会与行星重叠。"
	if region.has("outlaw_base") and StationGeometry.overlaps(geometry,StationGeometry.outpost(region.outlaw_base)):
		return "该处占用了据点的站体或泊位。"
	for id: int in region.ports:
		if id == station.id:
			continue
		var other: Dictionary = world.ports[id]
		if other.has("planet_index"):
			continue
		if Vector2(station.pos).distance_to(other.pos) < Industry.CONSTRUCTION.minimum_separation or StationGeometry.overlaps(geometry,StationGeometry.layout(other)):
			return "与%s的站体或泊位重叠。" % other.name
	return ""

static func build_ship_for(world, pos: Vector2) -> int:
	var vessel: Dictionary = world.ride()
	if vessel.is_empty() or vessel.layer or vessel.system < 0:
		return 0
	var reach: float = Industry.CONSTRUCTION.ship_work_range
	if Hulls.can_build_station(vessel.kind) and vessel.dock == 0 and not vessel.locked and Vector2(vessel.pos).distance_to(pos) <= reach:
		var occupied: bool = world.ports.values().any(func(port): return port.build > 0 and port.get("construction_ship",0) == vessel.id)
		if not occupied:
			return vessel.id
	for ship: Dictionary in world.ships.values():
		var contract: Dictionary = ship.get("construction_contract",{})
		if contract.get("client",0) != world.player or contract.get("status","") != "active" or contract.get("site",0) != 0:
			continue
		if ship.system == vessel.system and ship.dock == 0 and not ship.layer and not ship.locked and Hulls.can_build_station(ship.kind) and Vector2(ship.pos).distance_to(pos) <= reach:
			return ship.id
	return 0

static func construction_issue(world, kind: int, pos: Vector2, cells: Array = []) -> String:
	var vessel: Dictionary = world.ride()
	var terms: Dictionary = Industry.CONSTRUCTION.foundation
	if vessel.is_empty() or vessel.dock != 0 or vessel.layer or vessel.system < 0 or vessel.locked:
		return "请离港并离开交战区域，在星系内选址。"
	if kind not in range(world.MODULES.size()):
		return "请选择有效产业模块。"
	if build_ship_for(world,pos) == 0:
		return "需要自驾或雇用一艘带轨道施工设备的工程巡洋舰，并使其抵达工地附近（%d 单位内）。" % int(Industry.CONSTRUCTION.ship_work_range)
	if world.active().wallet < terms.credits:
		return "设立工地需要 ¢%d。" % int(terms.credits)
	var region: Dictionary = world.systems[vessel.system]
	if region.ports.filter(func(id): return not world.ports[id].has("planet_index")).size() >= Industry.CONSTRUCTION.max_sites:
		return "本星系的轨道站已达上限。"
	var orbit := Celestial.orbit_at(region,pos)
	if orbit < 0:
		return "请在一颗行星的引力圈内选址，泊位须高于地表至少 %d 单位。" % int(Industry.CONSTRUCTION.minimum_altitude)
	var heading := pos.angle_to_point(region.planets[orbit].pos)
	var site := {"pos":pos,"berth_heading":heading,"module":kind,"build":terms.days,"modules":[],"system":vessel.system,"id":world.next_id}
	var offset := StationGeometry.berth_for_core(site,Vector2.ZERO,heading)
	if Vector2(region.planets[orbit].pos).distance_to(pos-offset) > Celestial.gravity_radius(region,region.planets[orbit]):
		return "该处泊位过于靠近引力圈外沿，须将空间站核心置于行星引力圈内。"
	var planned := StationDesign.cells(site) if cells.is_empty() else cells
	return design_issue(world,site,planned)

static func deploy(world, kind: int, pos: Vector2, cells: Array = []) -> int:
	if not construction_issue(world,kind,pos,cells).is_empty():
		return 0
	var vessel: Dictionary = world.ride()
	var region: Dictionary = world.systems[vessel.system]
	var orbit := Celestial.orbit_at(region,pos)
	var heading := pos.angle_to_point(region.planets[orbit].pos)
	var builder := build_ship_for(world,pos)
	var terms: Dictionary = Industry.CONSTRUCTION.foundation
	var port_id: int = world.port(vessel.system, "%s · %s站 %s" % [world.active().house, world.MODULES[kind], world.next_id], pos, world.active().flag, world.player, kind, false)
	world.credit(world.player,-int(terms.credits),world.ports[port_id],"设立工地")
	world.ports[port_id].orbit = orbit
	world.ports[port_id].berth_heading = heading
	world.ports[port_id].design_cells = StationDesign.cells(world.ports[port_id]) if cells.is_empty() else cells.duplicate()
	world.ports[port_id].construction_ship = builder
	world.ports[port_id].scan = true
	world.ports[port_id].build = int(terms.days)
	if world.ships[builder].has("construction_contract"):
		world.ConstructionContract.assign_site(world,builder,port_id)
	world.event("已铺设工地，运齐材料后施工 %d 日。" % int(terms.days))
	return port_id

static func build_requirements(station: Dictionary) -> Dictionary:
	if station.build > 0:
		return Industry.FOUNDATION
	if station.expansion > 0:
		return Industry.EXPANSION
	return {}

static func build_funded(station: Dictionary) -> bool:
	return Industry.station_data(station).construction_funded(build_requirements(station))

static func fund_from_ship(vessel: Dictionary, station: Dictionary) -> int:
	var total := 0
	var bill := build_requirements(station)
	var inventory := Industry.station_data(station)
	for ware in bill:
		var moved := inventory.deliver_construction(ware,vessel.cargo[ware],bill)
		vessel.cargo[ware] -= moved
		total += moved
	return total

static func donate(world, port_id: int) -> int:
	var vessel: Dictionary = world.ride()
	var station: Dictionary = world.ports.get(port_id, {})
	if vessel.is_empty() or vessel.dock != port_id or station.is_empty() or not world.oversees(station.owner):
		return 0
	return fund_from_ship(vessel,station)

static func redesign(world, port_id: int, cells: Array) -> bool:
	var station: Dictionary = world.ports.get(port_id,{})
	var vessel: Dictionary = world.ride()
	if station.is_empty() or vessel.get("dock",0) != port_id or not world.oversees(station.owner):
		return false
	if not design_issue(world,station,cells).is_empty():
		return false
	station.design_cells = cells.duplicate()
	return true

static func expansion_cell(world, station: Dictionary, kind: int, existing: Array) -> Vector2i:
	if kind not in range(world.MODULES.size()):
		return StationDesign.AUTO
	var draft := station.duplicate()
	draft.extension = kind
	draft.expansion = int(Industry.CONSTRUCTION.expansion.days)
	for candidate: Vector2i in StationDesign.DEFAULT_CELLS:
		if design_issue(world,draft,existing + [candidate]).is_empty():
			return candidate
	return StationDesign.AUTO

static func expand(world, port_id: int, kind: int, cell: Vector2i = StationDesign.AUTO, revised_cells: Array = []) -> bool:
	var vessel: Dictionary = world.ride()
	var station: Dictionary = world.ports.get(port_id, {})
	if kind not in range(world.MODULES.size()) or vessel.is_empty() or station.is_empty() or vessel.dock != station.id or not world.oversees(station.owner):
		return false
	var terms: Dictionary = Industry.CONSTRUCTION.expansion
	if station.build > 0 or station.expansion > 0 or station.modules.size() >= Industry.CONSTRUCTION.max_modules or world.active().wallet < terms.credits:
		return false
	var draft := station.duplicate()
	draft.extension = kind
	draft.expansion = int(terms.days)
	var installed := StationDesign.cells(station) if revised_cells.is_empty() else revised_cells
	if cell == StationDesign.AUTO:
		cell = expansion_cell(world,station,kind,installed)
	var planned := installed + [cell]
	if cell == StationDesign.AUTO or not design_issue(world,draft,planned).is_empty():
		return false
	world.credit(world.player,-int(terms.credits),station,"扩建")
	station.extension = kind
	station.expansion = int(terms.days)
	station.design_cells = planned
	fund_from_ship(vessel,station)
	return true

static func assign(world, ship_id: int, person_id: int, kind: String, source: int = 0, target: int = 0) -> bool:
	var vessel: Dictionary = world.ships.get(ship_id, {})
	var worker: Dictionary = world.people.get(person_id, {})
	if vessel.is_empty() or worker.is_empty() or not world.oversees(world.ship_principal(vessel)) or vessel.captain == world.player:
		return false
	if not worker.alive or worker.id == world.player or world.reports_to(worker) not in [0, world.ship_principal(vessel)]:
		return false
	if vessel.captain != person_id and (worker.ship != 0 or worker.loc != world.active().loc or worker.loc != vessel.dock or vessel.dock == 0):
		return false
	if kind in ["贸易", "采矿"] and (source == target or not world.ports.has(source) or not world.ports.has(target)):
		return false
	if kind not in ["贸易","采矿","自动贸易","自动采矿","护航","停泊待命","巡逻"]:
		return false
	if kind in ["停泊待命","巡逻"] and not world.ports.has(source):
		return false
	if vessel.captain == person_id and kind in ["自动贸易","自动采矿"] and vessel.job.get("automatic",false) and vessel.job.get("kind","") == kind.trim_prefix("自动") and not vessel.has("commander_id"):
		return true
	if worker.employer == 0 and (vessel.captain != person_id or not vessel.has("firm")):
		if player_funds(world,vessel) < 55:
			return false
		player_pay(world,vessel,-55,"船长招募")
		world.credit(person_id, 55)
	if vessel.captain not in [0, person_id]:
		world.people[vessel.captain].ship = 0
		world.people[vessel.captain].loc = vessel.dock
	worker.employer = vessel.owner
	worker.ship = ship_id
	vessel.captain = person_id
	if vessel.get("order_queue",[]).is_empty():
		release_reservation(world,vessel)
		vessel.travel = {}
	vessel.erase("commander_id")
	vessel.erase("fleet_role")
	vessel.erase("resume_job")
	if kind in ["自动贸易","自动采矿"]:
		vessel.job = {"kind":kind.trim_prefix("自动"),"automatic":true,"label":kind,"phase":0}
		OperatingArea.apply_next(vessel)
		OperatingArea.anchor(world,vessel)
	elif kind in ["停泊待命","巡逻"]:
		vessel.job = {"kind":kind,"source":source,"system":world.ports[source].system}
	else:
		vessel.job = {"kind":kind,"source":source,"target":target,"phase":0,"system":vessel.system}
	vessel.default_behavior = vessel.job.duplicate(true)
	world.event("%s 接管%s，任务：%s。" % [worker.name, world.HULLS[vessel.kind], kind])
	return true

static func hire_remote_captain(world, ship_id: int, kind: String = "停泊待命", home_port: int = 0) -> bool:
	var vessel: Dictionary = world.ships.get(ship_id, {})
	if vessel.is_empty() or not world.oversees(world.ship_principal(vessel)) or vessel.captain != 0:
		return false
	if player_funds(world,vessel) < 85:
		return false
	if kind in ["站属贸易","站属采矿"]:
		var home: Dictionary = world.ports.get(home_port,{})
		if home.is_empty() or (home.firm != vessel.firm if vessel.has("firm") else home.owner != vessel.owner):
			return false
	var officer_id: int = world.random_person(vessel.flag, vessel.dock)
	var officer: Dictionary = world.people[officer_id]
	officer.employer = vessel.owner
	officer.ship = ship_id
	officer.loc = vessel.dock
	player_pay(world,vessel,-85,"船长招募")
	world.credit(officer_id, 85)
	vessel.captain = officer_id
	if vessel.get("order_queue", []).is_empty():
		release_reservation(world, vessel)
		vessel.travel = {}
	vessel.erase("commander_id")
	vessel.erase("fleet_role")
	vessel.erase("resume_job")
	if kind == "护航":
		vessel.job = {"kind":"护航","source":0,"target":0,"phase":0,"system":vessel.system}
		var lead_id: int = world.ride().get("id", 0)
		if lead_id > 0 and lead_id != ship_id:
			vessel.commander_id = lead_id
			vessel.fleet_role = "INTERCEPT"
	elif kind in ["站属贸易", "站属采矿"] and world.ports.has(home_port):
		vessel.job = {"kind":kind,"home_port":home_port,"automatic":true,"label":kind,"phase":0}
	else:
		var sys_ports: Array = world.systems[vessel.system].ports
		var fallback_port: int = int(sys_ports[0]) if not sys_ports.is_empty() else (int(world.systems[0].ports[0]) if not world.systems[0].ports.is_empty() else int(world.ports.keys()[0]))
		var dock_port: int = home_port if world.ports.has(home_port) else (vessel.dock if vessel.dock != 0 else fallback_port)
		vessel.job = {"kind":"停泊待命","source":dock_port,"system":world.ports[dock_port].system}
	vessel.default_behavior = vessel.job.duplicate(true)
	world.event("%s 赴任%s船长，任务：%s。" % [officer.name, world.HULLS[vessel.kind], kind])
	return true

static func assign_station_duty(world, ship_id: int, port_id: int, kind: String) -> bool:
	var vessel: Dictionary = world.ships.get(ship_id, {})
	var home: Dictionary = world.ports.get(port_id, {})
	if vessel.is_empty() or home.is_empty() or home.build > 0 or not world.oversees(world.ship_principal(vessel)) or vessel.captain in [0, world.player]:
		return false
	if vessel.has("firm") and home.firm != vessel.firm:
		return false
	if not vessel.has("firm") and home.owner != vessel.owner and not world.Dividends.can_manage(world, home):
		return false
	if kind not in ["站属贸易", "站属采矿", "巡逻"]:
		return false
	if vessel.get("order_queue", []).is_empty():
		release_reservation(world, vessel)
		vessel.travel = {}
	vessel.erase("commander_id")
	vessel.erase("fleet_role")
	vessel.erase("resume_job")
	if kind == "巡逻":
		vessel.job = {"kind": "巡逻", "source": port_id, "outbound": true, "label": "巡逻"}
	else:
		vessel.job = {"kind":kind,"home_port":port_id,"automatic":true,"label":kind,"phase":0}
	OperatingArea.apply_next(vessel)
	OperatingArea.anchor(world,vessel)
	vessel.operating_area.port = port_id
	vessel.operating_area.system = home.system
	vessel.default_behavior = vessel.job.duplicate(true)
	world.event("%s 已指派为 %s 执行%s。" % [world.HULLS[vessel.kind], home.name, kind])
	return true

static func buy_and_assign_to_station(world, port_id: int, kind: int, duty_kind: String, expected_price: int = -1) -> int:
	var station: Dictionary = world.ports.get(port_id, {})
	if station.is_empty() or station.build > 0 or duty_kind not in ["站属贸易", "站属采矿", "巡逻"]:
		return 0
	if not world.oversees(station.owner) and not world.oversees(station.get("manager", 0)) and not world.Dividends.can_manage(world, station):
		return 0
	if station.hulls[kind] <= 0 or not Hulls.model_limit(station, kind):
		return 0
	var quote := ship_quote(station, kind)
	if world.active().wallet < int(quote.price) + 55:
		return 0
	var new_id := buy_ship(world, port_id, kind, expected_price)
	if new_id == 0:
		return 0
	var vessel: Dictionary = world.ships[new_id]
	var busy_roles := {}
	for f in world.factions.values():
		if f.get("alive", false):
			busy_roles[int(f.get("leader", 0))] = true
	for st in world.ports.values():
		busy_roles[int(st.get("manager", 0))] = true
	for fm in world.firms.values():
		busy_roles[int(fm.get("director", 0))] = true
	var candidate := 0
	for p in world.people.values():
		if p.alive and int(p.loc) == port_id and int(p.ship) == 0 and int(p.employer) == 0 and int(p.id) != world.player and not busy_roles.has(int(p.id)) and world.Politics.age(world, p) >= 18:
			candidate = int(p.id)
			break
	if candidate == 0:
		candidate = world.random_person(int(station.flag), port_id)
	world.credit(world.player, -55, vessel, "招募船长")
	world.credit(candidate, 55)
	var cap: Dictionary = world.people[candidate]
	cap.employer = vessel.owner
	cap.ship = new_id
	cap.loc = port_id
	vessel.captain = candidate
	if not assign_station_duty(world, new_id, port_id, duty_kind):
		return 0
	return new_id

static func lease_daily_rent(station: Dictionary, vessel: Dictionary) -> int:
	var hull_price := int(Industry.ship_quote(station, Hulls.MODELS[vessel.kind]).price)
	return maxi(15, ceili(hull_price * 0.005))

static func set_station_job(world, vessel: Dictionary, home: Dictionary, kind: String) -> void:
	if vessel.get("order_queue", []).is_empty():
		release_reservation(world, vessel)
		vessel.travel = {}
	vessel.erase("commander_id")
	vessel.erase("fleet_role")
	vessel.erase("resume_job")
	vessel.job = {"kind":kind,"home_port":home.id,"automatic":true,"label":kind,"phase":0}
	OperatingArea.apply_next(vessel)
	OperatingArea.anchor(world,vessel)
	vessel.operating_area.port = home.id
	vessel.operating_area.system = home.system
	vessel.default_behavior = vessel.job.duplicate(true)

static func transfer_ship_to_station(world, ship_id: int, port_id: int, kind: String = "站属贸易") -> bool:
	var vessel: Dictionary = world.ships.get(ship_id, {})
	var home: Dictionary = world.ports.get(port_id, {})
	if vessel.is_empty() or home.is_empty() or home.build > 0 or not world.oversees(vessel.owner):
		return false
	if world.active().ship == ship_id or vessel.captain in [0, world.player] or kind not in ["站属贸易", "站属采矿"]:
		return false
	if not world.Dividends.can_manage(world, home) and home.owner != vessel.owner:
		return false
	vessel.erase("lease")
	vessel.owner = 0
	vessel.station_owner = port_id
	vessel.flag = home.flag
	set_station_job(world, vessel, home, kind)
	world.event("%s 已完全归属 %s（%s）。" % [world.HULLS[vessel.kind], home.name, kind])
	return true

static func lease_ship_to_station(world, ship_id: int, port_id: int, kind: String = "站属贸易") -> bool:
	var vessel: Dictionary = world.ships.get(ship_id, {})
	var home: Dictionary = world.ports.get(port_id, {})
	if vessel.is_empty() or home.is_empty() or home.build > 0 or not world.oversees(vessel.owner):
		return false
	if world.active().ship == ship_id or vessel.captain in [0, world.player] or kind not in ["站属贸易", "站属采矿"]:
		return false
	if not allowed(world, vessel, home) or world.enemy(world.people[vessel.owner], home):
		return false
	var rent := lease_daily_rent(home, vessel)
	if world.Treasury.available(home) < rent:
		return false
	vessel.erase("station_owner")
	vessel.lease = {"port":port_id,"lessor":vessel.owner,"daily_rent":rent,"started":world.day}
	set_station_job(world, vessel, home, kind)
	world.event("%s 已租赁给 %s（%s，日租 ¢%d）。" % [world.HULLS[vessel.kind], home.name, kind, rent])
	return true

static func end_ship_lease(world, ship_id: int) -> bool:
	var vessel: Dictionary = world.ships.get(ship_id, {})
	if vessel.is_empty() or not vessel.has("lease") or not world.oversees(vessel.owner):
		return false
	var lease_port := int(vessel.lease.get("port", vessel.dock))
	vessel.erase("lease")
	if vessel.get("order_queue", []).is_empty():
		release_reservation(world, vessel)
		vessel.travel = {}
	vessel.job = {"kind":"停泊待命","source":lease_port,"automatic":false}
	vessel.default_behavior = vessel.job.duplicate(true)
	world.event("已终止 %s 的空间站租赁，飞船已收回。" % world.HULLS[vessel.kind])
	return true

static func daily_leases(world) -> void:
	for vessel: Dictionary in world.ships.values():
		var st_owner := int(vessel.get("station_owner", 0))
		if st_owner > 0:
			var st: Dictionary = world.ports.get(st_owner, {})
			if st.is_empty():
				vessel.erase("station_owner")
			else:
				vessel.flag = st.flag
		if not vessel.has("lease"):
			continue
		var lease: Dictionary = vessel.lease
		var home: Dictionary = world.ports.get(int(lease.get("port", 0)), {})
		var lessor := int(lease.get("lessor", 0))
		var rent := int(lease.get("daily_rent", 0))
		var valid: bool = not home.is_empty() and home.build == 0 and vessel.owner == lessor and world.people.has(lessor) and rent > 0
		if valid and world.Treasury.post(world, home, -rent, "飞船租金", true):
			world.credit(lessor, rent)
			world.Finances.record(world, lessor, home, "飞船租金", rent, false, false)
		else:
			var lease_port := int(lease.get("port", vessel.dock))
			vessel.erase("lease")
			if vessel.get("order_queue", []).is_empty():
				release_reservation(world, vessel)
				vessel.travel = {}
			vessel.job = {"kind":"停泊待命","source":lease_port,"automatic":false}
			vessel.default_behavior = vessel.job.duplicate(true)
			if not home.is_empty():
				world.event("%s 因资金或状态原因终止了 %s 的租赁。" % [home.name, world.HULLS[vessel.kind]])

static func manager(world, port_id: int, person_id: int) -> bool:
	var station: Dictionary = world.ports.get(port_id, {})
	var worker: Dictionary = world.people.get(person_id, {})
	var can_appoint: bool = world.oversees(station.get("owner", 0)) or world.oversees(world.firms.get(station.get("firm", 0), {}).get("director", 0))
	if station.is_empty() or worker.is_empty() or not can_appoint or station.build != 0 or not worker.alive:
		return false
	if person_id == world.player:
		if station.manager != 0 and station.manager != world.player:
			world.people[station.manager].employer = 0
		station.manager = world.player
		return true
	if world.active().wallet < 45 or worker.loc != world.active().loc or worker.loc == 0 or worker.ship != 0 or worker.employer != 0:
		return false
	for flag in world.factions:
		if world.factions[flag].leader == worker.id:
			return false
	for other in world.ports:
		if world.ports[other].manager == person_id:
			return false
	if station.manager != 0 and station.manager != world.player:
		world.people[station.manager].employer = 0
	world.credit(world.player, -45,station,"站长招募")
	world.credit(person_id, 45)
	worker.employer = station.owner if station.owner != 0 else world.player
	worker.loc = port_id
	station.manager = person_id
	return true

## A public port with a persistent shortage can fund a local production line.
static func plan_provisions(world, station: Dictionary, inventory: StationData) -> void:
	if station.has("planet_index") or station.owner != 0 or station.firm != 0 or station.manager == world.player or station.get("blockaded",false) or station.get("coalition_blockade",false):
		return
	var mgr: Dictionary = world.people.get(station.manager, {})
	var mgr_traits: Array = mgr.get("ck_traits", [])
	var threshold := 12
	if "仁慈" in mgr_traits or (not mgr.is_empty() and mgr.stats.stewardship >= 10):
		threshold = 8
	elif "贪婪" in mgr_traits:
		threshold = 20
	if station.shortage < threshold:
		return
	if station.expansion > 0 or station.modules.size() >= Industry.CONSTRUCTION.max_modules:
		return
	var water := Industry.Ware.WATER
	var food := Industry.Ware.RATIONS
	var buffer := provisions_for(station,60)
	var need_water: bool = inventory.available(water)+inventory.incoming(water) < buffer and not station.get("surface_yields",{}).has(water)
	var need_food: bool = inventory.available(food)+inventory.incoming(food) < buffer and not station.get("surface_yields",{}).has(food)
	if not need_water and not need_food:
		return
	var kind := -1
	if inventory.available(Industry.Ware.ENERGY) <= int(Industry.EXPANSION[Industry.Ware.ENERGY])+6 and Industry.Module.SOLAR not in station.modules:
		kind = Industry.Module.SOLAR
	elif need_water and inventory.available(Industry.Ware.ICE) < 4 and Industry.Module.MINE not in station.modules and world.systems[station.system].get("deposits",{}).get(Industry.Ware.ICE,0) > 0:
		kind = Industry.Module.MINE
	elif need_water and Industry.Module.CHEMICAL not in station.modules and inventory.available(Industry.Ware.ICE) >= 4:
		kind = Industry.Module.CHEMICAL
	elif need_food and Industry.Module.HABITAT not in station.modules and inventory.available(water) > provisions_for(station,12):
		kind = Industry.Module.HABITAT
	if kind < 0:
		return
	var bill: Dictionary = Industry.EXPANSION
	var terms: Dictionary = Industry.CONSTRUCTION.expansion
	if world.Treasury.available(station) < int(terms.credits)+buffer*price(station,food,true):
		return
	for ware: int in bill:
		if inventory.available(ware) < inventory.construction_needed(ware,bill,false):
			return
	var cells := StationDesign.cells(station)
	var cell := expansion_cell(world,station,kind,cells)
	if cell == StationDesign.AUTO or not world.Treasury.post(world,station,-int(terms.credits),"民生扩建"):
		return
	for ware: int in bill:
		var moved := inventory.withdraw(ware,inventory.construction_needed(ware,bill,false))
		inventory.deliver_construction(ware,moved,bill)
	station.design_cells = cells+[cell]
	station.extension = kind
	station.expansion = int(terms.days)

static func produce(world, station: Dictionary) -> void:
	if station.get("landing_only",false):
		return
	var inventory := Industry.station_data(station)
	if station.build > 0:
		var builder: Dictionary = world.ships.get(station.get("construction_ship",0),{})
		if station.has("construction_ship") and (builder.is_empty() or builder.layer or builder.system != station.system or builder.locked or Vector2(builder.pos).distance_to(station.pos) > float(Industry.CONSTRUCTION.ship_work_range)):
			return
		if inventory.construction_funded(Industry.FOUNDATION):
			station.build = maxi(0, station.build - 6)
			if station.build == 0:
				inventory.consume_construction(Industry.FOUNDATION)
				station.modules.append(station.module)
				if not station.has("equity"):
					world.Capital.register_site(station)
				Industry.update_market(station)
				world.event(station.name + "竣工。")
				if builder.has("construction_contract"):
					world.ConstructionContract.advance(world,builder)
		return
	if world.day % 30 == 0 and station.expansion == 0:
		plan_provisions(world,station,inventory)
	elif station.expansion > 0 and inventory.construction_funded(Industry.EXPANSION):
		station.expansion = maxi(0, station.expansion - 6)
		if station.expansion == 0:
			inventory.consume_construction(Industry.EXPANSION)
			station.modules.append(station.extension)
			Industry.update_market(station)
			station.pop_cap += int(Industry.CONSTRUCTION.housing_expansion if station.extension == Industry.Module.HABITAT else Industry.CONSTRUCTION.standard_expansion)
			station.extension = -1
			world.event("%s 的扩建模块竣工。" % station.name)
	if station.has("surface_yields"):
		world.PlanetPorts.harvest(station,inventory)
	var yard_slot := 0
	for kind in station.modules:
		if kind == Industry.Module.YARD:
			shipyard(world, station, inventory, yard_slot)
			yard_slot += 1
		else:
			run_module(world, station, kind, inventory)
	_restock_black_luxury(world, station, inventory)
	_distribute_black_profits(world, station)

static func _distribute_black_profits(world, station: Dictionary) -> void:
	if world.day % 30 != 0 or station.build > 0 or station.black.is_empty():
		return
	var reserve := int(Industry.RULES.station_capital.get("black_cash", 1800))
	var excess := int(station.get("black_treasury", 0)) - reserve
	if excess < 80:
		return
	var mgr_id := int(station.get("manager", 0))
	if mgr_id != 0 and mgr_id != world.player and world.people.has(mgr_id):
		var mgr: Dictionary = world.people[mgr_id]
		var traits: Array = mgr.get("ck_traits", [])
		var greedy: bool = "贪婪" in traits or "狡诈" in traits or int(mgr.get("personality", {}).get("greed", 0)) >= 25
		if mgr.alive and greedy:
			var cut := floori(excess * 0.30)
			if cut > 0:
				station.black_treasury = int(station.black_treasury) - cut
				world.credit(mgr_id, cut)
				excess -= cut
				var secrets: Array = mgr.get("secrets", [])
				if not secrets.any(func(s): return s is Dictionary and s.get("kind", "") == "smuggling"):
					secrets.append({"kind": "smuggling", "port": int(station.id), "day": world.day})
					mgr.secrets = secrets
	if excess >= 60:
		var boss: Dictionary = world.Outlaws.boss_for(world, world.Outlaws.PIRATES)
		if not boss.is_empty() and boss.get("alive", false):
			var boss_cut := floori(excess * 0.50)
			if boss_cut > 0:
				station.black_treasury = int(station.black_treasury) - boss_cut
				world.credit(int(boss.id), boss_cut)

static func _restock_black_luxury(world, station: Dictionary, inventory: StationData) -> void:
	if world.day % 12 != 0 or station.build > 0 or station.black.is_empty():
		return
	var lux := Industry.Ware.LUXURY
	if int(station.black[lux]) >= 12:
		return
	var has_craft: bool = (Industry.Module.HABITAT in station.modules or Industry.Module.CHEMICAL in station.modules) and (Industry.Module.ELECTRONICS in station.modules or int(station.pop) >= 600)
	if not has_craft:
		return
	var food := Industry.Ware.RATIONS
	var elec := Industry.Ware.ELECTRONICS
	if inventory.available(food) < 25 or inventory.available(elec) < 8:
		return
	var cost := price(station, food, true) + price(station, elec, true)
	if int(station.get("black_treasury", 0)) < cost + 120:
		return
	if inventory.consume({food: 1, elec: 1}):
		station.black_treasury = int(station.get("black_treasury", 0)) - cost
		world.Treasury.post(world, station, cost, "黑市原料采购", false)
		station.black[lux] = int(station.black[lux]) + 2

static func order_hull(world, port_id: int, kind: int) -> bool:
	var station: Dictionary = world.ports.get(port_id,{})
	var vessel: Dictionary = world.ride()
	if station.is_empty() or not world.oversees(station.owner) or vessel.is_empty() or vessel.dock != port_id:
		return false
	if Industry.Module.YARD not in station.modules or station.build > 0 or kind not in range(Hulls.MODELS.size()) or not Hulls.model_limit(station,kind):
		return false
	if not supports_method(kind,station.method):
		return false
	return Industry.station_data(station).enqueue_hull(kind,12)

static func shipyard(world, station: Dictionary, inventory: StationData = null, slipway: int = 0) -> void:
	if world.day % 30 != 0:
		return
	if inventory == null:
		inventory = Industry.station_data(station)
	# Reserve this month's available worker shifts. Each YARD module (slipway) builds at most 1 hull at a time.
	if station.get("yard_labor_day",-1) != world.day:
		var market: Dictionary = Industry.RULES.ship_market
		station.yard_hours = floori(station.pop * float(market.shipyard_workforce_share)) * int(market.worker_hours_per_month)
		station.yard_labor_day = world.day
	if station.yard_hours <= 0:
		return
	var current: Dictionary = station.get("yard_work",{}) if slipway == 0 else station.get("yard_works",{}).get(slipway,{})
	var ordered: int = inventory.order_at(0) if inventory.order_count() > 0 else -1
	var start: int = current.get("kind",ordered)
	var selected := start >= 0
	if not selected:
		start = (int(world.day / 30) + int(station.id) + slipway) % Hulls.MODELS.size()
	for offset in range(1 if selected else Hulls.MODELS.size()):
		var model := (start + offset) % Hulls.MODELS.size()
		if not Hulls.model_limit(station,model) or not supports_method(model,station.method):
			continue
		if not selected and inventory.hull_stock(model) >= (1 if Hulls.MODELS[model].size == Hulls.Size.CAPITAL else 3):
			continue
		var bill := Industry.vessel_recipe(Hulls.MODELS[model],station.method)
		if not bill.keys().all(func(ware): return inventory.available(ware) >= bill[ware]):
			continue
		var required := Industry.labor_hours(Hulls.MODELS[model],station.method)
		var done := int(current.get("hours",0))
		var cash: int = world.Treasury.available(station)
		if cash == 0:
			return
		var paid := Industry.labor_charge(done)
		var funded_hours := floori((paid+cash) / float(Industry.RULES.ship_market.shipwright_hourly_wage))
		var labor := mini(station.yard_hours,mini(required,funded_hours)-done)
		if labor <= 0:
			return
		var wages := Industry.labor_charge(done+labor) - paid
		if not world.Treasury.post(world,station,-wages,"造船工人工资"):
			return
		station.yard_hours -= labor
		if done + labor < required:
			var prog := {"kind":model,"hours":done+labor,"required":required}
			if slipway == 0:
				station.yard_work = prog
			else:
				station.get_or_add("yard_works",{})[slipway] = prog
		elif inventory.complete_hull(model,bill,model == ordered):
			if slipway == 0:
				station.erase("yard_work")
			elif station.has("yard_works"):
				station.yard_works.erase(slipway)
		return

static func run_module(world, station: Dictionary, kind: int, inventory: StationData = null) -> void:
	if inventory == null:
		inventory = Industry.station_data(station)
	var field: Dictionary = world.systems[station.system]
	var manager_data: Dictionary = world.people.get(station.manager,{})
	var management := float(manager_data.stats.stewardship) if not manager_data.is_empty() else 6.0
	var efficiency := 1.0
	if station.shortage == 0 and Industry.Module.HABITAT in station.modules:
		efficiency += clampf(float(station.pop) / station.pop_cap,0,1) * clampf(0.25 + management * 0.015,0.25,0.6)
	if kind == Industry.Module.YARD:
		shipyard(world,station,inventory)
	elif kind == Industry.Module.SOLAR:
		var room := inventory.production_space(Industry.Ware.ENERGY,Industry.PROVISION_STOCK_TARGETS)
		inventory.deposit(Industry.Ware.ENERGY,mini(room,roundi((28 + 12 * float(field.star)) * efficiency)))
	elif kind == Industry.Module.MINE:
		if not field.has("deposits"):
			field.deposits = {Industry.Ware.SILICON:180,Industry.Ware.GAS:180,Industry.Ware.ICE:180}
		var ore := inventory.deposit(Industry.Ware.ORE,mini(int(field.ore),roundi(10 * efficiency)))
		field.ore -= ore
		record_mining(world,station.system,ore)
		for ware in field.deposits:
			var mined := inventory.deposit(ware,mini(int(field.deposits[ware]),roundi(5 * efficiency)))
			field.deposits[ware] -= mined
	elif kind == Industry.Module.DEFENSE:
		if station.defense < 78 and inventory.consume({Industry.Ware.ALLOY:2}):
			station.defense += 4
	else:
		var reserve := provisions_for(station,90)
		for recipe: StationData.Recipe in Industry.RECIPES[kind]:
			var keep := reserve
			if recipe.output == Industry.Ware.RATIONS:
				var food := inventory.available(Industry.Ware.RATIONS)
				var water := inventory.available(Industry.Ware.WATER)
				if food < reserve and water > food:
					# Converting one water into four rations should leave both stocks usable.
					keep = mini(keep,maxi(1,water-ceili(float(water-food)/(recipe.units+1))))
			inventory.process_recipe(recipe,efficiency,Industry.PROVISION_STOCK_TARGETS,keep)

static func record_mining(world, system_id: int, amount: int) -> void:
	if amount > 0 and system_id >= 2 and system_id < world.systems.size():
		var field: Dictionary = world.systems[system_id]
		field.mining_heat = mini(300, int(field.get("mining_heat",0)) + amount)

static func pay_maintenance(world, vessel: Dictionary) -> void:
	if vessel.dock == 0 or not vessel.battle.has("cr"):
		return
	var station: Dictionary = world.ports.get(vessel.dock,{})
	if station.is_empty() or station.build > 0 or not allowed(world,vessel,station):
		return
	if vessel.battle.cr < 0.999 or vessel.battle.battle_seconds > 0:
		var rations := maxi(1,ceili(float(Hulls.MODELS[vessel.kind].get("upkeep",3))/6.0))
		if Industry.consume(station,{Industry.Ware.RATIONS:rations}):
			vessel.battle.cr = minf(1,vessel.battle.cr+0.03)
			vessel.battle.battle_seconds = maxf(0,vessel.battle.battle_seconds-30)
	var magazines: Array = vessel.battle.get("magazines",[])
	for i in range(mini(magazines.size(),vessel.fit.weapons.size())):
		var spec: Dictionary = Hulls.WEAPONS.get(vessel.fit.weapons[i],{})
		var capacity: int = spec.get("ammo",0)
		if capacity > 0 and float(magazines[i]) < capacity and Industry.consume(station,{Industry.Ware.ORDNANCE:1}):
			magazines[i] = minf(capacity,float(magazines[i])+4.0)

static func operating_port(world, vessel: Dictionary) -> Dictionary:
	var job: Dictionary = vessel.get("job",{})
	if job.get("kind","") not in ["站属贸易","站属采矿"]:
		return {}
	var station: Dictionary = world.ports.get(job.get("home_port",0),{})
	if station.is_empty() or station.build > 0:
		return {}
	if int(vessel.get("station_owner",0)) == station.id:
		return station
	if int(vessel.get("lease",{}).get("port",0)) == station.id:
		return station
	if vessel.has("firm"):
		return station if station.firm == vessel.firm else {}
	if station.get("owner",-1) == vessel.owner:
		return station
	if vessel.owner != 0 and (station.manager == vessel.owner or world.firms.get(station.firm,{}).get("director",0) == vessel.owner):
		return station
	return station if world.oversees(vessel.owner) and world.Dividends.can_manage(world, station) else {}

static func personal_operator(vessel: Dictionary) -> bool:
	return vessel.owner == 0 and not vessel.has("firm") and not vessel.has("station_owner") and not vessel.job.has("home_port")

static func player_funds(world, vessel: Dictionary) -> int:
	return world.active().wallet if personal_operator(vessel) else account_balance(world,vessel)

static func player_pay(world, vessel: Dictionary, amount: int, category: String) -> void:
	if personal_operator(vessel):
		world.credit(world.player,amount,vessel,category)
	else:
		pay(world,vessel,amount,category)

static func account_balance(world, vessel: Dictionary, except_order: int = 0) -> int:
	var home := operating_port(world,vessel)
	if not home.is_empty():
		return world.Treasury.available(home,except_order)
	if vessel.has("firm"):
		return world.firms[vessel.firm].treasury
	if vessel.has("charter"):
		return world.people.get(vessel.charter.operator,{}).get("wallet",0)
	if vessel.owner == 0 and world.factions.has(vessel.flag):
		return world.factions[vessel.flag].treasury
	return world.people.get(vessel.owner if vessel.owner != 0 else vessel.captain,{}).get("wallet",0)

## A freight transfer between two wholly owned facilities leaves beneficial ownership unchanged.
static func internal_cargo(world, home: Dictionary, station: Dictionary) -> bool:
	if home.is_empty():
		return false
	if home.id==station.id:
		return true
	var source: Dictionary = world.StationEquity.cap_table(world,home)
	var dest: Dictionary = world.StationEquity.cap_table(world,station)
	if source.total<=0 or dest.total<=0:
		return false
	if source.company>0 and source.company==dest.company and source.company_units==source.total and dest.company_units==dest.total:
		return true
	if source.people.size()!=1 or dest.people.size()!=1:
		return false
	var holder: int = source.people.keys()[0]
	return source.people[holder]==source.total and dest.people.get(holder,0)==dest.total

static func pay(world, vessel: Dictionary, amount: int, category: String, except_order: int = 0) -> void:
	var home := operating_port(world,vessel)
	if not home.is_empty():
		world.Treasury.post(world,home,amount,category,true,except_order)
	elif vessel.has("firm"):
		var firm: Dictionary = world.firms[vessel.firm]
		firm.treasury += amount
		firm.operating_profit += amount
		if amount > 0:
			firm.revenue += amount
		world.Finances.record(world,firm.director,vessel,category,amount)
	elif vessel.has("charter"):
		world.credit(vessel.charter.operator,amount,vessel,category)
	elif vessel.owner == 0 and world.factions.has(vessel.flag):
		world.factions[vessel.flag].treasury += amount
	else:
		world.credit(vessel.owner if vessel.owner != 0 else vessel.captain,amount,vessel,category)

static func release_reservation(world, vessel: Dictionary) -> void:
	var reservation: Dictionary = vessel.get("reservation",{})
	if reservation.is_empty():
		return
	if world.ports.has(reservation.source):
		Industry.station_data(world.ports[reservation.source]).release(StationData.Booking.OUTBOUND,vessel.id)
	if world.ports.has(reservation.target):
		var target := Industry.station_data(world.ports[reservation.target])
		target.release(StationData.Booking.CONSTRUCTION if reservation.get("construction",false) else StationData.Booking.INBOUND,vessel.id)
		world.ports[reservation.target].cash_holds.erase(vessel.id)
	if world.ports.has(reservation.get("payer",0)):
		world.ports[reservation.payer].cash_holds.erase(vessel.id)
	vessel.erase("reservation")

static func clear_assignments(world, vessel: Dictionary) -> void:
	release_reservation(world,vessel)
	if vessel.has("construction_contract") and vessel.captain == 0:
		vessel.erase("construction_contract")
	vessel.job = {}
	vessel.order_queue = []
	vessel.travel = {}
	for key in ["commander_id","fleet_role","mimic_template","default_behavior","resume_job","last_order","route_hold"]:
		vessel.erase(key)

static func forbidden(vessel: Dictionary, station: Dictionary) -> bool:
	var rules: Dictionary = vessel.get("trade_rules",{})
	return station.system in rules.get("activity",[]) or station.system in rules.get("travel",[]) or station.flag in rules.get("trade",[])

static func set_trade_rule(world, ship_id: int, scope: String, subject: int, blocked: bool) -> bool:
	var vessel: Dictionary = world.ships.get(ship_id,{})
	if vessel.is_empty() or not world.oversees(world.ship_principal(vessel)) or scope not in ["travel","activity","trade"]:
		return false
	if scope == "trade":
		if subject != world.NEUTRAL and not world.factions.has(subject):
			return false
	elif subject not in range(world.systems.size()):
		return false
	var rules: Dictionary = vessel.get("trade_rules",{})
	var entries: Array = rules.get(scope,[])
	if blocked and subject not in entries:
		entries.append(subject)
	elif not blocked:
		entries.erase(subject)
	rules[scope] = entries
	vessel.trade_rules = rules
	if blocked:
		var reservation: Dictionary = vessel.get("reservation",{})
		if not reservation.is_empty() and (forbidden(vessel,world.ports[reservation.source]) or forbidden(vessel,world.ports[reservation.target])):
			release_reservation(world,vessel)
			vessel.travel = {}
	return true

static func reserve(world, vessel: Dictionary, source: Dictionary, target: Dictionary, ware: int, requested: int, loading: bool = true, construction: bool = false) -> bool:
	var field_delivery: bool = not loading and vessel.get("job",{}).get("kind","") in ["采矿","站属采矿"] and ware == Industry.Ware.ORE
	if (source.id == target.id and not field_delivery) or ware not in range(Industry.WARES.size()) or requested <= 0 or forbidden(vessel,target):
		return false
	if (loading and (forbidden(vessel,source) or not allowed(world,vessel,source))) or not allowed(world,vessel,target):
		return false
	if not vessel.get("reservation",{}).is_empty():
		return false
	var receiver := Industry.station_data(target)
	var supplier := Industry.station_data(source)
	var capacity := receiver.construction_needed(ware,build_requirements(target)) if construction else receiver.free_space(ware)
	var qty := mini(requested,capacity)
	var home := operating_port(world,vessel)
	var payer_id: int = home.get("id",0)
	var own_source := internal_cargo(world,home,source)
	var own_target := internal_cargo(world,home,target)
	if loading:
		qty = mini(qty,mini(supplier.available(ware),world.cargo_free(vessel)))
		if not own_source:
			qty = lot_quote(source,ware,qty,true,-1,false,account_balance(world,vessel)).x
	else:
		qty = mini(qty,vessel.cargo[ware])
	var buyer_hold := 0
	var fee := 0
	if not construction and not own_target:
		if vessel.job.get("relief_port",0) == target.id and vessel.job.get("ware",-1) == ware:
			fee = relief_rate(world,target,ware)
		var bid := Industry.lot_invoice(target,ware,qty,false,-1,false,world.Treasury.available(target),fee)
		qty = bid.units
		buyer_hold = bid.base+fee*qty
	if qty <= 0:
		return false
	var origin: int = vessel.system
	var position: Vector2 = vessel.pos
	var in_hyperspace: bool = vessel.layer
	var travel_days := 0
	if loading:
		var pickup := trip_plan(world,vessel,origin,position,in_hyperspace,source)
		if pickup.is_empty() or pickup.fuel > 100.0:
			if pickup.is_empty():
				vessel.route_hold = "无安全航线"
			return false
		travel_days += int(pickup.days)
		origin = source.system
		position = source.pos
		in_hyperspace = false
	var delivery := trip_plan(world,vessel,origin,position,in_hyperspace,target,travel_days)
	if delivery.is_empty() or delivery.fuel > 100.0:
		if delivery.is_empty():
			vessel.route_hold = "无安全航线"
		return false
	# Leave room for the six-day dispatch and trading cycles at both berths.
	var until: int = world.day + travel_days + int(delivery.days) + 36
	if loading:
		supplier.reserve(StationData.Booking.OUTBOUND,vessel.id,ware,qty,until)
		if payer_id != 0 and not own_source:
			home.cash_holds[vessel.id] = lot_quote(source,ware,qty,true).y
	if buyer_hold > 0:
		target.cash_holds[vessel.id] = buyer_hold
	receiver.reserve(StationData.Booking.CONSTRUCTION if construction else StationData.Booking.INBOUND,vessel.id,ware,qty,until)
	vessel.reservation = {"source":source.id,"target":target.id,"ware":ware,"qty":qty,"expires":until,"loaded":not loading,"construction":construction,"payer":payer_id}
	if fee > 0:
		vessel.reservation.delivery_fee = fee
	vessel.erase("route_hold")
	return true

static func exchange(world, vessel: Dictionary, station: Dictionary, ware: int, amount: int) -> bool:
	var reservation: Dictionary = vessel.get("reservation",{})
	var inventory := Industry.station_data(station)
	var limit_qty := absi(amount)
	var home := operating_port(world,vessel)
	var internal := internal_cargo(world,home,station)
	if not reservation.is_empty():
		if reservation.ware != ware or station.id != (reservation.source if amount > 0 else reservation.target) or (amount > 0) == bool(reservation.loaded):
			return false
		limit_qty = mini(limit_qty,reservation.qty)
	if amount > 0:
		var loadable := mini(limit_qty,mini(world.cargo_free(vessel),inventory.available(ware,vessel.id)))
		var quote := {"units":loadable} if internal else Industry.lot_invoice(station,ware,loadable,true,-1,false,account_balance(world,vessel,vessel.id))
		var qty := inventory.withdraw(ware,quote.units,vessel.id)
		if qty <= 0:
			return false
		vessel.cargo[ware] += qty
		if not internal:
			pay(world,vessel,-quote.total,"货物采购",vessel.id)
			world.Treasury.market(world,station,quote.base)
			remit_goods_tax(world,station.tariff_flag,quote.tax)
			Diagnostics.transfer(world,vessel,"采购 " + world.WARES[ware],station.name,-quote.total,qty,quote.tax,station.tariff_flag)
		elif Diagnostics.accessible(world,vessel):
			Diagnostics.record(world,vessel,"内部调拨",{"port":station.id,"ware":ware,"units":qty,"loading":true})
		if not reservation.is_empty():
			if not home.is_empty() and home.id != station.id:
				home.cash_holds.erase(vessel.id)
			inventory.release(StationData.Booking.OUTBOUND,vessel.id)
			reservation.loaded = true
			reservation.qty = qty
			var receiver := Industry.station_data(world.ports[reservation.target])
			receiver.update_reservation(StationData.Booking.CONSTRUCTION if reservation.get("construction",false) else StationData.Booking.INBOUND,vessel.id,qty)
		return true
	var unloadable := mini(limit_qty,mini(vessel.cargo[ware],inventory.free_space(ware,vessel.id)))
	var fee: int = reservation.get("delivery_fee",0)
	var quote := {"units":unloadable} if internal else Industry.lot_invoice(station,ware,unloadable,false,-1,false,world.Treasury.available(station,vessel.id),fee)
	var qty := inventory.deposit(ware,quote.units,vessel.id)
	if qty <= 0:
		return false
	vessel.cargo[ware] -= qty
	if not internal:
		world.Treasury.market(world,station,-quote.base,vessel.id)
		pay(world,vessel,quote.total,"货物销售")
		remit_goods_tax(world,station.tariff_flag,quote.tax)
		Diagnostics.transfer(world,vessel,"销售 " + world.WARES[ware],station.name,quote.total,qty,quote.tax,station.tariff_flag)
		if fee > 0 and world.Treasury.post(world,station,-fee*qty,"应急运输",true,vessel.id):
			pay(world,vessel,fee*qty,"应急运输")
			Diagnostics.transfer(world,vessel,"应急运输",station.name,fee*qty,qty)
	elif Diagnostics.accessible(world,vessel):
		Diagnostics.record(world,vessel,"内部调拨",{"port":station.id,"ware":ware,"units":qty,"loading":false})
	release_reservation(world,vessel)
	return true

static func refuel_trader(world, vessel: Dictionary, station: Dictionary, desired: float = 100.0) -> void:
	var internal: bool = operating_port(world,vessel).get("id",0) == station.id
	var units := maxi(0,ceili(desired-vessel.fuel-0.0001))
	var filled := pump_fuel(vessel,station,units if internal else mini(units,account_balance(world,vessel)))
	if not internal:
		pay(world,vessel,-filled,"燃料")
		world.Treasury.post(world,station,filled,"燃料")
		Diagnostics.transfer(world,vessel,"燃料",station.name,-filled,filled)
	if units > 0:
		Diagnostics.record(world,vessel,"请求补油",{"port":station.id,"requested":units,"filled":filled,"tank_after":vessel.fuel})

## Price both legs at the pumps the ship can actually use. A mining field has no pump.
static func freight_budget(world, vessel: Dictionary, first: float, second: float, transfer: Dictionary, funds: int, committed_fuel: int = 0) -> int:
	var tank: float = vessel.fuel
	var home: int = operating_port(world,vessel).get("id",0)
	var pump := 0 if transfer.is_empty() else maxi(0,Industry.available(transfer,Industry.Ware.FUEL)-committed_fuel)
	var depart := maxf(first,first+second-pump)
	if depart > 100.0001 or second > 100.0001:
		return -1
	var fill := maxi(0,ceili(depart-tank-0.0001))
	if fill > 0:
		var port: Dictionary = world.ports.get(vessel.dock,{})
		if port.is_empty() or fill > floori(100-tank) or Industry.available(port,Industry.Ware.FUEL) < fill:
			return -1
		if port.id != home:
			funds -= fill
		tank += fill
	var next := maxi(0,ceili(second-(tank-first)-0.0001))
	if next > pump or next > floori(100.0001-(tank-first)):
		return -1
	if transfer.get("id",0) != home:
		funds -= next
	return funds

static func begin_trip(world, vessel: Dictionary, target: Dictionary, departure_minimum: float = 0.0) -> void:
	var trip := trip_plan(world,vessel,vessel.system,vessel.pos,vessel.layer,target)
	if trip.is_empty() or forbidden(vessel,target):
		Diagnostics.record(world,vessel,"无法启航",{"port":target.id,"reason":"无可用航线或港口受限"})
		release_reservation(world,vessel)
		if MerchantSecurity.commercial(vessel):
			vessel.route_hold = "无安全航线"
		return
	vessel.erase("route_hold")
	var fuel_required := maxf(trip.fuel,departure_minimum)
	if fuel_required > 100.0:
		Diagnostics.record(world,vessel,"航程超过油箱容量",{"port":target.id,"required":fuel_required})
		release_reservation(world,vessel)
		return
	if vessel.fuel + 0.0001 < fuel_required and vessel.dock != 0:
		refuel_trader(world,vessel,world.ports[vessel.dock],fuel_required)
	if vessel.fuel + 0.0001 < fuel_required:
		Diagnostics.record(world,vessel,"启航燃料不足",{"port":target.id,"required":fuel_required,"tank":vessel.fuel,"dock":vessel.dock})
		release_reservation(world,vessel)
		return
	world.depart(vessel)
	vessel.travel = {"port":target.id,"waypoints":trip.route}
	if not vessel.layer:
		vessel.galpos = world.systems[vessel.system].pos

static func trip_plan(world, vessel: Dictionary, origin: int, position: Vector2, in_hyperspace: bool, target: Dictionary, days_before_departure: int = 0, return_to_beacon: bool = false, work_area: Variant = null) -> Dictionary:
	var route := flight_route(world,origin,target.system,vessel.get("trade_rules",{}).get("travel",[]))
	if MerchantSecurity.commercial(vessel):
		if MerchantSecurity.dangerous(world,vessel,target.system):
			return {}
		if MerchantSecurity.threatened_route(world,vessel,route):
			route = flight_route(world,origin,target.system,MerchantSecurity.exclusions(world,vessel))
	if work_area == null and OperatingArea.automatic(vessel):
		work_area = OperatingArea.coverage(world,vessel)
	if work_area != null:
		if not work_area.has(target.system):
			return {}
		if work_area.has(origin) and route.any(func(system): return not work_area.has(system)):
			var outside := []
			for index in world.systems.size():
				if not work_area.has(index):
					outside.append(index)
			route = flight_route(world,origin,target.system,outside)
	if origin != target.system and route.is_empty():
		return {}
	if in_hyperspace and origin == target.system:
		route.append(target.system)
	elif in_hyperspace and (return_to_beacon or vessel.has("route_hold")) and not MerchantSecurity.dangerous(world,vessel,origin) and not Vector2(vessel.galpos).is_equal_approx(world.systems[origin].pos):
		route.push_front(origin)
	var hull: Dictionary = Hulls.MODELS[vessel.kind]
	var speed := clampf(float(hull.speed),0.45,1.4)
	var days := 0
	var distance := 0.0
	if not route.is_empty():
		if not in_hyperspace:
			days += maxi(1,ceili(position.distance_to(Celestial.gravity_point(world.systems[origin])) / (LOCAL_DISTANCE_PER_DAY * speed)))
		var cursor: Vector2 = vessel.galpos if in_hyperspace else world.systems[origin].pos
		for waypoint in route:
			var beacon: Vector2 = world.systems[waypoint].pos
			var hop := cursor.distance_to(beacon)
			distance += hop
			days += maxi(1,ceili(hop / Hyperspace.distance_per_day(hull)))
			cursor = beacon
		days += route.size() - 1
		position = Celestial.gravity_point(world.systems[target.system])
	var local_gap := position.distance_to(target.pos)
	var closing_speed := LOCAL_DISTANCE_PER_DAY * speed
	if target.has("planet_index"):
		var body: Dictionary = world.systems[target.system].planets[target.planet_index]
		var port_speed: float = world.PlanetPorts.approach_speed(body)
		local_gap += (days_before_departure+days)*port_speed
		closing_speed = maxf(1.0,closing_speed-port_speed)
	days += ceili(local_gap / closing_speed)
	return {"route":route,"days":days,"distance":distance,"fuel":Hyperspace.fuel_for_distance(hull,distance)}

static func reroute_merchant(world, vessel: Dictionary, target: Dictionary) -> bool:
	if not MerchantSecurity.commercial(vessel):
		return true
	var voyage: Dictionary = vessel.travel
	if not voyage.has("hold") and not MerchantSecurity.dangerous(world,vessel,target.system) and not MerchantSecurity.threatened_route(world,vessel,voyage.waypoints):
		return true
	var plan := trip_plan(world,vessel,vessel.system,vessel.pos,vessel.layer,target,0,true)
	if plan.is_empty() or plan.fuel > vessel.fuel + 0.0001:
		vessel.route_hold = "无安全航线" if plan.is_empty() else "安全绕航所需燃料不足"
		voyage.hold = true
		voyage.waypoints = []
		if vessel.has("reservation"):
			voyage.rebook = vessel.reservation.duplicate()
		release_reservation(world,vessel)
		return false
	var previous: Dictionary = voyage.get("rebook",{})
	if not previous.is_empty():
		var supplier: Dictionary = world.ports.get(previous.source,{})
		var receiver: Dictionary = world.ports.get(previous.target,{})
		if supplier.is_empty() or receiver.is_empty():
			vessel.travel = {}
			vessel.erase("route_hold")
			return false
		if not reserve(world,vessel,supplier,receiver,previous.ware,previous.qty,not previous.loaded,previous.get("construction",false)):
			vessel.route_hold = "等待收发港重新确认舱位"
			return false
		voyage.erase("rebook")
	voyage.waypoints = plan.route
	voyage.erase("hold")
	vessel.erase("route_hold")
	var booking: Dictionary = vessel.get("reservation",{})
	if not booking.is_empty():
		var remaining := int(plan.days)
		if not booking.loaded and target.id == booking.source:
			var delivery := trip_plan(world,vessel,target.system,target.pos,false,world.ports[booking.target],remaining)
			if delivery.is_empty():
				release_reservation(world,vessel)
				return true
			remaining += int(delivery.days)
		booking.expires = maxi(booking.expires,world.day + remaining + 36)
		if not booking.loaded:
			Industry.station_data(world.ports[booking.source]).reserve(StationData.Booking.OUTBOUND,vessel.id,booking.ware,booking.qty,booking.expires)
		var inbound := StationData.Booking.CONSTRUCTION if booking.get("construction",false) else StationData.Booking.INBOUND
		Industry.station_data(world.ports[booking.target]).reserve(inbound,vessel.id,booking.ware,booking.qty,booking.expires)
	return true

static func flight_graph(world) -> Dictionary:
	var graph: Dictionary = world.get_meta("trade_navigation",{})
	if graph.is_empty():
		graph = {"navigation":AStar2D.new(),"coverage":{}}
		world.set_meta("trade_navigation",graph)
	var navigation: AStar2D = graph.navigation
	if navigation.get_point_count() == world.systems.size():
		return graph
	var core_reach := float(Celestial.Scale.data.core_beacon_spacing[1])
	var reach: float = world.CHUNK_SIZE * 2.0
	for i in range(navigation.get_point_count(),world.systems.size()):
		var point: Vector2 = world.systems[i].pos
		var cell: Vector2i = world.chunk_at(point)
		navigation.add_point(i,point)
		for j in world.systems_in(Rect2(point,Vector2.ZERO).grow(reach)):
			if j >= i:
				continue
			var separation := point.distance_to(world.systems[j].pos)
			var frontier_relay: bool = i >= world.core_count and cell.distance_squared_to(world.chunk_at(world.systems[j].pos)) <= 1
			if separation <= core_reach or (frontier_relay and separation <= reach):
				navigation.connect_points(i,j)
	graph.coverage.clear()
	return graph

static func flight_route(world, start: int, destination: int, excluded: Array) -> Array:
	if start == destination:
		return []
	var navigation: AStar2D = flight_graph(world).navigation
	for point in excluded:
		if point != start and navigation.has_point(point):
			navigation.set_point_disabled(point,true)
	var route := Array(navigation.get_id_path(start,destination))
	for point in excluded:
		if point != start and navigation.has_point(point):
			navigation.set_point_disabled(point,false)
	if not route.is_empty():
		route.pop_front()
	return route

static func move_local(vessel: Dictionary, destination: Vector2, speed: float) -> bool:
	var old: Vector2 = vessel.pos
	vessel.pos = old.move_toward(destination,speed)
	if old != vessel.pos:
		vessel.heading = old.angle_to_point(vessel.pos)
	return vessel.pos.is_equal_approx(destination)

## Local traffic uses the same distances and arrival rules as daily off-screen travel.
static func fly_leg(world, vessel: Dictionary, target: Dictionary, days: float) -> bool:
	var speed: float = clampf(float(Hulls.MODELS[vessel.kind].speed),0.45,1.4)
	var previous_layer: bool = vessel.layer
	if not vessel.layer and vessel.system == target.system:
		var mining: bool = vessel.travel.get("activity","") == "mine"
		var stop: Vector2 = world.systems[target.system].field if mining else target.pos
		if move_local(vessel,stop,LOCAL_DISTANCE_PER_DAY * speed * days):
			if not mining:
				world.berth(vessel,target.id)
				if vessel.job.get("kind","") == "客运":
					_disembark_arrived(world, vessel, target.id)
			vessel.travel = {}
			if not vessel.get("order_queue",[]).is_empty() and vessel.dock == target.id:
				step_order(world,vessel,0.0)
	elif not vessel.layer:
		var region: Dictionary = world.systems[vessel.system]
		if Celestial.at_gravity_point(region, vessel.pos) or move_local(vessel, Celestial.gravity_approach(region, vessel.id), LOCAL_DISTANCE_PER_DAY * speed * days):
			vessel.layer = true
	else:
		var waypoints: Array = vessel.travel.waypoints
		if waypoints.is_empty():
			vessel.layer = false
			return true
		var next_system: int = waypoints.front()
		if next_system in vessel.get("trade_rules",{}).get("travel",[]):
			release_reservation(world,vessel)
			vessel.travel = {}
			return true
		var dest: Vector2 = world.systems[next_system].pos
		var old: Vector2 = vessel.galpos
		var hull: Dictionary = Hulls.MODELS[vessel.kind]
		var fuel_range: float = vessel.fuel / Hyperspace.fuel_for_distance(hull,1.0)
		var step := minf(Hyperspace.distance_per_day(hull)*days,fuel_range)
		vessel.galpos = old.move_toward(dest,step)
		vessel.fuel = maxf(0,vessel.fuel-Hyperspace.fuel_for_distance(hull,old.distance_to(vessel.galpos)))
		if vessel.galpos.is_equal_approx(dest):
			vessel.layer = false
			vessel.system = int(waypoints.pop_front())
			vessel.pos = Celestial.gravity_arrival(world, vessel.system, vessel.id)
		elif vessel.fuel <= 0.0001:
			release_reservation(world,vessel)
			vessel.travel = {}
	return vessel.travel.is_empty() or previous_layer != vessel.layer or vessel.dock != 0

static func patrol_leg(world, vessel: Dictionary, days: float) -> void:
	var job: Dictionary = vessel.job
	var home: Dictionary = world.ports.get(job.get("source",0),{})
	if home.is_empty() or vessel.system != home.system or forbidden(vessel,home) or not allowed(world,vessel,home):
		return
	var target_enemy: Dictionary = {}
	var best_dist := 550.0 * 550.0
	for other in world.ships.values():
		if other.id == vessel.id or other.system != home.system or other.dock != 0 or other.layer or other.hp <= 0.0:
			continue
		if not world.enemy(vessel, other):
			continue
		var d2: float = Vector2(home.pos).distance_squared_to(other.pos)
		if other.job.get("kind", "") == "攻城":
			d2 *= 0.4
		if d2 < best_dist:
			best_dist = d2
			target_enemy = other
	if not target_enemy.is_empty():
		move_local(vessel, target_enemy.pos, 48.0 * days)
		return
	if world.cargo_free(vessel) > 0:
		for wid in world.wrecks.keys():
			var cache: Dictionary = world.wrecks[wid]
			if cache.system == home.system and Vector2(vessel.pos).distance_squared_to(cache.pos) < 220.0 * 220.0 and cache.stock.max() > 0:
				if move_local(vessel, cache.pos, 42.0 * days):
					for ware in mini(cache.stock.size(), vessel.cargo.size()):
						var moved := mini(world.cargo_free(vessel), int(cache.stock[ware]))
						cache.stock[ware] -= moved
						vessel.cargo[ware] += moved
					if not cache.has("hull_id") and cache.stock.max() <= 0:
						world.wrecks.erase(wid)
				return
	elif Vector2(vessel.pos).distance_squared_to(home.pos) < 30.0 * 30.0:
		var inv := Industry.station_data(home)
		for ware in range(vessel.cargo.size()):
			var qty := int(vessel.cargo[ware])
			if qty > 0:
				var deposited := inv.deposit(ware, qty)
				vessel.cargo[ware] -= deposited
	var waypoint: Vector2 = world.systems[home.system].field if job.get("outbound",true) else home.pos
	if move_local(vessel,waypoint,40.0*days):
		job.outbound = not job.get("outbound",true)

static func escort_rejoin(vessel: Dictionary, lead: Dictionary, days: float) -> void:
	move_local(vessel,Vector2(lead.pos)+Vector2(-60,40),float(Industry.RULES.fleet_rendezvous.escort_units_per_day)*days)

static func has_supplies(vessel: Dictionary, needs: Dictionary) -> bool:
	for ware: int in needs:
		if vessel.cargo[ware]>0:
			return true
	return false

static func supply_rejoin(vessel: Dictionary, lead: Dictionary, days: float) -> bool:
	var offset := Vector2(vessel.pos) - Vector2(lead.pos)
	var transfer_range := float(Defenses.geometry(vessel.kind).module_radius) + float(Defenses.geometry(lead.kind).module_radius) + 4.0
	if offset.length_squared() <= transfer_range*transfer_range:
		return true
	var alongside := Vector2(lead.pos) + offset.normalized()*transfer_range
	return move_local(vessel,alongside,float(Industry.RULES.fleet_rendezvous.supply_units_per_day)*days)

## The nearby escort has already been steered tactically in the current physics frame.
static func duty_leg(world, vessel: Dictionary, days: float, tactical: Dictionary = {}) -> void:
	if vessel.captain==0 or vessel.layer:
		return
	var queue: Array = vessel.get("order_queue",[])
	if not queue.is_empty():
		var order: Dictionary = queue.front()
		if order.kind != "escort_to":
			return
		var lead: Dictionary = world.ships.get(world.people.get(order.issuer,{}).get("ship",0),{})
		if world.oversees(world.ship_principal(vessel),order.issuer) and order.commander==lead.get("id",0) and lead.dock==0 and not lead.layer and lead.system==vessel.system and not tactical.has(vessel.id) and not vessel.battle.get("retired",false):
			var port: Dictionary = world.ports.get(order.port,{})
			if not port.is_empty() and allowed(world,vessel,port) and not forbidden(vessel,port):
				escort_rejoin(vessel,lead,days)
		return
	match vessel.job.get("kind",""):
		"巡逻":
			patrol_leg(world,vessel,days)
		"补给":
			var lead: Dictionary = world.ships.get(vessel.get("commander_id",0),{})
			if lead.get("system",-1)==vessel.system and not lead.layer and has_supplies(vessel,resupply_needs(lead)):
				supply_rejoin(vessel,lead,days)

static func visible_traffic(world, system: int, hyperspace: bool, days: float, moved: Dictionary, tactical: Dictionary = {}) -> void:
	for vessel: Dictionary in world.ships.values():
		if vessel.layer != hyperspace or (not hyperspace and vessel.system != system) or vessel.dock != 0 or vessel.locked or vessel.captain == world.player:
			continue
		var paid := float(moved.get(vessel.id,0.0))
		var duration := minf(days,1.0-paid)
		if duration <= 0.000001:
			continue
		if vessel.travel.is_empty():
			if vessel.layer or vessel.captain==0 or (vessel.job.get("kind","") not in ["巡逻","补给"] and vessel.get("order_queue",[]).is_empty()):
				continue
			duty_leg(world,vessel,duration,tactical)
		else:
			var target: Dictionary = world.ports.get(vessel.travel.port,{})
			if target.is_empty() or vessel.travel.get("hold",false):
				continue
			if paid == 0.0 and (forbidden(vessel,target) or not reroute_merchant(world,vessel,target) or not allowed(world,vessel,target)):
				continue
			if fly_leg(world,vessel,target,duration):
				moved[vessel.id] = 1.0
				continue
		moved[vessel.id] = paid + duration

static func transit_day(world, moved: Dictionary = {}) -> void:
	var lead: Dictionary = world.ride()
	var patrols := {}
	if world.day % 3 == 0:
		for patrol in world.ships.values():
			var outlaw: bool = not world.Outlaws.id_for(patrol).is_empty() and not patrol.job.get("ambush_only",false)
			if patrol.dock == 0 and not patrol.layer and (outlaw or patrol.job.get("kind","") in ["护航","攻城","巡逻"]) and patrol.get("order_queue",[]).is_empty() and not patrol.locked:
				if not patrols.has(patrol.system):
					patrols[patrol.system] = []
				patrols[patrol.system].append(patrol)
	for vessel in world.ships.values():
		if not world.ships.has(vessel.id):
			continue
		pay_maintenance(world,vessel)
		var reservation: Dictionary = vessel.get("reservation",{})
		if not reservation.is_empty() and (world.day > reservation.expires or vessel.captain == 0 or vessel.captain == world.player):
			release_reservation(world,vessel)
		if vessel.travel.is_empty() or vessel.locked or vessel.captain == world.player:
			if vessel.travel.is_empty() and not vessel.locked and vessel.captain not in [0,world.player] and vessel.dock == 0 and not vessel.layer:
				var remaining := clampf(1.0-float(moved.get(vessel.id,0.0)),0.0,1.0)
				if remaining > 0.000001:
					duty_leg(world,vessel,remaining)
			continue
		var target: Dictionary = world.ports.get(vessel.travel.port,{})
		if target.is_empty() or forbidden(vessel,target):
			release_reservation(world,vessel)
			vessel.travel = {}
			continue
		if not reroute_merchant(world,vessel,target):
			continue
		if not allowed(world,vessel,target):
			release_reservation(world,vessel)
			vessel.travel = {}
			continue
		var remaining := clampf(1.0-float(moved.get(vessel.id,0.0)),0.0,1.0)
		if remaining > 0.000001:
			fly_leg(world,vessel,target,remaining)
		if vessel.layer or vessel.dock != 0 or (not lead.is_empty() and not lead.layer and lead.system == vessel.system):
			continue
		for patrol in patrols.get(vessel.system,[]):
			if patrol.id == vessel.id or not world.ships.has(patrol.id) or not world.enemy(vessel,patrol) or vessel.pos.distance_to(patrol.pos) > 240 or not world.Outlaws.permits_target(patrol,vessel):
				continue
			vessel.hp -= maxf(1,float(Hulls.MODELS[patrol.kind].power) * 0.35)
			MerchantSecurity.report_attack(world,vessel,patrol)
			if vessel.hp <= 0:
				world.destruction(vessel.id,patrol.captain)
			break

static func management_radius(world, vessel: Dictionary, source: Dictionary) -> int:
	var manager_data: Dictionary = world.people.get(source.manager,{})
	var captain: Dictionary = world.people.get(vessel.captain,{})
	var skill: int = maxi(manager_data.stats.stewardship if not manager_data.is_empty() else 7,captain.stats.stewardship if not captain.is_empty() else 6)
	var stress: int = manager_data.get("stress",0)
	return clampi(1 + skill / 5 - stress / 150,1,5)

static func reachable_systems(world, origin: int, jumps: int, excluded: Array) -> Dictionary:
	var graph := flight_graph(world)
	var key := Vector2i(origin,jumps)
	if excluded.is_empty() and graph.coverage.has(key):
		return graph.coverage[key]
	var reached := {origin:true}
	var frontier := [origin]
	for hop in jumps:
		var next: Array = []
		for current in frontier:
			for neighbor in graph.navigation.get_point_connections(current):
				if not reached.has(neighbor) and neighbor not in excluded:
					reached[neighbor] = true
					next.append(neighbor)
		frontier = next
	if excluded.is_empty():
		graph.coverage[key] = reached
	return reached

static func relief_rate(world, port: Dictionary, ware: int) -> int:
	if port.owner != 0 or port.firm != 0 or port.manager == world.player or ware not in Industry.COLONY_NEEDS or port.get("blockaded",false) or port.get("coalition_blockade",false) or port.get("surface_yields",{}).has(ware):
		return 0
	var stock := Industry.available(port,ware) + Industry.station_data(port).incoming(ware)
	var target := provisions_for(port,90)
	if stock >= target or target <= 0:
		return 0
	return ceili(12.0*(target-stock)/target)

static func trade_plan(world, vessel: Dictionary) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var highest := -INF
	var coverage := OperatingArea.coverage(world,vessel)
	var hold: int = world.cargo_free(vessel)
	var budget := account_balance(world,vessel)
	var requests := {}
	for dest: Dictionary in world.ports.values():
		if dest.build == 0 and coverage.has(dest.system) and not forbidden(vessel,dest) and allowed(world,vessel,dest):
			for staple: int in Industry.COLONY_NEEDS:
				var fee := relief_rate(world,dest,staple)
				if fee > 0 and world.Treasury.available(dest) > fee:
					requests.get_or_add(staple,{})[dest.id] = fee
	for source in world.ports.values():
		if source.build > 0 or forbidden(vessel,source) or not allowed(world,vessel,source):
			continue
		if not coverage.has(source.system):
			continue
		var pickup := trip_plan(world,vessel,vessel.system,vessel.pos,vessel.layer,source,0,false,coverage)
		if pickup.is_empty() or pickup.fuel > 100.0:
			continue
		var deliveries := {}
		var offers: Array = source.get("exports",[]).duplicate()
		for staple: int in requests:
			if staple not in offers and Industry.available(source,staple) > provisions_for(source,120):
				offers.append(staple)
		for ware in offers:
			var stock := Industry.available(source,ware)
			if ware in Industry.COLONY_NEEDS:
				stock -= provisions_for(source,12 if source.get("surface_yields",{}).has(ware) else 120)
			if stock <= 0:
				continue
			var quote := price(source,ware,true)
			for dest in world.ports.values():
				var fee: int = requests.get(ware,{}).get(dest.id,0)
				if dest.id == source.id or dest.build > 0 or (fee == 0 and (ware not in dest.get("imports",[]) or ware not in source.exports)):
					continue
				if forbidden(vessel,dest) or not allowed(world,vessel,dest):
					continue
				if not coverage.has(dest.system):
					continue
				var margin := price(dest,ware,false) - quote + fee
				var space := Industry.space(dest,ware)
				if margin <= 0 or space <= 0:
					continue
				if not deliveries.has(dest.id):
					deliveries[dest.id] = trip_plan(world,vessel,source.system,source.pos,false,dest,pickup.days,false,coverage)
				var delivery: Dictionary = deliveries[dest.id]
				if delivery.is_empty() or delivery.fuel > 100.0:
					continue
				var fuel_cost := ceili(float(pickup.fuel) + float(delivery.fuel))
				var units := mini(stock,mini(hold,space))
				if ware == Industry.Ware.FUEL:
					var top_up := maxi(0,ceili(delivery.fuel-maxf(0.0,vessel.fuel-pickup.fuel)-0.0001))
					units = mini(units,maxi(0,stock-top_up))
				var spending := freight_budget(world,vessel,pickup.fuel,delivery.fuel,source,budget,units if ware == Industry.Ware.FUEL else 0)
				if spending < 0:
					continue
				var lot := Industry.freight_quote(source,dest,ware,units,spending,false,false,fee)
				var net := lot.y - fuel_cost
				if net <= 0:
					continue
				var depth_factor := clampf(float(stock) / maxf(8.0, float(hold)), 0.35, 1.0)
				var urgency := 1.0
				if ware in Industry.COLONY_NEEDS and int(dest.get("shortage", 0)) > 0:
					urgency *= 1.0 + clampf(float(dest.shortage) / 15.0, 0.6, 3.0)
				elif ware == Industry.Ware.ENERGY and (Industry.Module.HABITAT in dest.modules or Industry.Module.CHEMICAL in dest.modules) and Industry.available(dest, Industry.Ware.ENERGY) < 20:
					urgency *= 2.2
				var score := freight_score(net,pickup.days,delivery.days) * depth_factor * urgency
				highest = maxf(highest, score)
				candidates.append({"source":source.id,"target":dest.id,"ware":ware,"phase":0,"quantity":lot.x,"score":score,"relief_port":dest.id if fee > 0 else 0})
	if candidates.is_empty():
		return {}
	var threshold := highest * 0.78
	var top: Array[Dictionary] = []
	for item in candidates:
		if float(item.score) >= threshold:
			top.append(item)
	top.sort_custom(func(a, b): return float(a.score) > float(b.score))
	if top.size() > 4:
		top.resize(4)
	var chosen := top[0]
	if top.size() > 1:
		var total_w := 0.0
		for item in top:
			total_w += maxf(0.01, float(item.score))
		var seed_val := absi(int(vessel.id) * 1103515245 + int(world.day) * 12345) % 10000
		var pick := (float(seed_val) / 10000.0) * total_w
		var acc := 0.0
		for item in top:
			acc += maxf(0.01, float(item.score))
			if pick <= acc:
				chosen = item
				break
	chosen.erase("score")
	return chosen

## Prefer loading near the ship when a competitive order is available there.
## Empty repositioning ties up the hold; a larger remote margin can still justify it.
static func freight_score(net: int, pickup_days: int, delivery_days: int) -> float:
	return float(net) / (12.0 + delivery_days + pickup_days * float(Industry.RULES.operating_area.empty_travel_weight))

static func mining_plan(world, vessel: Dictionary, home: Dictionary = {}) -> Dictionary:
	var best := {}
	var highest := 0.0
	var coverage := OperatingArea.coverage(world,vessel)
	var mine_rate: int = Hulls.MODELS[vessel.kind].mine
	var hold: int = world.cargo_free(vessel)
	var funds := account_balance(world,vessel)
	if mine_rate <= 0 or hold <= 0:
		return {}
	var buyers: Array = []
	for port: Dictionary in ([home] if not home.is_empty() else world.ports.values()):
		if (not home.is_empty() or Industry.Module.REFINERY in port.modules) and port.build == 0 and coverage.has(port.system) and not forbidden(vessel,port) and allowed(world,vessel,port) and Industry.space(port,Industry.Ware.ORE) > 0:
			buyers.append(port)
	var fields := {}
	for source: Dictionary in world.ports.values():
		var region: Dictionary = world.systems[source.system]
		if fields.has(source.system) or not coverage.has(source.system) or source.build > 0 or region.ore <= 0 or forbidden(vessel,source) or not allowed(world,vessel,source):
			continue
		fields[source.system] = true
		var pickup := trip_plan(world,vessel,vessel.system,vessel.pos,vessel.layer,{"system":source.system,"pos":region.field},0,false,coverage)
		if pickup.is_empty():
			continue
		for dest: Dictionary in buyers:
			var qty := mini(hold,mini(region.ore,Industry.space(dest,Industry.Ware.ORE)))
			var budget: int = 2147483647 if not home.is_empty() else world.Treasury.available(dest)
			var sale := lot_quote(dest,Industry.Ware.ORE,qty,false,-1,false,budget)
			if sale.x <= 0:
				continue
			var work_days := 6*ceili(float(sale.x)/mine_rate)
			var delivery := trip_plan(world,vessel,source.system,region.field,false,dest,pickup.days+work_days,false,coverage)
			if delivery.is_empty() or freight_budget(world,vessel,pickup.fuel+delivery.fuel,0,{},funds) < 0:
				continue
			var score := freight_score(sale.y-ceili(pickup.fuel+delivery.fuel),pickup.days,delivery.days+work_days)
			if score > highest:
				highest = score
				best = {"source":source.id,"target":dest.id,"ware":Industry.Ware.ORE,"phase":0,"quantity":sale.x}
	return best

static func station_trade_plan(world, vessel: Dictionary, home: Dictionary) -> Dictionary:
	if home.is_empty() or operating_port(world,vessel).get("id",0) != home.id or forbidden(vessel, home) or not allowed(world, vessel, home):
		return {}
	var coverage := OperatingArea.coverage(world,vessel)
	if not coverage.has(home.system):
		return {}
	if home.get("harvest_carriers",{}).has(vessel.id):
		return harvest_trade_plan(world,vessel,home,coverage,home.harvest_carriers[vessel.id])
	var best := {}
	var highest := -INF
	for ware in home.get("imports", []):
		var need := mini(Industry.space(home,ware),int(Industry.stock_target(ware))-StationData.market_quantity(home,ware))
		if need <= 0:
			continue
		for source in world.ports.values():
			if source.id == home.id or source.build > 0 or not coverage.has(source.system):
				continue
			if forbidden(vessel, source) or not allowed(world, vessel, source) or Industry.available(source, ware) <= 0:
				continue
			var offer := station_freight_offer(world,vessel,source,home,ware,need,true)
			if not offer.is_empty() and offer.score > highest:
				highest = offer.score
				best = offer
	for ware in home.get("exports", []):
		if Industry.available(home, ware) <= 0:
			continue
		for dest in world.ports.values():
			if dest.id == home.id or dest.build > 0 or not coverage.has(dest.system):
				continue
			if ware not in dest.get("imports", []) or Industry.space(dest, ware) <= 0 or forbidden(vessel, dest) or not allowed(world, vessel, dest):
				continue
			var offer := station_freight_offer(world,vessel,home,dest,ware,Industry.space(dest,ware),false)
			if not offer.is_empty() and offer.score > highest:
				highest = offer.score
				best = offer
	return best

static func harvest_trade_plan(world, vessel: Dictionary, home: Dictionary, coverage: Dictionary, ware: int) -> Dictionary:
	var pickup := trip_plan(world,vessel,vessel.system,vessel.pos,vessel.layer,home,0,false,coverage)
	if pickup.is_empty() or pickup.fuel > 100.0:
		return {}
	var best := {}
	var highest := -INF
	var best_priority := -1
	var funds := account_balance(world,vessel)
	var surplus := Industry.available(home,ware)-provisions_for(home,12)
	var hold := mini(surplus,world.cargo_free(vessel))
	if hold <= 0:
		return {}
	for dest: Dictionary in world.ports.values():
		if dest.id == home.id or dest.build > 0 or dest.get("blockaded",false) or not coverage.has(dest.system):
			continue
		if dest.get("surface_yields",{}).has(ware) or forbidden(vessel,dest) or not allowed(world,vessel,dest):
			continue
		var delivery := trip_plan(world,vessel,home.system,home.pos,false,dest,pickup.days,false,coverage)
		if delivery.is_empty() or delivery.fuel > 100.0:
			continue
		if freight_budget(world,vessel,pickup.fuel,delivery.fuel,home,funds) < 0:
			continue
		var eta := int(pickup.days) + int(delivery.days) + 6
		var receiver := Industry.station_data(dest)
		var committed := receiver.available(ware) + receiver.incoming(ware)
		var reorder := maxi(int(Industry.stock_target(ware)),provisions_for(dest,eta+90))
		# The reorder point triggers a full cargo lot; it is not a ceiling on the load.
		var timely := receiver.available(ware)
		for booking: Dictionary in dest.inbound.values():
			if booking.ware == ware and int(booking.expires)-36 <= world.day+eta:
				timely += int(booking.qty)
		if timely > reorder:
			continue
		var units := mini(hold,receiver.free_space(ware))
		var other := Industry.Ware.WATER if ware == Industry.Ware.RATIONS else Industry.Ware.RATIONS
		var complement := receiver.available(other)+receiver.incoming(other)
		if committed > complement:
			units = mini(units,receiver.free_space(ware)-maxi(0,provisions_for(dest,60)-complement))
		if units <= 0:
			continue
		var internal := internal_cargo(world,home,dest)
		var budget: int = 2147483647 if internal else world.Treasury.available(dest)
		var sale := Industry.lot_quote(dest,ware,units,false,-1,false,budget)
		if sale.x <= 0:
			continue
		# Only earlier deliveries can keep households supplied before this ship arrives.
		var per_day := float(maxi(1,dest.pop))/int(Industry.RULES.colony.person_days_per_unit)
		var runway := maxf(0.0,(timely-float(dest.get("provision_person_days",0))/int(Industry.RULES.colony.person_days_per_unit))/per_day)
		var slack := runway-eta
		var priority := 2 if slack < 6 else (1 if slack < 36 else 0)
		var days_covered := minf(120.0,sale.x/per_day)
		var score := days_covered/(12.0+eta) * (1.0+minf(float(complement)/maxi(1,sale.x),1.0))
		score *= 1.0 + clampf(float(dest.shortage)/60.0,0.0,2.0)
		if priority > best_priority or (priority == best_priority and score > highest):
			best_priority = priority
			highest = score
			best = {"source":home.id,"target":dest.id,"ware":ware,"phase":0,"quantity":sale.x}
	return best

static func station_freight_offer(world, vessel: Dictionary, source: Dictionary, dest: Dictionary, ware: int, demand_units: int, replenish: bool) -> Dictionary:
	var capacity := mini(demand_units,mini(Industry.available(source,ware),world.cargo_free(vessel)))
	var budget := account_balance(world,vessel)
	var internal := internal_cargo(world,source,dest)
	var pickup := trip_plan(world,vessel,vessel.system,vessel.pos,vessel.layer,source)
	if pickup.is_empty() or pickup.fuel > 100.0:
		return {}
	var delivery := trip_plan(world,vessel,source.system,source.pos,false,dest,pickup.days)
	if delivery.is_empty() or delivery.fuel > 100.0:
		return {}
	budget = freight_budget(world,vessel,pickup.fuel,delivery.fuel,source,budget)
	if budget < 0:
		return {}
	var lot := Industry.freight_quote(source,dest,ware,capacity,budget,internal or not replenish,internal or replenish)
	if lot.x == 0 and not replenish:
		return {}
	var fuel_cost := ceili(float(pickup.fuel) + float(delivery.fuel))
	var days := 12 + int(pickup.days) + int(delivery.days)
	var score := freight_score(lot.y-fuel_cost,pickup.days,delivery.days)
	if score <= 0:
		if not replenish:
			return {}
		# A station can pay its captain to bring in missing production inputs.
		var order := Vector2i(capacity,0) if internal else lot_quote(source,ware,capacity,true,-1,false,budget)
		if order.x == 0:
			return {}
		lot.x = order.x
		score = -float(order.y+fuel_cost) * days / order.x
	return {"source":source.id,"target":dest.id,"ware":ware,"phase":0,"quantity":lot.x,"score":score}

static func station_mining_plan(world, vessel: Dictionary, home: Dictionary) -> Dictionary:
	if home.is_empty() or operating_port(world,vessel).get("id",0) != home.id:
		return {}
	return mining_plan(world,vessel,home)

## Find a solvent, reachable receiver for a load whose original sale fell through.
static func divert_cargo(world, vessel: Dictionary, source: Dictionary, ware: int) -> bool:
	var job: Dictionary = vessel.job
	var home := operating_port(world,vessel)
	if not home.is_empty() and (job.kind == "站属采矿" or job.target == home.id):
		return false
	var best := {}
	var highest := 0.0
	var coverage := OperatingArea.coverage(world,vessel)
	var funds := account_balance(world,vessel)
	for port: Dictionary in world.ports.values():
		if port.id in [source.id,job.target] or port.build > 0 or not coverage.has(port.system) or forbidden(vessel,port) or not allowed(world,vessel,port):
			continue
		if ware not in port.imports and not (ware == Industry.Ware.ORE and Industry.Module.REFINERY in port.modules):
			continue
		var room := mini(vessel.cargo[ware],Industry.space(port,ware))
		var sale := lot_quote(port,ware,room,false,-1,false,world.Treasury.available(port))
		if sale.x <= 0:
			continue
		var leg := trip_plan(world,vessel,vessel.system,vessel.pos,vessel.layer,port,0,false,coverage)
		if leg.is_empty() or freight_budget(world,vessel,leg.fuel,0,{},funds) < 0:
			continue
		var score := freight_score(sale.y-ceili(leg.fuel),0,leg.days)
		if score > highest:
			highest = score
			best = port
	if best.is_empty() or not reserve(world,vessel,source,best,ware,vessel.cargo[ware],false):
		return false
	job.target = best.id
	return true

static func queue_order(world, ship_id: int, port_id: int, kind: String = "dock", ware: int = -1, quantity: int = 0) -> bool:
	var vessel: Dictionary = world.ships.get(ship_id,{})
	var port: Dictionary = world.ports.get(port_id,{})
	if vessel.is_empty() or port.is_empty() or not world.oversees(world.ship_principal(vessel)) or vessel.captain in [0,world.player] or forbidden(vessel,port) or not allowed(world,vessel,port):
		return false
	var orders: Array = vessel.get("order_queue",[])
	var order := {"kind":kind,"port":port_id,"issuer":world.player}
	if FleetOrder.carries_goods(kind):
		order.ware = ware
		order.quantity = quantity
	if kind == "escort_to":
		order.commander = world.ride().get("id",0)
	if orders.size() >= FleetOrder.LIMIT or not FleetOrder.valid(order,Industry.WARES.size()) or not order_access(world,order,port):
		return false
	if orders.is_empty():
		release_reservation(world,vessel)
		vessel.travel = {}
		vessel.erase("route_hold")
		vessel.battle.erase("tactical_waypoint")
	orders.append(order)
	vessel.order_queue = orders
	return true

static func order_access(world, order: Dictionary, port: Dictionary) -> bool:
	if order.kind in ["buy","sell"]:
		return port.build == 0 and order.ware != Industry.Ware.LUXURY
	return order.kind not in ["load","unload"] or world.oversees(port.owner,order.issuer)

static func cancel_order(world, ship_id: int, index: int) -> bool:
	var ship: Dictionary = world.ships.get(ship_id,{})
	if ship.is_empty() or not world.oversees(world.ship_principal(ship)) or index not in range(ship.get("order_queue",[]).size()):
		return false
	if index == 0:
		ship.travel = {}
		ship.erase("route_hold")
	ship.order_queue.remove_at(index)
	return true

static func order_trip(world, ship: Dictionary, port: Dictionary) -> String:
	begin_trip(world,ship,port)
	if ship.has("route_hold"):
		return ""
	return "航线或燃料不足" if ship.travel.is_empty() else ""

static func escort_order(world, ship: Dictionary, order: Dictionary, port: Dictionary, days: float = 6.0) -> String:
	var issuer: Dictionary = world.people.get(order.issuer,{})
	var commander: Dictionary = world.ships.get(issuer.get("ship",0),{})
	if commander.get("id",0) != order.commander:
		return "旗舰已更换"
	if commander.dock == port.id:
		return "已护送到港" if ship.dock == port.id else order_trip(world,ship,port)
	if commander.layer:
		return ""
	if commander.dock != 0 and ship.dock == commander.dock:
		return ""
	if ship.system == commander.system and not ship.layer:
		if commander.dock != 0:
			var meeting: Dictionary = world.ports[commander.dock]
			if allowed(world,ship,meeting) and not forbidden(ship,meeting):
				return order_trip(world,ship,meeting)
		if ship.dock != 0:
			world.depart(ship)
		if days>0.0:
			escort_rejoin(ship,commander,days)
	else:
		for id in world.systems[commander.system].ports:
			var meeting: Dictionary = world.ports[id]
			if allowed(world,ship,meeting) and not forbidden(ship,meeting):
				return order_trip(world,ship,meeting)
		return "旗舰星系无可用泊位"
	return ""

static func step_order(world, ship: Dictionary, days: float = 6.0) -> void:
	var order: Dictionary = ship.order_queue.front()
	var port: Dictionary = world.ports.get(order.port,{})
	var result := ""
	var moved := 0
	if not world.people.get(order.issuer,{}).get("alive",false) or not world.oversees(world.ship_principal(ship),order.issuer):
		result = "下令人已无权指挥本舰"
	elif port.is_empty() or forbidden(ship,port) or not allowed(world,ship,port) or not order_access(world,order,port):
		result = "目的港不可用"
	elif order.kind == "escort_to":
		result = escort_order(world,ship,order,port,days)
	elif ship.dock != port.id:
		result = order_trip(world,ship,port)
	elif order.kind == "dock":
		result = "已停靠"
	else:
		var ware: int = order.ware
		var before: int = ship.cargo[ware]
		var inventory := Industry.station_data(port)
		match order.kind:
			"buy","sell":
				exchange(world,ship,port,ware,order.quantity if order.kind == "buy" else -order.quantity)
			"load":
				ship.cargo[ware] += inventory.withdraw(ware,mini(order.quantity,world.cargo_free(ship)))
			"unload":
				ship.cargo[ware] -= inventory.deposit(ware,mini(order.quantity,before))
		moved = absi(int(ship.cargo[ware]) - before)
		result = "已完成" if moved == order.quantity else ("部分完成" if moved > 0 else "未成交")
	if not result.is_empty():
		ship.last_order = {"order":ship.order_queue.pop_front(),"result":result,"moved":moved,"day":world.day}

static func supply_construction(world, ship_id: int, source_id: int, site_id: int) -> bool:
	var vessel: Dictionary = world.ships.get(ship_id,{})
	var source: Dictionary = world.ports.get(source_id,{})
	var site: Dictionary = world.ports.get(site_id,{})
	if vessel.is_empty() or source.is_empty() or site.is_empty() or not world.oversees(world.ship_principal(vessel)) or not world.oversees(site.owner):
		return false
	if vessel.captain in [0,world.player] or not vessel.get("order_queue",[]).is_empty() or source.id == site.id or source.build > 0 or build_requirements(site).is_empty():
		return false
	if not allowed(world,vessel,source) or not allowed(world,vessel,site) or forbidden(vessel,source) or forbidden(vessel,site):
		return false
	release_reservation(world,vessel)
	vessel.travel = {}
	if vessel.job.get("kind","") != "施工配送":
		vessel.resume_job = vessel.job.duplicate(true)
	vessel.job = {"kind":"施工配送","source":source_id,"target":site_id}
	return true

static func haul_construction(world, vessel: Dictionary) -> void:
	var source: Dictionary = world.ports.get(vessel.job.source,{})
	var site: Dictionary = world.ports.get(vessel.job.target,{})
	if source.is_empty() or site.is_empty() or build_requirements(site).is_empty() or forbidden(vessel,source) or forbidden(vessel,site):
		release_reservation(world,vessel)
		vessel.job = vessel.get("resume_job",{})
		vessel.erase("resume_job")
		return
	var reservation: Dictionary = vessel.get("reservation",{})
	if reservation.is_empty():
		for ware in build_requirements(site):
			var loading: bool = vessel.cargo[ware] == 0
			var available: int = world.cargo_free(vessel) if loading else int(vessel.cargo[ware])
			if reserve(world,vessel,source,site,ware,available,loading,true):
				reservation = vessel.reservation
				break
	if reservation.is_empty():
		return
	var destination := site if reservation.loaded else source
	if vessel.dock != destination.id:
		begin_trip(world,vessel,destination)
	elif reservation.loaded:
		var ware: int = reservation.ware
		var qty := Industry.station_data(site).deliver_construction(ware,mini(reservation.qty,vessel.cargo[ware]),build_requirements(site))
		vessel.cargo[ware] -= qty
		release_reservation(world,vessel)
	elif not exchange(world,vessel,source,reservation.ware,reservation.qty):
		release_reservation(world,vessel)

static func assign_role(world, ship_id: int, commander_id: int, role: String) -> bool:
	var vessel: Dictionary = world.ships.get(ship_id,{})
	var commander: Dictionary = world.ships.get(commander_id,{})
	if vessel.is_empty() or commander.is_empty() or ship_id == commander_id or vessel.captain in [0,world.player] or not world.oversees(world.ship_principal(vessel)) or not world.can_operate(commander):
		return false
	if role not in FleetOrder.ROLES:
		return false
	var cursor := commander
	var seen := {}
	while not cursor.is_empty():
		if cursor.id == ship_id or seen.has(cursor.id):
			return false
		seen[cursor.id] = true
		cursor = world.ships.get(cursor.get("commander_id",0),{})
	if vessel.get("order_queue",[]).is_empty():
		release_reservation(world,vessel)
		vessel.travel = {}
	vessel.erase("resume_job")
	vessel.commander_id = commander_id
	vessel.fleet_role = role
	if role == "MIMIC":
		vessel.mimic_template = commander.get("default_behavior",commander.job).duplicate(true)
		vessel.job = vessel.mimic_template.duplicate(true)
	elif role == "SUPPLY":
		vessel.job = {"kind":"补给"}
	else:
		vessel.job = {"kind":"护航","system":commander.system}
	vessel.default_behavior = vessel.job.duplicate(true)
	return true

static func resupply_needs(vessel: Dictionary) -> Dictionary:
	var needed := {}
	var fuel := maxi(0,ceili(85.0 - vessel.fuel))
	if fuel > 0:
		needed[Industry.Ware.FUEL] = fuel
	var damage := maxf(0.0,float(Hulls.MODELS[vessel.kind].hp)-float(vessel.hp))
	damage += maxf(0.0,float(Hulls.COMBAT[vessel.kind].armor)-float(vessel.battle.armor))
	if damage > 0.01:
		needed[Industry.Ware.HULL_PARTS] = ceili(damage/12.0)
	var missiles := 0
	var magazines: Array = vessel.battle.get("magazines",[])
	for i in range(mini(magazines.size(),vessel.fit.weapons.size())):
		var capacity: int = Hulls.WEAPONS.get(vessel.fit.weapons[i],{}).get("ammo",0)
		missiles += ceili(maxf(0,capacity-float(magazines[i]))/4.0)
	if missiles:
		needed[Industry.Ware.ORDNANCE] = missiles
	return needed

static func field_resupply(tender: Dictionary, lead: Dictionary, needs: Dictionary) -> void:
	for ware in needs:
		var units := mini(int(needs[ware]), int(tender.cargo[ware]))
		if units == 0:
			continue
		match ware:
			Industry.Ware.FUEL:
				lead.fuel = minf(100,lead.fuel+units)
			Industry.Ware.HULL_PARTS:
				var hull_repair := minf(units*12.0,maxf(0.0,float(Hulls.MODELS[lead.kind].hp)-float(lead.hp)))
				lead.hp += hull_repair
				Defenses.repair_armor(lead,units*12.0-hull_repair)
			Industry.Ware.ORDNANCE:
				var remaining := units
				var magazines: Array = lead.battle.get("magazines",[])
				for i in range(mini(magazines.size(),lead.fit.weapons.size())):
					var capacity: int = Hulls.WEAPONS.get(lead.fit.weapons[i],{}).get("ammo",0)
					var used := mini(remaining,ceili(maxf(0,capacity-float(magazines[i]))/4.0))
					magazines[i] = minf(capacity,float(magazines[i])+4*used)
					remaining -= used
				units -= remaining
		tender.cargo[ware] -= units

static func supply_commander(world, vessel: Dictionary, days: float = 6.0) -> void:
	var lead: Dictionary = world.ships.get(vessel.get("commander_id",0),{})
	if lead.is_empty() or lead.layer:
		return
	var needs := resupply_needs(lead)
	if needs.is_empty():
		return
	var carrying := has_supplies(vessel,needs)
	if not carrying:
		var port: Dictionary = world.ports.get(vessel.dock,{})
		if not port.is_empty() and allowed(world,vessel,port) and not forbidden(vessel,port):
			for ware in needs:
				carrying = exchange(world,vessel,port,ware,needs[ware]) or carrying
			if carrying:
				return
		var nearest: Dictionary = {}
		var distance := INF
		for other in world.ports.values():
			var gap: float = world.distance(other.system,vessel.system)
			if other.build > 0 or gap >= distance or forbidden(vessel,other) or not allowed(world,vessel,other):
				continue
			for ware in needs:
				if Industry.available(other,ware)>0:
					distance = gap
					nearest = other
					break
		if not nearest.is_empty() and nearest.id != vessel.dock:
			begin_trip(world,vessel,nearest)
	elif lead.system == vessel.system:
		if vessel.dock != 0:
			world.depart(vessel)
		if supply_rejoin(vessel,lead,days):
			field_resupply(vessel,lead,needs)
	else:
		for port_id in world.systems[lead.system].ports:
			var dest: Dictionary = world.ports[port_id]
			if allowed(world,vessel,dest) and not forbidden(vessel,dest):
				begin_trip(world,vessel,dest)
				return

static func step_ship(world, vessel: Dictionary, duty_days: float = 6.0) -> void:
	if vessel.captain in [0,world.player] or vessel.locked or not vessel.travel.is_empty():
		return
	if vessel.has("construction_contract"):
		world.ConstructionContract.advance(world,vessel)
		return
	if (vessel.owner != 0 or vessel.has("firm")) and vessel.dock != 0 and world.ports.has(vessel.dock):
		var depot: Dictionary = world.ports[vessel.dock]
		if depot.build == 0 and allowed(world, vessel, depot) and not forbidden(vessel, depot):
			if vessel.fuel < 50.0 and not OperatingArea.automatic(vessel):
				refuel_trader(world,vessel,depot)
			var max_hp: float = float(world.HULL_HP[vessel.kind])
			var parts := Industry.available(depot, Industry.Ware.HULL_PARTS)
			if vessel.hp < max_hp * 0.85 and parts > 0:
				var internal: bool = operating_port(world,vessel).get("id",0) == depot.id
				var budget := parts * 6 if internal else mini(parts*6,account_balance(world,vessel))
				var repair_cost := mini(budget,ceili((max_hp - vessel.hp) / 3.0))
				if repair_cost > 0:
					Industry.station_data(depot).withdraw(Industry.Ware.HULL_PARTS, maxi(1, ceili(repair_cost / 6.0)))
					vessel.hp = minf(max_hp, vessel.hp + 3.0 * repair_cost)
					if not internal:
						pay(world,vessel,-repair_cost,"维修")
						world.Treasury.post(world,depot,repair_cost,"维修")
	if not vessel.get("order_queue",[]).is_empty():
		step_order(world,vessel,duty_days)
		return
	if vessel.get("fleet_role","") == "MIMIC":
		var commander: Dictionary = world.ships.get(vessel.get("commander_id",0),{})
		var behavior: Dictionary = commander.get("default_behavior",commander.get("job",{}))
		if behavior != vessel.get("mimic_template",{}):
			release_reservation(world,vessel)
			vessel.job = behavior.duplicate(true)
			vessel.mimic_template = behavior.duplicate(true)
			vessel.default_behavior = behavior.duplicate(true)
	if vessel.job.is_empty():
		# Older NPC service companies can own a crewed first ship without an initial assignment.
		var firm: Dictionary = world.firms.get(vessel.get("firm", 0), {})
		if firm.is_empty() or int(vessel.dock) == 0 or not vessel.get("default_behavior", {}).is_empty() or vessel.has("fleet_role") or world.oversees(int(firm.director)):
			return
		if int(firm.director) <= 0 or not world.Politics.assign_company_service(world, str(firm.get("sector", "")), int(firm.director), vessel, int(firm.hq)):
			return
	var job: Dictionary = vessel.job
	if job.get("kind","") == "施工配送":
		haul_construction(world,vessel)
		return
	if job.get("kind","") == "客运":
		step_passenger_ship(world,vessel)
		return
	if job.get("kind","") == "工程承包" and not vessel.has("construction_contract"):
		world.ConstructionContract.step_contractor(world,vessel)
		return
	if job.get("kind","") in ["停泊待命","巡逻"]:
		var home: Dictionary = world.ports.get(int(job.get("source", 0)), {})
		if home.is_empty() or forbidden(vessel,home) or not allowed(world,vessel,home):
			return
		if job.kind == "停泊待命" or vessel.system != home.system or vessel.layer:
			if vessel.dock != home.id:
				begin_trip(world,vessel,home)
		else:
			if vessel.dock != 0:
				world.depart(vessel)
			if duty_days > 0.0:
				patrol_leg(world,vessel,duty_days)
		return
	if job.get("kind","") == "补给":
		supply_commander(world,vessel,duty_days)
		return
	if job.get("kind","") == "护航":
		if (vessel.owner != 0 or vessel.has("firm")) and vessel.dock != 0:
			var owner_ship := int(world.people[vessel.owner].ship) if world.people.has(vessel.owner) else 0
			var leader_id: int = int(vessel.get("commander_id", owner_ship))
			var lead: Dictionary = world.ships.get(leader_id,{})
			if not lead.is_empty() and lead.dock == 0 and lead.system == vessel.system:
				world.depart(vessel)
				vessel.pos += Vector2(25,-15)
		return
	if job.get("kind","") not in ["贸易","采矿","站属贸易","站属采矿"]:
		return
	var is_station_duty: bool = job.get("kind","") in ["站属贸易","站属采矿"]
	if is_station_duty and operating_port(world,vessel).is_empty():
		release_reservation(world,vessel)
		vessel.job = {}
		vessel.default_behavior = {}
		return
	var automatic: bool = (vessel.owner == 0 and not vessel.has("firm")) or job.get("automatic",false) or is_station_duty or (vessel.get("fleet_role","") == "MIMIC" and not vessel.default_behavior.has("source"))
	if automatic and not job.has("source"):
		OperatingArea.apply_next(vessel)
	if not job.has("source") and automatic and world.day >= job.get("retry_day",0):
		var planned := {}
		if is_station_duty:
			var home_st: Dictionary = world.ports.get(job.get("home_port", 0), {})
			planned = station_mining_plan(world, vessel, home_st) if job.kind == "站属采矿" else station_trade_plan(world, vessel, home_st)
		else:
			planned = mining_plan(world,vessel) if job.kind == "采矿" else trade_plan(world,vessel)
		job.merge(planned,true)
		job.retry_day = world.day + 18 + vessel.id % 18
		if Diagnostics.accessible(world,vessel):
			if planned.is_empty():
				Diagnostics.record(world,vessel,"未选到可执行的货单",{"funds":account_balance(world,vessel),"fuel":vessel.fuel,"free_space":world.cargo_free(vessel),"retry_day":job.retry_day})
			else:
				Diagnostics.record(world,vessel,"接单",{"source":job.source,"target":job.target,"ware":job.ware,"quantity":job.quantity})
	if not world.ports.has(job.get("source",0)) or not world.ports.has(job.get("target",0)):
		return
	var source: Dictionary = world.ports[job.source]
	var dest: Dictionary = world.ports[job.target]
	var loading: bool = job.phase == 0
	var goal := source if loading else dest
	var ware: int = job.get("ware",Industry.Ware.ORE if source.module == Industry.Module.MINE else Industry.Ware.ALLOY)
	if not loading and vessel.cargo[ware] == 0:
		release_reservation(world,vessel)
		job.phase = 0
		return
	var mining: bool = job.kind in ["采矿","站属采矿"]
	if forbidden(vessel,goal) or not allowed(world,vessel,goal) or goal.build > 0:
		release_reservation(world,vessel)
		if automatic and not loading:
			divert_cargo(world,vessel,source,ware)
		elif automatic:
			job.erase("source")
		return
	if (not mining or not loading) and vessel.get("reservation",{}).is_empty():
		var quantity: int = job.get("quantity",world.cargo_free(vessel)) if loading else int(vessel.cargo[ware])
		if not reserve(world,vessel,source,dest,ware,quantity,loading):
			Diagnostics.record(world,vessel,"订舱未成功",{"source":source.id,"target":dest.id,"ware":ware,"quantity":quantity,"loading":loading})
			if automatic and loading:
				job.erase("source")
			elif automatic:
				divert_cargo(world,vessel,source,ware)
			return
	if mining and loading:
		ware = Industry.Ware.ORE
		var field: Dictionary = world.systems[goal.system]
		if vessel.system != goal.system or vessel.layer or vessel.pos.distance_to(field.field) > 10:
			var outbound := trip_plan(world,vessel,vessel.system,vessel.pos,vessel.layer,{"system":goal.system,"pos":field.field})
			var inbound := trip_plan(world,vessel,goal.system,field.field,false,dest)
			if outbound.is_empty() or inbound.is_empty():
				if automatic: job.erase("source")
				return
			begin_trip(world,vessel,goal,outbound.fuel+inbound.fuel)
			if not vessel.travel.is_empty():
				vessel.travel.activity = "mine"
			elif automatic:
				job.erase("source")
			return
		var unload_room := maxi(0,mini(Industry.space(dest,ware),job.get("quantity",2147483647))-int(vessel.cargo[ware]))
		var qty := mini(Hulls.MODELS[vessel.kind].mine,mini(unload_room,mini(field.ore,world.cargo_free(vessel))))
		vessel.cargo[ware] += qty
		field.ore -= qty
		record_mining(world,goal.system,qty)
		if vessel.cargo[ware] > 0 and (qty >= unload_room or world.cargo_free(vessel) == 0 or field.ore == 0):
			job.phase = 1
		elif qty == 0 and automatic:
			job.erase("source")
		return
	if vessel.dock != goal.id:
		var depart := 0.0
		if loading and automatic:
			var pickup := trip_plan(world,vessel,vessel.system,vessel.pos,vessel.layer,source)
			var delivery := trip_plan(world,vessel,source.system,source.pos,false,dest)
			if not pickup.is_empty() and not delivery.is_empty():
				depart = pickup.fuel+delivery.fuel-Industry.available(source,Industry.Ware.FUEL)
		begin_trip(world,vessel,goal,depart)
		if automatic and vessel.travel.is_empty():
			if loading:
				job.erase("source")
			else:
				divert_cargo(world,vessel,source,ware)
		return
	if mining:
		ware = Industry.Ware.ORE
	if exchange(world,vessel,goal,ware,int(vessel.reservation.qty) if loading else -int(vessel.cargo[ware])):
		job.phase = 1 if loading or vessel.cargo[ware] > 0 else 0
		if automatic and (vessel.owner != 0 or vessel.has("firm")) and vessel.fuel < 50.0:
			refuel_trader(world,vessel,goal)
		if automatic and not loading and job.phase == 0:
			job.erase("source")
	else:
		release_reservation(world,vessel)
		if automatic and loading:
			job.erase("source")
		elif automatic:
			divert_cargo(world,vessel,source,ware)

static func weapon_materials(key: String) -> Dictionary:
	if key.is_empty() or not Hulls.WEAPONS.has(key):
		return {}
	var weapon: Dictionary = Hulls.WEAPONS[key]
	var mount: int = maxi(1, int(weapon.mount))
	var mat := {
		Industry.Ware.ORDNANCE: mount,
		Industry.Ware.ALLOY: mount
	}
	var elec: int = mount if (int(weapon.type) == 2 or bool(weapon.get("missile", false))) else maxi(0, mount - 1)
	if elec > 0:
		mat[Industry.Ware.ELECTRONICS] = elec
	return mat

static func weapon_price(key: String, buying: bool = true, black: bool = false, station: Dictionary = {}) -> int:
	if key.is_empty() or not Hulls.WEAPONS.has(key):
		return 0
	var weapon: Dictionary = Hulls.WEAPONS[key]
	var market: Dictionary = ArmsMarket.data
	var pricing: Dictionary = market.pricing
	var labor := float(weapon.op * pricing.per_op + weapon.mount * pricing.per_mount_size) * 0.45
	var mat_cost := 0.0
	var mats := weapon_materials(key)
	for ware: int in mats:
		var qty: int = int(mats[ware])
		if not station.is_empty() and not black:
			mat_cost += float(Industry.lot_quote(station, ware, qty, true).y)
		else:
			mat_cost += float(Industry.BASE[ware] * qty)
	var base := labor + mat_cost
	if key not in market.standard and key not in market.heavy:
		base *= float(pricing.variant_multiplier)
	if black and buying:
		base *= float(pricing.black_multiplier)
	return maxi(pricing.minimum, roundi(base if buying else base * float(pricing.trade_in)))

static func station_weapons(world, station: Dictionary, black: bool = false) -> Array:
	if station.is_empty() or station.build > 0 or station.get("landing_only",false):
		return []
	var market: Dictionary = ArmsMarket.data
	var catalog: Array = market.standard.duplicate()
	var modules: Array = station.get("modules",[station.module])
	var heavy: bool = black or station.get("capital_yard",false) or market.heavy_modules.any(func(id): return Industry.MODULE_ID[id] in modules)
	if heavy:
		catalog.append_array(market.heavy)
	var variants: Array = []
	for key in Hulls.WEAPONS:
		if key in market.standard or key in market.heavy:
			continue
		if heavy or Hulls.WEAPONS[key].mount <= market.light_mount_limit:
			variants.append(key)
	variants.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:weapons:%d:%d:%s" % [str(world.settings.get("seed", "")), station.id, int(world.day / int(market.refresh_days)), str(black)])
	var channel := "black" if black else ("yard" if Industry.Module.YARD in modules else "regular")
	var count: int = market.rotation_count[channel]
	for _pick in range(mini(count, variants.size())):
		var index := rng.randi_range(0, variants.size() - 1)
		catalog.append(variants.pop_at(index))
	return catalog

static func refit_target(world, target_ship_id: int = 0) -> Dictionary:
	return world.ships.get(target_ship_id, {}) if target_ship_id > 0 else world.ride()

static func slot_offers(world, port_id: int, slot_index: int, black: bool = false, target_ship_id: int = 0) -> Array:
	var vessel: Dictionary = refit_target(world, target_ship_id)
	var port: Dictionary = world.ports.get(port_id,{})
	if port.is_empty() or vessel.is_empty() or vessel.dock != port_id or slot_index not in range(vessel.fit.weapons.size()):
		return []
	if Hulls.slot_spec(vessel.kind,slot_index).builtin or (black and not world.is_regular(port)):
		return []
	var offered := station_weapons(world,port,black).filter(func(key): return Hulls.weapon_compatible(vessel.kind,slot_index,key))
	if vessel.fit.weapons[slot_index] != "":
		offered.append("")
	return offered

static func refit_quote(world, port_id: int, slot_index: int, weapon_key: String, black: bool = false, target_ship_id: int = 0) -> Dictionary:
	var vessel: Dictionary = refit_target(world, target_ship_id)
	var station: Dictionary = world.ports.get(port_id, {})
	if station.is_empty() or vessel.is_empty() or vessel.dock != port_id or world.active().loc != port_id or station.build > 0:
		return {"ok":false, "reason":"舰船未停靠在本站"}
	if not world.can_operate(vessel) or (black and not world.is_regular(station)) or (not black and not allowed(world, vessel, station)):
		return {"ok":false, "reason":"当前无权使用此武器库"}
	if slot_index not in range(vessel.fit.weapons.size()) or (weapon_key != "" and not Hulls.WEAPONS.has(weapon_key)):
		return {"ok":false, "reason":"无此挂点或武器"}
	var old_key: String = vessel.fit.weapons[slot_index]
	var budget: int = Hulls.COMBAT[vessel.kind].op
	var change := int(Hulls.WEAPONS.get(weapon_key,{}).get("op",0)) - int(Hulls.WEAPONS.get(old_key,{}).get("op",0))
	var used := Hulls.fitting_cost(vessel.kind, vessel.fit) + change
	var price := weapon_price(weapon_key,true,black,station) - weapon_price(old_key,false,false,station)
	var quote := {"ok":false, "reason":"", "current":old_key, "weapon":weapon_key, "net":price,
		"op_delta":change, "used_op":used, "free_op":budget-used}
	if old_key == weapon_key:
		quote.net = 0
		quote.reason = "已安装"
	elif Hulls.slot_spec(vessel.kind,slot_index).builtin:
		quote.reason = "内置武器固定在舰体上"
	elif not Hulls.weapon_compatible(vessel.kind,slot_index,weapon_key):
		quote.reason = "挂点类型或尺寸不兼容"
	elif weapon_key != "" and weapon_key not in station_weapons(world,station,black):
		quote.reason = "此渠道未出售该武器"
	elif used > budget:
		quote.reason = "装配点不足"
	elif price > 0 and player_funds(world,vessel) < price:
		quote.reason = "信用点不足"
	elif -price > (int(station.get("black_treasury", 0)) if black else world.Treasury.available(station)):
		quote.reason = "黑市回购资金不足" if black else "本站回购预算不足"
	elif weapon_key != "" and not black:
		var w_mats := weapon_materials(weapon_key)
		var lacking := false
		for ware: int in w_mats:
			if Industry.available(station, ware) < int(w_mats[ware]):
				lacking = true
				break
		if lacking:
			quote.reason = "本站制造材料（%s）不足" % "、".join(w_mats.keys().map(func(w): return world.WARES[w]))
		else:
			quote.ok = true
	else:
		quote.ok = true
	return quote

static func refit_slot(world, port_id: int, slot_index: int, weapon_key: String, black: bool = false, target_ship_id: int = 0) -> bool:
	var quote := refit_quote(world,port_id,slot_index,weapon_key,black,target_ship_id)
	if not quote.ok:
		return false
	var vessel: Dictionary = refit_target(world, target_ship_id)
	var station: Dictionary = world.ports[port_id]
	var candidate: Hulls.Fitting = vessel.fit.copy()
	candidate.weapons[slot_index] = weapon_key
	if Hulls.fitting_cost(vessel.kind,candidate) < 0:
		return false
	if not weapon_key.is_empty() and not black and not Industry.consume(station, weapon_materials(weapon_key)):
		return false
	player_pay(world,vessel,-int(quote.net),"整备换装")
	if black:
		station.black_treasury = maxi(0, int(station.get("black_treasury", 0)) + int(quote.net))
	else:
		world.Treasury.post(world,station,quote.net,"整备换装")
	vessel.fit = candidate
	if slot_index < vessel.battle.cooldowns.size():
		vessel.battle.cooldowns[slot_index] = 0.0
	if black and not weapon_key.is_empty():
		var actor: Dictionary = world.active()
		actor.suspicion = mini(100, int(actor.get("suspicion", 0)) + 4)
	world.combat_event("trade", station.pos, station.system)
	return true

static func wing_exchange(before: Array, after: Array) -> Dictionary:
	var differences := {}
	for id in before:
		differences[id] = int(differences.get(id,0))-1
	for id in after:
		differences[id] = int(differences.get(id,0))+1
	var quote := {"net":0,"materials":{}}
	for id in differences:
		var quantity: int = differences[id]
		var spec := Hulls.wing_spec(id)
		var price := int(spec.price)
		quote.net += quantity * (price if quantity > 0 else floori(price * 0.5))
		if quantity > 0:
			for material in spec.materials:
				var ware: int = Industry.WARE_ID[material]
				quote.materials[ware] = int(quote.materials.get(ware,0)) + quantity * int(spec.materials[material])
	return quote

static func refit_wing(world, port_id: int, bay: int, wing_id: String, target_ship_id: int = 0) -> bool:
	var vessel: Dictionary = refit_target(world, target_ship_id)
	if vessel.is_empty() or bay not in range(vessel.fit.wings.size()) or Hulls.wing_spec(wing_id).is_empty():
		return false
	var fit: Hulls.Fitting = vessel.fit.copy()
	fit.wings[bay] = wing_id
	return settle_refit(world,port_id,vessel,fit)

static func refit_preset(world, port_id: int, preset_id: String, target_ship_id: int = 0) -> bool:
	var vessel: Dictionary = refit_target(world, target_ship_id)
	if vessel.is_empty():
		return false
	var fit := Hulls.Fitting.from_dictionary(Hulls.preset_fit(vessel.kind,preset_id))
	return settle_refit(world,port_id,vessel,fit)

static func settle_refit(world, port_id: int, vessel: Dictionary, fit: Hulls.Fitting) -> bool:
	var station: Dictionary = world.ports.get(port_id,{})
	var actor: Dictionary = world.active()
	if vessel.is_empty() or station.is_empty() or vessel.dock != port_id or actor.loc != port_id or station.build > 0 or not world.can_operate(vessel) or not allowed(world,vessel,station):
		return false
	var current: Hulls.Fitting = vessel.fit
	if Hulls.fitting_cost(vessel.kind,fit) < 0 or current.matches(fit):
		return false
	# Moving an owned gun to another compatible slot incurs no broker spread.
	var balance := {}
	for key in current.weapons:
		if key != "":
			balance[key] = int(balance.get(key,0))-1
	for key in fit.weapons:
		if key != "":
			balance[key] = int(balance.get(key,0))+1
	var offered := station_weapons(world,station)
	var offer := wing_exchange(current.wings,fit.wings)
	var materials: Dictionary = offer.materials
	var net: int = offer.net
	for key in balance:
		var difference: int = balance[key]
		if difference > 0 and key not in offered:
			return false
		if difference > 0:
			var w_mats := weapon_materials(key)
			for ware: int in w_mats:
				materials[ware] = int(materials.get(ware, 0)) + difference * int(w_mats[ware])
		net += difference * weapon_price(key, difference > 0, false, station)
	for key in ["caps","vents"]:
		var difference := int(fit[key]) - int(current[key])
		net += difference * (8 if difference > 0 else 4)
	if net > player_funds(world,vessel) or -net > world.Treasury.available(station):
		return false
	for ware in materials:
		if Industry.available(station,ware) < int(materials[ware]):
			return false
	if not world.outfit(vessel.id,fit):
		return false
	Industry.consume(station,materials)
	player_pay(world,vessel,-net,"整备换装")
	world.Treasury.post(world,station,net,"整备换装")
	for i in range(current.weapons.size()):
		if current.weapons[i] != fit.weapons[i]:
			vessel.battle.cooldowns[i] = 0.0
	world.combat_event("trade",station.pos,station.system)
	return true

static func refit_tuning(world, port_id: int, caps_delta: int, vents_delta: int, target_ship_id: int = 0) -> bool:
	var vessel: Dictionary = refit_target(world, target_ship_id)
	var station: Dictionary = world.ports.get(port_id, {})
	if vessel.is_empty() or vessel.dock != port_id or station.is_empty() or station.build > 0 or not world.can_operate(vessel) or not allowed(world, vessel, station):
		return false
	if caps_delta == 0 and vents_delta == 0:
		return false
	var candidate: Hulls.Fitting = vessel.fit.copy()
	candidate.caps = int(candidate.caps) + caps_delta
	candidate.vents = int(candidate.vents) + vents_delta
	if Hulls.fitting_cost(vessel.kind, candidate) < 0:
		return false
	var added := maxi(0, caps_delta) + maxi(0, vents_delta)
	var removed := maxi(0, -caps_delta) + maxi(0, -vents_delta)
	var net := added * 8 - removed * 4
	if net > player_funds(world,vessel) or -net > world.Treasury.available(station):
		return false
	player_pay(world,vessel,-net,"整备换装")
	world.Treasury.post(world,station,net,"整备换装")
	vessel.fit = candidate
	world.combat_event("trade", station.pos, station.system)
	return true

static func refit_group(world, port_id: int, slot_index: int, group: int, target_ship_id: int = 0) -> bool:
	var vessel: Dictionary = refit_target(world, target_ship_id)
	var station: Dictionary = world.ports.get(port_id, {})
	if vessel.is_empty() or vessel.dock != port_id or station.is_empty() or station.build > 0 or not world.can_operate(vessel):
		return false
	if slot_index not in range(vessel.fit.groups.size()) or group not in [1, 2, 3]:
		return false
	vessel.fit.groups[slot_index] = group
	return true

static func advance(world) -> void:
	for station in world.ports.values():
		produce(world, station)
	for vessel in world.ships.values():
		step_ship(world, vessel,0.0)
		Diagnostics.sample(world,vessel)
	if world.day % 30 == 0:
		for index in range(world.core_count):
			var system: Dictionary = world.systems[index]
			system.ore = mini(180, system.ore + 14)
			for ware in system.get("deposits",{}):
				system.deposits[ware] = mini(180,system.deposits[ware]+14)

static func passenger_capacity(vessel: Dictionary) -> int:
	return clampi(6 + int(Hulls.MODELS[vessel.kind].size) * 4, 6, 18)

static func ticket_price(world, origin_id: int, dest_id: int) -> int:
	var p1: Dictionary = world.ports.get(origin_id, {})
	var p2: Dictionary = world.ports.get(dest_id, {})
	if p1.is_empty() or p2.is_empty():
		return 25
	var dist: float = world.distance(int(p1.system), int(p2.system))
	return clampi(roundi(12.0 + dist / 45.0), 15, 60)

static func passenger_fare(world, person: Dictionary, vessel: Dictionary, dest_id: int) -> int:
	var fare := ticket_price(world, int(vessel.dock), dest_id)
	var captain: Dictionary = world.people.get(vessel.captain, {})
	var negotiated := roundi(fare * 1.1)
	if not captain.is_empty() and captain.stats.diplomacy >= 9 and int(person.wallet) >= negotiated:
		fare = negotiated
	var peak := roundi(fare * 1.25)
	if vessel.get("passengers", []).size() * 2 >= passenger_capacity(vessel) and int(person.wallet) >= peak:
		fare = peak
	return fare

static func build_passenger_route(world, hub_id: int, carrier_flag: Variant = null) -> Array[int]:
	var hub: Dictionary = world.ports.get(hub_id, {})
	if hub.is_empty():
		return []
	var flag := int(hub.flag if carrier_flag == null else carrier_flag)
	if world.hostile(flag, int(hub.flag)):
		return []
	var by_sys := {}
	for port: Dictionary in world.ports.values():
		if int(port.id) == hub_id or int(port.build) != 0 or port.get("landing_only", false) or port.has("planet_index"):
			continue
		if world.hostile(int(hub.flag), int(port.flag)) or world.hostile(flag, int(port.flag)):
			continue
		var sys_id := int(port.system)
		if sys_id == int(hub.system):
			continue
		if not by_sys.has(sys_id) or int(port.pop) > int(world.ports[by_sys[sys_id]].pop):
			by_sys[sys_id] = int(port.id)
	var candidates: Array[Dictionary] = []
	for sys_id in by_sys:
		var pid: int = by_sys[sys_id]
		candidates.append({"id": pid, "dist": world.distance(int(hub.system), int(sys_id))})
	candidates.sort_custom(func(a, b): return float(a.dist) < float(b.dist) if float(a.dist) != float(b.dist) else int(a.id) < int(b.id))
	var route: Array[int] = [hub_id]
	for item in candidates.slice(0, 3):
		route.append(int(item.id))
	return route

static func docked_liners(world, port_id: int) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for sh: Dictionary in world.ships.values():
		if int(sh.get("dock", 0)) == port_id and sh.get("job", {}).get("kind", "") == "客运":
			list.append(sh)
	return list

static func assign_passenger_liner(world, ship_id: int, custom_route: Array = [], actor_id: int = 0) -> Dictionary:
	var vessel: Dictionary = world.ships.get(ship_id, {})
	if vessel.is_empty() or not world.oversees(world.ship_principal(vessel), actor_id):
		return {"ok": false, "reason": "无权调度该舰船。"}
	if int(vessel.captain) in [0, world.player]:
		return {"ok": false, "reason": "需先雇佣 NPC 代理人船长执掌该客船。"}
	var hub := int(vessel.dock) if int(vessel.dock) != 0 and world.ports.has(int(vessel.dock)) else int(world.systems[0].ports[0])
	var route: Array[int] = []
	if not custom_route.is_empty():
		for pid in custom_route:
			var id := int(pid)
			var st: Dictionary = world.ports.get(id, {})
			if not st.is_empty() and int(st.build) == 0 and not st.get("landing_only", false) and not world.hostile(int(vessel.flag), int(st.flag)) and id not in route:
				route.append(id)
	else:
		route = build_passenger_route(world, hub, vessel.flag)
	if route.size() < 2:
		return {"ok": false, "reason": "至少需要 2 座友好营业港口才能开通客运班线。"}
	if vessel.get("order_queue", []).is_empty():
		release_reservation(world, vessel)
		vessel.travel = {}
	vessel.erase("commander_id")
	vessel.erase("fleet_role")
	vessel.erase("resume_job")
	if not vessel.has("passengers"):
		vessel.passengers = []
	vessel.job = {"kind": "客运", "home_port": route[0], "route": route, "stop_index": 0, "layover": 1}
	vessel.default_behavior = vessel.job.duplicate(true)
	world.event("%s 已由代理人 %s 执飞自营客运班线（经停 %d 港）。" % [world.HULLS[vessel.kind], world.name_of(int(vessel.captain)), route.size()])
	return {"ok": true, "ship": ship_id, "route": route}

static func board_passenger(world, person_id: int, ship_id: int, dest_port_id: int, expected_fare: int = -1) -> Dictionary:
	var person: Dictionary = world.people.get(person_id, {})
	var vessel: Dictionary = world.ships.get(ship_id, {})
	if person.is_empty() or not person.alive or world.Politics.age(world, person) < 18:
		return {"ok": false, "reason": "乘客不符合登船条件。"}
	if int(person.get("ship", 0)) != 0 or int(person.get("transit_ship", 0)) != 0:
		return {"ok": false, "reason": "需先离舰且未处于乘船途中。"}
	if vessel.is_empty() or vessel.get("job", {}).get("kind", "") != "客运" or int(vessel.dock) == 0:
		return {"ok": false, "reason": "该客船当前未靠港。"}
	if int(person.loc) != int(vessel.dock):
		return {"ok": false, "reason": "需与客船在同一港口才能购票登船。"}
	var route: Array = vessel.job.get("route", [])
	if dest_port_id == int(vessel.dock) or dest_port_id not in route or not world.ports.has(dest_port_id):
		return {"ok": false, "reason": "目的地不在本班客船航线上。"}
	if world.hostile(int(person.flag), int(world.ports[dest_port_id].flag)):
		return {"ok": false, "reason": "敌对港口禁止购票前往。"}
	if not vessel.has("passengers"):
		vessel.passengers = []
	if vessel.passengers.size() >= passenger_capacity(vessel):
		return {"ok": false, "reason": "本班客船已满员。"}
	var fare := passenger_fare(world, person, vessel, dest_port_id)
	if expected_fare >= 0 and fare != expected_fare:
		return {"ok": false, "reason": "票价已变为 ¢%d，请重新购票。" % fare}
	if int(person.wallet) < fare:
		return {"ok": false, "reason": "信用点不足（票价 ¢%d）。" % fare}
	world.credit(person_id, -fare)
	var st_owner := int(vessel.get("station_owner", 0))
	if st_owner > 0 and world.ports.has(st_owner):
		world.Treasury.post(world, world.ports[st_owner], fare, "客运票款", false)
	elif vessel.has("firm") and world.firms.has(int(vessel.firm)):
		var f: Dictionary = world.firms[int(vessel.firm)]
		f.treasury = int(f.treasury) + fare
		f.revenue = int(f.get("revenue", 0)) + fare
		f.operating_profit = int(f.get("operating_profit", 0)) + fare
		world.Finances.record(world, int(f.director), {"id": int(vessel.firm), "name": f.name, "ledger_type": "company"}, "客运票款", fare, false, true)
	elif int(vessel.owner) > 0 and world.people.has(int(vessel.owner)):
		world.credit(int(vessel.owner), fare, vessel, "客运票款")
		world.Finances.record(world, int(vessel.owner), vessel, "客运票款", fare, false, false)
	elif world.ports.has(int(vessel.dock)):
		world.Treasury.post(world, world.ports[int(vessel.dock)], fare, "客运票款", false)
	vessel.passengers.append(person_id)
	person.loc = 0
	person.transit_ship = ship_id
	person.travel_dest = dest_port_id
	if person_id == world.player:
		world.event("已购票（¢%d）登上公共客船，前往 %s。" % [fare, world.ports[dest_port_id].name])
	return {"ok": true, "fare": fare, "ship": ship_id, "dest": dest_port_id}

static func disembark_passenger(world, person_id: int, port_id: int = 0) -> bool:
	var person: Dictionary = world.people.get(person_id, {})
	if person.is_empty():
		return false
	var ship_id := int(person.get("transit_ship", 0))
	if ship_id == 0:
		return false
	var vessel: Dictionary = world.ships.get(ship_id, {})
	var target_port := port_id if port_id > 0 else int(vessel.get("dock", 0))
	if target_port == 0 or not world.ports.has(target_port):
		return false
	if not vessel.is_empty() and vessel.has("passengers"):
		vessel.passengers.erase(person_id)
	person.loc = target_port
	person.erase("transit_ship")
	person.erase("travel_dest")
	return true

static func _disembark_arrived(world, vessel: Dictionary, port_id: int) -> void:
	var cur_port: Dictionary = world.ports.get(port_id, {})
	if cur_port.is_empty():
		return
	for pax_id in vessel.get("passengers", []).duplicate():
		var pax: Dictionary = world.people.get(int(pax_id), {})
		if pax.is_empty() or not pax.alive:
			vessel.passengers.erase(pax_id)
			continue
		var dest := int(pax.get("travel_dest", 0))
		if dest == port_id or dest == 0 or not world.ports.has(dest) or world.hostile(int(pax.flag), int(world.ports[dest].flag)):
			disembark_passenger(world, int(pax_id), port_id)
			if int(pax_id) == world.player:
				world.event("已随公共客船抵达 %s 并下船。" % cur_port.name)

static func step_passenger_ship(world, vessel: Dictionary) -> void:
	if not vessel.has("passengers"):
		vessel.passengers = []
	var job: Dictionary = vessel.job
	var hub_id := int(job.get("home_port", vessel.get("station_owner", vessel.dock)))
	var raw_route: Array = job.get("route", [])
	var route: Array[int] = []
	for pid in raw_route:
		var st: Dictionary = world.ports.get(int(pid), {})
		if not st.is_empty() and int(st.build) == 0 and not st.get("landing_only", false) and not world.hostile(int(vessel.flag), int(st.flag)):
			if int(pid) not in route:
				route.append(int(pid))
	if route.size() < 2 and world.ports.has(hub_id):
		route = build_passenger_route(world, hub_id, vessel.flag)
	job.route = route
	if route.size() < 2 or int(vessel.dock) == 0:
		return
	var cur_port_id := int(vessel.dock)
	var cur_port: Dictionary = world.ports.get(cur_port_id, {})
	if cur_port.is_empty():
		return
	# 1. Disembark arrived or invalid passengers
	_disembark_arrived(world, vessel, cur_port_id)
	# 2. Refuel at current port
	refuel_trader(world, vessel, cur_port)
	# 3. Board waiting NPCs bound for any other stop on this route
	var cap := passenger_capacity(vessel)
	if vessel.passengers.size() < cap:
		for other: Dictionary in world.people.values():
			if vessel.passengers.size() >= cap:
				break
			if not other.alive or int(other.id) == world.player or int(other.id) == world.regency:
				continue
			if int(other.loc) != cur_port_id or int(other.ship) != 0 or int(other.get("transit_ship", 0)) != 0:
				continue
			var want_dest := int(other.get("travel_dest", 0))
			if want_dest != 0 and want_dest != cur_port_id and want_dest in route:
				board_passenger(world, int(other.id), int(vessel.id), want_dest)
	# 4. Layover then depart to next stop on route
	var layover := int(job.get("layover", 0))
	if layover > 0:
		job.layover = layover - 1
		return
	var idx := route.find(cur_port_id)
	var next_idx := (idx + 1) % route.size() if idx >= 0 else 0
	var next_port: Dictionary = world.ports.get(route[next_idx], {})
	if not next_port.is_empty() and int(next_port.id) != cur_port_id:
		job.stop_index = next_idx
		job.layover = 1
		begin_trip(world, vessel, next_port)

## Used ship market: depreciated trade-in & purchase with preserved service history.
static func used_hull_price(world, station: Dictionary, kind: int, built_day: int) -> int:
	var base := int(ship_quote(station, kind).price)
	var age_years := maxf(0.0, float(world.day - built_day) / 360.0)
	var dep := clampf(0.68 - age_years * 0.04, 0.42, 0.68)
	return maxi(60, roundi(float(base) * dep))

static func sell_used_ship_to_yard(world, ship_id: int, port_id: int) -> int:
	var vessel: Dictionary = world.ships.get(ship_id, {})
	var station: Dictionary = world.ports.get(port_id, {})
	if vessel.is_empty() or station.is_empty() or int(station.build) != 0 or int(vessel.dock) != port_id:
		return 0
	if int(vessel.owner) <= 0 or not world.people.has(int(vessel.owner)) or int(vessel.captain) != 0:
		return 0
	var quote := used_hull_price(world, station, int(vessel.kind), int(vessel.get("built_day", 0)))
	if world.Treasury.available(station) < quote or not world.Treasury.post(world, station, -quote, "二手船回收", true):
		return 0
	var owner_id := int(vessel.owner)
	world.credit(owner_id, quote)
	var hist: Array = vessel.get("history", []).duplicate()
	hist.append("%d年 于 %s 折价挂牌二手船" % [2400 + world.day / 360, station.name])
	var used_list: Array = station.get_or_add("used_hulls", [])
	used_list.append({"id": world.uid(), "kind": int(vessel.kind), "built_day": int(vessel.get("built_day", 0)),
		"price": roundi(float(quote) * 1.15), "history": hist.slice(maxi(0, hist.size() - 8))})
	if used_list.size() > 6:
		used_list.pop_front()
	world.ships.erase(ship_id)
	return quote

static func buy_used_ship(world, buyer_id: int, port_id: int, listing_id: int) -> int:
	var buyer: Dictionary = world.people.get(buyer_id, {})
	var station: Dictionary = world.ports.get(port_id, {})
	if buyer.is_empty() or not buyer.alive or station.is_empty() or int(station.build) != 0:
		return 0
	var used_list: Array = station.get("used_hulls", [])
	var idx := -1
	for i in used_list.size():
		if int(used_list[i].get("id", 0)) == listing_id:
			idx = i
			break
	if idx < 0:
		return 0
	var item: Dictionary = used_list[idx]
	var cost := int(item.get("price", 0))
	if cost <= 0 or int(buyer.wallet) < cost:
		return 0
	world.credit(buyer_id, -cost)
	world.Treasury.post(world, station, cost, "二手船售出", false)
	var sid: int = world.ship(int(item.kind), buyer_id, 0, int(buyer.flag), int(station.system), station.pos, port_id)
	world.ships[sid].built_day = int(item.get("built_day", world.day))
	var hist: Array = item.get("history", []).duplicate()
	hist.append("%d年 由 %s 购入再服役" % [2400 + world.day / 360, buyer.name])
	world.ships[sid].history = hist
	used_list.remove_at(idx)
	return sid
