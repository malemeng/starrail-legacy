extends Control

const Pixels = preload("res://art/pixel_art.gd")
const Hulls = preload("res://hull_catalog.gd")
const Battle = preload("res://combat.gd")
const Celestial = preload("res://celestial.gd")

var game
var stars: Array = []
var galaxy := false
var camera := Vector2.ZERO
var zoom := 1.0
var impulse := 0.0
var motion_offset := Vector2.ZERO
var particles: Array = []
var event_cursor := 0
var event_system := -1
const GRID := Color("1b3146")
const CYAN := Color("8dd5de")
const GOLD := Color("f0bc79")
const JUMP_COLOR := Color("95deea")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	if event_system != system or event_cursor > game.world.combat_serial:
		particles.clear()
		event_system = system
		event_cursor = 0
	if not galaxy:
		for event in game.world.combat_events:
			if event.serial <= event_cursor:
				continue
			event_cursor = event.serial
			if event.system != system:
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
	impulse = move_toward(impulse, 0.0, delta * 31.0)
	motion_offset = Vector2(sin(Time.get_ticks_msec() * 0.09), cos(Time.get_ticks_msec() * 0.073)) * impulse if not galaxy else Vector2.ZERO

func ink(point: Vector2, caption: String, tone: Color, font_size: int = 15) -> void:
	draw_string(get_theme_default_font(), point, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tone)

func backdrop() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("070e19"))
	if not galaxy and game != null and game.world.player != 0:
		var texture := Pixels.backdrop_texture(posmod(game.current_system(), 3))
		var dimensions := Vector2(320, 180) * (maxf(size.x / 320.0, size.y / 180.0) + 0.38)
		var parallax := (camera * 0.075).clamp(Vector2(-49, -30), Vector2(49, 30))
		draw_texture_rect(texture, Rect2(((size - dimensions) * 0.5 - parallax).round(), dimensions), false, Color(0.71, 0.76, 0.82))
		return
	for star in stars:
		var pos: Vector2 = (Vector2(star.x, star.y) * size - camera * (0.09 + star.z * 0.09)).posmodv(size)
		draw_circle(pos, 0.5 + pow(star.z, 8) * 1.7, Color("9eb8d1", 0.16 + star.z * 0.63))
	var corner := location(Vector2.ZERO)
	var spacing := 80.0 if galaxy else 100.0
	for column in range(floori(corner.x / spacing), ceili(location(Vector2(size.x, 0)).x / spacing) + 1):
		var pixel := screen(Vector2(column * spacing, 0)).x
		draw_line(Vector2(pixel, 0), Vector2(pixel, size.y), GRID, 1)
	for row in range(floori(corner.y / spacing), ceili(location(Vector2(0, size.y)).y / spacing) + 1):
		var pixel := screen(Vector2(0, row * spacing)).y
		draw_line(Vector2(0, pixel), Vector2(size.x, pixel), GRID, 1)

func galaxy_map(world, vessel: Dictionary) -> void:
	for index in range(world.systems.size()):
		var system: Dictionary = world.systems[index]
		var pos := screen(system.pos)
		var tone: Color = world.flag_color(world.local_flag(index))
		draw_circle(pos, 42 * zoom, Color(tone, 0.07))
		draw_arc(pos, 30 * zoom, 0, TAU, 36, Color(tone, 0.37), 1, true)
		draw_circle(pos, 13, Color(tone, 0.24))
		draw_circle(pos, 5, tone)
		draw_circle(pos, 2, Color("ecf5f7"))
		ink(pos + Vector2(13, -6), system.name, tone if system.seen else Color("99adbf"))
		ink(pos + Vector2(13, 12), world.flag_name(world.local_flag(index)), Color("7189a0"), 12)
	if not vessel.is_empty():
		if game.waypoint_live:
			draw_dashed_line(screen(vessel.galpos), screen(game.waypoint), Color(GOLD, 0.55), 1, 6, true)
		draw_ship(screen(vessel.galpos), vessel.heading, vessel.kind, CYAN, 1.0, true)

