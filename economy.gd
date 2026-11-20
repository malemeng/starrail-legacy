extends RefCounted

const BASE := [9, 27, 8, 16, 43, 13, 75]
const Hulls = preload("res://hull_catalog.gd")
const Celestial = preload("res://celestial.gd")

static func colony_defaults(wild: bool) -> Dictionary:
	return {"pop":18 if wild else 570,"pop_cap":180 if wild else 1150,"stability":66.0 if wild else 81.0,
		"tax_rate":0.10,"black":[0,0,0,28,10,12,16],"tax_remainder":0.0,"market_used":0,"market_day":-1,"shortage":0}

static func demand(station: Dictionary) -> int:
	return maxi(1, ceili(station.pop / 720.0))

static func population_day(world) -> void:
	for station in world.ports.values():
		if station.build > 0:
			continue
		var demand_scale := demand(station)
		var blockaded := false
		if world.day % 6 == 0 or not station.has("blockaded"):
			for ship in world.ships.values():
				if ship.job.get("kind","") == "攻城" and ship.job.get("target",0) == station.id and ship.job.get("arrived",false):
					blockaded = true
					break
			station.blockaded = blockaded
		var shortage := 0
		for ware in [2,3,5]:
			var need := demand_scale if ware != 2 else maxi(1,ceili(demand_scale * 0.5))
			var supplied := mini(need,station.stock[ware])
			station.stock[ware] -= supplied
			shortage += need - supplied
		var supplied: bool = shortage == 0 and not station.blockaded
		station.shortage = 0 if supplied else station.shortage + 1
		station.stability = clampf(station.stability + (0.48 if supplied else -1.2 - shortage * 0.21), 0.0, 100.0)
		if supplied and station.stability >= 58 and world.day % 6 == 0:
			station.pop = mini(station.pop_cap, station.pop + maxi(1, floori(station.pop * 0.016)))
		elif not supplied and station.shortage > 7 and world.day % 6 == 0:
			var refugees := mini(station.pop - 1, maxi(1, floori(station.pop * 0.055)))
			station.pop -= refugees
			var refuge: Dictionary = {}
			var nearest := INF
			for other in world.ports.values():
				if other.id == station.id or other.build > 0 or other.stability < 65.0 or other.pop >= other.pop_cap or world.hostile(station.flag, other.flag):
					continue
				var gap: float = world.distance(station.system,other.system)
				if gap < nearest:
					nearest = gap
					refuge = other
			if not refuge.is_empty():
				refuge.pop = mini(refuge.pop_cap, refuge.pop + refugees)
			if station.shortage == 12 and refugees > 0:
				world.event("%s 断供，%s 位居民撤离。" % [station.name, refugees])
		if station.stability <= 16.0 and station.shortage == 30:
			world.event("%s 爆发补给骚乱，站务委员会要求自治。" % station.name)
		station.tax_remainder += station.pop * station.tax_rate * station.stability / 8500.0
		var taxes := floori(station.tax_remainder)
		station.tax_remainder -= taxes
		if station.owner != 0:
			world.credit(station.owner,taxes)
		elif world.factions.has(station.flag):
			world.factions[station.flag].treasury += taxes

static func crew(world, amount: int) -> int:
	var vessel: Dictionary = world.ride()
	if vessel.is_empty() or vessel.dock == 0 or amount == 0:
		return 0
	var station: Dictionary = world.ports[vessel.dock]
	if not allowed(world,vessel,station) or station.build > 0:
		return 0
	var count := mini(amount, mini(Hulls.crew_limits(vessel.kind).y - vessel.crew,mini(maxi(0,station.pop-10),world.active().wallet / 3))) if amount > 0 else -mini(-amount,mini(vessel.crew, station.pop_cap - station.pop))
	vessel.crew += count
	station.pop -= count
	if count > 0:
		world.credit(world.player, -3 * count)
	return count

static func allowed(world, vessel: Dictionary, station: Dictionary) -> bool:
	return world.can_dock(vessel, station) and (vessel.flag < 0 or world.firms.get(station.firm, {}).get("embargo", -1) != vessel.flag)

static func revenue(world, station: Dictionary, payment: int) -> void:
	var margin := int(payment / 8)
	if station.firm != 0:
		var enterprise: Dictionary = world.firms[station.firm]
		enterprise.revenue += margin
		world.credit(enterprise.director, margin)
	elif station.owner != 0:
		world.credit(station.owner, margin)

