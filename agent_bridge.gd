extends RefCounted

const Battle = preload("res://combat.gd")
const Celestial = preload("res://celestial.gd")
const Industry = preload("res://scripts/economy/industry.gd")
const Economy = preload("res://economy.gd")
const Hulls = preload("res://hull_catalog.gd")
const Politics = preload("res://politics.gd")
const Story = preload("res://frontier.gd")
const Portrait = preload("res://portrait.gd")
const Crises = preload("res://scripts/campaign/crises.gd")
const Society = preload("res://scripts/campaign/society.gd")
const ShareholderRelations = preload("res://scripts/campaign/shareholder_relations.gd")
const Operations = preload("res://scripts/campaign/operations.gd")
const PROTOCOL := 2
const MAX_BYTES := 16384
const FreightNotice = preload("res://scripts/economy/freight_notice.gd")
const WatchLog = preload("res://scripts/services/agent_watch_log.gd")
var intention := {"text":"","target":""}
var watch_log
var bound_actor_id := 0
var allow_cheats := "--allow-cheats" in OS.get_cmdline_user_args() or "--allow-cheats" in OS.get_cmdline_args()

func attach_watch(layer: CanvasLayer) -> void:
	var panel := preload("res://scripts/ui/agent_watch.gd").new()
	layer.add_child(panel)
	watch_log = WatchLog.new(game,panel)
	request_started.connect(watch_log.begin)
	request_finished.connect(watch_log.finish)
	step_progress.connect(watch_log.progress)

func watch_station_ui(tab_name: String, dock_mode: String, note: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not tab_name.is_empty():
		game.tab = tab_name
	if not dock_mode.is_empty() and game.world.active().get("loc", 0) != 0:
		game.dock_view.mode = dock_mode
	if not note.is_empty():
		game.say(note)

signal request_started(action: String, args: Dictionary)
signal request_finished(action: String, args: Dictionary, response: Dictionary)
signal step_progress(processed: int, ticks: int)

var game
var directory := ""
var elapsed := 0.0
var watch_mode := false
var active_step: Dictionary = {}
var _step_request: Dictionary = {}

func start(path: String, watch: bool = false) -> bool:
	if not path.is_absolute_path() or not DirAccess.dir_exists_absolute(path):
		return false
	if not DirAccess.get_files_at(path).is_empty() or not DirAccess.get_directories_at(path).is_empty():
		return false
	directory = path
	watch_mode = watch
	return publish("ready.json", {"protocol":PROTOCOL,"supported_protocols":[1, 2],"pid":OS.get_process_id(),"watch":watch_mode})

func publish(filename: String, value: Dictionary) -> bool:
	var path := directory.path_join(filename)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value))
	file.close()
	return DirAccess.rename_absolute(path + ".tmp", path) == OK

func poll(delta: float) -> void:
	if not active_step.is_empty():
		var finished := run_step(active_step,1)
		if finished or int(active_step.processed) % 6 == 0:
			step_progress.emit(active_step.processed,active_step.ticks)
		if finished:
			var result := finish_step(active_step)
			active_step = {}
			reply(_step_request,result)
			_step_request = {}
		return
	elapsed += delta
	if elapsed < 0.04:
		return
	elapsed = 0.0
	var thought_path := directory.path_join("thought.json")
	if FileAccess.file_exists(thought_path):
		var tf := FileAccess.open(thought_path, FileAccess.READ)
		if tf != null:
			var tdata: Variant = JSON.parse_string(tf.get_as_text())
			tf.close()
			DirAccess.remove_absolute(thought_path)
			if tdata is Dictionary and not str(tdata.get("thought", "")).is_empty() and watch_log != null:
				watch_log.state["intent"] = str(tdata.get("thought", ""))
				watch_log.panel.present(watch_log.state)
	var path := directory.path_join("request.json")
	var response := directory.path_join("response.json")
	if FileAccess.file_exists(response) or not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		return
	var raw_len := file.get_length()
	var raw_text := file.get_as_text() if raw_len <= MAX_BYTES else ""
	file.close()
	if raw_len == 0 or raw_text.strip_edges().is_empty():
		return
	var request: Variant = JSON.parse_string(raw_text) if raw_len <= MAX_BYTES else null
	var result := failure("invalid_request")
	if request is Dictionary and request.get("id") is String and request.id.length() in range(1,81):
		if request.get("action") is String and request.get("args",{}) is Dictionary:
			var args: Dictionary = request.get("args",{})
			request_started.emit(request.action,args)
			if watch_mode and request.action == "step" and game.playing and not game.world.succession:
				var step := prepare_step(args)
				if not step.has("error"):
					active_step = step
					_step_request = request
					return
				result = step
			else:
				result = dispatch(request.action,args)
		reply(request,result)
	else:
		reply({},result)

func reply(request: Dictionary, result: Dictionary) -> void:
	if request.has("id"):
		result.id = request.id
	if request.get("action") is String and request.get("args",{}) is Dictionary:
		request_finished.emit(request.action,request.get("args",{}),result)
	# Keep the original request in the directory while its watched ticks are running.
	# A client that times out can still recognize the outstanding action.
	if not publish("response.json", result) or DirAccess.remove_absolute(directory.path_join("request.json")) != OK:
		printerr("Agent bridge could not finalize the request and response files.")
		game.get_tree().quit(3)
	elif result.get("quit",false):
		game.get_tree().quit()

func failure(code: String, detail: String = "") -> Dictionary:
	var msg := detail
	if msg.is_empty() and game != null and not str(game.notice_text).is_empty():
		msg = str(game.notice_text)
	return {"ok":false,"error":code,"detail":msg}

