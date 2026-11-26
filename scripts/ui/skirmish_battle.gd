extends "res://scripts/ui/title_battle.gd"

const Hulls = preload("res://hull_catalog.gd")
const StationArt = preload("res://scripts/ui/station_art.gd")
const Geometry = preload("res://scripts/models/station_geometry.gd")
const Weapons = preload("res://art/weapon_mounts.gd")
const AirGroups = preload("res://scripts/battle/wing_visuals.gd")
const ACTIVE_PER_SIDE := 20

signal standings_changed(blue: Dictionary, red: Dictionary)
signal finished(winner: int)
signal camera_changed(mode: int, ship: int, zoom: float)
enum View { ALL, BLUE, RED, FIGHTERS, FREE, SHIP }

var orders: Array = [[],[]]
var stations: Array = [[],[]]
var sides: Array[int] = []
var air_fits: Array[String] = []
var waitlist: Array = [[],[]]
var module_layer := Node2D.new()
var air_layer := AirGroups.new()
var time_scale := 1
var paused := false
var ended := false
var camera_mode := 0
var tracked_id := 0
var followed_craft := {}
var view_center := Vector2.ZERO
var zoom_override := 0.0
var drag_start := Vector2.ZERO
var drag_last := Vector2.ZERO
var pointer_down := false
var dragged := false
var fingers := {}
var pinch_used := false
var last_raw_pinch_ms := -1000
var stats_clock := 0.0

func _ready() -> void:
	remember_lineup = false
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP
	space.add_child(module_layer)
	space.move_child(module_layer,0)
	module_layer.draw.connect(draw_stations)
	space.add_child(air_layer)
	frame_battle()

func start_round() -> void:
	clear_round()
	sides.clear()
	air_fits.clear()
	waitlist = [[],[]]
	world.ports.clear()
	world.systems[0].ports.clear()
	ended = false
	paused = false
	# A retry creates a fresh instance with identical deployment and random streams.
	rng.seed = 718
	world.rng.seed = 718
	for team in 2:
		for entry: Dictionary in orders[team]:
			var kind := Hulls.kind_for_id(entry.hull)
			if kind < 0: continue
			for ship in int(entry.count):
				waitlist[team].append(lineup.size())
				lineup.append(kind)
				sides.append(team)
				air_fits.append(str(entry.get("wing","")))
	var active := mini(ACTIVE_PER_SIDE,maxi(waitlist[0].size(),waitlist[1].size()))
	world.arena_extent = Vector2(maxf(800,920+active*24),maxf(500,425+active*25))
	if not stations[0].is_empty() or not stations[1].is_empty():
		world.arena_extent = world.arena_extent.max(Vector2(1700,880))
	if lineup.is_empty():
		world.arena_extent = Vector2(1320,780)
	for team in 2:
		if not stations[team].is_empty():
			deploy_station(team)
	deploy_reserves()

func flag_for(team: int) -> int:
	return world.NEUTRAL if team == 0 else world.RAIDERS

func blue_slot(slot: int) -> bool:
	return sides[slot] == 0

func deploy_station(team: int) -> void:
	var inward := 1.0 if team == 0 else -1.0
	var id := world.uid()
	var kinds: Array = stations[team].duplicate()
	var site := {"id":id,"name":"蓝方空间站" if team==0 else "红方空间站","system":0,"flag":flag_for(team),
		"pos":Vector2(-inward*world.arena_extent.x*0.60,0),"berth_heading":0.0 if team==0 else PI,
		"modules":kinds,"module":kinds.front(),"build":0,"expansion":0,"owner":0,"firm":0,
		"assault":{"actor":-999,"ship":-999,"nodes":[],"disabled":[]}}
	if lineup.is_empty():
		site.pos = Geometry.berth_for_core(site,Vector2(-inward*610,0),site.berth_heading)
	world.ports[id] = site
	world.systems[0].ports.append(id)
	world.StationAssault.deploy_modules(world,site,Vector2.ZERO)

