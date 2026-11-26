extends Control

const Pixels = preload("res://art/pixel_art.gd")
const Hulls = preload("res://hull_catalog.gd")
const Battle = preload("res://combat.gd")
const Celestial = preload("res://celestial.gd")
const StationGeometry = preload("res://scripts/models/station_geometry.gd")
const StationArt = preload("res://scripts/ui/station_art.gd")
const SystemChart = preload("res://scripts/ui/system_chart.gd")
const ShipVisual = preload("res://scripts/battle/ship_visual.gd")
const WeaponArt = preload("res://art/weapon_mounts.gd")
const FleetBatch = preload("res://scripts/battle/fleet_batch.gd")
const CombatFields = preload("res://scripts/battle/combat_fields.gd")
const WreckVisual = preload("res://scripts/battle/wreck_visual.gd")
const HullBatch = preload("res://scripts/battle/hull_batch.gd")
const Ordnance = preload("res://scripts/battle/ordnance_visuals.gd")
const WingVisuals = preload("res://scripts/battle/wing_visuals.gd")

var game
var stellar_art := preload("res://scripts/ui/stellar_art.gd").new()
var sky_layer := Node2D.new()
var body_layer := Node2D.new()
var body_quads: Array[ColorRect] = []
var visible_bodies := 0
var stars: Array = []
var galaxy := false
var chart_mode := false
var chart_selected: Dictionary = {}
var chart_markers: Array = []
var chart_stamp: Array = []
var camera := Vector2.ZERO
var zoom := 1.0
var impulse := 0.0
var motion_offset := Vector2.ZERO
var particles: Array = []
var event_cursor := 0
var event_system := -1
var battlefield := Node2D.new()
var battle_world := Node2D.new()
var hud := Node2D.new()
var visuals: Dictionary = {}
var station_fits: Dictionary = {}
var contacts: Array = []
var visible_wings: Array = []
var air_groups := WingVisuals.new()
var fleet_batch := FleetBatch.new()
var fields := CombatFields.new()
var fields_frame := -1
var visual_sync := 0
var hull_pages: Array = []
var wreck_layer := Node2D.new()
var wreck_views := {}
var burning_wrecks := {}
var crowded := false
var last_physics_frame := -1
var last_combat_step := -1
var last_canvas_size := Vector2.ZERO
var fleet_selection: Array = []
var context_regions: Array = []
var dragging := false
var drag_start := Vector2.ZERO
const GRID := Color("1b3146")
const CYAN := Color("8dd5de")
const GOLD := Color("f0bc79")
const JUMP_COLOR := Color("95deea")
const NO_WINGS := []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky_layer.show_behind_parent = true
	body_layer.show_behind_parent = true
	add_child(sky_layer)
	add_child(body_layer)
	sky_layer.draw.connect(backdrop)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	battlefield.name = "Battlefield"
	add_child(battlefield)
	battle_world.name = "BattleWorld2D"
	battlefield.add_child(battle_world)
	battle_world.add_child(wreck_layer)
	if game != null: game.world.ship_wrecked.connect(on_ship_wrecked)
	battle_world.add_child(fields.trails)
	battle_world.add_child(fleet_batch)
	battle_world.add_child(air_groups)
	battle_world.add_child(fields)
	hud.name = "HudLayer"
	add_child(hud)
	hud.draw.connect(draw_hud)
	visibility_changed.connect(clear_inactive_battle)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3902
	for index in range(390):
		stars.append(Vector3(rng.randf(), rng.randf(), rng.randf()))

func screen(point: Vector2) -> Vector2:
	return size * 0.5 + (point - camera) * zoom + motion_offset

func location(point: Vector2) -> Vector2:
	return (point - size * 0.5 - motion_offset) / zoom + camera

func _process(delta: float) -> void:
	if game == null or not visible or game.world.player == 0:
		return
	var system: int = game.current_system()
	var physical := Engine.get_physics_frames()
	var combat_step: int = game.flight.physics_frame
	var view_changed := size != last_canvas_size or battlefield.visible != (not galaxy and not chart_mode and not tactical_open())
	var events_changed: bool = system != event_system or event_cursor != game.world.combat_serial
	if event_system != system or event_cursor > game.world.combat_serial:
		particles.clear()
		if event_system != -1: clear_wrecks()
		event_system = system
		event_cursor = 0
	if not galaxy:
		var events: Array = game.world.combat_events
		var first := maxi(0, events.size() - (game.world.combat_serial - event_cursor))
		for i in range(first,events.size()):
			var event: Dictionary = events[i]
			event_cursor = event.serial
			if event.system != system:
				continue
			if event.kind == "ship_breakup":
				if event.pos.distance_to(camera) < 240: impulse = maxf(impulse,2.4*event.strength)
				continue
			if particles.size() >= 80:
				particles.pop_front()
			particles.append({"event":event,"age":0.0})
			if event.pos.distance_to(camera) < 240 and event.kind in ["impact","rupture","overload"]:
				impulse = maxf(impulse, 3.0 * event.strength)
	for index in range(particles.size() - 1, -1, -1):
		particles[index].age += delta
		if particles[index].age > (0.9 if particles[index].event.kind == "rupture" else 0.44):
			particles.remove_at(index)
	for id in burning_wrecks.keys():
		var view: WreckVisual = wreck_views[id]
		view.advance(delta if game.speed > 0 else 0.0)
		if view.age >= WreckVisual.COOL_TIME: burning_wrecks.erase(id)
	impulse = move_toward(impulse, 0.0, delta * 31.0)
	motion_offset = Vector2(sin(Time.get_ticks_msec() * 0.09), cos(Time.get_ticks_msec() * 0.073)) * impulse if not galaxy else Vector2.ZERO
	if view_changed or events_changed or physical != last_physics_frame or combat_step != last_combat_step:
		sync_battlefield(system)
		last_physics_frame = physical
		last_combat_step = combat_step
		last_canvas_size = size
	elif battlefield.visible:
		battle_world.transform = Transform2D(0.0, Vector2.ONE * zoom, 0.0, screen(Vector2.ZERO))

