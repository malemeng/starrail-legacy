extends SceneTree

const Game = preload("res://game.tscn")
const Hulls = preload("res://hull_catalog.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var bridge = Game.instantiate()
	bridge.test_profile = true
	root.add_child(bridge)
	bridge.creator.seed.text = "port-lifecycle"
	bridge.start_game()
	await process_frame
	var before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for i in range(100):
		bridge.tab = "港口"
		bridge.dock_view.mode = ["market","yard","refit"][i % 3]
		bridge.dock_view.model_id = [0,1,5,7][i % 4]
		bridge.refresh()
		await process_frame
	bridge.tab = "港口"
	bridge.dock_view.mode = "yard"
	bridge.dock_view.model_id = Hulls.kind_for_reference("onslaught")
	bridge.refresh()
	await process_frame
	await process_frame
	var after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("100 dock screen changes, orphan nodes ", before, " -> ", after)
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_temp_dir().path_join("starrail-yard.png"))
	bridge.queue_free()
	await process_frame
	await process_frame
	quit(1 if after > before else 0)
