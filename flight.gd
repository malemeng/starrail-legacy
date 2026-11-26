extends RefCounted

const Hulls = preload("res://hull_catalog.gd")
const Battle = preload("res://combat.gd")
const HullContacts = preload("res://scripts/battle/hull_contacts.gd")
const Economy = preload("res://economy.gd")
const Celestial = preload("res://celestial.gd")
const Hyperspace = preload("res://scripts/campaign/hyperspace.gd")
const Sensors = preload("res://scripts/battle/sensors.gd")
const Society = preload("res://scripts/campaign/society.gd")
const Outlaws = preload("res://scripts/campaign/outlaws.gd")
const StationGeometry = preload("res://scripts/models/station_geometry.gd")
const FLIGHT_DAYS_PER_SECOND := 1.0
const PORT_DAYS_PER_SECOND := [0.0, FLIGHT_DAYS_PER_SECOND, 3.0, 9.0, 20.0, 45.0]
const CRUISE_SPEED_SCALE := 125.0
const COMBAT_SPEED_SCALE := 88.0

var game
var accumulated := 0.0
var civil_motion := {}
var tactical_escorts := {}
var physics_frame := 0
var sensor_reading: Dictionary = {}
var sensor_countdown := 0.0
var scanning_threats := false
var autopilot_engaged := false

func reset(keep_battle: bool = false) -> void:
	var vessel: Dictionary = game.world.ride()
	if vessel.get("layer", false):
		game.world.stream_hyperspace(vessel.galpos)
	if not vessel.is_empty() and not keep_battle:
		vessel.battle.motion = Vector2.ZERO
		Battle.shield(vessel, false)
	accumulated = 0.0
	civil_motion.clear()
	sensor_countdown = 0.0
	sensor_reading.clear()
	game.world.projectiles.clear()
	game.waypoint_live = false
	game.waypoint_tracking = Callable()
	game.waypoint_arrived = Callable()

func target(vessel: Dictionary, find_range: float, first_visible: bool = false) -> int:
	var nearest := find_range * find_range
	var found := 0
	var world = game.world
	var origin: Vector2 = vessel.pos
	var id: int = vessel.id
	var system_id: int = vessel.system
	for other in world.ships.values():
		var gap := origin.distance_squared_to(other.pos)
		if gap >= nearest or other.id == id or not Battle.available(other, system_id) or not world.enemy(vessel, other):
			continue
		if not visible_contact(vessel, other):
			continue
		if first_visible:
			return other.id
		nearest = gap
		found = other.id
	return found

func visible_contact(vessel: Dictionary, other: Dictionary) -> bool:
	if sensor_reading.is_empty():
		sensor_reading = Sensors.fleet(game.world, vessel)
	return Sensors.seen(vessel,other,sensor_reading)

func sensor_ping() -> bool:
	var vessel: Dictionary = game.world.ride()
	if vessel.is_empty() or vessel.dock != 0:
		return false
	vessel.ping = 3.5
	sensor_reading = Sensors.fleet(game.world,vessel)
	if game.audio != null:
		game.audio.play("ping")
	game.say("已发射主动传感器脉冲：探测范围扩大，自身信号暴露。")
	return true

func ai_target(vessel: Dictionary, reach: float) -> int:
	var world = game.world
	var state: Dictionary = vessel.battle
	var current: Dictionary = world.ships.get(state.get("target_id", 0), {})
	var organization := Outlaws.id_for(vessel) if vessel.has("organization") else ""
	var guarding := organization == Outlaws.CULT
	if state.retarget_delay > 0.0 and not current.is_empty() and Battle.available(current, vessel.system) and world.enemy(vessel,current):
		if Vector2(vessel.pos).distance_squared_to(current.pos) < reach * reach and (not guarding or Outlaws.permits_target(vessel,current)):
			return current.id
	var best: Dictionary = {}
	var high := 0.0
	var current_score := 0.0
	var player_ship: int = world.ride().get("id",0)
	for other in world.ships.values():
		if not Battle.available(other, vessel.system) or not world.enemy(vessel, other):
			continue
		var distance: float = vessel.pos.distance_to(other.pos)
		if distance > reach or (guarding and not Outlaws.permits_target(vessel,other)):
			continue
		if not other.locked and not Sensors.npc_contact(vessel,other,float(sensor_reading.get("profile",-1.0)) if other.id == player_ship else -1.0):
			continue
		var role: String = vessel.get("fleet_role", "ATTACK")
		var size: int = Hulls.MODELS[other.kind].size
		var priority := (1.55 if size <= 1 else 0.7) if role == "INTERCEPT" else ((1.5 if size >= 2 else 0.7) if role == "BOMBARD" else 1.0)
		if other.battle.overload > 0.0 or other.battle.vent:
			priority *= 1.45
		elif other.hp < Hulls.MODELS[other.kind].hp * 0.35:
			priority *= 1.25
		if Battle.phased(other):
			priority *= 0.6
		if organization == Outlaws.PIRATES:
			priority *= Outlaws.cargo_priority(world,other)
		var score := priority / maxf(distance, 25.0)
		if other.id == current.get("id", 0):
			current_score = score
		if score > high:
			high = score
			best = other
	if current_score > 0.0 and (state.retarget_delay > 0.0 or high < current_score * 1.35):
		return current.id
	var chosen: int = best.get("id", 0)
	if chosen != state.target_id:
		state.target_id = chosen
		state.retarget_delay = 1.5
	return chosen

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
		var entry := Celestial.gravity_point(world.systems[index])
		var blocked := false
		for other in world.ships.values():
			if other.id != vessel.id and other.system == index and other.dock == 0 and not other.layer and other.hp > 0.0 and other.pos.distance_squared_to(entry) < 42.0 * 42.0:
				blocked = true
				break
		vessel.pos = Celestial.gravity_arrival(world, index, vessel.id) if blocked else entry
		world.mark_seen(index)
	else:
		var region: Dictionary = world.systems[vessel.system]
		if not Celestial.at_gravity_point(region, vessel.pos):
			var distance: float = vessel.pos.distance_to(Celestial.gravity_point(region))
			game.say("无法跃迁：距本星系引力点 %d，进入 %d 范围后再按 M。" % [ceili(distance), Celestial.JUMP_RANGE])
			return
		var builder: Dictionary = world.ConstructionContract.active_ship(world)
		if not builder.is_empty() and world.ConstructionContract.is_escort(builder,vessel,world.player) and builder.system == vessel.system and builder.dock == 0 and builder.pos.distance_to(vessel.pos) > 235.0:
			game.say("工程舰正在接近引力点。待它进入编队后再跃迁。")
			return
		vessel.galpos = world.systems[vessel.system].pos
		vessel.raid = world.NEUTRAL
		for other in world.ships.values():
			if escort(other, vessel) and other.system == vessel.system and other.dock == 0:
				other.layer = true
				other.galpos = vessel.galpos
	game.galaxy = not game.galaxy
	vessel.layer = game.galaxy
	Society.offer(world, "on_hyperspace_jump", {"system": vessel.system})
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
	var closest := Celestial.BEACON_RANGE * Celestial.BEACON_RANGE
	var result := -1
	var around := Rect2(vessel.galpos, Vector2.ZERO).grow(Celestial.BEACON_RANGE + 1.0)
	for index: int in world.systems_in(around):
		var gap: float = vessel.galpos.distance_squared_to(world.systems[index].pos)
		if gap < closest or (gap == closest and (result < 0 or index < result)):
			closest = gap
			result = index
	return result

