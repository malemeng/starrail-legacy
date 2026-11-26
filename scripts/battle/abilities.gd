extends RefCounted

const Hulls = preload("res://hull_catalog.gd")
const Ordnance = preload("res://scripts/battle/system_ordnance.gd")
static var profiles: Dictionary = Hulls.read_catalog("res://scripts/battle/ship_systems.json")
const FALLBACK := {"boost":"maneuveringjets","phase":"displacer","burst":"ammofeed","repair":"construction_swarm"}

const UNFITTED := {"id":"","label":"未配备舰载系统","name":"","effect":"none","description":"该舰体没有主动舰载系统。","duration":0.0,"cool":0.0,"flux":0.0}
const INACTIVE := {}
static var by_hull: Array[Dictionary] = build_hull_profiles()

static func build_hull_profiles() -> Array[Dictionary]:
	var indexed: Array[Dictionary] = []
	for kind in Hulls.MODELS.size():
		var hull: Dictionary = Hulls.MODELS[kind]
		var source: String
		if hull.has("source_system"):
			source = hull.source_system
		else:
			source = FALLBACK.get(Hulls.COMBAT[kind].get("system",""), "")
		indexed.append(profiles.get(source, UNFITTED))
	return indexed

static func profile(vessel: Dictionary) -> Dictionary:
	return by_hull[vessel.kind]

static func active(vessel: Dictionary) -> Dictionary:
	var state: Dictionary = vessel.battle
	return state.get("active_profile", INACTIVE) if state.system_time > 0 else INACTIVE

static func target(world, vessel: Dictionary, direction: Vector2, reach: float, preferred: int = 0, friendly: bool = false) -> Dictionary:
	if preferred != 0:
		var selected: Dictionary = world.ships.get(preferred, INACTIVE)
		if selected.is_empty() or selected.id == vessel.id or selected.system != vessel.system or selected.layer or selected.dock != 0 or selected.hp <= 0 or selected.battle.retired:
			return INACTIVE
		if Vector2(vessel.pos).distance_squared_to(selected.pos) <= reach * reach and (friendly or world.enemy(vessel, selected)):
			return selected
		return INACTIVE
	var best := INF
	var chosen := INACTIVE
	for ship in world.ships.values():
		if ship.id == vessel.id or ship.system != vessel.system or ship.layer or ship.dock != 0 or ship.hp <= 0 or ship.battle.retired:
			continue
		var aim := Vector2(ship.pos)-Vector2(vessel.pos)
		if aim.length_squared() > reach * reach:
			continue
		if not world.enemy(vessel,ship):
			continue
		var score := aim.length() * (1.4 - 0.55*aim.normalized().dot(direction))
		if score < best:
			best = score
			chosen = ship
	return chosen

static func heading_input(vessel: Dictionary, controls: Vector2, spec: Dictionary) -> Vector2:
	match spec.get("drive",""):
		"forward": return Vector2.from_angle(vessel.heading)
		"reverse": return -Vector2.from_angle(vessel.heading)
		"directed": return vessel.battle.system_axis
	return controls

static func eligible(vessel: Dictionary, weapon: Dictionary, slot: int, spec: Dictionary) -> bool:
	match spec.get("effect",""):
		"lidar": return slot >= 0 and Hulls.slot_spec(vessel.kind,slot).type == "固定" and not weapon.get("beam",false)
		"fragments":
			return slot >= 0 and not weapon.get("pd",false) and spec.slots.get(Hulls.slot_spec(vessel.kind,slot).reference,"") == vessel.fit.weapons[slot]
		"energy": return weapon.get("family","") == "energy"
		"ballistic": return weapon.get("family","") == "ballistic"
	return false

static func weapon_mod(vessel: Dictionary,weapon: Dictionary,key: String,slot: int = -1) -> float:
	var spec := active(vessel)
	if spec.is_empty():
		return float(profile(vessel).get("passive_range",1.0)) if key == "range" else 1.0
	return float(spec.get(key,1.0)) if eligible(vessel,weapon,slot,spec) else 1.0

static func allowed(vessel: Dictionary,weapon: Dictionary,slot: int) -> bool:
	var spec := active(vessel)
	return not spec.get("block_fire",false) and (spec.get("effect","") != "lidar" or eligible(vessel,weapon,slot,spec))

