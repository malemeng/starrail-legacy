extends RefCounted

const Industry = preload("res://scripts/economy/industry.gd")
const Partners = preload("res://scripts/economy/trade_partners.gd")
const StationEquity = preload("res://scripts/economy/station_equity.gd")
const TYPES := ["cash","ware","company_share","station_share","treaty"]
const MAX_LINES := 48
const MAX_UNITS := 2147483647

static func contacts(world) -> Array:
	return Partners.partners(world)

static func catalog(world, kind: String, id: int, black: bool = false) -> Dictionary:
	var empty := {"give":[],"want":[]}
	var partner := Partners.participant(world,kind,id,black)
	if partner.is_empty():
		return empty
	var give := []
	var physical: bool = partner.get("ship",0)!=0 or (kind=="station" and partner.local)
	for row in Partners.assets(world,"player",world.player,black):
		if row.kind=="ware" and not physical:
			continue
		if row.kind in ["company_share","station_share"] and (black or partner.ordinary_only or not handles_share(world,row.kind.trim_suffix("_share"),row.id,partner,false)):
			continue
		give.append(row)
	var want := Partners.assets(world,kind,id,black)
	return {"give":give,"want":want}

static func reply(reason: String, representative: int = 0) -> Dictionary:
	return {"accepted":false,"score":0,"threshold":60,"label":"尚未同意","factors":[reason],"reason":reason,"representative":representative,
		"decider":representative,"give_value":0,"want_value":0,"cash_delta":0,"deal_id":0,
		"tax":0,"tax_flag":-1,"tax_name":"免税","goods_given":0,"goods_received":0}

static func available_cash(world, kind: String, id: int, black: bool = false) -> int:
	match kind:
		"person","player": return int(world.people.get(id,{}).get("wallet",0))
		"company": return int(world.firms.get(id,{}).get("treasury",0))
		"faction": return int(world.factions.get(id,{}).get("treasury",0))
		"station":
			var site: Dictionary = world.ports.get(id,{})
			return int(site.get("black_treasury",0)) if black else world.Treasury.available(site)
	return 0

static func share_party(world, scope: String, asset: int, kind: String, id: int) -> int:
	if kind in ["person","player"]:
		return id
	if kind == "company":
		return -id if scope == "station" else 0
	if kind == "station" and scope == "station" and asset == id:
		return world.StationEquity.TREASURY_PARTY
	return -2147483647

static func holding(world, scope: String, asset: int, kind: String, id: int) -> int:
	if scope == "company":
		if not world.firms.has(asset):
			return 0
		if kind in ["person","player"]:
			return world.people.get(id,{}).get("shares",{}).get(asset,0)
		return int(world.firms[asset].treasury_shares) if kind == "company" and asset == id else 0
	if not world.ports.has(asset):
		return 0
	var table: Dictionary = world.StationEquity.cap_table(world,world.ports[asset])
	if kind in ["person","player"]:
		return table.people.get(id,0)
	if kind == "company" and table.company == id:
		return table.company_units
	return int(table.get("treasury_units",0)) if kind == "station" and asset == id else 0

static func reserved_shares(world, scope: String, asset: int, party: int) -> int:
	var listed: int = world.ShareExchange.reserved(world,scope,asset,party)
	var contract: Dictionary = world.campaign.get("diplomatic_deal",{})
	if contract.is_empty():
		return listed
	for side in ["give","want"]:
		var holder: int = contract.client if side == "give" else share_party(world,scope,asset,contract.kind,contract.party)
		if holder != party:
			continue
		for item in contract[side]:
			if item.kind == scope+"_share" and item.id == asset:
				return listed+int(item.quantity)
	return listed

static func reserved_order_quantity(world, order_id: int) -> int:
	var contract: Dictionary = world.campaign.get("diplomatic_deal",{})
	for side in ["give","want"]:
		for item in contract.get(side,[]):
			if item.get("order_id",0) == order_id and order_id > 0:
				return int(item.quantity)
	return 0

static func handles_share(world, scope: String, asset: int, partner: Dictionary, receiving: bool) -> bool:
	if partner.kind=="person":
		return true
	if partner.kind=="station":
		return scope=="station" and receiving and asset==partner.id
	if partner.kind!="company":
		return false
	if scope=="company":
		return receiving and asset==partner.id
	var site: Dictionary = world.ports.get(asset,{})
	if site.is_empty():
		return false
	var holdings: Dictionary=world.StationEquity.cap_table(world,site)
	return holdings.company==partner.id or (not receiving and holdings.company_units==0 and site.firm==partner.id)

