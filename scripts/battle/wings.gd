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
			for unit in wing.get("craft",[wing]):
				if unit.hp > 0 and unit.sortie:
					var dist := from.distance_squared_to(unit.pos)
					if dist < closest:
						closest = dist
						candidate = unit
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

static func berth_for(carrier: Dictionary, bay: int, bays: int) -> Vector2:
	var offset := Vector2(-15,(bay-(bays-1)*0.5)*11.0)
	if carrier.has("module_size"):
		# Launch through distinct doors on the central pressure-lock arm.
		offset = Vector2((float(bay)+0.5)/bays-0.5,0.0) * Vector2(carrier.module_size) * 0.68
	return Vector2(carrier.pos) + offset.rotated(carrier.heading)

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
			wings[i] = {"role":spec.get("role","fighter"),"id":id,"count":strength,"pos":berth_for(carrier,i,bays),"hp":wing_hp,"max_hp":wing_hp,
				"speed":clampf(float(spec.get("speed",180.0)),70.0,410.0),"refit_time":maxf(2.0,float(spec.get("refit",6.0))),
				"refit":0.0,"cool":0.0,"sortie":false,"returning":false}
		state.wing_loadout = assigned.duplicate()
	state.replacement_rate = minf(1.0,state.replacement_rate + delta * 0.007)
	var active: Dictionary = state.get("active_profile",{}) if state.system_time > 0.0 else {}
	var multiplier := float(active.get("wing_damage",1.0))
	for i in wings.size():
		var wing: Dictionary = wings[i]
		if wing.has("craft"):
			reconcile_health(wing)
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
				wing.pos = berth_for(carrier,i,bays)
				wing.returning = false
				wing.erase("run")
				wing.erase("craft")
			continue
		var spec := Hulls.wing_spec(wing.id)
		var base := clampi(ceili(wing.hp * wing.count / wing.max_hp),1,wing.count)
		wing.count_live = maxi(1,roundi(base * float(active.get("reserve_multiplier",1.0))))
		wing.reserve_count = wing.count_live - base
		wing.cool = maxf(0.0,wing.cool - delta)
		wing.scan_in = maxf(0.0,float(wing.get("scan_in",0.0))-delta)
		var berth := berth_for(carrier,i,bays)
		if not spec.has("service") and not spec.has("manifestation"):
			advance_squad(world,carrier,wing,spec,enemy,berth,i,delta,multiplier,active,combat,missiles,airborne)
			continue
		if wing.sortie and wing.hp < wing.max_hp*0.4 and not spec.has("service"):
			wing.returning = true
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
				continue
		wing.erase("run")
		if wing.sortie and Vector2(wing.pos).distance_to(berth) > 45.0:
			steer(wing,berth,delta)
		else:
			fly(wing,berth,delta)
		if Vector2(wing.pos).distance_squared_to(berth) < 49.0:
			wing.hp = minf(wing.max_hp,wing.hp + delta * 2.0)
			wing.sortie = false
			if wing.has("cargo_ware") and world.cargo_free(carrier) > 0:
				carrier.cargo[wing.cargo_ware] += 1
				wing.erase("cargo_ware")
			if wing.cool <= 0.0 and wing.hp >= wing.max_hp*0.8 and not wing.has("cargo_ware"):
				wing.returning = false

static func fly(wing: Dictionary, destination: Vector2, delta: float) -> void:
	var offset := destination - Vector2(wing.pos)
	if offset.length_squared() > 0.01:
		wing.heading = offset.angle()
	wing.pos = Vector2(wing.pos).move_toward(destination,wing.speed*delta)

static func craft_position(wing: Dictionary, heading: float, i: int) -> Vector2:
	var rank := ceili(i * 0.5)
	var side := 1 if i % 2 == 1 else -1
	return Vector2(wing.pos) + Vector2(-rank*13,side*rank*14).rotated(heading)

