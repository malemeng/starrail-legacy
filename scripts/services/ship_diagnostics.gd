extends RefCounted

const Industry = preload("res://scripts/economy/industry.gd")
const Hyperspace = preload("res://scripts/campaign/hyperspace.gd")
const SAMPLE_LIMIT := 16
const EVENT_LIMIT := 48

static func accessible(world, ship: Dictionary) -> bool:
	if ship.is_empty():
		return false
	if world.can_operate(ship):
		return true
	var home: Dictionary = world.ports.get(ship.get("station_owner", 0), {})
	return not home.is_empty() and world.Dividends.can_manage(world,home)

static func append_bounded(ship: Dictionary, key: String, entry: Dictionary, limit: int) -> void:
	var entries: Array = ship.get_or_add(key, [])
	entries.append(entry)
	while entries.size() > limit:
		entries.pop_front()

static func record(world, ship: Dictionary, event: String, details: Dictionary) -> void:
	if accessible(world, ship):
		append_bounded(ship, "diagnostic_events", {"day":world.day, "event":event, "details":details}, EVENT_LIMIT)

static func account(world, ship: Dictionary) -> String:
	var home: Dictionary = world.Economy.operating_port(world, ship)
	if not home.is_empty():
		return "%s 运营账户 #%d" % [home.name, home.id]
	if ship.has("firm"):
		return "%s 公司账户 #%d" % [world.firms[ship.firm].name,ship.firm]
	if ship.has("charter"):
		return person_name(world,ship.charter.operator)
	if ship.owner == 0 and world.factions.has(ship.flag):
		return "%s 国库" % world.flag_name(ship.flag)
	var person: int = ship.owner if ship.owner != 0 else ship.captain
	return "%s #%d" % [world.name_of(person), person]

static func person_name(world, id: int) -> String:
	return "%s #%d" % [world.name_of(id),id] if world.people.has(id) else "无"

static func transfer(world, ship: Dictionary, category: String, other: String, amount: int, units: int = 0, tax: int = 0, tax_flag: int = -1, personal: int = 0) -> void:
	if amount == 0 or not accessible(world, ship):
		return
	var operator := person_name(world,personal) if personal else account(world,ship)
	var sender := other if amount > 0 else operator
	record(world, ship, category, {"from":sender, "to":operator if amount > 0 else other,
		"amount":amount if amount > 0 else -amount-tax, "net_to_operator":amount, "units":units, "tax":tax,
		"tax_from":sender, "tax_to":world.flag_name(tax_flag) if tax else "",
		"owner":ship.owner, "captain":ship.captain, "firm":ship.get("firm",0), "operator_funds":world.Economy.account_balance(world,ship),
		"owner_wallet":world.people.get(ship.owner,{}).get("wallet"),
		"captain_wallet":world.people.get(ship.captain,{}).get("wallet")})

static func port_name(world, id: int) -> String:
	return "%s #%d" % [world.ports[id].name, id] if world.ports.has(id) else "—"

static func point(pos: Vector2) -> Array:
	return [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)]

## Follow the actual waypoint list. Distances in local space and hyperspace use different units.
static func navigation(world, ship: Dictionary) -> Dictionary:
	var trip: Dictionary = ship.travel
	var target: Dictionary = world.ports.get(trip.get("port", 0), {})
	if target.is_empty():
		return {}
	var origin: Vector2 = ship.galpos if ship.layer else world.systems[ship.system].pos
	var chart_distance := 0.0
	for system_id in trip.get("waypoints", []):
		var beacon: Vector2 = world.systems[system_id].pos
		chart_distance += origin.distance_to(beacon)
		origin = beacon
	var destination: Vector2
	var label: String
	if ship.layer:
		var route: Array = trip.get("waypoints", [])
		if route.is_empty():
			return {"target":target.id, "leg":"等待更新超空间航路", "hold":trip.get("hold", false)}
		destination = world.systems[route[0]].pos
		label = "%s 信标" % world.systems[route[0]].name
	elif ship.system != target.system:
		destination = world.Celestial.gravity_point(world.systems[ship.system])
		label = "恒星引力点"
	elif trip.get("activity", "") == "mine":
		destination = world.systems[ship.system].field
		label = "矿带"
	else:
		destination = target.pos
		label = port_name(world, target.id)
	var position: Vector2 = ship.galpos if ship.layer else ship.pos
	return {"target":target.id, "leg":label, "distance":snappedf(position.distance_to(destination), 0.1),
		"waypoint":point(destination), "layer":"超空间" if ship.layer else "星系内",
		"fuel_required":Hyperspace.fuel_for_distance(world.Hulls.MODELS[ship.kind], chart_distance), "hold":trip.get("hold", false)}

