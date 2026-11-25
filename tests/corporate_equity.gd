extends SceneTree

const World = preload("res://world.gd")
var count := 0
var failed := 0

func check(ok: bool, caption: String) -> bool:
	count += 1
	if not ok:
		failed += 1
		printerr("FAIL ",caption)
	return ok

func negotiation() -> void:
	var world := World.new()
	world.new_game({"seed":"negotiation","systems":12,"factions":3,"overrides":[{"regime":4}]})
	var firm_id: int = world.factions[0].firm
	var firm: Dictionary = world.firms[firm_id]
	var chief: Dictionary = world.people[firm.director]
	var actor := world.active()
	actor.wallet = 1000000
	# Capitalize this mature business so one-credit trading ticks resolve personality discounts.
	firm.treasury += int(firm.issued)*50
	var unit: int = world.Equity.overview(world,firm_id).unit_price
	var rows: Dictionary = world.Equity.participants(world,firm_id)
	var row: Dictionary = rows[chief.id]
	chief.wallet = unit*20+1000
	chief.opinions[actor.id] = -100
	var angry: Dictionary = world.EquityOrders.propose(world,"company",firm_id,chief.id,1,true,unit*3)
	check(not angry.accepted and angry.decider==chief.id and "好感" in angry.reason,"the shareholder can refuse even a premium because of a personal grievance")
	chief.opinions[actor.id] = 15
	var ordinary: Dictionary = world.EquityOrders.decision(world,"company",firm_id,chief.id,row,true,unit,unit*3)
	chief.opinions[actor.id] = 80
	var friendly: Dictionary = world.EquityOrders.decision(world,"company",firm_id,chief.id,row,true,unit,unit*3)
	check(ordinary.accepted and friendly.accepted and friendly.unit_price < ordinary.unit_price,"the same shareholder quotes a friend a lower price")
	chief.personality.greed += 40
	var demanding: Dictionary = world.EquityOrders.decision(world,"company",firm_id,chief.id,row,true,unit,unit*3)
	check(demanding.unit_price > friendly.unit_price,"the actual signer's higher greed raises their required consideration")
	var low: Dictionary = world.EquityOrders.propose(world,"company",firm_id,chief.id,1,true,demanding.unit_price-1)
	var approved: Dictionary = world.EquityOrders.propose(world,"company",firm_id,chief.id,1,true,demanding.unit_price)
	check(not low.accepted and approved.accepted and approved.unit_price==demanding.unit_price and approved.solicited,"a reluctant holder signs precisely the premium previously refused below")
	check(world.EquityOrders.cancel(world,approved.order_id) and not world.EquityOrders.propose(world,"company",firm_id,chief.id,1,true,unit*3).accepted,"withdrawing a signed negotiation does not regenerate that period's allotment")

	var other := world.random_person(0,firm.hq)
	var a: Dictionary = world.ports[world.port(0,"经营甲",Vector2(1200,0),world.NEUTRAL,actor.id,0)]
	var b: Dictionary = world.ports[world.port(0,"经营乙",Vector2(1600,0),world.NEUTRAL,actor.id,0)]
	a.manager = other
	b.manager = other
	var manager: Dictionary = world.people[other]
	manager.opinions[actor.id] = 70
	manager.wallet = 10000
	var original: int = manager.wallet
	var first: Dictionary = world.EquityOrders.propose(world,"station",a.id,other,2,false,1)
	var second: Dictionary = world.EquityOrders.propose(world,"station",b.id,other,2,false,1)
	if not check(first.accepted and second.accepted,"one real manager may independently submit funded bids for two related operations"):
		return
	check(first.escrow+second.escrow+manager.wallet==original and world.EquityOrders.escrow_for(world,other)==first.escrow+second.escrow,"cash already committed on one market cannot remain in the other market's spending budget")
	var restored := World.new()
	check(restored.load_state(world.snapshot()) and restored.EquityOrders.escrow_for(restored,other)==original-manager.wallet,"an active multilateral escrow survives save and load")
	var malformed := world.snapshot()
	malformed.campaign.equity_orders.orders[first.order_id].escrow += 1
	check(not restored.load_state(malformed),"altered escrow cannot be restored as spendable capital")
	var proceeds: int = actor.wallet
	check(world.StationEquity.trade(world,a,other,1,false,first.unit_price,first.order_id) and actor.wallet==proceeds+first.unit_price and world.EquityOrders.cancel(world,first.order_id) and world.EquityOrders.cancel(world,second.order_id) and manager.wallet==original-first.unit_price,"partial settlement pays the player once and cancellation returns both unspent deposits exactly")

	a.firm = firm_id
	a.equity = {"people":{actor.id:100},"company":0,"company_units":0,"treasury_units":0,"total":100}
	firm.treasury = 10000
	var pre := world.Equity.overview(world,firm_id)
	var bid: Dictionary = world.EquityOrders.propose(world,"station",a.id,-firm_id,2,false,1)
	if not check(bid.accepted and bid.decider==chief.id,"a related operating company can bid through its current director"):
		return
	var post := world.Equity.overview(world,firm_id)
	check(post.treasury+post.reserved_cash==pre.treasury and post.unit_price==pre.unit_price,"posting escrow does not reduce corporate net asset value")
	firm.director = other
	check(not world.StationEquity.trade(world,a,-firm_id,1,false,bid.unit_price,bid.order_id) and firm.treasury==pre.treasury and actor.wallet==proceeds+first.unit_price,"a removed director's old bid is void and the escrow returns to the corporation")
	var dock: Dictionary = world.ports[world.ride().dock]
	actor.ship = 0
	actor.loc = dock.id
	check(world.Equity.at_market(world),"a shipless resident can use their local brokerage")
	dock.coalition_blockade = true
	check(not world.Equity.at_market(world),"a physically blockaded resident cannot bypass the closure on foot")
	dock.coalition_blockade = false
	dock.firm = firm_id
	actor.flag = 1
	firm.embargo = actor.flag
	check(not world.Equity.at_market(world),"on-foot policy checks the resident's actual faction against the operating company's embargo")
	firm.embargo = -1
	dock.flag = 0
	world.set_treaty(0,1,-1)
	check(not world.Equity.at_market(world),"hostile factions cannot use an unfriendly market as civilians")
	actor.loc = 0
	check(not world.Equity.at_market(world),"without a physical port no brokerage is available")

