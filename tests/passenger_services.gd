extends SceneTree

const Game = preload("res://game.tscn")
const Bridge = preload("res://agent_bridge.gd")
const MobileAgent = preload("res://scripts/services/mobile_model_agent.gd")
const Economy = preload("res://economy.gd")
const Politics = preload("res://politics.gd")
const World = preload("res://world.gd")

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
	return ok

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.set_physics_process(false)
	var world: World = game.world
	world.new_game({"seed": "changes-review-1127", "systems": 12, "factions": 3})
	var home: Dictionary = world.ports[world.ride().dock]
	game.run_bridge()
	var bridge := Bridge.new()
	bridge.game = game
	var liner: Dictionary = Economy.docked_liners(world, home.id).front()
	check_fares(game, bridge, liner)
	check_companies(world, bridge, home, liner)
	game.free()
	print("Passenger services ", checks - failures, "/", checks)
	quit(1 if failures else 0)

func check_fares(game, bridge, liner: Dictionary) -> void:
	var world: World = game.world
	var dest := int(liner.job.route[1])
	var base := Economy.ticket_price(world, int(liner.dock), dest)
	var passenger := world.active()
	world.disembark()
	passenger.wallet = 900
	world.people[liner.captain].stats.diplomacy = 10
	var negotiated := roundi(base * 1.1)
	var peak := roundi(negotiated * 1.25)
	game.refresh()
	var observed: Dictionary = bridge.observe()
	var quote: Dictionary = observed.passenger_liners[0].stops[0]
	check(quote.port == dest and quote.fare == negotiated, "agent sees captain surcharge")
	var mobile := MobileAgent.compact_receipt({"ok": true, "state": observed})
	check("board_liner" in MobileAgent.ACTIONS and mobile.state.passenger_liners == observed.passenger_liners, "mobile model can use the same quote")
	var label := "%s (¢%d)" % [world.ports[dest].name, negotiated]
	var buy: Button
	for picker: OptionButton in game.body.find_children("*", "OptionButton", true, false):
		if picker.item_count > 0 and picker.get_item_text(0) == label:
			buy = picker.get_parent().get_child(-1) as Button
			break
	if not check(is_instance_valid(buy) and buy.text == "购票乘船", "port shows the same fare"):
		return
	for seat in range(ceili(Economy.passenger_capacity(liner) / 2.0)):
		var npc := world.random_person(world.NEUTRAL, int(liner.dock))
		world.people[npc].wallet = 900
		check(Economy.board_passenger(world, npc, int(liner.id), dest).ok, "passenger takes a seat")
	buy.pressed.emit()
	check(passenger.wallet == 900 and passenger.loc == liner.dock and passenger.id not in liner.passengers, "stale UI fare leaves passenger and funds in place")
	quote = bridge.observe().passenger_liners[0].stops[0]
	check(quote.fare == peak, "half-full surcharge stacks on negotiated fare")
	var args := {"ship": liner.id, "dest": dest, "fare": negotiated}
	check(not bridge.dispatch("board_liner", args).ok and passenger.wallet == 900, "stale agent quote also leaves funds in place")
	args.fare = quote.fare
	var receipt: Dictionary = bridge.dispatch("board_liner", args)
	check(receipt.ok and receipt.result.fare == peak and passenger.wallet == 900 - peak, "agent quote matches receipt and wallet")
	check(bridge.dispatch("disembark_liner", {}).ok and passenger.loc == liner.dock, "agent leaves the docked liner")
	passenger.wallet = base
	check(Economy.passenger_fare(world, passenger, liner, dest) == base, "passenger with exact base fare keeps the original discount")
	game.refresh()
	for button: Button in game.body.find_children("*", "Button", true, false):
		if button.text == "购票乘船":
			button.pressed.emit()
			break
	check(passenger.wallet == 0 and int(passenger.get("transit_ship", 0)) == int(liner.id), "port button charges its displayed fare")
	bridge.dispatch("disembark_liner", {})

func check_companies(world: World, bridge, home: Dictionary, public_liner: Dictionary) -> void:
	var founder := world.random_person(world.NEUTRAL, int(home.id))
	var captain := world.random_person(world.NEUTRAL, int(home.id))
	world.people[founder].wallet = 3500
	var sid := world.ship(int(public_liner.kind), founder, captain, world.NEUTRAL, int(home.system), home.pos, int(home.id))
	var ship: Dictionary = world.ships[sid]
	var home_flag := int(home.flag)
	var firm_count := world.firms.size()
	home.flag = world.RAIDERS
	check(not Politics._npc_found_service_company(world, world.people[founder], home, "found_liner"), "founder waits when no route can operate")
	check(world.people[founder].wallet == 3500 and ship.owner == founder and world.firms.size() == firm_count, "failed launch keeps the founder's ship and cash")
	home.flag = home_flag
	check(Politics._npc_found_service_company(world, world.people[founder], home, "found_liner"), "NPC incorporates with an existing ship")
	check(world.ship_principal(ship) == founder and ship.job.get("kind") == "客运" and ship.default_behavior == ship.job, "founder's ship immediately runs its route")
	check(not bridge.dispatch("assign_passenger_liner", {"ship": sid}).ok, "player cannot reassign an NPC company's liner")
	var passenger := world.random_person(world.NEUTRAL, int(home.id))
	world.people[passenger].wallet = 900
	var firm: Dictionary = world.firms[ship.firm]
	var balance := int(firm.treasury)
	var ticket := Economy.board_passenger(world, passenger, sid, int(ship.job.route[1]))
	check(ticket.ok and firm.treasury == balance + int(ticket.fare), "ticket revenue reaches the NPC company")
	Economy.step_ship(world, ship)
	Economy.step_ship(world, ship)
	check(ship.dock == 0 and not ship.travel.is_empty(), "the company's first scheduled departure takes place")

	var builder_kind := world.Hulls.kind_for_id("gantry_ca")
	home.hulls[builder_kind] = 1
	var builder_founder := world.random_person(world.NEUTRAL, int(home.id))
	world.people[builder_founder].wallet = 100000
	world.random_person(world.NEUTRAL, int(home.id))
	if not check(Politics._npc_found_service_company(world, world.people[builder_founder], home, "found_construction"), "NPC buys and incorporates an engineering ship"):
		return
	var builder: Dictionary = {}
	for candidate: Dictionary in world.ships.values():
		if world.ship_principal(candidate) == builder_founder:
			builder = candidate
			break
	if not check(not builder.is_empty() and builder.job.get("kind") == "工程承包", "builder immediately has a construction assignment"):
		return
	check(not bridge.dispatch("assign_contractor", {"ship": builder.id}).ok, "player cannot reassign an NPC contractor")
	builder.job = {}
	builder.default_behavior = {}
	var restored := World.new()
	if check(restored.load_state(world.snapshot()), "earlier company without a first assignment can reload"):
		var idle: Dictionary = restored.ships[builder.id]
		Economy.step_ship(restored, idle)
		check(idle.job.get("kind") == "工程承包", "existing idle contractor resumes the company service")