static func refill_magazines(vessel: Dictionary, fraction: float, missiles_only: bool, reset: bool = false) -> void:
	for i in vessel.fit.weapons.size():
		var weapon: Dictionary = Hulls.WEAPONS.get(vessel.fit.weapons[i],{})
		if missiles_only and not weapon.get("missile",false):
			continue
		if reset:
			vessel.battle.cooldowns[i] = 0.0
		var capacity := float(weapon.get("ammo",0))
		vessel.battle.magazines[i] = minf(capacity,float(vessel.battle.magazines[i])+capacity*fraction)

static func activate(world,vessel: Dictionary,direction: Vector2,spec: Dictionary,combat,aim: Vector2,preferred: int) -> bool:
	var state: Dictionary = vessel.battle
	var axis := direction.normalized() if not direction.is_zero_approx() else Vector2.from_angle(vessel.heading)
	var forward := Vector2.from_angle(vessel.heading)
	var enemy := {}
	var reach := float(spec.get("reach",0.0))
	if spec.effect in ["mine","overload","entropy","gaze","termination","attractor","lash","fragments"]:
		enemy = target(world,vessel,axis,reach if reach>0 else state.longest_weapon*2.0,preferred,spec.effect=="lash")
		if enemy.is_empty() and spec.effect in ["overload","entropy","termination","lash"]:
			return false
	if spec.effect=="attractor" and preferred==0 and aim.is_finite():
		enemy={}
		for candidate in world.ships.values():
			if combat.available(candidate,vessel.system) and world.enemy(vessel,candidate) and Vector2(candidate.pos).distance_to(vessel.pos)<=reach and Vector2(candidate.pos).distance_to(aim)<=float(combat.Defenses.geometry(candidate.kind).radius)+6:
				enemy=candidate
				break
	var point := Vector2(vessel.pos) + axis * reach
	if aim.is_finite():
		point = Vector2(vessel.pos) + (aim-Vector2(vessel.pos)).limit_length(reach)
	elif not enemy.is_empty():
		point = enemy.pos
	match spec.effect:
		"blink":
			var displacement: Vector2 = state.motion
			if spec.blink == "momentum" and not displacement.is_zero_approx():
				point = Vector2(vessel.pos)+displacement.normalized()*reach
			elif spec.blink == "momentum":
				point = Vector2(vessel.pos)+axis*reach
			vessel.pos = point
			state.contact_blink = true
			state.shield = false
		"impulse":
			state.motion += forward * float(spec.impulse)
			var epicenter := Vector2(vessel.pos)-forward*float(spec.reach)*0.65
			world.combat_event("rupture",epicenter,vessel.system,-forward)
			for other in world.ships.values():
				if combat.available(other,vessel.system) and world.enemy(vessel,other) and Vector2(other.pos).distance_to(epicenter) < spec.reach:
					var point_hit := Vector2(other.pos)+forward*float(combat.Defenses.geometry(other.kind).radius)
					Ordnance.direct_hit(world,vessel,other,spec.blast,0,1,point_hit,-forward,combat)
		"rack_reset": refill_magazines(vessel,0,true,true)
		"forge": refill_magazines(vessel,spec.reload,true)
		"recall":
			for wing in state.fighter_wings:
				wing.pos = vessel.pos
				wing.returning = true
				wing.sortie = false
				wing.cool = minf(wing.cool,0.4)
				for unit in wing.get("craft",[]):
					unit.pos = vessel.pos
					unit.returning = true
					unit.sortie = false
					unit.cool = minf(unit.cool,0.4)
					unit.launch_in = 0.45 + int(unit.index)*0.12
					unit.erase("run")
		"flare","flak","screen":
			for i in int(spec.count):
				var vector := forward.rotated(TAU*i/spec.count)
				var kind := "flare" if spec.effect=="flare" else ("canister" if spec.effect=="flak" else "screen")
				if kind == "screen": vector = forward.rotated((i-(spec.count-1)*0.5)*0.3)
				var release := Vector2(vessel.pos)+vector*(float(combat.Defenses.geometry(vessel.kind).radius)+4.0)
				var shot := Ordnance.spawn(world,vessel,kind,release,vector*(68.0 if kind!="flare" else 35.0),2.8 if kind!="canister" else 1.0,spec.get("power",0))
				shot.reach = reach
				shot.decoy = spec.get("decoy","")
				if kind=="flare": shot.missile = true
		"overload": overload(enemy,spec.lock)
		"lash":
			if world.enemy(vessel,enemy):
				if combat.phased(enemy): overload(enemy,spec.lock)
				Ordnance.direct_hit(world,vessel,enemy,4,spec.power,2,enemy.pos,axis,combat)
			else:
				var ally := profile(enemy)
				if "threat_hullmod" not in Hulls.MODELS[enemy.kind].builtins or ally.effect not in ["incursion","extract","fragments","blink"]: return false
				if ally.effect in ["incursion","extract","fragments","blink"] and "threat_hullmod" in Hulls.MODELS[enemy.kind].builtins:
					enemy.battle.system_charges = ally.get("charges",1)
					enemy.battle.system_cd = 0.0
					if ally.effect != "blink" and enemy.battle.system_time<=0: combat.system(world,enemy,axis)
			world.combat_event("emp",enemy.pos,vessel.system,axis)
			world.combat_event("beam",vessel.pos,vessel.system,Vector2(enemy.pos)-Vector2(vessel.pos))
		"entropy":
			enemy.battle.vulnerability_source = vessel.id
			enemy.battle.vulnerability_time = spec.duration
			enemy.battle.vulnerability = spec.power
		"mine":
			var mine := Ordnance.spawn(world,vessel,"mine",point,Vector2.ZERO,8.0,spec.power)
			mine.merge({"mine":true,"arming":0.65,"track_speed":spec.track_speed,"fuse":spec.fuse,"target":enemy.get("id",0)},true)
		"termination":
			for wing in state.fighter_wings:
				if "terminator" in str(wing.id) and wing.hp > 0:
					wing.hp = maxf(0,wing.hp-float(wing.max_hp)/maxf(1,wing.count))
					var drone := Ordnance.spawn(world,vessel,"terminator",wing.pos,(Vector2(enemy.pos)-Vector2(wing.pos)).normalized()*280,2,spec.power)
					drone.missile = true
					drone.target = enemy.id
					state.system_axis = axis
					return true
			return false
		"construction":
			var children := 0
			for child in world.ships.values():
				if child.battle.get("constructor_id",0)==vessel.id and child.hp>0: children+=1
			for shot in world.projectiles:
				if shot.get("ordnance","")=="constructor" and shot.ship==vessel.id: children+=1
			if children>=spec.max_children: return false
			var swarm := Ordnance.spawn(world,vessel,"constructor",vessel.pos,forward*32,spec.build_time,0)
			var allied_dp:=0
			for ally in world.ships.values():
				if ally.id!=vessel.id and ally.flag==vessel.flag and combat.available(ally,vessel.system):
					allied_dp+=int(Hulls.MODELS[ally.kind].dp)
			var choice:=mini(int(allied_dp/12),spec.units.size()-1)
			swarm.unit=spec.units[choice]
		"attractor":
			state.attractor_point = point
	state.system_axis = axis
	state.system_target = enemy.get("id",0)
	state.system_pulse = 0.0
	if spec.get("block_shield",false):
		state.shield=false
		state.phase_active=false
	return true