func sync_battlefield(system: int) -> void:
	battlefield.visible = not galaxy and not chart_mode and not tactical_open()
	var frame: int = game.flight.physics_frame
	var effect_delta := maxf(0.0, float(frame - fields_frame) / Engine.physics_ticks_per_second) if fields_frame >= 0 else 0.0
	fields_frame = frame
	contacts.clear()
	visible_wings.clear()
	visual_sync += 1
	var local_count := 0
	if battlefield.visible:
		battle_world.transform = Transform2D(0.0, Vector2.ONE * zoom, 0.0, screen(Vector2.ZERO))
		var world = game.world
		var lead: Dictionary = game.viewed_ship()
		var lead_id: int = lead.get("id",0)
		var flag_colors := {}
		var local_ships: Array = []
		var station_shields: Array[Dictionary] = []
		var bounds := Rect2(location(Vector2.ZERO), size / zoom)
		sync_wrecks(system,bounds)
		var wing_bounds := bounds.grow(55.0)
		for ship in world.ships.values():
			if not Battle.available(ship, system):
				continue
			var detected: bool = ship.has("defense_port") or lead.is_empty() or game.flight.visible_contact(lead,ship)
			for wing in ship.battle.get("fighter_wings",NO_WINGS):
				if not wing.sortie or wing.hp <= 0.0:
					continue
				if not wing_bounds.has_point(wing.pos) and not wing.get("craft",[]).any(func(unit): return unit.sortie and wing_bounds.has_point(unit.pos)):
					continue
				if detected or Vector2(lead.pos).distance_squared_to(wing.pos) <= pow(game.flight.sensor_reading.strength,2):
					if not flag_colors.has(ship.flag):
						flag_colors[ship.flag] = world.flag_color(ship.flag)
					visible_wings.append([wing,ship.heading,CYAN if ship.id == lead_id else flag_colors[ship.flag],int(ship.get("defense_port",0))])
			if not detected:
				continue
			if ship.has("defense_port"):
				if bounds.grow(Battle.Defenses.body_geometry(ship).reach).has_point(ship.pos):
					station_shields.append(ship)
				continue
			contacts.append(ship)
			var shape := Battle.Defenses.geometry(ship.kind)
			var radius: float = shape.reach
			if not bounds.grow(radius + 24.0).has_point(ship.pos):
				continue
			local_ships.append(ship)
		crowded = local_ships.size() >= 12 or world.projectiles.size() >= 64
		local_count = local_ships.size()
		fields.begin(local_count + station_shields.size(), effect_delta)
		for gun in station_shields:
			var tint := Color("79c6de")
			tint.a = 0.42 + 0.58 * float(gun.battle.shield_flash)
			fields.add_shield(gun,Battle.Defenses.shield_world_center(gun),Battle.Defenses.body_geometry(gun).shield_radius,tint)
		for ship in local_ships:
			var visual: ShipVisual = visuals.get(ship.id)
			if visual == null:
				visual = ShipVisual.new()
				battle_world.add_child(visual)
				battle_world.move_child(fields, -1)
				visuals[ship.id] = visual
			if not flag_colors.has(ship.flag):
				flag_colors[ship.flag] = world.flag_color(ship.flag)
			visual.last_seen = visual_sync
			visual.batched = crowded
			visual.sync(ship, CYAN if ship.id == lead_id else flag_colors[ship.flag], effect_delta)
			if ship.battle.shield or ship.battle.vent or not visual.echo_poses.is_empty():
				fields.add_vessel(visual)
	else:
		fields.begin(0, effect_delta)
	fields.finish()
	air_groups.sync(visible_wings)
	if visuals.size() != local_count:
		for id in visuals.keys():
			var visual: ShipVisual = visuals[id]
			if visual.last_seen != visual_sync:
				battle_world.remove_child(visual)
				visual.queue_free()
				visuals.erase(id)
	fleet_batch.visible = crowded and battlefield.visible
	if fleet_batch.visible:
		for view in visuals.values():
			var added := false
			for page in hull_pages:
				if page.add_vessel(view):
					added = true
					break
			if not added:
				var page := HullBatch.new()
				battle_world.add_child(page)
				battle_world.move_child(page, 1)
				hull_pages.append(page)
				page.add_vessel(view)
		fleet_batch.sync(visuals, game.world.projectiles, particles, system)
	for page in hull_pages:
		page.flush()
	hud.queue_redraw()

func on_ship_wrecked(id: int, record: Dictionary) -> void:
	if not is_visible_in_tree() or galaxy or chart_mode or tactical_open() or game.current_system() != record.system: return
	if not visuals.has(record.source_id): return
	add_wreck(id,record,true)

func add_wreck(id: int, record: Dictionary, burning: bool) -> void:
	var kind := Hulls.kind_for_id(record.hull_id)
	if kind < 0 or wreck_views.has(id): return
	var view := WreckVisual.new()
	view.configure(record,kind,burning)
	wreck_layer.add_child(view)
	wreck_views[id] = view
	if burning: burning_wrecks[id] = true

func sync_wrecks(system: int, bounds: Rect2) -> void:
	var visible_ids := {}
	for id in game.world.wrecks:
		var record: Dictionary = game.world.wrecks[id]
		if record.system != system or not record.has("hull_id"): continue
		var kind := Hulls.kind_for_id(record.hull_id)
		if kind < 0 or not bounds.grow(Battle.Defenses.geometry(kind).reach*1.5).has_point(record.pos): continue
		visible_ids[id] = true
		if not wreck_views.has(id): add_wreck(id,record,false)
	for id in wreck_views.keys():
		if not visible_ids.has(id): remove_wreck(id)

func remove_wreck(id: int) -> void:
	var view: WreckVisual = wreck_views[id]
	wreck_layer.remove_child(view)
	view.queue_free()
	wreck_views.erase(id)
	burning_wrecks.erase(id)

func clear_wrecks() -> void:
	for id in wreck_views.keys(): remove_wreck(id)

func clear_inactive_battle() -> void:
	if is_visible_in_tree():
		return
	dragging = false
	fleet_selection.clear()
	for node in visuals.values():
		battle_world.remove_child(node)
		node.queue_free()
	visuals.clear()
	clear_wrecks()
	fields_frame = -1

func tactical_open() -> bool:
	return game != null and not galaxy and is_instance_valid(game.tactics) and game.tactics.visible

func tactical_scale() -> float:
	return minf(size.x / 2840.0, size.y / 2000.0)

func tactical_screen(point: Vector2) -> Vector2:
	return size * 0.5 + (point - camera) * tactical_scale()

func tactical_input(event: InputEvent) -> bool:
	if not is_visible_in_tree() or not tactical_open() or not event is InputEventMouseButton:
		return false
	var point := get_local_mouse_position()
	if not Rect2(Vector2.ZERO, size).has_point(point):
		dragging = false
		return false
	var world = game.world
	var lead: Dictionary = world.ride()
	if lead.is_empty():
		return false
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			drag_start = point
			dragging = true
		elif dragging:
			var rect := Rect2(drag_start, point-drag_start).abs().grow(7.0)
			dragging = false
			fleet_selection.clear()
			for ship in world.ships.values():
				if game.flight.escort(ship, lead) and Battle.available(ship, lead.system) and rect.has_point(tactical_screen(ship.pos)):
					fleet_selection.append(ship.id)
		return true
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var local := camera + (point - size * 0.5) / tactical_scale()
		var target: int = game.flight.target_at(lead,local,12.0 / tactical_scale(),true)
		if target != 0:
			game.hud.open_ship_menu(target)
		else:
			for id in fleet_selection:
				var ship: Dictionary = world.ships.get(id, {})
				if not ship.is_empty() and game.flight.escort(ship, lead) and Battle.available(ship, lead.system):
					ship.battle.tactical_waypoint = local
		return true
	return false

