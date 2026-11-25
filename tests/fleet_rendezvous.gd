extends SceneTree

const Game = preload("res://game.tscn")
const World = preload("res://world.gd")
var checks := 0
var failures := 0

func check(condition: bool, msg: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ",msg)

func ship_at(world, where: Vector2) -> Dictionary:
	var crew: int = world.random_person(world.NEUTRAL,0)
	return world.ships[world.ship(0,world.player,crew,world.NEUTRAL,world.ride().system,where)]

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	var world = game.world
	world.new_game({"seed":"fleet-rendezvous","systems":12,"factions":3})
	game.run_bridge()
	game.set_physics_process(false)
	var lead: Dictionary = world.ride()
	var port: int = lead.dock
	world.depart(lead)
	lead.pos = Vector2(8700,4300)
	lead.fuel = 20.0
	var escort := ship_at(world,lead.pos+Vector2(1600,40))
	var close := ship_at(world,lead.pos+Vector2(0,440))
	var tender := ship_at(world,lead.pos+Vector2(0,920))
	var second := ship_at(world,lead.pos+Vector2(0,1600))
	second.fuel = 20.0
	var delivery := ship_at(world,second.pos+Vector2(44,0))
	var fuel: int = world.Industry.Ware.FUEL
	tender.cargo[fuel] = 11
	delivery.cargo[fuel] = 7
	check(world.Economy.queue_order(world,escort.id,port,"escort_to") and world.Economy.queue_order(world,close.id,port,"escort_to"),"two real escort commands are accepted")
	check(world.Economy.assign_role(world,tender.id,lead.id,"SUPPLY") and world.Economy.assign_role(world,delivery.id,second.id,"SUPPLY"),"two tenders are assigned through fleet roles")
	var background := World.new()
	check(background.load_state(world.snapshot()),"copy the same campaign before comparing foreground and background movement")
	var start_escort: Vector2 = escort.pos
	var start_tender: Vector2 = tender.pos
	var step_escort: float = float(world.Industry.RULES.fleet_rendezvous.escort_units_per_day)*game.flight.FLIGHT_DAYS_PER_SECOND/60.0
	var step_tender: float = float(world.Industry.RULES.fleet_rendezvous.supply_units_per_day)*game.flight.FLIGHT_DAYS_PER_SECOND/60.0
	var escort_frames := 0
	var supply_frames := 0
	var close_frames := 0
	game.speed = 1
	var frames_per_day: int = roundi(60.0/game.flight.FLIGHT_DAYS_PER_SECOND)
	var frames := 6*frames_per_day
	for frame in frames:
		var old_escort: Vector2 = escort.pos
		var old_tender: Vector2 = tender.pos
		var old_close: Vector2 = close.pos
		game.step_simulation(Vector2.ZERO,false,false,Vector2.ZERO,false)
		escort_frames += int(absf(escort.pos.distance_to(old_escort)-step_escort)<0.03)
		supply_frames += int(absf(tender.pos.distance_to(old_tender)-step_tender)<0.03)
		close_frames += int(game.flight.tactical_escorts.has(close.id) and absf(close.pos.distance_to(old_close)-Vector2(close.battle.motion).length()/60.0)<0.04)
		if frame==5*frames_per_day-1:
			var gap: float = delivery.pos.distance_to(second.pos)
			var reach := 2.0*float(world.Economy.Defenses.geometry(second.kind).module_radius)+4.0
			check(gap > 0.01 and gap <= reach + 0.01 and delivery.cargo[fuel]==7 and is_equal_approx(second.fuel,20.0),"tender can wait alongside without overlapping or transferring before the sixth day")
	check(world.day==6 and escort_frames==frames and supply_frames==frames,"all frames use the configured speeds including the sixth day")
	check(close_frames==frames,"a nearby escort receives exactly its physical steering displacement without any strategic pulse")
	check(delivery.cargo[fuel]==0 and is_equal_approx(second.fuel,27.0),"normal duty dispatch transfers exactly seven fuel after real rendezvous")
	background.tick(6)
	check(escort.pos.distance_to(background.ships[escort.id].pos)<0.1 and tender.pos.distance_to(background.ships[tender.id].pos)<0.1 and absf(escort.pos.distance_to(start_escort)-180.0)<0.1 and absf(tender.pos.distance_to(start_tender)-240.0)<0.1,"off-screen and visible service cover identical six-day distances")
	escort.pos = lead.pos+Vector2(621,0)
	for i in ceili(3.0/step_escort)+1:
		game.step_simulation(Vector2.ZERO,false,false,Vector2.ZERO,false)
	check(game.flight.tactical_escorts.has(escort.id) and escort.order_queue.size()==1,"the same distant escort rejoins the tactical formation while retaining its order")
	check(world.berth(lead,port),"flagship reaches the escorted destination")
	world.Economy.step_ship(world,escort,0.0)
	check(escort.travel.get("port",0)==port,"escort resumes the physical docking route when the commander reaches port")
	print("Fleet rendezvous %d/%d. Across %d frames: far escort %d, tender %d, tactical escort %d." % [checks-failures,checks,frames,escort_frames,supply_frames,close_frames])
	game.free()
	quit(1 if failures else 0)
