extends SceneTree

const World = preload("res://world.gd")
const Economy = preload("res://economy.gd")
const Industry = preload("res://scripts/economy/industry.gd")
const Hulls = preload("res://hull_catalog.gd")
const Hyperspace = preload("res://scripts/campaign/hyperspace.gd")
var failures := 0
var checks := 0

func expect(result: bool, description: String) -> void:
	checks += 1
	if not result:
		failures += 1
		printerr("FAIL ",description)

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var world = World.new()
	expect(world.new_game({"seed":"cargo-contract","systems":24,"factions":5,"avatar":{"name":"物流测试","house":"工会"}}),"new world")
	var flagship: Dictionary = world.ride()
	var home: Dictionary = world.ports[flagship.dock]
	var source: Dictionary = world.ports[world.systems[1].ports[0]]
	var dest: Dictionary = world.ports[world.systems[1].ports[1]]
	var worker: int = world.random_person(world.NEUTRAL,home.id)
	var ship_id: int = world.ship(1,world.player,worker,world.NEUTRAL,home.system,home.pos,home.id)
	var ship: Dictionary = world.ships[ship_id]
	ship.job = {"kind":"贸易","source":source.id,"target":dest.id,"phase":0}
	world.active().wallet = 50000
	source.stock[0] = 25
	for station in [source,dest]:
		expect(station.stock.size() == 16 and station.black.size() == 16,"all inventory columns initialized")
	expect(Economy.reserve(world,ship,source,dest,0,25),"both reservation endpoints")
	expect(Industry.available(source,0) == 0 and dest.inbound.has(ship_id),"stock inaccessible to second buyer")
	var checker: int = world.random_person(world.NEUTRAL,home.id)
	var second_id: int = world.ship(1,world.player,checker,world.NEUTRAL,home.system,home.pos,home.id)
	var second: Dictionary = world.ships[second_id]
	expect(not Economy.reserve(world,second,source,dest,0,10),"a competing freighter cannot double-book outbound stock")
	source.stock[0] += 15
	var capacity: int = dest.storage_cap[0]
	dest.storage_cap[0] -= Industry.space(dest,0)
	expect(not Economy.reserve(world,second,source,dest,0,10),"separate ships cannot reserve the same inbound storage space")
	dest.storage_cap[0] = capacity
	var saved = World.new()
	expect(saved.load_state(world.snapshot()) and saved.ships[ship_id].reservation.qty == 25 and saved.ports[source.id].outbound.has(ship_id),"active cargo reservation survives disk representation")
	var restored: Dictionary = saved.ports[source.id]
	var restored_store := Industry.station_data(restored)
	var reserved_qty: int = restored.outbound[ship_id].qty
	var free_qty := restored_store.available(Industry.Ware.ORE)
	expect(restored_store.withdraw(Industry.Ware.ORE,free_qty+reserved_qty) == free_qty and restored.stock[Industry.Ware.ORE] == reserved_qty,"live typed view preserves booked cargo on restored station")
	expect(Industry.station_data(restored).deposit(Industry.Ware.ORE,2) == 2 and restored_store.available(Industry.Ware.ORE) == 2 and source.stock[Industry.Ware.ORE] == 40,"two views share restored state and leave the original world independent")
	var broken := restored.duplicate(true)
	broken.inbound[ship_id] = {"ware":0,"qty":-1,"expires":saved.day+3}
	expect(Industry.valid_station(restored,Hulls.MODELS.size()) and not Industry.valid_station(broken,Hulls.MODELS.size()),"validate saved industrial fields and reject malformed bookings")
	expect(Economy.reserve(world,second,source,dest,0,10),"unused inbound space can be reserved")
	second.reservation.expires = world.day
	world.tick()
	expect(not source.outbound.has(second_id) and not dest.inbound.has(second_id),"abandoned reservation expires on both ends")
	Economy.begin_trip(world,ship,source)
	var previous: Vector2 = ship.pos
	world.tick()
	expect(ship.pos != previous and ship.dock == 0,"transport advances a physical location before docking")
	var reached := false
	for _day in range(int(ship.get("reservation",{}).get("expires",world.day)) - world.day + 1):
		world.tick()
		if ship.dock == dest.id and not ship.get("reservation",{}).has("ware") and ship.job.phase == 0:
			reached = true
			break
	expect(reached,"loaded reservation delivered and cleared")
	world.berth(ship,source.id)
	source.stock[0] = 25
	expect(Economy.reserve(world,ship,source,dest,0,20),"second reservation")
	world.destruction(ship_id)
	expect(not source.outbound.has(ship_id) and not dest.inbound.has(ship_id),"destroyed freighter releases both reservations immediately")
	var recycler := world.port(1,"拆船试验场",Vector2(690,100),world.NEUTRAL,world.player,Industry.Module.RECYCLER)
	var yard: Dictionary = world.ports[recycler]
	yard.stock[Industry.Ware.SCRAP] = 12
	yard.stock[Industry.Ware.ENERGY] = 8
	var initial_alloy: int = yard.stock[Industry.Ware.ALLOY]
	Economy.run_module(world,yard,Industry.Module.RECYCLER)
	expect(yard.stock[Industry.Ware.ALLOY] > initial_alloy and yard.stock[Industry.Ware.SCRAP] < 12,"recycler converts scrap plus energy")
	var factory := world.port(0,"订造船厂",Vector2(480,200),world.NEUTRAL,world.player,Industry.Module.YARD)
	yard = world.ports[factory]
	world.berth(flagship,factory)
	var payroll := 0
	for method in ["universal","direct","recycling"]:
		payroll += Industry.labor_charge(Industry.labor_hours(Hulls.MODELS[0],method))
	expect(world.Treasury.transfer(world,yard,world.player,payroll),"owner funds the actual payroll for all three queued builds")
	expect(Economy.order_hull(world,factory,0),"shipyard accepts player order")
	var initial_stock: int = yard.hulls[0]
	var bill := Industry.vessel_recipe(Hulls.MODELS[0])
	world.day = 30
	for ware in bill:
		yard.stock[ware] = bill[ware]
	yard.stock[Industry.Ware.ELECTRONICS] = 0
	Economy.shipyard(world,yard)
	expect(yard.production_orders.size() == 1 and yard.hulls[0] == initial_stock and yard.stock[Industry.Ware.ALLOY] == bill[Industry.Ware.ALLOY],"missing component blocks atomic construction")
	yard.stock[Industry.Ware.ELECTRONICS] = bill[Industry.Ware.ELECTRONICS]
	Economy.shipyard(world,yard)
	expect(yard.production_orders.is_empty() and yard.hulls[0] == initial_stock+1 and yard.stock[Industry.Ware.ALLOY] == 0,"completed order drains recipe and produces one hull")
	for method in ["direct","recycling"]:
		world.day += 30
		expect(Economy.set_method(world,factory,method) and Economy.order_hull(world,factory,0),"select and order "+method)
		bill = Industry.vessel_recipe(Hulls.MODELS[0],method)
		for ware in bill:
			yard.stock[ware] = bill[ware]
		Economy.shipyard(world,yard)
		expect(yard.production_orders.is_empty() and yard.stock[bill.keys()[0]] == 0,"distinct recipe consumed "+method)
	expect(Economy.station_overview(world,factory).inbound.is_empty(),"station overview")
	var site_id: int = world.port(0,"独立工地",Vector2(200,110),world.NEUTRAL,world.player,Industry.Module.REFINERY,false)
	var site: Dictionary = world.ports[site_id]
	world.berth(flagship,site_id)
	flagship.cargo[Industry.Ware.ALLOY] = 20
	expect(Economy.donate(world,site_id) == 20 and site.stock[Industry.Ware.ALLOY] == 0,"construction stock separate from open market")
	Economy.produce(world,site)
	expect(site.build == 30 and site.build_storage[Industry.Ware.ALLOY] == 20,"unfunded construction leaves materials and progress intact")
	var dispatcher: int = world.random_person(world.NEUTRAL,factory)
	var freighter_id: int = world.ship(1,world.player,dispatcher,world.NEUTRAL,0,yard.pos,factory)
	var freighter: Dictionary = world.ships[freighter_id]
	freighter.job = {"kind":"护航","system":0}
	yard.modules.append(Industry.Module.SOLAR)
	Industry.update_market(yard)
	for ware in Industry.FOUNDATION:
		yard.stock[ware] = 70
	expect(Economy.supply_construction(world,freighter_id,factory,site_id),"assign a real construction freighter")
	for _day in range(220):
		world.tick()
		if site.build == 0 and freighter.job.get("kind","") == "护航":
			break
	if site.build > 0:
		printerr("site day=%d build=%d store=%s freighter=%s travel=%s dock=%s reservation=%s attention=%s succession=%s source=%s" % [world.day,site.build,site.build_storage,freighter.job,freighter.travel,freighter.dock,freighter.get("reservation",{}),world.attention,world.succession,yard.stock])
	expect(site.build == 0 and site.modules == [Industry.Module.REFINERY] and site.stock[Industry.Ware.ALLOY] >= 0,"worker delivered the outstanding blueprint materials")
	expect(site.build_inbound.is_empty() and freighter.job.get("kind","") == "护航","builder releases logistics and restores job")
	var market: Dictionary = world.ports[world.systems[0].ports[0]]
	world.berth(freighter,market.id)
	world.berth(flagship,market.id)
	expect(Economy.assign_role(world,freighter.id,flagship.id,"SUPPLY"),"assign port tender before flagship departure")
	world.depart(flagship)
	flagship.pos = market.pos+Vector2(40,0)
	flagship.fuel = 68
	flagship.hp -= 10
	market.stock[Industry.Ware.FUEL] = 50
	market.stock[Industry.Ware.HULL_PARTS] = 30
	var sold_fuel: int = market.stock[Industry.Ware.FUEL]
	var sold_parts: int = market.stock[Industry.Ware.HULL_PARTS]
	Economy.step_ship(world,freighter)
	Economy.step_ship(world,freighter)
	expect(flagship.fuel >= 85 and is_equal_approx(flagship.hp,Hulls.MODELS[flagship.kind].hp) and market.stock[Industry.Ware.FUEL]<sold_fuel and market.stock[Industry.Ware.HULL_PARTS]<sold_parts,"auxiliary sources real fuel and repair materials and transfers them at rendezvous")
	long_distance_freight()
	starter_market_balance()
	freight_profit()
	freight_capacity()
	# Exercise the same tick path on a fresh, unattended sector without player decisions.
	if "--soak" in OS.get_cmdline_user_args():
		var simulation = World.new()
		simulation.new_game({"seed":"industrial-soak","systems":24,"factions":5,"avatar":{"name":"模拟员","house":"港务"}})
		for _day in range(10000):
			simulation.tick()
			if simulation.attention or simulation.succession:
				break
		expect(simulation.day == 10000,"ten thousand autonomous days advanced")
		for port in simulation.ports.values():
			expect(port.stock.all(func(value): return int(value)>=0) and port.build_storage.all(func(value): return int(value)>=0),"nonnegative warehouse")
			for bucket in [port.inbound,port.outbound,port.build_inbound]:
				for lock_id in bucket:
					expect(simulation.ships.has(lock_id) and bucket[lock_id].expires >= simulation.day,"live unexpired lock")
	print("Economy checks %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)

func long_distance_freight() -> void:
	var world = World.new()
	world.new_game({"seed":"freight-horizon","systems":24,"factions":5})
	var source: Dictionary = world.ports[world.ride().dock]
	var worker: int = world.random_person(world.NEUTRAL,source.id)
	var ship: Dictionary = world.ships[world.ship(1,world.player,worker,world.NEUTRAL,0,source.pos,source.id)]
	var remote := 1
	for system_id in range(2,world.core_count):
		if world.distance(0,system_id) > world.distance(0,remote):
			remote = system_id
	var route := Economy.flight_route(world,0,remote,[])
	expect(route.size() > 1 and route.back() == remote,"charted core provides a multi-hop path for the long-haul freighter")
	var blocked: Array = []
	for system_id in range(1,world.core_count):
		if system_id != remote:
			blocked.append(system_id)
	expect(Economy.flight_route(world,0,remote,blocked).is_empty() and Economy.flight_route(world,0,remote,[]) == route,"travel bans block intermediate beacons without altering other ships' routes")
	var stop_id: int = world.port(remote,"远轨货站",world.Celestial.gravity_point(world.systems[remote])+Vector2(16000,0),world.NEUTRAL,0,Industry.Module.SOLAR)
	var destination: Dictionary = world.ports[stop_id]
	var ware := Industry.Ware.ORE
	ship.job = {"kind":"贸易","source":source.id,"target":stop_id,"phase":1,"ware":ware}
	ship.cargo[ware] = 7
	ship.trade_rules = {"travel":blocked}
	expect(not Economy.reserve(world,ship,source,destination,ware,7,false) and not destination.inbound.has(ship.id),"unreachable route cannot lock destination capacity")
	ship.trade_rules = {}
	ship.fuel = 0.0
	source.stock[Industry.Ware.FUEL] = 0
	Economy.reserve(world,ship,source,destination,ware,7,false)
	Economy.begin_trip(world,ship,destination)
	expect(ship.dock == source.id and ship.travel.is_empty() and not destination.inbound.has(ship.id) and ship.cargo[ware] == 7,
		"dry fuel pump prevents departure and releases the booking without losing the freight")
	var plan := Economy.trip_plan(world,ship,ship.system,ship.pos,ship.layer,destination)
	var initial_stock := ceili(plan.fuel)+2
	source.stock[Industry.Ware.FUEL] = initial_stock
	var opening_balance: int = world.active().wallet
	expect(Economy.reserve(world,ship,source,destination,ware,7,false),"book already-loaded freight through reachable beacons")
	if not ship.has("reservation"):
		return
	var expires: int = ship.reservation.expires
	Economy.begin_trip(world,ship,destination)
	var supplied: int = initial_stock-source.stock[Industry.Ware.FUEL]
	expect(supplied >= ceili(plan.fuel) and ship.fuel == supplied and opening_balance-world.active().wallet == supplied,
		"NPC fills its tank from actual port stock at the same pump tariff as civilian pilots")
	var visited: Array = []
	var remained_booked := true
	var offscreen_motion := false
	var paid := false
	var distance_flown := 0.0
	var ordinary_flight_days := 0
	var burns_match := true
	var hull: Dictionary = Hulls.MODELS[ship.kind]
	for _day in range(expires+1):
		var had_balance: int = world.active().wallet
		var position: Vector2 = ship.pos
		var space_position: Vector2 = ship.galpos
		var previous_fuel: float = ship.fuel
		var was_in_hyperspace: bool = ship.layer
		world.tick()
		if was_in_hyperspace:
			var moved := space_position.distance_to(ship.galpos)
			distance_flown += moved
			burns_match = burns_match and absf(previous_fuel-ship.fuel-Hyperspace.fuel_for_distance(hull,moved)) < 0.0001
			if absf(moved-Hyperspace.distance_per_day(hull)) < 0.001:
				ordinary_flight_days += 1
		if ship.system != 0 and (visited.is_empty() or visited.back() != ship.system):
			visited.append(ship.system)
		if not ship.layer and ship.system == remote and ship.dock == 0 and position.distance_to(ship.pos) > 0:
			offscreen_motion = true
		if ship.cargo[ware] == 0:
			var pumped := maxi(0,roundi(ship.fuel-previous_fuel))
			paid = world.active().wallet + pumped > had_balance
			break
		remained_booked = remained_booked and destination.inbound.get(ship.id,{}).get("expires",0) == expires
	expect(visited == route and offscreen_motion,"freighter physically crosses each intervening system and approaches the distant berth")
	expect(burns_match and ordinary_flight_days > 1 and absf(distance_flown - float(plan.distance)) < 0.01,
		"each interstellar step uses the common cruise speed, real fuel rate and the full plotted distance")
	expect(world.day > 100 and world.day < expires and remained_booked,"original reservation covers the entire hundred-day remote approach")
	expect(ship.dock == stop_id and paid and ship.cargo[ware] == 0 and not destination.inbound.has(ship.id),"long-haul goods were unloaded and paid for by the receiving market")
	print("Freight delivery day=%d deadline=%d hops=%d distance=%.1f fuel=%.2f" % [world.day,expires,visited.size(),distance_flown,plan.fuel])

func starter_market_balance() -> void:
	var world := World.new()
	world.new_game({"seed":"anchor","systems":24,"factions":5,"avatar":{"noble":false,"origin":0}})
	var ship := world.ride()
	var starting_cash: int = world.active().wallet
	var home: Dictionary = world.ports[ship.dock]
	var mine: Dictionary = world.ports[world.systems[1].ports[0]]
	var refinery: Dictionary = world.ports[world.systems[1].ports[1]]
	var ware := Industry.Ware.ORE
	var profits: Array[int] = []
	for trip in 3:
		var before: int = world.active().wallet
		world.berth(ship,mine.id)
		var cost := Economy.trade_quote(world,mine,ware,18)
		var freight := Industry.freight_quote(mine,refinery,ware,18,before)
		var bought := Economy.trade(world,mine.id,ware,18)
		world.berth(ship,refinery.id)
		var receipts := Economy.trade_quote(world,refinery,ware,-18)
		var sold := Economy.trade(world,refinery.id,ware,-18)
		var profit: int = world.active().wallet-before
		expect(bought==18 and sold==-18 and ship.cargo[ware]==0 and profit==receipts.y-cost.y,
			"commoner can settle both quoted legs of each eighteen-unit shipment")
		profits.append(profit)
		if trip==0:
			expect(profit>0 and profit<=cost.y*0.30 and profit<starting_cash*0.10 and freight==Vector2i(18,profit),
				"an opening shortage pays a modest return at the same prices as commercial freight")
		if trip==2:
			expect(freight==Vector2i.ZERO,"freight stops quoting the filled order as a profitable run")
	expect(profits[0]>profits[1] and profits[1]>0 and profits[2]<=0,
		"without new consumption each load narrows the spread until the full run loses money")
	ware = Industry.Ware.ALLOY
	world.berth(ship,home.id)
	var cash: int = world.active().wallet
	var ask := Economy.trade_quote(world,home,ware,18)
	var bulk := Industry.freight_quote(home,mine,ware,18,cash)
	var bought := Economy.trade(world,home.id,ware,18)
	world.berth(ship,mine.id)
	var bid := Economy.trade_quote(world,mine,ware,-18)
	var sold := Economy.trade(world,mine.id,ware,-18)
	expect(ware not in mine.imports and bought==18 and sold==-18 and bid.y>0 and bid.y<ask.y
			and world.active().wallet==cash+bid.y-ask.y and bulk==Vector2i.ZERO,
		"the mine still buys unwanted alloy for resale without offering a shortage premium")
	print("Starting cash %d, 18-ore consecutive profits %s, 18-alloy resale %d -> %d" % [starting_cash,profits,ask.y,bid.y])
	var sampled := mine.duplicate(true)
	for supply in [Industry.Ware.FUEL,Industry.Ware.HULL_PARTS,Industry.Ware.ORDNANCE]:
		sampled.stock[supply] = 0
		var scarce := Economy.price(sampled,supply,false)
		sampled.stock[supply] = int(Industry.stock_target(supply))
		expect(scarce>Economy.price(sampled,supply,false),
			"empty docks pay for scarce goods used to refuel, repair or rearm ships")

func freight_profit() -> void:
	var world = World.new()
	world.new_game({"seed":"fuel-breakeven","systems":12,"factions":3})
	var source: Dictionary = world.ports[world.ride().dock]
	var dest: Dictionary = world.ports[world.systems[1].ports[0]]
	for station in world.ports.values():
		station.exports = []
		station.imports = []
	var ware := Industry.Ware.ORE
	source.exports = [ware]
	dest.imports = [ware]
	source.stock[ware] = 180
	dest.stock[ware] = int(Industry.stock_target(ware) / 2)
	var worker: int = world.random_person(world.NEUTRAL,source.id)
	var ship: Dictionary = world.ships[world.ship(1,world.player,worker,world.NEUTRAL,source.system,source.pos,source.id)]
	ship.cargo[Industry.Ware.SCRAP] = world.cargo_free(ship)-1
	var spread := Economy.lot_quote(dest,ware,1,false).y-Economy.lot_quote(source,ware,1,true).y
	var burn := Hyperspace.fuel_for_distance(Hulls.MODELS[ship.kind],world.distance(source.system,dest.system))
	expect(spread > 0 and spread < burn and Economy.trade_plan(world,ship).is_empty(),
		"a one-unit load with a positive price spread but negative profit after fuel stays in port")
	ship.cargo[Industry.Ware.SCRAP] = 0
	var viable := Economy.trade_plan(world,ship)
	expect(viable.get("source",0) == source.id and viable.get("target",0) == dest.id and viable.ware == ware,
		"a cargo large enough to cover fuel makes the same automatic route profitable again")

func freight_capacity() -> void:
	var small := haul_same_route("dram")
	var large := haul_same_route("colossus")
	expect(small.x == Hulls.MODELS[Hulls.kind_for_reference("dram")].cargo and large.x > small.x and large.y > small.y,
		"a larger hold sells more and earns more on the same autonomous route")
	print("Automatic ore freight same route: Dram %d units +%d credits, Colossus %d units +%d credits" % [small.x,small.y,large.x,large.y])
	var world := World.new()
	world.new_game({"seed":"mining-capacity","systems":12,"factions":3})
	var source: Dictionary = world.ports[world.ride().dock]
	var ore := Industry.Ware.ORE
	source.exports = [ore]
	source.imports = []
	source.stock[ore] = 12
	var pool := ["dram","buffalo","colossus"]
	var light := world.freight_hull(pool,source)
	source.stock[ore] = 350
	var heavy := world.freight_hull(pool,source)
	expect(Hulls.MODELS[light].reference == "dram" and Hulls.MODELS[heavy].reference == "colossus",
		"the same shipyard equips a light or heavy NPC hauler according to its actual freight volume")
	var refinery: Dictionary = world.ports[world.systems[1].ports[1]]
	refinery.stock[ore] = 350
	refinery.exports = [ore]
	refinery.imports = []
	expect(Hulls.MODELS[world.freight_hull(pool,refinery)].reference == "buffalo","small berths cap the hauler that can actually operate there")
	var ship_id := world.ship(Hulls.kind_for_reference("buffalo"),world.player,world.random_person(world.NEUTRAL,source.id),world.NEUTRAL,0,source.pos,source.id)
	var ship: Dictionary = world.ships[ship_id]
	world.depart(ship)
	var field: Dictionary = world.systems[ship.system]
	ship.pos = field.field
	ship.job = {"kind":"采矿","source":source.id,"target":refinery.id,"phase":0,"ware":ore}
	field.ore = 100
	refinery.stock[ore] = 0
	var rate: int = Hulls.MODELS[ship.kind].mine
	Economy.step_ship(world,ship)
	expect(ship.job.phase == 0 and ship.cargo[ore] == rate and field.ore == 100-rate,"one mining cycle consumes its actual rated yield and remains on site")
	for cycle in ceili(100.0/rate):
		if ship.job.phase != 0:
			break
		Economy.step_ship(world,ship)
	expect(ship.job.phase == 1 and ship.cargo[ore] == 100 and field.ore == 0,"the miner carries successive real batches until the field runs dry")

func haul_same_route(reference: String) -> Vector2i:
	var world := World.new()
	world.new_game({"seed":"hold-throughput","systems":12,"factions":3})
	var source: Dictionary = world.ports[world.ride().dock]
	var dest: Dictionary = world.ports[world.port(0,"集散港",source.pos+Vector2(460,0),world.NEUTRAL,0,Industry.Module.YARD)]
	var ore := Industry.Ware.ORE
	for port: Dictionary in world.ports.values():
		port.exports = []
		port.imports = []
	source.exports = [ore]
	dest.imports = [ore]
	source.stock[ore] = 350
	dest.stock[ore] = 0
	var initial: int = source.stock[ore]
	var worker := world.random_person(world.NEUTRAL,source.id)
	var ship: Dictionary = world.ships[world.ship(Hulls.kind_for_reference(reference),world.player,worker,world.NEUTRAL,0,source.pos,source.id)]
	world.active().wallet = 50000
	var before: int = world.active().wallet
	ship.job = {"kind":"贸易","automatic":true,"phase":0}
	Economy.step_ship(world,ship)
	var loaded: int = ship.cargo[ore]
	expect(loaded > 25 and loaded == ship.job.get("quantity",0) and source.stock[ore] == initial-loaded and dest.stock[ore] == 0 and world.active().wallet < before,
		reference+" loaded and paid for its chosen quantity at the origin")
	# Run this vessel through ordinary physical transit, without other markets trading between our two samples.
	Economy.step_ship(world,ship)
	for _day in range(40):
		if ship.dock == dest.id:
			break
		world.day += 1
		Economy.transit_day(world)
	Economy.step_ship(world,ship)
	var earned: int = world.active().wallet-before
	expect(loaded > 0 and dest.stock[ore] == loaded and ship.cargo[ore] == 0 and ship.dock == dest.id and earned > 0 and not dest.inbound.has(ship.id),
		reference+" docked, unloaded and received payment for the entire booked lot")
	if reference == "colossus":
		var player_vessel: Dictionary = world.ride()
		var hull: int = world.ship(ship.kind,world.player,0,world.NEUTRAL,0,source.pos,source.id)
		expect(player_vessel.dock == source.id and world.pilot(hull),"pilot the large freighter for a market transaction")
		source.stock[ore] = 350
		var quote := Economy.trade_quote(world,source,ore,100000)
		var bought := Economy.trade(world,source.id,ore,100000)
		expect(bought == Hulls.MODELS[ship.kind].cargo and bought == quote.x and bought > 200 and source.stock[ore] == 350-bought,
			"the current pilot fills a large hold from actual stock in one purchase")
		var sold := Economy.trade(world,source.id,ore,-100000)
		expect(sold == -bought and source.stock[ore] == 350 and world.cargo_free(world.ride()) == bought,
			"the same day's market can unload the entire hold back into its real warehouse")
	return Vector2i(loaded,earned)
