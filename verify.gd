extends SceneTree

const World = preload("res://world.gd")
const Portrait = preload("res://portrait.gd")
const Economy = preload("res://economy.gd")
const Politics = preload("res://politics.gd")
const Hulls = preload("res://hull_catalog.gd")
const Story = preload("res://frontier.gd")
const Pixels = preload("res://art/pixel_art.gd")
const Battle = preload("res://combat.gd")
const Celestial = preload("res://celestial.gd")
const Flight = preload("res://flight.gd")
const SCENE = preload("res://game.tscn")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("verify")

func check(condition: bool, caption: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", caption)

func press(game, code: Key, shifted: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.shift_pressed = shifted
	game._input(event)

func scenario(seed: String = "anchor", noble: bool = true) -> World:
	var world := World.new()
	world.new_game({"seed": seed, "systems": 24, "factions": 5,
		"avatar": {"name": "沈澜", "house": "断航", "noble": noble}})
	return world

func generation() -> void:
	for dimensions in [Vector2i(12, 3), Vector2i(24, 8), Vector2i(48, 8)]:
		for index in range(10):
			var options := {"seed": str(index), "systems": dimensions.x, "factions": dimensions.y,
				"overrides": [{"name": "曙铁共和国", "style": 2, "color": 5, "regime": 1}]}
			var first := World.new()
			var second := World.new()
			check(first.new_game(options) and second.new_game(options), "valid dimensions and seed")
			check(var_to_bytes(first.snapshot()) == var_to_bytes(second.snapshot()), "deterministic world byte signature")
			check(first.systems.size() == dimensions.x and first.factions.size() == dimensions.y, "world sizes")
			check(first.factions[0].name == "曙铁共和国" and first.factions[0].style == 2 and first.factions[0].regime == 1, "custom politics")
			check(first.local_flag(0) == -1 and first.local_flag(1) == -1 and first.ports[first.systems[1].ports[0]].stock[0] > 100, "protected starter market")
	var invalid := World.new()
	check(not invalid.new_game({"seed": "bad", "systems": 12, "factions": 8}), "impossible density rejected")

func logistics() -> void:
	var world := scenario()
	var vessel := world.ride()
	var home: int = vessel.dock
	var mine: int = world.systems[1].ports[0]
	var refinery: int = world.systems[1].ports[1]
	var start: int = world.active().wallet
	check(world.berth(vessel, mine), "berth at supplier")
	check(Economy.trade(world, mine, 0, 18) == 18, "buy mineral stock")
	check(world.berth(vessel, refinery) and Economy.trade(world, refinery, 0, -18) == -18, "sell at refinery")
	check(world.active().wallet > start, "starter market profitable")
	var yard: Dictionary = world.ports[home]
	var day_index := 0
	world.day = 30
	day_index = (1 + int(yard.id)) % Hulls.MODELS.size()
	while not Hulls.model_limit(yard, day_index):
		day_index = (day_index + 1) % Hulls.MODELS.size()
	yard.stock[1] = 0
	var before: int = yard.hulls[day_index]
	Economy.produce(world, yard)
	check(yard.hulls[day_index] == before, "shipyard stops when out of alloy")
	yard.stock[1] = 150
	Economy.produce(world, yard)
	check(yard.hulls[day_index] > before and yard.stock[1] == 150 - Hulls.MODELS[day_index].recipe, "shipyard consumes actual alloy")
	world.berth(vessel, home)
	var spare := Economy.buy_ship(world, home, 0)
	var workers: Array = world.people.values().filter(func(actor): return actor.loc == home and actor.id != world.player and actor.ship == 0)
	check(spare != 0 and Economy.assign(world, spare, workers.back().id, "贸易", mine, refinery), "hire and assign trader")
	world.tick(96)
	check(world.ships.has(spare) and world.ships[spare].captain == workers.back().id and world.ships[spare].system == 1, "delegated ship has travelled")
	world.active().wallet = 900
	world.depart(vessel)
	var planet: Dictionary = world.systems[0].planets[0]
	vessel.pos = planet.pos + Vector2(planet.radius + 100,0)
	vessel.cargo[1] = 36
	var site := Economy.deploy(world, 1, vessel.pos)
	check(site != 0 and world.berth(vessel, site) and Economy.donate(world, site) == 20, "player funds a construction site")
	world.tick(36)
	check(world.ports[site].build == 0, "material-backed construction completed")
	check(Economy.expand(world, site, 3), "station extension ordered")
	world.tick(36)
	check(world.ports[site].expansion == 0, "station extension completed")
	check(Economy.incorporate(world, site, "曙线精炼") and world.active().shares.has(world.ports[site].firm), "private company registration")
	check(Politics.found(world, "曙线领", site, 0) and world.active().noble, "independent hereditary power")

func player_capture() -> void:
	var world := scenario("capture", false)
	var vessel := world.ride()
	var capital: int = world.factions[0].capital
	var site: Dictionary = world.ports[capital]
	vessel.raid = 0
	check(not world.can_dock(vessel, site) and not world.enemy(vessel, {"flag": 1}), "a neutral raid does not declare war on other powers")
	Politics.conquer(world, site.id, vessel.flag, world.player)
	vessel.raid = World.NEUTRAL
	check(site.owner == world.player and world.active().noble and world.can_dock(vessel, site), "captured territory grants a title and opens its port")

func inheritance() -> void:
	for law in [0, 1]:
		var world := scenario("inheritance")
		var original := world.player
		var home: int = world.active().loc
		var mate: int = world.random_person(-1, home, "冬青")
		world.people[mate].noble = true
		check(Politics.marry(world, original, mate), "noble marriage")
		var heirs: Array = []
		for index in range(3):
			heirs.append(Politics.child(world, original, mate))
		var first: Dictionary = world.people[heirs[0]]
		check(first.parents == [original, mate] and first.noble, "noble kinship persists")
		check(first.look.wear == 3 and first.look.mark == 0, "clothes and scars aren't hereditary")
		first.birth = -30 * 360
		world.people[heirs[1]].birth = -25 * 360
		world.people[heirs[2]].birth = -21 * 360
		var first_station := world.port(0, "主站", Vector2(-200, 0), -1, original, 1)
		var second_station := world.port(0, "次站", Vector2(-420, 0), -1, original, 2)
		var firm := world.incorporate("世产", original, first_station)
		var inherited_ship: int = world.active().ship
		if law == 1:
			check(Politics.change_law(world) and world.people[heirs[1]].opinions[original] == -25, "concentration reduces heirs' opinion")
		Politics.die(world, original)
		check(world.player == first.id and world.ports[first_station].owner == first.id and world.ships[inherited_ship].owner == first.id, "main estate")
		check(world.ports[second_station].owner == (first.id if law else heirs[1]), "partition vs concentration")
		check(first.shares[firm] == 100 and world.firms[firm].director == first.id and first.ship == 0, "shares and appointment")
		if law == 0:
			check(world.people[heirs[2]].wallet > 0, "unlanded child compensated")
	var world := scenario("commoner", false)
	var previous := world.player
	var replacement: int = world.ports[world.active().loc].manager
	var funds: int = world.people[replacement].wallet
	check(not Politics.change_law(world) and not Politics.marry(world, previous, replacement), "commoners don't form dynasties")
	world.day = 240
	var markets: Array = world.ports[world.systems[1].ports[0]].stock.duplicate()
	Politics.die(world, previous)
	check(world.succession and world.player == 0 and Politics.choose(world, replacement), "heirless continuation")
	check(world.player == replacement and world.active().wallet == funds and world.day == 240 and world.ports[world.systems[1].ports[0]].stock == markets, "continuation leaves world and assets intact")
	var regency_world := scenario()
	var guardian: int = regency_world.random_person(-1, regency_world.active().loc, "另一家")
	regency_world.people[guardian].noble = true
	var progenitor := regency_world.player
	Politics.marry(regency_world, progenitor, guardian)
	var minor := Politics.child(regency_world, progenitor, guardian)
	var family_ship: int = regency_world.active().ship
	Politics.die(regency_world, progenitor)
	check(regency_world.player == guardian and regency_world.regency == minor, "living parent is regent")
	check(regency_world.pilot(family_ship) and regency_world.ships[family_ship].owner == minor, "regent can administer heir's assets without acquiring them")
	regency_world.people[minor].birth = -18 * 360
	regency_world.attention = false
	regency_world.tick(30)
	check(regency_world.regency == 0 and regency_world.player == minor, "majority ends regency")
	check(regency_world.ships[family_ship].captain == minor, "berth control returns to adult heir")

func genetic_distribution() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 3799
	var first := {"wear": 1, "mark": 2}
	var second := {"wear": 2, "mark": 3}
	for feature in Portrait.GENES:
		first[feature] = 0
		second[feature] = 1
	var maternal := 0
	var paternal := 0
	var mutation := 0
	var valid := true
	for index in range(400):
		var inherited := Portrait.inherit(first, second, random)
		for feature in Portrait.GENES:
			var value: int = inherited[feature]
			valid = valid and value >= 0 and value < Portrait.OPTIONS[feature].size()
			match value:
				0: maternal += 1
				1: paternal += 1
				_: mutation += 1
	check(valid and maternal > 1200 and paternal > 1200 and mutation > 15 and mutation < 130, "genetics uses both parents and rare bounded mutations")

func corporate_trade() -> void:
	var world := scenario("firms")
	var first_id: int = world.firms.keys()[0]
	var firm: Dictionary = world.firms[first_id]
	var flags := {}
	for station in world.ports.values():
		if station.firm == first_id:
			flags[station.flag] = true
	check(flags.size() >= 2 and flags.has(-1), "megacorporation operates across political borders")
	var branch: int = world.systems[1].ports[1]
	var vessel := world.ride()
	world.berth(vessel, branch)
	vessel.flag = 2
	firm.embargo = 2
	check(Economy.trade(world, branch, 1, 5) == 0 and vessel.cargo[1] == 0, "sanctions deny trade at branch")
	firm.embargo = -1
	check(Economy.trade(world, branch, 1, 5) == 5 and firm.revenue > 0, "restored trade contributes company revenue")

func government_and_wars() -> void:
	var world := scenario("war")
	world.tick(3900)
	check(world.chronicle.any(func(entry): return "被" in entry[1] and "夺取" in entry[1]), "NPC seize stations without player")
	check(world.factions.values().any(func(faction): return not faction.alive), "NPC elimination")
	for seed_index in range(6):
		world = scenario("long-" + str(seed_index), false)
		world.tick(10000)
		check(world.ports.values().all(func(station): return station.stock.all(func(stock): return stock >= 0)), "nonnegative inventory after long simulation")
		check(world.factions.values().all(func(power): return world.people.has(power.leader)), "faction leaders remain valid")
		check(world.people.values().all(func(actor): return actor.noble or (actor.children.is_empty() and actor.parents.is_empty() and actor.spouse == 0)), "NPC commoners do not enter noble genealogies")
	for regime in range(5):
		world = scenario("regime-" + str(regime))
		var power: Dictionary = world.factions[0]
		power.regime = regime
		var chief: int = power.leader
		var chief_data: Dictionary = world.people[chief]
		chief_data.noble = true
		var partner: int = chief_data.spouse
		if partner == 0:
			partner = world.random_person(0, power.capital, "异族")
			world.people[partner].noble = true
			Politics.marry(world, chief, partner)
		var heir := Politics.child(world, chief, partner)
		var officer: int = world.random_person(0, power.capital)
		world.people[officer].wallet = 5000
		world.people[officer].endorsement = 500
		world.people[officer].loyalty = 100
		world.people[officer].origin = 0
		world.ship(2, officer, officer, 0, world.ports[power.capital].system, Vector2.ZERO, power.capital)
		var firm := world.incorporate("控股", officer, power.capital)
		check(world.people[officer].shares[firm] == 100, "voting shares")
		Politics.die(world, chief)
		check(power.leader == heir if regime == 0 else power.leader == officer, "regime-specific leadership: " + str(regime))

func ui_flow() -> void:
	var game = SCENE.instantiate()
	game.test_profile = true
	root.add_child(game)
	await process_frame
	game.creator.name.text = "外貌验证"
	game.creator.seed.text = "航线验收"
	game.creator.noble.select(1)
	var eye: Dictionary = game.creator.inputs[5]
	eye.node.select(3)
	eye.node.item_selected.emit(3)
	check(game.portrait.look.iris == 3, "creator updates live portrait")
	game.start_game()
	await process_frame
	var world: World = game.world
	check(game.playing and world.active().look.iris == 3 and world.active().noble, "custom character enters actual game scene")
	check(game.dock_view.stage.visible and not game.canvas.visible, "docked player sees port scene rather than flight map")
	game.dock_view.talk(world.ports[Story.origin(world)].manager)
	await process_frame
	check(game.dock_view.rendered == "talk" and game.dock_view.contact_id != 0, "port contact has an actual conversation scene")
	game.dock_view.mode = "yard"
	game.dock_view.model_id = 8
	game.refresh()
	await process_frame
	check(game.dock_view.rendered == "yard", "capital hull preview reachable at ordinary shipyard")
	var vessel := world.ride()
	var origin: Vector2 = vessel.pos
	var home: int = vessel.dock
	var team: Array = []
	for index in range(2):
		var captain := world.random_person(world.NEUTRAL,home)
		var member := world.ship(0,world.player,captain,world.NEUTRAL,vessel.system,origin,home)
		check(Economy.assign(world,member,captain,"护航"),"assign captain to escort")
		team.append(member)
	game.flight.dock()
	check(team.all(func(member): return world.ships[member].dock == 0),"two escorts depart with flagship")
	game.set_speed(1)
	Input.action_press(&"left")
	for index in range(35):
		game.flight.step(1.0 / 60.0, Vector2.LEFT)
	Input.action_release(&"left")
	check(vessel.dock == 0 and vessel.pos.x < origin.x - 80, "live movement input")
	check(game.canvas.visible and not game.dock_view.stage.visible, "departure restores flight stage")
	var gravity := Celestial.gravity_point(world.systems[0])
	var fuel: float = vessel.fuel
	var coordinates: Vector2 = vessel.galpos
	game.flight.change_layer()
	check(not game.galaxy and not vessel.layer and vessel.fuel == fuel and vessel.galpos == coordinates,"open space cannot jump or spend fuel")
	vessel.pos = gravity + Vector2(Celestial.JUMP_RANGE + 1.0,0)
	game.flight.change_layer()
	check(not game.galaxy,"jump is forbidden immediately outside gravity point radius")
	vessel.pos = gravity
	vessel.locked = true
	game.flight.change_layer()
	check(not game.galaxy,"combat blocks jump even at gravity point center")
	vessel.locked = false
	vessel.pos = gravity + Vector2(Celestial.JUMP_RANGE,0)
	game.flight.change_layer()
	check(game.galaxy and vessel.layer, "exact gravity point radius permits hyperspace entry")
	vessel.galpos = Vector2(2500,2500)
	game.flight.change_layer()
	check(game.galaxy and vessel.system == 0,"hyperspace exit requires a system beacon")
	vessel.galpos = world.systems[1].pos
	game.flight.change_layer()
	check(not game.galaxy and world.systems[1].seen and vessel.pos == Celestial.gravity_point(world.systems[1]), "system arrival uses destination gravity point")
	check(team.all(func(member): return world.ships[member].system == 1 and not world.ships[member].layer),"escorts travel across star systems")
	press(game, KEY_TAB)
	check(game.tactics.visible, "Tab opens the tactical order bar")
	press(game, KEY_TAB)
	check(not game.tactics.visible, "Tab closes the tactical order bar")
	game.tactics_button.pressed.emit()
	check(game.tactics.visible,"mouse tactical button opens the same bar")
	game.tactics_button.pressed.emit()
	press(game, KEY_2)
	check(vessel.battle.group == 2, "2 selects weapon group")
	press(game, KEY_2, true)
	check(vessel.fit.auto[1], "Shift+2 enables group auto targeting")
	press(game, KEY_2, true)
	press(game, KEY_1)
	check(not vessel.fit.auto[1] and vessel.battle.group == 1, "Shift+2 toggles autofire back off; 1 selects main guns")
	press(game, KEY_F)
	check(vessel.battle.system_time > 0.0 and vessel.battle.soft_flux > 0.0, "F activates the flagship system")
	press(game, KEY_V)
	check(vessel.battle.vent and not vessel.battle.shield, "V initiates venting")
	Battle.tick(vessel, 2.0)
	vessel.pos = Vector2(-20,100)
	var threat: int = game.flight.target(vessel,350.0)
	check(threat != 0 and game.flight.issue(2,threat) == 2 and team.all(func(member): return world.ships[member].battle.focus == threat),"focus attack dispatches to both escorts")
	check(game.flight.issue(2,team[0]) == 0,"friendly or vanished target cannot receive focus order")
	check(game.flight.issue(0) == 2 and game.flight.issue(1) == 2,"free attack and guard switch both escorts")
	check(game.flight.issue(3) == 2,"withdraw requests reach every escort")
	for index in range(team.size()):
		var member: Dictionary = world.ships[team[index]]
		member.pos = vessel.pos + Vector2(-620, -40 + index*80)
		game.flight.drive_ai(member,vessel,1.0/60.0)
		check(member.battle.retired and not Battle.available(member,vessel.system),"withdrawn escort leaves active encounter")
	vessel.pos = Celestial.gravity_point(world.systems[1])
	game.flight.change_layer()
	check(game.galaxy, "withdrawal does not prevent the flagship's next jump")
	game.flight.change_layer()
	check(team.all(func(member): return not world.ships[member].battle.retired and world.ships[member].battle.order == 1),"withdrawn ships regroup on the next system entry")
	for index in range(team.size()):
		var member: Dictionary = world.ships[team[index]]
		member.pos = Vector2(-1000, 620 + index * 50)
	vessel.pos = Vector2(-20, 100)
	game.flight.auto_battle()
	check(not world.ships.values().any(func(other): return other.system == 1 and other.flag == world.RAIDERS), "automatic battle destroys its opponent")
	var npc := world.random_person(-2, 0)
	var enemy := world.ship(0, 0, npc, -2, 1, vessel.pos + Vector2(155, 0))
	world.ships[enemy].hp = 16
	world.ships[enemy].battle.armor = 0.0
	vessel.heading = 0.0
	press(game, KEY_1, true)
	game.flight.combat(vessel, 0.001)
	check(world.projectiles.any(func(shot): return shot.ship == vessel.id), "autofire launches a real projectile without mouse input")
	press(game, KEY_1, true)
	for index in range(35):
		Battle.project(world, vessel.system, 1.0 / 60.0)
	check(not world.ships.has(enemy), "projectile collision resolves battle in the world")
	game.tab = "资产"
	game.refresh()
	await process_frame
	game.tab = "人物"
	game.refresh()
	await process_frame
	game.tab = "疆域"
	game.refresh()
	await process_frame
	vessel.locked = false
	vessel.battle.hard_flux = 21.0
	vessel.battle.soft_flux = 13.0
	vessel.battle.armor = 19.0
	vessel.battle.motion = Vector2(12,24)
	check(game.flight.select_group(vessel,2,true) and vessel.fit.auto[1],"group autofire mode persists in fitting")
	check(game.save_game("user://verification.save", true), "write save")
	var saved := var_to_bytes(world.snapshot())
	world.active().wallet = 0
	check(game.load_game("user://verification.save") and saved == var_to_bytes(world.snapshot()), "same universe persists exactly")
	check(world.ride().battle.hard_flux == 21.0 and world.ride().battle.armor == 19.0 and world.ride().fit.auto[1],"combat persistence retains flux, armor and group modes")
	game.queue_free()
	await process_frame

func frontier_catalog() -> void:
	var world := scenario()
	var vessel := world.ride()
	var home := Story.origin(world)
	var destination := Story.foundry(world)
	check(Story.accept(world) and not Story.accept(world), "optional first contract cannot be duplicated")
	vessel.cargo[0] = 7
	check(world.berth(vessel, destination) and not Story.deliver(world), "needs entire shipment at foundry")
	vessel.cargo[0] = 8
	var opening_cash: int = world.active().wallet
	var existing_ore: int = world.ports[destination].stock[0]
	var contact: int = world.ports[destination].manager
	check(Story.deliver(world) and not Story.deliver(world), "delivery pays once")
	check(vessel.cargo[0] == 0 and world.ports[destination].stock[0] == existing_ore + 8 and world.active().wallet == opening_cash + 210, "first delivery changes existing economy")
	check(world.people[contact].opinions[world.player] == 16 and world.berth(vessel, home) and Story.return_to_port(world) and not Story.return_to_port(world), "delivery changes NPC opinion and unlocks one return stipend")
	check(Hulls.CLASS_NAMES.size() == 4 and Hulls.MODELS.size() >= 50 and Hulls.WEAPONS.size() >= 80, "four volume classes and expanded ship/weapon catalogs")
	for size in range(4):
		check(Hulls.MODELS.filter(func(model): return model.size == size).size() >= 2, "each hull class has multiple roles")
	check(not world.can_dock({"kind": 7, "flag": -1}, world.ports[home]), "freeport cannot dock a capital")
	var heavy_port: Dictionary = world.ports[world.factions[0].capital]
	check(Hulls.station_limit(heavy_port) == Hulls.Size.CAPITAL, "designated dock supports capital ships")
	var old := world.snapshot().duplicate(true)
	old.erase("save_version")
	old.version = 3
	for station in old.ports.values():
		station.hulls = station.hulls.slice(0, 3)
		station.stock = station.stock.slice(0, 3)
		station.erase("capital_yard")
		station.erase("pop")
	for ship in old.ships.values():
		ship.erase("battle")
		ship.erase("fit")
		ship.erase("crew")
		ship.cargo = ship.cargo.slice(0,3)
	var loaded := World.new()
	check(loaded.load_state(old) and loaded.ports[home].hulls.size() == Hulls.MODELS.size() and loaded.player == world.player and loaded.rng.state == world.rng.state, "v3 save migrates without remapping hulls or RNG")
	check(loaded.ride().battle.armor == Hulls.COMBAT[loaded.ride().kind].armor and loaded.ride().cargo.size() == 7 and loaded.ports[home].pop > 0,"migration refills old ship and station fields")
	var hashes := {}
	for model in range(Hulls.MODELS.size()):
		var sprite := Pixels.hull(model, Pixels.AMBER)
		check(sprite.get_size() == Vector2i(64, 40) and sprite.get_pixel(0, 0).a == 0.0, "hull sprite dimensions and transparency")
		hashes[hash(sprite.get_data())] = true
	check(hashes.size() == Hulls.MODELS.size(), "every ship model has a distinct pixel sprite")

func combat_edges() -> void:
	var world := scenario("combat")
	var vessel := world.ride()
	for kind in range(Hulls.MODELS.size()):
		var spec: Dictionary = Hulls.COMBAT[kind]
		check(spec.slots.size() in range(2,6) and Hulls.fitting_cost(kind,Hulls.stock_fit(kind)) >= 0, "stock slots and OP valid for hull %d" % kind)
	var state: Dictionary = vessel.battle
	var record: Dictionary = vessel.fit.duplicate(true)
	record.weapons[0] = "lance"
	check(not world.outfit(vessel.id, record), "heavy weapon rejected on small slot")
	record = vessel.fit.duplicate(true)
	record.caps = 12
	record.vents = 12
	check(not world.outfit(vessel.id, record), "OP ceiling enforced")
	record = vessel.fit.duplicate(true)
	record.caps = 2
	check(world.outfit(vessel.id, record) and is_equal_approx(Hulls.capacity(vessel),110), "valid fit changes capacity")
	Battle.shield(vessel,true)
	var armor: float = state.armor
	Battle.hit(world,vessel,20,0,vessel.pos,Vector2.RIGHT)
	check(state.hard_flux == 40.0 and state.armor == armor,"kinetic shield multiplier")
	Battle.add_flux(world,vessel,24)
	Battle.tick(vessel,0.5)
	check(state.hard_flux == 40.0 and state.soft_flux == 12.0,"raised shield traps hard flux and permits soft flux recovery")
	check(Battle.vent(vessel) and not state.shield and not Battle.ready(vessel),"V disables weapon and shield")
	Battle.tick(vessel,0.5)
	check(state.hard_flux == 16.0,"vent drains at twice normal rate")
	Battle.tick(vessel,2.0)
	check(not state.vent and state.hard_flux == 0.0 and state.soft_flux == 0.0,"vent ends at zero flux")
	Battle.shield(vessel,true)
	Battle.hit(world,vessel,219,1,vessel.pos,Vector2.RIGHT)
	check(state.hard_flux == 109.5 and state.armor == armor and state.overload == 0.0,"HE shield multiplier")
	Battle.hit(world,vessel,12,1,vessel.pos,Vector2.RIGHT)
	check(state.overload == 3.0 and not state.shield and is_equal_approx(state.armor,armor-22.0),"shield overflow consumes only unabsorbed HE")
	Battle.tick(vessel,2.99)
	check(not Battle.ready(vessel) and not Battle.vent(vessel) and not Battle.system(world,vessel,Vector2.RIGHT),"overload denies systems and vent before three seconds")
	Battle.add_flux(world,vessel,60)
	check(state.overload < 0.02,"overload cannot be refreshed by flux external calls")
	Battle.tick(vessel,0.02)
	check(Battle.ready(vessel),"weapons unlock after three seconds")
	Battle.tick(vessel,6)
	state.armor = 4.0
	var hp: float = vessel.hp
	Battle.hit(world,vessel,20,0,vessel.pos,Vector2.RIGHT)
	check(is_equal_approx(vessel.hp,hp-12.0) and state.armor == 0.0 and vessel.crew < Hulls.crew_limits(vessel.kind).x,"kinetic armor then hull with casualties")
	vessel.heading = 0.0
	check(not Battle.can_aim(vessel,0,vessel.pos+Vector2(-100,0),350),"fixed hardpoint cannot fire aft")
	check(Battle.can_aim(vessel,2,vessel.pos+Vector2(-100,0),118),"turret can aim behind")
	check(Battle.system(world,vessel,Vector2.RIGHT) and not Battle.system(world,vessel,Vector2.RIGHT),"active system consumes flux and has cooldown")
	check(not Battle.fire_slot(world,vessel,2,vessel.pos+Vector2.RIGHT*30.0),"PD does not consume manual fire group")
	var missile := {"missile":true,"hp":7.0,"system":vessel.system,"flag":world.RAIDERS,"raid":world.NEUTRAL,"pos":vessel.pos+Vector2(-65,0),"vel":Vector2.RIGHT}
	world.projectiles.append(missile)
	missile.vel = Vector2.LEFT
	Battle.point_defense(world,vessel)
	check(missile.hp == 7.0, "point defense does not target a departing missile")
	missile.vel = Vector2.RIGHT
	Battle.point_defense(world,vessel)
	check(missile.hp <= 0.0 and state.cooldowns[2] > 0.0,"PD intercepts incoming hostile missile")
	Battle.project(world,vessel.system,0.01)
	check(world.projectiles.is_empty(),"intercepted missile is removed before impact")
	check(Battle.ai_mode(vessel,280) == "压进" and Battle.ai_mode(vessel,120) == "侧翼拉扯","AI changes approach by range")
	state.hard_flux = 90.0
	check(Battle.ai_mode(vessel,280) == "降盾散热","high flux chooses disengagement")
	state.hard_flux = 50.0
	state.ai = "降盾散热"
	check(Battle.ai_mode(vessel,280) == "降盾散热","cooling has hysteresis instead of oscillating at threshold")
	state.hard_flux = 40.0
	state.soft_flux = 0.0
	check(Battle.ai_mode(vessel,280) == "压进","cooled ship resumes approach")
	var phase_ship: Dictionary = world.ships[world.ship(4,0,0,world.NEUTRAL,vessel.system,Vector2.ZERO)]
	check(Battle.system(world,phase_ship,Vector2.RIGHT) and phase_ship.pos.x == 86.0,"phase system moves ship forward")
	var phase_armor: float = phase_ship.battle.armor
	Battle.hit(world,phase_ship,40,1,phase_ship.pos,Vector2.RIGHT)
	check(phase_ship.battle.armor == phase_armor,"phase window avoids incoming damage")
	Battle.tick(phase_ship,1.0)
	Battle.hit(world,phase_ship,40,1,phase_ship.pos,Vector2.RIGHT)
	check(phase_ship.battle.armor == 0.0 and phase_ship.hp < Hulls.MODELS[4].hp,"HE armor multiplier applies after phase ends")
	var repairs: Dictionary = world.ships[world.ship(3,0,0,world.NEUTRAL,vessel.system,Vector2.ZERO)]
	repairs.hp -= 30.0
	repairs.battle.armor = 0.0
	Battle.system(world,repairs,Vector2.RIGHT)
	Battle.tick(repairs,1.0)
	check(repairs.battle.armor == 12.0 and repairs.hp == Hulls.MODELS[3].hp-26.0,"repair system restores armor and hull")
	var burst: Dictionary = world.ships[world.ship(2,0,0,world.NEUTRAL,vessel.system,Vector2.ZERO)]
	burst.heading = 0.0
	Battle.system(world,burst,Vector2.RIGHT)
	check(Battle.fire_slot(world,burst,0,Vector2(100,0)) and burst.battle.cooldowns[0] < Hulls.WEAPONS.rail.cool,"burst system reduces weapon cooldown")

func combat_run() -> void:
	var world := scenario("repeatable-duel")
	var game = SCENE.instantiate()
	game.world = world
	var flight := Flight.new()
	flight.game = game
	game.speed = 1
	var vessel := world.ride()
	world.depart(vessel)
	vessel.pos = Vector2.ZERO
	vessel.heading = 0.0
	var enemy_id := world.ship(0,0,0,world.RAIDERS,vessel.system,Vector2(245,0))
	var hostile: Dictionary = world.ships[enemy_id]
	hostile.battle.hard_flux = 95.0
	hostile.battle.shield = true
	vessel.locked = true
	var distance_before: float = hostile.pos.distance_to(vessel.pos)
	flight.drive_ai(hostile,vessel,0.125)
	check(hostile.pos.distance_to(vessel.pos) > distance_before and hostile.battle.vent and not hostile.battle.shield,"AI backs away and vents with high hard flux")
	vessel.locked = false
	world.ships.erase(enemy_id)
	for index in range(36):
		flight.step(1.0 / 60.0,Vector2.RIGHT)
	var normal_speed: float = vessel.battle.motion.length()
	check(Battle.system(world,vessel,Vector2.RIGHT),"boost fires on a moving flagship")
	for index in range(36):
		flight.step(1.0 / 60.0,Vector2.RIGHT)
	check(vessel.battle.motion.length() > normal_speed * 1.4,"boost measurably raises forward speed")
	flight.game = null
	game.free()

func old_combat_saves() -> void:
	var world := scenario("versions")
	for version in [4,5]:
		var raw := world.snapshot().duplicate(true)
		raw.erase("save_version")
		raw.version = version
		var original: Dictionary = raw.ships[world.ride().id]
		if version == 4:
			original.erase("fit")
			original.erase("battle")
		else:
			original.fit.caps = 3
			original.battle.hard_flux = 17.0
			original.battle.erase("motion")
		var restored := World.new()
		check(restored.load_state(raw) and restored.snapshot().save_version == World.VERSION,
			"legacy v%d receives current save version" % version)
		check(restored.ride().battle.motion == Vector2.ZERO and restored.ride().fit.caps == (3 if version == 5 else 0) and restored.ride().battle.hard_flux == (17.0 if version == 5 else 0.0),
			"legacy v%d preserves present combat fields and fills missing fields" % version)
	var future := world.snapshot().duplicate(true)
	future.save_version = World.VERSION + 1
	check(not world.load_state(future),"unknown newer save version is rejected without migration")

func outfitting_and_audio() -> void:
	var world := scenario("refit-audio")
	var vessel: Dictionary = world.ride()
	var port_id: int = vessel.dock
	var station: Dictionary = world.ports[port_id]
	var pub_weapons := Economy.station_weapons(world, station, false)
	var blk_weapons := Economy.station_weapons(world, station, true)
	check(pub_weapons.size() >= 6 and blk_weapons.size() >= 8, "station generates deterministic open and black weapon markets")
	check(Economy.station_weapons(world, station, false) == pub_weapons, "weapon market selection is deterministic for same seed/day")
	world.credit(world.player, 1000)
	var old_weapon: String = vessel.fit.weapons[0]
	check(Economy.refit_slot(world, port_id, 0, "", false), "unequipping a weapon slot succeeds and refunds trade-in value")
	check(vessel.fit.weapons[0].is_empty(), "slot 0 is empty after unequip")
	check(Economy.refit_slot(world, port_id, 0, old_weapon, false), "re-equipping a valid weapon from station stock succeeds")
	check(Economy.refit_tuning(world, port_id, 1, 1), "adding capacitor and vent points within OP succeeds")
	check(vessel.fit.caps == 1 and vessel.fit.vents == 1, "tuning updates ship fit caps and vents")
	check(Economy.refit_group(world, port_id, 0, 2) and vessel.fit.groups[0] == 2, "weapon group reassignment updates slot group")
	var AudioSys = preload("res://audio.gd")
	var wav: AudioStreamWAV = AudioSys.synth_tone(0.05, 440.0, 220.0, 0.25, 0.1, "sine")
	check(wav != null and wav.data.size() > 0, "procedural audio synthesizes non-empty 16-bit PCM WAV stream")

func verify() -> void:
	generation()
	logistics()
	player_capture()
	inheritance()
	genetic_distribution()
	corporate_trade()
	frontier_catalog()
	combat_edges()
	combat_run()
	old_combat_saves()
	outfitting_and_audio()
	government_and_wars()
	await ui_flow()
	print("Verification: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)