static func sample(world, ship: Dictionary) -> void:
	if not accessible(world, ship):
		return
	var nav := navigation(world, ship)
	append_bounded(ship, "diagnostic_samples", {"day":world.day, "system":ship.system, "dock":ship.dock,
		"layer":ship.layer, "position":point(ship.galpos if ship.layer else ship.pos), "fuel":ship.fuel,
		"phase":ship.job.get("phase", 0), "goal":nav.get("leg", ""), "distance":nav.get("distance", -1)}, SAMPLE_LIMIT)

static func status(world, ship: Dictionary) -> String:
	if ship.captain == 0:
		return "未任命船长"
	if ship.locked:
		return "交火锁定"
	if not str(ship.get("route_hold", "")).is_empty():
		return str(ship.route_hold)
	if not ship.get("order_queue", []).is_empty():
		return "正在执行队列命令 %s" % ship.order_queue[0].kind
	var job: Dictionary = ship.job
	if job.get("kind", "") in ["贸易", "站属贸易", "采矿", "站属采矿"]:
		if not job.has("source"):
			var retry := int(job.get("retry_day", 0))
			return "等待选单，第 %d 天起重试" % retry if retry > world.day else "等待调度选单"
		var loading: bool = job.get("phase", 0) == 0
		var verb := ("前往矿带" if "采矿" in job.kind else "取货") if loading else "交付"
		return "%s · %s" % [verb, port_name(world, job.get("source" if loading else "target", 0))]
	return str(job.get("label", job.get("kind", "未分配任务")))

static func snapshot(world, id: int) -> Dictionary:
	var ship: Dictionary = world.ships.get(id, {})
	if not accessible(world, ship):
		return {}
	var dock: Dictionary = world.ports.get(ship.dock, {})
	var home: Dictionary = world.Economy.operating_port(world, ship)
	var finances: Dictionary = world.Finances.report(world, 90)
	var account_id: int = home.get("id", id)
	var books := {"income":0, "expense":0, "net":0, "lines":{}}
	for row: Dictionary in finances.assets:
		if row.id == account_id:
			books = row
			break
	var cargo := {}
	for ware in ship.cargo.size():
		if ship.cargo[ware] > 0:
			cargo[world.WARES[ware]] = ship.cargo[ware]
	var job: Dictionary = ship.job
	var ware := int(job.get("ware", -1))
	var worker: Dictionary = world.people.get(ship.captain,{})
	var station_title: Dictionary = world.ports.get(ship.get("station_owner",0),{})
	var title := person_name(world,ship.owner) if ship.owner else str(station_title.get("name",world.flag_name(ship.flag)))
	if ship.has("firm"):
		title = "%s #%d" % [world.firms[ship.firm].name,ship.firm]
	elif ship.has("charter"):
		title = "航务局配舰"
	var superior: int = world.reports_to(worker) if not worker.is_empty() else 0
	var commander: Dictionary = world.ships.get(ship.get("commander_id",0),{})
	var command := "本船船长" if worker else "未任命船长"
	if not commander.is_empty():
		command = "指挥舰 #%d · %s" % [commander.id,person_name(world,commander.captain)]
	elif not home.is_empty():
		command = "%s · 站长 %s" % [home.name,person_name(world,home.get("manager",0))]
	var salaried: bool = ship.captain != 0 and superior != 0 and superior != ship.captain and superior == world.ship_principal(ship)
	return {"day":world.day, "seed":world.settings.seed, "ship":id, "model":world.HULLS[ship.kind],
		"owner":ship.owner, "captain":ship.captain, "captain_name":world.name_of(ship.captain) if ship.captain else "未任命",
		"title_holder":title, "owner_wallet":world.people.get(ship.owner,{}).get("wallet"),
		"captain_wallet":worker.get("wallet"), "employer":superior, "firm":ship.get("firm",0),
		"employer_name":person_name(world,superior), "command":command,
		"quarterly_salary":int(Industry.RULES.ship_market.captain_quarterly_pay) if salaried else 0,
		"account":account(world,ship), "available_funds":world.Economy.account_balance(world,ship),
		"system":world.systems[ship.system].name, "dock":ship.dock, "port":port_name(world,ship.dock),
		"position":point(ship.galpos if ship.layer else ship.pos), "layer":"超空间" if ship.layer else "星系内",
		"status":status(world,ship), "job":job.duplicate(true), "cargo":cargo, "free_space":world.cargo_free(ship),
		"ware":world.WARES[ware] if ware in range(world.WARES.size()) else "",
		"source":port_name(world,job.get("source",0)), "destination":port_name(world,job.get("target",0)),
		"reservation":ship.get("reservation",{}).duplicate(true), "navigation":navigation(world,ship),
		"fuel":ship.fuel, "pump_available":Industry.available(dock,Industry.Ware.FUEL) if not dock.is_empty() else null,
		"books":books, "book_scope":"本船" if home.is_empty() else "母港合计", "from_day":finances.from_day,
		"samples":ship.get("diagnostic_samples",[]).duplicate(true), "events":ship.get("diagnostic_events",[]).duplicate(true)}