static func share_terms(world, scope: String, asset: int, partner: Dictionary, quantity: int, receiving: bool) -> Dictionary:
	if not handles_share(world,scope,asset,partner,receiving):
		return {"ok":false,"reason":"该主体不能收取或给出这项股权。"}
	var party := share_party(world,scope,asset,partner.kind,partner.id)
	var law: Dictionary = world.TradeLaw.check_transfer(world,scope,asset,party,receiving,quantity)
	if not law.allowed:
		return {"ok":false,"reason":law.reason}
	var candidates: Dictionary = world.EquityOrders.participants(world,scope,asset)
	if not candidates.has(party):
		return {"ok":false,"reason":"对方无权以此账户交易这项股权。"}
	var candidate: Dictionary = candidates[party]
	if candidate.representative != partner.representative:
		return {"ok":false,"reason":"该股份须由其授权人签字。"}
	var direction: String = world.EquityOrders.direction(party,receiving)
	var ledger: Dictionary = world.campaign.get("equity_orders",{})
	var market: Dictionary = ledger.get("books",{}).get(world.EquityOrders.book_key(scope,asset),{})
	var already_signed := 0
	for order in ledger.get("orders",{}).values():
		if order.scope != scope or order.asset != asset or order.person != party or order.expires <= world.day:
			continue
		if order.buying:
			already_signed += int(order.quantity)
		if order.buying != receiving:
			return {"ok":false,"reason":"对方本期已签署相反方向的委托。"}
		if world.EquityOrders.authorized(world,order):
			if quantity > order.quantity:
				return {"ok":false,"reason":"组合提案超过对方已经签字的实际数量。"}
			return {"ok":true,"value":quantity*int(order.unit_price),"order_id":order.order_id,"expires":order.expires,"law_flag":law.flag,"law_regime":law.regime,"law_code":world.TradeLaw.jurisdiction(world,scope,asset).code}
	if market.get("epoch",-1) == world.EquityOrders.epoch(world) and (market.get("used",{}).has(direction) or market.get("used",{}).has(world.EquityOrders.direction(party,not receiving))):
		return {"ok":false,"reason":"这项股份的本期额度已签出或撤回，请使用原委托或等下一期。"}
	var value: int = world.EquityOrders.valuation(world,scope,asset)
	var terms: Dictionary = world.EquityOrders.decision(world,scope,asset,party,candidate,receiving,value,MAX_UNITS if receiving else 1)
	if not terms.get("accepted",false):
		return {"ok":false,"reason":terms.reason}
	if quantity > int(terms.quantity) or (receiving and quantity > int(candidate.units)-already_signed):
		return {"ok":false,"reason":"股份数量超过对方同意的限量或未预留持股。"}
	return {"ok":true,"value":quantity*int(terms.unit_price),"law_flag":law.flag,"law_regime":law.regime,"law_code":world.TradeLaw.jurisdiction(world,scope,asset).code}

static func normalized(lines: Array) -> Array:
	var result := []
	var seen := {}
	for raw in lines:
		if not raw is Dictionary or not raw.get("kind","") in TYPES:
			return []
		for key in ["quantity","id"]:
			var number: Variant = raw.get(key)
			if not (number is int or number is float) or absf(float(number)) > MAX_UNITS or float(int(number)) != float(number):
				return []
		var key := "%s/%d" % [raw.kind,int(raw.id)]
		if int(raw.quantity) < 1 or seen.has(key) or (raw.kind == "cash" and raw.id != 0):
			return []
		seen[key] = true
		result.append({"kind":str(raw.kind),"id":int(raw.id),"quantity":int(raw.quantity)})
	return result

static func ship_for(world, kind: String, id: int, party: Dictionary) -> Dictionary:
	if kind == "player":
		return world.ships.get(Partners.cargo_ship(world,world.active(),Partners.location(world)),{})
	return world.ships.get(party.get("ship",0),{}) if kind == "person" else {}

