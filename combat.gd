extends RefCounted

const MerchantSecurity = preload("res://scripts/economy/merchant_security.gd")

const Hulls = preload("res://hull_catalog.gd")
const Defenses = preload("res://scripts/battle/defenses.gd")
const Wings = preload("res://scripts/battle/wings.gd")
const Abilities = preload("res://scripts/battle/abilities.gd")
const ORDERS := ["自由交战", "护卫旗舰", "集火当前目标", "撤退"]

static func implementation() -> Script:
	return available.get_object() as Script

static func available(vessel: Dictionary, system: int) -> bool:
	return vessel.system == system and vessel.dock == 0 and not vessel.layer and not vessel.battle.retired and vessel.hp > 0.0

static func ready(vessel: Dictionary) -> bool:
	var state: Dictionary = vessel.battle
	return state.overload <= 0.0 and not state.vent and not phased_state(state)

static func system_label(vessel: Dictionary) -> String:
	return Abilities.profile(vessel).label

static func phased(vessel: Dictionary) -> bool:
	return phased_state(vessel.battle)

static func phased_state(state: Dictionary) -> bool:
	return state.get("phase_active", false) or (state.system_time > 0.0 and state.get("active_profile",Abilities.INACTIVE).get("effect","") == "blink")

static func ensure_state(vessel: Dictionary) -> void:
	var state: Dictionary = vessel.battle
	var weapons: Array = vessel.fit.weapons
	if state.has("turret_rates") and state.weapons_seen == weapons:
		return
	if not state.has("shield_offset"):
		state.merge({"shield_offset":0.0,"shield_target":0.0,"shield_arc_live":0.0,"phase_active":false,
			"engine_disabled":0.0,"recoil":[],"turret_angles":[],"disabled_slots":[],"magazines":[],
			"weapons_seen":[],"fighter_wings":[],"replacement_rate":1.0,"boost_energy":100.0,
			"target_id":0,"retarget_delay":0.0,"cr":1.0,"battle_seconds":0.0})
	var near := INF
	var far := 0.0
	var point_defense_slots: Array[int] = []
	var reload_slots: Array[int] = []
	var turret_rates := PackedFloat32Array()
	for key in ["recoil","turret_angles","disabled_slots","magazines","weapons_seen"]:
		var list: Array = state[key]
		if list.size() != weapons.size():
			list.resize(weapons.size())
	for i in weapons.size():
		var weapon: String = weapons[i]
		var spec: Dictionary = Hulls.WEAPONS.get(weapon, Abilities.INACTIVE)
		turret_rates.append(deg_to_rad(float(spec.get("turn_rate",360.0))))
		if spec.get("pd",false):
			point_defense_slots.append(i)
		if spec.get("ammo",0) > 0 and spec.get("ammo_per_sec",0.0) > 0.0:
			reload_slots.append(i)
		if not spec.is_empty() and not spec.get("pd", false):
			near = minf(near, spec.range)
			far = maxf(far, spec.range)
		if state.weapons_seen[i] == weapon:
			continue
		state.weapons_seen[i] = weapon
		state.recoil[i] = 0.0
		state.disabled_slots[i] = 0.0
		state.turret_angles[i] = deg_to_rad(float(Hulls.slot_spec(vessel.kind, i).facing))
		state.magazines[i] = float(spec.get("ammo", 0))
	state.shortest_weapon = near if is_finite(near) else 420.0
	state.longest_weapon = far if far > 0.0 else 420.0
	state.pd_slots = point_defense_slots
	state.reload_slots = reload_slots
	state.turret_rates = turret_rates
	Defenses.grid_for(vessel)

static func fraction(vessel: Dictionary) -> float:
	return (vessel.battle.soft_flux + vessel.battle.hard_flux) / Hulls.capacity(vessel)

static func shield(vessel: Dictionary, enabled: bool, target: Vector2 = Vector2.INF) -> void:
	ensure_state(vessel)
	var model: Dictionary = Hulls.MODELS[vessel.kind]
	var state: Dictionary = vessel.battle
	var active := Abilities.active(vessel)
	if not active.is_empty():
		if active.effect == "fortress" or active.effect == "gaze":
			enabled = true
		if enabled and active.get("block_shield",false):
			enabled = false
	if model.get("phase", false):
		state.phase_active = enabled and not state.vent and state.overload <= 0.0
		state.shield = false
		return
	var shield_type: String = model.get("shield_type", "FRONT")
	state.shield = enabled and ready(vessel) and shield_type != "NONE"
	if target.is_finite() and shield_type == "OMNI":
		state.shield_target = angle_difference(vessel.heading, (target - Vector2(vessel.pos)).angle())
	if not state.shield:
		state.shield_arc_live = 0.0

static func vent(vessel: Dictionary) -> bool:
	var state: Dictionary = vessel.battle
	if Abilities.active(vessel).get("block_vent",false) or not ready(vessel) or state.soft_flux + state.hard_flux <= 0.001:
		return false
	state.shield = false
	state.vent = true
	return true

