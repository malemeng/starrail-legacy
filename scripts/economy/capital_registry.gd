extends RefCounted

const Config = preload("res://data/economy/industry.json")
const StationEquity = preload("res://scripts/economy/station_equity.gd")
const LIMIT := 2147483647

static func register_site(site: Dictionary) -> void:
	var value := StationEquity.net_assets(site)
	var par := int(Config.data.equity.par_value)
	site.par_value=par
	site.paid_in_capital=value
	site.charter_units=maxi(1,value/par)

static func entity(world, scope: String, id: int) -> Dictionary:
	if scope=="company":
		return world.firms.get(id,{})
	return world.ports.get(id,{}) if scope=="station" else {}

static func overview(world, scope: String, id: int) -> Dictionary:
	var record := entity(world,scope,id)
	if record.is_empty():
		return {}
	var issued := 0
	var treasury := 0
	var assets := 0
	var price := 0
	var signer := 0
	var controller := 0
	var owned := 0
	var rows := []
	if scope=="company":
		var company: Dictionary = world.Equity.overview(world,id)
		issued = company.issued
		treasury = company.treasury_shares
		assets = company.net_assets
		price = company.unit_price
		owned = company.owned
		for holder in company.holders:
			rows.append({"party":holder.person,"units":holder.shares})
			if int(holder.shares)*2>issued-treasury:
				controller=holder.person
		if int(world.Equity.supporters(world,id).get(record.director,0))*2>issued-treasury:
			signer=record.director
	else:
		var table: Dictionary = world.StationEquity.cap_table(world,record)
		issued = table.total
		treasury = table.get("treasury_units",0)
		assets = world.StationEquity.net_assets(record)
		price = world.StationEquity.unit_price(record)
		owned = table.people.get(world.player,0)
		for holder: int in table.people:
			rows.append({"party":holder,"units":table.people[holder]})
			if int(table.people[holder])*2>issued-treasury:
				controller=holder
				signer=holder
		if table.company_units>0:
			rows.append({"party":-int(table.company),"units":table.company_units})
			if int(table.company_units)*2>issued-treasury:
				controller=-int(table.company)
				signer=world.firms[table.company].director
		for flag in table.get("factions",{}):
			var f_units := int(table.factions[flag])
			if f_units > 0:
				rows.append({"public":true,"flag":flag,"units":f_units})
		if issued==0:
			issued = record.charter_units
			rows.append({"public":true,"flag":record.flag,"units":issued})
	var outstanding := issued-treasury
	for holder in rows:
		holder.percent=100.0*int(holder.units)/maxi(1,outstanding)
	var par: int = record.par_value
	var offer: Dictionary = record.get("primary_offer",{})
	if not offer.is_empty() and (offer.get("expires",0)<=world.day or offer.get("signer",0)!=signer or not jurisdiction_matches(world,scope,id,offer)):
		offer={}
	var can_sign: bool = world.Equity.adult(world,world.people.get(signer,{})) and (scope=="company" or (record.build==0 and not record.get("landing_only",false)))
	var jurisdiction: Dictionary = world.TradeLaw.jurisdiction(world,scope,id)
	var raw_max := mini(outstanding*int(Config.data.equity.maximum_issue_percent)/100,issued*int(jurisdiction.get("issue_limit",0))/100)
	if raw_max == 0 and outstanding > 0 and int(jurisdiction.get("issue_limit",0)) > 0:
		raw_max = 1
	var max_qty := mini(LIMIT-issued, raw_max)
	var need := maxi(0,int(Config.data.equity.working_capital)-int(record.treasury))
	return {"issued":issued,"outstanding":outstanding,"treasury_units":treasury,"par_value":par,"votes_per_share":1,"net_assets":assets,"unit_price":price,
		"paid_in_capital":record.paid_in_capital,"share_capital":issued*par,"share_premium":maxi(0,int(record.paid_in_capital)-issued*par),
		"owned":owned,"holders":rows,"controller":controller,"offer":offer.duplicate(true),"signer":signer,"can_issue":can_sign and world.oversees(signer),
		"can_solicit":can_sign and not world.oversees(signer) and need>0,"minimum_price":maxi(par,price),"max_quantity":max_qty,"capital_needed":need}

static func result(ok: bool, reason: String, offer: Dictionary = {}) -> Dictionary:
	return {"ok":ok,"reason":reason,"offer":offer.duplicate(true)}