static func overload(enemy: Dictionary,duration: float) -> void:
	enemy.battle.overload = maxf(enemy.battle.overload,duration)
	enemy.battle.vent = false
	enemy.battle.phase_active = false
	enemy.battle.shield = false
	enemy.battle.system_time = 0.0
	enemy.battle.shield_arc_live = 0.0

static func pulses(world,vessel: Dictionary,spec: Dictionary,dt: float,combat) -> void:
	var s: Dictionary = vessel.battle
	s.system_pulse = s.get("system_pulse",0.0)-dt
	if s.system_pulse > 0: return
	s.system_pulse = spec.interval
	s.system_pulse_number=s.get("system_pulse_number",0)+1
	var forward := Vector2.from_angle(vessel.heading)
	match spec.effect:
		"emp":
			for ship in world.ships.values():
				if not combat.available(ship,vessel.system) or not world.enemy(vessel,ship): continue
				if Vector2(ship.pos).distance_squared_to(vessel.pos)<spec.reach*spec.reach:
					var point: Vector2 = ship.pos-(Vector2(ship.pos)-Vector2(vessel.pos)).normalized()*float(combat.Defenses.geometry(ship.kind).radius)
					if not combat.Defenses.covered(ship,point):
						var engines: Array=Hulls.MODELS[ship.kind].engine_slots
						var slot_count: int=ship.fit.weapons.size()
						var candidate := int(s.system_pulse_number-1)%maxi(1,slot_count+engines.size())
						if candidate<slot_count:
							point=combat.slot_position(ship,candidate)
						elif not engines.is_empty():
							point=Vector2(ship.pos)+Vector2(engines[candidate-slot_count]).rotated(ship.heading)
					Ordnance.direct_hit(world,vessel,ship,2,spec.power,2,point,forward,combat)
				for wing in ship.battle.get("fighter_wings",[]):
					for unit in wing.get("craft",[wing]):
						if unit.sortie and Vector2(unit.pos).distance_to(vessel.pos)<=spec.reach: unit.hp-=spec.power
			for missile in world.projectiles:
				if missile.missile and world.enemy(vessel,missile) and missile.system==vessel.system and Vector2(missile.pos).distance_to(vessel.pos)<=spec.reach: missile.hp-=spec.power
		"gaze":
			var shot := Ordnance.payload(vessel,"gaze",vessel.pos,forward,0.0,spec.power)
			var end := Vector2(vessel.pos)+forward*float(spec.reach)
			var contact: Dictionary = combat.trace(world,shot,vessel.pos,end)
			if not contact.is_empty():
				end = contact.point
				shot.emp=spec.power*0.4
				combat.impact(world,shot,contact,true)
			world.combat_event("beam",vessel.pos,vessel.system,end-Vector2(vessel.pos))

