extends SceneTree

const World = preload("res://world.gd")
const Game = preload("res://game.gd")
const Celestial = preload("res://celestial.gd")
const Hulls = preload("res://hull_catalog.gd")
const Defenses = preload("res://scripts/battle/defenses.gd")
const Stations = preload("res://scripts/models/station_geometry.gd")
var assertions := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	run.call_deferred()

func universe(seed_text: String) -> World:
	var world := World.new()
	world.new_game({"seed":seed_text,"systems":24,"factions":5})
	return world

func chart(world, index: int) -> Array:
	var region: Dictionary = world.systems[index]
	var stations := []
	for id: int in region.ports:
		stations.append(world.ports[id].pos)
	return [region.name,region.pos,region.sun,region.get("companion",{}),region.planets,
		region.field,region.rock_count,region.belt_angle,region.belt_width,region.sky_seed,region.starfield,stations]

func beacon_spacing(world: World) -> void:
	var home: Vector2 = world.systems[0].pos
	var first_leg := home.distance_to(world.systems[1].pos)
	check(first_leg >= 680.0 and first_leg <= 980.0, "the starting trade leg spans 680 to 980 hyperspace units")
	var nearby := world.nearby_beacons(home)
	var distances := nearby.map(func(id: int): return home.distance_to(world.systems[id].pos))
	var sorted := distances.duplicate()
	sorted.sort()
	check(1 in nearby and distances == sorted, "a scan includes the first trade destination and lists beacons nearest first")
	var count := world.systems.size()
	check(world.nearby_beacons(home) == nearby and world.systems.size() == count, "a repeat scan reuses the same streamed cells")
	var closest := INF
	for i in world.systems.size():
		for j in range(i):
			var p: Vector2 = world.systems[i].pos
			closest = minf(closest,p.distance_to(world.systems[j].pos))
	check(count > world.core_count and closest >= 599.99, "core and frontier beacons keep at least 600 units apart including adjacent cell edges")
	var original: Dictionary = world.systems[1]
	var relocated := {"name":original.name,"pos":original.pos * 3.0}
	Celestial.populate(relocated,world.settings.seed)
	check(original.sun == relocated.sun and original.planets == relocated.planets and original.field == relocated.field
		and Celestial.gravity_point(original) == Celestial.gravity_point(relocated),
		"moving a hyperspace beacon preserves its local orbits, resource belt and jump point")

func size_and_clearance(world) -> void:
	var longest_ship := 0.0
	for kind in Hulls.MODELS.size():
		if Hulls.available_for_market(kind):
			var width: Vector2 = Defenses.geometry(kind).rect.size
			longest_ship = maxf(longest_ship,maxf(width.x,width.y))
	var smallest_rock := INF
	var largest_rock := 0.0
	var smallest_giant := INF
	var largest_giant := 0.0
	var smallest_sun := INF
	var minimum_gap := INF
	var min_station := INF
	var max_station := 0.0
	for region: Dictionary in world.systems:
		smallest_sun = minf(smallest_sun,region.sun.radius)
		var bodies: Array = [region.sun]
		if region.has("companion"):
			bodies.append(region.companion)
		for planet: Dictionary in region.planets:
			bodies.append(planet)
			if planet.type < 20:
				smallest_rock = minf(smallest_rock,planet.radius)
				largest_rock = maxf(largest_rock,planet.radius)
			else:
				smallest_giant = minf(smallest_giant,planet.radius)
				largest_giant = maxf(largest_giant,planet.radius)
		for i in bodies.size():
			for j in range(i):
				var first: float = bodies[i].radius * (1.6 if bodies[i].get("rings",false) else 1.0)
				var second: float = bodies[j].radius * (1.6 if bodies[j].get("rings",false) else 1.0)
				var gap: float = bodies[i].pos.distance_to(bodies[j].pos) - first - second
				minimum_gap = minf(minimum_gap,gap)
	for station: Dictionary in world.ports.values():
		var span: float = Stations.layout(station).span
		min_station = minf(min_station,span)
		max_station = maxf(max_station,span)
	check(smallest_rock*2.0 > longest_ship*5.0, "even the smallest terrestrial disc spans more than five full capital hull lengths")
	check(longest_ship < min_station and max_station < 2.0*smallest_rock,
		"station structures sit between the largest marketable ship and the smallest rocky planet in physical span")
	check(smallest_giant > largest_rock and smallest_sun > largest_giant, "terrestrial, giant and primary-star physical radii occupy distinct scales")
	check(minimum_gap >= Celestial.Scale.data.surface_clearance - 0.01, "even the outer edges of rings preserve the configured clearance between bodies")
	print("System sizes hull_length_max=%.1f rock_radius=%.0f..%.0f giant_radius=%.0f..%.0f primary_radius_min=%.0f surface_gap_min=%.1f" %
		[longest_ship,smallest_rock,largest_rock,smallest_giant,largest_giant,smallest_sun,minimum_gap])

