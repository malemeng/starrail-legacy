extends RefCounted

const Hulls = preload("res://hull_catalog.gd")
const Defenses = preload("res://scripts/battle/defenses.gd")
const Industry = preload("res://scripts/economy/industry.gd")
const Ordnance = preload("res://scripts/battle/system_ordnance.gd")

static func threat(world, observer: Dictionary, from: Vector2, radius: float, active_carriers: Variant = null) -> Dictionary:
	var found := {}
	var nearest := radius * radius
	for carrier in (world.ships.values() if active_carriers == null else active_carriers):
		if carrier.system != observer.system or carrier.dock != 0 or carrier.layer:
			continue
		var candidate := {}
		var closest := nearest
		for wing in carrier.battle.get("fighter_wings", []):
			if wing.hp <= 0.0 or not wing.sortie:
				continue
			var dist := from.distance_squared_to(wing.pos)
			if dist < closest:
				closest = dist
				candidate = wing
		if not candidate.is_empty() and world.enemy(observer,carrier):
			nearest = closest
			found = candidate
	return found

static func engagement_range(spec: Dictionary) -> float:
	return clampf(spec.get("range",4000.0) * 0.25,200.0,1800.0)

static func operation_range(carrier: Dictionary) -> float:
	var furthest := 0.0
	for id in carrier.fit.wings:
		var spec := Hulls.wing_spec(id)
		if not spec.has("service"):
			furthest = maxf(furthest,engagement_range(spec))
	return furthest

static func advance(world, carrier: Dictionary, enemy: Dictionary, delta: float, combat, missiles: Variant = null, airborne: Variant = null) -> void:
	var hull: Dictionary = Hulls.MODELS[carrier.kind]
	var bays: int = hull.get("fighter_bays", 0)
	if bays == 0:
		return
	var state: Dictionary = carrier.battle
	var wings: Array = state.fighter_wings
	var assigned: Array = carrier.fit.wings
	if wings.size() != bays or state.get("wing_loadout") != assigned:
		wings.resize(bays)
		for i in bays:
			var id: String = assigned[i] if i < assigned.size() else ""
			if wings[i] is Dictionary and wings[i].get("id") == id:
				continue
			var spec := Hulls.wing_spec(id)
			var strength := maxi(1,int(spec.get("count",1)))
			var wing_hp := maxf(1.0,float(spec.get("hp",22.0))) * strength
			wings[i] = {"role":spec.get("role","fighter"),"id":id,"count":strength,"pos":carrier.pos,"hp":wing_hp,"max_hp":wing_hp,
				"speed":clampf(float(spec.get("speed",180.0)),70.0,410.0),"refit_time":maxf(2.0,float(spec.get("refit",6.0))),
				"refit":0.0,"cool":0.0,"sortie":false,"returning":false}
		state.wing_loadout = assigned.duplicate()
	state.replacement_rate = minf(1.0,state.replacement_rate + delta * 0.007)
	var active: Dictionary = state.get("active_profile",{}) if state.system_time > 0.0 else {}
	var multiplier := float(active.get("wing_damage",1.0))
	for i in wings.size():
		var wing: Dictionary = wings[i]
		if wing.hp <= 0.0:
			wing.count_live = 0
			wing.sortie = false
			if wing.refit <= 0.0:
				state.replacement_rate = maxf(0.12,state.replacement_rate - 0.18)
				wing.refit = wing.refit_time / state.replacement_rate
				wing.erase("cargo_ware")
			wing.refit -= delta
			if wing.refit <= 0.0:
				wing.hp = wing.max_hp
				wing.pos = carrier.pos
				wing.returning = false
			continue
		var spec := Hulls.wing_spec(wing.id)
		var base := clampi(ceili(wing.hp * wing.count / wing.max_hp),1,wing.count)
		wing.count_live = maxi(1,roundi(base * float(active.get("reserve_multiplier",1.0))))
		wing.reserve_count = wing.count_live - base
		wing.cool = maxf(0.0,wing.cool - delta)
		wing.scan_in = maxf(0.0,float(wing.get("scan_in",0.0))-delta)
		var berth := Vector2(carrier.pos) + Vector2(-15.0,(i - (bays - 1.0) * 0.5) * 11.0).rotated(carrier.heading)
		if not wing.returning and combat.ready(carrier):
			if spec.has("service"):
				if service(world,carrier,wing,spec,delta):
					continue
				if spec.has("construction") and not enemy.is_empty() and construct(world,carrier,wing,spec.construction,enemy,delta):
					continue
			elif not enemy.is_empty() and Vector2(carrier.pos).distance_squared_to(enemy.pos) <= pow(engagement_range(spec),2):
				wing.sortie = true
				if spec.has("manifestation"):
					manifestation(world,carrier,enemy,wing,spec.manifestation,delta,multiplier)
				else:
					attack(world,carrier,enemy,wing,spec,berth,i,delta,multiplier,missiles,airborne)
				continue
		fly(wing,berth,delta)
		if Vector2(wing.pos).distance_squared_to(berth) < 49.0:
			wing.hp = minf(wing.max_hp,wing.hp + delta * 2.0)
			wing.sortie = false
			if wing.has("cargo_ware") and world.cargo_free(carrier) > 0:
				carrier.cargo[wing.cargo_ware] += 1
				wing.erase("cargo_ware")
			if wing.cool <= 0.0 and not wing.has("cargo_ware"):
				wing.returning = false