func nearby_port(vessel: Dictionary) -> int:
	if game.galaxy:
		return 0
	var world = game.world
	var gap := StationGeometry.docking_range(vessel.kind)
	var result := 0
	for port_id in world.systems[vessel.system].ports:
		var distance: float = vessel.pos.distance_to(world.ports[port_id].pos)
		if distance <= gap:
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
		var offset := 0
		for other in world.ships.values():
			if escort(other, vessel) and other.dock == original_port:
				world.depart(other)
				other.battle.retired = false
				other.battle.order = 1
				other.battle.focus = 0
				other.battle.ai = "护卫舰位"
				other.pos = StationGeometry.departure(world.ports[original_port], other.kind, offset)
				offset += 1
	else:
		var port_id := nearby_port(vessel)
		if port_id == 0 and not game.galaxy:
			port_id = world.PlanetPorts.landing_at(world,vessel)
		if port_id == 0:
			game.say("附近没有港口；靠近泊位后再申请停靠。")
			return
		if not Hulls.berth_fits(vessel,world.ports[port_id]):
			game.say("本站泊位太小，需要可接收%s的船坞。" % Hulls.CLASS_NAMES[Hulls.MODELS[vessel.kind].size])
			return
		if not world.berth(vessel, port_id):
			game.say("正规港口请开启应答器（T）。" if not vessel.transponder else "该港拒绝停靠。")
			return
		for other in world.ships.values():
			if escort(other, vessel) and other.system == vessel.system and other.dock == 0 and not other.layer and not other.locked:
				if other.battle.retired or other.pos.distance_to(vessel.pos) < 620.0:
					if world.berth(other, port_id):
						var orders: Array = other.get("order_queue",[])
						if not orders.is_empty() and orders.front().kind == "escort_to" and orders.front().port == port_id:
							Economy.step_order(world,other)
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
		if cache.system == vessel.system and vessel.pos.distance_to(cache.pos) < 95 and cache.stock.max() > 0:
			var total := 0
			var arm := maxi(int(Hulls.MODELS[vessel.kind].salvage), 2 + int(Hulls.MODELS[vessel.kind].size) * 2)
			for ware in mini(cache.stock.size(), vessel.cargo.size()):
				var cap: int = arm if ware == Economy.Industry.SCRAP else int(cache.stock[ware])
				var moved := mini(world.cargo_free(vessel), mini(cache.stock[ware], cap))
				cache.stock[ware] -= moved
				vessel.cargo[ware] += moved
				total += moved
			if not cache.has("hull_id") and cache.stock.max() <= 0:
				world.wrecks.erase(wreck_id)
			game.say("打捞 %d 单位物资。" % total if total > 0 else "货舱已满，无法继续打捞。")
			game.update_header()
			game.assets_changed()
			return
	if vessel.pos.distance_to(system.field) < 95:
		var moved := mini(Hulls.MODELS[vessel.kind].mine, mini(world.cargo_free(vessel), system.ore))
		system.ore -= moved
		vessel.cargo[0] += moved
		if moved > 0:
			Economy.record_mining(world, vessel.system, moved)
		game.say("采得 %d 单位矿石。" % moved)
		game.update_header()
		world.combat_event("mine",vessel.pos,vessel.system)
	elif Celestial.survey(world,vessel):
		game.say(world.chronicle[0][1])
		game.update_header()
	else:
		game.say("靠近矿带、残骸或行星，再按 G。")