## Keep legacy area damage, carrier abilities and saved squad HP consistent with
## damage applied directly to individual airframes by point defence.
static func reconcile_health(wing: Dictionary) -> void:
	var delta := float(wing.hp) - float(wing.get("reported_hp",wing.hp))
	var total := 0.0
	for unit: Dictionary in wing.craft:
		unit.hp = clampf(unit.hp,0,unit.max_hp)
		if unit.get("reserve",false):
			continue
		var before := float(unit.hp)
		unit.hp = clampf(before+delta,0,unit.max_hp)
		delta -= float(unit.hp)-before
		total += float(unit.hp)
	wing.hp = total
	wing.reported_hp = total

static func new_airframe(wing: Dictionary, berth: Vector2, bay: int, index: int, hp: float, reserve: bool) -> Dictionary:
	var unit_hp := float(wing.max_hp)/int(wing.count)
	var deployed := bool(wing.sortie) and not reserve
	return {"id":wing.id,"role":wing.role,"bay":bay,"index":index,"reserve":reserve,"count_live":1,
		"pos":craft_position(wing,wing.get("heading",0.0),index) if deployed else berth,
		"heading":wing.get("heading",0.0),"hp":hp,"max_hp":unit_hp,"sortie":deployed,
		"speed":float(wing.speed)*(0.94+0.025*((index*3+bay)%6)),"cool":index*0.09,"scan_in":0.0,
		"returning":false,"launch_in":index*0.17+bay*0.09,"refit":wing.refit_time,"cycle":0}

static func advance_squad(world, carrier: Dictionary, wing: Dictionary, spec: Dictionary, enemy: Dictionary, berth: Vector2, bay: int, delta: float, multiplier: float, active: Dictionary, combat, missiles: Variant, airborne: Variant) -> void:
	var count := int(wing.count)
	var unit_hp := float(wing.max_hp)/count
	if not wing.has("craft"):
		var remaining := float(wing.hp)
		wing.craft = []
		for i in count:
			var hp := clampf(remaining,0,unit_hp)
			remaining -= hp
			wing.craft.append(new_airframe(wing,berth,bay,i,hp,false))
	var units: Array = wing.craft
	var extra := maxi(0,roundi(count * (float(active.get("reserve_multiplier",1.0))-1.0)))
	while units.size() < count + extra:
		units.append(new_airframe(wing,berth,bay,units.size(),unit_hp,true))
	if units.size() > count+extra:
		units.resize(count+extra)
	var scramble: bool = combat.ready(carrier) and not enemy.is_empty() and Vector2(carrier.pos).distance_squared_to(enemy.pos) <= pow(engagement_range(spec),2)
	var alive := 0
	var flying := 0
	var returning := 0
	var total_hp := 0.0
	var center := Vector2.ZERO
	var headings := Vector2.ZERO
	for unit: Dictionary in units:
		if unit.hp <= 0.0:
			unit.sortie = false
			unit.refit -= delta*float(carrier.battle.replacement_rate)
			if unit.refit > 0.0:
				continue
			unit.hp = unit_hp
			unit.refit = wing.refit_time
			unit.pos = berth
			unit.launch_in = 0.35
			unit.returning = false
			unit.erase("run")
			carrier.battle.replacement_rate = maxf(0.12,float(carrier.battle.replacement_rate)-0.05)
		unit.cool = maxf(0.0,float(unit.cool)-delta)
		unit.scan_in = maxf(0.0,float(unit.scan_in)-delta)
		if float(unit.hp) < unit_hp*0.40 or not scramble:
			unit.returning = true
		if not unit.sortie:
			unit.pos = berth
			unit.hp = minf(unit_hp,float(unit.hp)+delta*2.0)
			unit.launch_in = maxf(0,float(unit.launch_in)-delta)
			if scramble and unit.hp >= unit_hp*0.8 and unit.cool<=0 and unit.launch_in<=0:
				unit.returning = false
				unit.sortie = true
				unit.heading = berth.angle_to_point(enemy.pos)
		if unit.sortie:
			unit.separation = separation(unit,units)
			if unit.returning:
				unit.erase("run")
				if Vector2(unit.pos).distance_to(berth)>40:
					steer(unit,berth,delta)
				else:
					fly(unit,berth,delta)
				if Vector2(unit.pos).distance_to(berth)<7:
					unit.sortie = false
					unit.launch_in = 0.45+int(unit.index)*0.12
			else:
				attack(world,carrier,enemy,unit,spec,berth,bay*3+int(unit.index),delta,multiplier,missiles,airborne)
		alive += 1
		if not unit.reserve:
			total_hp += float(unit.hp)
		if unit.sortie:
			flying += 1
			if unit.returning: returning += 1
			center += Vector2(unit.pos)
			headings += Vector2.from_angle(unit.heading)
	wing.hp = total_hp
	wing.reported_hp = total_hp
	wing.count_live = alive
	wing.reserve_count = extra
	wing.airborne = flying
	wing.sortie = flying > 0
	wing.returning = flying > 0 and returning==flying
	wing.pos = center/flying if flying else berth
	if headings.length_squared()>0.001:
		wing.heading = headings.angle()

