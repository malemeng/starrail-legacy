extends SceneTree

const World = preload("res://world.gd")
const Deals = preload("res://scripts/economy/diplomatic_trade.gd")
const Industry = preload("res://scripts/economy/industry.gd")
var checks := 0
var errors := 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		errors += 1
		printerr("FAIL ",label)
	return ok

func item(kind: String, id: int, quantity: int) -> Dictionary:
	return {"kind":kind,"id":id,"quantity":quantity}

func credits(quantity: int) -> Dictionary:
	return item("cash",0,quantity)

func setup() -> World:
	var world := World.new()
	world.new_game({"seed":"joint-bilateral-ledger","systems":12,"factions":3,"overrides":[{"regime":4}]})
	return world

func snapshot(world: World) -> PackedByteArray:
	return var_to_bytes(world.snapshot())

func markets() -> void:
	var world := setup()
	var actor := world.active()
	var ship := world.ride()
	var site: Dictionary = world.ports[ship.dock]
	var start_cash: int = actor.wallet
	var shop: int = site.treasury
	var ore: int = site.stock[0]
	var water: int = site.stock[Industry.Ware.WATER]
	var ask := [item("ware",0,5),item("ware",Industry.Ware.WATER,2)]
	var expected := world.Economy.trade_quote(world,site,0,5).y+world.Economy.trade_quote(world,site,Industry.Ware.WATER,2).y
	var state := snapshot(world)
	var draft := Deals.preview(world,"station",site.id,[],ask)
	var catalogue := Deals.catalog(world,"station",site.id)
	check(not catalogue.want.is_empty() and not draft.accepted and draft.cash_delta==expected and draft.want_value==expected and snapshot(world)==state,"read-only catalog and incomplete draft quote both lots at ordinary prices")
	check(not Deals.preview(world,"station",site.id,[credits(1)],[item("ware",0,2147483647)]).accepted,"impossible quantities are rejected before quoting per-unit curves")
	var tender := [credits(expected)]
	var agreement := Deals.propose(world,"station",site.id,tender,ask)
	if not check(agreement.accepted,"the market signs the quoted two-commodity basket"):
		print(agreement)
		return
	check(actor.wallet==start_cash-expected and site.treasury==shop and site.stock[0]==ore-5 and ship.cargo[0]==0,"on signing both the money and actual stock enter escrow once")
	check(not Deals.propose(world,"station",site.id,tender,ask).accepted and world.cargo_free(ship)==world.HULL_CARGO[ship.kind]-7,"one live deal cannot be overwritten or promise cargo space twice")
	var copy := World.new()
	check(copy.load_state(world.snapshot()) and Deals.cancel(copy,agreement.deal_id) and copy.active().wallet==start_cash and copy.ports[site.id].stock[0]==ore,"signed whole bundle survives normal save/load and can be cancelled for a complete refund")
	check(Deals.confirm(world,agreement.deal_id).accepted and site.treasury==shop+expected and actor.wallet==start_cash-expected and site.stock[0]==ore-5 and site.stock[Industry.Ware.WATER]==water-2 and ship.cargo[0]==5 and ship.cargo[Industry.Ware.WATER]==2,"confirmation settles both wares and cash at their locked prices")
	check(not Deals.confirm(world,agreement.deal_id).accepted and not Deals.cancel(world,agreement.deal_id),"a confirmed deal can be neither repeated nor refunded")
	var offered := [item("ware",0,3),item("ware",Industry.Ware.WATER,1)]
	var take := [item("ware",Industry.Ware.FUEL,1)]
	var barter := Deals.preview(world,"station",site.id,offered,take)
	check(barter.cash_delta<0,"mixed barter computes the correct cash payable by the shop")
	take.append(credits(-barter.cash_delta))
	var before: int = actor.wallet
	var site_before: int = site.treasury
	var gain: int = -barter.cash_delta
	agreement = Deals.propose(world,"station",site.id,offered,take)
	check(agreement.accepted and Deals.confirm(world,agreement.deal_id).accepted and actor.wallet==before+gain and site.treasury==site_before-gain and ship.cargo[0]==2 and ship.cargo[Industry.Ware.FUEL]==1,"mixed barter transfers two kinds out and one kind plus change back, reconciling both wallets")
	site.treasury = 0
	state = snapshot(world)
	var bid := world.Economy.lot_quote(site,0,1,false,actor.origin).y
	check(not Deals.propose(world,"station",site.id,[item("ware",0,1)],[credits(bid)]).accepted and snapshot(world)==state,"an unfunded public bid cannot consume the trader's ore or create a deal")
	site.treasury = site_before
	var black_funds: int = site.black_treasury
	var public_funds: int = site.treasury
	var contraband: int = site.black[Industry.Ware.LUXURY]
	var black_quote := world.Economy.trade_quote(world,site,Industry.Ware.LUXURY,1,true)
	agreement = Deals.propose(world,"station",site.id,[credits(black_quote.y)],[item("ware",Industry.Ware.LUXURY,1)],true)
	check(agreement.accepted and Deals.confirm(world,agreement.deal_id).accepted and site.black_treasury==black_funds+black_quote.y and site.treasury==public_funds and ship.cargo[Industry.Ware.LUXURY]==1 and site.black[Industry.Ware.LUXURY]==contraband-1 and actor.suspicion==3,"contraband uses actual private stock, untaxed prices, separate cash and suspicion")
	check(not Deals.preview(world,"station",site.id,[item("ware",Industry.Ware.LUXURY,1)],[credits(1)]).accepted,"public market declines contraband")
	var quote := world.Economy.trade_quote(world,site,0,1)
	state = snapshot(world)
	agreement = Deals.propose(world,"station",site.id,[credits(quote.y)],[item("ware",0,1)])
	world.depart(ship)
	check(agreement.accepted and not Deals.confirm(world,agreement.deal_id).accepted and actor.wallet==before+gain-black_quote.y and not world.campaign.has("diplomatic_deal"),"departure invalidates delivery and returns the entire escrow to its original owners")