func local_map(world, vessel: Dictionary, system_index: int) -> void:
	var system: Dictionary = world.systems[system_index]
	celestial_markers(system, vessel)
	var tone := Color("91a7b7")
	for index in range(17):
		var angle := index * 2.399
		var rock_pos: Vector2 = system.field + Vector2.from_angle(angle) * (11.0 + index * 4)
		var rock := screen(rock_pos)
		var radius := (3 + index % 8) * zoom
		var outline := PackedVector2Array()
		for vertex in range(6):
			outline.append(rock + Vector2.from_angle(angle + vertex * TAU / 6) * radius * (0.76 + ((vertex + index) % 4) * 0.12))
		draw_colored_polygon(outline, Color("293c4b").lerp(Color("886d59"), (index % 5) * 0.18))
		outline.append(outline[0])
		draw_polyline(outline, Color("677387"), 1, true)
	ink(screen(system.field) + Vector2(-54, -79), "矿带  /  %s" % system.ore, GOLD, 13)
	for port_id in system.ports:
		var station: Dictionary = world.ports[port_id]
		var pos := screen(station.pos)
		tone = world.flag_color(station.flag)
		if not in_frame(pos):
			edge(pos, "港口", tone, vessel, station.pos)
			continue
		draw_arc(pos, 60 * zoom, 0, TAU, 48, Color(tone, 0.32), 1, true)
		draw_set_transform(pos, 0, Vector2.ONE * zoom)
		var skin := Pixels.station_texture(station.module, tone)
		draw_texture_rect(skin, Rect2(-57, -51, 114, 102), false,
			Color(0.65, 0.67, 0.73) if station.build > 0 else Color.WHITE)
		draw_set_transform(Vector2.ZERO)
		ink(pos + Vector2(36, -45), station.name, tone)
		ink(pos + Vector2(36, -26), "%s · %s" % [("施工 %s 日" % station.build) if station.build > 0 else world.MODULES[station.module], world.flag_name(station.flag)], Color("adb7bc"), 12)
		if not vessel.is_empty() and vessel.pos.distance_to(station.pos) < 75.0 and not vessel.locked and world.can_dock(vessel, station):
			tag(pos + Vector2(-34,63), "[E] 停靠", CYAN)
	for wreck in world.wrecks.values():
		if wreck.system != system_index:
			continue
		var pos := screen(wreck.pos)
		draw_set_transform(pos, float(int(wreck.at) % 8) * 0.4)
		draw_texture_rect(Pixels.ship_texture(0), Rect2(-15, -9, 30, 18), false, Color(0.51, 0.43, 0.38))
		draw_set_transform(Vector2.ZERO)
		ink(pos + Vector2(12, -8), "漂流残骸", Color("bc9b73"), 12)
		if not vessel.is_empty() and vessel.pos.distance_to(wreck.pos) < 80.0 and not vessel.locked:
			tag(pos + Vector2(18,19), "[G] 打捞", GOLD)
	for other in world.ships.values():
		if not Battle.available(other, system_index):
			continue
		var own: bool = other.id == vessel.get("id", 0)
		var pos := screen(other.pos)
		tone = CYAN if own else world.flag_color(other.flag)
		if not own and not vessel.is_empty() and world.enemy(vessel, other) and not in_frame(pos):
			edge(pos, "敌舰", Color("ef8f7b"), vessel, other.pos)
			continue
		if other.locked and not own:
			draw_arc(pos, 28, 0, TAU, 32, Color("e78275", 0.7), 1, true)
			draw_rect(Rect2(pos + Vector2(-20, -35), Vector2(40, 3)), Color("46323a"))
			draw_rect(Rect2(pos + Vector2(-20, -35), Vector2(40 * maxf(other.hp, 0) / world.HULL_HP[other.kind], 3)), Color("e78275"))
		draw_ship(pos, other.heading, other.kind, tone, zoom, own, other.battle.motion)
		var radius: float = Hulls.CLASS_RADIUS[Hulls.MODELS[other.kind].size] * zoom + 7
		if other.battle.shield:
			draw_circle(pos, radius, Color(tone, 0.09))
			draw_arc(pos, radius, 0, TAU, 44, Color(tone, 0.71), 2.0, true)
		if other.battle.overload > 0.0 or other.hp < Hulls.MODELS[other.kind].hp * 0.38:
			var phase := int(Time.get_ticks_msec() / 88 + other.id) % 4
			var spark := Pixels.effect_texture(1, phase, CYAN if other.battle.overload > 0.0 else GOLD)
			draw_texture_rect(spark, Rect2(pos + Vector2(-22 + phase * 6,-14),Vector2(40,40)), false)
		if not own:
			ink(pos + Vector2(13, 23), world.flag_name(other.flag), tone, 12)
			if other.locked or (world.oversees(other.owner) and other.job.get("kind","") == "护航"):
				tag(pos + Vector2(13,39), other.battle.ai, tone)
			if game.selected_target == other.id:
				draw_arc(pos, radius + 14, 0, TAU, 36, GOLD, 1, true)
				tag(pos + Vector2(-34,-radius-20), "集火目标", GOLD)
	if not in_frame(screen(system.field)):
		edge(screen(system.field), "矿带", GOLD, vessel, system.field)
	elif not vessel.is_empty() and vessel.pos.distance_to(system.field) < 95.0 and not vessel.locked:
		tag(screen(system.field) + Vector2(-31,61), "[G] 采掘", GOLD)
	for bolt in world.projectiles:
		if bolt.system != system_index:
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