static func check_side(world, partner: Dictionary, lines: Array, receiving: bool, black: bool, result: Dictionary) -> String:
	var owner: String = partner.kind if receiving else "player"
	var id: int = partner.id if receiving else world.player
	var ware_ship := ship_for(world,owner,id,partner)
	var local: Dictionary = world.ports.get(world.ride().get("dock",0),{})
	var value_key := "want_value" if receiving else "give_value"
	for item: Dictionary in lines:
		var asset: int = item.id
		var qty: int = item.quantity
		var amount := 0
		match item.kind:
			"cash":
				amount = qty
			"ware":
				if asset not in range(Industry.WARES.size()) or local.is_empty() or (not black and asset == Industry.Ware.LUXURY):
					return "该货物无法在此交割。"
				if partner.kind not in ["person","station"] or (partner.kind == "person" and world.ships.get(partner.get("ship",0),{}).get("dock",0) != local.id) or (partner.kind == "station" and partner.id != local.id):
					return "双方须在同港拥有可交收的货舱或仓库。"
				var available := 0
				if owner == "station":
					available = int(local.black[asset]) if black else Industry.available(local,asset)
				else:
					if ware_ship.is_empty() or ware_ship.dock != local.id:
						return "对方没有在本港的交货船。"
					available = Partners.available_cargo(ware_ship,asset)
				if qty > available:
					return "可交付库存或船上现货不足。"
				if world.ride().is_empty() or qty > int(world.HULL_CARGO[world.ride().kind]):
					return "数量超过承运舰的整个货舱。"
				var invoice: Dictionary = world.Industry.lot_invoice(local,asset,qty,receiving,world.active().origin if partner.kind == "station" else -1,black)
				var base: int = invoice.base
				var tax: int = invoice.tax
				if partner.kind == "person":
					var signer: Dictionary = world.people[partner.representative]
					var opinion: int = world.Politics.opinion(world,signer.id,world.player)
					var premium := clampf((int(signer.personality.greed)-opinion)*0.001+0.06,-0.08,0.25)
					base = maxi(1,ceili(base*(1.0+premium)) if receiving else floori(base*(1.0-premium)))
					tax = roundi(base*Industry.tariff_rate(local,black))
				amount = base+tax if receiving else base-tax
				item.base = base
				item.tax = tax
				result.tax += tax
				result["goods_received" if receiving else "goods_given"] += base
				result.tax_flag = -1 if black else int(local.get("tariff_flag",-1))
				result.tax_name = world.flag_name(result.tax_flag) if result.tax_flag>=0 else "免税"
			"company_share","station_share":
				if black:
					return "黑市柜台不经办股权。"
				var scope: String = "company" if item.kind == "company_share" else "station"
				var pledged: int = reserved_shares(world,scope,asset,id) if not receiving else 0
				if qty > holding(world,scope,asset,owner,id)-pledged:
					return "给出方实际持有的股份不足。"
				var pledge := share_terms(world,scope,asset,partner,qty,receiving)
				if not pledge.ok:
					return pledge.reason
				amount = pledge.value
				item.order_id = pledge.get("order_id",0)
				item.order_expiry = pledge.get("expires",0)
				item.law_flag = pledge.law_flag
				item.law_regime = pledge.law_regime
				item.law_code = pledge.law_code
				if not receiving and item.order_id > 0:
					result.bid_credit = result.get("bid_credit",0)+amount
			"treaty":
				if not receiving or partner.kind != "faction" or asset != partner.id or qty != 1:
					return "该账户无权提供这项条约。"
				var treaty: Dictionary = Partners.treaty(world,asset,false)
				if not treaty.get("ok",false):
					return treaty.get("reason","条约条件不符。")
				amount = int(treaty.unit_price)
		item.value = amount
		result[value_key] += amount
	return ""

static func amounts(lines: Array, type: String) -> Dictionary:
	var output := {}
	for item in lines:
		if item.kind == type:
			output[item.id] = item.quantity
	return output

static func mass(units: Dictionary) -> int:
	var total := 0
	for value in units.values():
		total += int(value)
	return total

static func warehouse_holds(outgoing: Dictionary, incoming: Dictionary) -> Dictionary:
	var holds: Dictionary={}
	for group in Industry.WARES_BY_STORAGE.size():
		var sent:=0
		var received:=0
		for ware in Industry.WARES_BY_STORAGE[group]:
			sent+=int(outgoing.get(ware,0))
			received+=int(incoming.get(ware,0))
		if sent+received>0:
			holds[group]=maxi(sent,received)
	return holds

static func capacity_issue(world, partner: Dictionary, give: Array, want: Array, black: bool) -> String:
	var leaving := amounts(give,"ware")
	var arriving := amounts(want,"ware")
	if leaving.is_empty() and arriving.is_empty():
		return ""
	var ship: Dictionary = world.ride()
	if ship.is_empty() or mass(arriving) > world.cargo_free(ship)+mass(leaving):
		return "玩家货舱装不下收取的整批货物。"
	if partner.kind == "person":
		var other: Dictionary = world.ships.get(partner.get("ship",0),{})
		if other.is_empty() or other.id == ship.id or mass(leaving) > world.cargo_free(other)+mass(arriving):
			return "对方船上没有足够的交收空间。"
	elif not black:
		var per_group := {}
		var site: Dictionary = world.ports[partner.id]
		for ware in leaving:
			var group: int = Industry.STORAGE[ware]
			per_group[group] = int(per_group.get(group,0))+int(leaving[ware])
		for ware in arriving:
			var group: int = Industry.STORAGE[ware]
			per_group[group] = int(per_group.get(group,0))-int(arriving[ware])
		for group in per_group:
			var ware: int = Industry.WARES_BY_STORAGE[group][0]
			if per_group[group] > Industry.space(site,ware):
				return "站点对应仓型的未预留空间不足。"
	return ""

static func preview(world, kind: String, id: int, give: Array, want: Array, black: bool = false) -> Dictionary:
	return evaluate(world,kind,id,give,want,black)