static func authorize(world, scope: String, id: int, quantity: int, unit_price: int) -> Dictionary:
	return open_offer(world,scope,id,quantity,unit_price,false)

static func solicit(world, scope: String, id: int, quantity: int, unit_price: int) -> Dictionary:
	return open_offer(world,scope,id,quantity,unit_price,true)

static func open_offer(world, scope: String, id: int, quantity: int, unit_price: int, request: bool) -> Dictionary:
	var facts := overview(world,scope,id)
	if facts.is_empty() or not world.Equity.at_market(world):
		return result(false,"须从营业市场办理发行登记。")
	if not (facts.can_solicit if request else facts.can_issue):
		return result(false,"没有合法多数授权，或发行人当前无融资需求。")
	if not facts.offer.is_empty():
		return result(false,"已有尚未结束的公开认购。",facts.offer)
	if quantity<=0 or quantity>facts.max_quantity or unit_price<facts.minimum_price or unit_price>LIMIT:
		return result(false,"数量超过授权额度，或发行价低于票面和每股净值。")
	var law: Dictionary = world.TradeLaw.check(world,"issue",scope,id,-1,0,quantity)
	if not law.allowed:
		return result(false,law.reason)
	if request and (world.Politics.opinion(world,facts.signer,world.player)<int(Config.data.equity_orders.minimum_opinion) or (quantity-1)*unit_price>=facts.capital_needed):
		return result(false,"签字人拒绝这次增发的规模或条款。")
	var offer := {"id":world.uid(),"signer":facts.signer,"unit_price":unit_price,"quantity":quantity,"remaining":quantity,
		"flag":law.flag,"regime":law.regime,"code":world.TradeLaw.jurisdiction(world,scope,id).code,"expires":world.day+int(Config.data.equity.offer_days)}
	entity(world,scope,id).primary_offer=offer
	return result(true,"发行人已签署公开认购。",offer)

static func subscribe(world, scope: String, id: int, quantity: int, expected_price: int, offer_id: int = 0) -> Dictionary:
	return subscribe_for(world, world.player, scope, id, quantity, expected_price, offer_id)

static func subscribe_for(world, subscriber_id: int, scope: String, id: int, quantity: int, expected_price: int, offer_id: int = 0) -> Dictionary:
	var facts := overview(world,scope,id)
	var buyer: Dictionary = world.people.get(subscriber_id, {})
	if facts.is_empty() or buyer.is_empty() or not buyer.get("alive", false) or facts.offer.is_empty():
		return result(false,"没有有效的公开发行。")
	if subscriber_id == world.player and not world.Equity.at_market(world):
		return result(false,"没有有效的公开发行。")
	var offer: Dictionary = facts.offer
	if quantity<=0 or quantity>offer.remaining or quantity>LIMIT-int(facts.issued) or expected_price!=offer.unit_price or (offer_id!=0 and offer.id!=offer_id):
		return result(false,"认购数量、单价或发行编号已变化。")
	var legal: Dictionary = world.TradeLaw.check(world,"subscribe",scope,id,subscriber_id,0,quantity)
	var issuing: Dictionary = world.TradeLaw.check(world,"issue",scope,id,-1,0,quantity)
	if not legal.allowed or not issuing.allowed or offer.flag!=issuing.flag or offer.regime!=issuing.regime:
		return result(false,"现行证券法或发行地管辖权已变化。" if legal.allowed and issuing.allowed else (legal.reason if not legal.allowed else issuing.reason))
	var cost: int = quantity*expected_price
	if cost>int(buyer.wallet):
		return result(false,"认购人的可用资金不足。")
	var record := entity(world,scope,id)
	world.credit(subscriber_id,-cost)
	record.paid_in_capital+=cost
	if scope=="company":
		record.treasury+=cost
		record.issued+=quantity
		world.StationEquity.add_units(buyer.shares,id,quantity)
		var asset: Dictionary = world.Dividends.company_asset(id,record)
		world.Finances.record(world,record.director,asset,"增发股本",cost,false,true)
		world.Finances.record(world,subscriber_id,asset,"认购新股",-cost,false,true)
	else:
		var table: Dictionary = world.StationEquity.cap_table(world,record)
		table.total+=quantity
		world.StationEquity.add_units(table.people,subscriber_id,quantity)
		record.equity=table
		world.Treasury.post(world,record,cost,"增发股本",false)
		world.Finances.record(world,subscriber_id,record,"认购新股",-cost,false,true)
	record.primary_offer.remaining-=quantity
	if record.primary_offer.remaining==0:
		record.erase("primary_offer")
	if scope=="company":
		world.Politics.board(world,id)
	world.EquityOrders.audit(world)
	var receipt:=result(true,"认购款已到发行方账户，新股已登记。")
	receipt.cost=cost
	receipt.quantity=quantity
	return receipt