func _initialize() -> void:
	negotiation()
	var world := World.new()
	world.new_game({"seed":"enterprise-register","systems":24,"factions":5,"overrides":[{"regime":2},{"regime":4}]})
	for flag in [0,1]:
		var group: Dictionary = world.factions[flag]
		var id: int = group.firm
		var data := world.Equity.overview(world,id)
		check(data.flag == flag and data.director == group.leader and data.hq == group.capital and data.ports.size() >= 2,"both corporate regimes have their own multiport holding company")
		var seat: Dictionary = world.ports[group.capital]
		world.mark_seen(seat.system)
		var surface: Dictionary = world.ports[world.systems[seat.system].planets[0].port_id]
		check(surface.firm == id and world.StationEquity.cap_table(world,surface).company == id,"newly visited corporate planets have the correct operator and majority owner")
	var company: int = world.factions[1].firm
	var chief: int = world.firms[company].director
	var actor := world.active()
	actor.wallet = 1000000
	var data := world.Equity.overview(world,company)
	var unit: int = data.unit_price
	var seller: Dictionary = world.people[chief]
	var cash: int = actor.wallet+seller.wallet
	var original: int = seller.shares[company]
	check(not world.Equity.trade(world,company,chief,1,true,unit),"money and a shareholder do not authorize an unposted trade")
	var majority: int = world.EquityOrders.majority(world,"company",company)
	var refused := world.EquityOrders.propose(world,"company",company,chief,original-majority+1,true,unit*2)
	check(original >= majority and not refused.accepted and seller.shares[company]==original,"an unsolicited majority takeover cannot force the chair to surrender control")
	var signed := world.EquityOrders.propose(world,"company",company,chief,4,true,unit*2)
	if not check(signed.accepted,"a founder signs a limited minority sale"):
		quit(1)
		return
	check(actor.shares.get(company,0)==0 and actor.wallet+seller.wallet==cash,"a signed ask awaits confirmation")
	check(not world.Equity.trade(world,company,chief,5,true,signed.unit_price,signed.order_id) and not world.Equity.trade(world,company,chief,4,true,signed.unit_price+1,signed.order_id),"the seller's limit and authorized quantity are binding")
	check(world.Equity.trade(world,company,chief,4,true,signed.unit_price,signed.order_id) and actor.shares[company]==4 and seller.shares[company]==original-4 and actor.wallet+seller.wallet==cash,
		"both sides settle exactly the price and quantity the founder approved")
	check(not world.Equity.trade(world,company,chief,4,true,signed.unit_price,signed.order_id),"replaying a filled quote cannot issue more shares")
	check(world.Equity.vote(world,company,chief) and world.firms[company].director==chief and world.Equity.supporters(world,company).get(chief,0)==original,
		"the new shareholder can cast its four real votes alongside the chair's remaining stake")
	var branches: Array = world.Equity.overview(world,company).ports
	var before: int = actor.wallet
	for id in branches.slice(0,2):
		var port: Dictionary = world.ports[id]
		world.Treasury.post(world,port,data.issued,"货物销售")
		port.dividend_policy = {"percent":100,"reserve":0}
		check(world.Dividends.settle(world,port)==data.issued,"a branch moves its distribution into the actual holding company's cash")
	world.firms[company].dividend_policy = {"percent":100,"reserve":0}
	check(world.firms[company].treasury == 2*int(data.issued) and actor.wallet == before and world.Dividends.settle_company(world,company)==2*int(data.issued) and actor.wallet == before+8,
		"two branches fund a single dividend of two credits per outstanding share")
	unit = world.Equity.overview(world,company).unit_price
	var buyer: int = world.random_person(1,data.hq)
	world.ports[branches[0]].manager = buyer
	world.people[buyer].opinions[world.player] = 70
	world.people[buyer].wallet = 20*unit+300
	var buyer_cash: int = world.people[buyer].wallet
	var bid := world.EquityOrders.propose(world,"company",company,buyer,1,false,maxi(1,unit/2))
	check(bid.accepted and world.people[buyer].wallet==buyer_cash-bid.get("unit_price",0) and actor.shares[company]==4,
		"a willing operating manager deposits an actual bid before any shares move")
	check(bid.accepted and world.Equity.trade(world,company,buyer,1,false,bid.unit_price,bid.order_id) and actor.shares[company]==3 and world.people[buyer].shares.get(company,0)==1,
		"the buyer receives the stock only after confirmation")
	var child: int = world.random_person(1,data.hq)
	seller.noble = true
	seller.children = [child]
	world.people[child].parents = [chief]
	var inherited: int = seller.shares[company]
	world.Politics.die(world,chief)
	check(world.people[child].shares.get(company,0) == inherited and seller.shares.is_empty(),"the registered position is inherited without issuing stock")
	var lost: Dictionary = world.ports[branches[1]]
	var previous := world.StationEquity.cap_table(world,lost)
	world.Politics.conquer(world,lost.id,0)
	var table := world.StationEquity.cap_table(world,lost)
	check(lost.firm == world.factions[0].firm and table.company == previous.company and table.company_units == previous.company_units,
		"conquest changes the operator while preserving pre-existing investors")
	var port_id: int = world.port(0,"私产",Vector2(4500,1500),world.NEUTRAL,world.player,0)
	var private_id := world.incorporate("私人运输",world.player,port_id)
	world.Politics.conquer(world,port_id,0)
	check(world.ports[port_id].firm == private_id and world.firms[private_id].flag == world.NEUTRAL,"a private operator remains a distinct company across sovereignty changes")
	var restored := World.new()
	check(restored.load_state(world.snapshot()) and restored.Equity.overview(restored,company).owned == 3 and restored.firms[company].ballots.get(world.player,0) == chief,
		"corporate affiliation, shares and proxy votes survive saving")
	var invalid := world.snapshot()
	invalid.people[world.player].shares[company] += 1
	check(not restored.load_state(invalid),"a save cannot mint an extra company share")
	for field in ["treasury","operating_profit","last_dividend_day","dividend_policy"]:
		invalid = world.snapshot()
		invalid.firms[company][field] = {"percent":101,"reserve":0} if field=="dividend_policy" else ("现金" if field=="operating_profit" else (-1 if field=="treasury" else world.day+1))
		check(not restored.load_state(invalid),"invalid corporate finance field rejected: "+field)
	world.people[child].noble = false
	world.Politics.die(world,child)
	var recovered: int = world.firms[company].treasury_shares
	var proceeds: int = world.firms[company].treasury
	var earnings: int = world.firms[company].operating_profit
	unit = world.Equity.overview(world,company).unit_price
	var ask := world.EquityOrders.propose(world,"company",company,0,1,true,unit*2)
	check(recovered == inherited and ask.accepted and world.Equity.trade(world,company,0,1,true,ask.unit_price,ask.order_id) and world.firms[company].treasury_shares == recovered-1 and world.firms[company].treasury == proceeds+ask.get("unit_price",0) and world.firms[company].operating_profit == earnings,
		"an heirless estate returns existing units to treasury, whose sale funds company capital with no synthetic profit")
	print("Corporate networks and shares %d/%d" % [count-failed,count])
	quit(1 if failed else 0)
