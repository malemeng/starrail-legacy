extends RefCounted

const Hulls = preload("res://hull_catalog.gd")
const Industry = preload("res://scripts/economy/industry.gd")
const Config = preload("res://scripts/campaign/crisis_rules.json")
static var rules: Dictionary = Config.data

static func fleets(world, ids: Array, tag: String) -> Array:
	var living := []
	for id in ids:
		var ship: Dictionary = world.ships.get(id,{})
		if ship.get("crisis_unit","") == tag and ship.owner == 0 and ship.hp > 0:
			living.append(id)
	return living

static func spawn(world, reference: String, system: int, position: Vector2, tag: String, flag: int) -> int:
	var kind := Hulls.kind_for_reference(reference)
	if kind < 0:
		return 0
	var id: int = world.ship(kind,0,0,flag,system,position)
	var ship: Dictionary = world.ships[id]
	ship.crisis_unit = tag
	ship.job = {"kind":"警戒","system":system}
	return id

static func enemies(first: Dictionary, second: Dictionary) -> bool:
	var target: int = first.get("blockade_owner",0)
	if target != 0 and target == (Hulls.operator_id(second) if second.has("owner") else second.get("credit", 0)):
		return true
	target = second.get("blockade_owner",0)
	return target != 0 and target == (Hulls.operator_id(first) if first.has("owner") else first.get("credit", 0))

static func summary(world) -> Dictionary:
	var current: Dictionary = world.campaign.crises.duplicate(true)
	current.signals = []
	for i in range(world.systems.size()):
		var region: Dictionary = world.systems[i]
		if region.get("mine_signal","") == "active" and region.get("seen",false):
			current.signals.append({"system":i,"pos":region.field,"heat":region.get("mining_heat",0)})
	return current

static func investigate(world) -> bool:
	var vessel: Dictionary = world.ride()
	if vessel.is_empty() or vessel.dock != 0 or vessel.layer:
		return false
	var field: Dictionary = world.systems[vessel.system]
	if field.get("mine_signal","") != "active" or vessel.pos.distance_to(field.field) > float(rules.mining.range):
		return false
	field.threat_units = []
	for index in range(rules.mining.encounter.size()):
		var pos: Vector2 = vessel.pos + Vector2.from_angle(float(index)*1.8+0.6) * (165+28*index)
		var id := spawn(world,rules.mining.encounter[index],vessel.system,pos,"hive",world.ROGUE_MACHINES)
		if id:
			field.threat_units.append(id)
	if field.threat_units.is_empty():
		return false
	field.mine_signal = "engaged"
	world.event("%s 矿区内的休眠守卫已暴露，转入实战接触。" % field.name)
	return true

static func start_swarm(world) -> bool:
	var own: Dictionary = world.ride()
	var crisis: Dictionary = world.campaign.crises.get("swarm",{})
	if own.is_empty() or own.layer or own.dock != 0 or not crisis.is_empty():
		return false
	var region: Dictionary = world.systems[own.system]
	if not region.get("wild",false) or not region.get("seen",false):
		return false
	var base: Vector2 = region.field + Vector2(240,50)
	var factory := spawn(world,rules.swarm.factory,own.system,base,"swarm",world.ROGUE_MACHINES)
	var miner := spawn(world,rules.swarm.miner,own.system,base+Vector2(36,0),"swarm",world.ROGUE_MACHINES)
	if not factory or not miner:
		return false
	world.campaign.crises.swarm = {"status":"active","system":own.system,"factory":factory,"miner":miner,"escorts":[],"built":0,"phase":"collect"}
	world.event("%s 的休眠制造母舰启动，采集艇正在驶向矿带。" % region.name)
	return true

static func fly_local(vessel: Dictionary, target: Vector2, distance: float) -> void:
	var origin: Vector2 = vessel.pos
	if not origin.is_equal_approx(target):
		vessel.heading = origin.angle_to_point(target)
		vessel.pos = origin.move_toward(target,distance)

