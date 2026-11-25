extends RefCounted

const Person = preload("res://scripts/models/person_data.gd")
const Ship = preload("res://scripts/models/ship_data.gd")
const Industry = preload("res://scripts/economy/industry.gd")
const StationEquity = preload("res://scripts/economy/station_equity.gd")
const DiplomaticTrade = preload("res://scripts/economy/diplomatic_trade.gd")
const StationDesign = preload("res://scripts/models/station_design.gd")
const Hulls = preload("res://hull_catalog.gd")
const VERSION := 7
const TABLES := ["settings", "ports", "people", "factions", "ships", "wrecks", "relations",
	"contracts", "firms", "chunks", "intel", "campaign"]
const LISTS := ["systems", "chronicle"]
const NUMBERS := ["day", "player", "next_id", "last_player", "regency", "regent", "core_count"]

static func capture(world) -> Dictionary:
	var data := {"save_version": VERSION, "rng_seed": world.rng.seed, "rng_state": world.rng.state,
		"succession": world.succession}
	for key in TABLES + LISTS:
		data[key] = {} if key in ["people","ships"] else world.get(key).duplicate(true)
	for key in NUMBERS:
		data[key] = world.get(key)
	for id in world.people:
		data.people[id] = Person.encode(world.people[id])
	for id in world.ships:
		data.ships[id] = Ship.encode(world.ships[id])
	for port in data.ports.values():
		port.erase("tariff_flag")
		port.erase("tariff_rate")
		var stock := {}
		for kind in range(port.hulls.size()):
			if port.hulls[kind] > 0:
				stock[Hulls.hull_id(kind)] = port.hulls[kind]
		port.hulls = stock
		port.production_orders = port.production_orders.map(func(kind): return Hulls.hull_id(kind))
		if port.has("yard_work"):
			port.yard_work.kind = Hulls.hull_id(port.yard_work.kind)
	return data

