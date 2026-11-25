extends SceneTree

const Game = preload("res://game.gd")
const Hulls = preload("res://hull_catalog.gd")
const Geometry = preload("res://scripts/models/station_geometry.gd")
const Defenses = preload("res://scripts/battle/defenses.gd")
const Economy = preload("res://economy.gd")
var total := 0
var failed := 0

func check(ok: bool, message: String) -> void:
	total += 1
	if not ok:
		failed += 1
		printerr("FAIL ",message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game := Game.new()
	game.test_profile = true
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.creator.seed.text = "station-berth-scale"
	game.start_game()
	game.set_physics_process(false)
	var world = game.world
	var flagship: Dictionary = world.ride()
	var port: Dictionary = world.ports[flagship.dock]
	var geom := Geometry.layout(port)
	var capital := Hulls.kind_for_reference("onslaught")
	var capital_length: float = Defenses.geometry(capital).rect.size.x
	for slot: int in Geometry.Profiles.data.modules.size():
		var candidate: Dictionary = port.duplicate()
		candidate.module = slot
		candidate.capital_yard = false
		var layout := Geometry.layout(candidate)
		check(layout.span >= 400 and layout.span <= 1100 and layout.span > capital_length, "station module %d physically larger than a capital hull" % slot)
		var transform := Transform2D(layout.angle,layout.center)
		for corner: Vector2 in [layout.size*0.5, -layout.size*0.5, layout.size*Vector2(-0.5,0.5),layout.size*Vector2(0.5,-0.5)]:
			check(layout.berth.distance_to(transform * corner) < Geometry.MAX_REACH,"bounded station footprint")
	for base: Dictionary in world.Outlaws.summary(world):
		var outpost := Geometry.outpost(world.systems[base.system].outlaw_base)
		check(outpost.berth == base.pos and outpost.span > capital_length,"outlaw station has a world-scale body and an external approach beacon")
	for kind: int in [flagship.kind,capital]:
		var departure := Geometry.departure(port,kind)
		var from_center: Vector2 = (departure - Vector2(geom.center)).rotated(-geom.angle)
		check(from_center.y - geom.size.y * 0.5 > Defenses.geometry(kind).radius,"undocking clears the entire hull")
	game.flight.dock()
	check(flagship.dock == 0 and flagship.pos.is_equal_approx(Geometry.departure(port,flagship.kind)),"normal undock uses exterior approach")
	var reach := Geometry.docking_range(flagship.kind)
	flagship.pos = geom.berth + geom.outward * (reach + 1)
	check(game.flight.nearby_port(flagship) != port.id,"outside approach range")
	flagship.pos = geom.berth + geom.outward * (reach - 1)
	game.flight.dock()
	check(flagship.dock == port.id and flagship.pos == geom.berth,"can dock using E on approach within the actual hull's reach")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await capture(game,geom,capital)
	construction(world,flagship)
	game.free()
	print("Station scale %d/%d" % [total-failed,total])
	quit(0 if failed == 0 else 1)

func construction(world, ship: Dictionary) -> void:
	var yard: int = ship.dock
	var engineer := Hulls.kind_for_id("gantry_ca")
	world.active().wallet += Economy.ship_quote(world.ports[yard],engineer).price
	var bought := Economy.buy_ship(world,yard,engineer)
	var piloted: bool = bought != 0 and world.pilot(bought)
	check(piloted,"pilot the shipyard's engineering cruiser before orbital construction")
	if not piloted:
		return
	ship = world.ride()
	world.depart(ship)
	var region: Dictionary = world.systems[ship.system]
	var center := Vector2(200000,200000)
	region.planets.append({"pos":center,"radius":700})
	var actor: Dictionary = world.active()
	actor.wallet = 1000
	var cost := int(Economy.Industry.CONSTRUCTION.foundation.credits)
	var berth := center + Vector2(800,0)
	ship.pos = berth
	var id := Economy.deploy(world,2,berth)
	if not check_site(world,id,1000-cost):
		return
	var dock := Geometry.layout(world.ports[id])
	check(dock.outward.dot(berth.direction_to(center)) > 0.99 and not Geometry.intersects_body(dock,region.planets.back()),"orbital yard extends away from the planet")
	var nearby := center + Vector2(800,0).rotated(0.28)
	ship.pos = nearby
	check(berth.distance_to(nearby) > Economy.Industry.CONSTRUCTION.minimum_separation and Economy.deploy(world,2,nearby) == 0 and actor.wallet == 1000-cost,
		"separated berth beacons do not permit two overlapping yards or deduct fees")
	var opposite := center - Vector2(800,0)
	var moon := {"pos":opposite-Vector2(300,0),"radius":80}
	region.planets.append(moon)
	ship.pos = opposite
	check(Economy.deploy(world,2,opposite) == 0 and actor.wallet == 1000-cost,"a body intersecting the station blocks a clear berth without charge")

func check_site(world, id: int, wallet: int) -> bool:
	var ok: bool = world.ports.has(id) and world.active().wallet == wallet
	check(ok,"free orbital site can be built for the listed price")
	return ok

func capture(game, geom: Dictionary, capital: int) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1440,900)
	var world = game.world
	game.flight.dock()
	var lead: Dictionary = world.ride()
	var at: Vector2 = geom.berth + geom.outward * 185 + Vector2(geom.outward).orthogonal()*200
	var capital_id: int = world.ship(capital,world.player,0,lead.flag,lead.system,at)
	await process_frame
	var combined := Rect2(geom.bounds).expand(lead.pos).merge(Rect2(at - Vector2.ONE * 125,Vector2.ONE * 250)).grow(36)
	game.flight_zoom = minf(0.6,minf(game.canvas.size.x/combined.size.x,game.canvas.size.y/combined.size.y))
	game.canvas.zoom = game.flight_zoom
	game.canvas.camera = combined.get_center()
	game.canvas.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var snapshot := root.get_texture().get_image()
	check(snapshot.save_png(OS.get_temp_dir().path_join("starrail-station-scale.png")) == OK,"save rendered shipyard, frigate and capital together")
	var sample: Vector2 = game.canvas.get_global_transform() * game.canvas.screen(geom.center)
	var normal := snapshot.get_pixelv(Vector2i(sample))
	game.canvas.set_process(false)
	game.canvas.crowded = true
	game.canvas.queue_redraw()
	await RenderingServer.frame_post_draw
	var dense := root.get_texture().get_image().get_pixelv(Vector2i(sample))
	check(normal.is_equal_approx(dense),"crowded combat preserves the same station pixels at the same scale")
	game.tactics.show()
	game.canvas.queue_redraw()
	await RenderingServer.frame_post_draw
	var tactical := root.get_texture().get_image()
	var center: Vector2 = game.canvas.get_global_transform() * game.canvas.tactical_screen(geom.center)
	check(tactical.get_pixelv(Vector2i(center)).get_luminance() > 0.2,"station center remains visible on the tactical map")
	var bow: Vector2 = at + Vector2.from_angle(world.ships[capital_id].heading) * Defenses.geometry(capital).rect.end.x * 0.60
	var bow_pixel: Vector2 = game.canvas.get_global_transform() * game.canvas.tactical_screen(bow)
	var bow_color := tactical.get_pixelv(Vector2i(bow_pixel))
	check(bow_color.g > 0.36 and bow_color.g > bow_color.r,"tactical capital silhouette extends to its actual projected bow")
	game.set_tactics(false)
	game.flight.dock()
