extends RefCounted

const Hulls = preload("res://hull_catalog.gd")
const Fitting = preload("res://scripts/models/fitting_data.gd").FittingData
const FleetOrder = preload("res://scripts/models/fleet_order.gd")

# The stored hull and mount identities survive catalog reordering.
static func create(id: int, kind: int, owner: int, captain: int, flag: int, system: int,
		position: Vector2, galactic_position: Vector2, dock: int, cargo: Array) -> Dictionary:
	return {
		"id": id, "kind": kind, "hull_id": Hulls.hull_id(kind), "owner": owner,
		"captain": captain, "flag": flag, "system": system, "pos": position, "dock": dock,
		"heading": -PI / 2, "hp": float(Hulls.MODELS[kind].hp), "cargo": cargo,
		"fuel": 70.0, "job": {}, "order_queue": [], "travel": {}, "locked": false, "cool": 0.0,
		"galpos": galactic_position, "layer": false, "raid": -1,
		"fit": Hulls.stock_fitting(kind), "battle": Hulls.battle_state(kind),
		"crew": Hulls.crew_limits(kind).x, "transponder": true, "ping": 0.0,
	}

static func encode(vessel: Dictionary) -> Dictionary:
	var data := vessel.duplicate(true)
	data.erase("kind")
	var mounts := {}
	for i in range(vessel.fit.weapons.size()):
		var slot_id: String = Hulls.slot_spec(vessel.kind, i).id
		mounts[slot_id] = {"weapon": vessel.fit.weapons[i], "group": vessel.fit.groups[i],
			"cooldown": vessel.battle.cooldowns[i]}
	var fit: Fitting = vessel.fit
	var automatic := []
	automatic.assign(fit.auto)
	var air_group := []
	air_group.assign(fit.wings)
	data.fit = {"auto":automatic,"caps":fit.caps,"vents":fit.vents,"mounts":mounts,"wings":air_group}
	data.battle.erase("cooldowns")
	return data

static func decode(data: Dictionary, ware_count: int) -> Dictionary:
	if data.has("charter"):
		var charter: Variant = data.charter
		if not charter is Dictionary or not charter.get("operator") is int or not charter.get("port") is int:
			return {}
		if data.get("owner") != 0 or charter.operator <= 0 or charter.port <= 0:
			return {}
	if data.has("station_owner") and (not data.station_owner is int or data.station_owner <= 0 or data.get("owner") != 0):
		return {}
	if data.has("lease"):
		var lease: Variant = data.lease
		if not lease is Dictionary or not lease.get("port") is int or not lease.get("lessor") is int or not lease.get("daily_rent") is int or not lease.get("started") is int:
			return {}
		if lease.port <= 0 or lease.lessor <= 0 or lease.daily_rent <= 0 or lease.started < 0:
			return {}
	if data.has("passengers"):
		var pax: Variant = data.passengers
		if not pax is Array:
			return {}
		for pid in pax:
			if not pid is int or pid <= 0:
				return {}
	var kind := Hulls.kind_for_id(str(data.get("hull_id", "")))
	if kind < 0 or not data.get("fit") is Dictionary or not data.get("battle") is Dictionary:
		return {}
	if not data.get("pos") is Vector2 or not data.get("galpos") is Vector2 or not data.get("cargo") is Array:
		return {}
	if data.cargo.size() != ware_count or not data.fit.get("mounts") is Dictionary:
		return {}
	var orders: Variant = data.get("order_queue",[])
	if not orders is Array or orders.size() > FleetOrder.LIMIT:
		return {}
	for order in orders:
		if not FleetOrder.valid(order,ware_count):
			return {}
	var mounts: Dictionary = data.fit.mounts
	var spec: Dictionary = Hulls.COMBAT[kind]
	if mounts.size() != spec.slots.size():
		return {}
	var ship := data.duplicate(true)
	ship.kind = kind
	var record: Dictionary = ship.fit
	record.erase("mounts")
	record.weapons = []
	record.groups = []
	ship.battle.cooldowns = []
	for i in range(spec.slots.size()):
		var slot_id: String = Hulls.slot_spec(kind, i).id
		var mount: Variant = mounts.get(slot_id)
		if not mount is Dictionary or not mount.get("weapon") is String or not mount.get("group") is int:
			return {}
		if not typeof(mount.get("cooldown")) in [TYPE_FLOAT, TYPE_INT]:
			return {}
		record.weapons.append(mount.weapon)
		record.groups.append(mount.group)
		ship.battle.cooldowns.append(mount.cooldown)
	var fit := Fitting.from_dictionary(record,false,Hulls.MODELS[kind].reference_wings)
	if Hulls.fitting_cost(kind, fit) < 0:
		return {}
	ship.fit = fit
	var defaults: Dictionary = Hulls.battle_state(kind)
	for key in defaults:
		if not ship.battle.has(key) or typeof(ship.battle[key]) != typeof(defaults[key]):
			return {}
	return ship
