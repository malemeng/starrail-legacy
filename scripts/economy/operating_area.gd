extends RefCounted

const Industry = preload("res://scripts/economy/industry.gd")
const Security = preload("res://scripts/economy/merchant_security.gd")

static func automatic(ship: Dictionary) -> bool:
	var job: Dictionary = ship.get("job",{})
	return ship.get("order_queue",[]).is_empty() and job.get("kind","") in ["贸易","采矿","站属贸易","站属采矿"] and ((ship.owner == 0 and not ship.has("firm")) or job.get("automatic",false) or ship.get("fleet_role","") == "MIMIC" and not ship.get("default_behavior",{}).has("source"))

static func settings(world, ship: Dictionary) -> Dictionary:
	var saved: Dictionary = ship.get("operating_area",{})
	var job: Dictionary = ship.get("job",{})
	var home: int = job.get("home_port",saved.get("port",ship.dock))
	var system: int = world.ports.get(home,{}).get("system",saved.get("system",ship.system))
	var rules: Dictionary = Industry.RULES.operating_area
	var mining := "采矿" in str(job.get("kind",""))
	var jumps: int = rules.mining_jumps if mining else rules.trade_jumps
	if world.ports.has(home):
		jumps = mini(jumps,world.Economy.management_radius(world,ship,world.ports[home]))
	if not mining:
		var capacity: int = world.HULL_CARGO[ship.kind]
		jumps += mini(int(rules.max_extra_trade_jumps),capacity / int(rules.cargo_per_extra_trade_jump))
		if world.ports.get(home,{}).get("harvest_carriers",{}).has(ship.id):
			jumps = maxi(jumps,int(rules.trade_jumps)+1)
		jumps = mini(jumps,int(rules.maximum_jumps))
	return {"port":home,"system":system,"jumps":int(saved.get("jumps",jumps))}

static func anchor(world, ship: Dictionary) -> void:
	if not ship.has("operating_area"):
		var area := settings(world,ship)
		ship.operating_area = {"port":area.port,"system":area.system}

static func apply_next(ship: Dictionary) -> void:
	if ship.has("next_operating_area"):
		ship.operating_area = ship.next_operating_area
		ship.erase("next_operating_area")
		ship.job.erase("retry_day")

static func configure(world, ship_id: int, port_id: int, jumps: int) -> bool:
	var ship: Dictionary = world.ships.get(ship_id,{})
	var home: Dictionary = world.ports.get(port_id,{})
	if ship.is_empty() or home.is_empty() or not world.oversees(world.ship_principal(ship)) or jumps < 0 or jumps > int(Industry.RULES.operating_area.maximum_jumps):
		return false
	if ship.job.has("home_port") and ship.job.home_port != port_id:
		return false
	if not world.systems[home.system].seen and not world.oversees(home.owner):
		return false
	var area := {"port":port_id,"system":home.system,"jumps":jumps}
	if automatic(ship) and ship.job.has("source") and (not ship.travel.is_empty() or not ship.get("reservation",{}).is_empty() or ship.job.get("phase",0) == 1):
		ship.next_operating_area = area
	else:
		ship.operating_area = area
		ship.erase("next_operating_area")
		if automatic(ship):
			ship.job.erase("source")
			ship.job.erase("retry_day")
	return true

static func coverage(world, ship: Dictionary) -> Dictionary:
	anchor(world,ship)
	var area := settings(world,ship)
	var blocked := Security.exclusions(world,ship)
	var reached: Dictionary = world.Economy.reachable_systems(world,area.system,area.jumps,blocked)
	if area.system in blocked:
		reached = reached.duplicate()
		reached.erase(area.system)
	return reached