static func tick(vessel: Dictionary, delta: float, world = null) -> void:
	ensure_state(vessel)
	var state: Dictionary = vessel.battle
	if state.get("ai_shield_hold",0.0) > 0:
		state.ai_shield_hold = maxf(0,state.ai_shield_hold-delta)
	if state.has("fleet_attackers"):
		state.threat_clock += delta
		if state.threat_clock >= state.threat_cleanup:
			state.threat_cleanup = state.threat_clock + 1.0
			for id in state.fleet_attackers.keys():
				if state.fleet_attackers[id] <= state.threat_clock:
					state.fleet_attackers.erase(id)
			if state.fleet_attackers.is_empty():
				state.erase("fleet_attackers")
	var model: Dictionary = Hulls.MODELS[vessel.kind]
	var spec_active: Dictionary = state.get("active_profile",Abilities.INACTIVE) if state.system_time > 0.0 else Abilities.INACTIVE
	var elapsed := minf(delta,state.system_time)
	var clock_delta := delta
	var repair_step := delta
	var dissipation_time := delta
	var reload_time := delta
	if not spec_active.is_empty():
		clock_delta += elapsed * (float(spec_active.get("clock",1.0)) - 1.0)
		repair_step = clock_delta + elapsed * float(spec_active.get("repair_rate",0.0))
		dissipation_time = clock_delta + elapsed * (float(spec_active.get("dissipation",1.0)) - 1.0)
		reload_time = clock_delta + elapsed * (float(spec_active.get("ammo_regen",1.0)) - 1.0)
	var kit := Abilities.profile(vessel)
	if not state.has("system_spec"):
		state.system_spec = kit
	if vessel.locked:
		state.out_of_battle=0.0
	elif state.has("out_of_battle") and state.out_of_battle<12.0:
		state.out_of_battle+=delta
		if state.out_of_battle>=12.0 and kit.has("charges"):
			state.system_charges=kit.charges
	if kit.has("charges") and state.get("system_charges",kit.charges) < kit.charges and kit.get("regen",0)>0:
		state.system_charges = minf(kit.charges,state.system_charges+clock_delta*kit.regen)
	if world != null and kit.effect == "attractor" and vessel.locked:
		Abilities.Ordnance.mote_field(world,vessel,kit,delta)
	if not spec_active.is_empty() and world != null:
		if spec_active.has("interval") and spec_active.effect != "attractor":
			Abilities.pulses(world,vessel,spec_active,elapsed,implementation())
		if spec_active.has("upkeep"): add_flux(world,vessel,Hulls.capacity(vessel)*spec_active.upkeep*elapsed)
		if spec_active.has("hard_upkeep"):
			add_flux(world,vessel,Hulls.capacity(vessel)*spec_active.hard_upkeep*elapsed,true)
		if spec_active.effect in ["extract","fragments"]:
			var enemy := Abilities.target(world,vessel,Vector2.from_angle(vessel.heading),state.longest_weapon*2.0,state.get("system_target",0))
			if not enemy.is_empty():
				train(vessel,enemy.pos,clock_delta)
				for i in vessel.fit.weapons.size():
					var gun: Dictionary=Hulls.WEAPONS.get(vessel.fit.weapons[i],Abilities.INACTIVE)
					if spec_active.effect=="extract" or Abilities.eligible(vessel,gun,i,spec_active):
						var endpoint: Vector2=enemy.pos
						if spec_active.effect=="fragments" and not can_aim(vessel,i,endpoint,gun.range*spec_active.range):
							var mount := Hulls.slot_spec(vessel.kind,i)
							var vector := Vector2.from_angle(vessel.heading+deg_to_rad(mount.facing))
							var muzzle := slot_position(vessel,i)
							if vector.dot((endpoint-muzzle).normalized())<.5: continue
							endpoint=muzzle+vector*minf(muzzle.distance_to(endpoint),gun.range*spec_active.range-.01)
						_fire_slot_prepared(world,vessel,i,endpoint,enemy.id)
	state.engine_disabled = maxf(0.0, state.engine_disabled - repair_step)
	state.hit_flash = maxf(0.0, state.get("hit_flash", 0.0) - delta * 4.0)
	state.shield_flash = maxf(0.0, state.get("shield_flash", 0.0) - delta * 4.0)
	state.retarget_delay = maxf(0.0, state.retarget_delay - delta)
	if state.get("vulnerability_time",0.0) > 0.0:
		var elapsed_vulnerability := delta
		if world!=null and world.ships.has(state.get("vulnerability_source",-1)):
			var origin: Dictionary=world.ships[state.vulnerability_source]
			elapsed_vulnerability *= 2.0 if origin.battle.phase_active else float(Abilities.active(origin).get("clock",1.0))
		state.vulnerability_time = maxf(0.0,state.vulnerability_time-elapsed_vulnerability)
	if state.shield:
		state.shield_offset = rotate_toward(state.shield_offset, state.shield_target, deg_to_rad(float(model.get("shield_turn_rate", 150.0))) * delta)
		state.shield_arc_live = move_toward(state.shield_arc_live, deg_to_rad(float(model.get("shield_arc", 150.0))), deg_to_rad(float(model.get("shield_unfold_rate", 420.0))) * delta)
		state.soft_flux = minf(Hulls.capacity(vessel) - state.hard_flux, state.soft_flux + float(model.get("shield_upkeep", 0.0)) * delta)
		if spec_active.get("effect","")=="gaze":
			state.shield_offset=PI
			state.shield_arc_live=TAU-deg_to_rad(spec_active.gap_arc)
	if world != null and spec_active.get("collision_stall",false) and state.motion.length_squared()>140*140:
		for other in world.ships.values():
			if other.id==vessel.id or not available(other,vessel.system) or phased(other): continue
			var distance: float = Defenses.geometry(vessel.kind).radius+Defenses.geometry(other.kind).radius
			if Vector2(vessel.pos).distance_squared_to(other.pos)<distance*distance:
				state.engine_disabled=2.5
				state.system_time=0
				state.motion*=0.2
				break
	if vessel.locked:
		state.battle_seconds += delta * (2.0 if state.phase_active else 1.0)
		if state.battle_seconds > float(model.get("peak_seconds", 180.0)):
			state.cr = maxf(0.0, state.cr - 0.001 * delta)
	elif vessel.dock != 0:
		state.battle_seconds = 0.0
	var dissipation := Hulls.dissipation(vessel)
	var recovery := dissipation * dissipation_time
	if spec_active.get("stop_dissipation",false): recovery=0.0
	if state.phase_active:
		var capacity := Hulls.capacity(vessel)
		state.hard_flux = minf(capacity - state.soft_flux, state.hard_flux + capacity * 0.11 * delta)
		recovery = 0.0
		if (state.soft_flux + state.hard_flux) / capacity >= 0.9999:
			state.phase_active = false
			state.overload = 3.0
	var locked_time := minf(delta, state.overload)
	if state.overload != 0.0:
		var remaining: float = state.overload - delta
		state.overload = remaining if remaining >= 0.000001 else 0.0
	if state.system_cd != 0.0:
		state.system_cd = maxf(0.0, state.system_cd - delta)
	if state.get("toggle_lock",0.0)>0: state.toggle_lock-=delta
	var will_finish: bool = state.system_time > 0.0 and state.system_time <= delta
	if state.system_time > 0.0 and not spec_active.get("sustained",false): state.system_time = maxf(0.0, state.system_time - delta)
	var cooldowns: Array = state.cooldowns
	var disabled: Array = state.disabled_slots
	var recoil: Array = state.recoil
	if fire_control != null:
		fire_control.cool_slots(cooldowns,disabled,recoil,clock_delta,repair_step,5.0*delta)
	else:
		for slot in cooldowns.size():
			cooldowns[slot] = maxf(0.0, cooldowns[slot] - clock_delta)
			disabled[slot] = maxf(0.0, disabled[slot] - repair_step)
			recoil[slot] = maxf(0.0, recoil[slot] - 5.0 * delta)
	var magazines: Array = state.magazines
	for slot: int in state.reload_slots:
		var spec: Dictionary = Hulls.WEAPONS[vessel.fit.weapons[slot]]
		magazines[slot] = minf(spec.ammo, magazines[slot] + spec.ammo_per_sec * reload_time)
	if locked_time > 0.0:
		recovery = dissipation * (delta - locked_time)
	if state.vent:
		recovery *= 2.0
	if not state.shield and state.hard_flux != 0.0:
		var drained := minf(state.hard_flux, recovery)
		state.hard_flux -= drained
		recovery -= drained
	if state.soft_flux != 0.0 or recovery < 0.0:
		state.soft_flux = maxf(0.0, state.soft_flux - recovery)
	if state.vent and state.hard_flux + state.soft_flux <= 0.0001:
		state.vent = false
	if will_finish and spec_active.get("effect","")=="extract":
		Abilities.refill_magazines(vessel,1.0,false,true)
		vent(vessel)

