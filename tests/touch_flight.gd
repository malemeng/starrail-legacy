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

func run() -> void:
	var game = Game.instantiate()
	game.mobile_play = true
	game.test_profile = true
	root.add_child(game)
	game.world.new_game({"seed":"android-flight","systems":12,"factions":3})
	game.run_bridge()
	game.set_physics_process(false)
	var deck = game.touch_deck
	check(not deck.visible and not game.side_collapsed,"port opens with touch-accessible management panel")
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