func celestial_markers(region: Dictionary, vessel: Dictionary) -> void:
	var star: Dictionary = region.sun
	var color := Color(Celestial.STARS[star.type][1])
	var sun_pos := screen(star.pos)
	var radius: float = star.radius * zoom
	draw_circle(sun_pos, radius + 12.0, Color(color, 0.16))
	draw_circle(sun_pos, radius, Color(color, 0.85))
	draw_circle(sun_pos - Vector2(radius * 0.13, radius * 0.19), radius * 0.79, color.lightened(0.40))
	if in_frame(sun_pos):
		tag(sun_pos + Vector2(-22, radius + 19.0), Celestial.STARS[star.type][0], color)
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
	var scale_factor: float = Hulls.CLASS_SPRITE[model.size] * magnitude * (0.55 if galaxy else 1.0)
	draw_set_transform(pos.round(), heading, Vector2.ONE * scale_factor)
	if thrust.length() > 12.0:
		var phase := int(Time.get_ticks_msec() / 80) % 4
		var plume := Pixels.effect_texture(0, phase, CYAN)
		var offset: int = [3, 7, 9][mini(kind, 2)] if kind < 3 else 4
		for nozzle in [-offset, offset]:
			var exhaust := pos + (Vector2(-27, nozzle) * scale_factor).rotated(heading)
			draw_set_transform(exhaust, thrust.angle(), Vector2.ONE * scale_factor)
			draw_texture_rect(plume, Rect2(-28, -9, 30, 18), false)
		draw_set_transform(pos.round(), heading, Vector2.ONE * scale_factor)
	var livery := Color(model.paint).lerp(tone, 0.38)
	draw_texture(Pixels.ship_texture(kind, livery), Vector2(-32,-20))
	draw_set_transform(Vector2.ZERO)
	if own:
		draw_arc(pos, 34, 0.2, 1.3, 14, tone, 1, true)
		draw_arc(pos, 34, 3.35, 4.45, 14, tone, 1, true)

func tag(pos: Vector2, text: String, color: Color) -> void:
	var width := get_theme_default_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_rect(Rect2(pos - Vector2(4,12), Vector2(width + 8,16)), Color("0b1420",0.91))
	ink(pos, text, color, 12)

func in_frame(point: Vector2) -> bool:
	return Rect2(Vector2(24,25), size - Vector2(48,50)).has_point(point)

func edge(point: Vector2, name_text: String, tone: Color, vessel: Dictionary, at: Vector2) -> void:
	var axis := (point - size * 0.5).normalized()
	var bounds := size * 0.5 - Vector2(62,42)
	var scale_factor := minf(bounds.x / maxf(absf(axis.x), 0.0001), bounds.y / maxf(absf(axis.y), 0.0001))
	var pos := size * 0.5 + axis * scale_factor
	draw_colored_polygon(PackedVector2Array([pos + axis * 9, pos - axis * 4 + axis.orthogonal() * 5, pos - axis * 4 - axis.orthogonal() * 5]), tone)
	var text := name_text if vessel.is_empty() else "%s %d" % [name_text, vessel.pos.distance_to(at)]
	tag(pos - axis * 25 + Vector2(-16,4), text, tone)

func effects(system: int) -> void:
	for particle in particles:
		var effect: Dictionary = particle.event
		if effect.system != system:
			continue
		var age: float = particle.age
		var pos := screen(effect.pos)
		match effect.kind:
			"shield":
				var angle: float = effect.direction.angle() + PI
				draw_arc(pos, 11 + age * 47, angle - 1.1, angle + 1.1, 16, Color(CYAN, maxf(0.0, 0.87 - age * 1.9)), 2, true)
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

