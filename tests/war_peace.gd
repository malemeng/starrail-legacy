extends SceneTree

const World = preload("res://world.gd")
const WarPeace = preload("res://scripts/campaign/war_peace.gd")
const StrategicMap = preload("res://scripts/ui/strategic_map.gd")
const SCENE = preload("res://game.tscn")

var checks := 0
var failures := 0

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var world := World.new()
	world.new_game({"seed":"war-peace-test","systems":24,"factions":5,"avatar":{"name":"Test Admiral"}})
	var f0 := 0
	var f1 := 1
	var owned1: Array = world.systems_owned(f1)
	expect(owned1.size() >= 1, "faction 1 owns at least one station")
	if owned1.is_empty():
		quit(1)
		return
	var target_pid := int(owned1[0])
	world.set_treaty(f0, f1, -1)
	var foe_ship := world.ship(0, 0, 0, f1, world.ports[target_pid].system, Vector2.ZERO)
	WarPeace.record_kill(world, world.ships[foe_ship], f0)
	var sc := WarPeace.scores_for(world, f0, f1)
	expect(sc.x > 0.0 and sc.y == 0.0, "naval kill grants war score to victor")

	WarPeace.occupy(world, target_pid, f0)
	expect(int(world.ports[target_pid].flag) == f0 and int(world.ports[target_pid].get("occupied_from", -1)) == f1, "wartime occupation transfers control while preserving original sovereignty")
	expect(world.factions[f1].alive, "occupation does not immediately eliminate faction")

	var preview := WarPeace.preview_peace(world, f0, f1, [target_pid], false)
	expect(preview.valid and preview.accepted, "sufficient war score allows annexing occupied station")

	var game = SCENE.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.set_physics_process(false)
	game.world = world
	world.active().flag = f0
	var map := StrategicMap.new()
	root.add_child(map)
	map.setup(game, "peace", f1)
	map._on_station_clicked(target_pid)
	expect(target_pid in map.annex_selection, "clicking occupied station in peace map toggles annexation")
	map._on_station_clicked(target_pid)
	expect(target_pid in map.release_selection and target_pid not in map.annex_selection, "second click toggles release as free port")
	map._on_station_clicked(target_pid)
	map.queue_free()
	game.queue_free()

	world.people[world.player].flag = f0
	world.people[world.player].merit = 40
	var ok := WarPeace.sign_peace(world, f0, f1, [target_pid], false, [], true)
	expect(ok and not world.hostile(f0, f1) and WarPeace.in_truce(world, f0, f1), "signing peace ends war and establishes 180-day truce")
	expect(not world.ports[target_pid].has("occupied_from") and int(world.ports[target_pid].flag) == f0, "annexed station becomes permanent territory")
	expect(int(world.ports[target_pid].manager) == world.player, "high-merit official receives newly annexed station management")

	# Test station master start (no ship) & joining faction / leader appointment
	var sm_world := World.new()
	sm_world.new_game({"seed":"station-master-test","systems":24,"factions":5,"avatar":{"name":"Manager","station_master":2}})
	expect(sm_world.ride().is_empty() and int(sm_world.active().ship) == 0, "employed station master starts without piloting a ship")
	expect(int(sm_world.active().flag) >= 0 and int(sm_world.ports[sm_world.active().loc].manager) == sm_world.player, "employed station master joins faction and manages assigned station")

	var join_world := World.new()
	join_world.new_game({"seed":"join-appoint-test","systems":24,"factions":5,"avatar":{"name":"Joiner","station_master":0}})
	expect(join_world.disembark() and join_world.ride().is_empty(), "captain can disembark at port")
	expect(join_world.Politics.join_faction(join_world, join_world.player, 1) and int(join_world.active().flag) == 1, "player can join an existing faction")
	var f1_ports := join_world.systems_owned(1)
	if not f1_ports.is_empty():
		var vacant_pid := int(f1_ports[0])
		join_world.ports[vacant_pid].manager = 0
		join_world.Politics.appointments(join_world)
		expect(int(join_world.ports[vacant_pid].manager) == join_world.player, "faction leader appoints shipless faction member as vacant station manager")

	# Test defensive alliance call-to-arms and one-click buy-and-assign station patrol
	var ally_world := World.new()
	ally_world.new_game({"seed":"ally-test","systems":24,"factions":5,"avatar":{"name":"Manager","station_master":1}})
	ally_world.set_treaty(1, 2, 1)
	ally_world.set_treaty(0, 1, -1)
	WarPeace.on_war_declared(ally_world, 0, 1)
	expect(ally_world.hostile(2, 0), "defensive ally joins war against aggressor")
	var home_pid := int(ally_world.active().loc)
	ally_world.active().wallet = 50000
	ally_world.ports[home_pid].hulls[0] = 1
	var patrol_id := ally_world.Economy.buy_and_assign_to_station(ally_world, home_pid, 0, "巡逻")
	expect(patrol_id > 0 and ally_world.ships[patrol_id].job.get("kind", "") == "巡逻", "station master can buy and directly assign patrol ship")

	ally_world.succession = true
	ally_world.player = 0
	expect(ally_world.Politics.new_adventurer(ally_world) and not ally_world.succession and not ally_world.ride().is_empty(), "new_adventurer creates a ship-owning successor in existing universe")

	# Verify agent observe() exposes state.fleet and state.managed_ports even when shipless (station master start)
	var api := preload("res://agent_bridge.gd").new()
	var g2 = SCENE.instantiate()
	g2.test_profile = true
	root.add_child(g2)
	g2.set_physics_process(false)
	api.game = g2
	var ng: Dictionary = api.dispatch("new_game", {"seed": "sm-observe", "role": "independent_manager"})
	var obs: Dictionary = api.dispatch("observe", {})
	expect(ng.ok and obs.ok and obs.state.ship.is_empty() and obs.state.fleet.size() >= 1 and obs.state.managed_ports.size() >= 1, "station master observe() exposes fleet and managed_ports without a flagship")
	g2.queue_free()

	# Test NPC colonization for wealthy peaceful faction
	ally_world.factions[1].treasury = 20000
	ally_world.factions[1].last_colonized = -500
	ally_world.set_treaty(0, 1, 0)
	ally_world.set_treaty(1, 2, 0)
	var before_owned: int = ally_world.systems_owned(1).size()
	ally_world.Politics.npc_colonize(ally_world)
	expect(ally_world.systems_owned(1).size() > before_owned, "wealthy peaceful NPC faction colonizes a new station")

	print("War & Peace checks %d/%d" % [checks - failures, checks])
	quit(1 if failures else 0)
