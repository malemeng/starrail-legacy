extends SceneTree

const WorldScript = preload("res://world.gd")
const Politics = preload("res://politics.gd")
const Economy = preload("res://economy.gd")

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
	var w = WorldScript.new()
	w.new_game({"seed": "character-parity-test", "systems": 16, "factions": 4, "avatar": {"name": "Origin Captain"}})

	var orig_player: int = w.player
	var npc_id := 0
	for pid in w.people:
		var p: Dictionary = w.people[pid]
		if int(pid) != orig_player and p.alive and int(p.flag) != w.RAIDERS and int(p.ship) > 0:
			npc_id = int(pid)
			break
	check(npc_id != 0, "found living NPC captain")

	# 1. Switch to any character and switch back
	check(Politics.switch_character(w, npc_id), "switch_character to NPC succeeds")
	check(w.player == npc_id, "world.player updated to NPC")
	check(not w.ride().locked, "new character ship unlocked for manual control")
	check(Politics.switch_character(w, orig_player), "switch_character back to original succeeds")
	check(w.player == orig_player, "world.player restored")

	# 2. Ordinary NPC pioneers & builds an orbital station
	var pioneer: Dictionary = w.people[npc_id]
	pioneer.wallet = 10000
	pioneer.flag = w.NEUTRAL
	var pre_ports: int = w.ports.size()
	check(Politics._npc_pioneer_station(w, pioneer), "ordinary NPC pioneers orbital station")
	check(w.ports.size() == pre_ports + 1, "new orbital construction site created")

	var built_pid := 0
	for pid in w.ports:
		if int(w.ports[pid].get("owner", 0)) == npc_id:
			built_pid = int(pid)
			break
	check(built_pid != 0, "NPC owns the new station site")
	w.ports[built_pid].build = 0

	# 3. Ordinary NPC founds a corporation
	pioneer.wallet = 2500
	check(Economy.incorporate(w, built_pid, "星野独立工坊", npc_id), "ordinary NPC incorporates firm")
	check(int(w.ports[built_pid].firm) != 0, "station affiliated with NPC firm")

	# 4. Ordinary NPC founds an independent faction
	pioneer.wallet = 12000
	check(Politics.found(w, "星野自由领", built_pid, 1, npc_id), "ordinary NPC founds faction")
	check(int(pioneer.flag) >= 0 and w.factions.has(int(pioneer.flag)), "NPC faction registered")
	check(bool(w.factions[int(pioneer.flag)].npc), "NPC-founded faction stays AI-controlled")

	print("CharacterParity checks %d/%d" % [passed, passed + failed])
	quit(0 if failed == 0 else 1)