func layouts() -> void:
	var baseline := universe("star-atlas")
	var repeat := universe("star-atlas")
	var other := universe("star-atlas-elsewhere")
	var seed_match := true
	var reconfigured := true
	for i in range(baseline.core_count):
		seed_match = seed_match and chart(baseline,i) == chart(repeat,i)
		var a: Dictionary = baseline.systems[i]
		var b: Dictionary = other.systems[i]
		var a_port: Vector2 = baseline.ports[a.ports[0]].pos
		var b_port: Vector2 = other.ports[b.ports[0]].pos
		reconfigured = reconfigured and a.sun.pos != b.sun.pos and a.planets[0].pos != b.planets[0].pos and a.field != b.field and a.sky_seed != b.sky_seed
		reconfigured = reconfigured and (a_port - a.sun.pos) != (b_port - b.sun.pos)
	check(seed_match, "restarting the same seed reproduces every core chart, its bodies, belts and station coordinates")
	check(reconfigured, "changing the seed reshapes every indexed system including home and the tutorial mining system")
	var home: Dictionary = baseline.systems[0]
	var mine: Dictionary = baseline.systems[1]
	check(chart(baseline,0) != chart(baseline,1) and home.sky_seed != mine.sky_seed and home.ports.size() >= 1 and mine.ports.size() >= 2,
		"home and mining regions have distinct lands while preserving their trade facilities")
	check(mine.pos != other.systems[1].pos and baseline.ports[mine.ports[1]].pos-mine.field != other.ports[other.systems[1].ports[1]].pos-other.systems[1].field,
		"the neighbouring trade route and the refinery-to-belt offset change with the seed")
	var star_types := {}
	var planet_counts := {}
	var sky_types := {}
	var single := false
	var binary := false
	var bodies_clear := true
	for region: Dictionary in baseline.systems:
		star_types[region.sun.type] = true
		planet_counts[region.planets.size()] = true
		sky_types[region.starfield] = true
		binary = binary or region.has("companion")
		single = single or not region.has("companion")
		for p: Dictionary in region.planets:
			bodies_clear = bodies_clear and p.pos.distance_to(region.sun.pos) > p.radius + region.sun.radius
			if region.has("companion"):
				bodies_clear = bodies_clear and p.pos.distance_to(region.companion.pos) > p.radius + region.companion.radius
			for id: int in region.ports:
				bodies_clear = bodies_clear and p.pos.distance_to(baseline.ports[id].pos) > p.radius
		for i in region.planets.size():
			for j in range(i):
				bodies_clear = bodies_clear and region.planets[i].pos.distance_to(region.planets[j].pos) > region.planets[i].radius + region.planets[j].radius
	check(star_types.size() >= 3 and sky_types.size() >= 3 and planet_counts.size() >= 3 and single and binary,
		"one seed produces distinct skies, star classes, planetary populations and single/binary systems")
	check(bodies_clear, "generated stars, planets and active ports do not overlap")
	var first := Vector2i(-14, 17)
	var second := Vector2i(19, -12)
	for cell: Vector2i in [first,second]:
		baseline.ensure_chunks_around(Vector2(cell)*World.CHUNK_SIZE,0)
	for cell: Vector2i in [second,first]:
		repeat.ensure_chunks_around(Vector2(cell)*World.CHUNK_SIZE,0)
		other.ensure_chunks_around(Vector2(cell)*World.CHUNK_SIZE,0)
	for cell: Vector2i in [first,second]:
		var a: Array = baseline.chunks[cell]
		var b: Array = repeat.chunks[cell]
		var c: Array = other.chunks[cell]
		var matches: bool = not a.is_empty() and a.size() == b.size()
		for i in mini(a.size(),b.size()):
			matches = matches and chart(baseline,a[i]) == chart(repeat,b[i])
		check(matches, "outer charts at %s reproduce independent of exploration order" % cell)
		check(not a.is_empty() and not c.is_empty() and chart(baseline,a[0]) != chart(other,c[0]), "the same outer cell varies across campaign seeds")
	size_and_clearance(baseline)
	beacon_spacing(baseline)

