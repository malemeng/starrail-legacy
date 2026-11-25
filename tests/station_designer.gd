extends SceneTree

const Game = preload("res://game.tscn")
const Designer = preload("res://scripts/ui/station_designer.gd")
const Design = preload("res://scripts/models/station_design.gd")
const Economy = preload("res://economy.gd")

var checks := 0
var failed := 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failed += 1
		printerr("FAIL ",label)
	return ok

func _initialize() -> void:
	run.call_deferred()

func button_with(parent: Node, text: String) -> Button:
	for item: Button in parent.find_children("*","Button",true,false):
		if item.text == text:
			return item
	return null

func open_from(parent: Node, caption: String, game) -> Window:
	var trigger := button_with(parent,caption)
	if trigger == null:
		return null
	trigger.pressed.emit()
	for node in game.get_children():
		if node is Designer and node.visible:
			return node
	return null

func click_grid(editor, cell: Vector2i) -> void:
	var point: Vector2 = editor.grid.core()+Vector2(cell)*editor.grid.pitch()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = point
	editor.grid._gui_input(event)

func run() -> void:
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.creator.seed.text = "station-berth-scale"
	game.start_game()
	game.set_physics_process(false)
	var world = game.world
	var station: Dictionary = world.ports[world.ride().dock]
	var wallet: int = world.active().wallet
	var editor = open_from(game.dock_view.stage,"空间站布局",game)
	if check(editor != null,"open a foreign station's blueprints from the real welcome page"):
		var prior: Array = editor.cells.duplicate()
		click_grid(editor,Vector2i(-2,0))
		check(editor.commit == null and editor.cells == prior,"a foreign station is read-only")
		button_with(editor,"关闭").pressed.emit()
	await process_frame
	station.owner = world.player
	station.design_cells = [Vector2i(-1,0),Vector2i(1,0),Vector2i(-1,-1),Vector2i(0,-1),Vector2i(-2,-1)]
	station.modules = [2,4,5,6,0]
	var original: Array = station.design_cells.duplicate()
	editor = open_from(game.dock_view.stage,"空间站布局",game)
	if check(editor != null and editor.commit != null,"the owner can edit through the same welcome entry"):
		await process_frame
		click_grid(editor,Vector2i(-2,-1))
		click_grid(editor,Vector2i(-2,-2))
		check(editor.commit.disabled and station.design_cells == original,"a disconnected trial cell blocks saving and leaves the live layout intact")
		click_grid(editor,Vector2i(1,-1))
		check(not editor.commit.disabled,"an orthogonally connected free cell can be saved")
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
			check(editor.get_texture().get_image().save_png(OS.get_temp_dir().path_join("starrail-station-designer.png")) == OK,"capture the owner's live layout editor")
		button_with(editor,"取消").pressed.emit()
		check(station.design_cells == original and world.active().wallet == wallet,"cancel discards the preview without changing cash")
	await process_frame
	game.tab = "资产"
	game.refresh()
	editor = open_from(game.body,"空间站布局",game)
	if check(editor != null,"open the same editor from owned assets"):
		await process_frame
		click_grid(editor,Vector2i(-2,-1))
		click_grid(editor,Vector2i(1,-1))
		editor.commit.pressed.emit()
		check(not editor.visible and station.design_cells[4] == Vector2i(1,-1),"saving commits the chosen cell to the actual orbital station")
	await process_frame
	editor = open_from(game.body,"设计扩建",game)
	if check(editor != null,"open the asset expansion plan before paying"):
		var before: int = station.modules.size()
		check(world.active().wallet == wallet and editor.cells.size() == before+1,"expansion shows proposed module and preserves funds while editing")
		editor.commit.pressed.emit()
		check(station.expansion > 0 and station.design_cells.size() == before+1 and world.active().wallet == wallet-int(Economy.Industry.CONSTRUCTION.expansion.credits),"one confirmation records the chosen construction slot and charges once")
	await process_frame
	editor = open_from(game.body,"设计轨道工地",game)
	if check(editor != null,"a docked civilian can survey candidate construction sites"):
		check(editor.commit.disabled and not editor.status.text.is_empty(),"the economic construction service explains why the draft cannot be commissioned")
		editor.select_site(1)
		var proposed: Vector2 = editor.station.pos
		var vessel: Dictionary = world.ride()
		check(not editor.site_navigation.disabled and editor.commit.disabled,"a candidate orbit can be plotted without construction permission")
		editor.site_navigation.pressed.emit()
		check(vessel.dock == 0 and game.speed > 0 and game.waypoint_live and game.waypoint_tracking.is_valid() and game.waypoint == proposed,"the navigation button undocks, starts flight and tracks the construction orbit as its planet moves")
	await process_frame
	game.free()
	print("Station designer %d/%d" % [checks-failed,checks])
	quit(0 if failed == 0 else 1)
