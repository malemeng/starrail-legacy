extends RefCounted

const COMMISSION := 2
const DELIVERY := 8
const PAYOUT := 210
const BONUS := 40

static func origin(world) -> int:
	return world.systems[0].ports[0]

static func mine(world) -> int:
	return world.systems[1].ports[0]

static func foundry(world) -> int:
	return world.systems[1].ports[1]

static func setup(world) -> void:
	var dawn: Dictionary = world.people[world.ports[origin(world)].manager]
	dawn.name = "沈照"
	dawn.look = {"face": 2, "skin": 1, "cut": 1, "hair": 0, "eyes": 1, "iris": 3, "nose": 1, "mouth": 1, "wear": 0, "mark": 2}
	dawn.birth = -42 * 360
	var recipient: int = world.random_person(world.NEUTRAL, foundry(world))
	world.ports[foundry(world)].manager = recipient
	var foreman: Dictionary = world.people[recipient]
	foreman.name = "罗启山"
	foreman.look = {"face": 1, "skin": 2, "cut": 3, "hair": 3, "eyes": 0, "iris": 1, "nose": 2, "mouth": 2, "wear": 3, "mark": 1}
	foreman.birth = -57 * 360

static func active(world) -> Dictionary:
	var commission: Dictionary = world.contracts.get(world.player, {})
	return commission if commission.get("type", -1) == COMMISSION else {}

static func accept(world) -> bool:
	var actor: Dictionary = world.active()
	if actor.loc != origin(world) or world.contracts.has(actor.id) or actor.get("first_berth", false) or world.ports[foundry(world)].manager == 0:
		return false
	world.contracts[actor.id] = {"type": COMMISSION, "target": foundry(world), "issuer": world.ports[origin(world)].manager,
		"recipient": world.ports[foundry(world)].manager, "issued": world.day}
	world.event("%s 接下了「熄火之前」：炉心转运站需要 8 单位矿石。" % actor.name)
	return true

static func deliver(world) -> bool:
	var commission := active(world)
	var vessel: Dictionary = world.ride()
	if commission.is_empty() or vessel.is_empty() or vessel.dock != commission.target or vessel.cargo[0] < DELIVERY:
		return false
	if not world.can_dock(vessel, world.ports[commission.target]):
		return false
	vessel.cargo[0] -= DELIVERY
	world.ports[commission.target].stock[0] += DELIVERY
	world.credit(world.player, PAYOUT)
	world.active().first_berth = true
	world.active().first_berth_return = false
	world.contracts.erase(world.player)
	for person_id in [commission.issuer, commission.recipient]:
		var contact: Dictionary = world.people.get(person_id, {})
		if contact.get("alive", false):
			contact.opinions[world.player] = mini(100, int(contact.opinions.get(world.player, 0)) + 16)
	world.event("「熄火之前」：炉心收到原矿，%s 的名字被记进供货账本。" % world.name_of(world.player))
	return true

static func return_to_port(world) -> bool:
	var actor: Dictionary = world.active()
	if actor.loc != origin(world) or not actor.get("first_berth", false) or actor.get("first_berth_return", false):
		return false
	actor.first_berth_return = true
	world.credit(actor.id, BONUS)
	world.event("晨曦航务局结清了 %s 的首航返程津贴。" % actor.name)
	return true

static func objective(world) -> String:
	if world.player == 0:
		return ""
	var commission := active(world)
	if commission.is_empty():
		return ""
	if world.ride().get("cargo", [0])[0] < DELIVERY:
		return "熄火之前  /  在铁尘矿带采集或购买 8 单位矿石"
	return "熄火之前  /  将 8 单位矿石送到炉心转运站"
