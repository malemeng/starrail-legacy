extends RefCounted

const Rules = preload("res://data/economy/industry.json")
const StationEquity = preload("res://scripts/economy/station_equity.gd")
const Law = preload("res://scripts/campaign/securities_law.gd")
const LIMIT := 2147483647

static func listings(world) -> Array:
	var result := []
	for listing: Dictionary in world.campaign.get("share_listings",{}).values():
		if listing.seller==world.player:
			result.append(listing.duplicate(true))
	result.reverse()
	return result

static func reserved(world, scope: String, id: int, party: int) -> int:
	var quantity := 0
	for listing: Dictionary in world.campaign.get("share_listings",{}).values():
		if listing.status=="open" and listing.seller==party and listing.scope==scope and listing.asset==id:
			quantity+=listing.remaining
	return quantity

static func held(world, scope: String, id: int, party: int) -> int:
	if scope=="company":
		return world.people.get(party,{}).get("shares",{}).get(id,0)
	return world.StationEquity.cap_table(world,world.ports[id]).people.get(party,0)

static func post(world, scope: String, id: int, quantity: int, unit_price: int) -> Dictionary:
	var asset: Dictionary = world.Capital.entity(world,scope,id)
	if asset.is_empty() or not world.Equity.at_market(world) or (scope=="station" and not world.StationEquity.listed(world,asset)):
		return {"ok":false,"reason":"请在营业港为已经登记的股权挂牌。"}
	if quantity<=0 or unit_price<=0 or quantity>LIMIT or unit_price>LIMIT:
		return {"ok":false,"reason":"股数和每股最低价必须为有效正整数。"}
	var free := held(world,scope,id,world.player)-int(world.DiplomaticTrade.reserved_shares(world,scope,id,world.player))
	if free<quantity:
		return {"ok":false,"reason":"可挂牌的自有股份不足，其余股份可能已在另一笔委托中。"}
	var law: Dictionary = world.TradeLaw.jurisdiction(world,scope,id)
	if law.flag>=0 and world.hostile(law.flag,world.active().flag):
		return {"ok":false,"reason":"登记地禁止交战方挂牌。"}
	var duration := int(Rules.data.equity_orders.listing_days)
	var listing := {"id":world.uid(),"scope":scope,"asset":id,"name":asset.name,"seller":world.player,"unit_price":unit_price,
		"quantity":quantity,"remaining":quantity,"sold":0,"proceeds":0,"last_buyer":0,"status":"open","opened":world.day,
		"expires":world.day+duration,"law_flag":law.flag,"law_regime":law.regime,"law_code":law.code}
	world.campaign.get_or_add("share_listings",{})[listing.id]=listing
	return {"ok":true,"reason":"卖单已公开，所列股份已预留。","listing_id":listing.id,"listing":listing.duplicate(true)}

static func cancel(world, id: int) -> bool:
	var listing: Dictionary = world.campaign.get("share_listings",{}).get(id,{})
	if listing.get("status","")!="open" or listing.seller!=world.player:
		return false
	listing.status="cancelled"
	return true

static func legal(world, listing: Dictionary) -> bool:
	if listing.seller!=world.player or not world.Equity.adult(world,world.people.get(listing.seller,{})):
		return false
	var law: Dictionary = world.TradeLaw.jurisdiction(world,listing.scope,listing.asset)
	return not law.is_empty() and world.EquityOrders.same_registry(listing,law) and (law.flag<0 or not world.hostile(law.flag,world.people[listing.seller].flag))

static func audit(world) -> void:
	for listing: Dictionary in world.campaign.get("share_listings",{}).values():
		if listing.status!="open":
			continue
		if world.day>=listing.expires:
			listing.status="expired"
		elif not legal(world,listing) or held(world,listing.scope,listing.asset,listing.seller)<int(world.DiplomaticTrade.reserved_shares(world,listing.scope,listing.asset,listing.seller)):
			listing.status="void"

static func release_for(world, person: int) -> void:
	for listing: Dictionary in world.campaign.get("share_listings",{}).values():
		if listing.status=="open" and listing.seller==person:
			listing.status="void"

static func permits_fill(world, id: int, scope: String, asset: int, qty: int, price: int) -> bool:
	var listing: Dictionary = world.campaign.get("share_listings",{}).get(id,{})
	return listing.get("status","")=="open" and listing.scope==scope and listing.asset==asset and qty>0 and qty<=listing.remaining and price>=listing.unit_price and world.day<listing.expires and legal(world,listing)

