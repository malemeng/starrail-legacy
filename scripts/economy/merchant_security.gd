extends RefCounted

const FleetOrder = preload("res://scripts/models/fleet_order.gd")
const Hulls = preload("res://hull_catalog.gd")
const HAULING := ["贸易","采矿","自动贸易","自动采矿","站属贸易","站属采矿","施工配送","补给"]
const INCIDENT_DAYS := 7

static func commercial(ship: Dictionary) -> bool:
	if ship.has("reservation") or ship.get("travel",{}).has("rebook") or ship.get("job",{}).get("kind","") in HAULING:
		return true
	for order: Dictionary in ship.get("order_queue",[]):
		if FleetOrder.carries_goods(order.kind) or (order.kind == "dock" and "civgrade" in Hulls.MODELS[ship.kind].builtins):
			return true
	return false

static func clearance(world, vessel: Dictionary, flag: int) -> bool:
	if flag == world.NEUTRAL:
		return true
	var authority := {"flag":flag}
	if world.enemy(vessel,authority):
		return false
	if vessel.flag == world.NEUTRAL:
		var captain: Dictionary = world.people.get(vessel.get("captain",0),{})
		if not captain.is_empty() and captain.flag != world.NEUTRAL:
			return not world.enemy(captain,authority)
	return true

static func dangerous(world, vessel: Dictionary, system: int) -> bool:
	if not clearance(world,vessel,world.local_flag(system)):
		return true
	var region: Dictionary = world.systems[system]
	var base: Dictionary = region.get("outlaw_base",{})
	if not base.is_empty():
		var flag := int(world.Outlaws.groups[base.group].flag)
		if not clearance(world,vessel,flag):
			if int(base.get("reserve",0)) > 0:
				return true
			for id: int in base.get("members",[]):
				if world.Outlaws.on_roster(world,id,base.group):
					return true
	if not region.get("wild",false) or not region.get("pirate",false) or clearance(world,vessel,world.RAIDERS):
		return false
	if not region.get("spawned",false):
		return true
	if region.has("pirate_patrol"):
		return world.Outlaws.on_roster(world,region.pirate_patrol,world.Outlaws.PIRATES)
	for patrol: Dictionary in world.ships.values():
		if patrol.system == system and world.Outlaws.id_for(patrol) == world.Outlaws.PIRATES and patrol.hp > 0:
			return true
	return false

static func exclusions(world, vessel: Dictionary) -> Array:
	var skipped: Array = vessel.get("trade_rules",{}).get("travel",[]).duplicate()
	for system in world.systems.size():
		if dangerous(world,vessel,system) and system not in skipped:
			skipped.append(system)
	return skipped

static func threatened_route(world, vessel: Dictionary, route: Array) -> bool:
	for system: int in route:
		if system in vessel.get("trade_rules",{}).get("travel",[]) or dangerous(world,vessel,system):
			return true
	return false

static func report_attack(world, vessel: Dictionary, aggressor: Dictionary) -> void:
	if not commercial(vessel) or aggressor.is_empty() or not world.enemy(vessel,aggressor):
		return
	var reservation: Dictionary = vessel.get("reservation",{})
	var receiver: Dictionary = world.ports.get(reservation.get("target",0),{})
	if not world.oversees(world.Hulls.operator_id(vessel)) and not world.oversees(receiver.get("owner",0)):
		return
	var latest: Dictionary = vessel.get("trade_attack",{})
	vessel.trade_attack = {"day":world.day,"system":vessel.system}
	if latest.get("system",-1) == vessel.system and world.day-latest.day <= INCIDENT_DAYS:
		return
	var incidents: Dictionary = world.campaign.get("trade_incidents",{})
	for system in incidents.keys():
		if world.day-int(incidents[system].day) > INCIDENT_DAYS:
			incidents.erase(system)
	world.campaign.trade_incidents = incidents
	var group: Dictionary = incidents.get(vessel.system,{})
	var label := "%s #%d" % [world.HULLS[vessel.kind],vessel.id]
	if group.is_empty() or world.day-group.day > INCIDENT_DAYS:
		group = {"day":world.day,"ships":[],"message":""}
	if label not in group.ships:
		group.ships.append(label)
	var names := PackedStringArray(group.ships.slice(0,3))
	var extra := " 等 %d 艘" % group.ships.size() if group.ships.size() > 3 else ""
	var message := "商船遇袭 · %s：%s%s" % [world.systems[vessel.system].name,"、".join(names),extra]
	var merged := false
	for row: Array in world.chronicle:
		if row[0] == group.day and row[1] == group.message:
			row[1] = message
			merged = true
			break
	if not merged:
		group.day = world.day
		world.event(message)
	group.message = message
	incidents[vessel.system] = group
	world.merchant_attacked.emit(message)
