extends RefCounted

const Hulls = preload("res://hull_catalog.gd")

static func payload(vessel: Dictionary,kind: String,pos: Vector2,velocity: Vector2,life: float,damage: float) -> Dictionary:
	return {"ordnance":kind,"pos":pos,"vel":velocity,"speed":velocity.length(),"life":life,"damage":damage,"type":2,"missile":false,
		"target":0,"system":vessel.system,"ship":vessel.id,"flag":vessel.flag,"raid":vessel.raid,"credit":Hulls.operator_id(vessel),"hp":8.0}

static func spawn(world,vessel: Dictionary,kind: String,pos: Vector2,velocity: Vector2,life: float,damage: float) -> Dictionary:
	var shot := payload(vessel,kind,pos,velocity,life,damage)
	world.projectiles.append(shot)
	if kind=="screen":
		var screens: Array=world.get_meta("battle_screens",[])
		screens.append(shot)
		world.set_meta("battle_screens",screens)
	return shot

static func direct_hit(world,source: Dictionary,victim: Dictionary,amount: float,emp: float,damage_type: int,point: Vector2,direction: Vector2,combat) -> void:
	var hit:=payload(source,"system_hit",point,direction,0,amount)
	hit.type=damage_type
	hit.emp=emp
	combat.impact(world,hit,{"ship":victim,"point":point,"shield":combat.Defenses.covered(victim,point)})

static func screen_contact(world,shot: Dictionary,start: Vector2,finish: Vector2,contact: Dictionary) -> Dictionary:
	var screens: Array=world.get_meta("battle_screens")
	var nearest := start.distance_squared_to(contact.point) if not contact.is_empty() else INF
	for i in range(screens.size()-1,-1,-1):
		var screen: Dictionary=screens[i]
		if screen.hp<=0 or screen.life<=0:
			screens.remove_at(i)
			continue
		if screen.system!=shot.system or screen.ship==shot.ship: continue
		var point := Geometry2D.get_closest_point_to_segment(screen.pos,start,finish) if start!=finish else start
		var dist := start.distance_squared_to(point)
		if dist<nearest and point.distance_squared_to(screen.pos)<=24*24 and world.enemy(shot,screen):
			contact={"screen":screen,"point":point}
			nearest=dist
	if screens.is_empty(): world.remove_meta("battle_screens")
	return contact

const MISSILE_CELL := 128.0

static func nearby_missiles(world, frame: Variant, system_id: int, point: Vector2, radius: float, dt: float) -> Array:
	if frame == null:
		return world.projectiles
	if not frame.has("missiles"):
		var missiles := []
		var cells := {}
		var fastest := 0.0
		for shot: Dictionary in world.projectiles:
			if not shot.missile or shot.system != system_id or shot.hp <= 0.0:
				continue
			var cell := Vector2i((Vector2(shot.pos)/MISSILE_CELL).floor())
			if not cells.has(cell):
				cells[cell] = []
			cells[cell].append(missiles.size())
			missiles.append(shot)
			# Entries already advanced by the reverse projectile loop still use their live coordinates.
			fastest = maxf(fastest,maxf(shot.get("speed",0.0),Vector2(shot.get("vel",Vector2.ZERO)).length()))
			if shot.get("decoy","") == "seeker":
				fastest = maxf(fastest,115.0)
		frame.missiles = missiles
		frame.cells = cells
		frame.margin = fastest*dt
	var all_missiles: Array = frame.missiles
	if all_missiles.size() <= 12:
		return all_missiles
	var extent := Vector2.ONE*(radius+float(frame.margin))
	var first := Vector2i(((point-extent)/MISSILE_CELL).floor())
	var last := Vector2i(((point+extent)/MISSILE_CELL).floor())
	if (last.x-first.x+1)*(last.y-first.y+1) > all_missiles.size():
		return all_missiles
	var indices := []
	for x in range(first.x,last.x+1):
		for y in range(first.y,last.y+1):
			var cell := Vector2i(x,y)
			if frame.cells.has(cell):
				indices.append_array(frame.cells[cell])
	# Preserve projectile order for physical intercepts and equal-distance targets.
	indices.sort()
	var nearby := []
	for index in indices:
		nearby.append(all_missiles[index])
	return nearby

static func wing_carriers(world, frame: Variant) -> Variant:
	if frame == null:
		return null
	if frame.get("ship_count",-1) != world.ships.size():
		var carriers := []
		for ship: Dictionary in world.ships.values():
			if not ship.battle.get("fighter_wings",[]).is_empty():
				carriers.append(ship)
		frame.carriers = carriers
		frame.ship_count = world.ships.size()
	return frame.carriers