func deploy_reserves() -> void:
	for side in 2:
		var queued: Array = waitlist[side]
		if queued.is_empty(): continue
		var fielded := 0
		for unit: Dictionary in world.ships.values():
			if unit.flag == flag_for(side) and not unit.has("defense_port"):
				fielded += 1
		while fielded < ACTIVE_PER_SIDE and not queued.is_empty():
			var slot := int(queued.front())
			var sign_x := -1.0 if side==0 else 1.0
			var index := fielded
			var columns := ceili(mini(fielded+queued.size(),ACTIVE_PER_SIDE)/5.0)
			var rows := mini(5,fielded+queued.size())
			var x := sign_x * (world.arena_extent.x*0.34 + floori(index/5.0)*minf(175,world.arena_extent.x*0.35/maxi(1,columns)))
			var y := ((index%5) - (rows-1)*0.5)*minf(210,world.arena_extent.y*1.5/maxi(1,rows))
			if not deploy(slot,Vector2(x,y)).is_finite():
				break
			queued.pop_front()
			fielded += 1

func configure_ship(ship: Dictionary, slot: int) -> void:
	if not air_fits[slot].is_empty():
		for bay in range(Hulls.MODELS[ship.kind].builtin_wings.size(),ship.fit.wings.size()):
			ship.fit.wings[bay] = air_fits[slot]

func replace_lost(_lost: Dictionary) -> void:
	# Only ships explicitly placed in the two rosters can reinforce a skirmish.
	pass

func fight(ship: Dictionary, foe: Dictionary, delta: float) -> void:
	if foe.is_empty():
		ship.locked = false
		ship.battle.target_id = 0
		Battle.shield(ship,false)
		if not ship.has("defense_port"):
			ship.battle.motion = Vector2(ship.battle.motion).move_toward(Vector2.ZERO,50.0*delta)
			ship.pos += Vector2(ship.battle.motion)*delta
	elif ship.has("defense_port"):
		world.StationAssault.fire(world,ship,foe,delta)
	else:
		super.fight(ship,foe,delta)
	if world.ships.has(ship.id):
		Battle.point_defense(world,ship)
		if not ship.fit.wings.is_empty():
			Battle.Wings.advance(world,ship,foe,delta,Battle)

func update_auxiliaries() -> void:
	var flights: Array = []
	for ship: Dictionary in world.ships.values():
		var tone := BLUE if ship.flag == world.NEUTRAL else AMBER
		if ship.has("defense_port"):
			var shape := Battle.Defenses.body_geometry(ship)
			tone.a = 0.42+0.58*float(ship.battle.shield_flash)
			fields.add_shield(ship,Battle.Defenses.shield_world_center(ship),shape.shield_radius,tone)
		elif not visuals.has(ship.id):
			var visual := ShipVisual.new()
			space.add_child(visual)
			visuals[ship.id] = visual
			visual.sync(ship,tone)
		for wing in ship.battle.get("fighter_wings",[]):
			if wing.sortie and wing.hp > 0:
				flights.append([wing,ship.heading,tone])
	air_layer.sync(flights)
	module_layer.queue_redraw()

func draw_stations() -> void:
	for site: Dictionary in world.ports.values():
		var geom := Geometry.layout(site)
		var tint := BLUE if site.flag == world.NEUTRAL else AMBER
		StationArt.draw_layout(module_layer,geom,geom.center,geom.angle,1.0,tint)
		for sid in site.assault.nodes:
			var gun: Dictionary = world.ships.get(sid,{})
			if not gun.is_empty():
				Weapons.draw_station_mounts(module_layer,gun,Transform2D(gun.heading,gun.pos))

func tally(team: int) -> Dictionary:
	var result := {"ships":0,"reserve":waitlist[team].size(),"modules":0,"aircraft":0}
	for ship: Dictionary in world.ships.values():
		if ship.flag != flag_for(team): continue
		if ship.has("defense_port"): result.modules += 1
		else: result.ships += 1
		for wing in ship.battle.get("fighter_wings",[]):
			if wing.sortie: result.aircraft += int(wing.get("airborne",wing.get("count_live",0)))
	return result

func stations_can_reach() -> bool:
	for gun in world.ships.values():
		var reach := maxf(float(gun.battle.get("longest_weapon",0.0)),Battle.Wings.operation_range(gun))
		for other in world.ships.values():
			if gun.flag != other.flag and Vector2(gun.pos).distance_to(other.pos)<=reach:
				return true
	return false

