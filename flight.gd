extends RefCounted

const Hulls = preload("res://hull_catalog.gd")
const Battle = preload("res://combat.gd")
const Economy = preload("res://economy.gd")
const Celestial = preload("res://celestial.gd")

var game
var accumulated := 0.0

func reset(keep_battle: bool = false) -> void:
	var vessel: Dictionary = game.world.ride()
	if not vessel.is_empty() and not keep_battle:
		vessel.battle.motion = Vector2.ZERO
		Battle.shield(vessel, false)
	accumulated = 0.0
	game.world.projectiles.clear()
	game.waypoint_live = false

func target(vessel: Dictionary, find_range: float) -> int:
	var nearest := find_range
	var found := 0
	var world = game.world
	for other in world.ships.values():
		if other.id == vessel.id or not Battle.available(other, vessel.system) or not world.enemy(vessel, other):
			continue
		var gap: float = vessel.pos.distance_to(other.pos)
		if gap < nearest:
			nearest = gap
			found = other.id
	return found

func change_layer() -> void:
	var world = game.world
	var vessel: Dictionary = world.ride()
	if vessel.is_empty() or vessel.dock != 0 or vessel.locked:
		game.say("先离港，并脱离交火。")
		return
	if game.galaxy:
		var index := nearby_system(vessel)
		if index < 0:
			game.say("靠近星系信标后才能进入。")
			return
		vessel.system = index
		vessel.pos = Celestial.gravity_point(world.systems[index])
		world.mark_seen(index)
	else:
		var region: Dictionary = world.systems[vessel.system]
		if not Celestial.at_gravity_point(region, vessel.pos):
			var distance: float = vessel.pos.distance_to(Celestial.gravity_point(region))
			game.say("无法跃迁：距本星系引力点 %d，进入 %d 范围后再按 M。" % [ceili(distance), Celestial.JUMP_RANGE])
			return
		vessel.galpos = world.systems[vessel.system].pos
		vessel.raid = world.NEUTRAL
		for other in world.ships.values():
			if escort(other, vessel) and other.system == vessel.system and other.dock == 0:
				other.layer = true
				other.galpos = vessel.galpos
	game.galaxy = not game.galaxy
	vessel.layer = game.galaxy
	if not game.galaxy:
		var formation := 0
		for other in world.ships.values():
			if escort(other, vessel) and other.layer:
				other.layer = false
				other.system = vessel.system
				other.pos = vessel.pos + Vector2(-82 - floori(formation / 2.0) * 52.0, (38 + formation * 5) * (-1 if formation % 2 == 0 else 1))
				if other.battle.order == 3:
					other.battle.retired = false
					other.battle.order = 1
					other.battle.focus = 0
					other.battle.ai = "护卫舰位"
				formation += 1
	reset()
	game.say("已跃入超空间。靠近目的星系信标后，按 M 跃入该星系的引力点。" if game.galaxy else "已从引力点进入 " + world.systems[vessel.system].name + "。")
	game.refresh()

func nearby_system(vessel: Dictionary) -> int:
	var world = game.world
	var closest := Celestial.BEACON_RANGE
	var result := -1
	for index in range(world.systems.size()):
		var gap: float = vessel.galpos.distance_to(world.systems[index].pos)
		if gap < closest or (result < 0 and gap == closest):
			closest = gap
			result = index
	return result

func nearby_port(vessel: Dictionary) -> int:
	if game.galaxy:
		return 0
	var world = game.world
	var gap := 75.0
	var result := 0
	for port_id in world.systems[vessel.system].ports:
		var distance: float = vessel.pos.distance_to(world.ports[port_id].pos)
		if distance < gap:
			gap = distance
			result = port_id
	return result

