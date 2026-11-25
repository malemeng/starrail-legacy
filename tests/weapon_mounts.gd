extends SceneTree
const Art = preload("res://art/weapon_mounts.gd")
const Batch = preload("res://scripts/battle/weapon_batch.gd")
const IDS = ["rail","howitzer","pulse","lance","missile","pd"]
func _initialize(): run.call_deferred()
func row_pose(i: int) -> Transform2D:
	var center := Vector2(34+(i%3)*85,30+floori(float(i)/3)*58)
	return Transform2D(0,Vector2.ONE*3,0,center)

func run():
	if DisplayServer.get_name() == "headless":
		print("Weapon mount pixel comparison requires a rendered window")
		quit()
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(520,240)
	var close := Node2D.new()
	root.add_child(close)
	close.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var far := Batch.new()
	far.position = Vector2(260,0)
	root.add_child(far)
	far.begin(12)
	for i in 12:
		var id: String=IDS[i%6]
		var parent_transform := row_pose(i)
		var angle := PI/2 if i >= 6 else 0.0
		far.add_mount(parent_transform,{"offset":Vector2.ZERO},id,angle,0,false)
	far.finish()
	close.draw.connect(func():
		for i in 12:
			var style := Art.profile(IDS[i%6])
			var parent_transform := row_pose(i)
			var angle := PI/2 if i >= 6 else 0.0
			Art.draw_mount(close,parent_transform*Art.pose({"offset":Vector2.ZERO},style,angle,0),style.family,Color.WHITE)
	)
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var bg := img.get_pixel(0,0)
	var mismatch := 0
	var painted := 0
	for y in 240:
		for x in 260:
			var a := img.get_pixel(x,y)
			var b := img.get_pixel(x+260,y)
			if a != bg: painted += 1
			if a != b: mismatch += 1
	print("GPU comparison 6 turret families, 2 bearings, rendered pixels=",painted," differing pixels=",mismatch)
	close.free()
	far.free()
	quit(1 if mismatch or painted < 100 else 0)
