extends RefCounted

const Hulls = preload("res://hull_catalog.gd")
const Industry = preload("res://scripts/economy/industry.gd")
const HULL_ID := "gantry_ca"

static func active_ship(world) -> Dictionary:
	for ship: Dictionary in world.ships.values():
		var contract: Dictionary = ship.get("construction_contract",{})
		if contract.get("status","") in ["active","working"] and contract.client == world.player:
			return ship
	return {}

static func is_escort(ship: Dictionary, lead: Dictionary, player_id: int) -> bool:
	var contract: Dictionary = ship.get("construction_contract",{})
	return contract.get("status","") == "active" and contract.client == player_id and lead.get("captain",0) == player_id and ship.captain != 0

static func offer(world, port_id: int) -> Dictionary:
	var result := {"ok":false,"fee":0,"hull_id":HULL_ID,"ship_id":0,"reason":""}
	var yard: Dictionary = world.ports.get(port_id,{})
	var kind := Hulls.kind_for_id(HULL_ID)
	var flagship: Dictionary = world.ride()
	if kind < 0 or yard.is_empty() or yard.build > 0 or Industry.Module.YARD not in yard.modules or not Hulls.model_limit(yard,kind):
		result.reason = "需要能接纳工程巡洋舰的营业船厂。"
		return result
	result.fee = ceili(float(world.Economy.ship_quote(yard,kind).price) * float(Industry.RULES.ship_market.engineering_contract_share))
	if flagship.get("dock",0) != port_id or not world.Economy.allowed(world,flagship,yard):
		result.reason = "须驾驶旗舰停靠签约船厂。"
		return result
	if not active_ship(world).is_empty():
		result.reason = "当前工程合同仍在执行。"
		return result
	for ship: Dictionary in world.ships.values():
		var contract: Dictionary = ship.get("construction_contract",{})
		if ship.dock == port_id and ship.captain != 0 and contract.get("status","") == "available" and contract.home == port_id:
			result.ship_id = ship.id
			break
	if result.ship_id == 0 and yard.hulls[kind] <= 0:
		result.reason = "本站没有在港承包舰或完工工程舰。"
	elif world.active().wallet < result.fee:
		result.reason = "账户不足以支付本次施工服务费。"
	else:
		result.ok = true
	return result

static func hire(world, port_id: int) -> int:
	var quote := offer(world,port_id)
	if not quote.ok:
		return 0
	var yard: Dictionary = world.ports[port_id]
	var id: int = quote.ship_id
	if id == 0:
		var kind := Hulls.kind_for_id(HULL_ID)
		if not Industry.station_data(yard).withdraw_hull(kind):
			return 0
		var captain: int = world.random_person(world.NEUTRAL,port_id)
		id = world.ship(kind,0,captain,world.NEUTRAL,yard.system,yard.pos,port_id)
	var ship: Dictionary = world.ships[id]
	world.credit(world.player,-quote.fee,ship,"工程舰雇佣")
	var wages := floori(quote.fee * float(Industry.RULES.ship_market.engineering_crew_share))
	world.credit(ship.captain,wages)
	world.Treasury.post(world,yard,quote.fee-wages,"工程舰租赁")
	ship.construction_contract = {"client":world.player,"home":port_id,"site":0,"status":"active","fee":quote.fee,"signed_day":world.day}
	ship.commander_id = world.ride().id
	ship.job = {"kind":"工程承包"}
	return id

static func assign_site(world, ship_id: int, site_id: int) -> bool:
	var ship: Dictionary = world.ships.get(ship_id,{})
	var site: Dictionary = world.ports.get(site_id,{})
	if not is_escort(ship,world.ride(),world.player) or site.get("construction_ship",0) != ship_id or site.owner != world.player:
		return false
	if ship.layer or ship.dock != 0 or ship.system != site.system or ship.construction_contract.site != 0 or Vector2(ship.pos).distance_to(site.pos) > Industry.CONSTRUCTION.ship_work_range:
		return false
	ship.construction_contract.site = site_id
	ship.construction_contract.status = "working"
	ship.erase("commander_id")
	ship.battle.target_id = 0
	ship.job = {"kind":"现场施工"}
	advance(world,ship)
	return true

static func cancel(world) -> bool:
	var ship := active_ship(world)
	if ship.is_empty() or ship.construction_contract.status != "active":
		return false
	return_to_yard(world,ship)
	return true

static func return_to_yard(world, ship: Dictionary) -> void:
	ship.erase("commander_id")
	ship.battle.target_id = 0
	ship.construction_contract.status = "returning"
	ship.job = {"kind":"工程返航"}
	advance(world,ship)

