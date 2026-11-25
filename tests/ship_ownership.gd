extends SceneTree

const World = preload("res://world.gd")
const Economy = preload("res://economy.gd")
const Hulls = preload("res://hull_catalog.gd")
const Payload = preload("res://scripts/battle/system_ordnance.gd")
const Politics = preload("res://politics.gd")
const Game = preload("res://game.tscn")
const Agent = preload("res://agent_bridge.gd")

var checks := 0
var failures := 0
var api := Agent.new()

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func scenario(noble: bool = false) -> World:
	var world := World.new()
	world.new_game({"seed":"working-captain","systems":12,"factions":3,"avatar":{"name":"林安","noble":noble}})
	return world

func ownership() -> void:
	var world := scenario()
	var actor := world.active()
	var ship := world.ride()
	var home: int = ship.dock
	var quote := Economy.charter_quote(world,ship.id)
	var hull_price: int = Economy.ship_quote(world.ports[home],ship.kind).price
	var minimum := 2147483647
	for kind in Hulls.MODELS.size():
		if Hulls.model_limit(world.ports[home],kind):
			minimum = mini(minimum,Economy.ship_quote(world.ports[home],kind).price)
	var yearly_pay := 4 * int(Economy.Industry.RULES.ship_market.captain_quarterly_pay)
	expect(not world.oversees(ship.owner) and world.can_operate(ship) and ship.captain == actor.id,"a working captain can sail but does not own the hull")
	expect(minimum > 0 and quote.price > 0 and quote.price < hull_price,"used charter costs less than the retail hull")
	actor.wallet = quote.price - 1
	expect(not Economy.buyout_charter(world,ship.id) and ship.has("charter"),"insufficient funds leave the starter contract open")
	expect(Payload.payload(ship,"mine",Vector2.ZERO,Vector2.ZERO,1.0,1.0).credit == actor.id,"captain receives combat credit")
	var other := world.ship(ship.kind,actor.id,0,ship.flag,ship.system,ship.pos,home)
	var worker := world.random_person(world.NEUTRAL,home)
	expect(world.pilot(other) and not Economy.assign(world,ship.id,worker,"护航") and world.pilot(ship.id),"can return to a charter but cannot hand it to hired staff")
	var loaded := World.new()
	expect(loaded.load_state(world.snapshot()) and loaded.ride().charter == ship.charter,"charter and entitlement survive save/load")
	var ship_count := world.ships.size()
	var inventory: Array = world.ports[home].hulls.duplicate()
	var balance: int = quote.price
	actor.wallet = balance
	world.depart(ship)
	expect(not Economy.buyout_charter(world,ship.id) and actor.wallet == balance,"buyout is available only at the registry")
	world.berth(ship,home)
	expect(Economy.buyout_charter(world,ship.id) and actor.wallet == 0 and ship.owner == actor.id and not ship.has("charter"),"buyout transfers this hull and charges once")
	expect(world.ships.size() == ship_count and world.ports[home].hulls == inventory and not Economy.buyout_charter(world,ship.id),"buyout neither duplicates a hull nor consumes retail inventory")
	var noble := scenario(true)
	expect(noble.ride().owner == noble.player and not noble.ride().has("charter"),"a noble starts with a family hull")
	print("Retail minimum ",minimum,"; starter new ",hull_price,"; charter buyout ",balance,"; employed captain's gross annual pay ",yearly_pay)

func markets() -> void:
	for black: bool in [false,true]:
		var world := scenario()
		var actor := world.active()
		var home: Dictionary = world.ports[actor.loc]
		var ship := world.ride()
		var ware := Economy.Industry.Ware.HULL_PARTS
		actor.wallet = 10000
		actor.origin = 1
		home.tax_rate = 0.0
		home.owner = actor.id
		home.firm = 0
		home.pop = 1000
		var stock: Array = home.black if black else home.stock
		stock[ware] = 64
		var start: int = actor.wallet
		var quote := Economy.trade_quote(world,home,ware,36,black)
		expect(Economy.trade(world,home.id,ware,36,black) == 36 and start - actor.wallet == quote.y,"bulk purchase pays the full supply curve")
		expect(Economy.trade(world,home.id,ware,-36,black) == -36 and actor.wallet < start and stock[ware] == 64,"selling back a whole batch at one's own station cannot generate credit")
		actor.wallet = 70
		quote = Economy.trade_quote(world,home,ware,36,black)
		var before: int = actor.wallet
		expect(Economy.trade(world,home.id,ware,36,black) == quote.x and actor.wallet == before - quote.y and actor.wallet >= 0,"partial purchase respects funds and the quoted total")

