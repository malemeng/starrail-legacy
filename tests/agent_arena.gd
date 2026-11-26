extends SceneTree

const SCENE = preload("res://game.tscn")

var passed := 0
var failed := 0

func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var g = SCENE.instantiate()
	g.test_profile = true
	get_root().add_child(g)
	g.show_creator()
	g.start_game()
	var human_player: int = g.world.player

	var cfgs := [
		{"name": "Alpha", "model": "m1", "goal": "trade", "auto_launch": false},
		{"name": "Beta", "model": "m2", "goal": "mine", "auto_launch": false},
	]
	check(g.arena.start_arena(g, cfgs, ""), "start_arena spawns 2 agent slots")
	check(g.arena.slots.size() == 2, "2 slots active")
	check(g.world.player == human_player, "human world.player unchanged")

	var b1 = g.arena.slots[0].bridge
	var b2 = g.arena.slots[1].bridge
	var obs1: Dictionary = b1.dispatch("observe", {})
	var obs2: Dictionary = b2.dispatch("observe", {})
	check(bool(obs1.get("ok", false)) and obs1.state.actor.name == "Alpha", "slot 1 observes as Alpha")
	check(bool(obs2.get("ok", false)) and obs2.state.actor.name == "Beta", "slot 2 observes as Beta")
	check(g.world.player == human_player, "world.player restored after slot dispatches")

	var sup1: Dictionary = b1.dispatch("supply_fleet", {})
	check(bool(sup1.get("ok", false)), "slot 1 runs supply_fleet independently")

	var rows: Array[Dictionary] = g.arena.standings()
	check(rows.size() == 2 and int(rows[0].net_worth) >= 2400, "standings computes net_worth")
	check(g.world.campaign.get("arena_slots", []).size() == 2, "arena_slots persisted in world.campaign")

	g.arena.stop_arena(false)
	check(not g.arena.active and g.world.campaign.get("arena_slots", []).size() == 2, "stop_arena(false) keeps saved arena_slots")
	check(g.arena.resume_arena(g, "", g._resolve_model_creds, false) and g.arena.slots.size() == 2, "resume_arena restores 2 slots")
	check(g.arena.slots[0].name == "Alpha" and g.arena.slots[1].name == "Beta", "resumed slot names match")

	g.arena.stop_arena(true)
	check(not g.arena.active and g.arena.slots.is_empty() and not g.world.campaign.has("arena_slots"), "stop_arena(true) cleans up")
	g.queue_free()
	await process_frame

	print("AgentArena checks %d/%d" % [passed, passed + failed])
	quit(0 if failed == 0 else 1)