static func add_flux(world, vessel: Dictionary, amount: float, hard: bool = false) -> void:
	if amount <= 0.0 or vessel.battle.overload > 0.0:
		return
	var state: Dictionary = vessel.battle
	var capacity := Hulls.capacity(vessel)
	amount *= float(Abilities.active(vessel).get("flux_mult",1.0))
	var open := maxf(0.0, capacity - state.hard_flux - state.soft_flux)
	var key := "hard_flux" if hard else "soft_flux"
	state[key] += minf(amount, open)
	if amount >= open and amount > 0.0:
		state.overload = 3.0
		state.vent = false
		state.shield = false
		state.system_time = 0.0
		state.phase_active = false
		state.shield_arc_live = 0.0
		world.combat_event("overload", vessel.pos, vessel.system)

static func hull_impact(world, vessel: Dictionary, amount: float, damage_type: int, point: Vector2, direction: Vector2, beam: bool = false) -> void:
	var effective := amount * float(Hulls.ARMOR_MULT[damage_type]) * (0.5 if beam else 1.0)
	var cell_id := -1
	var previous := 0.0
	if damage_type == 1:
		var cell := Defenses.cell_at(vessel, point)
		cell_id = cell.y * Defenses.GRID.x + cell.x
		previous = Defenses.grid_for(vessel)[cell_id]
	var critical_hp: float = Hulls.MODELS[vessel.kind].hp * 0.25
	var above_threshold: bool = vessel.hp > critical_hp
	var breach := Defenses.damage_armor(vessel, point, effective)
	vessel.hp -= breach
	if above_threshold and vessel.hp > 0.0 and vessel.hp <= critical_hp and vessel.captain != 0 and world.people.has(vessel.captain):
		var captain: Dictionary = world.people[vessel.captain]
		captain.injured_until = maxi(captain.get("injured_until",-1), world.day + 30)
	vessel.battle.hit_flash = 1.0
	vessel.battle.hit_local = (point - Vector2(vessel.pos)).rotated(-float(vessel.heading))
	if breach >= 10.0:
		vessel.crew = maxi(0, vessel.crew - maxi(1, floori(breach / 25.0)))
	world.combat_event("impact", point, vessel.system, direction, clampf(amount / 20.0, 0.5, 2.3))
	if cell_id >= 0 and previous > 0.0 and vessel.battle.armor_grid[cell_id] <= 0.0:
		world.combat_event("breach", point, vessel.system, direction, clampf(breach/20.0, 0.45, 2.0))

static func hit(world, vessel: Dictionary, amount: float, damage_type: int, point: Vector2, direction: Vector2, beam: bool = false, emp: float = 0.0, on_shield: bool = true) -> void:
	if phased(vessel) or amount <= 0.0 or damage_type < 0 or damage_type >= Hulls.SHIELD_MULT.size():
		return
	ensure_state(vessel)
	var state: Dictionary = vessel.battle
	if state.get("vulnerability_time",0.0) > 0.0:
		amount *= float(state.vulnerability)
	if state.system_time > 0.0:
		amount *= float(state.get("active_profile",{}).get("damage_taken",1.0))
	var incoming := amount
	if on_shield and ready(vessel) and Defenses.covered(vessel, point):
		var multiplier: float = Hulls.SHIELD_MULT[damage_type] * float(Hulls.MODELS[vessel.kind].get("shield_efficiency", 1.0))
		if state.system_time > 0.0:
			multiplier *= float(state.get("active_profile",{}).get("shield",1.0))
		state.shield_flash = 1.0
		state.shield_hit_angle = (point - Defenses.shield_world_center(vessel)).angle() - float(vessel.heading)
		var open := maxf(0.0, Hulls.capacity(vessel) - state.soft_flux - state.hard_flux)
		incoming = maxf(0.0, amount - open / multiplier)
		world.combat_event("shield", point, vessel.system, direction)
		add_flux(world, vessel, amount * multiplier, not beam)
	if incoming > 0.0001:
		hull_impact(world, vessel, incoming, damage_type, point, direction, beam)
		if emp > 0.0:
			var nearest := -1
			var distance := INF
			for slot in vessel.fit.weapons.size():
				var gap := slot_position(vessel, slot).distance_squared_to(point)
				if gap < distance and not str(vessel.fit.weapons[slot]).is_empty():
					nearest = slot
					distance = gap
			var duration := clampf(emp / 12.0, 0.35, 6.0)
			var engine_hit := false
			for engine: Vector2 in Hulls.MODELS[vessel.kind].get("engine_slots", []):
				if (Vector2(vessel.pos) + engine.rotated(vessel.heading)).distance_squared_to(point) < distance:
					engine_hit = true
			if engine_hit:
				state.engine_disabled = maxf(state.engine_disabled, duration)
			elif nearest >= 0:
				state.disabled_slots[nearest] = maxf(state.disabled_slots[nearest], duration)
			world.combat_event("emp", point, vessel.system, direction)

