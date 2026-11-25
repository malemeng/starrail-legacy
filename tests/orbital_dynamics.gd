extends SceneTree

const World = preload("res://world.gd")
const Celestial = preload("res://celestial.gd")
const Orbits = preload("res://scripts/campaign/orbital_dynamics.gd")
const Geometry = preload("res://scripts/models/station_geometry.gd")
const Ports = preload("res://scripts/campaign/planet_ports.gd")
const Game = preload("res://game.tscn")
var checks := 0
var failures := 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",description)

func _initialize() -> void:
	run.call_deferred()

func accelerations(gap: float, mass: float) -> Array[Vector2]:
	var left := {"pos":Vector2(-gap/2,50000),"mu":1000.0}
	var right := {"pos":Vector2(gap/2,50000),"mu":mass}
	Orbits.calculate_acceleration([left,right],Vector2.ZERO,0.0)
	return [left.orbital_acceleration,right.orbital_acceleration]

func gravity() -> void:
	var near := accelerations(1000.0,1000.0)
	var far := accelerations(2000.0,1000.0)
	check(near[0].x > 0 and near[1].x < 0 and is_equal_approx(near[0].x,-near[1].x),"two planets accelerate toward each other with equal and opposite pair forces")
	check(absf(near[0].x/far[0].x-4.0)<0.01,"doubling planet separation gives one quarter of the attraction outside the softening radius")
	var heavier := accelerations(1000.0,2000.0)
	check(absf(heavier[0].x/near[0].x-2.0)<0.001,"doubling the neighboring planet's mass doubles its gravitational pull")

func sector() -> World:
	var world := World.new()
	world.new_game({"seed":"orbital-mechanics","systems":12,"factions":3})
	return world

func orbit_state(world: World) -> Array:
	var region: Dictionary = world.systems[0]
	var readings := []
	for body: Dictionary in region.planets:
		readings.append([body.pos,body.orbital_velocity,body.spin,body.orbital_acceleration])
	for id in region.ports:
		var station: Dictionary = world.ports[id]
		readings.append([station.pos,station.get("berth_heading",0.0)])
	return readings

func calendar() -> void:
	var normal := sector()
	var fast := sector()
	var initial := orbit_state(normal)
	check(initial == orbit_state(fast),"independent campaigns with the same seed start with the same vectors and phases")
	var present: Dictionary = normal.ride()
	var orbital_port: int = present.dock
	var slot: Dictionary = normal.systems[0].planets[0]
	var id := normal.ship(0,0,0,normal.NEUTRAL,0,slot.pos)
	normal.berth(normal.ships[id],slot.port_id)
	for day in 96:
		normal.tick()
	fast.tick(96)
	check(normal.day == 96 and normal.day == fast.day and orbit_state(normal) == orbit_state(fast),"individually simulated days and a batch advance give exactly equal positions, velocities and spin")
	check(initial[0][0].distance_to(slot.pos)>5 and initial[0][1] != slot.orbital_velocity and absf(slot.spin)>0.01,"the world calendar advances orbital position, orbital velocity and surface orientation")
	check(normal.ships[id].pos.is_equal_approx(Ports.point(slot)) and present.pos.is_equal_approx(normal.ports[orbital_port].pos),"ships moored at an orbiting outpost and a moving surface port stay with their respective berths")
	var saved := World.new()
	check(saved.load_state(normal.snapshot()) and orbit_state(saved) == orbit_state(normal),"reloading restores orbital velocities, instantaneous positions, port directions and spin")
	normal.tick(72)
	saved.tick(72)
	check(orbit_state(saved) == orbit_state(normal),"reloaded trajectories continue identically for another 72 days")
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.set_physics_process(false)
	game.world = saved
	game.run_bridge()
	game.set_speed(0)
	var before_pause := orbit_state(saved)
	var day_paused := saved.day
	for frame in 160:
		game.step_simulation(Vector2.ZERO,false,false,Vector2.ZERO,false)
	check(saved.day == day_paused and orbit_state(saved) == before_pause,"pausing the actual flight simulation freezes bodies, berths and their rotation")
	game.free()

func orbital_clearance() -> void:
	var world := sector()
	var region: Dictionary = world.systems[0]
	var body: Dictionary = region.planets[0]
	var berth := Celestial.construction_point(region,body,Vector2.ZERO)
	var id := world.port(0,"轨道同步测试",berth,world.NEUTRAL,world.player,world.Industry.Module.YARD,false)
	var station: Dictionary = world.ports[id]
	station.orbit = 0
	station.berth_heading = berth.angle_to_point(body.pos)
	Orbits.advance_station(station,region,1)
	var motion: Dictionary = station.orbital_motion
	var period := TAU / absf(float(motion.rate))
	var separated := true
	var radial_error := 0.0
	var ship_clear := true
	for phase in 193:
		var day := 1+roundi(period*phase/96.0)
		Orbits.advance_station(station,region,day)
		var hull := Geometry.layout(station)
		separated = separated and not Geometry.intersects_body(hull,body)
		ship_clear = ship_clear and Geometry.departure(station,1).distance_to(body.pos) > body.radius
		radial_error = maxf(radial_error,absf(Vector2(hull.design_origin).distance_to(body.pos)-Vector2(motion.axis).length()))
	check(separated and ship_clear and radial_error<0.02,"the physical station and departing ships stay clear of the parent at 193 phases spanning two full local orbits")
	print("Low orbit period=%.1f days, maximum radial deviation=%.6f" % [period,radial_error])

func run() -> void:
	gravity()
	calendar()
	orbital_clearance()
	print("Orbital dynamics ",checks-failures,"/",checks)
	quit(1 if failures else 0)
