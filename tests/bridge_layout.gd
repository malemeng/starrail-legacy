extends SceneTree

const Game = preload("res://game.tscn")

var game
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL ", root.size, " ", description)

func settle() -> void:
	for frame in 4:
		await process_frame

func check_screen() -> void:
	var viewport := root.get_visible_rect()
	var screen := root.get_final_transform() * viewport
	check(screen.position.length() < 1.5 and screen.size.distance_to(Vector2(root.size)) < 2.0, "game viewport fills the window")
	var uniform_scale := minf(root.size.x / viewport.size.x, root.size.y / viewport.size.y)
	check((viewport.size * uniform_scale).distance_to(Vector2(root.size)) < 1.5, "uniform game scale within pixel rounding")
	check(viewport.encloses(game.side_panel.get_global_rect()), "entire sidebar inside the viewport on " + game.tab)
	check(viewport.encloses(game.campaign_button.get_global_rect()), "last sidebar tab visible")
	check(viewport.encloses(game.side_toggle.get_global_rect()), "rightmost header control visible")
	check(viewport.encloses(game.footer.get_global_rect()), "bottom message visible")

func run() -> void:
	game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.creator.seed.text = "bridge-layout"
	game.start_game()
	game.set_physics_process(false)
	game.set_waypoint(Vector2(42, 64), "曙光锚地 Ⅰ · 造船港 [自动停靠]")
	game.refresh()
	for window_size in [Vector2i(1440, 900), Vector2i(1280, 720), Vector2i(1536, 801), Vector2i(1024, 768), Vector2i(1920, 1080)]:
		root.size = window_size
		for tab_name in ["港口", "人物", "资产", "疆域", "纪事", "事务"]:
			game.tab = tab_name
			game.refresh()
			await settle()
			check_screen()
		print("Window ", root.size, " logical viewport ", root.get_visible_rect().size, " sidebar ", game.side_panel.get_global_rect())
	root.size = Vector2i(1280, 720)
	game.world.depart(game.world.ride())
	game.tab = "港口"
	game.refresh()
	var keys_button := game.location_banner.get_parent().get_child(0) as Button
	keys_button.pressed.emit()
	game.say("直达导航到曙光锚地造船港，停靠后补给舰队。".repeat(7))
	await settle()
	check_screen()
	for action in game.quick_actions.get_children():
		if action.visible:
			check(root.get_visible_rect().encloses(action.get_global_rect()), "flight action visible: " + action.text)
	game.queue_free()
	await process_frame
	print("Bridge layout failures: ", failures)
	quit(1 if failures else 0)
