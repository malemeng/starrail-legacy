extends RefCounted

const Rules = preload("res://data/economy/industry.json")
const Law = preload("res://scripts/campaign/securities_law.gd")
static var TERMS: Dictionary = Rules.data.equity_orders

static func book_key(scope: String, id: int) -> String:
	return "%s:%d" % [scope,id]

static func direction(party: int, buying: bool) -> String:
	return "%d:%d" % [party,int(buying)]

static func state(world) -> Dictionary:
	return world.campaign.get_or_add("equity_orders",{"sequence":0,"books":{},"orders":{}})

static func epoch(world) -> int:
	return int(world.day)/int(TERMS.period_days)

static func same_registry(record: Dictionary, law: Dictionary) -> bool:
	return record.get("law_flag",-2)==law.flag and record.get("law_regime",-2)==law.regime and record.get("law_code","")==law.code

static func book(world, scope: String, id: int) -> Dictionary:
	var books: Dictionary = state(world).books
	var key := book_key(scope,id)
	var law: Dictionary = world.TradeLaw.jurisdiction(world,scope,id)
	if not books.has(key) or books[key].epoch != epoch(world) or not same_registry(books[key],law):
		for order: Dictionary in state(world).orders.values():
			if world.day>=order.expires or (order.scope==scope and order.asset==id and not same_registry(order,law)):
				close(world,order)
		books[key] = {"scope":scope,"asset":id,"epoch":epoch(world),"law_flag":law.flag,"law_regime":law.regime,"law_code":law.code,"published":false,"used":{}}
	return books[key]

static func participants(world, scope: String, id: int) -> Dictionary:
	if scope == "company" and world.firms.has(id):
		return world.Equity.participants(world,id)
	if scope == "station" and world.ports.has(id) and world.StationEquity.listed(world,world.ports[id]):
		return world.StationEquity.participants(world,world.ports[id])
	return {}

static func valuation(world, scope: String, id: int) -> int:
	return world.Equity.overview(world,id).unit_price if scope == "company" else world.StationEquity.unit_price(world.ports[id])

static func majority(world, scope: String, id: int) -> int:
	if scope=="company":
		var firm: Dictionary = world.firms[id]
		return (int(firm.issued)-int(firm.treasury_shares))/2+1
	var table: Dictionary = world.StationEquity.cap_table(world,world.ports[id])
	return (int(table.total)-int(table.get("treasury_units",0)))/2+1

static func account(world, scope: String, id: int, party: int) -> Dictionary:
	if party == world.StationEquity.TREASURY_PARTY:
		return world.ports.get(id,{}) if scope=="station" else {}
	if party <= 0:
		return world.firms.get(id if party==0 else -party,{})
	return world.people.get(party,{})

static func balance(entity: Dictionary) -> int:
	return entity.get("wallet",entity.get("treasury",0))

static func controlled(world, row: Dictionary, scope: String, id: int, party: int) -> bool:
	var who: int = row.get("representative",party if party>0 else 0)
	if row.get("player_controlled",false) or who <= 0 or world.oversees(who) or not world.Equity.adult(world,world.people.get(who,{})):
		return true
	if party == world.StationEquity.TREASURY_PARTY:
		var port: Dictionary = world.ports[id]
		var table: Dictionary = world.StationEquity.cap_table(world,port)
		return world.oversees(port.owner) or world.oversees(world.firms.get(port.firm,{}).get("director",0)) or int(table.people.get(world.player,0))*2>int(table.total)
	if party <= 0:
		var company := id if party==0 else -party
		var firm: Dictionary = world.firms.get(company,{})
		return world.oversees(firm.get("director",0)) or int(world.active().get("shares",{}).get(company,0))*2>int(firm.get("issued",0)-firm.get("treasury_shares",0))
	return false

