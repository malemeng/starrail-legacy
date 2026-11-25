extends RefCounted

const Battle = preload("res://combat.gd")
const Hulls = preload("res://hull_catalog.gd")
const Economy = preload("res://economy.gd")
const InputController = preload("res://scripts/services/input_controller.gd")
const SHIPS := 40
const SHOTS := 300
const WARMUP := 35
const DEFAULT_SAMPLES := 120
var min_simulated_shots := 2147483647
var min_visible_shots := 2147483647
var tick_timings: Array[float] = []
var wide := false

func replenish(game, ships: Array, system_id: int, rng: RandomNumberGenerator) -> void:
	var world = game.world
	var bounds := Rect2(game.canvas.location(Vector2.ZERO),Vector2(game.canvas.size) / float(game.canvas.zoom)).grow(-8.0)
	var visible := 0
	for shot in world.projectiles:
		if shot.system == system_id and bounds.has_point(shot.pos):
			visible += 1
	for i in maxi(0,SHOTS-visible):
		var shooter: Dictionary = ships[rng.randi_range(0, SHIPS - 1)]
		var position: Vector2 = shooter.pos + Vector2(rng.randf_range(-16,16), rng.randf_range(-10,10))
		if not bounds.has_point(position):
			position = position.clamp(bounds.position + Vector2.ONE,bounds.end - Vector2.ONE)
		var velocity := Vector2.from_angle(rng.randf_range(-PI, PI)) * 430.0
		world.projectiles.append({"ship":shooter.id,"system":system_id,"pos":position,"vel":velocity,"speed":430.0,
			"life":1.0,"damage":0.05,"type":0,"flag":shooter.flag,"raid":shooter.raid,"credit":0,"hp":10.0,"missile":false})
		visible += 1
	min_visible_shots = mini(min_visible_shots, visible)

func advance(game, ships: Array, system_id: int, rng: RandomNumberGenerator, full_tick: bool) -> void:
	var world = game.world
	var flagship: Dictionary = ships[0]
	if flagship.ping < 0.2:
		flagship.ping = 3.5
	min_simulated_shots = mini(min_simulated_shots, world.projectiles.size())
	var before := Time.get_ticks_usec()
	if full_tick:
		game.step_simulation(Vector2.ZERO,false,false,Vector2.RIGHT * 140.0,true)
		game.update_bridge(1.0/60.0)
	else:
		game.flight.combat(flagship,1.0/60.0)
	tick_timings.append((Time.get_ticks_usec() - before) / 1000.0)
	# Frame the ships' hulls with the same magnification limits as the flight controls.
	var formation := Rect2(flagship.pos,Vector2.ZERO)
	for ship in ships:
		var radius := float(Battle.Defenses.geometry(ship.kind).reach)
		var half_size := Vector2.ONE * radius
		formation = formation.merge(Rect2(ship.pos - half_size, 2.0 * half_size))
	game.canvas.camera = formation.get_center()
	if wide:
		var framed := formation.grow(24.0).size
		var fit := minf(game.canvas.size.x / framed.x,game.canvas.size.y / framed.y)
		while game.flight_zoom > fit and game.flight_zoom > InputController.MIN_FLIGHT_ZOOM:
			game.flight_zoom = maxf(InputController.MIN_FLIGHT_ZOOM,game.flight_zoom / 1.2)
		game.canvas.zoom = game.flight_zoom
	replenish(game, ships, system_id, rng)
	game.canvas.queue_redraw()

