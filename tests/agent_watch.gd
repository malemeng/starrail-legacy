extends SceneTree

const Game = preload("res://game.tscn")
const Bridge = preload("res://agent_bridge.gd")
var checks := 0
var failures := 0
var sequence := 0
var started := []
var finished := []
var progress := []
var pending_marker := true
var cameras := {}
var combat_frames := 0
var game
var bridge := Bridge.new()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)
	return ok

func _initialize() -> void:
	run.call_deferred()

func request(action: String, args: Dictionary = {}) -> Dictionary:
	sequence += 1
	var id := str(sequence)
	bridge.publish("request.json",{"id":id,"action":action,"args":args})
	var response := bridge.directory.path_join("response.json")
	var deadline := Time.get_ticks_msec() + 15000
	while not FileAccess.file_exists(response) and Time.get_ticks_msec() < deadline:
		await physics_frame
	if not check(FileAccess.file_exists(response),"file request completes: "+action):
		return {}
	var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(response))
	DirAccess.remove_absolute(response)
	check(result.id == id,"the eventual reply belongs to its original request")
	return result

func run() -> void:
	game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	var directory := OS.get_temp_dir().path_join("starrail-watch-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_absolute(directory)
	bridge.game = game
	game.agent_bridge = bridge
	check(bridge.start(directory,true) and JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("ready.json"))).watch,"the session advertises watch mode")
	bridge.request_started.connect(func(action,_args): started.append(action))
	bridge.request_finished.connect(func(action,_args,_response): finished.append(action))
	bridge.step_progress.connect(func(done,total):
		progress.append(Vector2i(done,total))
		pending_marker = pending_marker and FileAccess.file_exists(directory.path_join("request.json")) and not FileAccess.file_exists(directory.path_join("response.json")))
	var creation := {"seed":"agent-watch-frames","systems":12,"factions":3}
	var opening := await request("new_game",creation)
	var home: int = opening.state.ship.dock
	var departure := await request("depart")
	var origin: Array = departure.state.ship.pos
	var waypoint := {"kind":"point","pos":[origin[0]+260,origin[1]+80]}
	await request("waypoint",waypoint)
	game.canvas.draw.connect(func():
		if not bridge.active_step.is_empty() and game.canvas.visible:
			cameras[game.canvas.camera] = true
			if game.world.ride().locked and (not game.world.projectiles.is_empty() or not game.canvas.particles.is_empty()):
				combat_frames += 1)
	var input := {"ticks":36,"speed":1,"stop":"arrival"}
	var watch := await request("step",input)
	check(watch.ok and watch.result.ticks == 36 and watch.result.stopped == "tick_limit" and watch.state.speed == 0,"a watched command advances exactly its budget then pauses")
	check(progress.size() == 6 and progress.front() == Vector2i(6,36) and progress.back() == Vector2i(36,36) and pending_marker,"the pending request remains visible to clients through progress updates until its single final reply")
	if DisplayServer.get_name() != "headless":
		check(cameras.size() >= 3,"multiple actual viewport draws follow distinct ship positions before the reply")
	print("Watched 36 ticks, visible drawn camera positions ",cameras.size(),", progress ",progress.size())
	var reference = Game.instantiate()
	reference.test_profile = true
	root.add_child(reference)
	reference.set_physics_process(false)
	reference.hide()
	var batch := Bridge.new()
	batch.game = reference
	reference.agent_bridge = batch
	batch.dispatch("new_game",creation)
	batch.dispatch("depart",{})
	batch.dispatch("waypoint",waypoint)
	var fast := batch.dispatch("step",input)
	check(fast.result.ticks == watch.result.ticks and fast.result.stopped == watch.result.stopped and fast.state.ship.pos == watch.state.ship.pos and fast.state.ship.fuel == watch.state.ship.fuel,"private batch and watched execution reach the same simulation state")
	reference.free()
	var stable: Vector2 = game.world.ride().pos
	for frame in 5:
		await physics_frame
	check(game.world.ride().pos == stable,"waiting for the next action advances no simulation ticks")
	var rest := await request("step",{"ticks":1800,"speed":3,"stop":"arrival"})
	check(rest.result.stopped == "arrival" and rest.result.ticks < 1800 and rest.state.waypoint == null,"arrival stops the outstanding long request at the waypoint")
	await request("waypoint",{"kind":"port","target":home})
	await request("step",{"ticks":1800,"speed":3,"stop":"arrival"})
	var docked := await request("dock")
	check(docked.ok and docked.state.screen == "port" and docked.state.ship.dock == home,"the watched flight returns to the real port interface")
	var invalid := await request("step",{"ticks":0})
	check(not invalid.ok and invalid.error == "invalid_step" and bridge.active_step.is_empty(),"invalid requests return their error without scheduling ticks")
	await check_jump_and_battle()
	check(started == finished and finished.size() == sequence,"each accepted request emits one paired start and finish")
	game.free()
	DirAccess.remove_absolute(directory.path_join("ready.json"))
	DirAccess.remove_absolute(directory)
	print("Agent watched execution ",checks-failures,"/",checks)
	quit(1 if failures else 0)

func check_jump_and_battle() -> void:
	await request("depart")
	await request("waypoint",{"kind":"gravity"})
	await request("step",{"ticks":1800,"speed":5,"stop":"arrival"})
	var jump := await request("jump")
	if not check(jump.ok and jump.state.screen == "hyperspace","departing the gravity point switches the watched view into hyperspace"):
		return
	await request("waypoint",{"kind":"system","target":1})
	var route := await request("step",{"ticks":1800,"speed":5,"stop":"arrival"})
	check(route.result.stopped == "arrival" and route.state.jump_allowed,"the interstellar step stops at the actual destination beacon")
	var entry := await request("jump")
	check(entry.ok and entry.state.screen == "flight" and entry.state.system.id == 1,"entering the destination switches the view back to its local ships")
	var ship: Dictionary = game.world.ride()
	var hostile: int = game.world.ship(game.world.Hulls.kind_for_reference("kite"),0,0,game.world.RAIDERS,ship.system,ship.pos+Vector2(150,0))
	ship.heading = 0.0
	var encounter := await request("step",{"ticks":120,"stop":"encounter"})
	check(encounter.result.stopped == "encounter" and encounter.result.ticks < 120,"the same stop condition interrupts a watched step on a real hostile contact")
	var before: int = game.world.combat_serial
	var firing := await request("step",{"ticks":60,"target":hostile,"fire":true,"shield":true,"stop":"never"})
	check(firing.ok and game.world.combat_serial > before,"targeted fire processes real combat events in the watched simulation")
	if DisplayServer.get_name() != "headless":
		check(combat_frames >= 2,"live projectile or combat effects are drawn across multiple frames")
		print("Watched combat frames with effects ",combat_frames)
