extends SceneTree

const Game = preload("res://game.tscn")
const Agent = preload("res://agent_bridge.gd")
const SEED := "agent-flight-acceptance"
# Measured with the released EXE 7E6C03A1, same seed, hull, cargo and flight controls.
const FORMER_DISTANCE := 459.850708
const FORMER_SECONDS := 4.616667
const FORMER_FUEL := 7.323908
const FORMER_DAYS := 18

var checks := 0
var failures := 0

func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)
	return condition

func _initialize() -> void:
	run.call_deferred()

func follow(api, waypoint: Dictionary, speed: int) -> int:
	if not api.dispatch("waypoint", waypoint).ok:
		return -1
	var total := 0
	while total < 36000:
		var response: Dictionary = api.dispatch("step", {"ticks":1800, "speed":speed, "stop":"arrival"})
		if not response.ok:
			return -1
		total += response.result.ticks
		if response.result.stopped == "arrival":
			return total
		if response.result.stopped != "tick_limit" or api.game.world.ride().fuel <= 0:
			return -1
	return -1

func voyage(speed: int, frontier: bool) -> Dictionary:
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.set_physics_process(false)
	var api := Agent.new()
	api.game = game
	var outcome := measure(api, speed, frontier)
	game.free()
	return outcome

func manual_freight() -> void:
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.set_physics_process(false)
	var api := Agent.new()
	api.game = game
	fly_market_route(api)
	game.free()

func freight_trade(api, ware: int, amount: int) -> int:
	var previous: int = api.game.world.active().wallet
	var reply: Dictionary = api.dispatch("trade",{"ware":ware,"amount":amount})
	check(reply.ok and reply.result.moved == amount,"the entire freight lot trades at the dock")
	return int(api.game.world.active().wallet) - previous

func fly_market_route(api) -> void:
	if not check(api.dispatch("new_game",{"seed":SEED}).ok,"create an ordinary charter captain for the freight run"):
		return
	var world = api.game.world
	var ship: Dictionary = world.ride()
	var mine: Dictionary = world.ports[world.Frontier.mine(world)]
	var foundry: Dictionary = world.ports[world.Frontier.foundry(world)]
	var alloy_cost := -freight_trade(api,world.Industry.Ware.ALLOY,18)
	var tank: float = ship.fuel
	if not check(api.dispatch("depart",{}).ok and follow(api,{"kind":"gravity"},3) > 0 and api.dispatch("jump",{}).ok,"depart the home shipyard with alloy"):
		return
	if not check(follow(api,{"kind":"system","target":mine.system},3) > 0 and api.dispatch("jump",{}).ok,"fly the laden ship to the mining system"):
		return
	if not check(follow(api,{"kind":"port","target":mine.id},3) > 0 and api.dispatch("dock",{}).ok,"dock at the mining station and use its live market"):
		return
	var alloy_sale := freight_trade(api,world.Industry.Ware.ALLOY,-18)
	check(alloy_cost > alloy_sale and ship.fuel < tank,"the mine's resale bid leaves a loss even before paying for the jump fuel")
	var ore_cost := -freight_trade(api,world.Industry.Ware.ORE,18)
	var initial_gap: float = ship.pos.distance_to(foundry.pos)
	var departed_day: int = world.day
	if not check(api.dispatch("depart",{}).ok,"depart with ore purchased at the live mine"):
		return
	var ticks := follow(api,{"kind":"port","target":foundry.id},3)
	if not check(ticks > 0 and api.dispatch("dock",{}).ok,"follow the moving foundry and dock to complete the local leg"):
		return
	var ore_sale := freight_trade(api,world.Industry.Ware.ORE,-18)
	var normal_seconds := float(ticks) * 3 / Engine.physics_ticks_per_second
	# Previous release, same flight controls and seed: 1717.49 units and 10.05 seconds at 1x.
	check(initial_gap > 2700 and normal_seconds > 15.0,"the local mine and foundry require a longer physical flight")
	check(ore_cost > 0 and ore_sale > ore_cost and ore_sale < ore_cost * 1.5,"a real consumer pays a modest margin on the first live ore delivery")
	print("MANUAL_FREIGHT ",JSON.stringify({"alloy_cost":alloy_cost,"alloy_sale":alloy_sale,"jump_fuel":tank-float(ship.fuel),
		"ore_cost":ore_cost,"ore_sale":ore_sale,"local_distance":initial_gap,"local_seconds_1x":normal_seconds,"local_days":world.day-departed_day}))