## Resolve one specific signed market order into the same bilateral docket used for ordinary cargo.
static func quote_order(world, order_id: int, quantity: int) -> Dictionary:
	var order: Dictionary=world.campaign.get("equity_orders",{}).get("orders",{}).get(order_id,{})
	if order.is_empty() or not world.EquityOrders.authorized(world,order):
		return reply("该挂牌已撤回、到期或失去签字授权。")
	var available: int=world.EquityOrders.executable_terms(world,order).quantity
	if quantity<=0 or quantity>available:
		return reply("股数超过挂牌当前可成交的余量。",order.decider)
	var kind: String="person"
	var id: int=order.person
	if id==world.StationEquity.TREASURY_PARTY:
		kind="station"
		id=order.asset
	elif id<=0:
		kind="company"
		id=order.asset if id==0 else -id
	var shares: Array=[{"kind":order.scope+"_share","id":order.asset,"quantity":quantity}]
	var money: Array=[{"kind":"cash","id":0,"quantity":quantity*int(order.unit_price)}]
	var give: Array=money if order.buying else shares
	var want: Array=shares if order.buying else money
	var terms:=preview(world,kind,id,give,want)
	if terms.accepted:
		var linked: Dictionary=terms.want[0] if order.buying else terms.give[0]
		if linked.get("order_id",0)!=order_id:
			return reply("当前条款对应另一份委托，请重新选择。",order.decider)
	terms.order_id=order_id
	terms.unit_price=order.unit_price
	terms.quantity=quantity
	terms.available=available
	terms.expires=order.expires
	terms.contact_kind=kind
	terms.contact_id=id
	terms.give=give
	terms.want=want
	return terms

static func sign_order(world, order_id: int, quantity: int, expected_price: int) -> Dictionary:
	var terms:=quote_order(world,order_id,quantity)
	if not terms.accepted:
		return terms
	if expected_price!=terms.unit_price:
		return reply("该挂牌的签字限价与确认价不符。",terms.representative)
	var signed:=propose(world,terms.contact_kind,terms.contact_id,terms.give,terms.want)
	if signed.accepted:
		signed.order_id=order_id
		signed.unit_price=expected_price
	return signed

static func evaluate(world, kind: String, id: int, offered: Array, requested: Array, black: bool) -> Dictionary:
	if offered.size()+requested.size() > MAX_LINES:
		return reply("条款过多。")
	var partner: Dictionary = Partners.participant(world,kind,id,black)
	if partner.is_empty() or (black and kind != "station"):
		return reply("须在营业港联系有授权的交易对方。")
	var give := normalized(offered)
	var want := normalized(requested)
	var result := reply("请添加交易条款。",partner.representative)
	if give.size() != offered.size() or want.size() != requested.size() or (give.is_empty() and want.is_empty()):
		return result
	var offered_keys := {}
	for item in give:
		offered_keys["%s/%d"%[item.kind,item.id]] = true
	for item in want:
		if offered_keys.has("%s/%d"%[item.kind,item.id]):
			result.reason = "同一资产不能同时列在两侧。"
			return result
	var issue := check_side(world,partner,give,false,black,result)
	if issue.is_empty():
		issue = check_side(world,partner,want,true,black,result)
	result.cash_delta = result.want_value-result.give_value
	if issue.is_empty():
		issue = capacity_issue(world,partner,give,want,black)
	var posted: bool = kind == "station" and (give+want).all(func(row):return row.kind in ["cash","ware"])
	if not posted and partner.get("ordinary_only",false):
		issue = "本站柜台只执行挂牌商品交易。"
	if issue.is_empty() and not posted and world.oversees(partner.representative):
		issue = "该账户须由玩家本人签署，不能由代理人代为批准。"
	if issue.is_empty() and not posted and world.Politics.opinion(world,partner.representative,world.player) < int(Industry.RULES.equity_orders.minimum_opinion):
		issue = "%s 拒绝与当前人物缔约。" % world.name_of(partner.representative)
	var requested_cash: int = amounts(want,"cash").get(0,0)
	var payment: int = amounts(give,"cash").get(0,0)
	var tax_reserve := maxi(0,int(result.tax)-payment)
	result.tax_reserve = tax_reserve
	var bid_credit := mini(requested_cash,int(result.get("bid_credit",0)))
	result.bid_credit = bid_credit
	if issue.is_empty() and kind == "person":
		var personal: Dictionary = world.people[id]
		var reserve := maxi(0,int(Industry.RULES.equity_orders.cash_reserve)-int(personal.personality.boldness))
		if requested_cash+tax_reserve > bid_credit and personal.wallet+bid_credit-requested_cash-tax_reserve < reserve:
			issue = "%s 要保留必要的个人周转金。" % personal.name
	result.score = clampi(roundi(60.0*float(result.give_value)/maxf(1,result.want_value)),0,100)
	if issue.is_empty() and (payment>available_cash(world,"player",world.player) or requested_cash-bid_credit+tax_reserve>available_cash(world,kind,id,black)):
		issue = "一方可支配资金不足。"
	if issue.is_empty() and (give.is_empty() or want.is_empty()):
		issue = "请给出双方的对价。"
	if issue.is_empty() and ((posted and result.cash_delta != 0) or (not posted and result.cash_delta > 0)):
		issue = "按当前条款尚有 ¢%d 差价。" % absi(result.cash_delta)
	if not issue.is_empty():
		result.reason = issue
		result.factors = [issue]
		result.score = mini(59,result.score)
		return result
	result.accepted = true
	result.label = "可以签署"
	result.reason = "双方货款按本港公布的整批价格结算。" if posted else "%s 同意这些条款。" % world.name_of(partner.representative)
	result.factors = [result.reason]
	result.give = give
	result.want = want
	result.partner_ship = int(partner.get("ship",0))
	return result