func field_repair() -> bool:
	var world = game.world
	var vessel: Dictionary = world.ride()
	if vessel.is_empty() or game.galaxy or vessel.dock != 0 or vessel.locked:
		game.say("只能在太空中脱离交火后进行野外抢修。")
		return false
	var targets: Array[Dictionary] = [vessel]
	for other in world.ships.values():
		if other.id != vessel.id and other.system == vessel.system and other.dock == 0 and not other.layer and escort(other, vessel):
			targets.append(other)
	var hull_repaired := 0.0
	var armor_repaired := 0.0
	var used := {Economy.Industry.Ware.HULL_PARTS: 0, Economy.Industry.Ware.ALLOY: 0, Economy.Industry.Ware.SCRAP: 0}
	var tiers := [
		[Economy.Industry.Ware.HULL_PARTS, 1.0, 22.0, 18.0],
		[Economy.Industry.Ware.ALLOY, 0.9, 14.0, 12.0],
		[Economy.Industry.Ware.SCRAP, 0.75, 8.0, 6.0],
	]
	for ship in targets:
		Battle.ensure_state(ship)
		var model: Dictionary = Hulls.MODELS[ship.kind]
		var max_hp := float(model.hp)
		var max_armor := float(Hulls.COMBAT[ship.kind].armor)
		var eff := Hulls.crew_efficiency(ship)
		var ship_used := 0
		for tier in tiers:
			var ware: int = tier[0]
			var cap_ratio: float = tier[1]
			var hp_per_unit: float = tier[2] * eff
			var armor_per_unit: float = tier[3] * eff
			while int(vessel.cargo[ware]) > 0 and (ship.hp < max_hp * cap_ratio - 0.5 or ship.battle.armor < max_armor * cap_ratio - 0.5):
				vessel.cargo[ware] -= 1
				used[ware] += 1
				ship_used += 1
				var dh := minf(hp_per_unit, maxf(0.0, max_hp * cap_ratio - float(ship.hp)))
				var da := minf(armor_per_unit, maxf(0.0, max_armor * cap_ratio - float(ship.battle.armor)))
				ship.hp += dh
				Battle.Defenses.repair_armor(ship, da)
				hull_repaired += dh
				armor_repaired += da
		if ship_used == 0:
			var emergency_hp := minf(maxf(18.0, max_hp * 0.22) * eff, maxf(0.0, max_hp * 0.45 - float(ship.hp)))
			var emergency_armor := minf(maxf(12.0, max_armor * 0.20) * eff, maxf(0.0, max_armor * 0.40 - float(ship.battle.armor)))
			if emergency_hp > 0.5 or emergency_armor > 0.5:
				ship.hp += emergency_hp
				Battle.Defenses.repair_armor(ship, emergency_armor)
				hull_repaired += emergency_hp
				armor_repaired += emergency_armor
	if hull_repaired < 0.5 and armor_repaired < 0.5:
		var has_parts := int(vessel.cargo[Economy.Industry.Ware.HULL_PARTS]) + int(vessel.cargo[Economy.Industry.Ware.ALLOY]) + int(vessel.cargo[Economy.Industry.Ware.SCRAP]) > 0
		game.say("舰队状态已达当前抢修上限。" if has_parts else "无修理材料（需船体部件/合金/废料），无料应急抢修上限为 45% 船体。")
		return false
	world.tick(1)
	game.say("野外抢修完成（1 日）：恢复 %.0f 船体、%.0f 护甲，消耗部件 %d / 合金 %d / 废料 %d。" % [
		hull_repaired, armor_repaired,
		used[Economy.Industry.Ware.HULL_PARTS], used[Economy.Industry.Ware.ALLOY], used[Economy.Industry.Ware.SCRAP]])
	game.update_header()
	game.assets_changed()
	return true

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
	if not world.berth(vessel, home_id):
		game.say("拖航未出发：请先开启应答器（T）。" if not vessel.transponder and world.is_regular(world.ports[home_id]) else "拖航未出发：目的港拒绝停靠。")
		return
	vessel.raid = world.NEUTRAL
	vessel.fuel = maxf(vessel.fuel, 12)
	world.credit(world.player, -mini(world.active().wallet, 60),vessel,"拖航")
	world.tick(18)
	game.galaxy = false
	game.tab = "港口"
	reset()
	game.say("拖船已抵达%s（18 日，最多 60 信用点）。" % world.ports[home_id].name)
	game.refresh()

func escort(other: Dictionary, lead: Dictionary) -> bool:
	var world = game.world
	if other.has("construction_contract") and world.ConstructionContract.is_escort(other,lead,world.player):
		return true
	if other.id == lead.id or other.captain == 0 or not world.oversees(world.ship_principal(other)) or world.enemy(other,lead):
		return false
	var orders: Array = other.get("order_queue",[])
	if not orders.is_empty():
		var order: Dictionary = orders.front()
		if order.kind != "escort_to" or order.commander != lead.id or not other.travel.is_empty():
			return false
		if other.layer:
			return Vector2(other.galpos).distance_to(lead.galpos) < 160.0
		return other.system == lead.system and Vector2(other.pos).distance_to(lead.pos) < 620.0
	return other.get("commander_id",lead.id) == lead.id and (other.job.get("kind", "") == "护航" or other.get("fleet_role", "") in ["ATTACK","INTERCEPT","BOMBARD","DEFEND"])

func issue(order: int, focus: int = 0, selection: Array = []) -> int:
	var world = game.world
	var lead: Dictionary = world.ride()
	if lead.is_empty() or lead.dock != 0 or game.galaxy or order not in range(Battle.ORDERS.size()):
		return 0
	var designated: Dictionary = world.ships.get(focus, {})
	if order == 2 and (designated.is_empty() or designated.id == lead.id or not Battle.available(designated, lead.system) or not visible_contact(lead,designated)):
		return 0
	if order == 2 and escort(designated,lead):
		game.say("无法命令编队集火自己的护航舰。")
		return 0
	var count := 0
	for other in world.ships.values():
		if (order != 2 or other.id != focus) and not other.has("construction_contract") and escort(other, lead) and Battle.available(other, lead.system) and (selection.is_empty() or other.id in selection):
			if order == 2:
				world.engage_ship(lead,designated,world.player)
				world.engage_ship(other,designated,0)
			other.battle.order = order
			other.battle.erase("tactical_waypoint")
			other.battle.focus = focus if order == 2 else 0
			count += 1
	return count

func select_group(vessel: Dictionary, group: int, toggle_auto: bool) -> bool:
	if group == 0:
		if toggle_auto:
			var any_off := false
			for i in range(3):
				if not vessel.fit.auto[i]:
					any_off = true
					break
			for i in range(3):
				vessel.fit.auto[i] = any_off
		else:
			vessel.battle.group = 0 if vessel.battle.group != 0 else 1
		return true
	if group not in [1,2,3] or group not in vessel.fit.groups:
		return false
	if toggle_auto:
		vessel.fit.auto[group-1] = not vessel.fit.auto[group-1]
	else:
		vessel.battle.group = group
	return true

func target_at(lead: Dictionary, aim: Vector2, max_distance: float = 52.0, include_allies: bool = false) -> int:
	var world = game.world
	var found := 0
	var nearest := max_distance
	for other in world.ships.values():
		if other.id == lead.id or not Battle.available(other, lead.system) or (not include_allies and not world.enemy(lead, other)):
			continue
		if not visible_contact(lead, other):
			continue
		var shape := Battle.Defenses.geometry(other.kind)
		var point := (aim - Vector2(other.pos)).rotated(-float(other.heading))
		if point.length_squared() > pow(max_distance + float(shape.radius), 2):
			continue
		var gap := 0.0
		var polygon: PackedVector2Array = shape.bounds
		if not Geometry2D.is_point_in_polygon(point, polygon):
			gap = INF
			var prior := polygon[-1]
			for vertex in polygon:
				gap = minf(gap, point.distance_to(Geometry2D.get_closest_point_to_segment(point,prior,vertex)))
				prior = vertex
		if gap < nearest:
			found = other.id
			nearest = gap
	return found