static func incorporate(world, port_id: int, label: String) -> bool:
	var station: Dictionary = world.ports.get(port_id, {})
	if station.is_empty() or station.owner != world.player or station.build != 0 or station.firm != 0 or world.active().wallet < 180 or label.strip_edges().is_empty():
		return false
	world.credit(world.player, -180)
	world.incorporate(label, world.player, port_id)
	world.event(label + " 已注册成立。")
	return true

static func price(station: Dictionary, ware: int, buying: bool, origin: int = -1, black: bool = false) -> int:
	var target := 65.0 if ware != 2 else 90.0
	var stock: Array = station.black if black else station.stock
	var cost: float = BASE[ware] * clampf(1.55 - stock[ware] / target * 0.48, 0.55, 1.85)
	var tariff: float = 0.0 if black else station.get("tax_rate",0.0)
	return maxi(1, roundi(cost * (1.06 + tariff if buying else 0.91 - tariff) * (0.94 if origin == 1 and buying else 1.0)))

static func limit(world, station: Dictionary, ware: int, buying: bool, black: bool) -> int:
	var vessel: Dictionary = world.ride()
	var character: Dictionary = world.active()
	if vessel.is_empty() or (not black and ware == 6):
		return 0
	var remaining := maxi(0, 24 + int(station.pop / 10) - (station.market_used if station.market_day == world.day else 0))
	var stock: Array = station.black if black else station.stock
	var quote := price(station,ware,buying,character.origin,black)
	return mini(remaining,mini(stock[ware],mini(world.cargo_free(vessel),character.wallet / quote))) if buying else mini(remaining,vessel.cargo[ware])

static func trade(world, port_id: int, ware: int, amount: int, black: bool = false) -> int:
	var vessel: Dictionary = world.ride()
	var character: Dictionary = world.active()
	var station: Dictionary = world.ports.get(port_id, {})
	if station.is_empty() or vessel.is_empty() or vessel.dock != port_id or ware not in range(world.WARES.size()) or amount == 0:
		return 0
	if station.build > 0 or (black and not world.is_regular(station)) or (not black and not allowed(world, vessel, station)):
		return 0
	var buying := amount > 0
	var quote := price(station, ware, buying, character.origin, black)
	var quantity := mini(absi(amount),limit(world,station,ware,buying,black))
	if quantity <= 0:
		return 0
	var moved := quantity if buying else -quantity
	var stock: Array = station.black if black else station.stock
	stock[ware] -= moved
	vessel.cargo[ware] += moved
	if station.market_day != world.day:
		station.market_day = world.day
		station.market_used = 0
	station.market_used += quantity
	world.credit(world.player, -moved * quote)
	if black:
		character.suspicion = mini(100, int(character.get("suspicion",0)) + quantity * (3 if ware == 6 else 1))
	elif moved > 0:
		revenue(world, station, moved * quote)
	if not black:
		world.chart(port_id)
	world.combat_event("trade", station.pos, station.system)
	return moved

static func inspect_departure(world, vessel: Dictionary) -> int:
	var actor: Dictionary = world.active()
	var suspicion: int = actor.get("suspicion",0)
	if suspicion == 0 or vessel.dock == 0 or not world.is_regular(world.ports[vessel.dock]):
		return 0
	actor.suspicion = maxi(0,suspicion - 11)
	if world.rng.randi_range(1,100) > suspicion:
		return 0
	var fine := mini(actor.wallet,25 + suspicion * 2 + vessel.cargo[6] * 3)
	world.credit(actor.id,-fine)
	vessel.cargo[6] = 0
	world.event("巡逻队盘查：违禁品被扣，罚款 %d。" % fine)
	return fine

static func buy_ship(world, port_id: int, kind: int) -> int:
	var station: Dictionary = world.ports.get(port_id, {})
	var character: Dictionary = world.active()
	if station.is_empty() or station.build != 0 or character.loc != port_id or kind not in range(Hulls.MODELS.size()) or station.hulls[kind] <= 0:
		return 0
	var price_tag: int = Hulls.MODELS[kind].price
	if character.wallet < price_tag or not Hulls.model_limit(station, kind) or not allowed(world, {"flag": character.flag, "kind": kind}, station):
		return 0
	world.credit(world.player, -price_tag)
	station.hulls[kind] -= 1
	return world.ship(kind, world.player, 0, character.flag, station.system, station.pos, port_id)