static func fly(wing: Dictionary, destination: Vector2, delta: float) -> void:
	var offset := destination - Vector2(wing.pos)
	if offset.length_squared() > 0.01:
		wing.heading = offset.angle()
	wing.pos = Vector2(wing.pos).move_toward(destination,wing.speed*delta)

static func intercept(world, carrier: Dictionary, wing: Dictionary, spec: Dictionary, multiplier: float, missiles: Variant, airborne: Variant) -> bool:
	if wing.cool > 0.0 or not spec.has("pd"):
		return false
	for missile in (world.projectiles if missiles == null else missiles):
		if missile.system == carrier.system and missile.missile and missile.hp > 0.0 and Vector2(wing.pos).distance_squared_to(missile.pos) <= 10000.0 and world.enemy(carrier,missile):
			missile.hp -= float(spec.pd) * wing.count_live * multiplier
			wing.cool = 0.62
			world.combat_event("intercept",missile.pos,carrier.system)
			return true
	var hostile := threat(world,carrier,wing.pos,105.0,airborne)
	if not hostile.is_empty():
		hostile.hp -= float(spec.pd) * wing.count_live * multiplier * 0.55
		wing.cool = 0.72
		return true
	return false

static func attack(world, carrier: Dictionary, enemy: Dictionary, wing: Dictionary, spec: Dictionary, berth: Vector2, bay: int, delta: float, multiplier: float, missiles: Variant, airborne: Variant) -> void:
	var goal: Vector2 = enemy.pos
	var axis := (goal - Vector2(wing.pos)).normalized()
	var shots: Array = spec.get("payloads",[])
	var cycle: int = wing.get("cycle",0)
	var weapon: Dictionary = {} if shots.is_empty() else shots[cycle % shots.size()]
	var reach := float(weapon.get("range",120.0))
	var destination := goal - axis * reach * 0.65 + axis.orthogonal() * (bay*5-6)
	if wing.role == "support":
		destination = berth + berth.direction_to(goal)*53.0
	fly(wing,destination,delta)
	if wing.cool > 0.0 or weapon.is_empty():
		return
	if wing.scan_in <= 0.0:
		wing.scan_in = 0.12
		if intercept(world,carrier,wing,spec,multiplier,missiles,airborne):
			return
		if wing.role == "fighter":
			var hostile := threat(world,carrier,wing.pos,reach,airborne)
			if not hostile.is_empty():
				hostile.hp -= weapon.damage * wing.count_live * multiplier
				wing.cool = weapon.cycle
				wing.cycle = cycle + 1
				return
	if Vector2(wing.pos).distance_squared_to(goal) > reach*reach:
		return
	var bomber: bool = wing.role == "bomber"
	var burst: int = shots.size() if bomber else 1
	for mount in burst:
		weapon = shots[(cycle+mount)%shots.size()]
		launch(world,carrier,enemy,wing,weapon,multiplier)
	wing.cycle = cycle + burst
	wing.cool = float(weapon.cycle)
	wing.returning = bomber

static func manifestation(world, carrier: Dictionary, enemy: Dictionary, wing: Dictionary, effect: Dictionary, delta: float, multiplier: float) -> void:
	var axis := Vector2(carrier.pos).direction_to(enemy.pos)
	var screen: bool = effect.kind == "screen"
	var goal: Vector2 = Vector2(carrier.pos)+axis*45.0 if screen else Vector2(enemy.pos)
	fly(wing,goal,delta)
	wing.age = float(wing.get("age",0.0))+delta
	if Vector2(wing.pos).distance_squared_to(goal) > 16.0*16.0 and wing.age < effect.life:
		return
	if screen:
		var cloud := Ordnance.spawn(world,carrier,"screen",wing.pos,axis*effect.speed,effect.life,0.0)
		cloud.hp = effect.hp
		cloud.wing_id = wing.id
	else:
		var burst := Ordnance.payload(carrier,"vortex",wing.pos,Vector2.ZERO,effect.fuse+1.0,effect.damage*multiplier)
		burst.merge({"mine":true,"arming":0.0,"fuse":effect.fuse,"triggered":true,"wing_id":wing.id})
		world.projectiles.append(burst)
	wing.hp = 0.0
	wing.age = 0.0