static func contacts(world, scope: String, id: int) -> Array:
	var result := []
	var parties := participants(world,scope,id)
	for party: int in parties:
		var row: Dictionary = parties[party]
		if controlled(world,row,scope,id,party):
			continue
		var who: int = row.get("representative",party)
		var asset := account(world,scope,id,party)
		result.append({"person":party,"decider":who,"representative":who,"name":row.get("name",asset.get("name","")),
			"units":row.units,"interest":row.interest,"controller":row.controller})
	return result

static func refusal(reason: String, who: int = 0) -> Dictionary:
	return {"accepted":false,"score":0,"threshold":int(TERMS.consent_threshold),"label":"无法签署","factors":[reason],
		"binding":false,"reason":reason,"decider":who,"representative":who}

## The signer's relationship, temperament, spending power and control position determine consent.
static func decision(world, scope: String, id: int, party: int, row: Dictionary, buying: bool, value: int, limit: int = 0) -> Dictionary:
	var who: int = row.get("representative",party)
	if controlled(world,row,scope,id,party):
		return refusal("该账户没有可自主签字的成年代表。",who)
	var signer: Dictionary = world.people[who]
	var opinion: int = world.Politics.opinion(world,who,world.player)
	if opinion < int(TERMS.minimum_opinion):
		return refusal("%s 因对你的好感过低，拒绝接洽。" % signer.name,who)
	var personality: Dictionary = signer.personality
	var cash := balance(account(world,scope,id,party))
	var floor_cash := maxi(1,int(TERMS.cash_reserve)-int(personality.boldness))
	var markup := float(TERMS.ask_markup) + (int(personality.greed)-opinion)*0.001
	var bid_ratio := float(TERMS.bid_ratio) + (opinion-int(personality.greed))*0.001
	var ask := maxi(1,ceili(value*markup))
	var bid := maxi(1,floori(value*bid_ratio))
	var units: int = row.units
	var majority_units := majority(world,scope,id)
	var max_lot := maxi(1,(majority_units*2-1)*(int(TERMS.lot_percent)+int(personality.boldness)/20+opinion/35)/100)
	var why := ""
	var needs_negotiation := false
	if buying:
		var keep := mini(units,majority_units) if row.controller else 0
		var available: int = units-keep-world.DiplomaticTrade.reserved_shares(world,scope,id,party)
		if available<=0:
			if units>keep:
				return refusal("%s 的可售股份已作另约。"%signer.name,who)
			return refusal("%s 要保留控制权。" % signer.name if units>0 else "%s 没有可出售的股份。" % signer.name,who)
		var needs_cash := cash < floor_cash + value*2
		if not needs_cash and (row.interest or row.controller):
			ask = ceili(ask*float(TERMS.long_term_ask_multiplier))
			needs_negotiation = true
		max_lot = mini(max_lot,available)
		why = "筹集周转金" if needs_cash else "按认可的溢价减持"
	else:
		if party in [0,world.StationEquity.TREASURY_PARTY]:
			return refusal("发行人没有授权回购库存股。",who)
		if not row.interest and (units==0 or opinion<25):
			return refusal("%s 对增持这项资产没有兴趣。" % signer.name,who)
		if units >= majority_units:
			return refusal("%s 已持有控制权，当前没有增持计划。" % signer.name,who)
		if not row.controller and int(personality.boldness)<0 and opinion<10:
			bid = maxi(1,floori(bid*float(TERMS.cautious_bid_multiplier)))
			needs_negotiation = true
		var investable := maxi(0,cash-floor_cash)*int(TERMS.bid_budget_percent)/100
		max_lot = mini(max_lot,investable/maxi(1,bid))
		if max_lot<=0:
			return refusal("%s 要保留周转金，未批准这笔买入预算。" % signer.name,who)
		why = "愿在预留周转金后增持"
	var price := ask if buying else bid
	var accepts_price := not needs_negotiation if limit == 0 else (limit>=price if buying else limit<=price)
	var reason := "%s %s（%s，对你好感 %+d）。" % [signer.name,why,world.TRAITS[signer.trait],opinion]
	if not accepts_price:
		reason = "%s 的%s为每股 ¢%d。" % [signer.name,"最低卖价" if buying else "最高买价",price]
	var factors := ["%s · 对你好感 %+d" % [world.TRAITS[signer.trait],opinion],why]
	if buying and row.controller:
		factors.append("至少保留 %d 股控制权" % majority_units)
	return {"accepted":accepts_price,"decider":who,"representative":who,"name":row.get("name",account(world,scope,id,party).name),
		"reason":reason,"factors":factors,
		"quantity":max_lot,"unit_price":price}