func draw_tactical_map() -> void:
	var world = game.world
	var lead: Dictionary = world.ride()
	if lead.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("09151f"))
	var extent := size * 0.5 / tactical_scale()
	for x in range(ceili((camera.x-extent.x)/200),floori((camera.x+extent.x)/200)+1):
		var px := tactical_screen(Vector2(x*200,camera.y)).x
		draw_line(Vector2(px,0),Vector2(px,size.y),GRID)
	for y in range(ceili((camera.y-extent.y)/200),floori((camera.y+extent.y)/200)+1):
		var py := tactical_screen(Vector2(camera.x,y*200)).y
		draw_line(Vector2(0,py),Vector2(size.x,py),GRID)
	var system: Dictionary = world.systems[lead.system]
	for port_id: int in system.ports:
		draw_station(world,world.ports[port_id],lead,true)
	if system.has("outlaw_base"):
		draw_outlaw_base(world,system.outlaw_base,lead,true)
	ink(Vector2(16,24), "舰队战术图 · 左键框选护航舰 · 右键舰船打开菜单 · 右键空白处指定航点", CYAN, 13)
	for ship in world.ships.values():
		if not Battle.available(ship, lead.system) or not game.flight.visible_contact(lead,ship):
			continue
		if ship.has("defense_port"):
			continue
		var pos := tactical_screen(ship.pos)
		var tone := Color("f1927d") if world.enemy(lead, ship) else CYAN
		var hull := Battle.Defenses.geometry(ship.kind)
		var projection := tactical_scale()
		var axis := Vector2.from_angle(ship.heading)
		if hull.rect.size.x * projection >= 4.0:
			draw_set_transform(pos,ship.heading,Vector2.ONE*projection)
			draw_colored_polygon(hull.bounds,Color(tone,0.70))
			draw_set_transform(Vector2.ZERO)
			draw_line(pos,pos + axis * hull.rect.end.x * projection,tone,1.4,true)
		else:
			draw_circle(pos,1.6,tone)
			draw_line(pos,pos+axis*3.0,tone,1.0,true)
		if ship.id in fleet_selection:
			draw_arc(pos,maxf(5.0,hull.radius*projection+3.0),0,TAU,24,GOLD,1.0)
		if ship.battle.has("tactical_waypoint"):
			draw_line(pos, tactical_screen(ship.battle.tactical_waypoint), Color(CYAN, 0.6), 1)
		elif ship.battle.focus != 0 and world.ships.has(ship.battle.focus):
			draw_line(pos, tactical_screen(world.ships[ship.battle.focus].pos), Color(GOLD,0.75), 1)
	if dragging:
		draw_rect(Rect2(drag_start, get_local_mouse_position() - drag_start).abs(), GOLD, false)

func draw_hud() -> void:
	if game == null or game.world.player == 0 or galaxy or chart_mode or tactical_open():
		return
	var lead: Dictionary = game.world.ride()
	if lead.is_empty():
		return
	var target: Dictionary = game.world.ships.get(game.selected_target, {})
	if not target.is_empty() and Battle.available(target, lead.system) and game.flight.visible_contact(lead,target):
		var predicted := Battle.lead_point(lead, target, lead.battle.group)
		hud.draw_arc(screen(predicted), 6, 0, TAU, 16, CYAN, 1.4, true)
	tactical_overlay(game.world, lead)

func context_at(point: Vector2) -> Dictionary:
	if not Rect2(Vector2.ZERO,size).has_point(point):
		return {}
	var world = game.world
	if chart_mode:
		var marker := chart_pick(point)
		if marker.get("kind","") in ["port","ship","planet"]:
			return game.entity_menus.ref_for(marker.kind,marker.id,game.current_system() if marker.kind == "planet" else -1)
		if not marker.is_empty():
			return game.entity_menus.ref_for(marker.kind,0,game.current_system())
	for i in range(context_regions.size()-1,-1,-1):
		if context_regions[i].rect.has_point(point):
			return context_regions[i].entity
	if chart_mode or galaxy:
		return {}
	var observer: Dictionary = game.viewed_ship()
	var tactical := tactical_open()
	var projection := tactical_scale() if tactical else zoom
	var pos := camera+(point-size*0.5)/projection if tactical else location(point)
	var closest := INF
	var hit := 0
	for ship: Dictionary in world.ships.values():
		if not Battle.available(ship,game.current_system()) or (not observer.is_empty() and not game.flight.visible_contact(observer,ship)):
			continue
		var delta_pos: Vector2 = pos-Vector2(ship.pos)
		var gap := delta_pos.length_squared()
		if gap < closest and (gap*projection*projection <= 36.0 or Geometry2D.is_point_in_polygon(delta_pos.rotated(-ship.heading),Battle.Defenses.geometry(ship.kind).bounds)):
			closest = gap
			hit = ship.id
	if hit: return game.entity_menus.ref_for("ship",hit)
	var sys: int = game.current_system()
	var region: Dictionary = world.systems[sys]
	var probe := {"pos":pos,"radius":4.0/projection}
	for id: int in region.ports:
		var port: Dictionary = world.ports[id]
		if pos.distance_to(port.pos)*projection <= 8.0 or (not port.has("planet_index") and StationGeometry.intersects_body(StationGeometry.layout(port),probe)):
			return game.entity_menus.ref_for("port",id)
	if region.has("outlaw_base") and StationGeometry.intersects_body(StationGeometry.outpost(region.outlaw_base),probe):
		return game.entity_menus.ref_for("outlaw",0,sys)
	if not tactical:
		for i in region.planets.size():
			var planet: Dictionary = region.planets[i]
			if pos.distance_to(planet.pos) <= planet.radius:
				return game.entity_menus.ref_for("planet",i,sys)
		for entry in ["companion","sun"]:
			if region.has(entry) and pos.distance_to(region[entry].pos) <= region[entry].radius:
				return game.entity_menus.ref_for("star" if entry == "sun" else entry,0,sys)
		if pos.distance_to(Celestial.gravity_point(region))*projection <= 13:
			return game.entity_menus.ref_for("gravity",0,sys)
	return {}

func ink(point: Vector2, caption: String, tone: Color, font_size: int = 15, entity: Dictionary = {}) -> void:
	if not entity.is_empty():
		var font := get_theme_default_font()
		var extent := font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
		context_regions.append({"rect":Rect2(point-Vector2(0,font.get_ascent(font_size)),extent),"entity":entity})
	draw_string(get_theme_default_font(), point, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tone)

func backdrop() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	if not galaxy and game != null and game.world.player != 0:
		var texture := stellar_art.sky(game.world.systems[game.current_system()])
		var dimensions := Vector2(320, 180) * (maxf(size.x / 320.0, size.y / 180.0) + 0.38)
		var parallax := (camera * 0.075).clamp(Vector2(-49, -30), Vector2(49, 30))
		sky_layer.draw_texture_rect(texture, Rect2(((size - dimensions) * 0.5 - parallax).round(), dimensions), false)
		return
	sky_layer.draw_rect(Rect2(Vector2.ZERO, size), Color("070e19"))
	for star in stars:
		var pos: Vector2 = (Vector2(star.x, star.y) * size - camera * (0.09 + star.z * 0.09)).posmodv(size)
		sky_layer.draw_circle(pos, 0.5 + pow(star.z, 8) * 1.7, Color("9eb8d1", 0.16 + star.z * 0.63))
	var corner := location(Vector2.ZERO)
	var spacing := 80.0 if galaxy else 100.0
	for column in range(floori(corner.x / spacing), ceili(location(Vector2(size.x, 0)).x / spacing) + 1):
		var pixel := screen(Vector2(column * spacing, 0)).x
		sky_layer.draw_line(Vector2(pixel, 0), Vector2(pixel, size.y), GRID, 1)
	for row in range(floori(corner.y / spacing), ceili(location(Vector2(0, size.y)).y / spacing) + 1):
		var pixel := screen(Vector2(0, row * spacing)).y
		sky_layer.draw_line(Vector2(0, pixel), Vector2(size.x, pixel), GRID, 1)

