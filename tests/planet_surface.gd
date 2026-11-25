extends SceneTree

const Game = preload("res://game.tscn")
const Saves = preload("res://scripts/services/save_manager.gd")
var checks := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	run.call_deferred()

func surface_image(game, planet: Dictionary) -> Image:
	game.canvas.camera = planet.pos
	game.flight_zoom = minf(game.canvas.size.x,game.canvas.size.y)*0.34/float(planet.radius)
	game.canvas.zoom = game.flight_zoom
	game.canvas.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func difference(left: Image, right: Image, center: Vector2i) -> float:
	var changed := 0
	var total := 0
	for y in range(center.y-62,center.y+62,2):
		for x in range(center.x-62,center.x+62,2):
			var a := left.get_pixel(x,y)
			var b := right.get_pixel(x,y)
			if maxi(absi(a.r8-b.r8),maxi(absi(a.g8-b.g8),absi(a.b8-b.b8))) > 2:
				changed += 1
			total += 1
	return float(changed)/total

func run() -> void:
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.creator.seed.text = "rotating-world-render"
	game.start_game()
	game.set_physics_process(false)
	game.flight.dock()
	game.set_speed(0)
	var world = game.world
	var system: int = world.ride().system
	var region: Dictionary = world.systems[system]
	var planet: Dictionary = region.planets[0]
	var initial: float = planet.get("spin",0.0)
	var rendered := DisplayServer.get_name() != "headless"
	var before: Image
	var after: Image
	var center := Vector2i.ZERO
	if rendered:
		root.size = Vector2i(1440,900)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		await process_frame
		before = await surface_image(game,planet)
		center = Vector2i(game.canvas.get_global_transform()*game.canvas.screen(planet.pos))
		var paused: Image = await surface_image(game,planet)
		check(difference(before,paused,center) == 0.0,"paused surface stays fixed across rendered frames")
	world.tick(150)
	game.update_header()
	check(absf(angle_difference(initial,planet.spin)) > 0.09,"calendar progress rotates the planet by a measurable angle")
	if rendered:
		after = await surface_image(game,planet)
		check(difference(before,after,center) > 0.18,"real surface features move across the illuminated hemisphere")
		if "--capture" in OS.get_cmdline_user_args():
			before.save_png(OS.get_temp_dir().path_join("starrail-planet-day-0.png"))
			after.save_png(OS.get_temp_dir().path_join("starrail-planet-day-150.png"))
	var angle: float = planet.spin
	var path := OS.get_temp_dir().path_join("starrail-surface-%d-%d.save" % [OS.get_process_id(),Time.get_ticks_usec()])
	check(Saves.write(world,path,false) and Saves.read(world,path),"the running campaign can be saved and restored")
	DirAccess.remove_absolute(path)
	planet = world.systems[system].planets[0]
	check(is_equal_approx(planet.spin,angle),"restored rotation matches the saved epoch")
	if rendered:
		var restored: Image = await surface_image(game,planet)
		check(difference(after,restored,center) < 0.01,"reopening the save restores the visible surface")
		game.toggle_system_chart()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var found := false
		for quad in game.canvas.body_quads:
			if quad.visible and quad.get_meta("surface_key",-1) == planet.surface_seed:
				found = is_equal_approx(quad.material.get_shader_parameter("spin"),planet.spin)
				var sunward: Vector2 = quad.material.get_shader_parameter("sunward")
				check(sunward.is_equal_approx(Vector2(planet.pos).direction_to(world.systems[system].sun.pos)),"orbital position keeps the day side facing the primary star")
		check(found,"system chart displays the same planet with the current physical angle")
	game.free()
	print("Planet surfaces %d/%d" % [checks-failed,checks])
	quit(0 if failed == 0 else 1)