static func advance(world, ship: Dictionary) -> void:
	var contract: Dictionary = ship.construction_contract
	if ship.locked or not ship.travel.is_empty():
		return
	if contract.status == "active" and not world.people.get(contract.client,{}).get("alive",false):
		return_to_yard(world,ship)
		return
	if contract.status == "working":
		var site: Dictionary = world.ports.get(contract.site,{})
		if site.is_empty() or site.build == 0:
			return_to_yard(world,ship)
		elif ship.dock != site.id:
			world.Economy.begin_trip(world,ship,site)
		return
	if contract.status != "returning":
		return
	if ship.dock == contract.home:
		contract.status = "available"
		contract.client = 0
		ship.job = {}
		return
	var yard: Dictionary = world.ports.get(contract.home,{})
	if yard.is_empty():
		return
	world.Economy.begin_trip(world,ship,yard)
	if not ship.travel.is_empty():
		return
	# A return beyond one tank may need a real fuel stop along the charted route.
	var route: Array = world.Economy.flight_route(world,ship.system,yard.system,[])
	var stops: Array = [ship.system] + route
	stops.reverse()
	for system_id in stops:
		for port_id in world.systems[system_id].ports:
			var port: Dictionary = world.ports[port_id]
			if port_id == ship.dock or port_id == yard.id or port.build > 0 or Industry.available(port,Industry.Ware.FUEL) <= 0 or not world.Economy.allowed(world,ship,port):
				continue
			world.Economy.begin_trip(world,ship,port)
			if not ship.travel.is_empty():
				return

## Player/company engineering ship operating as a B2B contractor with an employed agent captain.
static func assign_contractor(world, ship_id: int, home_port: int = 0, actor_id: int = 0) -> Dictionary:
	var vessel: Dictionary = world.ships.get(ship_id, {})
	if vessel.is_empty() or not world.can_dispatch_service(vessel, actor_id):
		return {"ok": false, "reason": "无权调度该工程舰。"}
	if not Hulls.can_build_station(vessel.kind):
		return {"ok": false, "reason": "仅工程巡洋舰（如龙门级）可执行外包施工。"}
	if int(vessel.captain) in [0, world.player]:
		return {"ok": false, "reason": "需先雇佣 NPC 代理人船长执掌该工程舰。"}
	if not vessel.get("passengers", []).is_empty():
		return {"ok": false, "reason": "请先将乘客送达，再改派工程任务。"}
	if vessel.has("construction_contract") and vessel.construction_contract.get("status", "") in ["active", "working"]:
		return {"ok": false, "reason": "该工程舰正处于其他施工合同中。"}
	var home := home_port if world.ports.has(home_port) else (int(vessel.dock) if int(vessel.dock) != 0 else int(world.systems[0].ports[0]))
	if vessel.get("order_queue", []).is_empty():
		world.Economy.release_reservation(world, vessel)
		vessel.travel = {}
	vessel.erase("commander_id")
	vessel.erase("fleet_role")
	vessel.erase("resume_job")
	vessel.job = {"kind": "工程承包", "home_port": home, "site": 0, "fee": 0, "phase": 0}
	vessel.default_behavior = vessel.job.duplicate(true)
	world.event("%s 代理人 %s 已开始承接星区轨道工程订单。" % [world.HULLS[vessel.kind], world.name_of(int(vessel.captain))])
	return {"ok": true, "ship": ship_id, "home_port": home}

static func _contractor_fee(world, site: Dictionary, captain: Dictionary) -> int:
	var is_new: bool = int(site.get("build", 0)) > 0
	var base_cost := int(Industry.CONSTRUCTION.foundation.credits if is_new else Industry.CONSTRUCTION.expansion.credits)
	var stew := float(captain.stats.stewardship) if not captain.is_empty() else 6.0
	return clampi(roundi(float(base_cost) * (0.15 + stew * 0.008)), 320, 1400)

static func _settle_contractor_fee(world, vessel: Dictionary, site: Dictionary, fee: int) -> int:
	var paid := 0
	var avail_st: int = world.Treasury.available(site)
	if avail_st >= fee and world.Treasury.post(world, site, -fee, "外包工程结算", true):
		paid = fee
	elif int(site.flag) >= 0 and world.factions.has(int(site.flag)) and int(world.factions[int(site.flag)].get("treasury", 0)) >= fee:
		world.factions[int(site.flag)].treasury -= fee
		paid = fee
	elif int(site.owner) > 0 and world.people.has(int(site.owner)) and int(world.people[int(site.owner)].wallet) >= fee:
		world.credit(int(site.owner), -fee)
		paid = fee
	elif avail_st > 0 and world.Treasury.post(world, site, -avail_st, "外包工程结算", true):
		paid = avail_st
	if paid <= 0:
		return 0
	var cap_id := int(vessel.captain)
	var wages := floori(float(paid) * float(Industry.RULES.ship_market.engineering_crew_share))
	if cap_id != 0 and world.people.has(cap_id):
		world.credit(cap_id, wages)
	var net := paid - wages
	if world.ports.has(vessel.get("station_owner", 0)):
		world.Treasury.post(world, world.ports[vessel.station_owner], net, "工程承包收入", false)
	elif vessel.has("firm") and world.firms.has(int(vessel.firm)):
		var firm: Dictionary = world.firms[int(vessel.firm)]
		firm.treasury = int(firm.treasury) + net
		firm.revenue = int(firm.get("revenue", 0)) + net
		firm.operating_profit = int(firm.get("operating_profit", 0)) + net
		world.Finances.record(world, int(firm.director), {"id": int(vessel.firm), "name": firm.name, "ledger_type": "company"}, "工程承包收入", net, false, true)
	elif int(vessel.owner) > 0 and world.people.has(int(vessel.owner)):
		world.credit(int(vessel.owner), net, vessel, "工程承包收入")
		world.Finances.record(world, int(vessel.owner), vessel, "工程承包收入", net, false, false)
	if int(site.flag) >= 0 and world.oversees(world.ship_principal(vessel)):
		world.change_faction_trust(int(site.flag), world.player, 2, "外包工程竣工：%s" % site.name)
	return paid

