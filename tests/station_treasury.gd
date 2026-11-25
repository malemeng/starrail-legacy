extends SceneTree

const World = preload("res://world.gd")
const Economy = preload("res://economy.gd")
const Industry = preload("res://scripts/economy/industry.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func capital(world: World) -> int:
	var total: int = world.campaign.market_capital.core + world.campaign.market_capital.frontier
	for station in world.ports.values():
		total += int(station.treasury)+int(station.get("black_treasury",0))
	return total

func worker(world: World, home: Dictionary) -> Dictionary:
	var captain := world.random_person(world.NEUTRAL,home.id)
	return world.ships[world.ship(1,world.player,captain,world.NEUTRAL,home.system,home.pos,home.id)]

func _initialize() -> void:
	var world := World.new()
	check(world.new_game({"seed":"port-treasuries","systems":12,"factions":3}),"new game")
	var home: Dictionary = world.ports[world.ride().dock]
	var mine: Dictionary = world.ports[world.systems[1].ports[0]]
	var receiver: Dictionary = world.ports[world.systems[1].ports[1]]
	var total := capital(world)
	world.mark_seen(1)
	var planet: Dictionary = world.systems[1].planets[0]
	var surface: Dictionary = world.ports[planet.port_id]
	check(surface.treasury > 0 and capital(world) == total and surface.operating_profit == 0,"open planetary markets receive real capital once")
	world.mark_seen(1)
	check(capital(world) == total,"returning to a planet cannot recapitalise its markets")
	world.ensure_chunks_around(Vector2(46000,58000),1)
	for region in world.systems:
		if not region.get("frontier_depot",false):
			continue
		var before: int = world.campaign.market_capital.frontier
		world.mark_seen(world.systems.find(region))
		var depot: Dictionary = world.ports[region.depot_port]
		check(before-world.campaign.market_capital.frontier == depot.treasury and depot.treasury > 0 and capital(world) == total,"frontier depot borrows from finite founding reserve")
		break
	var site: Dictionary = world.ports[world.port(0,"新建工地",home.pos+Vector2(450,0),world.NEUTRAL,world.player,0,false)]
	check(site.treasury == 0 and site.operating_profit == 0 and capital(world) == total,"new construction has an empty treasury")
	var wallet: int = world.active().wallet
	check(world.Treasury.transfer(world,site,world.player,100) and site.treasury == 100 and world.active().wallet == wallet-100 and site.operating_profit == 0,"owner injection debits wallet without producing earnings")
	check(not world.Treasury.transfer(world,mine,world.player,1) and not world.Treasury.transfer(world,site,world.player,999999),"funds and permissions checked")
	check(world.Treasury.transfer(world,site,world.player,-45) and site.treasury == 55 and world.active().wallet == wallet-55,"withdrawal moves existing funds")

	var lead: Dictionary = world.ride()
	home.owner = world.player
	var opening: int = home.treasury
	wallet = world.active().wallet
	var quote := Economy.trade_quote(world,home,0,2)
	check(Economy.trade(world,home.id,0,2) == 2 and home.treasury-opening == quote.y and wallet-world.active().wallet == quote.y,"own public market settles both wallets without a rebate")
	var report: Dictionary = world.Finances.report(world,7)
	check(report.station.income == quote.y and report.ship.expense == quote.y and report.net == 0,"internal portfolio public sale has matching settled accounts")
	var row: Dictionary = report.assets.filter(func(asset):return asset.id == home.id).front()
	check(row.sales == quote.y and row.income == quote.y and not row.lines.has("商业分成"),"turnover and profit not counted twice")
	var unit := Economy.lot_quote(home,0,1,false,world.active().origin).y
	home.treasury = unit
	wallet = world.active().wallet
	check(Economy.trade(world,home.id,0,-2) == -1 and home.treasury == 0 and world.active().wallet == wallet+unit,"poor port purchases only affordable units")
	var last_report: Dictionary = world.Finances.report(world,7)
	check(Economy.trade(world,home.id,0,-1) == 0 and last_report == world.Finances.report(world,7),"failed sale produces no money, inventory or report entry")
	check(lead.cargo[0] > 0,"unsold cargo remains aboard")

	var first := worker(world,mine)
	var second := worker(world,mine)
	first.cargo[0] = 12
	second.cargo[0] = 12
	receiver.treasury = Economy.lot_quote(receiver,0,8,false).y
	check(Economy.reserve(world,first,mine,receiver,0,8,false) and world.Treasury.available(receiver) == 0,"confirmed import holds counterparty payment")
	check(not Economy.reserve(world,second,mine,receiver,0,8,false),"a second captain cannot promise the same cash twice")
	var loaded := World.new()
	check(loaded.load_state(world.snapshot()) and loaded.Treasury.available(loaded.ports[receiver.id]) == 0 and loaded.ports[receiver.id].cash_holds.has(first.id),"save and load restore the committed budget")
	wallet = world.active().wallet
	var pledged: int = receiver.treasury
	world.berth(first,receiver.id)
	check(Economy.exchange(world,first,receiver,0,-8) and receiver.treasury == 0 and receiver.cash_holds.is_empty() and world.active().wallet-wallet == pledged,"completed delivery debits receiver and releases its pledge")
	receiver.treasury = pledged
	check(Economy.reserve(world,second,mine,receiver,0,8,false),"another order can use new cash")
	world.destruction(second.id)
	check(world.Treasury.available(receiver) == pledged and receiver.cash_holds.is_empty(),"ship loss promptly releases all cash")

	var merchant := worker(world,home)
	var rival := worker(world,home)
	check(Economy.assign_station_duty(world,merchant.id,home.id,"站属贸易") and not Economy.assign_station_duty(world,rival.id,mine.id,"站属贸易"),"only its own station can authorize a merchant to spend public funds")
	var ask := Economy.lot_quote(mine,0,6,true)
	home.treasury = ask.y
	var pre_profit: int = home.operating_profit
	wallet = world.active().wallet
	check(Economy.reserve(world,merchant,mine,home,0,6) and world.Treasury.available(home) == 0,"mother port holds purchasing budget for its inbound captain")
	check(not world.Treasury.transfer(world,home,world.player,-1),"reserved purchasing funds cannot be withdrawn")
	var sell_cash: int = mine.treasury
	world.berth(merchant,mine.id)
	check(Economy.exchange(world,merchant,mine,0,6) and home.treasury == 0 and mine.treasury-sell_cash == ask.y and world.active().wallet == wallet,"station merchant buys with its home treasury")
	var stock: int = home.stock[0]
	world.berth(merchant,home.id)
	check(Economy.exchange(world,merchant,home,0,-6) and home.stock[0] == stock+6 and home.treasury == 0 and home.operating_profit == pre_profit-ask.y,"landing owned goods creates neither revenue nor expense")
	check(Economy.exchange(world,merchant,home,0,2) and merchant.cargo[0] == 2 and home.treasury == 0,"home can load its own cargo even with an empty treasury")
	var gain := Economy.lot_quote(mine,0,2,false).y
	sell_cash = mine.treasury
	world.berth(merchant,mine.id)
	check(Economy.exchange(world,merchant,mine,0,-2) and home.treasury == gain and sell_cash-mine.treasury == gain and world.active().wallet == wallet,"revenues on visiting markets return to the mother port")
	merchant.fuel = 97.0
	Economy.refuel_trader(world,merchant,mine)
	check(merchant.fuel == 100.0 and home.treasury == gain-3 and sell_cash-mine.treasury == gain-3,"external fuel is paid to the supplier")
	merchant.fuel = 98.0
	pre_profit = home.operating_profit
	world.berth(merchant,home.id)
	var fuel: int = home.stock[Industry.Ware.FUEL]
	Economy.refuel_trader(world,merchant,home)
	check(merchant.fuel == 100.0 and home.stock[Industry.Ware.FUEL] == fuel-2 and home.operating_profit == pre_profit and home.treasury == gain-3,"own fuel is a physical transfer without circular income")

	var saved_profit: int = home.operating_profit
	var final := World.new()
	check(final.load_state(world.snapshot()) and final.ports[home.id].operating_profit == saved_profit and final.ports[home.id].treasury == home.treasury,"individual balances and unallocated profit survive save/load")
	payroll(world)
	print("Station treasury %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)

func payroll(world: World) -> void:
	var yard: Dictionary = world.ports[world.port(0,"订单工资试验",Vector2(800,200),world.NEUTRAL,world.player,Industry.Module.YARD)]
	var ship := world.ride()
	world.berth(ship,yard.id)
	var model: Dictionary = world.Hulls.MODELS[0]
	var bill := Industry.vessel_recipe(model)
	for ware in bill:
		yard.stock[ware] = bill[ware]
	var quote := Economy.ship_quote(yard,0)
	var start: int = yard.hulls[0]
	check(Economy.order_hull(world,yard.id,0),"place funded-materials shipyard order")
	world.day += 30
	Economy.shipyard(world,yard)
	check(not yard.has("yard_work") and yard.hulls[0] == start,"a yard with raw materials and no cash cannot begin work")
	world.credit(world.player,quote.labor_cost)
	check(world.Treasury.transfer(world,yard,world.player,73),"owner pays in part of the labor budget")
	Economy.shipyard(world,yard)
	var done: int = yard.yard_work.hours
	check(done > 0 and done < quote.labor_hours and Industry.labor_charge(done) == 73 and yard.treasury == 0 and yard.operating_profit == -73,"partial payroll purchases only affordable worker hours")
	Economy.shipyard(world,yard)
	check(yard.yard_work.hours == done and yard.operating_profit == -73,"unpaid retries cannot progress or charge twice")
	var restored := World.new()
	check(restored.load_state(world.snapshot()),"part-paid construction survives save/load")
	yard = restored.ports[yard.id]
	check(restored.Treasury.transfer(restored,yard,restored.player,quote.labor_cost-73),"remaining payroll financed from the owner's wallet")
	Economy.shipyard(restored,yard)
	check(yard.hulls[0] == start+1 and yard.operating_profit == -quote.labor_cost and yard.treasury == 0 and yard.production_orders.is_empty(),"completed hull used all and only the quoted labor and stock")
