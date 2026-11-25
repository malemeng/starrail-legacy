extends SceneTree

const Game = preload("res://game.tscn")
const Art = preload("res://scripts/ui/station_art.gd")
const Geometry = preload("res://scripts/models/station_geometry.gd")
const Hulls = preload("res://hull_catalog.gd")
const Design = preload("res://scripts/models/station_design.gd")
const TINT := Color("69b9b8")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	run.call_deferred()

func module_silhouettes() -> void:
	var masks: Array[BitMap] = []
	for kind in 10:
		var im := Art.module_image(kind,TINT)
		var mask := BitMap.new()
		mask.create_from_image_alpha(im)
		check(mask.get_true_bit_count() > 600 and mask.get_true_bit_count() < 4700, "module %d has a bounded silhouette" % kind)
		for previous in masks:
			var overlap := 0
			for y in im.get_height():
				for x in im.get_width():
					if mask.get_bit(x,y) and previous.get_bit(x,y):
						overlap += 1
			var union_area := mask.get_true_bit_count()+previous.get_true_bit_count()-overlap
			check(float(overlap)/union_area < 0.89, "module %d has a distinct silhouette from each preceding module" % kind)
		masks.append(mask)

func run() -> void:
	module_silhouettes()
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.creator.seed.text = "station-berth-scale"
	game.start_game()
	game.set_physics_process(false)
	var world = game.world
	var lead: Dictionary = world.ride()
	var station: Dictionary = world.ports[lead.dock]
	# Representative five-module fixture using the same station record, geometry and renderer as a built station.
	station.modules = [2,4,5,6,0]
	station.design_cells = [Vector2i(-1,0),Vector2i(1,0),Vector2i(-1,-1),Vector2i(0,-1),Vector2i(-2,-1)]
	check(Design.issue(station.design_cells).is_empty(),"the pictured workshop layout has valid connected modules")
	var geom := Geometry.layout(station)
	check(geom.parts.size() == 6 and geom.links.size() >= 5,"the station includes every production building and connecting passage")
	if DisplayServer.get_name() != "headless" and "--capture" in OS.get_cmdline_user_args():
		await capture(game,geom)
	game.free()
	print("Station artwork %d/%d" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)

func capture(game, geom: Dictionary) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1440,900)
	var world = game.world
	game.flight.dock()
	var flagship: Dictionary = world.ride()
	var escort_pos: Vector2 = geom.berth + geom.outward*180 + Vector2(geom.outward).orthogonal()*160
	world.ship(Hulls.kind_for_reference("onslaught"),world.player,0,flagship.flag,flagship.system,escort_pos)
	await process_frame
	var frame: Rect2 = geom.bounds.merge(Rect2(escort_pos-Vector2.ONE*140,Vector2.ONE*280)).expand(flagship.pos).grow(60)
	game.canvas.zoom = minf(game.canvas.size.x/frame.size.x,game.canvas.size.y/frame.size.y)
	game.flight_zoom = game.canvas.zoom
	game.canvas.camera = frame.get_center()
	game.canvas.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var snapshot := root.get_texture().get_image()
	check(snapshot.save_png(OS.get_temp_dir().path_join("starrail-modular-station.png")) == OK, "save the workshop and ships in the actual flight viewport")
	var part: Dictionary = geom.parts[0]
	var center: Vector2 = geom.center + Vector2(part.center).rotated(geom.angle)
	var sample := Vector2i(game.canvas.get_global_transform() * game.canvas.screen(center))
	var regular := snapshot.get_pixelv(sample)
	check(regular.get_luminance() > 0.12,"the rendered station core appears where the actual geometry puts it")
	game.canvas.set_process(false)
	game.canvas.crowded = true
	game.canvas.queue_redraw()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().get_pixelv(sample).is_equal_approx(regular),"crowded combat uses the same station artwork at actual world scale")
