extends Node

const AgentBridge = preload("res://agent_bridge.gd")
const Portrait = preload("res://portrait.gd")

const ARENA_DIR := "user://agent_arena"

var game
var active := false
var slots: Array[Dictionary] = []

func start_arena(p_game, slot_configs: Array, runner_script: String) -> bool:
	stop_arena(false)
	game = p_game
	if game == null or not game.playing or slot_configs.is_empty():
		return false
	var world = game.world
	var base_dir := ProjectSettings.globalize_path(ARENA_DIR)
	DirAccess.make_dir_recursive_absolute(base_dir)
	var ready_ports: Array[int] = []
	for pid in world.ports:
		var st: Dictionary = world.ports[pid]
		if int(st.get("build", 0)) == 0 and not st.get("landing_only", false) and int(st.get("flag", world.NEUTRAL)) >= 0:
			ready_ports.append(int(pid))
	if ready_ports.is_empty():
		ready_ports.append(1)

	var rng: RandomNumberGenerator = world.rng
	for i in range(slot_configs.size()):
		var cfg: Dictionary = slot_configs[i]
		var start_pid: int = ready_ports[i % ready_ports.size()]
		var st: Dictionary = world.ports[start_pid]
		var cname := str(cfg.get("name", "Agent-%d" % (i + 1))).strip_edges()
		if cname.is_empty():
			cname = "Agent-%d" % (i + 1)
		var g_idx := i % 2
		var actor_id: int = world.person(
			cname, "竞争者", world.day - 24 * 360, world.NEUTRAL,
			start_pid, 0, i % 4, Portrait.random_look_for_gender(rng, g_idx), g_idx
		)
		world.people[actor_id]["wallet"] = 2400
		var ship_id: int = world.ship(0, actor_id, actor_id, world.NEUTRAL, int(st.system), Vector2(st.pos), start_pid)
		if not world.is_watched(actor_id):
			world.toggle_watch(actor_id)

		var sdir := base_dir.path_join("slot_%d" % (i + 1))
		DirAccess.make_dir_recursive_absolute(sdir)
		for fname in DirAccess.get_files_at(sdir):
			DirAccess.remove_absolute(sdir.path_join(fname))
		var bridge := AgentBridge.new()
		bridge.game = game
		bridge.bound_actor_id = actor_id
		if not bridge.start(sdir, false):
			continue
		var py_pid := -1
		if bool(cfg.get("auto_launch", true)) and not runner_script.is_empty():
			var others: Array[String] = []
			for j in range(slot_configs.size()):
				if j == i:
					continue
				var ocfg: Dictionary = slot_configs[j]
				var oname := str(ocfg.get("name", "Agent-%d" % (j + 1))).strip_edges()
				if oname.is_empty():
					oname = "Agent-%d" % (j + 1)
				others.append("%s(%s)" % [oname, str(ocfg.get("model", ""))])
			var py_args := PackedStringArray([
				runner_script, "--session-dir", sdir,
				"--api-base", str(cfg.get("api_base", "")),
				"--api-key", str(cfg.get("api_key", "")),
				"--model", str(cfg.get("model", "")),
				"--max-steps", str(int(cfg.get("max_steps", 40))),
				"--goal", str(cfg.get("goal", "")),
				"--rivals", "你是「%s」；同宇宙对手：%s" % [cname, "、".join(others)] if not others.is_empty() else "",
			])
			py_pid = game.launch_agent_runner(py_args)
		slots.append({
			"slot": i + 1,
			"name": cname,
			"model": str(cfg.get("model", "")),
			"goal": str(cfg.get("goal", "")),
			"actor_id": actor_id,
			"ship_id": ship_id,
			"max_steps": int(cfg.get("max_steps", 0)),
			"dir": sdir,
			"bridge": bridge,
			"pid": py_pid,
			"thought": "等待首轮思考...",
			"last_action": "",
		})
	active = not slots.is_empty()
	_sync_campaign_slots()
	if active and game.speed == 0:
		game.set_speed(2)
	return active

func _sync_campaign_slots() -> void:
	if game == null or game.world == null:
		return
	var saved: Array = []
	for s in slots:
		saved.append({
			"slot": int(s.get("slot", saved.size() + 1)),
			"name": str(s.get("name", "")),
			"model": str(s.get("model", "")),
			"goal": str(s.get("goal", "")),
			"actor_id": int(s.get("actor_id", 0)),
			"ship_id": int(s.get("ship_id", 0)),
			"max_steps": int(s.get("max_steps", 0)),
		})
	if saved.is_empty():
		game.world.campaign.erase("arena_slots")
	else:
		game.world.campaign["arena_slots"] = saved