static func system(world, vessel: Dictionary, direction: Vector2, aim_point: Vector2 = Vector2.INF, target_id: int = 0) -> bool:
	ensure_state(vessel)
	var state: Dictionary = vessel.battle
	var spec := Abilities.profile(vessel)
	if spec.effect=="none": return false
	if spec.get("toggle",false) and state.system_time>0.0:
		if state.get("toggle_lock",0.0)>0.0: return false
		state.system_time=0.0
		state.system_cd=maxf(0.35,spec.cool)
		return true
	var cost: float = float(Hulls.COMBAT[vessel.kind].capacity)*spec.flux_capacity if spec.has("flux_capacity") else spec.flux
	if state.overload>0 or state.vent or state.system_cd>0 or state.system_time>0 or Hulls.capacity(vessel)-state.hard_flux-state.soft_flux<=cost:
		return false
	if spec.has("charges") and state.get("system_charges",spec.charges)<0.99999:
		return false
	if spec.effect == "termination" and state.fighter_wings.is_empty():
		Wings.advance(world,vessel,{},0.0,implementation())
	if not Abilities.activate(world,vessel,direction,spec,implementation(),aim_point,target_id):
		return false
	add_flux(world,vessel,cost,spec.get("hard_flux",false))
	state.system_cd=spec.cool
	state.system_time=spec.duration
	state.active_profile=spec
	if spec.has("charges"): state.system_charges=float(state.get("system_charges",spec.charges))-1.0
	if spec.get("toggle",false): state.toggle_lock=.35
	if spec.effect in ["fortress","gaze"]: shield(vessel,true)
	if spec.effect=="attractor":
		state.mote_delay=0.0
		Abilities.Ordnance.mote_field(world,vessel,spec,0)
	world.combat_event("system",vessel.pos,vessel.system)
	return true

static func slot_position(vessel: Dictionary, index: int) -> Vector2:
	var slot: Dictionary = Hulls.slot_spec(vessel.kind, index)
	return Vector2(vessel.pos) + Vector2(slot.offset).rotated(vessel.heading)

static func can_aim(vessel: Dictionary, index: int, endpoint: Vector2, distance: float) -> bool:
	var slot: Dictionary = Hulls.MODELS[vessel.kind].mounts[index]
	var heading: float = vessel.heading
	var offset: Vector2 = slot.offset
	return within_arc(endpoint - (Vector2(vessel.pos) + offset.rotated(heading)),heading,slot,distance)

static func within_arc(vector: Vector2, heading: float, mount: Dictionary, reach: float) -> bool:
	return vector.length_squared() <= reach * reach and absf(angle_difference(heading + deg_to_rad(mount.facing), vector.angle())) <= deg_to_rad(mount.arc*.5) + .00001

static func flag_threat(flagship: Dictionary, attacker: int) -> void:
	var state: Dictionary = flagship.battle
	if not state.has("fleet_attackers"):
		state.fleet_attackers = {}
		state.threat_clock = 0.0
		state.threat_cleanup = 1.0
	state.fleet_attackers[attacker] = state.threat_clock + 5.0

static func fire_slot(world, vessel: Dictionary, index: int, endpoint: Vector2, target_id: int = 0) -> bool:
	ensure_state(vessel)
	return _fire_slot_prepared(world, vessel, index, endpoint, target_id)

static func _fire_slot_prepared(world, vessel: Dictionary, index: int, endpoint: Vector2, target_id: int, instigator: int = 0) -> bool:
	var state: Dictionary = vessel.battle
	var key: String = vessel.fit.weapons[index]
	if key.is_empty() or state.cooldowns[index] > 0.0 or state.disabled_slots[index] > 0.0 or not ready(vessel):
		return false
	var spec: Dictionary = Hulls.WEAPONS[key]
	var active := Abilities.active(vessel)
	if spec.get("pd",false) or active.get("block_fire",false):
		return false
	var modifier := Abilities.INACTIVE
	if not active.is_empty():
		if Abilities.eligible(vessel,spec,index,active):
			modifier = active
		elif active.effect == "lidar":
			return false
	var mount: Dictionary = Hulls.MODELS[vessel.kind].mounts[index]
	var point := Vector2(vessel.pos) + Vector2(mount.offset).rotated(vessel.heading)
	var range_factor: float = Abilities.profile(vessel).get("passive_range",1.0) if active.is_empty() else modifier.get("range",1.0)
	var reach: float = spec.range * range_factor
	if not within_arc(endpoint - point,vessel.heading,mount,reach):
		return false
	var direction := (endpoint - point).normalized()
	if direction.is_zero_approx() or not weapon_aligned(vessel, index, direction, spec, mount):
		return false
	if spec.get("ammo", 0) > 0:
		if state.magazines[index] < 1.0:
			return false
		state.magazines[index] -= 1.0
	var missile: bool = spec.get("missile", false)
	var burst: int = spec.get("burst",1)
	if target_id != 0:
		if instigator != 0:
			world.engage_ship(vessel,world.ships.get(target_id,{}),instigator)
		var pilot: Variant = world.get("player")
		if vessel.get("captain",0) == pilot:
			vessel.battle.last_fired_target = target_id
		elif world.ships.get(target_id,{}).get("captain",0) == pilot:
			flag_threat(world.ships[target_id],vessel.id)
	var shot_state := {"pos":point, "vel":direction * spec.speed, "speed":spec.speed, "life":reach / maxf(spec.speed, 1.0),
		"system":vessel.system,"ship":vessel.id,"flag":vessel.flag,"raid":vessel.raid,"credit":Hulls.combat_credit(vessel),
		"damage":spec.damage * modifier.get("damage",1.0),"type":spec.type,"missile":missile,"target":target_id,"hp":14.0,"emp":spec.get("emp", 0.0)}
	if spec.get("beam", false):
		var end := point + direction * reach
		var contact := trace(world, shot_state, point, end)
		if not contact.is_empty():
			end = contact.point
			impact(world, shot_state, contact, true)
		world.combat_event("beam", point, vessel.system, end - point)
	else:
		var spread: float = spec.get("spread",0.0) * modifier.get("spread",1.0)
		for shot in range(burst):
			var vector := direction.rotated((shot - (burst-1)*0.5) * spread)
			var bolt := shot_state if shot == burst - 1 else shot_state.duplicate()
			bolt.vel = vector * spec.speed
			bolt.damage /= burst
			world.projectiles.append(bolt)
	vessel.battle.recoil[index] = 1.0
	vessel.battle.cooldowns[index] = spec.cool * modifier.get("rate",1.0) / (Hulls.crew_efficiency(vessel) * lerpf(0.6, 1.0, vessel.battle.cr))
	world.combat_event("muzzle", point, vessel.system, direction, 1.2 if missile else 0.8)
	add_flux(world, vessel, spec.flux * modifier.get("weapon_flux",1.0))
	return true

