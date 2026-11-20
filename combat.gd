extends RefCounted

const Hulls = preload("res://hull_catalog.gd")
const ORDERS := ["自由交战", "护卫旗舰", "集火当前目标", "撤退"]
const SYSTEMS := {
	"boost":{"duration":2.4,"cool":10.0,"flux":20.0},
	"phase":{"duration":0.7,"cool":12.0,"flux":25.0},
	"burst":{"duration":3.2,"cool":12.0,"flux":24.0},
	"repair":{"duration":3.0,"cool":14.0,"flux":18.0},
}

static func available(vessel: Dictionary, system: int) -> bool:
	return vessel.system == system and vessel.dock == 0 and vessel.travel.is_empty() and not vessel.layer and not vessel.battle.retired and vessel.hp > 0.0

static func ready(vessel: Dictionary) -> bool:
	return vessel.battle.overload <= 0.0 and not vessel.battle.vent and not phased(vessel)

static func phased(vessel: Dictionary) -> bool:
	return Hulls.COMBAT[vessel.kind].system == "phase" and vessel.battle.system_time > 0.0

static func fraction(vessel: Dictionary) -> float:
	return (vessel.battle.soft_flux + vessel.battle.hard_flux) / Hulls.capacity(vessel)

static func shield(vessel: Dictionary, enabled: bool) -> void:
	vessel.battle.shield = enabled and ready(vessel)

static func vent(vessel: Dictionary) -> bool:
	var state: Dictionary = vessel.battle
	if not ready(vessel) or state.soft_flux + state.hard_flux <= 0.001:
		return false
	state.shield = false
	state.vent = true
	return true

static func tick(vessel: Dictionary, delta: float) -> void:
	var state: Dictionary = vessel.battle
	var recovery := Hulls.dissipation(vessel) * delta
	var locked_time := minf(delta, state.overload)
	state.overload = maxf(0.0, state.overload - delta)
	if state.overload < 0.000001:
		state.overload = 0.0
	state.system_cd = maxf(0.0, state.system_cd - delta)
	var active_system := minf(delta, state.system_time)
	state.system_time = maxf(0.0, state.system_time - delta)
	for slot in range(state.cooldowns.size()):
		state.cooldowns[slot] = maxf(0.0, state.cooldowns[slot] - delta)
	if locked_time > 0.0:
		recovery = Hulls.dissipation(vessel) * (delta - locked_time)
	if state.vent:
		recovery *= 2.0
	if not state.shield:
		var drained := minf(state.hard_flux, recovery)
		state.hard_flux -= drained
		recovery -= drained
	state.soft_flux = maxf(0.0, state.soft_flux - recovery)
	if state.hard_flux + state.soft_flux <= 0.0001:
		state.vent = false
	if Hulls.COMBAT[vessel.kind].system == "repair" and locked_time == 0.0:
		state.armor = minf(Hulls.COMBAT[vessel.kind].armor, state.armor + active_system * 12.0 * Hulls.crew_efficiency(vessel))
		vessel.hp = minf(Hulls.MODELS[vessel.kind].hp, vessel.hp + active_system * 4.0 * Hulls.crew_efficiency(vessel))

static func add_flux(world, vessel: Dictionary, amount: float, hard: bool = false) -> void:
	if amount <= 0.0 or vessel.battle.overload > 0.0:
		return
	var state: Dictionary = vessel.battle
	var capacity := Hulls.capacity(vessel)
	var open := maxf(0.0, capacity - state.hard_flux - state.soft_flux)
	var key := "hard_flux" if hard else "soft_flux"
	state[key] += minf(amount, open)
	if amount >= open and amount > 0.0:
		state.overload = 3.0
		state.vent = false
		state.shield = false
		state.system_time = 0.0
		world.combat_event("overload", vessel.pos, vessel.system)

static func hull_impact(world, vessel: Dictionary, amount: float, damage_type: int, point: Vector2, direction: Vector2) -> void:
	var state: Dictionary = vessel.battle
	var multiplier: float = Hulls.ARMOR_MULT[damage_type]
	var armor_loss := minf(state.armor, amount * multiplier)
	state.armor -= armor_loss
	var breach := maxf(0.0, amount - armor_loss / multiplier)
	vessel.hp -= breach
	if breach >= 10.0:
		vessel.crew = maxi(0, vessel.crew - maxi(1, floori(breach / 25.0)))
	world.combat_event("impact", point, vessel.system, direction, clampf(amount / 20.0, 0.5, 2.3))

