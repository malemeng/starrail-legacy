extends SceneTree

const Game = preload("res://game.tscn")
const Chart = preload("res://scripts/ui/system_chart.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1440,900)
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.creator.seed.text = "station-berth-scale"
	game.start_game()
	game.set_physics_process(false)
	await process_frame
	var world = game.world
	var ship: Dictionary = world.ride()
	var berth: int = ship.dock
	var region: Dictionary = world.systems[ship.system]
	game.chart_button.pressed.emit()
	await process_frame
	game.update_bridge(0)
	check(game.system_chart and game.canvas.is_visible_in_tree() and not game.dock_view.stage.visible and ship.dock == berth,"the permanent bridge button opens the local chart while staying docked")
	var markers := Chart.markers(game.canvas,world,region,ship)
	var keys := {}
	var pickable := true
	var tags := 0
	for marker: Dictionary in markers:
		keys[marker.kind] = true
		var target: Dictionary = game.canvas.chart_pick(marker.at)
		pickable = pickable and target.get("kind","") == marker.kind and target.get("id",-1) == marker.id
		if Rect2(marker.label_box).has_area():
			tags += 1
			target = game.canvas.chart_pick(Rect2(marker.label_box).get_center())
			pickable = pickable and target.get("kind","") == marker.kind and target.get("id",-1) == marker.id
	for type in ["star","planet","port","ship","gravity","field"]:
		check(keys.has(type),"the chart contains a selectable "+type)
	check(pickable and tags >= 5,"overlapping objects at the home berth retain independently clickable glyphs and labels")
	var station: Dictionary
	var craft: Dictionary
	for marker: Dictionary in markers:
		if marker.kind == "port" and marker.id == berth:
			station = marker
		if marker.kind == "ship":
			craft = marker
	check(station.pos == craft.pos and Vector2(station.at).distance_to(craft.at) >= 12.0,"coincident physical positions have separated screen hit targets")
	game.select_chart_target(station)
	if DisplayServer.get_name() != "headless" and "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(OS.get_temp_dir().path_join("starrail-system-chart.png")) == OK,"capture the actual docked chart and selection panel")
	game.chart_button.pressed.emit()
	check(not game.system_chart and game.dock_view.stage.visible and ship.dock == berth,"closing the chart returns directly to the same dock")
	game.flight.dock()
	game.chart_button.pressed.emit()
	await process_frame
	check(game.system_chart and ship.dock == 0,"the same chart is also available in flight")
	var whole: Rect2 = game.canvas.chart_bounds(region,ship.pos)
	check(whole.has_point(region.sun.pos) and whole.has_point(ship.pos) and whole.has_point(region.field),"auto-fit uses real stellar, navigation and ship bounds")
	game.free()
	print("System chart %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