func survey() -> void:
	var standard := survey_trip(1)
	var cruise := survey_trip(3)
	check(absi(standard.days-cruise.days) <= 1 and cruise.frames < standard.frames*0.4,
		"third-speed cruise reaches the same survey orbit in a third of real time at the same calendar cost")
	print("Survey voyage days=%d/%d frames=%d/%d at speeds 1/3" % [standard.days,cruise.days,standard.frames,cruise.frames])

func survey_trip(pace: int) -> Dictionary:
	var game := Game.new()
	game.test_profile = true
	root.add_child(game)
	game.set_physics_process(false)
	game.world.new_game({"seed":"survey-route","systems":12,"factions":3})
	game.run_bridge()
	game.flight.dock()
	var region: Dictionary = game.world.systems[0]
	var planet: Dictionary = region.planets.front()
	var ship: Dictionary = game.world.ride()
	var credits: int = game.world.active().wallet
	game.track_planet(0,false)
	game.set_speed(pace)
	var frames := 0
	for frame in range(24000):
		if ship.pos.distance_to(planet.pos) <= planet.radius + 48.0:
			break
		game.step_simulation(Vector2.ZERO,false,false,Vector2.ZERO,false)
		frames += 1
	game.flight.salvage()
	check(planet.surveyed and game.world.active().wallet > credits and planet.name in game.notice_text,
		"fly to the generated planet and survey its actual marker through the flight action")
	credits = game.world.active().wallet
	game.flight.salvage()
	check(game.world.active().wallet == credits, "the same physical survey cannot pay twice")
	var restored := World.new()
	check(restored.load_state(game.world.snapshot()) and restored.systems[0].planets[0] == planet, "the surveyed body remains identified after reload")
	var trip := {"days":game.world.day,"frames":frames}
	game.free()
	return trip

func rendered_frame(view: Control, viewport: SubViewport, system: int) -> Image:
	view.sync_battlefield(system)
	view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func rendered_landmarks() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var game := Game.new()
	game.test_profile = true
	root.add_child(game)
	game.set_physics_process(false)
	var world = game.world
	world.new_game({"seed":"stellar-limbs","systems":12,"factions":3})
	game.run_bridge()
	game.flight.dock()
	game.speed = 0
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720,480)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view: Control = game.canvas
	view.reparent(viewport,false)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var region: Dictionary = world.systems[0]
	var lead: Dictionary = world.ride()
	for body: Dictionary in [region.sun,region.planets[0]]:
		var original: Vector2 = body.pos
		lead.pos = original + Vector2.RIGHT * (body.radius + 160.0)
		game.flight_zoom = 0.45
		game.update_bridge(0.0)
		var ordinary := await rendered_frame(view,viewport,0)
		var patch := Rect2i(180,220,38,40)
		var pixels := ordinary.get_region(patch).get_data()
		check(not view.crowded, "ordinary flight uses the local navigation render path")
		var escorts := []
		for i in 40:
			escorts.append(world.ship(0,world.player,0,world.NEUTRAL,0,lead.pos + Vector2(65+i%8*12,135+floori(i/8.0)*12)))
		var dense := await rendered_frame(view,viewport,0)
		check(view.crowded and dense.get_region(patch).get_data() == pixels, "crowded flight retains the same celestial surface at its true distance")
		body.pos = original + Vector2.LEFT * (2.0 * body.radius + 9000.0)
		var empty := await rendered_frame(view,viewport,0)
		check(empty.get_region(patch).get_data() != pixels, "the sampled landmark really contributes pixels to the crowded-path framebuffer")
		body.pos = original
		for id: int in escorts:
			world.ships.erase(id)
	viewport.free()
	game.free()

func run() -> void:
	layouts()
	survey()
	await rendered_landmarks()
	print("System generation %d/%d" % [assertions-failures,assertions])
	quit(0 if failures == 0 else 1)