static func train(vessel: Dictionary, endpoint: Vector2, delta: float) -> void:
	ensure_state(vessel)
	var mounts: Array = Hulls.MODELS[vessel.kind].mounts
	var angles: Array = vessel.battle.turret_angles
	var weapons: Array = vessel.fit.weapons
	var heading: float = vessel.heading
	var local_target := (endpoint - Vector2(vessel.pos)).rotated(-heading)
	if fire_control != null:
		if not turret_geometry.has(vessel.kind):
			var layout := PackedVector4Array()
			for mount: Dictionary in mounts:
				layout.append(Vector4(mount.offset.x,mount.offset.y,deg_to_rad(mount.facing),deg_to_rad(mount.arc*.5)))
			turret_geometry[vessel.kind] = layout
		fire_control.train(local_target,turret_geometry[vessel.kind],vessel.battle.turret_rates,angles,delta)
		return
	for i in vessel.fit.weapons.size():
		var slot: Dictionary = mounts[i]
		var neutral := deg_to_rad(float(slot.facing))
		var aim := (local_target - Vector2(slot.offset)).angle()
		var half_arc := deg_to_rad(float(slot.arc)) * 0.5
		var dest := neutral + clampf(angle_difference(neutral, aim), -half_arc, half_arc)
		var weapon: Dictionary = Hulls.WEAPONS.get(weapons[i], {})
		var speed := deg_to_rad(float(weapon.get("turn_rate", 360.0)))
		angles[i] = rotate_toward(angles[i], dest, delta * speed)

static func weapon_aligned(vessel: Dictionary, index: int, direction: Vector2, spec: Dictionary, slot: Dictionary = Abilities.INACTIVE) -> bool:
	if slot.is_empty():
		slot = Hulls.slot_spec(vessel.kind, index)
	if slot.type == "固定":
		return true
	var angle: float = vessel.heading + vessel.battle.turret_angles[index]
	return absf(angle_difference(angle, direction.angle())) <= deg_to_rad(float(spec.get("aim_tolerance", 14.0)))

static func group_fire(world, vessel: Dictionary, group: int, point: Vector2, target_id: int = 0, instigator: int = 0) -> int:
	ensure_state(vessel)
	var fired := 0
	var groups: Array = vessel.fit.groups
	var target_ship: Dictionary = world.ships.get(target_id, {}) if target_id != 0 else {}
	for index in groups.size():
		var in_group: bool = (groups[index] in [1, 2, 3]) if group == 0 else (groups[index] == group)
		if not in_group:
			continue
		var aim := point
		if not target_ship.is_empty():
			var slot_aim := lead_for_slot(vessel, target_ship, index)
			if slot_aim.is_finite():
				aim = slot_aim
		if _fire_slot_prepared(world, vessel, index, aim, target_id,instigator):
			fired += 1
	return fired

static func fire_groups(fit: Variant) -> Array:
	if fit is Dictionary:
		return Hulls.Fitting.index_fire_groups(fit.weapons,fit.groups,Hulls.WEAPONS)
	return fit.fire_groups(Hulls.WEAPONS)

# Predict the intercept point per ready weapon slot, avoiding wasted shots on phased targets or self-overload.
static func auto_fire(world, vessel: Dictionary, foe: Dictionary, pilot: bool = false) -> void:
	if not ready(vessel) or foe.is_empty() or not available(foe, vessel.system) or phased(foe):
		return
	ensure_state(vessel)
	var fit = vessel.fit
	var state: Dictionary = vessel.battle
	var groups := fire_groups(fit)
	var timers: Array = state.cooldowns
	var disabled: Array = state.disabled_slots
	var capacity := Hulls.capacity(vessel)
	var foe_shielded: bool = foe.battle.get("shield", false) and fraction(foe) < 0.35
	var has_non_missile := false
	if not pilot and foe_shielded:
		for key: String in fit.weapons:
			if not key.is_empty():
				var wspec: Dictionary = Hulls.WEAPONS[key]
				if not wspec.get("pd", false) and not wspec.get("missile", false):
					has_non_missile = true
					break
	for group in groups.size():
		if pilot and not fit.auto[group]:
			continue
		var slots: Array = groups[group]
		for slot: int in slots:
			if timers[slot] > 0.0 or disabled[slot] > 0.0:
				continue
			var spec: Dictionary = Hulls.WEAPONS[fit.weapons[slot]]
			if not pilot:
				var flux_cost := float(spec.flux)
				if flux_cost > 0.0 and state.hard_flux + state.soft_flux + flux_cost >= capacity * 0.96 and foe.hp > float(spec.damage) * 1.5:
					continue
				if foe_shielded and has_non_missile and spec.get("ammo", 0) > 0 and spec.get("missile", false) and int(spec.type) == 1:
					continue
			var aim := lead_for_slot(vessel, foe, slot)
			if not aim.is_finite():
				aim = foe.pos
			_fire_slot_prepared(world, vessel, slot, aim, foe.id)