func meter(pos: Vector2, caption: String, amount: float, tone: Color, secondary: float = 0.0) -> void:
	ink(pos, caption, Color("b6c9d3"), 11)
	var origin := pos + Vector2(39,-8)
	draw_rect(Rect2(origin,Vector2(175,9)), Color("28374a"))
	var base := 175 * clampf(amount,0.0,1.0)
	draw_rect(Rect2(origin,Vector2(base,9)), tone)
	draw_rect(Rect2(origin + Vector2(base,0),Vector2(175 * clampf(secondary,0.0,1.0 - base / 175.0),9)), Color("e18565"))

func tactical_overlay(world, vessel: Dictionary) -> void:
	if vessel.is_empty():
		return
	var state: Dictionary = vessel.battle
	var start := Vector2(12,size.y - 117)
	var title_color := CYAN if state.overload <= 0.0 else Color("f8a975")
	draw_rect(Rect2(start,Vector2(237,106)),Color("081421",0.94))
	ink(start + Vector2(9,16), "旗舰状态    /    " + ("过载 %.1f 秒" % state.overload if state.overload > 0.0 else ("主动排散" if state.vent else "战备")), title_color, 12)
	meter(start + Vector2(9,33), "船体", vessel.hp / Hulls.MODELS[vessel.kind].hp, Color("7ad0ab"))
	meter(start + Vector2(9,47), "装甲", state.armor / Hulls.COMBAT[vessel.kind].armor, Color("e0b981"))
	meter(start + Vector2(9,61), "幅能", state.soft_flux / Hulls.capacity(vessel), Color("6faeca"), state.hard_flux / Hulls.capacity(vessel))
	if state.soft_flux + state.hard_flux > 0.0:
		var split := "%d 软 / %d 硬" % [roundi(state.soft_flux),roundi(state.hard_flux)]
		var width := get_theme_default_font().get_string_size(split,HORIZONTAL_ALIGNMENT_LEFT,-1,9).x
		var center := start + Vector2(134.0 - width * 0.5,60.0)
		draw_rect(Rect2(center - Vector2(2,9),Vector2(width + 4,10)), Color("081421",0.82))
		ink(center,split,Color("e3f2ee"),9)
	for group in range(1,4):
		var cooldown := 0.0
		var equipped := false
		for index in range(vessel.fit.groups.size()):
			if vessel.fit.groups[index] == group and not str(vessel.fit.weapons[index]).is_empty():
				equipped = true
				cooldown = maxf(cooldown, state.cooldowns[index])
		var label := "—" if not equipped else ("%.1fs" % cooldown if cooldown > 0.0 else "就绪")
		ink(start + Vector2(9 + (group - 1) * 74,79), "%s%s %s" % [group,"自" if vessel.fit.auto[group-1] else "",label], GOLD if state.group == group else Color("88a1b1"), 11)
	ink(start + Vector2(9,97), "F  %s · %s" % [Hulls.SYSTEM_NAMES[Hulls.COMBAT[vessel.kind].system],
		("激活 %.1fs" % state.system_time) if state.system_time > 0.0 else (("%.1fs" % state.system_cd) if state.system_cd > 0.0 else "就绪")], CYAN, 11)
	var radar := Vector2(size.x-86,88)
	draw_rect(Rect2(radar - Vector2(76,76),Vector2(152,152)),Color("081421",0.93))
	for ring in [24,49,68]:
		draw_arc(radar,ring,0,TAU,44,Color("436479",0.67),1,true)
	draw_line(radar - Vector2(68,0),radar + Vector2(68,0),Color("30465b"))
	draw_line(radar - Vector2(0,68),radar + Vector2(0,68),Color("30465b"))
	for port_id in world.systems[vessel.system].ports:
		var station: Dictionary = world.ports[port_id]
		draw_rect(Rect2(radar + ((Vector2(station.pos)-Vector2(vessel.pos))*0.085).limit_length(65) - Vector2(2,2),Vector2(4,4)), GOLD)
	for ship in world.ships.values():
		if ship.id != vessel.id and Battle.available(ship,vessel.system):
			var point := radar + ((Vector2(ship.pos)-Vector2(vessel.pos))*0.085).limit_length(65)
			draw_circle(point, 2.4, Color("ef8f7b") if world.enemy(vessel,ship) else CYAN)
	draw_circle(radar,3,Color("d7f7e5"))

func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	backdrop()
	if game == null or game.world.player == 0:
		return
	var world = game.world
	var vessel: Dictionary = world.ride()
	var system_index: int = game.current_system()
	if galaxy:
		galaxy_map(world, vessel)
	else:
		local_map(world, vessel, system_index)
		tactical_overlay(world, vessel)
	draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), Color("385066"), false)
