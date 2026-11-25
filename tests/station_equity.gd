extends SceneTree

const World = preload("res://world.gd")
const Equity = preload("res://scripts/economy/station_equity.gd")
const Industry = preload("res://scripts/economy/industry.gd")
const Politics = preload("res://politics.gd")
const Saves = preload("res://scripts/services/save_manager.gd")
var checks := 0
var failures := 0

func check(ok: bool, name: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",name)
	return ok

func quote(offered: Array, id: int) -> Dictionary:
	for row in offered:
		if row.person == id:
			return row
	return {}

func scenario() -> World:
	var world := World.new()
	world.new_game({"seed":"non-dilutive-equity","systems":12,"factions":3})
	return world

func next_period(world: World) -> void:
	world.tick(10)

func transact(world: World, site: Dictionary, order: Dictionary, units: int, buying: bool) -> bool:
	return not order.is_empty() and Equity.trade(world,site,order.person,units,buying,order.unit_price,order.order_id)

func private_orders() -> void:
	var world := scenario()
	var actor := world.active()
	var home: Dictionary = world.ports[world.ride().dock]
	var seller := world.random_person(world.NEUTRAL,home.id)
	var site: Dictionary = world.ports[world.port(0,"民营采矿轨道站",Vector2(200,200),world.NEUTRAL,seller,Industry.Module.MINE)]
	var buyer := world.random_person(world.NEUTRAL,site.id)
	var bystander := world.random_person(world.NEUTRAL,site.id)
	site.manager = buyer
	var company_shares: Dictionary = actor.shares.duplicate()
	var valuation := Equity.unit_price(site)
	actor.wallet = valuation*100
	world.people[seller].trait = 3
	world.people[seller].wallet = 0
	world.people[buyer].wallet = valuation*100
	world.people[buyer].trait = 1
	world.people[buyer].opinions[actor.id] = 65
	world.people[bystander].trait = 0
	world.people[bystander].origin = 0
	world.people[bystander].wallet = valuation*100
	world.people[bystander].opinions[actor.id] = -90
	var issue: int = Equity.cap_table(world,site).total
	check(issue>0 and Equity.cap_table(world,site).people == {seller:issue},"sole private owner holds the complete registered issue")
	check(not Equity.trade(world,site,seller,1,true,valuation),"an instruction cannot itself fabricate a shareholder sell order")
	site.scan = false
	check(not Equity.listed(world,site) and Equity.offers(world,site,true).is_empty(),"unlisted private business cannot be traded")
	site.scan = true
	var sell := quote(Equity.offers(world,site,true),seller)
	if not check(not sell.is_empty() and sell.quantity > 1,"a founder who needs liquidity offers a bounded non-controlling lot"):
		return
	var original: int = sell.quantity
	var n := mini(4,original-1)
	var wallet: int = actor.wallet
	var seller_wallet: int = world.people[seller].wallet
	check(sell.representative == seller and sell.expires > world.day and issue-original>issue/2,"real founder consents for a period while retaining a voting majority")
	check(not Equity.trade(world,site,seller,1,true,sell.unit_price-1,sell.order_id) and not transact(world,site,sell,original+1,true),"wrong price and oversized orders leave both accounts untouched")
	check(transact(world,site,sell,n,true) and actor.wallet == wallet-n*sell.unit_price and world.people[seller].wallet == seller_wallet+n*sell.unit_price and site.treasury == 0,"matched personal order pays the seller without withdrawing company or site money")
	check(quote(Equity.offers(world,site,true),seller).quantity == original-n and Equity.cap_table(world,site).people[actor.id] == n and actor.shares == company_shares,"partial fills reduce the same signed lot and transfer only station shares")
	check(not transact(world,site,sell,original-n+1,true),"partially executed offer cannot be overfilled or refreshed by reopening")
	var before: int = world.people[bystander].wallet
	var rejection: Dictionary = world.EquityOrders.propose(world,"station",site.id,bystander,1,false,sell.unit_price)
	check(not rejection.accepted and not rejection.reason.is_empty() and not Equity.trade(world,site,bystander,1,false,sell.unit_price) and world.people[bystander].wallet == before,"a rich but unwilling resident rejects the seller without transferring shares or cash")
	var bid := quote(Equity.offers(world,site,false),buyer)
	if not check(not bid.is_empty(),"a willing and solvent station manager signs a bid"):
		return
	var escrow_wallet: int = world.people[buyer].wallet
	wallet = actor.wallet
	check(transact(world,site,bid,1,false) and world.people[buyer].wallet == escrow_wallet and actor.wallet == wallet+bid.unit_price and Equity.cap_table(world,site).people[buyer] == 1,"matched bid uses the maker's escrow exactly once")
	var was: int = world.player
	world.player = seller
	check(world.EquityOrders.cancel(world,sell.order_id),"signer may withdraw the unfilled balance")
	world.player = was
	check(quote(Equity.offers(world,site,true),seller).is_empty() and not transact(world,site,sell,1,true),"a revoked order is neither matched nor recreated by refreshing this period")
	var restored := World.new()
	check(restored.load_state(world.snapshot()) and Equity.cap_table(restored,restored.ports[site.id]) == Equity.cap_table(world,site),"open and cancelled orders follow an exact save/load round trip")
	world.tick(maxi(1,int(bid.expires)-world.day+1))
	check(not transact(world,site,bid,1,false),"expired bid cannot be resurrected using its previous price or ID")
	var heir := world.random_person(world.NEUTRAL,site.id)
	world.people[seller].noble = true
	world.people[heir].noble = true
	world.people[seller].children.append(heir)
	world.people[heir].parents.append(seller)
	Politics.die(world,seller)
	check(Equity.cap_table(world,site).people[heir] == issue-n and not Equity.cap_table(world,site).people.has(seller),"inherited private equity keeps the same total issued rights")

func institutions() -> void:
	var world := scenario()
	var actor := world.active()
	var home: Dictionary = world.ports[world.ride().dock]
	var company: int = world.firms.keys().front()
	var firm: Dictionary = world.firms[company]
	var site: Dictionary = world.ports[world.systems[0].planets[0].port_id]
	Equity.set_operator(world,site,company)
	var subsidiary_units: int = Equity.cap_table(world,site).company_units
	site.scan = false
	var valuation := Equity.unit_price(site)
	var rows := Equity.participants(world,site)
	check(rows[-company].representative == firm.director and Equity.listed(world,site),"published unscanned planetary branch names the living director who represents the corporate account")
	firm.treasury = 0
	actor.wallet = 500000
	world.people[firm.director].wallet = 0
	var parent_sale := quote(world.Equity.offers(world,company,true),firm.director)
	if not check(not parent_sale.is_empty(),"the independent parent-company director signs a personal sale of existing company stock"):
		return
	var parent_units: int = mini(3,parent_sale.quantity)
	check(world.Equity.trade(world,company,firm.director,parent_units,true,parent_sale.unit_price,parent_sale.order_id),"acquire the parent position from the quoted counterparty at their price")
	world.depart(world.ride())
	check(Equity.offers(world,site,true).is_empty() and not Equity.trade(world,site,-company,1,true,valuation),"shares remain readable in flight; dealing requires a working brokerage port")
	world.berth(world.ride(),home.id)
	var sell := quote(Equity.offers(world,site,true),-company)
	if not check(not sell.is_empty(),"company places a real financing sale for a portion of its subsidiary"):
		return
	var n := mini(5,sell.quantity)
	var personal: int = actor.wallet
	var owner_cash: int = world.people[firm.director].wallet
	var station_cash: int = site.treasury
	var corporate_cash: int = firm.treasury
	check(sell.representative == firm.director and transact(world,site,sell,n,true),"authorized director signs for the company")
	check(firm.treasury == corporate_cash+n*sell.unit_price and site.treasury == station_cash and world.people[firm.director].wallet == owner_cash and actor.wallet == personal-n*sell.unit_price,"company consideration stays separate from the shareholder, booking agent and subsidiary")
	var table := Equity.cap_table(world,site)
	check(table.company_units == subsidiary_units-n and table.people[actor.id] == n,"direct and corporate station holdings are both represented after a signed trade")
	var inaccessible := world.random_person(world.NEUTRAL,site.id)
	var other_id: int = world.incorporate("新运营人",inaccessible,home.id,false)
	Equity.set_operator(world,site,other_id)
	check(Equity.cap_table(world,site).company == company and Equity.cap_table(world,site).company_units == subsidiary_units-n and site.firm == other_id,"change of operator cannot confiscate an existing corporate stake")
	site.owner = actor.id
	check(not world.Treasury.transfer(world,site,actor.id,-1) and world.Treasury.transfer(world,site,actor.id,1) and Equity.cap_table(world,site).people[actor.id] == n,"outside shares bar direct withdrawals and capital contributions do not issue stock")
	var forged := world.snapshot()
	forged.ports[site.id].equity.company_units += 1
	check(not World.new().load_state(forged),"a persisted register cannot overissue shares")
	world.Dividends.configure(world,site,100,0)
	var distribution: int = 10*(int(table.total)-int(table.treasury_units))
	world.Treasury.post(world,site,distribution,"居民税收")
	corporate_cash = firm.treasury
	personal = actor.wallet
	var company_income := (subsidiary_units-n)*10
	check(world.Dividends.settle(world,site) == distribution and firm.treasury-corporate_cash == company_income and actor.wallet-personal == n*10,"after a genuinely accepted deal, each outstanding station share earns ten credits")
	world.player = firm.director
	check(world.Dividends.configure_company(world,company,100,0),"the separate company board authorizes payment of its retained income")
	world.player = actor.id
	var indirect_expected := company_income*parent_units/(int(firm.issued)-int(firm.treasury_shares))
	personal = actor.wallet
	check(world.Dividends.settle_company(world,company) == company_income and absi(actor.wallet-personal-indirect_expected) <= 1,"ordinary investor receives a second cash dividend from real signed parent shares and the exact retained subsidiary payment")
	var new_director: int = firm.director
	firm.director = actor.id
	next_period(world)
	check(quote(Equity.offers(world,site,true),-company).is_empty() and quote(Equity.offers(world,site,false),-company).is_empty(),"a corporation directed by the player does not sign autonomous dealings with its own director")
	firm.director = new_director

func estates() -> void:
	var world := scenario()
	var home: Dictionary = world.ports[world.ride().dock]
	var ownerless := world.random_person(world.NEUTRAL,home.id)
	var site: Dictionary = world.ports[world.port(0,"无继承人民营站",Vector2(1200,600),world.NEUTRAL,ownerless,Industry.Module.MINE)]
	var issue: int = Equity.cap_table(world,site).total
	Politics.die(world,ownerless)
	var table := Equity.cap_table(world,site)
	check(table.people.is_empty() and table.treasury_units == table.total and table.total == issue and issue>0,"unclaimed private estate conserves every authorized unit as saleable facility treasury stock")
	world.Treasury.post(world,site,1000,"居民税收")
	check(world.Dividends.settle(world,site) == 0 and site.treasury == 1000,"cash remains at the station when there are no outstanding shares")
	world.active().wallet = 500000
	var resale := quote(Equity.offers(world,site,true),Equity.TREASURY_PARTY)
	if not check(not resale.is_empty(),"the estate registrar offers a real treasury-stock lot"):
		return
	var signer := Equity.trustee(world,site)
	var cash: int = site.treasury
	var profit: int = site.operating_profit
	var signer_cash: int = world.people[signer].wallet
	check(signer != 0 and resale.representative == signer and resale.name == "站点库存股" and transact(world,site,resale,1,true),"independent named estate registrar signs the facility issue")
	check(site.treasury == cash+resale.unit_price and site.operating_profit == profit and world.people[signer].wallet == signer_cash and world.people[ownerless].wallet == 0,"the facility receives financing without creating income for dead holders or its representative")
	check(World.new().load_state(world.snapshot()),"partially issued estate stock and its order are loadable")

func control_rights() -> void:
	var world := scenario()
	var actor := world.active()
	var home: Dictionary = world.ports[world.ride().dock]
	var founder := world.random_person(world.NEUTRAL,home.id)
	var site: Dictionary = world.ports[world.port(0,"控股人谈判",Vector2(300,300),world.NEUTRAL,founder,Industry.Module.MINE)]
	var table := Equity.cap_table(world,site)
	var majority := int(table.total)/2+1
	table.people = {founder:majority,actor.id:int(table.total)-majority}
	site.equity = table
	actor.wallet = 500000
	world.people[founder].wallet = 0
	var demand: Dictionary = world.EquityOrders.propose(world,"station",site.id,founder,1,true,100000)
	check(not demand.accepted and demand.representative == founder and "控制权" in demand.reason,"even an extravagant offer cannot force a controlling founder to give up the final majority share")
	check(quote(Equity.offers(world,site,true),founder).is_empty() and not Equity.trade(world,site,founder,1,true,100000) and Equity.cap_table(world,site).people[founder] == majority,"an unwilling owner cannot be acquired solely because they hold enough stock")

func long_market() -> void:
	var world := World.new()
	world.new_game({"seed":"industrial-soak","systems":24,"factions":5,"avatar":{"age":18}})
	for index in range(6):
		world.mark_seen(index)
	var start := Time.get_ticks_msec()
	var half := 0
	var max_open := 0
	var max_bytes := 0
	var active_books := 0
	var last_sequence := 0
	var error := ""
	var save_path := "user://equity-soak-%s.save" % OS.get_process_id()
	for segment in 20:
		world.tick(500)
		var market: Dictionary = world.EquityOrders.state(world)
		active_books = market.books.size()
		last_sequence = market.sequence
		max_open = maxi(max_open,market.orders.size())
		max_bytes = maxi(max_bytes,var_to_bytes(market).size())
		for order in market.orders.values():
			if order.expires <= world.day or order.escrow != (0 if order.buying else order.quantity*order.unit_price) or order.quantity <= 0:
				error = "stale, unfunded or negative order %d at day %d" % [order.order_id,world.day]
		if not error.is_empty() or world.day != (segment+1)*500:
			break
		if segment == 9 or segment == 19:
			var restored := World.new()
			if not Saves.write(world,save_path,false) or not Saves.read(restored,save_path) or restored.campaign.equity_orders != market:
				error = "real disk save rejected or changed live orders on day %d" % world.day
				break
			world = restored
			if segment == 9:
				half = Time.get_ticks_msec()-start
	var elapsed := Time.get_ticks_msec()-start
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	check(world.day == 10000 and error.is_empty(),"10,000 live campaign days and two disk restores with solvent order escrow: "+error)
	check(active_books <= world.ports.size()+world.firms.size() and last_sequence > max_open*10,"expired orders do not accumulate on the active books")
	print("Equity soak day=%d ports=%d firms=%d books=%d issued=%d peak_live=%d peak_ledger_bytes=%d first_5000_ms=%d second_5000_ms=%d" % [world.day,world.ports.size(),world.firms.size(),active_books,last_sequence,max_open,max_bytes,half,elapsed-half])

func _initialize() -> void:
	private_orders()
	institutions()
	estates()
	control_rights()
	if "--soak" in OS.get_cmdline_user_args():
		long_market()
	print("Station equity %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
