extends RefCounted

const Celestial = preload("res://celestial.gd")
const Industry = preload("res://scripts/economy/industry.gd")
const Profiles = preload("res://data/campaign/planet_ports.json")
const StationGeometry = preload("res://scripts/models/station_geometry.gd")

static func outward(planet: Dictionary) -> Vector2:
	var longitude := deg_to_rad(float(int(planet.surface_seed) % 360))
	return Vector2.from_angle(longitude + float(planet.get("spin",0.0)))

static func point(planet: Dictionary) -> Vector2:
	return Vector2(planet.pos) + outward(planet) * (float(planet.radius) + 24.0)

static func approach_speed(planet: Dictionary) -> float:
	return Vector2(planet.get("orbital_velocity",Vector2.ZERO)).length() + (float(planet.radius)+24.0) * absf(float(planet.get("spin_rate",0.0)))

static func profile(world, system: int, index: int) -> String:
	var region: Dictionary = world.systems[system]
	var planet: Dictionary = region.planets[index]
	if planet.get("port_id",0) != 0:
		return world.ports[planet.port_id].surface_profile
	if region.get("wild",false):
		return "landing"
	if index == 0 and (system == 0 or int(planet.surface_seed) % 11 == 0):
		return "yard"
	if planet.type >= 20:
		return "gas"
	if Celestial.PLANETS[planet.type][2] >= 0.4:
		return "settlement"
	return "mine" if Celestial.PLANETS[planet.type][3] >= 25 else "refinery"

static func caption(world, system: int, index: int) -> String:
	var planet: Dictionary = world.systems[system].planets[index]
	if planet.get("port_id",0) != 0:
		return world.ports[planet.port_id].name
	var category := profile(world,system,index)
	var title := "浮空着陆点" if planet.type >= 20 else "地表着陆点"
	if category != "landing":
		title = Profiles.data[category].title
	return "%s · %s" % [planet.name,title]

static func prepare(world, system: int) -> void:
	var region: Dictionary = world.systems[system]
	if region.get("wild",false):
		return
	for index in range(region.planets.size()):
		materialize(world,system,index)

## Settled core producers trade before the player visits their system.
static func prepare_producers(world) -> void:
	for system in range(world.core_count):
		var planets: Array = world.systems[system].planets
		for index in planets.size():
			if not Celestial.SURFACE_YIELDS.has(planets[index].type):
				continue
			var site: Dictionary = world.ports[materialize(world,system,index)]
			if site.surface_profile == "colony" or site.has("harvest_carriers"):
				continue
			site.harvest_carriers = {}
			var kind: int = world.Hulls.kind_for_reference("buffalo")
			for ware: int in site.surface_yields:
				var captain: int = world.random_person(site.flag,site.id)
				var id: int = world.ship(kind,0,captain,site.flag,system,site.pos,site.id)
				site.harvest_carriers[id] = ware
				var ship: Dictionary = world.ships[id]
				ship.station_owner = site.id
				world.Economy.set_station_job(world,ship,site,"站属贸易")

static func configure_harvest(station: Dictionary, planet: Dictionary) -> void:
	var rates: Vector2i = Celestial.SURFACE_YIELDS.get(planet.type,Vector2i.ZERO)
	var crops := {}
	if rates.x > 0:
		crops[Industry.Ware.WATER] = rates.x
	if rates.y > 0:
		crops[Industry.Ware.RATIONS] = rates.y
	station.surface_yields = crops
	if not station.get("landing_only",false):
		Industry.update_market(station)

static func harvest_units(station: Dictionary, ware: int) -> int:
	return floori(float(station.surface_yields[ware]) * int(station.pop) / 1000.0)

static func harvest(station: Dictionary, inventory: Industry.StationData) -> void:
	for ware: int in station.surface_yields:
		# Leave shared storage for the other harvest and the port's industries.
		var opening := maxi(0,int(Industry.stock_target(ware)*4)-int(station.stock[ware]))
		var room := mini(opening,inventory.production_space(ware,Industry.PROVISION_STOCK_TARGETS))
		inventory.deposit(ware,mini(room,harvest_units(station,ware)))

static func materialize(world, system: int, index: int) -> int:
	var region: Dictionary = world.systems[system]
	var planet: Dictionary = region.planets[index]
	if planet.get("port_id",0) != 0:
		return planet.port_id
	var category := profile(world,system,index)
	var ready := category != "landing"
	var specialty: Dictionary = Profiles.data.get(category,{})
	var kind: int = Industry.MODULE_ID[specialty.module] if ready else Industry.Module.HABITAT
	var port_id: int = world.port(system,caption(world,system,index),point(planet),world.local_flag(system) if ready else world.NEUTRAL,0,kind,ready)
	var station: Dictionary = world.ports[port_id]
	station.planet_index = index
	station.surface_profile = category
	station.landing_only = not ready
	station.berth_heading = outward(planet).angle()
	station.scan = region.seen
	planet.port_id = port_id
	configure_harvest(station,planet)
	if kind != Industry.Module.YARD:
		station.hulls.fill(0)
	if ready:
		station.pop = int(specialty.population)
		station.pop_cap = maxi(station.pop_cap,station.pop)
		for ware in specialty.stock:
			station.stock[Industry.WARE_ID[ware]] = int(specialty.stock[ware])
	else:
		station.build = 0
		station.pop = 0
		station.pop_cap = 0
		station.black.fill(0)
		station.imports.clear()
		station.exports.clear()
	return port_id

static func landing_at(world, vessel: Dictionary) -> int:
	if vessel.is_empty() or vessel.layer or vessel.dock != 0 or vessel.locked:
		return 0
	var reach := StationGeometry.docking_range(vessel.kind)
	var region: Dictionary = world.systems[vessel.system]
	for index in range(region.planets.size()):
		if point(region.planets[index]).distance_to(vessel.pos) <= reach:
			return materialize(world,vessel.system,index)
	return 0

static func found(world, kind: int) -> bool:
	var ship: Dictionary = world.ride()
	var station: Dictionary = world.ports.get(ship.get("dock",0),{})
	var terms: Dictionary = Industry.CONSTRUCTION.foundation
	if not station.get("landing_only",false) or kind not in range(Industry.MODULES.size()) or world.active().wallet < terms.credits:
		return false
	var planet: Dictionary = world.systems[station.system].planets[station.planet_index]
	if not planet.surveyed:
		return false
	station.landing_only = false
	station.surface_profile = "colony"
	station.name = "%s · %s港" % [planet.name,Industry.MODULES[kind]]
	world.credit(world.player,-int(terms.credits),station,"设立工地")
	station.owner = world.player
	station.flag = world.active().flag
	world.refresh_tariffs(station.system)
	world.Equity.update_operator(world,station)
	station.module = kind
	station.build = int(terms.days)
	station.since = world.day
	station.pop = 85
	station.pop_cap = 180
	world.Economy.fund_from_ship(ship,station)
	world.event("%s 已立项，材料齐备后施工 %d 日。" % [station.name,station.build])
	return true