static func supply(world, repair: bool) -> bool:
	var vessel: Dictionary = world.ride()
	if vessel.is_empty() or vessel.dock == 0:
		return false
	var station: Dictionary = world.ports[vessel.dock]
	if station.build > 0 or not world.can_dock(vessel, station):
		return false
	var wallet: int = world.active().wallet
	if repair:
		var max_hp: int = world.HULL_HP[vessel.kind]
		var max_armor: float = Hulls.COMBAT[vessel.kind].armor
		var repair_scale := Hulls.crew_efficiency(vessel)
		var hull_cost := mini(wallet, ceili((max_hp - vessel.hp) / 3.0 / repair_scale))
		var armor_cost := mini(wallet - hull_cost, ceili((max_armor - vessel.battle.armor) / 4.0 / Hulls.crew_efficiency(vessel)))
		var cost := hull_cost + armor_cost
		vessel.hp = minf(max_hp, vessel.hp + 3.0 * hull_cost * repair_scale)
		vessel.battle.armor = minf(max_armor, vessel.battle.armor + 4.0 * armor_cost * Hulls.crew_efficiency(vessel))
		world.credit(world.player, -cost)
		return cost > 0
	var from_cargo := mini(vessel.cargo[2], ceili(100.0 - vessel.fuel))
	vessel.cargo[2] -= from_cargo
	vessel.fuel = minf(100, vessel.fuel + from_cargo)
	var units := mini(floori(100.0 - vessel.fuel), mini(station.stock[2], wallet))
	station.stock[2] -= units
	vessel.fuel += units
	world.credit(world.player, -units)
	return units + from_cargo > 0

static func deploy(world, kind: int, pos: Vector2) -> int:
	var vessel: Dictionary = world.ride()
	if vessel.is_empty() or vessel.dock != 0 or vessel.system < 0 or world.active().wallet < 120 or kind not in range(world.MODULES.size()):
		return 0
	if world.systems[vessel.system].ports.size() >= 6:
		return 0
	var orbit := Celestial.orbit_at(world.systems[vessel.system],pos)
	if orbit < 0:
		return 0
	for port_id in world.systems[vessel.system].ports:
		if pos.distance_to(world.ports[port_id].pos) < 145:
			return 0
	world.credit(world.player, -120)
	var port_id: int = world.port(vessel.system, "%s · %s站 %s" % [world.active().house, world.MODULES[kind], world.next_id], pos, world.active().flag, world.player, kind, false)
	world.ports[port_id].orbit = orbit
	world.ports[port_id].scan = true
	world.event("已铺设工地：需要送达 20 单位合金，再施工 30 日。")
	return port_id

static func donate(world, port_id: int) -> int:
	var vessel: Dictionary = world.ride()
	var station: Dictionary = world.ports.get(port_id, {})
	if vessel.is_empty() or vessel.dock != port_id or station.is_empty() or not world.oversees(station.owner) or station.build == 0:
		return 0
	var moved := mini(vessel.cargo[1], 20 - station.stock[1])
	vessel.cargo[1] -= moved
	station.stock[1] += moved
	return moved

static func expand(world, port_id: int, kind: int) -> bool:
	var vessel: Dictionary = world.ride()
	var station: Dictionary = world.ports.get(port_id, {})
	if kind not in range(world.MODULES.size()) or vessel.is_empty() or station.is_empty() or vessel.dock != station.id or not world.oversees(station.owner):
		return false
	if station.build > 0 or station.extension != -1 or world.active().wallet < 90 or vessel.cargo[1] < 16:
		return false
	world.credit(world.player, -90)
	vessel.cargo[1] -= 16
	station.extension = kind
	station.expansion = 30
	return true

static func assign(world, ship_id: int, person_id: int, kind: String, source: int = 0, target: int = 0) -> bool:
	var vessel: Dictionary = world.ships.get(ship_id, {})
	var worker: Dictionary = world.people.get(person_id, {})
	if vessel.is_empty() or worker.is_empty() or not world.oversees(vessel.owner) or vessel.captain == world.player:
		return false
	if not worker.alive or worker.id == world.player or worker.employer not in [0, vessel.owner]:
		return false
	if vessel.captain != person_id and (worker.ship != 0 or worker.loc != world.active().loc or worker.loc != vessel.dock or vessel.dock == 0):
		return false
	if kind in ["贸易", "采矿"] and (source == target or not world.ports.has(source) or not world.ports.has(target)):
		return false
	if worker.employer == 0:
		if world.active().wallet < 55:
			return false
		world.credit(world.player, -55)
		world.credit(person_id, 55)
	if vessel.captain not in [0, person_id]:
		world.people[vessel.captain].ship = 0
		world.people[vessel.captain].loc = vessel.dock
	worker.employer = vessel.owner
	worker.ship = ship_id
	vessel.captain = person_id
	vessel.job = {"kind": kind, "source": source, "target": target, "phase": 0, "system": vessel.system}
	world.event("%s 接管%s，任务：%s。" % [worker.name, world.HULLS[vessel.kind], kind])
	return true

