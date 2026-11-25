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
	var w := World.new()
	w.new_game({"seed":"securities-law","systems":18,"factions":4,"overrides":[{"regime":3},{"regime":1}]})
	var actor := w.active()
	actor.wallet=1000000
	actor.flag=1
	w.set_treaty(0,1,0)
	var seat: Dictionary = w.ports[w.factions[0].capital]
	var other: Dictionary = w.ports[w.factions[1].capital]
	var founder := w.random_person(0,seat.id)
	var hq := w.port(seat.system,"外资公司总部",seat.pos+Vector2(500,0),1,founder,0)
	var branch := w.port(other.system,"异地经营港",other.pos+Vector2(500,0),0,founder,0)
	var company := w.incorporate("登记公司",founder,hq)
	w.StationEquity.set_operator(w,w.ports[branch],company)
	w.people[founder].wallet=0
	w.people[founder].opinions[actor.id]=80
	var outstanding: int = w.firms[company].issued
	var threshold := ceili(outstanding*0.1)
	var limit := outstanding*49/100
	var law := w.TradeLaw.jurisdiction(w,"company",company)
	check(law.flag==0 and law.code=="restricted" and w.TradeLaw.jurisdiction(w,"station",branch).code=="open","HQ and each branch register under the government of their own physical system")
	check(w.TradeLaw.check(w,"transfer","company",company,actor.id,founder,threshold-1).allowed and w.TradeLaw.check(w,"transfer","company",company,actor.id,founder,threshold).approval_required,"outside investors can buy below the review threshold")
	check(not w.TradeLaw.enact(w,0,"open").allowed and w.TradeLaw.realm_code(w,0)=="restricted","private investors cannot legislate")
	var buyer := w.random_person(1,hq)
	w.ports[hq].manager=buyer
	var manager: Dictionary = w.people[buyer]
	manager.wallet=50000
	manager.opinions[actor.id]=80
	w.people[founder].shares[company]-=threshold-2
	actor.shares[company]=threshold-2
	var offers := w.Equity.offers(w,company,true)
	var asks := offers.filter(func(row):return row.person==founder)
	if check(asks.size()==1 and asks[0].quantity==1,"the displayed public ask has exactly one legally deliverable share"):
		var ask: Dictionary=asks[0]
		var wallet: int=actor.wallet
		check(not w.Equity.trade(w,company,founder,2,true,ask.unit_price,ask.order_id) and w.Equity.trade(w,company,founder,1,true,ask.unit_price,ask.order_id) and actor.wallet==wallet-ask.unit_price and actor.shares[company]==threshold-1,"the legal fraction changes both cash and voting shares, with no overfill")
	var ruler: int=law.ruler
	w.people[ruler].opinions[actor.id]=-100
	check(not w.TradeLaw.request_permit(w,"company",company).allowed and w.TradeLaw.active_permit(w,"company",company,actor.id,law).is_empty(),"a disapproving living regulator refuses an application")
	w.people[ruler].opinions[actor.id]=80
	check(w.TradeLaw.request_permit(w,"company",company).allowed and w.TradeLaw.check_transfer(w,"company",company,founder,true,1).allowed,"the actual regulator's signature opens the review threshold")
	check(w.TradeLaw.check_transfer(w,"company",company,founder,true,limit-int(actor.shares[company])).allowed and not w.TradeLaw.check_transfer(w,"company",company,founder,true,limit-int(actor.shares[company])+1).allowed,"the foreign ownership ceiling still applies above a signed permit")
	var permit: Dictionary=w.TradeLaw.active_permit(w,"company",company,actor.id,law)
	var today:int=w.day
	w.day=permit.expires
	check(not w.TradeLaw.check_transfer(w,"company",company,founder,true,1).allowed,"a permit stops authorizing settlement on its expiry day")
	w.day=today
	w.day+=10
	var mandate:=w.EquityOrders.propose(w,"company",company,founder,2,true,1000)
	if check(mandate.accepted,"two shares can be signed while the permit is active"):
		var successor:=w.random_person(0,seat.id)
		w.Society.install_ruler(w,0,successor,false)
		check(w.TradeLaw.active_permit(w,"company",company,actor.id,w.TradeLaw.jurisdiction(w,"company",company)).is_empty() and not w.EquityOrders.state(w).orders.has(mandate.order_id) and not w.Equity.trade(w,company,founder,1,true,mandate.unit_price,mandate.order_id),"a new head of state invalidates the old permit and orders relying on it")
	var issue_site:=w.port(seat.system,"自有工业站",seat.pos+Vector2(-500,0),1,actor.id,0)
	var facts:=w.Capital.overview(w,"station",issue_site)
	var permitted_qty:=int(facts.issued)*15/100
	check(not w.Capital.authorize(w,"station",issue_site,permitted_qty+1,facts.minimum_price).ok and w.Capital.authorize(w,"station",issue_site,permitted_qty,facts.minimum_price).ok,"primary issuance is capped at exactly the registry's percentage of issued capital")
	var before:int=manager.wallet
	var bid:=w.EquityOrders.propose(w,"company",company,buyer,2,false,1)
	if check(bid.accepted and manager.wallet==before-2*bid.unit_price,"a real independent bidder escrows the full cash for lawful resale"):
		w.set_treaty(0,1,-1)
		check(manager.wallet==before and not w.EquityOrders.state(w).orders.has(bid.order_id) and not w.Equity.trade(w,company,buyer,1,false,bid.unit_price,bid.order_id),"war immediately refunds the buyer and blocks old settlement")
		w.set_treaty(0,1,0)
		check(not w.Equity.trade(w,company,buyer,1,false,bid.unit_price,bid.order_id),"a peace treaty cannot resurrect the retired bid")
	w.day+=10
	var authority:=w.EquityOrders.propose(w,"company",company,buyer,2,false,1)
	if check(authority.accepted,"a new signed bid can be settled under current law"):
		w.Society.install_ruler(w,0,w.player,false)
		var changed:=w.TradeLaw.enact(w,0,"licensed")
		check(changed.allowed and w.TradeLaw.realm_code(w,0)=="licensed" and manager.wallet==before and not w.EquityOrders.state(w).orders.has(authority.order_id),"a ruler enacting a new code within the same regime refunds existing orders")
		check(not w.ports[issue_site].has("primary_offer") and not w.Equity.trade(w,company,buyer,1,false,authority.unit_price,authority.order_id),"the old primary issue and secondary ID cannot be reused after reform")
	var new_bid:=w.EquityOrders.propose(w,"company",company,buyer,2,false,1)
	if check(new_bid.accepted,"a lawful bid can be freshly negotiated without waiting for the previous registry's book to expire"):
		w.Politics.conquer(w,seat.id,1)
		check(w.TradeLaw.jurisdiction(w,"company",company).flag==1 and manager.wallet==before and not w.EquityOrders.state(w).orders.has(new_bid.order_id),"a foreign conquest changes private headquarters jurisdiction and releases its old cash escrow")
		var fresh:=w.EquityOrders.propose(w,"company",company,buyer,2,false,1)
		var funds: int=actor.wallet
		check(fresh.accepted and fresh.order_id!=new_bid.order_id and w.Equity.trade(w,company,buyer,1,false,fresh.unit_price,fresh.order_id) and actor.wallet==funds+fresh.unit_price and manager.shares[company]==1 and w.EquityOrders.state(w).orders[fresh.order_id].quantity==1,"a newly signed two-share order permits one actual share to cross into the new jurisdiction")
	print("Securities jurisdiction and secondary settlement %d/%d" % [checks-errors,checks])
	quit(1 if errors else 0)