static func hit(world, vessel: Dictionary, amount: float, damage_type: int, point: Vector2, direction: Vector2) -> void:
	if phased(vessel) or amount <= 0.0 or damage_type not in range(Hulls.SHIELD_MULT.size()):
		return
	var state: Dictionary = vessel.battle
	var incoming := amount
	if state.shield and ready(vessel):
		var multiplier: float = Hulls.SHIELD_MULT[damage_type]
		var open := maxf(0.0, Hulls.capacity(vessel) - state.soft_flux - state.hard_flux)
		incoming = maxf(0.0, amount - open / multiplier)
		world.combat_event("shield", point, vessel.system, direction)
		add_flux(world, vessel, amount * multiplier, true)
	if incoming > 0.0001:
		hull_impact(world, vessel, incoming, damage_type, point, direction)

static func system(world, vessel: Dictionary, direction: Vector2) -> bool:
	var state: Dictionary = vessel.battle
	var name: String = Hulls.COMBAT[vessel.kind].system
	var spec: Dictionary = SYSTEMS[name]
	if not ready(vessel) or state.system_cd > 0.0 or Hulls.capacity(vessel) - state.hard_flux - state.soft_flux <= spec.flux:
		return false
	add_flux(world, vessel, spec.flux)
	state.system_cd = spec.cool
	state.system_time = spec.duration
	if name == "phase":
		state.shield = false
		var heading := direction.normalized() if not direction.is_zero_approx() else Vector2.from_angle(vessel.heading)
		vessel.pos = (vessel.pos + heading * 86.0).clamp(Vector2(-1320,-900), Vector2(1320,900))
	world.combat_event("system", vessel.pos, vessel.system)
	return true

static func slot_position(vessel: Dictionary, index: int) -> Vector2:
	var spec: Dictionary = Hulls.COMBAT[vessel.kind]
	var slot: Dictionary = Hulls.SLOTS[spec.slots[index]]
	return vessel.pos + (slot.offset * Hulls.CLASS_SPRITE[Hulls.MODELS[vessel.kind].size]).rotated(vessel.heading)

static func can_aim(vessel: Dictionary, index: int, endpoint: Vector2, distance: float) -> bool:
	var slot: Dictionary = Hulls.SLOTS[Hulls.COMBAT[vessel.kind].slots[index]]
	var difference := endpoint - slot_position(vessel, index)
	var center: float = vessel.heading + deg_to_rad(slot.facing)
	return difference.length_squared() <= distance * distance and absf(angle_difference(center, difference.angle())) <= deg_to_rad(slot.arc * 0.5) + 0.00001

static func fire_slot(world, vessel: Dictionary, index: int, endpoint: Vector2, target_id: int = 0) -> bool:
	var key: String = vessel.fit.weapons[index]
	if key.is_empty() or not ready(vessel) or vessel.battle.cooldowns[index] > 0.0:
		return false
	var spec: Dictionary = Hulls.WEAPONS[key]
	var point := slot_position(vessel, index)
	if spec.get("pd", false) or not can_aim(vessel, index, endpoint, spec.range):
		return false
	var direction := (endpoint - point).normalized()
	if direction.is_zero_approx():
		return false
	var missile: bool = spec.get("missile", false)
	var burst: int = spec.get("burst",1)
	for shot in range(burst):
		var vector := direction.rotated((shot - (burst-1)*0.5) * float(spec.get("spread",0.0)))
		world.projectiles.append({"pos":point,"vel":vector * spec.speed,"speed":spec.speed,"life":spec.range / spec.speed,
			"system":vessel.system,"ship":vessel.id,"flag":vessel.flag,"raid":vessel.raid,"credit":vessel.owner,
			"damage":spec.damage / burst,"type":spec.type,"missile":missile,"target":target_id,"hp":14.0})
	vessel.battle.cooldowns[index] = spec.cool * (0.53 if Hulls.COMBAT[vessel.kind].system == "burst" and vessel.battle.system_time > 0.0 else 1.0) / Hulls.crew_efficiency(vessel)
	world.combat_event("muzzle", point, vessel.system, direction, 1.2 if missile else 0.8)
	add_flux(world, vessel, spec.flux)
	return true

