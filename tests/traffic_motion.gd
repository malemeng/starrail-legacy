extends SceneTree

const Game = preload("res://game.tscn")
var checks := 0
var failures := 0

func check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	var world = game.world
	world.new_game({"seed":"nearby-shipping","systems":12,"factions":3})
	game.run_bridge()
	game.set_physics_process(false)
	var lead: Dictionary = world.ride()
	world.depart(lead)
	var start: Vector2 = lead.pos + Vector2(-220,35)
	var port: int = world.port(lead.system,"航线终点",start + Vector2(3500,0),world.NEUTRAL,0,0)
	var captain: int = world.random_person(world.NEUTRAL,0)
	var freighter: Dictionary = world.ships[world.ship(0,captain,captain,world.NEUTRAL,lead.system,start)]
	freighter.travel = {"port":port,"waypoints":[]}
	freighter.transponder = true
	var job: int = world.random_person(world.NEUTRAL,0)
	var patrol: Dictionary = world.ships[world.ship(0,job,job,world.NEUTRAL,lead.system,start+Vector2(0,75))]
	patrol.job = {"kind":"巡逻","source":port,"outbound":true}
	var original_patrol: Vector2 = patrol.pos
	var patrol_target: Vector2 = world.systems[lead.system].field
	var hidden_start: Vector2 = world.systems[1].field + Vector2(1900,0)
	var distant_captain: int = world.random_person(world.NEUTRAL,0)
	var distant: Dictionary = world.ships[world.ship(0,distant_captain,distant_captain,world.NEUTRAL,1,hidden_start)]
	distant.travel = {"port":world.systems[1].ports[0],"waypoints":[],"activity":"mine"}
	game.speed = 1
	game.canvas.camera = lead.pos
	var expected: float = world.Economy.LOCAL_DISTANCE_PER_DAY * clampf(world.Hulls.MODELS[freighter.kind].speed,0.45,1.4) * game.flight.FLIGHT_DAYS_PER_SECOND/60.0
	var changed := 0
	var visible_changes := 0
	var max_step := 0.0
	var min_step := INF
	var previous_view := start
	var rendered_run := "--render-traffic" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	for frame in 60:
		var before: Vector2 = freighter.pos
		game.step_simulation(Vector2.ZERO,false,false,Vector2.ZERO,false)
		var displacement: float = before.distance_to(freighter.pos)
		changed += int(displacement > 0.01)
		max_step = maxf(max_step,displacement)
		min_step = minf(min_step,displacement)
		if rendered_run:
			await physics_frame
			game.update_bridge(1.0/60.0)
			await RenderingServer.frame_post_draw
		else:
			game.canvas.sync_battlefield(lead.system)
		var visual = game.canvas.visuals.get(freighter.id)
		if is_instance_valid(visual):
			var rendered: Vector2 = visual.last_pose.origin
			visible_changes += int(rendered.distance_to(previous_view) > 0.01 and rendered.is_equal_approx(freighter.pos))
			previous_view = rendered
		if frame == 5:
			check(distant.pos == hidden_start,"distant freight stays on the daily simulation")
	check(changed == 60 and visible_changes == 60,"the actual hull changes position on every one of sixty consecutive physics frames")
	check(absf(min_step-expected)<0.06 and absf(max_step-expected)<0.06 and world.day == 4,"day boundaries preserve route speed without a second movement pulse")
	check(patrol.pos.distance_to(original_patrol.move_toward(patrol_target,160.0))<0.1,"civil patrol follows the correct per-day speed")
	check(distant.pos.distance_to(hidden_start.move_toward(world.systems[1].field,expected*60))<0.2,"distant and visible routes cover the same distance after four days")
	game.speed = 0
	var frozen: Vector2 = freighter.pos
	game.step_simulation(Vector2.ZERO,false,false,Vector2.ZERO,false)
	check(freighter.pos == frozen,"pausing freezes the visible ship")
	game.speed = 1
	var destination: Dictionary = world.ports[port]
	destination.pos = frozen + Vector2(3,0)
	game.step_simulation(Vector2.ZERO,false,false,Vector2.ZERO,false)
	check(freighter.dock == port and freighter.travel.is_empty(),"a short final step docks the real ship at the actual destination")
	game.galaxy = true
	lead.layer = true
	var tanker: Dictionary = distant
	var next := 2
	tanker.layer = true
	tanker.galpos = world.systems[1].pos
	tanker.fuel = 90.0
	tanker.travel = {"port":world.systems[next].ports[0],"waypoints":[next]}
	var hyper_count := 0
	var hyper_origin: Vector2 = tanker.galpos
	for frame in 60:
		var before: Vector2 = tanker.galpos
		game.step_simulation(Vector2.ZERO,false,false,Vector2.ZERO,false)
		hyper_count += int(before.distance_to(tanker.galpos)>0.001)
	var burned: float = world.Economy.Hyperspace.fuel_for_distance(world.Hulls.MODELS[tanker.kind],hyper_origin.distance_to(tanker.galpos))
	check(hyper_count == 60 and absf(90.0-tanker.fuel-burned)<0.002,"hyperspace traffic moves every tick and pays fuel for exactly the distance flown")
	print("Traffic motion %d/%d. Moving hull frames %d/60, model %d/60, min/max %.3f/%.3f units; hyperspace %d/60." % [checks-failures,checks,visible_changes,changed,min_step,max_step,hyper_count])
	game.free()
	quit(1 if failures else 0)