static func point_defense(world, vessel: Dictionary, incoming: Variant = null, airborne: Variant = null, protect: Dictionary = {}) -> void:
	if incoming is Array and incoming.is_empty() and airborne is Array and airborne.is_empty():
		return
	ensure_state(vessel)
	var active := Abilities.active(vessel)
	if not ready(vessel) or active.get("block_fire",false):
		return
	var passive_range := float(vessel.battle.get("system_spec",{}).get("passive_range",1.0)) if active.is_empty() else 1.0
	for index: int in vessel.battle.pd_slots:
		if vessel.battle.cooldowns[index] > 0.0 or vessel.battle.disabled_slots[index] > 0.0:
			continue
		var spec: Dictionary = Hulls.WEAPONS[vessel.fit.weapons[index]]
		if active.get("effect","")=="lidar" and not Abilities.eligible(vessel,spec,index,active):
			continue
		var modifier: Dictionary=active if not active.is_empty() and Abilities.eligible(vessel,spec,index,active) else {}
		var reach: float=spec.range*modifier.get("range",passive_range)
		var best: Dictionary = {}
		var nearest: float = reach
		var muzzle := slot_position(vessel, index)
		for missile in (world.projectiles if incoming == null else incoming):
			if not missile.missile or missile.hp <= 0.0 or missile.system != vessel.system:
				continue
			var distance_sq := muzzle.distance_squared_to(missile.pos)
			if distance_sq >= nearest * nearest:
				continue
			if missile.get("ordnance","") != "flare" and missile.vel.dot(Vector2(vessel.pos) - Vector2(missile.pos)) <= 0.0:
				if protect.is_empty() or missile.vel.dot(Vector2(protect.pos) - Vector2(missile.pos)) <= 0.0:
					continue
			if world.enemy(vessel,missile) and can_aim(vessel, index, missile.pos, reach):
				best = missile
				nearest = sqrt(distance_sq)
		var fighter := Wings.threat(world, vessel, muzzle, nearest, airborne)
		if not fighter.is_empty() and can_aim(vessel, index, fighter.pos, reach):
			best = fighter
		if not best.is_empty() and (spec.get("ammo", 0) <= 0 or vessel.battle.magazines[index] >= 1.0):
			best.hp -= spec.damage*float(modifier.get("damage",1.0))
			vessel.battle.recoil[index] = 1.0
			vessel.battle.turret_angles[index] = (Vector2(best.pos) - muzzle).angle() - vessel.heading
			if spec.get("ammo", 0) > 0:
				vessel.battle.magazines[index] -= 1.0
			vessel.battle.cooldowns[index] = spec.cool*float(modifier.get("rate",1.0)) / Hulls.crew_efficiency(vessel)
			world.combat_event("intercept", best.pos, vessel.system, (best.pos - muzzle).normalized())
			add_flux(world, vessel, spec.flux*float(modifier.get("weapon_flux",1.0)))
			if not ready(vessel):
				break

const COLLISION_CELL := 64.0
static var collision_engine: RefCounted
static var collision_checked := false
static var collision_models := {}
static var collision_shapes := {}
static var fire_control: RefCounted
static var turret_geometry := {}

static func init_accelerators() -> void:
	if not collision_checked:
		collision_checked = true
		if OS.get_name() == "Windows" and Engine.get_architecture_name() == "x86_64" and "--script-collision" not in OS.get_cmdline_user_args():
			if not ClassDB.class_exists(&"FleetCollision"):
				GDExtensionManager.load_extension("res://native/battle/fleet_collision.gdextension")
			if ClassDB.class_exists(&"FleetCollision"):
				collision_engine = ClassDB.instantiate(&"FleetCollision")
			if ClassDB.class_exists(&"FleetScanner"):
				fire_control = ClassDB.instantiate(&"FleetScanner")

static func prepare_collision(world, system_id: int) -> bool:
	init_accelerators()
	if collision_engine == null:
		return false
	collision_engine.clear_bodies()
	for ship: Dictionary in world.ships.values():
		if available(ship, system_id) and not phased(ship):
			if not collision_models.has(ship.kind) or not is_same(collision_shapes[ship.kind],Defenses.shapes.get(ship.kind)):
				var shape := Defenses.geometry(ship.kind)
				var parts: Array = Hulls.MODELS[ship.kind].get("modules",[])
				if parts.size() > 63:
					return false
				collision_engine.define_hull(ship.kind,shape.bounds,parts,shape.module_radius,shape.shield_center,shape.shield_radius)
				collision_models[ship.kind] = parts
				collision_shapes[ship.kind] = shape
			sync_collision_body(ship)
	return true

static func sync_collision_body(ship: Dictionary) -> void:
	if ship.hp <= 0.0 or phased(ship):
		collision_engine.remove_body(ship.id)
		return
	var state: Dictionary = ship.battle
	var destroyed := 0
	if state.has("module_integrity"):
		var parts: Array = collision_models[ship.kind]
		for index in parts.size():
			var part: Dictionary = parts[index]
			if state.module_integrity.get(part.mount,{}).get("hp",part.hp) <= 0.0:
				destroyed |= 1 << index
	collision_engine.set_body(ship.id,ship.kind,ship.pos,ship.heading,state.get("shield_offset",0.0),state.get("shield_arc_live",0.0) if state.shield else 0.0,destroyed)

static func native_contact(world, shot: Dictionary, start: Vector2, finish: Vector2, relations: Dictionary) -> Dictionary:
	var contacts: PackedFloat64Array = collision_engine.sweep(start,finish,shot.ship)
	for i in range(0,contacts.size(),3):
		var id := int(contacts[i])
		var ship: Dictionary = world.ships[id]
		var pair := Vector2i(shot.ship,id)
		if not relations.has(pair):
			relations[pair] = world.enemy(shot,ship)
		if relations[pair]:
			var part := int(contacts[i+2])
			var hit := {"ship":ship,"point":start.lerp(finish,contacts[i+1]),"shield":part == -2}
			if part >= 0:
				hit.module = collision_models[ship.kind][part]
			return Abilities.Ordnance.screen_contact(world,shot,start,finish,hit) if world.has_meta("battle_screens") else hit
	return Abilities.Ordnance.screen_contact(world,shot,start,finish,{}) if world.has_meta("battle_screens") else {}

static func ballistic_impact(shot: Dictionary,victim: Variant,point: Vector2,part: int,world) -> bool:
	if part == -3:
		impact(world,shot,{"screen":victim,"point":point})
		return world.succession or world.attention
	var ship: Dictionary = world.ships[victim]
	var contact := {"ship":ship,"point":point,"shield":part == -2}
	if part >= 0:
		contact.module = collision_models[ship.kind][part]
	impact(world,shot,contact)
	sync_collision_body(ship)
	return world.succession or world.attention

