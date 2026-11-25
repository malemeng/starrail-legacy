extends SceneTree

const Game = preload("res://game.gd")
const Agent = preload("res://agent_bridge.gd")
const Celestial = preload("res://celestial.gd")
const Battle = preload("res://combat.gd")
const Hulls = preload("res://hull_catalog.gd")
const Saves = preload("res://scripts/services/save_manager.gd")
const Industry = preload("res://scripts/economy/industry.gd")
const Economy = preload("res://economy.gd")
var checks := 0
var failures := 0

func check(ok: bool, description: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", description)
	return ok

func _initialize() -> void:
	run.call_deferred()

func fly_to(game, point: Vector2) -> bool:
	game.set_waypoint(point)
	game.set_speed(1)
	var vessel: Dictionary = game.world.ride()
	for frame in range(6000):
		game.step_simulation(Vector2.ZERO, false, false, Vector2.ZERO, false)
		if not game.waypoint_live:
			var actual: Vector2 = vessel.galpos if game.galaxy else vessel.pos
			return actual.distance_to(point) < 14.0
		if game.speed == 0 or vessel.locked or (game.galaxy and vessel.fuel <= 0.0):
			return false
	return false

func local_flight(game, api) -> void:
	for point in [Vector2(1540, 1040), Vector2(-1500, -1060)]:
		check(api.dispatch("waypoint", {"kind":"point","pos":[point.x,point.y]}).ok, "set a distant local waypoint through the public bridge")
		check(fly_to(game, point), "actually fly beyond the old local edge at %s" % point)
	var world = game.world
	var origin := Vector2(-1750, 1200)
	var id: int = world.ship(Hulls.kind_for_reference("wolf"), 0, 0, world.NEUTRAL, 0, origin)
	var npc: Dictionary = world.ships[id]
	game.flight.maneuver(npc, Vector2.ZERO, 1.0/60.0, npc.heading)
	check(npc.pos == origin, "an idle NPC outside the old sector stays in place")
	game.flight.maneuver(npc, Vector2.LEFT, 0.2, PI)
	check(npc.pos.x < origin.x and npc.pos.y == origin.y, "NPC thrust operates beyond the old sector")
	var before: Vector2 = npc.pos
	check(Battle.system(world, npc, Vector2.LEFT) and npc.pos.x < before.x and npc.pos.y == before.y,
		"phase skimmer retains direction and range outside the old sector")
	check(api.vector([1100000,-2000000]) == Vector2(1100000,-2000000) and api.vector([INF,0]) == null,
		"finite remote navigation coordinates are accepted and invalid coordinates refused")

func hyperspace(game, api) -> void:
	var world = game.world
	var vessel: Dictionary = world.ride()
	if not check(fly_to(game, Celestial.gravity_point(world.systems[vessel.system])), "return to the local gravity point by flight"):
		return
	game.flight.change_layer()
	var initial_count: int = world.systems.size()
	check(game.galaxy and initial_count > world.core_count, "leaving the port region discovers the first surrounding chunks")
	Economy.flight_graph(world)
	var start: Vector2 = vessel.galpos
	var outward: Vector2 = Vector2(-1.12, -0.34) * world.CHUNK_SIZE
	if not check(fly_to(game, start + outward), "cross several frontier chunks under own power"):
		return
	check(world.systems.size() > initial_count and world.chunk_at(start) != world.chunk_at(vessel.galpos), "moving across chunks streams new stars")
	var count: int = world.systems.size()
	for frame in range(18):
		game.step_simulation(Vector2.ZERO, false, false, Vector2.ZERO, false)
	check(world.systems.size() == count, "stationary flight does not duplicate generated systems")
	var plotted := true
	for records: Array in world.chunks.values():
		if not records.is_empty():
			var depots := records.filter(func(id): return world.systems[id].get("frontier_depot", false))
			plotted = plotted and depots.size() == 1 and world.systems[depots.front()].ports.is_empty()
	check(plotted, "every non-empty outer chunk charts one fuel stop without materializing unexplored economies")
	var destination := -1
	for beacon in api.observe().beacons:
		var chart: Dictionary = world.systems[beacon.id]
		if beacon.id >= initial_count and chart.get("frontier_depot", false) and not chart.pirate:
			destination = beacon.id
			break
	if not check(destination >= 0, "the navigation panel reveals a new outer beacon within reach"):
		return
	var region: Dictionary = world.systems[destination]
	if not check(fly_to(game, region.pos) and game.flight.nearby_system(vessel) == destination, "approach the newly generated beacon and acquire it"):
		return
	game.flight.change_layer()
	check(not game.galaxy and vessel.system == destination and region.seen and vessel.pos == Celestial.gravity_point(region),
		"enter the generated system through its gravity point")
	if not check(region.has("depot_port") and region.ports.size() == 1, "first arrival materializes a single advertised supply port"):
		return
	var depot: int = region.depot_port
	var station: Dictionary = world.ports[depot]
	var route := Economy.flight_route(world,0,destination,[])
	check(not route.is_empty() and route.back() == destination, "newly streamed supply station joins the freighters' physical route network")
	check(station.scan and station.flag == world.NEUTRAL and Industry.Module.CHEMICAL in station.modules and station.hulls.all(func(q): return q == 0),
		"a neutral operating fuel plant has no free ship stock")
	if not check(fly_to(game,station.pos) and api.dispatch("dock",{}).ok and vessel.dock == depot, "ordinary civilian hull reaches the new market and actually docks"):
		return
	for ware: int in [Industry.Ware.ORE,Industry.Ware.FUEL]:
		var previous: int = station.stock[ware]
		var purchased: Dictionary = api.dispatch("trade",{"ware":ware,"amount":1})
		check(purchased.ok and station.stock[ware] == previous-1, "buying %s withdraws real station inventory" % world.WARES[ware])
		var sold: Dictionary = api.dispatch("trade",{"ware":ware,"amount":-1})
		check(sold.ok and station.stock[ware] == previous, "selling %s returns it to the depot" % world.WARES[ware])
	var stock_before: int = station.stock[Industry.Ware.FUEL]
	var wallet: int = world.active().wallet
	var before: float = vessel.fuel
	var replenished: Dictionary = api.dispatch("refuel",{})
	var units: int = stock_before - station.stock[Industry.Ware.FUEL]
	check(replenished.ok and units > 0 and is_equal_approx(vessel.fuel - before, units) and world.active().wallet == wallet-units,
		"refuel after the deep voyage deducts exactly the tank gain from stock and charges the operator")
	check(api.dispatch("depart",{}).ok and fly_to(game, Celestial.gravity_point(region)), "depart after refuelling and return to the gravity point")
	var inventory: Array = station.stock.duplicate()
	var path := OS.get_temp_dir().path_join("starrail-frontier-%s-%s.save" % [OS.get_process_id(),Time.get_ticks_usec()])
	if not check(Saves.write(world, path, false) and Saves.read(world, path), "persist and reopen the newly explored system"):
		return
	DirAccess.remove_absolute(path)
	game.run_bridge()
	vessel = world.ride()
	check(world.systems[destination].name == region.name and world.systems[destination].planets == region.planets, "reload preserves the discovered identity and local layout")
	count = world.systems.size()
	game.flight.change_layer()
	check(game.galaxy and game.flight.nearby_system(vessel) == destination and world.systems.size() == count, "revisiting mapped space reuses its beacon")
	game.flight.change_layer()
	check(not game.galaxy and vessel.system == destination, "re-enter the same system after reload")
	check(world.systems[destination].ports == [depot] and world.systems[destination].depot_port == depot and world.ports[depot].stock == inventory,
		"reload and actual re-entry keep the same port ID and exactly the real remaining stock")
	check(not Economy.flight_route(world,destination,0,[]).is_empty(), "reloaded frontier relay reconnects to the core trade network")

func run() -> void:
	var game := Game.new()
	game.test_profile = true
	root.add_child(game)
	game.set_physics_process(false)
	var api := Agent.new()
	api.game = game
	check(api.dispatch("new_game", {"seed":"route-outward","systems":12,"factions":3}).ok, "start a normal 12-system campaign")
	game.flight.dock()
	local_flight(game, api)
	hyperspace(game, api)
	game.free()
	print("Open navigation %d/%d" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