func galaxy_map(world, vessel: Dictionary) -> void:
	var extent := size * (0.5/zoom)
	world.stream_hyperspace(camera,extent)
	for index in world.systems_in(Rect2(camera-extent,extent*2.0).grow(110/zoom)):
		var system: Dictionary = world.systems[index]
		var pos := screen(system.pos)
		context_regions.append({"rect":Rect2(pos-Vector2(10,10),Vector2(20,20)),"entity":game.entity_menus.ref_for("system",index)})
		var tone: Color = world.flag_color(world.local_flag(index))
		draw_circle(pos, 42 * zoom, Color(tone, 0.07))
		draw_arc(pos, 30 * zoom, 0, TAU, 36, Color(tone, 0.37), 1, true)
		draw_circle(pos, 13, Color(tone, 0.24))
		var stellar_color := Color(Celestial.STARS[system.sun.type][1])
		draw_circle(pos, 3.5 + clampf(system.sun.radius/3200.0,0.5,5.0), stellar_color)
		draw_circle(pos, 2, Color("ecf5f7"))
		if system.has("companion"):
			draw_circle(pos+Vector2(6,-4),2.5,Color(Celestial.STARS[system.companion.type][1]))
		ink(pos + Vector2(13, -6), system.name,tone if system.seen else Color("99adbf"),15,game.entity_menus.ref_for("system",index))
		if zoom >= 0.55:
			var authority: String = world.flag_name(world.local_flag(index))
			if system.get("frontier_depot",false):
				authority = "燃料补给站"
			if system.has("outlaw_base"):
				authority = world.Outlaws.groups[system.outlaw_base.group].base_name
			ink(pos + Vector2(13, 12), authority, Color("9aafbf"), 12)
	if not vessel.is_empty():
		draw_sensor_envelope(vessel, vessel.galpos)
		for ship in world.ships.values():
			if ship.id == vessel.id:
				continue
			var own_ship: bool = world.can_operate(ship)
			if own_ship:
				if ship.layer and ship.dock == 0:
					var spos := screen(ship.galpos)
					var dest_port: int = ship.get("travel", {}).get("port", 0)
					if dest_port != 0 and world.ports.has(dest_port):
						var dest_sys: int = world.ports[dest_port].system
						draw_dashed_line(spos, screen(world.systems[dest_sys].pos), Color(CYAN, 0.45), 1, 5, true)
					context_regions.append({"rect":Rect2(spos-Vector2(13,10),Vector2(26,20)),"entity":game.entity_menus.ref_for("ship",ship.id)})
					draw_ship(spos, ship.heading, ship.kind, Color("7ef0b8"), 0.72, false)
					tag(spos + Vector2(10, -10), "#%d %s" % [ship.id, world.HULLS[ship.kind]],Color("7ef0b8"),game.entity_menus.ref_for("ship",ship.id))
				else:
					var sys_pos := screen(world.systems[ship.system].pos)
					draw_arc(sys_pos, 18.0, 0.0, TAU, 24, Color("7ef0b8", 0.75), 1.5, true)
					tag(sys_pos + Vector2(14, 18), "#%d %s" % [ship.id, world.HULLS[ship.kind]],Color("7ef0b8"),game.entity_menus.ref_for("ship",ship.id))
			elif ship.layer and ship.dock == 0:
				var is_indie_npc: bool = ship.owner != 0 and not world.enemy(vessel, ship)
				if is_indie_npc or game.flight.visible_contact(vessel, ship):
					var npos := screen(ship.galpos)
					var ntone: Color = world.flag_color(ship.flag)
					context_regions.append({"rect":Rect2(npos-Vector2(13,10),Vector2(26,20)),"entity":game.entity_menus.ref_for("ship",ship.id)})
					draw_ship(npos, ship.heading, ship.kind, ntone, 0.46, false)
					if is_indie_npc and zoom >= 0.65:
						tag(npos + Vector2(8, -8), "%s(%s)" % [world.name_of(ship.captain), ship.job.get("kind", "航行")],ntone,game.entity_menus.ref_for("person",ship.captain) if ship.captain else game.entity_menus.ref_for("ship",ship.id))
		if game.waypoint_live:
			var start := screen(vessel.galpos)
			var end := screen(game.waypoint)
			var route := (end - start).limit_length(size.length())
			draw_dashed_line(start,start+route,Color(GOLD,0.55),1,6,true)
			if not in_frame(end):
				edge(end,game.waypoint_label if not game.waypoint_label.is_empty() else "航点",GOLD,vessel,game.waypoint)
		context_regions.append({"rect":Rect2(screen(vessel.galpos)-Vector2(13,10),Vector2(26,20)),"entity":game.entity_menus.ref_for("ship",vessel.id)})
		draw_ship(screen(vessel.galpos), vessel.heading, vessel.kind, CYAN, 1.0, true)

func local_map(world, vessel: Dictionary, system_index: int) -> void:
	var system: Dictionary = world.systems[system_index]
	if crowded:
		battle_landmarks(world, system)
		station_wing_labels()
		return
	if not vessel.is_empty() and not vessel.locked:
		draw_sensor_envelope(vessel, vessel.pos)
	celestial_markers(system, vessel)
	var tone := Color("91a7b7")
	for index in range(system.get("rock_count",17)):
		var angle: float = index * 2.399 + system.get("belt_angle",0.0)
		var offset := (Vector2.from_angle(angle) * (14.0 + index*3.8)) * Vector2(1,system.get("belt_width",0.7))
		var rock_pos: Vector2 = system.field + offset.rotated(system.get("belt_angle",0.0))
		var rock := screen(rock_pos)
		var radius := (3 + index % 8) * zoom
		if radius < 0.8 or not Rect2(Vector2.ZERO,size).grow(radius+1).has_point(rock):
			continue
		var outline := PackedVector2Array()
		for vertex in range(6):
			outline.append(rock + Vector2.from_angle(angle + vertex * TAU / 6) * radius * (0.76 + ((vertex + index) % 4) * 0.12))
		draw_colored_polygon(outline, Color("293c4b").lerp(Color("886d59"), (index % 5) * 0.18))
		outline.append(outline[0])
		draw_polyline(outline, Color("677387"), 1, true)
	if in_frame(screen(system.field)):
		ink(screen(system.field) + Vector2(-54, -79), "矿带  /  %s" % system.ore, GOLD, 13)
	if system.has("outlaw_base"):
		draw_outlaw_base(world,system.outlaw_base,vessel)
	for port_id in system.ports:
		draw_station(world,world.ports[port_id],vessel)
	for wreck in world.wrecks.values():
		if wreck.system != system_index:
			continue
		var pos := screen(wreck.pos)
		var kind := Hulls.kind_for_id(wreck.get("hull_id",""))
		if not Rect2(Vector2.ZERO,size).grow(160).has_point(pos): continue
		if kind < 0:
			draw_set_transform(pos,float(int(wreck.at)%8)*0.4)
			draw_texture_rect(Pixels.ship_texture(0),Rect2(-15,-9,30,18),false,Color("827064"))
			draw_set_transform(Vector2.ZERO)
		var label_at := pos+Vector2(12,-8) if kind < 0 else pos+Vector2(8,Battle.Defenses.geometry(kind).radius*zoom+12)
		ink(label_at,"漂流残骸" if kind < 0 else "%s 残骸" % Hulls.MODELS[kind].name,Color("bc9b73"),12)
		if not vessel.is_empty() and vessel.pos.distance_to(wreck.pos) < 95.0 and not vessel.locked and wreck.stock.max() > 0:
			tag(label_at+Vector2(0,17),"[G] 打捞",GOLD)
	for other in world.ships.values():
		if not Battle.available(other, system_index) or (not vessel.is_empty() and not game.flight.visible_contact(vessel,other)):
			continue
		if other.has("defense_port"):
			continue
		var own: bool = other.id == vessel.get("id", 0)
		var pos := screen(other.pos)
		tone = CYAN if own else world.flag_color(other.flag)
		if crowded and not own and game.selected_target != other.id:
			continue
		if not own and not vessel.is_empty() and world.enemy(vessel, other) and not in_frame(pos):
			edge(pos, "敌舰", Color("ef8f7b"), vessel, other.pos,game.entity_menus.ref_for("ship",other.id))
			continue
		if other.locked and not own:
			draw_arc(pos, 28, 0, TAU, 32, Color("e78275", 0.7), 1, true)
			draw_rect(Rect2(pos + Vector2(-20, -35), Vector2(40, 3)), Color("46323a"))
			draw_rect(Rect2(pos + Vector2(-20, -35), Vector2(40 * maxf(other.hp, 0) / world.HULL_HP[other.kind], 3)), Color("e78275"))
		var radius: float = Battle.Defenses.geometry(other.kind).radius * zoom + 7
		if other.battle.overload > 0.0 or other.hp < Hulls.MODELS[other.kind].hp * 0.38:
			var phase := int(Time.get_ticks_msec() / 88 + other.id) % 4
			var spark := Pixels.effect_texture(1, phase, CYAN if other.battle.overload > 0.0 else GOLD)
			draw_texture_rect(spark, Rect2(pos + Vector2(-22 + phase * 6,-14),Vector2(40,40)), false)
		if not own:
			ink(pos + Vector2(13, 23), world.flag_name(other.flag), tone, 12)
			if other.locked or (world.can_operate(other) and other.job.get("kind","") == "护航"):
				tag(pos + Vector2(13,39), other.battle.ai, tone)
			if game.selected_target == other.id:
				draw_arc(pos, radius + 14, 0, TAU, 36, GOLD, 1, true)
				tag(pos + Vector2(-34,-radius-20), "集火目标", GOLD)
	if not in_frame(screen(system.field)):
		edge(screen(system.field), "矿带", GOLD, vessel, system.field)
	elif not vessel.is_empty() and vessel.pos.distance_to(system.field) < 95.0 and not vessel.locked:
		tag(screen(system.field) + Vector2(-31,61), "[G] 采掘", GOLD)
	station_wing_labels()
	for bolt in world.projectiles:
		if bolt.system != system_index:
			continue
		var kind: String = bolt.get("ordnance","")
		if Ordnance.GLYPHS.has(kind):
			Ordnance.draw_shot(kind, bolt.pos, bolt.vel, draw_ordnance_segment)
			continue
		if bolt.get("mine",false):
			var center := screen(bolt.pos)
			draw_circle(center,3.0,Color("fbba80"))
			draw_arc(center,6.5,0,TAU,12,Color("ca714a"),1.0)
			continue
		var direction: Vector2 = bolt.vel.normalized()
		var color: Color = [Color("b1d4eb"),Color("f4a273"),CYAN,Color("bbbd86")][bolt.type]
		if bolt.missile:
			for segment in range(1, 7):
				draw_circle(screen(bolt.pos - direction * segment * 7), 1.1 + segment * 0.62, Color("b3a4a0", 0.32 - segment * 0.042))
		draw_line(screen(bolt.pos - direction * (11 if bolt.missile else 19)), screen(bolt.pos), color, 2.5, true)
	effects(system_index)
	if game.waypoint_live:
		var point := screen(game.waypoint)
		if not in_frame(point):
			edge(point, "航点", GOLD, vessel, game.waypoint)
		draw_arc(point, 13, 0, TAU, 20, GOLD, 1, true)
		draw_line(point - Vector2(17, 0), point + Vector2(17, 0), GOLD)