static func lash_recipient(world,source: Dictionary,foe: Dictionary) -> Dictionary:
	var spec := profile(source)
	for other in world.ships.values():
		if other.id==source.id or other.hp<=0 or other.dock!=0 or other.layer or other.battle.retired or other.system!=source.system: continue
		if Vector2(other.pos).distance_squared_to(source.pos)>spec.reach*spec.reach or world.enemy(source,other): continue
		var p:=profile(other)
		if "threat_hullmod" in Hulls.MODELS[other.kind].builtins and p.effect in ["blink","incursion","extract","fragments"] and other.battle.get("system_charges",1.0)<1.0 and other.battle.system_time<=0:
			return other
	return foe

static func ai_use(vessel: Dictionary,foe: Dictionary,distance: float,imminent: bool,approaching: bool) -> bool:
	var p := profile(vessel)
	var s: Dictionary = vessel.battle
	var foe_phased: bool = foe.battle.get("phase_active", false) or (foe.battle.system_time > 0.0 and foe.battle.get("active_profile", INACTIVE).get("effect", "") == "blink")
	match p.effect:
		"none": return false
		"flare","flak","fortress","damper","screen": return imminent
		"extract": return imminent or vessel.hp < Hulls.MODELS[vessel.kind].hp*.65
		"thrust","blink","impulse": return (approaching and distance>155) or imminent or (s.get("ai", "") == "降盾散热" and distance < 190.0)
		"entropy","overload": return not foe_phased and distance<=p.reach and foe.battle.overload<=0
		"recall":
			for wing in s.fighter_wings:
				if wing.hp>0 and (wing.returning or wing.hp<wing.max_hp*.5): return true
			return false
		"target_feed","reserve": return not s.fighter_wings.is_empty() and distance<450
		"rack_reset","forge":
			for i in vessel.fit.weapons.size():
				var gun: Dictionary=Hulls.WEAPONS.get(vessel.fit.weapons[i],{})
				if gun.get("missile",false) and (s.cooldowns[i]>.4 if p.effect=="rack_reset" else gun.get("ammo",0)>0 and s.magazines[i]<gun.ammo*.6): return true
			return false
		"gaze": return not foe_phased and absf(angle_difference(vessel.heading,(Vector2(foe.pos)-Vector2(vessel.pos)).angle()))<deg_to_rad(p.arc) and distance<=p.reach
	return distance<=float(p.get("reach",s.shortest_weapon))