func fire(vessel: Dictionary, aim: Vector2) -> int:
	var world = game.world
	var id := target_at(vessel,aim,23.0,true)
	if id != 0 and id != game.selected_target and not world.enemy(vessel,world.ships[id]):
		id = target_at(vessel,aim,23.0)
	if id != 0:
		var other: Dictionary = world.ships[id]
		aim = Battle.lead_point(vessel, other, vessel.battle.group)
	return Battle.group_fire(world,vessel,vessel.battle.group,aim,id,world.player)

func maneuver(other: Dictionary, direction: Vector2, delta: float, heading: float) -> void:
	var state: Dictionary = other.battle
	var world = game.world
	if (other.id != world.ride().get("id", 0) or game.autopilot) and (not direction.is_zero_approx() or state.motion.length_squared() > 4.0):
		direction = direction + _ai_separation(world, other)
	state.ai_thrust = direction
	state.ai_heading = heading
	if direction == Vector2.ZERO and state.motion == Vector2.ZERO and heading == other.heading and state.system_time <= 0.0:
		return
	var model: Dictionary = Hulls.MODELS[other.kind]
	var acceleration: float = model.get("acceleration",240.0/(1.0+model.size*.3))
	var turn_rate := deg_to_rad(float(model.get("turn_rate",235.0/(1+model.size*.35))))
	var speed: float = COMBAT_SPEED_SCALE * model.speed * Hulls.crew_efficiency(other)
	if state.system_time > 0.0:
		var ability: Dictionary = state.get("active_profile",{})
		direction = Battle.Abilities.heading_input(other,direction,ability)
		acceleration *= float(ability.get("accel",1.0))
		turn_rate *= float(ability.get("turn",1.0))
		speed *= float(ability.get("speed",1.0))
	var thrust := direction.limit_length() * speed
	if state.get("engine_disabled", 0.0) > 0.0:
		thrust *= 0.18
	var mass_ratio := load_factor(other)
	state.motion = state.motion.move_toward(thrust, acceleration * delta / mass_ratio)
	other.pos += state.motion * delta
	other.heading = rotate_toward(other.heading, heading, turn_rate * delta / mass_ratio)

func load_factor(vessel: Dictionary) -> float:
	var cargo := 0.0
	for quantity: int in vessel.cargo:
		cargo += quantity
	return 1.0 + 0.45 * cargo / maxf(1.0, float(Hulls.MODELS[vessel.kind].cargo))

func personality(vessel: Dictionary) -> int:
	if vessel.id == game.world.ride().get("id", 0) and game.autopilot:
		var tactic_personality := [0, 1, 3, 1, 4]
		return tactic_personality[clampi(int(game.combat_tactic), 0, tactic_personality.size() - 1)]
	var captain: Dictionary = game.world.people.get(vessel.captain, {})
	var boldness := float(captain.get("personality", {}).get("boldness", 0))
	var risk := boldness - float(captain.get("stress", 0)) * 0.15
	return clampi(roundi(2.0 - risk / 40.0), 0, 4)

func retaliate(ship: Dictionary, lead: Dictionary, reach: float) -> int:
	var attackers: Dictionary = lead.battle.get("fleet_attackers",{})
	var best := 0
	var nearest := INF
	for id in attackers:
		if attackers[id] <= lead.battle.threat_clock:
			continue
		var attacker: Dictionary = game.world.ships.get(id,{})
		if attacker.is_empty() or not Battle.available(attacker,lead.system) or not game.world.enemy(ship,attacker):
			continue
		var distance: float = ship.pos.distance_squared_to(attacker.pos)
		if distance <= reach * reach and distance < nearest:
			best = id
			nearest = distance
	return best

func screening_target(ship: Dictionary, lead: Dictionary, missiles: Variant, carriers: Variant) -> Vector2:
	var world = game.world
	var reach := 450.0
	var nearest := reach * reach
	var point := Vector2.INF
	for shot in (world.projectiles if missiles == null else missiles):
		if not shot.missile or shot.hp <= 0 or shot.system != lead.system:
			continue
		var gap: Vector2 = lead.pos - shot.pos
		if gap.length_squared() >= nearest or shot.vel.dot(gap) <= 0.0:
			continue
		if shot.get("target",0) != lead.id and absf(gap.cross(Vector2(shot.vel).normalized())) > 85.0:
			continue
		if world.enemy(ship,shot):
			point = shot.pos
			nearest = gap.length_squared()
	if carriers == null or not carriers.is_empty():
		var wing := Battle.Wings.threat(world,ship,lead.pos,sqrt(nearest),carriers)
		if not wing.is_empty():
			return wing.pos
	return point

func _ai_separation(world, vessel: Dictionary) -> Vector2:
	var push := Vector2.ZERO
	var origin := Vector2(vessel.pos)
	var self_vel := Vector2(vessel.battle.get("motion", Vector2.ZERO))
	var self_radius := float(Battle.Defenses.geometry(vessel.kind).radius)
	for other in world.ships.values():
		if other.id == vessel.id or not Battle.available(other, vessel.system):
			continue
		var other_pos := Vector2(other.pos)
		var other_vel := Vector2(other.battle.get("motion", Vector2.ZERO))
		var is_enemy: bool = world.enemy(vessel, other)
		var margin := 16.0 if is_enemy else 34.0
		var min_gap := self_radius + float(Battle.Defenses.geometry(other.kind).radius) + margin
		var future_diff := (origin + self_vel * 0.6) - (other_pos + other_vel * 0.6)
		var now_diff := origin - other_pos
		var diff := future_diff if future_diff.length_squared() < now_diff.length_squared() else now_diff
		var dist_sq := diff.length_squared()
		if dist_sq < min_gap * min_gap:
			if dist_sq < 0.01:
				push += Vector2.RIGHT.rotated(float(vessel.id)) * 0.7
			else:
				var dist := sqrt(dist_sq)
				var away := diff / dist
				var strength := ((min_gap - dist) / min_gap) * (0.95 if not is_enemy else 0.70)
				var tangent := away.orthogonal() * (1.0 if int(vessel.id) % 2 == 0 else -1.0)
				push += (away + tangent * 0.45) * strength
	return push.limit_length(0.95)