static func manager(world, port_id: int, person_id: int) -> bool:
	var station: Dictionary = world.ports.get(port_id, {})
	var worker: Dictionary = world.people.get(person_id, {})
	if station.is_empty() or worker.is_empty() or not world.oversees(station.owner) or station.build != 0:
		return false
	if world.active().wallet < 45 or worker.loc != world.active().loc or worker.loc == 0 or worker.ship != 0 or not worker.alive or worker.employer != 0 or worker.id == world.player:
		return false
	for flag in world.factions:
		if world.factions[flag].leader == worker.id:
			return false
	for other in world.ports:
		if world.ports[other].manager == person_id:
			return false
	if station.manager != 0:
		world.people[station.manager].employer = 0
	world.credit(world.player, -45)
	world.credit(person_id, 45)
	worker.employer = station.owner
	worker.loc = port_id
	station.manager = person_id
	return true

static func produce(world, station: Dictionary) -> void:
	if station.build > 0:
		if station.stock[1] >= 20:
			station.build = maxi(0, station.build - 6)
			if station.build == 0:
				station.stock[1] -= 20
				station.stock[2] += 20
				world.event(station.name + "竣工。")
		return
	if station.expansion > 0:
		station.expansion = maxi(0, station.expansion - 6)
		if station.expansion == 0:
			station.pop_cap += 460 if station.extension == 4 else 140
			world.event("%s 的扩建模块竣工。" % station.name)
	run_module(world, station, station.module)
	if station.expansion == 0 and station.extension >= 0:
		run_module(world, station, station.extension)

static func run_module(world, station: Dictionary, kind: int) -> void:
	var efficiency := clampi(int(station.pop / 260),0,5) + (1 if station.manager != 0 and world.people[station.manager].origin == 2 else 0)
	if station.stability < 25:
		efficiency = 0
	if not world.systems[station.system].get("wild",false):
		station.stock[3] = mini(160,station.stock[3]+5+efficiency)
		station.stock[5] = mini(160,station.stock[5]+5+efficiency)
		station.stock[2] = mini(145,station.stock[2]+5+efficiency)
	match kind:
		0:
			station.stock[0] = mini(155, station.stock[0] + 10 + efficiency)
			station.stock[2] = mini(125, station.stock[2] + 3)
		1:
			var batches := maxi(0, mini((station.stock[0] / 3) as int, mini(4 + efficiency, (145 - station.stock[1]) / 2)))
			station.stock[0] -= 3 * batches
			station.stock[1] += 2 * batches
			station.stock[4] = mini(90, station.stock[4] + batches / 2)
		2:
			if world.day % 30 == 0:
				var start := (int(world.day / 30) + int(station.id)) % Hulls.MODELS.size()
				for offset in range(Hulls.MODELS.size()):
					var model := (start + offset) % Hulls.MODELS.size()
					var recipe: int = Hulls.MODELS[model].recipe
					if not Hulls.model_limit(station, model):
						continue
					if station.hulls[model] >= (1 if Hulls.MODELS[model].size == Hulls.Size.CAPITAL else 3):
						continue
					if station.stock[1] < recipe:
						break
					station.stock[1] -= recipe
					station.hulls[model] += 1
					break
		3:
			if station.stock[1] >= 2 and station.defense < 78:
				station.stock[1] -= 2
				station.defense += 4
		4:
			station.stock[5] = mini(160,station.stock[5]+12+efficiency)
			station.stock[3] = mini(160,station.stock[3]+9+efficiency)

static func exchange(world, vessel: Dictionary, station: Dictionary, ware: int, amount: int) -> bool:
	var account: int = vessel.owner if vessel.owner else vessel.captain
	var fleet_budget: int = world.factions.get(vessel.flag, {}).get("treasury", 0)
	var budget: int = world.people[account].wallet if vessel.owner != 0 or not world.factions.has(vessel.flag) else fleet_budget
	var balance := 0
	if amount > 0:
		var quote := price(station, ware, true)
		var quantity := mini(amount, mini(world.cargo_free(vessel), mini(station.stock[ware], budget / quote)))
		if quantity < 1:
			return false
		station.stock[ware] -= quantity
		vessel.cargo[ware] += quantity
		balance = -quantity * quote
		revenue(world, station, -balance)
	else:
		var quantity: int = vessel.cargo[ware]
		if quantity < 1:
			return false
		balance = quantity * price(station, ware, false)
		station.stock[ware] += quantity
		vessel.cargo[ware] = 0
	if vessel.owner == 0 and world.factions.has(vessel.flag):
		world.factions[vessel.flag].treasury += balance
	else:
		world.credit(account, balance)
	return true

