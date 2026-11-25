extends RefCounted

const Industry = preload("res://scripts/economy/industry.gd")

static func at_market(world, ship: Dictionary, port: Dictionary) -> bool:
	return not ship.is_empty() and ship.dock == port.id and ship.system == port.system and not ship.layer and world.active().loc == port.id and port.build == 0 and not port.get("blockaded",false) and world.Economy.allowed(world,ship,port)

## A public procurement notice quotes goods at the receiving market and a fixed haulage fee.
static func offer(world, source: Dictionary) -> Dictionary:
	var ship: Dictionary = world.ride()
	if not at_market(world,ship,source):
		return {}
	var rules: Dictionary = Industry.RULES.freight_notices
	var units := int(rules.lot_size)
	var supplies := {}
	for ware: int in source.exports:
		if Industry.available(source,ware) < units or world.cargo_free(ship) + ship.cargo[ware] < units:
			continue
		var missing := maxi(0,units-int(ship.cargo[ware]))
		var quote := Industry.lot_quote(source,ware,units,true,world.active().origin)
		var cash_needed := quote.y if missing == units else Industry.lot_quote(source,ware,missing,true,world.active().origin).y
		if cash_needed <= world.Economy.player_funds(world,ship):
			supplies[ware] = {"cost":quote.y,"cash_needed":cash_needed}
	if supplies.is_empty():
		return {}
	var carrier := ship.duplicate()
	carrier.job = {"kind":"贸易"}
	var excluded: Array = world.Economy.MerchantSecurity.exclusions(world,carrier)
	var area: Dictionary = world.Economy.reachable_systems(world,source.system,int(rules.search_jumps),excluded)
	var best := {}
	var greatest_need := -1.0
	for receiver: Dictionary in world.ports.values():
		if receiver.id == source.id or receiver.build > 0 or receiver.get("blockaded",false) or receiver.system in excluded or not area.has(receiver.system):
			continue
		if world.Economy.forbidden(ship,receiver) or not world.Economy.allowed(world,ship,receiver):
			continue
		var trip: Dictionary = world.Economy.trip_plan(world,carrier,source.system,source.pos,false,receiver,0,false,area)
		if trip.is_empty() or trip.fuel > 100.0:
			continue
		for ware: int in supplies:
			if ware not in receiver.imports or Industry.space(receiver,ware) < units:
				continue
			var target := Industry.stock_target(ware)
			var incoming := 0
			for booking: Dictionary in receiver.inbound.values():
				if booking.ware == ware:
					incoming += int(booking.qty)
			var deficit := target - int(receiver.stock[ware]) - incoming
			if deficit < units:
				continue
			var quote := Industry.lot_invoice(receiver,ware,units,false)
			var fee := ceili(float(trip.fuel)) + roundi(units * float(Industry.BASE[ware]) * float(rules.handling_fraction))
			var carried_fuel := maxi(0,int(ship.cargo[Industry.Ware.FUEL]) - (units if ware == Industry.Ware.FUEL else 0))
			var refuel := maxi(0,ceili(float(trip.fuel)-float(ship.fuel))-carried_fuel)
			var fuel_supply := Industry.available(source,Industry.Ware.FUEL)
			if ware == Industry.Ware.FUEL:
				fuel_supply -= maxi(0,units-int(ship.cargo[ware]))
			if refuel > fuel_supply or refuel + supplies[ware].cash_needed > world.Economy.player_funds(world,ship):
				continue
			if quote.total <= supplies[ware].cost or Industry.Treasury.available(receiver) < quote.base + fee:
				continue
			var need := deficit / target
			if need < greatest_need or (is_equal_approx(need,greatest_need) and trip.days >= best.days):
				continue
			greatest_need = need
			best = {"type":0,"source":source.id,"target":receiver.id,"ware":ware,"quantity":units,
				"fee":fee,"estimate":quote.total,"jumps":trip.route.size(),"days":trip.days}
	return best

static func accept(world, notice: Dictionary) -> bool:
	if notice.is_empty() or world.contracts.has(world.player):
		return false
	var source: Dictionary = world.ports.get(notice.source,{})
	if source.is_empty() or offer(world,source) != notice:
		return false
	world.contracts[world.player] = notice.duplicate()
	return true

static func deliver(world, receiver: Dictionary) -> int:
	var contract: Dictionary = world.contracts.get(world.player,{})
	var ship: Dictionary = world.ride()
	if contract.get("type",-1) != 0 or contract.target != receiver.id or not at_market(world,ship,receiver):
		return 0
	if world.Economy.forbidden(ship,receiver):
		return 0
	var ware := int(contract.get("ware",Industry.Ware.ORE))
	var units := int(contract.get("quantity",8))
	var fee := int(contract.get("fee",0))
	var invoice: Dictionary = world.Economy.trade_invoice(world,receiver,ware,-units)
	if invoice.units != units or Industry.Treasury.available(receiver) < invoice.base + fee:
		return 0
	if world.Economy.trade(world,receiver.id,ware,-units) != -units:
		return 0
	world.contracts.erase(world.player)
	if fee > 0:
		world.Treasury.post(world,receiver,-fee,"货运委托")
		world.Economy.player_pay(world,ship,fee,"货运委托")
	world.change_faction_trust(receiver.flag,world.player,4,"完成 %s 的货运委托" % receiver.name)
	return int(invoice.total) + fee