func securities() -> void:
	var world := setup()
	var actor := world.active()
	var lead := world.ride()
	var home: Dictionary = world.ports[lead.dock]
	var founder: int = world.random_person(world.NEUTRAL,home.id)
	world.people[founder].wallet=1250
	var merchant: Dictionary = world.ships[world.ship(0,founder,founder,world.NEUTRAL,0,home.pos,home.id)]
	var company: int = world.incorporate("组包航运",founder,home.id,false)
	world.firms[company].treasury = 50000
	var person: Dictionary = world.people[founder]
	person.wallet = 0
	person.opinions[actor.id] = 65
	actor.wallet = 100000
	var sell: Dictionary = {}
	for row in world.Equity.offers(world,company,true):
		if row.person==founder:
			sell=row
			break
	if not check(not sell.is_empty() and sell.quantity>=4,"real owner of an operating company has signed an independently limited sell mandate"):
		return
	var want := [item("company_share",company,2)]
	var give := [item("ware",0,1)]
	lead.cargo[0] = 1
	var draft := Deals.preview(world,"person",founder,give,want)
	if not check(draft.cash_delta>0,"cargo partly funds a signed offer of privately held company shares"):
		print(draft)
		return
	give.append(credits(draft.cash_delta))
	var base: int = actor.wallet
	var agreement := Deals.propose(world,"person",founder,give,want)
	if not check(agreement.accepted,"personal mixed securities deal signs after supplementing the cash balance"):
		print(agreement)
		return
	var remainder := 0
	for row in world.Equity.offers(world,company,true):
		if row.order_id==sell.order_id:
			remainder=row.quantity
	check(remainder==sell.quantity-2 and Deals.reserved_shares(world,"company",company,founder)==2,"shares already signed into the bundle are absent from the broker's independently executable balance")
	check(world.Equity.trade(world,company,founder,1,true,sell.unit_price,sell.order_id),"remaining uncommitted shares stay tradable")
	check(Deals.confirm(world,agreement.deal_id).accepted and actor.shares[company]==3 and person.shares[company]==world.firms[company].issued-3 and actor.wallet==base-draft.cash_delta-sell.unit_price and merchant.cargo[0]==1,"both routes can complete without double-spending a share, credit or commodity")
	var left: Dictionary = world.campaign.equity_orders.orders[sell.order_id]
	check(left.quantity==sell.quantity-3 and world.firms[company].treasury==50000,"only the executed original mandate units were retired; the person did not spend company cash")
	merchant.owner = 0
	check(not Deals.preview(world,"person",founder,[credits(1000)],[item("ware",0,1)]).accepted,"a captain cannot sell borrowed or entrusted cargo as their own")
	var state := snapshot(world)
	check(not Deals.propose(world,"company",company,[credits(200)],[item("ware",0,1)]).accepted and snapshot(world)==state,"a corporation cannot invent ware stock or raid a subsidiary's warehouse")
	var corp: int = world.factions[0].firm
	var firm: Dictionary = world.firms[corp]
	var site: Dictionary = world.ports[firm.hq]
	var stock := [item("station_share",site.id,1)]
	world.people[firm.director].opinions[actor.id] = 65
	firm.treasury = 0
	draft = Deals.preview(world,"company",corp,[],stock)
	agreement = Deals.propose(world,"company",corp,[credits(maxi(1,int(draft.cash_delta)))],stock)
	if check(agreement.accepted,"a company's real director signs only for its station holdings"):
		check(Deals.confirm(world,agreement.deal_id).accepted and world.StationEquity.cap_table(world,site).people[actor.id]==1 and firm.treasury==draft.cash_delta,"corporate holdings and treasury settle without transferring the director's private stock")

