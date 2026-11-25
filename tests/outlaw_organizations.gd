extends SceneTree

const Game = preload("res://game.gd")
const Agent = preload("res://agent_bridge.gd")
const World = preload("res://world.gd")
const Battle = preload("res://combat.gd")
const Celestial = preload("res://celestial.gd")
const Outlaws = preload("res://scripts/campaign/outlaws.gd")
const Saves = preload("res://scripts/services/save_manager.gd")
var checks := 0
var failures := 0

func check(ok: bool, description: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", description)
	return ok

func _initialize() -> void:
	run.call_deferred()

func waypoint(game, point: Vector2) -> bool:
	game.set_waypoint(point)
	game.set_speed(1)
	for tick in range(2500):
		game.step_simulation(Vector2.ZERO, false, false, Vector2.ZERO, false)
		if not game.waypoint_live:
			return true
		if game.speed == 0 or game.world.ride().locked:
			return false
	return false

func journey(game, site: Dictionary) -> void:
	var world = game.world
	var lead: Dictionary = world.ride()
	game.flight.dock()
	if not check(waypoint(game, Celestial.gravity_point(world.systems[lead.system])), "leave the home port and reach its gravity point"):
		return
	game.flight.change_layer()
	if not check(game.galaxy and waypoint(game, world.systems[site.system].pos), "fly normally to the advertised base system of " + site.id):
		return
	game.flight.change_layer()
	check(not game.galaxy and lead.system == site.system, "cross into the organization's system")
	game.set_speed(1)
	var acquired := false
	var reacted := false
	for tick in range(2500):
		var target: Dictionary = {}
		var nearest := INF
		for id: int in world.systems[site.system].outlaw_base.members:
			if not world.ships.has(id):
				continue
			var other: Dictionary = world.ships[id]
			var distance: float = other.pos.distance_to(lead.pos)
			if distance < nearest:
				target = other
				nearest = distance
		if target.is_empty() or world.player == 0 or not world.ships.has(lead.id):
			break
		game.step_simulation(lead.pos.direction_to(target.pos), true, false, target.pos, true)
		acquired = acquired or (game.flight.visible_contact(lead,target) and game.flight.target_at(lead,target.pos) == target.id and world.enemy(lead,target))
		reacted = reacted or target.battle.get("target_id", 0) == lead.id
		if acquired and reacted:
			break
	check(acquired, "sensors and targeting acquire a naturally generated " + site.name + " hull")
	check(reacted, "approaching its patrol draws a real combat response from " + site.name)

func tactics(game, reports: Dictionary) -> void:
	var world = game.world
	for group: String in reports:
		var report: Dictionary = reports[group]
		var base: Dictionary = world.systems[report.system].outlaw_base
		var patrol: Dictionary = world.ships[base.members[0]]
		Battle.ensure_state(patrol)
		# Isolate the two contacts from existing traffic while retaining the real hull, AI and allegiance.
		var arena := Vector2(3500, 2200)
		patrol.pos = arena
		patrol.job.anchor = arena
		var first: int = world.ship(0, 0, 0, world.NEUTRAL, report.system, arena + Vector2.RIGHT*75.0)
		var second: int = world.ship(0, 0, 0, world.NEUTRAL, report.system, arena + Vector2.UP*105.0)
		var loaded: Dictionary = world.ships[second]
		loaded.cargo[0] = world.HULL_CARGO[loaded.kind]
		if group == Outlaws.PIRATES:
			check(game.flight.ai_target(patrol,490) == second, "raiders choose a loaded ship over a nearer empty ship")
		else:
			check(game.flight.ai_target(patrol,490) == first, "cult guard challenges the nearest intruder inside its shrine")
			var radius := float(Outlaws.groups[group].guard_radius)
			patrol.pos = arena + Vector2.RIGHT * (radius - 15.0)
			world.ships[first].pos = arena + Vector2.RIGHT * (radius + 15.0)
			loaded.pos = arena + Vector2.RIGHT * (radius + 25.0)
			check(game.flight.ai_target(patrol,490) == 0, "the cult drops even a cached target that leaves the shrine boundary")

func support(world, reports: Dictionary) -> void:
	var pirate: Dictionary = world.systems[reports[Outlaws.PIRATES].system].outlaw_base
	var member: Dictionary = world.ships[pirate.members[0]]
	var wreck_id: int = world.next_id
	var scrap_ware := 1
	world.wreck(member.system, member.pos, 11, 0)
	var saved_stock: int = pirate.stock[scrap_ware]
	world.tick(6)
	var wreck: Dictionary = world.wrecks[wreck_id]
	var carried := 0
	for id: int in pirate.members:
		carried += int(world.ships[id].cargo[scrap_ware])
	check(wreck.stock[scrap_ware] < 11 and carried + pirate.stock[scrap_ware] - saved_stock + wreck.stock[scrap_ware] == 11,
		"offscreen pirates transfer real material out of a wreck into their holds or depot")
	var cult_report: Dictionary = reports[Outlaws.CULT]
	var base: Dictionary = world.systems[cult_report.system].outlaw_base
	var lost: int = base.members[0]
	world.destruction(lost)
	world.tick(6)
	var deadline: int = base.next_muster
	check(deadline > world.day and not world.ships.has(lost), "a lost patrol leaves a vacancy and a future replacement date")
	var path := OS.get_temp_dir().path_join("starrail-outlaws-%d-%d.save" % [OS.get_process_id(),Time.get_ticks_usec()])
	var restored := World.new()
	if not check(Saves.write(world,path,false) and Saves.read(restored,path), "restart from a save containing actual outlaw activity"):
		return
	DirAccess.remove_absolute(path)
	var new_site: Dictionary = restored.systems[cult_report.system].outlaw_base
	var new_pirate: Dictionary = restored.systems[reports[Outlaws.PIRATES].system].outlaw_base
	check(new_site.next_muster == deadline and new_site.pos == base.pos and new_pirate.stock == pirate.stock and restored.wrecks[wreck_id].stock == wreck.stock,
		"readback preserves both bases, looted cargo and the pending loss")
	restored.tick(deadline - restored.day - 1)
	check(new_site.members[0] == lost and not restored.ships.has(lost), "no early replacement across a reload")
	restored.tick(7)
	var member_id: int = new_site.members[0]
	check(member_id != lost and Outlaws.on_roster(restored,member_id,Outlaws.CULT) and new_site.members.size() == cult_report.capacity and new_site.reserve == base.reserve - 1,
		"one new cult ship fills the vacancy at its original base")
	for spare in range(new_site.reserve):
		restored.destruction(new_site.members[0])
		restored.tick(int(Outlaws.groups[Outlaws.CULT].rebuild_days) + 12)
	var final_member: int = new_site.members[0]
	restored.destruction(final_member)
	restored.tick(int(Outlaws.groups[Outlaws.CULT].rebuild_days) + 12)
	check(new_site.reserve == 0 and not restored.ships.has(final_member) and not Outlaws.on_roster(restored,new_site.members[0],Outlaws.CULT),
		"destroying the reserve ends reinforcement without creating free ships")

func run() -> void:
	var game := Game.new()
	game.test_profile = true
	root.add_child(game)
	game.set_physics_process(false)
	var api := Agent.new()
	api.game = game
	check(api.dispatch("new_game", {"seed":"outlaw-routes","systems":12,"factions":3}).ok, "start a normal civilian voyage")
	var world = game.world
	var opening: Dictionary = world.snapshot()
	var reports := {}
	for site: Dictionary in Outlaws.summary(world):
		reports[site.id] = site
	if check(reports.has(Outlaws.PIRATES) and reports.has(Outlaws.CULT), "both organizations generate in the same campaign"):
		check(reports[Outlaws.PIRATES].system != reports[Outlaws.CULT].system and reports.values().all(func(s): return s.system >= 2 and s.active == s.capacity),
			"each organization starts with a distinct frontier base and an actual complement")
		check(not world.ships.values().any(func(s): return s.system == 0 and world.enemy(s, world.ride())), "starter port has no hostile ships")
		for site: Dictionary in reports.values():
			check(world.load_state(opening), "restart the original saved voyage")
			game.run_bridge()
			journey(game, site)
		world.load_state(opening)
		game.run_bridge()
		tactics(game, reports)
		world.load_state(opening)
		support(world, reports)
	game.free()
	print("Outlaw organizations %d/%d" % [checks - failures,checks])
	quit(0 if failures == 0 else 1)