static func cash(world, kind: String, id: int, delta: int, black: bool) -> void:
	if delta == 0:
		return
	match kind:
		"person","player": world.credit(id,delta)
		"station":
			if black:
				world.ports[id].black_treasury += delta
			else:
				world.ports[id].treasury += delta
		"company": world.firms[id].treasury += delta
		"faction": world.factions[id].treasury += delta

static func inventory(world, d: Dictionary, player_side: bool) -> Array:
	if player_side:
		return world.ships[d.ship].cargo
	if d.kind == "station":
		return world.ports[d.party].black if d.black else world.ports[d.party].stock
	return world.ships[d.partner_ship].cargo

static func lock_space(world, d: Dictionary, reserve: bool) -> void:
	var outgoing := amounts(d.give,"ware")
	var incoming := amounts(d.want,"ware")
	if outgoing.is_empty() and incoming.is_empty():
		return
	var peak := maxi(mass(outgoing),mass(incoming))
	world.ships[d.ship].deal_space = peak if reserve else 0
	if d.kind == "person":
		world.ships[d.partner_ship].deal_space = peak if reserve else 0
	elif not d.black:
		world.ports[d.party].deal_space = warehouse_holds(outgoing,incoming) if reserve else {}

static func receivable(d: Dictionary) -> int:
	var value: int=d.tax_reserve-int(d.get("bid_credit",0))
	for item in d.want:
		if item.kind=="cash":
			value+=int(item.quantity)
		elif item.kind=="ware":
			value+=int(item.quantity)*int(Industry.BASE[item.id])
	return value

static func escrow(world, d: Dictionary, withdraw: bool) -> void:
	var sign := -1 if withdraw else 1
	cash(world,d.kind,d.party,sign*int(d.tax_reserve),false)
	if d.kind=="company" or (d.kind=="station" and not d.black):
		var entity: Dictionary = world.firms[d.party] if d.kind=="company" else world.ports[d.party]
		if withdraw:
			entity.deal_receivable=receivable(d)
		else:
			entity.erase("deal_receivable")
	for side in ["give","want"]:
		var player_side: bool = side == "give"
		for item in d[side]:
			if item.kind == "cash":
				var reserved_elsewhere: int = 0 if player_side else int(d.get("bid_credit",0))
				cash(world,"player" if player_side else d.kind,d.client if player_side else d.party,sign*(int(item.quantity)-reserved_elsewhere),d.black and not player_side)
			elif item.kind == "ware":
				var stock := inventory(world,d,player_side)
				stock[item.id] += sign*int(item.quantity)
	lock_space(world,d,withdraw)

static func propose(world, kind: String, id: int, give: Array, want: Array, black: bool = false) -> Dictionary:
	if not world.campaign.get("diplomatic_deal",{}).is_empty():
		return reply("已有尚待确认的签约，可先交割或取消原协议。")
	var info := evaluate(world,kind,id,give,want,black)
	if not info.accepted:
		return info
	var number: int = world.uid()
	var d := {"id":number,"client":world.player,"kind":kind,"party":id,"black":black,"representative":info.representative,"give":info.give.duplicate(true),"want":info.want.duplicate(true),"bid_credit":info.bid_credit,
		"ship":world.ride().get("id",0),"dock":Partners.location(world),"partner_ship":info.partner_ship,"expires":world.day+int(Industry.RULES.equity_orders.period_days),
		"tax":info.tax,"tax_reserve":info.tax_reserve,"tax_flag":info.tax_flag,"tax_name":info.tax_name,"tax_rate":world.ports[Partners.location(world)].get("tariff_rate",0.0),
		"goods_given":info.goods_given,"goods_received":info.goods_received,"give_value":info.give_value,"want_value":info.want_value,"cash_delta":info.cash_delta}
	world.campaign.diplomatic_deal = d
	for side in ["give","want"]:
		for item in d[side]:
			if item.kind not in ["company_share","station_share"]:
				continue
			if item.order_id > 0:
				d.expires = mini(d.expires,item.order_expiry)
			else:
				var scope: String = "company" if item.kind=="company_share" else "station"
				var book: Dictionary = world.EquityOrders.book(world,scope,item.id)
				var party := share_party(world,scope,item.id,d.kind,d.party)
				book.used[world.EquityOrders.direction(party,side=="want")] = true
				item.epoch = book.epoch
	escrow(world,d,true)
	info.deal_id = number
	info.expires = d.expires
	return info

static func unlock(world, d: Dictionary, completed: bool = false) -> void:
	escrow(world,d,false)
	world.campaign.erase("diplomatic_deal")
	for side in ["give","want"]:
		for item in d[side]:
			if item.kind not in ["company_share","station_share"]:
				continue
			var scope := "company" if item.kind=="company_share" else "station"
			var registry: Dictionary = world.campaign.get("equity_orders",{})
			if item.order_id > 0 and completed:
				var order: Dictionary = registry.get("orders",{}).get(item.order_id,{})
				if not order.is_empty():
					order.quantity -= int(item.quantity)
					if not order.buying:
						var released: int = item.quantity*order.unit_price
						order.escrow -= released
						cash(world,d.kind,d.party,released,false)
					if order.quantity == 0:
						world.EquityOrders.close(world,order)
			elif item.order_id == 0 and not completed:
				var book: Dictionary = registry.get("books",{}).get(world.EquityOrders.book_key(scope,item.id),{})
				if book.get("epoch",-1) == item.get("epoch",-2):
					book.used.erase(world.EquityOrders.direction(share_party(world,scope,item.id,d.kind,d.party),side=="want"))