func dock() -> void:
	var world = game.world
	var vessel: Dictionary = world.ride()
	if vessel.is_empty():
		game.say("先从「资产」选择停在本站的自有船只。")
		return
	if vessel.locked:
		game.say("交火中不能停靠。")
		return
	if vessel.dock != 0:
		var original_port: int = vessel.dock
		var fine := Economy.inspect_departure(world,vessel)
		if fine > 0:
			game.say("离港盘查：扣押违禁品并罚款 %d。" % fine)
		world.depart(vessel)
		vessel.pos += Vector2(-50, 0)
		var offset := 0
		for other in world.ships.values():
			if escort(other, vessel) and other.dock == original_port:
				world.depart(other)
				other.battle.retired = false
				other.battle.order = 1
				other.battle.focus = 0
				other.battle.ai = "护卫舰位"
				other.pos += Vector2(-70 - offset * 10, 54 + offset * 28)
				offset += 1
	else:
		var port_id := nearby_port(vessel)
		if port_id == 0:
			game.say("附近没有港口；靠近泊位后再申请停靠。")
			return
		if not Hulls.model_limit(world.ports[port_id], vessel.kind):
			game.say("本站泊位太小，需要可接收%s的船坞。" % Hulls.CLASS_NAMES[Hulls.MODELS[vessel.kind].size])
			return
		if not world.berth(vessel, port_id):
			game.say("正规港口请开启应答器（T）。" if not vessel.transponder else "该港拒绝停靠。")
			return
		for other in world.ships.values():
			if escort(other, vessel) and other.system == vessel.system and other.dock == 0 and not other.layer and not other.locked:
				if other.battle.retired or other.pos.distance_to(vessel.pos) < 620.0:
					if world.berth(other, port_id):
						other.battle.retired = false
						other.battle.order = 1
						other.battle.focus = 0
						other.battle.ai = "护卫舰位"
		game.tab = "港口"
		world.combat_event("dock",vessel.pos,vessel.system)
		if not game.test_profile:
			game.save_game(game.AUTO, true)
	reset()
	game.refresh()

func salvage() -> void:
	var world = game.world
	var vessel: Dictionary = world.ride()
	if vessel.is_empty() or game.galaxy or vessel.dock != 0 or vessel.locked:
		return
	var system: Dictionary = world.systems[vessel.system]
	for wreck_id in world.wrecks.keys():
		var cache: Dictionary = world.wrecks[wreck_id]
		if cache.system == vessel.system and vessel.pos.distance_to(cache.pos) < 80:
			var total := 0
			var recovered := 0
			if not cache.get("stripped", false) and cache.stock[1] > 0:
				recovered = Hulls.MODELS[vessel.kind].salvage
			for ware in [1, 2]:
				var moved := mini(world.cargo_free(vessel), cache.stock[ware])
				cache.stock[ware] -= moved
				vessel.cargo[ware] += moved
				total += moved
			if cache.stock == [0, 0, 0]:
				world.wrecks.erase(wreck_id)
			var extra := mini(recovered, world.cargo_free(vessel))
			vessel.cargo[1] += extra
			if extra > 0:
				cache.stripped = true
			game.say("打捞 %d 单位货物。%s" % [total, "回收臂另拆出 %d 合金。" % extra if extra > 0 else ""])
			game.update_header()
			return
	if vessel.pos.distance_to(system.field) < 95:
		var moved := mini(Hulls.MODELS[vessel.kind].mine, mini(world.cargo_free(vessel), system.ore))
		system.ore -= moved
		vessel.cargo[0] += moved
		game.say("采得 %d 单位矿石。" % moved)
		game.update_header()
		world.combat_event("mine",vessel.pos,vessel.system)
	elif Celestial.survey(world,vessel):
		game.say(world.chronicle[0][1])
		game.update_header()
	else:
		game.say("靠近矿带、残骸或行星，再按 G。")

func tow() -> void:
	var world = game.world
	var vessel: Dictionary = world.ride()
	if vessel.is_empty() or vessel.locked or vessel.dock != 0:
		return
	var home_id: int = world.systems[0].ports[0]
	if not world.can_dock(vessel, world.ports[home_id]):
		var closest := INF
		for station in world.ports.values():
			if station.build == 0 and world.can_dock(vessel, station):
				var distance: float = world.distance(vessel.system, station.system)
				if distance < closest:
					closest = distance
					home_id = station.id
		if not is_finite(closest):
			game.say("没有可接收本舰的友好泊位。")
			return
	vessel.layer = false
	vessel.raid = world.NEUTRAL
	vessel.fuel = maxf(vessel.fuel, 12)
	world.credit(world.player, -mini(world.active().wallet, 60))
	world.berth(vessel, home_id)
	world.tick(18)
	game.galaxy = false
	game.tab = "港口"
	reset()
	game.say("拖船已抵达%s（18 日，最多 60 信用点）。" % world.ports[home_id].name)
	game.refresh()