static func decode(data: Dictionary, wares: int) -> Dictionary:
	if data.get("save_version") != VERSION or not data.get("succession") is bool:
		return {}
	for key in TABLES:
		if not data.get(key) is Dictionary:
			return {}
	var capital: Variant = data.campaign.get("market_capital")
	if not capital is Dictionary:
		return {}
	for market in ["core","frontier"]:
		if not capital.get(market) is int or capital[market] < 0:
			return {}
	for key in LISTS:
		if not data.get(key) is Array:
			return {}
	for key in NUMBERS + ["rng_seed", "rng_state"]:
		if not data.get(key) is int:
			return {}
	if not DiplomaticTrade.valid(data):
		return {}
	if data.core_count <= 0 or data.core_count > data.systems.size() or data.people.is_empty():
		return {}
	if not data.succession and not data.people.has(data.player):
		return {}
	var copy := data.duplicate(true)
	for system in copy.systems.size():
		var region: Variant = copy.systems[system]
		if not region is Dictionary or not region.get("pos") is Vector2 or not region.get("ports") is Array:
			return {}
		for id in region.ports:
			if not copy.ports.get(id) is Dictionary or copy.ports[id].get("system",-1)!=system:
				return {}
		for index in range(region.get("planets",[]).size()):
			var planet: Dictionary = region.planets[index]
			if planet.has("port"):
				# Early NPC colonies used a second field for the same landing site.
				var old_id: Variant = planet.port
				var colony: Dictionary = copy.ports.get(old_id,{})
				if old_id not in region.ports or colony.get("planet_index",-1) != index or colony.get("surface_profile","") != "colony":
					return {}
				if planet.get("port_id",old_id) == old_id:
					planet.port_id = old_id
					colony.get_or_add("landing_only",false)
				else:
					# Preserve both established ports, their contracts, stock and accounts.
					colony.erase("planet_index")
					colony.erase("surface_profile")
					colony.erase("surface_yields")
					colony.orbit = index
				planet.erase("port")
			if planet.has("port_id"):
				var site: Dictionary = copy.ports.get(planet.port_id,{})
				if planet.port_id not in region.ports or site.get("planet_index",-1) != index:
					return {}
	for id in copy.ports:
		var port: Variant = copy.ports[id]
		if not port is Dictionary or port.get("id") != id or not port.get("system") in range(copy.systems.size()):
			return {}
		if not port.get("flag") is int or (port.flag>=0 and not copy.factions.has(port.flag)) or id not in copy.systems[port.system].ports:
			return {}
		if port.has("planet_index"):
			var bodies: Array = copy.systems[port.system].get("planets",[])
			var index: Variant = port.planet_index
			if not index is int or index < 0 or index >= bodies.size() or bodies[index].get("port_id",0) != id:
				return {}
		if port.has("harvest_carriers"):
			if not port.harvest_carriers is Dictionary or not port.has("planet_index"):
				return {}
			for carrier: Variant in port.harvest_carriers:
				if not carrier is int or carrier <= 0 or port.harvest_carriers[carrier] not in Industry.COLONY_NEEDS:
					return {}
		var provision_days: Variant = port.get("provision_person_days",0)
		if not provision_days is int or provision_days < 0 or provision_days >= int(Industry.RULES.colony.person_days_per_unit):
			return {}
		var rate: Variant = port.get("tax_rate")
		if typeof(rate) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(rate)) or rate<0 or rate>1:
			return {}
		if not port.get("treasury") is int or port.treasury < 0 or not port.get("operating_profit") is int or not port.get("cash_holds") is Dictionary:
			return {}
		if port.has("dividend_policy"):
			var policy: Variant = port.dividend_policy
			if not policy is Dictionary or not policy.get("percent") is int or policy.percent < 0 or policy.percent > 100 or not policy.get("reserve") is int or policy.reserve < 0:
				return {}
		if port.has("last_dividend_day") and (not port.last_dividend_day is int or port.last_dividend_day > copy.day):
			return {}
		var reserved_cash := 0
		for borrower in port.cash_holds:
			var booking: Dictionary = copy.ships.get(borrower,{}).get("reservation",{})
			if not borrower is int or not port.cash_holds[borrower] is int or port.cash_holds[borrower] <= 0:
				return {}
			if id not in [booking.get("payer",0),booking.get("target",0)]:
				return {}
			reserved_cash += int(port.cash_holds[borrower])
		if reserved_cash > port.treasury:
			return {}
		if not port.get("charter_units") is int or port.charter_units<=0 or not port.get("black_treasury") is int or port.black_treasury<0:
			return {}
		if port.has("equity"):
			var ownership: Variant = port.equity
			if not ownership is Dictionary or not ownership.get("people") is Dictionary or not ownership.get("total") is int or ownership.total<=0 or ownership.total>2147483647:
				return {}
			if not ownership.get("company") is int or not ownership.get("company_units") is int or ownership.company_units < 0:
				return {}
			if ownership.company != 0 and not copy.firms.has(ownership.company):
				return {}
			if ownership.company == 0 and ownership.company_units != 0:
				return {}
			if not ownership.get("treasury_units",0) is int or ownership.get("treasury_units",0) < 0:
				return {}
			var issued: int = ownership.company_units + ownership.get("treasury_units",0)
			for holder in ownership.people:
				if not copy.people.has(holder) or not ownership.people[holder] is int or ownership.people[holder] <= 0:
					return {}
				issued += int(ownership.people[holder])
			if issued != ownership.total:
				return {}
		if port.has("planet_index"):
			var planets: Array = copy.systems[port.system].get("planets",[])
			if not port.planet_index is int or port.planet_index not in range(planets.size()) or planets[port.planet_index].get("port_id",0) != id or not port.get("landing_only") is bool:
				return {}
		if not port.get("stock") is Array or port.stock.size() != wares or not port.get("hulls") is Dictionary:
			return {}
		var inventory := Hulls.inventory(false)
		inventory.fill(0)
		for hull in port.hulls:
			if not hull is String:
				return {}
			var kind := Hulls.kind_for_id(hull)
			if kind < 0 or not port.hulls[hull] is int or port.hulls[hull] < 0:
				return {}
			inventory[kind] = port.hulls[hull]
		port.hulls = inventory
		if not port.get("production_orders") is Array:
			return {}
		var orders: Array = []
		for hull in port.production_orders:
			if not hull is String or Hulls.kind_for_id(hull) < 0:
				return {}
			orders.append(Hulls.kind_for_id(hull))
		port.production_orders = orders
		if port.has("yard_work"):
			var work: Variant = port.yard_work
			if not work is Dictionary or not work.get("kind") is String or Hulls.kind_for_id(work.kind) < 0:
				return {}
			if not work.get("hours") is int or not work.get("required") is int or work.hours <= 0 or work.hours >= work.required:
				return {}
			work.kind = Hulls.kind_for_id(work.kind)
		for counter in ["yard_hours","yard_labor_day"]:
			if port.has(counter) and (not port[counter] is int or port[counter] < 0):
				return {}
		if not Industry.valid_station(port, Hulls.MODELS.size()):
			return {}
		if port.has("design_cells"):
			if port.get("module",-1) not in range(Industry.MODULES.size()) or port.get("extension",-1) not in range(-1,Industry.MODULES.size()):
				return {}
			if port.get("expansion",0) > 0 and port.get("extension",-1) < 0:
				return {}
			var cells: Variant = port.design_cells
			if not cells is Array or cells.size() != StationDesign.kinds(port).size() or not StationDesign.issue(cells).is_empty():
				return {}
	for id in copy.ships:
		var raw: Variant = copy.ships[id]
		if not raw is Dictionary or raw.get("id") != id:
			return {}
		if raw.has("privateer_firm") and copy.firms.has(raw.privateer_firm):
			# Company-funded privateers used to list the director as their personal owner.
			if not raw.has("firm") and not raw.has("station_owner") and not raw.has("lease") and not raw.has("charter"):
				raw.owner = 0
				raw.firm = raw.privateer_firm
			elif raw.get("firm",0) != raw.privateer_firm:
				raw.erase("privateer_firm")
		if raw.has("firm") and (not copy.firms.has(raw.firm) or raw.get("owner") != 0 or raw.has("lease") or raw.has("station_owner") or raw.has("charter")):
			return {}
		if raw.get("owner",0) != 0 and raw.has("station_owner") and copy.ports.has(raw.station_owner):
			# Older private duty appointments also set the station's ownership marker.
			raw.erase("station_owner")
		var ship := Ship.decode(raw, wares)
		if ship.is_empty() or ship.get("system", -1) not in range(copy.systems.size()):
			return {}
		var principal: int = copy.firms.get(ship.get("firm",0),{}).get("director",ship.get("owner",0))
		var issuer: int = copy.regent if principal != 0 and principal == copy.regency and copy.player == copy.regent else principal
		for order in ship.get("order_queue", []).duplicate():
			if not order.has("issuer"):
				if copy.people.has(issuer):
					order.issuer = issuer
				else:
					ship.order_queue.erase(order)
		if not ship.get("dock") is int or (ship.dock != 0 and not copy.ports.has(ship.dock)):
			return {}
		if not ship.get("captain") is int or (ship.captain != 0 and not copy.people.has(ship.captain)):
			return {}
		for field in ["operating_area","next_operating_area"]:
			if not ship.has(field):
				continue
			var area: Variant = ship[field]
			if not area is Dictionary or not area.get("system") is int or area.system not in range(copy.systems.size()) or not area.get("port") is int:
				return {}
			if area.port != 0 and copy.ports.get(area.port,{}).get("system",-1) != area.system:
				return {}
			if area.has("jumps") and (not area.jumps is int or area.jumps < 0 or area.jumps > int(Industry.RULES.operating_area.maximum_jumps)):
				return {}
		if ship.has("construction_contract"):
			var contract: Variant = ship.construction_contract
			if not contract is Dictionary or not copy.ports.has(contract.get("home",0)) or not contract.get("status","") in ["active","working","returning","available"]:
				return {}
			# Older captures transferred the hull and removed its captain but retained the yard contract.
			var transferred: bool = copy.people.has(ship.get("owner",0)) or ship.has("firm")
			var abandoned_prize: bool = ship.captain == 0 and ship.get("job") == {} and ship.get("crew",0) > 0
			if Hulls.can_build_station(ship.kind) and (transferred or abandoned_prize):
				ship.erase("construction_contract")
			elif not copy.people.has(ship.captain) or ship.owner != 0 or not Hulls.can_build_station(ship.kind) or not contract.get("fee") is int or contract.fee <= 0:
				return {}
			elif contract.status == "active" and (not copy.people.has(contract.get("client",0)) or contract.get("site",-1) != 0):
				return {}
			elif contract.status == "working" and copy.ports.get(contract.get("site",0),{}).get("construction_ship",0) != id:
				return {}
		copy.ships[id] = ship
	for id in copy.people:
		var person: Variant = copy.people[id]
		if not person is Dictionary or person.get("id") != id or not person.get("alive") is bool:
			return {}
		if not Person.decode_into(person):
			return {}
		var trust: Variant = person.get("faction_trust",{})
		if not trust is Dictionary:
			return {}
		for flag in trust:
			var entry: Variant = trust[flag]
			if not copy.factions.has(flag) or not entry is Dictionary or not entry.get("score") is int or absi(entry.score) > 100 or not entry.get("day") is int or not entry.get("change") is int or not entry.get("reason") is String:
				return {}
		if not person.get("loc") is int or (person.loc != 0 and not copy.ports.has(person.loc)):
			return {}
		if not person.get("ship") is int or (person.ship != 0 and not copy.ships.has(person.ship)):
			return {}
	return copy