static func _post(world, scope: String, id: int, party: int, buying: bool, signed_offer: Dictionary, quantity: int, solicited: bool = false) -> Dictionary:
	var ledger := state(world)
	var market := book(world,scope,id)
	var slot := direction(party,buying)
	if market.used.has(slot) or market.used.has(direction(party,not buying)):
		return refusal("本轮的交易意向已经签署或撤回。",signed_offer.decider)
	var legal := legal_quantity(world,scope,id,party,buying,quantity)
	if legal<=0 or (solicited and legal<quantity):
		return refusal("这些股份无法在当前法域登记。",signed_offer.decider)
	quantity = legal
	var total: int = int(signed_offer.unit_price)*quantity
	var entity := account(world,scope,id,party)
	if not buying:
		if balance(entity)<total:
			return refusal("可托管资金不足。",signed_offer.decider)
		if party>0:
			world.credit(party,-total)
		else:
			entity.treasury -= total
	ledger.sequence += 1
	var order: Dictionary = signed_offer.duplicate()
	order.merge({"order_id":ledger.sequence,"scope":scope,"asset":id,"person":party,"buying":buying,
		"law_flag":market.law_flag,"law_regime":market.law_regime,"law_code":market.law_code,
		"expires":(epoch(world)+1)*int(TERMS.period_days),"epoch":epoch(world),"escrow":0 if buying else total,
		"client":world.player,"solicited":solicited},true)
	order.quantity = quantity
	ledger.orders[order.order_id] = order
	market.used[slot] = true
	return order

static func publish(world, scope: String, id: int, value: int, parties: Dictionary) -> void:
	var market := book(world,scope,id)
	if market.published or world.player<=0:
		return
	market.published = true
	for party: int in parties:
		var row: Dictionary = parties[party]
		if controlled(world,row,scope,id,party):
			continue
		for buying: bool in [true,false]:
			var offer := decision(world,scope,id,party,row,buying,value)
			if offer.accepted:
				_post(world,scope,id,party,buying,offer,offer.quantity)
				break

static func registered(world, order: Dictionary) -> bool:
	var law: Dictionary = world.TradeLaw.check_transfer(world,order.scope,order.asset,order.person,order.buying,1)
	return law.allowed and same_registry(order,law)

static func legal_quantity(world, scope: String, id: int, party: int, buying: bool, quantity: int) -> int:
	if quantity<=0 or world.TradeLaw.check_transfer(world,scope,id,party,buying,quantity).allowed:
		return maxi(0,quantity)
	var low := 0
	var high := quantity
	while high-low>1:
		var mid := low+(high-low)/2
		if world.TradeLaw.check_transfer(world,scope,id,party,buying,mid).allowed:
			low=mid
		else:
			high=mid
	return low

static func authorized(world, order: Dictionary) -> bool:
	if world.day>=order.expires or order.client!=world.player or not registered(world,order):
		return false
	var parties := participants(world,order.scope,order.asset)
	var row: Dictionary = parties.get(order.person,{})
	if row.is_empty() or row.get("representative",order.person)!=order.decider or controlled(world,row,order.scope,order.asset,order.person):
		return false
	if not order.buying:
		return true
	var free: int = row.units - world.DiplomaticTrade.reserved_shares(world,order.scope,order.asset,order.person) + world.DiplomaticTrade.reserved_order_quantity(world,order.order_id)
	return free-order.quantity >= (majority(world,order.scope,order.asset) if row.controller else 0)

