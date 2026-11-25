extends Control

const World = preload("res://world.gd")
const Battle = preload("res://combat.gd")
const Flight = preload("res://flight.gd")
const ShipVisual = preload("res://scripts/battle/ship_visual.gd")
const CombatFields = preload("res://scripts/battle/combat_fields.gd")
const StellarArt = preload("res://scripts/ui/stellar_art.gd")
const HISTORY := "user://opening_fleet.cfg"
const ARENA_HALF_SIZE := Vector2(560,355)
const TURN_DISTANCE := 64.0

# Exhibition ships have no owners, crew estates or campaign consequences.
class Exhibition extends World:
	func movement_limit(kind: int) -> Vector2:
		var reach := float(Battle.Defenses.geometry(kind).reach)
		return (ARENA_HALF_SIZE - Vector2.ONE*reach).max(Vector2.ZERO)

	func ship(hull_type: int, owner: int, captain: int, flag: int, system: int, pos: Vector2, at_port: int = 0) -> int:
		var limit := movement_limit(hull_type)
		return super.ship(hull_type,owner,captain,flag,system,pos.clamp(-limit,limit),at_port)

	func confine(vessel: Dictionary) -> void:
		var limit := movement_limit(vessel.kind)
		var pos := Vector2(vessel.pos).clamp(-limit,limit)
		var velocity: Vector2 = vessel.battle.motion
		for axis in 2:
			if absf(pos[axis]) >= limit[axis] and pos[axis]*velocity[axis] > 0.0:
				velocity[axis] = 0.0
		vessel.pos = pos
		vessel.battle.motion = velocity

	func destruction(ship_id: int, _killer: int = 0) -> void:
		if ships.has(ship_id):
			var vessel: Dictionary = ships[ship_id]
			var id := leave_ship_wreck(vessel,BLUE if vessel.flag == NEUTRAL else AMBER)
			# The exhibition keeps the visible remains on its battle backdrop.
			wrecks.erase(id)
			ships.erase(ship_id)

# Redirect thrust near a wall while the pilot keeps aiming its weapons.
class ExhibitionFlight extends Flight:
	func maneuver(vessel: Dictionary, direction: Vector2, delta: float, heading: float) -> void:
		var limit: Vector2 = game.world.movement_limit(vessel.kind)
		var pos: Vector2 = vessel.pos
		for axis in 2:
			var clearance := limit[axis]-absf(pos[axis])
			var inward := 1.0-smoothstep(0.0,TURN_DISTANCE,clearance)
			direction[axis] = lerpf(direction[axis],-signf(pos[axis]),inward)
		super.maneuver(vessel,direction,delta,heading)
		game.world.confine(vessel)

var world := Exhibition.new()
var flight := ExhibitionFlight.new()
var space := Node2D.new()
var effects := Node2D.new()
var remains := preload("res://scripts/ui/title_wrecks.gd").new()
var fields := CombatFields.new()
var planet := ColorRect.new()
var visuals := {}
var flashes: Array = []
var event_cursor := 0
var elapsed := 0.0
var round_number := 0
var sky: Texture2D
var rng := RandomNumberGenerator.new()
var previous_hulls: Array = []
var lineup: Array[int] = []
var remember_lineup := true
var reserves: Array[Dictionary] = []
var hull_pools := [[],[],[],[]]
const BLUE := Color("72cde0")
const AMBER := Color("eea364")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	world.systems.append({"name":"边疆航线","pos":Vector2.ZERO,"ports":[]})
	world.player = -999
	rng.randomize()
	world.rng.randomize()
	if remember_lineup and FileAccess.file_exists(HISTORY):
		var history := ConfigFile.new()
		if history.load(HISTORY) == OK:
			var saved = history.get_value("battle","hulls",[])
			if saved is Array and saved.size() == 6: previous_hulls = saved
	flight.game = self
	var art := StellarArt.new()
	sky = art.sky({"name":"远岚","sky_seed":51226,"starfield":1})
	planet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	planet.material = art.material_for({"pos":Vector2.ZERO,"type":20,"rings":true,"surface_seed":821},false)
	planet.material.set_shader_parameter("hue",Color("ad9379"))
	planet.material.set_shader_parameter("sunward",Vector2(-0.93,-0.57))
	planet.material.set_shader_parameter("tilt",-0.28)
	add_child(planet)
	add_child(space)
	space.add_child(remains)
	remains.setup(ARENA_HALF_SIZE)
	world.ship_wrecked.connect(remains.add_wreck)
	space.add_child(fields.trails)
	space.add_child(fields)
	fields.z_index = 1
	space.add_child(effects)
	effects.z_index = 1
	effects.draw.connect(draw_fire)
	build_hull_pools()
	start_round()
	resized.connect(frame_battle)
	frame_battle()