func overview_bounds() -> Rect2:
	var bounds := Rect2()
	var valid := false
	for unit: Dictionary in world.ships.values():
		var radius := float(Battle.Defenses.body_geometry(unit).reach)
		var area := Rect2(Vector2(unit.pos)-Vector2.ONE*radius,Vector2.ONE*radius*2.0)
		bounds = bounds.merge(area) if valid else area
		valid = true
	for site: Dictionary in world.ports.values():
		var area: Rect2 = Geometry.layout(site).bounds
		bounds = bounds.merge(area) if valid else area
		valid = true
	return bounds.grow(90.0) if valid else Rect2(-world.arena_extent,world.arena_extent*2.0)

func followed_unit() -> Dictionary:
	if camera_mode==View.SHIP:
		return world.ships.get(tracked_id,{})
	var candidate := {}
	var score := -1
	for unit: Dictionary in world.ships.values():
		if camera_mode in [View.BLUE,View.RED] and unit.flag==flag_for(camera_mode-1):
			return unit
		if camera_mode==View.FIGHTERS:
			for wing in unit.battle.get("fighter_wings",[]):
				if wing.sortie:
					for craft in wing.get("craft",[wing]):
						if craft.hp<=0 or not craft.sortie: continue
						var rank := 0 if craft.returning else (2 if craft.get("run",{}).get("phase","")=="strafe" else 1)
						if is_same(craft,followed_craft) and not craft.returning: return craft
						if rank>score:
							candidate=craft
							score=rank
	followed_craft=candidate
	return candidate

func set_view(mode: int, id: int = 0) -> void:
	if mode==View.SHIP and not world.ships.has(id): return
	var keep_scale := camera_mode==View.SHIP and mode==View.SHIP
	tracked_id = id if mode==View.SHIP else 0
	camera_mode = mode
	if not keep_scale: zoom_override=space.scale.x if mode==View.FREE else 0.0
	frame_battle()
	camera_changed.emit(camera_mode,tracked_id,space.scale.x)

func change_zoom(factor: float, anchor: Vector2 = Vector2.INF) -> void:
	if factor<=0 or size.x<=0: return
	var before := space.transform.affine_inverse() * anchor if anchor.is_finite() else view_center
	if camera_mode==View.ALL: camera_mode=View.FREE
	zoom_override=clampf(space.scale.x*factor,0.12,8.0)
	if camera_mode==View.FREE and anchor.is_finite():
		view_center=before-(anchor-size*0.5)/zoom_override
	frame_battle()
	camera_changed.emit(camera_mode,tracked_id,space.scale.x)

func frame_battle() -> void:
	if camera_mode==View.SHIP and not world.ships.has(tracked_id):
		camera_mode=View.FREE
		tracked_id=0
		zoom_override=space.scale.x
		camera_changed.emit(camera_mode,0,zoom_override)
	if not is_inside_tree() or size.x<=0 or size.y<=0: return
	var scale_value:=space.scale.x
	if camera_mode==View.ALL:
		var bounds:=overview_bounds()
		view_center=bounds.get_center()
		scale_value=clampf(minf(size.x/bounds.size.x,size.y/bounds.size.y),0.12,1.8)
	elif camera_mode!=View.FREE:
		var unit:=followed_unit()
		if not unit.is_empty():
			view_center=unit.pos
			var diameter:=float(Battle.Defenses.body_geometry(unit).radius)*2.0 if unit.has("kind") else 22.0
			scale_value=clampf(minf(size.x,size.y)*0.44/maxf(1,diameter),1.45,5.0)
	if zoom_override>0: scale_value=zoom_override
	space.scale=Vector2.ONE*scale_value
	space.position=size*0.5-view_center*scale_value
	planet.size = Vector2.ONE*size.y*0.72
	planet.position = Vector2(size.x*0.75,-size.y*0.3)
	queue_redraw()

func draw_fire() -> void:
	super.draw_fire()
	if camera_mode!=View.SHIP or not world.ships.has(tracked_id): return
	var ship: Dictionary=world.ships[tracked_id]
	var radius: float=Battle.Defenses.body_geometry(ship).radius+6.0/space.scale.x
	for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
		var p:Vector2=Vector2(ship.pos)+corner*radius
		effects.draw_line(p,p-Vector2(corner.x,0)*8.0/space.scale.x,Color("f4d49a"),1.5/space.scale.x,true)
		effects.draw_line(p,p-Vector2(0,corner.y)*8.0/space.scale.x,Color("f4d49a"),1.5/space.scale.x,true)