static func settled(world, id: int, buyer: int, qty: int, price: int) -> void:
	var listing: Dictionary = world.campaign.share_listings[id]
	listing.remaining-=qty
	listing.sold+=qty
	listing.proceeds+=qty*price
	listing.last_buyer=buyer
	if listing.remaining==0:
		listing.status="filled"

static func match_bids(world, listing: Dictionary) -> void:
	var scope: String = listing.scope
	var asset: int = listing.asset
	world.EquityOrders.publish(world,scope,asset,world.EquityOrders.valuation(world,scope,asset),world.EquityOrders.participants(world,scope,asset))
	var bids: Array = world.EquityOrders.quotes(world,scope,asset,false)
	bids.sort_custom(func(a,b):return a.unit_price>b.unit_price if a.unit_price!=b.unit_price else a.order_id<b.order_id)
	for bid: Dictionary in bids:
		if bid.unit_price<listing.unit_price or listing.remaining<=0:
			break
		var qty := mini(listing.remaining,bid.quantity)
		if scope=="company":
			world.Equity.trade(world,asset,bid.person,qty,false,bid.unit_price,bid.order_id,listing.id)
		else:
			world.StationEquity.trade(world,world.ports[asset],bid.person,qty,false,bid.unit_price,bid.order_id,listing.id)

static func daily(world) -> void:
	var ledger: Dictionary = world.campaign.get("share_listings",{})
	if ledger.is_empty():
		return
	audit(world)
	var asks := []
	for listing: Dictionary in ledger.values():
		if listing.status=="open":
			asks.append(listing)
		elif world.day>int(listing.expires)+int(Rules.data.equity_orders.listing_days):
			ledger.erase(listing.id)
	asks.sort_custom(func(a,b):return a.unit_price<b.unit_price if a.unit_price!=b.unit_price else a.id<b.id)
	for listing: Dictionary in asks:
		match_bids(world,listing)

static func valid(data: Dictionary) -> bool:
	var ledger: Variant = data.campaign.get("share_listings",{})
	if not ledger is Dictionary:
		return false
	var locked := {}
	for key in ledger:
		var listing: Variant = ledger[key]
		if not listing is Dictionary or not key is int or key<=0 or key>=data.next_id or key!=listing.get("id") or listing.get("scope") not in ["company","station"]:
			return false
		for field in ["asset","seller","unit_price","quantity","remaining","sold","proceeds","last_buyer","opened","expires","law_flag","law_regime"]:
			if not listing.get(field) is int:
				return false
		var assets: Dictionary = data.firms if listing.scope=="company" else data.ports
		if not assets.has(listing.asset) or not data.people.has(listing.seller) or not listing.get("name") is String or not listing.get("law_code") is String:
			return false
		if not Law.Rules.data.codes.has(listing.law_code) or listing.law_flag< -1 or (listing.law_flag>=0 and not data.factions.has(listing.law_flag)):
			return false
		if listing.get("status") not in ["open","cancelled","expired","void","filled"] or listing.unit_price<=0 or listing.unit_price>LIMIT or listing.quantity<=0 or listing.quantity>LIMIT or listing.remaining<0 or listing.remaining>listing.quantity or listing.sold!=listing.quantity-listing.remaining or listing.proceeds<listing.sold*listing.unit_price:
			return false
		if listing.opened<0 or listing.opened>data.day or listing.expires!=int(listing.opened)+int(Rules.data.equity_orders.listing_days) or (listing.remaining==0)!=(listing.status=="filled"):
			return false
		if listing.sold==0:
			if listing.proceeds!=0 or listing.last_buyer!=0:
				return false
		elif not (data.people.has(listing.last_buyer) if listing.last_buyer>0 else data.firms.has(-int(listing.last_buyer))):
			return false
		if listing.status!="open":
			continue
		var owner: Dictionary = data.people[listing.seller]
		if listing.seller!=data.player or not owner.alive:
			return false
		var subject := [listing.scope,listing.asset,listing.seller]
		locked[subject]=int(locked.get(subject,0))+int(listing.remaining)
		var committed := 0
		var deal: Dictionary=data.campaign.get("diplomatic_deal",{})
		if deal.get("client",0)==listing.seller:
			for item: Dictionary in deal.get("give",[]):
				if item.kind==str(listing.scope)+"_share" and item.id==listing.asset:
					committed+=int(item.quantity)
		var owned: int = owner.shares.get(listing.asset,0)
		if listing.scope=="station":
			owned=StationEquity.cap_table(data,assets[listing.asset]).people.get(listing.seller,0)
		if int(locked[subject])+committed>owned:
			return false
	return true
