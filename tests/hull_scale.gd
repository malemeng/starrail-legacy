extends SceneTree

const ScaleChart = preload("res://scripts/ui/hull_scale.gd")
const Hulls = preload("res://hull_catalog.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var spans := [Vector2(INF,0),Vector2(INF,0),Vector2(INF,0),Vector2(INF,0)]
	for i in range(Hulls.MODELS.size()):
		var model: Dictionary = Hulls.MODELS[i]
		var length := ScaleChart.dimensions(i).size.x
		var tier: int = model.size
		spans[tier] = Vector2(minf(spans[tier].x,length),maxf(spans[tier].y,length))
	for tier in range(1,4):
		if spans[tier].x < spans[tier-1].y * 1.25:
			printerr("Adjacent hull classes overlap: ", spans)
			quit(1)
			return
	if spans[3].x < spans[0].y*5.0:
		printerr("Capital / frigate silhouette ratio below 5:1")
		quit(1)
		return
	print("Hull scale verified for ", Hulls.MODELS.size(), " models, ranges ", spans)
	if "--capture" in OS.get_cmdline_user_args():
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.size = Vector2i(920,320)
		root.transparent_bg = false
		var chart := ScaleChart.new()
		var face := SystemFont.new()
		face.font_names = ["Microsoft YaHei UI","Microsoft YaHei","Noto Sans CJK SC"]
		var ui_theme := Theme.new()
		ui_theme.default_font = face
		chart.theme = ui_theme
		chart.configure(Hulls.kind_for_reference("onslaught"))
		root.add_child(chart)
		chart.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		await RenderingServer.frame_post_draw
		var output := root.get_texture().get_image()
		if output.save_png("res://art/fleet_scale.png") != OK:
			printerr("Failed to save scale chart")
			quit(1)
			return
	quit()