func resume_arena(p_game, runner_script: String, resolve_creds: Callable, auto_launch: bool = true) -> bool:
	stop_arena(false)
	game = p_game
	if game == null or not game.playing:
		return false
	var world = game.world
	var saved: Variant = world.campaign.get("arena_slots", [])
	if not (saved is Array) or saved.is_empty():
		return false
	var base_dir := ProjectSettings.globalize_path(ARENA_DIR)
	DirAccess.make_dir_recursive_absolute(base_dir)
	var valid_entries: Array[Dictionary] = []
	for item in saved:
		if not (item is Dictionary):
			continue
		var aid := int(item.get("actor_id", 0))
		var actor: Dictionary = world.people.get(aid, {})
		if actor.is_empty() or not bool(actor.get("alive", false)):
			continue
		valid_entries.append(item)
	if valid_entries.is_empty():
		world.campaign.erase("arena_slots")
		return false

	for i in range(valid_entries.size()):
		var item: Dictionary = valid_entries[i]
		var aid := int(item.get("actor_id", 0))
		var cname := str(item.get("name", world.name_of(aid)))
		var mname := str(item.get("model", ""))
		var gtext := str(item.get("goal", ""))
		if not world.is_watched(aid):
			world.toggle_watch(aid)
		var sdir := base_dir.path_join("slot_%d" % (i + 1))
		DirAccess.make_dir_recursive_absolute(sdir)
		for fname in DirAccess.get_files_at(sdir):
			DirAccess.remove_absolute(sdir.path_join(fname))
		var bridge := AgentBridge.new()
		bridge.game = game
		bridge.bound_actor_id = aid
		if not bridge.start(sdir, false):
			continue
		var py_pid := -1
		if auto_launch and not runner_script.is_empty():
			var creds: Dictionary = resolve_creds.call(mname) if resolve_creds.is_valid() else {}
			var others: Array[String] = []
			for j in range(valid_entries.size()):
				if j == i:
					continue
				var oitem: Dictionary = valid_entries[j]
				others.append("%s(%s)" % [str(oitem.get("name", "")), str(oitem.get("model", ""))])
			var py_args := PackedStringArray([
				runner_script, "--session-dir", sdir,
				"--api-base", str(creds.get("api_base", "")),
				"--api-key", str(creds.get("api_key", "")),
				"--model", mname,
				"--max-steps", str(int(item.get("max_steps", creds.get("max_steps", 0)))),
				"--goal", gtext,
				"--rivals", "你是「%s」；同宇宙对手：%s" % [cname, "、".join(others)] if not others.is_empty() else "",
			])
			py_pid = game.launch_agent_runner(py_args)
		slots.append({
			"slot": i + 1,
			"name": cname,
			"model": mname,
			"goal": gtext,
			"actor_id": aid,
			"ship_id": int(item.get("ship_id", 0)),
			"max_steps": int(item.get("max_steps", 0)),
			"dir": sdir,
			"bridge": bridge,
			"pid": py_pid,
			"thought": "已从存档恢复，等待续跑思考...",
			"last_action": "",
		})
	active = not slots.is_empty()
	_sync_campaign_slots()
	return active

func stop_arena(clear_saved: bool = true) -> void:
	for s in slots:
		var py_pid := int(s.get("pid", -1))
		if py_pid > 0 and OS.is_process_running(py_pid):
			OS.kill(py_pid)
		var b = s.get("bridge")
		if b != null:
			b.publish("shutdown.json", {"ok": true, "reason": "arena_stopped"})
	slots.clear()
	active = false
	if clear_saved and game != null and game.world != null:
		game.world.campaign.erase("arena_slots")

func poll(delta: float) -> void:
	if not active or game == null or not game.playing:
		return
	for s in slots:
		var b = s.get("bridge")
		if b == null:
			continue
		var tpath := str(s.dir).path_join("thought.json")
		if FileAccess.file_exists(tpath):
			var tf := FileAccess.open(tpath, FileAccess.READ)
			if tf != null:
				var td: Variant = JSON.parse_string(tf.get_as_text())
				tf.close()
				DirAccess.remove_absolute(tpath)
				if td is Dictionary and not str(td.get("thought", "")).is_empty():
					s["thought"] = str(td.thought)
		b.poll(delta)

static func net_worth(world, actor_id: int) -> int:
	var actor: Dictionary = world.people.get(actor_id, {})
	if actor.is_empty():
		return 0
	var total := int(actor.get("wallet", 0))
	for sh in world.ships.values():
		if int(sh.get("owner", 0)) == actor_id:
			total += 6800 + int(sh.get("kind", 0)) * 2500
	for st in world.ports.values():
		if int(st.get("owner", 0)) == actor_id:
			total += int(st.get("treasury", 0)) + 6000
	for fid in actor.get("shares", {}):
		var units := int(actor.shares[fid])
		if units > 0 and world.firms.has(fid):
			total += units * 40
	return total

func standings() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if game == null:
		return rows
	var world = game.world
	for s in slots:
		var aid := int(s.actor_id)
		var actor: Dictionary = world.people.get(aid, {})
		var ships := 0
		for sh in world.ships.values():
			if int(sh.get("owner", 0)) == aid:
				ships += 1
		var ports := 0
		for st in world.ports.values():
			if int(st.get("owner", 0)) == aid:
				ports += 1
		rows.append({
			"slot": s.slot,
			"name": s.name,
			"model": s.model,
			"actor_id": aid,
			"credits": int(actor.get("wallet", 0)),
			"net_worth": net_worth(world, aid),
			"ships": ships,
			"ports": ports,
			"thought": str(s.get("thought", "")),
			"alive": bool(actor.get("alive", false)),
		})
	rows.sort_custom(func(a, b): return int(a.net_worth) > int(b.net_worth))
	return rows
