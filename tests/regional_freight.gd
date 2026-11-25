extends SceneTree

const World = preload("res://world.gd")
const Economy = preload("res://economy.gd")
const Industry = Economy.Industry
const Area = Economy.OperatingArea
const SEED := "freight-distances-1122"
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)
	return ok

func _initialize() -> void:
	var world := World.new()
	world.new_game({"seed":SEED,"systems":24,"factions":5})
	var merchants := 0
	var interstellar := 0
	var distance := 0.0
	var carrier: Dictionary = {}
	var plan: Dictionary = {}
	for ship: Dictionary in world.ships.values():
		if ship.job.get("kind","") != "贸易":
			continue
		merchants += 1
		var route := Economy.trade_plan(world,ship)
		if route.is_empty():
			continue
		var source: Dictionary = world.ports[route.source]
		var target: Dictionary = world.ports[route.target]
		var trip := Economy.trip_plan(world,ship,source.system,source.pos,false,target)
		if trip.route.is_empty():
			continue
		interstellar += 1
		distance += trip.distance
		if carrier.is_empty() and trip.route.size() >= 2 and source.id == ship.dock:
			carrier = ship
			plan = route
	check(interstellar*2 > merchants,"regional production offers cross-system work to most of the opening NPC traders")
	print("Opening NPC loaded routes ",interstellar,"/",merchants," cross-system, total chart distance ",snappedf(distance,0.1))
	if check(not carrier.is_empty(),"at least one opening contract can load here and deliver through an intermediate system"):
		complete_delivery(world,carrier,plan)
	check_player_radius(world)
	check_campaign_deliveries()
	print("Regional freight ",checks-failures,"/",checks)
	quit(1 if failures else 0)

func complete_delivery(world, ship: Dictionary, plan: Dictionary) -> void:
	var source: Dictionary = world.ports[plan.source]
	var target: Dictionary = world.ports[plan.target]
	var trip := Economy.trip_plan(world,ship,source.system,source.pos,false,target)
	var starting_tank: float = ship.fuel
	var quantity: int = plan.quantity
	var buying := Industry.lot_invoice(source,plan.ware,quantity,true)
	var selling := Industry.lot_invoice(target,plan.ware,quantity,false)
	var source_cash: int = source.treasury
	var target_cash: int = target.treasury
	var target_stock: int = target.stock[plan.ware]
	Economy.step_ship(world,ship)
	if not check(ship.cargo[plan.ware] == quantity and source.treasury-source_cash == buying.base,"the AI reserves the contract, pays the supplier and loads the quoted quantity"):
		return
	Economy.step_ship(world,ship)
	var days := 0
	while not ship.travel.is_empty() and days < trip.days+12:
		Economy.fly_leg(world,ship,target,1.0)
		days += 1
	check(ship.dock == target.id and days >= trip.route.size() and absi(days-trip.days) <= 6,"the loaded hauler physically reaches its destination close to its advertised ETA")
	Economy.step_ship(world,ship)
	check(ship.cargo[plan.ware] == 0 and target.stock[plan.ware]-target_stock == quantity and target_cash-target.treasury == selling.base,"the receiver pays its own cash on delivery and takes the full cargo")
	var fuel: float = starting_tank-ship.fuel
	var net: int = selling.total-buying.total-ceili(fuel)
	check(net > 0 and fuel > 0 and is_equal_approx(fuel,trip.fuel),"the executed multi-hop order pays a positive margin after tax and actual fuel")
	print("Executed ",trip.route.size()," jumps / ",snappedf(trip.distance,0.1)," chart units / ",days," flight days, ",quantity," units, ",net," net")

func check_player_radius(world) -> void:
	var home: Dictionary = world.ports[world.ride().dock]
	var captain: int = world.random_person(world.NEUTRAL,home.id)
	var id: int = world.ship(world.Hulls.kind_for_reference("colossus"),world.player,captain,world.NEUTRAL,home.system,home.pos,home.id)
	var ship: Dictionary = world.ships[id]
	world.people[captain].employer = world.player
	world.people[captain].stats.stewardship = 12
	check(Economy.assign(world,id,captain,"自动贸易") and Area.settings(world,ship).jumps >= 3,"large player freighters also receive an extended default search area")
	check(Area.configure(world,id,home.id,0) and Area.coverage(world,ship).keys() == [home.system],"an explicit same-system limit overrides a heavy freighter's default")
	check(Economy.freight_score(100,0,45) > Economy.freight_score(100,22,23),"equal-profit orders with the same voyage time favor carrying cargo over empty repositioning")

func check_campaign_deliveries() -> void:
	var world := World.new()
	world.new_game({"seed":SEED,"systems":24,"factions":5})
	var completed := 0
	for day in 165:
		var hauling := {}
		for ship: Dictionary in world.ships.values():
			if ship.job.get("kind","") == "贸易" and ship.job.get("phase",0) == 1 and ship.has("reservation"):
				var order: Dictionary = ship.reservation
				if world.ports[order.source].system != world.ports[order.target].system:
					hauling[ship.id] = [order.target,order.ware]
		world.tick()
		for id: int in hauling:
			var ship: Dictionary = world.ships.get(id,{})
			if ship.get("dock",0) == hauling[id][0] and not ship.has("reservation") and ship.cargo[hauling[id][1]] == 0:
				completed += 1
	check(completed >= 2,"NPC ships deliver between systems in a running campaign with production, competing captains and security active")
	print("Live campaign day ",world.day,", completed NPC intersystem shipments ",completed)