static func executable_terms(world, order: Dictionary) -> Dictionary:
	var terms := order.duplicate(true)
	var legal := legal_quantity(world,order.scope,order.asset,order.person,order.buying,terms.quantity)
	terms.quantity = maxi(0,legal-world.DiplomaticTrade.reserved_order_quantity(world,order.order_id))
	return terms

static func refund(world, order: Dictionary, amount: int) -> void:
	if amount<=0:
		return
	if order.person>0:
		world.credit(order.person,amount)
	else:
		var entity := account(world,order.scope,order.asset,order.person)
		entity.treasury += amount
	order.escrow -= amount

static func close(world, order: Dictionary) -> void:
	world.DiplomaticTrade.release_order(world,order.order_id)
	refund(world,order,order.escrow)
	state(world).orders.erase(order.order_id)

static func cancel(world, order_id: int) -> bool:
	var order: Dictionary = state(world).orders.get(order_id,{})
	if order.is_empty() or (not world.oversees(order.decider) and not (order.solicited and order.client==world.player)):
		return false
	close(world,order)
	return true

static func revoke_signer(world, who: int) -> void:
	for order in state(world).orders.values():
		if order.decider==who or order.client==who:
			close(world,order)

static func audit(world, scope: String = "", id: int = 0) -> void:
	var ledger := state(world)
	for order: Dictionary in ledger.orders.values():
		if not scope.is_empty() and (order.scope!=scope or order.asset!=id):
			continue
		if not authorized(world,order):
			close(world,order)
			continue
		var legal := legal_quantity(world,order.scope,order.asset,order.person,order.buying,order.quantity)
		if legal<order.quantity:
			if world.DiplomaticTrade.reserved_order_quantity(world,order.order_id)>legal:
				world.DiplomaticTrade.release_order(world,order.order_id)
			if not order.buying:
				refund(world,order,(int(order.quantity)-legal)*int(order.unit_price))
			order.quantity=legal
	for key in ledger.books.keys():
		var market: Dictionary=ledger.books[key]
		if (scope.is_empty() or (market.scope==scope and market.asset==id)) and not same_registry(market,world.TradeLaw.jurisdiction(world,market.scope,market.asset)):
			ledger.books.erase(key)

static func escrow_for(world, party: int) -> int:
	var amount := 0
	for order: Dictionary in world.campaign.get("equity_orders",{}).get("orders",{}).values():
		if not order.buying and order.person==party:
			amount += int(order.escrow)
	return amount

static func quotes(world, scope: String, id: int, buying: bool) -> Array:
	var result := []
	for order: Dictionary in state(world).orders.values():
		if order.scope==scope and order.asset==id and order.buying==buying:
			if authorized(world,order):
				var terms := executable_terms(world,order)
				if terms.quantity>0:
					result.append(terms)
			else:
				close(world,order)
	return result