func yard_accounting() -> void:
	var world := scenario()
	var ship := world.ride()
	var home: Dictionary = world.ports[ship.dock]
	var kind: int = ship.kind
	var initial := Economy.ship_quote(home,kind)
	var bill := Economy.Industry.vessel_recipe(Hulls.MODELS[kind],home.method)
	var sum := 0
	for line in initial.materials:
		expect(bill[line.ware] == line.units and line.cost == Economy.lot_quote(home,line.ware,line.units,true).y,"a quote values the actual replenishment bill at executable unit prices")
		sum += int(line.cost)
	expect(initial.material_cost == sum and initial.labor_cost == ceili(initial.labor_hours*initial.hourly_wage) and initial.price == sum+initial.labor_cost+initial.yard_fee+initial.tax,"invoice adds up to retail price")
	var charter := Economy.charter_quote(world,ship.id)
	expect(charter.replacement_price == initial.price and charter.price + charter.depreciation == initial.price,"used hull is discounted from the same local quote")
	var other: Dictionary = world.ports[world.systems[1].ports[1]]
	other.tax_rate = home.tax_rate
	other.stock = home.stock.duplicate()
	expect(Economy.ship_quote(other,kind).price == initial.price,"same method and market yield the same price")
	home.stock[Economy.Industry.Ware.ALLOY] = 0
	var scarce := Economy.ship_quote(home,kind)
	expect(scarce.material_cost > initial.material_cost and scarce.labor_cost == initial.labor_cost and Economy.ship_quote(other,kind).price < scarce.price,"shortages raise the local material line only")
	var wallet: int = scarce.price
	world.active().wallet = wallet
	var stock: int = home.hulls[kind]
	expect(not Economy.buyout_charter(world,ship.id,charter.price) and Economy.buy_ship(world,home.id,kind,initial.price) == 0 and world.active().wallet == wallet and home.hulls[kind] == stock,"a changed quote never silently spends funds")
	expect(Economy.buy_ship(world,home.id,kind,scarce.price) != 0 and world.active().wallet == 0 and home.hulls[kind] == stock-1,"sale charges the displayed local price exactly once")
	var shipyard_id := world.port(0,"工时验收",Vector2(300,190),world.NEUTRAL,world.player,Economy.Industry.Module.YARD)
	var yard: Dictionary = world.ports[shipyard_id]
	world.berth(ship,shipyard_id)
	world.credit(world.player,initial.labor_cost)
	expect(world.Treasury.transfer(world,yard,world.player,initial.labor_cost),"shipyard receives the payroll for the order")
	yard.pop = 80
	var ordered: int = yard.hulls[kind]
	for ware in bill:
		yard.stock[ware] = bill[ware]
	expect(Economy.order_hull(world,shipyard_id,kind),"place an order with the local shipyard")
	world.day = 30
	Economy.shipyard(world,yard)
	var hours: int = yard.get("yard_work",{}).get("hours",0)
	expect(hours > 0 and hours < initial.labor_hours and yard.hulls[kind] == ordered,"understaffed shipyard carries work on this hull into next month")
	Economy.shipyard(world,yard)
	expect(yard.yard_work.hours == hours and not Economy.set_method(world,shipyard_id,"direct"),"same shifts cannot be reused or switched to another process")
	var restored := World.new()
	expect(restored.load_state(world.snapshot()) and restored.ports[shipyard_id].yard_work.hours == hours,"work in progress survives save/load")
	var started: int = world.day
	while yard.hulls[kind] == ordered and world.day-started < 120:
		world.day += 30
		Economy.shipyard(world,yard)
	expect(yard.hulls[kind] == ordered+1 and yard.production_orders.is_empty() and not yard.has("yard_work"),"labor and funded order produce exactly one completed hull")
	expect(bill.keys().all(func(ware): return yard.stock[ware] == 0),"shipyard consumed all and only the quoted inputs")
	var flag: Dictionary = world.factions[0]
	var capital: Dictionary = world.ports[flag.capital]
	capital.hulls.fill(0)
	capital.hulls[kind] = 1
	for group in world.factions.values():
		group.npc = group == flag
	# Procurement is needed only if no existing patrol can take the assignment.
	for patrol in world.ships.values():
		if patrol.flag == 0 and patrol.job.get("kind","") == "护航":
			patrol.locked = true
	flag.last_war = -10000
	world.set_treaty(0,1,-1)
	var government: int = Economy.ship_quote(capital,kind).price
	flag.treasury = government-1
	expect(Politics.procurement_kind(capital,flag) == -1,"a treasury short one credit cannot procure")
	flag.treasury = government
	Politics.military(world)
	expect(flag.treasury == 0 and capital.hulls[kind] == 0,"the navy pays the full public cost and depletes real inventory")
	print("Local invoice ",initial,"; after alloy shortage ",scarce.price,"; navy ",government)

