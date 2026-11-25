extends SceneTree

const World = preload("res://world.gd")
const Game = preload("res://game.gd")
const Bridge = preload("res://agent_bridge.gd")
const Society = preload("res://scripts/campaign/society.gd")
const EventEngine = preload("res://scripts/campaign/event_engine.gd")
const Ops = preload("res://scripts/campaign/operations.gd")
const Industry = preload("res://scripts/economy/industry.gd")
const Politics = preload("res://politics.gd")
const Celestial = preload("res://celestial.gd")
const ModRegistry = preload("res://scripts/fleet/mod_registry.gd")
const BRIBE := "frontier.smuggler_bribe"
const PRIZE := "frontier.prize_watch"
var passed := 0
var failed := 0

func check(ok: bool, caption: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error(caption)

func scenario() -> World:
	var world := World.new()
	world.new_game({"seed": "event-ports", "systems": 12, "factions": 3, "avatar": {"name": "关澜", "noble": true}})
	return world

func _initialize() -> void:
	call_deferred("run")

func inspection() -> Dictionary:
	var world := scenario()
	var actor := world.active()
	var ship := world.ride()
	var site: Dictionary = world.ports[ship.dock]
	var context := {"vessel": ship.id, "port": site.id, "manager": site.manager}
	var row: Dictionary = Society.entries[BRIBE]
	actor.wallet = 150
	actor.suspicion = 18
	actor.stats.intrigue = 8
	actor.personality.greed = -5
	ship.cargo[Industry.Ware.LUXURY] = 1
	check(EventEngine.weight(world, context, row) == 0, "contraband quantity gates inspection")
	ship.cargo[Industry.Ware.LUXURY] = 2
	actor.suspicion = 14
	check(EventEngine.weight(world, context, row) == 0, "suspicion gates inspection independently of cargo")
	actor.suspicion = 18
	check(EventEngine.weight(world, context, row) == 12, "base inspection weight")
	actor.personality.greed = 2
	check(EventEngine.weight(world, context, row) == 30, "greed multiplies weight")
	actor.stats.intrigue = 12
	check(is_equal_approx(EventEngine.weight(world, context, row), 12.0), "multiple modifiers multiply including fractional weights")
	world.depart(ship)
	check(world.berth(ship, site.id), "ship berths at the inspected port")
	var event := Society.pending(world)
	check(event.get("id", "") == BRIBE and site.name in event.body and world.name_of(site.manager) in event.body, "real regular berth produces inspection naming original contacts")
	check(event.options.size() == 4 and not event.options[1].enabled and not event.options[1].reason.is_empty(), "missing hook is explained at offer time")
	return world.snapshot()

func resolutions(snapshot: Dictionary) -> void:
	var world := World.new()
	check(world.load_state(snapshot), "load pending inspection with its source ship, port and manager")
	var actor := world.active()
	var manager: Dictionary = world.people[world.ports[actor.loc].manager]
	var saved: Dictionary = world.campaign.events[actor.id][0]
	check(Society.pending(world).id == BRIBE and saved.context.port == actor.loc, "saved encounter retains scope")
	var initial: int = actor.wallet
	check(Society.decide(world, BRIBE, 0) and actor.wallet == initial - 65 and actor.suspicion == 3, "bribe deducts promised sum and reduces suspicion")
	check(actor.secrets.back().kind == "bribery" and manager.hooks.has(actor.id) and manager.hooks[actor.id].strength == 1, "port manager gains a real hook")
	check(not Society.decide(world, BRIBE, 0) and actor.wallet == initial - 65, "one settlement per event")
	var home: int = actor.loc
	world.day += 1
	world.depart(world.ride())
	actor.suspicion = 25
	world.berth(world.ride(), home)
	check(Society.pending(world).is_empty() and world.campaign.last_event[actor.id][BRIBE] == saved.day, "returning next day does not repeat an inspection")
	world.load_state(snapshot)
	actor = world.active()
	manager = world.people[world.ports[actor.loc].manager]
	actor.wallet = 64
	check(not Society.pending(world).options[0].enabled and not Society.decide(world, BRIBE, 0) and actor.wallet == 64, "insufficient credit rejected without mutation")
	actor.hooks[manager.id] = {"kind": "bribery", "strength": 1, "expires": world.day - 1}
	check(not Society.decide(world, BRIBE, 1), "expired hook rejected")
	actor.hooks[manager.id].expires = world.day + 1
	var opinion: int = manager.opinions.get(actor.id, 0)
	check(Society.decide(world, BRIBE, 1) and not actor.hooks.has(manager.id) and manager.opinions[actor.id] == opinion - 15 and actor.suspicion == 0, "valid hook spent against the scoped manager")
	world.load_state(snapshot)
	var ship := world.ride()
	ship.cargo[Industry.Ware.LUXURY] = 1
	check(not Society.decide(world, BRIBE, 2) and ship.cargo[Industry.Ware.LUXURY] == 1, "cargo gate rechecked immediately before confiscation")
	world.depart(ship)
	check(Society.pending(world).is_empty() and not Society.decide(world, BRIBE, 0) and world.active().wallet == initial, "leaving port clears the inspection without deducting money or choosing an outcome")
	check(world.load_state(snapshot), "restore inspection again to exercise a change of port manager")
	world.ports[world.active().loc].manager = 0
	check(Society.pending(world).is_empty(), "departed port manager cannot keep an obsolete inspection open")

func queue_scope(snapshot: Dictionary) -> void:
	var world := World.new()
	world.load_state(snapshot)
	var ship := world.ride()
	var kind := World.Hulls.MODELS.find_custom(func(model): return model.crew_max >= 12)
	var first := world.ship(kind, world.player, 0, ship.flag, ship.system, ship.pos)
	var second := world.ship(kind, world.player, 0, ship.flag, ship.system, ship.pos)
	world.ships[first].crew = 1
	world.ships[second].crew = 4
	var label: String = world.HULLS[kind]
	Society.offer(world, "on_ship_captured", {"prize": first, "ship_name": label})
	world.day += 31
	Society.offer(world, "on_ship_captured", {"prize": second, "ship_name": label})
	check(world.campaign.events[world.player].size() == 2 and Society.pending(world).id == BRIBE, "two distinct decisions can coexist and repeat prizes cannot grow the queue")
	var both := world.snapshot()
	var game := Game.new()
	game.test_profile = true
	root.add_child(game)
	game.world.load_state(both)
	game.run_bridge()
	game.set_physics_process(false)
	var affairs := button_with_text(game.tabs, "事务 (2)")
	check(affairs != null, "both pending decisions count on the bridge immediately after loading")
	if affairs != null:
		affairs.pressed.emit()
	var recruit := button_with_text(game.body, "¢45")
	check(recruit != null and not recruit.disabled and button_with_text(game.body, "¢65") != null, "affairs exposes both actionable decisions side by side")
	var agent := Bridge.new()
	agent.game = game
	var state := agent.observe()
	check(state.event.get("id") == BRIBE and state.get("events", []).map(func(event): return event.id) == [BRIBE, PRIZE], "agent can see both decisions and the legacy first event")
	if recruit != null:
		recruit.pressed.emit()
	await process_frame
	var keep := Society.pending(game.world)
	var pending: Array = game.world.campaign.events.get(game.world.player, [])
	check(pending.size() == 1 and pending.front() == world.campaign.events[world.player].front() and keep.get("id") == BRIBE, "resolving the second decision preserves the first decision and its exact original context")
	check(game.world.ships[first].crew == 3 and game.world.ships[second].crew == 4 and game.world.active().wallet == 105, "resolving a second decision recruits on its original ship and charges exactly once")
	check(affairs != null and affairs.text == "事务 (1)" and button_with_text(game.body, "¢65") != null and button_with_text(game.body, "¢45") == null, "the affairs list updates just the completed prize and leaves the inspection actionable")
	game.queue_free()
	await process_frame
	var restored := World.new()
	check(restored.load_state(both) and restored.campaign.events[restored.player][1].context.prize == first, "saving a deferred prize preserves the original ship")
	check(Society.decide(restored, BRIBE, 3) and Society.pending(restored).get("id") == PRIZE, "handling inspection exposes the deferred prize")
	restored.ships[first].owner = 0
	var wallet: int = restored.active().wallet
	check(Society.pending(restored).is_empty() and not Society.decide(restored, PRIZE, 0) and restored.active().wallet == wallet, "lost prize clears without a recruitment charge")

func retired_decisions(snapshot: Dictionary) -> void:
	var data := snapshot.duplicate(true)
	var actor: int = data.player
	# A retired decision at the head of a queue must not hide a valid inspection behind it.
	data.campaign.events[actor].push_front({"id":"jump_5", "action":"on_hyperspace_jump", "day":data.day, "context":{}})
	data.campaign.last_event[actor]["jump_5"] = data.day
	var world := World.new()
	check(world.load_state(data) and Society.pending_count(world) == 1 and Society.pending(world).get("id") == BRIBE and
		not world.campaign.last_event[actor].has("jump_5"), "loading discards a retired template and retains a valid inspection")

func capture() -> void:
	var world := scenario()
	var ship := world.ride()
	world.tick(30)
	check(Society.pending(world).is_empty(), "ordinary month passes with no mandatory decisions")
	world.depart(ship)
	var kind: int = world.Hulls.MODELS.find_custom(func(model): return model.crew_max >= 12)
	var target := world.ship(kind, 0, 0, world.RAIDERS, ship.system, ship.pos)
	var prize: Dictionary = world.ships[target]
	prize.hp = 1
	prize.crew = 1
	prize.battle.shield = false
	ship.crew = world.Hulls.crew_limits(ship.kind).x + 6
	check(Ops.begin_boarding(world, target), "normal damaged-ship boarding action accepted")
	world.tick(3)
	var event := Society.pending(world)
	check(prize.owner == world.player and event.get("id") == PRIZE and world.HULLS[prize.kind] in event.get("body", ""), "boarding succeeds and the decision identifies the actual captured vessel")
	world.active().wallet = 100
	var crew: int = prize.crew
	check(Society.decide(world, PRIZE, 0) and prize.crew == crew + 2 and world.active().wallet == 55, "recruitment boards two crew on the actual captured ship")

func mod_events() -> void:
	var world := scenario()
	var pack: Dictionary = preload("res://examples/mods/waypost/fleet.json").data.duplicate(true)
	pack.erase("hulls")
	var loaded := []
	check(ModRegistry.add_pack(pack, [], {}, {}, loaded) and loaded.size() == 2, "original and data-driven mod formats load together")
	var timing: Dictionary = loaded.back()
	world.day += 1
	world.active().stats.learning = 8
	EventEngine.offer(world, timing.on_action, {}, [timing])
	check(not EventEngine.pending(world, {timing.id: timing}).options[0].enabled, "external authored skill gate affects playable option")
	var invalid: Dictionary = timing.duplicate(true)
	invalid.options[0].effects["bad_effect"] = true
	check(not ModRegistry.add_pack({"id":"waypost","events":[loaded.front(), invalid]}, [], {}, {}, []), "unknown effect rejects entire external pack")
	var scoped := timing.duplicate(true)
	scoped.options = [timing.options[0]]
	var catalog := {timing.id: scoped}
	world.active().stats.learning = 10
	check(not EventEngine.decide(world, catalog, timing.id, 1, Society.stress), "cannot bypass a live choice by sending its end index")
	world.active().stats.learning = 8
	check(EventEngine.pending(world, catalog).options.back().enabled and EventEngine.decide(world, catalog, timing.id, 1, Society.stress), "an external event can be archived if every authored choice becomes unavailable")

func routine_actions_and_succession() -> void:
	var world := scenario()
	var ship := world.ride()
	var home: int = ship.dock
	for visit in range(10):
		world.trade_event(false, world.player)
		world.trade_event(true, world.player)
		world.depart(ship)
		world.berth(ship, home)
		world.tick()
	check(Society.pending(world).is_empty() and not world.attention, "repeated cargo transactions and routine port calls create no decisions")
	world.ensure_chunks_around(Vector2(3300, 3300), 0)
	var site := world.port(world.core_count, "流浪哨站", Vector2(90, 60), world.NEUTRAL, 0, 0)
	world.ports[site].pop = 20
	world.depart(ship)
	check(world.berth(ship, site) and Society.pending(world).is_empty(), "a frontier berth creates no decision")
	world.depart(ship)
	var target := world.ship(0, 0, 0, world.RAIDERS, ship.system, ship.pos)
	world.destruction(target, world.player)
	check(Society.pending(world).is_empty(), "winning a combat creates no victory ceremony")
	world = scenario()
	var parent_id := world.player
	var other := world.random_person(-1, world.active().loc, "测试家族", 1-int(world.active().gender))
	world.people[other].noble = true
	world.people[other].opinions[parent_id] = 75
	check(Politics.marry(world, parent_id, other), "the willing noble couple marry at the same port")
	var child := Politics.child(world, parent_id, other)
	check(child != 0 and not world.attention and "家族新成员" in world.chronicle.front()[1], "birth logs the new family member while time continues")
	Politics.die(world, parent_id)
	check(world.regent == world.player and world.attention and Society.pending(world).is_empty(), "the regent takes office and the actual change of character still gets attention")
	world.people[child].birth = -18 * 360
	world.attention = false
	world.tick(30)
	check(world.player == child and world.attention and Society.pending(world).is_empty(), "the heir takes over at majority and the change of character still gets attention")
	world = scenario()
	var survivor := world.random_person(-1, world.active().loc)
	Politics.die(world, world.player)
	check(world.succession and world.attention and Politics.choose(world, survivor) and world.player == survivor and not world.succession,
		"when there is no heir the player can still choose the next character")

func button_with_text(parent: Node, fragment: String) -> Button:
	for item: Button in parent.find_children("*", "Button", true, false):
		if fragment in item.text:
			return item
	return null

func human_and_agent(snapshot: Dictionary) -> void:
	var game := Game.new()
	game.test_profile = true
	root.add_child(game)
	game.world.load_state(snapshot)
	game.run_bridge()
	game.set_physics_process(false)
	game.set_speed(2)
	var original_tab: String = game.tab
	await process_frame
	var affairs := button_with_text(game.tabs, "事务")
	check(game.find_children("*", "AcceptDialog", true, false).is_empty() and game.tab == original_tab and not game.world.attention and game.speed == 2,
		"restored decision leaves the current tab, controls and simulation speed alone")
	check(affairs != null and affairs.text == "事务 (1)", "affairs tab shows the pending choice without demanding attention")
	affairs.pressed.emit()
	var bribe := button_with_text(game.body, "¢65")
	var hook := button_with_text(game.body, "缺少对港务经理")
	check(game.tab == "事务" and bribe != null and hook != null and hook.disabled, "player opens available choices and disabled reasons in the affairs panel")
	if bribe != null:
		bribe.pressed.emit()
	await process_frame
	check(Society.pending(game.world).is_empty() and game.world.active().wallet == 85 and affairs.text == "事务" and game.speed == 2,
		"choosing in affairs pays exactly once, clears the count and preserves speed")
	game.world.active().suspicion = 18
	game.world.day += 180
	var site: int = game.world.ride().dock
	game.world.depart(game.world.ride())
	game.world.berth(game.world.ride(), site)
	game.update_bridge(1.0 / 60.0)
	await process_frame
	check(game.speed == 2 and not game.world.attention and game.find_children("*", "AcceptDialog", true, false).is_empty(), "new qualifying inspection at double speed never opens a dialog or pauses")
	check(affairs.text == "事务 (1)" and button_with_text(game.body, "¢65") != null, "the open affairs panel shows the new decision without navigating away")
	# Agent input remains opt-in even while the graphical bridge displays the same choice.
	game.world.load_state(snapshot)
	var bridge := Bridge.new()
	bridge.game = game
	var halted := bridge.dispatch("step", {"ticks": 60, "stop": "event"})
	check(halted.result.stopped == "event" and halted.result.ticks == 0, "agent can halt simulation at an unresolved event")
	var stepping := bridge.dispatch("step", {"ticks": 2, "stop": "never"})
	check(stepping.result.ticks == 2 and Society.pending(game.world).id == BRIBE, "agent can also step past a pending decision without settling it")
	check(bridge.observe().event.options.size() == 4 and not bridge.dispatch("event_choice", {"event_id": BRIBE, "option_index": 9}).ok, "agent sees all choices and rejects out-of-range index")
	var decision := bridge.dispatch("event_choice", {"event_id": BRIBE, "option_index": 2})
	check(decision.ok and game.world.ride().cargo[Industry.Ware.LUXURY] == 0 and game.world.active().legitimacy == 3, "agent selects third option and confiscates scoped cargo")
	game.world.depart(game.world.ride())
	var region: Dictionary = game.world.systems[game.world.ride().system]
	game.world.ride().pos = Celestial.gravity_point(region)
	game.set_speed(1)
	game.flight.change_layer()
	check(game.galaxy and Society.pending(game.world).is_empty() and game.speed == 1, "manual departure from gravity point runs without generating an interruption")
	game.world.day += 1
	game.flight.change_layer()
	check(not game.galaxy and Society.pending(game.world).is_empty() and game.speed == 1, "manual arrival at a beacon runs without generating an interruption")
	game.queue_free()
	await process_frame

func run() -> void:
	Society.build_events()
	var ids := EventEngine.authored().map(func(row): return row.id)
	check(ids.size() == 2 and BRIBE in ids and PRIZE in ids, "bundled choices are limited to smuggling inspections and actual captured ships")
	check(EventEngine.authored().all(EventEngine.valid_template), "all bundled templates pass the external event schema")
	var snapshot := inspection()
	resolutions(snapshot)
	await queue_scope(snapshot)
	retired_decisions(snapshot)
	capture()
	mod_events()
	routine_actions_and_succession()
	await human_and_agent(snapshot)
	print("Campaign events: %d/%d" % [passed, passed + failed])
	quit(1 if failed else 0)