func station_wing_labels() -> void:
	var groups := {}
	for flight in visible_wings:
		var station := int(flight[3])
		if station > 0:
			var wing: Dictionary = flight[0]
			var row: Dictionary = groups.get_or_add(station,{"pos":wing.pos,"aircraft":0,"squadrons":0})
			row.aircraft += int(wing.get("airborne",wing.get("count_live",wing.count)))
			row.squadrons += 1
	for row: Dictionary in groups.values():
		tag(screen(row.pos)+Vector2(12,-18),"驻站机群 · %d 队 / %d 架" % [row.squadrons,row.aircraft],Color("f5cd84"))

func draw_ordnance_segment(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	draw_line(screen(a), screen(b), color, width * zoom, true)

func battle_landmarks(world, system: Dictionary) -> void:
	draw_bodies(system,{},false)
	var lead: Dictionary = world.ride()
	if system.has("outlaw_base"):
		draw_outlaw_base(world,system.outlaw_base,lead)
	for id in system.ports:
		draw_station(world,world.ports[id],lead)
	var mine := screen(system.field)
	if in_frame(mine):
		draw_circle(mine, 5, GOLD)
	var target: Dictionary = world.ships.get(game.selected_target,{})
	if not target.is_empty() and Battle.available(target, system.id):
		var at := screen(target.pos)
		draw_arc(at, float(Battle.Defenses.geometry(target.kind).radius)*zoom+4,0,TAU,24,GOLD,1.0)
	if game.waypoint_live:
		draw_arc(screen(game.waypoint),9,0,TAU,12,GOLD,1.0)

func draw_station_hull(geom: Dictionary, tone: Color, modulation: Color, tactical: bool) -> Vector2:
	var scale_factor := tactical_scale() if tactical else zoom
	var center := tactical_screen(geom.center) if tactical else screen(geom.center)
	var bounds: Rect2 = geom.bounds
	if Rect2(center-bounds.size*scale_factor*0.5,bounds.size*scale_factor).intersects(Rect2(Vector2.ZERO,size)):
		if geom.has("parts"):
			StationArt.draw_layout(self,geom,center,geom.angle,scale_factor,tone,modulation)
		else:
			draw_set_transform(center, geom.angle, Vector2.ONE * scale_factor)
			draw_texture_rect(Pixels.station_hull_texture(geom.skin,tone),Rect2(-geom.size*0.5,geom.size),false,modulation)
			draw_set_transform(Vector2.ZERO)
	return tactical_screen(geom.berth) if tactical else screen(geom.berth)

func draw_station(world, station: Dictionary, vessel: Dictionary, tactical: bool = false) -> void:
	if station.has("planet_index"):
		var landing := tactical_screen(station.pos) if tactical else screen(station.pos)
		if in_frame(landing):
			draw_circle(landing,4.0,CYAN)
			if not crowded or tactical:
				ink(landing+Vector2(9,-8),station.name,CYAN,12,game.entity_menus.ref_for("port",station.id))
		return
	var geom := StationGeometry.layout(station)
	var tint: Color = world.flag_color(station.flag)
	var at := draw_station_hull(geom, tint, Color("a5abba") if station.build > 0 else Color.WHITE, tactical)
	if not tactical and not station.has("assault") and station.build == 0 and centered_rect(geom.center,geom.span).intersects(Rect2(Vector2.ZERO,size)):
		var signature := hash([station.modules,station.get("capital_yard",false),station.get("module_armaments",{})])
		var cached: Dictionary = station_fits.get(station.id,{})
		if cached.get("signature",-1) != signature:
			cached = {"signature":signature,"rows":[]}
			for i in station.modules.size()+1:
				cached.rows.append({"kind":world.StationArmament.profile(station,i),"fit":world.StationArmament.fitting(station,i),"mount_offsets":world.StationArmament.mount_offsets(geom.parts[i]),"battle":{}})
			if station_fits.size() >= 128:
				station_fits.clear()
			station_fits[station.id] = cached
		for i in cached.rows.size():
			var part: Dictionary = geom.parts[i]
			var idle: Dictionary = cached.rows[i]
			idle.pos = Vector2(geom.center) + Vector2(part.center).rotated(geom.angle)
			idle.heading = geom.angle
			idle.module_size = part.size
			draw_station_weapons(idle,false)
	for sid in station.get("assault",{}).get("nodes",[]):
		var gun: Dictionary = world.ships.get(sid,{})
		if not gun.is_empty():
			draw_station_battery(gun,tactical)
	if not tactical:
		for index in station.get("assault",{}).get("disabled",[]):
			var center: Vector2 = geom.center + Vector2(geom.parts[index].center).rotated(geom.angle)
			var at_module := screen(center)
			draw_line(at_module-Vector2(8,8),at_module+Vector2(8,8),Color("e88261"),2)
			draw_line(at_module+Vector2(-8,8),at_module+Vector2(8,-8),Color("e88261"),2)
			tag(at_module+Vector2(12,3),"武备失能",Color("d99876"))
	if not in_frame(at):
		if not tactical:
			edge(at,station.name,tint,vessel,station.pos,game.entity_menus.ref_for("port",station.id))
		return
	draw_arc(at,8.0,0,TAU,12,CYAN,1.5,true)
	var outward: Vector2 = geom.outward
	draw_line(at+outward*9.0,at+outward*17.0,CYAN,1.5)
	var name_at := at + Vector2(13,-10)
	ink(name_at,station.name,tint,13,game.entity_menus.ref_for("port",station.id))
	if tactical:
		return
	var mooring: bool = not vessel.is_empty() and not vessel.locked and vessel.pos.distance_to(station.pos) <= StationGeometry.docking_range(vessel.kind) and world.can_dock(vessel,station)
	if mooring:
		tag(name_at+Vector2(0,18),"[E] 停靠",CYAN)
	elif not crowded:
		ink(name_at+Vector2(0,16),("施工 %d 日" % station.build) if station.build > 0 else "%s · 泊位" % world.MODULES[station.module],Color("adb7bc"),12)

func centered_rect(center: Vector2, span: float) -> Rect2:
	var extent := Vector2.ONE * span * zoom
	return Rect2(screen(center)-extent,extent*2.0)

func draw_station_weapons(gun: Dictionary, tactical: bool) -> void:
	var pos := tactical_screen(gun.pos) if tactical else screen(gun.pos)
	var scale_factor := tactical_scale() if tactical else zoom
	var hull_transform := Transform2D(gun.heading,Vector2.ONE * scale_factor,0,pos)
	var angles: Array = gun.battle.get("turret_angles",[])
	var recoils: Array = gun.battle.get("recoil",[])
	var disabled: Array = gun.battle.get("disabled_slots",[])
	for slot in gun.fit.weapons.size():
		var id: String = gun.fit.weapons[slot]
		if id == "":
			continue
		var mount := Hulls.slot_spec(gun.kind,slot)
		var style := WeaponArt.profile(id)
		var angle := float(angles[slot]) if slot < angles.size() else deg_to_rad(float(mount.facing))
		var recoil := float(recoils[slot]) if slot < recoils.size() else 0.0
		var pose := WeaponArt.pose(mount,style,angle,recoil)
		pose.origin += Battle.slot_offset(gun,slot) - Vector2(mount.offset)
		pose = hull_transform * pose
		var jammed: bool = slot < disabled.size() and float(disabled[slot])>0.0
		WeaponArt.draw_mount(self,pose,style.family,WeaponArt.tint(jammed,recoil))
		if recoil > 0.75 and not jammed:
			draw_circle(pose*Vector2(7,0),1.9*recoil*scale_factor,Color("ffe8aa"))

func draw_station_battery(gun: Dictionary, tactical: bool) -> void:
	var pos := tactical_screen(gun.pos) if tactical else screen(gun.pos)
	var scale_factor := tactical_scale() if tactical else zoom
	var shape := Battle.Defenses.body_geometry(gun)
	var radius := maxf(4.0,shape.radius * scale_factor)
	var tone := Color("f29273")
	draw_station_weapons(gun,tactical)
	if tactical and gun.battle.shield:
		var origin := Battle.Defenses.shield_world_center(gun)
		var shield := tactical_screen(origin) if tactical else screen(origin)
		var facing := float(gun.heading) + float(gun.battle.shield_offset)
		var half_arc := float(gun.battle.shield_arc_live)*0.5
		draw_arc(shield,maxf(5.0,shape.shield_radius*scale_factor),facing-half_arc,facing+half_arc,48,Color("79e3fd"),2.0+gun.battle.shield_flash*2.0,true)
	draw_rect(Rect2(pos+Vector2(-25,-radius-10),Vector2(50,4)),Color("422e33"))
	draw_rect(Rect2(pos+Vector2(-25,-radius-10),Vector2(50*clampf(float(gun.hp)/Hulls.MODELS[gun.kind].hp,0,1),4)),tone)
	draw_rect(Rect2(pos+Vector2(-25,-radius-15),Vector2(50,3)),Color("23404a"))
	if gun.battle.shield:
		draw_rect(Rect2(pos+Vector2(-25,-radius-15),Vector2(50*(1.0-clampf(Battle.fraction(gun),0,1)),3)),Color("79e3fd"))
	if not tactical:
		ink(pos+Vector2(-31,-radius-20),str(gun.job.label) + " · " + ("过载" if gun.battle.overload>0 else ("升盾" if gun.battle.shield else "无盾")),tone,13)

func draw_outlaw_base(world, base: Dictionary, vessel: Dictionary, tactical: bool = false) -> void:
	var spec: Dictionary = world.Outlaws.groups[base.group]
	var tint := Color(spec.color)
	var at := draw_station_hull(StationGeometry.outpost(base),tint,Color.WHITE,tactical)
	if not in_frame(at):
		if not tactical:
			edge(at,spec.base_name,tint,vessel,base.pos,game.entity_menus.ref_for("outlaw",0,game.current_system()))
		return
	if spec.has("guard_radius"):
		draw_arc(at,spec.guard_radius*(tactical_scale() if tactical else zoom),0,TAU,60,Color(tint,0.33),1.5,true)
	tag(at+Vector2(12,-12),spec.base_name,tint,game.entity_menus.ref_for("outlaw",0,game.current_system()))

func display_body(body: Dictionary, star: bool, at: Vector2, radius: float, sunward: Vector2 = Vector2.ZERO) -> void:
	if visible_bodies == body_quads.size():
		var surface := ColorRect.new()
		surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body_layer.add_child(surface)
		body_quads.append(surface)
	var quad := body_quads[visible_bodies]
	visible_bodies += 1
	var key: int = body.get("surface_seed",hash([body.type,body.radius]))
	var changed: bool = quad.get_meta("surface_key",-1) != key
	if changed:
		quad.material = stellar_art.material_for(body,star)
		quad.set_meta("surface_key",key)
	var spin := float(body.get("spin",0.0))
	if quad.get_meta("body_spin",INF) != spin:
		quad.material.set_shader_parameter("spin",spin)
		quad.set_meta("body_spin",spin)
	if not star and (changed or quad.get_meta("sunward",Vector2.INF) != sunward):
		quad.material.set_shader_parameter("sunward",sunward)
		quad.set_meta("sunward",sunward)
	quad.position = at - Vector2.ONE*radius*1.65
	quad.size = Vector2.ONE*radius*3.3
	quad.show()

func draw_sun(star: Dictionary, labels: bool) -> void:
	var color := Color(Celestial.STARS[star.type][1])
	var sun_pos := screen(star.pos)
	var radius: float = star.radius * zoom
	if not Rect2(Vector2.ZERO,size).grow(radius*1.2).has_point(sun_pos):
		return
	display_body(star,true,sun_pos,radius)
	if labels and in_frame(sun_pos):
		tag(sun_pos + Vector2(-22, radius + 19.0), Celestial.STARS[star.type][0], color)

func draw_bodies(region: Dictionary, vessel: Dictionary, labels: bool) -> void:
	draw_sun(region.sun,labels)
	if region.has("companion"):
		draw_sun(region.companion,labels)
	for planet: Dictionary in region.planets:
		var at := screen(planet.pos)
		var diameter: float = planet.radius * zoom * 3.3
		var bounds := Rect2(at-Vector2.ONE*diameter*0.5,Vector2.ONE*diameter)
		if bounds.intersects(Rect2(Vector2.ZERO,size)):
			display_body(planet,false,at,planet.radius*zoom,Vector2(planet.pos).direction_to(region.sun.pos))
			if labels:
				var can_survey: bool = not vessel.is_empty() and not planet.surveyed and vessel.pos.distance_to(planet.pos) <= planet.radius+52
				tag(at+Vector2(-22,planet.radius*zoom+14), "[G] 勘测" if can_survey else Celestial.PLANETS[planet.type][0], Color("a8c2ce"))
			if labels and not planet.get("port_id",0):
				var landing := screen(game.world.PlanetPorts.point(planet))
				if in_frame(landing):
					draw_circle(landing,4,CYAN)
					ink(landing+Vector2(8,-8),"[E] 着陆点",CYAN,12)

func celestial_markers(region: Dictionary, vessel: Dictionary) -> void:
	draw_bodies(region,vessel,true)
	var gravity := Celestial.gravity_point(region)
	var destination := screen(gravity)
	if not in_frame(destination):
		edge(destination, "引力点", JUMP_COLOR, vessel, gravity)
		return
	var ready: bool = not vessel.is_empty() and not vessel.locked and Celestial.at_gravity_point(region, vessel.pos)
	draw_arc(destination, Celestial.JUMP_RANGE * zoom, 0.0, TAU, 48, Color(JUMP_COLOR, 0.52 if ready else 0.22), 1.5, true)
	draw_arc(destination, 13.0, 0.0, TAU, 30, JUMP_COLOR, 2.0, true)
	draw_circle(destination, 4.0, JUMP_COLOR)
	tag(destination + Vector2(-27, -20), "[M] 跃入超空间" if ready else "恒星引力点", JUMP_COLOR)

func draw_ship(pos: Vector2, heading: float, kind: int, tone: Color, magnitude: float, own: bool, thrust: Vector2 = Vector2.ZERO) -> void:
	var model: Dictionary = Hulls.MODELS[kind]
	var map_scale := magnitude * (0.55 if galaxy else 1.0)
	var scale_factor: float = model.sprite_scale * map_scale
	draw_set_transform(pos.round(), heading, Vector2.ONE * scale_factor)
	if thrust.length() > 12.0:
		var phase := int(Time.get_ticks_msec() / 80) % 4
		var plume := Pixels.effect_texture(0, phase, CYAN)
		for nozzle: Vector2 in model.engine_slots:
			var exhaust := pos + (nozzle * map_scale).rotated(heading)
			draw_set_transform(exhaust, heading, Vector2.ONE * map_scale)
			draw_texture_rect(plume, Rect2(-28, -9, 30, 18), false)
		draw_set_transform(pos.round(), heading, Vector2.ONE * scale_factor)
	var livery := Color(model.paint).lerp(tone, 0.38)
	draw_texture(Pixels.ship_texture(kind, livery), -Vector2(model.sprite_center))
	draw_set_transform(Vector2.ZERO)
	if own:
		var ring: float = Battle.Defenses.geometry(kind).radius * map_scale + 4.0
		draw_arc(pos, ring, 0.2, 1.3, 14, tone, 1, true)
		draw_arc(pos, ring, 3.35, 4.45, 14, tone, 1, true)

func tag(pos: Vector2, text: String, color: Color, entity: Dictionary = {}) -> void:
	var width := get_theme_default_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_rect(Rect2(pos - Vector2(4,12), Vector2(width + 8,16)), Color("0b1420",0.91))
	ink(pos,text,color,12,entity)

func in_frame(point: Vector2) -> bool:
	return Rect2(Vector2(24,25), size - Vector2(48,50)).has_point(point)

func edge(point: Vector2, name_text: String, tone: Color, vessel: Dictionary, at: Vector2, entity: Dictionary = {}) -> void:
	var axis := (point - size * 0.5).normalized()
	var bounds := size * 0.5 - Vector2(62,42)
	var scale_factor := minf(bounds.x / maxf(absf(axis.x), 0.0001), bounds.y / maxf(absf(axis.y), 0.0001))
	var pos := size * 0.5 + axis * scale_factor
	draw_colored_polygon(PackedVector2Array([pos + axis * 9, pos - axis * 4 + axis.orthogonal() * 5, pos - axis * 4 - axis.orthogonal() * 5]), tone)
	var origin: Vector2 = vessel.get("galpos" if galaxy else "pos",at)
	var text := name_text if vessel.is_empty() else "%s %d" % [name_text, origin.distance_to(at)]
	tag(pos-axis*25+Vector2(-16,4),text,tone,entity)

func effects(system: int) -> void:
	for particle in particles:
		var effect: Dictionary = particle.event
		if effect.system != system:
			continue
		var age: float = particle.age
		var pos := screen(effect.pos)
		match effect.kind:
			"beam":
				var end := screen(Vector2(effect.pos) + Vector2(effect.direction))
				var fade := maxf(0.0, 1.0 - age * 8.0)
				draw_line(pos, end, Color(0.25,0.75,1.0, fade * 0.45), 5.0, true)
				draw_line(pos, end, Color(0.86,0.99,1.0, fade), 1.6, true)
			"emp":
				var axis := Vector2(effect.direction).orthogonal()
				var points := PackedVector2Array([pos-axis*9.0, pos-axis*4.0+Vector2(3,2), pos+axis*2.0-Vector2(3,2), pos+axis*9.0])
				draw_polyline(points, Color(0.7,0.75,1.0,maxf(0.0,1.0-age*4.0)), 1.5, true)
			"shield":
				draw_circle(pos, 2.5 * zoom, Color(CYAN, maxf(0.0,1.0-age*8.0)))
			"rupture":
				draw_circle(pos, (8 + age * 49) * effect.strength, Color("ffae69",maxf(0.0,0.45-age*0.48)))
				for fragment in range(13):
					var axis := Vector2.from_angle(fragment * 2.4 + int(effect.serial) % 9)
					var point: Vector2 = pos + axis * age * (28 + fragment * 4) * effect.strength
					draw_rect(Rect2(point.round(),Vector2(3,2)), Color(GOLD,1.0-age))
			_:
				var radius := (5 + age * 34.0) * float(effect.strength)
				var tone := CYAN if effect.kind in ["overload","system","intercept"] else GOLD
				var image := Pixels.effect_texture(1, mini(3, int(age * 13)), tone)
				draw_texture_rect(image, Rect2(pos - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), false, Color(1,1,1,maxf(0.0,1.0-age*2.0)))

func hud_ink(point: Vector2, caption: String, tone: Color, font_size: int = 15) -> void:
	hud.draw_string(get_theme_default_font(), point, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tone)

func meter(pos: Vector2, amount: float, tone: Color, secondary: float = 0.0) -> void:
	var origin := pos + Vector2(39,-8)
	hud.draw_rect(Rect2(origin,Vector2(175,9)), Color("28374a"))
	var base := 175 * clampf(amount,0.0,1.0)
	if base > 0.0:
		hud.draw_rect(Rect2(origin,Vector2(base,9)), tone)
	if secondary > 0.0 and base < 175.0:
		hud.draw_rect(Rect2(origin + Vector2(base,0),Vector2(minf(175 * secondary,175.0-base),9)), Color("e8f2f3"))

func tactical_overlay(world, vessel: Dictionary) -> void:
	if vessel.is_empty():
		return
	var state: Dictionary = vessel.battle
	var start := Vector2(12,size.y - 117)
	var title_color := CYAN if state.overload <= 0.0 else Color("f8a975")
	hud.draw_rect(Rect2(start,Vector2(237,106)),Color("081421",0.94))
	meter(start + Vector2(9,33), vessel.hp / Hulls.MODELS[vessel.kind].hp, Color("7ad0ab"))
	meter(start + Vector2(9,47), state.armor / Hulls.COMBAT[vessel.kind].armor, Color("e0b981"))
	meter(start + Vector2(9,61), state.soft_flux / Hulls.capacity(vessel), Color("6faeca"), state.hard_flux / Hulls.capacity(vessel))
	if state.soft_flux + state.hard_flux > 0.0:
		var split := "%d 软 / %d 硬" % [roundi(state.soft_flux),roundi(state.hard_flux)]
		var width := get_theme_default_font().get_string_size(split,HORIZONTAL_ALIGNMENT_LEFT,-1,9).x
		var center := start + Vector2(134.0 - width * 0.5,60.0)
		hud.draw_rect(Rect2(center - Vector2(2,9),Vector2(width + 4,10)), Color("081421",0.82))
		hud_ink(center,split,Color("e3f2ee"),9)
	hud_ink(start + Vector2(9,16), "旗舰状态    /    " + ("过载 %.1f 秒" % state.overload if state.overload > 0.0 else ("主动排散" if state.vent else "战备")), title_color, 12)
	hud_ink(start + Vector2(9,33), "船体", Color("b6c9d3"), 11)
	hud_ink(start + Vector2(9,47), "装甲", Color("b6c9d3"), 11)
	hud_ink(start + Vector2(9,61), "幅能", Color("b6c9d3"), 11)
	for group in range(1,4):
		var cooldown := 0.0
		var equipped := false
		for index in range(vessel.fit.groups.size()):
			if vessel.fit.groups[index] == group and not str(vessel.fit.weapons[index]).is_empty():
				equipped = true
				cooldown = maxf(cooldown, state.cooldowns[index])
		var label := "—" if not equipped else ("%.1fs" % cooldown if cooldown > 0.0 else "就绪")
		hud_ink(start + Vector2(9 + (group - 1) * 74,79), "%s%s %s" % [group,"自" if vessel.fit.auto[group-1] else "",label], GOLD if state.group == group else Color("88a1b1"), 11)
	var system := Battle.Abilities.profile(vessel)
	var status := "%.1fs" % state.system_cd if state.system_cd > 0.0 else "就绪"
	if state.system_time > 0.0:
		status = "开启" if system.get("toggle",false) else "激活 %.1fs" % state.system_time
	var uses := ""
	if system.has("charges"):
		var remaining := floori(state.get("system_charges",system.charges) + 0.00001)
		uses = "  %d/%d" % [remaining,system.charges]
		if remaining == 0 and state.system_cd <= 0.0 and state.system_time <= 0.0:
			status = "充能中" if system.get("regen",0.0) > 0.0 else "耗尽"
	var system_line := "F  %s%s · %s" % [system.label,uses,status] if system.effect != "none" else str(system.label)
	hud_ink(start + Vector2(9,97), system_line, CYAN, 11)
	var radar := Vector2(size.x-86,88)
	hud.draw_rect(Rect2(radar - Vector2(76,76),Vector2(152,152)),Color("081421",0.93))
	for ring in [24,49,68]:
		hud.draw_arc(radar,ring,0,TAU,44,Color("436479",0.67),1,true)
	hud.draw_line(radar - Vector2(68,0),radar + Vector2(68,0),Color("30465b"))
	hud.draw_line(radar - Vector2(0,68),radar + Vector2(0,68),Color("30465b"))
	for port_id in world.systems[vessel.system].ports:
		var station: Dictionary = world.ports[port_id]
		hud.draw_rect(Rect2(radar + ((Vector2(station.pos)-Vector2(vessel.pos))*0.085).limit_length(65) - Vector2(2,2),Vector2(4,4)), GOLD)
	var friendly := PackedVector2Array()
	var enemies := PackedVector2Array()
	for ship in contacts:
		if ship.id != vessel.id:
			var point := radar + ((Vector2(ship.pos)-Vector2(vessel.pos))*0.085).limit_length(65)
			if world.enemy(vessel,ship):
				enemies.append(point-Vector2(1.5,0))
				enemies.append(point+Vector2(1.5,0))
			else:
				friendly.append(point-Vector2(1.5,0))
				friendly.append(point+Vector2(1.5,0))
	if not enemies.is_empty():
		hud.draw_multiline(enemies, Color("ef8f7b"), 3.0)
	if not friendly.is_empty():
		hud.draw_multiline(friendly, CYAN, 3.0)
	hud.draw_circle(radar,3,Color("d7f7e5"))

func draw_sensor_envelope(vessel: Dictionary, at: Vector2) -> void:
	if game.flight.sensor_reading.is_empty():
		return
	var center := screen(at)
	var reading: Dictionary = game.flight.sensor_reading
	draw_arc(center, float(reading.strength)*zoom, 0.0, TAU, 64, Color(CYAN,0.18),1.0)
	draw_arc(center, float(reading.profile)*zoom, 0.0, TAU, 64, Color(GOLD,0.23),1.0)

func _draw() -> void:
	context_regions.clear()
	if size.x <= 0 or size.y <= 0:
		return
	visible_bodies = 0
	sky_layer.queue_redraw()
	if game == null or game.world.player == 0:
		return
	var world = game.world
	var vessel: Dictionary = game.viewed_ship()
	var system_index: int = game.current_system()
	if galaxy:
		galaxy_map(world, vessel)
	elif chart_mode:
		draw_system_chart(world,world.systems[system_index],vessel)
	elif tactical_open():
		draw_tactical_map()
	else:
		local_map(world, vessel, system_index)
	for index in range(visible_bodies,body_quads.size()):
		body_quads[index].hide()
	draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), Color("385066"), false)

