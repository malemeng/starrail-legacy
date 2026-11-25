extends SceneTree

const World = preload("res://world.gd")
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> bool:
	checks+=1
	if not ok:
		errors+=1
		printerr("FAIL ",message)
	return ok

func _initialize() -> void:
	var w:=World.new()
	w.new_game({"seed":"registered-capital","systems":12,"factions":3,"overrides":[{"regime":4}]})
	var p:=w.active()
	p.wallet=50000
	var home: Dictionary=w.ports[w.ride().dock]
	var founder:=w.random_person(w.NEUTRAL,home.id)
	w.people[founder].opinions[p.id]=80
	w.people[founder].wallet=1400
	var company:=w.incorporate("安珀勘探",founder,home.id,false)
	var corporation: Dictionary=w.firms[company]
	var original:=w.Capital.overview(w,"company",company)
	check(original.issued==1400/int(original.par_value) and original.outstanding==original.issued and original.paid_in_capital==1400 and corporation.treasury==1400 and w.people[founder].wallet==0,"a cash-founded company uses actual paid-in assets, with one vote per outstanding share")
	var before:=var_to_bytes(w.snapshot())
	check(not w.Capital.authorize(w,"company",company,20,20).ok and not w.Capital.solicit(w,"company",company,50,1).ok and var_to_bytes(w.snapshot())==before,"an outsider cannot sign in place of the holder or obtain a below-par issue")
	var issue_qty: int = mini(8, int(original.max_quantity))
	var issue_price: int = int(original.minimum_price)
	var offer:=w.Capital.solicit(w,"company",company,issue_qty,issue_price)
	if check(offer.ok and corporation.issued==original.issued and p.shares.get(company,0)==0,"the actual controlling founder signs public issue terms before any dilution or cash receipt"):
		var sub_qty := maxi(1, issue_qty - 2)
		var cost:=issue_price*sub_qty
		var funds:int=p.wallet
		var founder_shares:int=w.people[founder].shares[company]
		var filled:=w.Capital.subscribe(w,"company",company,sub_qty,issue_price,offer.offer.id)
		var after:=w.Capital.overview(w,"company",company)
		check(filled.ok and filled.cost==cost and corporation.treasury==1400+cost and p.wallet==funds-cost and after.issued==original.issued+sub_qty and p.shares[company]==sub_qty,"cash settles to the issuing corporation while new shares settle to the subscriber")
		check(after.offer.remaining==issue_qty-sub_qty and p.shares[company]*1.0/after.outstanding>0 and w.people[founder].shares[company]==founder_shares and founder_shares*1.0/after.outstanding<1.0 and after.paid_in_capital==1400+cost and after.share_premium==sub_qty*(issue_price-int(after.par_value)) and corporation.operating_profit==0,"the old holder is diluted only by actual subscriptions and issue premium is capital rather than profit")
		var restored:=World.new()
		check(restored.load_state(w.snapshot()) and restored.Capital.overview(restored,"company",company).offer.remaining==issue_qty-sub_qty and not restored.Capital.subscribe(restored,"company",company,issue_qty-sub_qty+1,issue_price).ok and not restored.Capital.subscribe(restored,"company",company,1,issue_price-1).ok and not restored.Capital.subscribe(restored,"company",company,1,issue_price,offer.offer.id+1).ok,"remaining quantity, issue ID and issue price survive a save")
		p.wallet=1
		before=var_to_bytes(w.snapshot())
		check(not w.Capital.subscribe(w,"company",company,2,issue_price).ok and var_to_bytes(w.snapshot())==before,"an unfunded subscription cannot dilute the cap table")
		w.day=offer.offer.expires
		check(not w.Capital.subscribe(w,"company",company,1,issue_price).ok,"expired primary issues cannot be filled")
	p.wallet=50000
	var yard: Dictionary=w.ports[w.port(0,"独立轨道船厂",Vector2(400,300),w.NEUTRAL,p.id,w.Industry.Module.YARD)]
	var mine: Dictionary=w.ports[w.port(0,"小型采矿站",Vector2(200,250),w.NEUTRAL,p.id,w.Industry.Module.MINE)]
	var a:=w.Capital.overview(w,"station",yard.id)
	var b:=w.Capital.overview(w,"station",mine.id)
	check(a.issued>100 and b.issued>100 and a.issued!=b.issued and a.votes_per_share==1 and a.signer==p.id and a.can_issue,"independent facilities register different numbers of shares against different actual assets")
	var qty:=mini(10,a.max_quantity)
	var unit:int=a.minimum_price+2
	offer=w.Capital.authorize(w,"station",yard.id,qty,unit)
	if check(offer.ok,"a station's majority owner can authorize a legal at-or-above-value issue"):
		var treasury:int=yard.treasury
		var tick:=w.Capital.subscribe(w,"station",yard.id,qty,unit)
		var final:=w.Capital.overview(w,"station",yard.id)
		check(tick.ok and final.issued==a.issued+qty and final.owned==final.issued and yard.treasury==treasury+qty*unit and yard.operating_profit==0 and final.offer.is_empty(),"station financing is paid into the station treasury without fabricating a trading profit")
		check(not w.Capital.subscribe(w,"station",yard.id,1,unit).ok,"an exhausted issue cannot deliver an extra share")
	var public:=w.Capital.overview(w,"station",home.id)
	check(not public.can_issue and not public.can_solicit and public.holders[0].get("public",false),"an unincorporated public port keeps its public mandate and cannot be diluted by a visiting investor")
	home.flag=0
	w.refresh_tariffs(0)
	p.flag=0
	w.factions[0].leader=p.id
	var current:String=w.TradeLaw.realm_code(w,0)
	var stricter:="licensed" if current!="licensed" else "restricted"
	offer=w.Capital.authorize(w,"station",yard.id,3,unit)
	check(offer.ok and w.TradeLaw.enact(w,0,stricter).allowed and not yard.has("primary_offer") and w.TradeLaw.enact(w,0,current).allowed and not w.Capital.subscribe(w,"station",yard.id,1,unit).ok,"an enacted statute invalidates the original authorization even if the old statute is subsequently reinstated")
	print("Capital registry and subscriptions %d/%d"%[checks-errors,checks])
	quit(1 if errors else 0)