static func advance_swarm(world, record: Dictionary, visible_motion: Dictionary = {}) -> void:
	if record.status != "active":
		return
	var factory: Dictionary = world.ships.get(record.factory,{})
	if factory.is_empty() or factory.owner != 0:
		record.status = "defeated"
		world.event("制造母舰已失去控制，自复制舰群停止扩张。")
		return
	var miner: Dictionary = world.ships.get(record.miner,{})
	var region: Dictionary = world.systems[record.system]
	var bill := {Industry.Ware.ORE:int(rules.swarm.ore),Industry.Ware.SILICON:int(rules.swarm.silicon),Industry.Ware.ENERGY:int(rules.swarm.energy)}
	# The factory harvests stellar energy. Ore and silicon arrive only in the tender's hold.
	if world.day % 3 == 0 and world.cargo_free(factory) > 0:
		factory.cargo[Industry.Ware.ENERGY] += mini(2,mini(world.cargo_free(factory),maxi(0,2*int(rules.swarm.energy)-int(factory.cargo[Industry.Ware.ENERGY]))))
	if not miner.is_empty() and miner.owner == 0 and not miner.locked:
		var gathering: bool = record.phase == "collect"
		var target: Vector2 = region.field if gathering else factory.pos
		if not visible_motion.has(miner.id):
			fly_local(miner,target,float(rules.swarm.miner_units_per_day))
		if miner.pos.distance_to(target) < 1:
			if gathering:
				if not region.has("deposits"):
					region.deposits = {Industry.Ware.SILICON:180,Industry.Ware.GAS:180,Industry.Ware.ICE:180}
				var ore_needed := maxi(0,2 * int(rules.swarm.ore)-int(factory.cargo[Industry.Ware.ORE]))
				var ore := mini(int(region.ore),mini(world.cargo_free(miner),ore_needed))
				region.ore -= ore
				miner.cargo[Industry.Ware.ORE] += ore
				var silicon_needed := maxi(0,2 * int(rules.swarm.silicon)-int(factory.cargo[Industry.Ware.SILICON]))
				var silicon := mini(int(region.deposits[Industry.Ware.SILICON]),mini(world.cargo_free(miner),silicon_needed))
				region.deposits[Industry.Ware.SILICON] -= silicon
				miner.cargo[Industry.Ware.SILICON] += silicon
				record.phase = "deliver"
			else:
				for ware in [Industry.Ware.ORE,Industry.Ware.SILICON]:
					var moved := mini(miner.cargo[ware],world.cargo_free(factory))
					factory.cargo[ware] += moved
					miner.cargo[ware] -= moved
				record.phase = "collect"
	record.escorts = fleets(world, record.escorts, "swarm")
	if record.escorts.size() >= int(rules.swarm.fleet_cap):
		return
	for ware in bill:
		if factory.cargo[ware] < bill[ware]:
			return
	var reference: String = rules.swarm.output[int(record.built) % rules.swarm.output.size()]
	var escort := spawn(world,reference,record.system,Vector2(factory.pos)+Vector2.from_angle(record.built*1.7)*115,"swarm",world.ROGUE_MACHINES)
	if not escort:
		return
	for ware in bill:
		factory.cargo[ware] -= int(bill[ware])
	record.escorts.append(escort)
	record.built += 1

static func assets(world) -> int:
	var value: int = world.active().get("wallet",0)
	for vessel in world.ships.values():
		if world.oversees(vessel.owner):
			value += int(Hulls.MODELS[vessel.kind].price)
	for station in world.ports.values():
		if world.oversees(station.owner) and station.build == 0:
			value += 450 * station.modules.size()
	return value

static func start_blockade(world, port_id: int) -> bool:
	var station: Dictionary = world.ports.get(port_id,{})
	if station.is_empty() or station.build > 0 or not world.oversees(station.owner) or not world.campaign.crises.get("blockade",{}).is_empty():
		return false
	var forces := []
	for group_id in world.factions:
		var group: Dictionary = world.factions[group_id]
		if group_id < 0 or not group.alive or group_id == station.flag:
			continue
		for vessel in world.ships.values():
			if vessel.flag != group_id or vessel.owner != 0 or vessel.captain == 0 or vessel.job.get("kind","") != "护航" or vessel.locked:
				continue
			forces.append(vessel.id)
			break
		if forces.size() >= int(rules.blockade.max_ships):
			break
	if forces.is_empty():
		return false
	for id in forces:
		var vessel: Dictionary = world.ships[id]
		vessel.crisis_unit = "coalition"
		vessel.blockade_owner = station.owner
		vessel.job = {"kind":"封锁","prior":vessel.job.duplicate(true)}
		world.depart(vessel)
	world.campaign.crises.blockade = {"status":"mobilizing","started":world.day,"target":port_id,"owner":station.owner,"forces":forces}
	world.event("多方舰队已接到对%s的封锁动员令。" % station.name)
	return true

static func end_blockade(world, record: Dictionary, result: String) -> void:
	var station: Dictionary = world.ports[record.target]
	station.erase("coalition_blockade")
	for id in record.forces:
		var ship: Dictionary = world.ships.get(id,{})
		if ship.is_empty() or ship.get("crisis_unit","") != "coalition":
			continue
		ship.job = ship.job.get("prior",{"kind":"护航","system":ship.system}) if ship.owner == 0 else {}
		ship.erase("crisis_unit")
		ship.erase("blockade_owner")
	record.status = result
	world.event("%s 的航运封锁结束。" % station.name)

static func guard_position(vessel: Dictionary, station: Dictionary) -> Vector2:
	return station.pos + Vector2.from_angle(float(vessel.id % 12)*TAU/12.0)*125