func build_hull_pools() -> void:
	for kind in world.Hulls.MODELS.size():
		var model: Dictionary = world.Hulls.MODELS[kind]
		if not model.get("market",true): continue
		for weapon in model.combat.stock:
			if not weapon.is_empty() and not world.Hulls.WEAPONS.get(weapon,{}).get("pd",false):
				hull_pools[model.size].append(kind)
				break

func base_hull(kind: int) -> String:
	var model: Dictionary = world.Hulls.MODELS[kind]
	return model.get("reference_base",model.id)

func pick_hull(tonnage: int, excluded: Array) -> int:
	var candidates: Array = hull_pools[tonnage].filter(func(kind): return base_hull(kind) not in excluded)
	if candidates.is_empty(): candidates = hull_pools[tonnage]
	return candidates[rng.randi_range(0,candidates.size()-1)]

func save_lineup() -> void:
	previous_hulls = lineup.map(base_hull)
	if remember_lineup:
		var history := ConfigFile.new()
		history.set_value("battle","hulls",previous_hulls)
		history.save(HISTORY)

func deploy(slot: int, position_in_space: Vector2) -> Vector2:
	var blue := slot < 3
	var kind := lineup[slot]
	var limit := world.movement_limit(kind)
	var at := position_in_space.clamp(-limit,limit)
	for attempt in 41:
		if Flight.HullContacts.fits(world,0,kind,Transform2D((-at).angle(),at)): break
		if attempt == 40: return Vector2.INF
		var column := 0.95-0.22*floori(attempt/8.0)
		at = Vector2((-column if blue else column)*limit.x,lerpf(-0.95,0.95,float(attempt%8)/7)*limit.y)
	var id := world.ship(kind,0,0,world.NEUTRAL if blue else world.RAIDERS,0,at)
	var ship: Dictionary = world.ships[id]
	ship.heading = (-Vector2(ship.pos)).angle()
	ship.locked = true
	ship.demo_slot = slot
	Battle.ensure_state(ship)
	var visual := ShipVisual.new()
	space.add_child(visual)
	visuals[id] = visual
	visual.sync(ship,BLUE if blue else AMBER)
	return at

func deploy_reserves() -> void:
	var changed := false
	for i in range(reserves.size()-1,-1,-1):
		var entry := reserves[i]
		if elapsed < entry.arrival: continue
		var slot: int = entry.slot
		var fallen := lineup[slot]
		var size_class: int = world.Hulls.MODELS[fallen].size
		lineup[slot] = pick_hull(size_class,lineup.map(base_hull))
		var bearing := rng.randf_range(-0.65,0.65)+(PI if slot < 3 else 0.0)
		var at := Vector2.from_angle(bearing)*world.movement_limit(lineup[slot])*0.95
		at = deploy(slot,at)
		if not at.is_finite():
			lineup[slot] = fallen
			entry.arrival = elapsed+0.4
			continue
		reserves.remove_at(i)
		world.combat_event("arrival",at,0,at.direction_to(Vector2.ZERO))
		changed = true
	if changed: save_lineup()

func start_round() -> void:
	for visual: Node in visuals.values(): visual.queue_free()
	visuals.clear()
	world.ships.clear()
	world.projectiles.clear()
	if world.has_meta("battle_screens"): world.remove_meta("battle_screens")
	flashes.clear()
	remains.reset()
	fields.begin(0,0.0)
	fields.finish()
	event_cursor = world.combat_serial
	round_number += 1
	elapsed = 0.0
	reserves.clear()
	lineup.clear()
	var excluded := previous_hulls.duplicate()
	for tonnage: int in [3,rng.randi_range(1,2),0,3,rng.randi_range(1,2),0]:
		var kind := pick_hull(tonnage,excluded)
		lineup.append(kind)
		excluded.append(base_hull(kind))
	save_lineup()
	var angle := rng.randf_range(-0.38,0.38)
	for side in 2:
		for n in 3:
			var axis := 1.0 if side == 0 else -1.0
			var offset := Vector2(axis*(-230.0-n*53),axis*(140.0-n*167))
			offset = offset.rotated(angle)+Vector2(rng.randf_range(-12,12),rng.randf_range(-15,15))
			if not deploy(side*3+n,offset).is_finite():
				reserves.append({"slot":side*3+n,"arrival":elapsed+0.4})
	frame_battle()

