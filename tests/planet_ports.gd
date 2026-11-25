extends SceneTree

const World = preload("res://world.gd")
const Ports = preload("res://scripts/campaign/planet_ports.gd")
const Economy = preload("res://economy.gd")
const Industry = preload("res://scripts/economy/industry.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	run.call_deferred()

func check_harvest(world, station: Dictionary) -> void:
	var site := station.duplicate(true)
	var water := Industry.Ware.WATER
	var food := Industry.Ware.RATIONS
	site.modules.clear()
	site.stock.fill(0)
	site.outbound.clear()
	site.inbound.clear()
	site.build_storage.fill(0)
	site.pop = 1000
	Ports.configure_harvest(site,{"type":3})
	Economy.produce(world,site)
	check(site.stock[water] == 100 and site.stock[food] == 150 and water in site.exports and food in site.exports,
		"temperate residents harvest both goods into sellable stock without industrial inputs")
	site.pop = 500
	site.stock.fill(0)
	Ports.configure_harvest(site,{"type":2})
	Economy.produce(world,site)
	check(site.stock[water] == 36 and site.stock[food] == 0 and food not in site.exports,"ice harvesting scales with labor and offers only water")
	Ports.configure_harvest(site,{"type":22})
	Economy.produce(world,site)
	check(site.stock[water] == 36 and site.stock[food] == 0 and site.exports.is_empty(),"an ice giant has no accessible surface harvest")
	Ports.configure_harvest(site,{"type":4})
	site.landing_only = true
	Economy.produce(world,site)
	site.landing_only = false
	site.build = 30
	Economy.produce(world,site)
	check(site.stock[water] == 36 and site.stock[food] == 0,"a landing or unfunded worksite cannot sell a harvest")
	site.build = 0
	site.stock.fill(0)
	var store := Industry.station_data(site)
	store.reserve(Industry.StationData.Booking.INBOUND,42,water,50,world.day+30)
	site.stock[Industry.Ware.ENERGY] = site.storage_cap[Industry.Storage.CONTAINER]-260
	check(store.production_space(Industry.Ware.ENERGY,Industry.PROVISION_STOCK_TARGETS) == 0 and store.free_space(food) == 210,
		"household goods keep their loading space and inbound water counts toward the reserve")
	site.pop = 600
	site.provision_person_days = int(Industry.RULES.colony.person_days_per_unit)-site.pop-1
	check(Economy.demand(site) == 0,"fractional household demand does not round a small settlement up to a full cargo unit")
	site.provision_person_days += 1
	check(Economy.demand(site) == 1,"household consumption charges at the exact population-day boundary")

func check_harvest_freight() -> void:
	var world := World.new()
	world.new_game({"seed":"harvest-route","systems":12,"factions":3})
	var region: Dictionary = world.systems[0]
	var origin: Dictionary = world.ports[region.planets[0].port_id]
	var buyer: Dictionary = world.ports[region.ports[0]]
	var ware := Industry.Ware.WATER
	Ports.configure_harvest(origin,{"type":2})
	for id: int in region.ports:
		world.ports[id].stock[ware] = 200
	buyer.stock[ware] = int(Industry.stock_target(ware))
	var captain := world.random_person(world.NEUTRAL,origin.id)
	var ship_id := world.ship(world.Hulls.kind_for_reference("buffalo"),0,captain,world.NEUTRAL,0,origin.pos,origin.id)
	var ship: Dictionary = world.ships[ship_id]
	origin.get_or_add("harvest_carriers",{})[ship_id] = ware
	ship.station_owner = origin.id
	Economy.set_station_job(world,ship,origin,"站属贸易")
	ship.operating_area.jumps = 0
	var load := world.cargo_free(ship)
	var start_stock: int = origin.stock[ware]
	var till: int = buyer.treasury
	buyer.treasury = 0
	check(Economy.station_trade_plan(world,ship,origin).is_empty(),"an insolvent receiver cannot book a harvest shipment")
	buyer.treasury = till
	Economy.step_ship(world,ship)
	check(ship.cargo[ware] == load and origin.stock[ware] == start_stock-load and buyer.inbound.has(ship_id),"crossing the reorder point loads a full funded lot from the surface warehouse")
	Economy.step_ship(world,ship)
	for day in 1200:
		if ship.travel.is_empty():
			break
		Economy.fly_leg(world,ship,buyer,1.0)
	Economy.step_ship(world,ship)
	check(ship.dock == buyer.id and ship.cargo[ware] == 0 and buyer.stock[ware] == int(Industry.stock_target(ware))+load and buyer.treasury < till and not buyer.inbound.has(ship_id),
		"a physical surface-to-orbit trip delivers the whole paid lot and releases the booking")

func run() -> void:
	var world = World.new()
	world.new_game({"seed":"planet-landfall","systems":12,"factions":3})
	var ship: Dictionary = world.ride()
	var home: Dictionary = world.ports[ship.dock]
	var region: Dictionary = world.systems[0]
	var planet: Dictionary = region.planets[0]
	var yard: Dictionary = world.ports[planet.port_id]
	check(yard.planet_index == 0 and yard.pop > 0 and Industry.Module.YARD in yard.modules and not yard.landing_only,"developed homeworld has its own populated surface shipyard")
	var worker: int = world.random_person(world.NEUTRAL,home.id)
	var trader: Dictionary = world.ships[world.ship(1,world.player,worker,world.NEUTRAL,0,home.pos,home.id)]
	trader.cargo[0] = 8
	trader.job = {"kind":"贸易","source":home.id,"target":yard.id,"phase":1,"ware":0}
	check(Economy.reserve(world,trader,home,yard,0,8,false),"a real freighter can book a delivery to the rotating planetary berth")
	var deadline: int = trader.reservation.expires
	var departure: Vector2 = yard.pos
	Economy.begin_trip(world,trader,yard)
	for _day in range(deadline):
		world.tick()
		if trader.dock == yard.id and trader.cargo[0] == 0:
			break
	check(trader.dock == yard.id and trader.cargo[0] == 0 and not yard.inbound.has(trader.id) and world.day < deadline,"freighter follows the moving surface port and unloads before reservation expiry")
	check(yard.pos.distance_to(departure) > 5 and yard.pos.is_equal_approx(Ports.point(planet)) and trader.pos.distance_to(yard.pos)<0.01,"planet rotation/orbit carries the berth and moored ships")
	world.depart(ship)
	ship.pos = Ports.point(planet)
	check(Ports.landing_at(world,ship) == yard.id and world.berth(ship,yard.id) and planet.surveyed,"touching down identifies this planet and docks at its own market")
	var ore: int = yard.stock[0]
	check(Economy.trade(world,yard.id,0,1) == 1 and yard.stock[0] == ore-1,"planetary trade withdraws physical inventory")
	ship.hp -= 12
	ship.fuel = 92.0
	var fuel: int = yard.stock[2]
	check(Economy.supply(world,true) and Economy.supply(world,false) and yard.stock[2] == fuel-8,"port repair and fuel use the local warehouse")
	world.active().wallet += Economy.ship_quote(yard,0).price
	check(Economy.buy_ship(world,yard.id,0) > 0,"a populated planetary shipyard sells an actual completed hull")
	world.depart(ship)
	check((ship.pos-Ports.point(planet)).dot(Ports.outward(planet)) > 0,"departing launches outward from the rotating surface")
	world.ensure_chunks_around(Vector2(12,15)*world.CHUNK_SIZE,0)
	var remote: int = world.chunks[Vector2i(12,15)][0]
	world.mark_seen(remote)
	var outer: Dictionary = world.systems[remote]
	var body: Dictionary = outer.planets[0]
	var original_count: int = outer.ports.size()
	check(not body.has("port_id"),"scanning an outer system creates no idle planetary markets")
	ship.system = remote
	ship.pos = Ports.point(body) + Ports.outward(body)*200
	check(Ports.landing_at(world,ship) == 0 and outer.ports.size() == original_count,"remote docking cannot create a planetary settlement")
	ship.pos = Ports.point(body)
	var landing := Ports.landing_at(world,ship)
	check(landing != 0 and Ports.landing_at(world,ship) == landing and outer.ports.size() == original_count+1 and world.berth(ship,landing),"actual first landing produces a single persistent site")
	var site: Dictionary = world.ports[landing]
	check(site.landing_only and site.pop == 0 and site.hulls.all(func(q):return q == 0) and not Economy.supply(world,false) and Economy.trade(world,landing,0,-1) == 0,"uninhabited ground supports landing without phantom trade, fuel, people or ships")
	world.active().wallet = int(Industry.CONSTRUCTION.foundation.credits)
	for ware in Industry.FOUNDATION:
		ship.cargo[ware] = Industry.FOUNDATION[ware]
	var wallet: int = world.active().wallet
	check(Ports.found(world,Industry.Module.YARD) and world.active().wallet == wallet-int(Industry.CONSTRUCTION.foundation.credits) and not Ports.found(world,Industry.Module.YARD),"founding a surface port spends once and binds the project to the same planetary berth")
	world.tick(36)
	check(site.build == 0 and Industry.Module.YARD in site.modules and site.build_storage.all(func(q):return q==0),"supplied material and construction time complete the surface yard")
	check(Economy.order_hull(world,landing,0),"owned planetary yard accepts normal shipbuilding orders")
	var restored = World.new()
	check(restored.load_state(world.snapshot()) and restored.systems[remote].planets[0].port_id == landing and restored.ports[landing].production_orders == [0] and restored.ride().dock == landing,"reload restores the developed planet, real berth, market and ship order")
	check_harvest(world,yard)
	var markets: int = world.ports.size()
	var fleets: int = world.ships.size()
	Ports.prepare_producers(world)
	check(world.ports.size() == markets and world.ships.size() == fleets and not site.has("harvest_carriers"),
		"preparing the core twice duplicates neither markets nor ships and leaves the frontier colony's fleet to its owner")
	var seller: Dictionary = {}
	for port: Dictionary in world.ports.values():
		if port.has("harvest_carriers") and not world.systems[port.system].seen:
			seller = port
			break
	check(not seller.is_empty() and not seller.scan and restored.ports[seller.id].harvest_carriers == seller.harvest_carriers and seller.harvest_carriers.keys().all(func(id): return restored.ships[id].station_owner == seller.id),
		"an unvisited core producer trades with persistent station-owned freighters without revealing the port")
	check_harvest_freight()
	print("Planetary ports ",checks-failures,"/",checks)
	quit(1 if failures else 0)