static func step_contractor(world, vessel: Dictionary) -> void:
	if not Hulls.can_build_station(vessel.kind) or int(vessel.captain) in [0, world.player] or vessel.locked:
		return
	var job: Dictionary = vessel.job
	var cap: Dictionary = world.people.get(int(vessel.captain), {})
	var site_id := int(job.get("site", 0))
	if site_id != 0:
		var site: Dictionary = world.ports.get(site_id, {})
		if site.is_empty() or world.Economy.forbidden(vessel, site) or world.hostile(int(vessel.flag), int(site.flag)):
			if not site.is_empty() and int(site.get("contractor_ship", 0)) == int(vessel.id):
				site.erase("contractor_ship")
			job.site = 0
			job.fee = 0
			return
		var still_building: bool = int(site.get("build", 0)) > 0 or int(site.get("expansion", 0)) > 0
		if not still_building:
			var paid := _settle_contractor_fee(world, vessel, site, int(job.get("fee", 320)))
			if int(site.get("contractor_ship", 0)) == int(vessel.id):
				site.erase("contractor_ship")
			job.site = 0
			job.fee = 0
			if world.oversees(world.ship_principal(vessel)) and paid > 0:
				world.event("工程代理人 %s 完成 %s 施工合同，结算工程款 ¢%d。" % [world.name_of(int(vessel.captain)), site.name, paid])
			return
		if int(vessel.dock) == site_id or (int(vessel.system) == int(site.system) and not vessel.layer):
			var stew := int(cap.stats.stewardship) if not cap.is_empty() else 6
			var traits: Array = cap.get("ck_traits", [])
			var speed_days := clampi(2 + stew / 4 + (2 if "勤勉" in traits else 0), 2, 8)
			if int(site.get("build", 0)) > 0:
				site.build = maxi(1, int(site.build) - speed_days)
			elif int(site.get("expansion", 0)) > 0:
				site.expansion = maxi(1, int(site.expansion) - speed_days)
			if ("贪婪" in traits or "狡诈" in traits) and world.rng.randf() < 0.08:
				var secrets: Array = cap.get("secrets", [])
				if not secrets.any(func(s): return s is Dictionary and s.get("kind", "") == "kickback"):
					secrets.append({"kind": "kickback", "port": site_id, "day": world.day})
					cap.secrets = secrets
		elif vessel.travel.is_empty():
			world.Economy.begin_trip(world, vessel, site)
		return
	# Seek a nearby construction / expansion site without an assigned contractor
	var best_site: Dictionary = {}
	var best_dist := INF
	for st: Dictionary in world.ports.values():
		if int(st.get("build", 0)) <= 0 and int(st.get("expansion", 0)) <= 0:
			continue
		if int(st.get("contractor_ship", 0)) != 0 and world.ships.has(int(st.contractor_ship)):
			continue
		if world.Economy.forbidden(vessel, st) or world.hostile(int(vessel.flag), int(st.flag)):
			continue
		var fee := _contractor_fee(world, st, cap)
		var can_pay: bool = world.Treasury.available(st) >= fee or (int(st.flag) >= 0 and int(world.factions.get(int(st.flag), {}).get("treasury", 0)) >= fee) or (int(st.owner) > 0 and int(world.people.get(int(st.owner), {}).get("wallet", 0)) >= fee)
		if not can_pay:
			continue
		var d: float = world.distance(int(vessel.system), int(st.system))
		if d < best_dist:
			best_dist = d
			best_site = st
	if not best_site.is_empty():
		var fee := _contractor_fee(world, best_site, cap)
		job.site = int(best_site.id)
		job.fee = fee
		best_site.contractor_ship = int(vessel.id)
		world.Economy.begin_trip(world, vessel, best_site)
		if world.oversees(world.ship_principal(vessel)):
			world.event("工程代理人 %s 接下 %s 轨道工程合同（合同额 ¢%d），已启航赴工地。" % [world.name_of(int(vessel.captain)), best_site.name, fee])
