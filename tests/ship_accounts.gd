extends SceneTree

const Game = preload("res://game.tscn")
const Bridge = preload("res://agent_bridge.gd")
const Economy = preload("res://economy.gd")
const World = preload("res://world.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.set_physics_process(false)
	var world: World = game.world
	world.new_game({"seed":"fleet-cash-audit","systems":12,"factions":3})
	game.run_bridge()
	var bridge := Bridge.new()
	bridge.game = game
	var owner := world.player
	var port: Dictionary = world.ports[world.ride().dock]
	var cap := world.random_person(world.NEUTRAL,port.id)
	var id := world.ship(1,owner,cap,world.NEUTRAL,port.system,port.pos,port.id)
	var ship: Dictionary = world.ships[id]
	world.active().wallet = 20000
	check(Economy.assign(world,id,cap,"自动贸易"),"hire a private freight captain")
	port.treasury = 100000
	port.tariff_flag = world.factions.keys().front()
	port.tariff_rate = 0.2
	ship.cargo[0] = 12
	var seller: Dictionary = world.people[owner]
	var captain: Dictionary = world.people[cap]
	var owner_cash: int = seller.wallet
	var captain_cash: int = captain.wallet
	var port_cash: int = port.treasury
	var quote := Economy.Industry.lot_invoice(port,0,3,false)
	check(Economy.exchange(world,ship,port,0,-3),"settle automated sale")
	check(seller.wallet == owner_cash+quote.total and captain.wallet == captain_cash and port.treasury == port_cash-quote.base,"autotrader pays seller and tariff, captain receives zero")
	print("Private automatic sale: owner +",seller.wallet-owner_cash,", captain +",captain.wallet-captain_cash,", port ",port.treasury-port_cash,", tax ",quote.tax)
	world.player = cap
	owner_cash = seller.wallet
	port_cash = port.treasury
	var manual := Economy.trade_invoice(world,port,0,-3)
	check(Economy.trade(world,port.id,0,-3) == -3,"manually trade while playing the hired captain")
	check(seller.wallet == owner_cash+manual.total and captain.wallet == captain_cash and port.treasury == port_cash-manual.base,"direct sale uses the private operator and personal captain keeps zero")
	print("Captain-operated sale: owner +",seller.wallet-owner_cash,", captain +",captain.wallet-captain_cash,", port ",port.treasury-port_cash,", tax ",manual.tax)
	world.player = owner
	check(Economy.Diagnostics.snapshot(world,id).books.lines["货物销售"].income == quote.total+manual.total,"both sales remain in the owner's ledger after returning from the captain")
	world.day = 90
	owner_cash = seller.wallet
	world.Politics.appointments(world)
	world.Politics.appointments(world)
	check(seller.wallet == owner_cash and captain.wallet == captain_cash,"extra appointments have no payroll effect")
	world.Politics.settle_captain_payroll(world)
	world.Politics.settle_captain_payroll(world)
	var salary := int(Economy.Industry.RULES.ship_market.captain_quarterly_pay)
	check(seller.wallet == owner_cash-salary and captain.wallet == captain_cash+salary,"one quarterly payroll")
	var registered := bridge.dispatch("incorporate_ship",{"ship":id,"name":"渡鸦航运"})
	check(registered.ok,"launch shipping company with a privately owned hull and no owned station")
	if not registered.ok:
		quit(1)
		return
	var fid: int = registered.result.firm
	var firm: Dictionary = world.firms[fid]
	check(ship.owner == 0 and ship.firm == fid and port.firm != fid and world.can_operate(ship) and world.reports_to(captain) == owner,"legal title, registry and employer are distinct")
	check(world.Equity.overview(world,fid).ships == [id] and world.Equity.overview(world,fid).net_assets == firm.treasury + world.Hulls.MODELS[ship.kind].price,"ship counted exactly once in NAV")
	check(not bridge.dispatch("incorporate_ship",{"ship":id,"name":"重复"}).ok,"same ship cannot be incorporated twice")
	var other := world.ship(0,owner,0,world.NEUTRAL,port.system,port.pos,port.id)
	check(bridge.dispatch("contribute_ship",{"ship":other,"firm":fid}).ok and world.ships[other].firm == fid,"contribute another ship")
	owner_cash = seller.wallet
	captain_cash = captain.wallet
	var treasury: int = firm.treasury
	quote = Economy.Industry.lot_invoice(port,0,2,false)
	check(Economy.exchange(world,ship,port,0,-2) and firm.treasury == treasury+quote.total and seller.wallet == owner_cash and captain.wallet == captain_cash,"corporate sale pays company only")
	print("Company automatic sale: company +",firm.treasury-treasury,", founder +",seller.wallet-owner_cash,", captain +",captain.wallet-captain_cash)
	world.player = cap
	treasury = firm.treasury
	manual = Economy.trade_invoice(world,port,0,-2)
	check(Economy.trade(world,port.id,0,-2) == -2 and firm.treasury == treasury+manual.total and captain.wallet == captain_cash,"company manual sale also pays company")
	world.player = owner
	ship.fuel = 15
	port.stock[Economy.Industry.Ware.FUEL] = 200
	treasury = firm.treasury
	Economy.refuel_trader(world,ship,port)
	check(ship.fuel == 100 and firm.treasury == treasury-85 and seller.wallet == owner_cash,"corporate fuel charge")
	world.day = 180
	treasury = firm.treasury
	world.Politics.settle_captain_payroll(world)
	check(firm.treasury == treasury-salary and captain.wallet == captain_cash+salary and seller.wallet == owner_cash,"company pays its own captain")
	var diag: Dictionary = bridge.dispatch("debug_ship",{"ship":id}).result
	check(diag.firm == fid and diag.account.contains(firm.name) and diag.events.back().details.to.contains(captain.name) and diag.events.back().details.amount == salary,"diagnostics expose actual payer, recipient and amount")
	check(not bridge.dispatch("debug_ship",{"ship":9999999}).ok,"unavailable ship rejected")
	var replacement := world.random_person(world.NEUTRAL,port.id)
	firm.director = replacement
	check(not world.can_operate(ship) and world.reports_to(captain) == replacement,"company follows the board chair change")
	firm.director = owner
	var restored := World.new()
	check(restored.load_state(world.snapshot()) and restored.ships[id].firm == fid and restored.firms[fid].treasury == firm.treasury and restored.ships[id].diagnostic_events == ship.diagnostic_events,"corporate title, money and evidence survive save/load")
	game.hud.open_diagnostics(id)
	check(game.hud.diagnostics_open and game.body.find_children("*","OptionButton",true,false).size() == 1,"actual asset tab opens the ship diagnostic selector")
	game.hud.dossier.open(game,cap)
	var found := false
	for button in game.body.find_children("*","Button",true,false):
		if button.text.begins_with("直属上级") and button.text.contains(seller.name):
			button.pressed.emit()
			found = game.hud.dossier.person_id == owner
			break
	check(found,"click direct supervisor in the captain dossier")
	var docked: Dictionary = world.ports[world.systems[1].ports[0]]
	var receiving: Dictionary = world.ports[world.systems[1].ports[1]]
	world.berth(ship,docked.id)
	docked.stock[0] = 100
	docked.stock[Economy.Industry.Ware.FUEL] = 100
	receiving.treasury = 90000
	ship.job = {"kind":"贸易","automatic":true,"phase":0,"source":docked.id,"target":receiving.id,"quantity":3,"ware":0}
	ship.fuel = 12
	check(Economy.reserve(world,ship,docked,receiving,0,3),"reserve a small real freight order")
	check(Economy.assign(world,id,cap,"自动贸易") and ship.has("reservation") and ship.job.source == docked.id,"repeated automation keeps reservation and route")
	Economy.step_ship(world,ship)
	check(ship.job.phase == 1 and ship.fuel == 100 and docked.stock[Economy.Industry.Ware.FUEL] == 12,"after purchasing booked freight the automatic captain draws fuel from the actual port")
	var legacy := world.snapshot()
	var planet: Dictionary = legacy.systems[0].planets[0]
	var site: Dictionary = legacy.ports[planet.port_id]
	site.surface_profile = "colony"
	site.erase("landing_only")
	planet.port = planet.port_id
	planet.erase("port_id")
	check(restored.load_state(legacy) and restored.systems[0].planets[0].port_id == site.id,"old NPC colony links recover on load")
	game.queue_free()
	print("Ship accounts and command ",checks-failures,"/",checks)
	quit(1 if failures else 0)
