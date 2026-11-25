extends SceneTree

const Scene = preload("res://game.tscn")
const Bridge = preload("res://agent_bridge.gd")
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		printerr("FAIL ",label)
		failures += 1

func _initialize(): run.call_deferred()

func run():
	var game = Scene.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.show_title()
	var demo = game.get_node("TitleMenu").battle
	demo.set_physics_process(false)
	var ship: Dictionary = demo.world.ships.values()[0]
	demo.world.destruction(ship.id)
	check(demo.remains.live.size() == 1 and not demo.world.ships.has(ship.id),"lethal damage leaves an untargetable broken hull")
	demo._physics_process(1.0/60)
	demo.remains.advance(3.5)
	check(demo.remains.live.is_empty() and demo.remains.printed == 1,"cold menu hulls leave the animated list")
	demo.elapsed += 3.0
	demo._physics_process(1.0/60)
	check(demo.world.ships.size() == 6 and demo.remains.printed == 1,"reinforcing an empty slot preserves its corpse")
	demo.start_round()
	check(demo.remains.printed == 0 and demo.remains.live.is_empty(),"changing the exhibition clears the previous battlefield")
	var bridge := Bridge.new()
	bridge.game = game
	check(bridge.dispatch("new_game",{"seed":"persistent-derelict"}).ok,"start a campaign")
	var world = game.world
	var lead: Dictionary = world.ride()
	game.flight.dock()
	game.galaxy = false
	var canvas = game.canvas
	canvas.show()
	canvas.galaxy = false
	lead.pos = Vector2(370,470)
	canvas.camera = lead.pos
	var id: int = world.ship(4,0,0,lead.flag,lead.system,lead.pos+Vector2(45,15))
	var fallen: Dictionary = world.ships[id]
	fallen.heading = 0.74
	canvas.sync_battlefield(lead.system)
	check(canvas.visuals.has(id),"doomed ship is actually visible in campaign")
	var wid: int = world.next_id
	world.destruction(id)
	var corpse: Dictionary = world.wrecks[wid]
	check(corpse.hull_id == world.Hulls.hull_id(4) and corpse.source_id == id and corpse.pos == fallen.pos and corpse.heading == fallen.heading,"wreck stores original hull, identity, pose and stock")
	check(canvas.burning_wrecks.has(wid) and corpse.stock.max() > 0,"campaign draws a new hot wreck with salvage")
	for i in 13:
		world.ship(0,0,0,lead.flag,lead.system,lead.pos+Vector2(15*i,60))
	canvas.sync_battlefield(lead.system)
	check(canvas.crowded and canvas.wreck_views.has(wid),"crowded fleet mode keeps the wreck visible")
	corpse.stock.fill(0)
	corpse.stock[0] = 1
	lead.cargo.fill(0)
	lead.locked = false
	game.flight.salvage()
	check(world.wrecks.has(wid) and corpse.stock.max() == 0 and lead.cargo[0] == 1,"taking the last cargo leaves the hull behind")
	var fresh := preload("res://world.gd").new()
	check(fresh.load_state(world.snapshot()) and fresh.wrecks[wid] == corpse,"wreck identity and stripped state survive save round trip")
	canvas.clear_wrecks()
	canvas.sync_battlefield(lead.system)
	check(canvas.wreck_views.has(wid) and not canvas.burning_wrecks.has(wid),"revisiting the battlefield shows a cold hull")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
	game.free()
	print("Shipwrecks ",checks-failures,"/",checks)
	quit(1 if failures else 0)