func auto_battle() -> void:
	var world = game.world
	var vessel: Dictionary = world.ride()
	if vessel.is_empty() or vessel.dock != 0 or game.galaxy or vessel.locked:
		game.say("只能在交火前自动结算。")
		return
	var enemy_id := target(vessel, 350)
	if enemy_id == 0:
		game.say("350 距离内没有可结算的敌船。")
		return
	var nearby := 0
	for other in world.ships.values():
		if Battle.available(other,vessel.system) and other.id != vessel.id and vessel.pos.distance_to(other.pos) < 420:
			nearby += 1
	if nearby != 1:
		game.say("只允许结算孤立的一对一遭遇。")
		return
	var foe: Dictionary = world.ships[enemy_id]
	var strength: float = float(Hulls.MODELS[foe.kind].power) / Hulls.MODELS[vessel.kind].power
	var damage := roundi(foe.hp * (0.52 if world.active().origin == 0 else 0.65) * clampf(sqrt(strength), 0.4, 2.5))
	if vessel.hp <= damage:
		game.say("预计需承受 %d 伤害，当前船体不足；请撤离或手操。" % damage)
		return
	vessel.hp -= damage
	world.destruction(enemy_id, world.player)
	game.say("自动结算：击毁目标，船体损伤 %d；残骸仍在原处。" % damage)
	game.assets_changed()

func escort(other: Dictionary, lead: Dictionary) -> bool:
	var world = game.world
	return other.id != lead.id and world.oversees(other.owner) and other.captain != 0 and other.job.get("kind", "") == "护航"

func issue(order: int, focus: int = 0) -> int:
	var world = game.world
	var lead: Dictionary = world.ride()
	if lead.is_empty() or lead.dock != 0 or game.galaxy or order not in range(Battle.ORDERS.size()):
		return 0
	var designated: Dictionary = world.ships.get(focus, {})
	if order == 2 and (designated.is_empty() or not Battle.available(designated, lead.system) or not world.enemy(lead, designated)):
		return 0
	var count := 0
	for other in world.ships.values():
		if escort(other, lead) and Battle.available(other, lead.system):
			other.battle.order = order
			other.battle.focus = focus if order == 2 else 0
			count += 1
	return count

func select_group(vessel: Dictionary, group: int, toggle_auto: bool) -> bool:
	if group not in [1,2,3] or group not in vessel.fit.groups:
		return false
	if toggle_auto:
		vessel.fit.auto[group-1] = not vessel.fit.auto[group-1]
	else:
		vessel.battle.group = group
	return true

func target_at(lead: Dictionary, aim: Vector2, max_distance: float = 52.0) -> int:
	var world = game.world
	var found := 0
	var nearest := max_distance
	for other in world.ships.values():
		if other.id == lead.id or not Battle.available(other, lead.system) or not world.enemy(lead, other):
			continue
		var gap: float = aim.distance_to(other.pos)
		if gap < nearest:
			found = other.id
			nearest = gap
	return found

func fire(vessel: Dictionary, aim: Vector2) -> int:
	var world = game.world
	var id := target_at(vessel, aim, 23.0)
	if id != 0:
		var other: Dictionary = world.ships[id]
		aim = other.pos + other.battle.motion * (vessel.pos.distance_to(other.pos) / 510.0)
	return Battle.group_fire(world, vessel, vessel.battle.group, aim, id)