static func begin_trip(world, vessel: Dictionary, target: Dictionary) -> void:
	var distance: float = world.distance(vessel.system, target.system)
	world.depart(vessel)
	vessel.travel = {"port": target.id, "eta": world.day + clampi(ceili(distance / 35.0), 6, 36)}

static func trade_plan(world, vessel: Dictionary) -> Dictionary:
	var highest := 0.0
	var plan := {}
	for source_id in world.ports:
		var source: Dictionary = world.ports[source_id]
		if not allowed(world, vessel, source) or source.build > 0:
			continue
		var ware := 0 if source.module == 0 else 1
		if source.module not in [0, 1] or source.stock[ware] < 9:
			continue
		for target_id in world.ports:
			var target: Dictionary = world.ports[target_id]
			if target.module != ware + 1 or target.stock[ware] >= 80 or target.build > 0 or not allowed(world, vessel, target):
				continue
			var profit := price(target, ware, false) - price(source, ware, true)
			var score: float = (profit + 3.0) / (10 + world.distance(vessel.system, source.system) * 0.018 + world.distance(source.system, target.system) * 0.025)
			if score > highest:
				highest = score
				plan = {"source": source_id, "target": target_id, "ware": ware, "phase": 0}
	return plan

static func step_ship(world, vessel: Dictionary) -> void:
	if vessel.captain == 0 or vessel.captain == world.player or vessel.locked or vessel.job.is_empty():
		return
	if not vessel.travel.is_empty():
		if world.day < vessel.travel.eta:
			return
		var stop: Dictionary = world.ports[vessel.travel.port]
		vessel.travel = {}
		if not world.berth(vessel, stop.id):
			if vessel.owner == 0:
				vessel.job.erase("source")
			return
	if vessel.job.kind == "护航":
		if vessel.owner != 0 and vessel.dock != 0:
			var commander: Dictionary = world.people[vessel.owner]
			var lead: Dictionary = world.ships.get(commander.ship, {})
			if not lead.is_empty() and lead.dock == 0 and lead.system == vessel.system:
				world.depart(vessel)
				vessel.pos += Vector2(25, -15)
		return
	if vessel.job.kind == "攻城":
		return
	if not vessel.job.has("source") and vessel.owner == 0:
		vessel.job.merge(trade_plan(world, vessel), true)
	if not vessel.job.has("source"):
		return
	var loading: bool = vessel.job.phase == 0
	var goal: Dictionary = world.ports[vessel.job.source if loading else vessel.job.target]
	if not allowed(world, vessel, goal) or goal.build > 0:
		if vessel.owner == 0:
			vessel.job.erase("source")
		return
	if vessel.dock != goal.id:
		begin_trip(world, vessel, goal)
		return
	var ware: int = vessel.job.get("ware", 0 if world.ports[vessel.job.source].module == 0 else 1)
	if vessel.job.kind == "采矿":
		ware = 0
		if loading:
			var field: Dictionary = world.systems[goal.system]
			var quantity := mini(Hulls.MODELS[vessel.kind].mine, mini(field.ore, world.cargo_free(vessel)))
			vessel.cargo[0] += quantity
			field.ore -= quantity
			vessel.job.phase = 1 if quantity > 0 else 0
			return
	if exchange(world, vessel, goal, ware, 25 if loading else -1) or not loading:
		vessel.job.phase = 1 if loading else 0
		if not loading and vessel.owner == 0:
			vessel.job.erase("source")
	elif vessel.owner == 0:
		vessel.job.erase("source")

static func weapon_price(key: String, buying: bool = true, black: bool = false) -> int:
	if key.is_empty() or not Hulls.WEAPONS.has(key):
		return 0
	var weapon: Dictionary = Hulls.WEAPONS[key]
	var base := float(weapon.op * 14 + weapon.mount * 16)
	if "_" in key:
		base *= 1.25
	if black and buying:
		base *= 1.12
	return maxi(10, roundi(base if buying else base * 0.65))