func run(game) -> void:
	var tree: SceneTree = game.get_tree()
	var root := tree.root
	var args := OS.get_cmdline_user_args()
	var samples := DEFAULT_SAMPLES
	for argument in args:
		if argument.begins_with("--samples="):
			var value := argument.trim_prefix("--samples=")
			if not value.is_valid_int() or int(value) < 60 or int(value) > 36000:
				push_error("--samples requires an integer between 60 and 36000")
				tree.quit(2)
				return
			samples = int(value)
	var realtime := "--realtime" in args
	var full_tick := realtime or "--full-tick" in args or "--battle-benchmark" in args
	var strict := "--require-60" in args
	root.size = Vector2i(1440, 900)
	await tree.process_frame
	game.creator.name.text = "验收船长"
	game.creator.seed.text = "fleet-stress-40"
	game.start_game()
	game.set_physics_process(false)
	var world = game.world
	var flagship: Dictionary = world.ride()
	world.before_death = Callable()
	game.flight.dock()
	var system_id: int = flagship.system
	for id in world.ships.keys():
		if id != flagship.id:
			world.ships.erase(id)
	flagship.pos = Vector2.ZERO
	flagship.heading = 0.0
	flagship.hp = 100000.0
	var ships: Array = [flagship]
	var with_roles := "--fleet-roles" in args
	var roles := ["ATTACK","INTERCEPT","BOMBARD","DEFEND"]
	var role_counts := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	for index in range(1, SHIPS):
		var side: int = world.RAIDERS if index % 2 else flagship.flag
		var position := Vector2(-245 + (index % 8) * 69, -155 + floori(index / 8.0) * 70)
		var owner: int = world.player if with_roles and side == flagship.flag else 0
		var captain: int = world.random_person(side,0) if owner != 0 else 0
		var id: int = world.ship(index % Hulls.MODELS.size(),owner,captain,side,system_id,position)
		var ship: Dictionary = world.ships[id]
		ship.hp = 100000.0
		ship.heading = PI if index % 2 else 0.0
		ship.locked = true
		if side == flagship.flag:
			if with_roles:
				var role: String = roles[(index / 2 - 1) % roles.size()]
				if not Economy.assign_role(world,id,flagship.id,role):
					push_error("Fleet role assignment failed for ship %d" % id)
					tree.quit(2)
					return
				role_counts[ship.fleet_role] = int(role_counts.get(ship.fleet_role,0)) + 1
			else:
				ship.commander_id = flagship.id
		ships.append(ship)
	if with_roles:
		print("FLEET_ROLES ",JSON.stringify(role_counts))
	game.canvas.camera = Vector2.ZERO
	wide = "--wide" in args
	game.flight_zoom = 0.96
	game.canvas.zoom = game.flight_zoom
	game.set_speed(1)
	flagship.ping = 3.5
	game.flight.sensor_reading.clear()
	await tree.process_frame
	var frame_times: Array[float] = []
	var draw_counts: Array[int] = []
	var min_visible := 2147483647
	var furthest_center := Vector2.ZERO
	var min_contacts := 2147483647
	var min_drawn_shots := 2147483647
	var ticks_at_start := 0
	var sample_start := 0
	var last_present := 0
	replenish(game, ships, system_id, rng)
	var tick := advance.bind(game,ships,system_id,rng,full_tick)
	if realtime:
		tree.physics_frame.connect(tick)
	for frame in range(WARMUP + samples):
		var frame_start := Time.get_ticks_usec()
		if frame == WARMUP:
			sample_start = frame_start
			last_present = sample_start
			ticks_at_start = game.flight.physics_frame
			tick_timings.clear()
		if not realtime:
			tick.call()
		await tree.process_frame
		if frame >= WARMUP:
			var present := Time.get_ticks_usec()
			frame_times.append((present - last_present) / 1000.0)
			last_present = present
			draw_counts.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			var drawn := 0
			var bounds := Rect2(Vector2.ZERO, game.canvas.size)
			for visual in game.canvas.visuals.values():
				var center: Vector2 = game.canvas.screen(visual.ship.pos)
				furthest_center = furthest_center.max((center - bounds.get_center()).abs() / (bounds.size * 0.5))
				if bounds.has_point(center):
					drawn += 1
			min_visible = mini(min_visible, drawn if game.canvas.battlefield.is_visible_in_tree() else 0)
			min_contacts = mini(min_contacts,game.canvas.contacts.size())
			min_drawn_shots = mini(min_drawn_shots, game.canvas.fleet_batch.projectile_count)
	var elapsed := (Time.get_ticks_usec() - sample_start) / 1000000.0
	if realtime:
		tree.physics_frame.disconnect(tick)
	tick_timings.sort()
	frame_times.sort()
	draw_counts.sort()
	var headless := DisplayServer.get_name() == "headless"
	var fps := float(samples) / maxf(0.001, elapsed)
	var pick := ceili(samples * 0.95) - 1
	var combat_ticks: int = game.flight.physics_frame-ticks_at_start
	var physics_hz := combat_ticks / elapsed
	var full_workload := absf(physics_hz - 60.0) < 2.0 if realtime else combat_ticks == samples
	print("BATTLE_STRESS ", JSON.stringify({"display":DisplayServer.get_name(),"adapter":RenderingServer.get_video_adapter_name(),
		"simulated_day":world.day,"game_speed":game.speed,"attention":world.attention,
		"ships":ships.size(),"ships_on_screen_min":min_visible,"contacts_min":min_contacts,"furthest_xy_fraction":str(furthest_center),"simulated_projectiles_min":min_simulated_shots,
		"drawn_projectiles_min":min_drawn_shots,"projectiles_in_view_min":min_visible_shots,"resolution":str(root.size),"camera_zoom":game.canvas.zoom,"samples":samples,"full_game_tick":full_tick,
		"native_collision":Battle.collision_engine != null,"native_strokes":game.canvas.fleet_batch.native != null,
		"combat_ticks":combat_ticks,"realtime":realtime,"physics_ticks_per_second":physics_hz,"frame_p95_ms":frame_times[pick],
		"frame_median_ms":frame_times[samples/2],"frame_p99_ms":frame_times[ceili(samples*0.99)-1],"frame_max_ms":frame_times[-1],
		"physics_p95_ms":tick_timings[ceili(tick_timings.size()*0.95)-1],"physics_max_ms":tick_timings[-1],"frame_rate":0.0 if headless else fps,
		"draw_calls_p95":draw_counts[pick],"draw_calls_max":draw_counts[-1],"render_measured":not headless}))
	if "--capture" in args and not headless:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_temp_dir().path_join("starrail-battle-40.png"))
	var passed: bool = not headless and fps >= 60.0 and min_visible >= SHIPS and min_drawn_shots >= SHOTS and min_visible_shots >= SHOTS and min_simulated_shots >= SHOTS and draw_counts[-1] <= 180 and full_workload
	if "--profile-stages" in args:
		var slots := [0,0,0,0,0]
		for pass_index in range(10):
			var native_scan := Battle.fire_control != null
			var m: Array = Battle.fire_control.begin_frame(world.projectiles,system_id) if native_scan else world.projectiles.filter(func(p): return p.missile and p.system == system_id and p.hp > 0)
			var carriers: Array = ships.filter(func(s): return s.system == system_id and not s.battle.get("fighter_wings", []).is_empty())
			var start := Time.get_ticks_usec()
			for ship in ships:
				Battle.tick(ship,1.0/60.0)
			slots[0] += Time.get_ticks_usec()-start
			start = Time.get_ticks_usec()
			game.flight.scanning_threats = native_scan
			for ship in ships:
				if ship.id != flagship.id:
					game.flight.drive_ai(ship,flagship,1.0/60.0,m,carriers)
			game.flight.scanning_threats = false
			slots[1] += Time.get_ticks_usec()-start
			start = Time.get_ticks_usec()
			for ship in ships:
				var protect: Dictionary = flagship if ship.get("fleet_role","") == "INTERCEPT" and game.flight.escort(ship,flagship) and ship.battle.order != 3 else {}
				Battle.point_defense(world,ship,m,carriers,protect)
			slots[2] += Time.get_ticks_usec()-start
			start = Time.get_ticks_usec()
			for ship in ships:
				if Hulls.MODELS[ship.kind].fighter_bays > 0:
					var foe: Dictionary = world.ships.get(ship.battle.get("target_id",0),{}) if ship.locked else {}
					Battle.Wings.advance(world,ship,foe,1.0/60.0,Battle,m,carriers)
			slots[3] += Time.get_ticks_usec()-start
			var snapshot: Array = world.projectiles.duplicate(true)
			start = Time.get_ticks_usec()
			Battle.project(world,system_id,1.0/60.0)
			slots[4] += Time.get_ticks_usec()-start
			world.projectiles = snapshot
		print("BATTLE_STAGES_US_10X tick ai pd wings project ",slots)
		if not headless:
			var stages := [0,0]
			for i in 10:
				var start := Time.get_ticks_usec()
				game.canvas.sync_battlefield(system_id)
				stages[0] += Time.get_ticks_usec() - start
				start = Time.get_ticks_usec()
				game.canvas.fleet_batch.sync(game.canvas.visuals,world.projectiles,game.canvas.particles,system_id,game.canvas.visible_wings)
				stages[1] += Time.get_ticks_usec() - start
			print("RENDER_STAGES_US_10X view_including_strokes strokes ",stages)
			game.canvas.set_process(false)
			game.canvas.battlefield.hide()
			await tree.process_frame
			await tree.process_frame
			var without_ships := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			game.canvas.hud.hide()
			await tree.process_frame
			await tree.process_frame
			var without_hud := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			game.canvas.hide()
			await tree.process_frame
			await tree.process_frame
			print("BATTLE_DRAWS without_ships without_hud other_ui ",[without_ships, without_hud, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	game.queue_free()
	await tree.process_frame
	tree.quit(1 if strict and not passed else 0)