## A preview only reads existing orders. A request may sign the exact terms shown here.
static func preview(world, scope: String, id: int, party: int, qty: int, buying: bool, limit: int) -> Dictionary:
	var row: Dictionary = participants(world,scope,id).get(party,{})
	var who: int = row.get("representative",0)
	if row.is_empty() or qty<=0 or limit<=0 or not world.Equity.at_market(world):
		return refusal("请在营业港联系有关股东或经营代表，填写正数股数和价格。",who)
	var law: Dictionary = world.TradeLaw.check_transfer(world,scope,id,party,buying,qty)
	if not law.allowed:
		return refusal(law.reason,who)
	if not buying:
		var held: int = world.active().shares.get(id,0) if scope=="company" else world.StationEquity.cap_table(world,world.ports[id]).people.get(world.player,0)
		if qty>held-world.DiplomaticTrade.reserved_shares(world,scope,id,world.player):
			return refusal("你持有的股数不足以履行提议。",who)
	if buying and row.controller and qty > int(row.units)-majority(world,scope,id):
		return refusal("%s 要保留控制权。" % world.name_of(who),who)
	var ledger: Dictionary = world.campaign.get("equity_orders",{})
	var market: Dictionary = ledger.get("books",{}).get(book_key(scope,id),{})
	var terms := {}
	for order: Dictionary in ledger.get("orders",{}).values():
		if order.scope==scope and order.asset==id and order.person==party and order.buying==buying and authorized(world,order):
			terms = executable_terms(world,order)
			if terms.quantity<=0:
				var unavailable := refusal("整笔委托已为待确认的交易协议预留。",who)
				unavailable.merge({"order_id":order.order_id,"expires":order.expires,"binding":true},true)
				return unavailable
			break
	var bound := not terms.is_empty()
	if not bound:
		if market.get("epoch",-1)==epoch(world) and same_registry(market,law) and (market.used.has(direction(party,buying)) or market.used.has(direction(party,not buying))):
			return refusal("该代表本轮的委托额度已用完、撤回或另有安排。",who)
		terms = decision(world,scope,id,party,row,buying,valuation(world,scope,id),limit)
		if not terms.has("unit_price"):
			return terms
	var price: int = terms.unit_price
	var cap: int = terms.quantity
	var pass_score := int(TERMS.consent_threshold)
	var price_ratio := float(limit)/price if buying else float(price)/limit
	var quantity_ratio := float(cap)/qty
	var ratio := minf(price_ratio,quantity_ratio)
	var score := clampi(floori(pass_score*ratio),0,pass_score-1) if ratio<1.0 else mini(100,pass_score+floori(40.0*(1.0-1.0/ratio)))
	var reasons: Array = terms.get("factors",[]).duplicate()
	reasons.append("%s ¢%d · 最多 %d 股" % ["最低卖价" if buying else "最高买价",price,cap])
	if bound:
		reasons.append("已签至第 %d 日" % int(terms.expires))
	terms.merge({"binding":bound,"score":score,"threshold":pass_score,"accepted":score>=pass_score,"factors":reasons,
		"max_quantity":cap,"label":"符合已签条件" if bound and score>=pass_score else ("愿意签署" if score>=pass_score else "需要调整")},true)
	if buying and world.active().wallet < qty*price:
		terms.merge({"accepted":false,"score":0,"label":"资金不足","reason":"你的资金不足以按对方限价取得这些股份。"},true)
	elif qty>cap:
		terms.reason = "%s 最多愿意签 %d 股。" % [world.name_of(who),cap]
	elif price_ratio<1.0:
		terms.reason = "%s 的%s为每股 ¢%d。" % [world.name_of(who),"最低卖价" if buying else "最高买价",price]
	terms.quantity = qty
	return terms

static func propose(world, scope: String, id: int, party: int, qty: int, buying: bool, limit: int) -> Dictionary:
	var terms := preview(world,scope,id,party,qty,buying,limit)
	if not terms.accepted:
		if terms.has("order_id"):
			terms.standing_order_id = terms.order_id
			terms.erase("order_id")
		return terms
	if terms.binding:
		return terms
	return _post(world,scope,id,party,buying,terms,qty,true).duplicate(true)

static func fill(world, scope: String, id: int, party: int, qty: int, buying: bool, price: int, order_id: int = 0, listing_id: int = 0) -> bool:
	if qty<=0 or price<=0:
		return false
	if listing_id!=0:
		if buying or not world.ShareExchange.permits_fill(world,listing_id,scope,id,qty,price):
			return false
	elif not world.Equity.at_market(world):
		return false
	if not buying:
		var held: int = world.active().shares.get(id,0) if scope=="company" else world.StationEquity.cap_table(world,world.ports[id]).people.get(world.player,0)
		var locked: int = world.DiplomaticTrade.reserved_shares(world,scope,id,world.player)
		if qty>held-locked+(qty if listing_id!=0 else 0):
			return false
	for candidate in quotes(world,scope,id,buying):
		if candidate.person!=party or candidate.unit_price!=price or candidate.quantity<qty or (order_id!=0 and candidate.order_id!=order_id):
			continue
		var order: Dictionary = state(world).orders[candidate.order_id]
		var total := qty*price
		var actor: Dictionary = world.active()
		if buying and actor.wallet<total:
			return false
		if not buying and order.escrow<total:
			return false
		if buying:
			world.credit(actor.id,-total)
			var entity := account(world,scope,id,party)
			if party==world.StationEquity.TREASURY_PARTY:
				world.Treasury.post(world,entity,total,"库存股出售",false)
			elif party>0:
				world.credit(party,total)
			else:
				entity.treasury+=total
				world.Finances.record(world,entity.director,world.Dividends.company_asset(id if party==0 else -party,entity),"股权出售",total,false,true)
		else:
			order.escrow-=total
			world.credit(actor.id,total)
		order.quantity-=qty
		if order.quantity==0:
			close(world,order)
		return true
	return false