func pick_ship(point: Vector2) -> int:
	var best := 0
	var distance := INF
	for ship: Dictionary in world.ships.values():
		var gap := point.distance_to(space.transform*Vector2(ship.pos))
		if gap < distance and gap <= maxf(18.0,Battle.Defenses.body_geometry(ship).reach*space.scale.x):
			distance=gap
			best=ship.id
	return best

func pan_view(motion: Vector2) -> void:
	if camera_mode in [View.ALL,View.FREE]:
		if camera_mode==View.ALL: set_view(View.FREE)
		view_center-=motion/space.scale.x
		frame_battle()

func _input(input_event: InputEvent) -> void:
	if not is_visible_in_tree() or not (input_event is InputEventScreenTouch or input_event is InputEventScreenDrag or input_event is InputEventMagnifyGesture):
		return
	var event := make_input_local(input_event)
	if event is InputEventMagnifyGesture:
		if Rect2(Vector2.ZERO,size).has_point(event.position):
			if Time.get_ticks_msec()-last_raw_pinch_ms>45:
				change_zoom(event.factor,event.position)
			get_viewport().set_input_as_handled()
		return
	if not fingers.has(event.index) and not (event is InputEventScreenTouch and event.pressed and Rect2(Vector2.ZERO,size).has_point(event.position)):
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			fingers[event.index]=event.position
			if fingers.size()==1:
				drag_start=event.position
				dragged=false
				pinch_used=false
			else: pinch_used=true
		else:
			if fingers.has(event.index) and fingers.size()==1 and not dragged and not pinch_used:
				var picked:=pick_ship(event.position)
				if picked: set_view(View.SHIP,picked)
			fingers.erase(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and fingers.has(event.index):
		var previous: Vector2=fingers[event.index]
		fingers[event.index]=event.position
		if fingers.size()==2:
			var ids:=fingers.keys()
			var other: Vector2=fingers[ids[1] if ids[0]==event.index else ids[0]]
			var span:=previous.distance_to(other)
			if span>2:
				var ratio: float=event.position.distance_to(other)/span
				if absf(ratio-1.0)>0.001:
					last_raw_pinch_ms=Time.get_ticks_msec()
					change_zoom(ratio,(event.position+other)*0.5)
		elif fingers.size()==1 and not pinch_used:
			dragged=dragged or drag_start.distance_to(event.position)>7
			if dragged: pan_view(event.position-previous)
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device==InputEvent.DEVICE_ID_EMULATION:
		accept_event()
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			change_zoom(1.22 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.22,event.position)
		elif event.button_index==MOUSE_BUTTON_LEFT:
			pointer_down=event.pressed
			if event.pressed:
				drag_start=event.position
				drag_last=event.position
				dragged=false
			elif not dragged:
				var picked:=pick_ship(event.position)
				if picked: set_view(View.SHIP,picked)
		accept_event()
	elif event is InputEventMouseMotion and pointer_down:
		dragged=dragged or drag_start.distance_to(event.position)>7
		if dragged: pan_view(event.position-drag_last)
		drag_last=event.position
		accept_event()

func _physics_process(delta: float) -> void:
	if paused: return
	for tick in time_scale:
		super._physics_process(delta)
		var blue := tally(0)
		var red := tally(1)
		var a: int = blue.ships+blue.modules+blue.reserve
		var b: int = red.ships+red.modules+red.reserve
		stats_clock += delta
		if stats_clock>=0.25 or (not ended and (a==0 or b==0)):
			stats_clock = 0.0
			standings_changed.emit(blue,red)
			if not ended and a>0 and b>0 and blue.ships+red.ships+blue.reserve+red.reserve+blue.aircraft+red.aircraft==0 and world.projectiles.is_empty() and not stations_can_reach():
				ended = true
				finished.emit(-1)
		if not ended and (a==0 or b==0):
			ended = true
			finished.emit(-1 if a==0 and b==0 else (0 if b==0 else 1))
	frame_battle()