func drive_ai(other: Dictionary, lead: Dictionary, delta: float, missiles: Variant = null, carriers: Variant = null) -> void:
	var world = game.world
	var state: Dictionary = other.battle
	Battle.ensure_state(other)
	if other.has("defense_port"):
		world.StationAssault.fire(world,other,lead,delta)
		return
	if other.has("construction_contract") and world.ConstructionContract.is_escort(other,lead,world.player):
		state.ai = "随行施工"
		state.target_id = 0
		other.locked = false
		var berth := Vector2(lead.pos) - Vector2.from_angle(lead.heading)*95.0
		var offset := berth - Vector2(other.pos)
		maneuver(other,offset/60.0,delta*maxi(1,game.speed),offset.angle() if offset.length() > 5.0 else lead.heading)
		return
	if state.has("tactical_waypoint"):
		var waypoint: Vector2 = state.tactical_waypoint
		var delta_pos := waypoint - Vector2(other.pos)
		if delta_pos.length() > 20.0:
			state.ai = "前往航点"
			maneuver(other, delta_pos.normalized(), delta, delta_pos.angle())
			return
		state.erase("tactical_waypoint")
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
		var role: String = other.get("fleet_role","") if other.get("order_queue",[]).is_empty() else "DEFEND"
		if state.order == 2 and not focus.is_empty() and Battle.available(focus, lead.system) and world.enemy(other, focus):
			enemy_id = focus.id
		elif role == "DEFEND":
			enemy_id = retaliate(other,lead,500.0)
		elif role == "INTERCEPT" and not state.pd_slots.is_empty():
			var screen := screening_target(other,lead,missiles,carriers)
			if screen.is_finite():
				state.ai = "截击来袭目标"
				state.target_id = 0
				other.locked = true
				var gap := screen - Vector2(other.pos)
				maneuver(other,gap / 100.0,delta,gap.angle())
				return
		if enemy_id == 0 and role == "ATTACK":
			for id in [game.selected_target,lead.battle.get("last_fired_target",0)]:
				var target_ship: Dictionary = world.ships.get(id,{})
				if not target_ship.is_empty() and Battle.available(target_ship,lead.system) and world.enemy(other,target_ship) and other.pos.distance_squared_to(target_ship.pos) <= 250000.0:
					enemy_id = id
					break
		if enemy_id == 0 and role != "DEFEND" and (role in ["ATTACK","INTERCEPT","BOMBARD"] or state.order != 1 or other.pos.distance_to(lead.pos) <= 195.0):
			enemy_id = ai_target(other,500.0 if state.order == 0 or not role.is_empty() else 270.0)
		if role.is_empty() and state.order == 1 and enemy_id != 0 and world.ships[enemy_id].pos.distance_to(lead.pos) > 325.0:
			enemy_id = 0
		state.target_id = enemy_id
	elif other.has("organization") and not other.job.get("ambush_only", false) and not Outlaws.id_for(other).is_empty() and other.pos.distance_to(lead.pos) < 585.0:
		enemy_id = ai_target(other, 490.0)
	elif world.enemy(other, lead) and (lead.locked or other.locked) and other.pos.distance_to(lead.pos) < 585.0:
		enemy_id = ai_target(other, 490.0)
	other.locked = enemy_id != 0
	if enemy_id == 0:
		state.ai = "护卫舰位" if ally else "巡航"
		if state.system_time > 0.0 and state.active_profile.get("toggle", false):
			Battle.system(world, other, Vector2.from_angle(other.heading))
		Battle.shield(other, false)
		if ally:
			var side := -1.0 if int(other.id) % 2 == 0 else 1.0
			var anchor := Vector2(lead.pos) + Vector2(-70 - int(other.id) % 3 * 35, 75 * side).rotated(lead.heading)
			var gap := anchor - Vector2(other.pos)
			maneuver(other, gap / 75.0, delta, lead.heading)
		elif other.has("organization") and other.job.has("waypoint") and not Outlaws.id_for(other).is_empty():
			var gap := Vector2(other.job.waypoint) - Vector2(other.pos)
			state.ai = "守卫圣所" if other.organization == Outlaws.CULT else "海盗巡航"
			maneuver(other, gap / 85.0, delta, gap.angle() if gap.length_squared() > 2.0 else other.heading)
		else:
			state.motion = Vector2.ZERO
			state.ai_thrust = Vector2.ZERO
			state.ai_heading = other.heading
		return
	_engage_target(other, world.ships[enemy_id], delta)

func weapon_threat(foe: Dictionary, defender: Dictionary) -> bool:
	if not Battle.ready(foe) or Battle.Abilities.active(foe).get("block_fire",false): return false
	Battle.ensure_state(foe)
	for slot in foe.fit.weapons.size():
		var key: String = foe.fit.weapons[slot]
		if key.is_empty() or foe.battle.cooldowns[slot] > 0.55 or foe.battle.disabled_slots[slot] > 0.55: continue
		var gun: Dictionary = Hulls.WEAPONS[key]
		if gun.get("pd",false) or (gun.get("ammo",0) > 0 and foe.battle.magazines[slot] < 1): continue
		if Battle.can_aim(foe,slot,defender.pos,gun.range) and Battle.weapon_aligned(foe,slot,Vector2(defender.pos)-Battle.slot_position(foe,slot),gun):
			return true
	return false

