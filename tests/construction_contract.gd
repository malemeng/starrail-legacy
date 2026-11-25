extends SceneTree

const Game = preload("res://game.tscn")
const Hire = preload("res://scripts/campaign/construction_contract.gd")
const Economy = preload("res://economy.gd")
const World = preload("res://world.gd")
const Hulls = preload("res://hull_catalog.gd")
const Industry = preload("res://scripts/economy/industry.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)
	return ok

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.set_physics_process(false)
	var world: World = game.world
	world.new_game({"seed":"civil-engineering","systems":12,"factions":3})
	game.run_bridge()
	var lead := world.ride()
	var yard: Dictionary = world.ports[lead.dock]
	var kind := Hulls.kind_for_id(Hire.HULL_ID)
	var quote := Hire.offer(world,yard.id)
	if check(kind >= 0 and quote.fee > 0 and yard.hulls[kind] > 0,"licensed shipyard offers a real completed engineering cruiser"):
		check_cycle(game,yard,kind,quote.fee)
		owner_built(kind)
	game.free()
	print("Civilian engineering contracts ",checks-failures,"/",checks)
	quit(1 if failures else 0)

func check_cycle(game, yard: Dictionary, kind: int, fee: int) -> void:
	var world: World = game.world
	var lead := world.ride()
	var inventory: int = yard.hulls[kind]
	var fleet := world.ships.size()
	var funds: int = world.active().wallet
	world.active().wallet = fee-1
	check(Hire.hire(world,yard.id) == 0 and yard.hulls[kind] == inventory and world.ships.size() == fleet,"insufficient payment consumes neither a ship nor shipyard stock")
	world.active().wallet = funds + fee + int(Industry.CONSTRUCTION.foundation.credits)
	var balance: int = world.active().wallet
	var yard_balance: int = yard.treasury
	var id := Hire.hire(world,yard.id)
	if not check(id != 0,"charter issued at the player's current yard"):
		return
	var builder: Dictionary = world.ships[id]
	check(yard.hulls[kind] == inventory-1 and world.active().wallet == balance-fee and world.people[builder.captain].ship == id,"one real hull and fee change hands and an independent captain takes command")
	var payout := floori(fee*float(Industry.RULES.ship_market.engineering_crew_share))
	check(yard.treasury-yard_balance == fee-payout and yard.operating_profit == fee-payout,"only the equipment hire portion of the contract is paid to the yard")
	check(not world.pilot(id) and not world.can_operate(builder) and not Economy.assign_role(world,id,lead.id,"ATTACK") and Hire.hire(world,yard.id) == 0,"a single service contract grants neither title, combat command nor a second hull")
	var restored := World.new()
	check(restored.load_state(world.snapshot()) and Hire.active_ship(restored).id == id and not restored.can_operate(restored.ships[id]),"save and reload preserve the exact independent contractor")
	game.flight.dock()
	check(lead.dock == 0 and builder.dock == 0 and game.flight.escort(builder,lead),"contractor actually departs the yard behind the flagship")
	var body: Dictionary = world.systems[lead.system].planets[0]
	var point: Vector2 = Vector2(body.pos) + Vector2.RIGHT * (body.radius+110.0)
	var total_ports := world.ports.size()
	check(Economy.deploy(world,Industry.Module.SOLAR,point) == 0 and world.ports.size() == total_ports,"a yard contract cannot deploy a remote station while its equipment is elsewhere")
	var arrived := false
	for frame in range(24000):
		point = Vector2(body.pos) + Vector2.RIGHT * (body.radius+110.0)
		if lead.pos.distance_to(point) < 25.0 and Economy.build_ship_for(world,point) == id:
			arrived = true
			break
		if frame % 12 == 0:
			game.set_waypoint(point)
			game.set_speed(3)
		game.step_simulation(Vector2.ZERO,false,false,Vector2.ZERO,false)
	if not check(arrived,"the independent engineer follows the pilot to the actual orbital construction site"):
		print("Approach lead=",lead.pos.distance_to(point)," builder=",builder.pos.distance_to(point)," combat=",lead.locked," day=",world.day)
		return
	var site := Economy.deploy(world,Industry.Module.SOLAR,point)
	if not check(site != 0 and world.ports[site].construction_ship == id,"a nearby working engineer establishes and signs exactly one orbital project"):
		print(Economy.construction_issue(world,Industry.Module.SOLAR,point))
		return
	check(Hire.active_ship(world).id == id and builder.construction_contract.status == "working" and builder.construction_contract.site == site and not game.flight.escort(builder,lead),"the paid project ends its escort and assigns the same vessel to the worksite")
	check(Economy.build_ship_for(world,point) == 0 and not Hire.cancel(world),"on-duty equipment cannot be reassigned or signed off before completion")
	game.flight.dock()
	var foundation: Dictionary = world.ports[site]
	world.tick(42)
	check(builder.dock == site and Vector2(builder.pos).distance_to(foundation.pos) < 0.01 and foundation.build == int(Industry.CONSTRUCTION.foundation.days) and builder.construction_contract.status == "working","the engineer stays attached to the moving berth while waiting for missing materials")
	var working_save := World.new()
	check(working_save.load_state(world.snapshot()) and working_save.ships[id].construction_contract.status == "working" and working_save.ships[id].dock == site,"an unfunded active worksite and the assigned engineer survive reloading")
	for ware in Industry.FOUNDATION:
		lead.cargo[ware] = Industry.FOUNDATION[ware]
	check(lead.dock == site and Economy.donate(world,site) > 0,"the owner delivers the real foundation material to the waiting contractor")
	for day in range(36):
		world.tick()
		if foundation.build == 0:
			break
	check(foundation.build == 0 and builder.construction_contract.status == "returning" and Hire.active_ship(world).is_empty(),"only a completed project releases the signed ship to return to its yard")
	var homeward: Vector2 = builder.pos
	world.tick()
	check(builder.dock == 0 and not Vector2(builder.pos).is_equal_approx(homeward),"returning to the yard consumes actual flight time")
	for day in range(1600):
		world.tick()
		if builder.construction_contract.status == "available":
			break
	check(builder.dock == yard.id and builder.construction_contract.status == "available","the original independent ship and crew arrive back at their yard")
	world.berth(lead,yard.id)
	world.active().wallet += Hire.offer(world,yard.id).fee
	var yard_stock: int = yard.hulls[kind]
	var same := Hire.hire(world,yard.id)
	var paid: int = world.active().wallet
	check(same == id and yard.hulls[kind] == yard_stock,"a later job reuses the returned hull without withdrawing or duplicating another ship")
	check(Hire.cancel(world) and not Hire.cancel(world) and builder.dock == yard.id and world.active().wallet == paid and yard.hulls[kind] == yard_stock,"cancelling at the yard returns availability once without a refund or free inventory")
	print("Engineering service fee=",fee," credits; returned hull=",id," project=",site," day=",world.day)

func owner_built(kind: int) -> void:
	var world := World.new()
	world.new_game({"seed":"civil-engineering","systems":12,"factions":3})
	var yard: Dictionary = world.ports[world.ride().dock]
	var id := world.ship(kind,world.player,0,world.NEUTRAL,0,yard.pos,yard.id)
	world.pilot(id)
	var ship := world.ride()
	world.depart(ship)
	var body: Dictionary = world.systems[0].planets[0]
	ship.pos = Vector2(body.pos)+Vector2.RIGHT*(body.radius+110.0)
	var site := Economy.deploy(world,Industry.Module.SOLAR,ship.pos)
	if not check(site != 0 and world.ports[site].construction_ship == id,"an owned and piloted engineering cruiser can accept its own orbital project"):
		return
	var foundation: Dictionary = world.ports[site]
	for ware in Industry.FOUNDATION:
		ship.cargo[ware] = Industry.FOUNDATION[ware]
	world.berth(ship,site)
	Economy.donate(world,site)
	world.depart(ship)
	ship.pos += Vector2(3000,3000)
	check(Economy.build_ship_for(world,ship.pos) == 0,"the same privately owned hull cannot sign a second site while the first is outstanding")
	world.tick(36)
	check(foundation.build == Industry.CONSTRUCTION.foundation.days,"a funded worksite pauses when its owner's equipment departs")
	world.berth(ship,site)
	world.tick(36)
	world.depart(ship)
	check(foundation.build == 0 and Economy.build_ship_for(world,ship.pos) == id,"bringing the owned builder back completes the first project and frees it for the next")