static func spatial_buckets(world, system_id: int) -> Dictionary:
	var buckets := {}
	for ship in world.ships.values():
		if not available(ship, system_id) or phased(ship):
			continue
		var shape := Defenses.geometry(ship.kind)
		var reach: float = maxf(shape.module_radius, shape.shield_radius + Vector2(shape.shield_center).length())
		var first := Vector2i(((Vector2(ship.pos) - Vector2.ONE * reach) / COLLISION_CELL).floor())
		var last := Vector2i(((Vector2(ship.pos) + Vector2.ONE * reach) / COLLISION_CELL).floor())
		for x in range(first.x, last.x + 1):
			for y in range(first.y, last.y + 1):
				var key := Vector2i(x,y)
				if not buckets.has(key):
					buckets[key] = []
				buckets[key].append(ship)
	return buckets

static func nearby_targets(buckets: Dictionary, start: Vector2, finish: Vector2) -> Array:
	var first := Vector2i((start.min(finish) / COLLISION_CELL).floor())
	var last := Vector2i((start.max(finish) / COLLISION_CELL).floor())
	if first == last:
		return buckets.get(first, [])
	var found := {}
	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			for ship in buckets.get(Vector2i(x,y), []):
				found[ship.id] = ship
	return found.values()

static func trace(world, blast: Dictionary, start: Vector2, finish: Vector2, candidates: Variant = null, relations: Variant = null) -> Dictionary:
	var best := INF
	var contact := {}
	var span := finish - start
	var length_sq := span.length_squared()
	for ship in (world.ships.values() if candidates == null else candidates):
		if ship.id == blast.ship or ship.hp <= 0:
			continue
		if candidates == null and (not available(ship, blast.system) or phased(ship)):
			continue
		if candidates == null and length_sq > 0.0:
			var center: Vector2 = ship.pos
			var shape := Defenses.geometry(ship.kind)
			var reach: float = shape.reach
			var at := clampf((center - start).dot(span)/length_sq,0.0,1.0)
			if center.distance_squared_to(start+span*at) > reach*reach:
				continue
		if relations != null:
			var pair := Vector2i(blast.ship,ship.id)
			if not relations.has(pair):
				relations[pair] = world.enemy(blast,ship)
			if not relations[pair]:
				continue
		elif not world.enemy(blast,ship):
			continue
		var hull := Defenses.hull_contact(ship, start, finish)
		var barrier := Defenses.shield_contact(ship, start, finish)
		var module := Defenses.module_contact(ship,start,finish) if not Hulls.MODELS[ship.kind].get("modules",[]).is_empty() else {}
		if not module.is_empty() and (not hull.is_finite() or start.distance_squared_to(module.point) <= start.distance_squared_to(hull)):
			hull = module.point
		else:
			module = {}
		var on_shield := barrier.is_finite() and (not hull.is_finite() or start.distance_squared_to(barrier) <= start.distance_squared_to(hull))
		var point := barrier if on_shield else hull
		if not point.is_finite():
			continue
		var dist := start.distance_squared_to(point)
		if dist >= best:
			continue
		best = dist
		contact = {"ship":ship, "point":point, "shield":on_shield}
		if not on_shield and not module.is_empty():
			contact.module = module.module
	return Abilities.Ordnance.screen_contact(world,blast,start,finish,contact) if world.has_meta("battle_screens") else contact

static func impact(world, shot: Dictionary, contact: Dictionary, beam: bool = false) -> void:
	if contact.has("screen"):
		contact.screen.hp-=shot.damage
		world.combat_event("intercept",contact.point,shot.system)
		return
	var victim: Dictionary = contact.ship
	if victim.get("captain",0) == world.get("player"):
		flag_threat(victim,shot.ship)
	var amount: float = shot.damage
	if contact.has("module"):
		var part: Dictionary = contact.module
		if not victim.battle.has("module_integrity"):
			victim.battle.module_integrity = {}
		var integrity: Dictionary = victim.battle.module_integrity.get(part.mount,{"hp":part.hp,"armor":part.armor})
		var absorbed := minf(integrity.armor,amount * float(Hulls.ARMOR_MULT[shot.type]))
		integrity.armor -= absorbed
		amount = maxf(0.0,amount - absorbed/float(Hulls.ARMOR_MULT[shot.type]))
		var structural := minf(integrity.hp,amount)
		integrity.hp -= structural
		amount -= structural
		victim.battle.module_integrity[part.mount] = integrity
		world.combat_event("rupture" if integrity.hp <= 0.0 else "impact",contact.point,victim.system)
	hit(world, victim, amount, shot.type, contact.point, Vector2(shot.vel).normalized(), beam, shot.get("emp", 0.0), contact.shield)
	if shot.damage > 0 or shot.get("emp",0.0) > 0:
		MerchantSecurity.report_attack(world,victim,world.ships.get(shot.ship,shot))
	victim.locked = true
	if world.ships.has(shot.ship):
		world.ships[shot.ship].locked = true
	if victim.hp <= 0.0:
		world.destruction(victim.id, shot.credit)