func measure(api, speed: int, frontier: bool) -> Dictionary:
	var game = api.game
	var world = game.world
	if not check(api.dispatch("new_game", {"seed":SEED}).ok and api.dispatch("depart", {}).ok, "a new charter captain departs the home port"):
		return {}
	if not check(not api.dispatch("jump", {}).ok, "the departing ship must reach its local gravity point"):
		return {}
	var local_steps := follow(api, {"kind":"gravity"}, speed)
	if not check(local_steps > 0 and api.dispatch("jump", {}).ok and game.galaxy, "leave the actual gravity point through hyperspace"):
		return {}
	var ship: Dictionary = world.ride()
	var origin: Vector2 = ship.galpos
	var destination := 1
	if frontier:
		var nearest := INF
		destination = -1
		for index in range(world.core_count, world.systems.size()):
			var region: Dictionary = world.systems[index]
			if not region.get("frontier_depot", false) or region.pirate or world.chunk_at(region.pos) == world.chunk_at(origin):
				continue
			var distance := origin.distance_to(region.pos)
			if distance < nearest:
				nearest = distance
				destination = index
	if not check(destination >= 0, "a frontier relay can be selected beyond the home cell" if frontier else "select the tutorial's neighboring system"):
		return {}
	var region: Dictionary = world.systems[destination]
	var initial_fuel: float = ship.fuel
	var day: int = world.day
	var chunks_before: int = world.chunks.size()
	var ticks := follow(api, {"kind":"system", "target":destination}, speed)
	if not check(ticks > 0 and game.flight.nearby_system(ship) == destination, "an unmodified starter ship navigates to the destination beacon"):
		return {}
	var route := {"speed":speed, "route":"frontier" if frontier else "first-neighbor", "destination":region.name,
		"beacon_distance":origin.distance_to(region.pos), "flown_distance":origin.distance_to(ship.galpos),
		"ticks":ticks, "seconds":float(ticks)/Engine.physics_ticks_per_second, "days":world.day-day,
		"fuel":initial_fuel-ship.fuel, "fuel_remaining":ship.fuel, "loaded_chunks":world.chunks.size()-chunks_before}
	check(route.fuel > 0 and route.fuel_remaining > 0, "the journey spends real fuel and leaves reserve in the tank")
	check(api.dispatch("jump", {}).ok and not game.galaxy and ship.system == destination and region.seen, "enter and discover the target through its ordinary jump gate")
	if frontier:
		check(route.loaded_chunks > 0 and world.chunk_at(origin) != world.chunk_at(ship.galpos), "travel crosses the home chart boundary and streams new space")
		check(region.has("depot_port") and world.ports.has(region.depot_port), "arriving at the frontier activates its actual supply station")
	print("TRAVEL_MEASUREMENT ", JSON.stringify(route))
	return route

func run() -> void:
	var normal := voyage(1, false)
	var fast := voyage(3, false)
	var outer := voyage(3, true)
	if not normal.is_empty() and not fast.is_empty():
		check(normal.destination == fast.destination and is_equal_approx(normal.beacon_distance,fast.beacon_distance), "both speeds fly the same seeded route")
		check(absf(float(normal.fuel)-float(fast.fuel)) < 1 and absi(int(normal.days)-int(fast.days)) <= 1, "fast-forward preserves fuel usage and calendar duration")
		check(absf(float(normal.ticks)/float(fast.ticks)-3.0) < 0.12, "3x fast-forward shortens actual passage time proportionally")
		if "--former-release" not in OS.get_cmdline_user_args():
			check(float(normal.beacon_distance) >= FORMER_DISTANCE*1.85, "the first two beacons have more physical space between them")
			check(float(normal.seconds) >= FORMER_SECONDS*2.8, "interstellar passage at normal speed takes time to fly")
			check(absf(float(normal.fuel)-FORMER_FUEL) <= 1.0 and absi(int(normal.days)-FORMER_DAYS) <= 3, "a more spacious route stays affordable in fuel and calendar time")
	check(not outer.is_empty(), "a naturally flown frontier voyage completes")
	if "--former-release" not in OS.get_cmdline_user_args():
		manual_freight()
	print("Interstellar travel %d/%d" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)