static func cancel(world, id: int) -> bool:
	var d: Dictionary = world.campaign.get("diplomatic_deal",{})
	if d.is_empty() or d.id != id or d.client != world.player:
		return false
	unlock(world,d)
	return true

static func daily(world) -> void:
	var d: Dictionary = world.campaign.get("diplomatic_deal",{})
	if d.is_empty():
		return
	if world.day>=d.expires:
		unlock(world,d)
		return
	for side in ["give","want"]:
		for item in d[side]:
			if item.kind not in ["company_share","station_share"]:
				continue
			var scope: String = item.kind.trim_suffix("_share")
			var jurisdiction: Dictionary = world.TradeLaw.jurisdiction(world,scope,item.id)
			var party := share_party(world,scope,item.id,d.kind,d.party)
			if jurisdiction.get("code","")!=item.law_code or jurisdiction.flag!=item.law_flag or jurisdiction.regime!=item.law_regime or not world.TradeLaw.check_transfer(world,scope,item.id,party,side=="want",item.quantity).allowed:
				unlock(world,d)
				return

static func release_order(world, order_id: int) -> void:
	if reserved_order_quantity(world,order_id)>0:
		unlock(world,world.campaign.diplomatic_deal)

static func release_for(world, person: int = 0, ship: int = 0) -> void:
	var d: Dictionary = world.campaign.get("diplomatic_deal",{})
	if d.is_empty():
		return
	if (person != 0 and (person == d.client or person == d.representative)) or (ship != 0 and (ship == d.ship or ship == d.partner_ship)):
		unlock(world,d)

static func change_shares(world, scope: String, asset: int, kind: String, id: int, delta: int) -> void:
	if scope == "company":
		if kind in ["player","person"]:
			world.StationEquity.add_units(world.people[id].shares,asset,delta)
		else:
			world.firms[asset].treasury_shares += delta
		return
	var site: Dictionary = world.ports[asset]
	var table: Dictionary = world.StationEquity.cap_table(world,site)
	if kind in ["player","person"]:
		world.StationEquity.add_units(table.people,id,delta)
	elif kind == "company":
		table.company = id
		table.company_units += delta
	else:
		table.treasury_units += delta
	site.equity = table

static func finalize_cash(world, d: Dictionary, amount: int, to_player: bool) -> void:
	var delta := amount if to_player else -amount
	var asset: Dictionary = world.ships.get(d.ship,{})
	var commodities: bool = (d.give+d.want).all(func(row):return row.kind in ["ware","cash"])
	var category := ("货物销售" if to_player else "货物采购") if commodities else "组合交易"
	world.credit(d.client,delta,asset,category)
	if d.kind == "station" and not d.black:
		var site: Dictionary = world.ports[d.party]
		var capital_receipt := 0
		for line in d.want:
			if line.kind=="station_share" and line.id==d.party:
				capital_receipt = mini(maxi(0,-delta),int(line.value))
		if capital_receipt>0:
			world.Treasury.post(world,site,capital_receipt,"库存股出售",false)
		if -delta!=capital_receipt:
			world.Treasury.post(world,site,-delta-capital_receipt,("货物采购" if to_player else "货物销售") if commodities else category)
	else:
		cash(world,d.kind,d.party,-delta,d.black)
		if d.kind == "company":
			var firm: Dictionary = world.firms[d.party]
			world.Finances.record(world,firm.director,world.Dividends.company_asset(d.party,firm),category,-delta,false,true)