static func project(world, system_id: int, delta: float) -> void:
	if world.projectiles.is_empty():
		return
	var native := prepare_collision(world,system_id)
	var local := {} if native else spatial_buckets(world,system_id)
	var relations := {}
	var hit_callback := ballistic_impact.bind(world)
	var ordnance_frame := {}
	var cursor: int = world.projectiles.size()-1
	while cursor >= 0:
		if native:
			var screens: Array = world.get_meta("battle_screens",[])
			cursor = collision_engine.advance_ballistics(world.projectiles,cursor,system_id,delta,world,world.ships,screens,hit_callback)
			if screens.is_empty() and world.has_meta("battle_screens"):
				world.remove_meta("battle_screens")
			if cursor < 0:
				return
		var index := cursor
		cursor -= 1
		var blast: Dictionary = world.projectiles[index]
		if blast.system != system_id or blast.hp <= 0.0 or blast.life <= 0.0:
			world.projectiles.remove_at(index)
			continue
		if blast.has("ordnance") and Abilities.Ordnance.advance(world,blast,delta,implementation(),ordnance_frame):
			if native and blast.life <= 0.0:
				if blast.ordnance == "constructor":
					native = prepare_collision(world,system_id)
					local = {} if native else spatial_buckets(world,system_id)
				elif blast.ordnance == "mote":
					if world.ships.has(blast.target):
						sync_collision_body(world.ships[blast.target])
					else:
						collision_engine.remove_body(int(blast.target))
			if blast.life<=0 or blast.hp<=0: world.projectiles.remove_at(index)
			if world.succession or world.attention:
				return
			continue
		var previous: Vector2 = blast.pos
		if blast.get("mine",false):
			blast.life -= delta
			var tracked: Dictionary=world.ships.get(blast.get("target",0),{})
			if tracked.is_empty() and blast.get("track_speed",0)>0:
				blast.search_delay=blast.get("search_delay",0.0)-delta
				if blast.search_delay<=0:
					blast.search_delay=.25
					var nearest:=120.0*120.0
					for ship in world.ships.values():
						var dist:=previous.distance_squared_to(ship.pos)
						if dist<nearest and available(ship,system_id) and not phased(ship) and world.enemy(blast,ship):
							nearest=dist
							tracked=ship
					blast.target=tracked.get("id",0)
			if not tracked.is_empty() and available(tracked,system_id):
				blast.pos=Vector2(blast.pos).move_toward(tracked.pos,blast.get("track_speed",0.0)*delta)
				previous=blast.pos
			blast.arming = maxf(0.0,blast.arming-delta)
			if blast.arming <= 0.0:
				var victims := []
				if native and local.is_empty():
					local = spatial_buckets(world,system_id)
				for ship in nearby_targets(local,previous-Vector2(54,54),previous+Vector2(54,54)):
					if ship.hp > 0.0 and previous.distance_to(ship.pos) <= float(Defenses.geometry(ship.kind).radius)+38.0 and world.enemy(blast,ship):
						victims.append(ship)
				if not victims.is_empty() or blast.has("triggered"):
					blast.triggered=true
					blast.fuse=blast.get("fuse",0.0)-delta
					if blast.fuse>0: continue
					blast.life = 0.0
					world.combat_event("rupture",previous,system_id)
					for victim in victims:
						var direction := (Vector2(victim.pos)-previous).normalized()
						var point := Vector2(victim.pos) - direction * float(Defenses.geometry(victim.kind).radius)
						impact(world,blast,{"ship":victim,"point":point,"shield":Defenses.covered(victim,point)})
						if native:
							sync_collision_body(victim)
						if world.succession or world.attention:
							world.projectiles.remove_at(index)
							return
			if blast.life <= 0.0:
				world.projectiles.remove_at(index)
			continue
		if blast.missile:
			var target: Dictionary = world.ships.get(blast.target, {})
			if blast.get("decoy_time",0)>0:
				blast.decoy_time-=delta
				blast.vel=Vector2.from_angle(rotate_toward(blast.vel.angle(),(Vector2(blast.decoy_point)-Vector2(blast.pos)).angle(),3.5*delta))*blast.speed
			elif not target.is_empty() and available(target, system_id) and world.enemy(blast, target):
				var angle: float = rotate_toward(blast.vel.angle(), (target.pos - blast.pos).angle(), 2.1 * delta)
				blast.vel = Vector2.from_angle(angle) * blast.speed
		var interval := minf(delta, blast.life)
		blast.pos += blast.vel * interval
		blast.life -= interval
		var contact := native_contact(world,blast,previous,blast.pos,relations) if native else trace(world, blast, previous, blast.pos, nearby_targets(local, previous, blast.pos),relations)
		if not contact.is_empty():
			blast.life = 0.0
			world.projectiles.remove_at(index)
			impact(world, blast, contact)
			if native and contact.has("ship"):
				sync_collision_body(contact.ship)
			if world.succession or world.attention:
				return
		elif blast.life <= 0.0:
			world.projectiles.remove_at(index)

static func ai_mode(vessel: Dictionary, distance: float, personality: int = 2) -> String:
	var flux := fraction(vessel)
	var thresholds := [0.92,0.85,0.62,0.45,0.28]
	if vessel.battle.overload > 0.0 or vessel.battle.vent:
		return "降盾散热"
	if vessel.hp < Hulls.MODELS[vessel.kind].hp * 0.27:
		return "脱离交战"
	if Abilities.active(vessel).get("effect","")=="incursion" and flux<0.78: return "压进"
	if flux >= float(thresholds[personality]) or (vessel.battle.ai == "降盾散热" and flux > minf(0.38, thresholds[personality] * 0.65)):
		return "降盾散热"
	if distance > preferred_range(vessel, personality):
		return "压进"
	return "侧翼拉扯"

static func preferred_range(vessel: Dictionary, personality: int) -> float:
	ensure_state(vessel)
	var factors := [0.55,0.75,0.95,1.05,1.15]
	return float(vessel.battle.shortest_weapon if personality < 2 else vessel.battle.longest_weapon) * float(factors[personality])

static func lead_point(vessel: Dictionary, target: Dictionary, group: int) -> Vector2:
	if group < 1 or group > 3:
		return target.pos
	return lead_for_slots(vessel,target,fire_groups(vessel.fit)[group - 1])

static func lead_for_slot(vessel: Dictionary, target: Dictionary, slot: int) -> Vector2:
	var key: String = vessel.fit.weapons[slot]
	if key.is_empty():
		return target.pos
	var spec: Dictionary = Hulls.WEAPONS[key]
	if spec.get("beam", false):
		return target.pos
	var offset := Vector2(target.pos) - slot_position(vessel, slot)
	var velocity: Vector2 = target.battle.motion
	var speed := float(spec.speed)
	var a := velocity.length_squared() - speed * speed
	var b := 2.0 * offset.dot(velocity)
	var c := offset.length_squared()
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return Vector2.INF
	var t := INF
	if absf(a) < 0.0001:
		if b < -0.0001:
			t = -c / b
	else:
		var root := sqrt(disc)
		var first := (-b - root) / (2.0 * a)
		var second := (-b + root) / (2.0 * a)
		if first >= 0.0:
			t = first
		if second >= 0.0:
			t = minf(t, second)
	if is_finite(t):
		return Vector2(target.pos) + velocity * t
	return Vector2.INF

static func lead_for_slots(vessel: Dictionary, target: Dictionary, slots: Array) -> Vector2:
	for i: int in slots:
		var point := lead_for_slot(vessel, target, i)
		if point.is_finite():
			return point
	return target.pos