func maneuver(other: Dictionary, direction: Vector2, delta: float, heading: float) -> void:
	var thrust := direction.limit_length() * 117.0 * float(Hulls.MODELS[other.kind].speed) * Hulls.crew_efficiency(other)
	other.battle.motion = other.battle.motion.move_toward(thrust, 260.0 * delta)
	other.pos = (other.pos + other.battle.motion * delta).clamp(Vector2(-1320,-900), Vector2(1320,900))
	other.heading = rotate_toward(other.heading, heading, 4.6 * delta)

func drive_ai(other: Dictionary, lead: Dictionary, delta: float) -> void:
	var world = game.world
	var state: Dictionary = other.battle
	var ally := escort(other, lead)
	var enemy_id := 0
	if ally:
		if state.order == 3:
			state.ai = "战术撤退"
			state.shield = false
			var escape := (Vector2(other.pos) - Vector2(lead.pos)).normalized()
			if escape.is_zero_approx():
				escape = Vector2.LEFT
			maneuver(other, escape, delta, escape.angle())
			if other.pos.distance_to(lead.pos) > 610.0:
				state.retired = true
				other.locked = false
			return
		var focus: Dictionary = world.ships.get(state.focus, {})
		if state.order == 2 and not focus.is_empty() and Battle.available(focus, lead.system) and world.enemy(other, focus):
			enemy_id = focus.id
		elif state.order != 1 or other.pos.distance_to(lead.pos) <= 195.0:
			enemy_id = target(other, 500.0 if state.order == 0 else 270.0)
		if state.order == 1 and enemy_id != 0 and world.ships[enemy_id].pos.distance_to(lead.pos) > 325.0:
			enemy_id = 0
	elif world.enemy(other, lead) and (lead.locked or other.locked) and other.pos.distance_to(lead.pos) < 585.0:
		enemy_id = target(other, 490.0)
	other.locked = enemy_id != 0
	if enemy_id == 0:
		state.ai = "护卫舰位" if ally else "巡航"
		Battle.shield(other, false)
		if ally:
			var side := -1.0 if int(other.id) % 2 == 0 else 1.0
			var anchor := Vector2(lead.pos) + Vector2(-70 - int(other.id) % 3 * 35, 75 * side).rotated(lead.heading)
			var gap := anchor - Vector2(other.pos)
			maneuver(other, gap / 75.0, delta, lead.heading)
		else:
			state.motion = Vector2.ZERO
		return
	var foe: Dictionary = world.ships[enemy_id]
	var gap := Vector2(foe.pos) - Vector2(other.pos)
	var axis := gap.normalized()
	var mode := Battle.ai_mode(other, gap.length())
	state.ai = mode
	if mode == "降盾散热":
		Battle.shield(other, false)
		if gap.length() > 210.0 and Battle.fraction(other) > 0.38:
			Battle.vent(other)
		maneuver(other, -axis + axis.orthogonal() * 0.22, delta, gap.angle())
		return
	var lateral := axis.orthogonal() * (-1.0 if int(other.id) % 2 == 0 else 1.0)
	var move := axis * 0.90 + lateral * 0.28 if mode == "压进" else lateral * 0.64 + axis * (0.20 if gap.length() > 152.0 else -0.52)
	maneuver(other, move, delta, gap.angle())
	var imminent := false
	for projectile in world.projectiles:
		if projectile.system == other.system and world.enemy(other, projectile) and projectile.pos.distance_to(other.pos) < 128.0 and projectile.vel.dot(other.pos - projectile.pos) > 0.0:
			imminent = true
			break
	Battle.shield(other, imminent and Battle.fraction(other) < 0.58)
	if Battle.fraction(other) < 0.67:
		for group in [1, 2, 3]:
			Battle.group_fire(world, other, group, foe.pos + foe.battle.motion * (gap.length() / 510.0), enemy_id)