static func advance(world,shot: Dictionary,dt: float,combat, frame: Variant = null) -> bool:
	var kind: String = shot.ordnance
	if kind not in ["flare","canister","screen","constructor","mote"]: return false
	var travel := minf(dt,shot.life)
	shot.life-=dt
	if kind=="constructor":
		shot.pos+=shot.vel*travel
		if shot.life<=0 and world.ships.has(shot.ship):
			var builder: Dictionary = world.ships[shot.ship]
			var id: int = world.ship(Hulls.kind_for_reference(shot.unit),Hulls.operator_id(builder),0,builder.flag,builder.system,shot.pos)
			var unit: Dictionary = world.ships[id]
			unit.battle.constructor_id=builder.id
			unit.raid=builder.raid
			unit.locked=builder.locked
			if frame != null:
				frame.erase("ship_count")
		return true
	if kind=="mote":
		advance_mote(world,shot,travel,combat,frame,dt)
		return true
	if kind == "flare" and shot.decoy == "pd":
		shot.pos += shot.vel*travel
		return true
	var closest := INF
	var nearest := {}
	var radius := 64.0 if kind == "screen" else (28.0 if kind == "canister" else float(shot.reach))
	for hostile in nearby_missiles(world,frame,shot.system,shot.pos,radius,dt):
		if not hostile.missile or hostile.hp<=0 or hostile.get("life",1.0)<=0 or hostile.system!=shot.system or hostile.ship==shot.ship: continue
		var dist := Vector2(hostile.pos).distance_squared_to(shot.pos)
		if kind=="screen":
			if dist<64*64 and world.enemy(shot,hostile):
				hostile.decoy_point=shot.pos
				hostile.decoy_time=.4
			continue
		if hostile.get("ordnance","")=="flare": continue
		if kind=="canister":
			if dist<=28*28 and world.enemy(shot,hostile):
				hostile.hp-=shot.damage
				shot.life=0.0
				world.combat_event("rupture",shot.pos,shot.system)
			continue
		if dist>shot.reach*shot.reach or not world.enemy(shot,hostile): continue
		hostile.decoy_point=shot.pos
		hostile.decoy_time=.35
		if dist<closest:
			closest=dist
			nearest=hostile
		var end := Vector2(hostile.pos)+Vector2(hostile.get("vel",Vector2.ZERO))*travel
		if dist<=12*12 or (end!=hostile.pos and Geometry2D.get_closest_point_to_segment(shot.pos,hostile.pos,end).distance_squared_to(shot.pos)<=12*12):
			hostile.hp=0.0
			shot.hp=0.0
			break
	if kind=="flare" and shot.decoy=="seeker" and not nearest.is_empty():
		shot.vel=(Vector2(nearest.pos)-Vector2(shot.pos)).normalized()*115
	if kind=="canister":
		var wing: Dictionary = combat.Wings.threat(world,shot,shot.pos,32,wing_carriers(world,frame))
		if not wing.is_empty():
			wing.hp-=shot.damage
			shot.life=0.0
			world.combat_event("rupture",shot.pos,shot.system)
	shot.pos+=shot.vel*travel
	return true

static func advance_mote(world,shot: Dictionary,dt: float,combat,frame: Variant = null,frame_dt: float = 0.0) -> void:
	var dest: Vector2 = shot.anchor
	var entity := {}
	var ship: Dictionary=world.ships.get(shot.target,{})
	if not ship.is_empty() and combat.available(ship,shot.system):
		dest=ship.pos
	else:
		var best := 85.0*85.0
		for missile in nearby_missiles(world,frame,shot.system,shot.pos,85.0,frame_dt):
			if missile.hp<=0 or missile.get("life",1.0)<=0 or not missile.missile or missile.system!=shot.system: continue
			var d:=Vector2(missile.pos).distance_squared_to(shot.pos)
			if d<best and world.enemy(shot,missile):
				best=d
				entity=missile
		if entity.is_empty(): entity=combat.Wings.threat(world,shot,shot.pos,85,wing_carriers(world,frame))
		if not entity.is_empty(): dest=entity.pos
	shot.pos=Vector2(shot.pos).move_toward(dest,175*dt)
	if Vector2(shot.pos).distance_to(dest)<=8.0:
		if not entity.is_empty():
			entity.hp-=shot.damage
			shot.life=0.0
		elif not ship.is_empty() and combat.available(ship,shot.system):
			var direction := (Vector2(ship.pos)-Vector2(shot.pos)).normalized()
			var point := Vector2(ship.pos)-direction*float(combat.Defenses.geometry(ship.kind).radius)
			var payload_hit:=shot.duplicate()
			payload_hit.damage=2.0
			payload_hit.emp=shot.damage
			combat.impact(world,payload_hit,{"ship":ship,"point":point,"shield":combat.Defenses.covered(ship,point)})
			shot.life=0.0

static func mote_field(world,vessel: Dictionary,spec: Dictionary,dt: float) -> void:
	var s: Dictionary=vessel.battle
	s.mote_delay=s.get("mote_delay",0.0)-dt
	if s.mote_delay>0: return
	s.mote_delay=spec.interval
	var live:=0
	var attracting: bool=s.system_time>0 and s.has("attractor_point")
	for shot in world.projectiles:
		if shot.get("ordnance","")=="mote" and shot.ship==vessel.id:
			shot.target=s.system_target if attracting else 0
			shot.anchor=s.attractor_point if attracting else vessel.pos
			live+=1
	if live>=spec.count: return
	var offset:=Vector2.from_angle(live*TAU/spec.count)*22
	var mote:=spawn(world,vessel,"mote",Vector2(vessel.pos)+offset,offset,6.0,spec.power)
	mote.target=s.system_target if attracting else 0
	mote.anchor=s.attractor_point if attracting else Vector2(vessel.pos)+offset

