extends RefCounted

const Battle = preload("res://combat.gd")
const Celestial = preload("res://celestial.gd")
const Economy = preload("res://economy.gd")
const Hulls = preload("res://hull_catalog.gd")
const Politics = preload("res://politics.gd")
const Story = preload("res://frontier.gd")
const Portrait = preload("res://portrait.gd")
const PROTOCOL := 1
const MAX_BYTES := 16384

var game
var directory := ""
var elapsed := 0.0

func start(path: String) -> bool:
	if not path.is_absolute_path() or not DirAccess.dir_exists_absolute(path):
		return false
	if not DirAccess.get_files_at(path).is_empty() or not DirAccess.get_directories_at(path).is_empty():
		return false
	directory = path
	return publish("ready.json", {"protocol":PROTOCOL,"pid":OS.get_process_id()})

func publish(filename: String, value: Dictionary) -> bool:
	var path := directory.path_join(filename)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value))
	file.close()
	return DirAccess.rename_absolute(path + ".tmp", path) == OK

func poll(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.04:
		return
	elapsed = 0.0
	var path := directory.path_join("request.json")
	var response := directory.path_join("response.json")
	if FileAccess.file_exists(response) or not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		return
	var request: Variant = JSON.parse_string(file.get_as_text()) if file.get_length() <= MAX_BYTES else null
	file.close()
	if DirAccess.remove_absolute(path) != OK:
		return
	var result := failure("invalid_request")
	if request is Dictionary and request.get("id") is String and request.id.length() in range(1,81):
		if request.get("action") is String and request.get("args",{}) is Dictionary:
			result = dispatch(request.action,request.get("args",{}))
		result.id = request.id
	if not publish("response.json", result):
		printerr("Agent bridge could not write response.json.")
		game.get_tree().quit(3)
	elif result.get("quit",false):
		game.get_tree().quit()

func failure(code: String, detail: String = "") -> Dictionary:
	return {"ok":false,"error":code,"detail":detail}

func integer(args: Dictionary, field: String, fallback: int, from: int, to: int) -> int:
	var value: Variant = args.get(field,fallback)
	if (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= from and value <= to:
		return int(value)
	return from - 1

func vector(value: Variant) -> Variant:
	if not value is Array or value.size() != 2:
		return null
	for coordinate in value:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) or absf(float(coordinate)) > 1000000.0:
			return null
	return Vector2(value[0],value[1])

func coords(point: Vector2) -> Array:
	return [snappedf(point.x,0.01),snappedf(point.y,0.01)]

func success(extra: Dictionary = {}) -> Dictionary:
	return {"ok":true,"result":extra,"state":observe()}

func observe() -> Dictionary:
	if not game.playing:
		return {"screen":"title"}
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
	if not vessel.is_empty():
		var battle: Dictionary = vessel.battle
		var fleets: Array = []
		for other in world.ships.values():
			if other.owner == world.player:
				fleets.append({"id":other.id,"model":world.HULLS[other.kind],"captain":other.captain,"dock":other.dock,"order":Battle.ORDERS[other.battle.order]})
		state.ship = {"id":vessel.id,"model":world.HULLS[vessel.kind],"pos":coords(vessel.galpos if game.galaxy else vessel.pos),
			"velocity":coords(battle.motion),"heading":snappedf(float(vessel.heading),0.001),"dock":vessel.dock,"hp":vessel.hp,"armor":battle.armor,
			"crew":vessel.crew,"fuel":vessel.fuel,"free_cargo":world.cargo_free(vessel),"locked":vessel.locked,"cargo":vessel.cargo.duplicate(),
			"soft_flux":battle.soft_flux,"hard_flux":battle.hard_flux,"capacity":Hulls.capacity(vessel),"shield":battle.shield,
			"vent":battle.vent,"overload":battle.overload,"group":battle.group,"cooldowns":battle.cooldowns.duplicate(),"system_cd":battle.system_cd,
			"system_time":battle.system_time,"weapons":vessel.fit.weapons.duplicate(),"auto":vessel.fit.auto.duplicate(),"fleet":fleets}
		state.waypoint = coords(game.waypoint) if game.waypoint_live else null
	state.wares = world.WARES
	state.ship_catalog = Hulls.MODELS.map(func(model): return {"name":model.name,"price":model.price,"cargo":model.cargo}) if state.screen == "port" else []
	if game.galaxy and not vessel.is_empty():
		var point: Vector2 = vessel.galpos
		var ordered: Array = world.systems_in(Rect2(point - Vector2(850,850),Vector2(1700,1700)))
		ordered.sort_custom(func(first,second): return point.distance_squared_to(world.systems[first].pos) < point.distance_squared_to(world.systems[second].pos))
		state.beacons = []
		for index in ordered.slice(0,16):
			var destination: Dictionary = world.systems[index]
			state.beacons.append({"id":index,"name":destination.name,"pos":coords(destination.pos),"distance":point.distance_to(destination.pos),"visited":destination.seen})
		state.jump_allowed = not vessel.locked and game.flight.nearby_system(vessel) >= 0
	else:
		state.gravity = coords(Celestial.gravity_point(region))
		state.mine = coords(region.field)
		state.jump_allowed = not vessel.is_empty() and vessel.dock == 0 and not vessel.locked and Celestial.at_gravity_point(region,vessel.pos)
		for port_id in region.ports:
			var station: Dictionary = world.ports[port_id]
			var entry := {"id":port_id,"name":station.name,"pos":coords(station.pos),"hostile":world.hostile(actor.flag,station.flag)}
			if actor.loc == port_id:
				entry.stock = station.stock.duplicate()
				entry.buy = []
				entry.sell = []
				for ware in range(world.WARES.size()):
					entry.buy.append(Economy.price(station,ware,true,actor.origin) if ware < 6 else null)
					entry.sell.append(Economy.price(station,ware,false,actor.origin) if ware < 6 else null)
				entry.ships = station.hulls.duplicate()
			state.ports.append(entry)
		for other in world.ships.values():
			if not vessel.is_empty() and other.id != vessel.id and Battle.available(other,system_index) and vessel.pos.distance_to(other.pos) <= 680.0:
				state.targets.append({"id":other.id,"pos":coords(other.pos),"velocity":coords(other.battle.motion),"hp":other.hp,
					"armor":other.battle.armor,"shield":other.battle.shield,"hostile":world.enemy(vessel,other),"model":world.HULLS[other.kind]})
		if actor.loc != 0:
			for other in world.people.values():
				if other.alive and other.id != actor.id and other.loc == actor.loc:
					state.contacts.append({"id":other.id,"name":other.name,"age":Politics.age(world,other),"noble":other.noble,"opinion":Politics.opinion(world,other.id,actor.id)})
			state.contacts = state.contacts.slice(0,32)
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
	var options := {"seed":seed_value,"systems":count,"factions":groups,"avatar":{"name":label,"house":"远岚","age":26,"origin":0,"trait":0,
		"noble":noble,"look":Portrait.random_look(random)}}
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
		point = world.ports[id].pos
	elif destination == "system" and game.galaxy:
		var id := integer(args,"target",-1,0,world.systems.size()-1)
		if id < 0:
			return failure("unknown_system")
		point = world.systems[id].pos
	elif destination == "point":
		var value: Variant = vector(args.get("pos"))
		if value == null or (not game.galaxy and (absf(value.x)>1320.0 or absf(value.y)>900.0)):
			return failure("invalid_waypoint")
		point = value
	else:
		return failure("wrong_navigation_layer")
	game.set_waypoint(point,"代理航点")
	return success()

func advance(args: Dictionary) -> Dictionary:
	var world = game.world
	var steps := integer(args,"ticks",60,1,1800)
	var speed := integer(args,"speed",1,1,5)
	var move: Variant = vector(args.get("move",[0,0]))
	var aim: Variant = vector(args.get("aim",[0,0]))
	var gun: Variant = args.get("fire",false)
	var shield_hold: Variant = args.get("shield",false)
	var has_aim := args.has("aim")
	var target_id := integer(args,"target",0,0,2147483647)
	var halt: Variant = args.get("stop","encounter")
	if steps < 1 or speed < 1 or move == null or aim == null or not gun is bool or not shield_hold is bool or target_id < 0 or halt not in ["encounter","arrival","never"]:
		return failure("invalid_step")
	var vessel: Dictionary = world.ride()
	if args.has("target") and target_id != 0 and not visible_target(vessel,target_id):
		return failure("unknown_target")
	if not vessel.is_empty() and vessel.dock == 0 and speed > 1 and (vessel.locked or not game.waypoint_live or move != Vector2.ZERO):
		return failure("speed_restricted")
	if gun and not has_aim and target_id == 0:
		return failure("aim_required")
	var initial_waypoint: bool = game.waypoint_live
	var original: int = world.player
	game.set_speed(speed)
	var processed := 0
	var stopped := "tick_limit"
	for tick in range(steps):
		if world.succession or world.attention or world.player != original:
			stopped = "attention"
			break
		vessel = world.ride()
		var had_contact: bool = vessel.get("locked",false)
		var point: Vector2 = aim
		var has_target := false
		if target_id != 0 and not vessel.is_empty():
			has_target = visible_target(vessel,target_id)
			if has_target:
				point = world.ships[target_id].pos
			elif not has_aim:
				stopped = "target_lost"
				break
		game.flight.step(1.0/60.0,Vector2(move).limit_length(),shield_hold,gun and (has_aim or has_target),point,has_aim or has_target)
		processed += 1
		if not had_contact and vessel.get("locked",false) and halt != "never":
			stopped = "encounter"
			break
		if initial_waypoint and not game.waypoint_live and halt == "arrival":
			stopped = "arrival"
			break
	if world.attention or world.succession:
		stopped = "attention"
	game.speed = 0
	game.refresh()
	return success({"ticks":processed,"stopped":stopped})

func visible_target(vessel: Dictionary, target_id: int) -> bool:
	if vessel.is_empty() or game.galaxy or vessel.dock != 0:
		return false
	var world = game.world
	var target: Dictionary = world.ships.get(target_id,{})
	return not target.is_empty() and Battle.available(target,vessel.system) and world.enemy(vessel,target) and target.pos.distance_to(vessel.pos) <= 680.0

func dispatch(action: String, args: Dictionary) -> Dictionary:
	if action == "observe":
		return success()
	if action == "quit":
		return {"ok":true,"quit":true}
	if action == "new_game":
		return new_game(args)
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
		"step":
			return advance(args)
		"waypoint":
			return navigation(args,vessel)
		"dock":
			if vessel.is_empty() or vessel.dock != 0:
				return failure("not_in_flight")
			game.flight.dock()
			if vessel.dock == 0:
				return failure("cannot_dock",game.notice_text)
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
		"trade":
			var ware := integer(args,"ware",-1,0,world.WARES.size()-1)
			var quantity := integer(args,"amount",0,-1000,1000)
			var black: Variant = args.get("black",false)
			if vessel.is_empty() or ware < 0 or quantity < -1000 or quantity == 0 or not black is bool:
				return failure("invalid_trade")
			var moved := Economy.trade(world,vessel.dock,ware,quantity,black)
			return success({"moved":moved}) if moved != 0 else failure("trade_rejected")
		"repair","refuel":
			if not Economy.supply(world,action == "repair"):
				return failure("service_unavailable")
		"buy_ship":
			var model := integer(args,"model",-1,0,Hulls.MODELS.size()-1)
			var ship_id := Economy.buy_ship(world,world.active().loc,model)
			if ship_id == 0:
				return failure("purchase_rejected")
			game.refresh()
			return success({"ship":ship_id})
		"assign_escort":
			var captain := integer(args,"captain",-1,1,2147483647)
			var ship_id := integer(args,"ship",-1,1,2147483647)
			if not Economy.assign(world,ship_id,captain,"护航"):
				return failure("assignment_rejected")
		"accept_first_job":
			if not Story.accept(world):
				return failure("job_unavailable")
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
			var ready := Battle.vent(vessel) if action == "vent" else Battle.system(world,vessel,Vector2.ZERO)
			if not ready:
				return failure("combat_action_rejected")
		"order":
			var order := integer(args,"order",-1,0,3)
			var target := integer(args,"target",0,0,2147483647)
			if order == 2 and not visible_target(vessel,target):
				return failure("unknown_target")
			var sent: int = game.flight.issue(order,target)
			return success({"ships":sent}) if sent > 0 else failure("order_rejected")
		"auto_battle":
			var previous: int = world.ships.size()
			game.flight.auto_battle()
			if world.ships.size() == previous:
				return failure("encounter_rejected",game.notice_text)
		_:
			return failure("unknown_action", action)
	game.refresh()
	return success()
