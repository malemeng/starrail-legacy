extends SceneTree

const Game = preload("res://game.tscn")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func touch(deck: Control, index: int, point: Vector2, pressed: bool) -> bool:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	return deck.handle(event)

func _initialize() -> void:
	run.call_deferred()

func check_dock_navigation(game) -> void:
	var dock = game.dock_view
	var details: ScrollContainer = dock.stage.get_node("Margins/Content/Scroll")
	var menu: HBoxContainer = dock.stage.get_node("Margins/Content/Places")
	var list: ScrollContainer = game.side_panel.get_node("Column/Scroll")
	game.tab = "资产"
	game.refresh()
	menu.get_child(2).pressed.emit()
	await process_frame
	await process_frame
	check(game.tab == "港口" and dock.rendered == "yard", "dock navigation returns from assets to the ship catalogue")
	for section in ["yard", "refit", "market", "people"]:
		dock.mode = section
		game.refresh()
		await process_frame
		await process_frame
		var back: Button = menu.get_child(0)
		check(back.text == "返回泊位" and dock.stage.get_global_rect().encloses(back.get_global_rect()),
			"berth navigation fits within the dock in " + section)
		if section == "yard":
			var original_y := back.global_position.y
			details.scroll_vertical = 250
			list.scroll_vertical = 180
			var detail_position := details.scroll_vertical
			var list_position := list.scroll_vertical
			game.refresh()
			await process_frame
			await process_frame
			check(detail_position > 0 and details.scroll_vertical == detail_position and menu.get_child(0).global_position.y == original_y,
				"ship quote scrolls independently and keeps its position across refresh")
			check(list_position > 0 and list.scroll_vertical == list_position, "ship catalogue scrolls independently")
			back = menu.get_child(0)
		if section in ["yard", "market"]:
			game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		else:
			back.pressed.emit()
		await process_frame
		await process_frame
		check(dock.mode == "welcome" and game.playing and details.scroll_vertical == 0 and list.scroll_vertical == 0,
			"return from " + section + " restores the berth and its own list position")

func run() -> void:
	var game = Game.instantiate()
	game.mobile_play = true
	game.test_profile = true
	root.add_child(game)
	var previous_idle := OS.low_processor_usage_mode
	game.show_title()
	var title = game.get_node("TitleMenu")
	var replay = title.replay
	check(title.battle == null and title.find_children("*","SubViewport",true,false).is_empty(),"mobile menu never starts a combat world or an off-screen battle viewport")
	check(replay.tile.atlas.get_size() == Vector2(replay.FRAME*replay.GRID),"all replay frames fit in one imported texture")
	var texture = replay.texture
	var first: Rect2 = replay.tile.region
	for i in replay.GRID.x*replay.GRID.y:
		replay.next_frame()
	check(replay.tile.region == first and replay.texture == texture,"replay loops without reallocating the texture")
	game.show_creator()
	check(OS.low_processor_usage_mode == previous_idle,"leaving the mobile title restores the campaign rendering policy")
	game.world.new_game({"seed":"android-flight","systems":12,"factions":3})
	game.run_bridge()
	game.set_physics_process(false)
	var deck = game.touch_deck
	check(not deck.visible and not game.side_collapsed,"port opens with touch-accessible management panel")
	await check_dock_navigation(game)
	game.flight.dock()
	await process_frame
	await process_frame
	check(deck.visible and game.side_collapsed,"departure makes the helm available")
	var pad: Vector2 = deck.get_global_transform_with_canvas()*deck.pad_center()
	var buttons: Dictionary = deck.buttons()
	var shield: Vector2 = deck.get_global_transform_with_canvas()*buttons.shield.get_center()
	var boost: Vector2 = deck.get_global_transform_with_canvas()*buttons.boost.get_center()
	var attack: Vector2 = deck.get_global_transform_with_canvas()*buttons.attack.get_center()
	var point: Vector2 = game.canvas.get_global_rect().get_center()+Vector2(85,0)
	check(touch(deck,0,pad+Vector2(40,0),true) and deck.movement.x>0.8,"thumb controls analog thrust")
	check(touch(deck,1,shield,true) and touch(deck,2,boost,true) and deck.shield and deck.boost,"shield and boost work independently of the helm finger")
	touch(deck,1,shield,false)
	check(not deck.shield and deck.boost and deck.movement.x>0.8,"releasing one finger preserves the others")
	touch(deck,2,boost,false)
	touch(deck,0,pad,false)
	game.speed = 1
	touch(deck,0,point,true)
	touch(deck,0,point,false)
	check(game.waypoint_live and not deck.firing,"course taps set a waypoint without firing")
	touch(deck,0,attack,true)
	touch(deck,0,attack,false)
	touch(deck,0,point,true)
	check(deck.firing and deck.has_aim and deck.world_point(deck.aim_at).is_equal_approx(game.waypoint),"fire uses the touched world coordinate")
	deck.hide()
	check(not deck.firing and not deck.shield and deck.movement == Vector2.ZERO and deck.fingers.is_empty(),"leaving the flight view releases held controls")
	game.free()
	print("Touch flight %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
