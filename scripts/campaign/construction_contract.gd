extends RefCounted

const Hulls = preload("res://hull_catalog.gd")
const Industry = preload("res://scripts/economy/industry.gd")
const HULL_ID := "gantry_ca"

static func active_ship(world) -> Dictionary:
	for ship: Dictionary in world.ships.values():
		var contract: Dictionary = ship.get("construction_contract",{})
		if contract.get("status","") in ["active","working"] and contract.client == world.player:
			return ship
	return {}

static func is_escort(ship: Dictionary, lead: Dictionary, player_id: int) -> bool:
	var contract: Dictionary = ship.get("construction_contract",{})
	return contract.get("status","") == "active" and contract.client == player_id and lead.get("captain",0) == player_id and ship.captain != 0

static func offer(world, port_id: int) -> Dictionary:
	var result := {"ok":false,"fee":0,"hull_id":HULL_ID,"ship_id":0,"reason":""}
	var yard: Dictionary = world.ports.get(port_id,{})
	var kind := Hulls.kind_for_id(HULL_ID)
	var flagship: Dictionary = world.ride()
	if kind < 0 or yard.is_empty() or yard.build > 0 or Industry.Module.YARD not in yard.modules or not Hulls.model_limit(yard,kind):
		result.reason = "需要能接纳工程巡洋舰的营业船厂。"
		return result
	result.fee = ceili(float(world.Economy.ship_quote(yard,kind).price) * float(Industry.RULES.ship_market.engineering_contract_share))
	if flagship.get("dock",0) != port_id or not world.Economy.allowed(world,flagship,yard):
		result.reason = "须驾驶旗舰停靠签约船厂。"
		return result
	if not active_ship(world).is_empty():
		result.reason = "当前工程合同仍在执行。"
		return result
	for ship: Dictionary in world.ships.values():
		var contract: Dictionary = ship.get("construction_contract",{})
		if ship.dock == port_id and ship.captain != 0 and contract.get("status","") == "available" and contract.home == port_id:
			result.ship_id = ship.id
			break
	if result.ship_id == 0 and yard.hulls[kind] <= 0:
		result.reason = "本站没有在港承包舰或完工工程舰。"
	elif world.active().wallet < result.fee:
		result.reason = "账户不足以支付本次施工服务费。"
	else:
		result.ok = true
	return result

static func hire(world, port_id: int) -> int:
	var quote := offer(world,port_id)
	if not quote.ok:
		return 0
	var yard: Dictionary = world.ports[port_id]
	var id: int = quote.ship_id
	if id == 0:
		var kind := Hulls.kind_for_id(HULL_ID)
		if not Industry.station_data(yard).withdraw_hull(kind):
			return 0
		var captain: int = world.random_person(world.NEUTRAL,port_id)
		id = world.ship(kind,0,captain,world.NEUTRAL,yard.system,yard.pos,port_id)
	var ship: Dictionary = world.ships[id]
	world.credit(world.player,-quote.fee,ship,"工程舰雇佣")
	var wages := floori(quote.fee * float(Industry.RULES.ship_market.engineering_crew_share))
	world.credit(ship.captain,wages)
	world.Treasury.post(world,yard,quote.fee-wages,"工程舰租赁")
	ship.construction_contract = {"client":world.player,"home":port_id,"site":0,"status":"active","fee":quote.fee,"signed_day":world.day}
	ship.commander_id = world.ride().id
	ship.job = {"kind":"工程承包"}
	return id

static func assign_site(world, ship_id: int, site_id: int) -> bool:
	var ship: Dictionary = world.ships.get(ship_id,{})
	var site: Dictionary = world.ports.get(site_id,{})
	if not is_escort(ship,world.ride(),world.player) or site.get("construction_ship",0) != ship_id or site.owner != world.player:
		return false
	if ship.layer or ship.dock != 0 or ship.system != site.system or ship.construction_contract.site != 0 or Vector2(ship.pos).distance_to(site.pos) > Industry.CONSTRUCTION.ship_work_range:
		return false
	ship.construction_contract.site = site_id
	ship.construction_contract.status = "working"
	ship.erase("commander_id")
	ship.battle.target_id = 0
	ship.job = {"kind":"现场施工"}
	advance(world,ship)
	return true

static func cancel(world) -> bool:
	var ship := active_ship(world)
	if ship.is_empty() or ship.construction_contract.status != "active":
		return false
	return_to_yard(world,ship)
	return true

static func return_to_yard(world, ship: Dictionary) -> void:
	ship.erase("commander_id")
	ship.battle.target_id = 0
	ship.construction_contract.status = "returning"
	ship.job = {"kind":"工程返航"}
	advance(world,ship)

static func advance(world, ship: Dictionary) -> void:
	var contract: Dictionary = ship.construction_contract
	if ship.locked or not ship.travel.is_empty():
		return
	if contract.status == "active" and not world.people.get(contract.client,{}).get("alive",false):
		return_to_yard(world,ship)
		return
	if contract.status == "working":
		var site: Dictionary = world.ports.get(contract.site,{})
		if site.is_empty() or site.build == 0:
			return_to_yard(world,ship)
		elif ship.dock != site.id:
			world.Economy.begin_trip(world,ship,site)
		return
	if contract.status != "returning":
		return
	if ship.dock == contract.home:
		contract.status = "available"
		contract.client = 0
		ship.job = {}
		return
	var yard: Dictionary = world.ports.get(contract.home,{})
	if yard.is_empty():
		return
	world.Economy.begin_trip(world,ship,yard)
	if not ship.travel.is_empty():
		return
	# A return beyond one tank may need a real fuel stop along the charted route.
	var route: Array = world.Economy.flight_route(world,ship.system,yard.system,[])
	var stops: Array = [ship.system] + route
	stops.reverse()
	for system_id in stops:
		for port_id in world.systems[system_id].ports:
			var port: Dictionary = world.ports[port_id]
			if port_id == ship.dock or port_id == yard.id or port.build > 0 or Industry.available(port,Industry.Ware.FUEL) <= 0 or not world.Economy.allowed(world,ship,port):
				continue
			world.Economy.begin_trip(world,ship,port)
			if not ship.travel.is_empty():
				return
