extends SceneTree

# Render the game's real title battle once on a development machine.
# godot --path . --rendering-method gl_compatibility --script tools/bake_title_replay.gd
const Exhibition = preload("res://scripts/ui/title_battle.gd")
const FRAME := Vector2i(448,252)
const GRID := Vector2i(4,8)

func _initialize() -> void:
	bake.call_deferred()

func bake() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Baking the replay requires a rendering device.")
		quit(1)
		return
	var screen := SubViewport.new()
	screen.size = FRAME
	screen.disable_3d = true
	screen.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(screen)
	var demo := Exhibition.new()
	demo.remember_lineup = false
	screen.add_child(demo)
	demo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	demo.set_physics_process(false)
	demo.rng.seed = 71209
	demo.world.rng.seed = 55021
	demo.previous_hulls.clear()
	demo.start_round()
	var sheet := Image.create_empty(FRAME.x*GRID.x,FRAME.y*GRID.y,false,Image.FORMAT_RGB8)
	for index in GRID.x*GRID.y:
		for tick in 10:
			demo._physics_process(1.0/60.0)
		await RenderingServer.frame_post_draw
		var frame := screen.get_texture().get_image()
		frame.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(frame,Rect2i(Vector2i.ZERO,FRAME),Vector2i(index%GRID.x,floori(float(index)/GRID.x))*FRAME)
	var err := sheet.save_webp("res://art/mobile_title_replay.webp",true,0.91)
	screen.queue_free()
	quit(0 if err == OK else 1)