func _initialize() -> void:
	ownership()
	markets()
	yard_accounting()
	check_flight_clock.call_deferred()

func check_flight_clock() -> void:
	var durations := []
	var steps := []
	for speed: int in [1,3]:
		var game = Game.instantiate()
		game.test_profile = true
		root.add_child(game)
		api.game = game
		api.dispatch("new_game",{"seed":"agent-flight-acceptance"})
		api.dispatch("depart",{})
		api.dispatch("waypoint",{"kind":"gravity"})
		var departure: int = game.world.day
		var ticks := 0
		var stopped := "tick_limit"
		while stopped == "tick_limit" and ticks < 7200:
			var flight := api.dispatch("step",{"ticks":1800,"speed":speed,"stop":"arrival"})
			if not flight.ok:
				break
			ticks += int(flight.result.ticks)
			stopped = flight.result.stopped
		expect(stopped == "arrival","starter reaches the home gravity point at speed %d" % speed)
		durations.append(game.world.day - departure)
		steps.append(ticks)
		game.free()
	expect(durations[0] > 0 and absi(durations[0]-durations[1]) <= 1 and steps[1] < steps[0],"fast-forward reaches the same waypoint in fewer ticks with the same calendar time")
	print("Home to gravity point, speeds 1/3: days ",durations,", simulation ticks ",steps)
	if "--voyage" in OS.get_cmdline_user_args():
		merchant_voyage.call_deferred()
	else:
		finish()

func follow(kind: String, target: int = 0) -> bool:
	var order := api.dispatch("waypoint",{"kind":kind,"target":target})
	if not order.ok:
		print("Navigation rejected ",kind," #",target,": ",order)
		return false
	for segment in 12:
		var arrival := api.dispatch("step",{"ticks":1200,"speed":3,"stop":"arrival"})
		if arrival.ok and arrival.result.stopped == "encounter":
			if not pass_contact(arrival.state) or not api.dispatch("waypoint",{"kind":kind,"target":target}).ok:
				return false
			continue
		if not arrival.ok or arrival.result.stopped != "tick_limit":
			if not arrival.ok or arrival.result.stopped != "arrival":
				print("Navigation stopped ",kind," #",target,": ",arrival.get("error",arrival.get("result",{})))
			return arrival.ok and arrival.result.stopped == "arrival"
	print("Waypoint still distant ",kind," #",target," ship ",api.game.world.ride().pos," waypoint ",api.game.waypoint)
	return false

func pass_contact(state: Dictionary) -> bool:
	for attempt in 35:
		if state.ship.is_empty() or state.attention:
			return false
		if not state.ship.locked:
			return true
		var hostile: Dictionary = {}
		for contact in state.targets:
			if contact.hostile:
				hostile = contact
				break
		if hostile.is_empty():
			return false
		var enemy := Vector2(hostile.pos[0],hostile.pos[1])
		var here := Vector2(state.ship.pos[0],state.ship.pos[1])
		var away := enemy.direction_to(here)
		var result := api.dispatch("step",{"ticks":24,"speed":1,"target":hostile.id,"move":[away.x,away.y],"fire":true,"shield":true,"boost":true,"stop":"never"})
		if not result.ok:
			return false
		state = result.state
	return not state.ship.is_empty() and not state.ship.locked

func travel(destination: Dictionary) -> bool:
	var ship: Dictionary = api.game.world.ride()
	if ship.dock != 0 and not api.dispatch("depart",{}).ok:
		print("Departure unavailable at ",ship.dock)
		return false
	if ship.system != destination.system:
		if not follow("gravity") or not api.dispatch("jump",{}).ok:
			print("Could not leave system ",ship.system," from ",ship.pos," fuel ",ship.fuel," locked ",ship.locked)
			return false
		if not follow("system",destination.system) or not api.dispatch("jump",{}).ok:
			print("Could not reach system ",destination.system," fuel ",ship.fuel)
			return false
	var docked: bool = follow("port",destination.id) and api.dispatch("dock",{}).ok and ship.dock == destination.id
	if not docked:
		print("Could not berth at ",destination.id," current ",ship.dock," hull/fuel ",ship.hp,"/",ship.fuel," locked ",ship.locked)
	return docked