static func complete(world, d: Dictionary) -> void:
	unlock(world,d,true)
	var companies := {}
	var share_markets := []
	var traded := {}
	for side in ["give","want"]:
		var receiving: bool = side == "want"
		var owner: String = d.kind if receiving else "player"
		var recipient: String = "player" if receiving else d.kind
		var source: int = d.party if receiving else d.client
		var target: int = d.client if receiving else d.party
		for item in d[side]:
			match item.kind:
				"cash":
					finalize_cash(world,d,item.quantity,receiving)
				"ware":
					var outgoing := inventory(world,d,not receiving)
					var incoming := inventory(world,d,receiving)
					outgoing[item.id] -= int(item.quantity)
					incoming[item.id] += int(item.quantity)
					traded[item.id] = true
					if d.kind == "station" and not d.black:
						var port: Dictionary = world.ports[d.party]
						world.Finances.record(world,port.owner,port,"",item.base if receiving else -item.base,true)
						if receiving and port.firm != 0:
							world.firms[port.firm].revenue += int(item.base)
					if d.black:
						var actor: Dictionary = world.people[d.client]
						actor.suspicion = mini(100,int(actor.get("suspicion",0))+int(item.quantity)*(3 if item.id==Industry.Ware.LUXURY else 1))
				"company_share","station_share":
					var scope := "company" if item.kind == "company_share" else "station"
					change_shares(world,scope,item.id,owner,source,-int(item.quantity))
					change_shares(world,scope,item.id,recipient,target,item.quantity)
					if scope=="company":
						companies[item.id] = true
					share_markets.append([scope,item.id])
				"treaty":
					Partners.treaty(world,item.id,true)
	for company in companies:
		world.Politics.board(world,company)
	if d.give.size()==1 and d.want.size()==1 and share_markets.size()==1:
		var security: Dictionary=d.give[0] if d.give[0].kind!="cash" else d.want[0]
		var consideration: Dictionary=d.want[0] if d.give[0].kind!="cash" else d.give[0]
		if consideration.kind=="cash":
			world.StockPrices.record(world,share_markets[0][0],security.id,security.quantity,consideration.quantity)
	for market in share_markets:
		world.EquityOrders.audit(world,market[0],market[1])
	if d.tax>0:
		if d.kind=="station":
			world.Treasury.post(world,world.ports[d.party],-int(d.tax),"商品税代缴")
		elif d.kind=="person":
			world.credit(d.party,-int(d.tax),world.ships[d.partner_ship],"商品税代缴")
		world.Economy.remit_goods_tax(world,d.tax_flag,d.tax)
	if not traded.is_empty() and d.kind=="station":
		var site: Dictionary = world.ports[d.party]
		if not d.black:
			world.chart(site.id)
		world.combat_event("trade",site.pos,site.system)
		world.trade_event(d.black,d.client)
		for ware in traded:
			world.market_updated.emit(site.id,ware,d.black)

static func confirm(world, id: int) -> Dictionary:
	var d: Dictionary = world.campaign.get("diplomatic_deal",{})
	if d.is_empty() or d.id != id or d.client != world.player:
		return reply("没有这份待交割的协议。")
	var p: Dictionary = Partners.participant(world,d.kind,d.party,d.black)
	var valid: bool = world.day < d.expires and not p.is_empty() and p.get("representative",0) == d.representative and Partners.location(world)==d.dock
	if not d.black and int(d.goods_given)+int(d.goods_received)>0:
		var port: Dictionary = world.ports.get(d.dock,{})
		valid = valid and int(port.get("tariff_flag",-1))==d.tax_flag and (d.tax_flag<0 or is_equal_approx(float(port.get("tariff_rate",0.0)),float(d.tax_rate)))
	for side in ["give","want"]:
		var receiving: bool = side=="want"
		for item in d[side]:
			if item.kind=="ware":
				valid = valid and Partners.cargo_ship(world,world.active(),d.dock)==d.ship and (d.kind!="person" or p.get("ship",0)==d.partner_ship)
			elif item.kind in ["company_share","station_share"]:
				var scope := "company" if item.kind=="company_share" else "station"
				valid = valid and holding(world,scope,item.id,d.kind if receiving else "player",d.party if receiving else d.client)>=item.quantity
				var party := share_party(world,scope,item.id,d.kind,d.party)
				var signer: Dictionary = world.EquityOrders.participants(world,scope,item.id).get(party,{})
				var law: Dictionary = world.TradeLaw.check_transfer(world,scope,item.id,party,receiving,item.quantity)
				valid = valid and law.allowed and law.flag==item.law_flag and law.regime==item.law_regime and world.TradeLaw.jurisdiction(world,scope,item.id).code==item.law_code
				valid = valid and not signer.is_empty() and signer.get("representative",0)==d.representative and not world.EquityOrders.controlled(world,signer,scope,item.id,party)
				if receiving and signer.get("controller",false):
					valid = valid and int(signer.units)-int(item.quantity)>=world.EquityOrders.majority(world,scope,item.id)
				if item.order_id>0:
					var order: Dictionary = world.campaign.get("equity_orders",{}).get("orders",{}).get(item.order_id,{})
					valid = valid and order.get("quantity",0)>=item.quantity and world.EquityOrders.authorized(world,order)
			elif item.kind=="treaty":
				valid = valid and Partners.treaty(world,item.id,false).get("ok",false)
	if not valid:
		unlock(world,d)
		return reply("泊位、产权、签字权限或期限已变化，托管资产已返还。",d.representative)
	complete(world,d)
	var result := reply("协议全部交割。",d.representative)
	result.accepted = true
	result.score = 100
	result.label = "已交割"
	result.deal_id = id
	for field in ["tax","tax_flag","tax_name","goods_given","goods_received","give_value","want_value","cash_delta"]:
		result[field] = d[field]
	return result