func diplomacy() -> void:
	var world := setup()
	var actor := world.active()
	var group: Dictionary = world.factions[1]
	var own: Dictionary = world.factions[0]
	actor.flag = 0
	actor.wallet = 100000
	world.set_treaty(0,1,-1)
	world.people[group.leader].opinions[actor.id]=60
	var treaty := [item("treaty",1,1)]
	check(not Deals.preview(world,"faction",1,[credits(1000)],treaty).accepted,"a private citizen cannot exchange faction agreements")
	own.leader = actor.id
	var quote := Deals.preview(world,"faction",1,[],treaty)
	var before: int = group.treasury
	var chief: int = world.people[group.leader].wallet
	var pact := Deals.propose(world,"faction",1,[credits(quote.cash_delta)],treaty)
	if check(pact.accepted and world.treaty(0,1).state==-1,"both factions' proper mandates are required and signing alone does not end the war"):
		check(Deals.confirm(world,pact.deal_id).accepted and world.treaty(0,1).state==0 and group.treasury-before==quote.cash_delta and world.people[group.leader].wallet==chief,"confirmation sets the real truce, pays the foreign treasury once and leaves its envoy's money alone")

func commodity_taxes() -> void:
	var world := setup()
	var actor := world.active()
	var ship := world.ride()
	var home: Dictionary = world.ports[ship.dock]
	home.flag=0
	home.tax_rate=0.2
	var manager := world.random_person(world.NEUTRAL,home.id)
	var port: Dictionary = world.ports[world.port(0,"外资贸易站",Vector2(1500,0),1,manager,Industry.Module.MINE)]
	port.manager=manager
	port.stock[0]=160
	port.stock[Industry.Ware.FUEL]=60
	port.treasury=2500
	port.tax_rate=0.03
	world.refresh_tariffs(0)
	world.berth(ship,port.id)
	actor.wallet=10000
	actor.origin=1
	var crown: int = world.factions[0].treasury
	var foreign: int = world.factions[1].treasury
	var merchant: int = world.people[manager].wallet
	var dues := [item("ware",0,5),item("ware",Industry.Ware.FUEL,2)]
	var preview := Deals.preview(world,"station",port.id,[],dues)
	var bill: Dictionary = Industry.lot_invoice(port,0,5,true,actor.origin)
	var fuel: Dictionary = Industry.lot_invoice(port,Industry.Ware.FUEL,2,true,actor.origin)
	if not check(preview.tax==bill.tax+fuel.tax and preview.tax>0 and preview.tax_flag==0 and preview.goods_received==bill.base+fuel.base and preview.cash_delta==bill.total+fuel.total,"a public lot shows its discounted tax base and attributes both commodities to the local sovereign"):
		print(preview)
		return
	var before: int = port.treasury
	var profit: int = port.operating_profit
	var signed := Deals.propose(world,"station",port.id,[credits(preview.cash_delta)],dues)
	check(signed.accepted and world.factions[0].treasury==crown and Deals.cancel(world,signed.deal_id) and world.factions[0].treasury==crown,"unsigned and cancelled commerce generates no sovereign tax")
	signed=Deals.propose(world,"station",port.id,[credits(preview.cash_delta)],dues)
	home.flag=1
	world.refresh_tariffs(0)
	check(not Deals.confirm(world,signed.deal_id).accepted and world.factions[1].treasury==foreign and actor.wallet==10000,"a new sovereign cannot collect a predecessor's unconfirmed invoice")
	home.flag=0
	world.refresh_tariffs(0)
	signed=Deals.propose(world,"station",port.id,[credits(preview.cash_delta)],dues)
	var receipt:=Deals.confirm(world,signed.deal_id)
	check(receipt.accepted and receipt.tax==preview.tax and actor.wallet==10000-preview.cash_delta and port.treasury==before+preview.goods_received and port.operating_profit==profit+preview.goods_received and world.factions[0].treasury==crown+receipt.tax and world.people[manager].wallet==merchant and world.factions[1].treasury==foreign,"discounted market purchase and operating income reconcile across all three distinct accounts")
	var give := [item("ware",Industry.Ware.FUEL,1)]
	var want := [item("ware",0,1)]
	var draft := Deals.preview(world,"station",port.id,give,want)
	if draft.cash_delta<0:
		want.append(credits(-draft.cash_delta))
	elif draft.cash_delta>0:
		give.append(credits(draft.cash_delta))
	before=actor.wallet+port.treasury+world.factions[0].treasury
	crown=world.factions[0].treasury
	signed=Deals.propose(world,"station",port.id,give,want)
	check(signed.accepted and Deals.confirm(world,signed.deal_id).accepted and world.factions[0].treasury==crown+draft.tax and draft.tax>0 and before==actor.wallet+port.treasury+world.factions[0].treasury,"two-way barter remits tax on both goods even when only the net difference changes hands")
	var person: Dictionary = world.people[manager]
	var other: Dictionary = world.ships[world.ship(0,manager,manager,world.NEUTRAL,0,port.pos,port.id)]
	person.loc=port.id
	person.opinions[actor.id]=65
	person.wallet=1600
	other.cargo[0]=9
	want=[item("ware",0,3)]
	draft=Deals.preview(world,"person",manager,[],want)
	before=person.wallet
	crown=world.factions[0].treasury
	signed=Deals.propose(world,"person",manager,[credits(draft.cash_delta)],want)
	check(signed.accepted and draft.tax>0 and Deals.confirm(world,signed.deal_id).accepted and world.factions[0].treasury==crown+draft.tax and person.wallet==before+draft.goods_received,"ordinary private handover is taxed at the port on the person's actual negotiated price")