static func station_weapons(world, station: Dictionary, black: bool = false) -> Array:
	if station.is_empty() or station.build > 0:
		return []
	var catalog: Array = ["pulse", "rail", "howitzer", "missile", "pd"]
	var heavy: bool = station.module in [2, 3] or station.get("capital_yard", false) or black
	if heavy:
		catalog.append("lance")
	var variants: Array = []
	for key in Hulls.WEAPONS.keys():
		if "_" in key:
			var weapon: Dictionary = Hulls.WEAPONS[key]
			if heavy or weapon.mount <= 2:
				variants.append(key)
	variants.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:weapons:%d:%d:%s" % [str(world.settings.get("seed", "")), station.id, int(world.day / 30), str(black)])
	var count := 10 if (black or station.module == 2) else 6
	for _pick in range(mini(count, variants.size())):
		var index := rng.randi_range(0, variants.size() - 1)
		var chosen: String = variants[index]
		if chosen not in catalog:
			catalog.append(chosen)
	return catalog

static func refit_slot(world, port_id: int, slot_index: int, weapon_key: String, black: bool = false) -> bool:
	var vessel: Dictionary = world.ride()
	var station: Dictionary = world.ports.get(port_id, {})
	if vessel.is_empty() or vessel.dock != port_id or station.is_empty() or station.build > 0:
		return false
	if black and not world.is_regular(station):
		return false
	if not black and not allowed(world, vessel, station):
		return false
	var spec: Dictionary = Hulls.COMBAT[vessel.kind]
	if slot_index not in range(spec.slots.size()):
		return false
	var old_key: String = vessel.fit.weapons[slot_index]
	if old_key == weapon_key:
		return false
	if not weapon_key.is_empty():
		if not Hulls.WEAPONS.has(weapon_key):
			return false
		if weapon_key not in station_weapons(world, station, black):
			return false
	var candidate: Dictionary = vessel.fit.duplicate(true)
	candidate.weapons[slot_index] = weapon_key
	if Hulls.fitting_cost(vessel.kind, candidate) < 0:
		return false
	var net := weapon_price(weapon_key, true, black) - weapon_price(old_key, false, false)
	var actor: Dictionary = world.active()
	if net > 0 and actor.wallet < net:
		return false
	world.credit(world.player, -net)
	vessel.fit = candidate
	if slot_index < vessel.battle.cooldowns.size():
		vessel.battle.cooldowns[slot_index] = 0.0
	if black and not weapon_key.is_empty():
		actor.suspicion = mini(100, int(actor.get("suspicion", 0)) + 4)
	world.combat_event("trade", station.pos, station.system)
	return true

static func refit_tuning(world, port_id: int, caps_delta: int, vents_delta: int) -> bool:
	var vessel: Dictionary = world.ride()
	var station: Dictionary = world.ports.get(port_id, {})
	if vessel.is_empty() or vessel.dock != port_id or station.is_empty() or station.build > 0 or not allowed(world, vessel, station):
		return false
	if caps_delta == 0 and vents_delta == 0:
		return false
	var candidate: Dictionary = vessel.fit.duplicate(true)
	candidate.caps = int(candidate.caps) + caps_delta
	candidate.vents = int(candidate.vents) + vents_delta
	if Hulls.fitting_cost(vessel.kind, candidate) < 0:
		return false
	var added := maxi(0, caps_delta) + maxi(0, vents_delta)
	var removed := maxi(0, -caps_delta) + maxi(0, -vents_delta)
	var net := added * 8 - removed * 4
	if net > 0 and world.active().wallet < net:
		return false
	world.credit(world.player, -net)
	vessel.fit = candidate
	world.combat_event("trade", station.pos, station.system)
	return true

static func refit_group(world, port_id: int, slot_index: int, group: int) -> bool:
	var vessel: Dictionary = world.ride()
	var station: Dictionary = world.ports.get(port_id, {})
	if vessel.is_empty() or vessel.dock != port_id or station.is_empty() or station.build > 0:
		return false
	if slot_index not in range(vessel.fit.groups.size()) or group not in [1, 2, 3]:
		return false
	vessel.fit.groups[slot_index] = group
	return true

static func advance(world) -> void:
	for station in world.ports.values():
		produce(world, station)
	for vessel in world.ships.values():
		step_ship(world, vessel)
	if world.day % 30 == 0:
		for index in range(world.core_count):
			var system: Dictionary = world.systems[index]
			system.ore = mini(180, system.ore + 14)