func _engage_target(other: Dictionary, foe: Dictionary, delta: float) -> void:
	var world = game.world
	var state: Dictionary = other.battle
	var gap := Vector2(foe.pos) - Vector2(other.pos)
	var axis := gap.normalized()
	if axis.is_zero_approx():
		axis = Vector2.from_angle(other.heading)
	var p := personality(other)
	var mode := Battle.ai_mode(other, gap.length(), p)
	var aim_point := Battle.lead_point(other, foe, other.battle.group)
	if not aim_point.is_finite():
		aim_point = foe.pos
	Battle.train(other, aim_point, delta)
	var aim_vec := aim_point - Vector2(other.pos)
	var face_angle := aim_vec.angle() if not aim_vec.is_zero_approx() else gap.angle()
	var imminent := false
	var threat_pos := Vector2.INF
	if scanning_threats:
		imminent = Battle.fire_control.imminent(world,other,world.projectiles)
	if not scanning_threats or imminent:
		var nearest_threat := 16384.0
		for projectile in world.projectiles:
			if projectile.system == other.system and world.enemy(other, projectile):
				var dist_sq: float = projectile.pos.distance_squared_to(other.pos)
				if dist_sq < nearest_threat and projectile.vel.dot(other.pos - projectile.pos) > 0.0:
					imminent = true
					nearest_threat = dist_sq
					threat_pos = projectile.pos
	var lateral := axis.orthogonal() * (-1.0 if int(other.id) % 2 == 0 else 1.0)
	state.ai = mode
	var cloak: bool = Hulls.MODELS[other.kind].get("phase",false)
	var anticipating: bool = not cloak and Hulls.MODELS[other.kind].get("shield_type","FRONT") != "NONE" and weapon_threat(foe,other)
	if imminent or anticipating: state.ai_shield_hold = 0.5
	var guard: bool = imminent if cloak else state.get("ai_shield_hold",0.0) > 0
	var shield_aim: Vector2 = threat_pos if threat_pos.is_finite() else foe.pos
	if mode in ["降盾散热","脱离交战"]:
		if state.system_time > 0.0 and state.active_profile.get("toggle", false):
			var active_def: bool = state.active_profile.get("effect", "") in ["flare", "flak", "fortress", "damper", "screen", "extract", "blink", "thrust", "impulse", "recall"]
			var active_cap := 0.85 if active_def else 0.58
			if Battle.fraction(other) >= active_cap or not Battle.Abilities.ai_use(other, foe, gap.length(), imminent, false):
				Battle.system(world, other, -axis)
		elif state.system_cd <= 0.0 and state.system_time <= 0.0:
			var eff: String = Battle.Abilities.profile(other).effect
			if eff == "extract" or (eff in ["flare", "flak", "fortress", "damper", "screen", "blink", "thrust", "impulse"] and Battle.Abilities.ai_use(other, foe, gap.length(), imminent, false)):
				Battle.system(world, other, -axis, foe.pos, foe.id)
		Battle.shield(other, guard and Battle.fraction(other) < 0.74, shield_aim)
		if not state.shield and not imminent and gap.length() > 210.0 and Battle.fraction(other) > 0.38 and Battle.vent(other):
			world.combat_event("vent", other.pos, other.system)
		maneuver(other, -axis + lateral * 0.25, delta, gap.angle())
		return
	var desired := Battle.preferred_range(other, p)
	var dist := gap.length()
	var tactic: int = int(game.combat_tactic) if (other.id == world.ride().get("id", 0) and game.autopilot) else -1
	var move := Vector2.ZERO
	if tactic == 0:
		# 激进突击：贴近主炮射程并保持侧移压迫，不后退放风筝
		state.ai = "激进突击"
		move = axis * 0.95 + lateral * 0.25 if dist > desired * 0.65 else lateral * 0.65 + axis * 0.25
	elif tactic == 1:
		# 稳健接战：保持有效射程内绕飞交火
		state.ai = "稳健接战"
		var radial := 0.45 if dist > desired * 0.95 else (-0.25 if dist < desired * 0.50 else 0.0)
		move = lateral * 0.68 + axis * radial
	elif tactic == 2:
		# 游击拉扯：远距风筝拉扯
		state.ai = "游击拉扯"
		var radial := 0.24 if dist > desired * 0.95 else (-0.65 if dist < desired * 0.78 else 0.0)
		move = lateral * 0.72 + axis * radial
	elif tactic == 3:
		# 护盾抗线：稳步接敌，减少横移，高幅能持盾
		state.ai = "护盾抗线"
		var radial := 0.40 if dist > desired else (-0.15 if dist < desired * 0.45 else 0.0)
		move = axis * radial + lateral * 0.32
	elif tactic == 4:
		# 避战撤离：拉开距离并及早散热
		state.ai = "避战撤离"
		move = -axis * 0.90 + lateral * 0.35
	else:
		var radial := 0.42 if dist > desired * 0.92 else (-0.30 if dist < desired * 0.52 else 0.0)
		move = axis * 0.92 + lateral * 0.26 if mode == "压进" else lateral * 0.72 + axis * radial
	if tactic != 4 and foe.hp < Hulls.MODELS[foe.kind].hp * 0.28 and Battle.fraction(other) < 0.78:
		state.ai = "追击补刀"
		move = axis * 0.96 + lateral * 0.22
	maneuver(other, move, delta, face_angle)
	var shield_cap: float = 0.88 if tactic == 3 else [0.85, 0.76, 0.62, 0.48, 0.36][p]
	Battle.shield(other, guard and Battle.fraction(other) < shield_cap+ (0.06 if state.shield else 0.0),shield_aim)
	var ability_profile := Battle.Abilities.profile(other)
	var is_defensive: bool = ability_profile.effect in ["flare", "flak", "fortress", "damper", "screen", "extract", "blink", "thrust", "impulse", "recall"]
	var flux_limit := 0.85 if is_defensive else 0.58
	if state.system_time > 0.0 and state.active_profile.get("toggle", false):
		if Battle.fraction(other) >= flux_limit or not Battle.Abilities.ai_use(other, foe, dist, imminent, mode == "压进"):
			Battle.system(world, other, axis)
	elif state.system_cd <= 0.0 and state.system_time <= 0.0 and Battle.fraction(other) < flux_limit:
		var recipient: Dictionary = Battle.Abilities.lash_recipient(world, other, foe) if ability_profile.effect == "lash" else foe
		if Battle.Abilities.ai_use(other, recipient, other.pos.distance_to(recipient.pos), imminent, mode == "压进"):
			Battle.system(world, other, axis, recipient.pos, recipient.id)
	var fire_cap: float = [0.86, 0.78, 0.68, 0.58, 0.48][p]
	if Battle.fraction(other) < fire_cap:
		Battle.auto_fire(world, other, foe)