func draw_system_chart(world, region: Dictionary, vessel: Dictionary) -> void:
	draw_bodies(region,{},false)
	update_chart_markers(world,region,vessel)
	SystemChart.draw(self,region,vessel,chart_markers)
	ink(Vector2(14,23),"%s · 星系星图" % region.name,CYAN,16,game.entity_menus.ref_for("system",game.current_system()))
	ink(Vector2(14,size.y-9),"细线 · 公转轨道　青圈 · 行星引力圈　□ 轨道站　◇ 地表着陆点",Color("a2b9c7"),12)

func chart_bounds(region: Dictionary, ship_pos: Vector2) -> Rect2:
	return SystemChart.bounds(game.world,region,ship_pos)

func update_chart_markers(world, region: Dictionary, vessel: Dictionary) -> void:
	var stamp := [world.settings.seed,region.name,world.day,region.ports.size(),vessel.get("id",0),vessel.get("pos",Vector2.ZERO),
		camera,size,zoom,motion_offset,chart_selected.get("kind",""),chart_selected.get("id",-1)]
	if stamp != chart_stamp:
		chart_stamp = stamp
		chart_markers = SystemChart.markers(self,world,region,vessel)

func chart_pick(point: Vector2) -> Dictionary:
	if not chart_mode or not Rect2(Vector2.ZERO,size).has_point(point):
		return {}
	var region: Dictionary = game.world.systems[game.current_system()]
	update_chart_markers(game.world,region,game.viewed_ship())
	return SystemChart.pick(chart_markers,point)