func market_action(label: String) -> bool:
	api.game.dock_view.mode = "market"
	api.game.refresh()
	for item: Button in api.game.body.find_children("*","Button",true,false):
		if item.text.begins_with(label) and not item.disabled:
			item.pressed.emit()
			return true
	print("Port action unavailable: ",label," at ",api.game.world.ride().dock)
	return false

func finish_with_local_ore(home: Dictionary, shortfall: int) -> bool:
	var world: World = api.game.world
	var ship: Dictionary = world.ride()
	var region: Dictionary = world.systems[home.system]
	var units := mini(world.cargo_free(ship),int(region.ore))
	var best: Dictionary = {}
	var value := 0
	for id in region.ports:
		var port: Dictionary = world.ports[id]
		if not Economy.allowed(world,ship,port):
			continue
		var quote := Economy.lot_quote(port,0,mini(units,Economy.Industry.space(port,0)),false,world.active().origin,false,world.Treasury.available(port))
		if quote.y > value:
			value = quote.y
			best = port
	if value < shortfall or best.is_empty() or not api.dispatch("depart",{}).ok or not follow("mine"):
		return false
	while world.cargo_free(ship) > 0 and api.dispatch("mine_or_salvage",{}).ok:
		pass
	if ship.cargo[0] <= 0 or not travel(best):
		return false
	api.dispatch("trade",{"ware":0,"amount":-int(ship.cargo[0])})
	return ship.dock == home.id or travel(home)

func merchant_voyage() -> void:
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	api.game = game
	var launch := api.dispatch("new_game",{"seed":"agent-flight-acceptance","name":"试航商人"})
	var world: World = game.world
	var home: Dictionary = world.ports[world.ride().dock]
	var mine: Dictionary = world.ports[world.systems[1].ports[0]]
	var refinery: Dictionary = world.ports[world.systems[1].ports[1]]
	var hull: int = world.ride().id
	if not launch.ok or not api.dispatch("accept_first_job",{}).ok or not travel(mine):
		expect(false,"depart from home and reach the mine through hyperspace")
		finish()
		return
	if not api.dispatch("trade",{"ware":0,"amount":36}).ok or not travel(refinery) or not api.dispatch("deliver_first_job",{}).ok:
		expect(false,"deliver the first commission at the refinery")
		finish()
		return
	api.dispatch("trade",{"ware":0,"amount":-36})
	if not travel(home):
		expect(false,"return to the starting registry")
		finish()
		return
	expect(api.dispatch("claim_return_bonus",{}).ok,"collect the actual one-time return stipend after delivery")
	print("First trading voyage: day ",world.day,", balance ",world.active().wallet)
	var trips := 0
	while world.active().wallet < Economy.charter_quote(world,hull).price and trips < 20:
		var wallet: int = world.active().wallet
		if finish_with_local_ore(home,Economy.charter_quote(world,hull).price-wallet) and world.active().wallet >= Economy.charter_quote(world,hull).price:
			break
		if world.ride().fuel < 35:
			api.dispatch("refuel",{})
		if not market_action("接运输委托") or not api.dispatch("depart",{}).ok or not follow("mine"):
			break
		while world.cargo_free(world.ride()) > 0 and api.dispatch("mine_or_salvage",{}).ok:
			pass
		if world.ride().cargo[0] < 16:
			if not travel(mine) or not api.dispatch("trade",{"ware":0,"amount":16-world.ride().cargo[0]}).ok:
				break
		if not travel(refinery) or not market_action("交货") or not market_action("接运输委托"):
			break
		var spare: int = world.ride().cargo[0] - 8
		if spare > 0:
			api.dispatch("trade",{"ware":0,"amount":-spare})
		if world.ride().fuel < 35:
			api.dispatch("refuel",{})
		if not travel(home) or not market_action("交货"):
			break
		trips += 1
		print("Freight round trip ",trips," day ",world.day," net ",world.active().wallet-wallet," wallet ",world.active().wallet)
	var price: int = Economy.charter_quote(world,hull).price
	expect(Economy.buyout_charter(world,hull,price) and world.ride().owner == world.player,"ordinary captain buys title using the commission, a trading voyage and local mining")
	print("Voyage buyout: ",trips," freight round trips, day ",world.day,", price ",price,", balance ",world.active().wallet)
	game.free()
	finish()

func finish() -> void:
	print("Ship ownership %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