func attack_target(id: int) -> bool:
	var world = game.world
	var lead: Dictionary = world.ride()
	var foe: Dictionary = world.ships.get(id,{})
	if lead.is_empty() or foe.is_empty() or lead.id == id or game.galaxy or game.watch_ship_id or not Battle.available(lead,lead.system) or not Battle.available(foe,lead.system) or not visible_contact(lead,foe):
		return false
	game.selected_target = id
	game.waypoint_live = false
	game.set_autopilot(true,true)
	world.engage_ship(lead,foe,world.player)
	return true

func _autopilot_target(vessel: Dictionary) -> int:
	var world = game.world
	var chosen: int = game.selected_target
	if chosen != 0:
		var picked: Dictionary = world.ships.get(chosen, {})
		if not picked.is_empty() and Battle.available(picked, vessel.system) and world.enemy(vessel, picked) and visible_contact(vessel, picked):
			return chosen
	var auto_id := ai_target(vessel, 620.0)
	if auto_id != 0:
		return auto_id
	return target(vessel, 620.0)

func combat(vessel: Dictionary, delta: float, aiming: bool = false, aim: Vector2 = Vector2.ZERO, defer_contacts := false) -> void:
	var world = game.world
	var starts := {} if defer_contacts else HullContacts.capture(world,vessel.system)
	var entering := false
	if vessel.locked:
		var lock_id := target(vessel, 520.0, true)
		vessel.locked = lock_id != 0 and visible_contact(vessel, world.ships[lock_id])
	else:
		var threat := target(vessel,255.0)
		entering = threat != 0 and Sensors.npc_contact(world.ships[threat],vessel,float(sensor_reading.get("profile",-1.0)))
		vessel.locked = entering
	if entering:
		game.waypoint_live = false
		game.say("敌舰已接近：左键开火，Shift 护盾，V 排散，Tab 下达舰队指令。")
	Battle.tick(vessel, delta, world)
	physics_frame += 1
	var busy: bool = world.projectiles.size() >= 64
	var missiles: Array = []
	var carriers: Array = []
	Battle.init_accelerators()
	scanning_threats = Battle.fire_control != null
	if scanning_threats:
		missiles = Battle.fire_control.begin_frame(world.projectiles,vessel.system)
	else:
		for shot in world.projectiles:
			if shot.missile and shot.system == vessel.system and shot.hp > 0:
				missiles.append(shot)
	for ship in world.ships.values():
		if ship.system == vessel.system and not ship.battle.get("fighter_wings", []).is_empty():
			carriers.append(ship)
	for other in world.ships.values():
		if other.id == vessel.id or not world.ships.has(other.id) or not Battle.available(other, vessel.system):
			continue
		Battle.tick(other, delta, world)
		var queue: Array = other.get("order_queue",[])
		if not queue.is_empty() and queue.front().kind=="escort_to" and (escort(other,vessel) or other.battle.has("tactical_waypoint")):
			tactical_escorts[other.id] = true
		var decide: bool = not busy or not other.battle.has("ai_thrust") or (physics_frame + int(other.id)) % 5 == 0
		if decide:
			drive_ai(other,vessel,delta,missiles,carriers)
			var protect: Dictionary = vessel if other.get("fleet_role","") == "INTERCEPT" and escort(other,vessel) and other.battle.order != 3 else {}
			Battle.point_defense(world,other,missiles,carriers,protect)
		elif other.battle.has("ai_heading"):
			maneuver(other, other.battle.ai_thrust, delta, other.battle.ai_heading)
		if Hulls.MODELS[other.kind].fighter_bays > 0:
			Battle.Wings.advance(world, other, world.ships.get(other.battle.get("target_id", 0), {}) if other.locked else {}, delta, Battle, missiles, carriers)
	if not world.ships.has(vessel.id):
		scanning_threats = false
		return
	var auto_pilot: bool = game.autopilot and not game.waypoint_live
	var auto_target := _autopilot_target(vessel) if auto_pilot else target(vessel, 510.0)
	if auto_pilot:
		if auto_target != 0:
			autopilot_engaged = true
			_engage_target(vessel, world.ships[auto_target], delta)
		else:
			vessel.battle.ai = "自动驾驶待命"
			maneuver(vessel, Vector2.ZERO, delta, vessel.heading)
			Battle.shield(vessel, false)
			if autopilot_engaged and not vessel.locked:
				autopilot_engaged = false
				if world.cargo_free(vessel) > 0:
					for cache in world.wrecks.values():
						if cache.system == vessel.system and Vector2(vessel.pos).distance_to(cache.pos) < 95.0 and cache.stock.max() > 0:
							salvage()
							break
				if vessel.hp < float(Hulls.MODELS[vessel.kind].hp) * 0.55:
					field_repair()
	scanning_threats = false
	var foe: Dictionary = world.ships.get(auto_target, {})
	if not auto_pilot:
		if aiming or not foe.is_empty():
			Battle.train(vessel, aim if aiming else Battle.lead_point(vessel, foe, vessel.battle.group), delta)
		if aiming:
			fire(vessel, aim)
		if not foe.is_empty() and world.ships.has(foe.id):
			Battle.auto_fire(world,vessel,foe,true)
	var wing_target := auto_target
	if wing_target == 0 and Hulls.MODELS[vessel.kind].fighter_bays > 0:
		wing_target = target(vessel,Battle.Wings.operation_range(vessel))
	Battle.Wings.advance(world, vessel, world.ships.get(wing_target, {}), delta, Battle, missiles, carriers)
	Battle.point_defense(world, vessel, missiles, carriers)
	if not defer_contacts: HullContacts.resolve(world,vessel.system,starts)
	Battle.project(world, vessel.system, delta)