func combat(vessel: Dictionary, delta: float, aiming: bool = false, aim: Vector2 = Vector2.ZERO) -> void:
	var world = game.world
	var threat := target(vessel, 255)
	var entering: bool = threat != 0 and not vessel.locked
	vessel.locked = threat != 0 or (vessel.locked and target(vessel, 520) != 0)
	if entering:
		game.waypoint_live = false
		game.say("敌舰已接近：左键开火，Shift 护盾，V 排散，Tab 下达舰队指令。")
	Battle.tick(vessel, delta)
	for other in world.ships.values():
		if other.id == vessel.id or not Battle.available(other, vessel.system):
			continue
		Battle.tick(other, delta)
		drive_ai(other, vessel, delta)
		Battle.point_defense(world, other)
	if aiming:
		fire(vessel, aim)
	var auto_target := target(vessel, 510.0)
	if auto_target != 0:
		var foe: Dictionary = world.ships[auto_target]
		for slot in range(vessel.fit.auto.size()):
			if vessel.fit.auto[slot]:
				Battle.group_fire(world, vessel, slot + 1, foe.pos + foe.battle.motion * (vessel.pos.distance_to(foe.pos) / 510.0), auto_target)
	Battle.point_defense(world, vessel)
	Battle.project(world, vessel.system, delta)

func step(delta: float, controls: Vector2 = Vector2.ZERO, shield_held: bool = false, aiming: bool = false, aim: Vector2 = Vector2.ZERO, cursor: bool = false) -> void:
	var world = game.world
	if world.succession or world.attention or game.speed == 0:
		return
	var vessel: Dictionary = world.ride()
	var airborne: bool = not vessel.is_empty() and vessel.dock == 0
	var manual: bool = airborne and not game.waypoint_live
	var engaged: bool = airborne and not game.galaxy and target(vessel, 260) != 0
	if manual or engaged:
		game.speed = 1
	if airborne:
		var state: Dictionary = vessel.battle
		if not controls.is_zero_approx():
			game.waypoint_live = false
			game.speed = 1
		elif game.waypoint_live and not engaged:
			var gap: Vector2 = game.waypoint - (vessel.galpos if game.galaxy else vessel.pos)
			if gap.length() < 13:
				game.waypoint_live = false
				state.motion = Vector2.ZERO
			else:
				controls = gap.normalized()
		var model: Dictionary = Hulls.MODELS[vessel.kind]
		var flight_speed: float = (105.0 if game.galaxy else 165.0) * model.speed * Hulls.crew_efficiency(vessel)
		if Hulls.COMBAT[vessel.kind].system == "boost" and state.system_time > 0.0:
			flight_speed *= 1.68
		var field := "galpos" if game.galaxy else "pos"
		var pace: float = minf(game.speed, 3.0) if game.waypoint_live else 1.0
		state.motion = state.motion.move_toward(controls.normalized() * flight_speed, 390 * model.speed * delta)
		if game.galaxy and vessel.fuel <= 0:
			state.motion = Vector2.ZERO
		vessel[field] += state.motion * delta * pace
		if game.galaxy:
			Battle.tick(vessel, delta)
			vessel.fuel = maxf(0, vessel.fuel - state.motion.length() * 0.021 * delta * pace * model.fuel)
			for other in world.ships.values():
				if other.owner == world.player and other.layer and other.job.get("kind", "") == "护航":
					other.galpos = vessel.galpos + Vector2(-22, 22)
		else:
			vessel.pos = vessel.pos.clamp(Vector2(-1320, -900), Vector2(1320, 900))
		if not game.galaxy and cursor and Vector2(vessel.pos).distance_squared_to(aim) > 48.0:
			vessel.heading = rotate_toward(vessel.heading, (aim - Vector2(vessel.pos)).angle(), (5.4 - Hulls.MODELS[vessel.kind].size * 0.8) * delta)
		elif state.motion.length() > 8:
			vessel.heading = lerp_angle(vessel.heading, state.motion.angle(), minf(1, delta * 7))
		Battle.shield(vessel, not game.galaxy and shield_held)
		if not game.galaxy:
			combat(vessel, delta, aiming, aim)
	elif not vessel.is_empty():
		Battle.shield(vessel, false)
		Battle.tick(vessel, delta)
	if not world.attention and not world.succession:
		accumulated += delta * [0, 4, 14, 52, 160, 420][game.speed]
		var elapsed := floori(accumulated)
		if elapsed > 0:
			accumulated -= elapsed
			world.tick(elapsed)