static func patrol_travel(world, vessel: Dictionary, station: Dictionary, days: float) -> void:
	if vessel.system==station.system and not vessel.layer:
		fly_local(vessel,guard_position(vessel,station),float(rules.blockade.patrol_units_per_day)*days)
		return
	var destination: Vector2 = world.systems[station.system].pos
	var origin: Vector2 = vessel.galpos
	vessel.layer = true
	if not origin.is_equal_approx(destination):
		vessel.heading = origin.angle_to_point(destination)
	vessel.galpos = origin.move_toward(destination,float(rules.blockade.hyperspace_units_per_day)*days)
	if Vector2(vessel.galpos).is_equal_approx(destination):
		vessel.system = station.system
		vessel.layer = false
		vessel.pos = station.pos + Vector2(420,100)

static func move_visible(world, system: int, hyper: bool, days: float, moved: Dictionary) -> void:
	if days<=0:
		return
	var state: Dictionary = world.campaign.crises
	var swarm: Dictionary = state.get("swarm",{})
	if not hyper and swarm.get("status","")=="active" and swarm.system==system:
		var factory: Dictionary = world.ships.get(swarm.factory,{})
		var miner: Dictionary = world.ships.get(swarm.miner,{})
		if factory.get("owner",-1)==0 and miner.get("owner",-1)==0 and not miner.locked and not miner.layer and miner.system==system:
			var target: Vector2 = world.systems[system].field if swarm.phase=="collect" else factory.pos
			fly_local(miner,target,float(rules.swarm.miner_units_per_day)*days)
			moved[miner.id] = true
	var blockade: Dictionary = state.get("blockade",{})
	if blockade.get("status","") not in ["mobilizing","active"]:
		return
	var station: Dictionary = world.ports.get(blockade.target,{})
	if station.get("owner",0)!=blockade.owner or world.day-blockade.started>=int(rules.blockade.mandate_days):
		return
	for id: int in blockade.forces:
		var vessel: Dictionary = world.ships.get(id,{})
		if vessel.get("crisis_unit","")!="coalition" or vessel.owner!=0 or vessel.locked or vessel.hp<=0:
			continue
		if (hyper and (vessel.layer or vessel.system!=station.system)) or (not hyper and not vessel.layer and vessel.system==system):
			patrol_travel(world,vessel,station,days)
			moved[id] = true

static func advance_blockade(world, record: Dictionary, visible_motion: Dictionary = {}) -> void:
	if record.status not in ["mobilizing","active"]:
		return
	var live := fleets(world,record.forces,"coalition")
	var station: Dictionary = world.ports[record.target]
	if live.is_empty() or station.owner != record.owner:
		end_blockade(world,record,"lifted")
		return
	if world.day - record.started >= int(rules.blockade.mandate_days):
		end_blockade(world,record,"expired")
		return
	var on_station := 0
	for id in live:
		var vessel: Dictionary = world.ships[id]
		if vessel.locked:
			on_station += int(vessel.system == station.system and not vessel.layer)
			continue
		if not visible_motion.has(id):
			patrol_travel(world,vessel,station,1.0)
		if not vessel.layer and vessel.system==station.system and vessel.pos.distance_to(guard_position(vessel,station))<5:
			on_station += 1
	if on_station and world.day - record.started >= int(rules.blockade.grace_days):
		if record.status != "active":
			world.event("%s 外航道被封锁，公开市场运输中断。" % station.name)
		record.status = "active"
		station.coalition_blockade = true

static func act(world, kind: String, port_id: int = 0) -> bool:
	match kind:
		"investigate": return investigate(world)
		"swarm": return start_swarm(world)
		"challenge": return assets(world) >= int(rules.blockade.asset_threshold) and start_blockade(world,port_id)
		"negotiate":
			var record: Dictionary = world.campaign.crises.get("blockade",{})
			if record.get("status","") not in ["mobilizing","active"] or world.active().loc != record.target:
				return false
			var cost := int(rules.blockade.fee)
			if world.active().wallet < cost:
				return false
			world.credit(world.player,-cost)
			end_blockade(world,record,"negotiated")
			return true
	return false

static func daily(world, visible_motion: Dictionary = {}) -> void:
	var state: Dictionary = world.campaign.crises
	if state.has("swarm"):
		advance_swarm(world,state.swarm,visible_motion)
	if state.has("blockade"):
		advance_blockade(world,state.blockade,visible_motion)
	elif world.day % 90 == 0 and assets(world) >= int(rules.blockade.asset_threshold):
		for port in world.ports.values():
			if world.oversees(port.owner) and start_blockade(world,port.id):
				break
	if world.day % 6 != 0:
		return
	for index in range(2,world.systems.size()):
		var field: Dictionary = world.systems[index]
		if field.get("mine_signal","") == "engaged" and fleets(world,field.threat_units,"hive").is_empty():
			field.mine_signal = ""
			field.mining_heat = 0
			field.recovery_until = world.day + int(rules.mining.recovery_days)
		if field.get("mining_heat",0) >= int(rules.mining.threshold) and field.get("mine_signal","") == "" and world.day >= field.get("recovery_until",0):
			field.mine_signal = "active"
			if field.get("seen",false):
				world.event("%s 矿场检测到异常回波，驶近矿带可进行侦察。" % field.name)