static func daily(world) -> void:
	var ledger := state(world)
	for order: Dictionary in ledger.orders.values():
		if world.day>=order.expires or world.oversees(order.decider) or not registered(world,order):
			close(world,order)
	if world.player<=0 or (world.day!=1 and world.day % int(TERMS.period_days)!=0):
		return
	for firm_id: int in world.firms:
		publish(world,"company",firm_id,valuation(world,"company",firm_id),participants(world,"company",firm_id))
	for site: Dictionary in world.ports.values():
		if site.scan and world.StationEquity.listed(world,site):
			publish(world,"station",site.id,valuation(world,"station",site.id),participants(world,"station",site.id))

static func valid(data: Dictionary) -> bool:
	if not data.campaign.has("equity_orders"):
		return true
	var ledger: Variant = data.campaign.equity_orders
	if not ledger is Dictionary or not ledger.get("sequence") is int or ledger.sequence<0 or not ledger.get("books") is Dictionary or not ledger.get("orders") is Dictionary:
		return false
	for key in ledger.books:
		var market: Variant = ledger.books[key]
		if not market is Dictionary or market.get("scope") not in ["company","station"] or not market.get("asset") is int:
			return false
		var assets: Dictionary = data.firms if market.scope=="company" else data.ports
		if not assets.has(market.asset) or not market.get("used") is Dictionary or not market.get("epoch") is int or not market.get("published") is bool:
			return false
		if not market.get("law_flag") is int or not market.get("law_regime") is int or not Law.Rules.data.codes.has(market.get("law_code","")) or (market.law_flag>=0 and not data.factions.has(market.law_flag)):
			return false
		if key != book_key(market.scope,market.asset) or market.epoch<0 or market.epoch>int(data.day)/int(TERMS.period_days):
			return false
	var current := {}
	for id in ledger.orders:
		var order: Variant = ledger.orders[id]
		if not id is int or id<=0 or id>ledger.sequence or not order is Dictionary or order.get("order_id")!=id:
			return false
		for field in ["asset","person","quantity","unit_price","escrow","expires","epoch","decider","client"]:
			if not order.get(field) is int:
				return false
		if not order.get("buying") is bool or not order.get("solicited") is bool or not order.get("reason") is String or not order.get("name") is String or order.get("scope") not in ["company","station"]:
			return false
		var key := book_key(order.scope,order.asset)
		var market: Dictionary = ledger.books.get(key,{})
		var slot := direction(order.person,order.buying)
		if market.is_empty() or current.has([key,slot]) or not market.used.has(slot) or order.epoch!=market.epoch or order.get("law_flag",-2)!=market.law_flag or order.get("law_regime",-2)!=market.law_regime or order.get("law_code","")!=market.law_code:
			return false
		if not data.people.has(order.client) or not data.people.has(order.decider) or order.expires!=(order.epoch+1)*int(TERMS.period_days):
			return false
		if order.quantity<=0 or order.quantity>2147483647 or order.unit_price<=0 or order.unit_price>2147483647 or order.escrow!=(0 if order.buying else order.quantity*order.unit_price):
			return false
		if order.person>0 and not data.people.has(order.person):
			return false
		if order.scope=="company" and order.person<0:
			return false
		if order.scope=="station" and (order.person==0 or (order.person<0 and order.person!=-2147483648 and not data.firms.has(-order.person))):
			return false
		current[[key,slot]] = true
	return true
