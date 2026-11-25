extends SceneTree

const World = preload("res://world.gd")
const Industry = preload("res://scripts/economy/industry.gd")
const Economy = preload("res://economy.gd")
var count := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	count += 1
	if not ok:
		failed += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	var world := World.new()
	world.new_game({"seed":"sovereign-customs","systems":16,"factions":4})
	var actor := world.active()
	var lead := world.ride()
	var seat: Dictionary = world.ports[world.factions[0].capital]
	var sovereign: Dictionary = world.factions[0]
	var local_owner: int = world.random_person(1,seat.id)
	var id := world.port(seat.system,"外资自由贸易码头",seat.pos+Vector2(900,0),1,local_owner,0)
	var dock: Dictionary = world.ports[id]
	var firm: Dictionary = world.firms[world.incorporate("异乡运输",local_owner,id)]
	var foreign: Dictionary = world.factions[1]
	dock.tax_rate = 0.01
	seat.tax_rate = 0.20
	world.refresh_tariffs(seat.system)
	check(world.sovereign(seat.system)==0 and dock.tariff_flag==0 and is_equal_approx(dock.tariff_rate,0.20),"a foreign-owned company port follows its system's political seat and rates")
	check(world.berth(lead,id),"neutral customer docks at the foreign branch")
	actor.wallet = 10000
	dock.treasury = 5000
	dock.stock[Industry.Ware.ELECTRONICS] = 24
	var invoice := Industry.lot_invoice(dock,Industry.Ware.ELECTRONICS,3,true,actor.origin)
	var royal: int = sovereign.treasury
	var foreign_cash: int = foreign.treasury
	var director_cash: int = world.people[local_owner].wallet
	var operating: int = dock.operating_profit
	var revenue: int = firm.revenue
	check(invoice.tax>0 and invoice.total==invoice.base+invoice.tax and Economy.trade(world,id,Industry.Ware.ELECTRONICS,3)==3,"purchase pays a visible positive tax")
	check(actor.wallet==10000-invoice.total and dock.treasury==5000+invoice.base and dock.operating_profit==operating+invoice.base and firm.revenue==revenue+invoice.base,"only the pre-tax sale counts toward port income and company turnover")
	check(sovereign.treasury==royal+invoice.tax and foreign.treasury==foreign_cash and world.people[local_owner].wallet==director_cash,"the other government's flag, company and manager confer no rights over the duty")
	royal = sovereign.treasury
	invoice = Industry.lot_invoice(dock,Industry.Ware.ELECTRONICS,3,false,actor.origin)
	dock.treasury = invoice.total
	var capped := Economy.trade_quote(world,dock,Industry.Ware.ELECTRONICS,-3)
	check(capped.x<3 and invoice.base==invoice.total+invoice.tax,"buying port needs total seller proceeds and sovereign tax in cash")
	dock.treasury = invoice.base
	var cash: int = actor.wallet
	check(Economy.trade(world,id,Industry.Ware.ELECTRONICS,-3)==-3 and dock.treasury==0 and actor.wallet==cash+invoice.total and sovereign.treasury==royal+invoice.tax,"sale splits the real receiving port payment between the seller and state")

	var officer := world.random_person(world.NEUTRAL,seat.id)
	var freight: Dictionary = world.ships[world.ship(1,world.player,officer,world.NEUTRAL,seat.system,seat.pos,id)]
	freight.cargo[Industry.Ware.ELECTRONICS] = 4
	invoice = Industry.lot_invoice(dock,Industry.Ware.ELECTRONICS,4,false)
	dock.treasury = invoice.base
	royal = sovereign.treasury
	cash = actor.wallet
	check(Economy.reserve(world,freight,seat,dock,Industry.Ware.ELECTRONICS,4,false) and dock.cash_holds[freight.id]==invoice.base and world.Treasury.available(dock)==0,"AI import contract locks the entire taxable invoice")
	check(Economy.exchange(world,freight,dock,Industry.Ware.ELECTRONICS,-4) and dock.treasury==0 and dock.cash_holds.is_empty() and actor.wallet==cash+invoice.total and sovereign.treasury==royal+invoice.tax,"AI delivery uses the same invoice, pays the state once, and releases the hold")
	var owned: Dictionary = world.ports[world.port(seat.system,"同属甲",seat.pos+Vector2(1800,0),0,actor.id,0)]
	var branch: Dictionary = world.ports[world.port(seat.system,"同属乙",seat.pos+Vector2(2300,0),0,actor.id,0)]
	check(Economy.assign_station_duty(world,freight.id,owned.id,"站属贸易"),"assign the merchant to its real station")
	royal = sovereign.treasury
	var ore: int = branch.stock[0]
	world.berth(freight,owned.id)
	check(Economy.exchange(world,freight,owned,0,4),"an empty-treasury facility loads its own goods")
	world.berth(freight,branch.id)
	check(Economy.exchange(world,freight,branch,0,-4) and branch.stock[0]==ore+4 and sovereign.treasury==royal and owned.treasury==0 and branch.treasury==0,"internal shipment between wholly owned facilities creates no taxable sale or earnings")
	check(Industry.lot_invoice(dock,Industry.Ware.ELECTRONICS,10,true,-1,true).tax==0 and Industry.lot_invoice(world.ports[world.systems[0].ports[0]],0,20,true).tax==0,"black market and a nominally ungoverned system are exempt")
	world.Politics.conquer(world,dock.id,2)
	check(dock.tariff_flag==0,"occupying one foreign subsidiary does not seize customs rights")
	world.Politics.conquer(world,seat.id,2)
	check(world.sovereign(seat.system)==2 and dock.tariff_flag==2 and owned.tariff_flag==2,"a capture of the political seat changes duties throughout the system")
	var saved := world.snapshot()
	saved.ports[id].tariff_flag = 3
	saved.ports[id].tariff_rate = 0.99
	var restored := World.new()
	check(restored.load_state(saved) and restored.ports[id].tariff_flag==2 and is_equal_approx(restored.ports[id].tariff_rate,seat.tax_rate),"loading derives customs authority from sovereignty rather than a forged cache")
	saved.ports[seat.id].tax_rate = NAN
	check(not World.new().load_state(saved),"the authoritative seat cannot contain an invalid rate")
	print("Sovereign goods taxation %d/%d" % [count-failed,count])
	quit(1 if failed else 0)
