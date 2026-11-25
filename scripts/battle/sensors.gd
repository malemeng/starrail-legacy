extends RefCounted

const Hulls = preload("res://hull_catalog.gd")
const SIGNAL_BY_SIZE := [36.0, 57.0, 88.0, 128.0]

static func signature(ship: Dictionary) -> float:
	var model: Dictionary = Hulls.MODELS[ship.kind]
	var base: float = model.get("sensor_profile", SIGNAL_BY_SIZE[model.size])
	var multiplier := 0.64 if model.get("phase", false) else 1.0
	if ship.get("transponder", true):
		multiplier *= 1.6
	if ship.battle.get("silent_running", false):
		multiplier *= 0.5
	return base * multiplier + (440.0 if ship.get("ping", 0.0) > 0.0 else 0.0)

static func fleet(world, lead: Dictionary) -> Dictionary:
	var profiles: Array[float] = [signature(lead)]
	var operator_id := Hulls.operator_id(lead)
	var slowest: float = Hulls.MODELS[lead.kind].get("burn",9.0)
	for ship in world.ships.values():
		if ship.id == lead.id or ship.dock != 0 or ship.layer != lead.layer or ship.system != lead.system:
			continue
		if not (ship.get("commander_id",0) == lead.id or (operator_id != 0 and ship.owner == operator_id and ship.get("job",{}).get("kind","") == "护航")):
			continue
		profiles.append(signature(ship))
		slowest = minf(slowest,float(Hulls.MODELS[ship.kind].get("burn",9.0)))
	profiles.sort()
	var combined_profile := 0.0
	for i in mini(profiles.size(),5):
		combined_profile += profiles[-1-i]
	var base_strength := 560.0 + 55.0 * float(Hulls.MODELS[lead.kind].size)
	return {"strength":base_strength + minf(140.0, float(profiles.size()) * 10.0) + (420.0 if lead.get("ping",0.0)>0 else 0.0),
		"profile":combined_profile, "burn":slowest}

static func seen(observer: Dictionary, contact: Dictionary, fleet_data: Dictionary) -> bool:
	if observer.id == contact.id or (contact.owner != 0 and contact.owner == Hulls.operator_id(observer)):
		return true
	var reach := float(fleet_data.strength) + signature(contact)
	var a: Vector2 = observer.galpos if observer.layer else observer.pos
	var b: Vector2 = contact.galpos if contact.layer else contact.pos
	return a.distance_squared_to(b) <= reach * reach

static func npc_contact(observer: Dictionary, contact: Dictionary, fleet_profile: float = -1.0) -> bool:
	var strength := 145.0 + 22.0 * float(Hulls.MODELS[observer.kind].size)
	var profile := signature(contact) if fleet_profile < 0.0 else fleet_profile
	var reach := strength + profile + (220.0 if observer.get("ping",0.0) > 0.0 else 0.0)
	return Vector2(observer.pos).distance_squared_to(contact.pos) <= reach * reach