func frame_battle() -> void:
	var span := ARENA_HALF_SIZE*2.0
	var scale_factor := minf(minf(size.x*0.65/span.x,size.y*0.87/span.y),1.65)
	space.scale = Vector2.ONE*scale_factor
	space.position = size*Vector2(0.665,0.53)
	var diameter := minf(size.x*0.74,size.y*1.02)
	planet.size = Vector2.ONE*diameter
	planet.position = size*Vector2(0.82,0.12)-planet.size*0.5
	queue_redraw()

func _physics_process(delta: float) -> void:
	elapsed += delta
	remains.advance(delta)
	deploy_reserves()
	var starts := Flight.HullContacts.capture(world,0)
	for ship: Dictionary in world.ships.values():
		if not world.ships.has(ship.id): continue
		var foe := {}
		var nearest := INF
		for candidate: Dictionary in world.ships.values():
			if ship.flag == candidate.flag: continue
			var gap := Vector2(ship.pos).distance_squared_to(candidate.pos)
			if gap < nearest:
				nearest = gap
				foe = candidate
		Battle.tick(ship,delta,world)
		if not foe.is_empty():
			flight._engage_target(ship,foe,delta)
		# A ship system can blink or apply an impulse after the regular maneuver.
		world.confine(ship)
	Flight.HullContacts.resolve(world,0,starts,ARENA_HALF_SIZE)
	Battle.project(world,0,delta)
	fields.begin(visuals.size(),delta)
	for id: int in visuals.keys():
		if world.ships.has(id):
			var ship: Dictionary = world.ships[id]
			visuals[id].sync(ship,BLUE if ship.flag == world.NEUTRAL else AMBER,delta)
			fields.add_vessel(visuals[id])
		else:
			var lost: Dictionary = visuals[id].ship
			reserves.append({"slot":lost.demo_slot,"arrival":elapsed+rng.randf_range(1.4,2.8)})
			visuals[id].queue_free()
			visuals.erase(id)
	fields.finish()
	for i in range(flashes.size()-1,-1,-1):
		flashes[i].age += delta
		if flashes[i].age > 0.42: flashes.remove_at(i)
	for event: Dictionary in world.combat_events:
		if event.serial > event_cursor:
			if event.kind != "ship_breakup": flashes.append({"event":event,"age":0.0})
			event_cursor = event.serial
	effects.queue_redraw()

func _draw() -> void:
	if sky: draw_texture_rect(sky,Rect2(Vector2.ZERO,size),false,Color("929ba9"))

func draw_fire() -> void:
	for shot: Dictionary in world.projectiles:
		var color := BLUE if shot.flag == world.NEUTRAL else AMBER
		var tail := Vector2(shot.pos)-Vector2(shot.vel).normalized()*(15.0 if shot.missile else 9.0)
		effects.draw_line(tail,shot.pos,Color(color,0.36),3.4,true)
		effects.draw_line(tail,shot.pos,color.lightened(0.4),1.2,true)
	for f: Dictionary in flashes:
		var event: Dictionary = f.event
		var pos: Vector2 = event.pos
		var alpha := clampf(1.0-f.age/0.32,0,1)
		match event.kind:
			"arrival":
				effects.draw_arc(pos,maxf(1.0,45.0*alpha),0,TAU,40,Color(0.7,0.95,1,alpha),2.0,true)
				effects.draw_line(pos-Vector2(event.direction)*110.0*alpha,pos,Color(0.64,0.89,1,alpha),3.0,true)
			"beam":
				effects.draw_line(pos,pos+Vector2(event.direction),Color(0.55,0.9,1,alpha*0.75),1.3,true)
			"muzzle","impact","shield","rupture":
				var radius: float = (13.0 if event.kind == "rupture" else 3.6)*event.strength
				var tone := BLUE if event.kind == "shield" else AMBER
				effects.draw_circle(pos,maxf(0.1,radius*alpha),Color(tone,alpha))
				if event.kind != "muzzle": effects.draw_arc(pos,radius*(1+f.age*6),0,TAU,24,Color(tone,alpha*0.78),1.1,true)