static func construct(world, carrier: Dictionary, wing: Dictionary, plan: Dictionary, enemy: Dictionary, delta: float) -> bool:
	if wing.cool > 0.0:
		return false
	for material in plan.materials:
		if carrier.cargo[Industry.WARE_ID[material]] < int(plan.materials[material]):
			return false
	for unit in world.ships.values():
		if unit.battle.get("constructor_id",0) == carrier.id:
			return false
	for shot in world.projectiles:
		if shot.get("ordnance","") == "constructor" and shot.ship == carrier.id:
			return false
	var point := Vector2(carrier.pos)+Vector2(carrier.pos).direction_to(enemy.pos)*60.0
	wing.sortie = true
	fly(wing,point,delta)
	if Vector2(wing.pos).distance_squared_to(point) <= 49.0:
		for material in plan.materials:
			carrier.cargo[Industry.WARE_ID[material]] -= int(plan.materials[material])
		var seed := Ordnance.spawn(world,carrier,"constructor",wing.pos,Vector2.ZERO,plan.time,0.0)
		seed.unit = plan.unit
		seed.wing_id = wing.id
		wing.cool = plan.time
		wing.returning = true
	return true

static func launch(world, carrier: Dictionary, enemy: Dictionary, wing: Dictionary, weapon: Dictionary, multiplier: float) -> void:
	var flight: String = weapon.get("flight","gun")
	var salvo := int(weapon.get("salvo",1))
	var axis := Vector2(wing.pos).direction_to(enemy.pos)
	for i in salvo:
		var heading := axis.rotated((i-(salvo-1)*0.5)*0.045)
		var missile := flight in ["guided","rocket","bomb"]
		world.projectiles.append({"pos":wing.pos,"vel":heading*weapon.speed,"speed":weapon.speed,"life":maxf(0.55,weapon.range/weapon.speed*1.9),
			"system":carrier.system,"ship":carrier.id,"flag":carrier.flag,"raid":carrier.raid,"credit":Hulls.operator_id(carrier),
			"damage":weapon.damage*wing.count_live*multiplier,"type":int(weapon.type),"emp":float(weapon.get("emp",0.0))*wing.count_live,
			"missile":missile,"target":enemy.id if flight == "guided" else 0,"hp":9.0,"wing_id":wing.id})

static func needs_repair(ship: Dictionary) -> bool:
	return ship.hp < Hulls.MODELS[ship.kind].hp or ship.battle.armor < Hulls.COMBAT[ship.kind].armor - 0.001

static func service(world, carrier: Dictionary, wing: Dictionary, spec: Dictionary, delta: float) -> bool:
	var repair: bool = spec.service == "repair"
	var candidates: Dictionary = world.ships if repair else world.wrecks
	if repair and carrier.cargo[Industry.Ware.HULL_PARTS] <= 0 or not repair and world.cargo_free(carrier) <= 0:
		return false
	var target: Dictionary = candidates.get(wing.get("service_target",0),{})
	if not target.is_empty() and (target.system != carrier.system or repair and (target.dock != 0 or target.layer or not needs_repair(target)) or not repair and target.stock.max() <= 0):
		target = {}
	if target.is_empty():
		wing.search_time = maxf(0.0,float(wing.get("search_time",0.0))-delta)
		if wing.search_time > 0.0:
			return false
		wing.search_time = 0.6
		var nearest := 540.0*540.0
		for key in candidates:
			var item: Dictionary = candidates[key]
			if item.system != carrier.system:
				continue
			if repair:
				if item.flag != carrier.flag or item.dock != 0 or item.layer or item.hp <= 0 or not needs_repair(item):
					continue
			elif item.stock.max() <= 0:
				continue
			var dist := Vector2(carrier.pos).distance_squared_to(item.pos)
			if dist < nearest:
				nearest = dist
				wing.service_target = key
				target = item
	if target.is_empty() or Vector2(carrier.pos).distance_squared_to(target.pos) > 540.0*540.0:
		wing.erase("service_target")
		return false
	var goal: Vector2 = target.pos
	if repair:
		goal += Vector2.from_angle(target.heading+PI*0.5)*float(Defenses.geometry(target.kind).radius)*0.75
	wing.sortie = true
	fly(wing,goal,delta)
	if wing.cool > 0.0 or Vector2(wing.pos).distance_squared_to(goal) > 81.0:
		return true
	if repair:
		carrier.cargo[Industry.Ware.HULL_PARTS] -= 1
		target.hp = minf(Hulls.MODELS[target.kind].hp,target.hp+12.0)
		Defenses.repair_armor(target,15.0)
		wing.cool = 2.0
	else:
		for ware in target.stock.size():
			if target.stock[ware] > 0:
				target.stock[ware] -= 1
				wing.cargo_ware = ware
				wing.returning = true
				if not target.has("hull_id") and target.stock.max() == 0:
					world.wrecks.erase(wing.service_target)
				break
	wing.erase("service_target")
	return true