static func group_fire(world, vessel: Dictionary, group: int, point: Vector2, target_id: int = 0) -> int:
	var fired := 0
	for index in range(vessel.fit.groups.size()):
		if vessel.fit.groups[index] == group and fire_slot(world, vessel, index, point, target_id):
			fired += 1
	return fired

static func point_defense(world, vessel: Dictionary) -> void:
	for index in range(vessel.fit.weapons.size()):
		var key: String = vessel.fit.weapons[index]
		if key.is_empty() or not ready(vessel) or vessel.battle.cooldowns[index] > 0.0:
			continue
		var spec: Dictionary = Hulls.WEAPONS[key]
		if not spec.get("pd", false):
			continue
		var best: Dictionary = {}
		var nearest: float = spec.range
		var muzzle := slot_position(vessel, index)
		for missile in world.projectiles:
			if not missile.missile or missile.hp <= 0.0 or missile.system != vessel.system or not world.enemy(vessel, missile):
				continue
			if missile.vel.dot(Vector2(vessel.pos) - Vector2(missile.pos)) <= 0.0:
				continue
			var dist: float = muzzle.distance_to(missile.pos)
			if dist < nearest and can_aim(vessel, index, missile.pos, spec.range):
				best = missile
				nearest = dist
		if not best.is_empty():
			best.hp -= spec.damage
			vessel.battle.cooldowns[index] = spec.cool / Hulls.crew_efficiency(vessel)
			world.combat_event("intercept", best.pos, vessel.system, (best.pos - muzzle).normalized())
			add_flux(world, vessel, spec.flux)

static func project(world, system_id: int, delta: float) -> void:
	for index in range(world.projectiles.size() - 1, -1, -1):
		var blast: Dictionary = world.projectiles[index]
		if blast.system != system_id or blast.hp <= 0.0 or blast.life <= 0.0:
			world.projectiles.remove_at(index)
			continue
		var previous: Vector2 = blast.pos
		if blast.missile:
			var target: Dictionary = world.ships.get(blast.target, {})
			if not target.is_empty() and available(target, system_id) and world.enemy(blast, target):
				var angle: float = rotate_toward(blast.vel.angle(), (target.pos - blast.pos).angle(), 2.1 * delta)
				blast.vel = Vector2.from_angle(angle) * blast.speed
		var interval := minf(delta, blast.life)
		blast.pos += blast.vel * interval
		blast.life -= interval
		var nearest := INF
		var victim: Dictionary = {}
		var contact := Vector2.ZERO
		for vessel in world.ships.values():
			if vessel.id == blast.ship or not available(vessel, system_id) or phased(vessel) or not world.enemy(blast, vessel):
				continue
			var point := Geometry2D.get_closest_point_to_segment(vessel.pos, previous, blast.pos)
			var reach: int = Hulls.CLASS_RADIUS[Hulls.MODELS[vessel.kind].size]
			if point.distance_squared_to(vessel.pos) > reach * reach:
				continue
			var depth := previous.distance_squared_to(point)
			if depth < nearest:
				nearest = depth
				victim = vessel
				contact = point
		if not victim.is_empty():
			hit(world, victim, blast.damage, blast.type, contact, blast.vel.normalized())
			victim.locked = true
			if world.ships.has(blast.ship):
				world.ships[blast.ship].locked = true
			world.projectiles.remove_at(index)
			if victim.hp <= 0.0:
				world.destruction(victim.id, blast.credit)
			if world.succession or world.attention:
				return
		elif blast.life <= 0.0:
			world.projectiles.remove_at(index)

static func ai_mode(vessel: Dictionary, distance: float) -> String:
	var flux := fraction(vessel)
	if vessel.battle.overload > 0.0 or vessel.battle.vent or flux >= 0.72 or (vessel.battle.ai == "降盾散热" and flux > 0.38) or vessel.hp / Hulls.MODELS[vessel.kind].hp < 0.27:
		return "降盾散热"
	if distance > 225.0:
		return "压进"
	return "侧翼拉扯"
