extends SceneTree

const World=preload("res://world.gd")
var count:=0
var failures:=0

func check(ok: bool, note: String) -> bool:
	count+=1
	if not ok:
		failures+=1
		printerr("FAIL ",note)
	return ok

func _initialize() -> void:
	var w:=World.new()
	w.new_game({"seed":"executed-prices","systems":12,"factions":3})
	var p:=w.active()
	var home: Dictionary=w.ports[w.ride().dock]
	p.wallet=100000
	var owner:=w.random_person(w.NEUTRAL,home.id)
	w.people[owner].opinions[p.id]=60
	var site: Dictionary=w.ports[w.port(0,"云岬加工",Vector2(600,0),w.NEUTRAL,owner,w.Industry.Module.MINE)]
	var firm:=w.incorporate("云岬物流",owner,site.id)
	var price:=w.StockPrices.quote(w,"company",firm)
	check(price.reference>0 and price.last==0 and price.history.is_empty(),"a newly registered company has a valuation and no fabricated market price")
	var ask: Dictionary={}
	for order in w.Equity.offers(w,firm,true):
		if order.person==owner:
			ask=order
			break
	if not check(not ask.is_empty(),"a real founder has registered an ask"):
		quit(1)
		return
	var amount:int=ask.unit_price
	var block_trade:=World.new()
	if check(ask.quantity>100 and block_trade.load_state(w.snapshot()),"a funded shareholder may post an order larger than one hundred shares and retain the entire signed quantity across saves"):
		var block_order:=block_trade.DiplomaticTrade.sign_order(block_trade,ask.order_id,101,amount)
		check(block_order.accepted and block_trade.DiplomaticTrade.confirm(block_trade,block_order.deal_id).accepted and block_trade.active().shares[firm]==101 and block_trade.StockPrices.quote(block_trade,"company",firm).volume==101,"a single real trade transfers more than one hundred shares without breaking the holder's voting majority")
	var tradable:=w.DiplomaticTrade.quote_order(w,ask.order_id,3)
	check(tradable.accepted and tradable.contact_id==owner and tradable.unit_price==amount and not w.DiplomaticTrade.sign_order(w,ask.order_id,3,amount+1).accepted and w.StockPrices.quote(w,"company",firm).last==0,"looking at one specific ask or refusing the wrong limit does not print a trade")
	var signed:=w.DiplomaticTrade.sign_order(w,ask.order_id,3,amount)
	check(signed.accepted and w.StockPrices.quote(w,"company",firm).last==0 and w.DiplomaticTrade.confirm(w,signed.deal_id).accepted,"the unified table settles exactly the selected order, printing only at settlement")
	price=w.StockPrices.quote(w,"company",firm)
	check(price.last==amount and price.previous==0 and price.change==0 and price.history.size()==1 and price.volume==3,"first print and trading-day volume reflect three real shares")
	var security: Array=[{"kind":"company_share","id":firm,"quantity":1}]
	var higher:=amount+8
	signed=w.DiplomaticTrade.propose(w,"person",owner,[{"kind":"cash","id":0,"quantity":higher}],security)
	check(signed.accepted and w.DiplomaticTrade.confirm(w,signed.deal_id).accepted,"the buyer can offer a higher actual cash price to the owner")
	price=w.StockPrices.quote(w,"company",firm)
	check(price.last==higher and price.previous==amount and price.change==8 and price.change_percent>0 and price.volume==4 and price.history.size()==1 and price.history[0].price==higher,"a second trade raises the price and updates the same day's close and quantity")
	w.day+=1
	var buyer:=w.random_person(w.NEUTRAL,home.id)
	site.manager=buyer
	w.people[buyer].wallet=5000
	w.people[buyer].opinions[p.id]=70
	var bid:=w.EquityOrders.propose(w,"company",firm,buyer,2,false,1)
	if check(bid.accepted and bid.unit_price<higher,"a different buyer signs a funded bid for the player's shares"):
		var selected:=w.DiplomaticTrade.quote_order(w,bid.order_id,2)
		signed=w.DiplomaticTrade.sign_order(w,bid.order_id,2,bid.unit_price)
		check(selected.accepted and selected.want[0].kind=="cash" and signed.accepted and w.DiplomaticTrade.confirm(w,signed.deal_id).accepted and not w.DiplomaticTrade.sign_order(w,bid.order_id,1,bid.unit_price).accepted,"the same unified table can sell into a bid and cannot resubmit a filled order")
		price=w.StockPrices.quote(w,"company",firm)
		check(price.last==bid.unit_price and price.previous==higher and price.change<0 and price.change_percent<0 and price.volume==2 and price.history.size()==2 and price.history[0].volume==4,"a genuinely lower trade marks down the instrument while preserving the earlier close")
	var restored:=World.new()
	check(restored.load_state(w.snapshot()) and restored.StockPrices.quote(restored,"company",firm)==price,"price, movement and aggregated actual trading history round-trip through normal saves")
	var raw:=w.snapshot()
	raw.campaign.stock_tape.values()[0].history.back().volume=-1
	check(not restored.load_state(raw),"corrupted trading volume does not load")
	print("Executed stock prices and pinned order dockets %d/%d"%[count-failures,count])
	quit(1 if failures else 0)