func linked_bids() -> void:
	var world:=setup()
	var actor:=world.active()
	var home: Dictionary=world.ports[world.ride().dock]
	var site: Dictionary=world.ports[world.port(0,"私有设施",Vector2(900,100),world.NEUTRAL,world.player,Industry.Module.MINE)]
	var buyer:=world.random_person(world.NEUTRAL,home.id)
	site.manager=buyer
	var person: Dictionary=world.people[buyer]
	person.opinions[actor.id]=70
	person.wallet=10000
	var bid: Dictionary=world.EquityOrders.propose(world,"station",site.id,buyer,3,false,1)
	if not check(bid.accepted,"a willing manager signs a real three-share bid"):
		print(bid)
		return
	world.credit(buyer,-int(person.wallet))
	var credit_before: int=actor.wallet
	var give: Array=[item("station_share",site.id,2)]
	var want: Array=[credits(2*int(bid.unit_price))]
	var signed:=Deals.propose(world,"person",buyer,give,want)
	if not check(signed.accepted and world.campaign.diplomatic_deal.bid_credit==2*int(bid.unit_price) and person.wallet==0,"a linked buyer pays from their existing escrow, without charging their wallet a second time"):
		print(signed)
		return
	var copy:=World.new()
	check(copy.load_state(world.snapshot()) and copy.EquityOrders.cancel(copy,bid.order_id) and not copy.campaign.has("diplomatic_deal") and copy.people[buyer].wallet==3*int(bid.unit_price),"revoking the underlying order cancels the entire saved agreement and returns its original deposit")
	check(world.StationEquity.trade(world,site,buyer,1,false,bid.unit_price,bid.order_id) and Deals.confirm(world,signed.deal_id).accepted and person.wallet==0 and actor.wallet==credit_before+3*int(bid.unit_price) and world.StationEquity.cap_table(world,site).people[buyer]==3,"broker and package settle disjoint slices of the original funded buy order")

func signed_law() -> void:
	var world:=setup()
	var actor:=world.active()
	var home: Dictionary=world.ports[world.ride().dock]
	home.flag=0
	world.refresh_tariffs(0)
	world.factions[0].leader=actor.id
	actor.flag=0
	actor.wallet=6000
	var owner:=world.random_person(0,home.id)
	world.people[owner].wallet=1200
	world.people[owner].opinions[actor.id]=70
	var business:=world.incorporate("金库",owner,home.id,false)
	var wanted: Array=[item("company_share",business,2)]
	var terms:=Deals.preview(world,"person",owner,[],wanted)
	var signed:=Deals.propose(world,"person",owner,[credits(terms.cash_delta)],wanted)
	if not check(signed.accepted and actor.wallet==6000-int(terms.cash_delta),"a real shareholder signs a mixed-market share agreement under current jurisdiction"):
		print(signed)
		return
	var old: String=world.TradeLaw.realm_code(world,0)
	var new_code:="licensed" if old!="licensed" else "restricted"
	check(world.TradeLaw.enact(world,0,new_code).allowed and not world.campaign.has("diplomatic_deal") and actor.wallet==6000 and world.TradeLaw.enact(world,0,old).allowed and not Deals.confirm(world,signed.deal_id).accepted,"even while the government and leader remain in office a new statute releases cash and stock; the superseded agreement cannot revive")

func _initialize() -> void:
	markets()
	securities()
	diplomacy()
	commodity_taxes()
	linked_bids()
	signed_law()
	print("Bilateral transactions and ordinary markets %d/%d" % [checks-errors,checks])
	quit(1 if errors else 0)