## Allow wealthy NPC investors to evaluate and subscribe to open primary share offerings.
static func daily(world) -> void:
	for scope in ["company", "station"]:
		var catalog: Dictionary = world.firms if scope == "company" else world.ports
		for raw_id in catalog.keys():
			var id := int(raw_id)
			var record: Dictionary = catalog[id]
			if not record.has("primary_offer"):
				continue
			var facts := overview(world, scope, id)
			var offer: Dictionary = facts.get("offer", {})
			if offer.is_empty():
				continue
			var strike := int(offer.unit_price)
			var max_fair := maxi(int(facts.minimum_price) + 10, roundi(float(facts.minimum_price) * 1.25))
			if strike > max_fair:
				continue
			var candidates: Array[int] = []
			for pid_raw in world.people.keys():
				var pid := int(pid_raw)
				if pid == world.player or pid == int(offer.signer):
					continue
				var p: Dictionary = world.people[pid]
				if not p.alive or int(p.get("flag", world.NEUTRAL)) == world.RAIDERS:
					continue
				if world.Politics.age(world, p) < 18 or int(p.get("wallet", 0)) < strike * 2:
					continue
				if world.Politics.opinion(world, pid, int(offer.signer)) < -30:
					continue
				candidates.append(pid)
			if candidates.is_empty():
				continue
			candidates.sort_custom(func(a, b): return int(world.people[a].wallet) > int(world.people[b].wallet))
			for pid in candidates.slice(0, mini(4, candidates.size())):
				if not record.has("primary_offer"):
					break
				var cur_rem := int(record.primary_offer.get("remaining", 0))
				if cur_rem <= 0:
					break
				if world.rng.randf() > 0.35:
					continue
				var p: Dictionary = world.people[pid]
				var budget := int(float(p.wallet) * 0.25)
				var qty := clampi(budget / maxi(1, strike), 1, cur_rem)
				var res := subscribe_for(world, pid, scope, id, qty, strike, int(offer.id))
				if bool(res.get("ok", false)):
					world.event("【新股认购】%s 以每股 ¢%d 认购了 %s 增发的 %d 股新股（共 ¢%d）。" % [
						p.name, strike, record.get("name", "发行方"), qty, int(res.get("cost", qty * strike))
					])
					break

static func cancel(world, scope: String, id: int) -> bool:
	var record := entity(world,scope,id)
	var offer: Dictionary = record.get("primary_offer",{})
	if offer.is_empty() or not world.oversees(overview(world,scope,id).get("signer",0)):
		return false
	record.erase("primary_offer")
	return true

static func jurisdiction_matches(world, scope: String, id: int, offer: Dictionary) -> bool:
	var statute: Dictionary=world.TradeLaw.jurisdiction(world,scope,id)
	return statute.get("code","")==offer.get("code","") and statute.get("flag",-1)==offer.flag and statute.get("regime",-1)==offer.regime

static func audit(world, _flag: int = -1) -> void:
	for scope in ["company","station"]:
		var registry: Dictionary=world.firms if scope=="company" else world.ports
		for id in registry:
			var record: Dictionary=registry[id]
			if record.has("primary_offer") and overview(world,scope,id).offer.is_empty():
				record.erase("primary_offer")

static func valid(data: Dictionary) -> bool:
	for table in [data.firms,data.ports]:
		for record in table.values():
			if not record is Dictionary:
				return false
			if not record.get("par_value") is int or record.par_value<=0 or not record.get("paid_in_capital") is int or record.paid_in_capital<0:
				return false
			if not record.has("primary_offer"):
				continue
			var offer: Variant = record.primary_offer
			if not offer is Dictionary or not offer.get("code") is String:
				return false
			for key in ["id","signer","unit_price","quantity","remaining","flag","regime","expires"]:
				if not offer.get(key) is int:
					return false
			if offer.id<=0 or offer.id>=data.next_id or not data.people.has(offer.signer) or offer.unit_price<=0 or offer.unit_price>LIMIT or offer.quantity<=0 or offer.quantity>LIMIT or offer.remaining<=0 or offer.remaining>offer.quantity:
				return false
	return true