func step(delta: float, controls: Vector2 = Vector2.ZERO, shield_held: bool = false, aiming: bool = false, aim: Vector2 = Vector2.ZERO, cursor: bool = false, boost: bool = false) -> void:
	var world = game.world
	tactical_escorts.clear()
	if world.succession or world.attention or game.speed == 0:
		return
	var vessel: Dictionary = world.ride()
	var airborne: bool = not vessel.is_empty() and vessel.dock == 0
	var local_system: int = game.current_system() if not game.galaxy and (airborne or game.watch_ship_id > 0 or game.system_chart) else -1
	var starts := HullContacts.capture(world,local_system) if local_system >= 0 else {}
	var manual: bool = airborne and not game.waypoint_live
	var engaged: bool = airborne and not game.galaxy and (game.waypoint_live or sensor_reading.is_empty()) and target(vessel,260.0,true) != 0
	if manual or engaged:
		game.speed = 1
	var days_per_second: float = PORT_DAYS_PER_SECOND[game.speed]
	if airborne:
		var state: Dictionary = vessel.battle
		Battle.ensure_state(vessel)
		sensor_countdown -= delta
		vessel.ping = maxf(0.0, vessel.get("ping", 0.0) - delta)
		if sensor_countdown <= 0.0:
			sensor_reading = Sensors.fleet(world, vessel)
			sensor_countdown = 0.2
		if not controls.is_zero_approx():
			game.waypoint_live = false
			if game.autopilot and game.agent_bridge == null:
				game.set_autopilot(false, true)
			game.speed = 1
		elif game.waypoint_live and not engaged:
			if game.waypoint_tracking.is_valid():
				game.waypoint = game.waypoint_tracking.call()
			var gap: Vector2 = game.waypoint - (vessel.galpos if game.galaxy else vessel.pos)
			var at_destination: bool = game.waypoint_arrived.call(gap.length()) if game.waypoint_arrived.is_valid() else gap.length() < 13
			if at_destination:
				game.waypoint_live = false
				state.motion = Vector2.ZERO
			else:
				controls = gap.normalized() if game.galaxy else (gap.normalized() + _ai_separation(world, vessel)).normalized()
		var auto_combat: bool = game.autopilot and not game.galaxy and not game.waypoint_live
		var pace := float(game.speed) if game.waypoint_live else 1.0
		days_per_second = (float(Hyperspace.Rules.data.days_per_second) if game.galaxy else FLIGHT_DAYS_PER_SECOND) * pace
		if not auto_combat:
			var model: Dictionary = Hulls.MODELS[vessel.kind]
			var base_scale := COMBAT_SPEED_SCALE if vessel.locked else CRUISE_SPEED_SCALE
			var flight_speed: float = Hyperspace.cruise_speed(model) if game.galaxy else base_scale * model.speed
			flight_speed *= Hulls.crew_efficiency(vessel)
			if game.galaxy:
				flight_speed *= float(sensor_reading.get("burn", 9.0)) / maxf(1.0, float(model.get("burn", 9.0)))
				if state.get("silent_running", false):
					flight_speed *= 0.5
			var ability: Dictionary = state.get("active_profile",{}) if state.system_time > 0.0 else {}
			flight_speed *= float(ability.get("speed",1.0))
			var boosting: bool = boost and state.boost_energy > 0.0 and not controls.is_zero_approx() and state.engine_disabled <= 0.0
			var boost_mult := 1.35 if vessel.locked else 1.6
			if boosting:
				flight_speed *= boost_mult
			state.boost_energy = clampf(state.boost_energy + (-32.0 if boosting else (0.0 if boost else 13.0)) * delta, 0.0, 100.0)
			if state.engine_disabled > 0.0:
				flight_speed *= 0.18
			var field := "galpos" if game.galaxy else "pos"
			var travel_delta := delta * pace
			var accel := float(model.get("acceleration", 260.0 * model.speed / (1.0 + 0.2 * model.size)))
			state.motion = state.motion.move_toward(Battle.Abilities.heading_input(vessel,controls,ability).normalized() * flight_speed, accel * float(ability.get("accel",1.0)) * (boost_mult if boosting else 1.0) * travel_delta / load_factor(vessel))
			if game.galaxy and vessel.fuel <= 0:
				state.motion = Vector2.ZERO
			var displacement: Vector2 = state.motion * travel_delta
			if game.waypoint_live:
				displacement = displacement.limit_length(Vector2(vessel[field]).distance_to(game.waypoint))
			if game.galaxy:
				var fuel_cost := Hyperspace.fuel_for_distance(model,displacement.length())
				if fuel_cost > vessel.fuel:
					displacement *= vessel.fuel / fuel_cost
				vessel.fuel = maxf(0.0,vessel.fuel-fuel_cost)
			vessel[field] += displacement
			if game.galaxy:
				world.stream_hyperspace(vessel.galpos)
				Battle.tick(vessel, delta, world)
				for other in world.ships.values():
					if other.layer and escort(other,vessel):
						other.galpos = vessel.galpos + Vector2(-22, 22)
			if not game.galaxy and cursor and Vector2(vessel.pos).distance_squared_to(aim) > 48.0:
				vessel.heading = rotate_toward(vessel.heading, (aim - Vector2(vessel.pos)).angle(), deg_to_rad(float(model.turn_rate)) * float(ability.get("turn",1.0)) * delta)
			elif state.motion.length() > 8:
				vessel.heading = rotate_toward(vessel.heading, state.motion.angle(), deg_to_rad(float(model.turn_rate)) * float(ability.get("turn",1.0)) * delta)
			Battle.shield(vessel, not game.galaxy and shield_held, aim if cursor else Vector2.INF)
		if not game.galaxy:
			combat(vessel, delta, aiming, aim,true)
	elif not vessel.is_empty():
		Battle.shield(vessel, false)
		Battle.tick(vessel, delta, world)
	if not world.attention and not world.succession:
		advance_clock(delta * days_per_second,airborne or game.watch_ship_id > 0 or game.system_chart)
	if local_system >= 0: HullContacts.resolve(world,local_system,starts)

func advance_clock(days: float, observing: bool) -> void:
	var world = game.world
	if not observing:
		accumulated += days
		var completed := floori(accumulated + 0.0000001)
		if completed > 0:
			accumulated = maxf(0.0,accumulated-completed)
			world.tick(completed,civil_motion)
			civil_motion.clear()
		return
	var view: Dictionary = game.viewed_ship()
	var system: int = game.current_system()
	var hyperspace: bool = view.get("layer",false)
	while days > 0.0000001 and not world.succession and not world.attention:
		var duration := minf(days,1.0-accumulated)
		Economy.visible_traffic(world,system,hyperspace,duration,civil_motion,tactical_escorts)
		world.Crises.move_visible(world,system,hyperspace,duration,civil_motion)
		accumulated += duration
		days -= duration
		if accumulated >= 0.9999999:
			accumulated = 0.0
			world.tick(1,civil_motion)
			civil_motion.clear()
