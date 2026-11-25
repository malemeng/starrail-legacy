extends SceneTree

const Game = preload("res://game.tscn")
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.show_title()
	var title = game.get_node("TitleMenu")
	var demo = title.battle
	demo.set_physics_process(false)
	check(not game.playing and demo.world != game.world and game.world.ships.is_empty(),"the opening is independent of the campaign")
	var initial: Vector2 = demo.world.ships.values()[0].pos
	var framing: Transform2D = demo.space.transform
	for i in 180: demo._physics_process(1.0/60.0)
	check(demo.world.combat_serial > 0 and demo.world.combat_events.any(func(e): return e.kind in ["muzzle","beam","impact","shield"]),"the demonstration simulates live combat")
	check(initial != demo.world.ships.values()[0].pos and game.world.ships.is_empty(),"autonomous maneuvering leaves the campaign untouched")
	check(demo.space.transform == framing,"engagements do not move or zoom the opening camera")
	var vessel: Dictionary = demo.world.ships.values()[0]
	var limit: Vector2 = demo.world.movement_limit(vessel.kind)
	# Start a fast outward move close to each wall, keeping the tangential speed.
	for axis in 2:
		for side in [-1.0,1.0]:
			vessel.pos = Vector2.ZERO
			vessel.pos[axis] = side*(limit[axis]-0.1)
			vessel.battle.motion = Vector2(45.0,45.0)
			vessel.battle.motion[axis] = side*1500.0
			var outward := Vector2.ZERO
			outward[axis] = side
			demo.flight.maneuver(vessel,outward,1.0/60.0,outward.angle())
			check(absf(vessel.pos[axis]) <= limit[axis] and vessel.battle.motion[axis] == 0.0 and vessel.battle.motion[1-axis] > 0,"wall stops outward motion while allowing sliding")
			check(vessel.battle.ai_thrust[axis]*side < 0,"edge steering points back into the arena")
	vessel.pos = Vector2(2000,-1800)
	vessel.battle.motion = Vector2(-30,50)
	demo._physics_process(1.0/60.0)
	check(Vector2(vessel.pos).is_equal_approx(Vector2(vessel.pos).clamp(-limit,limit)),"a displaced hull is back inside before rendering")
	var first_hulls: Array = demo.previous_hulls.duplicate()
	var shuffle: Button
	for item: Button in title.find_children("*","Button",true,false):
		if item.text == "换一场": shuffle = item
	shuffle.pressed.emit()
	check(demo.round_number == 2 and demo.world.ships.size() == 6,"changing the broadcast starts a new battle")
	check(demo.previous_hulls.all(func(id): return id not in first_hulls),"consecutive encounters do not reuse hull silhouettes")
	var fallen: Dictionary = demo.world.ships.values()[0]
	var survivor: int = demo.world.ships.keys()[3]
	var loss_slot: int = fallen.demo_slot
	demo.world.destruction(fallen.id)
	demo._physics_process(1.0/60.0)
	check(demo.world.ships.size() == 5 and demo.reserves.size() == 1,"loss schedules one reinforcement")
	demo.elapsed += 3.0
	demo._physics_process(1.0/60.0)
	var relief: Array = demo.world.ships.values().filter(func(s): return s.demo_slot == loss_slot)
	check(relief.size() == 1 and relief[0].flag == fallen.flag and demo.base_hull(relief[0].kind) != demo.base_hull(fallen.kind) and demo.world.ships.has(survivor) and demo.round_number == 2,"a different hull reinforces the same side while surviving ships stay in battle")
	if relief.size() == 1:
		var entry_limit: Vector2 = demo.world.movement_limit(relief[0].kind)
		var entry: Vector2 = relief[0].pos
		check(entry == entry.clamp(-entry_limit,entry_limit) and entry.x < 0,"reinforcement enters inside its own edge")
	for button: Button in title.choices.get_children():
		if button.text == "新航程":
			button.pressed.emit()
			break
	await process_frame
	await process_frame
	check(game.creator.has("name") and not is_instance_valid(demo),"new voyage opens character creation and disposes of the simulation")
	game.show_title()
	check(game.has_node("TitleMenu"),"character creation can return to the main menu")
	game.show_creator()
	game.start_game()
	var path := OS.get_temp_dir().path_join("starrail-continue-%s-%s.save" % [OS.get_process_id(),Time.get_ticks_usec()])
	var saved := bool(game.save_game(path,true))
	check(saved,"create an isolated docked save for Continue")
	if saved:
		var port_id: int = game.world.ride().dock
		var saved_day: int = game.world.day
		game.world.day += 1
		game.show_title()
		game.get_node("TitleMenu").resume(path)
		await process_frame
		check(game.playing and not game.has_node("TitleMenu") and game.speed == 0 and game.world.day == saved_day and port_id > 0 and game.world.ride().dock == port_id and is_instance_valid(game.canvas),"Continue restores a paused campaign at its saved port")
		DirAccess.remove_absolute(path)
	game.free()
	print("Opening menu ",checks-failures,"/",checks)
	quit(1 if failures else 0)
