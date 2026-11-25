extends SceneTree

const World = preload("res://world.gd")
var checks := 0
var errors := 0

func check(ok: bool, label: String) -> bool:
	checks+=1
	if not ok:
		errors+=1
		printerr("FAIL ",label)
	return ok

func _initialize() -> void:
	var w:=World.new()
	w.new_game({"seed":"public-exchange","systems":16,"factions":4,"overrides":[{"regime":1}]})
	var actor:=w.active()
	var vessel:=w.ride()
	var dock:int=vessel.dock
	var seat: Dictionary=w.ports[w.factions[0].capital]
	var private_id:=w.port(seat.system,"贸易公司总部",seat.pos+Vector2(500,0),1,actor.id,0)
	var company:=w.incorporate("晨曦运输",actor.id,private_id)
	var firm: Dictionary=w.firms[company]
	actor.flag=1
	w.set_treaty(0,1,0)
	var buyer:=w.random_person(0,dock)
	w.ports[private_id].manager=buyer
	var manager: Dictionary=w.people[buyer]
	manager.wallet=50000
	manager.opinions[actor.id]=80
	var before:int=actor.shares[company]
	var cash:int=actor.wallet
	var bid:=w.EquityOrders.propose(w,"company",company,buyer,2,false,1)
	if not check(bid.accepted and manager.wallet==50000-2*bid.unit_price,"an independent manager posted and funded a limited two-share bid"):
		quit(1)
		return
	var expensive:=w.ShareExchange.post(w,"company",company,before-5,100000)
	var cheap:=w.ShareExchange.post(w,"company",company,5,1)
	check(expensive.ok and cheap.ok and w.ShareExchange.reserved(w,"company",company,actor.id)==before and actor.shares[company]==before and actor.wallet==cash,"two distinct asks lock their stocks without delivering cash or shares")
	check(not w.ShareExchange.post(w,"company",company,1,1).ok and not w.Equity.trade(w,company,buyer,1,false,bid.unit_price,bid.order_id) and w.Equity.offers(w,company,false).is_empty(),"a second public ask and direct broker trade cannot reuse the same pledged shares")
	var barter:=w.DiplomaticTrade.preview(w,"person",buyer,[{"kind":"company_share","id":company,"quantity":1}],[{"kind":"cash","id":0,"quantity":1}])
	check(not barter.accepted,"the bilateral trade desk cannot sell a share already publicly listed")
	var saved:=World.new()
	var original:=w.snapshot()
	check(saved.load_state(original) and saved.ShareExchange.listings(saved).size()==2 and saved.ShareExchange.reserved(saved,"company",company,actor.id)==before,"a real save restores both live asks and their full ownership reservation")
	var tampered:=original.duplicate(true)
	tampered.campaign.share_listings[cheap.listing_id].quantity+=1
	tampered.campaign.share_listings[cheap.listing_id].remaining+=1
	check(not saved.load_state(tampered),"a save with overlapping asks for more than the real holdings is rejected")
	w.depart(vessel)
	check(not w.ShareExchange.post(w,"company",company,1,1).ok,"new sales must be posted from a live market")
	w.tick()
	var sale: Dictionary=w.campaign.share_listings[cheap.listing_id]
	var tape:=w.StockPrices.quote(w,"company",company)
	check(sale.status=="open" and sale.sold==2 and sale.remaining==3 and sale.last_buyer==buyer and sale.proceeds==2*bid.unit_price,"a docked manager's signed two-share bid partially fills the cheapest ask while the seller is in flight")
	check(actor.wallet==cash+sale.proceeds and manager.wallet==50000-sale.proceeds and actor.shares[company]==before-2 and manager.shares.get(company,0)==2 and tape.last==bid.unit_price and tape.volume==2,"cash, beneficial ownership and execution tape all settle exactly once")
	check(w.campaign.share_listings[expensive.listing_id].sold==0 and w.ShareExchange.cancel(w,cheap.listing_id) and not w.ShareExchange.cancel(w,cheap.listing_id) and w.ShareExchange.reserved(w,"company",company,actor.id)==before-5,"unmatched asks do not fabricate a buyer and cancelling releases only the three unsold units")
	w.set_treaty(0,1,-1)
	check(w.campaign.share_listings[expensive.listing_id].status=="void" and w.ShareExchange.reserved(w,"company",company,actor.id)==0,"the registry embargo revokes existing asks and restores stock immediately")
	w.set_treaty(0,1,0)
	w.berth(vessel,dock)
	var guarded:=w.ShareExchange.post(w,"company",company,2,100000)
	w.Politics.conquer(w,seat.id,1)
	check(guarded.ok and w.campaign.share_listings[guarded.listing_id].status=="void","a change in registered sovereignty retires old offers, even when both jurisdictions permit trade")
	var site_id:=w.port(0,"私人矿站",Vector2(900,1000),w.NEUTRAL,actor.id,0)
	var site: Dictionary=w.ports[site_id]
	var local:=w.random_person(w.NEUTRAL,site_id)
	w.people[local].wallet=40000
	w.people[local].opinions[actor.id]=90
	site.manager=local
	var ask:=w.ShareExchange.post(w,"station",site_id,3,1)
	w.tick()
	var bought: Dictionary=w.campaign.share_listings[ask.listing_id]
	var register:=w.StationEquity.cap_table(w,site)
	check(bought.status=="filled" and bought.sold==3 and register.people.get(local,0)==3 and w.StockPrices.quote(w,"station",site_id).volume==3,"independent station managers can initiate orders and completely fill a public station-share listing")
	var unfilled:=w.ShareExchange.post(w,"station",site_id,4,1000000)
	w.day=unfilled.listing.expires
	w.ShareExchange.daily(w)
	check(w.campaign.share_listings[unfilled.listing_id].status=="expired" and w.ShareExchange.reserved(w,"station",site_id,actor.id)==0,"when no purchaser accepts the requested price the public sale expires without transferring ownership")
	var will:=w.ShareExchange.post(w,"company",company,5,99999)
	var heirs:=w.Politics.heirs(w,actor.id)
	var old_units:int=actor.shares[company]
	w.Politics.die(w,actor.id,false)
	var received:=0
	for heir in heirs:
		received+=int(w.people[heir].shares.get(company,0))
	check(will.ok and w.campaign.share_listings[will.listing_id].status=="void" and w.ShareExchange.reserved(w,"company",company,actor.id)==0 and (heirs.is_empty() or received==old_units),"death withdraws the deceased's instructions before ordinary estate distribution")
	check(firm.issued==before,"secondary trading and expiry never issue extra shares")
	print("Public share exchange %d/%d" % [checks-errors,checks])
	quit(1 if errors else 0)