static func separation(unit: Dictionary, units: Array) -> Vector2:
	var push := Vector2.ZERO
	for other: Dictionary in units:
		if other.index == unit.index or not other.sortie or other.hp<=0: continue
		var apart := Vector2(unit.pos)-Vector2(other.pos)
		var distance := apart.length()
		if distance > 0.01 and distance < 26.0:
			push += apart/distance * (1.0-distance/26.0)
	return push.limit_length()

static func steer(wing: Dictionary, destination: Vector2, delta: float) -> void:
	var desired := (Vector2(wing.pos).direction_to(destination) + Vector2(wing.get("separation",Vector2.ZERO))*0.9).angle()
	var heading := float(wing.get("heading",desired))
	var turn := 2.7 if wing.role == "bomber" else (4.9 if wing.role == "interceptor" else 3.8)
	var bank := absf(angle_difference(heading,desired))
	wing.heading = rotate_toward(heading,desired,turn*delta)
	var speed := float(wing.speed)*lerpf(1.0,0.62,clampf(bank/PI,0,1))
	wing.pos = Vector2(wing.pos) + Vector2.from_angle(wing.heading)*speed*delta

## Flanking gates move with the target, while the direction of each attack run
## stays fixed. Passing the target takes the squadron away before its next turn.
static func strafe(wing: Dictionary, enemy: Dictionary, berth: Vector2, bay: int, reach: float, delta: float) -> bool:
	var target: Vector2 = enemy.pos + Vector2(enemy.battle.get("motion",Vector2.ZERO))*0.25
	var run: Dictionary = wing.get("run",{})
	if run.get("target",-1) != enemy.id:
		var side := 1.0 if bay % 2 == 0 else -1.0
		var axis := target.direction_to(wing.pos)
		if axis.is_zero_approx(): axis = Vector2.RIGHT
		axis = axis.rotated(side*(0.52+0.13*(bay%3)))
		var arc := float(enemy.battle.get("shield_arc_live",0))
		var facing := float(enemy.heading)+float(enemy.battle.get("shield_offset",0))
		if enemy.battle.shield and arc > 0.1 and arc < TAU-0.4 and absf(angle_difference(facing,axis.angle())) < arc*0.5:
			axis = Vector2.from_angle(facing+side*(arc*0.5+0.22))
		run = {"target":enemy.id,"phase":"flank","side":side,"axis":axis,"passes":0}
		wing.run = run
	var axis: Vector2 = run.axis
	var side: Vector2 = axis.orthogonal()*float(run.side)
	var radius: float = Defenses.body_geometry(enemy).radius
	var gate := maxf(reach*1.30, radius + float(wing.speed)*0.42 + 55.0)
	var offset := minf(reach*0.48, radius*0.65+13.0+(bay%3)*6.0)
	match run.phase:
		"flank":
			var entry := target + axis*gate
			steer(wing,entry,delta)
			if Vector2(wing.pos).distance_to(entry) < maxf(35.0,wing.speed*0.28):
				run.phase = "strafe"
		"strafe":
			steer(wing,target+side*offset-axis*gate,delta)
			if (Vector2(wing.pos)-target).dot(axis) < 0:
				run.phase = "break"
			return run.phase == "strafe"
		"break":
			var exit_point := target-axis*gate + side*(gate*0.65)
			steer(wing,exit_point,delta)
			if Vector2(wing.pos).distance_to(exit_point) < maxf(45.0,wing.speed*0.30):
				run.passes += 1
				run.side = -float(run.side)
				run.phase = "rally"
		"rally":
			var homeward := target.direction_to(berth)
			var rendezvous := target+homeward*(gate+90.0)+homeward.orthogonal()*((int(wing.bay)%3-1)*70.0)
			steer(wing,rendezvous,delta)
			if Vector2(wing.pos).distance_to(rendezvous) < maxf(52.0,wing.speed*0.34):
				run.axis = target.direction_to(wing.pos).rotated(float(run.side)*(0.35+0.10*(int(wing.index)%4)))
				run.phase = "flank"
	return false

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
	var shots: Array = spec.get("payloads",[])
	var cycle: int = wing.get("cycle",0)
	var weapon: Dictionary = {} if shots.is_empty() else shots[cycle % shots.size()]
	var reach := float(weapon.get("range",120.0))
	var on_run := true
	if wing.role == "support":
		fly(wing,berth+berth.direction_to(goal)*53.0,delta)
	else:
		on_run = strafe(wing,enemy,berth,bay,reach,delta)
	if wing.cool > 0.0 or weapon.is_empty():
		return
	if wing.scan_in <= 0.0:
		wing.scan_in = 0.12
		if intercept(world,carrier,wing,spec,multiplier,missiles,airborne):
			return
		if wing.role == "fighter" or wing.role == "interceptor":
			var hostile := threat(world,carrier,wing.pos,reach,airborne)
			if not hostile.is_empty() and Vector2.from_angle(wing.heading).dot(Vector2(wing.pos).direction_to(hostile.pos)) > 0.70:
				hostile.hp -= weapon.damage * wing.count_live * multiplier
				wing.cool = weapon.cycle
				wing.cycle = cycle + 1
				return
	var flight_time := minf(0.50,Vector2(wing.pos).distance_to(goal)/maxf(1.0,weapon.speed))
	var aim: Vector2 = goal+Vector2(enemy.battle.get("motion",Vector2.ZERO))*flight_time
	if not on_run or Vector2(wing.pos).distance_squared_to(goal) > reach*reach:
		return
	if wing.role != "support" and Vector2.from_angle(wing.heading).dot(Vector2(wing.pos).direction_to(aim)) < 0.76:
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
	var muzzle := Vector2(wing.pos)
	var time := minf(0.50,muzzle.distance_to(enemy.pos)/maxf(1.0,weapon.speed))
	var axis := muzzle.direction_to(Vector2(enemy.pos)+Vector2(enemy.battle.get("motion",Vector2.ZERO))*time)
	for round_index in salvo:
		var heading := axis.rotated((round_index-(salvo-1)*0.5)*0.045)
		world.projectiles.append({"pos":muzzle,"vel":heading*weapon.speed,"speed":weapon.speed,"life":maxf(0.55,weapon.range/weapon.speed*1.9),
			"system":carrier.system,"ship":carrier.id,"flag":carrier.flag,"raid":carrier.raid,"credit":Hulls.combat_credit(carrier),
			"damage":weapon.damage*multiplier,"type":int(weapon.type),"emp":float(weapon.get("emp",0.0)),
			"missile":flight in ["guided","rocket","bomb"],"target":enemy.id if flight == "guided" else 0,"hp":9.0,
			"wing_id":wing.id,"bay":wing.bay,"airframe":wing.index})

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