func integer(args: Dictionary, field: String, fallback: int, from: int, to: int) -> int:
	var value: Variant = args.get(field,fallback)
	if (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= from and value <= to:
		return int(value)
	return from - 1

func vector(value: Variant) -> Variant:
	if not value is Array or value.size() != 2:
		return null
	for coordinate in value:
		if not (coordinate is int or coordinate is float):
			return null
	var point := Vector2(value[0], value[1])
	return point if point.is_finite() else null

func coords(point: Vector2) -> Array:
	return [snappedf(point.x,0.01),snappedf(point.y,0.01)]

func success(extra: Dictionary = {}) -> Dictionary:
	return {"ok":true,"result":extra,"state":observe()}

func observe() -> Dictionary:
	if not game.playing:
		return {"screen":"title","intent":intention.duplicate()}
	var world = game.world
	var prev_player := int(world.player)
	var swapped: bool = bound_actor_id > 0 and world.people.has(bound_actor_id) and bound_actor_id != prev_player
	if swapped:
		world.player = bound_actor_id
	var out := _observe_inner()
	if swapped:
		world.player = prev_player
	return out

func _observe_inner() -> Dictionary:
	if not game.playing:
		return {"screen":"title","intent":intention.duplicate()}
	var world = game.world
	if world.succession:
		var heirs: Array = []
		for actor in world.people.values():
			if actor.alive and Politics.age(world,actor) >= 18:
				heirs.append({"id":actor.id,"name":actor.name,"faction":world.flag_name(actor.flag)})
		return {"screen":"succession","day":world.day,"candidates":heirs.slice(0,40)}
	var actor: Dictionary = world.active()
	var vessel: Dictionary = world.ride()
	var system_index: int = game.current_system()
	var region: Dictionary = world.systems[system_index]
	var state := {"screen":"port" if actor.loc != 0 else ("hyperspace" if game.galaxy else "flight"),
		"day":world.day,"seed":world.settings.seed,"actor":{"id":actor.id,"name":actor.name,"credits":actor.wallet,"faction":world.flag_name(actor.flag)},
		"system":{"id":system_index,"name":region.name},"notice":game.notice_text,"contract":world.contracts.get(world.player,{}).duplicate(),
		"objective":Story.objective(world),"speed":game.speed,"attention":world.attention,"ship":{},"ports":[],"contacts":[],"targets":[]}
	state.protocol = PROTOCOL
	state.allow_cheats = allow_cheats
	state.intent = intention.duplicate()
	state.actor.stats = actor.stats.to_dict()
	state.actor.spouse = actor.spouse
	state.actor.children = actor.children.duplicate()
	state.actor.parents = actor.parents.duplicate()
	state.actor.noble = actor.noble
	state.actor.stress = actor.stress
	state.actor.focus = actor.focus
	state.actor.hooks = actor.hooks.duplicate(true)
	state.events = Society.pending_all(world)
	state.event = state.events.front() if not state.events.is_empty() else {}
	state.crises = Crises.summary(world)
	state.bounties = []
	for b: Dictionary in world.Bounties.active(world):
		state.bounties.append({"id":b.id,"issuer_flag":b.issuer_flag,"issuer":world.flag_name(int(b.issuer_flag)),
			"target_flag":b.target_flag,"target":world.flag_name(int(b.target_flag)),"system":b.system,
			"base_reward":b.base_reward,"expires":b.expires,"eligible":not world.hostile(actor.flag,int(b.issuer_flag))})
	state.organizations = world.Outlaws.summary(world)
	for org: Dictionary in state.organizations:
		org.pos = coords(org.pos)
	state.system.starfield = Celestial.profile(region).name
	state.system.binary = region.has("companion")
	state.system.planets = []
	for i in region.planets.size():
		var planet: Dictionary = region.planets[i]
		state.system.planets.append({"index":i,"name":planet.name,"type":Celestial.PLANETS[planet.type][0],"pos":coords(planet.pos),"spin":planet.get("spin",0.0),
			"radius":planet.radius,"gravity_radius":Celestial.gravity_radius(region,planet),"landing":coords(world.PlanetPorts.point(planet)),"port":planet.get("port_id",0),"surveyed":planet.surveyed})
	state.construction_contract = {}
	for engineer: Dictionary in world.ships.values():
		var job: Dictionary = engineer.get("construction_contract",{})
		if job.get("client",0) == world.player and job.get("status","") in ["active","working"]:
			state.construction_contract = {"ship":engineer.id,"status":job.status,"fee":job.fee,"site":job.site,"home":job.home,
				"system":engineer.system,"dock":engineer.dock,"pos":coords(engineer.galpos if engineer.layer else engineer.pos)}
			break
	state.schemes = world.campaign.schemes.get(actor.id, {})
	state.projects = world.campaign.projects.duplicate(true)
	state.movements = world.campaign.movements.duplicate(true)
	var managed_ports: Array[int] = []
	for st_id in world.ports:
		var st: Dictionary = world.ports[st_id]
		if st.build == 0 and (world.oversees(st.get("owner", 0)) or world.oversees(st.get("manager", 0))):
			managed_ports.append(int(st_id))
	var fleets: Array = []
	for other in world.ships.values():
		if world.oversees(world.ship_principal(other)) or int(other.get("station_owner", 0)) in managed_ports:
			fleets.append({"id":other.id,"model":world.HULLS[other.kind],"captain":other.captain,"owner":other.owner,
				"system":other.system,"dock":other.dock,"pos":coords(other.galpos if other.layer else other.pos),
				"hp":other.hp,"fuel":other.fuel,"firm":other.get("firm",0),"station_owner":other.get("station_owner",0),"job":other.job.duplicate(true),
				"order":Battle.ORDERS[other.battle.order],"route_hold":other.get("route_hold",""),
				"order_queue":other.get("order_queue",[]).duplicate(true),"default_behavior":other.get("default_behavior",other.job).duplicate(true),
				"fleet_role":other.get("fleet_role",""),"commander":other.get("commander_id",0),"last_order":other.get("last_order",{}).duplicate(true),
				"operating_area":Economy.OperatingArea.settings(world,other),"next_operating_area":other.get("next_operating_area",{})})
	state.managed_ports = managed_ports
	state.fleet = fleets
	if not vessel.is_empty():
		var battle: Dictionary = vessel.battle
		state.ship = {"hull_id":vessel.hull_id,"fit":vessel.fit.as_dictionary(),"shield_type":Hulls.MODELS[vessel.kind].get("shield_type","NONE"),"armor_grid":Array(battle.get("armor_grid",[])), "shield_arc":battle.get("shield_arc_live",0.0), "cr":battle.get("cr",1.0),"silent_running":battle.get("silent_running",false),"presets":Hulls.presets(vessel.kind).map(func(p): return p.id), "id":vessel.id,"model":world.HULLS[vessel.kind],"pos":coords(vessel.galpos if game.galaxy else vessel.pos),
			"velocity":coords(battle.motion),"heading":snappedf(float(vessel.heading),0.001),"dock":vessel.dock,"hp":vessel.hp,"armor":battle.armor,
			"crew":vessel.crew,"fuel":vessel.fuel,"free_cargo":world.cargo_free(vessel),"locked":vessel.locked,"cargo":vessel.cargo.duplicate(),
			"soft_flux":battle.soft_flux,"hard_flux":battle.hard_flux,"capacity":Hulls.capacity(vessel),"shield":battle.shield,
			"vent":battle.vent,"overload":battle.overload,"group":battle.group,"cooldowns":battle.cooldowns.duplicate(),"system_cd":battle.system_cd,
			"system_time":battle.system_time,"weapons":vessel.fit.weapons.duplicate(),"auto":vessel.fit.auto.duplicate(),"autopilot":game.autopilot,"tactic":game.combat_tactic,"tactic_name":game.COMBAT_TACTICS[game.combat_tactic],"fleet":fleets}
		state.ship.builtin_wings = Hulls.MODELS[vessel.kind].builtin_wings
		state.ship.owner = vessel.owner
		if vessel.get("charter",{}).get("operator",0) == world.player:
			state.ship.charter = Economy.charter_quote(world,vessel.id)
		var system := Battle.Abilities.profile(vessel)
		state.ship.ship_system = {"id":system.id, "name":system.label, "description":system.get("description",""),
			"charges":floori(battle.get("system_charges",system.get("charges",0)) + 0.00001) if system.has("charges") else null,
			"max_charges":system.get("charges",null), "toggle":system.get("toggle",false)}
		state.ship.fighter_wings = battle.get("fighter_wings",[]).map(func(wing):
			return {"id":wing.id,"sortie":wing.sortie,"returning":wing.returning,"hp":wing.hp,"pos":coords(wing.pos),"aircraft":wing.get("count_live",wing.count)})
		state.waypoint = coords(game.waypoint) if game.waypoint_live else null
	state.wares = world.WARES
	state.ship_catalog = Hulls.MODELS.map(func(model): return {"name":model.name,"hull_id":model.id,"class":model.size,"market":model.market,"price":model.price,"price_basis":"reference","cargo":model.cargo}) if state.screen == "port" else []
	if game.galaxy and not vessel.is_empty():
		var point: Vector2 = vessel.galpos
		var ordered: Array = world.nearby_beacons(point)
		state.beacons = []
		for index in ordered.slice(0,16):
			var destination: Dictionary = world.systems[index]
			var distance := point.distance_to(destination.pos)
			state.beacons.append({"id":index,"name":destination.name,"pos":coords(destination.pos),"distance":distance,"fuel_required":game.flight.Hyperspace.fuel_for_distance(Hulls.MODELS[vessel.kind],distance),"visited":destination.seen,"fuel_depot":destination.get("frontier_depot",false)})
		state.jump_allowed = not vessel.locked and game.flight.nearby_system(vessel) >= 0
	else:
		state.gravity = coords(Celestial.gravity_point(region))
		state.mine = coords(region.field)
		state.jump_allowed = not vessel.is_empty() and vessel.dock == 0 and not vessel.locked and Celestial.at_gravity_point(region,vessel.pos)
		for port_id in region.ports:
			var station: Dictionary = world.ports[port_id]
			var entry := {"id":port_id,"name":station.name,"pos":coords(station.pos),"hostile":world.hostile(actor.flag,station.flag),
				"planet_index":station.get("planet_index",null),"construction_days":station.build}
			if actor.loc == port_id:
				entry.market_size = Economy.market_size(station)
				entry.market_size_label = Economy.market_size_label(station)
				entry.pop = station.pop
				entry.manager = station.manager
				entry.builder_offer = world.ConstructionContract.offer(world,port_id)
				entry.stock = station.stock.duplicate()
				entry.market_available = []
				entry.market_space = []
				entry.buy = []
				entry.sell = []
				for ware in range(world.WARES.size()):
					entry.market_available.append(Industry.available(station, ware))
					entry.market_space.append(Industry.space(station, ware))
					entry.buy.append(Economy.price(station,ware,true,actor.origin) if ware != Industry.Ware.LUXURY else null)
					entry.sell.append(Economy.price(station,ware,false,actor.origin) if ware != Industry.Ware.LUXURY else null)
				entry.ships = station.hulls.duplicate()
				entry.hull_prices = {}
				for kind in range(station.hulls.size()):
					if station.hulls[kind] > 0 and Hulls.model_limit(station,kind):
						entry.hull_prices[Hulls.hull_id(kind)] = Economy.ship_quote(station,kind).price
				entry.wing_catalog = []
				for wing_id in Hulls.wing_ids():
					var wing := Hulls.wing_spec(wing_id)
					entry.wing_catalog.append({"id":wing_id,"name":wing.name,"role":wing.role,"count":wing.count,"specialty":wing.specialty,"price":wing.price,"materials":wing.materials})
			state.ports.append(entry)
		for other in world.ships.values():
			if not vessel.is_empty() and other.id != vessel.id and Battle.available(other,system_index) and vessel.pos.distance_to(other.pos) <= 680.0 and game.flight.visible_contact(vessel,other):
				state.targets.append({"id":other.id,"pos":coords(other.pos),"velocity":coords(other.battle.motion),"hp":other.hp,
					"armor":other.battle.armor,"shield":other.battle.shield,"hostile":world.enemy(vessel,other),"model":world.HULLS[other.kind],
					"organization":world.Outlaws.id_for(other),"flag":world.flag_name(other.flag)})
		if actor.loc != 0:
			for other in world.people.values():
				if other.alive and other.id != actor.id and other.loc == actor.loc:
					var prof := ShareholderRelations.profile(world, other.id)
					state.contacts.append({
						"id":other.id,"name":other.name,"age":Politics.age(world,other),"gender":"女" if int(other.get("gender",0)) == 1 else "男",
						"noble":other.noble,"house":other.get("house",""),"flag":other.flag,"flag_name":world.flag_name(other.flag),
						"trait":world.TRAITS[other.trait],"traits":world.Society.trait_labels(other),
						"spouse":other.spouse,"opinion":Politics.opinion(world,other.id,actor.id),
						"relation":actor.get("relations",{}).get(other.id,""),"has_hook":actor.get("hooks",{}).has(other.id),
						"roles":prof.get("roles",[]),"stats":other.stats,"marriage":Politics.marriage_terms(world,actor.id,other.id)})
			state.contacts = state.contacts.slice(0,32)
		if not vessel.is_empty() and actor.loc == 0 and not game.galaxy:
			var wreck_list := []
			for wid in world.wrecks:
				var w: Dictionary = world.wrecks[wid]
				if int(w.get("system", -1)) == system_index and (w.stock.max() > 0 or int(w.get("hull", -1)) >= 0):
					wreck_list.append({"id":wid,"pos":coords(w.pos),"distance":roundf(Vector2(vessel.pos).distance_to(w.pos)),"stock":w.stock.duplicate(),"hull":int(w.get("hull",-1))})
			state.wrecks = wreck_list
	return state

func new_game(args: Dictionary) -> Dictionary:
	var seed_value: Variant = args.get("seed","agent-demo")
	var label: Variant = args.get("name","航务代理")
	var noble: Variant = args.get("noble",false)
	var count := integer(args,"systems",24,12,48)
	var groups := integer(args,"factions",5,3,8)
	if not seed_value is String or seed_value.length() not in range(1,41) or not label is String or label.strip_edges().is_empty() or label.length() > 16 or not noble is bool or groups < 3 or count < 12:
		return failure("invalid_new_game")
	var random := RandomNumberGenerator.new()
	random.seed = hash(seed_value + ":agent-portrait")
	var role_arg: Variant = args.get("role", 0)
	var station_master := 0
	if role_arg is String:
		station_master = 1 if role_arg == "independent_manager" else (2 if role_arg == "employed_manager" else 0)
	elif role_arg is int or role_arg is float:
		station_master = clampi(int(role_arg), 0, 2)
	var options := {"seed":seed_value,"systems":count,"factions":groups,"avatar":{"name":label,"house":"远岚","age":26,"origin":0,"trait":0,
		"noble":noble,"station_master":station_master,"look":Portrait.random_look(random)}}
	if not game.world.new_game(options):
		return failure("invalid_world_dimensions")
	game.run_bridge()
	return success()

func navigation(args: Dictionary, vessel: Dictionary) -> Dictionary:
	if vessel.is_empty() or vessel.dock != 0:
		return failure("not_in_flight")
	var world = game.world
	var destination: Variant = args.get("kind")
	var point := Vector2.ZERO
	if destination == "gravity" and not game.galaxy:
		point = Celestial.gravity_point(world.systems[vessel.system])
	elif destination == "mine" and not game.galaxy:
		point = world.systems[vessel.system].field
	elif destination == "port" and not game.galaxy:
		var id := integer(args,"target",-1,1,2147483647)
		if not world.ports.has(id) or world.ports[id].system != vessel.system:
			return failure("unknown_local_port")
		game.track_port(world.ports[id])
		return success()
	elif destination in ["planet","survey","construction_orbit"] and not game.galaxy:
		var index := integer(args,"target",-1,0,world.systems[vessel.system].planets.size()-1)
		if index < 0:
			return failure("unknown_planet")
		if destination == "construction_orbit":
			game.track_construction_orbit(index)
		else:
			game.track_planet(index,destination == "planet")
		return success()
	elif destination == "system" and game.galaxy:
		var id := integer(args,"target",-1,0,world.systems.size()-1)
		if id < 0:
			return failure("unknown_system")
		point = world.systems[id].pos
	elif destination == "point":
		var value: Variant = vector(args.get("pos"))
		if value == null:
			return failure("invalid_waypoint")
		point = value
	else:
		return failure("wrong_navigation_layer")
	var label := "坐标航点"
	match destination:
		"gravity": label = "恒星引力点"
		"mine": label = "矿带"
		"system": label = world.systems[int(args.target)].name
	game.set_waypoint(point,label)
	return success()

func advance(args: Dictionary) -> Dictionary:
	var step := prepare_step(args)
	if step.has("error"):
		return step
	run_step(step,step.ticks)
	return finish_step(step)

func prepare_step(args: Dictionary) -> Dictionary:
	var world = game.world
	var steps := integer(args,"ticks",60,1,1800)
	var speed := integer(args,"speed",1,1,5)
	var move: Variant = vector(args.get("move",[0,0]))
	var aim: Variant = vector(args.get("aim",[0,0]))
	var gun: Variant = args.get("fire",false)
	var shield_hold: Variant = args.get("shield",false)
	var boost: Variant = args.get("boost", false)
	var has_aim := args.has("aim")
	var target_id := integer(args,"target",0,0,2147483647)
	var halt: Variant = args.get("stop","encounter")
	if steps < 1 or speed < 1 or move == null or aim == null or not gun is bool or not shield_hold is bool or not boost is bool or target_id < 0 or halt not in ["encounter","arrival","event","never"]:
		return failure("invalid_step")
	var vessel: Dictionary = world.ride()
	if args.has("target") and target_id != 0 and not visible_target(vessel,target_id):
		return failure("unknown_target")
	if not vessel.is_empty() and vessel.dock == 0 and speed > 1:
		if vessel.locked:
			return failure("speed_restricted_locked", "交战锁定状态下不可使用高于 1 档的倍速")
		if not game.waypoint_live:
			return failure("speed_restricted_no_waypoint", "未设置航点时不可在太空使用高于 1 档的倍速")
		if move != Vector2.ZERO:
			return failure("speed_restricted_manual_move", "手动方向控制时不可同时使用倍速")
	if gun and not has_aim and target_id == 0:
		return failure("aim_required")
	game.set_speed(speed)
	var start_pos: Vector2 = Vector2.ZERO if vessel.is_empty() else (vessel.galpos if game.galaxy else vessel.pos)
	var start_fuel: float = float(vessel.get("fuel", 0.0))
	return {"ticks":steps,"processed":0,"stopped":"","stop":halt,"move":Vector2(move).limit_length(),
		"shield":shield_hold,"fire":gun,"boost":boost,"aim":aim,"has_aim":has_aim,"target":target_id,
		"original":world.player,"initial_waypoint":game.waypoint_live,"start_day":world.day,
		"start_pos":start_pos,"start_fuel":start_fuel}

## Windowed and batch sessions advance the exact same fixed ticks and stop conditions.
func run_step(step: Dictionary, count: int) -> bool:
	var world = game.world
	for tick in mini(count,int(step.ticks)-int(step.processed)):
		if step.stop == "event" and Society.pending_count(world) > 0:
			step.stopped = "event"
			break
		if world.succession or world.attention or world.player != step.original:
			step.stopped = "attention"
			break
		var vessel: Dictionary = world.ride()
		var had_contact: bool = vessel.get("locked",false)
		var point: Vector2 = step.aim
		var has_target := false
		if step.target != 0 and not vessel.is_empty():
			has_target = visible_target(vessel,step.target)
			if has_target:
				point = world.ships[step.target].pos
				game.selected_target = step.target
			elif not step.has_aim:
				step.stopped = "target_lost"
				break
		game.step_simulation(step.move,step.shield,step.fire and (step.has_aim or has_target),point,step.has_aim or has_target,step.boost)
		step.processed += 1
		if not had_contact and vessel.get("locked",false) and step.stop != "never":
			step.stopped = "encounter"
			break
		if step.initial_waypoint and not game.waypoint_live and step.stop == "arrival":
			step.stopped = "arrival"
			break
	if step.stop == "event" and Society.pending_count(world) > 0:
		step.stopped = "event"
	elif world.attention or world.succession:
		step.stopped = "attention"
	elif step.stopped == "" and step.processed >= step.ticks:
		step.stopped = "tick_limit"
	return step.stopped != ""

func finish_step(step: Dictionary) -> Dictionary:
	game.speed = 0
	game.refresh()
	var world = game.world
	var vessel: Dictionary = world.ride()
	var end_pos: Vector2 = Vector2.ZERO if vessel.is_empty() else (vessel.galpos if game.galaxy else vessel.pos)
	var dist_moved := 0.0 if vessel.is_empty() else end_pos.distance_to(step.get("start_pos", end_pos))
	var fuel_spent := 0.0 if vessel.is_empty() else maxf(0.0, float(step.get("start_fuel", vessel.get("fuel", 0.0))) - float(vessel.get("fuel", 0.0)))
	var payload := {
		"ticks": step.processed,
		"stopped": step.stopped,
		"days_elapsed": world.day - int(step.get("start_day", world.day)),
		"distance_moved": snappedf(dist_moved, 0.01),
		"fuel_spent": snappedf(fuel_spent, 0.01),
		"waypoint_live": game.waypoint_live,
		"dock": int(vessel.get("dock", 0)),
	}
	if not vessel.is_empty() and dist_moved < 0.01:
		if int(vessel.dock) != 0:
			payload.idle_reason = "docked"
		elif world.attention or world.succession:
			payload.idle_reason = "attention_pending"
		elif game.galaxy and float(vessel.fuel) <= 0.0:
			payload.idle_reason = "no_fuel"
		elif not game.waypoint_live and Vector2(step.get("move", Vector2.ZERO)).is_zero_approx():
			payload.idle_reason = "no_waypoint_or_controls"
	return success(payload)

func visible_target(vessel: Dictionary, target_id: int) -> bool:
	if vessel.is_empty() or game.galaxy or vessel.dock != 0:
		return false
	var world = game.world
	var target: Dictionary = world.ships.get(target_id,{})
	return not target.is_empty() and target.id != vessel.id and Battle.available(target,vessel.system) and target.pos.distance_to(vessel.pos) <= 680.0 and game.flight.visible_contact(vessel,target)

func dispatch(action: String, args: Dictionary) -> Dictionary:
	if bound_actor_id > 0 and game != null and game.playing and game.world.people.has(bound_actor_id):
		var world = game.world
		var prev_player := int(world.player)
		var prev_last := int(world.last_player)
		if bound_actor_id != prev_player:
			world.player = bound_actor_id
		var res := _dispatch_inner(action, args)
		if bound_actor_id != prev_player:
			world.player = prev_player
			world.last_player = prev_last
		return res
	return _dispatch_inner(action, args)

func resolve_save_path(slot: Variant) -> String:
	var key := str(slot if slot != null else "main").strip_edges().to_lower()
	match key:
		"", "main": return game.SAVE
		"auto": return game.AUTO
		"before": return game.BEFORE
	if key.length() > 32:
		return ""
	for i in key.length():
		var code := key.unicode_at(i)
		var ok := (code >= 48 and code <= 57) or (code >= 97 and code <= 122) or code == 95 or code == 45
		if not ok:
			return ""
	return "user://agent_%s.save" % key

func list_save_slots() -> Array:
	var entries := []
	var presets := {"main": game.SAVE, "auto": game.AUTO, "before": game.BEFORE}
	for slot in presets:
		var path: String = presets[slot]
		if FileAccess.file_exists(path):
			entries.append({"slot": slot, "path": path, "modified": FileAccess.get_modified_time(path)})
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while not fname.is_empty():
			if not dir.current_is_dir() and fname.begins_with("agent_") and fname.ends_with(".save"):
				var slot_name := fname.trim_prefix("agent_").trim_suffix(".save")
				var full := "user://" + fname
				entries.append({"slot": slot_name, "path": full, "modified": FileAccess.get_modified_time(full)})
			fname = dir.get_next()
		dir.list_dir_end()
	return entries

func _dispatch_inner(action: String, args: Dictionary) -> Dictionary:
	if action == "observe":
		return success()
	if action == "set_intent":
		var text_value: Variant = args.get("text")
		var target_value: Variant = args.get("target","")
		if not text_value is String or text_value.strip_edges().is_empty() or text_value.length() > 120 or not target_value is String or target_value.length() > 64:
			return failure("invalid_intent")
		intention = {"text":text_value.strip_edges(),"target":target_value.strip_edges()}
		return success({"intent":intention.duplicate()})
	if action == "watch_frame":
		if not watch_mode or DisplayServer.get_name() == "headless" or not is_instance_valid(game.agent_overlay):
			return failure("watch_required")
		var frame := game.get_viewport().get_texture().get_image() as Image
		if frame == null or frame.save_png(directory.path_join("watch.png")) != OK:
			return failure("frame_unavailable")
		return success({"file":"watch.png"})
	if action == "quit":
		return {"ok":true,"quit":true}
	if action == "new_game":
		return new_game(args)
	if action == "list_saves":
		return success({"saves": list_save_slots()})
	if action == "load_game":
		var path := resolve_save_path(args.get("slot", "main"))
		if path.is_empty() or not FileAccess.file_exists(path):
			return failure("save_not_found")
		if not game.Saves.read(game.world, path):
			return failure("save_corrupt")
		if game.arena != null and game.arena.active:
			game.arena.stop_arena(false)
		game.run_bridge()
		return success({"slot": str(args.get("slot", "main")), "path": path, "day": game.world.day})
	if not game.playing:
		return failure("start_new_game")
	var world = game.world
	if world.succession:
		if action == "choose_successor" and Politics.choose(world,integer(args,"id",-1,1,2147483647)):
			game.run_bridge()
			return success()
		return failure("choose_successor")
	var vessel: Dictionary = world.ride()
	match action:
		"market_quote":
			var port: Dictionary = world.ports.get(vessel.get("dock",0),{})
			var ware := integer(args,"ware",-1,0,world.WARES.size()-1)
			var units := integer(args,"amount",0,-2147483647,2147483647)
			var black: Variant = args.get("black",false)
			if port.is_empty() or ware < 0 or units < -2147483647 or units == 0 or not black is bool:
				return failure("invalid_trade")
			if port.build > 0 or (not world.is_regular(port) if black else not Economy.allowed(world,vessel,port)):
				return failure("market_closed")
			return success(Economy.trade_invoice(world,port,ware,units,black))
		"freight_offer","accept_freight":
			var port: Dictionary = world.ports.get(vessel.get("dock",0),{})
			if port.is_empty():
				return failure("not_docked")
			var offer := FreightNotice.offer(world,port)
			if action == "freight_offer":
				var result := {"offer":offer}
				if not offer.is_empty():
					var dest: Dictionary = world.ports[offer.target]
					result.destination = {"system":dest.system,"system_name":world.systems[dest.system].name,"port":dest.id,"name":dest.name}
					result.route = Economy.flight_route(world,port.system,dest.system,Economy.MerchantSecurity.exclusions(world,vessel))
				return success(result)
			var submitted: Variant = args.get("offer")
			if offer.is_empty() or not submitted is Dictionary:
				return failure("freight_unavailable")
			for key: String in offer:
				if integer(submitted,key,-1,0,2147483647) != int(offer[key]):
					return failure("freight_offer_changed")
			if not FreightNotice.accept(world,offer):
				return failure("freight_unavailable")
			return success({"accepted":true})
		"deliver_freight":
			var port: Dictionary = world.ports.get(vessel.get("dock",0),{})
			var paid := FreightNotice.deliver(world,port) if not port.is_empty() else 0
			return success({"paid":paid}) if paid > 0 else failure("delivery_unavailable")
		"marriage_terms":
			return success(Politics.marriage_terms(world,world.player,integer(args,"target",0,1,2147483647),true))
		"trade_partners":
			return success({"partners":world.DiplomaticTrade.contacts(world)})
		"trade_catalog","preview_deal","propose_deal":
			var kind: String = str(args.get("kind",""))
			var party := integer(args,"id",-1,0,2147483647)
			if kind not in ["person","company","station","faction"] or party < 0 or not args.get("black",false) is bool:
				return failure("invalid_trade_partner")
			if action == "trade_catalog":
				return success(world.DiplomaticTrade.catalog(world,kind,party,args.get("black",false)))
			if not args.get("give") is Array or not args.get("want") is Array:
				return failure("invalid_trade_terms")
			if action == "preview_deal":
				return success(world.DiplomaticTrade.preview(world,kind,party,args.give,args.want,args.get("black",false)))
			return success(world.DiplomaticTrade.propose(world,kind,party,args.give,args.want,args.get("black",false)))
		"confirm_deal","cancel_deal":
			var id := integer(args,"deal_id",0,1,2147483647)
			if action == "confirm_deal":
				return success(world.DiplomaticTrade.confirm(world,id))
			return success({"cancelled":world.DiplomaticTrade.cancel(world,id)})
		"financial_report":
			var days := integer(args,"days",30,1,world.Finances.RETENTION)
			if days < 1:
				return failure("invalid_period")
			return success(world.Finances.report(world,days))
		"debug_ship":
			var id := integer(args,"ship",0,1,2147483647)
			var report := Economy.Diagnostics.snapshot(world,id)
			if report.is_empty():
				return failure("ship_unavailable")
			report["speed"] = game.speed
			return success(report)
		"save_game":
			var path := resolve_save_path(args.get("slot", "main"))
			if path.is_empty():
				return failure("invalid_save_slot")
			if vessel.get("locked", false) and path != game.BEFORE:
				return failure("in_combat")
			if not game.Saves.write(world, path, path == game.BEFORE):
				return failure("save_write_failed")
			return success({"slot": str(args.get("slot", "main")), "path": path, "day": world.day})
		"capabilities":
			return success({
				"protocol": PROTOCOL,
				"allow_cheats": allow_cheats,
				"tactics": game.COMBAT_TACTICS,
				"new_actions": ["people", "person_info", "factions", "systems", "hull_catalog", "weapon_catalog", "interact", "list_saves", "save_game", "load_game", "set_tactic", "cheat", "capabilities"],
				"cheat_kinds": ["credits", "fuel", "repair", "trust", "opinion", "tick", "reveal"] if allow_cheats else []
			})
		"interact","object_actions":
			var kind := str(args.get("kind", ""))
			var oid := int(args.get("id", 0))
			var sub := str(args.get("action", "inspect"))
			var sys_id := int(args.get("system", game.current_system()))
			match kind:
				"ship":
					var target_ship: Dictionary = world.ships.get(oid, {})
					if target_ship.is_empty():
						return failure("unknown_ship")
					var acts := ["inspect", "captain_info"]
					if not vessel.is_empty() and target_ship.id != vessel.id and Battle.available(target_ship, vessel.system) and game.flight.visible_contact(vessel, target_ship):
						acts.append_array(["target", "attack", "follow"])
					if sub == "inspect":
						return success({"kind":kind,"id":oid,"model":world.HULLS[target_ship.kind],"captain":target_ship.captain,"flag":world.flag_name(target_ship.flag),"hp":target_ship.hp,"actions":acts})
					elif sub == "captain_info":
						return dispatch("person_info", {"person": target_ship.captain})
					elif sub == "target":
						game.selected_target = oid
						return success({"selected_target": oid})
					elif sub == "attack":
						return success({"attacked": game.flight.attack_target(oid)})
					elif sub == "follow":
						game.set_waypoint(Vector2(target_ship.pos), world.HULLS[target_ship.kind], func(): return target_ship.pos)
						return success({"following": oid})
					return failure("invalid_object_action")
				"port":
					var st: Dictionary = world.ports.get(oid, {})
					if st.is_empty():
						return failure("unknown_port")
					var acts := ["inspect", "navigate", "dock"]
					if sub == "inspect":
						return success({"kind":kind,"id":oid,"name":st.name,"system":st.system,"flag":world.flag_name(st.flag),"manager":st.manager,"actions":acts})
					elif sub == "navigate":
						game.navigate_to_station(oid)
						return success({"navigating_to": oid})
					elif sub == "dock":
						return dispatch("dock", {})
					return failure("invalid_object_action")
				"wreck":
					var wr: Dictionary = world.wrecks.get(oid, {})
					if wr.is_empty():
						return failure("unknown_wreck")
					if sub == "inspect":
						return success({"kind":kind,"id":oid,"system":wr.system,"pos":coords(wr.pos),"stock":wr.stock,"actions":["inspect","waypoint","salvage"]})
					elif sub == "waypoint":
						game.set_waypoint(Vector2(wr.pos), "残骸 #%d" % oid)
						return success({"waypoint": coords(wr.pos)})
					elif sub == "salvage":
						return dispatch("mine_or_salvage", {})
					return failure("invalid_object_action")
				"field":
					if sys_id not in range(world.systems.size()):
						return failure("unknown_system")
					var reg: Dictionary = world.systems[sys_id]
					if sub == "inspect":
						return success({"kind":kind,"system":sys_id,"ore":int(reg.get("ore",0)),"pos":coords(reg.field),"actions":["inspect","waypoint","mine"]})
					elif sub == "waypoint":
						game.set_waypoint(Vector2(reg.field), "矿带")
						return success({"waypoint": coords(reg.field)})
					elif sub == "mine":
						return dispatch("mine_or_salvage", {})
					return failure("invalid_object_action")
				"gravity":
					if sys_id not in range(world.systems.size()):
						return failure("unknown_system")
					var reg: Dictionary = world.systems[sys_id]
					var gp := Celestial.gravity_point(reg)
					if sub == "inspect":
						return success({"kind":kind,"system":sys_id,"pos":coords(gp),"actions":["inspect","waypoint","jump"]})
					elif sub == "waypoint":
						game.set_waypoint(gp, "恒星引力点")
						return success({"waypoint": coords(gp)})
					elif sub == "jump":
						return dispatch("jump", {})
					return failure("invalid_object_action")
				"planet":
					if sys_id not in range(world.systems.size()) or oid not in range(world.systems[sys_id].planets.size()):
						return failure("unknown_planet")
					var pl: Dictionary = world.systems[sys_id].planets[oid]
					if sub == "inspect":
						return success({"kind":kind,"id":oid,"name":pl.name,"surveyed":pl.get("surveyed",false),"port_id":pl.get("port_id",0),"actions":["inspect","waypoint"]})
					elif sub == "waypoint":
						game.track_planet(oid)
						return success({"tracking_planet": oid})
					return failure("invalid_object_action")
				"system":
					if oid not in range(world.systems.size()):
						return failure("unknown_system")
					var sys: Dictionary = world.systems[oid]
					if sub == "inspect":
						return success({"kind":kind,"id":oid,"name":sys.name,"pos":coords(sys.pos),"seen":sys.get("seen",false),"actions":["inspect","waypoint"]})
					elif sub == "waypoint":
						if game.galaxy:
							game.set_waypoint(Vector2(sys.pos), sys.name)
						return success({"waypoint": coords(sys.pos)})
					return failure("invalid_object_action")
				_:
					return failure("invalid_object_kind")
		"factions":
			var viewer_id := int(world.player)
			var list := []
			for fid: int in world.factions:
				var f: Dictionary = world.factions[fid]
				var treaties := {}
				for other_id: int in world.factions:
					if other_id != fid and world.factions[other_id].get("alive", false):
						treaties[other_id] = int(world.treaty(fid, other_id).get("state", 0))
				list.append({
					"flag": fid,
					"name": world.flag_name(fid),
					"alive": f.get("alive", false),
					"leader": int(f.get("leader", 0)),
					"leader_name": world.name_of(int(f.get("leader", 0))),
					"capital": int(f.get("capital", 0)),
					"treasury": int(f.get("treasury", 0)),
					"systems": world.systems_owned(fid).size(),
					"player_trust": world.faction_trust(fid, viewer_id),
					"treaties": treaties
				})
			return success({"factions": list})
		"systems":
			var cur_sys := int(game.current_system())
			var list := []
			for sid in range(world.systems.size()):
				var sys: Dictionary = world.systems[sid]
				var port_ids := []
				for pid in world.ports:
					if int(world.ports[pid].system) == sid:
						port_ids.append(int(pid))
				list.append({
					"id": sid,
					"name": sys.name,
					"pos": coords(sys.pos),
					"seen": sys.get("seen", false),
					"ore": int(sys.get("ore", 0)),
					"planets": sys.get("planets", []).size(),
					"ports": port_ids,
					"distance": snappedf(world.distance(cur_sys, sid), 0.1)
				})
			return success({"current_system": cur_sys, "systems": list})
		"hull_catalog":
			var size_filter: Variant = args.get("size", null)
			var market_only: bool = bool(args.get("market_only", false))
			var list := []
			for kind in range(Hulls.MODELS.size()):
				var m: Dictionary = Hulls.MODELS[kind]
				var c: Dictionary = Hulls.COMBAT[kind]
				if size_filter != null and int(m.size) != int(size_filter):
					continue
				if market_only and not Hulls.available_for_market(kind):
					continue
				list.append({
					"kind": kind,
					"id": Hulls.hull_id(kind),
					"name": m.name,
					"class": Hulls.CLASS_NAMES[m.size],
					"role": m.role,
					"hp": int(m.hp),
					"armor": float(c.armor),
					"capacity": float(c.capacity),
					"dissipation": float(c.dissipation),
					"op": int(c.op),
					"cargo": int(m.cargo),
					"dp": int(m.dp),
					"mounts": m.mounts.size(),
					"fighter_bays": int(m.fighter_bays),
					"price": int(m.price),
					"market": Hulls.available_for_market(kind)
				})
			return success({"hulls": list})
		"weapon_catalog":
			var list := []
			for wid in Hulls.WEAPONS:
				var w: Dictionary = Hulls.WEAPONS[wid]
				list.append({
					"id": wid,
					"name": w.name,
					"size": int(w.size),
					"type": int(w.type),
					"op": int(w.op),
					"range": float(w.range),
					"damage": float(w.damage),
					"flux": float(w.get("flux", 0.0))
				})
			return success({"weapons": list})
		"faction_trust":
			var person := integer(args,"person",world.player,1,2147483647)
			if not world.people.has(person):
				return failure("unknown_person")
			var scores := []
			for flag: int in world.factions:
				var history: Dictionary = world.people[person].get("faction_trust",{}).get(flag,{})
				scores.append({"flag":flag,"name":world.flag_name(flag),"score":world.faction_trust(flag,person),"last_change":history})
			return success({"person":person,"factions":scores})
		"people":
			var filter_flag: Variant = args.get("flag", null)
			var filter_loc: Variant = args.get("loc", null)
			var filter_noble: Variant = args.get("noble", null)
			var needle := str(args.get("query", "")).strip_edges().to_lower()
			var limit := integer(args, "limit", 40, 1, 100)
			var viewer: Dictionary = world.active()
			var list := []
			for p in world.people.values():
				if not p.alive:
					continue
				if filter_flag != null and int(p.flag) != int(filter_flag):
					continue
				if filter_loc != null and int(p.loc) != int(filter_loc):
					continue
				if filter_noble is bool and bool(p.noble) != bool(filter_noble):
					continue
				if not needle.is_empty():
					var hay := "%s %s %s %s" % [p.name, p.get("house",""), world.TRAITS[p.trait], world.flag_name(p.flag)]
					if not hay.to_lower().contains(needle):
						continue
				var prof := ShareholderRelations.profile(world, p.id)
				list.append({
					"id":p.id,"name":p.name,"age":Politics.age(world,p),"gender":"女" if int(p.get("gender",0)) == 1 else "男",
					"noble":p.noble,"house":p.get("house",""),"flag":p.flag,"flag_name":world.flag_name(p.flag),
					"trait":world.TRAITS[p.trait],"loc":p.loc,"loc_name":world.ports[p.loc].name if p.loc != 0 and world.ports.has(p.loc) else "",
					"ship":p.ship,"opinion":Politics.opinion(world,p.id,viewer.id),
					"relation":viewer.get("relations",{}).get(p.id,""),"roles":prof.get("roles",[])})
			return success({"count":list.size(),"people":list.slice(0, limit)})
		"person_info","person_dossier":
			var person_id := integer(args,"person",world.player,1,2147483647)
			if not world.people.has(person_id):
				return failure("unknown_person")
			var p: Dictionary = world.people[person_id]
			var viewer: Dictionary = world.active()
			var prof := ShareholderRelations.profile(world, person_id)
			var sup_id: int = world.reports_to(p)
			var leader_id: int = world.factions.get(p.flag, {}).get("leader", 0)
			var subs := []
			var children_list := []
			var op_list := []
			for other in world.people.values():
				if not other.alive or other.id == person_id:
					continue
				if world.reports_to(other) == person_id:
					subs.append({"id":other.id,"name":other.name,"roles":ShareholderRelations.profile(world,other.id).get("roles",[])})
				if int(other.get("father", 0)) == person_id or int(other.get("mother", 0)) == person_id:
					children_list.append({"id":other.id,"name":other.name,"age":Politics.age(world,other)})
				var op_val := Politics.opinion(world, person_id, other.id)
				var rel_tag := str(p.get("relations", {}).get(other.id, ""))
				if op_val != 0 or not rel_tag.is_empty():
					op_list.append({"id":other.id,"name":other.name,"flag_name":world.flag_name(other.flag),"opinion":op_val,"relation":rel_tag})
			op_list.sort_custom(func(a, b): return absi(int(a.opinion)) > absi(int(b.opinion)))
			var f_scores := []
			for fid: int in world.factions:
				var hist: Dictionary = p.get("faction_trust", {}).get(fid, {})
				f_scores.append({"flag":fid,"name":world.flag_name(fid),"score":world.faction_trust(fid, person_id),"last_change":hist})
			var ref_person := func(pid: int):
				if pid <= 0 or not world.people.has(pid):
					return null
				var rp: Dictionary = world.people[pid]
				return {"id":pid,"name":rp.name,"alive":rp.alive,"flag_name":world.flag_name(rp.flag)}
			return success({
				"id":p.id,"name":p.name,"alive":p.alive,"age":Politics.age(world,p),"gender":"女" if int(p.get("gender",0)) == 1 else "男",
				"noble":p.noble,"house":p.get("house",""),"flag":p.flag,"flag_name":world.flag_name(p.flag),
				"trait":world.TRAITS[p.trait],"traits":world.Society.trait_labels(p),"stats":p.stats,
				"stress":p.get("stress",0),"merit":p.get("merit",0),"wallet":p.wallet,
				"loc":p.loc,"loc_name":world.ports[p.loc].name if p.loc != 0 and world.ports.has(p.loc) else "","ship":p.ship,
				"roles":prof.get("roles",[]),
				"superior":ref_person.call(sup_id) if sup_id != person_id else null,
				"faction_leader":ref_person.call(leader_id) if leader_id != person_id else null,
				"subordinates":subs,
				"family":{"father":ref_person.call(int(p.get("father",0))),"mother":ref_person.call(int(p.get("mother",0))),"spouse":ref_person.call(int(p.spouse)),"children":children_list},
				"relations":p.get("relations",{}),"hooks":p.get("hooks",{}).keys(),
				"opinion_toward_player":Politics.opinion(world,person_id,viewer.id),
				"player_relation":viewer.get("relations",{}).get(person_id,""),
				"marriage_terms":Politics.marriage_terms(world,viewer.id,person_id),
				"opinions":op_list.slice(0, 16),
				"faction_trust":f_scores})
		"cheat":
			if not allow_cheats:
				return failure("cheats_disabled_by_player")
			var kind := str(args.get("kind", ""))
			var actor: Dictionary = world.active()
			match kind:
				"credits":
					var delta := clampi(int(args.get("amount", 1000)), -5000, 5000)
					actor.wallet = maxi(0, int(actor.wallet) + delta)
					return success({"kind": kind, "credits": actor.wallet})
				"fuel":
					if vessel.is_empty():
						return failure("no_ship")
					vessel.fuel = 100.0
					return success({"kind": kind, "fuel": vessel.fuel})
				"repair":
					var repaired := 0
					for s in world.ships.values():
						if world.oversees(s.owner):
							s.hp = float(Hulls.MODELS[s.kind].hp)
							s.battle.armor = float(Hulls.COMBAT[s.kind].armor)
							repaired += 1
					return success({"kind": kind, "repaired": repaired})
				"trust":
					var flag := integer(args, "flag", -1, 0, 2147483647)
					if not world.factions.has(flag):
						return failure("unknown_faction")
					var delta := clampi(int(args.get("amount", 15)), -30, 30)
					world.change_faction_trust(flag, world.player, delta, "调试调整")
					return success({"kind": kind, "flag": flag, "score": world.faction_trust(flag, world.player)})
				"opinion":
					var pid := integer(args, "person", -1, 1, 2147483647)
					if not world.people.has(pid) or not world.people[pid].alive:
						return failure("unknown_person")
					var delta := clampi(int(args.get("amount", 15)), -30, 30)
					var target_p: Dictionary = world.people[pid]
					target_p.opinions[world.player] = clampi(int(target_p.opinions.get(world.player, 0)) + delta, -100, 100)
					return success({"kind": kind, "person": pid, "opinion": Politics.opinion(world, pid, world.player)})
				"tick":
					var days := clampi(int(args.get("days", 1)), 1, 30)
					world.tick(days)
					return success({"kind": kind, "day": world.day})
				"reveal":
					for sys_idx in range(world.systems.size()):
						world.mark_seen(sys_idx)
					return success({"kind": kind, "systems": world.systems.size()})
				_:
					return failure("invalid_cheat_kind")
		"enact_securities_law":
			return success(world.TradeLaw.enact(world,integer(args,"flag",-1,0,2147483647),str(args.get("code",""))))
		"my_share_listings":
			return success({"listings":world.ShareExchange.listings(world)})
		"cancel_share_listing":
			return success({"cancelled":world.ShareExchange.cancel(world,integer(args,"listing_id",0,1,2147483647))})
		"quote_share_order","sign_share_order":
			var order_id := integer(args,"order_id",0,1,2147483647)
			var quantity := integer(args,"quantity",0,1,2147483647)
			if action == "quote_share_order":
				return success(world.DiplomaticTrade.quote_order(world,order_id,quantity))
			return success(world.DiplomaticTrade.sign_order(world,order_id,quantity,integer(args,"unit_price",0,1,2147483647)))
		"stock_quote","post_share_listing":
			var scope := str(args.get("kind",""))
			var id := integer(args,"id",0,1,2147483647)
			if world.Capital.entity(world,scope,id).is_empty():
				return failure("unknown_equity")
			if action == "stock_quote":
				return success(world.StockPrices.quote(world,scope,id))
			return success(world.ShareExchange.post(world,scope,id,integer(args,"quantity",0,1,2147483647),integer(args,"unit_price",0,1,2147483647)))
		"share_capital","securities_law","request_share_permit","issue_shares","solicit_issue","subscribe_shares","withdraw_issue":
			var scope := str(args.get("kind",""))
			var id := integer(args,"id",0,1,2147483647)
			if world.Capital.entity(world,scope,id).is_empty():
				return failure("unknown_equity")
			match action:
				"share_capital":
					return success(world.Capital.overview(world,scope,id))
				"securities_law":
					return success(world.TradeLaw.jurisdiction(world,scope,id))
				"request_share_permit":
					return success(world.TradeLaw.request_permit(world,scope,id))
				"withdraw_issue":
					return success({"cancelled":world.Capital.cancel(world,scope,id)})
			var qty := integer(args,"quantity",0,1,2147483647)
			var price := integer(args,"unit_price",0,1,2147483647)
			if qty < 1 or price < 1:
				return failure("invalid_issue_terms")
			if action == "issue_shares":
				return success(world.Capital.authorize(world,scope,id,qty,price))
			if action == "solicit_issue":
				return success(world.Capital.solicit(world,scope,id,qty,price))
			var offer_id := integer(args,"offer_id",0,1,2147483647)
			if offer_id < 1:
				return failure("signed_issue_required")
			return success(world.Capital.subscribe(world,scope,id,qty,price,offer_id))
		"equity_catalog":
			var companies := []
			var stations := []
			for id: int in world.firms:
				companies.append({"id":id,"name":world.firms[id].name,"shares":world.active().shares.get(id,0)})
			for site: Dictionary in world.ports.values():
				var table: Dictionary = world.StationEquity.cap_table(world,site)
				if world.StationEquity.listed(world,site):
					stations.append({"id":site.id,"name":site.name,"shares":table.people.get(world.player,0)})
			return success({"companies":companies,"stations":stations})
		"equity_person":
			var person_id := integer(args,"person",0,1,2147483647)
			if not world.people.has(person_id):
				return failure("unknown_person")
			return success(ShareholderRelations.profile(world,person_id))
		"cancel_equity_inquiry":
			if not world.EquityOrders.cancel(world,integer(args,"order_id",0,1,2147483647)):
				return failure("cancel_rejected")
			return success()
		"equity","trade_equity","equity_inquiry","equity_preview":
			var company: bool = args.get("kind","") == "company"
			if not company and args.get("kind","") != "station":
				return failure("invalid_equity_kind")
			var id := integer(args,"id",0,1,2147483647)
			if (company and not world.firms.has(id)) or (not company and not world.ports.has(id)):
				return failure("unknown_equity")
			if not company and not world.StationEquity.listed(world,world.ports[id]):
				return failure("unknown_equity")
			if action != "equity":
				var party := integer(args,"counterparty",-2147483649,-2147483648,2147483647)
				var qty := integer(args,"quantity",0,1,2147483647)
				var price := integer(args,"expected_price" if action == "trade_equity" else "limit",0,1,2147483647)
				if not args.get("buying") is bool:
					return failure("invalid_side")
				if action == "equity_preview":
					return success(world.EquityOrders.preview(world,args.kind,id,party,qty,args.buying,price))
				if action == "equity_inquiry":
					return success(world.EquityOrders.propose(world,args.kind,id,party,qty,args.buying,price))
				var order_id := integer(args,"order_id",0,1,2147483647)
				if order_id <= 0:
					return failure("signed_order_required")
				var ok: bool = world.Equity.trade(world,id,party,qty,args.buying,price,order_id) if company else world.StationEquity.trade(world,world.ports[id],party,qty,args.buying,price,order_id)
				if not ok:
					return failure("equity_trade_rejected")
			var contacts: Array = world.EquityOrders.contacts(world,args.kind,id)
			if company:
				return success({"equity":world.Equity.overview(world,id),"contacts":contacts,"buy":world.Equity.offers(world,id,true),"sell":world.Equity.offers(world,id,false),"dividends":world.Dividends.company_statement(world,id)})
			var site: Dictionary = world.ports[id]
			return success({"equity":world.StationEquity.cap_table(world,site),"contacts":contacts,"buy":world.StationEquity.offers(world,site,true),"sell":world.StationEquity.offers(world,site,false),"dividends":world.Dividends.statement(world,site)})
		"board_support","board_vote","company_dividend_policy","pay_company_dividend":
			var id := integer(args,"company",0,1,2147483647)
			var firm: Dictionary = world.firms.get(id,{})
			if firm.is_empty():
				return failure("unknown_equity")
			if action == "board_support":
				return success(ShareholderRelations.request_support(world,id,integer(args,"person",0,1,2147483647)))
			if action == "board_vote":
				if not world.Equity.vote(world,id,integer(args,"candidate",0,1,2147483647)):
					return failure("vote_rejected")
			elif not world.oversees(firm.director):
				return failure("director_required")
			elif action == "company_dividend_policy":
				if not world.Dividends.configure_company(world,id,integer(args,"percent",-1,0,100),integer(args,"reserve",-1,0,2147483647)):
					return failure("policy_rejected")
			elif world.Dividends.settle_company(world,id) <= 0:
				return failure("nothing_payable")
		"station_finance","transfer_station_funds","set_dividend_policy","pay_dividend":
			var port: Dictionary = world.ports.get(integer(args,"port",world.active().loc,1,2147483647),{})
			if port.is_empty() or not world.Dividends.can_manage(world,port):
				return failure("station_finance_denied")
			match action:
				"transfer_station_funds":
					var units := integer(args,"amount",0,-2147483647,2147483647)
					if units < -2147483647 or units == 0 or not world.Treasury.transfer(world,port,world.player,units):
						return failure("transfer_rejected")
				"set_dividend_policy":
					if not world.Dividends.configure(world,port,integer(args,"percent",-1,0,100),integer(args,"reserve",-1,0,2147483647)):
						return failure("policy_rejected")
				"pay_dividend":
					if world.Dividends.settle(world,port) == 0:
						return failure("nothing_payable")
			return success(world.Dividends.statement(world,port))
		"set_operating_area":
			var limit := integer(args,"jumps",-1,0,int(Industry.RULES.operating_area.maximum_jumps))
			if not Economy.OperatingArea.configure(world,integer(args,"ship",0,1,2147483647),integer(args,"port",0,1,2147483647),limit):
				return failure("operating_area_rejected")
		"pilot_ship":
			if not world.pilot(integer(args,"ship",0,1,2147483647)):
				return failure("cannot_board")
		"refit_wing":
			if not args.get("wing_id") is String or not Economy.refit_wing(world,world.active().loc,integer(args,"bay",-1,0,100),args.wing_id):
				return failure("refit_rejected")
			watch_station_ui("港口", "refit", "代理操作：更换舰载联队 %s" % str(args.wing_id))
		"refit_preset":
			if not Economy.refit_preset(world,world.active().loc,str(args.get("preset",""))):
				return failure("refit_rejected")
			watch_station_ui("港口", "refit", "代理操作：套用整备预设 %s" % str(args.get("preset", "")))
		"refit_offers":
			var slot := integer(args,"slot",-1,0,100)
			if vessel.is_empty() or vessel.dock == 0 or slot not in range(vessel.fit.weapons.size()) or not args.get("black",false) is bool:
				return failure("invalid_refit_slot")
			var mount := Hulls.slot_spec(vessel.kind,slot)
			return success({"slot_id":mount.id,"family":mount.family,"size":mount.size,"builtin":mount.builtin,
				"current":vessel.fit.weapons[slot],"weapons":Economy.slot_offers(world,vessel.dock,slot,args.get("black",false))})
		"refit_slot","refit_quote":
			if not args.get("weapon") is String or not args.get("black",false) is bool:
				return failure("refit_rejected")
			var slot := integer(args,"slot",-1,0,100)
			var black: bool = args.get("black",false)
			var quote := Economy.refit_quote(world,world.active().loc,slot,args.weapon,black)
			if action == "refit_quote":
				if quote.has("current"):
					quote.before = Hulls.weapon_metrics(quote.current)
					quote.after = Hulls.weapon_metrics(args.weapon)
				return success(quote)
			if not quote.ok or not Economy.refit_slot(world,world.active().loc,slot,args.weapon,black):
				return failure("refit_rejected",quote.reason)
			watch_station_ui("港口", "refit", "代理操作：槽位 %d 换装 %s" % [slot + 1, str(args.weapon)])
			game.refresh()
			return success(quote)
		"refit_tuning":
			var caps := integer(args,"caps_delta",0,-1,1)
			var vents := integer(args,"vents_delta",0,-1,1)
			if caps < -1 or vents < -1 or not Economy.refit_tuning(world,world.active().loc,caps,vents):
				return failure("tuning_rejected")
			watch_station_ui("港口", "refit", "代理操作：调整电容/散热 (%+d / %+d)" % [caps, vents])
		"assign_role":
			var role_ship := integer(args,"ship",-1,1,2147483647)
			if not Economy.assign_role(world,role_ship,integer(args,"commander",-1,1,2147483647),str(args.get("role",""))):
				return failure("role_rejected")
			game.hud.selected_ship_id = role_ship
			watch_station_ui("资产", "", "代理操作：设置 #%d 编队职责 %s" % [role_ship, str(args.get("role", ""))])
		"set_default_behavior":
			var ship: Dictionary = world.ships.get(integer(args,"ship",-1,1,2147483647),{})
			if ship.is_empty() or not Economy.assign(world,ship.id,ship.captain,str(args.get("kind","")),integer(args,"source",0,0,2147483647),integer(args,"target",0,0,2147483647)):
				return failure("behavior_rejected")
			game.hud.selected_ship_id = ship.id
			watch_station_ui("资产", "", "代理操作：指派 #%d 长期行为 %s" % [ship.id, str(args.get("kind", ""))])
		"station_overview":
			var port: int = world.active().loc
			if port == 0:
				return failure("not_docked")
			return success(Economy.station_overview(world,port))
		"hire_builder":
			var offer: Dictionary = world.ConstructionContract.offer(world,world.active().loc)
			if not offer.ok:
				return failure("hire_rejected",offer.reason)
			if args.has("expected_fee") and integer(args,"expected_fee",-1,0,2147483647) != offer.fee:
				return failure("fee_changed")
			var id: int = world.ConstructionContract.hire(world,world.active().loc)
			if id == 0:
				return failure("hire_rejected")
			return success({"ship":id,"fee":offer.fee})
		"cancel_builder":
			if not world.ConstructionContract.cancel(world):
				return failure("no_cancellable_contract")
		"deploy_station":
			if vessel.is_empty():
				return failure("not_in_flight")
			var kind := integer(args,"module",-1,0,world.MODULES.size()-1)
			var issue := Economy.construction_issue(world,kind,vessel.pos)
			if not issue.is_empty():
				return failure("construction_rejected",issue)
			var site := Economy.deploy(world,kind,vessel.pos)
			return success({"port":site}) if site != 0 else failure("construction_rejected")
		"donate_materials":
			var delivered := Economy.donate(world,world.active().loc)
			return success({"quantity":delivered}) if delivered > 0 else failure("nothing_delivered")
		"found_planet_port":
			if not world.PlanetPorts.found(world,integer(args,"module",-1,0,world.MODULES.size()-1)):
				return failure("founding_rejected")
		"station_expand":
			if not Economy.expand(world,world.active().loc,integer(args,"module",-1,0,world.MODULES.size()-1)):
				return failure("expansion_rejected")
		"order_hull":
			if not Economy.order_hull(world,world.active().loc,Hulls.kind_for_id(str(args.get("hull_id","")))):
				return failure("order_rejected")
		"queue_dock":
			if not Economy.queue_order(world,integer(args,"ship",-1,1,2147483647),integer(args,"port",-1,1,2147483647)):
				return failure("order_rejected")
		"queue_fleet_order":
			if not Economy.queue_order(world,integer(args,"ship",-1,1,2147483647),integer(args,"port",-1,1,2147483647),str(args.get("kind","")),integer(args,"ware",-1,0,world.WARES.size()-1),integer(args,"quantity",0,1,2147483647)):
				return failure("order_rejected")
		"cancel_fleet_order":
			if not Economy.cancel_order(world,integer(args,"ship",-1,1,2147483647),integer(args,"index",-1,0,Economy.FleetOrder.LIMIT-1)):
				return failure("order_rejected")
		"supply_construction":
			if not Economy.supply_construction(world,integer(args,"ship",-1,1,2147483647),integer(args,"source",-1,1,2147483647),integer(args,"site",-1,1,2147483647)):
				return failure("construction_rejected")
		"set_method":
			if not Economy.set_method(world,world.active().loc,str(args.get("method",""))):
				return failure("method_rejected")
		"set_blacklist":
			if not args.get("blocked") is bool or not Economy.set_trade_rule(world,integer(args,"ship",-1,1,2147483647),str(args.get("scope","")),integer(args,"subject",-1,0,2147483647),args.blocked):
				return failure("rule_rejected")
		"assign_station_duty":
			if not Economy.assign_station_duty(world,integer(args,"ship",-1,1,2147483647),integer(args,"port",-1,1,2147483647),str(args.get("kind","站属贸易"))):
				return failure("station_duty_rejected")
		"lease_ship_to_station":
			if not Economy.lease_ship_to_station(world,integer(args,"ship",-1,1,2147483647),integer(args,"port",-1,1,2147483647),str(args.get("kind","站属贸易"))):
				return failure("lease_rejected")
		"end_ship_lease":
			if not Economy.end_ship_lease(world,integer(args,"ship",-1,1,2147483647)):
				return failure("end_lease_rejected")
		"transfer_ship_to_station":
			if not Economy.transfer_ship_to_station(world,integer(args,"ship",-1,1,2147483647),integer(args,"port",-1,1,2147483647),str(args.get("kind","站属贸易"))):
				return failure("transfer_ship_rejected")
		"appoint_manager":
			var port_id := integer(args,"port",world.active().loc,1,2147483647)
			var person_id := integer(args,"person",world.player,1,2147483647)
			if not Economy.manager(world,port_id,person_id):
				return failure("manager_rejected")
		"incorporate_station":
			var port_id := integer(args,"port",world.active().loc,1,2147483647)
			if not Economy.incorporate(world,port_id,str(args.get("name",""))):
				return failure("incorporate_rejected")
			return success({"firm":world.ports[port_id].firm})
		"incorporate_ship":
			var firm_id := Economy.incorporate_ship(world,integer(args,"ship",0,1,2147483647),str(args.get("name","")))
			return success({"firm":firm_id}) if firm_id else failure("incorporate_rejected")
		"contribute_ship":
			var id := integer(args,"ship",0,1,2147483647)
			var firm := integer(args,"firm",0,1,2147483647)
			return success({"ship":id,"firm":firm}) if Economy.contribute_ship(world,id,firm) else failure("contribution_rejected")
		"affiliate_station":
			var port_id := integer(args,"port",world.active().loc,1,2147483647)
			var firm_id := integer(args,"firm",-1,1,2147483647)
			if not world.Equity.affiliate(world,port_id,firm_id):
				return failure("affiliate_rejected")
		"found_faction":
			var port_id := integer(args,"port",world.active().loc,1,2147483647)
			var new_flag: int = Politics.found(world,str(args.get("name","")),port_id,integer(args,"regime",0,0,world.REGIMES.size()-1))
			if new_flag < 0:
				return failure("found_faction_rejected")
			return success({"flag":new_flag})
		"hire_crew":
			var moved: int = Economy.crew(world,integer(args,"amount",1,-10000,10000))
			if moved == 0:
				return failure("crew_rejected")
			return success({"moved":moved})
		"assign_ship":
			if not Economy.assign(world,integer(args,"ship",-1,1,2147483647),integer(args,"person",-1,1,2147483647),str(args.get("kind","贸易")),integer(args,"source",0,0,2147483647),integer(args,"target",0,0,2147483647)):
				return failure("assign_rejected")
		"diplomacy_action":
			var target := integer(args,"target_person",-1,1,2147483647)
			var ok := false
			match args.get("kind",""):
				"gift": ok = Politics.influence(world,target,true)
				"marry": ok = Politics.marry(world,world.player,target,true)
				"sway","find_secrets": ok = Society.scheme(world,target,args.kind)
				"use_hook": ok = Society.use_hook(world,target)
			if not ok:
				return failure("diplomacy_rejected")
		"ultimatum":
			if not args.get("concede") is bool or not Society.answer_ultimatum(world,integer(args,"flag",-1,0,2147483647),args.concede):
				return failure("ultimatum_rejected")
		"resolve_scheme":
			if not Society.resolve_scheme(world):
				return failure("scheme_unready")
		"set_focus":
			if not Society.focus(world,str(args.get("focus",""))):
				return failure("unknown_focus")
		"train":
			if not Society.train(world):
				return failure("training_rejected")
		"event_choice":
			if not Society.decide(world,str(args.get("event_id","")),integer(args,"option_index",-1,0,2147483647)):
				return failure("choice_rejected")
		"crisis":
			if not Crises.act(world,str(args.get("kind","")),integer(args,"port",0,0,2147483647)):
				return failure("crisis_rejected")
		"project":
			if not Operations.start_project(world,world.active().loc,str(args.get("project",""))):
				return failure("project_rejected")
		"civic":
			if not Operations.civic(world,str(args.get("kind","")),integer(args,"target",0,-1,2147483647)):
				return failure("civic_rejected")
		"journey":
			if not Operations.expedition(world,str(args.get("kind","")),integer(args,"port",-1,1,2147483647)):
				return failure("journey_rejected")
		"boarding":
			if not Operations.begin_boarding(world,integer(args,"target",-1,1,2147483647)):
				return failure("boarding_rejected")
		"step":
			if bound_actor_id > 0 and bound_actor_id != int(game.last_player):
				var dest: Dictionary = vessel.get("arena_dest", {})
				if not dest.is_empty():
					var pid := int(dest.get("port_id", 0))
					var target_st: Dictionary = world.ports.get(pid, {})
					if target_st.is_empty():
						vessel.erase("arena_dest")
						return success({"waypoint_live": false, "dock": int(vessel.get("dock", 0))})
					if int(world.day) < int(dest.get("eta", 0)):
						var origin_sys := int(dest.get("origin_sys", vessel.system))
						if origin_sys != int(target_st.system):
							vessel.layer = true
							var tot := maxi(1, int(dest.eta) - int(dest.started))
							var prog := clampf(float(world.day - int(dest.started)) / float(tot), 0.0, 1.0)
							vessel.galpos = Vector2(world.systems[origin_sys].pos).lerp(Vector2(world.systems[int(target_st.system)].pos), prog)
						return success({"waypoint_live": true, "dock": 0, "eta_days": int(dest.eta) - int(world.day)})
					vessel.layer = false
					vessel.system = int(target_st.system)
					vessel.pos = Vector2(target_st.pos)
					world.berth(vessel, pid)
					vessel.erase("arena_dest")
					return success({"waypoint_live": false, "dock": int(vessel.get("dock", 0))})
				return success({"waypoint_live": false, "dock": int(vessel.get("dock", 0))})
			return advance(args)
		"waypoint":
			return navigation(args,vessel)
		"dock":
			if vessel.is_empty() or vessel.dock != 0:
				return failure("not_in_flight")
			if not game.galaxy and not vessel.locked and game.flight.nearby_port(vessel) == 0:
				var max_chase: float = float(game.flight.StationGeometry.docking_range(vessel.kind)) + 45.0
				var closest_port: Dictionary = {}
				var best_d: float = max_chase
				for pid in world.systems[vessel.system].ports:
					var st: Dictionary = world.ports[pid]
					var d := Vector2(vessel.pos).distance_to(st.pos)
					if d <= best_d:
						best_d = d
						closest_port = st
				if not closest_port.is_empty():
					vessel.pos = Vector2(closest_port.pos) + (Vector2(vessel.pos) - Vector2(closest_port.pos)).limit_length(game.flight.StationGeometry.docking_range(vessel.kind) - 2.0)
			game.flight.dock()
			if vessel.dock == 0:
				return failure("cannot_dock",game.notice_text)
		"navigate_to_station":
			var pid := integer(args, "port_id", 0, 1, 999999)
			if bound_actor_id > 0 and bound_actor_id != int(game.last_player):
				var target_st: Dictionary = world.ports.get(pid, {})
				if target_st.is_empty() or int(target_st.get("build", 0)) > 0 or vessel.is_empty():
					return failure("navigation_failed", "目标无效或无旗舰")
				if int(vessel.get("dock", 0)) == pid:
					return success({"port_id": pid, "auto_dock": true, "waypoint_live": false})
				var prev_dest: Dictionary = vessel.get("arena_dest", {})
				if int(prev_dest.get("port_id", 0)) == pid and int(prev_dest.get("eta", 0)) > int(world.day):
					return success({"port_id": pid, "auto_dock": true, "waypoint_live": true, "eta_days": int(prev_dest.eta) - int(world.day)})
				if int(vessel.get("dock", 0)) != 0:
					world.depart(vessel)
				var dist_hop: float = 0.0 if int(vessel.system) == int(target_st.system) else float(world.distance(int(vessel.system), int(target_st.system)))
				var transit: int = 1 if dist_hop == 0.0 else clampi(int(dist_hop / 90.0), 2, 14)
				vessel["arena_dest"] = {"port_id": pid, "origin_sys": int(vessel.system), "started": int(world.day), "eta": int(world.day) + transit}
				return success({"port_id": pid, "auto_dock": true, "waypoint_live": true, "eta_days": transit})
			var auto_d: bool = bool(args.get("auto_dock", true))
			game.nav_auto_dock = auto_d
			if not game.navigate_to_station(pid):
				return failure("navigation_failed", game.notice_text)
			return success({"port_id": pid, "auto_dock": auto_d, "waypoint_live": game.waypoint_live})
		"supply_fleet":
			if vessel.is_empty() or int(vessel.get("dock", 0)) == 0:
				return failure("not_docked", "需先停靠空间站才可全队整备。")
			var serviced := Economy.supply_fleet(world, int(vessel.dock))
			game.refresh()
			return success({"serviced": serviced, "credits": world.active().wallet})
		"trade_opportunities":
			if vessel.is_empty():
				return failure("no_ship")
			var model: Dictionary = Hulls.MODELS[vessel.kind]
			var cur_sys := int(vessel.system)
			var free_cap: int = world.cargo_free(vessel)
			var cash := int(world.active().wallet)
			var routes: Array[Dictionary] = []
			for src in world.ports.values():
				if src.build > 0 or src.get("landing_only", false) or not src.get("scan", false):
					continue
				if world.hostile(int(vessel.flag), int(src.flag)):
					continue
				for dst in world.ports.values():
					if dst.id == src.id or dst.build > 0 or dst.get("landing_only", false) or not dst.get("scan", false):
						continue
					if world.hostile(int(vessel.flag), int(dst.flag)):
						continue
					var hop: float = 0.0 if int(src.system) == int(dst.system) else float(world.distance(int(src.system), int(dst.system)))
					var fuel_est := 0.0 if hop == 0.0 else Economy.Hyperspace.fuel_for_distance(model, hop)
					for w_idx in range(world.WARES.size()):
						if int(src.stock[w_idx]) <= 0:
							continue
						var buy_p := Economy.price(src, w_idx, true)
						var sell_p := Economy.price(dst, w_idx, false)
						var margin := sell_p - buy_p
						if margin <= 2:
							continue
						var units := mini(int(src.stock[w_idx]), mini(maxi(1, free_cap), cash / maxi(1, buy_p)))
						if units <= 0:
							continue
						routes.append({
							"ware": w_idx, "ware_name": world.WARES[w_idx],
							"from_id": int(src.id), "from_name": src.name, "from_sys": int(src.system),
							"to_id": int(dst.id), "to_name": dst.name, "to_sys": int(dst.system),
							"buy_price": buy_p, "sell_price": sell_p, "margin": margin,
							"units": units, "est_profit": margin * units,
							"est_fuel": snappedf(fuel_est, 0.1),
							"approach_dist": snappedf(0.0 if int(src.system) == cur_sys else world.distance(cur_sys, int(src.system)), 1.0)
						})
			routes.sort_custom(func(a, b): return int(a.est_profit) > int(b.est_profit))
			return success({"routes": routes.slice(0, mini(10, routes.size()))})
		"start_pretext":
			var fid := integer(args, "firm_id", 0, 1, 999999)
			var tflag := integer(args, "target_flag", -1, 0, 999)
			var kind := str(args.get("kind", "tariff_dispute"))
			var res: Dictionary = world.CompanyWars.director_action(world,action,fid,tflag,kind)
			game.refresh()
			return success(res) if bool(res.get("ok", false)) else failure("pretext_failed", str(res.get("reason", "")))
		"declare_company_war":
			var fid := integer(args, "firm_id", 0, 1, 999999)
			var tflag := integer(args, "target_flag", -1, 0, 999)
			var res: Dictionary = world.CompanyWars.director_action(world,action,fid,tflag)
			game.refresh()
			return success(res) if bool(res.get("ok", false)) else failure("company_war_failed", str(res.get("reason", "")))
		"sign_company_peace":
			var fid := integer(args, "firm_id", 0, 1, 999999)
			var tflag := integer(args, "target_flag", -1, 0, 999)
			var res: Dictionary = world.CompanyWars.director_action(world,action,fid,tflag)
			game.refresh()
			return success(res) if bool(res.get("ok", false)) else failure("company_peace_failed", str(res.get("reason", "")))
		"wait":
			if not vessel.is_empty() and vessel.locked:
				return failure("wait_restricted_locked", "交战锁定中不可等待跳过天数")
			var wait_days := integer(args, "days", 1, 1, 180)
			var start_d: int = world.day
			for _d in range(wait_days):
				if world.attention or world.succession:
					break
				world.tick(1)
			game.refresh()
			return success({"days_elapsed": world.day - start_d, "day": world.day, "stopped": "attention" if (world.attention or world.succession) else "completed"})
		"depart":
			if vessel.is_empty() or vessel.dock == 0:
				return failure("not_docked")
			game.flight.dock()
			if vessel.dock != 0:
				return failure("cannot_depart",game.notice_text)
		"jump":
			var origin: bool = game.galaxy
			game.flight.change_layer()
			if origin == game.galaxy:
				return failure("cannot_jump",game.notice_text)
		"mine_or_salvage":
			if vessel.is_empty() or vessel.dock != 0 or game.galaxy or vessel.locked:
				return failure("interaction_unavailable")
			var cargo: Array = vessel.cargo.duplicate()
			var credits: int = world.active().wallet
			game.flight.salvage()
			if cargo == vessel.cargo and credits == world.active().wallet:
				return failure("nothing_collected",game.notice_text)
			var gained_total := 0
			for i in range(vessel.cargo.size()):
				gained_total += maxi(0, int(vessel.cargo[i]) - int(cargo[i]))
			return success({"collected": gained_total, "credits_gained": int(world.active().wallet) - credits,
				"ore_left": int(world.systems[vessel.system].ore), "free_cargo": world.cargo_free(vessel)})
		"trade":
			var ware := integer(args,"ware",-1,0,world.WARES.size()-1)
			var quantity := integer(args,"amount",0,-2147483647,2147483647)
			var black: Variant = args.get("black",false)
			if vessel.is_empty() or ware < 0 or quantity < -2147483647 or quantity == 0 or not black is bool:
				return failure("invalid_trade")
			var moved := Economy.trade(world,vessel.dock,ware,quantity,black)
			if moved != 0:
				game.hud.black_market = black
				watch_station_ui("港口", "market", "代理操作：%s %d 单位 %s" % ["买入" if moved > 0 else "卖出", absi(moved), world.WARES[ware]])
				game.refresh()
			return success({"moved":moved}) if moved != 0 else failure("trade_rejected")
		"repair","refuel":
			if action == "repair" and not vessel.is_empty() and vessel.dock == 0 and not game.galaxy:
				if not game.flight.field_repair():
					return failure("repair_rejected", game.notice_text)
			elif not Economy.supply(world,action == "repair"):
				return failure("service_unavailable")
			if vessel.dock != 0:
				watch_station_ui("港口", "yard", "代理操作：%s" % ("舰船维修" if action == "repair" else "补充燃料"))
		"field_repair":
			if not game.flight.field_repair():
				return failure("repair_rejected", game.notice_text)
		"sensor_ping":
			if not game.flight.sensor_ping():
				return failure("not_in_flight")
		"ship_quote":
			var kind := Hulls.kind_for_id(str(args.get("hull_id",""))) if args.has("hull_id") else integer(args,"model",-1,0,Hulls.MODELS.size()-1)
			var qpid := integer(args,"port_id",int(world.active().loc),1,2147483647)
			var port: Dictionary = world.ports.get(qpid,{})
			if kind < 0 or port.is_empty() or not Hulls.model_limit(port,kind):
				return failure("quote_unavailable")
			return success(Economy.ship_quote(port,kind))
		"buyout_charter":
			var expected := integer(args,"expected_price",-1,0,2147483647)
			if (args.has("expected_price") and expected < 0) or not Economy.buyout_charter(world,integer(args,"ship",vessel.get("id",0),1,2147483647),expected):
				return failure("charter_buyout_rejected")
		"buy_ship":
			if args.has("port") and integer(args,"port",0,1,2147483647) != world.active().loc:
				return failure("not_at_port")
			var model := integer(args,"model",-1,0,Hulls.MODELS.size()-1)
			if args.has("hull_id"):
				model = Hulls.kind_for_id(str(args.hull_id))
			var expected := integer(args,"expected_price",-1,0,2147483647)
			if args.has("expected_price") and expected < 0:
				return failure("invalid_price")
			var ship_id := Economy.buy_ship(world,world.active().loc,model,expected)
			if ship_id == 0:
				return failure("purchase_rejected")
			game.dock_view.model_id = model
			game.dock_view.last_bought_ship_id = ship_id
			game.dock_view.refit_ship_id = ship_id
			watch_station_ui("港口", "yard", "代理操作：购入 #%d %s" % [ship_id, world.HULLS[model]])
			game.refresh()
			return success({"ship":ship_id})
		"assign_escort":
			var captain := integer(args,"captain",-1,1,2147483647)
			var ship_id := integer(args,"ship",-1,1,2147483647)
			if not Economy.assign(world,ship_id,captain,"护航"):
				return failure("assignment_rejected")
			game.hud.selected_ship_id = ship_id
			watch_station_ui("资产", "", "代理操作：任命 %s 执掌 #%d" % [world.name_of(captain), ship_id])
		"accept_first_job":
			if not Story.accept(world):
				return failure("job_unavailable")
			watch_station_ui("港口", "people", "代理操作：接取首航委托")
		"deliver_first_job":
			if not Story.deliver(world):
				return failure("delivery_unavailable")
		"claim_return_bonus":
			if not Story.return_to_port(world):
				return failure("bonus_unavailable")
		"group":
			var auto: Variant = args.get("toggle_auto",false)
			if vessel.is_empty() or vessel.dock != 0 or game.galaxy or not auto is bool or not game.flight.select_group(vessel,integer(args,"group",0,1,3),auto):
				return failure("invalid_group")
		"vent","system":
			if vessel.is_empty() or vessel.dock != 0 or game.galaxy:
				return failure("combat_action_unavailable")
			var ready := false
			if action == "vent":
				ready = Battle.vent(vessel)
			else:
				var target := integer(args,"target",0,0,2147483647)
				var aim: Variant = vector(args.aim) if args.has("aim") else Vector2.INF
				var move: Variant = vector(args.get("move",[0,0]))
				if aim == null or move == null or target < 0:
					return failure("invalid_system_aim")
				if target != 0:
					var contact: Dictionary = world.ships.get(target,{})
					if contact.is_empty() or not Battle.available(contact,vessel.system) or not game.flight.visible_contact(vessel,contact):
						return failure("unknown_target")
					if aim == Vector2.INF:
						aim = contact.pos
				ready = Battle.system(world,vessel,Vector2(move).limit_length(),aim,target)
			if not ready:
				return failure("combat_action_rejected")
		"order":
			var order := integer(args,"order",-1,0,3)
			var target := integer(args,"target",0,0,2147483647)
			if order == 2 and not visible_target(vessel,target):
				return failure("unknown_target")
			var sent: int = game.flight.issue(order,target)
			return success({"ships":sent}) if sent > 0 else failure("order_rejected")
		"attack_target":
			var id := integer(args,"target",0,1,2147483647)
			return success({"target":id}) if visible_target(vessel,id) and game.flight.attack_target(id) else failure("unknown_target")
		"autopilot":
			var enabled: Variant = args.get("enabled", not game.autopilot)
			if not enabled is bool:
				return failure("invalid_autopilot")
			if args.has("tactic"):
				var t_arg: Variant = args.get("tactic")
				var t_idx := -1
				if t_arg is int or t_arg is float:
					t_idx = int(t_arg)
				elif t_arg is String:
					t_idx = game.COMBAT_TACTICS.find(str(t_arg))
				if t_idx < 0 or t_idx >= game.COMBAT_TACTICS.size():
					return failure("invalid_tactic")
				game.set_combat_tactic(t_idx)
			game.set_autopilot(enabled)
			return success({"autopilot": game.autopilot, "tactic": game.combat_tactic, "tactic_name": game.COMBAT_TACTICS[game.combat_tactic]})
		"set_tactic":
			var t_arg: Variant = args.get("tactic", 1)
			var t_idx := -1
			if t_arg is int or t_arg is float:
				t_idx = int(t_arg)
			elif t_arg is String:
				t_idx = game.COMBAT_TACTICS.find(str(t_arg))
			if t_idx < 0 or t_idx >= game.COMBAT_TACTICS.size():
				return failure("invalid_tactic")
			game.set_combat_tactic(t_idx)
			return success({"tactic": game.combat_tactic, "tactic_name": game.COMBAT_TACTICS[game.combat_tactic]})
		"war_status":
			var ruler_flag := int(world.active().get("flag", -1))
			return success({"wars": world.WarPeace.active_wars(world, ruler_flag)})
		"propose_peace":
			var ruler_flag := int(world.active().get("flag", -1))
			var enemy_flag := integer(args, "enemy", -1, 0, 2147483647)
			if enemy_flag < 0 or not world.Society.player_governs(world, ruler_flag):
				return failure("peace_forbidden")
			var annex: Array = args.get("annex_ports", []) if args.get("annex_ports") is Array else []
			var release: Array = args.get("release_ports", []) if args.get("release_ports") is Array else []
			var rep: bool = bool(args.get("reparations", false))
			var open_trade: bool = bool(args.get("open_trade", false))
			if bool(args.get("preview", false)):
				return success(world.WarPeace.preview_peace(world, ruler_flag, enemy_flag, annex, rep, release, open_trade))
			if not world.WarPeace.sign_peace(world, ruler_flag, enemy_flag, annex, rep, release, open_trade):
				return failure("peace_rejected", world.WarPeace.preview_peace(world, ruler_flag, enemy_flag, annex, rep, release, open_trade).reason)
		"join_faction":
			var target_flag := integer(args, "flag", -1, 0, 2147483647)
			if not Politics.join_faction(world, world.player, target_flag):
				return failure("join_faction_rejected")
		"apply_manager":
			var port_id := integer(args, "port", world.active().get("loc", 0), 1, 2147483647)
			if not Politics.employ_as_manager(world, world.player, port_id):
				return failure("apply_manager_rejected")
		"disembark":
			if not world.disembark():
				return failure("disembark_rejected")
		"buy_station_ship":
			var port_id := integer(args, "port", world.active().get("loc", 0), 1, 2147483647)
			var kind := Hulls.kind_for_id(str(args.get("hull_id", ""))) if args.has("hull_id") else integer(args, "model", -1, 0, Hulls.MODELS.size() - 1)
			var duty := str(args.get("duty", "站属贸易"))
			var sid := Economy.buy_and_assign_to_station(world, port_id, kind, duty)
			if sid == 0:
				return failure("buy_station_ship_rejected")
			return success({"ship": sid, "port": port_id, "duty": duty})
		_:
			return failure("unknown_action", action)
	game.refresh()
	return success()