static func valid(data: Dictionary) -> bool:
	var d: Variant = data.campaign.get("diplomatic_deal",{})
	if not d is Dictionary:
		return false
	if d.is_empty():
		for registry in [data.firms,data.ports]:
			for entity in registry.values():
				if not entity is Dictionary or entity.get("deal_receivable",0)!=0:
					return false
		return true
	for key in ["id","client","party","representative","dock","ship","partner_ship","expires"]:
		if not d.get(key) is int:
			return false
	for field in ["tax","tax_reserve","bid_credit","goods_given","goods_received","give_value","want_value"]:
		if not d.get(field) is int or d[field]<0:
			return false
	if not d.get("tax_flag") is int or not d.get("tax_rate") is float or not d.get("tax_name") is String or not d.get("cash_delta") is int:
		return false
	if d.id <= 0 or d.id >= data.next_id or d.expires <= data.day or d.client != data.player or not data.people.has(d.client) or not d.get("black") is bool or not data.people.has(d.representative) or not data.ports.has(d.dock) or not data.campaign.get("share_listings",{}) is Dictionary:
		return false
	var tables := {"company":"firms","station":"ports","person":"people","faction":"factions"}
	if not tables.has(d.get("kind")) or not data[tables[d.kind]].has(d.party):
		return false
	for ship in [d.ship,d.partner_ship]:
		if ship != 0 and not data.ships.has(ship):
			return false
	var tax_sum := 0
	var guaranteed := 0
	var unique := {}
	var measures := {"give":0,"want":0,"goods_give":0,"goods_want":0}
	for side in ["give","want"]:
		if not d.get(side) is Array or d[side].is_empty() or d[side].size()>MAX_LINES:
			return false
		var rows: Array = d[side]
		if normalized(rows).size()!=rows.size():
			return false
		for item in rows:
			if not item.get("value") is int or item.value<0:
				return false
			var key: String = "%s/%d"%[item.kind,item.id]
			if unique.has(key):
				return false
			unique[key]=true
			measures[side]+=item.value
			match item.kind:
				"cash":
					if item.id!=0 or item.value!=item.quantity:
						return false
				"ware":
					if item.id not in range(Industry.WARES.size()) or d.ship==0 or d.kind not in ["person","station"] or (d.kind=="person" and d.partner_ship==0):
						return false
					if not item.get("tax") is int or item.tax<0 or not item.get("base") is int or item.base<=0 or item.value!=(item.base+item.tax if side=="want" else item.base-item.tax):
						return false
					tax_sum+=int(item.tax)
					measures["goods_"+side]+=item.base
				"company_share","station_share":
					var scope := "company" if item.kind=="company_share" else "station"
					if not data["firms" if scope=="company" else "ports"].has(item.id) or not item.get("order_id") is int or not item.get("law_flag") is int or not item.get("law_regime") is int or not item.get("law_code") is String:
						return false
					if item.order_id>0:
						var order: Dictionary = data.campaign.get("equity_orders",{}).get("orders",{}).get(item.order_id,{})
						if order.get("scope","")!=scope or order.get("asset",-1)!=item.id or order.get("quantity",0)<item.quantity or order.buying!=(side=="want") or order.decider!=d.representative or item.value!=int(order.unit_price)*int(item.quantity):
							return false
						if side=="give":
							guaranteed+=int(item.value)
				"treaty":
					if d.kind!="faction" or side!="want" or item.id!=d.party or item.quantity!=1:
						return false
	var paid: int = amounts(d.give,"cash").get(0,0)
	var requested: int = amounts(d.want,"cash").get(0,0)
	if d.kind=="company" or (d.kind=="station" and not d.black):
		if data["firms" if d.kind=="company" else "ports"][d.party].get("deal_receivable",0)!=receivable(d):
			return false
	for item in d.give:
		if item.kind not in ["company_share","station_share"]:
			continue
		var scope: String=item.kind.trim_suffix("_share")
		var quantity: int=item.quantity
		for listing in data.campaign.get("share_listings",{}).values():
			if listing is Dictionary and listing.get("status","")=="open" and listing.get("seller",0)==d.client and listing.get("scope","")==scope and listing.get("asset",-1)==item.id:
				quantity+=int(listing.get("remaining",0))
		var own: int=data.people[d.client].shares.get(item.id,0) if scope=="company" else StationEquity.cap_table(data,data.ports[item.id]).people.get(d.client,0)
		if quantity>own:
			return false
	var leaving:=amounts(d.give,"ware")
	var arriving:=amounts(d.want,"ware")
	if not arriving.is_empty() or not leaving.is_empty():
		var peak:=maxi(mass(leaving),mass(arriving))
		if int(data.ships[d.ship].get("deal_space",0))!=peak or (d.kind=="person" and int(data.ships[d.partner_ship].get("deal_space",0))!=peak):
			return false
		if d.kind=="station" and not d.black and data.ports[d.party].get("deal_space",{})!=warehouse_holds(leaving,arriving):
			return false
	return d.tax==tax_sum and d.tax_reserve==maxi(0,tax_sum-paid) and d.bid_credit==mini(requested,guaranteed) and measures.give==d.give_value and measures.want==d.want_value and d.cash_delta==d.want_value-d.give_value and measures.goods_give==d.goods_given and measures.goods_want==d.goods_received and (not d.black or tax_sum==0)
