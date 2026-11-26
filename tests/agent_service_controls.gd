extends SceneTree

const Game = preload("res://game.tscn")
const Bridge = preload("res://agent_bridge.gd")
const Mobile = preload("res://scripts/services/mobile_model_agent.gd")

var game
var bridge := Bridge.new()
var mobile := Mobile.new()
var checks := 0
var failures := 0
var sequence := 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
	return ok

func action(command: String, args: Dictionary = {}) -> Dictionary:
	sequence += 1
	var tool := "observe" if command == "observe" else "game_action"
	var params := {} if tool == "observe" else {"action":command, "args_json":JSON.stringify(args)}
	mobile.run_tool({"id":str(sequence),"function":{"name":tool,"arguments":JSON.stringify(params)}})
	if not mobile.request_id.is_empty():
		bridge.poll(1.0)
		mobile.read_receipt()
	return JSON.parse_string(mobile.turn.back().content)

func click(window: Window, target: Button) -> void:
	await process_frame
	await process_frame
	var p := target.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = p
	window.push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = p
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		window.push_input(event,true)
	await process_frame

func find_button(node: Node, text: String) -> Button:
	for b: Button in node.find_children("*","Button",true,false):
		if b.is_visible_in_tree() and b.text == text:
			return b
	return null

func run() -> void:
	game = Game.instantiate()
	game.test_profile = true
	game.mobile_play = true
	root.add_child(game)
	game.set_physics_process(false)
	var world = game.world
	world.new_game({"seed":"agent-second-check","systems":12,"factions":3})
	game.run_bridge()
	await process_frame
	var money := int(world.active().wallet)
	var open := find_button(game,"作弊")
	if check(open != null, "player has a clickable console entry"):
		await click(root, open)
		var dialogs: Array[Node] = game.find_children("*","AcceptDialog",true,false)
		if check(not dialogs.is_empty(), "pointer opens the player console"):
			var dialog: AcceptDialog = dialogs.back()
			var cash := find_button(dialog,"+10万信用点")
			if check(cash != null, "quick money command is reachable"):
				cash.pressed.emit()
				await process_frame
				check(world.active().wallet == money + 100000,"quick cheat credits actual player without an Agent")
			dialog.hide()
			dialog.queue_free()
			await process_frame
	bridge.game = game
	var temp := OS.get_temp_dir().path_join("starrail-service-controls-%s-%s" % [OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(temp)
	bridge.start(temp,true)
	game.agent_bridge = bridge
	game.agent_overlay = CanvasLayer.new()
	game.add_child(game.agent_overlay)
	bridge.attach_watch(game.agent_overlay)
	game.add_child(mobile)
	mobile.start(bridge, {"api_base":"http://127.0.0.1:1","model":"local-test"})
	mobile.set_process(false)
	await process_frame
	# Exercise the overlay over a visible flight canvas, where watch-drag used to consume the click.
	game.flight.dock()
	game.refresh()
	await process_frame
	var toggle: CheckButton = bridge.watch_log.panel.cheat_toggle
	check(game.canvas.visible and game.canvas.get_global_rect().has_point(toggle.get_global_rect().get_center()),"toggle overlaps the flight canvas")
	check(not action("cheat",{"kind":"credits"}).ok,"model cheat starts disabled")
	await click(root,toggle)
	var before := int(world.active().wallet)
	check(bridge.allow_cheats and toggle.button_pressed and "cheat" in mobile.allowed_actions(), "click enables the tool without starting a camera drag")
	check(action("cheat",{"kind":"credits","amount":111}).ok and world.active().wallet == before + 111 and not game.watch_drag,"enabled model cheat actually credits the account")
	await click(root,toggle)
	check(not bridge.allow_cheats and "cheat" not in mobile.allowed_actions() and not action("cheat",{"kind":"credits"}).ok and not bridge.dispatch("cheat",{"kind":"credits"}).ok and world.active().wallet == before + 111,"second click revokes advertised tool and execution")

	world.new_game({"seed":"agent-second-check","systems":12,"factions":3})
	game.run_bridge()
	var start := action("observe")
	var flagship := int(start.state.ship.id)
	check(action("disembark").ok and world.active().ship == 0, "mobile captain leaves the flagship")
	var st: Dictionary = action("observe").state
	check(st.contacts.size() > 0 and st.fleet.any(func(s): return int(s.id) == flagship),"on-foot observation retains crew and fleet")
	var liner: Dictionary = st.passenger_liners.front()
	var stop: Dictionary = liner.stops.front()
	var booking := {"ship":liner.ship,"dest":stop.port,"fare":stop.fare}
	var boarded := action("board_liner", booking)
	check(boarded.ok and boarded.result.fare == stop.fare and boarded.state.screen == "passenger" and boarded.state.passenger_trip.dest == stop.port, "quoted fare and journey go through mobile tool dispatch")
	check(stop.name in bridge.watch_log.state.result and "¢" in bridge.watch_log.state.result,"spectator sees actual destination and ticket price")
	check(action("disembark_liner").ok and int(world.active().loc) == int(st.actor.port),"mobile passenger can leave during a stop")
	action("board_liner",booking)
	var arrival := action("wait",{"days":180})
	check(arrival.result.stopped == "disembarked" and arrival.state.actor.port == stop.port and not arrival.state.has("passenger_trip"),"wait stops at the actual destination")

	world.new_game({"seed":"station-dispatch","systems":12,"factions":3,"avatar":{"station_master":1}})
	game.run_bridge()
	st = action("observe").state
	var station_ship: Dictionary = st.fleet.filter(func(s): return s.station_owner == st.actor.port and s.job.kind == "站属贸易").front()
	check(action("debug_ship",{"ship":station_ship.id}).ok and game.tab == "资产","Agent can inspect the starting station's freighter")
	check(action("assign_passenger_liner",{"ship":station_ship.id}).ok and world.ships[int(station_ship.id)].job.kind == "客运","station manager can dispatch the actual starter")
	check("→" in bridge.watch_log.state.result and bridge.watch_log.state.action == "开通客运班线","watch shows the assigned route")
	var home: Dictionary = world.ports[int(st.actor.port)]
	var engineer: int = world.ship(world.Hulls.kind_for_id("gantry_ca"),0,0,home.flag,home.system,home.pos,home.id)
	world.ships[engineer].station_owner = home.id
	var treasury := int(home.treasury)
	check(action("hire_captain",{"ship":engineer}).ok and int(home.treasury) == treasury - 85,"station pays for its own engineering captain")
	check(action("assign_contractor",{"ship":engineer}).ok and world.ships[engineer].job.kind == "工程承包" and home.name in bridge.watch_log.state.result,"engineer dispatch has a visible home port")
	var stranger: int = world.random_person(world.NEUTRAL,home.id)
	bridge.bound_actor_id = stranger
	check(not action("assign_contractor",{"ship":engineer}).ok and not action("assign_passenger_liner",{"ship":station_ship.id}).ok,"another arena actor cannot commandeer station ships")
	mobile.stop()
	game.agent_bridge = null
	game.free()
	print("Agent service controls ", checks - failures, "/", checks)
	quit(1 if failures else 0)

func _initialize() -> void:
	run.call_deferred()
