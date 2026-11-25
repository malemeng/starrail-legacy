extends SceneTree

const Game = preload("res://game.tscn")
const Bridge = preload("res://agent_bridge.gd")
const World = preload("res://world.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	run.call_deferred()

func two_holder_payment(pool: int, units: int, circulating: int, first_for_ties: bool) -> int:
	var weighted := pool*units
	var remainder := weighted % circulating
	return weighted/circulating + int(2*remainder>circulating or (2*remainder==circulating and first_for_ties))

func run() -> void:
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.set_physics_process(false)
	var world: World = game.world
	world.new_game({"seed":"public-accounts","systems":12,"factions":3})
	game.run_bridge()
	var bridge := Bridge.new()
	bridge.game = game
	var ship := world.ride()
	var home: Dictionary = world.ports[ship.dock]
	var planet: Dictionary = world.ports[world.systems[0].planets[0].port_id]
	home.owner = world.player
	home.firm = 0
	planet.owner = world.player
	var before: int = world.active().wallet
	var opening: int = home.treasury
	var surface: int = planet.treasury
	check(bridge.dispatch("transfer_station_funds",{"port":home.id,"amount":100}).ok and home.treasury == opening+100 and world.active().wallet == before-100 and planet.treasury == surface,"injection moves real money into only one of two station accounts")
	check(bridge.dispatch("set_dividend_policy",{"port":home.id,"percent":100,"reserve":0}).ok and not bridge.dispatch("pay_dividend",{"port":home.id}).ok,"neither opening capital nor injected cash counts as dividends")
	var credits: int = world.active().wallet
	var finance: Dictionary = world.Finances.report(world)
	check(not bridge.dispatch("transfer_station_funds",{"port":home.id,"amount":credits+1}).ok and world.Finances.report(world) == finance,"rejected transfer generates no receipts")
	check(bridge.dispatch("trade",{"ware":0,"amount":3}).ok,"player executes an actual market purchase")
	var cost: int = credits-world.active().wallet
	var book: Dictionary = bridge.dispatch("financial_report",{}).result
	check(cost > 0 and home.treasury == opening+100+cost and home.operating_profit == cost,"public purchase credits the port with the exact settled price")
	check(book.ship.expense == cost and book.station.income == cost and book.net == 0 and book.capital_in == 100,"ship and station entries reconcile without treating initial capital or gross turnover as extra income")
	var home_row: Array = book.assets.filter(func(row): return row.id == home.id)
	check(home_row.size() == 1 and home_row[0].sales == cost,"actual public-market turnover is separately available")
	check(bridge.dispatch("set_dividend_policy",{"port":home.id,"percent":100,"reserve":home.treasury}).ok and world.Dividends.statement(world,home).payable == 0,"minimum cash reserve protects the operating balance")
	bridge.dispatch("set_dividend_policy",{"port":home.id,"percent":100,"reserve":0})
	home.cash_holds[-20] = home.treasury-2
	check(world.Dividends.statement(world,home).payable == mini(2,cost),"committed purchase funds cannot be distributed")
	home.cash_holds.erase(-20)
	var wallet: int = world.active().wallet
	check(bridge.dispatch("pay_dividend",{"port":home.id}).ok and world.active().wallet == wallet+cost and home.operating_profit == 0 and home.treasury == opening+100,"dividends actually transfer profit to the owner's wallet")
	check(not bridge.dispatch("pay_dividend",{"port":home.id}).ok and bridge.dispatch("financial_report",{}).result.dividends == cost,"repeating the same declaration cannot pay twice")
	world.Treasury.post(world,planet,40,"居民税收")
	world.Dividends.configure(world,planet,50,0)
	world.day = 30
	world.Dividends.monthly(world)
	check(planet.operating_profit == 20 and planet.treasury == surface+20 and world.active().wallet == wallet+cost+20,"a different planet runs its own dividend policy on the monthly date")
	world.Dividends.monthly(world)
	check(planet.operating_profit == 20,"a second monthly pass on the same date is idempotent")
	var restored := World.new()
	check(restored.load_state(world.snapshot()) and restored.Finances.report(restored,90) == world.Finances.report(world,90) and restored.Dividends.statement(restored,restored.ports[planet.id]) == world.Dividends.statement(world,planet),"ledger, operating balances, dividend policy and last payment round-trip together")
	check(bridge.dispatch("financial_report",{"days":30}).result.capital_in == 0 and bridge.dispatch("financial_report",{"days":31}).result.capital_in == 100,"date filters include exactly the requested days")
	check(not bridge.dispatch("financial_report",{"days":91}).ok,"out-of-range reporting periods are rejected")
	game.tab = "资产"
	game.refresh()
	for node in game.body.find_children("*","Button",true,false):
		if node.text == "船队与空间站收支简报":
			node.pressed.emit()
			break
	check(game.hud.report_open and game.body.find_children("*","OptionButton",true,false).size() == 1,"the asset screen opens the actual reporting controls")
	world.day = 90
	world.Finances.expire(world)
	check(not world.campaign.financial_days.has(0) and world.Finances.report(world,90).dividends == 20,"90-day retention expires old data and keeps newer dividends")
	var company := world.incorporate("两岸航运",world.player,home.id)
	var holder := world.random_person(world.NEUTRAL,home.id)
	var registry: Dictionary = world.firms[company]
	var circulating := int(registry.issued)-int(registry.treasury_shares)
	var minority := maxi(1,roundi(circulating*0.4))
	world.active().shares[company] = circulating-minority
	world.people[holder].shares[company] = minority
	var first_payment := two_holder_payment(11,circulating-minority,circulating,world.player<holder)
	world.Treasury.post(world,home,11,"居民税收")
	var first_cash: int = world.active().wallet
	var second_cash: int = world.people[holder].wallet
	var capital: int = home.treasury
	var company_before: int = world.firms[company].treasury
	check(world.Dividends.settle(world,home) == 11 and world.firms[company].treasury == company_before+11 and home.treasury == capital-11 and world.active().wallet == first_cash,"the parent retains its dividend independently from personal shareholder wallets")
	world.Dividends.configure_company(world,company,100,0)
	check(world.Dividends.settle_company(world,company) == 11 and world.active().wallet == first_cash+first_payment and world.people[holder].wallet == second_cash+11-first_payment,"company distributes all eleven credits by relative share ownership with deterministic rounding")
	check(world.Finances.report(world,1).received_dividends == first_payment and world.Finances.report(world,1).dividends == 11,"the personal dividend receipt remains distinct from the station's full payout")
	world.day += 30
	var parent_stake := maxi(1,roundi(circulating*0.1))
	world.active().shares[company] = parent_stake
	world.people[holder].shares[company] = circulating-parent_stake
	var site_register := world.StationEquity.cap_table(world,home)
	var site_circulating := int(site_register.total)-int(site_register.treasury_units)
	var direct_units := maxi(1,roundi(site_circulating*0.2))
	site_register.people = {world.player:direct_units}
	site_register.company = company
	site_register.company_units = site_circulating-direct_units
	home.equity = site_register
	var direct := two_holder_payment(100,direct_units,site_circulating,false)
	var parent_income := 100-direct
	var indirect := two_holder_payment(parent_income,parent_stake,circulating,world.player<holder)
	world.Treasury.post(world,home,100,"居民税收")
	first_cash = world.active().wallet
	second_cash = world.people[holder].wallet
	world.Dividends.settle(world,home)
	check(world.active().wallet == first_cash+direct and world.firms[company].operating_profit == parent_income,"direct owner and corporate parent divide station dividends by their actual circulating units")
	check(world.Dividends.settle_company(world,company) == parent_income and world.active().wallet == first_cash+direct+indirect and world.people[holder].wallet == second_cash+parent_income-indirect,"direct and indirect stakes settle exactly once with one hundred credits total")
	check(world.Finances.report(world,1).received_dividends == direct+indirect and world.Dividends.settle(world,home) == 0 and world.Dividends.settle_company(world,company) == 0,"repeat settlement cannot draw a second dividend at either tier")
	game.free()
	print("Asset financial reports and dividends ",checks-failures,"/",checks)
	quit(1 if failures else 0)
