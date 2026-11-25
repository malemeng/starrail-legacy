extends SceneTree

const Game = preload("res://game.tscn")
const Contacts = preload("res://scripts/battle/hull_contacts.gd")
const Battle = preload("res://combat.gd")
const Art = preload("res://art/weapon_mounts.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",message)

func _initialize(): run.call_deferred()

func outline(vessel: Dictionary) -> PackedVector2Array:
	return Transform2D(vessel.heading,vessel.pos)*PackedVector2Array(Battle.Defenses.geometry(vessel.kind).bounds)

func run():
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.show_title()
	var demo = game.get_node("TitleMenu").battle
	demo.set_physics_process(false)
	var world = demo.world
	world.ships.clear()
	var a: Dictionary = world.ships[world.ship(2,0,0,world.NEUTRAL,0,Vector2(-75,0))]
	var b: Dictionary = world.ships[world.ship(7,0,0,world.RAIDERS,0,Vector2(100,0))]
	a.heading = 0
	b.heading = PI
	var starts := Contacts.capture(world,0)
	a.pos = Vector2(140,0)
	b.pos = Vector2(-80,0)
	a.battle.motion = Vector2(900,14)
	b.battle.motion = Vector2(-900,14)
	Contacts.resolve(world,0,starts)
	check(a.pos.x < b.pos.x and Geometry2D.intersect_polygons(outline(a),outline(b)).is_empty(),"fast opposing ships cannot tunnel through each other")
	check(a.battle.motion.x < 0 and absf(b.battle.motion.x+900) < absf(a.battle.motion.x-900),"lighter hull receives the larger impulse")
	var at_wall := Contacts.Body.new(a,{},Vector2(365,240),Contacts.active_parts(a))
	at_wall.pose.origin = Vector2(0,-at_wall.limit.y)
	var free_axis: float = at_wall.push_out(Vector2(-1,-1).normalized(),1.0)
	check(free_axis > 0.99 and at_wall.pose.origin.y == -at_wall.limit.y,"a pinned hull slides sideways to free the other ship")
	a.pos = Vector2(-110,0)
	b.pos = Vector2.ZERO
	starts = Contacts.capture(world,0)
	a.pos = Vector2(130,0)
	a.battle.contact_blink = true
	Contacts.resolve(world,0,starts)
	check(Vector2(a.pos).is_equal_approx(Vector2(130,0)) and b.pos == Vector2.ZERO,"a blink crosses intervening hulls and checks the destination")
	a.pos = Vector2.ZERO
	b.pos = Vector2.ZERO
	a.heading = PI/4
	b.heading = PI/2
	Contacts.resolve(world,0,{})
	check(Geometry2D.intersect_polygons(outline(a),outline(b)).is_empty(),"rotated ships already stacked in a save separate")
	a.pos = Vector2.ZERO
	b.pos = Vector2.ZERO
	a.battle.phase_active = true
	Contacts.resolve(world,0,{})
	check(a.pos == b.pos,"phased hull passes through")
	a.battle.phase_active = false
	b.dock = 91
	Contacts.resolve(world,0,{})
	check(a.pos == b.pos,"docked ship does not block a flying ship")
	b.dock = 0
	# Test held shields against a real incoming beam, including their recovery.
	a.pos = Vector2(-85,0)
	b.pos = Vector2(85,0)
	a.heading = 0
	b.heading = PI
	a.battle.motion = Vector2.ZERO
	b.battle.motion = Vector2.ZERO
	for ship: Dictionary in [a,b]:
		Battle.ensure_state(ship)
		ship.battle.system_cd = 30
	for slot in b.fit.weapons.size(): b.fit.weapons[slot] = ""
	b.fit.weapons[0] = "lance_02"
	Battle.ensure_state(b)
	b.heading = (Vector2(a.pos)-Vector2(b.pos)).angle()-deg_to_rad(float(game.Hulls.slot_spec(b.kind,0).facing))
	Battle.train(b,a.pos,2.0)
	check(demo.flight.weapon_threat(b,a),"an armed enemy covering our position is recognized before a shot exists")
	demo.flight._engage_target(a,b,1.0/60.0)
	check(a.battle.shield,"AI raises a usable shield before the first shot")
	Battle.tick(a,0.35,world)
	var hp: float = a.hp
	var flux: float = a.battle.soft_flux
	Battle.train(b,a.pos,2.0)
	check(Battle.fire_slot(world,b,0,a.pos,a.id),"an actual beam fires at the defending ship")
	check(a.hp == hp and a.battle.soft_flux > flux,"raised arc actually absorbs beam damage")
	b.battle.cooldowns.fill(3.0)
	demo.flight._engage_target(a,b,1.0/60.0)
	check(a.battle.shield,"brief gaps between volleys do not flicker the shield")
	a.battle.hard_flux = game.Hulls.capacity(a)*0.92
	demo.flight._engage_target(a,b,1.0/60.0)
	check(not a.battle.shield,"a saturated defender drops the shield")
	var families := {}
	var patterns := {}
	for id in ["rail","howitzer","lance","missile","pulse","pd"]:
		var family: int = Art.profile(id).family
		families[family] = true
		var silhouette := PackedByteArray()
		for y in int(Art.SIZE.y):
			var row: String = Art.PATTERNS[family][y] if y < Art.PATTERNS[family].size() else ""
			for x in int(Art.SIZE.x): silhouette.append(int(x < row.length() and row[x] != "."))
		patterns[silhouette] = true
	check(families.size() == 6 and patterns.size() == 6,"all six weapon families have distinct mount art")
	var bridge = preload("res://agent_bridge.gd").new()
	bridge.game = game
	check(bridge.dispatch("new_game",{"seed":"hull-contact-at-berth"}).ok,"launch campaign from the normal new game command")
	var player_ship: Dictionary = game.world.ride()
	game.world.depart(player_ship)
	player_ship.pos = Vector2(920,890)
	var civilian: Dictionary = game.world.ships[game.world.ship(0,0,0,player_ship.flag,player_ship.system,player_ship.pos)]
	game.speed = 1
	game.galaxy = false
	game.flight.step(1.0/60.0)
	check(Geometry2D.intersect_polygons(outline(player_ship),outline(civilian)).is_empty(),"campaign local flight separates peaceful ships")
	game.free()
	print("Ship contacts and defensive AI ",checks-failures,"/",checks)
	quit(1 if failures else 0)
